extends StaticBody2D
## Декор уровня: книжные полки, статуи, жаровни, столбы моста, арка.
## Начало координат = точка основания, рисуем вверх (сортировка по Y).

const SHELF := 0
const STATUE := 1
const TORCH := 2
const POST := 3
const ARCH := 4

const INK := Color(0.025, 0.025, 0.05)
const RIM := Color(0.40, 0.42, 1.0, 0.55)

static var _gtex: Texture2D

var kind := SHELF
var variant := 1.0
var lift := 0.0        # высота платформы, на которой стоит
var cells_w := 2.0     # ширина в клетках (полка, арка)
var _glow: Sprite2D
var _ph := 0.0


static func glow_tex() -> Texture2D:
	if _gtex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.35, Color(1, 1, 1, 0.45))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 128
		t.height = 128
		_gtex = t
	return _gtex


func _ready() -> void:
	_ph = randf() * TAU
	if kind == SHELF:
		var cs := CollisionShape2D.new()
		var sh := RectangleShape2D.new()
		sh.size = Vector2(cells_w * 96.0 * 0.92, 26.0)
		cs.shape = sh
		cs.position = Vector2(0, -10)
		add_child(cs)
	elif kind == STATUE:
		var cs2 := CollisionShape2D.new()
		var sh2 := CircleShape2D.new()
		sh2.radius = 24.0
		cs2.shape = sh2
		add_child(cs2)
	elif kind == TORCH:
		_glow = Sprite2D.new()
		_glow.texture = glow_tex()
		_glow.position = Vector2(0, -78.0 - lift)
		_glow.scale = Vector2(2.8, 2.4)
		_glow.modulate = Color(0.55, 0.45, 1.0, 0.5)
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_glow.material = m
		add_child(_glow)
	queue_redraw()


func _process(_delta: float) -> void:
	if kind == TORCH:
		queue_redraw()
	if _glow:
		var t := Time.get_ticks_msec() * 0.001
		_glow.modulate.a = 0.42 + 0.08 * sin(t * 9.0 + _ph) + 0.04 * sin(t * 23.0 + _ph * 2.0)


func _draw() -> void:
	draw_set_transform(Vector2(0, -lift), 0.0, Vector2.ONE)
	match kind:
		SHELF:
			_draw_shelf()
		STATUE:
			_draw_statue()
		TORCH:
			_draw_torch()
		POST:
			_draw_post()
		_:
			_draw_arch()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _shadow(rx: float) -> void:
	draw_set_transform(Vector2(0, -lift), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, rx, Color(0, 0, 0, 0.38))
	draw_set_transform(Vector2(0, -lift), 0.0, Vector2.ONE)


