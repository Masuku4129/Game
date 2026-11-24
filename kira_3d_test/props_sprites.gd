class_name PropSprites
extends Node3D
## Двор руин в изометрии: арт из листов пользователя как спрайты. Камера ортографическая, поэтому полные
## биллборды работают как настоящая 2D-сортировка (кто ниже на экране - тот ближе). Кира остаётся живой 3D между ними.
## Координаты раскладки - экранные: sx вправо, sy вверх по экрану (метры на земле).

const PPM := 69.0                       # пикселей арта на метр (листы увеличены в 1.5 раза)
const R := Vector2(1.0, 0.0)            # экранное "вправо" в мире (x, z), камера yaw 0
const U := Vector2(0.0, -1.0)           # экранное "вверх" (от камеры)
const COS_P := 0.81                     # cos(36 градусов)
const XH := 19.0                        # полуширина двора
const SY_BACK := 14.5                   # задняя стена двора
const SY_FRONT := -10.5                 # передний край

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
func put(name: String, sx: float, sy: float, hgt := 3.0, solid := 0.0, flip := false) -> Vector2:
	var tex: Texture2D = load("res://sp/%s.png" % name)
	if tex == null:
		return Vector2.ZERO
	var h := hgt
	var w := float(tex.get_width()) / float(tex.get_height()) * hgt
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


func _aspect(name: String) -> float:
	var tex: Texture2D = load("res://sp/%s.png" % name)
	return float(tex.get_width()) / float(tex.get_height())


## ряд стен вдоль экранной оси x: от start наружу (dirn -1 влево, +1 вправо); справа спрайты зеркалятся
func _wall_run(sy: float, dirn: float, start: float, seq: Array) -> void:
	var x := start
	var i := 0
	for it in seq:
		var nm: String = it[0]
		var hh: float = it[1]
		var w := _aspect(nm) * hh
		put(nm, x + dirn * w * 0.5, sy + 0.04 * float(i), hh, 0.9, dirn > 0.0)
		x += dirn * (w - 0.8)
		i += 1


## невидимая ограда из препятствий
func _fence(x0: float, y0: float, x1: float, y1: float, step := 1.3) -> void:
	var d := Vector2(x1 - x0, y1 - y0)
	var n := maxi(int(d.length() / step), 1)
	for k in range(n + 1):
		var t := float(k) / float(n)
		var p := _w(x0 + d.x * t, y0 + d.y * t)
		valley.add_obstacle(p.x, p.y, 0.9, 6.0)


