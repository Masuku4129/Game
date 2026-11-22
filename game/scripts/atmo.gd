extends Node3D
## Атмосферные эффекты вокруг камеры: стелющийся туман в низинах, листопад с ближних
## лиственных деревьев, брызги капель на земле и воде, капель с крон после дождя.
## Всё дешёвое: несколько прозрачных плоскостей и небольшие GPU-частицы.

var main: Node3D
var weather
var rng := RandomNumberGenerator.new()

var mist_layers: Array = []
var leaves: GPUParticles3D
var splash: GPUParticles3D
var drips: GPUParticles3D
var _splash_mat: StandardMaterial3D
var _leaf_img: Image
var _leaf_tex: ImageTexture
var _splash_img: Image
var _splash_tex: ImageTexture
var _leaf_at := Vector3(1e9, 0, 0)
var _leaf_t := 0.0
var _leaf_n := 0
var _splash_at := Vector3(1e9, 0, 0)
var _splash_t := 0.0
var _kh := {}

const LEAF_PTS := 256
const SPLASH_PTS := 1024
const DECIDUOUS := ["birch", "aspen", "larch", "rowan"]

func _ready() -> void:
	rng.seed = 404
	_make_mist()
	leaves = _make_leaves()
	splash = _make_splash()
	drips = _make_drips()

# ---------- туман ----------

func _make_mist() -> void:
	var sh := load("res://shaders/paint/mist.gdshader")
	for i in 3:
		var pm := PlaneMesh.new()
		pm.size = Vector2(150, 150)
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("water_y", main.WATER_Y)
		m.set_shader_parameter("layer", float(i))
		m.set_shader_parameter("radius", 72.0)
		m.render_priority = i
		pm.material = m
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		mist_layers.append(mi)

func _update_mist(c: Vector3) -> void:
	var mist: float = weather.mist
	var on := mist > 0.03
	var col: Color = main.env.fog_light_color.lightened(0.12)
	var drift := Vector2(Time.get_ticks_msec() * 0.001, Time.get_ticks_msec() * 0.0004) * (0.4 + float(weather.wind) * 0.9)
	for i in mist_layers.size():
		var mi: MeshInstance3D = mist_layers[i]
		mi.visible = on
		if not on:
			continue
		mi.global_position = Vector3(roundf(c.x), main.WATER_Y + 1.4 + i * 0.85 + mist * 0.6, roundf(c.z))
		var m: ShaderMaterial = (mi.mesh as PlaneMesh).material
		if m.get_shader_parameter("hmap") == null:
			m.set_shader_parameter("hmap", main.hmap_tex)
		m.set_shader_parameter("mist", mist)
		m.set_shader_parameter("col", col)
		m.set_shader_parameter("drift", drift)
		m.set_shader_parameter("center", c)

# ---------- листопад ----------

func _points_tex(n: int) -> Array:
	var img := Image.create(n, 1, false, Image.FORMAT_RGBF)
	var tex := ImageTexture.create_from_image(img)
	return [img, tex]

func _make_leaves() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	var pt := _points_tex(LEAF_PTS)
	_leaf_img = pt[0]
	_leaf_tex = pt[1]
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	pm.emission_point_texture = _leaf_tex
	pm.emission_point_count = 1
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 70.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.5
	pm.gravity = Vector3(0.3, -0.7, 0.1)
	pm.damping_min = 0.4
	pm.damping_max = 0.9
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.2
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_influence_min = 0.04
	pm.turbulence_influence_max = 0.12
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -220.0
	pm.angular_velocity_max = 220.0
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.3))
	sc.add_point(Vector2(0.08, 1.0))
	sc.add_point(Vector2(0.85, 1.0))
	sc.add_point(Vector2(1.0, 0.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.set_color(0, Color(0.95, 0.78, 0.2))
	g.set_color(1, Color(0.78, 0.25, 0.1))
	g.add_point(0.45, Color(0.92, 0.55, 0.14))
	g.add_point(0.8, Color(0.6, 0.38, 0.16))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_initial_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.11, 0.11)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.albedo_texture = _leaf_shape()
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.backlight_enabled = true
	m.backlight = Color(0.5, 0.35, 0.1)
	q.material = m
	p.draw_pass_1 = q
	p.amount = 140
	p.lifetime = 7.0
	p.randomness = 0.6
	p.local_coords = false
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-40, -20, -40), Vector3(80, 40, 80))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p

