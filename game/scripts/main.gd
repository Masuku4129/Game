extends Node3D
## Этап 2: кусок тайги 512×512 м в стиле 4: рельеф с обрывами и рекой,
## деревья с ветками-геометрией и хвоей/листвой из текстур.

const SIZE := 512.0
const SEG := 384
const WATER_Y := -2.0
const CELL := 64.0

var n_hill := FastNoiseLite.new()
var n_cliff := FastNoiseLite.new()
var n_detail := FastNoiseLite.new()
var n_forest := FastNoiseLite.new()
var n_crag := FastNoiseLite.new()
var n_crag2 := FastNoiseLite.new()
var n_biome := FastNoiseLite.new()

var t_hours := 9.0
var day_count := 1
var day_factor := 1.0
var hero
var rig
var joy
var hud
var hunger := 0.85
var warmth := 0.8
var stamina := 1.0
var blockers := {}
var seats := {}
var act_btn: Button
var fps_lbl: Label
var _fps_t := 0.0
var weather
var feet
var terrain_mat: ShaderMaterial
var health := 1.0
var thirst := 0.9
var bleed := 0.0
var injuries := {}
var inv := {}
var pickables := {}
var animals
var flash: ColorRect
var dead_lbl: Label
var dead_t := 0.0
var msg_t := 0.0
var msg := ""
var water_mat: ShaderMaterial

