class_name PropSprites
extends Node3D
## Двор древних руин, целиком из нарисованных спрайтов. Полные биллборды: вертикали не заваливаются при камере сверху.

var valley: Valley
var rng := RandomNumberGenerator.new()
var _mats := {}
var _glow_tex: GradientTexture2D


func _mat(name: String, bright: float) -> StandardMaterial3D:
	var key := name + str(bright)
	if _mats.has(key):
		return _mats[key]
	var tex: Texture2D = load("res://sprites/%s.png" % name)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = tex
	m.albedo_color = Color(0.74, 0.76, 0.92) * bright
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


## h - высота на экране в метрах, (x, z) - точка основания
func put(name: String, x: float, z: float, h: float, bright := 1.0, obst := 0.0, flip := false) -> Node3D:
	var tex: Texture2D = load("res://sprites/%s.png" % name)
	if tex == null:
		return null
	var w := h * float(tex.get_width()) / float(tex.get_height())
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	q.center_offset = Vector3(0.0, h * 0.5, 0.0)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = _mat(name, bright)
	mi.position = Vector3(x, valley.height_at(x, z) + 0.02 * h, z)
	if flip:
		mi.scale = Vector3(-1.0, 1.0, 1.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	if obst > 0.0:
		valley.add_obstacle(x, z, obst, h)
	return mi


## мягкое свечение (аддитивный круг) + источник света
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
	s.modulate = Color(col.r, col.g, col.b, 0.55)
	s.material_override = _glow_mat()
	s.pixel_size = size / 128.0
	s.position = Vector3(x, valley.height_at(x, z) + y, z)
	s.no_depth_test = false
	add_child(s)
	if not light:
		return
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = range_m
	l.omni_attenuation = 1.3
	l.position = s.position
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


func _ok(x: float, z: float, r: float, rmin := 0.0) -> bool:
	var d := Vector2(x, z).length()
	return d < Valley.ARENA + 14.0 and d > rmin and Vector2(x - Valley.START_POS.x, z - Valley.START_POS.z).length() > 2.6 and valley.is_free(x, z, r)


func build(v: Valley) -> void:
	valley = v
	rng.seed = 777
	var c := Valley.RING_C
	# --- композиция: у дальней стены (север) святилище, статуя, жаровни
	put("shrine", 0.0, -26.0, 9.5, 1.0, 3.0)
	put("statue", c.x, c.y - 14.0, 5.2, 1.0, 1.2)
	for s: float in [-1.0, 1.0]:
		put("brazier", c.x + s * 4.2, c.y - 12.6, 2.1, 1.1, 0.6)
		glow(c.x + s * 4.2, 1.9, c.y - 12.6, Color(0.7, 0.4, 1.0), 4.0, 2.6, 8.0)
		put("column_a", c.x + s * 8.0, c.y - 15.5, 6.6, 1.0, 0.8, s < 0.0)
	# --- колонны полукругом вокруг площадки
	for k in range(9):
		var a := PI * 0.15 + PI * 0.70 * float(k) / 8.0 + PI
		var x := c.x + cos(a) * 15.5
		var z := c.y + sin(a) * 15.5
		if _ok(x, z, 0.6):
			put("column_a" if k % 2 == 0 else "column_b", x, z, 6.2 if k % 2 == 0 else 5.8, 1.0, 0.7, k % 3 == 0)
	# --- фонари и баннеры по краям плиты
	for k in range(8):
		var a := TAU * float(k) / 8.0 + 0.2
		var x := c.x + cos(a) * 11.0
		var z := c.y + sin(a) * 11.0
		if _ok(x, z, 0.5):
			if k % 2 == 0:
				put("lamp_a" if k % 4 == 0 else "lamp_b", x, z, 4.4, 1.0, 0.3)
				glow(x, 3.6, z, Color(1.0, 0.68, 0.35), 3.4, 2.4, 9.0)
			else:
				put("banner_b", x, z, 5.4, 1.0, 0.3)
	# --- руины-стены и обломки по кольцу
	for k in range(14):
		var a := TAU * float(k) / 14.0 + 0.1
		var r := 21.0 + rng.randf_range(-1.5, 1.5)
		var x := cos(a) * r
		var z := sin(a) * r
		if _ok(x, z, 1.2):
			if k % 3 == 0:
				put("ruin_wall", x, z, 5.4, 1.0, 1.8, rng.randf() < 0.5)
			elif k % 3 == 1:
				put("stonewall", x, z, 3.8, 1.0, 1.5, rng.randf() < 0.5)
			else:
				put("rubble", x, z, 2.2, 1.0, 1.0, rng.randf() < 0.5)
	# --- кристаллы
	for p in [Vector2(-9.0, 8.0), Vector2(10.0, 7.0), Vector2(-14.0, -6.0), Vector2(15.0, -8.0), Vector2(-4.0, 17.0)]:
		if _ok(p.x, p.y, 0.7):
			put("crystal", p.x, p.y, 3.0, 1.1, 0.7)
			glow(p.x, 1.5, p.y, Color(0.6, 0.35, 1.0), 4.0, 3.0, 7.0)
	put("cage", 12.0, 12.0, 3.0, 1.0, 0.5)
	# --- лес по краю двора (не проходим: ARENA ограничивает, плюс препятствия)
	var trees := ["tree_green", "tree_purple", "tree_pine", "tree_dead", "tree_purple", "tree_green"]
	for i in range(260):
		var a := rng.randf() * TAU
		var r := rng.randf_range(Valley.ARENA - 7.0, Valley.ARENA + 14.0)
		var x := cos(a) * r
		var z := sin(a) * r
		if _ok(x, z, 1.0):
			var nm: String = trees[rng.randi() % trees.size()]
			var h := rng.randf_range(8.0, 13.0) if nm != "tree_pine" else rng.randf_range(10.0, 16.0)
			put(nm, x, z, h, rng.randf_range(0.8, 1.0), 0.9 if r < Valley.ARENA + 1.0 else 0.0, rng.randf() < 0.5)
	# --- цветы, лаванда, грибы, трава, камни: густо у краёв и вокруг колонн, редко на плите
	var small := ["flowers", "lavender", "lavender", "mushroom", "grass", "flowers", "grass", "rock_big"]
	for i in range(420):
		var a := rng.randf() * TAU
		var r := (Valley.ARENA - 1.0) * pow(rng.randf(), 0.45)
		var x := cos(a) * r
		var z := sin(a) * r
		if r < 7.5 and rng.randf() < 0.85:
			continue
		if _ok(x, z, 0.2):
			var nm: String = small[rng.randi() % small.size()]
			var h: float = {"flowers": 1.0, "lavender": 1.1, "mushroom": 1.1, "grass": 0.9, "rock_big": 1.4}[nm]
			h *= rng.randf_range(0.8, 1.6)
			put(nm, x, z, h, rng.randf_range(0.85, 1.15), 0.0, rng.randf() < 0.5)
			if nm == "mushroom" and rng.randf() < 0.5:
				glow(x, 0.6, z, Color(0.55, 0.4, 1.0), 1.6, 0.7, 3.0, false)
	# --- компас-руна под ногами (плоский декаль)
	var comp := Sprite3D.new()
	comp.texture = load("res://sprites/compass.png")
	comp.axis = Vector3.AXIS_Y
	comp.pixel_size = 9.0 / float(comp.texture.get_width())
	comp.position = Vector3(c.x, valley.height_at(c.x, c.y) + 0.05, c.y)
	comp.shaded = false
	comp.transparent = true
	comp.modulate = Color(0.8, 0.8, 1.0, 0.6)
	add_child(comp)
