import bpy, math, random, os, sys
from mathutils import Vector

# Deterministic procedural asset batch. Run:
# blender -b --python tools/generate_assets.py -- --output assets/generated

def arg_value(flag, default):
    args = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
    return args[args.index(flag)+1] if flag in args else default

OUT = os.path.abspath(arg_value("--output", "assets/generated"))
os.makedirs(OUT, exist_ok=True)

def reset():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials):
        for block in list(datablocks):
            if block.users == 0: datablocks.remove(block)

def mat(name, color, rough=0.88, noise=False):
    m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
    p=m.node_tree.nodes.get("Principled BSDF"); p.inputs["Base Color"].default_value=(*color,1); p.inputs["Roughness"].default_value=rough
    if noise:
        n=m.node_tree.nodes.new("ShaderNodeTexNoise"); n.inputs["Scale"].default_value=7.0; n.inputs["Detail"].default_value=3.0
        ramp=m.node_tree.nodes.new("ShaderNodeValToRGB"); ramp.color_ramp.elements[0].position=.22; ramp.color_ramp.elements[0].color=(*(c*.55 for c in color),1); ramp.color_ramp.elements[1].position=.78; ramp.color_ramp.elements[1].color=(*(min(1,c*1.35) for c in color),1)
        links=m.node_tree.links; links.new(n.outputs["Fac"],ramp.inputs["Fac"]); links.new(ramp.outputs["Color"],p.inputs["Base Color"])
    return m

BARK=mat("Bark | rough dark brown",(0.19,.105,.055),.96,True)
BIRCH=mat("Birch | pale layered bark",(.72,.69,.55),.92,True)
BIRCH_DARK=mat("Birch | dark bark scars",(.12,.105,.08),.95)
NEEDLE_DARK=mat("Spruce | deep needles",(.035,.12,.075),.92,True)
NEEDLE=mat("Pine | muted needles",(.10,.22,.12),.9,True)
LEAF=mat("Broadleaf | forest green",(.17,.28,.105),.88,True)
LEAF_LIGHT=mat("Leaves | young green",(.27,.37,.13),.9,True)
FERN=mat("Fern | rich green",(.10,.27,.105),.88,True)
MOSS=mat("Moss | damp green",(.16,.23,.085),1,True)
STONE=mat("Stone | weathered grey",(.28,.30,.28),.94,True)
WOOD=mat("Cut wood | warm heartwood",(.42,.25,.12),.92,True)

def finish(name, mats):
    bpy.ops.object.select_all(action="SELECT")
    objs=[o for o in bpy.context.scene.objects if o.type=="MESH"]
    for o in objs:
        o.select_set(True)
        if o.name.startswith("trunk"): o.data.materials.append(BARK)
    bpy.context.view_layer.objects.active=objs[0] if objs else None
    if len(objs)>1: bpy.ops.object.join()
    root=bpy.context.object
    root.name=name
    # Center at ground, preserve dimensions and smooth only curved surfaces.
    bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
    bpy.ops.object.select_all(action="DESELECT"); root.select_set(True)
    bpy.context.view_layer.objects.active=root
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT,name+".glb"), export_format="GLB", use_selection=True, export_apply=True)
    print("EXPORTED",name,root.dimensions[:])

def cone_between(a,b,r1,r2,material,verts=8):
    d=Vector(b)-Vector(a); mid=(Vector(a)+Vector(b))/2
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r1, radius2=r2, depth=d.length, location=mid)
    o=bpy.context.object; o.name="branch_or_trunk"; o.rotation_mode="QUATERNION"; o.rotation_quaternion=d.to_track_quat("Z","Y"); o.data.materials.append(material)
    return o

def sphere(loc, scale, material, seg=12, rings=8, ico=False):
    if ico: bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1, location=loc)
    else: bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=rings, radius=1, location=loc)
    o=bpy.context.object; o.scale=scale; o.data.materials.append(material)
    for p in o.data.polygons: p.use_smooth=True
    return o

def curve_tube(points, radius, material, name="twig"):
    c=bpy.data.curves.new(name,"CURVE"); c.dimensions="3D"; c.resolution_u=2; c.bevel_depth=radius; c.bevel_resolution=1
    s=c.splines.new("POLY"); s.points.add(len(points)-1)
    for p,co in zip(s.points,points): p.co=(*co,1)
    o=bpy.data.objects.new(name,c); bpy.context.collection.objects.link(o); o.data.materials.append(material)
    bpy.context.view_layer.objects.active=o; o.select_set(True); bpy.ops.object.convert(target="MESH"); return bpy.context.object

def spruce():
    reset(); rng=random.Random(1101)
    cone_between((0,0,0),(0,0,7.2),.32,.035,BARK,12)
    for level in range(13):
        z=.75+level*.47; radius=2.05*(1-z/8.1)**.78+.12
        for j in range(7):
            a=2*math.pi*j/7+level*.37; length=radius*rng.uniform(.72,1.05)
            end=(math.cos(a)*length,z*0+math.sin(a)*length,z-.18)
            mid=(math.cos(a)*length*.55,math.sin(a)*length*.55,z+.12)
            curve_tube([(0,0,z+.18),mid,end],rng.uniform(.035,.065),BARK)
            # layered needle sprays along every bough
            for k in range(4):
                t=.25+k*.17; p=Vector(mid).lerp(Vector(end),t)
                sphere((p.x,p.y,p.z),(.22,.22,.14),NEEDLE_DARK if (j+k)%3 else NEEDLE,8,5)
    finish("tree_spruce",[])

