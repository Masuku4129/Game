"""Wildlands authoritative browser simulation and deterministic procedural world.
Executed inside Pyodide; rendering remains a presentation layer only.
"""
from __future__ import annotations
import math
import random

WEATHER = {
    "clear": {"cloud": .10, "rain": 0.0, "snow": 0.0, "fog": .006, "storm": 0.0},
    "rain":  {"cloud": .82, "rain": .82, "snow": 0.0, "fog": .014, "storm": 0.0},
    "storm": {"cloud": 1.0, "rain": 1.0, "snow": 0.0, "fog": .022, "storm": 1.0},
    "snow":  {"cloud": .78, "rain": 0.0, "snow": 1.0, "fog": .019, "storm": 0.0},
}
SEASONS = ("spring", "summer", "autumn", "winter")
BIOMES = ("mixed_forest", "conifer_forest", "clearing", "wetland", "rocky_upland")
CHUNK_SIZE = 72.0


def _fade(t): return t*t*(3.0-2.0*t)
def _hash2(ix, iz, seed=0):
    n=math.sin(ix*127.1+iz*311.7)*43758.5453
    return n-math.floor(n)
def _noise(x,z,seed=0):
    ix,iz=math.floor(x),math.floor(z); fx,fz=_fade(x-ix),_fade(z-iz)
    a,b=_hash2(ix,iz),_hash2(ix+1,iz); c,d=_hash2(ix,iz+1),_hash2(ix+1,iz+1)
    return (a+(b-a)*fx)+((c+(d-c)*fx)-(a+(b-a)*fx))*fz
def _fbm(x,z,seed=0,octaves=5):
    total=norm=0.0; amp=1.0; freq=1.0
    for _ in range(octaves):
        total+=_noise(x*freq,z*freq)*amp; norm+=amp; amp*=.5; freq*=2.1
    return total/norm
