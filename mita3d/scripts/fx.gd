class_name Trail
extends MeshInstance3D
## Световой след-плоскость: летит вперёд, режет всех, кого пересёк (каждого один раз).

var player
var dir := Vector3.FORWARD
var speed := 30.0
var life := 0.3
var half := Vector3(3.0, 0.6, 0.6)   # половинные размеры в локальных осях
var dmg := 10.0
var color := Color(0.8, 0.85, 1.0)
var vertical := false
var done := {}

func _ready() -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(color.r, color.g, color.b, 0.9)
	material_override = m
	var bm := BoxMesh.new()
	if vertical:
		bm.size = Vector3(half.x * 2.0, half.y * 2.0, 0.06)
	else:
		bm.size = Vector3(half.x * 2.0, 0.05, half.z * 2.0)
	mesh = bm

func _process(dt: float) -> void:
	life -= dt
	global_position += dir * speed * dt
	var a := clampf(life / 0.12, 0.0, 1.0)
	(material_override as StandardMaterial3D).albedo_color.a = 0.9 * a
	for e in player.enemies:
		if not is_instance_valid(e) or e.dead or done.has(e):
			continue
		var l: Vector3 = to_local(e.global_position + Vector3(0, 0.9, 0))
		var ok := false
		if vertical:
			ok = absf(l.x) < half.x and absf(l.y + 0.1) < half.y and absf(l.z) < 1.2
		else:
			ok = absf(l.x) < half.x and absf(l.z) < half.z and absf(l.y) < 1.0
		if ok:
			done[e] = true
			player.hit_enemy(e, dmg, dir, 3.0, 0.5)
	if life <= 0.0:
		queue_free()
