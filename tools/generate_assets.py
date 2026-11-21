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
    for datablocks in (bpy.data.meshes, bpy.data.curves):
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
GRASS_DARK=mat("Grass | deep blades",(.075,.17,.065),.92,True)
GRASS_LIGHT=mat("Grass | sunlit blades",(.22,.31,.095),.9,True)
GRASS_SEED=mat("Grass | seed heads",(.42,.34,.17),.94,True)
STONE_LIGHT=mat("Stone | pale fractured faces",(.39,.39,.35),.96,True)

def _seasonal_material(source, season):
    material = source.copy()
    material.name = source.name + " | " + season
    palette = {
        "spring": {
            "Spruce | deep needles": (.055, .19, .12),
            "Pine | muted needles": (.16, .29, .16),
            "Broadleaf | forest green": (.27, .43, .16),
            "Leaves | young green": (.43, .57, .20),
            "Fern | rich green": (.19, .39, .14),
            "Moss | damp green": (.22, .34, .12),
            "Grass | deep blades": (.12, .24, .08),
            "Grass | sunlit blades": (.34, .47, .16),
            "Grass | seed heads": (.47, .38, .18),
        },
        "summer": {
            "Spruce | deep needles": (.035, .12, .075),
            "Pine | muted needles": (.10, .22, .12),
            "Broadleaf | forest green": (.17, .28, .105),
            "Leaves | young green": (.27, .37, .13),
            "Fern | rich green": (.10, .27, .105),
            "Moss | damp green": (.16, .23, .085),
            "Grass | deep blades": (.075, .17, .065),
            "Grass | sunlit blades": (.22, .31, .095),
            "Grass | seed heads": (.42, .34, .17),
        },
        "autumn": {
            "Spruce | deep needles": (.045, .13, .085),
            "Pine | muted needles": (.13, .20, .10),
            "Broadleaf | forest green": (.66, .25, .075),
            "Leaves | young green": (.82, .48, .10),
            "Fern | rich green": (.48, .30, .10),
            "Moss | damp green": (.25, .20, .085),
            "Grass | deep blades": (.40, .29, .10),
            "Grass | sunlit blades": (.68, .47, .14),
            "Grass | seed heads": (.62, .45, .20),
        },
        "winter": {
            "Spruce | deep needles": (.18, .25, .22),
            "Pine | muted needles": (.23, .29, .24),
            "Broadleaf | forest green": (.28, .30, .27),
            "Leaves | young green": (.30, .31, .28),
            "Fern | rich green": (.30, .25, .16),
            "Moss | damp green": (.48, .52, .49),
            "Grass | deep blades": (.29, .32, .29),
            "Grass | sunlit blades": (.43, .45, .41),
            "Grass | seed heads": (.55, .53, .45),
            "Stone | pale fractured faces": (.53, .56, .57),
            "Stone | weathered grey": (.48, .52, .54),
        },
    }
    color = palette[season].get(source.name)
    if color is not None:
        material.diffuse_color = (*color, 1)
        if material.use_nodes:
            shader = material.node_tree.nodes.get("Principled BSDF")
            if shader:
                shader.inputs["Base Color"].default_value = (*color, 1)
    return material


