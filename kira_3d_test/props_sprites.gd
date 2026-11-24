class_name PropSprites
extends Node3D
## Двор руин в изометрии: арт из листов пользователя как спрайты. Камера ортографическая, поэтому полные
## биллборды работают как настоящая 2D-сортировка (кто ниже на экране - тот ближе). Кира остаётся живой 3D между ними.
## Координаты раскладки - экранные: sx вправо, sy вверх по экрану (метры на земле).

const PPM := 69.0                       # пикселей арта на метр (листы увеличены в 1.5 раза)
const R := Vector2(0.70711, -0.70711)   # экранное "вправо" в мире (x, z) при yaw 45
const U := Vector2(-0.70711, -0.70711)  # экранное "вверх"
const COS_P := 0.84

var valley: Valley
var rng := RandomNumberGenerator.new()
var _mats := {}
var _glow_tex: GradientTexture2D
var _sh_tex: GradientTexture2D
var lights := 0


func _w(sx: float, sy: float) -> Vector2:
	return R * sx + U * sy


func _mat(name: String) -> StandardMaterial3D:
	if _mats.has(name):
		return _mats[name]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = load("res://sp/%s.png" % name)
	m.albedo_color = Color(0.80, 0.82, 1.0)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.45
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[name] = m
	return m


func _shadow(p: Vector2, r: float, a: float) -> void:
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
	s.position = Vector3(p.x, 0.03, p.y)
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(s)


## Ставит спрайт основанием в точку (sx, sy). Возвращает размер в метрах (w, h).
## solid > 0 - непроходимый (число = доля ширины, которую занимает основание).
func put(name: String, sx: float, sy: float, mul := 1.0, solid := 0.0, flip := false) -> Vector2:
	var tex: Texture2D = load("res://sp/%s.png" % name)
	if tex == null:
		return Vector2.ZERO
	var h := float(tex.get_height()) / PPM * mul
	var w := float(tex.get_width()) / PPM * mul
	var p := _w(sx, sy)
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	q.center_offset = Vector3(0.0, h * 0.5 - 0.05 * h, 0.0)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = _mat(name)
	mi.position = Vector3(p.x, 0.0, p.y)
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
			var po := _w(sx + off, sy)
			valley.add_obstacle(po.x, po.y, rr, h)
		_shadow(p, minf(w * 0.45, 3.2), 0.5)
	return Vector2(w, h)


## мягкое свечение (аддитивный круг) + источник света. y - высота над землёй в мире
func glow(sx: float, sy: float, y: float, col: Color, size: float, energy: float, range_m: float, light := true) -> void:
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
	var p := _w(sx, sy)
	var s := Sprite3D.new()
	s.texture = _glow_tex
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.transparent = true
	s.modulate = Color(col.r, col.g, col.b, 0.5)
	s.material_override = _glow_mat()
	s.pixel_size = size / 128.0
	s.position = Vector3(p.x, y, p.y)
	add_child(s)
	if not light or lights >= 13:
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
func _lit(sx: float, sy: float, hgt: float, f: float, col: Color, size: float, energy: float, rng_m: float, light := true) -> void:
	glow(sx, sy, hgt * f / COS_P, col, size, energy, rng_m, light)


