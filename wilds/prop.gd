extends StaticBody2D
## Объект мира: мёртвое дерево, камень, колючий куст, обломок колонны.
## Начало координат = точка основания, рисуем вверх: так работает сортировка по Y.

const TREE := 0
const ROCK := 1
const BUSH := 2
const PILLAR := 3

const INK := Color(0.025, 0.025, 0.05)
const BARK := Color(0.06, 0.055, 0.10)
const RIM := Color(0.36, 0.38, 0.95, 0.55)
const BUD := Color(0.55, 0.45, 1.0, 0.9)

var kind := TREE
var variant := 1.0
var flip := false


func _ready() -> void:
	var r := 0.0
	match kind:
		TREE:
			r = 13.0
		ROCK:
			r = 24.0
		PILLAR:
			r = 22.0
	if r > 0.0:
		var cs := CollisionShape2D.new()
		var sh := CircleShape2D.new()
		sh.radius = r * variant
		cs.shape = sh
		add_child(cs)
	queue_redraw()


func _draw() -> void:
	var sx := -1.0 if flip else 1.0
	_shadow()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(sx * variant, variant))
	match kind:
		TREE:
			_draw_tree()
		ROCK:
			_draw_rock()
		BUSH:
			_draw_bush()
		_:
			_draw_pillar()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _shadow() -> void:
	var rx := 44.0
	match kind:
		ROCK:
			rx = 38.0
		BUSH:
			rx = 28.0
		PILLAR:
			rx = 34.0
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(variant, 0.4 * variant))
	draw_circle(Vector2.ZERO, rx, Color(0, 0, 0, 0.38))


func _line(pts: PackedVector2Array, w: float) -> void:
	# ветка/линия с бликом по левому краю
	var shifted := PackedVector2Array()
	for p in pts:
		shifted.append(p + Vector2(-1.6, -0.6))
	draw_polyline(shifted, RIM, w + 1.0, true)
	draw_polyline(pts, BARK, w, true)


func _draw_tree() -> void:
	var trunk := PackedVector2Array([
		Vector2(-12, 2), Vector2(-7, -60), Vector2(-4, -120), Vector2(0, -152),
		Vector2(4, -118), Vector2(8, -58), Vector2(13, 2)])
	draw_polyline(PackedVector2Array([trunk[0], trunk[1], trunk[2], trunk[3]]).duplicate(), RIM, 2.2, true)
	draw_colored_polygon(trunk, BARK)
	draw_polyline(PackedVector2Array([trunk[0] + Vector2(1.5, 0), trunk[1] + Vector2(1.5, 0),
		trunk[2] + Vector2(1.5, 0), trunk[3] + Vector2(1.0, 0)]), RIM, 1.6, true)
	_line(PackedVector2Array([Vector2(-5, -70), Vector2(-24, -92), Vector2(-42, -97)]), 4.5)
	_line(PackedVector2Array([Vector2(-24, -92), Vector2(-31, -114)]), 3.0)
	_line(PackedVector2Array([Vector2(5, -80), Vector2(26, -104), Vector2(38, -134)]), 4.5)
	_line(PackedVector2Array([Vector2(26, -104), Vector2(42, -100)]), 3.0)
	_line(PackedVector2Array([Vector2(-2, -110), Vector2(-17, -131), Vector2(-14, -154)]), 3.4)
	_line(PackedVector2Array([Vector2(1, -126), Vector2(15, -147)]), 2.8)
	for b in [Vector2(-42, -97), Vector2(-31, -114), Vector2(38, -134),
			Vector2(42, -100), Vector2(-14, -154), Vector2(15, -147)]:
		draw_circle(b, 4.0, Color(BUD.r, BUD.g, BUD.b, 0.18))
		draw_circle(b, 2.0, BUD)