class ProceduralWorld:
    """Python-authoritative continuous world; terrain equations match the browser sampler."""
    def __init__(self,seed=1847): self.seed=int(seed)
    def height(self,x,z):
        broad=(_fbm(x*.0027,z*.0027,0,5)-.5)*36
        hills=(_fbm(x*.010,z*.010,0,4)-.5)*10
        detail=(_fbm(x*.043,z*.043,0,3)-.5)*1.35
        ridge=max(0.0,_fbm((x+80)*.0018,(z-40)*.0018,0,4)-.66)*48
        valley=max(0.0,.48-_fbm((x+210)*.004,(z-130)*.004,0,3))*5.5
        return broad+hills+detail+ridge-valley
    def slope(self,x,z):
        h=self.height(x,z)
        return abs(self.height(x+2,z)-h)+abs(self.height(x,z+2)-h)
    def moisture(self,x,z): return _fbm((x-300)*.005,(z+90)*.005,0,2)
    def canopy(self,x,z):
        h=self.height(x,z); f=_fbm((x+400)*.006,(z+250)*.006,0,3)+(_noise(x*.04,z*.04)-.5)*.14; m=self.moisture(x,z)
        smooth=lambda a,b,v: (lambda q:q*q*(3-2*q))(max(0.0,min(1.0,(v-a)/(b-a))))
        bog=smooth(.56,.66,m)*(1-smooth(1,3,h))*(1.0 if h>-1.3 else 0.0)
        return smooth(.44,.58,f)*(1-smooth(22,34,h))*(1-bog*.9)
    def biome_weights(self,x,z):
        h,m,c=self.height(x,z),self.moisture(x,z),self.canopy(x,z)
        bog=max(0.0,min(1.0,(m-.56)/.10))*(1-max(0.0,min(1.0,(h-1.0)/2.0)))
        rock=max(0.0,min(1.0,(h-6.5)/4.0))*max(0.0,min(1.0,self.slope(x,z)))
        clearing=max(0.0,min(1.0,(.25-c)*2.8))
        conifer=max(0.0,min(1.0,(_fbm((x+300)*.004,z*.004,0,3)-.5)*4.0))*(1-bog)*(1-rock)
        mixed=max(.02,1-bog*.75-rock*.7-clearing*.65-conifer*.55)
        vals={'wetland':bog,'rocky_upland':rock,'clearing':clearing,'conifer_forest':conifer,'mixed_forest':mixed}
        total=sum(vals.values()) or 1.0
        return {k:v/total for k,v in vals.items()}
    def biome(self,x,z):
        w=self.biome_weights(x,z); return max(w,key=w.get)
    def snow_factor(self,x,z):
        h=self.height(x,z); gx=self.height(x+1,z)-self.height(x-1,z); gz=self.height(x,z+1)-self.height(x,z-1)
        ny=2/math.sqrt(4+gx*gx+gz*gz); smooth=lambda a,b,v:(lambda q:q*q*(3-2*q))(max(0.0,min(1.0,(v-a)/(b-a))))
        cn=self.canopy(x,z); cc=(self.height(x+2.5,z)+self.height(x-2.5,z)+self.height(x,z+2.5)+self.height(x,z-2.5))/4-h
        drift=(max(0.0,min(1.0,cc/.4))*.6+_noise(x*.12,z*.12)*.5)*(1-cn*.3)
        return min(1.25,smooth(.5,.9,ny)*(.08+1.18*drift))
    def mud_factor(self,x,z):
        h=self.height(x,z); m=self.moisture(x,z); smooth=lambda a,b,v:(lambda q:q*q*(3-2*q))(max(0.0,min(1.0,(v-a)/(b-a))))
        bog=smooth(.56,.66,m)*(1-smooth(1,3,h))*(1.0 if h>-1.3 else 0.0)
        return max((1-smooth(.2,1.4,h))*(.8 if h>-1.5 else 0.0),bog*.8,smooth(.68,.8,_noise(x*.07+9,z*.07))*.7)
    def trees_for_chunk(self,cx,cz):
        # Globally seeded jittered cells + local Poisson rejection: varied clumps,
        # stable chunk borders and no costly unbounded rejection loop.
        cell=3.4; margin=7.0; accepted=[]; trees=[]
        gx0=math.floor((cx*CHUNK_SIZE-margin)/cell); gx1=math.ceil(((cx+1)*CHUNK_SIZE+margin)/cell)
        gz0=math.floor((cz*CHUNK_SIZE-margin)/cell); gz1=math.ceil(((cz+1)*CHUNK_SIZE+margin)/cell)
        density={'clearing':.07,'wetland':.32,'rocky_upland':.22,'mixed_forest':.96,'conifer_forest':1.0}
        for gz in range(gz0,gz1):
            for gx in range(gx0,gx1):
                rng=random.Random(self.seed^(gx*73856093)^(gz*19349663))
                x=(gx+.5+rng.uniform(-.43,.43))*cell; z=(gz+.5+rng.uniform(-.43,.43))*cell
                h=self.height(x,z)
                if h < -17.0 or h>48.0: continue
                sl=self.slope(x,z)
                if sl>1.35: continue
                weights=self.biome_weights(x,z); biome=max(weights,key=weights.get); canopy=self.canopy(x,z)
                grove=.08+_fbm(x*.016+21,z*.016-7,0,4)*.92
                if rng.random()>density[biome]*grove*(.48+.82*canopy): continue
                age=rng.random()**.62; radius=1.65+age*3.6
                if any((x-tx)**2+(z-tz)**2<max(2.1,(radius+tr)*.58)**2 for tx,tz,tr in accepted): continue
                wet=self.moisture(x,z)
                if biome=='conifer_forest': species=rng.choices(('spruce','fir','pine'),(48,34,18))[0]
                elif biome=='wetland': species=rng.choices(('alder','birch','spruce'),(46,38,16))[0]
                elif biome=='rocky_upland': species=rng.choices(('pine','birch','fir'),(48,32,20))[0]
                elif wet>.62: species=rng.choices(('birch','alder','oak'),(42,40,18))[0]
                else: species=rng.choices(('oak','birch','pine','spruce'),(34,30,20,16))[0]
                base={'spruce':13.5,'fir':16.0,'pine':18.5,'birch':14.0,'alder':12.0,'oak':16.5}[species]
                height=base*(.43+age*.78)*rng.uniform(.82,1.19); accepted.append((x,z,radius))
                if cx*CHUNK_SIZE<=x<(cx+1)*CHUNK_SIZE and cz*CHUNK_SIZE<=z<(cz+1)*CHUNK_SIZE:
                    trees.append({'x':x,'z':z,'species':species,'height':height,'radius':radius,'age':age,'seed':rng.randrange(1<<30),'lean':(rng.random()-.5)*.12})
        return trees
    def objects_for_chunk(self,cx,cz):
        # Understory grows in coherent patches around suitable moisture, shade and soil.
        size=CHUNK_SIZE; rng=random.Random((self.seed+991)^(cx*83492791)^(cz*2971215073))
        kinds=('fern','shrub','moss_rock','boulder','fallen_log','stump','mushroom','grass_clump',
               'branch','wildflower','cattail','root_cluster','pinecone','deadwood','berry_bush','reed',
               'small_sapling','leaf_litter','lichen','bracken','exposed_root','dry_grass','heather',
               'thistle','animal_burrow','fallen_bark','moss_patch')
        weights=(18,12,9,4,7,4,7,17,6,8,5,5,5,4,4,4,5,7,5,6,4,7,3,3,2,3,10)
        patches=[]
        for _ in range(13):
            px=cx*size+rng.uniform(0,size); pz=cz*size+rng.uniform(0,size)
            pb=self.biome(px,pz); pm=self.moisture(px,pz); pc=self.canopy(px,pz)
            theme='wet' if pb=='wetland' or pm>.72 else 'rock' if pb=='rocky_upland' else 'flower' if pc<.3 else 'litter' if rng.random()<.36 else 'understory'
            patches.append((px,pz,rng.uniform(3.5,12.0),theme))
        out=[]
        for i in range(560):
            if rng.random()<.78:
                px,pz,spread,theme=rng.choice(patches)
                x=max(cx*size,min((cx+1)*size-0.01,rng.gauss(px,spread)))
                z=max(cz*size,min((cz+1)*size-0.01,rng.gauss(pz,spread)))
            else:
                x=cx*size+rng.random()*size; z=cz*size+rng.random()*size; theme='open'
            biome=self.biome(x,z); moisture=self.moisture(x,z); canopy=self.canopy(x,z); slope=self.slope(x,z)
            h=self.height(x,z)
            themed={
                'understory':(('fern','shrub','bracken','berry_bush','small_sapling','moss_rock','moss_patch'),(24,18,16,8,10,5,12)),
                'litter':(('leaf_litter','pinecone','mushroom','branch','fallen_bark','deadwood'),(25,14,16,12,7,5)),
                'flower':(('wildflower','thistle','heather','dry_grass','grass_clump'),(28,13,18,16,12)),
                'wet':(('reed','cattail','exposed_root','root_cluster','fern','moss_rock','moss_patch'),(24,20,14,12,12,8,14)),
                'rock':(('boulder','lichen','moss_rock','heather','dry_grass','branch'),(22,18,14,16,12,5)),
                'open':(kinds,weights)}
            choice_kinds,choice_weights=themed.get(theme,themed['open']); kind=rng.choices(choice_kinds,choice_weights)[0]
            if biome=='rocky_upland':
                if kind in ('fern','mushroom','wildflower','cattail','reed','bracken'): kind=rng.choice(('boulder','lichen','heather','dry_grass'))
            elif biome=='wetland':
                if kind in ('boulder','pinecone','deadwood','heather'): kind=rng.choice(('reed','cattail','fern','exposed_root'))
            elif biome=='clearing' and kind in ('cattail','reed','moss_rock'):
                kind=rng.choice(('wildflower','dry_grass','thistle'))
            if moisture>.78 and kind in ('dry_grass','heather'): kind='bracken'
            if slope>1.15 and kind in ('mushroom','flower','reed','cattail'): continue
            if canopy>.7 and kind in ('wildflower','thistle','dry_grass'): continue
            if h < -17 and kind not in ('reed','cattail','root_cluster','exposed_root','moss_patch'): continue
            out.append({'x':x,'z':z,'kind':kind,'scale':rng.uniform(.35,2.2),
                        'rotation':rng.random()*math.tau,'seed':rng.randrange(1<<30),
                        'moisture':moisture,'canopy':canopy,'biome':biome})
        return out
    def terrain_grid(self,cx,cz,segments=24):
        rows=[]
        for iz in range(segments+1):
            row=[]
            for ix in range(segments+1):
                x=cx*CHUNK_SIZE+CHUNK_SIZE*ix/segments; z=cz*CHUNK_SIZE+CHUNK_SIZE*iz/segments
                row.append((x,z,self.height(x,z),self.moisture(x,z),self.slope(x,z)))
            rows.append(row)
        return rows
    def chunk(self,cx,cz):
        return {'cx':int(cx),'cz':int(cz),'size':CHUNK_SIZE,'trees':self.trees_for_chunk(cx,cz),'objects':self.objects_for_chunk(cx,cz)}