func _ready() -> void:
	_setup_noise()
	weather = preload("res://scripts/weather.gd").new()
	weather.main = self
	add_child(weather)
	_make_environment()
	_make_terrain()
	_make_water()
	_scatter_all()
	grass_mesh_vars = [pv.tuft(1500), pv.tuft(1501), pv.tuft(1502), pv.tuft(1503, 1.3), pv.tuft(1504, 0.8)]
	hero = preload("res://scripts/hero.gd").new()
	hero.main = self
	add_child(hero)
	feet = preload("res://scripts/footprints.gd").new()
	feet.main = self
	add_child(feet)
	hero.position = _find_start()
	animals = preload("res://scripts/animals.gd").new()
	animals.main = self
	add_child(animals)
	animals.populate()
	rig = preload("res://scripts/camera_rig.gd").new()
	rig.target = hero
	add_child(rig)
	rig.position = hero.position
	player_rig = hero
	var ui := CanvasLayer.new()
	add_child(ui)
	hud = preload("res://scripts/hud.gd").new()
	hud.anchor_right = 1.0
	hud.anchor_bottom = 1.0
	ui.add_child(hud)
	joy = preload("res://scripts/joystick.gd").new()
	joy.anchor_top = 1.0
	joy.anchor_bottom = 1.0
	joy.offset_left = 40.0
	joy.offset_right = 400.0
	joy.offset_top = -400.0
	joy.offset_bottom = -40.0
	ui.add_child(joy)
	act_btn = Button.new()
	act_btn.anchor_left = 1.0
	act_btn.anchor_right = 1.0
	act_btn.anchor_top = 1.0
	act_btn.anchor_bottom = 1.0
	act_btn.offset_left = -330.0
	act_btn.offset_right = -60.0
	act_btn.offset_top = -230.0
	act_btn.offset_bottom = -90.0
	act_btn.add_theme_font_size_override("font_size", 40)
	act_btn.focus_mode = Control.FOCUS_NONE
	act_btn.visible = false
	act_btn.pressed.connect(func(): hero.do_action())
	ui.add_child(act_btn)
	fps_lbl = Label.new()
	fps_lbl.anchor_left = 0.5
	fps_lbl.anchor_right = 0.5
	fps_lbl.offset_left = -300.0
	fps_lbl.offset_right = 300.0
	fps_lbl.offset_top = 14.0
	fps_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fps_lbl.add_theme_font_size_override("font_size", 24)
	fps_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	fps_lbl.add_theme_constant_override("outline_size", 6)
	fps_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(fps_lbl)
	flash = ColorRect.new()
	flash.anchor_right = 1.0
	flash.anchor_bottom = 1.0
	flash.color = Color(0.6, 0.0, 0.0, 0.0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(flash)
	dead_lbl = Label.new()
	dead_lbl.anchor_right = 1.0
	dead_lbl.anchor_bottom = 1.0
	dead_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dead_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dead_lbl.add_theme_font_size_override("font_size", 64)
	dead_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	dead_lbl.add_theme_constant_override("outline_size", 10)
	dead_lbl.visible = false
	ui.add_child(dead_lbl)
	_update_sky()

func _find_start() -> Vector3:
	for r in range(0, 120, 3):
		for k in 16:
			var a := TAU * k / 16.0
			var x := cos(a) * r
			var z := sin(a) * r
			var y := height(x, z)
			if y > WATER_Y + 0.8 and normal_at(x, z).y > 0.93 and not blocked(x, z, 1.5):
				return Vector3(x, y, z)
	return Vector3(0, height(0, 0), 0)

func _add_blocker(x: float, z: float, r: float) -> void:
	var k := Vector2i(floori(x / 8.0), floori(z / 8.0))
	if not blockers.has(k):
		blockers[k] = []
	blockers[k].append(Vector3(x, z, r))

## Твёрдые тела, на которые можно встать: [вид, a, b, радиус, высота].
## 0 — купол камня (a — центр основания), 1 — бревно (ось a→b), 2 — пень-цилиндр.
var solids := {}

func _add_solid(sd: Array) -> void:
	var a: Vector3 = sd[1]
	var c := a
	var ext: float = sd[3] + 0.5
	if sd[0] == 1:
		var bb: Vector3 = sd[2]
		c = (a + bb) * 0.5
		ext += a.distance_to(bb) * 0.5
	for gx in range(floori((c.x - ext) / 8.0), floori((c.x + ext) / 8.0) + 1):
		for gz in range(floori((c.z - ext) / 8.0), floori((c.z + ext) / 8.0) + 1):
			var k := Vector2i(gx, gz)
			if not solids.has(k):
				solids[k] = []
			solids[k].append(sd)

## Верх твёрдого тела в точке (или -1e9, если его нет).
func solid_top(x: float, z: float) -> float:
	var k := Vector2i(floori(x / 8.0), floori(z / 8.0))
	if not solids.has(k):
		return -1e9
	var best := -1e9
	for sd in solids[k]:
		var a: Vector3 = sd[1]
		var r: float = sd[3]
		match int(sd[0]):
			0:
				var d := Vector2(x - a.x, z - a.z).length()
				if d < r:
					best = maxf(best, a.y + float(sd[4]) * sqrt(1.0 - (d / r) * (d / r)))
			1:
				var bb: Vector3 = sd[2]
				var ab := Vector2(bb.x - a.x, bb.z - a.z)
				var t := clampf(Vector2(x - a.x, z - a.z).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
				var cp := a.lerp(bb, t)
				var d := Vector2(x - cp.x, z - cp.z).length()
				if d < r:
					best = maxf(best, cp.y + sqrt(r * r - d * d))
			2:
				if Vector2(x - a.x, z - a.z).length() < r:
					best = maxf(best, a.y + float(sd[4]))
	return best

## Высота опоры: земля или камень/бревно/пень сверху.
func ground_at(x: float, z: float) -> float:
	return maxf(height(x, z), solid_top(x, z))

func ground_normal(x: float, z: float) -> Vector3:
	var e := 0.3
	return Vector3(ground_at(x - e, z) - ground_at(x + e, z), 2.0 * e, ground_at(x, z - e) - ground_at(x, z + e)).normalized()

func _add_seat(p: Vector3, yaw: float) -> void:
	var k := Vector2i(floori(p.x / 8.0), floori(p.z / 8.0))
	if not seats.has(k):
		seats[k] = []
	seats[k].append([p, yaw])

## Ближайшее место, где можно сесть (в радиусе 1,5 м): [точка сиденья, поворот] или [].
func find_seat(p: Vector3) -> Array:
	var c := Vector2i(floori(p.x / 8.0), floori(p.z / 8.0))
	var best: Array = []
	var bd := 1.5 * 1.5
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var k := Vector2i(c.x + dx, c.y + dz)
			if not seats.has(k):
				continue
			for s in seats[k]:
				var sp: Vector3 = s[0]
				var dd := Vector2(sp.x - p.x, sp.z - p.z).length_squared()
				if dd < bd:
					bd = dd
					best = s
	return best

func blocked(x: float, z: float, rad: float) -> bool:
	var c := Vector2i(floori(x / 8.0), floori(z / 8.0))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var k := Vector2i(c.x + dx, c.y + dz)
			if not blockers.has(k):
				continue
			for b in blockers[k]:
				var ddx: float = b.x - x
				var ddz: float = b.y - z
				var rr: float = b.z + rad
				if ddx * ddx + ddz * ddz < rr * rr:
					return true
	return false

func _setup_noise() -> void:
	n_hill.seed = 1640; n_hill.frequency = 0.004; n_hill.fractal_octaves = 4
	n_cliff.seed = 77; n_cliff.frequency = 0.009; n_cliff.fractal_octaves = 2
	n_detail.seed = 5; n_detail.frequency = 0.05; n_detail.fractal_octaves = 3
	n_crag.seed = 31; n_crag.frequency = 0.16; n_crag.fractal_octaves = 4
	n_crag2.seed = 32; n_crag2.frequency = 0.55; n_crag2.fractal_octaves = 2
	n_biome.seed = 4242; n_biome.frequency = 0.0042; n_biome.fractal_octaves = 2
	n_forest.seed = 909; n_forest.frequency = 0.02; n_forest.fractal_octaves = 3

func river_dist(x: float, z: float) -> float:
	return absf(z - 70.0 * sin(x / 95.0) - 20.0)

func biome(x: float, z: float) -> float:
	return clampf(n_biome.get_noise_2d(x, z) * 2.2, -1.0, 1.0)

func height(x: float, z: float) -> float:
	var rocky := clampf(biome(x, z), 0.0, 1.0)
	var h := n_hill.get_noise_2d(x, z) * (8.0 + rocky * 6.0) + n_detail.get_noise_2d(x, z) * 1.0 + 3.0
	var c := n_cliff.get_noise_2d(x, z)
	# ступени-обрывы: резкий подъём на узкой полосе шума
	var t1 := smoothstep(0.09, 0.21, c)
	var t2 := smoothstep(0.31, 0.43, c)
	h += t1 * 6.0 + t2 * 5.0
	# рваная скалистая поверхность обрывов: крупные и мелкие сколы только на самом уступе
	var face := (t1 * (1.0 - t1) + t2 * (1.0 - t2)) * 4.0
	h += n_crag.get_noise_2d(x, z) * 1.8 * face + n_crag2.get_noise_2d(x, z) * 0.6 * face
	h = maxf(h, WATER_Y + 0.6 + n_detail.get_noise_2d(x * 0.5, z * 0.5) * 0.3)
	var r := 1.0 - smoothstep(7.0, 32.0, river_dist(x, z))
	return lerpf(h, WATER_Y - 2.5, r)

func normal_at(x: float, z: float) -> Vector3:
	var e := 1.0
	return Vector3(height(x - e, z) - height(x + e, z), 2.0 * e, height(x, z - e) - height(x, z + e)).normalized()

func forest_density(x: float, z: float) -> float:
	var b := biome(x, z)
	var d := n_forest.get_noise_2d(x, z) * 1.6 + 0.55
	if b > 0.0:
		d -= b * 0.75
	else:
		d += b * 0.5
	return clampf(d, 0.0, 1.0)

var sky_mat: ProceduralSkyMaterial
var env: Environment
var sun: DirectionalLight3D
var moon: DirectionalLight3D

func _make_environment() -> void:
	sky_mat = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_density = 0.004
	env.fog_sky_affect = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 38.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.66, 0.95)
	moon.rotation_degrees = Vector3(-48, 200, 0)
	add_child(moon)
	_update_sky()

## Время суток: sun/moon, цвета неба, туман, свет факела у героя.
func _update_sky() -> void:
	var e := sin((t_hours / 24.0) * TAU - PI * 0.5)
	var d := smoothstep(-0.05, 0.25, e)
	var dusk := clampf(1.0 - absf(e) * 4.0, 0.0, 1.0)
	var elev := clampf(e, 0.0, 1.0) * 60.0 + 5.0
	sun.rotation_degrees = Vector3(-elev, 40.0 + (t_hours - 12.0) * 15.0, 0)
	var cl: float = weather.cloud if weather != null else 0.0
	sun.light_energy = 1.6 * smoothstep(0.0, 0.3, e) * (1.0 - cl * 0.72)
	sun.light_color = Color(1.0, 0.55, 0.30).lerp(Color(1.0, 0.93, 0.82), smoothstep(0.0, 0.45, e))
	sun.visible = e > -0.02
	moon.light_energy = 0.3 * (1.0 - d)
	moon.visible = d < 0.98
	var day_top := Color(0.50, 0.58, 0.66)
	var day_hor := Color(0.72, 0.75, 0.74)
	var night_top := Color(0.015, 0.025, 0.06)
	var night_hor := Color(0.05, 0.07, 0.12)
	var top := night_top.lerp(day_top, d).lerp(Color(0.30, 0.32, 0.46), dusk * 0.55)
	var hor := night_hor.lerp(day_hor, d).lerp(Color(0.88, 0.52, 0.34), dusk * 0.7)
	var grey := Color(0.5, 0.53, 0.56) * (0.15 + d * 0.85)
	top = top.lerp(grey, cl * 0.8)
	hor = hor.lerp(grey.lightened(0.15), cl * 0.6)
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = hor
	sky_mat.ground_horizon_color = hor.darkened(0.15)
	sky_mat.ground_bottom_color = hor.darkened(0.6)
	env.fog_light_color = hor.darkened(0.08)
	env.ambient_light_energy = lerpf(0.22, 0.7, d) * (1.0 + cl * 0.25)
	if weather != null:
		env.fog_density = 0.004 + weather.fogv * 0.03 + weather.precip * 0.008 + weather.snow * 0.0
	if hero != null:
		hero.torch.light_energy = 2.2 * (1.0 - d)
	day_factor = d

func _make_terrain() -> void:
	var n := SEG + 1
	var step := SIZE / SEG
	var half := SIZE * 0.5
	var verts := PackedVector3Array(); verts.resize(n * n)
	var norms := PackedVector3Array(); norms.resize(n * n)
	var cols := PackedColorArray(); cols.resize(n * n)
	var hs := PackedFloat32Array(); hs.resize(n * n)
	for iz in n:
		for ix in n:
			hs[iz * n + ix] = height(ix * step - half, iz * step - half)
	for iz in n:
		for ix in n:
			var x := ix * step - half
			var z := iz * step - half
			var i := iz * n + ix
			var y := hs[i]
			verts[i] = Vector3(x, y, z)
			var hl := hs[iz * n + maxi(ix - 1, 0)]
			var hr := hs[iz * n + mini(ix + 1, n - 1)]
			var hd := hs[maxi(iz - 1, 0) * n + ix]
			var hu := hs[mini(iz + 1, n - 1) * n + ix]
			norms[i] = Vector3(hl - hr, 2.0 * step, hd - hu).normalized()
			var fd := forest_density(x, z)
			var grass := clampf(1.0 - fd * 1.4, 0.0, 1.0)
			grass *= 1.0 - smoothstep(0.08, 0.22, 1.0 - norms[i].y)
			var mud := clampf((WATER_Y + 1.2 - y) / 1.5, 0.0, 1.0)
			var leaves := clampf(n_detail.get_noise_2d(x * 2.0, z * 2.0) * 0.8 + fd * 0.5, 0.0, 1.0)
			cols[i] = Color(fd, mud, leaves)
	var idx := PackedInt32Array()
	for iz in SEG:
		for ix in SEG:
			var a := iz * n + ix
			idx.append_array([a, a + 1, a + n, a + 1, a + n + 1, a + n])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/paint/ground.gdshader")
	mat.set_shader_parameter("water_y", WATER_Y)
	mesh.surface_set_material(0, mat)
	terrain_mat = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)

