extends Control
## Виртуальный джойстик слева внизу. value — вектор от -1 до 1.

var value := Vector2.ZERO
var touch_id := -1
const RADIUS := 120.0

func _center() -> Vector2:
	return global_position + size * 0.5

func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed and touch_id == -1 and get_global_rect().has_point(e.position):
			touch_id = e.index
			_update_value(e.position)
			get_viewport().set_input_as_handled()
		elif not e.pressed and e.index == touch_id:
			touch_id = -1
			value = Vector2.ZERO
			queue_redraw()
			get_viewport().set_input_as_handled()
	elif e is InputEventScreenDrag and e.index == touch_id:
		_update_value(e.position)
		get_viewport().set_input_as_handled()

func _update_value(pos: Vector2) -> void:
	var v := (pos - _center()) / RADIUS
	value = v.limit_length(1.0)
	queue_redraw()

func _draw() -> void:
	var c := size * 0.5
	draw_circle(c, RADIUS, Color(1, 1, 1, 0.07))
	draw_arc(c, RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.3), 3.0)
	draw_circle(c + value * RADIUS, 48.0, Color(1, 1, 1, 0.3))
	draw_arc(c + value * RADIUS, 48.0, 0, TAU, 32, Color(1, 1, 1, 0.5), 2.0)
