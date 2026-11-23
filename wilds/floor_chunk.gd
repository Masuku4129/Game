extends Node2D
## Кусок пола 8x8 ячеек: плиты, доски, земля, обрывы, мосты, лестницы.
## Рисуется один раз.

const G := preload("res://geo.gd")
const SPAN := 8

var lv
var cx0 := 0
var cy0 := 0


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	for y in range(cy0, mini(cy0 + SPAN, G.GH)):
		for x in range(cx0, mini(cx0 + SPAN, G.GW)):
			var i: int = y * G.GW + x
			var k: int = lv.kind[i]
			if k == G.FLOOR or k == G.RAISED:
				_floor(x, y, i)
			elif k == G.BRIDGE:
				_bridge(x, y)
			elif k == G.STAIRS:
				_stairs(x, y, i)
			elif k == G.CHASM:
				_chasm(x, y)


func _floor(x: int, y: int, i: int) -> void:
	var z: int = lv.zone[i]
	var lift := 0.0
	if lv.kind[i] == G.RAISED:
		lift = G.LIFT
	var p := Vector2(x * G.W, y * G.H - lift)
	var base: Color = G.floor_color(z)
	var n := G.hash2(x, y, 1)
	var sh := (n - 0.5) * 0.035
	draw_rect(Rect2(p, Vector2(G.W, G.H)), Color(base.r + sh, base.g + sh, base.b + sh * 1.5))
	# швы плит и светлая кромка сверху и слева
	draw_line(p + Vector2(0, G.H), p + Vector2(G.W, G.H), Color(0, 0, 0.03, 0.55), 2.0)
	draw_line(p + Vector2(G.W, 0), p + Vector2(G.W, G.H), Color(0, 0, 0.03, 0.45), 2.0)
	draw_line(p, p + Vector2(G.W, 0), Color(0.5, 0.55, 1.0, 0.07), 1.5)
	draw_line(p, p + Vector2(0, G.H), Color(0.5, 0.55, 1.0, 0.05), 1.5)

	if z == G.Z_LIB:
		draw_line(p + Vector2(0, 24), p + Vector2(G.W, 24), Color(0, 0, 0.03, 0.3), 1.5)
		draw_line(p + Vector2(0, 48), p + Vector2(G.W, 48), Color(0, 0, 0.03, 0.3), 1.5)
		var jx := G.hash2(x, y, 3) * G.W
		draw_line(p + Vector2(jx, 0), p + Vector2(jx, 24), Color(0, 0, 0.03, 0.3), 1.5)
		draw_line(p + Vector2(G.W - jx, 48), p + Vector2(G.W - jx, G.H), Color(0, 0, 0.03, 0.3), 1.5)
	elif z == G.Z_OUT:
		var tuft := Color(0.13, 0.12, 0.30)
		var tuft_l := Color(0.30, 0.30, 0.72, 0.7)
		for t in 3:
			var tx := G.hash2(x, y, 10 + t) * (G.W - 12.0) + 6.0
			var ty := G.hash2(x, y, 20 + t) * (G.H - 16.0) + 14.0
			var hh := 6.0 + G.hash2(x, y, 30 + t) * 6.0
			var c := tuft if G.hash2(x, y, 40 + t) < 0.65 else tuft_l
			var q := p + Vector2(tx, ty)
			draw_line(q, q + Vector2(-3, -hh), c, 2.0)
			draw_line(q, q + Vector2(0, -hh - 3), c, 2.0)
			draw_line(q, q + Vector2(3, -hh), c, 2.0)
		if n > 0.93:
			var q2 := p + Vector2(G.W * 0.5, G.H * 0.5)
			_ellipse(q2, 32.0, 14.0, Color(0.16, 0.18, 0.5, 0.35))
			_ellipse(q2, 22.0, 9.0, Color(0.24, 0.27, 0.65, 0.25))
	# трещины и обломки
	if G.hash2(x, y, 2) > 0.87:
		var a := p + Vector2(G.hash2(x, y, 4) * G.W, G.hash2(x, y, 5) * G.H * 0.5)
		var b := a + Vector2((G.hash2(x, y, 6) - 0.5) * 50.0, 20.0)
		var c2 := b + Vector2((G.hash2(x, y, 7) - 0.5) * 40.0, 22.0)
		draw_polyline(PackedVector2Array([a, b, c2]), Color(0, 0, 0.03, 0.7), 2.0)
	if z != G.Z_OUT and G.hash2(x, y, 8) > 0.93:
		var r := p + Vector2(G.hash2(x, y, 9) * G.W, G.hash2(x, y, 11) * G.H)
		draw_circle(r, 5.0, Color(0.03, 0.03, 0.07))
		draw_circle(r + Vector2(-1, -1), 3.0, Color(0.16, 0.17, 0.35))


func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for s in 20:
		var a := TAU * float(s) / 20.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)