def pine():
    reset(); rng=random.Random(2202)
    cone_between((0,0,0),(0,0,6.8),.28,.045,BARK,10)
    for level in range(8):
        z=2.0+level*.48; radius=2.1*(1-level/10)
        for j in range(5):
            a=2*math.pi*j/5+level*.52; length=radius*rng.uniform(.7,1.0)
            end=(math.cos(a)*length,math.sin(a)*length,z+.15)
            curve_tube([(0,0,z), (end[0]*.52,end[1]*.52,z+.2),end],.045,BARK)
            for k in range(3):
                p=Vector(end)*(.45+k*.17); p.z=z+.25+k*.06
                sphere(p,(.34,.17,.13),NEEDLE,9,6)
    finish("tree_pine",[])

def birch():
    reset(); rng=random.Random(3303)
    cone_between((0,0,0),(0,0,6.5),.22,.075,BIRCH,12)
    # characteristic horizontal dark scars and peeling patches
    for i in range(28):
        z=rng.uniform(.35,6.2); a=rng.uniform(0,math.tau); r=.18*(1-z/9)
        o=sphere((math.cos(a)*r,math.sin(a)*r,z),(rng.uniform(.07,.16),.035,rng.uniform(.018,.045)),BIRCH_DARK,8,5)
        o.rotation_euler[2]=a
    for i in range(9):
        z=rng.uniform(3.5,6.1); a=math.tau*i/9+rng.uniform(-.2,.2); length=rng.uniform(1.0,1.8)
        end=(math.cos(a)*length,math.sin(a)*length,z+rng.uniform(.2,.9))
        curve_tube([(0,0,z-.3),(end[0]*.55,end[1]*.55,z+.15),end],.045,BIRCH_DARK)
        for k in range(3):
            sphere((end[0]*(.65+k*.1),end[1]*(.65+k*.1),end[2]+k*.13),(.34,.3,.28),LEAF_LIGHT,10,7)
    finish("tree_birch",[])

def shrub():
    reset(); rng=random.Random(4404)
    for i in range(18):
        a=rng.uniform(0,math.tau); r=rng.uniform(0,.9); z=rng.uniform(.25,.9)
        loc=(math.cos(a)*r,math.sin(a)*r,z)
        curve_tube([(0,0,.08), (loc[0]*.6,loc[1]*.6,z*.65),loc],rng.uniform(.018,.035),BARK)
        sphere(loc,(rng.uniform(.22,.42),rng.uniform(.2,.38),rng.uniform(.18,.34)),LEAF if i%3 else LEAF_LIGHT,10,7)
    finish("shrub_mixed",[])

def fern():
    reset(); rng=random.Random(5505)
    for frond in range(9):
        a=math.tau*frond/9; length=rng.uniform(1.0,1.55); height=rng.uniform(.45,.8)
        pts=[]
        for j in range(7):
            t=j/6; rad=length*t; z=.08+height*math.sin(t*math.pi*.78)
            pts.append((math.cos(a)*rad,math.sin(a)*rad,z))
        curve_tube(pts,.018,FERN)
        for j in range(1,7):
            t=j/7; p=Vector(pts[j]); size=.24*(1-t*.55)
            for side in (-1,1):
                q=p+Vector((-math.sin(a)*size*side,math.cos(a)*size*side,-.035))
                o=sphere(q,(size*.72,.055,.035),FERN,8,5); o.rotation_euler[2]=a
    finish("fern_cluster",[])

def rock():
    reset(); rng=random.Random(6606)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3,radius=1,location=(0,0,.62))
    o=bpy.context.object; o.name="weathered_rock"; o.scale=(1.15,.9,.72)
    for v in o.data.vertices:
        n=rng.uniform(.82,1.18); v.co*=n
    o.data.materials.append(STONE)
    for p in o.data.polygons: p.use_smooth=True
    for i in range(5):
        sphere((rng.uniform(-.65,.65),rng.uniform(-.55,.55),rng.uniform(.85,1.12)),(rng.uniform(.16,.38),rng.uniform(.12,.3),.055),MOSS,8,5)
    finish("rock_mossy",[])

def stump():
    reset(); rng=random.Random(7707)
    cone_between((0,0,0),(0,0,1.0),.48,.39,BARK,11)
    bpy.ops.mesh.primitive_cylinder_add(vertices=11,radius=.39,depth=.055,location=(0,0,1.01))
    bpy.context.object.data.materials.append(WOOD)
    for i in range(5):
        a=math.tau*i/5; cone_between((math.cos(a)*.2,math.sin(a)*.2,.25),(math.cos(a)*.72,math.sin(a)*.72,.05),.11,.025,BARK,7)
    for i in range(7):
        a=rng.uniform(0,math.tau); sphere((math.cos(a)*.35,math.sin(a)*.35,.18),(.16,.13,.07),MOSS,8,5)
    finish("stump_mossy",[])

def fallen_log():
    reset()
    cone_between((-1.9,0,.32),(1.9,.12,.28),.28,.22,BARK,12)
    # broken branch stubs
    for x,y,z in [(-.9,-.12,.5),(.15,.1,.48),(1.05,-.08,.46)]:
        cone_between((x,y,z),(x+.22,y+.35,z+.34),.09,.025,BARK,7)
    finish("fallen_log",[])

for build in (spruce,pine,birch,shrub,fern,rock,stump,fallen_log):
    build()
print("ASSET_BATCH_COMPLETE", OUT)
