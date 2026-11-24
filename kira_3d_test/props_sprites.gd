class_name PropSprites
extends Node3D
## Длинный мост над пропастью к замку. Настил, парапеты, опоры, площадка - простая 3D-геометрия с камнем из шейдера;
## врата замка, колонны, статуи, знамёна, острова и деревья - спрайты из листов пользователя (камера ортографическая).

const COS_P := 0.81                     # cos(питча камеры 36 градусов)
const BR_W := 3.4                       # полуширина настила
const Z_N := -34.2                      # север моста / начало площадки замка
const Z_S := 35.2                       # сломанный южный конец
const PL_X := 15.0                      # полуширина площадки
const PL_Z := -44.6                     # задний край площадки
const GATE_Z := -44.2

var valley: Valley
var rng := RandomNumberGenerator.new()
var _mats := {}
var _glow_tex: GradientTexture2D
var _sh_tex: GradientTexture2D
var _mist_tex: GradientTexture2D
var lights := 0
var stone: ShaderMaterial
var stone_fade: ShaderMaterial
var iron: StandardMaterial3D
var lamp_glass: StandardMaterial3D


func _mat(name: String, dim := 1.0) -> StandardMaterial3D:
	var key := name + str(dim)
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = load("res://sp/%s.png" % name)
	m.albedo_color = Color(0.80, 0.82, 1.0) * dim
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.45
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


func _shadow(p: Vector2, r: float, a: float, y := 0.03) -> void:
	if _sh_tex == null:
		_sh_tex = GradientTexture2D.new()
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 1))
		g.set_color(1, Color(0, 0, 0, 0))
		_sh_tex.gradient = g
		_sh_tex.fill = GradientTexture2D.FILL_RADIAL
		_sh_tex.fill_from = Vector2(0.5, 0.5)
		_sh_tex.fill_to = Vector2(1.0, 0.5)
		_sh_tex.width = 64
		_sh_tex.height = 64
	var s := Sprite3D.new()
	s.texture = _sh_tex
	s.axis = Vector3.AXIS_Y
	s.shaded = false
	s.transparent = true
	s.modulate = Color(0, 0, 0, a)
	s.pixel_size = r * 2.0 / 64.0
	s.position = Vector3(p.x, y, p.y)
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(s)


## Спрайт основанием в точку мира (x, z), по высоте y0. hgt - высота на экране в метрах.
## solid > 0 - непроходимый (доля ширины спрайта вдоль оси x, занятая основанием)
func put(name: String, x: float, z: float, hgt := 3.0, solid := 0.0, flip := false, y0 := 0.0, dim := 1.0) -> Vector2:
	var tex: Texture2D = load("res://sp/%s.png" % name)
	if tex == null:
		return Vector2.ZERO
	var h := hgt
	var w := float(tex.get_width()) / float(tex.get_height()) * hgt
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	q.center_offset = Vector3(0.0, h * 0.5 - 0.05 * h, 0.0)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = _mat(name, dim)
	mi.position = Vector3(x, y0, z)
	if flip:
		mi.scale = Vector3(-1.0, 1.0, 1.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	if solid > 0.0:
		var span := w * solid
		var n := maxi(int(ceil(span / 2.2)), 1)
		var rr := clampf(span / float(n) * 0.55, 0.35, 1.4)
		for k in range(n):
			var off := ((float(k) + 0.5) / float(n) - 0.5) * (span - rr * 2.0 if n > 1 else 0.0)
			valley.add_obstacle(x + off, z, rr, h)
		_shadow(Vector2(x, z), minf(w * 0.45, 3.2), 0.5)
	return Vector2(w, h)


func glow(x: float, y: float, z: float, col: Color, size: float, energy: float, range_m: float, light := true) -> void:
	if _glow_tex == null:
		_glow_tex = GradientTexture2D.new()
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_glow_tex.gradient = g
		_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.5)
		_glow_tex.fill_to = Vector2(1.0, 0.5)
		_glow_tex.width = 128
		_glow_tex.height = 128
	var s := Sprite3D.new()
	s.texture = _glow_tex
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.transparent = true
	s.modulate = Color(col.r, col.g, col.b, 0.5)
	s.material_override = _glow_mat()
	s.pixel_size = size / 128.0
	s.position = Vector3(x, y, z)
	add_child(s)
	if not light or lights >= 12:
		return
	lights += 1
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = range_m
	l.omni_attenuation = 1.3
	l.position = s.position + Vector3(0.0, 0.6, 0.0)
	add_child(l)


