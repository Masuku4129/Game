extends Node3D
## Этап 2: кусок тайги 512×512 м в стиле 4: рельеф с обрывами и рекой,
## деревья с ветками-геометрией и хвоей/листвой из текстур.

const SIZE := 512.0
const SEG := 384
const WATER_Y := -2.0
const CELL := 32.0

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

func _ready() -> void:
	_setup_noise()
	_make_environment()
	_make_terrain()
	_make_water()
	_scatter_all()
	grass_mesh_vars = [veg.grass_patch(1500), veg.grass_patch(1501), veg.grass_patch(1502), veg.grass_patch(1503), veg.grass_patch(1504)]
	hero = preload("res://scripts/hero.gd").new()
	hero.main = self
	add_child(hero)
	hero.position = _find_start()
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
	n_hill.seed = 1640; n_hill.frequency = 0.006; n_hill.fractal_octaves = 4
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
	var h := n_hill.get_noise_2d(x, z) * (12.0 + rocky * 9.0) + n_detail.get_noise_2d(x, z) * 1.0 + 3.0
	var c := n_cliff.get_noise_2d(x, z)
	# ступени-обрывы: резкий подъём на узкой полосе шума
	var t1 := smoothstep(0.09, 0.16, c)
	var t2 := smoothstep(0.31, 0.37, c)
	h += t1 * 8.0 + t2 * 7.0
	# рваная скалистая поверхность обрывов: крупные и мелкие сколы только на самом уступе
	var face := (t1 * (1.0 - t1) + t2 * (1.0 - t2)) * 4.0
	h += n_crag.get_noise_2d(x, z) * 3.2 * face + n_crag2.get_noise_2d(x, z) * 1.1 * face
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
	sun.directional_shadow_max_distance = 45.0
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
	sun.light_energy = 1.6 * smoothstep(0.0, 0.3, e)
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
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = hor
	sky_mat.ground_horizon_color = hor.darkened(0.15)
	sky_mat.ground_bottom_color = hor.darkened(0.6)
	env.fog_light_color = hor.darkened(0.08)
	env.ambient_light_energy = lerpf(0.22, 0.7, d)
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
			cols[i] = Color(grass, mud, leaves)
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
	mat.shader = preload("res://shaders/terrain.gdshader")
	mat.set_shader_parameter("forest", load("res://textures/ground_forest.png"))
	mat.set_shader_parameter("grass", load("res://textures/ground_grass.png"))
	mat.set_shader_parameter("rock", load("res://textures/ground_rock.png"))
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)

func _make_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(SIZE, SIZE)
	plane.subdivide_width = 2
	plane.subdivide_depth = 2
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/water.gdshader")
	mat.set_shader_parameter("wave", load("res://textures/water_wave.png"))
	plane.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.position.y = WATER_Y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

# ---------- растительность ----------

var veg = preload("res://scripts/veg.gd").new()
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
	hero.move_vec = joy.value
	hero.cam_yaw = rig.rotation.y
	# время суток: 1 игровой час за 75 секунд
	t_hours += delta / 75.0
	if t_hours >= 24.0:
		t_hours -= 24.0
		day_count += 1
	_sky_timer -= delta
	if _sky_timer <= 0.0:
		_sky_timer = 0.25
		_update_sky()
		_update_stats(0.25)
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

func _update_stats(dt: float) -> void:
	hunger = maxf(0.0, hunger - 0.0004 * dt)
	var target_w := 0.28 + 0.55 * day_factor
	warmth = lerpf(warmth, target_w, 0.01 * dt * 4.0)
	if hero.moving:
		stamina = maxf(0.0, stamina - 0.012 * dt)
	else:
		stamina = minf(1.0, stamina + 0.05 * dt)
	var hh := int(t_hours)
	var mm := int((t_hours - hh) * 60.0)
	var temp := int(round(lerpf(-9.0, 7.0, day_factor)))
	hud.set_state(hunger, warmth, stamina, "День %d · %02d:%02d · %d°C" % [day_count, hh, mm, temp])

