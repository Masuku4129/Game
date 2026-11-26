#!/usr/bin/env python3
"""Generate original, Y-up, import-ready Taiga environment GLBs.

No third-party meshes or paid services are used. Geometry is procedural, vertex-colored, Y-up, and merged into one render mesh per asset to reduce mobile draw calls.
"""
from pathlib import Path
import math
import numpy as np
import trimesh
from skimage.measure import marching_cubes

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "game" / "models" / "environment"
OUT.mkdir(parents=True, exist_ok=True)
RNG = np.random.default_rng(20261126)

def color_mesh(mesh, rgba):
    mesh.visual.face_colors = np.tile(np.asarray(rgba, dtype=np.uint8), (len(mesh.faces), 1))
    return mesh

def tube(a, b, r0, r1, color, sections=8, sides=8, bend=(0, 0, 0)):
    a, b = np.asarray(a, float), np.asarray(b, float)
    axis = b - a
    length = np.linalg.norm(axis)
    if length < 1e-6:
        return None
    d = axis / length
    ref = np.array([0., 0., 1.]) if abs(d[2]) < .9 else np.array([0., 1., 0.])
    u = np.cross(d, ref); u /= np.linalg.norm(u)
    v = np.cross(d, u); v /= np.linalg.norm(v)
    verts, faces = [], []
    for i in range(sections + 1):
        t = i / sections
        center = a * (1 - t) + b * t + np.asarray(bend) * math.sin(math.pi * t)
        radius = r0 * (1 - t) + r1 * t
        for j in range(sides):
            ang = 2 * math.pi * j / sides
            verts.append(center + radius * (u * math.cos(ang) + v * math.sin(ang)))
    for i in range(sections):
        for j in range(sides):
            p = i * sides + j
            q = i * sides + (j + 1) % sides
            faces.extend([[p, p + sides, q], [q, p + sides, q + sides]])
    return color_mesh(trimesh.Trimesh(vertices=verts, faces=faces, process=True), color)

def organic_union(centers, scales, bounds, resolution=52, smooth=.25, base=(55, 105, 57)):
    (xmin, xmax), (ymin, ymax), (zmin, zmax) = bounds
    xs = np.linspace(xmin, xmax, resolution)
    ys = np.linspace(ymin, ymax, resolution)
    zs = np.linspace(zmin, zmax, resolution)
    X, Y, Z = np.meshgrid(xs, ys, zs, indexing="ij")
    field = np.full(X.shape, 1e3, dtype=np.float32)
    for c, s in zip(centers, scales):
        q = np.sqrt(((X-c[0])/s[0])**2 + ((Y-c[1])/s[1])**2 + ((Z-c[2])/s[2])**2)
        d = (q - 1) * min(s)
        h = np.maximum(smooth - np.abs(field-d), 0) / smooth
        field = np.minimum(field, d) - h*h*smooth*.25
    field += np.sin(X*7+Z*4) * np.cos(Y*8-Z*2) * .015
    spacing = ((xmax-xmin)/(resolution-1), (ymax-ymin)/(resolution-1), (zmax-zmin)/(resolution-1))
    verts, faces, _, _ = marching_cubes(field, level=0, spacing=spacing)
    verts += np.array([xmin, ymin, zmin])
    mesh = trimesh.Trimesh(vertices=verts, faces=faces, process=True)
    heights = mesh.triangles_center[:, 2]
    noise = np.sin(mesh.triangles_center[:, 0]*8 + mesh.triangles_center[:, 1]*5)*.5 + .5
    cols = np.zeros((len(faces), 4), dtype=np.uint8)
    for i, (z, normal) in enumerate(zip(heights, mesh.face_normals)):
        f = .82 + .17*(z-zmin)/(zmax-zmin) + .08*noise[i] + .06*max(0, normal[2])
        cols[i, :3] = np.clip(np.asarray(base)*f, 0, 255)
        cols[i, 3] = 255
    mesh.visual.face_colors = cols
    return mesh