func _make_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(SIZE, SIZE)
	plane.subdivide_width = 2
	plane.subdivide_depth = 2
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/paint/water.gdshader")
	plane.material = mat
	water_mat = mat
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.position.y = WATER_Y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

# ---------- растительность ----------

var veg = preload("res://scripts/veg.gd").new()
var pv = preload("res://scripts/pveg.gd").new()
var player_rig: Node3D
var grass_mesh_vars: Array = []
var grass_cells := {}
var grass_timer := 0.0
var _sky_timer := 0.0
const GCELL := 16.0
const GRADIUS := 2

func _process(delta: float) -> void:
	if hero == null or joy == null:
		return
	var hp: Vector3 = hero.position + Vector3(0, 1.0, 0)
	var cp: Vector3 = rig.cam.global_position
	for m in veg.fade_list:
		m.set_shader_parameter("hero_pos", hp)
		m.set_shader_parameter("cam_pos", cp)
	for m in pv.fade_list:
		m.set_shader_parameter("hero_pos", hp)
		m.set_shader_parameter("cam_pos", cp)
	pv.mats["tuft"].set_shader_parameter("hero_pos", hp)
	_fps_t -= delta
	if _fps_t <= 0.0:
		_fps_t = 0.5
		fps_lbl.text = "FPS %d · вызовов %d · треуг. %.1f тыс." % [Engine.get_frames_per_second(), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0]
	flash.color.a = maxf(0.0, flash.color.a - delta * 0.6)
	if dead_t > 0.0:
		dead_t -= delta
		if dead_t <= 0.0:
			_respawn()
	_near_t -= delta
	if _near_t <= 0.0:
		_near_t = 0.25
		_update_near()
	hero.move_vec = joy.value if health > 0.0 else Vector2.ZERO
	hero.cam_yaw = rig.rotation.y
	# время суток: 1 игровой час за 75 секунд
	t_hours += delta / 75.0
	weather.step(delta / 75.0)
	weather.update_visual(rig.position)
	if t_hours >= 24.0:
		t_hours -= 24.0
		day_count += 1
	_sky_timer -= delta
	if _sky_timer <= 0.0:
		_sky_timer = 0.25
		_update_sky()
		_update_stats(0.25)
		weather.apply(veg.fade_list + pv.fade_list, terrain_mat, pv.mats["tuft"], water_mat)
		var lbl: String = hero.action_label()
		act_btn.visible = lbl != ""
		act_btn.text = lbl
	if player_rig == null:
		return
	grass_timer -= delta
	if grass_timer > 0.0:
		return
	grass_timer = 0.12
	var c := Vector2i(floori((player_rig.position.x + SIZE * 0.5) / GCELL), floori((player_rig.position.z + SIZE * 0.5) / GCELL))
	# удалить далёкие клетки
	for k in grass_cells.keys():
		if absi(k.x - c.x) > GRADIUS + 1 or absi(k.y - c.y) > GRADIUS + 1:
			grass_cells[k].queue_free()
			grass_cells.erase(k)
	# построить одну ближайшую недостающую клетку за раз
	var best := Vector2i.ZERO
	var best_d := 1e9
	for dz in range(-GRADIUS, GRADIUS + 1):
		for dx in range(-GRADIUS, GRADIUS + 1):
			var k := Vector2i(c.x + dx, c.y + dz)
			if grass_cells.has(k) or k.x < 0 or k.y < 0 or k.x >= int(SIZE / GCELL) or k.y >= int(SIZE / GCELL):
				continue
			var d := float(dx * dx + dz * dz)
			if d < best_d:
				best_d = d
				best = k
	if best_d < 1e9:
		_build_grass_cell(best)

