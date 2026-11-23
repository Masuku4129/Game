extends RefCounted
## Герой: базовая фигура Quaternius (Universal Base Characters) + анимации Universal Animation
## Library 1 и 2 (одна и та же схема костей). Одежда строится из самой фигуры: участки тела
## раздуваются по нормалям и сохраняют веса костей, поэтому гнутся вместе с телом.

const BODY := "res://models/hero/Superhero_Male_FullBody.gltf"
const LIBS := ["res://models/hero/UAL1.glb", "res://models/hero/UAL2.glb"]
const HAIR := ["res://models/hero/Hair_SimpleParted.gltf", "res://models/hero/Hair_Beard.gltf"]

static var _sh: Shader = null

static func mat(c: Color, tex: Texture2D = null, vc: bool = false, cut: float = 0.0) -> ShaderMaterial:
	if _sh == null:
		_sh = load("res://shaders/paint/skin.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _sh
	m.set_shader_parameter("tint", Vector3(c.r, c.g, c.b))
	m.set_shader_parameter("use_tex", tex != null)
	if tex != null:
		m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("use_vc", vc)
	m.set_shader_parameter("alpha_cut", cut)
	return m

static func _tex_of(m: Material) -> Texture2D:
	if m is BaseMaterial3D:
		return (m as BaseMaterial3D).albedo_texture
	return null

## Сборка: возвращает {model, ap, sk}.
## --- colony: pal — своя раскраска для каждого землепроходца (ключи jacket, pants,
## boots, fur, hair); пусто — цвета героя. ---
static func build(parent: Node3D, pal: Dictionary = {}) -> Dictionary:
	var model: Node3D = load(BODY).instantiate()
	parent.add_child(model)
	var sk: Skeleton3D = model.find_child("Skeleton3D", true, false)
	var body: MeshInstance3D = sk.find_child("SuperHero_Male", false, false)
	# материалы: кожа и глаза с текстурой, живописный свет
	for mi: MeshInstance3D in sk.find_children("*", "MeshInstance3D", false, false):
		for s in mi.mesh.get_surface_count():
			var om := mi.mesh.surface_get_material(s)
			var tint := Color(1, 1, 1)
			if mi == body:
				tint = Color(1.0, 0.97, 0.95)
			elif mi.name == "Eyebrows":
				tint = Color(0.45, 0.32, 0.22)
			mi.set_surface_override_material(s, mat(tint, _tex_of(om), false, 0.4 if mi.name == "Eyebrows" else 0.0))
	_dress(sk, body, pal)
	# причёска и борода — неподвижные модели, крепим к голове
	var hb := sk.find_bone("Head")
	var ba := BoneAttachment3D.new()
	ba.bone_name = "Head"
	sk.add_child(ba)
	for h in HAIR:
		var hn: Node3D = load(h).instantiate()
		var hair_c: Color = pal.get("hair", Color(0.5, 0.36, 0.26))
		for mi: MeshInstance3D in hn.find_children("*", "MeshInstance3D", true, false):
			for s in mi.mesh.get_surface_count():
				mi.set_surface_override_material(s, mat(hair_c, _tex_of(mi.mesh.surface_get_material(s)), false, 0.35))
		hn.transform = sk.get_bone_global_rest(hb).affine_inverse()
		ba.add_child(hn)
	# анимации: обе библиотеки в один проигрыватель; позиции костей оставляем только у таза
	var ap := AnimationPlayer.new()
	model.add_child(ap)
	ap.root_node = ap.get_path_to(model)
	var lib := AnimationLibrary.new()
	for path in LIBS:
		var src: Node = load(path).instantiate()
		var sap: AnimationPlayer = src.find_children("*", "AnimationPlayer", true, false)[0]
		for n in sap.get_animation_list():
			if lib.has_animation(n):
				continue
			var a: Animation = sap.get_animation(n).duplicate()
			for t in range(a.get_track_count() - 1, -1, -1):
				if a.track_get_type(t) == Animation.TYPE_POSITION_3D and not String(a.track_get_path(t)).ends_with(":pelvis") and not String(a.track_get_path(t)).ends_with(":root"):
					a.remove_track(t)
			if String(n).ends_with("_Loop"):
				a.loop_mode = Animation.LOOP_LINEAR
			lib.add_animation(n, a)
		src.free()
	ap.add_animation_library("", lib)
	ap.playback_default_blend_time = 0.25
	ap.play("Idle")
	return {"model": model, "ap": ap, "sk": sk}

## Одежда из тела: куртка-полушубок до бёдер с меховым воротом и обшлагами, штаны, сапоги.
## Каждый треугольник тела принадлежит ровно одному слою — без щелей; под одеждой тело убирается.
static func _dress(sk: Skeleton3D, body: MeshInstance3D, pal: Dictionary = {}) -> void:
	var mesh: ArrayMesh = body.mesh
	var arr := mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var ws: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var per: int = bones.size() / vs.size()
	var skin: Skin = body.skin
	var bname := []
	for i in skin.get_bind_count():
		var nm := String(skin.get_bind_name(i))
		if nm == "":
			nm = sk.get_bone_name(skin.get_bind_bone(i))
		bname.append(nm)
	var hand_l := sk.get_bone_global_rest(sk.find_bone("hand_l")).origin
	var hand_r := sk.get_bone_global_rest(sk.find_bone("hand_r")).origin
	var neck_y := sk.get_bone_global_rest(sk.find_bone("neck_01")).origin.y
	var knee_y := sk.get_bone_global_rest(sk.find_bone("calf_l")).origin.y
	var hip_y := sk.get_bone_global_rest(sk.find_bone("pelvis")).origin.y
	# слой вершины: 0 кожа, 1 куртка, 2 штаны, 3 сапоги; 4 — мех (ворот, обшлага, подол куртки)
	var region := PackedInt32Array()
	region.resize(vs.size())
	for i in vs.size():
		var best := 0
		var bw := -1.0
		for k in per:
			if ws[i * per + k] > bw:
				bw = ws[i * per + k]
				best = bones[i * per + k]
		var b: String = bname[best] if best < bname.size() else ""
		var v := vs[i]
		var r := 0
		if b.begins_with("hand") or b.begins_with("index") or b.begins_with("middle") or b.begins_with("ring") or b.begins_with("pinky") or b.begins_with("thumb") or b == "Head":
			r = 0
		elif b.begins_with("neck"):
			r = 4 if v.y < neck_y + 0.03 else 0
		elif b.begins_with("lowerarm"):
			var hd := minf(v.distance_to(hand_l), v.distance_to(hand_r))
			r = 4 if hd < 0.09 else 1
		elif b.begins_with("spine") or b.begins_with("clavicle") or b.begins_with("upperarm"):
			r = 1
		elif b == "pelvis" or b.begins_with("thigh"):
			r = 1 if v.y > hip_y - 0.02 else (4 if v.y > hip_y - 0.09 else 2)
		elif b.begins_with("calf"):
			r = 2 if v.y > knee_y - 0.12 else 3
		elif b.begins_with("foot") or b.begins_with("ball"):
			r = 3
		region[i] = r
	var lay := {1: [0.032, pal.get("jacket", Color(0.5, 0.41, 0.31))], 2: [0.014, pal.get("pants", Color(0.44, 0.43, 0.37))],
		3: [0.018, pal.get("boots", Color(0.3, 0.22, 0.16))], 4: [0.03, pal.get("fur", Color(0.82, 0.76, 0.64))]}
	var tris := {0: PackedInt32Array(), 1: PackedInt32Array(), 2: PackedInt32Array(), 3: PackedInt32Array(), 4: PackedInt32Array()}
	for t in range(0, idx.size(), 3):
		# слой треугольника — наибольший номер среди вершин (мех и одежда перекрывают кожу)
		var r := maxi(region[idx[t]], maxi(region[idx[t + 1]], region[idx[t + 2]]))
		var pa: PackedInt32Array = tris[r]
		pa.append(idx[t]); pa.append(idx[t + 1]); pa.append(idx[t + 2])
		tris[r] = pa
	# сглаженные нормали по совпадающим позициям: швы развёртки не рвут раздутую одежду
	var acc := {}
	for i in vs.size():
		var key := Vector3i((vs[i] * 2000.0).round())
		acc[key] = (acc.get(key, Vector3.ZERO) as Vector3) + ns[i]
	var sn := PackedVector3Array(); sn.resize(vs.size())
	for i in vs.size():
		var key := Vector3i((vs[i] * 2000.0).round())
		sn[i] = (acc[key] as Vector3).normalized()
	var fmt := mesh.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	# тело: только открытая кожа
	var a0 := arr.duplicate()
	a0[Mesh.ARRAY_INDEX] = tris[0]
	var m0 := ArrayMesh.new()
	m0.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a0, [], {}, fmt)
	m0.surface_set_material(0, body.get_surface_override_material(0))
	body.mesh = m0
	for rid: int in [1, 2, 3, 4]:
		var off: float = lay[rid][0]
		var col: Color = lay[rid][1]
		var nv := PackedVector3Array(); nv.resize(vs.size())
		var cols := PackedColorArray(); cols.resize(vs.size())
		for i in vs.size():
			var o := off
			if rid == 1 and vs[i].y < hip_y + 0.2:
				o += (hip_y + 0.2 - vs[i].y) * 0.08
			nv[i] = vs[i] + sn[i] * o
			cols[i] = col
		var a2 := arr.duplicate()
		a2[Mesh.ARRAY_VERTEX] = nv
		a2[Mesh.ARRAY_COLOR] = cols
		a2[Mesh.ARRAY_INDEX] = tris[rid]
		a2[Mesh.ARRAY_TANGENT] = null
		var m2 := ArrayMesh.new()
		m2.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a2, [], {}, fmt)
		var mi := MeshInstance3D.new()
		mi.mesh = m2
		mi.skin = skin
		sk.add_child(mi)
		mi.skeleton = mi.get_path_to(sk)
		mi.material_override = mat(Color(1, 1, 1), null, true)