func _draw_rock() -> void:
	var pts := PackedVector2Array([
		Vector2(-36, -2), Vector2(-30, -30), Vector2(-10, -46), Vector2(14, -42),
		Vector2(34, -22), Vector2(38, -2), Vector2(12, 5), Vector2(-16, 5)])
	draw_colored_polygon(pts, Color(0.16, 0.16, 0.27))
	draw_colored_polygon(PackedVector2Array([
		Vector2(-30, -30), Vector2(-10, -46), Vector2(14, -42), Vector2(2, -24)]),
		Color(0.27, 0.28, 0.45))
	draw_colored_polygon(PackedVector2Array([
		Vector2(14, -42), Vector2(34, -22), Vector2(38, -2), Vector2(12, 5), Vector2(6, -14)]),
		Color(0.10, 0.10, 0.19))
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, INK, 2.0, true)
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2]]), RIM, 1.8, true)
	draw_polyline(PackedVector2Array([
		Vector2(-6, -22), Vector2(-1, -12), Vector2(-8, -3)]), Color(0.55, 0.45, 1.0, 0.85), 1.7, true)


func _draw_bush() -> void:
	draw_colored_polygon(PackedVector2Array([
		Vector2(-22, 2), Vector2(-18, -16), Vector2(-6, -24), Vector2(8, -26),
		Vector2(20, -16), Vector2(24, 2)]), Color(0.055, 0.055, 0.105))
	var thorn := Color(0.22, 0.20, 0.50)
	for i in 7:
		var bx := -18.0 + 6.0 * float(i)
		var up := 22.0 + float((i * 5) % 9)
		var lean := (float(i) - 3.0) * 4.0
		draw_polyline(PackedVector2Array([
			Vector2(bx, 0), Vector2(bx + lean * 0.5, -up * 0.55),
			Vector2(bx + lean, -up)]), thorn, 1.6, true)
	draw_polyline(PackedVector2Array([Vector2(-22, 2), Vector2(-18, -16), Vector2(-6, -24)]), RIM, 1.5, true)
	for b in [Vector2(-8, -16), Vector2(6, -21), Vector2(15, -10)]:
		draw_circle(b, 4.0, Color(BUD.r, BUD.g, BUD.b, 0.2))
		draw_circle(b, 2.1, BUD)


func _draw_pillar() -> void:
	var stone := Color(0.17, 0.17, 0.29)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-27, 3), Vector2(-25, -10), Vector2(25, -10), Vector2(27, 3)]), Color(0.14, 0.14, 0.24))
	var shaft := PackedVector2Array([
		Vector2(-17, -10), Vector2(-16, -88), Vector2(-8, -97), Vector2(0, -91),
		Vector2(9, -105), Vector2(17, -89), Vector2(17, -10)])
	draw_colored_polygon(shaft, stone)
	draw_colored_polygon(PackedVector2Array([
		Vector2(5, -10), Vector2(17, -10), Vector2(17, -89), Vector2(9, -105), Vector2(5, -95)]),
		Color(0.11, 0.11, 0.20))
	for x in [-8.0, 0.0]:
		draw_line(Vector2(x, -13), Vector2(x, -86), Color(0.09, 0.09, 0.17), 2.0)
	draw_polyline(PackedVector2Array([Vector2(-17, -10), Vector2(-16, -88), Vector2(-8, -97)]), RIM, 1.8, true)
	draw_polyline(PackedVector2Array([
		Vector2(-5, -60), Vector2(-1, -48), Vector2(-7, -36)]), Color(0.55, 0.45, 1.0, 0.8), 1.6, true)
	# обломки у основания
	draw_colored_polygon(PackedVector2Array([
		Vector2(-38, 3), Vector2(-33, -7), Vector2(-24, -4), Vector2(-26, 3)]), Color(0.13, 0.13, 0.22))
	draw_colored_polygon(PackedVector2Array([
		Vector2(28, 4), Vector2(33, -4), Vector2(42, -1), Vector2(38, 5)]), Color(0.12, 0.12, 0.2))
