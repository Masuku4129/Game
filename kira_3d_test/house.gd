class_name House
extends Node3D
## Бревенчатый дом у поляны: каменный фундамент, брёвна, крыша из тёмной черепицы, труба с дымом, крыльцо,
## тёплые окна и фонари. Плюс хозяйственные мелочи: поленница, бочки, ящики, забор.

const WOOD := Color(0.115, 0.078, 0.060)
const WOOD_D := Color(0.075, 0.050, 0.042)
const STONE := Color(0.150, 0.155, 0.195)
const ROOF_A := Color(0.075, 0.095, 0.130)
const ROOF_B := Color(0.120, 0.140, 0.185)
const WARM := Color(1.0, 0.68, 0.30)

var body := Valley.MeshBuilder.new()
var glow := Valley.MeshBuilder.new()
var valley: Valley
var base := Vector3.ZERO


func _jit(c: Color, k: float, seed_v: float) -> Color:
	var j := 1.0 + k * (fposmod(sin(seed_v * 12.9898) * 43758.5453, 1.0) - 0.5) * 2.0
	return Color(c.r * j, c.g * j, c.b * j, 1.0)


func _box(mb: Valley.MeshBuilder, c: Vector3, s: Vector3, col: Color, yaw := 0.0) -> void:
	var h := s * 0.5
	var rot := Basis(Vector3.UP, yaw)
	for axis in range(3):
		for sgn in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[axis] = sgn
			var u := Vector3.ZERO
			var v := Vector3.ZERO
			u[(axis + 1) % 3] = 1.0
			v[(axis + 2) % 3] = 1.0
			var f := n * h
			var pa := rot * (f - u * h - v * h) + c
			var pb := rot * (f + u * h - v * h) + c
			var pc := rot * (f + u * h + v * h) + c
			var pd := rot * (f - u * h + v * h) + c
			mb.quad(pa, pb, pc, pd, col, rot * n)


func _prism(mb: Valley.MeshBuilder, c: Vector3, r: float, hgt: float, col: Color, sides := 7) -> void:
	for k in range(sides):
		var a0 := TAU * float(k) / float(sides)
		var a1 := TAU * float(k + 1) / float(sides)
		var b0 := c + Vector3(cos(a0) * r, 0.0, sin(a0) * r)
		var b1 := c + Vector3(cos(a1) * r, 0.0, sin(a1) * r)
		var t0 := b0 + Vector3(0.0, hgt, 0.0)
		var t1 := b1 + Vector3(0.0, hgt, 0.0)
		var mid := Vector3(cos((a0 + a1) * 0.5), 0.0, sin((a0 + a1) * 0.5))
		mb.quad(b0, b1, t1, t0, col, mid)
		mb.tri(t0, t1, c + Vector3(0.0, hgt, 0.0), col, col, col, Vector3.UP)