func _build_grass_cell(k: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = k.y * 7919 + k.x * 104729 + 13
	var x0 := k.x * GCELL - SIZE * 0.5
	var z0 := k.y * GCELL - SIZE * 0.5
	var per_var := []
	for v in grass_mesh_vars:
		per_var.append([])
	var step := 1.4
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
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		holder.add_child(mmi)
	add_child(holder)
	grass_cells[k] = holder

## Варианты: [mesh, высота]. Несколько вариантов на породу, чтобы лес не повторялся.
func _variants(kind: String) -> Array:
	var out := []
	match kind:
		"spruce":
			for i in 4: out.append(veg.spruce(100 + i))
		"spruce_dead":
			for i in 2: out.append(veg.spruce(200 + i, true))
		"pine":
			for i in 3: out.append(veg.branchy(300 + i, "pine"))
		"birch":
			for i in 3: out.append(veg.branchy(400 + i, "birch"))
		"bare":
			for i in 2: out.append(veg.branchy(500 + i, "bare"))
			out.append(veg.branchy(510, "bare_birch"))
		"bush":
			for i in 3: out.append(veg.bush(600 + i))
		"fern":
			for i in 3: out.append(veg.fern(700 + i))
		"grass":
			for i in 4: out.append(veg.grass(800 + i))
		"rock":
			for i in 8: out.append(veg.rock(900 + i))
		"pebble":
			for i in 3: out.append(veg.rock(950 + i))
		"reeds":
			for i in 3: out.append(veg.reeds(1200 + i))
		"twig":
			for i in 4: out.append(veg.twig(1300 + i))
		"stump":
			out.append(veg.stump(1000))
		"log":
			for i in 2: out.append(veg.log_fallen(1100 + i))
	return out

func _scatter_all() -> void:
	# вид, попыток на клетку 32 м, масштаб, дальность видимости, тень, правило
	var rules := [
		["spruce", 30, Vector2(0.75, 1.15), 90.0, true, "spruce_t"],
		["pine", 14, Vector2(0.85, 1.15), 90.0, true, "pine_t"],
		["birch", 16, Vector2(0.8, 1.15), 90.0, true, "birch_t"],
		["birch", 5, Vector2(0.8, 1.15), 90.0, true, "edge"],
		["bare", 3, Vector2(0.8, 1.2), 90.0, true, "edge"],
		["spruce_dead", 2, Vector2(0.7, 1.0), 90.0, true, "tree"],
		["spruce", 8, Vector2(0.18, 0.35), 60.0, true, "under"],
		["bush", 20, Vector2(0.8, 1.5), 60.0, false, "under"],
		["fern", 70, Vector2(0.7, 1.2), 45.0, false, "fern"],
		["reeds", 14, Vector2(0.8, 1.4), 80.0, false, "reed"],
		["twig", 40, Vector2(0.8, 1.3), 40.0, false, "under"],
		["pebble", 40, Vector2(0.15, 0.45), 40.0, false, "pebble"],
		["rock", 12, Vector2(0.5, 2.2), 85.0, true, "rock"],
		["rock", 14, Vector2(1.8, 4.6), 110.0, true, "boulder"],
		["stump", 2, Vector2(0.8, 1.2), 60.0, true, "under"],
		["log", 1, Vector2(0.9, 1.1), 70.0, true, "under"],
	]
	var cache := {}
	for r in rules:
		if not cache.has(r[0]):
			cache[r[0]] = _variants(r[0])
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
				for k in int(r[1]):
					var x := x0 + rng.randf() * CELL
					var z := z0 + rng.randf() * CELL
					if not _accept(r[5], x, z, rng):
						continue
					var vi := rng.randi() % vars.size()
					var sc: Vector2 = r[2]
					var s := rng.randf_range(sc.x, sc.y)
					var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.1), s))
					per_var[vi].append(Transform3D(b, Vector3(x, height(x, z) - 0.05, z)))
				for vi in vars.size():
					var xs: Array = per_var[vi]
					if xs.is_empty():
						continue
					var mm := MultiMesh.new()
					mm.transform_format = MultiMesh.TRANSFORM_3D
					mm.mesh = vars[vi][0]
					mm.instance_count = xs.size()
					for i in xs.size():
						mm.set_instance_transform(i, xs[i])
					var mmi := MultiMeshInstance3D.new()
					mmi.multimesh = mm
					mmi.visibility_range_end = r[3]
					mmi.visibility_range_end_margin = 10.0
					mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
					mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if r[4] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					add_child(mmi)

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
