extends Control
## Шкалы выживания, часы и строка состояния (раны, вещи, сообщения).

var vals := [1.0, 0.85, 0.9, 0.8, 1.0]
var names := ["Здоровье", "Сытость", "Жажда", "Тепло", "Силы"]
var cols := [Color(0.78, 0.22, 0.2), Color(0.80, 0.66, 0.30), Color(0.35, 0.6, 0.85), Color(0.86, 0.46, 0.26), Color(0.52, 0.72, 0.42)]
var clock := ""
var info := ""
var bag_btn: BagButton

## Кнопка короба: нарисованный берестяной короб с лямками и подписью.
class BagButton extends Button:
	func _ready() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 4.0
		var dn := is_pressed() and is_hovered()
		draw_circle(c + Vector2(3, 4), r, Color(0, 0, 0, 0.3))
		draw_circle(c, r, Color(0.3, 0.21, 0.13, 0.82) if not dn else Color(0.45, 0.31, 0.18, 0.9))
		draw_arc(c, r - 3.0, 0.0, TAU, 48, Color(0.86, 0.76, 0.56, 0.9), 4.0, true)
		# короб: корпус, крышка со скаткой, лямки
		var w := r * 0.82
		var h := r * 0.86
		var o := c + Vector2(0, -r * 0.08)
		var body := Rect2(o.x - w * 0.5, o.y - h * 0.35, w, h * 0.8)
		draw_rect(body, Color(0.82, 0.68, 0.45))
		for i in 4:
			var y := body.position.y + body.size.y * (0.2 + i * 0.2)
			draw_line(Vector2(body.position.x + 3, y), Vector2(body.end.x - 3, y), Color(0.6, 0.46, 0.28), 2.0)
		draw_rect(body, Color(0.35, 0.23, 0.13), false, 3.0)
		draw_rect(Rect2(o.x - w * 0.56, o.y - h * 0.5, w * 1.12, h * 0.17), Color(0.62, 0.47, 0.29))
		draw_rect(Rect2(o.x - w * 0.56, o.y - h * 0.5, w * 1.12, h * 0.17), Color(0.35, 0.23, 0.13), false, 2.5)
		var rr := Rect2(o.x - w * 0.6, o.y - h * 0.72, w * 1.2, h * 0.22)
		draw_rect(rr, Color(0.55, 0.2, 0.15))
		draw_circle(Vector2(rr.position.x, rr.get_center().y), rr.size.y * 0.5, Color(0.45, 0.16, 0.12))
		draw_circle(Vector2(rr.end.x, rr.get_center().y), rr.size.y * 0.5, Color(0.62, 0.25, 0.18))
		for sx in [-0.25, 0.25]:
			draw_line(Vector2(o.x + w * sx, body.position.y - 2), Vector2(o.x + w * sx, body.end.y + 2), Color(0.25, 0.15, 0.08), 4.0)
		var f := ThemeDB.fallback_font
		draw_string(f, Vector2(c.x - 60, c.y + r * 0.78), "Рюкзак", HORIZONTAL_ALIGNMENT_CENTER, 120, 19, Color(1, 0.95, 0.85))

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	bag_btn = BagButton.new()
	bag_btn.anchor_left = 1.0
	bag_btn.anchor_right = 1.0
	bag_btn.anchor_top = 1.0
	bag_btn.anchor_bottom = 1.0
	bag_btn.offset_left = -236.0
	bag_btn.offset_right = -86.0
	bag_btn.offset_top = -400.0
	bag_btn.offset_bottom = -250.0
	add_child(bag_btn)

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