def export(name, parts):
    scene = trimesh.Scene()
    # glTF uses Y-up; authoring helpers use Z-up. Merge all colored parts
    # into one renderable mesh to avoid hundreds of draw calls per tree.
    rotate = trimesh.transformations.rotation_matrix(-math.pi/2, [1, 0, 0])
    meshes = []
    for _, mesh in parts:
        if mesh is None:
            continue
        mesh = mesh.copy()
        mesh.apply_transform(rotate)
        meshes.append(mesh)
    if not meshes:
        raise ValueError(f"{name}: no geometry to export")
    merged = trimesh.util.concatenate(meshes)
    scene.add_geometry(merged, geom_name=Path(name).stem, node_name=Path(name).stem)
    (OUT / name).write_bytes(scene.export(file_type="glb"))

def spruce():
    parts = [("Trunk", tube((0,0,0), (.04,0,7.8), .34, .035, (91,62,40,255), 22, 12, (.12,0,0)))]
    for tier, z in enumerate(np.linspace(.8, 6.6, 10)):
        frac = 1-z/8
        for j in range(7):
            a = 2*math.pi*j/7 + tier*.42
            length = (1.9*frac+.35)*RNG.uniform(.82,1.12)
            start = np.array([.01,0,z])
            end = start + np.array([math.cos(a)*length, -.08*length, math.sin(a)*length])
            parts.append((f"Bough_{tier}_{j}", tube(start, end, .075*frac+.018, .012, (83,65,43,255), 5, 6, (0,-.08,0))))
    verts, faces = [], []
    rings, sides = 40, 64
    for i in range(rings+1):
        t = i/rings; z = .65+t*7.0; radius = 2.15*(1-t)**.82
        for j in range(sides):
            a = 2*math.pi*j/sides
            jag = 1+.09*math.sin(9*a+z*2.7)+.045*math.sin(17*a-z*1.3)
            r = max(.025, radius*jag)
            verts.append([r*math.cos(a), r*math.sin(a), z])
    for i in range(rings):
        for j in range(sides):
            a=i*sides+j; b=i*sides+(j+1)%sides
            c=(i+1)*sides+j; d=(i+1)*sides+(j+1)%sides
            faces.extend([[a,c,b],[b,c,d]])
    canopy = trimesh.Trimesh(vertices=verts, faces=faces, process=True)
    cols=[]
    for p in canopy.triangles_center:
        f=.78+.18*(p[2]/7.65)+.08*(math.sin(p[0]*9+p[1]*6)*.5+.5)
        cols.append([int(35*f),int(83*f),int(48*f),255])
    canopy.visual.face_colors=np.asarray(cols,dtype=np.uint8)
    parts.append(("Organic_Needle_Canopy", canopy))
    export("taiga_spruce.glb", parts)

def birch():
    parts=[("Pale_Birch_Trunk",tube((0,0,0),(.05,0,6.6),.23,.055,(218,216,195,255),24,12,(.16,0,0)))]
    for i,z in enumerate(np.linspace(.45,6.1,18)):
        a=(i*2.399)%(2*math.pi); x=.225*math.cos(a); y=.225*math.sin(a)
        parts.append((f"Bark_Scar_{i}",tube((x,y,z),(x*.94,y*.94,z+RNG.uniform(.06,.22)),.012,.006,(64,61,53,255),2,5)))
    for i in range(13):
        z=2.2+i*.29
        for side in (-1,1):
            a=i*.78+(0 if side==1 else math.pi)
            length=(.9+z/6)*RNG.uniform(.7,1.15)
            start=np.array([.04,0,z]); end=start+np.array([math.cos(a)*length,.02,math.sin(a)*length*.6])
            parts.append((f"Branch_{i}_{side}",tube(start,end,.045,.009,(91,72,48,255),5,6)))
    centers=[]; scales=[]
    for i in range(18):
        a=2*math.pi*i/18
        centers.append((math.cos(a)*.9,0,5.55+math.sin(a)*.6))
        scales.append((.78,.56,.7))
    centers += [(0,0,6.1),(.1,0,5.1)]
    scales += [(.62,.55,.72),(.72,.58,.55)]
    parts.append(("Fused_Birch_Crown",organic_union(centers,scales,((-1.9,1.9),(-.8,.8),(4.65,6.95)),64,.32,(85,127,62))))
    export("taiga_birch.glb",parts)

