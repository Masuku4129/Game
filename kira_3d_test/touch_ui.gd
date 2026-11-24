class_name TouchUI
extends Control
## Экранное управление.
## Слева плавающий джойстик (слабый наклон = ходьба, сильный = бег).
## Справа кнопки: УДАР, ПРЫЖОК, ОТСКОК, РЫВОК, БЛОК (держать).
## Свайп по свободной части экрана справа вращает камеру.

signal attack_pressed
signal jump_pressed
signal dodge_pressed
signal dash_pressed
signal block_changed(held: bool)
signal camera_drag(delta: Vector2)

const JOY_RADIUS := 120.0
const RUN_RING := 0.65

var move_vector := Vector2.ZERO
var _joy_index := -1
var _joy_center := Vector2.ZERO
var _hint_center := Vector2.ZERO
var _cam_index := -1
var _cam_last := Vector2.ZERO
# кнопка: id -> {pos, r, label, color, index}
var _buttons := {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	var s := get_viewport_rect().size
	var a := Vector2(s.x - 165.0, s.y - 165.0)   # центр кнопки удара
	_buttons = {
		"attack": {"pos": a, "r": 80.0, "label": "УДАР", "color": Color(0.75, 0.3, 1.0), "index": -1},
		"jump": {"pos": a + Vector2(-205.0, 40.0), "r": 58.0, "label": "ПРЫЖОК", "color": Color(0.35, 0.55, 1.0), "index": -1},
		"dodge": {"pos": a + Vector2(-175.0, -150.0), "r": 54.0, "label": "ОТСКОК", "color": Color(0.3, 0.75, 0.7), "index": -1},
		"dash": {"pos": a + Vector2(-20.0, -215.0), "r": 54.0, "label": "РЫВОК", "color": Color(0.55, 0.2, 0.9), "index": -1},
		"block": {"pos": a + Vector2(-380.0, 55.0), "r": 54.0, "label": "БЛОК", "color": Color(0.85, 0.75, 0.35), "index": -1},
	}
	_hint_center = Vector2(210.0, s.y - 190.0)
	queue_redraw()


func is_joystick_active() -> bool:
	return _joy_index != -1


func _button_at(p: Vector2) -> String:
	for id in _buttons:
		var b: Dictionary = _buttons[id]
		if p.distance_to(b["pos"]) <= float(b["r"]) * 1.25:
			return id
	return ""


func _press(id: String) -> void:
	match id:
		"attack":
			attack_pressed.emit()
		"jump":
			jump_pressed.emit()
		"dodge":
			dodge_pressed.emit()
		"dash":
			dash_pressed.emit()
		"block":
			block_changed.emit(true)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			var p := t.position
			var id := _button_at(p)
			if id != "" and int(_buttons[id]["index"]) == -1:
				_buttons[id]["index"] = t.index
				_press(id)
			elif _joy_index == -1 and p.x < get_viewport_rect().size.x * 0.42:
				_joy_index = t.index
				_joy_center = p
				move_vector = Vector2.ZERO
			elif _cam_index == -1:
				_cam_index = t.index
				_cam_last = p
			queue_redraw()
		else:
			if t.index == _joy_index:
				_joy_index = -1
				move_vector = Vector2.ZERO
			elif t.index == _cam_index:
				_cam_index = -1
			for id in _buttons:
				if int(_buttons[id]["index"]) == t.index:
					_buttons[id]["index"] = -1
					if id == "block":
						block_changed.emit(false)
			queue_redraw()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _joy_index:
			move_vector = ((d.position - _joy_center) / JOY_RADIUS).limit_length(1.0)
			queue_redraw()
		elif d.index == _cam_index:
			camera_drag.emit(d.position - _cam_last)
			_cam_last = d.position


func _draw() -> void:
	var active := _joy_index != -1
	var c := _joy_center if active else _hint_center
	draw_circle(c, JOY_RADIUS, Color(1, 1, 1, 0.08))
	draw_arc(c, JOY_RADIUS, 0.0, TAU, 64, Color(1, 1, 1, 0.35), 3.0)
	draw_arc(c, JOY_RADIUS * RUN_RING, 0.0, TAU, 64, Color(0.75, 0.55, 1.0, 0.45), 2.0)
	draw_circle(c + move_vector * JOY_RADIUS, 44.0, Color(1, 1, 1, 0.38 if active else 0.16))
	var font := ThemeDB.fallback_font
	for id in _buttons:
		var b: Dictionary = _buttons[id]
		var pos: Vector2 = b["pos"]
		var r: float = b["r"]
		var col: Color = b["color"]
		var pressed := int(b["index"]) != -1
		draw_circle(pos, r, Color(col.r, col.g, col.b, 0.65 if pressed else 0.32))
		draw_arc(pos, r, 0.0, TAU, 64, Color(1, 1, 1, 0.6), 3.0)
		var fs := 30 if id == "attack" else 20
		draw_string(font, pos + Vector2(-r, fs * 0.35), String(b["label"]), HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, Color(1, 1, 1, 0.95))
