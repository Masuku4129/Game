extends Node3D
## Этап 2: кусок тайги 512×512 м в стиле 4: рельеф с обрывами и рекой,
## деревья с ветками-геометрией и хвоей/листвой из текстур.

const SIZE := 512.0
const SEG := 256
const WATER_Y := -2.0
const CELL := 32.0

var n_hill := FastNoiseLite.new()
var n_cliff := FastNoiseLite.new()
var n_detail := FastNoiseLite.new()
var n_forest := FastNoiseLite.new()

func _ready() -> void:
	_setup_noise()
	_make_environment()
	_make_terrain()
	_make_water()
	_scatter_all()
	var rig := preload("res://scripts/camera_rig.gd").new()
	rig.bounds = SIZE * 0.5 - 20.0
	rig.height_func = height
	add_child(rig)

func _setup_noise() -> void:
	n_hill.seed = 1640; n_hill.frequency = 0.006; n_hill.fractal_octaves = 4
	n_cliff.seed = 77; n_cliff.frequency = 0.009; n_cliff.fractal_octaves = 2
	n_detail.seed = 5; n_detail.frequency = 0.05; n_detail.fractal_octaves = 3
	n_forest.seed = 909; n_forest.frequency = 0.02; n_forest.fractal_octaves = 3

func river_dist(x: float, z: float) -> float:
	return absf(z - 70.0 * sin(x / 95.0) - 20.0)

func height(x: float, z: float) -> float:
	var h := n_hill.get_noise_2d(x, z) * 12.0 + n_detail.get_noise_2d(x, z) * 1.0 + 3.0
	var c := n_cliff.get_noise_2d(x, z)
	# ступени-обрывы: резкий подъём на узкой полосе шума
	h += smoothstep(0.10, 0.15, c) * 8.0 + smoothstep(0.32, 0.36, c) * 7.0
	var r := 1.0 - smoothstep(7.0, 32.0, river_dist(x, z))
	return lerpf(h, WATER_Y - 2.5, r)

func normal_at(x: float, z: float) -> Vector3:
	var e := 1.0
	return Vector3(height(x - e, z) - height(x + e, z), 2.0 * e, height(x, z - e) - height(x, z + e)).normalized()

func forest_density(x: float, z: float) -> float:
	return clampf(n_forest.get_noise_2d(x, z) * 1.6 + 0.55, 0.0, 1.0)

func _make_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.50, 0.58, 0.66)
	sky_mat.sky_horizon_color = Color(0.72, 0.75, 0.74)
	sky_mat.ground_horizon_color = Color(0.60, 0.62, 0.58)
	sky_mat.ground_bottom_color = Color(0.25, 0.27, 0.23)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.66, 0.70, 0.69)
	env.fog_density = 0.004
	env.fog_sky_affect = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.light_energy = 1.5
	sun.rotation_degrees = Vector3(-42, 40, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(sun)

func _make_terrain() -> void:
	var n := SEG + 1
	var step := SIZE / SEG
	var half := SIZE * 0.5
	var verts := PackedVector3Array(); verts.resize(n * n)
	var norms := PackedVector3Array(); norms.resize(n * n)
	var cols := PackedColorArray(); cols.resize(n * n)
	for iz in n:
		for ix in n:
			var x := ix * step - half
			var z := iz * step - half
			var y := height(x, z)
			var i := iz * n + ix
			verts[i] = Vector3(x, y, z)
			norms[i] = normal_at(x, z)
			var fd := forest_density(x, z)
			var grass := clampf(1.0 - fd * 1.4, 0.0, 1.0)
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
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)

func _make_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(SIZE, SIZE)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.24, 0.24, 0.88)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.04
	mat.metallic = 0.5
	plane.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.position.y = WATER_Y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

# ---------- растительность ----------

var veg = preload("res://scripts/veg.gd").new()

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
			for i in 4: out.append(veg.rock(900 + i))
		"stump":
			out.append(veg.stump(1000))
		"log":
			for i in 2: out.append(veg.log_fallen(1100 + i))
	return out

func _scatter_all() -> void:
	# вид, попыток на клетку 32 м, масштаб, дальность видимости, тень, правило
	var rules := [
		["spruce", 30, Vector2(0.75, 1.15), 120.0, true, "tree"],
		["pine", 9, Vector2(0.85, 1.15), 120.0, true, "tree"],
		["birch", 9, Vector2(0.8, 1.15), 120.0, true, "edge"],
		["bare", 3, Vector2(0.8, 1.2), 120.0, true, "edge"],
		["spruce_dead", 2, Vector2(0.7, 1.0), 120.0, true, "tree"],
		["spruce", 8, Vector2(0.18, 0.35), 60.0, true, "under"],
		["bush", 20, Vector2(0.8, 1.5), 60.0, false, "under"],
		["fern", 70, Vector2(0.7, 1.2), 45.0, false, "fern"],
		["grass", 900, Vector2(0.35, 0.6), 36.0, false, "grass"],
		["rock", 10, Vector2(0.5, 2.2), 100.0, true, "rock"],
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
	if y < WATER_Y + 0.3:
		return kind == "rock" and y > WATER_Y - 0.8 and rng.randf() < 0.3
	var slope := 1.0 - normal_at(x, z).y
	var fd := forest_density(x, z)
	match kind:
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
			return slope > 0.15 or rng.randf() < 0.15
	return true
