class_name SlashTrail
extends Node3D
## Белый шлейф замаха: рисуется за клинком, пока кончик меча движется быстрее порога.
## Работает с любой анимацией, ничего не нужно размечать по кадрам.

@export var tip_node: Node3D                 # TrailTip из katana.glb
@export var base_node: Node3D                # TrailBase из katana.glb
@export var character_height := 2.0          # высота персонажа в единицах сцены (в модели 2.0)
@export var speed_per_height := 11.0         # порог скорости кончика: единиц/с на 1 высоту персонажа
@export var lifetime := 0.22                 # сколько секунд живёт хвост шлейфа
@export var subdivisions := 6                # сглаживание дуги между кадрами
@export var color := Color(1, 1, 1, 1)

var _mesh := ImmediateMesh.new()
var _mi := MeshInstance3D.new()
var _samples := []
var _sword: Node3D
var _tip_local := Vector3.ZERO
var _base_local := Vector3.ZERO
var _last_tip := Vector3.ZERO
var _has_last := false
var _tip_speed := 0.0


func _ready() -> void:
	_sword = tip_node.get_parent() as Node3D
	_tip_local = tip_node.position
	_base_local = base_node.position
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	_mi.mesh = _mesh
	_mi.material_override = mat
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mi)
	_mi.top_level = true
	_mi.global_transform = Transform3D.IDENTITY


func get_tip_speed() -> float:
	return _tip_speed


func _fade(age: float) -> Color:
	var f := clampf(1.0 - age / lifetime, 0.0, 1.0)
	return Color(color.r, color.g, color.b, color.a * pow(f, 1.4))


func _process(delta: float) -> void:
	var now := float(Time.get_ticks_msec()) / 1000.0
	var xf := _sword.global_transform
	var tip := xf * _tip_local
	var speed := 0.0
	if _has_last and delta > 0.0:
		speed = tip.distance_to(_last_tip) / delta
	_last_tip = tip
	_has_last = true
	_tip_speed = speed
	_samples.append({"xf": xf, "t": now, "moving": speed >= speed_per_height * character_height})
	while _samples.size() > 0 and now - float(_samples[0]["t"]) > lifetime:
		_samples.pop_front()
	_rebuild(now)


func _rebuild(now: float) -> void:
	_mesh.clear_surfaces()
	var verts := []
	var cols := []
	for i in range(1, _samples.size()):
		var a: Dictionary = _samples[i - 1]
		var b: Dictionary = _samples[i]
		if not b["moving"]:
			continue
		var xa: Transform3D = a["xf"]
		var xb: Transform3D = b["xf"]
		for s in range(subdivisions):
			var u0 := float(s) / float(subdivisions)
			var u1 := float(s + 1) / float(subdivisions)
			var x0: Transform3D = xa.interpolate_with(xb, u0)
			var x1: Transform3D = xa.interpolate_with(xb, u1)
			var c0 := _fade(now - lerpf(float(a["t"]), float(b["t"]), u0))
			var c1 := _fade(now - lerpf(float(a["t"]), float(b["t"]), u1))
			var t0: Vector3 = x0 * _tip_local
			var b0: Vector3 = x0 * _base_local
			var t1: Vector3 = x1 * _tip_local
			var b1: Vector3 = x1 * _base_local
			verts.append(t0)
			cols.append(c0)
			verts.append(b0)
			cols.append(c0)
			verts.append(t1)
			cols.append(c1)
			verts.append(b0)
			cols.append(c0)
			verts.append(b1)
			cols.append(c1)
			verts.append(t1)
			cols.append(c1)
	if verts.is_empty():
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(verts.size()):
		_mesh.surface_set_color(cols[i])
		_mesh.surface_add_vertex(verts[i])
	_mesh.surface_end()
