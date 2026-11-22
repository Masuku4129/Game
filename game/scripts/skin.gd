extends RefCounted
## Готовые модели с анимациями (Quaternius, CC0): загрузка, масштаб, живописная перекраска,
## сглаживание граней и выбор анимаций.

const ANIMALS := {
	"roe": {"path": "res://models/animals/Deer.gltf", "scale": 0.27,
		"cols": {"Main": Color(0.56, 0.36, 0.2), "Main_Light": Color(0.86, 0.8, 0.7), "Main_Dark": Color(0.3, 0.2, 0.13), "Hooves": Color(0.12, 0.1, 0.08)},
		"winter": {"Main": Color(0.45, 0.38, 0.32)}},
	"deer": {"path": "res://models/animals/Stag.gltf", "scale": 0.46,
		"cols": {}, "winter": {}},
	"wolf": {"path": "res://models/animals/Wolf.gltf", "scale": 0.34,
		"cols": {"Main": Color(0.47, 0.44, 0.4), "Main_Light": Color(0.76, 0.72, 0.66)},
		"winter": {"Main": Color(0.56, 0.54, 0.5)}},
	"boar": {"path": "res://models/animals/Pig.fbx", "scale": 0.22, "rig": true,
		"cols": {"Material": Color(0.24, 0.19, 0.15), "Material.003": Color(0.2, 0.16, 0.13)}, "winter": {}},
	"fox": {"path": "res://models/animals/Fox.gltf", "scale": 0.2,
		"cols": {"Main": Color(0.8, 0.4, 0.15), "Main_Light": Color(0.92, 0.88, 0.82), "Black": Color(0.12, 0.09, 0.07)},
		"winter": {}},
}

static var _fur: Shader = null
static var _smoothed := {}

static func has(kind: String) -> bool:
	return ANIMALS.has(kind)

