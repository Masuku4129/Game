extends Node3D

const WORLD_EXTENT := 90.0
const GRID_CELLS := 144
const TREE_COUNT := 1050
const PLAYER_SPEED := 5.5
const PLAYER_ACCELERATION := 22.0
const PLAYER_DECELERATION := 28.0
const CAMERA_OFFSET := Vector3(7.0, 7.8, 7.0)
const CAMERA_FOV := 44.0

@export_enum("spring", "summer", "autumn", "winter") var active_season: String = "summer"
const HUMANOID_RIG = preload("res://scripts/animation/procedural_humanoid.gd")

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
var asset_mesh_cache: Dictionary = {}
var debug_move_input := Vector2.ZERO
var debug_move_direction := Vector3.ZERO


func _ready() -> void:
	set_physics_process(true)
	_setup_noise()
	_create_environment()
	_create_terrain()
	_create_forest()
	_create_ground_cover()
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
	sun.directional_shadow_max_distance = 65.0
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
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	terrain.material_override = material
	add_child(terrain)

	var terrain_body := StaticBody3D.new()
	terrain_body.name = "TerrainCollision"
	var terrain_collision := CollisionShape3D.new()
	var terrain_shape := HeightMapShape3D.new()
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


func _add_terrain_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	for point in [a, b, c]:
		var variation := detail_noise.get_noise_2d(point.x * 1.7, point.z * 1.7)
		var height_tint := clampf(0.38 + point.y * 0.009 + variation * 0.09, 0.20, 0.58)
		var damp := clampf((0.25 - point.y) * 0.08, 0.0, 0.08)
		surface.set_color(Color(height_tint * (0.88 - damp), height_tint * 1.02, height_tint * (0.72 - damp)))
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
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3(scale, scale, scale))
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


func _create_ground_cover() -> void:
	_scatter_environment_asset("shrub_mixed", 360, 0.72, 1.18, 12001, 10.0)
	_scatter_environment_asset("fern_cluster", 525, 0.68, 1.22, 12002, 8.0)
	_scatter_environment_asset("rock_mossy", 260, 0.55, 1.35, 12003, 7.0)
	_scatter_environment_asset("stump_mossy", 60, 0.72, 1.18, 12004, 14.0)
	_scatter_environment_asset("fallen_log", 70, 0.72, 1.24, 12005, 14.0)


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
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3(scale, scale, scale))
		transforms.append(Transform3D(basis, Vector3(x, _height_at(x, z), z)))
	if transforms.is_empty():
		return
	var multi := _make_asset_multimesh(mesh, transforms.size())
	for index in range(transforms.size()):
		multi.multimesh.set_instance_transform(index, transforms[index])
	add_child(multi)


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
	var mesh := mesh_instance.mesh
	asset_mesh_cache[cache_key] = mesh
	model_root.free()
	return mesh


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
	camera.far = 180.0
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
	add_child(layer)


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

	var target_position := player.global_position + CAMERA_OFFSET
	camera.global_position = camera.global_position.lerp(target_position, 1.0 - exp(-delta * 5.5))
	camera.look_at(player.global_position + Vector3.UP * 0.7, Vector3.UP)

