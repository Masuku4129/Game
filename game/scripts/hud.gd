extends Control
## Шкалы выживания, часы и строка состояния (раны, вещи, сообщения).

var vals := [1.0, 0.85, 0.9, 0.8, 1.0]
var names := ["Здоровье", "Сытость", "Жажда", "Тепло", "Силы"]
var cols := [Color(0.78, 0.22, 0.2), Color(0.80, 0.66, 0.30), Color(0.35, 0.6, 0.85), Color(0.86, 0.46, 0.26), Color(0.52, 0.72, 0.42)]
var clock := ""
var info := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_state(v: Array, text: String, inf: String) -> void:
	vals = v
	clock = text
	info = inf
	queue_redraw()

func _draw() -> void:
	var f := ThemeDB.fallback_font
	for i in vals.size():
		var y := 40.0 + i * 42.0
		draw_string(f, Vector2(30, y + 1), names[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color(0, 0, 0, 0.6))
		draw_string(f, Vector2(28, y), names[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color(1, 1, 1, 0.92))
		draw_rect(Rect2(28, y + 7, 230, 10), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(28, y + 7, 230.0 * clampf(vals[i], 0.0, 1.0), 10), cols[i])
	if info != "":
		var y2 := 40.0 + vals.size() * 42.0 + 8.0
		draw_string(f, Vector2(30, y2 + 1), info, HORIZONTAL_ALIGNMENT_LEFT, 900, 22, Color(0, 0, 0, 0.7))
		draw_string(f, Vector2(28, y2), info, HORIZONTAL_ALIGNMENT_LEFT, 900, 22, Color(1, 0.93, 0.8, 0.95))
	draw_string(f, Vector2(size.x - 728, 41), clock, HORIZONTAL_ALIGNMENT_RIGHT, 700, 26, Color(0, 0, 0, 0.6))
	draw_string(f, Vector2(size.x - 730, 40), clock, HORIZONTAL_ALIGNMENT_RIGHT, 700, 26, Color(1, 1, 1, 0.95))
