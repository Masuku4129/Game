extends Node3D

const WORLD_EXTENT := 90.0
const GRID_CELLS := 144
const TREE_COUNT := 1050
const WIND_NEAR_RADIUS_SQUARED := 42.0 * 42.0
const PLAYER_SPEED := 5.5
const PLAYER_ACCELERATION := 22.0
const PLAYER_DECELERATION := 28.0
const CAMERA_OFFSET := Vector3(10.2, 25.0, 10.2)
const CAMERA_FOV := 44.0

@export_enum("spring", "summer", "autumn", "winter") var active_season: String = "summer"
const HUMANOID_RIG = preload("res://scripts/animation/procedural_humanoid.gd")
const SURFACE_SIMULATION = preload("res://scripts/environment/surface_simulation.gd")

var terrain_noise := FastNoiseLite.new()
var detail_noise := FastNoiseLite.new()
var player: CharacterBody3D
var camera: Camera3D
var player_visual: Node3D
var touch_vector := Vector2.ZERO
var touch_origin := Vector2.ZERO
var active_touch := -1
var hud_label: Label
var joystick: Control
var weather_button: Button
var season_button: Button
var environment_instances: Array[MultiMeshInstance3D] = []
var asset_mesh_cache: Dictionary = {}
var asset_base_materials: Dictionary = {}
var debug_move_input := Vector2.ZERO
var debug_move_direction := Vector3.ZERO
var terrain_material: ShaderMaterial
var terrain_shape: HeightMapShape3D
var surface_simulation: SurfaceSimulation
var terrain_collision_update_clock := 0.0
var weather_particles: GPUParticles3D
var weather_mode := "clear"
var wind_clock := 0.0
var wind_update_clock := 0.0
var wind_update_interval := 0.20
var puddle_update_clock := 0.0
var wind_batches: Array[Dictionary] = []
var footprint_nodes: Array[MeshInstance3D] = []
var footprint_distance := 0.0
var footprint_side := 0
var puddle_nodes: Array[MeshInstance3D] = []
var snow_accumulation := 0.0
var wetness_accumulation := 0.0
var last_environment_wetness := -1.0
var last_environment_snow := -1.0


func _ready() -> void:
	set_physics_process(true)
	_setup_noise()
	surface_simulation = SURFACE_SIMULATION.new()
	surface_simulation.initialize(WORLD_EXTENT, _height_at)
	_create_environment()
	_create_terrain()
	_create_forest()
	_create_ground_cover()
	_create_puddles()
	_create_player()
	_create_camera()
	_create_hud()


func _setup_noise() -> void:
	terrain_noise.seed = 4129
	terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	terrain_noise.frequency = 0.026
	terrain_noise.fractal_octaves = 5
	terrain_noise.fractal_gain = 0.48
	terrain_noise.fractal_lacunarity = 2.05
	detail_noise.seed = 7813
	detail_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	detail_noise.frequency = 0.12
	detail_noise.fractal_octaves = 3


func _height_at(x: float, z: float) -> float:
	var broad := terrain_noise.get_noise_2d(x, z) * 5.8
	var ridge := terrain_noise.get_noise_2d(x * 0.52 + 300.0, z * 0.52 - 120.0)
	var detail := detail_noise.get_noise_2d(x, z) * 0.72
	var drainage := absf(terrain_noise.get_noise_2d(x * 0.31 + 90.0, z * 0.31)) * 1.25
	return broad + ridge * 2.1 + detail - drainage

func _terrain_normal_at(x: float, z: float) -> Vector3:
	var sample := 0.35
	var slope_x := (_height_at(x + sample, z) - _height_at(x - sample, z)) / (sample * 2.0)
	var slope_z := (_height_at(x, z + sample) - _height_at(x, z - sample)) / (sample * 2.0)
	return Vector3(-slope_x, 1.0, -slope_z).normalized()


func _create_environment() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.12, 0.22, 0.29)
	sky_material.sky_horizon_color = Color(0.62, 0.68, 0.65)
	sky_material.ground_bottom_color = Color(0.10, 0.13, 0.11)
	sky_material.ground_horizon_color = Color(0.39, 0.44, 0.38)
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.72
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.58, 0.64, 0.61)
	environment.fog_density = 0.0028
	world.environment = environment
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -28.0, 0.0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 48.0
	add_child(sun)