func build(v: Valley, pos: Vector3) -> void:
	valley = v
	base = pos
	position = pos
	var W := 3.5          # полуширина по X
	var D := 3.0          # полуглубина по Z (дверь на +Z)
	# каменный фундамент
	_box(body, Vector3(0, 0.30, 0), Vector3(W * 2 + 0.5, 0.6, D * 2 + 0.5), STONE)
	for k in range(14):
		var a := float(k) * 1.37
		var sx := (float(k % 7) / 6.0 - 0.5) * (W * 2 + 0.2)
		var sz := D + 0.28 if k < 7 else -D - 0.28
		_box(body, Vector3(sx, 0.32, sz), Vector3(0.7 + 0.2 * sin(a), 0.5, 0.2), _jit(STONE, 0.25, a))
	# стены: брёвна венцами, торцы выступают в углах
	var courses := 7
	for i in range(courses):
		var y := 0.6 + 0.21 + 0.42 * float(i)
		var col := _jit(WOOD if i % 2 == 0 else WOOD_D, 0.18, float(i))
		_box(body, Vector3(0, y, D), Vector3(W * 2, 0.40, 0.42), col)
		_box(body, Vector3(0, y, -D), Vector3(W * 2, 0.40, 0.42), col)
		_box(body, Vector3(W, y, 0), Vector3(0.42, 0.40, D * 2), _jit(col, 0.1, float(i) + 3.0))
		_box(body, Vector3(-W, y, 0), Vector3(0.42, 0.40, D * 2), _jit(col, 0.1, float(i) + 7.0))
		var ext := 0.34 if i % 2 == 0 else -0.05
		for cx in [-1.0, 1.0]:
			for cz in [-1.0, 1.0]:
				_box(body, Vector3(cx * (W + ext * 0.5), y, cz * (D + ext * 0.5)), Vector3(0.50 + ext, 0.40, 0.50 + ext), _jit(col, 0.12, float(i) * 2.0 + cx + cz))
	# внутренний объём, чтобы не просвечивало
	_box(body, Vector3(0, 1.8, 0), Vector3(W * 2 - 0.4, 2.8, D * 2 - 0.4), WOOD_D)
	# крыша: двускатная, с выносом, рядами черепицы
	var eave_y := 3.45
	var ridge_y := 5.45
	var over_z := 3.75
	var x0 := -W - 0.65
	var x1 := W + 0.65
	var rows := 8
	for sgn in [-1.0, 1.0]:
		for i in range(rows):
			var u0 := float(i) / float(rows)
			var u1 := float(i + 1) / float(rows)
			var za := sgn * over_z * (1.0 - u0)
			var zb := sgn * over_z * (1.0 - u1)
			var ya := eave_y + (ridge_y - eave_y) * u0
			var yb := eave_y + (ridge_y - eave_y) * u1
			var base_c := ROOF_A.lerp(ROOF_B, 0.5 + 0.5 * sin(float(i) * 2.1 + sgn))
			var lo := Color(base_c.r * 0.55, base_c.g * 0.55, base_c.b * 0.6, 1.0)
			var hint := Vector3(0.0, 1.0, sgn * 0.8)
			var nseg := 7
			for s in range(nseg):
				var xa := lerpf(x0, x1, float(s) / float(nseg))
				var xb := lerpf(x0, x1, float(s + 1) / float(nseg))
				var cj := _jit(base_c, 0.22, float(i * 17 + s) + sgn * 5.0)
				var cl := Color(cj.r * 0.55, cj.g * 0.55, cj.b * 0.6, 1.0)
				body.tri(Vector3(xa, ya, za), Vector3(xb, ya, za), Vector3(xb, yb, zb), cl, cl, cj, hint)
				body.tri(Vector3(xa, ya, za), Vector3(xb, yb, zb), Vector3(xa, yb, zb), cl, cj, cj, hint)
		# подбой крыши
		body.quad(Vector3(x0, eave_y - 0.1, sgn * over_z), Vector3(x1, eave_y - 0.1, sgn * over_z), Vector3(x1, ridge_y - 0.1, 0.0), Vector3(x0, ridge_y - 0.1, 0.0), WOOD_D, Vector3(0.0, -1.0, 0.0))
	_box(body, Vector3(0, ridge_y + 0.04, 0), Vector3(x1 - x0 + 0.1, 0.22, 0.34), ROOF_B * 0.8)
	# фронтоны из досок
	for sx in [-1.0, 1.0]:
		var gx: float = sx * W
		body.tri(Vector3(gx, 3.40, D + 0.05), Vector3(gx, 3.40, -D - 0.05), Vector3(gx, ridge_y - 0.1, 0.0), WOOD, WOOD, WOOD_D, Vector3(sx, 0.0, 0.0))
	for sz in [-1.0, 1.0]:
		var gz: float = sz * (D + 0.02)
		for k in range(6):
			var xa := -W + (2.0 * W) * float(k) / 6.0
			var xb := -W + (2.0 * W) * float(k + 1) / 6.0
			var c1 := _jit(WOOD, 0.2, float(k) + sz * 4.0)
			body.quad(Vector3(xa, 3.30, gz), Vector3(xb, 3.30, gz), Vector3(xb, 3.50, gz), Vector3(xa, 3.50, gz), c1, Vector3(0.0, 0.0, sz))
	# дверь с железными полосами и рамой
	var dz := D + 0.24
	_box(body, Vector3(0, 1.0, dz - 0.02), Vector3(1.55, 2.25, 0.16), WOOD * 1.5)
	_box(body, Vector3(0, 0.98, dz + 0.04), Vector3(1.25, 2.05, 0.10), Color(0.060, 0.040, 0.035))
	for yy in [0.55, 1.40]:
		_box(body, Vector3(0, yy, dz + 0.10), Vector3(1.20, 0.10, 0.05), Color(0.10, 0.10, 0.13))
	_box(body, Vector3(0.45, 1.0, dz + 0.12), Vector3(0.09, 0.09, 0.07), Color(0.40, 0.36, 0.28))
	# окна: рама и тёплое стекло
	for wx in [-2.25, 2.25]:
		_box(body, Vector3(wx, 1.75, dz - 0.02), Vector3(1.20, 0.95, 0.14), WOOD * 1.6)
		glow.quad(Vector3(wx - 0.48, 1.30, dz + 0.07), Vector3(wx + 0.48, 1.30, dz + 0.07), Vector3(wx + 0.48, 2.18, dz + 0.07), Vector3(wx - 0.48, 2.18, dz + 0.07), WARM, Vector3(0, 0, 1))
		_box(body, Vector3(wx, 1.75, dz + 0.09), Vector3(1.0, 0.07, 0.04), WOOD * 1.8)
		_box(body, Vector3(wx, 1.75, dz + 0.09), Vector3(0.07, 0.9, 0.04), WOOD * 1.8)
	for sx in [-1.0, 1.0]:
		var wxx: float = sx * (W + 0.26)
		_box(body, Vector3(wxx, 1.75, 0.0), Vector3(0.14, 0.95, 1.2), WOOD * 1.6)
		glow.quad(Vector3(wxx + sx * 0.08, 1.30, 0.48), Vector3(wxx + sx * 0.08, 1.30, -0.48), Vector3(wxx + sx * 0.08, 2.18, -0.48), Vector3(wxx + sx * 0.08, 2.18, 0.48), WARM * 0.9, Vector3(sx, 0, 0))
	# труба
	_box(body, Vector3(-2.3, 4.7, -1.2), Vector3(0.95, 3.2, 0.95), STONE * 1.15)
	_box(body, Vector3(-2.3, 6.35, -1.2), Vector3(1.15, 0.22, 1.15), STONE * 0.9)
	# крыльцо: настил, ступень, столбы, навес-козырёк и фонарь
	_box(body, Vector3(0, 0.12, D + 1.1), Vector3(3.2, 0.24, 1.9), WOOD * 1.1)
	_box(body, Vector3(0, 0.04, D + 2.3), Vector3(2.2, 0.12, 0.7), WOOD_D * 1.3)
	for px in [-1.45, 1.45]:
		_box(body, Vector3(px, 1.5, D + 1.85), Vector3(0.2, 2.8, 0.2), WOOD * 1.2)
	_box(body, Vector3(0, 2.92, D + 1.15), Vector3(3.5, 0.18, 2.3), WOOD_D)
	for sgn2 in [-1.0, 1.0]:
		body.quad(Vector3(-1.9, 3.0, D + 0.05), Vector3(1.9, 3.0, D + 0.05), Vector3(1.9, 2.7, D + 2.4), Vector3(-1.9, 2.7, D + 2.4), ROOF_A, Vector3(0, 1, 0.3))
		break
	_prism(glow, Vector3(1.15, 2.30, D + 1.85), 0.12, 0.30, WARM, 6)
	# хозяйство: поленница, бочки, ящики
	for r in range(4):
		for k in range(5 - r):
			_box(body, Vector3(-W - 0.9, 0.17 + 0.33 * float(r), -1.7 + 0.38 * float(k) + 0.19 * float(r)), Vector3(0.9, 0.31, 0.34), _jit(WOOD, 0.25, float(r * 7 + k)))
	_box(body, Vector3(-W - 1.0, 0.45, -0.6), Vector3(0.9, 0.9, 2.4), WOOD_D * 1.2)
	for bb in [Vector3(W + 0.9, 0.0, D - 0.6), Vector3(W + 1.5, 0.0, D + 0.2)]:
		_prism(body, bb, 0.38, 0.85, WOOD * 1.2, 8)
		_prism(body, bb + Vector3(0, 0.25, 0), 0.40, 0.06, Color(0.10, 0.10, 0.13), 8)
	_box(body, Vector3(W + 1.2, 0.30, D + 1.3), Vector3(0.7, 0.6, 0.7), WOOD * 1.3, 0.4)
	_box(body, Vector3(W + 1.25, 0.85, D + 1.25), Vector3(0.5, 0.5, 0.5), WOOD * 1.1, 0.9)
	# фонарные столбы вдоль тропы и забор
	for lp in [Vector3(-2.0, 0.0, D + 4.0), Vector3(2.0, 0.0, D + 8.5), Vector3(-2.0, 0.0, D + 13.0)]:
		var gh := valley.height_at(base.x + lp.x, base.z + lp.z) - base.y
		_box(body, Vector3(lp.x, gh + 0.9, lp.z), Vector3(0.14, 1.8, 0.14), WOOD_D * 1.4)
		_box(body, Vector3(lp.x, gh + 1.95, lp.z), Vector3(0.40, 0.08, 0.40), Color(0.09, 0.09, 0.12))
		_prism(glow, Vector3(lp.x, gh + 1.62, lp.z), 0.13, 0.30, WARM, 6)
		valley.add_obstacle(base.x + lp.x, base.z + lp.z, 0.2, 3.0)
	for fx in [-1.0, 1.0]:
		for k in range(7):
			var fz := D + 3.0 + 1.1 * float(k)
			var xx := fx * (4.6 + 0.0)
			var gh2 := valley.height_at(base.x + xx, base.z + fz) - base.y
			_box(body, Vector3(xx, gh2 + 0.55, fz), Vector3(0.14, 1.1, 0.14), WOOD_D * 1.5)
			if k < 6:
				for ry in [0.45, 0.85]:
					_box(body, Vector3(xx, gh2 + ry, fz + 0.55), Vector3(0.08, 0.08, 1.12), WOOD * 1.1)
			valley.add_obstacle(base.x + xx, base.z + fz, 0.2, 1.2)
	# собираем меши
	var mi := MeshInstance3D.new()
	mi.mesh = body.build()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.95
	mi.material_override = m
	add_child(mi)
	var gi := MeshInstance3D.new()
	gi.mesh = glow.build()
	var gm := ShaderMaterial.new()
	gm.shader = load("res://lamp.gdshader")
	gi.material_override = gm
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(gi)
	# дым из трубы
	var smoke := CPUParticles3D.new()
	smoke.amount = 16
	smoke.lifetime = 7.0
	smoke.preprocess = 7.0
	smoke.local_coords = false
	smoke.mesh = QuadMesh.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://mist.gdshader")
	sm.set_shader_parameter("tint", Color(0.55, 0.55, 0.65, 0.22))
	sm.set_shader_parameter("near_fade", 3.0)
	smoke.material_override = sm
	smoke.position = Vector3(-2.3, 6.6, -1.2)
	smoke.direction = Vector3(0.35, 1.0, 0.1)
	smoke.spread = 12.0
	smoke.initial_velocity_min = 0.7
	smoke.initial_velocity_max = 1.1
	smoke.gravity = Vector3(0.25, 0.1, 0.0)
	smoke.scale_amount_min = 1.0
	smoke.scale_amount_max = 2.2
	var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	gr.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	smoke.color_ramp = gr
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(smoke)
	# столкновения: заполняем площадь дома кругами
	var ox := -W - 0.3
	while ox <= W + 0.31:
		var oz := -D - 0.3
		while oz <= D + 0.31:
			valley.add_obstacle(base.x + ox, base.z + oz, 0.95, 99.0)
			oz += 1.1
		ox += 1.1
	# фонарь у входа даёт ощущение жилья: тёплые блики на земле рисуем отдельно (простое пятно света)
