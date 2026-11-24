class_name Ruins3D
extends Node3D
## Двор руин как настоящая 3D-геометрия: колонны, стены, арки, мост через ручей, статуя, фонари, жаровни, кристаллы, деревья.
## Камень рисует stone.gdshader (кладка блоками), цвета и композиция - по артам пользователя.

var valley: Valley
var rng := RandomNumberGenerator.new()
var stone: ShaderMaterial
var iron: StandardMaterial3D
var bark: StandardMaterial3D
var lamp_glass: StandardMaterial3D
var flame_mat: StandardMaterial3D
var crystal_mat: StandardMaterial3D
var banner_mats := {}


func _ready_mats() -> void:
	stone = ShaderMaterial.new()
	stone.shader = load("res://stone.gdshader")
	stone.set_shader_parameter("slab_tex", load("res://sprites/floor_atlas.png"))
	iron = StandardMaterial3D.new()
	iron.albedo_color = Color(0.10, 0.09, 0.13)
	iron.roughness = 0.6
	iron.metallic = 0.5
	bark = StandardMaterial3D.new()
	bark.albedo_color = Color(0.20, 0.13, 0.10)
	bark.roughness = 1.0
	lamp_glass = StandardMaterial3D.new()
	lamp_glass.albedo_color = Color(1.0, 0.7, 0.3)
	lamp_glass.emission_enabled = true
	lamp_glass.emission = Color(1.0, 0.62, 0.22)
	lamp_glass.emission_energy_multiplier = 3.2
	flame_mat = StandardMaterial3D.new()
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.albedo_color = Color(0.75, 0.45, 1.0, 0.85)
	flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_mat.emission_enabled = true
	flame_mat.emission = Color(0.7, 0.4, 1.0)
	flame_mat.emission_energy_multiplier = 2.5
	crystal_mat = StandardMaterial3D.new()
	crystal_mat.albedo_color = Color(0.55, 0.35, 1.0)
	crystal_mat.roughness = 0.15
	crystal_mat.emission_enabled = true
	crystal_mat.emission = Color(0.50, 0.28, 1.0)
	crystal_mat.emission_energy_multiplier = 1.8


# ---------------------------------------------------------------- примитивы
func _gy(x: float, z: float) -> float:
	return valley.terrain_h(x, z)


func _bx(pos: Vector3, size: Vector3, rot := Vector3.ZERO, mat: Material = null, shadow := true) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat if mat != null else stone
	mi.transform = Transform3D(Basis.from_euler(rot), pos)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _cy(pos: Vector3, r_top: float, r_bot: float, h: float, rot := Vector3.ZERO, mat: Material = null, sides := 10) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bot
	m.height = h
	m.radial_segments = sides
	m.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat if mat != null else stone
	mi.transform = Transform3D(Basis.from_euler(rot), pos)
	add_child(mi)
	return mi


func _sp(pos: Vector3, r: float, mat: Material, sc := Vector3.ONE) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 8
	m.rings = 5
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.transform = Transform3D(Basis.from_scale(sc), pos)
	add_child(mi)
	return mi


