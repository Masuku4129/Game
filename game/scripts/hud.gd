extends Control
## Шкалы выживания и часы.

var vals := [0.85, 0.8, 1.0]
var names := ["Сытость", "Тепло", "Силы"]
var cols := [Color(0.80, 0.66, 0.30), Color(0.86, 0.46, 0.26), Color(0.52, 0.72, 0.42)]
var clock := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_state(h: float, w: float, s: float, text: String) -> void:
	vals = [h, w, s]
	clock = text
	queue_redraw()

func _draw() -> void:
	var f := ThemeDB.fallback_font
	for i in 3:
		var y := 40.0 + i * 46.0
		draw_string(f, Vector2(30, y + 1), names[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0, 0, 0, 0.6))
		draw_string(f, Vector2(28, y), names[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.92))
		draw_rect(Rect2(28, y + 8, 230, 11), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(28, y + 8, 230.0 * clampf(vals[i], 0.0, 1.0), 11), cols[i])
	draw_string(f, Vector2(size.x - 728, 41), clock, HORIZONTAL_ALIGNMENT_RIGHT, 700, 26, Color(0, 0, 0, 0.6))
	draw_string(f, Vector2(size.x - 730, 40), clock, HORIZONTAL_ALIGNMENT_RIGHT, 700, 26, Color(1, 1, 1, 0.95))
