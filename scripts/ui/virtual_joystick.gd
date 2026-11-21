extends Control

signal value_changed(value: Vector2)

@export var radius: float = 76.0
@export var knob_radius: float = 31.0
@export_range(0.0, 0.4) var deadzone: float = 0.12

var value := Vector2.ZERO
var _touch_index := -1
var _knob_offset := Vector2.ZERO

func _ready() -> void:
	custom_minimum_size = Vector2(190.0, 190.0)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	var center := size * 0.5
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1 and event.position.distance_to(center) <= radius * 1.55:
			_touch_index = event.index
			_update_from_position(event.position)
			accept_event()
		elif not event.pressed and event.index == _touch_index:
			_touch_index = -1
			_set_value(Vector2.ZERO)
			accept_event()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		_update_from_position(event.position)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and event.position.distance_to(center) <= radius * 1.55:
			_touch_index = -2
			_update_from_position(event.position)
			accept_event()
		elif not event.pressed and _touch_index == -2:
			_touch_index = -1
			_set_value(Vector2.ZERO)
			accept_event()
	elif event is InputEventMouseMotion and _touch_index == -2:
		_update_from_position(event.position)
		accept_event()

func _update_from_position(point: Vector2) -> void:
	var offset := point - size * 0.5
	if offset.length() > radius:
		offset = offset.normalized() * radius
	_knob_offset = offset
	var strength := offset.length() / radius
	var next_value := Vector2.ZERO
	if strength >= deadzone:
		next_value = offset.normalized() * ((strength - deadzone) / (1.0 - deadzone))
	_set_value(next_value)

func _set_value(next_value: Vector2) -> void:
	value = next_value
	if value == Vector2.ZERO:
		_knob_offset = Vector2.ZERO
	value_changed.emit(value)
	queue_redraw()

func get_value() -> Vector2:
	return value

func _draw() -> void:
	var center := size * 0.5
	draw_circle(center, radius + 5.0, Color(0.02, 0.035, 0.03, 0.22))
	draw_circle(center, radius, Color(0.06, 0.09, 0.08, 0.46))
	draw_arc(center, radius, 0.0, TAU, 64, Color(0.76, 0.82, 0.73, 0.58), 2.0, true)
	draw_circle(center + _knob_offset, knob_radius, Color(0.025, 0.045, 0.035, 0.42))
	draw_circle(center + _knob_offset, knob_radius - 3.0, Color(0.78, 0.83, 0.73, 0.88))
	draw_arc(center + _knob_offset, knob_radius - 3.0, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.5), 1.5, true)
