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
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
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
	var cc := Valley.RING_C
	# --- цветы, лаванда, грибы, трава, камни: густо у краёв и вокруг колонн, редко на плите
	var small := ["flowers", "lavender", "lavender", "mushroom", "grass", "flowers", "grass", "mushroom"]
	for i in range(300):
		var a := rng.randf() * TAU
		var r := (Valley.ARENA - 1.0) * pow(rng.randf(), 0.45)
		var x := cos(a) * r
		var z := sin(a) * r
		if r < 7.5 and rng.randf() < 0.85:
			continue
		if _ok(x, z, 0.35) and absf(z - Valley.STREAM_Z) > 3.2:
			var nm: String = small[rng.randi() % small.size()]
			var h: float = {"flowers": 1.0, "lavender": 1.1, "mushroom": 1.1, "grass": 0.9}[nm]
			h *= rng.randf_range(0.8, 1.6)
			put(nm, x, z, h, rng.randf_range(0.85, 1.15), 0.0, rng.randf() < 0.5)
			if nm == "mushroom" and rng.randf() < 0.5:
				glow(x, 0.6, z, Color(0.55, 0.4, 1.0), 1.6, 0.7, 3.0, false)
	# --- компас-руна под ногами (плоский декаль)
	var comp := Sprite3D.new()
	comp.texture = load("res://sprites/compass.png")
	comp.axis = Vector3.AXIS_Y
	comp.pixel_size = 9.0 / float(comp.texture.get_width())
	comp.position = Vector3(cc.x, valley.height_at(cc.x, cc.y) + 0.05, cc.y)
	comp.shaded = false
	comp.transparent = true
	comp.modulate = Color(0.8, 0.8, 1.0, 0.6)
	add_child(comp)