## Проверка сезонов: тап по часам в правом верхнем углу перематывает время на 2 дня вперёд.
func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch and e.pressed:
		var vs := get_viewport().get_visible_rect().size
		if e.position.x > vs.x - 520.0 and e.position.y < 90.0:
			weather.fast_forward(48.0)
			get_viewport().set_input_as_handled()

func _update_stats(dt: float) -> void:
	hunger = maxf(0.0, hunger - 0.0004 * dt)
	thirst = maxf(0.0, thirst - 0.0007 * dt * (1.5 if hero.running else 1.0))
	var gh := dt / 75.0
	if health > 0.0:
		# кровотечение, голод, жажда, холод — урон; сытый и в тепле — заживает
		health -= bleed * 0.004 * dt
		bleed = maxf(0.0, bleed - 0.0015 * dt)
		if hunger <= 0.0 or thirst <= 0.0:
			health -= 0.0012 * dt
		if warmth < 0.1:
			health -= 0.001 * dt
		if bleed <= 0.01 and hunger > 0.2 and thirst > 0.2:
			health = minf(1.0, health + gh * (0.02 if hero.state != "sit" else 0.035))
		for k in injuries.keys():
			injuries[k] = float(injuries[k]) - gh
			if injuries[k] <= 0.0:
				injuries.erase(k)
		if health <= 0.0:
			health = 0.0
			_die("")
	msg_t -= dt
	var tc: float = weather.temp
	var soak: float = maxf(float(weather.wet) * 0.6, float(hero.soaked))
	var target_w := clampf(0.55 + tc * 0.025 - soak * 0.35 - weather.wind * 0.05 - (0.25 if hero.swimb > 0.5 else 0.0), 0.02, 0.95)
	warmth = lerpf(warmth, target_w, 0.01 * dt * 4.0)
	if hero.moving:
		var drain := 0.012
		if hero.running:
			drain = 0.05
		if hero.climbing > 0.5:
			drain = 0.04
		if hero.state == "climb":
			drain = 0.07
		if hero.swimb > 0.5:
			drain = 0.035
		stamina = maxf(0.0, stamina - drain * dt)
	else:
		stamina = minf(1.0, stamina + (0.11 if hero.state == "sit" else 0.05) * dt)
	var hh := int(t_hours)
	var mm := int((t_hours - hh) * 60.0)
	var temp := int(round(tc))
	var info := ""
	if bleed > 0.02:
		info += "Кровотечение! "
	if not injuries.is_empty():
		info += ", ".join(PackedStringArray(injuries.keys())) + " "
	var items := PackedStringArray()
	for k in inv.keys():
		if int(inv[k]) > 0:
			items.append("%s %d" % [PICK_NAME[k], inv[k]])
	if not items.is_empty():
		info += "· " + ", ".join(items)
	if msg_t > 0.0:
		info = msg + "   " + info
	hud.set_state([health, hunger, thirst, warmth, stamina], "%s, день %d · %02d:%02d · %d°C · %s" % [weather.season_name(), day_count, hh, mm, temp, weather.kind], info)