def _export_seasonal_variant(root, asset_name, season):
    variant = root.copy()
    variant.data = root.data.copy()
    variant.name = asset_name + "_" + season
    bpy.context.collection.objects.link(variant)
    variant_material_names = []
    for index, source in enumerate(list(variant.data.materials)):
        if source is None:
            continue
        seasonal = _seasonal_material(source, season)
        variant.data.materials[index] = seasonal
        variant_material_names.append((index, source.name))

    # Deciduous crowns thin during autumn and become bare in winter.
    if season in ("autumn", "winter") and asset_name in ("tree_birch", "shrub_mixed"):
        import bmesh
        leaf_slots = {
            index for index, name in variant_material_names
            if name in ("Broadleaf | forest green", "Leaves | young green")
        }
        if leaf_slots:
            bm = bmesh.new()
            bm.from_mesh(variant.data)
            rng = random.Random(sum(ord(ch) for ch in asset_name + season) + 1703)
            if season == "winter":
                doomed = [face for face in bm.faces if face.material_index in leaf_slots]
            else:
                doomed = [face for face in bm.faces if face.material_index in leaf_slots and rng.random() < 0.28]
            bmesh.ops.delete(bm, geom=doomed, context="FACES")
            bm.to_mesh(variant.data)
            bm.free()
            variant.data.update()

    # Grass bends down under autumn decay and winter snow cover.
    if asset_name == "grass_tuft":
        if season in ("autumn", "winter"):
            factor = 0.82 if season == "autumn" else 0.56
            for vertex in variant.data.vertices:
                vertex.co.z *= factor
                if season == "winter":
                    vertex.co.x += vertex.co.z * 0.16

    # Snow rests on upper-facing foliage and ground objects in winter.
    if season == "winter":
        snow = mat("Seasonal snow | " + asset_name, (.82, .88, .91), .78, True)
        snow_index = len(variant.data.materials)
        variant.data.materials.append(snow)
        rng = random.Random(sum(ord(ch) for ch in asset_name) + 9901)
        for polygon in variant.data.polygons:
            original_index = polygon.material_index
            original_name = next((name for idx, name in variant_material_names if idx == original_index), "")
            eligible = (
                original_name.startswith("Spruce |") or
                original_name.startswith("Pine |") or
                (asset_name in ("rock_mossy", "stone_cluster", "stump_mossy", "fallen_log", "fern_cluster")
                 and polygon.normal.z > 0.48 and not original_name.startswith("Bark"))
            )
            if eligible and rng.random() < (0.28 if asset_name.startswith("tree_") else 0.20):
                polygon.material_index = snow_index

    bpy.ops.object.select_all(action="DESELECT")
    variant.select_set(True)
    bpy.context.view_layer.objects.active = variant
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(OUT, variant.name + ".glb"),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
    )
    print("EXPORTED_SEASON", variant.name, tuple(variant.dimensions))


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
    bpy.context.scene.cursor.location=(0,0,0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    for season in ("spring", "summer", "autumn", "winter"):
        _export_seasonal_variant(root, name, season)
    bpy.ops.object.select_all(action="DESELECT")
    bpy.data.objects.remove(root, do_unlink=True)

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
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active=o; o.select_set(True); bpy.ops.object.convert(target="MESH"); return bpy.context.object

def leaf(loc, direction, length, width, material, name="leaf"):
    axis = Vector(direction).normalized()
    if axis.length < 0.001:
        axis = Vector((0, 0, 1))
    reference = Vector((0, 0, 1)) if abs(axis.z) < 0.92 else Vector((0, 1, 0))
    side = axis.cross(reference).normalized()
    normal = axis.cross(side).normalized()
    vertices = []
    # A gently cupped, pointed leaf with a raised central vein.
    profile = [(0.0, 0.10), (0.22, 0.72), (0.52, 1.0), (0.78, 0.66), (1.0, 0.0)]
    for t, spread in profile:
        center = Vector(loc) + axis * (length * t) + normal * (math.sin(t * math.pi) * length * 0.075)
        half = width * spread
        vertices.extend([
            center - side * half - normal * 0.012,
            center + normal * 0.025,
            center + side * half - normal * 0.012,
        ])
    faces = []
    for row in range(len(profile) - 1):
        a = row * 3
        b = (row + 1) * 3
        faces.extend([(a, b, b + 1, a + 1), (a + 1, b + 1, b + 2, a + 2)])
    mesh = bpy.data.meshes.new(name + "_mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(material)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for poly in mesh.polygons:
        poly.use_smooth = True
    return obj


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
                leaf((p.x,p.y,p.z), (math.cos(a)*.65, math.sin(a)*.65, -.35), .52, .16, NEEDLE_DARK if (j+k)%3 else NEEDLE, "spruce_needle_spray")
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
                leaf(p, (math.cos(a)*.45, math.sin(a)*.45, .08), .72, .19, NEEDLE, "pine_needle_cluster")
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
            leaf((end[0]*(.65+k*.1),end[1]*(.65+k*.1),end[2]+k*.13), (math.cos(a),math.sin(a),.24), .62, .22, LEAF_LIGHT, "birch_leaf")
    finish("tree_birch",[])

def shrub():
    reset(); rng=random.Random(4404)
    for i in range(18):
        a=rng.uniform(0,math.tau); r=rng.uniform(0,.9); z=rng.uniform(.25,.9)
        loc=(math.cos(a)*r,math.sin(a)*r,z)
        curve_tube([(0,0,.08), (loc[0]*.6,loc[1]*.6,z*.65),loc],rng.uniform(.018,.035),BARK)
        leaf(loc, (math.cos(a), math.sin(a), rng.uniform(-.12,.42)), rng.uniform(.42,.72), rng.uniform(.13,.23), LEAF if i%3 else LEAF_LIGHT, "shrub_leaf")
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
                leaf(q, (-math.sin(a)*side, math.cos(a)*side, -.18), size*2.2, size*.48, FERN, "fern_pinna")
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

def grass_tuft():
    reset(); rng=random.Random(8808)
    for clump in range(5):
        cx=rng.uniform(-.22,.22); cy=rng.uniform(-.22,.22)
        for blade in range(11):
            a=rng.uniform(0,math.tau); lean=rng.uniform(.16,.62)
            height=rng.uniform(.42,1.05); width=rng.uniform(.035,.075)
            leaf((cx,cy,.025),(math.cos(a)*lean,math.sin(a)*lean,height),1.0,width,GRASS_LIGHT if blade%5==0 else GRASS_DARK,"grass_blade")
        if clump == 2:
            for spike in range(3):
                a=math.tau*spike/3
                curve_tube([(cx,cy,.12),(cx+math.cos(a)*.08,cy+math.sin(a)*.08,.65),(cx+math.cos(a)*.16,cy+math.sin(a)*.16,.92)],.012,GRASS_SEED,"grass_seed_stem")
                sphere((cx+math.cos(a)*.16,cy+math.sin(a)*.16,.94),(.035,.035,.12),GRASS_SEED,7,5)
    finish("grass_tuft",[])



def mushroom_cluster():
    reset()
    rng = random.Random(10101)
    cap_red = mat("Mushroom | russet cap", (0.48, 0.16, 0.075), 0.84, True)
    cap_ochre = mat("Mushroom | ochre cap", (0.55, 0.34, 0.13), 0.9, True)
    cap_pale = mat("Mushroom | pale cap", (0.68, 0.61, 0.43), 0.92, True)
    stem_mat = mat("Mushroom | ivory stem", (0.72, 0.67, 0.53), 0.96, True)
    gill_mat = mat("Mushroom | gills", (0.42, 0.34, 0.27), 0.98)
    ring_mat = mat("Mushroom | veil ring", (0.82, 0.77, 0.64), 0.9)
    moss_mat = MOSS
    for index in range(9):
        angle = rng.uniform(0.0, math.tau)
        radius = rng.uniform(0.0, 0.72)
        x = math.cos(angle) * radius
        y = math.sin(angle) * radius
        height = rng.uniform(0.24, 0.82)
        cap_radius = height * rng.uniform(0.28, 0.39)
        stem_radius = cap_radius * rng.uniform(0.17, 0.23)
        stem_top = height * 0.79
        cone_between((x, y, 0.025), (x, y, stem_top), stem_radius * 0.72, stem_radius, stem_mat, 9)
        # A distinct cap silhouette with a shallow underside and softly domed crown.
        cap_material = (cap_red, cap_ochre, cap_pale)[index % 3]
        sphere((x, y, height), (cap_radius, cap_radius * rng.uniform(0.88, 1.12), cap_radius * 0.48), cap_material, 16, 10)
        # Radial gills are visible from low camera angles beneath the cap.
        for gill in range(11):
            a = math.tau * gill / 11.0
            start = (x + math.cos(a) * stem_radius * 0.35, y + math.sin(a) * stem_radius * 0.35, height - cap_radius * 0.12)
            end = (x + math.cos(a) * cap_radius * 0.82, y + math.sin(a) * cap_radius * 0.82, height - cap_radius * 0.18)
            curve_tube([start, end], max(0.003, cap_radius * 0.018), gill_mat, "mushroom_gill")
        if index % 3 == 0:
            sphere((x, y, stem_top * 0.76), (stem_radius * 1.45, stem_radius * 1.45, 0.018), ring_mat, 9, 5)
        if index % 2 == 0:
            for spot in range(5):
                a = math.tau * spot / 5.0 + index
                spot_x = x + math.cos(a) * cap_radius * 0.48
                spot_y = y + math.sin(a) * cap_radius * 0.48
                sphere((spot_x, spot_y, height + cap_radius * 0.30), (cap_radius * 0.075, cap_radius * 0.065, 0.012), ring_mat, 7, 4)
    for index in range(7):
        a = math.tau * index / 7.0
        sphere((math.cos(a) * 0.62, math.sin(a) * 0.62, 0.035), (0.20, 0.13, 0.045), moss_mat, 8, 5)
    finish("mushroom_cluster", [])

def stone_cluster():
    reset(); rng=random.Random(9909)
    for i in range(9):
        angle=rng.uniform(0,math.tau); radius=rng.uniform(0.0,1.0)
        x=math.cos(angle)*radius; y=math.sin(angle)*radius; size=rng.uniform(.22,.64)
        count=9
        vertices=[]
        rings=[(.82,.06), (1.0,.43), (.66,.82)]
        offsets=[rng.uniform(-.18,.18) for _ in rings]
        for ring_index,(ring_radius,ring_height) in enumerate(rings):
            for vertex_index in range(count):
                a=math.tau*vertex_index/count+offsets[ring_index]
                radial=ring_radius*rng.uniform(.78,1.18)
                vertices.append((math.cos(a)*radial*size*rng.uniform(.9,1.12), math.sin(a)*radial*size*rng.uniform(.9,1.12), ring_height*size*rng.uniform(.88,1.12)))
        top_index=len(vertices)
        vertices.append((rng.uniform(-.08,.08)*size,rng.uniform(-.08,.08)*size,size*rng.uniform(.92,1.12)))
        bottom_index=len(vertices)
        vertices.append((0.0,0.0,.015*size))
        faces=[]
        for vertex_index in range(count):
            nxt=(vertex_index+1)%count
            faces.append((bottom_index,nxt,vertex_index))
            for ring_index in range(2):
                a=ring_index*count+vertex_index; b=ring_index*count+nxt
                c=(ring_index+1)*count+nxt; d=(ring_index+1)*count+vertex_index
                faces.extend([(a,b,c),(a,c,d)])
            faces.append((2*count+vertex_index,2*count+nxt,top_index))
        mesh=bpy.data.meshes.new("fractured_stone_mesh")
        mesh.from_pydata(vertices,[],faces); mesh.materials.append(STONE); mesh.materials.append(STONE_LIGHT); mesh.update()
        rock_obj=bpy.data.objects.new("fractured_stone",mesh); bpy.context.collection.objects.link(rock_obj)
        rock_obj.location=(x,y,0.0)
        rock_obj.rotation_euler[2]=rng.uniform(0,math.tau)
        for face in mesh.polygons:
            face.use_smooth=False
            face.material_index=1 if rng.random()<.24 else 0
        if i%2==0: sphere((x-size*.12,y+size*.08,size*.72),(size*.22,size*.16,.025),MOSS,7,5)
    finish("stone_cluster",[])


for build in (spruce,pine,birch,shrub,fern,rock,grass_tuft,stone_cluster,stump,fallen_log,mushroom_cluster):
    build()
print("ASSET_BATCH_COMPLETE", OUT)