func _create_terrain() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := WORLD_EXTENT * 2.0 / float(GRID_CELLS)

	for z in range(GRID_CELLS):
		for x in range(GRID_CELLS):
			var x0 := -WORLD_EXTENT + float(x) * step
			var z0 := -WORLD_EXTENT + float(z) * step
			var x1 := x0 + step
			var z1 := z0 + step
			var p00 := Vector3(x0, _height_at(x0, z0), z0)
			var p10 := Vector3(x1, _height_at(x1, z0), z0)
			var p01 := Vector3(x0, _height_at(x0, z1), z1)
			var p11 := Vector3(x1, _height_at(x1, z1), z1)
			_add_terrain_triangle(surface, p00, p01, p10)
			_add_terrain_triangle(surface, p10, p01, p11)

	surface.generate_normals()
	var terrain_mesh := surface.commit()
	var terrain := MeshInstance3D.new()
	terrain.mesh = terrain_mesh
	terrain_material = ShaderMaterial.new()
	var terrain_shader := Shader.new()
	terrain_shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D ground_albedo : source_color, repeat_enable;
uniform float snow_cover = 0.0;
uniform float surface_wetness = 0.0;
uniform sampler2D surface_state_texture : filter_linear, repeat_disable;
varying vec4 terrain_vertex_color;
varying vec4 local_surface_state;
void vertex() {
    terrain_vertex_color = COLOR;
    local_surface_state = textureLod(surface_state_texture, UV2, 0.0);
    VERTEX.y += local_surface_state.r * 0.42 - local_surface_state.b * 0.10 - local_surface_state.a * 0.035;
}
void fragment() {
    vec3 surface_color = texture(ground_albedo, UV * 1.0).rgb;
    vec3 ground = surface_color * terrain_vertex_color.rgb;
    float snow_amount = clamp(local_surface_state.r, 0.0, 1.0);
    float wet_amount = clamp(local_surface_state.g, 0.0, 1.0);
    float track_darkening = local_surface_state.b * 0.22;
    vec3 mud = ground * vec3(0.48, 0.39, 0.29);
    ground = mix(ground, mud, clamp(wet_amount * 0.72 + local_surface_state.a * 0.18, 0.0, 0.82));
    ground *= 1.0 - track_darkening;
    ground = mix(ground, vec3(0.78, 0.84, 0.88), snow_amount);
    ALBEDO = mix(ground, ground * vec3(0.66, 0.70, 0.72), wet_amount * 0.28);
    ROUGHNESS = mix(0.97, 0.22, wet_amount * 0.72);
}
"""
	terrain_material.shader = terrain_shader
	terrain_material.set_shader_parameter("ground_albedo", _make_ground_texture())
	terrain_material.set_shader_parameter("surface_state_texture", surface_simulation.get_texture())
	terrain.material_override = terrain_material
	add_child(terrain)

	var terrain_body := StaticBody3D.new()
	terrain_body.name = "TerrainCollision"
	var terrain_collision := CollisionShape3D.new()
	terrain_shape = HeightMapShape3D.new()
	terrain_shape.map_width = GRID_CELLS + 1
	terrain_shape.map_depth = GRID_CELLS + 1
	var height_data := PackedFloat32Array()
	height_data.resize((GRID_CELLS + 1) * (GRID_CELLS + 1))
	for z in range(GRID_CELLS + 1):
		for x in range(GRID_CELLS + 1):
			var sample_x := -WORLD_EXTENT + float(x) * step
			var sample_z := -WORLD_EXTENT + float(z) * step
			height_data[z * (GRID_CELLS + 1) + x] = _height_at(sample_x, sample_z) / step
	terrain_shape.map_data = height_data
	terrain_collision.shape = terrain_shape
	# HeightMapShape3D uses one local unit per sample; uniform scaling matches
	# the visual terrain grid while preserving the correct world-space heights.
	terrain_collision.scale = Vector3.ONE * step
	terrain_body.add_child(terrain_collision)
	add_child(terrain_body)


func _update_terrain_collision() -> void:
	if terrain_shape == null or surface_simulation == null:
		return
	var step := WORLD_EXTENT * 2.0 / float(GRID_CELLS)
	var width := GRID_CELLS + 1
	var height_data := PackedFloat32Array()
	height_data.resize(width * width)
	for z in range(width):
		for x in range(width):
			var world_x := -WORLD_EXTENT + float(x) * step
			var world_z := -WORLD_EXTENT + float(z) * step
			var displaced_height := _height_at(world_x, world_z) + surface_simulation.get_height_offset(world_x, world_z)
			height_data[z * width + x] = displaced_height / step
	terrain_shape.map_data = height_data


func _make_ground_texture() -> Texture2D:
	var image := Image.create(512, 512, false, Image.FORMAT_RGBA8)
	var broad_noise := FastNoiseLite.new()
	broad_noise.seed = 61021
	broad_noise.frequency = 0.018
	broad_noise.fractal_octaves = 4
	var grain_noise := FastNoiseLite.new()
	grain_noise.seed = 61022
	grain_noise.frequency = 0.31
	grain_noise.fractal_octaves = 2
	for y in range(512):
		for x in range(512):
			var u := float(x) / 512.0
			var v := float(y) / 512.0
			var broad := broad_noise.get_noise_2d(float(x), float(y))
			var grain := grain_noise.get_noise_2d(float(x) * 1.7, float(y) * 1.7)
			var grit := detail_noise.get_noise_2d(float(x) * 0.73, float(y) * 0.73)
			var damp := clampf(0.46 + broad * 0.17 + grit * 0.12, 0.16, 0.78)
			var value := grain * 0.035
			var moss_mix := clampf((broad + grit * 0.35 + 0.22) * 0.5, 0.0, 0.34)
			var soil := Color(0.20 + damp * 0.18 + value, 0.145 + damp * 0.13 + value, 0.095 + damp * 0.075 + value)
			var moss := Color(0.105 + damp * 0.10, 0.145 + damp * 0.13, 0.075 + damp * 0.06)
			image.set_pixel(x, y, soil.lerp(moss, moss_mix))
	return ImageTexture.create_from_image(image)


func _add_terrain_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	for point in [a, b, c]:
		var variation := detail_noise.get_noise_2d(point.x * 1.7, point.z * 1.7)
		var height_tint := clampf(0.38 + point.y * 0.009 + variation * 0.09, 0.20, 0.58)
		var damp := clampf((0.25 - point.y) * 0.08, 0.0, 0.08)
		surface.set_color(Color(height_tint * (0.88 - damp), height_tint * 1.02, height_tint * (0.72 - damp)))
		surface.set_uv(Vector2(point.x * 0.075, point.z * 0.075))
		surface.set_uv2(Vector2((point.x + WORLD_EXTENT) / (WORLD_EXTENT * 2.0), (point.z + WORLD_EXTENT) / (WORLD_EXTENT * 2.0)))
		surface.add_vertex(point)


func _create_forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var counts := [0, 0, 0, 0]
	var transforms: Array = [[], [], [], []]
	for i in range(TREE_COUNT):
		var x := rng.randf_range(-WORLD_EXTENT + 5.0, WORLD_EXTENT - 5.0)
		var z := rng.randf_range(-WORLD_EXTENT + 5.0, WORLD_EXTENT - 5.0)
		if Vector2(x, z).length() < 13.0:
			continue
		var species := rng.rand_weighted(PackedFloat32Array([0.38, 0.25, 0.22, 0.15]))
		var scale := rng.randf_range(0.82, 1.28)
		var yaw := rng.randf_range(0.0, TAU)
		var ground := _height_at(x, z)
		var alignment := Quaternion(Vector3.UP, _terrain_normal_at(x, z))
		var basis := (Basis(alignment) * Basis(Vector3.UP, yaw)).scaled(Vector3(scale, scale, scale))
		transforms[species].append(Transform3D(basis, Vector3(x, ground, z)))
		counts[species] += 1

	var families := ["tree_spruce", "tree_pine", "tree_birch", "shrub_mixed"]
	for species in range(families.size()):
		if counts[species] == 0:
			continue
		var mesh := _load_environment_mesh(families[species])
		if mesh == null:
			continue
		var multi := _make_asset_multimesh(mesh, counts[species])
		for index in range(counts[species]):
			multi.multimesh.set_instance_transform(index, transforms[species][index])
		add_child(multi)
		environment_instances.append(multi)
		_register_wind_batch(multi, transforms[species], families[species])


func _create_ground_cover() -> void:
	_scatter_environment_asset("shrub_mixed", 360, 0.72, 1.18, 12001, 10.0)
	_scatter_environment_asset("fern_cluster", 525, 0.68, 1.22, 12002, 8.0)
	_scatter_environment_asset("rock_mossy", 260, 0.55, 1.35, 12003, 7.0)
	_scatter_environment_asset("grass_tuft", 2400, 0.72, 1.35, 12006, 6.0)
	_scatter_environment_asset("stone_cluster", 420, 0.55, 1.35, 12007, 7.0)
	_scatter_environment_asset("stump_mossy", 60, 0.72, 1.18, 12004, 14.0)
	_scatter_environment_asset("fallen_log", 70, 0.72, 1.24, 12005, 14.0)
	_scatter_environment_asset("mushroom_cluster", 190, 0.68, 1.24, 12008, 5.5)


func _scatter_environment_asset(asset_name: String, amount: int, min_scale: float, max_scale: float, seed_value: int, clear_radius: float) -> void:
	var mesh := _load_environment_mesh(asset_name)
	if mesh == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var transforms: Array[Transform3D] = []
	for index in range(amount):
		var x := rng.randf_range(-WORLD_EXTENT + 3.0, WORLD_EXTENT - 3.0)
		var z := rng.randf_range(-WORLD_EXTENT + 3.0, WORLD_EXTENT - 3.0)
		if Vector2(x, z).length() < clear_radius:
			continue
		var scale := rng.randf_range(min_scale, max_scale)
		var yaw := rng.randf_range(0.0, TAU)
		var alignment := Quaternion(Vector3.UP, _terrain_normal_at(x, z))
		var basis := (Basis(alignment) * Basis(Vector3.UP, yaw)).scaled(Vector3(scale, scale, scale))
		transforms.append(Transform3D(basis, Vector3(x, _height_at(x, z), z)))
	if transforms.is_empty():
		return
	var multi := _make_asset_multimesh(mesh, transforms.size())
	for index in range(transforms.size()):
		multi.multimesh.set_instance_transform(index, transforms[index])
	add_child(multi)
	multi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	environment_instances.append(multi)
	if asset_name in ["shrub_mixed", "fern_cluster", "grass_tuft", "tree_spruce", "tree_pine", "tree_birch"]:
		_register_wind_batch(multi, transforms, asset_name)


func _register_wind_batch(instance: MultiMeshInstance3D, transforms: Array, family: String) -> void:
	wind_batches.append({"node": instance, "base": transforms.duplicate(), "family": family})


func _process(delta: float) -> void:
	wind_clock += delta
	if surface_simulation != null and player != null:
		surface_simulation.step(delta, weather_mode, player.global_position, Vector2(player.velocity.x, player.velocity.z).length())
		terrain_collision_update_clock += delta
		if terrain_collision_update_clock >= 1.0:
			terrain_collision_update_clock = 0.0
			_update_terrain_collision()
	puddle_update_clock += delta
	if puddle_update_clock >= 0.4:
		puddle_update_clock = 0.0
		if weather_mode == "rain":
			_update_puddle_hydrology()
	wind_update_clock += delta
	if wind_update_clock < wind_update_interval:
		return
	var wind_delta := wind_update_clock
	wind_update_clock = 0.0
	if weather_mode == "snow":
		snow_accumulation = minf(0.88, snow_accumulation + wind_delta * 0.025)
		terrain_material.set_shader_parameter("snow_cover", snow_accumulation)
		_apply_environment_snow(snow_accumulation)
	elif weather_mode == "rain":
		wetness_accumulation = minf(1.0, wetness_accumulation + wind_delta * 0.08)
		terrain_material.set_shader_parameter("surface_wetness", wetness_accumulation)
		_apply_environment_wetness(wetness_accumulation)
	else:
		snow_accumulation = maxf(0.0, snow_accumulation - wind_delta * 0.003)
		wetness_accumulation = maxf(0.0, wetness_accumulation - wind_delta * 0.012)
		terrain_material.set_shader_parameter("snow_cover", snow_accumulation)
		terrain_material.set_shader_parameter("surface_wetness", wetness_accumulation)
		_apply_environment_wetness(wetness_accumulation)
		_apply_environment_snow(snow_accumulation)
	var wind_strength := 0.035
	if weather_mode == "rain":
		wind_strength = 0.11
	elif weather_mode == "snow":
		wind_strength = 0.085
	for batch in wind_batches:
		var instance := batch["node"] as MultiMeshInstance3D
		if not is_instance_valid(instance):
			continue
		var bases: Array = batch["base"]
		var family: String = batch["family"]
		for index in range(bases.size()):
			var base: Transform3D = bases[index]
			if player != null and base.origin.distance_squared_to(player.global_position) > WIND_NEAR_RADIUS_SQUARED:
				continue
			var phase := wind_clock * 1.4 + base.origin.x * 0.13 + base.origin.z * 0.11
			var sway := sin(phase) * wind_strength
			var axis := Vector3.RIGHT
			var rotated := base.basis.rotated(axis, sway * (1.8 if family == "grass_tuft" else 1.0))
			instance.multimesh.set_instance_transform(index, Transform3D(rotated, base.origin))


func _load_environment_mesh(asset_name: String) -> Mesh:
	var cache_key := asset_name + "_" + active_season
	if asset_mesh_cache.has(cache_key):
		return asset_mesh_cache[cache_key] as Mesh
	var resource_path := "res://assets/generated/%s_%s.glb" % [asset_name, active_season]
	var packed_scene := load(resource_path) as PackedScene
	if packed_scene == null:
		push_error("Missing seasonal environment model: " + resource_path)
		return null
	var model_root := packed_scene.instantiate()
	var mesh_instance := _find_mesh_instance(model_root)
	if mesh_instance == null or mesh_instance.mesh == null:
		push_error("Seasonal model contains no MeshInstance3D: " + resource_path)
		model_root.free()
		return null
	var mesh := mesh_instance.mesh.duplicate() as ArrayMesh
	if mesh == null:
		push_error("Seasonal environment model is not an ArrayMesh: " + resource_path)
		model_root.free()
		return null
	var base_materials: Array[Material] = []
	for surface_index in range(mesh.get_surface_count()):
		var source_material := mesh.surface_get_material(surface_index)
		if source_material != null:
			base_materials.append(source_material.duplicate() as Material)
		else:
			base_materials.append(null)
	asset_base_materials[cache_key] = base_materials
	asset_mesh_cache[cache_key] = mesh
	model_root.free()
	return mesh


func _apply_environment_wetness(amount: float) -> void:
	if absf(amount - last_environment_wetness) < 0.12:
		return
	last_environment_wetness = amount
	for cache_key in asset_mesh_cache.keys():
		var mesh := asset_mesh_cache[cache_key] as ArrayMesh
		var originals: Array = asset_base_materials.get(cache_key, [])
		if mesh == null:
			continue
		for surface_index in range(mini(mesh.get_surface_count(), originals.size())):
			var source := originals[surface_index] as StandardMaterial3D
			if source == null:
				continue
			var wet := source.duplicate() as StandardMaterial3D
			wet.roughness = lerpf(source.roughness, 0.24, amount)
			wet.albedo_color = source.albedo_color.lerp(source.albedo_color * Color(0.68, 0.72, 0.76), amount * 0.42)
			mesh.surface_set_material(surface_index, wet)


func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_mesh_instance(child)
		if found != null:
			return found
	return null


func _make_asset_multimesh(mesh: Mesh, count: int) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = count
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multi
	return instance


func _create_weather_particles() -> void:
	weather_particles = GPUParticles3D.new()
	weather_particles.name = "WeatherParticles"
	weather_particles.amount = 720
	weather_particles.lifetime = 2.8
	weather_particles.emitting = false
	weather_particles.visibility_aabb = AABB(Vector3(-36, -18, -36), Vector3(72, 36, 72))
	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material.emission_box_extents = Vector3(28, 10, 28)
	process_material.direction = Vector3(0, -1, 0)
	process_material.spread = 4.0
	process_material.initial_velocity_min = 9.0
	process_material.initial_velocity_max = 13.0
	process_material.gravity = Vector3(0, -1.5, 0)
	weather_particles.process_material = process_material
	var rain_mesh := QuadMesh.new()
	rain_mesh.size = Vector2(0.025, 0.34)
	var drop_material := StandardMaterial3D.new()
	drop_material.albedo_color = Color(0.62, 0.75, 0.82, 0.72)
	drop_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rain_mesh.material = drop_material
	weather_particles.draw_pass_1 = rain_mesh
	add_child(weather_particles)


func _set_weather(mode: String) -> void:
	weather_mode = mode
	if weather_particles == null:
		_create_weather_particles()
	var process_material := weather_particles.process_material as ParticleProcessMaterial
	var particle_mesh := QuadMesh.new()
	var particle_material := StandardMaterial3D.new()
	particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	match mode:
		"rain":
			weather_particles.amount = 1800
			weather_particles.lifetime = 2.8
			process_material.initial_velocity_min = 10.0
			process_material.initial_velocity_max = 14.0
			process_material.gravity = Vector3(0, -1.5, 0)
			process_material.direction = Vector3(0.16, -1.0, 0.08)
			process_material.spread = 8.0
			particle_mesh.size = Vector2(0.018, 0.30)
			particle_material.albedo_color = Color(0.62, 0.76, 0.86, 0.72)
			snow_accumulation = 0.0
			terrain_material.set_shader_parameter("snow_cover", 0.0)
			_apply_environment_snow(0.0)
			wetness_accumulation = 0.0
			terrain_material.set_shader_parameter("surface_wetness", 0.0)
			_apply_environment_wetness(0.0)
			_create_rain_puddles()
		"snow":
			weather_particles.amount = 2400
			weather_particles.lifetime = 7.0
			process_material.initial_velocity_min = 0.8
			process_material.initial_velocity_max = 2.0
			process_material.gravity = Vector3(0, -0.28, 0)
			process_material.direction = Vector3(0.24, -1.0, 0.16)
			process_material.spread = 18.0
			particle_mesh.size = Vector2(0.075, 0.075)
			particle_material.albedo_color = Color(0.92, 0.96, 1.0, 0.92)
			wetness_accumulation = 0.08
			terrain_material.set_shader_parameter("surface_wetness", 0.08)
			_apply_environment_wetness(0.08)
			snow_accumulation = maxf(snow_accumulation, 0.12)
			terrain_material.set_shader_parameter("snow_cover", snow_accumulation)
			_clear_puddles()
		_:
			weather_particles.emitting = false
			terrain_material.set_shader_parameter("snow_cover", snow_accumulation)
			terrain_material.set_shader_parameter("surface_wetness", wetness_accumulation)
			_clear_puddles()
			return
	particle_mesh.material = particle_material
	weather_particles.draw_pass_1 = particle_mesh
	weather_particles.emitting = true


func _season_label(season: String) -> String:
	match season:
		"spring": return "весна"
		"summer": return "лето"
		"autumn": return "осень"
		"winter": return "зима"
	return season


func _cycle_season() -> void:
	var seasons := ["spring", "summer", "autumn", "winter"]
	var current_index := seasons.find(active_season)
	active_season = seasons[(current_index + 1) % seasons.size()]
	for instance in environment_instances:
		if is_instance_valid(instance):
			instance.queue_free()
	environment_instances.clear()
	wind_batches.clear()
	asset_mesh_cache.clear()
	asset_base_materials.clear()
	_create_forest()
	_create_ground_cover()
	if player_visual != null:
		player_visual.call("set_season", active_season)
	last_environment_wetness = -1.0
	last_environment_snow = -1.0
	_apply_environment_wetness(wetness_accumulation)
	_apply_environment_snow(snow_accumulation)
	if season_button != null:
		season_button.text = "Сезон: " + _season_label(active_season)


func _cycle_weather() -> void:
	match weather_mode:
		"clear": _set_weather("rain")
		"rain": _set_weather("snow")
		_: _set_weather("clear")
	if hud_label != null:
		hud_label.text = "ПОГОДА: %s\\nКнопка погоды — смена условий" % weather_mode.to_upper()
	if weather_button != null:
		weather_button.text = "Погода: " + weather_mode


func _create_puddles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 74119
	for index in range(48):
		var x := rng.randf_range(-WORLD_EXTENT + 8.0, WORLD_EXTENT - 8.0)
		var z := rng.randf_range(-WORLD_EXTENT + 8.0, WORLD_EXTENT - 8.0)
		var center_height := _height_at(x, z)
		var rim_height := (_height_at(x + 1.8, z) + _height_at(x - 1.8, z) + _height_at(x, z + 1.8) + _height_at(x, z - 1.8)) * 0.25
		if center_height > rim_height - 0.06:
			continue
		var puddle := _build_conforming_puddle(Vector3(x, center_height, z), rng.randf_range(0.65, 1.6), rng.randf_range(0.4, 1.1))
		puddle.set_meta("surface_sample_position", Vector3(x, center_height, z))
		add_child(puddle)
		puddle.visible = false
		puddle_nodes.append(puddle)


func _build_conforming_puddle(center: Vector3, radius_x: float, radius_z: float) -> MeshInstance3D:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 16
	for i in range(segments):
		var a0 := TAU * float(i) / segments
		var a1 := TAU * float(i + 1) / segments
		var center_point := Vector3(center.x, _height_at(center.x, center.z) + 0.018, center.z)
		var p1 := Vector3(center.x + cos(a0) * radius_x, 0.0, center.z + sin(a0) * radius_z)
		var p2 := Vector3(center.x + cos(a1) * radius_x, 0.0, center.z + sin(a1) * radius_z)
		p1.y = _height_at(p1.x, p1.z) + 0.018
		p2.y = _height_at(p2.x, p2.z) + 0.018
		for point in [center_point, p2, p1]:
			tool.set_uv(Vector2(point.x * 0.5, point.z * 0.5))
			tool.add_vertex(point)
	tool.generate_normals()
	var patch := MeshInstance3D.new()
	patch.name = "TerrainConformingPuddle"
	patch.mesh = tool.commit()
	var water_shader := Shader.new()
	water_shader.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform vec3 water_tint = vec3(0.045, 0.085, 0.09);
uniform float water_depth = 0.0;
void fragment() {
    float ripple_a = sin(UV.x * 9.0 + UV.y * 7.0 + TIME * 1.8);
    float ripple_b = sin(UV.y * 13.0 - UV.x * 5.0 + TIME * 1.2);
    ALBEDO = water_tint * mix(0.68, 1.0, water_depth) + vec3(0.018) * (ripple_a + ripple_b) * water_depth;
    ROUGHNESS = mix(0.36, 0.12, water_depth) + abs(ripple_a) * 0.035 * water_depth;
    METALLIC = 0.08;
    SPECULAR = 0.85;
    NORMAL = normalize(vec3(ripple_a * 0.055, 1.0, ripple_b * 0.055));
}
"""
	var water_material := ShaderMaterial.new()
	water_material.shader = water_shader
	patch.material_override = water_material
	return patch


