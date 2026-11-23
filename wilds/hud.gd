extends Control
## Полоса здоровья Миты, счётчик убийств, сообщения (умение открыто и т.д.).

var player
var main
var _msg := ""
var _msg_t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_to_group("hud")


func show_message(text: String) -> void:
	_msg = text
	_msg_t = 3.5


func _process(d: float) -> void:
	if _msg_t > 0.0:
		_msg_t -= d
	queue_redraw()


func _draw() -> void:
	if player == null:
		return
	var f: float = clampf(player.hp / player.max_hp, 0.0, 1.0)
	var r := Rect2(16, 46, 260, 14)
	draw_rect(r.grow(3), Color(0.16, 0.14, 0.28, 0.75))
	draw_rect(r, Color(0.35, 0.3, 0.5, 0.55))
	draw_rect(Rect2(r.position, Vector2(r.size.x * f, r.size.y)), Color(0.95, 0.55, 0.7))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(16, 84), "Убито: %d" % main.kills, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.2, 0.18, 0.35))
	# плавающее сообщение по центру экрана
	if _msg_t > 0.0:
		var a := clampf(_msg_t * 2.0, 0.0, 1.0)
		var s := get_viewport_rect().size
		var col := Color(1.0, 0.9, 0.3, a)
		var col2 := Color(0.1, 0.08, 0.2, a * 0.6)
		var tw := 320.0
		var th2 := 44.0
		var rx := Rect2((s.x - tw) * 0.5, s.y * 0.35, tw, th2)
		draw_rect(rx.grow(6), col2)
		draw_rect(rx, Color(0.0, 0.0, 0.0, a * 0.4))
		draw_string(font, Vector2(rx.position.x + 12, rx.position.y + 29), _msg,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 26, col)