def bush():
    parts=[]
    for i in range(9):
        a=2*math.pi*i/9; length=RNG.uniform(.65,1.15)
        start=np.array([0.,0.,.05]); end=np.array([math.cos(a)*length*.65,math.sin(a)*length*.65,length])
        parts.append((f"Woody_Stem_{i}",tube(start,end,.045,.012,(87,59,39,255),6,6)))
        for k in range(3):
            t=.45+k*.22; c=start*(1-t)+end*t
            tip=c+np.array([math.cos(a+.6)*.25,math.sin(a+.6)*.25,.25])
            parts.append((f"Twig_{i}_{k}",tube(c,tip,.018,.006,(95,65,41,255),3,5)))
    centers=[]; scales=[]
    for i in range(20):
        a=2*math.pi*i/20; r=RNG.uniform(.15,.7); z=RNG.uniform(.35,1.0)
        centers.append((math.cos(a)*r,math.sin(a)*r,z))
        scales.append((RNG.uniform(.38,.56),RNG.uniform(.32,.5),RNG.uniform(.32,.5)))
    parts.append(("Fused_Bush_Foliage",organic_union(centers,scales,((-1.25,1.25),(-1.25,1.25),(0,1.65)),56,.28,(45,103,50))))
    export("taiga_bush.glb",parts)

def rock():
    mesh=trimesh.creation.icosphere(subdivisions=3,radius=1)
    v=mesh.vertices.copy()
    for i,p in enumerate(v):
        f=1+.12*math.sin(p[0]*9+p[2]*4)+.07*math.cos(p[1]*11-p[0]*3)
        v[i]=p*f*np.array([1.25,.72,.92])+np.array([0,0,.72])
    mesh.vertices=v
    cols=[]
    for i,p in enumerate(mesh.triangles_center):
        base=np.array([91,91,83]) if p[2]>.75 else np.array([69,70,65])
        jitter=int(RNG.integers(-12,13))
        cols.append([*np.clip(base+jitter,0,255),255])
    mesh.visual.face_colors=np.asarray(cols,dtype=np.uint8)
    export("taiga_rock.glb",[("Weathered_Irregular_Rock",mesh)])

def fallen_log():
    parts=[("Tapered_Fallen_Trunk",tube((0,0,.38),(3.1,.08,.28),.34,.27,(103,70,44,255),28,16,(0,0,.1)))]
    for i in range(9):
        a=2*math.pi*i/9
        off=np.array([0,math.cos(a)*.32,math.sin(a)*.32])
        parts.append((f"Longitudinal_Bark_Ridge_{i}",tube(np.array([0,0,.38])+off,np.array([3.1,.08,.28])+off*.8,.028,.015,(72,51,34,255),20,5)))
    for x,r,z in ((0,.34,.38),(3.1,.27,.28)):
        disk=trimesh.creation.cylinder(radius=r*.93,height=.035,sections=24)
        disk.apply_transform(trimesh.transformations.rotation_matrix(math.pi/2,[0,1,0]))
        disk.apply_translation((x,0,z))
        color_mesh(disk,(174,139,94,255))
        parts.append((f"Exposed_Cut_End_{x}",disk))
    export("taiga_fallen_log.glb",parts)


def larch():
    parts=[("Larch_Trunk",tube((0,0,0),(.08,0,8.2),.31,.035,(91,65,43,255),24,12,(.18,0,0)))]
    for tier,z in enumerate(np.linspace(1.0,7.1,13)):
        frac=1-z/8.5
        for j in range(6):
            a=2*math.pi*j/6+tier*.47
            length=(2.0*frac+.28)*RNG.uniform(.8,1.15)
            start=np.array([.04,0,z])
            end=start+np.array([math.cos(a)*length,math.sin(a)*length*.55,-.16*length])
            parts.append((f"Larch_Branch_{tier}_{j}",tube(start,end,.055*frac+.012,.006,(92,70,46,255),5,5)))
            # Small needle sprays along each branch give larch a lighter, open crown.
            for k in range(3):
                t=.35+k*.22
                p=start*(1-t)+end*t
                tip=p+np.array([math.cos(a+.7)*.22,math.sin(a+.7)*.18,.18])
                parts.append((f"Needle_Spray_{tier}_{j}_{k}",tube(p,tip,.045,.008,(93,119,62,255),3,5)))
    centers=[]; scales=[]
    for i in range(11):
        z=1.0+i*.52
        r=1.85*(1-z/8.8)
        for j in range(5):
            a=2*math.pi*j/5+i*.38
            centers.append((math.cos(a)*r*.55,math.sin(a)*r*.55,z))
            scales.append((.48,.42,.55))
    parts.append(("Open_Larch_Needle_Clusters",organic_union(centers,scales,((-1.7,1.7),(-1.5,1.5),(.4,7.2)),56,.18,(94,125,65))))
    export("taiga_larch.glb",parts)