func _create_rain_puddles() -> void:
	_update_puddle_hydrology()


func _update_puddle_hydrology() -> void:
	if surface_simulation == null:
		return
	for puddle in puddle_nodes:
		if not is_instance_valid(puddle):
			continue
		var sample_position: Vector3 = puddle.get_meta("surface_sample_position", Vector3.ZERO)
		var state: Dictionary = surface_simulation.sample_surface(sample_position)
		var water_level := clampf(float(state["moisture"]) * 0.52 + float(state["runoff"]) * 1.8, 0.0, 1.0)
		puddle.visible = weather_mode == "rain" and water_level > 0.18
		var water_material := puddle.material_override as ShaderMaterial
		if water_material != null:
			water_material.set_shader_parameter("water_depth", water_level)


func _clear_puddles() -> void:
	for puddle in puddle_nodes:
		if is_instance_valid(puddle):
			puddle.visible = false


func _add_footprint(position: Vector3, direction: Vector3) -> void:
	var forward := Vector3(direction.x, 0.0, direction.z).normalized()
	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD
	var right := forward.cross(Vector3.UP).normalized()
	var center := Vector3(position.x, _height_at(position.x, position.z) + 0.006, position.z) + right * (0.13 if footprint_side == 0 else -0.13)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 10
	for i in range(segments):
		var a0 := TAU * float(i) / segments
		var a1 := TAU * float(i + 1) / segments
		var p1 := center + right * cos(a0) * 0.105 + forward * sin(a0) * 0.19
		var p2 := center + right * cos(a1) * 0.105 + forward * sin(a1) * 0.19
		p1.y = _height_at(p1.x, p1.z) + 0.035
		p2.y = _height_at(p2.x, p2.z) + 0.035
		for point in [center, p2, p1]:
			tool.add_vertex(point)
	tool.generate_normals()
	var mark := MeshInstance3D.new()
	mark.name = "SnowFootprint" if weather_mode == "snow" else "MudFootprint"
	mark.mesh = tool.commit()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.48, 0.53, 0.55, 0.72) if weather_mode == "snow" else Color(0.10, 0.065, 0.035, 0.78)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.96 if weather_mode == "snow" else 0.82
	mark.material_override = material
	add_child(mark)
	footprint_nodes.append(mark)
	if footprint_nodes.size() > 100:
		var oldest: MeshInstance3D = footprint_nodes.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	footprint_side = 1 - footprint_side