func build(v: Valley) -> void:
	valley = v
	rng.seed = 777
	var amber := Color(1.0, 0.68, 0.30)
	var violet := Color(0.62, 0.38, 1.0)
	# --- руна под ногами
	var comp := Sprite3D.new()
	comp.texture = load("res://sprites/compass.png")
	comp.axis = Vector3.AXIS_Y
	comp.pixel_size = 11.0 / float(comp.texture.get_width())
	comp.position = Vector3(0.0, 0.04, 0.0)
	comp.shaded = false
	comp.transparent = true
	comp.modulate = Color(0.8, 0.8, 1.0, 0.55)
	add_child(comp)

	# ===== ЗАМОК. Задняя линия (север): центральные врата, по сторонам стены, на углах башни
	var gate := put("gate_arch1", 0.0, SY_BACK, 9.0, 0.7)
	_lit(0.0, SY_BACK, gate.y, 0.30, violet, 6.0, 2.6, 11.0)
	_wall_run(SY_BACK, -1.0, -gate.x * 0.5 + 0.9, [["wall_win", 5.6], ["wall_long", 4.2], ["wall_tall", 8.6]])
	_wall_run(SY_BACK, 1.0, gate.x * 0.5 - 0.9, [["wall_win", 5.6], ["wall_long", 4.2], ["wall_tall", 8.6]])
	put("col_a", -5.6, SY_BACK - 1.6, 6.2, 0.5)
	put("col_b", 5.6, SY_BACK - 1.6, 6.2, 0.5)
	put("banner_a", -3.3, SY_BACK - 1.0, 5.2, 0.3)
	put("banner_b", 3.3, SY_BACK - 1.0, 5.2, 0.3, true)
	var br := put("brazier_p", -2.6, SY_BACK - 3.6, 3.0, 0.7)
	put("brazier_p", 2.6, SY_BACK - 3.6, 3.0, 0.7)
	for s: float in [-1.0, 1.0]:
		_lit(s * 2.6, SY_BACK - 3.6, br.y, 0.82, violet, 2.6, 2.4, 9.0)

	# ===== за стеной: громада замка, чтобы за воротами не было пустоты
	put("wall_win", -13.0, SY_BACK + 3.5, 8.5, 0.0)
	put("wall_tall", 12.0, SY_BACK + 3.0, 10.0, 0.0, true)
	put("wall_arch", -2.0, SY_BACK + 5.0, 10.5, 0.0)
	put("wall_win", 20.0, SY_BACK + 4.0, 9.0, 0.0, true)
	put("wall_tall", -22.0, SY_BACK + 5.0, 11.0, 0.0)

	# ===== боковые крылья: полуразрушенные залы по обе стороны двора
	put("wall_win", -XH + 3.2, 4.5, 7.2, 0.9)
	put("wall_win", XH - 3.2, 4.5, 7.2, 0.9, true)
	put("wall_arch", -XH + 2.6, -3.5, 8.0, 0.8)
	put("wall_arch", XH - 2.6, -3.5, 8.0, 0.8, true)
	put("rubble_a", -XH + 3.5, 10.3, 2.6, 0.7)
	put("rubble_b", XH - 3.5, 10.3, 2.6, 0.7, true)
	put("wall_rub", -XH + 3.0, -8.4, 2.6, 0.8)
	put("wall_rub", XH - 3.0, -8.4, 2.6, 0.8, true)

	# ===== аллея к воротам: колонны и фонари парами, статуи у ворот
	for sy: float in [-6.0, 0.0, 6.0]:
		put("col_a", -7.4, sy, 6.0, 0.5)
		put("col_b", 7.4, sy, 6.0, 0.5, true)
	var li := 0
	for sy: float in [-8.0, -2.5, 3.0, 8.5]:
		var lw := put("lamp_a", -4.4, sy, 4.6, 0.2)
		put("lamp_a", 4.4, sy, 4.6, 0.2, true)
		_lit(-4.4 + lw.x * 0.27, sy, lw.y, 0.64, amber, 2.4, 2.6, 10.0)
		_lit(4.4 - lw.x * 0.27, sy, lw.y, 0.64, amber, 2.4, 2.6, 10.0)
		li += 1
	put("statue_angel", -10.5, 10.0, 4.8, 0.6)
	put("statue_hood", 10.5, 10.0, 4.8, 0.6)
	put("ped_crystal", -10.5, -9.0, 3.4, 0.6)
	put("ped_crystal", 10.5, -9.0, 3.4, 0.6)
	_lit(-10.5, -9.0, 3.4, 0.82, violet, 2.2, 0.0, 1.0, false)
	_lit(10.5, -9.0, 3.4, 0.82, violet, 2.2, 0.0, 1.0, false)

	# ===== украшения двора
	var sh := put("shrine", XH - 6.5, -0.5, 6.0, 0.6)
	_lit(XH - 6.5, -0.5, sh.y, 0.45, violet, 4.0, 2.2, 9.0)
	var ca := put("crystal_a", -XH + 6.8, 0.5, 3.4, 0.5)
	_lit(-XH + 6.8, 0.5, ca.y, 0.45, violet, 3.0, 2.2, 9.0)
	var cb := put("crystal_c", 13.0, 8.0, 3.2, 0.5)
	_lit(13.0, 8.0, cb.y, 0.45, violet, 2.8, 2.0, 8.0)
	put("orrery", -13.2, 8.0, 3.6, 0.5)
	put("cage", 13.0, -6.0, 3.4, 0.4)
	put("wheel", -13.0, -6.0, 3.8, 0.5)

	# ===== передний край (юг): низкая ограда, проход посередине, колонны и знамёна у проёма
	var bw := _aspect("balust") * 1.9
	var x := -XH + bw * 0.5 - 0.3
	var bi := 0
	while x < -3.6:
		put("balust", x, SY_FRONT + 0.03 * float(bi), 1.9, 0.9)
		x += bw - 0.25
		bi += 1
	x = XH - bw * 0.5 + 0.3
	while x > 3.6:
		put("balust", x, SY_FRONT + 0.03 * float(bi), 1.9, 0.9, true)
		x -= bw - 0.25
		bi += 1
	put("col_c", -3.9, SY_FRONT, 6.0, 0.5)
	put("col_d", 3.9, SY_FRONT, 6.0, 0.5, true)
	put("banner_c", -6.2, SY_FRONT - 0.5, 4.6, 0.3)
	put("banner_c", 6.2, SY_FRONT - 0.5, 4.6, 0.3, true)

	# ===== невидимые границы: боковые края двора и конец дороги на юге
	_fence(-XH - 0.2, SY_BACK, -XH - 0.2, SY_FRONT - 7.0)
	_fence(XH + 0.2, SY_BACK, XH + 0.2, SY_FRONT - 7.0)
	_fence(-XH - 0.2, SY_FRONT - 7.0, -2.8, SY_FRONT - 7.0)
	_fence(2.8, SY_FRONT - 7.0, XH + 0.2, SY_FRONT - 7.0)
	_fence(-2.8, SY_FRONT - 7.0, -2.8, SY_FRONT)
	_fence(2.8, SY_FRONT - 7.0, 2.8, SY_FRONT)
	_fence(-2.8, SY_FRONT - 7.4, 2.8, SY_FRONT - 7.4)
	put("tree_big", -4.8, SY_FRONT - 7.2, 11.0, 0.0)
	put("tree_purple", 4.8, SY_FRONT - 7.2, 10.0, 0.0, true)

	_forest()
	_flora()