def pine():
    parts=[("Pine_Trunk",tube((0,0,0),(.08,0,8.0),.34,.045,(91,65,43,255),24,12,(.18,0,0)))]
    centers=[]; scales=[]
    # Distinct Scots-pine silhouette: open crown, long lateral limbs and
    # irregular needle pads concentrated near branch tips.
    for tier,z in enumerate([3.5,4.0,4.55,5.1,5.65,6.15,6.6,7.0]):
        radius=[2.5,2.55,2.4,2.15,1.85,1.45,1.05,.65][tier]
        for j in range(5):
            a=2*math.pi*j/5+tier*.59
            start=np.array([.04,0,z])
            end=start+np.array([math.cos(a)*radius,math.sin(a)*radius*.78,.12+radius*.12])
            parts.append((f"Pine_Limb_{tier}_{j}",tube(start,end,.075,.018,(98,72,48,255),8,7,(0,0,.12))))
            for k in range(4):
                t=.48+k*.14
                p=start*(1-t)+end*t
                side=np.array([-math.sin(a),math.cos(a),0])
                center=p+side*((k-1.5)*.11)+np.array([0,0,.1])
                centers.append(tuple(center))
                scales.append((.34,.29,.26))
    centers += [(0,0,7.15),(.1,-.05,6.65)]
    scales += [(.62,.55,.72),(.72,.62,.48)]
    parts.append(("Irregular_Pine_Needle_Pads",organic_union(centers,scales,((-3.0,3.0),(-2.5,2.5),(3.1,8.0)),64,.2,(54,91,49))))
    export("taiga_pine.glb",parts)

def cedar():
    parts=[("Cedar_Trunk",tube((0,0,0),(.03,0,7.4),.38,.08,(86,62,42,255),24,12,(.1,0,0)))]
    centers=[]; scales=[]
    # Broad, irregular whorls rather than a narrow spruce cone.
    for tier,z in enumerate([2.0,2.8,3.7,4.6,5.4,6.1,6.7]):
        rad=[2.5,2.35,2.15,1.85,1.5,1.12,.72][tier]
        for j in range(8):
            a=2*math.pi*j/8+tier*.31
            centers.append((math.cos(a)*rad*.42,math.sin(a)*rad*.42,z))
            scales.append((rad*.52,RNG.uniform(.48,.68),RNG.uniform(.62,.9)))
            end=np.array([math.cos(a)*rad,math.sin(a)*rad*.8,z-.18])
            parts.append((f"Cedar_Bough_{tier}_{j}",tube((0,0,z),end,.085,.018,(91,68,45,255),6,6)))
    parts.append(("Dense_Cedar_Crown",organic_union(centers,scales,((-2.8,2.8),(-2.6,2.6),(1.2,7.5)),68,.38,(38,83,48))))
    export("taiga_cedar.glb",parts)

def aspen():
    parts=[("Aspen_Pale_Trunk",tube((0,0,0),(.04,0,7.2),.25,.045,(204,201,178,255),24,12,(.12,0,0)))]
    for i,z in enumerate(np.linspace(.5,6.8,22)):
        a=i*2.399
        x=.24*math.cos(a); y=.24*math.sin(a)
        parts.append((f"Dark_Bark_Mark_{i}",tube((x,y,z),(x*.95,y*.95,z+RNG.uniform(.04,.18)),.018,.006,(55,57,48,255),2,5)))
    for i in range(10):
        z=2.7+i*.3
        a=i*2.4
        end=np.array([math.cos(a)*RNG.uniform(1.0,1.7),math.sin(a)*RNG.uniform(.7,1.2),z+.45])
        parts.append((f"Aspen_Branch_{i}",tube((.03,0,z),end,.05,.01,(91,69,46,255),5,6)))
    centers=[]; scales=[]
    for i in range(22):
        a=2*math.pi*i/22
        centers.append((math.cos(a)*1.0,math.sin(a)*.75,6.0+RNG.uniform(-.45,.45)))
        scales.append((RNG.uniform(.55,.78),RNG.uniform(.48,.7),RNG.uniform(.55,.78)))
    centers += [(0,0,6.4),(.1,0,5.7)]
    scales += [(.75,.65,.7),(.7,.62,.65)]
    parts.append(("Rounded_Aspen_Canopy",organic_union(centers,scales,((-2,2),(-1.7,1.7),(4.9,7.2)),64,.32,(105,139,63))))
    export("taiga_aspen.glb",parts)

