extends Node2D
## Земля: тёмная индиго-равнина, плиты руин в изометрии 2:1, лужи, трава.
## Рисуется один раз.

var radius := 2400.0
var seed_value := 1


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 7

	draw_circle(Vector2.ZERO, radius + 500.0, Color(0.02, 0.02, 0.06))
	draw_circle(Vector2.ZERO, radius, Color(0.06, 0.06, 0.14))

	# пятна и светящиеся лужи: сплюснутые эллипсы (перспектива)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	for i in 120:
		var p := _rand_in_circle(rng, radius - 60.0)
		var r := rng.randf_range(70.0, 190.0)
		var s := rng.randf_range(-0.02, 0.03)
		draw_circle(p, r, Color(0.075 + s, 0.075 + s, 0.17 + s, 0.6))
	for i in 55:
		var p := _rand_in_circle(rng, radius - 100.0)
		var r := rng.randf_range(24.0, 70.0)
		draw_circle(p, r, Color(0.16, 0.18, 0.5, 0.35))
		draw_circle(p, r * 0.7, Color(0.24, 0.27, 0.65, 0.25))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# стартовая площадка: плиты 2:1, часть выбита
	for gx in range(-4, 5):
		for gy in range(-4, 5):
			if rng.randf() < 0.2:
				continue
			var c := Vector2(float(gx - gy) * 60.0, float(gx + gy) * 30.0)
			var shade := 0.0 if (gx + gy) % 2 == 0 else 0.025
			_tile(c, 118.0, Color(0.11 + shade, 0.11 + shade, 0.22 + shade))

	# разбросанные плиты поменьше
	for i in 60:
		var p := _rand_in_circle(rng, radius - 80.0)
		if absf(p.x) < 460.0 and absf(p.y) < 260.0:
			continue
		_tile(p, rng.randf_range(60.0, 110.0), Color(0.10, 0.10, 0.2))

	# трава
	var tuft := Color(0.13, 0.12, 0.30)
	var tuft_light := Color(0.30, 0.30, 0.72, 0.7)
	for i in 1300:
		var p := _rand_in_circle(rng, radius - 10.0)
		var h := rng.randf_range(6.0, 12.0)
		var c := tuft if rng.randf() < 0.65 else tuft_light
		draw_line(p, p + Vector2(-3, -h), c, 2.0)
		draw_line(p, p + Vector2(0, -h - 3), c, 2.0)
		draw_line(p, p + Vector2(3, -h), c, 2.0)


func _tile(c: Vector2, w: float, col: Color) -> void:
	var h := w * 0.5
	var pts := PackedVector2Array([
		c + Vector2(0, -h * 0.5), c + Vector2(w * 0.5, 0), c + Vector2(0, h * 0.5), c + Vector2(-w * 0.5, 0)])
	draw_colored_polygon(pts, col)
	var edge := pts.duplicate()
	edge.append(pts[0])
	draw_polyline(edge, Color(0.03, 0.03, 0.08), 2.0, true)
	draw_polyline(PackedVector2Array([pts[3], pts[0], pts[1]]), Color(0.30, 0.32, 0.75, 0.5), 1.5, true)


func _rand_in_circle(rng: RandomNumberGenerator, r: float) -> Vector2:
	var a := rng.randf() * TAU
	var d := sqrt(rng.randf()) * r
	return Vector2(cos(a), sin(a)) * d