class WildlandsBrowserCore:
    """Authoritative Python simulation: locomotion, weather, seasons and surface state."""
    def __init__(self, seed=1847):
        self.seed=int(seed); self.rng=random.Random(seed); self.world=ProceduralWorld(seed)
        self.current=dict(WEATHER["clear"],wind=.2); self.target=WEATHER["clear"].copy()
        self.wind_target=.2; self.forced_weather=None; self.wind_override=None; self.weather_timer=36.0
        self.wet=0.0; self.snow_cover=0.0; self.puddles=0.0; self.canopy_snow=0.0
        self.elapsed=0.0; self.season_override=None; self.season_length=900.0
        self.x=self.z=self.y=self.vx=self.vz=0.0; self.heading=self.heading_velocity=0.0
        self.walk_phase=0.0; self.last_stride=0; self.footprints=[]
    def season(self):
        if self.season_override in SEASONS: return self.season_override
        return SEASONS[int(self.elapsed/self.season_length)%4]
    def set_season(self,name):
        if name in (None,"auto",""): self.season_override=None
        elif name in SEASONS: self.season_override=name
        else: raise ValueError("Unknown season: "+str(name))
    def set_weather(self,name):
        if name in (None,"auto",""): self.forced_weather=None; self.weather_timer=0.0; return
        if name not in WEATHER: raise ValueError("Unknown weather: "+str(name))
        self.forced_weather=name; self.target=WEATHER[name].copy()
    def set_wind(self,value): self.wind_override=None if value is None else max(0.0,min(1.0,float(value)))
    def world_sample(self,x,z):
        return (self.world.height(x,z),self.world.slope(x,z),self.world.moisture(x,z),self.world.canopy(x,z),self.world.biome(x,z),self.world.snow_factor(x,z),self.world.mud_factor(x,z))
    def step(self,dt,t,ix0,iy0,x,z,y,vx,vz,heading,heading_velocity,ground_height,terrain_slope,snow_factor,mud_factor,world_limit):
        dt=max(0.0,min(float(dt),.05)); self.elapsed+=dt
        self.x,self.z,self.y=float(x),float(z),float(y); self.vx,self.vz=float(vx),float(vz); self.heading,self.heading_velocity=float(heading),float(heading_velocity)
        self.weather_timer-=dt
        if self.forced_weather is None and self.weather_timer<=0:
            key=self.rng.choices(tuple(WEATHER),(38,28,13,21))[0]; self.target=WEATHER[key].copy()
            self.wind_target=self.rng.choice((.12,.28,.48,.72,1.0))
            if self.target["storm"]: self.wind_target=max(self.wind_target,.72)
            if self.season()=="summer" and key=="snow": self.target=WEATHER["rain"].copy()
            self.weather_timer=self.rng.uniform(55.0,105.0)
        target_wind=self.wind_override if self.wind_override is not None else self.wind_target
        blend=min(1.0,dt*.32)
        for key in self.current: self.current[key]+=((target_wind if key=="wind" else self.target[key])-self.current[key])*blend
        gust=max(.18,min(1.42,.72+.24*math.sin(t*.61)+.19*math.sin(t*1.73+2)+.13*math.sin(t*4.1)))
        wind=self.current["wind"]*gust; angle=.6+math.sin(t*.04)*.6; wind_x,wind_z=math.cos(angle),math.sin(angle)
        rain,snow=self.current["rain"],self.current["snow"]
        self.wet=max(0.0,min(1.0,self.wet+((1.0 if rain>.18 else 0.0)-self.wet)*min(1.0,dt*.075)))
        self.snow_cover=max(0.0,min(1.0,self.snow_cover+(dt*.022 if snow>.45 else -dt*.016 if rain>.3 else -dt*.0015)))
        self.puddles=max(0.0,min(1.0,self.puddles+(dt*.045 if rain>.25 else -dt*.008)))
        # Snow load builds on sheltered crowns, then sheds in strong wind or warm rain.
        canopy_target=self.snow_cover*(.45+.55*(1.0-wind*.55)) if snow>.25 else 0.0
        self.canopy_snow=max(0.0,min(1.0,self.canopy_snow+(canopy_target-self.canopy_snow)*min(1.0,dt*(.09 if canopy_target>self.canopy_snow else .22))))
        ix,iy=float(ix0),float(iy0); length=math.hypot(ix,iy)
        if length>1: ix,iy,length=ix/length,iy/length,1.0
        sf=max(0.0,float(snow_factor)); mf=max(0.0,float(mud_factor))
        snow_depth=self.snow_cover*sf*1.35; mud_depth=self.wet*mf*.95
        slow=(.48 if self.y<-.65 else 1.0)*(1.0-min(.62,snow_depth*.38))*(1.0-min(.62,mud_depth*.62))
        mx,mz=.7071067811865476*(ix+iy),.7071067811865476*(iy-ix); accel=min(1.0,dt*8.5)
        self.vx+=(mx*5.2*length*slow-self.vx)*accel; self.vz+=(mz*5.2*length*slow-self.vz)*accel
        speed=math.hypot(self.vx,self.vz)
        if speed>.05:
            nx,nz=self.x+self.vx*dt,self.z+self.vz*dt
            if terrain_slope*speed*dt<1.7 and abs(nx)<world_limit and abs(nz)<world_limit: self.x,self.z=nx,nz
            else: self.vx=self.vz=0.0; speed=0.0
        target_y=float(ground_height)+snow_depth-mud_depth
        self.y+=(target_y-self.y)*min(1.0,dt*(4.5 if mud_depth>.35 else 9.0))
        if speed>.4:
            delta=math.atan2(self.vx,self.vz)-self.heading; delta=math.atan2(math.sin(delta),math.cos(delta))
            self.heading_velocity+=(delta*8.0-self.heading_velocity)*min(1.0,dt*10.0); self.heading+=delta*min(1.0,dt*8.0)
        else: self.heading_velocity*=.9
        self.walk_phase+=dt*speed*1.5*(1.0+snow_depth*.5+mud_depth*.3)
        stride=int(self.walk_phase/math.pi); step_event=stride!=self.last_stride and speed>.4; self.last_stride=stride
        side=1 if stride&1 else -1; foot_x=self.x+math.sin(self.heading)*.1+math.cos(self.heading)*.13*side
        foot_z=self.z+math.cos(self.heading)*.1-math.sin(self.heading)*.13*side
        material="snow" if snow_depth>mud_depth and snow_depth>.04 else "mud" if mud_depth>.06 else "earth"
        if step_event:
            self.footprints.append((foot_x,foot_z,self.heading,min(1.0,max(snow_depth,mud_depth)),material,self.elapsed))
            if len(self.footprints)>1800: self.footprints=self.footprints[-1800:]
        # Rain and thaw soften tracks; old marks slowly fade but persist in cold weather.
        decay_rate=.012+rain*.09+(0.12 if self.season()=="summer" else 0.0)
        if self.footprints and int(self.elapsed*2)!=int((self.elapsed-dt)*2):
            self.footprints=[m for m in self.footprints if self.elapsed-m[5]<2400 and (self.elapsed-m[5])*decay_rate<1.0]
        season=SEASONS.index(self.season()); leaf_fall=(max(0.0,1.0-abs(season-2)*.7) if season==2 else 0.0)
        return (self.x,self.z,self.y,self.vx,self.vz,self.heading,self.heading_velocity,speed,snow_depth,mud_depth,
            self.current["cloud"],rain,snow,self.current["fog"],self.current["storm"],wind,wind_x,wind_z,
            self.wet,self.snow_cover,self.puddles,self.walk_phase,step_event,foot_x,foot_z,
            season,leaf_fall,self.canopy_snow,self.elapsed)

_CORE=WildlandsBrowserCore()
def game_step(*args): return _CORE.step(*args)
def set_weather(name): _CORE.set_weather(name)
def set_wind(value): _CORE.set_wind(value)
def set_season(name): _CORE.set_season(name)
def world_chunk(cx,cz): return _CORE.world.chunk(int(cx),int(cz))
def world_terrain_grid(cx,cz,segments=24): return _CORE.world.terrain_grid(int(cx),int(cz),int(segments))
def world_sample(x,z): return _CORE.world_sample(float(x),float(z))
def world_footprints(): return list(_CORE.footprints)