func _bridge(x: int, y: int) -> void:
	var p := Vector2(x * G.W, y * G.H)
	draw_rect(Rect2(p, Vector2(G.W, G.H)), Color(0.008, 0.008, 0.03))
	var wood := Color(0.12, 0.09, 0.17)
	# доски поперёк моста
	var nb := 6
	for b in nb:
		var bx := p.x + float(b) * G.W / nb
		var sh := (G.hash2(x * 7 + b, y, 12) - 0.5) * 0.03
		if G.hash2(x * 7 + b, y, 13) > 0.94:
			continue   # выбитая доска
		draw_rect(Rect2(bx + 1.0, p.y + 4.0, G.W / nb - 2.0, G.H - 8.0), Color(wood.r + sh, wood.g + sh, wood.b + sh * 1.5))
		draw_line(Vector2(bx + 1.0, p.y + 4.0), Vector2(bx + G.W / nb - 1.0, p.y + 4.0), Color(0.5, 0.5, 1.0, 0.1), 1.0)
	# балки по краям
	draw_line(p + Vector2(0, 3), p + Vector2(G.W, 3), Color(0.05, 0.04, 0.09), 6.0)
	draw_line(p + Vector2(0, G.H - 3), p + Vector2(G.W, G.H - 3), Color(0.05, 0.04, 0.09), 6.0)
	draw_line(p + Vector2(0, 0.5), p + Vector2(G.W, 0.5), Color(0.4, 0.42, 1.0, 0.3), 1.5)


func _chasm(x: int, y: int) -> void:
	var p := Vector2(x * G.W, y * G.H)
	draw_rect(Rect2(p, Vector2(G.W, G.H)), Color(0.008, 0.008, 0.03))
	var n := G.hash2(x, y, 5)
	if n > 0.45:
		_ellipse(p + Vector2(G.W * n, G.H * 0.6), 40.0, 16.0, Color(0.07, 0.06, 0.2, 0.3))
	# что над ячейкой
	var up: int = lv.kind_at(x, y - 1)
	if up == G.BRIDGE:
		draw_rect(Rect2(p, Vector2(G.W, 16.0)), Color(0, 0, 0.02, 0.65))
	elif G.walkable(up):
		var lift: float = lv.cell_lift(x, y - 1) * G.LIFT
		var top := p.y - lift
		var face := lift + 70.0
		var bands := 7
		for b in bands:
			var t := float(b) / bands
			var c := Color(0.085 - 0.08 * t, 0.085 - 0.08 * t, 0.17 - 0.15 * t)
			draw_rect(Rect2(p.x, top + face * t, G.W, face / bands + 1.0), c)
		for s in 3:
			var sx := p.x + G.hash2(x, y, 14 + s) * G.W
			var sy := top + G.hash2(x, y, 17 + s) * face * 0.4
			draw_line(Vector2(sx, sy), Vector2(sx + (G.hash2(x, y, 20 + s) - 0.5) * 14.0, sy + face * 0.5), Color(0, 0, 0.03, 0.6), 2.0)
		draw_line(Vector2(p.x, top), Vector2(p.x + G.W, top), Color(0.45, 0.47, 1.0, 0.45), 2.0)
	# боковые края обрыва
	if G.walkable(lv.kind_at(x - 1, y)):
		draw_rect(Rect2(p, Vector2(10.0, G.H)), Color(0, 0, 0.02, 0.55))
	if G.walkable(lv.kind_at(x + 1, y)):
		draw_rect(Rect2(p + Vector2(G.W - 10.0, 0), Vector2(10.0, G.H)), Color(0, 0, 0.02, 0.55))


func _stairs(x: int, y: int, i: int) -> void:
	var a: float = lv.la[i]
	var b: float = lv.lb[i]
	var dx: int = lv.sdx[i]
	var dy: int = lv.sdy[i]
	var base: Color = G.floor_color(lv.zone[i])
	var tread := Color(base.r * 1.35, base.g * 1.35, base.b * 1.3)
	var riser := Color(base.r * 0.45, base.g * 0.45, base.b * 0.6)
	var o := Vector2(x * G.W, y * G.H)
	var n := 4
	var rise := (b - a) * G.LIFT / n
	if dy != 0:
		var sh := G.H / n
		for jj in n:
			var j := jj
			if dy == -1:
				j = n - 1 - jj          # сначала дальние (верхние) ступени
			var ytop := o.y + G.H - float(j + 1) * sh
			if dy == 1:
				ytop = o.y + float(j) * sh
			var lj := lerpf(a, b, (float(j) + 0.5) / n) * G.LIFT
			if dy == -1:
				draw_rect(Rect2(o.x, ytop + sh - lj, G.W, rise + 1.0), riser)
			draw_rect(Rect2(o.x, ytop - lj, G.W, sh), tread)
			draw_line(Vector2(o.x, ytop + sh - lj), Vector2(o.x + G.W, ytop + sh - lj), Color(0.55, 0.58, 1.0, 0.3), 1.5)
	else:
		var sw := G.W / n
		for j in n:
			var xs := o.x + float(j) * sw
			if dx == -1:
				xs = o.x + G.W - float(j + 1) * sw
			var lj := lerpf(a, b, (float(j) + 0.5) / n) * G.LIFT
			draw_rect(Rect2(xs, o.y + G.H - lj, sw, lj + 1.0), riser)
			draw_rect(Rect2(xs, o.y - lj, sw, G.H), tread)
			draw_line(Vector2(xs, o.y - lj), Vector2(xs + sw, o.y - lj), Color(0.55, 0.58, 1.0, 0.3), 1.5)
			draw_line(Vector2(xs + 1.0, o.y - lj), Vector2(xs + 1.0, o.y + G.H - lj), Color(0, 0, 0.03, 0.35), 1.5)
