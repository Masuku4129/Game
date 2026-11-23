extends Control
## Кнопки действий в правой половине экрана: удар (большая), рывок, умение.
## Нажатие вызывает методы игрока. Клавиатура: J удар, K рывок, L умение.

var player
var _attack_c := Vector2.ZERO
var _dash_c := Vector2.ZERO
var _skill_c := Vector2.ZERO
const R_ATTACK := 95.0
const R_DASH := 66.0
const R_SKILL := 58.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout()
	get_viewport().size_changed.connect(_layout)


func _layout() -> void:
	var s := get_viewport_rect().size
	_attack_c = Vector2(s.x - 190.0, s.y - 170.0)
	_dash_c = Vector2(s.x - 370.0, s.y - 110.0)
	_skill_c = Vector2(s.x - 370.0, s.y - 230.0)
	queue_redraw()


func _input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch and touch.pressed and player:
		if touch.position.distance_to(_attack_c) <= R_ATTACK * 1.15:
			player.attack_requested = true
		elif touch.position.distance_to(_dash_c) <= R_DASH * 1.2:
			player.dash_requested = true
		elif player.skill_unlocked and touch.position.distance_to(_skill_c) <= R_SKILL * 1.2:
			player.skill_requested = true
	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		if key.keycode == KEY_L and player and player.skill_unlocked:
			player.skill_requested = true


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_circle(_attack_c, R_ATTACK, Color(0.35, 0.3, 0.9, 0.22))
	draw_arc(_attack_c, R_ATTACK, 0.0, TAU, 48, Color(0.7, 0.65, 1.0, 0.7), 3.0)
	draw_string(font, _attack_c + Vector2(-34, 8), "УДАР", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 1, 1, 0.85))
	draw_circle(_dash_c, R_DASH, Color(0.35, 0.3, 0.9, 0.18))
	draw_arc(_dash_c, R_DASH, 0.0, TAU, 40, Color(0.7, 0.65, 1.0, 0.6), 3.0)
	draw_string(font, _dash_c + Vector2(-34, 8), "РЫВОК", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.8))
	# кнопка умения — светится когда открыта
	if player and player.skill_unlocked:
		var cd_frac := clampf(player.skill_cd / 4.0, 0.0, 1.0)
		var ready := cd_frac <= 0.0
		var col_bg := Color(0.9, 0.7, 0.2, 0.28) if ready else Color(0.4, 0.4, 0.4, 0.18)
		var col_arc := Color(1.0, 0.85, 0.3, 0.9) if ready else Color(0.6, 0.6, 0.6, 0.5)
		draw_circle(_skill_c, R_SKILL, col_bg)
		draw_arc(_skill_c, R_SKILL, 0.0, TAU, 40, col_arc, 3.0)
		# прогресс перезарядки
		if cd_frac > 0.0:
			draw_arc(_skill_c, R_SKILL - 5.0, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - cd_frac), 36, Color(1.0, 0.85, 0.3, 0.7), 4.0)
		var txt_col := Color(1, 0.9, 0.3, 0.95) if ready else Color(0.8, 0.8, 0.8, 0.6)
		draw_string(font, _skill_c + Vector2(-42, 6), "УМЕНИЕ", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, txt_col)
	else:
		# серая заблокированная кнопка
		draw_circle(_skill_c, R_SKILL, Color(0.3, 0.3, 0.3, 0.12))
		draw_arc(_skill_c, R_SKILL, 0.0, TAU, 40, Color(0.5, 0.5, 0.5, 0.3), 2.0)
		draw_string(font, _skill_c + Vector2(-14, 6), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.6, 0.6, 0.6, 0.4))
