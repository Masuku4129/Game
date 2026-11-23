extends Control
## Полоса здоровья Миты и счётчик убийств.

var player
var main


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_d: float) -> void:
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
