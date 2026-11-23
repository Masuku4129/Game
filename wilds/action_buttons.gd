extends Control
## Кнопки действий в правой половине экрана: удар (большая) и рывок.
## Нажатие вызывает методы игрока. Клавиатура: J удар, K рывок.

var player
var _attack_c := Vector2.ZERO
var _dash_c := Vector2.ZERO
const R_ATTACK := 95.0
const R_DASH := 66.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout()
	get_viewport().size_changed.connect(_layout)


func _layout() -> void:
	var s := get_viewport_rect().size
	_attack_c = Vector2(s.x - 190.0, s.y - 170.0)
	_dash_c = Vector2(s.x - 370.0, s.y - 110.0)
	queue_redraw()


func _input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch and touch.pressed and player:
		if touch.position.distance_to(_attack_c) <= R_ATTACK * 1.15:
			player.attack_requested = true
		elif touch.position.distance_to(_dash_c) <= R_DASH * 1.2:
			player.dash_requested = true


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_circle(_attack_c, R_ATTACK, Color(0.35, 0.3, 0.9, 0.22))
	draw_arc(_attack_c, R_ATTACK, 0.0, TAU, 48, Color(0.7, 0.65, 1.0, 0.7), 3.0)
	draw_string(font, _attack_c + Vector2(-34, 8), "УДАР", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 1, 1, 0.85))
	draw_circle(_dash_c, R_DASH, Color(0.35, 0.3, 0.9, 0.18))
	draw_arc(_dash_c, R_DASH, 0.0, TAU, 40, Color(0.7, 0.65, 1.0, 0.6), 3.0)
	draw_string(font, _dash_c + Vector2(-34, 8), "РЫВОК", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.8))
