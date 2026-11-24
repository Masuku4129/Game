class_name TouchUI
extends Control
## Экранное управление: плавающий джойстик слева, кнопка удара справа.
## Лёгкий наклон джойстика = ходьба, сильный наклон (кольцо) = бег.

signal attack_pressed
signal jump_pressed

const JOY_RADIUS := 120.0
const RUN_RING := 0.65
const ATTACK_RADIUS := 78.0
const JUMP_RADIUS := 62.0

var move_vector := Vector2.ZERO
var _joy_index := -1
var _joy_center := Vector2.ZERO
var _attack_index := -1
var _attack_center := Vector2.ZERO
var _jump_index := -1
var _jump_center := Vector2.ZERO
var _hint_center := Vector2.ZERO


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	var s := get_viewport_rect().size
	_attack_center = Vector2(s.x - 170.0, s.y - 170.0)
	_jump_center = Vector2(s.x - 360.0, s.y - 120.0)
	_hint_center = Vector2(210.0, s.y - 190.0)
	queue_redraw()


func is_joystick_active() -> bool:
	return _joy_index != -1


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			var p := t.position
			if _jump_index == -1 and p.distance_to(_jump_center) <= JUMP_RADIUS * 1.4:
				_jump_index = t.index
				jump_pressed.emit()
				queue_redraw()
			elif _attack_index == -1 and p.distance_to(_attack_center) <= ATTACK_RADIUS * 1.5:
				_attack_index = t.index
				attack_pressed.emit()
				queue_redraw()
			elif _joy_index == -1 and p.x < get_viewport_rect().size.x * 0.55:
				_joy_index = t.index
				_joy_center = p
				move_vector = Vector2.ZERO
				queue_redraw()
		else:
			if t.index == _joy_index:
				_joy_index = -1
				move_vector = Vector2.ZERO
				queue_redraw()
			elif t.index == _attack_index:
				_attack_index = -1
				queue_redraw()
			elif t.index == _jump_index:
				_jump_index = -1
				queue_redraw()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _joy_index:
			move_vector = ((d.position - _joy_center) / JOY_RADIUS).limit_length(1.0)
			queue_redraw()


func _draw() -> void:
	var active := _joy_index != -1
	var c := _joy_center if active else _hint_center
	draw_circle(c, JOY_RADIUS, Color(1, 1, 1, 0.08))
	draw_arc(c, JOY_RADIUS, 0.0, TAU, 64, Color(1, 1, 1, 0.35), 3.0)
	draw_arc(c, JOY_RADIUS * RUN_RING, 0.0, TAU, 64, Color(0.75, 0.55, 1.0, 0.45), 2.0)
	draw_circle(c + move_vector * JOY_RADIUS, 44.0, Color(1, 1, 1, 0.38 if active else 0.16))
	var pressed := _attack_index != -1
	draw_circle(_attack_center, ATTACK_RADIUS, Color(0.75, 0.3, 1.0, 0.65 if pressed else 0.32))
	draw_arc(_attack_center, ATTACK_RADIUS, 0.0, TAU, 64, Color(1, 1, 1, 0.6), 3.0)
	var jp := _jump_index != -1
	draw_circle(_jump_center, JUMP_RADIUS, Color(0.35, 0.55, 1.0, 0.6 if jp else 0.3))
	draw_arc(_jump_center, JUMP_RADIUS, 0.0, TAU, 64, Color(1, 1, 1, 0.6), 3.0)
	var font := ThemeDB.fallback_font
	draw_string(font, _jump_center + Vector2(-JUMP_RADIUS, 9.0), "ПРЫЖОК", HORIZONTAL_ALIGNMENT_CENTER, JUMP_RADIUS * 2.0, 22, Color(1, 1, 1, 0.95))
	draw_string(font, _attack_center + Vector2(-ATTACK_RADIUS, 11.0), "УДАР", HORIZONTAL_ALIGNMENT_CENTER, ATTACK_RADIUS * 2.0, 32, Color(1, 1, 1, 0.95))