func _glow_mat() -> StandardMaterial3D:
	if _mats.has("_glow"):
		return _mats["_glow"]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = _glow_tex
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = false
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["_glow"] = m
	return m


## свечение на доле высоты спрайта f (0 низ, 1 верх)
func _lit(x: float, z: float, hgt: float, f: float, col: Color, size: float, energy: float, rng_m: float, light := true, y0 := 0.0) -> void:
	glow(x, y0 + hgt * f / COS_P, z, col, size, energy, rng_m, light)


# ---------------------------------------------------------------- простая 3D-геометрия
func _bx(pos: Vector3, size: Vector3, mat: Material = null, shadow := true) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat if mat != null else stone
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _cy(pos: Vector3, r_top: float, r_bot: float, h: float, mat: Material, sides := 6) -> void:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bot
	m.height = h
	m.radial_segments = sides
	m.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	add_child(mi)


func _fence(x0: float, z0: float, x1: float, z1: float, r := 0.7, step := 1.2) -> void:
	var d := Vector2(x1 - x0, z1 - z0)
	var n := maxi(int(d.length() / step), 1)
	for k in range(n + 1):
		var t := float(k) / float(n)
		valley.add_obstacle(x0 + d.x * t, z0 + d.y * t, r, 6.0)


func _mats_init() -> void:
	stone = ShaderMaterial.new()
	stone.shader = load("res://stone.gdshader")
	stone.set_shader_parameter("slab_tex", load("res://sprites/floor_atlas.png"))
	stone_fade = ShaderMaterial.new()
	stone_fade.shader = load("res://stone_fade.gdshader")
	stone_fade.set_shader_parameter("slab_tex", load("res://sprites/floor_atlas.png"))
	iron = StandardMaterial3D.new()
	iron.albedo_color = Color(0.10, 0.09, 0.13)
	iron.roughness = 0.6
	iron.metallic = 0.5
	lamp_glass = StandardMaterial3D.new()
	lamp_glass.albedo_color = Color(1.0, 0.7, 0.3)
	lamp_glass.emission_enabled = true
	lamp_glass.emission = Color(1.0, 0.62, 0.22)
	lamp_glass.emission_energy_multiplier = 3.2


func _lantern(x: float, z: float, base_y: float, light: bool) -> void:
	_cy(Vector3(x, base_y + 0.55, z), 0.05, 0.07, 1.1, iron)
	_bx(Vector3(x, base_y + 1.35, z), Vector3(0.36, 0.5, 0.36), lamp_glass, false)
	_cy(Vector3(x, base_y + 1.72, z), 0.0, 0.34, 0.26, iron, 4)
	glow(x, base_y + 1.35, z, Color(1.0, 0.68, 0.30), 2.0, 0.0, 1.0, false)
	if light:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.66, 0.32)
		l.light_energy = 2.8
		l.omni_range = 11.0
		l.omni_attenuation = 1.3
		l.position = Vector3(x, base_y + 1.5, z)
		add_child(l)


func _bridge() -> void:
	var zc := (Z_N + Z_S) * 0.5
	var zl := Z_S - Z_N
	for s: float in [-1.0, 1.0]:
		# парапет и карниз
		_bx(Vector3(s * 3.15, 0.52, zc), Vector3(0.55, 1.04, zl))
		_bx(Vector3(s * 3.15, 1.14, zc), Vector3(0.85, 0.2, zl))
		# боковая стена с арками (видна с камеры стороны +x, остальная скрыта настилом)
		var q := QuadMesh.new()
		q.size = Vector2(zl + 1.0, 17.0)
		var fm := ShaderMaterial.new()
		fm.shader = load("res://bridge_face.gdshader")
		fm.set_shader_parameter("slab_tex", load("res://sprites/floor_atlas.png"))
		fm.set_shader_parameter("zend", Z_S)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = fm
		mi.transform = Transform3D(Basis.from_euler(Vector3(0.0, -s * PI * 0.5, 0.0)), Vector3(s * BR_W, -8.5, zc))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	# столбы с фонарями
	var zs := [31.0, 23.0, 15.0, 7.0, -1.0, -9.0, -17.0, -25.0, -32.0]
	for i in range(zs.size()):
		for s: float in [-1.0, 1.0]:
			var z: float = zs[i]
			_bx(Vector3(s * 3.15, 0.95, z), Vector3(1.0, 1.9, 1.0))
			_bx(Vector3(s * 3.15, 2.02, z), Vector3(1.25, 0.24, 1.25))
			var on := (s > 0.0 and i % 3 == 0) or (s < 0.0 and i % 3 == 1)
			_lantern(s * 3.15, z, 2.14, on)
	# препятствия: края настила и сломанный конец
	_fence(3.15, Z_N, 3.15, Z_S - 0.6)
	_fence(-3.15, Z_N, -3.15, Z_S - 0.6)
	_fence(-3.0, Z_S - 0.2, 3.0, Z_S - 0.2)
	# дно пропасти
	var ab := MeshInstance3D.new()
	var aq := QuadMesh.new()
	aq.size = Vector2(700.0, 700.0)
	ab.mesh = aq
	var am := ShaderMaterial.new()
	am.shader = load("res://abyss.gdshader")
	ab.material_override = am
	ab.transform = Transform3D(Basis.from_euler(Vector3(-PI * 0.5, 0.0, 0.0)), Vector3(0.0, -26.0, -10.0))
	ab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ab)