func _light(pos: Vector3, col: Color, energy: float, rng_m: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng_m
	l.omni_attenuation = 1.3
	l.position = pos
	add_child(l)


func _obs(x: float, z: float, r: float, top := 6.0) -> void:
	valley.add_obstacle(x, z, r, top)


# ---------------------------------------------------------------- элементы
func column(x: float, z: float, h: float, broken := false) -> void:
	var y0 := _gy(x, z)
	if broken:
		h *= 0.55
	_bx(Vector3(x, y0 + 0.25, z), Vector3(1.6, 0.5, 1.6))
	_bx(Vector3(x, y0 + 0.68, z), Vector3(1.15, 0.36, 1.15))
	_cy(Vector3(x, y0 + 0.86 + h * 0.5, z), 0.40, 0.46, h)
	if broken:
		_bx(Vector3(x + 0.1, y0 + 0.86 + h + 0.12, z), Vector3(0.7, 0.4, 0.6), Vector3(0.0, 0.5, 0.35))
		_cy(Vector3(x + 1.4, y0 + 0.4, z + 0.6), 0.42, 0.42, 1.1, Vector3(0.0, 0.0, PI * 0.5), null, 9)
	else:
		_cy(Vector3(x, y0 + 0.86 + h + 0.22, z), 0.60, 0.40, 0.46)
		_bx(Vector3(x, y0 + 0.86 + h + 0.62, z), Vector3(1.4, 0.32, 1.4))
	_obs(x, z, 0.85, h + 1.5)


func wall(x: float, z: float, length: float, hgt: float, yaw: float, broken := false) -> void:
	var dir := Vector3(cos(yaw), 0.0, -sin(yaw))
	var n := maxi(int(length / 0.95), 1)
	for i in range(n):
		var t := (float(i) + 0.5) / float(n) - 0.5
		var px := x + dir.x * t * length
		var pz := z + dir.z * t * length
		var hh := hgt
		if broken:
			hh = hgt * rng.randf_range(0.35, 1.0)
		var y0 := _gy(px, pz)
		_bx(Vector3(px, y0 + hh * 0.5 - 0.15, pz), Vector3(length / float(n) + 0.04, hh + 0.3, 0.85), Vector3(0.0, yaw, 0.0))
		if hh > hgt * 0.8:
			_bx(Vector3(px, y0 + hh + 0.08, pz), Vector3(length / float(n) + 0.18, 0.2, 1.0), Vector3(0.0, yaw, 0.0))
		_obs(px, pz, 0.65, hh + 0.2)


func arch_gate(x: float, z: float, yaw: float, span := 2.3, h := 5.2) -> void:
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var y0 := _gy(x, z)
	for s: float in [-1.0, 1.0]:
		var px := x + right.x * s * (span + 0.55)
		var pz := z + right.z * s * (span + 0.55)
		_bx(Vector3(px, y0 + h * 0.5, pz), Vector3(1.3, h, 1.3), Vector3(0.0, yaw, 0.0))
		_bx(Vector3(px, y0 + h + 0.15, pz), Vector3(1.5, 0.3, 1.5), Vector3(0.0, yaw, 0.0))
		_obs(px, pz, 0.95, h + 1.0)
	var seg := 11
	for k in range(seg):
		var a := PI * (float(k) + 0.5) / float(seg)
		var cx := cos(a) * (span + 0.05)
		var cyy := sin(a) * (span + 0.05) * 1.15
		var p := Vector3(x + right.x * cx, y0 + h + cyy, z + right.z * cx)
		var tilt := a - PI * 0.5
		var bs := Basis.from_euler(Vector3(0.0, yaw, 0.0)) * Basis(Vector3(0, 0, 1), -tilt)
		var mi := _bx(p, Vector3(0.95, 0.85, 1.25), Vector3.ZERO)
		mi.transform = Transform3D(bs, p)
	_bx(Vector3(x, y0 + h + (span + 0.05) * 1.15 + 0.35, z), Vector3(0.7, 0.9, 1.35), Vector3(0.0, yaw, 0.0))


func pedestal_statue(x: float, z: float) -> void:
	var y0 := _gy(x, z)
	_bx(Vector3(x, y0 + 0.35, z), Vector3(2.4, 0.7, 2.4))
	_bx(Vector3(x, y0 + 1.15, z), Vector3(1.8, 0.9, 1.8))
	_bx(Vector3(x, y0 + 1.7, z), Vector3(2.1, 0.22, 2.1))
	_cy(Vector3(x, y0 + 3.0, z), 0.32, 0.78, 2.5, Vector3.ZERO, null, 9)         # складки плаща
	_sp(Vector3(x, y0 + 4.45, z), 0.34, stone)
	_bx(Vector3(x, y0 + 3.9, z), Vector3(1.0, 0.35, 0.5))
	for s: float in [-1.0, 1.0]:
		_bx(Vector3(x + s * 0.95, y0 + 3.6, z - 0.28), Vector3(0.14, 2.4, 1.0), Vector3(0.0, 0.0, -s * 0.45))
	_bx(Vector3(x, y0 + 2.35, z + 0.55), Vector3(0.1, 2.0, 0.2), Vector3.ZERO)
	_obs(x, z, 1.5, 5.0)


func lamp(x: float, z: float, yaw: float) -> void:
	var y0 := _gy(x, z)
	_bx(Vector3(x, y0 + 0.3, z), Vector3(0.6, 0.6, 0.6))
	_cy(Vector3(x, y0 + 2.2, z), 0.06, 0.09, 3.8, Vector3.ZERO, iron, 6)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	_bx(Vector3(x + right.x * 0.4, y0 + 4.05, z + right.z * 0.4), Vector3(0.9, 0.07, 0.07), Vector3(0.0, yaw, 0.0), iron)
	var lp := Vector3(x + right.x * 0.78, y0 + 3.55, z + right.z * 0.78)
	_bx(lp, Vector3(0.36, 0.52, 0.36), Vector3(0.0, yaw, 0.0), lamp_glass, false)
	_cy(lp + Vector3(0, 0.38, 0), 0.0, 0.32, 0.26, Vector3.ZERO, iron, 4)
	_light(lp, Color(1.0, 0.66, 0.32), 2.6, 9.0)
	_obs(x, z, 0.35, 4.0)


func brazier(x: float, z: float) -> void:
	var y0 := _gy(x, z)
	_bx(Vector3(x, y0 + 0.5, z), Vector3(1.0, 1.0, 1.0))
	_cy(Vector3(x, y0 + 1.3, z), 0.62, 0.42, 0.55, Vector3.ZERO, null, 10)
	var f := _cy(Vector3(x, y0 + 1.95, z), 0.0, 0.40, 1.1, Vector3.ZERO, flame_mat, 7)
	f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_light(Vector3(x, y0 + 2.2, z), Color(0.7, 0.4, 1.0), 2.8, 8.0)
	_obs(x, z, 0.7, 2.0)


func crystals(x: float, z: float, s: float) -> void:
	var y0 := _gy(x, z)
	_sp(Vector3(x, y0 + 0.15 * s, z), 0.8 * s, stone, Vector3(1.0, 0.45, 1.0))
	for i in range(5):
		var a := TAU * float(i) / 5.0 + rng.randf()
		var rr := 0.35 * s * (0.4 if i == 0 else 1.0)
		var hh := s * rng.randf_range(1.2, 2.4) * (1.35 if i == 0 else 1.0)
		var tilt := 0.0 if i == 0 else rng.randf_range(0.15, 0.4)
		var p := Vector3(x + cos(a) * rr * (0.0 if i == 0 else 1.6), y0 + 0.3 * s + hh * 0.5, z + sin(a) * rr * (0.0 if i == 0 else 1.6))
		var mi := _cy(p, 0.0, 0.26 * s, hh, Vector3(sin(a) * tilt, 0.0, -cos(a) * tilt), crystal_mat, 6)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_light(Vector3(x, y0 + 1.4 * s, z), Color(0.6, 0.35, 1.0), 2.4, 7.0)
	_obs(x, z, 0.8 * s, 2.5)


func banner(x: float, z: float, yaw: float, tex_name: String) -> void:
	var y0 := _gy(x, z)
	_cy(Vector3(x, y0 + 2.4, z), 0.07, 0.10, 4.8, Vector3.ZERO, iron, 6)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	_bx(Vector3(x, y0 + 4.5, z), Vector3(1.5, 0.08, 0.08), Vector3(0.0, yaw, 0.0), iron)
	if not banner_mats.has(tex_name):
		var m := StandardMaterial3D.new()
		m.albedo_texture = load("res://sprites/%s.png" % tex_name)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = 1.0
		m.emission_enabled = true
		m.emission_texture = m.albedo_texture
		m.emission_energy_multiplier = 0.25
		banner_mats[tex_name] = m
	var q := QuadMesh.new()
	q.size = Vector2(1.25, 2.9)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = banner_mats[tex_name]
	mi.transform = Transform3D(Basis.from_euler(Vector3(0.0, yaw, 0.0)), Vector3(x, y0 + 3.0, z))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_obs(x, z, 0.3, 4.0)


func broadleaf(x: float, z: float, s: float, purple: bool) -> void:
	var y0 := _gy(x, z)
	_cy(Vector3(x, y0 + 2.2 * s, z), 0.30 * s, 0.62 * s, 4.4 * s, Vector3(0.0, 0.0, rng.randf_range(-0.08, 0.08)), bark, 7)
	var lm := ShaderMaterial.new()
	lm.shader = load("res://leaf.gdshader")
	if purple:
		lm.set_shader_parameter("base_col", Color(0.20, 0.07, 0.38))
		lm.set_shader_parameter("hi_col", Color(0.62, 0.30, 0.95))
	else:
		lm.set_shader_parameter("base_col", Color(0.06, 0.18, 0.09))
		lm.set_shader_parameter("hi_col", Color(0.34, 0.45, 0.12))
	for i in range(6):
		var a := TAU * float(i) / 6.0 + rng.randf()
		var rr := (1.5 if i > 0 else 0.0) * s
		var p := Vector3(x + cos(a) * rr, y0 + (5.2 + rng.randf_range(-0.3, 1.6)) * s, z + sin(a) * rr)
		_sp(p, rng.randf_range(1.5, 2.2) * s, lm, Vector3(1.0, 0.8, 1.0)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_obs(x, z, 0.75 * s, 7.0)


# ---------------------------------------------------------------- мост (ось вдоль Z, центр на ручье)
func bridge() -> void:
	var bx := Valley.BRIDGE_X
	var bz := Valley.STREAM_Z
	var W := 3.4
	var step := 0.5
	var u := -5.9 + step * 0.5
	while u < 5.9:
		var au := absf(u)
		var top := valley.bridge_h(bx, bz + u)
		if au > Valley.BR_HALF_U:
			break
		var topy := maxf(top, 0.0)
		if au <= 2.5:
			var k := au / 2.5
			var y_in := 1.55 * sqrt(maxf(1.0 - k * k, 0.0))
			var y_out := y_in + 0.6
			var slope := 0.0
			if au > 0.001:
				slope = -(1.55 * k / maxf(sqrt(maxf(1.0 - k * k, 0.02)), 0.14)) / 2.5 * signf(u)
			var ang := atan(slope)
			_bx(Vector3(bx, (y_in + y_out) * 0.5, bz + u), Vector3(W, 0.6, step + 0.12), Vector3(-ang, 0.0, 0.0))
			var th := topy + 0.15 - y_out
			if th > 0.05:
				_bx(Vector3(bx, y_out + th * 0.5 - 0.1, bz + u), Vector3(W, th, step + 0.04))
		elif au <= 3.4:
			_bx(Vector3(bx, (topy - 1.0) * 0.5, bz + u), Vector3(W, topy + 1.0, step + 0.04))
		else:
			# лестница: ступени
			var sh := floorf(topy / 0.33) * 0.33 + 0.12
			_bx(Vector3(bx, (sh - 1.0) * 0.5, bz + u), Vector3(W - 0.9, sh + 1.0, step + 0.02))
			for sd: float in [-1.0, 1.0]:
				_bx(Vector3(bx + sd * (W * 0.5 - 0.2), (sh - 0.1) * 0.5, bz + u), Vector3(0.45, sh + 1.9, step + 0.04))
		u += step
	# поручни и столбы
	for sd: float in [-1.0, 1.0]:
		var vx := bx + sd * 1.4
		var uu := -3.3
		while uu <= 3.3 + 0.01:
			var y := valley.bridge_h(bx, bz + uu) + 0.15
			_cy(Vector3(vx, y + 0.42, bz + uu), 0.09, 0.12, 0.85, Vector3.ZERO, null, 6)
			uu += 0.55
		var u1 := -3.3
		while u1 < 3.3:
			var ya := valley.bridge_h(bx, bz + u1) + 0.15
			var yb := valley.bridge_h(bx, bz + u1 + 0.55) + 0.15
			var ln := Vector2(0.55, yb - ya).length()
			var ang2 := atan2(yb - ya, 0.55)
			_bx(Vector3(vx, (ya + yb) * 0.5 + 0.9, bz + u1 + 0.275), Vector3(0.22, 0.16, ln + 0.05), Vector3(-ang2, 0.0, 0.0))
			u1 += 0.55
		for e: float in [-1.0, 1.0]:
			var pz := bz + e * 3.3
			var py := valley.bridge_h(bx, pz) + 0.15
			_bx(Vector3(vx, py + 0.75, pz), Vector3(0.6, 1.5, 0.6))
			_bx(Vector3(vx, py + 1.6, pz), Vector3(0.75, 0.2, 0.75))
	# фонари и баннеры на столбах, наружу от моста
	for sd: float in [-1.0, 1.0]:
		for e: float in [-1.0, 1.0]:
			var pz2 := bz + e * 3.3
			var py2 := valley.bridge_h(bx, pz2) + 0.15
			var vx2 := bx + sd * 1.4
			_cy(Vector3(vx2 + sd * 0.55, py2 + 2.3, pz2), 0.06, 0.08, 4.6, Vector3.ZERO, iron, 6)
			_bx(Vector3(vx2 + sd * 0.8, py2 + 4.5, pz2), Vector3(0.7, 0.07, 0.07), Vector3.ZERO, iron)
			var lp := Vector3(vx2 + sd * 1.05, py2 + 4.0, pz2)
			_bx(lp, Vector3(0.36, 0.5, 0.36), Vector3.ZERO, lamp_glass, false)
			_light(lp, Color(1.0, 0.66, 0.32), 2.4, 8.0)
	# вода
	var water := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(90.0, 6.0)
	water.mesh = qm
	var wm := ShaderMaterial.new()
	wm.shader = load("res://water.gdshader")
	water.material_override = wm
	water.transform = Transform3D(Basis.from_euler(Vector3(-PI * 0.5, 0.0, 0.0)), Vector3(0.0, -0.40, bz))
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	# непроходимая вода, кроме проезда моста
	var xx := -28.0
	while xx <= 28.0:
		if absf(xx - bx) > 3.0:
			_obs(xx, bz, 1.0, 1.0)
			_obs(xx, bz - 0.9, 0.9, 1.0)
			_obs(xx, bz + 0.9, 0.9, 1.0)
		xx += 1.0


# ---------------------------------------------------------------- композиция двора
func build(v: Valley) -> void:
	valley = v
	rng.seed = 2024
	_ready_mats()
	var c := Valley.RING_C
	bridge()
	# святилище за мостом
	arch_gate(0.0, -24.2, 0.0, 2.6, 5.6)
	for s: float in [-1.0, 1.0]:
		wall(s * 9.5, -24.0, 12.0, 4.2, 0.0, true)
	pedestal_statue(c.x - 11.5, c.y + 1.5)
	pedestal_statue(c.x + 11.5, c.y + 1.5)
	for s: float in [-1.0, 1.0]:
		brazier(s * 3.6, -21.0)
	# колонны полукругом у площадки
	for k in range(8):
		var a := PI * 0.12 + PI * 0.76 * float(k) / 7.0
		var x := c.x + cos(a) * 14.0
		var z := c.y + 4.5 - sin(a) * 6.0
		if valley.is_free(x, z, 0.8) and Vector2(x, z).distance_to(Vector2(0.0, 5.0)) > 3.0:
			column(x, z, 5.4, k % 3 == 1)
	# колонны по бокам двора и на «юге»
	for p in [Vector2(-16.0, 9.0), Vector2(16.0, 9.0), Vector2(-20.0, -4.0), Vector2(20.0, -4.0), Vector2(-9.0, 20.0), Vector2(9.0, 20.0)]:
		if valley.is_free(p.x, p.y, 0.8):
			column(p.x, p.y, 5.0, rng.randf() < 0.4)
	# руины стен по кольцу
	var wl := [[-18.0, 14.0, 7.0, 0.5, true], [18.0, 13.0, 8.0, -0.5, true], [-22.0, -10.0, 6.0, 1.45, true], [22.0, -9.0, 6.0, 1.7, true],
		[-13.0, 22.0, 7.0, 0.2, true], [14.0, 22.0, 7.0, -0.3, true]]
	for w in wl:
		if valley.is_free(float(w[0]), float(w[1]), 0.7):
			wall(float(w[0]), float(w[1]), float(w[2]), 3.4, float(w[3]), w[4])
	# фонари и баннеры
	for k in range(6):
		var a := TAU * float(k) / 6.0 + 0.45
		var x := c.x + cos(a) * 9.8
		var z := c.y + sin(a) * 9.8
		if valley.is_free(x, z, 0.6) and absf(z - Valley.STREAM_Z) > 3.5 and Vector2(x, z).distance_to(Vector2(0.0, 5.0)) > 3.0:
			lamp(x, z, a)
	for p in [Vector2(-6.0, 12.0), Vector2(6.0, 12.0), Vector2(-14.0, -12.0), Vector2(14.0, -12.0)]:
		if valley.is_free(p.x, p.y, 0.5):
			banner(p.x, p.y, 0.0, "banner_b")
	# кристаллы
	for p in [Vector2(-9.0, 9.0), Vector2(10.0, 8.0), Vector2(-15.0, -7.0), Vector2(15.0, -9.0), Vector2(5.0, 17.0)]:
		if valley.is_free(p.x, p.y, 1.0):
			crystals(p.x, p.y, 1.3)
	# валуны группами по краю
	var bm: Array[ArrayMesh] = [valley._mesh_boulder(1), valley._mesh_boulder(2), valley._mesh_boulder(3)]
	var bxf: Array = [[], [], []]
	var bcu: Array = [[], [], []]
	for q in range(26):
		var a := rng.randf() * TAU
		var r := rng.randf_range(14.0, Valley.ARENA - 1.5)
		var x := cos(a) * r
		var z := sin(a) * r
		if not valley.is_free(x, z, 1.6) or absf(z - Valley.STREAM_Z) < 4.0:
			continue
		var s := rng.randf_range(0.9, 2.2)
		var k := rng.randi() % 3
		var bs := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.1), s))
		(bxf[k] as Array).append(Transform3D(bs, Vector3(x, _gy(x, z) + 0.1 * s, z)))
		(bcu[k] as Array).append(valley._tint(0.85, 1.1))
		valley.add_obstacle(x, z, 1.0 * s, 1.5 * s)
	for i in range(3):
		valley._mm(bm[i], valley.mat_rigid, bxf[i], bcu[i], true)
	# лес по краю: широколиственные, ели, сухие
	var sxf: Array = []
	var scu: Array = []
	var dxf: Array = []
	var dcu: Array = []
	var spruce := valley._mesh_spruce(7, 1.7, 13.0, 9, Color(0.080, 0.060, 0.055))
	var dead := valley._mesh_dead(9.0)
	for i in range(130):
		var a := rng.randf() * TAU
		var r := rng.randf_range(Valley.ARENA - 2.5, Valley.ARENA + 14.0)
		var x := cos(a) * r
		var z := sin(a) * r
		if not valley.is_free(x, z, 1.4) or absf(z - Valley.STREAM_Z) < 3.5:
			continue
		var roll := rng.randf()
		if roll < 0.38:
			broadleaf(x, z, rng.randf_range(1.1, 1.7), rng.randf() < 0.4)
		elif roll < 0.85:
			var s := rng.randf_range(0.8, 1.3)
			sxf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(x, _gy(x, z) - 0.1, z)))
			scu.append(valley._tint(0.9, 1.15))
			valley.add_obstacle(x, z, 0.7 * s, 12.0)
		else:
			var s2 := rng.randf_range(0.8, 1.2)
			dxf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s2, s2, s2)), Vector3(x, _gy(x, z) - 0.1, z)))
			dcu.append(valley._tint(0.9, 1.1))
			valley.add_obstacle(x, z, 0.6 * s2, 8.0)
	valley._mm(spruce, valley.mat_tree, sxf, scu, true)
	valley._mm(dead, valley.mat_tree, dxf, dcu, true)