func _inside_court(sx: float, sy: float, m: float) -> bool:
	return absf(sx) < XH + m and sy > SY_FRONT - m and sy < SY_BACK + m


func _forest() -> void:
	var kinds := ["pine_a", "pine_b", "tree_g", "tree_big", "tree_purple", "tree_dead", "tree_white", "pine_a", "pine_b", "tree_purple", "tree_g"]
	var hts := {"pine_a": 12.0, "pine_b": 11.0, "tree_g": 9.5, "tree_big": 11.0, "tree_purple": 9.5, "tree_dead": 10.0, "tree_white": 9.0}
	var placed: Array[Vector2] = []
	var tries := 0
	while placed.size() < 230 and tries < 4000:
		tries += 1
		var sx := rng.randf_range(-40.0, 40.0)
		var sy := rng.randf_range(-28.0, 32.0)
		if _inside_court(sx, sy, 1.8):
			continue
		# у дороги на юге оставляем проход
		if absf(sx) < 4.5 and sy < SY_FRONT and sy > SY_FRONT - 8.0:
			continue
		var ok := true
		for q in placed:
			if absf(q.x - sx) < 3.3 and absf(q.y - sy) < 2.0:
				ok = false
				break
		if not ok:
			continue
		placed.append(Vector2(sx, sy))
		var k: String = kinds[rng.randi() % kinds.size()]
		put(k, sx, sy, float(hts[k]) * rng.randf_range(0.85, 1.2), 0.0, rng.randf() < 0.5)


func _flora() -> void:
	var kinds := ["bush_b", "bush_c", "bush_d", "lav_a", "lav_b", "mush_a", "mush_b", "blue_fl", "white_fl", "grass_a", "reeds", "rock_a", "rock_b", "rock_c", "rock_d", "rock_e", "stump", "bush_a", "grass_a", "lav_b"]
	var hts := {"bush_b": 1.7, "bush_c": 1.5, "bush_d": 1.2, "lav_a": 1.9, "lav_b": 1.0, "mush_a": 1.0, "mush_b": 1.2, "blue_fl": 1.0, "white_fl": 1.1,
		"grass_a": 1.2, "reeds": 1.6, "rock_a": 1.2, "rock_b": 1.0, "rock_c": 1.0, "rock_d": 1.4, "rock_e": 1.3, "stump": 1.1, "bush_a": 2.0}
	var n := 0
	var tries := 0
	while n < 260 and tries < 2500:
		tries += 1
		var sx := rng.randf_range(-36.0, 36.0)
		var sy := rng.randf_range(-24.0, 28.0)
		var inside := _inside_court(sx, sy, -0.3)
		# внутри двора только у краёв и в углах; на центральной дорожке чисто
		if inside and (absf(sx) < 6.0 or rng.randf() < 0.6):
			continue
		var p := _w(sx, sy)
		if not valley.is_free(p.x, p.y, 0.8):
			continue
		n += 1
		var k: String = kinds[rng.randi() % kinds.size()]
		var solid := 0.0
		if k.begins_with("rock") or k == "stump":
			solid = 0.6 if inside else 0.0
		var sz := put(k, sx, sy, float(hts[k]) * rng.randf_range(0.85, 1.3), solid, rng.randf() < 0.5)
		if k.begins_with("mush") and rng.randf() < 0.6:
			_lit(sx, sy, sz.y, 0.4, Color(0.55, 0.4, 1.0), 1.6, 0.0, 1.0, false)