static func _paint(c: Color) -> ShaderMaterial:
	if _fur == null:
		_fur = load("res://shaders/paint/fur.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _fur
	m.set_shader_parameter("use_vc", false)
	m.set_shader_parameter("tint", Vector3(c.r, c.g, c.b))
	return m

## Сглаживание: усредняем нормали вершин в одной точке (модели гранёные).
static func smooth(mesh: ArrayMesh) -> ArrayMesh:
	if _smoothed.has(mesh):
		return _smoothed[mesh]
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var acc := {}
		for i in vs.size():
			var k := Vector3i(roundi(vs[i].x * 10000.0), roundi(vs[i].y * 10000.0), roundi(vs[i].z * 10000.0))
			acc[k] = acc.get(k, Vector3.ZERO) + ns[i]
		for i in vs.size():
			var k := Vector3i(roundi(vs[i].x * 10000.0), roundi(vs[i].y * 10000.0), roundi(vs[i].z * 10000.0))
			var n: Vector3 = acc[k]
			ns[i] = n.normalized() if n.length() > 0.0001 else ns[i]
		arr[Mesh.ARRAY_NORMAL] = ns
		arr[Mesh.ARRAY_TANGENT] = null
		var fl := mesh.surface_get_format(s) & (Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
		out.add_surface_from_arrays(mesh.surface_get_primitive_type(s), arr, [], {}, fl)
		out.surface_set_material(s, mesh.surface_get_material(s))
		out.surface_set_name(s, mesh.surface_get_name(s))
	_smoothed[mesh] = out
	return out

## Перекраска: каждый исходный материал → живописный с тем же или заданным цветом.
static func repaint(root: Node, cols: Dictionary) -> void:
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		mi.mesh = smooth(mi.mesh)
		for s in mi.mesh.get_surface_count():
			var om := mi.mesh.surface_get_material(s)
			var nm := om.resource_name if om != null else ""
			var c := Color(0.5, 0.5, 0.5)
			if om is BaseMaterial3D:
				c = (om as BaseMaterial3D).albedo_color
			if cols.has(nm):
				c = cols[nm]
			mi.set_surface_override_material(s, _paint(c))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

static func loop_anims(ap: AnimationPlayer, names: Array) -> void:
	for n in ap.get_animation_list():
		for k in names:
			if String(n).ends_with(k):
				ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR

## Находит анимацию по одному из вариантов имени (без учёта префикса «Armature|»).
static func find_anim(ap: AnimationPlayer, opts: Array) -> String:
	for o in opts:
		for n in ap.get_animation_list():
			if String(n) == o or String(n).ends_with("|" + o) or String(n).ends_with("_" + o):
				return n
	return ""

static func build_animal(root: Node3D, kind: String, scale_k: float, winter: bool) -> Dictionary:
	var cfg: Dictionary = ANIMALS[kind]
	var n: Node3D = load(cfg["path"]).instantiate()
	var s: float = cfg["scale"] * scale_k
	n.scale = Vector3(s, s, s)
	root.add_child(n)
	var cols: Dictionary = (cfg["cols"] as Dictionary).duplicate()
	if winter:
		cols.merge(cfg["winter"], true)
	repaint(n, cols)
	var ap: AnimationPlayer = n.find_children("*", "AnimationPlayer", true, false)[0]
	if cfg.get("rig", false):
		return _rig_legs(n, ap, s, kind)
	loop_anims(ap, ["Walk", "Gallop", "Idle", "Idle_2", "Eating", "Idle_Headlow", "Idle_2_HeadLow"])
	ap.playback_default_blend_time = 0.3
	ap.play(find_anim(ap, ["Idle"]))
	return {"model": n, "ap": ap, "L": 4.4 * s, "H": 2.0 * s, "cur": ""}


## Модель без анимации шага (кабан): ноги ведём сами — стопы по циклу шага, колени через IK.
const LEGS := [["FrontUpLeg.L", "FrontLowLeg.L_end", "FrontFoot.L"], ["FrontUpLeg.R", "FrontLowLeg.R_end", "FrontFoot.R"], ["BackUpLeg.L", "BackLowLeg.L_end", "BackFoot.L"], ["BackUpLeg.R", "BackLowLeg.R_end", "BackFoot.R"]]

static func _rig_legs(n: Node3D, ap: AnimationPlayer, s: float, kind: String) -> Dictionary:
	ap.stop()
	ap.active = false
	var sk: Skeleton3D = n.find_children("*", "Skeleton3D", true, false)[0]
	var legs := []
	for l in LEGS:
		var fi := sk.find_bone(l[2])
		var ik := SkeletonIK3D.new()
		ik.root_bone = l[0]
		ik.tip_bone = l[1]
		ik.override_tip_basis = false
		ik.interpolation = 1.0
		sk.add_child(ik)
		var tg := Node3D.new()
		sk.add_child(tg)
		ik.target_node = ik.get_path_to(tg)
		legs.append({"ik": ik, "tg": tg, "foot": fi, "rest": sk.get_bone_rest(fi).origin})
	# головы и хвост остаются в позе покоя; модель: длина ~7.5 ед., голова на высоте ~3 ед.
	return {"model": n, "rig": sk, "legs": legs, "L": 7.0 * s, "H": 3.0 * s, "cur": "", "ph": 0.0}

## Цикл шага для модели с ногами на IK. ph — фаза, k — размах (0 — стоит).
static func step_legs(parts: Dictionary, ph: float, k: float, gallop: bool) -> void:
	var sk: Skeleton3D = parts["rig"]
	var offs := [0.0, 0.5, 0.5, 0.0] if not gallop else [0.0, 0.1, 0.5, 0.6]
	var i := 0
	for lg in parts["legs"]:
		var p: float = ph + float(offs[i]) * TAU
		var rest: Vector3 = lg["rest"]
		# скелет Z-вверх, вперёд — по -Y (как в Blender): шаг вдоль -Y, подъём вдоль +Z
		var fwd := -sin(p) * 0.45 * k
		var lift := maxf(0.0, cos(p)) * 0.35 * k
		var pos := rest + Vector3(0, -fwd, lift) * 0.01
		sk.set_bone_pose_position(lg["foot"], pos)
		var tg: Node3D = lg["tg"]
		tg.transform = Transform3D(Basis(), pos)
		var ik: SkeletonIK3D = lg["ik"]
		ik.start(true)
		i += 1
