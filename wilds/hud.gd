extends Control
## Полоса здоровья Миты, счётчик убийств, сообщения (умение открыто и т.д.).

var player
var main
var _msg := ""
var _msg_t := 0.0
var boss : Node = null          # ссылка на текущего босса (hd)
var _boss_intro := 0.0          # таймер появления бар-босса


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_to_group("hud")


func show_message(text: String) -> void:
	_msg = text
	_msg_t = 3.5


func show_boss(b: Node) -> void:
	boss       = b
	_boss_intro = 2.0
	show_message("⚔ Альфа-Гончая")


func _process(d: float) -> void:
	if _msg_t > 0.0:
		_msg_t -= d
	if _boss_intro > 0.0:
		_boss_intro -= d
	# убрать ссылку если босс мёртв
	if boss != null and (not is_instance_valid(boss) or boss.dead):
		boss = null
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
	# ---- Бар босса ----
	if boss != null and is_instance_valid(boss) and not boss.dead:
		var s2 := get_viewport_rect().size
		var bw  := s2.x * 0.55
		var bh  := 18.0
		var bx  := (s2.x - bw) * 0.5
		var by  := s2.y - 56.0
		var bf  := clampf(boss.hp / boss.max_hp, 0.0, 1.0)
		var anim := clampf(2.0 - _boss_intro, 0.0, 1.0)  # плавное появление
		var alpha := anim
		# фон
		draw_rect(Rect2(bx - 4, by - 24, bw + 8, bh + 32).grow(2), Color(0.0, 0.0, 0.0, 0.5 * alpha))
		draw_rect(Rect2(bx - 4, by - 24, bw + 8, bh + 32), Color(0.25, 0.1, 0.35, 0.6 * alpha))
		# заголовок
		var font2 := ThemeDB.fallback_font
		var rage_txt := "  ★ АЛЬФА-ГОНЧАЯ ★" if boss._boss_phase == 0 else "  ⚡ АЛЬФА-ГОНЧАЯ — ЯРОСТЬ ⚡"
		var rage_col := Color(1.0, 0.75, 0.2, alpha) if boss._boss_phase == 0 else Color(1.0, 0.3, 0.1, alpha)
		draw_string(font2, Vector2(bx, by - 8), rage_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, rage_col)
		# полоса
		draw_rect(Rect2(bx, by, bw, bh), Color(0.15, 0.08, 0.22, 0.8 * alpha))
		var bar_col := Color(0.75, 0.3, 0.9) if boss._boss_phase == 0 else Color(0.95, 0.25, 0.1)
		draw_rect(Rect2(bx, by, bw * bf, bh), bar_col.lerp(Color.WHITE, 0.15) * Color(1,1,1,alpha))
		# засечки каждые 25%
		for i in 3:
			var lx := bx + bw * (i + 1) * 0.25
			draw_line(Vector2(lx, by), Vector2(lx, by + bh), Color(0,0,0,0.4 * alpha), 2.0)
		# цифры
		draw_string(font2, Vector2(bx + bw * 0.5 - 24, by + bh - 3),
			"%d / %d" % [int(boss.hp), int(boss.max_hp)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1,1,1,0.75 * alpha))
