extends Control
## Плавающий джойстик: касание в левой половине экрана ставит его под палец.
## Правая половина свободна под кнопки действий.

const RADIUS := 90.0
const DEADZONE := 0.15

var value := Vector2.ZERO
var _idx := -1
var _base := Vector2.ZERO
var _knob := Vector2.ZERO


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch:
		if touch.pressed:
			if _idx == -1 and touch.position.x < get_viewport_rect().size.x * 0.5:
				_idx = touch.index
				_base = touch.position
				_move_knob(touch.position)
		elif touch.index == _idx:
			_idx = -1
			value = Vector2.ZERO
			queue_redraw()
		return
	var drag := event as InputEventScreenDrag
	if drag and drag.index == _idx:
		_move_knob(drag.position)


func _move_knob(p: Vector2) -> void:
	var d := p - _base
	if d.length() > RADIUS:
		d = d.normalized() * RADIUS
	_knob = _base + d
	value = d / RADIUS
	if value.length() < DEADZONE:
		value = Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	if _idx == -1:
		return
	draw_circle(_base, RADIUS, Color(1, 1, 1, 0.12))
	draw_arc(_base, RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 3.0)
	draw_circle(_knob, 38.0, Color(1, 1, 1, 0.45))