func _apply_environment_snow(amount: float) -> void:
	if absf(amount - last_environment_snow) < 0.12:
		return
	last_environment_snow = amount
	for cache_key in asset_mesh_cache.keys():
		var mesh := asset_mesh_cache[cache_key] as ArrayMesh
		var originals: Array = asset_base_materials.get(cache_key, [])
		if mesh == null:
			continue
		for surface_index in range(mini(mesh.get_surface_count(), originals.size())):
			var source := originals[surface_index] as StandardMaterial3D
			if source == null:
				continue
			var frosted := source.duplicate() as StandardMaterial3D
			frosted.albedo_color = source.albedo_color.lerp(Color(0.78, 0.84, 0.88), amount * 0.22)
			frosted.roughness = lerpf(source.roughness, 0.94, amount * 0.65)
			mesh.surface_set_material(surface_index, frosted)


func _create_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	player.position = Vector3(0.0, _height_at(0.0, 0.0) + 1.0, 0.0)

	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.42
	capsule.height = 1.8
	collision.shape = capsule
	player.add_child(collision)

	player_visual = Node3D.new()
	player_visual.name = "ProceduralHumanoid"
	player_visual.set_script(HUMANOID_RIG)
	player.add_child(player_visual)
	add_child(player)
	player_visual.call("set_season", active_season)


