extends Node2D
## Фиолетовый шар стрелка: летит по прямой, гаснет о препятствия, ранит Миту.

var vel := Vector2.ZERO
var dmg := 8.0
var life := 4.0
var _t := 0.0


func _ready() -> void:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = m
	z_index = 5


func _physics_process(delta: float) -> void:
	_t += delta
	life -= delta
	var nxt := position + vel * delta
	var q := PhysicsRayQueryParameters2D.create(global_position, global_position + vel * delta + vel.normalized() * 14.0, 1)
	var r := get_world_2d().direct_space_state.intersect_ray(q)
	position = nxt
	if r:
		var c = r.collider
		if c.is_in_group("player"):
			c.hurt(dmg, global_position - vel)
		queue_free()
		return
	var ps := get_tree().get_nodes_in_group("player")
	if ps.size() > 0:
		var pp: Vector2 = ps[0].global_position + Vector2(0, -50.0)
		if pp.distance_to(global_position) < 34.0:
			ps[0].hurt(dmg, global_position - vel)
			queue_free()
			return
	if life <= 0.0:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var p := 1.0 + sin(_t * 18.0) * 0.12
	draw_circle(Vector2.ZERO, 30.0 * p, Color(0.55, 0.2, 0.9, 0.18))
	draw_circle(Vector2.ZERO, 20.0 * p, Color(0.7, 0.35, 1.0, 0.4))
	draw_circle(Vector2.ZERO, 11.0, Color(0.95, 0.8, 1.0, 0.95))
	for i in 4:
		draw_circle(-vel.normalized() * (12.0 + i * 9.0), 8.0 - i * 1.6, Color(0.6, 0.25, 1.0, 0.35 - i * 0.07))
