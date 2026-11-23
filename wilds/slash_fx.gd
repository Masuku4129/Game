extends Node2D
## Светящийся полумесяц по дуге взмаха, рисуется кодом (аддитивное смешивание).
var rx := 108.0
var ry := 84.0
var rot := 0.0
var a0 := -1.4
var a1 := 1.4
var dur := 0.14
var fade := 0.16
var hold := -1.0      # >=0: заморозить на этом прогрессе (для кадров предпросмотра)
var _t := 0.0


func _ready() -> void:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = m


func _process(delta: float) -> void:
	if hold < 0.0:
		_t += delta
		if _t > dur + fade:
			queue_free()
	queue_redraw()


func _pt(a: float) -> Vector2:
	return Vector2(rx * cos(a), ry * sin(a)).rotated(rot)


func _draw() -> void:
	var p: float
	var alpha := 1.0
	var tail_p := 0.0
	if hold >= 0.0:
		p = hold
		tail_p = maxf(0.0, p - 0.7)
	else:
		p = clampf(_t / dur, 0.0, 1.0)
		p = 1.0 - pow(1.0 - p, 2.2)
		tail_p = maxf(0.0, p - 0.7)
		if _t > dur:
			var k := (_t - dur) / fade
			alpha = 1.0 - k
			tail_p = 0.3 + 0.7 * k
	if p - tail_p < 0.02:
		return
	var head := a0 + (a1 - a0) * p
	var tail := a0 + (a1 - a0) * tail_p
	var n := 30
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var layers := [
		[1.9, Color(0.40, 0.25, 1.0, 0.28)],
		[1.15, Color(0.55, 0.80, 1.0, 0.55)],
		[0.5, Color(1.0, 1.0, 1.0, 0.95)]]
	for L in layers:
		outer.clear()
		inner.clear()
		for i in n + 1:
			var u := float(i) / n
			var pos := _pt(lerpf(tail, head, u))
			var lw: float = L[0]
			var w: float = pow(sin(PI * u), 0.75) * 26.0 * lw
			var nrm := pos.normalized()
			outer.append(pos + nrm * w * 0.30)
			inner.append(pos - nrm * w * 0.70)
		inner.reverse()
		var poly := outer + inner
		var c: Color = L[1]
		c.a *= alpha
		draw_colored_polygon(poly, c)
