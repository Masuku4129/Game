extends Node2D
## Рисунки поверх пола: ковры, символы, верёвки мостов.
## Список записей берётся из level.gd (lv.decals).

var lv


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	for d in lv.decals:
		var t: String = d[0]
		if t == "rect":
			draw_rect(d[1], d[2])
		elif t == "line":
			draw_line(d[1], d[2], d[3], d[4])
		elif t == "ering":
			var c: Vector2 = d[1]
			var pts := PackedVector2Array()
			for s in 49:
				var a := TAU * float(s) / 48.0
				pts.append(c + Vector2(cos(a) * d[2], sin(a) * d[3]))
			draw_polyline(pts, d[4], d[5], true)
		elif t == "rope":
			var a2: Vector2 = d[1]
			var b2: Vector2 = d[2]
			var pts2 := PackedVector2Array()
			for s in 9:
				var u := float(s) / 8.0
				pts2.append(a2.lerp(b2, u) + Vector2(0, sin(PI * u) * 9.0))
			draw_polyline(pts2, Color(0.03, 0.025, 0.06), 3.0, true)
			draw_polyline(pts2, Color(0.35, 0.33, 0.7, 0.45), 1.0, true)
