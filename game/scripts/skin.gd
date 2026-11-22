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
	# сначала точное имя: иначе "Idle" находил "Crouch_Idle" (присед при остановке)
	for o in opts:
		if ap.has_animation(o):
			return o
	for o in opts:
		for n in ap.get_animation_list():
			if String(n).ends_with("|" + o) or String(n).ends_with("_" + o):
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
	loop_anims(ap, ["Walk", "Gallop", "Idle", "Idle_2", "Eating", "Idle_Headlow", "Idle_2_HeadLow"])
	ap.playback_default_blend_time = 0.3
	ap.play(find_anim(ap, ["Idle"]))
	return {"model": n, "ap": ap, "L": 4.4 * s, "H": 2.0 * s, "cur": ""}
