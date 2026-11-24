class_name PropSprites
extends Node3D
## Спрайтовые декорации из нарисованных листов: картонки с вертикальным биллбордом (камера фиксированная).

var valley: Valley
var rng := RandomNumberGenerator.new()
var _mats := {}


func _mat(name: String, glow: float) -> StandardMaterial3D:
	var key := name + str(glow)
	if _mats.has(key):
		return _mats[key]
	var tex: Texture2D = load("res://sprites/%s.png" % name)
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.emission_enabled = true
	m.emission_texture = tex
	m.emission = Color.WHITE
	m.emission_energy_multiplier = 0.22 + glow
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


## h - высота в метрах; позиция - ножка предмета на земле
func put(name: String, x: float, z: float, h: float, glow := 0.0, obst := 0.0, flip := false) -> Node3D:
	var tex: Texture2D = load("res://sprites/%s.png" % name)
	if tex == null:
		return null
	var w := h * float(tex.get_width()) / float(tex.get_height())
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	q.center_offset = Vector3(0.0, h * 0.5, 0.0)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = _mat(name, glow)
	mi.position = Vector3(x, valley.height_at(x, z) - 0.04 * h, z)
	if flip:
		mi.scale = Vector3(-1.0, 1.0, 1.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	if obst > 0.0:
		valley.add_obstacle(x, z, obst, h)
	return mi


func _light(x: float, y: float, z: float, col: Color, energy: float, rng_m: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng_m
	l.omni_attenuation = 1.4
	l.position = Vector3(x, valley.height_at(x, z) + y, z)
	add_child(l)


func _ok(x: float, z: float, r: float) -> bool:
	return Vector2(x, z).length() < Valley.ARENA - 0.5 and Vector2(x - Valley.START_POS.x, z - Valley.START_POS.z).length() > 3.0 \
		and valley._path_mask(x, z) < 0.35 and valley.is_free(x, z, r)


func build(v: Valley) -> void:
	valley = v
	rng.seed = 777
	var c := Valley.RING_C
	# центр боевой площадки: статуя, жаровни, кристаллы
	put("statue", c.x, c.y - 13.0, 4.2, 0.1, 1.2)
	for s: float in [-1.0, 1.0]:
		put("brazier", c.x + s * 3.2, c.y - 11.2, 1.7, 0.5, 0.5)
		_light(c.x + s * 3.2, 1.6, c.y - 11.2, Color(0.7, 0.4, 1.0), 2.4, 7.0)
		put("column_a", c.x + s * 6.5, c.y - 12.0, 5.2, 0.0, 0.7)
	# фонари вдоль краёв площадки
	for k in range(6):
		var a := TAU * float(k) / 6.0 + 0.5
		var x := c.x + cos(a) * 12.5
		var z := c.y + sin(a) * 12.5
		if _ok(x, z, 0.5):
			put("lamp_a" if k % 2 == 0 else "lamp_b", x, z, 3.6, 0.9, 0.3)
			_light(x, 3.0, z, Color(1.0, 0.68, 0.35), 2.2, 8.0)
	# баннеры и колонны
	for k in range(7):
		var a := TAU * float(k) / 7.0 + 0.9
		var x := c.x + cos(a) * 15.5 + rng.randf_range(-1.0, 1.0)
		var z := c.y + sin(a) * 15.5 + rng.randf_range(-1.0, 1.0)
		if _ok(x, z, 0.6):
			if k % 2 == 0:
				put("banner_b", x, z, 4.6, 0.1, 0.3)
			else:
				put("column_b", x, z, 4.6, 0.0, 0.6)
	# руины на заднем плане
	for p in [Vector2(-17.0, -17.0), Vector2(16.0, -18.0), Vector2(0.0, -23.0), Vector2(-22.0, 2.0), Vector2(22.0, 4.0)]:
		if _ok(p.x, p.y, 1.0):
			put("ruin_wall", p.x, p.y, 4.2, 0.0, 1.8, rng.randf() < 0.5)
	for p in [Vector2(-12.0, -20.0), Vector2(9.0, -21.0), Vector2(-19.0, -8.0), Vector2(20.0, -6.0)]:
		if _ok(p.x, p.y, 0.8):
			put("rubble", p.x, p.y, 1.7, 0.0, 1.0, rng.randf() < 0.5)
	# кристаллы со свечением
	for p in [Vector2(-8.0, 8.0), Vector2(9.0, 4.0), Vector2(-4.0, -15.0), Vector2(6.0, -14.0)]:
		if _ok(p.x, p.y, 0.7):
			put("crystal", p.x, p.y, 2.4, 1.0, 0.6)
			_light(p.x, 1.2, p.y, Color(0.6, 0.35, 1.0), 2.6, 6.0)
	# деревья по краю поляны (дальше стена елей)
	var trees := ["tree_green", "tree_purple", "tree_pine", "tree_dead"]
	for i in range(34):
		var a := rng.randf() * TAU
		var r := rng.randf_range(17.0, Valley.ARENA - 0.5)
		var x := cos(a) * r
		var z := sin(a) * r
		if z > 8.0 and absf(x) < 6.0:
			continue
		if _ok(x, z, 1.0):
			var nm: String = trees[rng.randi() % trees.size()]
			var h := rng.randf_range(6.0, 9.5) if nm != "tree_pine" else rng.randf_range(8.0, 12.0)
			put(nm, x, z, h, 0.0, 0.8, rng.randf() < 0.5)
	# мелочь: цветы, лаванда, грибы, трава, камни
	var small := ["flowers", "lavender", "mushroom", "grass", "grass", "rock_big"]
	for i in range(110):
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * (Valley.ARENA - 1.0)
		var x := cos(a) * r
		var z := sin(a) * r
		if _ok(x, z, 0.3):
			var nm: String = small[rng.randi() % small.size()]
			var h: float = {"flowers": 0.8, "lavender": 0.85, "mushroom": 0.9, "grass": 0.75, "rock_big": 1.1}[nm]
			h *= rng.randf_range(0.8, 1.4)
			put(nm, x, z, h, 0.5 if nm == "mushroom" else 0.0, 0.0, rng.randf() < 0.5)
	# компас-руна под ногами
	var comp := Sprite3D.new()
	comp.texture = load("res://sprites/compass.png")
	comp.axis = Vector3.AXIS_Y
	comp.pixel_size = 7.0 / float(comp.texture.get_width())
	comp.position = Vector3(c.x, valley.height_at(c.x, c.y) + 0.06, c.y)
	comp.shaded = false
	comp.transparent = true
	comp.modulate = Color(1, 1, 1, 0.55)
	comp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	add_child(comp)
