extends RefCounted
## Значки для HUD и короба (inventory.icon): лук, стрела, верёвка, присед.

static func icon(ci: CanvasItem, kind: String, c: Vector2, r: float) -> bool:
	match kind:
		"rifle":
			var wood := Color(0.45, 0.29, 0.16)
			var steel := Color(0.28, 0.31, 0.32)
			ci.draw_line(c + Vector2(-r * 0.82, r * 0.58), c + Vector2(r * 0.65, -r * 0.48), wood, r * 0.22)
			ci.draw_line(c + Vector2(-r * 0.2, r * 0.12), c + Vector2(r * 0.92, -r * 0.76), steel, r * 0.12)
			ci.draw_line(c + Vector2(r * 0.45, -r * 0.42), c + Vector2(r * 0.92, -r * 0.76), steel.lightened(0.25), r * 0.045)
			ci.draw_line(c + Vector2(-r * 0.28, r * 0.18), c + Vector2(-r * 0.43, r * 0.52), Color(0.2, 0.16, 0.12), r * 0.08)
			return true
		"rifle_round":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.22, r * 0.78), c + Vector2(r * 0.22, r * 0.78), c + Vector2(r * 0.22, -r * 0.25), c + Vector2(0, -r * 0.78), c + Vector2(-r * 0.22, -r * 0.25)]), Color(0.65, 0.48, 0.22))
			ci.draw_line(c + Vector2(-r * 0.18, r * 0.55), c + Vector2(r * 0.18, r * 0.55), Color(0.9, 0.72, 0.38), r * 0.07)
			return true
		"bow":
			# плечи дугой, тетива, обмотка рукояти
			var pts := PackedVector2Array()
			for i in 17:
				var t := float(i) / 16.0
				var y := lerpf(-1.0, 1.0, t)
				var x := -0.45 * (1.0 - y * y) + 0.12 * smoothstep(0.75, 1.0, absf(y))
				pts.append(c + Vector2(x * r + r * 0.25, y * r * 0.95).rotated(0.0))
			ci.draw_line(pts[0], pts[16], Color(0.85, 0.78, 0.6), maxf(1.5, r * 0.05))
			ci.draw_polyline(pts, Color(0, 0, 0, 0.2), r * 0.2)
			ci.draw_polyline(pts, Color(0.5, 0.35, 0.2), r * 0.14)
			ci.draw_line(c + Vector2(-r * 0.2 + r * 0.0, -r * 0.12), c + Vector2(-r * 0.2, r * 0.12), Color(0.7, 0.6, 0.4), r * 0.18)
			return true
		"arrow":
			var a := c + Vector2(-r * 0.85, r * 0.85)
			var b := c + Vector2(r * 0.7, -r * 0.7)
			ci.draw_line(a, b, Color(0.6, 0.47, 0.3), r * 0.1)
			var d := (b - a).normalized()
			var n := Vector2(-d.y, d.x)
			ci.draw_colored_polygon(PackedVector2Array([b + d * r * 0.3, b + n * r * 0.13, b - n * r * 0.13]), Color(0.36, 0.33, 0.31))
			for k in 2:
				var q := a + d * r * (0.1 + 0.18 * k)
				ci.draw_colored_polygon(PackedVector2Array([q, q + d * r * 0.25 + n * r * 0.18, q + d * r * 0.25]), Color(0.45, 0.4, 0.36))
				ci.draw_colored_polygon(PackedVector2Array([q, q + d * r * 0.25 - n * r * 0.18, q + d * r * 0.25]), Color(0.55, 0.5, 0.45))
			return true
		"rope":
			for k in 3:
				ci.draw_arc(c + Vector2(0, (k - 1) * r * 0.12), r * (0.7 - k * 0.12), 0.0, TAU, 28, Color(0.62, 0.5, 0.32).darkened(k * 0.08), r * 0.13, true)
			ci.draw_line(c + Vector2(r * 0.5, r * 0.3), c + Vector2(r * 0.95, r * 0.85), Color(0.6, 0.48, 0.3), r * 0.12)
			return true
		"crouch":
			# фигура на корточках
			var col := Color(0.32, 0.22, 0.13)
			ci.draw_circle(c + Vector2(r * 0.15, -r * 0.6), r * 0.2, col)
			ci.draw_line(c + Vector2(r * 0.05, -r * 0.38), c + Vector2(-r * 0.3, r * 0.15), col, r * 0.2)
			ci.draw_line(c + Vector2(-r * 0.3, r * 0.15), c + Vector2(r * 0.25, r * 0.25), col, r * 0.16)
			ci.draw_line(c + Vector2(r * 0.25, r * 0.25), c + Vector2(r * 0.1, r * 0.8), col, r * 0.15)
			ci.draw_line(c + Vector2(-r * 0.3, r * 0.15), c + Vector2(-r * 0.45, r * 0.8), col, r * 0.15)
			ci.draw_line(c + Vector2(r * 0.0, -r * 0.25), c + Vector2(r * 0.45, -r * 0.05), col, r * 0.12)
			return true
	return false
