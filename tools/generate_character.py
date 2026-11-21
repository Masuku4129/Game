import bpy, math, os
from mathutils import Vector
from math import sin, cos, pi

OUT=os.path.abspath("assets/character/field_explorer.glb")
os.makedirs(os.path.dirname(OUT),exist_ok=True)
bpy.ops.object.select_all(action="SELECT"); bpy.ops.object.delete(use_global=False)
for datablocks in (bpy.data.meshes,bpy.data.materials,bpy.data.armatures,bpy.data.actions):
    for block in list(datablocks):
        if block.users==0: datablocks.remove(block)

# Packed procedural textile atlas: mottled wool, canvas and leather micro-patterns.
def fabric_mat(name, base, rough=.92, pattern_scale=1.0):
    m=bpy.data.materials.new(name); m.use_nodes=True
    nt=m.node_tree; nodes=nt.nodes; links=nt.links; p=nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value=(*base,1); p.inputs["Roughness"].default_value=rough
    noise=nodes.new("ShaderNodeTexNoise"); noise.inputs["Scale"].default_value=32*pattern_scale; noise.inputs["Detail"].default_value=3; noise.inputs["Roughness"].default_value=.72
    ramp=nodes.new("ShaderNodeValToRGB"); ramp.color_ramp.elements[0].position=.18; ramp.color_ramp.elements[0].color=(*(c*.78 for c in base),1); ramp.color_ramp.elements[1].position=.82; ramp.color_ramp.elements[1].color=(*(min(1,c*1.18) for c in base),1)
    links.new(noise.outputs["Fac"],ramp.inputs["Fac"])
    # Embedded color texture with textile grain and cross-weave detail (GLB-compatible).
    size=128; pixels=[]
    seed=sum(ord(ch) for ch in name)+23
    for y in range(size):
        v=y/float(size-1)
        for x in range(size):
            u=x/float(size-1)
            weave=0.965+0.025*sin(x*1.65)+0.018*cos(y*1.48)+0.012*sin((x+y)*2.2)
            mottling=0.92+0.075*sin(x*.19+y*.13+seed)+0.035*cos(x*.31-y*.17)
            f=weave*mottling
            pixels.extend((min(1,base[0]*f),min(1,base[1]*f),min(1,base[2]*f),1.0))
    img=bpy.data.images.new(name.replace(" ","_")+"_Albedo",width=size,height=size,alpha=False)
    img.pixels=pixels; img.pack()
    tex=nodes.new("ShaderNodeTexImage"); tex.image=img; tex.interpolation="Linear"
    links.new(tex.outputs["Color"],p.inputs["Base Color"])
    bump=nodes.new("ShaderNodeBump"); bump.inputs["Strength"].default_value=.10; bump.inputs["Distance"].default_value=.012; links.new(noise.outputs["Fac"],bump.inputs["Height"]); links.new(bump.outputs["Normal"],p.inputs["Normal"])
    return m
coat=fabric_mat("Wool | worn umber field coat",(.22,.18,.13),.96)
shirt=fabric_mat("Linen | muted oatmeal",(.47,.42,.33),.93)
pants=fabric_mat("Wool | dark charcoal brown",(.18,.17,.14),.96)
leather=fabric_mat("Leather | saddle brown",(.16,.09,.045),.86)
boot=fabric_mat("Boot leather | blackened",(.055,.045,.033),.82)
skin=fabric_mat("Skin | natural warm",(.44,.29,.21),.72)
hair=fabric_mat("Hair | dark chestnut",(.065,.038,.025),.88)
scarf=fabric_mat("Woven scarf | olive",(.24,.21,.12),.93)
brass=bpy.data.materials.new("Brass hardware"); brass.diffuse_color=(.48,.32,.13,1); brass.use_nodes=True; brass.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value=(.48,.32,.13,1); brass.node_tree.nodes["Principled BSDF"].inputs["Metallic"].default_value=.55
brass_image=bpy.data.images.new("BrassHardware_Albedo",width=64,height=64,alpha=False)
brass_pixels=[]
for y in range(64):
    for x in range(64):
        grain=0.94+0.045*sin(x*.21+y*.17)
        brass_pixels.extend((.48*grain,.32*grain,.13*grain,1.0))
brass_image.pixels=brass_pixels; brass_image.pack()
brass_texture=brass.node_tree.nodes.new("ShaderNodeTexImage"); brass_texture.image=brass_image
brass.node_tree.links.new(brass_texture.outputs["Color"],brass.node_tree.nodes["Principled BSDF"].inputs["Base Color"])