func _platform() -> void:
	# скала под площадкой
	_bx(Vector3(0.0, -13.0, (Z_N + PL_Z) * 0.5), Vector3(PL_X * 2.0, 26.0, Z_N - PL_Z), stone_fade)
	var zc := (Z_N + PL_Z) * 0.5
	var zl := Z_N - PL_Z
	# парапет по краям площадки
	for s: float in [-1.0, 1.0]:
		_bx(Vector3(s * (PL_X - 0.3), 0.52, zc), Vector3(0.55, 1.04, zl))
		_bx(Vector3(s * (PL_X - 0.3), 1.14, zc), Vector3(0.85, 0.2, zl))
		var wlen := PL_X - BR_W - 0.3
		_bx(Vector3(s * (BR_W + wlen * 0.5 + 0.15), 0.52, Z_N + 0.3), Vector3(wlen, 1.04, 0.55))
		_bx(Vector3(s * (BR_W + wlen * 0.5 + 0.15), 1.14, Z_N + 0.3), Vector3(wlen + 0.3, 0.2, 0.85))
	_fence(-PL_X + 0.4, Z_N + 0.3, -BR_W, Z_N + 0.3)
	_fence(BR_W, Z_N + 0.3, PL_X - 0.4, Z_N + 0.3)
	_fence(-PL_X + 0.4, Z_N + 0.3, -PL_X + 0.4, PL_Z + 0.6)
	_fence(PL_X - 0.4, Z_N + 0.3, PL_X - 0.4, PL_Z + 0.6)
	_fence(-PL_X, PL_Z + 0.5, PL_X, PL_Z + 0.5)


func _mist() -> void:
	if _mist_tex == null:
		_mist_tex = GradientTexture2D.new()
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_mist_tex.gradient = g
		_mist_tex.fill = GradientTexture2D.FILL_RADIAL
		_mist_tex.fill_from = Vector2(0.5, 0.5)
		_mist_tex.fill_to = Vector2(1.0, 0.5)
		_mist_tex.width = 128
		_mist_tex.height = 128
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = _mist_tex
	m.albedo_color = Color(0.42, 0.34, 0.66, 0.34)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var z := Z_S + 6.0
	while z > PL_Z - 8.0:
		for s: float in [-1.0, 1.0]:
			var sp := Sprite3D.new()
			sp.texture = _mist_tex
			sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sp.shaded = false
			sp.transparent = true
			sp.modulate = Color(0.46, 0.38, 0.72, rng.randf_range(0.20, 0.34))
			sp.pixel_size = rng.randf_range(13.0, 20.0) / 128.0
			sp.position = Vector3(s * rng.randf_range(7.0, 16.0), rng.randf_range(-9.0, -3.5), z + rng.randf_range(-3.0, 3.0))
			add_child(sp)
		z -= rng.randf_range(5.0, 8.0)