func _leaf_shape() -> Texture2D:
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	for y in n:
		for x in n:
			var u := (float(x) + 0.5) / n * 2.0 - 1.0
			var v := (float(y) + 0.5) / n * 2.0 - 1.0
			# лист: заострённый эллипс, светлая жилка посередине, черешок снизу
			var w := 0.55 * (1.0 - v * v) * (1.0 - 0.25 * v)
			if absf(u) < w and v > -0.85 and v < 0.8:
				var vein := 1.0 - smoothstep(0.0, 0.07, absf(u))
				img.set_pixel(x, y, Color(0.92 + vein * 0.08, 0.92 + vein * 0.08, 0.9, 1.0))
			elif absf(u) < 0.05 and v >= 0.8:
				img.set_pixel(x, y, Color(0.6, 0.5, 0.35, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## Высота кроны породы (по детальной модели), кэш по ключу.
func _crown(key: String) -> Vector2:
	if not _kh.has(key):
		var ab: AABB = (main.near_mesh[key] as Mesh).get_aabb()
		_kh[key] = Vector2(ab.end.y, maxf(ab.size.x, ab.size.z) * 0.35)
	return _kh[key]

## Точки вылета листьев — внутри крон ближних лиственных деревьев.
func _rebuild_leaf_points(c: Vector3) -> void:
	var trees: Array = []
	var g0 := Vector2i(floori((c.x - 26.0) / 16.0), floori((c.z - 26.0) / 16.0))
	for gz in range(g0.y, g0.y + 5):
		for gx in range(g0.x, g0.x + 5):
			var gk := Vector2i(gx, gz)
			if not main.tree_grid.has(gk):
				continue
			for rec: Array in main.tree_grid[gk]:
				var key: String = rec[3]
				if not DECIDUOUS.has(key.rstrip("0123456789")):
					continue
				var t: Transform3D = rec[2]
				if t.origin.y < -100.0 or Vector2(t.origin.x - c.x, t.origin.z - c.z).length() > 26.0:
					continue
				trees.append([t, key])
	_leaf_n = trees.size()
	leaves.global_position = c
	if trees.is_empty():
		return
	for i in LEAF_PTS:
		var tr: Array = trees[i % trees.size()]
		var t: Transform3D = tr[0]
		var cr := _crown(tr[1])
		var s := t.basis.get_scale().y
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * cr.y * s
		var lp := t.origin + Vector3(cos(a) * r, cr.x * s * rng.randf_range(0.45, 0.9), sin(a) * r)
		_leaf_img.set_pixel(i, 0, Color(lp.x - c.x, lp.y - c.y, lp.z - c.z))
	_leaf_tex.update(_leaf_img)
	(leaves.process_material as ParticleProcessMaterial).emission_point_count = LEAF_PTS

func _update_leaves(c: Vector3, dt: float) -> void:
	var aut: float = weather.autumn
	var drop: float = weather.leaf_drop
	# листья летят, пока они ещё есть на деревьях: сильнее в разгар листопада и на ветру
	var k := smoothstep(0.25, 0.6, aut) * (1.0 - smoothstep(0.85, 1.0, drop)) * (0.35 + smoothstep(0.1, 0.6, drop) * 0.65)
	k *= clampf(0.4 + float(weather.wind) * 0.5, 0.0, 1.2) * (1.0 - float(weather.snow))
	_leaf_t -= dt
	if k > 0.02 and (_leaf_t <= 0.0 or Vector2(c.x - _leaf_at.x, c.z - _leaf_at.z).length() > 5.0):
		_leaf_t = 1.5
		_leaf_at = c
		_rebuild_leaf_points(c)
	var on := k > 0.02 and _leaf_n > 0
	leaves.emitting = on
	leaves.amount_ratio = clampf(k * minf(1.0, _leaf_n / 6.0), 0.0, 1.0)
	var pm: ParticleProcessMaterial = leaves.process_material
	var w: float = weather.wind
	pm.gravity = Vector3(w * 0.9, -0.7, w * 0.35)

# ---------- брызги и капель ----------

func _make_splash() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	var pt := _points_tex(SPLASH_PTS)
	_splash_img = pt[0]
	_splash_tex = pt[1]
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	pm.emission_point_texture = _splash_tex
	pm.emission_point_count = 1
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.35))
	sc.add_point(Vector2(0.5, 1.0))
	sc.add_point(Vector2(1.0, 1.15))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.9))
	g.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.2, 0.12)
	q.center_offset = Vector3(0, 0.05, 0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = _crown_shape()
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.albedo_color = Color(0.8, 0.85, 0.9, 0.7)
	_splash_mat = m
	q.material = m
	p.draw_pass_1 = q
	p.amount = 700
	p.lifetime = 0.22
	p.randomness = 0.5
	p.local_coords = false
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-24, -12, -24), Vector3(48, 24, 48))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p