# Skeleton
arm=bpy.data.armatures.new("ExplorerSkeleton"); rig=bpy.data.objects.new("ExplorerRig",arm); bpy.context.collection.objects.link(rig); bpy.context.view_layer.objects.active=rig; rig.select_set(True)
rig.show_in_front=True; arm.display_type="OCTAHEDRAL"
bpy.ops.object.mode_set(mode="EDIT"); bones={}
def bone(name,head,tail,parent=None,connect=False):
    b=arm.edit_bones.new(name); b.head=head; b.tail=tail
    if parent: b.parent=bones[parent]; b.use_connect=connect
    bones[name]=b; return b
bone("root",(0,0,0),(0,0,.15))
bone("pelvis",(0,0,.86),(0,0,1.03),"root")
bone("spine",(0,0,1.03),(0,0,1.32),"pelvis",True)
bone("chest",(0,0,1.32),(0,0,1.48),"spine",True)
bone("neck",(0,0,1.48),(0,0,1.57),"chest",True)
bone("head",(0,0,1.57),(0,0,1.78),"neck",True)
for side,sgn in [("L",-1),("R",1)]:
    bone("upper_arm_"+side,(sgn*.19,0,1.43),(sgn*.34,0,1.22),"chest")
    bone("forearm_"+side,(sgn*.34,0,1.22),(sgn*.37,-.01,.98),"upper_arm_"+side,True)
    bone("hand_"+side,(sgn*.37,-.01,.98),(sgn*.37,-.03,.88),"forearm_"+side,True)
    bone("thigh_"+side,(sgn*.12,0,.91),(sgn*.13,0,.53),"pelvis")
    bone("shin_"+side,(sgn*.13,0,.53),(sgn*.13,-.015,.13),"thigh_"+side,True)
    bone("foot_"+side,(sgn*.13,-.015,.13),(sgn*.13,-.20,.08),"shin_"+side,True)
bpy.ops.object.mode_set(mode="OBJECT"); rig.animation_data_create()

def smooth(obj):
    if obj.type=="MESH":
        for f in obj.data.polygons: f.use_smooth=True
def assign_rigid(obj,bn):
    obj.parent=rig; obj.matrix_parent_inverse=rig.matrix_world.inverted()
    vg=obj.vertex_groups.new(name=bn); vg.add(list(range(len(obj.data.vertices))),1.0,"REPLACE")
    obj.modifiers.new("Explorer skin","ARMATURE").object=rig
def ellipsoid(name,loc,scale,mat,bn,seg=20,rings=12):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg,ring_count=rings,radius=1,location=loc); o=bpy.context.object; o.name=name; o.scale=scale; o.data.materials.append(mat); smooth(o); assign_rigid(o,bn); return o
def tapered(name,loc,r1,r2,depth,mat,bn,verts=16,axis="Z"):
    bpy.ops.mesh.primitive_cone_add(vertices=verts,radius1=r1,radius2=r2,depth=depth,location=loc); o=bpy.context.object; o.name=name; o.data.materials.append(mat); smooth(o)
    if axis=="Y": o.rotation_euler[0]=pi/2
    assign_rigid(o,bn); return o
def box(name,loc,scale,mat,bn,bevel=.04):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc); o=bpy.context.object; o.name=name; o.dimensions=scale; bpy.ops.object.transform_apply(location=False,rotation=False,scale=True); o.data.materials.append(mat)
    if bevel:
        mod=o.modifiers.new("Soft worn edges","BEVEL"); mod.width=bevel; mod.segments=2
        o.modifiers.new("Weighted corner normals","WEIGHTED_NORMAL")
    assign_rigid(o,bn); return o

# Body torso volume, shirt, coat shell and layered details.
ellipsoid("Linen shirt torso",(0,0,1.25),(.245,.145,.31),shirt,"spine",24,16)
ellipsoid("Coat body",(0,0,1.25),(.29,.19,.34),coat,"spine",24,16)
ellipsoid("Chest coat shaping",(0,-.006,1.39),(.31,.195,.20),coat,"chest",24,16)
ellipsoid("Hip coat skirt",(0,.015,1.02),(.31,.205,.19),coat,"pelvis",24,16)
# two coat front panels, collar/lapels, stitching and buttons
for s in [-1,1]:
    ellipsoid("Coat lapel",(s*.105,-.176,1.39),(.105,.035,.17),shirt,"chest",18,12)
    ellipsoid("Front seam piping",(s*.11,-.207,1.22),(.014,.008,.22),leather,"spine",12,8)
    box("Pocket flap",(s*.19,-.195,1.18),(.14,.025,.075),leather,"spine",.015)
    ellipsoid("Pocket button",(s*.19,-.213,1.17),(.018,.012,.018),brass,"spine",10,8)
