extends StaticBody2D
## Участок стены в одну строку: коллизия по основанию, рисуем вверх.
## Начало координат = левый нижний угол первой ячейки участка.

const G := preload("res://geo.gd")

var lv
var cell_x := 0
var cell_y := 0
var count := 1
var zone := 0
var lift := 0.0      # высота платформы под стеной (террасы)


func _ready() -> void:
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(count * G.W, G.H)
	cs.shape = sh
	cs.position = Vector2(count * G.W * 0.5, -G.H * 0.5)
	add_child(cs)
	queue_redraw()


func _draw() -> void:
	var pal: Array = G.wall_colors(zone)
	var front: Color = pal[0]
	var top: Color = pal[1]
	var rim: Color = pal[2]
	var rock := zone == G.Z_OUT
	for k in count:
		var x := cell_x + k
		var y := cell_y
		var x0 := float(k) * G.W
		var s_wall: bool = lv.kind_at(x, y + 1) == G.WALL
		var n_wall: bool = lv.kind_at(x, y - 1) == G.WALL
		var w_wall: bool = lv.kind_at(x - 1, y) == G.WALL
		var e_wall: bool = lv.kind_at(x + 1, y) == G.WALL
		# верхняя грань
		var tr := Rect2(x0, -G.WALL_H - G.H - lift, G.W, G.H)
		var sh := (G.hash2(x, y, 51) - 0.5) * 0.03
		draw_rect(tr, Color(top.r + sh, top.g + sh, top.b + sh * 1.4))
		if not n_wall:
			draw_line(tr.position, tr.position + Vector2(G.W, 0), rim, 2.0)
		if not w_wall:
			draw_line(tr.position, tr.position + Vector2(0, G.H), Color(rim.r, rim.g, rim.b, 0.3), 1.5)
		if not e_wall:
			draw_line(tr.position + Vector2(G.W, 0), tr.position + Vector2(G.W, G.H), Color(0, 0, 0.03, 0.5), 2.0)
		if rock:
			for b in 2:
				var bx := x0 + G.hash2(x, y, 60 + b) * G.W
				draw_circle(Vector2(bx, tr.position.y + G.hash2(x, y, 63 + b) * G.H), 7.0 + b * 3.0, Color(top.r * 1.2, top.g * 1.2, top.b * 1.2, 0.8))
		else:
			if G.hash2(x, y, 52) > 0.6:
				draw_line(tr.position + Vector2(G.W * 0.5, 0), tr.position + Vector2(G.W * 0.5, G.H), Color(0, 0, 0.03, 0.3), 1.5)
		# лицевая грань, если спереди не стена
		if s_wall:
			continue
		if lift > 0.0:
			draw_rect(Rect2(x0, -lift, G.W, lift + 1.0), Color(0.035, 0.035, 0.08))
			for s in 2:
				var sx := x0 + G.hash2(x, y, 70 + s) * G.W
				draw_line(Vector2(sx, -lift), Vector2(sx + 5.0, 0), Color(0.12, 0.12, 0.25, 0.6), 2.0)
		var fr := Rect2(x0, -G.WALL_H - lift, G.W, G.WALL_H)
		draw_rect(fr, Color(front.r + sh, front.g + sh, front.b + sh * 1.4))
		var line := Color(0, 0, 0.03, 0.55)
		if rock:
			for s in 4:
				var sx := x0 + G.hash2(x, y, 80 + s) * G.W
				var sy := fr.position.y + G.hash2(x, y, 84 + s) * 40.0
				draw_line(Vector2(sx, sy), Vector2(sx + (G.hash2(x, y, 88 + s) - 0.5) * 16.0, sy + 40.0 + G.hash2(x, y, 92 + s) * 40.0), line, 2.5)
		else:
			# кирпичная кладка
			var rows := 6
			var rh := G.WALL_H / rows
			for r in rows:
				var ry := fr.position.y + float(r) * rh
				draw_line(Vector2(x0, ry), Vector2(x0 + G.W, ry), line, 1.5)
				var off := 0.0 if (r + x) % 2 == 0 else 16.0
				var bx := x0 + off + 16.0
				while bx < x0 + G.W:
					draw_line(Vector2(bx, ry), Vector2(bx, ry + rh), line, 1.5)
					bx += 32.0
			if G.hash2(x, y, 53) > 0.82:
				var cx := x0 + G.hash2(x, y, 54) * G.W
				draw_polyline(PackedVector2Array([
					Vector2(cx, fr.position.y), Vector2(cx - 6.0, fr.position.y + 36.0),
					Vector2(cx + 5.0, fr.position.y + 70.0)]), Color(0, 0, 0.03, 0.8), 2.0)
		# кромка и тень у земли
		draw_line(fr.position, fr.position + Vector2(G.W, 0), Color(rim.r, rim.g, rim.b, 0.25), 1.5)
		draw_rect(Rect2(x0, -lift - 16.0, G.W, 16.0), Color(0, 0, 0.03, 0.35))