func _build_grass_cell(k: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = k.y * 7919 + k.x * 104729 + 13
	var x0 := k.x * GCELL - SIZE * 0.5
	var z0 := k.y * GCELL - SIZE * 0.5
	var per_var := []
	for v in grass_mesh_vars:
		per_var.append([])
	var step := 1.25
	var z := 0.0
	while z < GCELL:
		var x := 0.0
		while x < GCELL:
			var px := x0 + x + rng.randf_range(-0.4, 0.4)
			var pz := z0 + z + rng.randf_range(-0.4, 0.4)
			x += step
			var y := height(px, pz)
			if y < WATER_Y + 0.15:
				continue
			var fd := forest_density(px, pz)
			var slope := 1.0 - normal_at(px, pz).y
			if slope > 0.1 or rng.randf() > (1.0 - fd) * 0.85 + 0.22:
				continue
			var h1 := height(px + 1.0, pz)
			var h2 := height(px - 1.0, pz)
			var h3 := height(px, pz + 1.0)
			var h4 := height(px, pz - 1.0)
			if maxf(maxf(h1, h2), maxf(h3, h4)) - minf(minf(h1, h2), minf(h3, h4)) > 0.7:
				continue
			var s := rng.randf_range(0.9, 1.5)
			var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s))
			per_var[rng.randi() % grass_mesh_vars.size()].append(Transform3D(b, Vector3(px, y - 0.03, pz)))
		z += step
	var holder := Node3D.new()
	for vi in grass_mesh_vars.size():
		var xs: Array = per_var[vi]
		if xs.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = grass_mesh_vars[vi][0]
		mm.instance_count = xs.size()
		for i in xs.size():
			mm.set_instance_transform(i, xs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = (GRADIUS + 0.55) * GCELL
		mmi.visibility_range_end_margin = 8.0
		holder.add_child(mmi)
	add_child(holder)
	grass_cells[k] = holder

## Варианты: [mesh, высота]. Несколько вариантов на породу, чтобы лес не повторялся.
func _variants(kind: String) -> Array:
	var out := []
	match kind:
		"spruce":
			for i in 4: out.append(pv.spruce(100 + i))
		"spruce_dead":
			for i in 2: out.append(veg.spruce(200 + i, true))
		"pine":
			for i in 3: out.append(pv.pine(300 + i))
		"birch":
			for i in 3: out.append(pv.birch(400 + i))
		"bare":
			for i in 2: out.append(veg.branchy(500 + i, "bare"))
			out.append(veg.branchy(510, "bare_birch"))
		"bush":
			for i in 3: out.append(pv.bush(600 + i))
		"larch":
			for i in 3: out.append(pv.birch(1400 + i, "larch"))
		"aspen":
			for i in 3: out.append(pv.birch(1500 + i, "leaf"))
		"berry":
			for i in 3: out.append(veg.berry_bush(1600 + i))
		"mushroom":
			for i in 2: out.append(veg.mushroom(1700 + i, true))
			for i in 3: out.append(veg.mushroom(1710 + i, false))
		"anthill":
			out.append(veg.anthill(1800))
		"fern":
			for i in 3: out.append(veg.fern(700 + i))
		"grass":
			for i in 4: out.append(veg.grass(800 + i))
		"rock":
			for i in 8: out.append(pv.rock(900 + i))
		"pebble":
			for i in 3: out.append(pv.rock(950 + i))
		"reeds":
			for i in 3: out.append(veg.reeds(1200 + i))
		"twig":
			for i in 4: out.append(veg.twig(1300 + i))
		"stump":
			out.append(veg.stump(1000))
		"log":
			for i in 2: out.append(veg.log_fallen(1100 + i))
	return out

const TREE_KINDS := []
const NEAR_R := 30.0
var tree_grid := {}
var near_mesh := {}
var near_mmi := {}
var near_set := {}
var _near_at := Vector3(1e9, 0, 0)
var _near_t := 0.0
var _tree_id := 0

## Детальные деревья только вблизи: в радиусе NEAR_R дерево берётся из полной модели,
## а в дальнем MultiMesh его экземпляр прячется. Остальной лес — лёгкие модели.
func _update_near(force: bool = false) -> void:
	var c: Vector3 = rig.position
	if not force and Vector2(c.x - _near_at.x, c.z - _near_at.z).length() < 2.5:
		return
	_near_at = c
	var hide := Transform3D(Basis().scaled(Vector3(0.0001, 0.0001, 0.0001)), Vector3(0, -500, 0))
	var now := {}
	var by_key := {}
	var r2 := NEAR_R * NEAR_R
	var g0 := Vector2i(floori((c.x - NEAR_R) / 16.0), floori((c.z - NEAR_R) / 16.0))
	var g1 := Vector2i(floori((c.x + NEAR_R) / 16.0), floori((c.z + NEAR_R) / 16.0))
	for gz in range(g0.y, g1.y + 1):
		for gx in range(g0.x, g1.x + 1):
			var gk := Vector2i(gx, gz)
			if not tree_grid.has(gk):
				continue
			for rec in tree_grid[gk]:
				var t: Transform3D = rec[2]
				if (t.origin.x - c.x) * (t.origin.x - c.x) + (t.origin.z - c.z) * (t.origin.z - c.z) > r2:
					continue
				var id: int = rec[4]
				now[id] = rec
				if not near_set.has(id):
					rec[0].set_instance_transform(rec[1], hide)
				var key: String = rec[3]
				if not by_key.has(key):
					by_key[key] = []
				by_key[key].append(t)
	for id in near_set.keys():
		if not now.has(id):
			var rec: Array = near_set[id]
			rec[0].set_instance_transform(rec[1], rec[2])
	near_set = now
	for key in near_mmi.keys():
		if not by_key.has(key):
			near_mmi[key].visible = false
	for key in by_key.keys():
		if not near_mmi.has(key):
			var mmi := MultiMeshInstance3D.new()
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = near_mesh[key]
			mmi.multimesh = mm
			add_child(mmi)
			near_mmi[key] = mmi
		var mi: MultiMeshInstance3D = near_mmi[key]
		var xs: Array = by_key[key]
		mi.multimesh.instance_count = xs.size()
		for i in xs.size():
			mi.multimesh.set_instance_transform(i, xs[i])
		mi.visible = true

const PICK := ["berry", "mushroom", "twig", "pebble"]
const PICK_NAME := {"berry": "ягоды", "mushroom": "гриб", "amanita": "мухомор", "twig": "хворост", "pebble": "камень"}

func _add_pick(p: Vector3, kind: String, mm: MultiMesh, i: int) -> void:
	var k := Vector2i(floori(p.x / 8.0), floori(p.z / 8.0))
	if not pickables.has(k):
		pickables[k] = []
	pickables[k].append([p, kind, mm, i])

## Ближайшее, что можно подобрать (до 1,4 м).
func find_pick(p: Vector3) -> Array:
	var c := Vector2i(floori(p.x / 8.0), floori(p.z / 8.0))
	var best: Array = []
	var bd := 1.4 * 1.4
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var k := Vector2i(c.x + dx, c.y + dz)
			if not pickables.has(k):
				continue
			for it in pickables[k]:
				var q: Vector3 = it[0]
				var dd := Vector2(q.x - p.x, q.z - p.z).length_squared()
				if dd < bd:
					bd = dd
					best = it
	return best

func take_pick(it: Array) -> void:
	var q: Vector3 = it[0]
	var k := Vector2i(floori(q.x / 8.0), floori(q.z / 8.0))
	pickables[k].erase(it)
	var mm: MultiMesh = it[2]
	mm.set_instance_transform(it[3], Transform3D(Basis().scaled(Vector3(0.001, 0.001, 0.001)), q - Vector3(0, 5, 0)))
	var kind: String = it[1]
	match kind:
		"berry":
			hunger = minf(1.0, hunger + 0.05)
			thirst = minf(1.0, thirst + 0.03)
			_say("Съел горсть ягод")
		"mushroom":
			hunger = minf(1.0, hunger + 0.07)
			_say("Съел гриб")
		"amanita":
			health = maxf(0.05, health - 0.2)
			hunger = maxf(0.0, hunger - 0.05)
			flash.color.a = 0.25
			_say("Мухомор! Отравление")
		_:
			inv[kind] = int(inv.get(kind, 0)) + 1
			_say("+1 %s" % PICK_NAME[kind])

func near_water(p: Vector3) -> bool:
	for a in 8:
		var v := Vector3(cos(a * TAU / 8.0), 0, sin(a * TAU / 8.0)) * 1.3
		if height(p.x + v.x, p.z + v.z) < WATER_Y - 0.05:
			return true
	return false

func drink() -> void:
	thirst = minf(1.0, thirst + 0.35)
	_say("Напился")

func bandage() -> void:
	bleed = 0.0
	for k in injuries.keys():
		if k != "перелом ноги":
			injuries[k] = minf(float(injuries[k]), 24.0)
	_say("Раны перевязаны")

func _say(t: String) -> void:
	msg = t
	msg_t = 3.0

## Ближайший ствол (по сетке препятствий) или INF.
func nearest_tree(p: Vector3, r: float) -> Vector3:
	var c := Vector2i(floori(p.x / 8.0), floori(p.z / 8.0))
	var best := Vector3.INF
	var bd := r * r
	var n := int(ceil(r / 8.0))
	for dz in range(-n, n + 1):
		for dx in range(-n, n + 1):
			var k := Vector2i(c.x + dx, c.y + dz)
			if not blockers.has(k):
				continue
			for b in blockers[k]:
				var dd: float = (b.x - p.x) * (b.x - p.x) + (b.y - p.z) * (b.y - p.z)
				if dd < bd:
					bd = dd
					best = Vector3(b.x, 0, b.y)
	return best

## Удар зверя: часть тела, кровотечение, переломы, отбрасывание.
func hurt(amount: float, from: Vector3, kind: String) -> void:
	if health <= 0.0:
		return
	var big := kind in ["bear", "tiger"]
	var roll := randf()
	var part := "нога"
	if roll < (0.2 if big else 0.06):
		part = "голова"
	elif roll < (0.45 if big else 0.2):
		part = "грудь"
	elif roll < 0.65:
		part = "рука"
	var dmg := amount * (1.7 if big and part in ["голова", "грудь"] else 1.0)
	if hero.state == "sit":
		hero._stand_up()
	health = maxf(0.0, health - dmg)
	bleed = minf(1.0, bleed + dmg * 0.6)
	var key := "рана: " + part
	injuries[key] = float(injuries.get(key, 0.0)) + 24.0 + dmg * 80.0
	if part == "нога" and (big or kind == "boar") and randf() < 0.35:
		injuries["перелом ноги"] = 96.0
	var away: Vector3 = hero.position - from
	away.y = 0
	hero.vel += away.normalized() * (6.0 if big else 3.0)
	hero.land_t = 0.4
	hero.land_k = 0.5
	flash.color.a = clampf(0.25 + dmg, 0.0, 0.6)
	if health <= 0.0:
		_die(kind)

func _die(kind: String) -> void:
	hero.state = "dead"
	dead_t = 6.0
	var who: String = {"wolf": "волки", "bear": "медведь", "tiger": "тигр", "boar": "кабан"}.get(kind, "")
	dead_lbl.text = "Вы погибли" + ("\n" + who if who != "" else "")
	dead_lbl.visible = true

func _respawn() -> void:
	dead_lbl.visible = false
	health = 0.6
	bleed = 0.0
	injuries.clear()
	hunger = maxf(hunger, 0.5)
	thirst = maxf(thirst, 0.5)
	warmth = maxf(warmth, 0.5)
	stamina = 1.0
	for k in inv.keys():
		inv[k] = int(inv[k]) / 2
	hero.revive(_find_start())

## Множитель скорости от ран: хромота при ранах ноги, сильнее при переломе.
func move_factor() -> float:
	var f := 1.0
	if injuries.has("перелом ноги"):
		f = 0.5
	elif injuries.has("рана: нога"):
		f = 0.78
	return f * (0.6 + 0.4 * clampf(health * 2.0, 0.0, 1.0))

const BLOCK_R := {"spruce": 0.4, "pine": 0.32, "birch": 0.28, "bare": 0.3, "spruce_dead": 0.3, "stump": 0.45, "rock": 0.5, "boulder": 0.6, "larch": 0.32, "aspen": 0.26}

func _scatter_all() -> void:
	# вид, попыток на клетку 32 м, масштаб, дальность видимости, тень, правило
	var rules := [
		["spruce", 30, Vector2(0.75, 1.15), 80.0, true, "spruce_t"],
		["pine", 14, Vector2(0.85, 1.15), 80.0, true, "pine_t"],
		["birch", 16, Vector2(0.8, 1.15), 80.0, true, "birch_t"],
		["birch", 5, Vector2(0.8, 1.15), 80.0, true, "edge"],
		["bare", 3, Vector2(0.8, 1.2), 80.0, true, "edge"],
		["spruce_dead", 2, Vector2(0.7, 1.0), 80.0, true, "tree"],
		["spruce", 8, Vector2(0.18, 0.35), 60.0, true, "under"],
		["bush", 30, Vector2(0.8, 1.5), 60.0, false, "under"],
		["fern", 70, Vector2(0.7, 1.2), 45.0, false, "fern"],
		["reeds", 14, Vector2(0.8, 1.4), 80.0, false, "reed"],
		["twig", 60, Vector2(0.8, 1.3), 40.0, false, "under"],
		["pebble", 40, Vector2(0.15, 0.45), 40.0, false, "pebble"],
		["rock", 12, Vector2(0.5, 2.2), 85.0, true, "rock"],
		["rock", 14, Vector2(1.8, 4.6), 95.0, true, "boulder"],
		["stump", 3, Vector2(0.8, 1.2), 60.0, true, "under"],
		["log", 2, Vector2(0.9, 1.1), 70.0, true, "under"],
		["larch", 8, Vector2(0.85, 1.15), 80.0, true, "larch_t"],
		["aspen", 8, Vector2(0.8, 1.15), 80.0, true, "edge"],
		["berry", 25, Vector2(0.7, 1.3), 40.0, false, "under"],
		["mushroom", 14, Vector2(0.8, 1.4), 30.0, false, "under"],
		["anthill", 1, Vector2(0.8, 1.2), 50.0, true, "under"],
	]
	var cache := {}
	var cache_lod := {}
	for r in rules:
		if not cache.has(r[0]):
			cache[r[0]] = _variants(r[0])
			if r[0] in TREE_KINDS:
				veg.lod = true
				cache_lod[r[0]] = _variants(r[0])
				veg.lod = false
	var cells := int(SIZE / CELL)
	for cz in cells:
		for cx in cells:
			var rng := RandomNumberGenerator.new()
			rng.seed = cz * 1000 + cx
			var x0 := cx * CELL - SIZE * 0.5
			var z0 := cz * CELL - SIZE * 0.5
			for r in rules:
				var vars: Array = cache[r[0]]
				var per_var := []
				for v in vars:
					per_var.append([])
				var pick_kind: String = r[0] if r[0] in PICK else ""
				for k in int(r[1]) * 4:
					var x := x0 + rng.randf() * CELL
					var z := z0 + rng.randf() * CELL
					if not _accept(r[5], x, z, rng):
						continue
					var vi := rng.randi() % vars.size()
					var sc: Vector2 = r[2]
					var s := rng.randf_range(sc.x, sc.y)
					var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.1), s))
					if r[0] == "log":
						# наклон по рельефу: концы лежат на земле
						var ax0: Vector3 = b.x.normalized()
						var h1 := height(x + ax0.x * 2.5, z + ax0.z * 2.5)
						var h0 := height(x - ax0.x * 2.5, z - ax0.z * 2.5)
						var tilt := atan2(h1 - h0, 5.0)
						b = Basis(ax0.cross(Vector3.UP).normalized(), tilt) * b
					per_var[vi].append(Transform3D(b, Vector3(x, height(x, z) - 0.05, z)))
					var by: float = height(x, z) - 0.05
					if r[0] == "rock":
						# камень — твёрдый купол: на него можно встать или залезть
						var rsc: Vector3 = vars[vi][2]
						var hr: float = (rsc.x + rsc.z) * 0.45 * s
						var ht: float = rsc.y * 0.9 * s
						if ht > 0.12:
							_add_solid([0, Vector3(x, by, z), Vector3.ZERO, hr, ht])
					elif r[0] == "stump":
						_add_solid([2, Vector3(x, by, z), Vector3.ZERO, 0.45 * s, 0.75 * s])
					elif r[0] == "log":
						var ax1: Vector3 = b.x
						var o := Vector3(x, by, z)
						_add_solid([1, o - ax1 * 2.3 + b.y * 0.3, o + ax1 * 2.3 + b.y * 0.28, 0.31 * s, 0.0])
					else:
						var br: float = BLOCK_R.get(r[0], 0.0)
						if br > 0.0 and not (r[0] == "spruce" and r[5] == "under"):
							_add_blocker(x, z, br * s)
					if r[0] == "log":
						var ax: Vector3 = b.x.normalized()
						var yaw := atan2(ax.z, -ax.x)
						for t in [-1.2, 1.2]:
							var sx: float = x + ax.x * t
							var sz: float = z + ax.z * t
							_add_seat(Vector3(sx, height(sx, sz) + 0.62 * s, sz), yaw)
					if r[0] == "stump":
						_add_seat(Vector3(x, height(x, z) + 0.7 * s, z), rng.randf() * TAU)
				for vi in vars.size():
					var xs: Array = per_var[vi]
					if xs.is_empty():
						continue
					var mm := MultiMesh.new()
					mm.transform_format = MultiMesh.TRANSFORM_3D
					var is_tree: bool = cache_lod.has(r[0])
					mm.mesh = cache_lod[r[0]][vi][0] if is_tree else vars[vi][0]
					mm.instance_count = xs.size()
					for i in xs.size():
						mm.set_instance_transform(i, xs[i])
					var mmi := MultiMeshInstance3D.new()
					mmi.multimesh = mm
					mmi.visibility_range_end = r[3]
					mmi.visibility_range_end_margin = 10.0
					mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if r[4] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					add_child(mmi)
					if is_tree:
						var key: String = r[0] + str(vi)
						near_mesh[key] = vars[vi][0]
						for i in xs.size():
							var o: Vector3 = xs[i].origin
							var gk := Vector2i(floori(o.x / 16.0), floori(o.z / 16.0))
							if not tree_grid.has(gk):
								tree_grid[gk] = []
							_tree_id += 1
							tree_grid[gk].append([mm, i, xs[i], key, _tree_id])
					if pick_kind != "":
						var pk := pick_kind
						if pk == "mushroom" and vi < 2:
							pk = "amanita"
						for i in xs.size():
							_add_pick(xs[i].origin, pk, mm, i)