## Венчик брызг: капельки по дуге над точкой удара.
func _crown_shape() -> Texture2D:
	var w := 32
	var h := 20
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var r := RandomNumberGenerator.new()
	r.seed = 3
	for i in 9:
		var a := lerpf(0.15, PI - 0.15, float(i) / 8.0) + r.randf_range(-0.12, 0.12)
		var cx := 16.0 + cos(a) * r.randf_range(9.0, 14.0)
		var cy := 17.0 - sin(a) * r.randf_range(7.0, 15.0)
		var rad := r.randf_range(1.0, 1.9)
		for y in h:
			for x in w:
				var d := Vector2(x + 0.5 - cx, y + 0.5 - cy).length()
				if d < rad:
					img.set_pixel(x, y, Color(1, 1, 1, clampf(rad - d, 0.0, 1.0)))
	for x in range(6, 26):
		var a2 := 1.0 - absf(x - 16.0) / 10.0
		img.set_pixel(x, 18, Color(1, 1, 1, a2 * 0.8))
		img.set_pixel(x, 19, Color(1, 1, 1, a2 * 0.5))
	return ImageTexture.create_from_image(img)

func _rebuild_splash_points(c: Vector3) -> void:
	splash.global_position = c
	for i in SPLASH_PTS:
		var x := c.x + rng.randf_range(-17.0, 17.0)
		var z := c.z + rng.randf_range(-17.0, 17.0)
		var y := maxf(main.grid_height(x, z), main.WATER_Y) + 0.02
		_splash_img.set_pixel(i, 0, Color(x - c.x, y - c.y, z - c.z))
	_splash_tex.update(_splash_img)
	(splash.process_material as ParticleProcessMaterial).emission_point_count = SPLASH_PTS

func _make_drips() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(9, 1.2, 9)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 2.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.5
	pm.gravity = Vector3(0, -9.8, 0)
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.014, 0.16)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.8, 0.86, 0.9, 0.45)
	q.material = m
	p.draw_pass_1 = q
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	p.amount = 60
	p.lifetime = 1.0
	p.randomness = 0.5
	p.local_coords = false
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-12, -10, -12), Vector3(24, 14, 24))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p

func _update_rain_fx(c: Vector3, dt: float) -> void:
	var warm: bool = float(weather.temp) >= 0.5
	var amt := clampf(float(weather.precip) * 1.15, 0.0, 1.0) if warm else 0.0
	splash.emitting = amt > 0.05
	if splash.emitting:
		_splash_t -= dt
		if _splash_t <= 0.0 or Vector2(c.x - _splash_at.x, c.z - _splash_at.z).length() > 3.0:
			_splash_t = 0.6
			_splash_at = c
			_rebuild_splash_points(c)
		splash.amount_ratio = amt
		var lv: float = 0.25 + float(main.day_factor) * 0.75
		_splash_mat.albedo_color = Color(0.8 * lv, 0.85 * lv, 0.9 * lv, 0.7)
	# капель с крон: в лесу в дождь и ещё долго после него
	var hp: Vector3 = main.hero.position
	var fd: float = main.forest_density(hp.x, hp.z)
	var wet: float = weather.wet
	var dk := smoothstep(0.35, 0.7, fd) * smoothstep(0.15, 0.5, wet) * (1.0 - float(weather.leaf_drop) * 0.6) if warm else 0.0
	drips.emitting = dk > 0.05
	drips.amount_ratio = clampf(dk * (0.5 + amt * 0.5), 0.0, 1.0)
	drips.global_position = Vector3(hp.x, hp.y + 5.0, hp.z)

func update(c: Vector3) -> void:
	var dt := get_process_delta_time()
	_update_mist(c)
	_update_leaves(c, dt)
	_update_rain_fx(c, dt)