def alder():
    parts=[]
    centers=[]; scales=[]
    for stem in range(4):
        a=2*math.pi*stem/4
        base=np.array([math.cos(a)*.22,math.sin(a)*.22,0.])
        top=base+np.array([math.cos(a)*.5,math.sin(a)*.5,RNG.uniform(4.4,5.6)])
        parts.append((f"MultiStem_{stem}",tube(base,top,.16,.035,(91,67,47,255),20,9)))
        for j in range(5):
            ang=a+j*1.7
            tip=top+np.array([math.cos(ang)*RNG.uniform(.7,1.3),math.sin(ang)*RNG.uniform(.6,1.1),RNG.uniform(-.25,.55)])
            parts.append((f"Alder_Branch_{stem}_{j}",tube(top,tip,.045,.008,(90,66,46,255),5,5)))
            centers.append(tuple(tip+np.array([0,0,.2])))
            scales.append((RNG.uniform(.4,.62),RNG.uniform(.35,.55),RNG.uniform(.35,.55)))
    parts.append(("Alder_Leaf_Crowns",organic_union(centers,scales,((-2,2),(-2,2),(3.3,6.4)),56,.25,(68,111,57))))
    export("taiga_alder.glb",parts)

def fern():
    parts=[]
    for frond in range(11):
        a=2*math.pi*frond/11+RNG.uniform(-.15,.15)
        length=RNG.uniform(.68,.92)
        points=[]
        for i in range(13):
            t=i/12
            r=length*t
            z=.08+math.sin(t*math.pi)*.58+t*.52
            points.append(np.array([math.cos(a)*r,math.sin(a)*r,z]))
        for i in range(12):
            parts.append((f"Fern_Rachis_{frond}_{i}",tube(points[i],points[i+1],.025*(1-i/15),.018*(1-i/15),(83,107,48,255),2,5)))
        for i in range(2,12):
            t=i/12
            center=points[i]
            side_len=(.2*(1-t)+.035)*RNG.uniform(.8,1.15)
            for side in (-1,1):
                aa=a+side*1.15
                tip=center+np.array([math.cos(aa)*side_len,math.sin(aa)*side_len,.06])
                mid=(center+tip)*.5+np.array([0,0,.045])
                verts=[center,mid+np.array([0,0,.035]),tip,mid-np.array([0,0,.02])]
                mesh=trimesh.Trimesh(vertices=verts,faces=[[0,1,2],[0,2,3]],process=False)
                color_mesh(mesh,(55+int(RNG.integers(0,18)),104+int(RNG.integers(0,24)),45,255))
                parts.append((f"Fern_Pinna_{frond}_{i}_{side}",mesh))
    export("taiga_fern.glb",parts)

def stump():
    parts=[("Broken_Stump_Bark",tube((0,0,0),(.05,0,1.05),.42,.34,(83,58,39,255),14,12,(.06,0,0)))]
    for i in range(12):
        a=2*math.pi*i/12
        r=RNG.uniform(.34,.41)
        p=np.array([math.cos(a)*r,math.sin(a)*r,.05])
        q=np.array([math.cos(a)*r*.86,math.sin(a)*r*.86,1.0+RNG.uniform(-.12,.16)])
        parts.append((f"Ragged_Bark_Ridge_{i}",tube(p,q,.035,.02,(61,45,32,255),5,5)))
    cap=trimesh.creation.annulus(r_min=.08,r_max=.35,height=.035,sections=32)
    cap.apply_translation((.05,0,1.02))
    color_mesh(cap,(156,119,77,255))
    parts.append(("Exposed_Wood_Rings",cap))
    export("taiga_stump.glb",parts)

if __name__ == "__main__":
    spruce(); birch(); bush(); rock(); fallen_log(); pine(); larch(); cedar(); aspen(); alder(); fern(); stump()
    print("Generated 12 original Taiga GLB models in", OUT)