for z in [1.31,1.22,1.13,1.04]:
    ellipsoid("Coat button",(0,-.205,z),(.018,.012,.018),brass,"spine",10,8)
# Neck, face sculpting: brow, nose, ears, eyes, cheekbones, beard and hair.
ellipsoid("Neck",(0,0,1.55),(.09,.09,.12),skin,"neck")
ellipsoid("Head skull",(0,-.005,1.67),(.125,.112,.16),skin,"head",24,16)
ellipsoid("Jaw",(0,-.04,1.59),(.095,.095,.075),skin,"head")
ellipsoid("Nose bridge",(0,-.115,1.675),(.026,.032,.05),skin,"head",14,10)
ellipsoid("Nose tip",(0,-.137,1.65),(.033,.03,.024),skin,"head",14,10)
for s in [-1,1]:
    ellipsoid("Ear",(s*.125,-.008,1.665),(.024,.035,.045),skin,"head",12,8)
    ellipsoid("Eye",(s*.047,-.107,1.70),(.019,.012,.012),hair,"head",12,8)
    ellipsoid("Brow",(s*.048,-.116,1.72),(.032,.012,.011),hair,"head",12,8)
    ellipsoid("Cheek",(s*.061,-.089,1.625),(.043,.034,.042),skin,"head",14,10)
# hair cap and side locks; short beard/moustache adds historical rugged silhouette
ellipsoid("Hair cap",(0,.005,1.785),(.128,.12,.07),hair,"head",22,12)
for s in [-1,1]:
    ellipsoid("Sideburn",(s*.105,-.018,1.68),(.027,.043,.075),hair,"head",14,10)
    ellipsoid("Mustache",(s*.04,-.132,1.626),(.04,.019,.018),hair,"head",14,8)
ellipsoid("Short beard",(0,-.065,1.585),(.087,.09,.052),hair,"head",18,10)
# Arms: sleeves have layered shoulder and articulated elbow/forearm segments
for s,side in [(-1,"L"),(1,"R")]:
    ellipsoid("Shoulder cloth "+side,(s*.225,0,1.405),(.155,.17,.17),coat,"upper_arm_"+side,18,12)
    ellipsoid("Upper sleeve "+side,(s*.29,0,1.31),(.105,.12,.15),coat,"upper_arm_"+side,18,12)
    ellipsoid("Elbow "+side,(s*.345,0,1.22),(.085,.095,.085),coat,"forearm_"+side,16,10)
    ellipsoid("Forearm cuff "+side,(s*.36,0,1.04),(.075,.085,.095),shirt,"forearm_"+side,16,10)
    ellipsoid("Hand "+side,(s*.37,-.018,.94),(.052,.06,.075),skin,"hand_"+side,16,10)
    # Fingers grouped but individually shaped, rigidly bound to hand bone
    for finger in range(4):
        xx=s*.37+s*(finger-1.5)*.022
        ellipsoid("Finger "+side,(xx,-.04,.905),(.012,.018,.035),skin,"hand_"+side,10,6)
    ellipsoid("Thumb "+side,(s*.415,-.02,.935),(.018,.02,.04),skin,"hand_"+side,10,6)
# Pants, thigh cloth and lower gaiters
for s,side in [(-1,"L"),(1,"R")]:
    ellipsoid("Hip trousers "+side,(s*.105,0,.89),(.115,.145,.16),pants,"pelvis",18,12)
    ellipsoid("Thigh trousers "+side,(s*.13,0,.70),(.10,.12,.22),pants,"thigh_"+side,18,12)
    ellipsoid("Knee reinforcement "+side,(s*.13,-.01,.52),(.095,.13,.09),leather,"shin_"+side,16,10)
    ellipsoid("Shin "+side,(s*.13,0,.32),(.073,.095,.20),pants,"shin_"+side,18,12)
    ellipsoid("Gaiter "+side,(s*.13,-.002,.17),(.078,.10,.09),leather,"shin_"+side,16,10)
    ellipsoid("Boot ankle "+side,(s*.13,-.005,.095),(.088,.12,.07),boot,"foot_"+side,16,10)
    ellipsoid("Boot toe "+side,(s*.13,-.10,.07),(.088,.19,.065),boot,"foot_"+side,18,10)
    # Boot welt and brass hooks
    ellipsoid("Boot welt "+side,(s*.13,-.095,.025),(.09,.19,.018),leather,"foot_"+side,16,8)
    for lace in range(4):
        ellipsoid("Boot lace "+side,(s*.13,-.11,.105-lace*.018),(.045,.008,.006),shirt,"foot_"+side,10,6)