func _draw_shelf() -> void:
	var w := cells_w * 96.0
	_shadow(w * 0.5)
	var hw := w * 0.5
	var h := 150.0
	draw_rect(Rect2(-hw, -h, w, h), Color(0.07, 0.055, 0.11))
	draw_rect(Rect2(-hw, -h, w, h), INK, false, 2.0)
	draw_line(Vector2(-hw, -h), Vector2(hw, -h), RIM, 2.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(position.x * 7.0 + position.y * 13.0)
	var cols := [Color(0.16, 0.12, 0.30), Color(0.10, 0.14, 0.30), Color(0.22, 0.12, 0.24),
		Color(0.12, 0.10, 0.20), Color(0.26, 0.20, 0.38)]
	for s in 4:
		var by := -h + 8.0 + float(s) * 35.0
		var bx := -hw + 6.0
		while bx < hw - 8.0:
			var bw := rng.randf_range(5.0, 11.0)
			var bh := rng.randf_range(18.0, 28.0)
			if rng.randf() > 0.12:
				draw_rect(Rect2(bx, by + 28.0 - bh, bw, bh), cols[rng.randi() % cols.size()])
			bx += bw + 1.5
		draw_line(Vector2(-hw, by + 29.0), Vector2(hw, by + 29.0), INK, 3.0)
		draw_line(Vector2(-hw, by + 28.0), Vector2(hw, by + 28.0), Color(0.4, 0.42, 1.0, 0.18), 1.0)


func _draw_statue() -> void:
	_shadow(36.0)
	draw_rect(Rect2(-24, -34, 48, 34), Color(0.09, 0.09, 0.19))
	draw_rect(Rect2(-24, -34, 48, 34), INK, false, 2.0)
	draw_line(Vector2(-24, -34), Vector2(24, -34), RIM, 2.0)
	var body := PackedVector2Array([
		Vector2(-16, -34), Vector2(-12, -86), Vector2(-9, -118), Vector2(9, -118),
		Vector2(12, -86), Vector2(16, -34)])
	draw_colored_polygon(body, Color(0.11, 0.11, 0.23))
	draw_polyline(PackedVector2Array([body[0], body[1], body[2]]), RIM, 2.0, true)
	draw_polyline(body, INK, 2.0, true)
	if variant < 1.15:
		draw_circle(Vector2(0, -132), 13.0, Color(0.12, 0.12, 0.25))
		draw_arc(Vector2(0, -132), 13.0, 0.0, TAU, 20, INK, 2.0)
		draw_arc(Vector2(0, -132), 13.0, PI * 0.9, PI * 1.5, 8, RIM, 2.0)
	else:
		draw_colored_polygon(PackedVector2Array([Vector2(-9, -118), Vector2(-4, -126), Vector2(2, -120), Vector2(9, -118)]), Color(0.11, 0.11, 0.23))
	# рука с мечом
	draw_line(Vector2(12, -96), Vector2(30, -64), Color(0.11, 0.11, 0.23), 7.0)
	draw_line(Vector2(30, -64), Vector2(30, -12), Color(0.16, 0.17, 0.35), 4.0)


func _draw_torch() -> void:
	_shadow(20.0)
	draw_line(Vector2(0, 0), Vector2(0, -66), INK, 7.0)
	draw_line(Vector2(0, 0), Vector2(0, -66), Color(0.10, 0.09, 0.18), 4.0)
	draw_line(Vector2(-1.5, -4), Vector2(-1.5, -62), RIM, 1.5)
	var bowl := PackedVector2Array([Vector2(-15, -72), Vector2(15, -72), Vector2(9, -60), Vector2(-9, -60)])
	draw_colored_polygon(bowl, Color(0.09, 0.08, 0.16))
	draw_polyline(PackedVector2Array([bowl[0], bowl[3], bowl[2], bowl[1]]), INK, 2.0)
	draw_line(bowl[0], bowl[1], RIM, 2.0)
	var t := Time.get_ticks_msec() * 0.001
	var f := 1.0 + 0.12 * sin(t * 11.0 + _ph)
	var flame := PackedVector2Array([Vector2(-10, -72), Vector2(-6, -88 * f), Vector2(0, -106 * f),
		Vector2(6, -90 * f), Vector2(10, -72)])
	draw_colored_polygon(flame, Color(0.45, 0.35, 1.0, 0.9))
	var core := PackedVector2Array([Vector2(-5, -72), Vector2(0, -94 * f), Vector2(5, -72)])
	draw_colored_polygon(core, Color(0.9, 0.88, 1.0, 0.95))


func _draw_post() -> void:
	draw_line(Vector2(0, 0), Vector2(0, -48), INK, 8.0)
	draw_line(Vector2(0, 0), Vector2(0, -48), Color(0.12, 0.09, 0.17), 5.0)
	draw_line(Vector2(-1.5, -2), Vector2(-1.5, -46), RIM, 1.5)
	draw_circle(Vector2(0, -50), 5.0, Color(0.15, 0.12, 0.22))
	draw_arc(Vector2(0, -50), 5.0, 0.0, TAU, 10, INK, 1.5)


func _draw_arch() -> void:
	var w := cells_w * 96.0
	var hw := w * 0.5 + 24.0
	var col := Color(0.11, 0.11, 0.23)
	for sgn in [-1.0, 1.0]:
		var x0: float = sgn * hw
		draw_rect(Rect2(x0 - 22, -190, 44, 190), col)
		draw_rect(Rect2(x0 - 22, -190, 44, 190), INK, false, 2.0)
		draw_line(Vector2(x0 - 22, -190), Vector2(x0 - 22, 0), RIM, 2.0)
		draw_rect(Rect2(x0 - 28, -26, 56, 26), Color(0.09, 0.09, 0.19))
		draw_rect(Rect2(x0 - 28, -26, 56, 26), INK, false, 2.0)
	# перемычка с обвалом посередине
	var lt := PackedVector2Array([Vector2(-hw - 28, -190), Vector2(-hw - 28, -222), Vector2(-26, -226),
		Vector2(-14, -204), Vector2(-34, -196), Vector2(-20, -190)])
	draw_colored_polygon(lt, col)
	draw_polyline(lt, INK, 2.0, true)
	draw_line(lt[0], lt[1], RIM, 2.0)
	draw_line(lt[1], lt[2], RIM, 2.0)
	var rt := PackedVector2Array([Vector2(hw + 28, -190), Vector2(hw + 28, -222), Vector2(38, -224),
		Vector2(46, -206), Vector2(28, -196), Vector2(40, -190)])
	draw_colored_polygon(rt, col)
	draw_polyline(rt, INK, 2.0, true)
	draw_line(rt[0], rt[1], RIM, 2.0)
	draw_line(rt[1], rt[2], RIM, 2.0)