func build(v: Valley) -> void:
	valley = v
	rng.seed = 777
	var amber := Color(1.0, 0.68, 0.30)
	var violet := Color(0.62, 0.38, 1.0)
	# --- пол: руна под ногами
	var comp := Sprite3D.new()
	comp.texture = load("res://sprites/compass.png")
	comp.axis = Vector3.AXIS_Y
	comp.pixel_size = 10.0 / float(comp.texture.get_width())
	comp.position = Vector3(0.0, 0.04, 0.0)
	comp.shaded = false
	comp.transparent = true
	comp.modulate = Color(0.8, 0.8, 1.0, 0.55)
	add_child(comp)

	# --- задняя линия: врата, колонны, стены, знамёна
	var g := put("gate_arch1", 0.0, 18.0, 2.1, 0.62)
	put("col_a", -8.5, 15.5, 1.55, 0.5)
	put("col_b", 8.5, 15.5, 1.55, 0.5)
	put("col_d", -13.0, 14.5, 1.5, 0.5)
	put("col_c", 13.0, 14.5, 1.5, 0.5)
	put("wall_win", -18.5, 15.5, 1.6, 0.8)
	put("wall_tall", 19.0, 15.0, 1.6, 0.7)
	put("wall_long", -25.0, 10.0, 1.4, 0.8)
	put("wall_arch", 25.0, 9.5, 1.6, 0.7)
	var b1 := put("banner_a", -5.2, 13.2, 1.5, 0.3)
	put("banner_b", 5.2, 13.2, 1.5, 0.3)
	var br := put("brazier_p", -3.4, 11.0, 1.35, 0.6)
	put("brazier_p", 3.4, 11.0, 1.35, 0.6)
	for s: float in [-1.0, 1.0]:
		_lit(s * 3.4, 11.0, br.y, 0.82, violet, 2.6, 2.4, 9.0)
	_lit(0.0, 18.0, g.y, 0.35, violet, 5.5, 2.6, 11.0)

	# --- средняя линия: статуи, святилище, кристаллы, фонари
	put("statue_angel", -10.5, 8.0, 1.7, 0.6)
	put("statue_hood", 10.5, 8.0, 1.7, 0.6)
	put("shrine", 19.0, 5.5, 1.5, 0.55)
	_lit(19.0, 5.5, 231.0 / PPM * 1.5, 0.5, violet, 4.0, 2.2, 9.0)
	var ca := put("crystal_a", -16.5, 3.0, 1.5, 0.5)
	_lit(-16.5, 3.0, ca.y, 0.45, violet, 3.2, 2.4, 9.0)
	var cb := put("crystal_c", 15.0, -3.5, 1.5, 0.5)
	_lit(15.0, -3.5, cb.y, 0.45, violet, 3.2, 2.2, 9.0)
	put("crystal_b", -12.5, -10.0, 1.4, 0.5)
	_lit(-12.5, -10.0, 172.0 / PPM * 1.4, 0.45, violet, 3.0, 0.0, 1.0, false)
	for p in [Vector2(-7.5, 4.0), Vector2(7.5, 4.0), Vector2(-9.5, -5.0), Vector2(9.5, -6.0)]:
		var lh := put("lamp_a" if p.x < 0.0 else "lamp_c", p.x, p.y, 1.55, 0.2)
		_lit(p.x, p.y, lh.y, 0.74, amber, 2.4, 2.6, 10.0)
	put("ped_crystal", -6.5, -14.0, 1.5, 0.6)
	put("ped_crystal", 6.5, -14.0, 1.5, 0.6)
	_lit(-6.5, -14.0, 171.0 / PPM * 1.5, 0.8, violet, 2.2, 0.0, 1.0, false)
	_lit(6.5, -14.0, 171.0 / PPM * 1.5, 0.8, violet, 2.2, 0.0, 1.0, false)

	# --- колонны и руины по бокам и спереди
	put("col_c", -14.5, -2.0, 1.55, 0.5)
	put("col_d", 15.0, 1.0, 1.55, 0.5)
	put("col_a", -11.0, -10.5, 1.55, 0.5)
	put("col_b", 11.5, -11.0, 1.55, 0.5)
	put("col_ruin", -19.5, -5.0, 1.5, 0.5)
	put("col_a", 19.5, -7.0, 1.55, 0.5)
	put("wall_rub", -21.0, -12.0, 1.5, 0.8)
	put("wall_rub", 21.0, -14.0, 1.5, 0.8)
	put("banner_c", -14.0, -14.5, 1.5, 0.3)
	put("banner_c", 14.0, -15.5, 1.5, 0.3)
	put("orrery", -18.0, 10.5, 1.5, 0.5)
	put("wheel", 14.5, 11.0, 1.5, 0.5)
	put("cage", 20.0, -2.0, 1.5, 0.4)
	put("tower", -22.0, -2.0, 1.5, 0.5)
	put("pond", 3.5, -19.0, 1.4, 0.9)
	put("waterfall", -3.0, 22.0, 1.5, 0.8)
	put("balust", 0.0, 9.0, 1.2, 0.0)
	put("window_arch", 10.0, 19.5, 1.6, 0.6)

	_forest()
	_flora()


func _forest() -> void:
	var kinds := ["pine_a", "pine_b", "tree_g", "tree_big", "tree_purple", "tree_dead", "tree_white", "pine_a", "pine_b", "tree_purple"]
	var muls := {"pine_a": 2.4, "pine_b": 2.3, "tree_g": 1.9, "tree_big": 2.0, "tree_purple": 1.9, "tree_dead": 1.9, "tree_white": 1.9}
	var placed: Array[Vector2] = []
	var tries := 0
	while placed.size() < 120 and tries < 900:
		tries += 1
		var a := rng.randf() * TAU
		var r := rng.randf_range(Valley.ARENA - 2.0, Valley.ARENA + 15.0)
		var p := Vector2(cos(a) * r, sin(a) * r)
		var ok := true
		for q in placed:
			if q.distance_to(p) < 2.6:
				ok = false
				break
		if not ok:
			continue
		placed.append(p)
		var k: String = kinds[rng.randi() % kinds.size()]
		var sc := rng.randf_range(0.85, 1.2)
		# перевод мировых (x, z) в экранные sx, sy
		var sx := p.dot(R)
		var sy := p.dot(U)
		put(k, sx, sy, float(muls[k]) * sc, 0.0, rng.randf() < 0.5)
		valley.add_obstacle(p.x, p.y, 0.9, 10.0)
		_shadow(p, 1.8, 0.4)


func _flora() -> void:
	var kinds := ["bush_b", "bush_c", "bush_d", "lav_a", "lav_b", "mush_a", "mush_b", "blue_fl", "white_fl", "grass_a", "reeds", "rock_a", "rock_b", "rock_c", "rock_d", "rock_e", "stump", "bush_a", "grass_a", "lav_b"]
	var muls := {"bush_b": 0.9, "bush_c": 1.0, "bush_d": 1.1, "lav_a": 0.8, "lav_b": 1.0, "mush_a": 0.9, "mush_b": 0.9, "blue_fl": 1.0, "white_fl": 1.0,
		"grass_a": 1.1, "reeds": 1.0, "rock_a": 1.0, "rock_b": 1.0, "rock_c": 1.0, "rock_d": 1.0, "rock_e": 1.0, "stump": 1.0, "bush_a": 1.0}
	for i in range(240):
		var a := rng.randf() * TAU
		var r := (Valley.ARENA - 0.5) * pow(rng.randf(), 0.5)
		var p := Vector2(cos(a) * r, sin(a) * r)
		if r < 8.5 and rng.randf() < 0.9:
			continue
		if not valley.is_free(p.x, p.y, 0.7):
			continue
		var k: String = kinds[rng.randi() % kinds.size()]
		var solid := 0.0
		if k.begins_with("rock") or k == "stump":
			solid = 0.6
		var sx := p.dot(R)
		var sy := p.dot(U)
		var sz := put(k, sx, sy, float(muls[k]) * rng.randf_range(0.85, 1.3), solid, rng.randf() < 0.5)
		if k.begins_with("mush") and rng.randf() < 0.6:
			_lit(sx, sy, sz.y, 0.4, Color(0.55, 0.4, 1.0), 1.6, 0.0, 1.0, false)