func _accept(kind: String, x: float, z: float, rng: RandomNumberGenerator) -> bool:
	var y := height(x, z)
	if kind == "boulder":
		return (1.0 - normal_at(x, z).y) > 0.3 and y > WATER_Y + 0.5 and rng.randf() < 0.35
	if kind == "reed":
		return y > WATER_Y - 0.5 and y < WATER_Y + 0.35 and rng.randf() < 0.9
	if kind == "pebble":
		return y > WATER_Y - 0.6 and y < WATER_Y + 1.2 or rng.randf() < 0.15
	if y < WATER_Y + 0.3:
		return kind == "rock" and y > WATER_Y - 0.8 and rng.randf() < 0.3
	var slope := 1.0 - normal_at(x, z).y
	var fd := forest_density(x, z)
	var bio := biome(x, z)
	match kind:
		"spruce_t":
			return slope < 0.25 and rng.randf() < fd * fd * clampf(1.0 - bio * 0.8 - 0.2, 0.15, 1.0)
		"pine_t":
			return slope < 0.25 and rng.randf() < fd * clampf(0.3 + bio * 0.8, 0.05, 1.0)
		"birch_t":
			return slope < 0.25 and rng.randf() < fd * clampf(0.15 - bio * 0.9, 0.0, 1.0)
		"larch_t":
			return slope < 0.3 and rng.randf() < fd * clampf(0.2 + bio * 0.6, 0.05, 0.8)
		"tree":
			return slope < 0.25 and rng.randf() < fd * fd
		"edge":
			return slope < 0.25 and rng.randf() < fd * (1.0 - fd) * 3.0
		"under":
			return slope < 0.3 and rng.randf() < fd * 0.8
		"fern":
			return slope < 0.3 and rng.randf() < fd * 0.7
		"grass":
			return slope < 0.32 and rng.randf() < (1.0 - fd) * 0.9 + 0.15
		"rock":
			return slope > 0.15 or rng.randf() < 0.15 + maxf(bio, 0.0) * 0.6
		"boulder":
			return slope > 0.3 and rng.randf() < 0.3
	return true