func _create_camera() -> void:
	camera = Camera3D.new()
	camera.name = "GameplayCamera"
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = CAMERA_FOV
	camera.near = 0.08
	camera.far = 190.0
	camera.position = player.position + CAMERA_OFFSET
	add_child(camera)
	camera.make_current()
	camera.look_at(player.global_position + Vector3.UP * 0.7, Vector3.UP)


func _create_hud() -> void:
	var layer := CanvasLayer.new()
	var panel := PanelContainer.new()
	panel.position = Vector2(18.0, 18.0)
	panel.custom_minimum_size = Vector2(250.0, 54.0)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	hud_label = Label.new()
	hud_label.text = "ПОЛЕВОЕ ИСПЫТАНИЕ\nЛевый джойстик — ходьба"
	margin.add_child(hud_label)
	panel.add_child(margin)
	layer.add_child(panel)
	joystick = Control.new()
	joystick.set_script(load("res://scripts/ui/virtual_joystick.gd"))
	joystick.name = "MovementJoystick"
	joystick.anchor_left = 0.0
	joystick.anchor_top = 1.0
	joystick.anchor_right = 0.0
	joystick.anchor_bottom = 1.0
	joystick.offset_left = 28.0
	joystick.offset_top = -218.0
	joystick.offset_right = 218.0
	joystick.offset_bottom = -28.0
	layer.add_child(joystick)
	weather_button = Button.new()
	weather_button.text = "Погода: ясно"
	weather_button.position = Vector2(18.0, 88.0)
	weather_button.custom_minimum_size = Vector2(190.0, 48.0)
	weather_button.pressed.connect(_cycle_weather)
	layer.add_child(weather_button)
	season_button = Button.new()
	season_button.text = "Сезон: " + _season_label(active_season)
	season_button.position = Vector2(18.0, 144.0)
	season_button.custom_minimum_size = Vector2(190.0, 48.0)
	season_button.pressed.connect(_cycle_season)
	layer.add_child(season_button)
	add_child(layer)
	_create_weather_particles()