# Back pack, straps, side pouch and bedroll
box("Canvas pack",(0,.205,1.25),(.38,.19,.44),leather,"chest",.07)
box("Pack flap",(0,.105,1.46),(.34,.035,.10),coat,"chest",.04)
for s in [-1,1]:
    ellipsoid("Pack strap",(s*.19,-.09,1.32),(.035,.04,.28),leather,"chest",14,10)
    ellipsoid("Pack buckle",(s*.19,-.125,1.25),(.026,.012,.035),brass,"chest",10,8)
# Seasonal outer garments and scarf geometry: winter collar/scarf variants exported as named mesh pieces.
ellipsoid("Neck scarf",(0,-.12,1.51),(.16,.045,.08),scarf,"chest",18,12)
ellipsoid("Scarf tail",(s*.12,-.12,1.43),(.045,.035,.12),scarf,"chest",16,10)
# Animation helpers
def key_pose(frame, pose):
    for name,rot in pose.items():
        pb=rig.pose.bones.get(name)
        if pb:
            pb.rotation_mode="XYZ"; pb.rotation_euler=rot; pb.keyframe_insert(data_path="rotation_euler",frame=frame,group=name)
def base_pose():
    for pb in rig.pose.bones: pb.rotation_mode="XYZ"; pb.rotation_euler=(0,0,0)
# Idle loop, subtle chest/neck/arms motion
bpy.context.scene.frame_start=1; bpy.context.scene.frame_end=48; bpy.context.scene.render.fps=24
base_pose(); key_pose(1,{"chest":(0,0,0),"head":(0,0,0),"upper_arm_L":(0,0,-.03),"upper_arm_R":(0,0,.03)})
key_pose(24,{"chest":(.018,0,0),"head":(-.012,0,0),"upper_arm_L":(.015,0,-.03),"upper_arm_R":(-.015,0,.03)})
key_pose(48,{"chest":(0,0,0),"head":(0,0,0),"upper_arm_L":(0,0,-.03),"upper_arm_R":(0,0,.03)})
action=bpy.data.actions[-1]; action.name="Explorer_Idle_Breathing"
# Walk cycle: opposite arms/legs, slight torso sway and knee lift
bpy.ops.object.mode_set(mode="OBJECT")
rig.animation_data.action=None
base_pose()
for frame in [1,13,25,37,49]:
    ph=(frame-1)/48.0*2*pi
    pose={"thigh_L":(sin(ph)*.48,0,0),"thigh_R":(sin(ph+pi)*.48,0,0),
          "upper_arm_L":(sin(ph+pi)*.30,0,-.05),"upper_arm_R":(sin(ph)*.30,0,.05),
          "spine":(0,0,sin(ph)*.025),"chest":(0,0,sin(ph)*.035)}
    key_pose(frame,pose)
bpy.context.scene.frame_end=48
walk=bpy.data.actions[-1]; walk.name="Explorer_Walk"
# Run loop amplitude/speed enhanced
bpy.ops.object.mode_set(mode="OBJECT"); rig.animation_data.action=None; base_pose()
bpy.context.scene.frame_end=36
for frame in [1,10,19,28,37]:
    ph=(frame-1)/36.0*2*pi
    key_pose(frame,{"thigh_L":(sin(ph)*.78,0,0),"thigh_R":(sin(ph+pi)*.78,0,0),
      "upper_arm_L":(sin(ph+pi)*.48,0,-.08),"upper_arm_R":(sin(ph)*.48,0,.08),
      "spine":(sin(ph)*.045,0,sin(ph)*.04),"chest":(sin(ph)*.04,0,sin(ph)*.055)})
run=bpy.data.actions[-1]; run.name="Explorer_Run"
# Export rig, skinned mesh objects, and three actions as glTF animations
bpy.ops.object.mode_set(mode="OBJECT")
bpy.ops.object.select_all(action="DESELECT")
rig.select_set(True)
for obj in list(bpy.context.scene.objects):
    if obj != rig: obj.select_set(True)
bpy.context.view_layer.objects.active=rig
# Export actions from NLA strips
rig.animation_data.action=None
for act in [action,walk,run]:
    track=rig.animation_data.nla_tracks.new(); track.name=act.name
    strip=track.strips.new(act.name,1,act); strip.action=act; strip.blend_type="REPLACE"
bpy.ops.export_scene.gltf(filepath=OUT,export_format="GLB",use_selection=True,export_animations=True,export_nla_strips=True,export_apply=True)
print("EXPLORER_CHARACTER_EXPORTED",OUT)