func build(v: Valley) -> void:
	valley = v
	rng.seed = 777
	_mats_init()
	var amber := Color(1.0, 0.68, 0.30)
	var violet := Color(0.62, 0.38, 1.0)
	_bridge()
	_platform()

	# ===== замок: врата, стены с башнями, колонны, знамёна, жаровни, статуи
	var gate := put("gate_arch1", 0.0, GATE_Z, 10.5, 0.0)
	_lit(0.0, GATE_Z + 0.3, gate.y, 0.30, violet, 6.0, 2.6, 12.0)
	_wall_run(GATE_Z - 0.2, -1.0, -gate.x * 0.5 + 0.9, [["wall_win", 5.4], ["wall_tall", 8.8]])
	_wall_run(GATE_Z - 0.2, 1.0, gate.x * 0.5 - 0.9, [["wall_win", 5.4], ["wall_tall", 8.8]])
	put("col_a", -5.4, -36.6, 6.2, 0.5)
	put("col_b", 5.4, -36.6, 6.2, 0.5, true)
	put("banner_a", -3.3, -40.6, 5.2, 0.3)
	put("banner_b", 3.3, -40.6, 5.2, 0.3, true)
	var br := put("brazier_p", -2.5, -38.4, 3.0, 0.7)
	put("brazier_p", 2.5, -38.4, 3.0, 0.7)
	for s: float in [-1.0, 1.0]:
		_lit(s * 2.5, -38.4, br.y, 0.82, violet, 2.6, 2.4, 9.0)
	put("statue_angel", -9.6, -40.0, 4.8, 0.6)
	put("statue_hood", 9.6, -40.0, 4.8, 0.6)
	var comp := Sprite3D.new()
	comp.texture = load("res://sprites/compass.png")
	comp.axis = Vector3.AXIS_Y
	comp.pixel_size = 9.0 / float(comp.texture.get_width())
	comp.position = Vector3(0.0, 0.05, -39.2)
	comp.shaded = false
	comp.transparent = true
	comp.modulate = Color(0.8, 0.8, 1.0, 0.5)
	add_child(comp)
	# громада замка за стенами
	put("wall_arch", -3.0, -50.0, 12.5, 0.0, false, 0.0, 0.75)
	put("wall_tall", 9.5, -49.0, 14.0, 0.0, true, 0.0, 0.75)
	put("wall_win", -14.0, -48.5, 10.5, 0.0, false, 0.0, 0.75)
	put("wall_tall", -21.0, -52.0, 15.0, 0.0, false, 0.0, 0.7)
	put("wall_win", 20.0, -52.0, 11.0, 0.0, true, 0.0, 0.7)
	put("wall_arch", 28.0, -56.0, 14.0, 0.0, false, 0.0, 0.65)

	# ===== сломанный южный конец моста
	put("rubble_a", -1.8, 33.6, 2.4, 0.0)
	put("rubble_b", 1.7, 33.0, 2.2, 0.0, true)
	put("col_ruin", -2.2, 30.6, 3.4, 0.0, false)
	put("rock_a", 0.4, 34.6, 1.2, 0.0)

	# ===== парящие острова и кристаллы по краям пропасти
	var isl := [[-17.0, 20.0, -7.0, "tree_purple", 8.5], [19.0, 8.0, -9.0, "tree_white", 8.0], [-21.0, -6.0, -11.0, "tree_dead", 9.0], [22.0, -22.0, -8.0, "tree_purple", 8.0],
		[-15.0, -26.0, -9.0, "pine_a", 10.0], [17.0, 30.0, -10.0, "pine_b", 9.0], [-26.0, 32.0, -13.0, "tree_g", 8.0]]
	for it in isl:
		var rh := 6.0 + rng.randf() * 2.0
		put("rock_big", float(it[0]), float(it[1]), rh, 0.0, rng.randf() < 0.5, float(it[2]), 0.85)
		put(str(it[3]), float(it[0]) + 0.2, float(it[1]), float(it[4]), 0.0, rng.randf() < 0.5, float(it[2]) + rh * 0.52 / COS_P, 0.85)
	for p in [Vector3(-6.2, -2.0, 19.0), Vector3(6.6, -2.5, 3.0), Vector3(-6.4, -2.0, -12.0), Vector3(6.4, -2.2, -26.0), Vector3(-7.0, -3.0, 28.0)]:
		var cs := put("crystal_b" if int(p.z) % 2 == 0 else "crystal_a", p.x, p.z, 3.4, 0.0, false, p.y, 0.95)
		_lit(p.x, p.z, cs.y, 0.45, violet, 3.0, 0.0, 1.0, false, p.y)
	_mist()


func _aspect(name: String) -> float:
	var tex: Texture2D = load("res://sp/%s.png" % name)
	return float(tex.get_width()) / float(tex.get_height())


## ряд стен вдоль оси x: от start наружу (dirn -1 влево, +1 вправо); справа спрайты зеркалятся
func _wall_run(z: float, dirn: float, start: float, seq: Array) -> void:
	var x := start
	var i := 0
	for it in seq:
		var nm: String = it[0]
		var hh: float = it[1]
		var w := _aspect(nm) * hh
		put(nm, x + dirn * w * 0.5, z + 0.04 * float(i), hh, 0.9, dirn > 0.0)
		x += dirn * (w - 0.8)
		i += 1