func _physics_process(delta: float) -> void:
	var direction := Vector3.ZERO
	var keyboard := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var stick: Vector2 = joystick.get_value() if joystick != null else Vector2.ZERO
	var move_input := (keyboard + stick).limit_length(1.0)
	debug_move_input = move_input

	if move_input.length_squared() > 0.001:
		# Map both joystick axes through the active camera basis. Do not read
		# direction.y here: the input's vertical axis is move_input.y.
		var camera_right := camera.global_basis.x
		var camera_forward := camera.global_basis.z
		direction = camera_right * move_input.x + camera_forward * move_input.y
		direction.y = 0.0
		if direction.length_squared() > 0.001:
			direction = direction.normalized()
		else:
			push_warning("Camera-relative movement direction collapsed to zero.")
	debug_move_direction = direction

	var horizontal_velocity := Vector2(player.velocity.x, player.velocity.z)
	var target_velocity := Vector2(direction.x, direction.z) * PLAYER_SPEED
	var response := PLAYER_ACCELERATION if direction.length_squared() > 0.001 else PLAYER_DECELERATION
	horizontal_velocity = horizontal_velocity.move_toward(target_velocity, response * delta)
	player.velocity.x = horizontal_velocity.x
	player.velocity.z = horizontal_velocity.y
	if not player.is_on_floor():
		player.velocity.y -= 24.0 * delta
	else:
		player.velocity.y = -0.1
	player.move_and_slide()
	if weather_mode != "clear":
		footprint_distance += Vector2(player.velocity.x, player.velocity.z).length() * delta
		if footprint_distance >= 0.62 and Vector2(player.velocity.x, player.velocity.z).length() > 0.8:
			_add_footprint(player.global_position, direction)
			if surface_simulation != null:
				surface_simulation.stamp_footstep(player.global_position, weather_mode)
			footprint_distance = 0.0
	var horizontal_speed := Vector2(player.velocity.x, player.velocity.z).length()
	var slope_ahead := 0.0
	if direction.length_squared() > 0.001:
		var ahead := player.position + direction * 1.0
		slope_ahead = _height_at(ahead.x, ahead.z) - _height_at(player.position.x, player.position.z)
	player_visual.call("set_motion", horizontal_speed, slope_ahead)
	if direction.length_squared() > 0.001:
		# The humanoid rig faces local -Z. Rotate smoothly toward travel direction.
		var target_yaw := atan2(-direction.x, -direction.z)
		player_visual.rotation.y = lerp_angle(player_visual.rotation.y, target_yaw, 1.0 - exp(-delta * 12.0))

	if weather_particles != null:
		weather_particles.global_position = player.global_position + Vector3(0, 9, 0)
	var target_position := player.global_position + CAMERA_OFFSET
	camera.global_position = camera.global_position.lerp(target_position, 1.0 - exp(-delta * 5.5))
	camera.look_at(player.global_position + Vector3.UP * 0.7, Vector3.UP)

