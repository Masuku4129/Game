extends Node3D

const WORLD_EXTENT := 120.0
const GRID_CELLS := 72
const TREE_COUNT := 260
const PLAYER_SPEED := 7.0
const CAMERA_OFFSET := Vector3(34.0, 34.0, 34.0)

var terrain_noise := FastNoiseLite.new()
var player: CharacterBody3D
var camera: Camera3D
var touch_vector := Vector2.ZERO
var touch_origin := Vector2.ZERO
var active_touch := -1
var hud_label: Label


func _ready() -> void:
	_setup_noise()
	_create_environment()
	_create_terrain()
	_create_forest()
	_create_player()
	_create_camera()
	_create_hud()


func _setup_noise() -> void:
	terrain_noise.seed = 4129
	terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	terrain_noise.frequency = 0.018
	terrain_noise.fractal_octaves = 4
	terrain_noise.fractal_gain = 0.48
	terrain_noise.fractal_lacunarity = 2.1


func _height_at(x: float, z: float) -> float:
	var broad := terrain_noise.get_noise_2d(x, z) * 7.0
	var detail := terrain_noise.get_noise_2d(x * 2.8 + 91.0, z * 2.8 - 37.0) * 1.2
	var valley := absf(terrain_noise.get_noise_2d(x * 0.42 + 300.0, z * 0.42)) * 1.8
	return broad + detail - valley


func _create_environment() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.19, 0.31, 0.39)
	sky_material.sky_horizon_color = Color(0.67, 0.72, 0.68)
	sky_material.ground_bottom_color = Color(0.13, 0.17, 0.14)
	sky_material.ground_horizon_color = Color(0.48, 0.52, 0.45)
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.65
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = environment
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
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
	material.albedo_color = Color(0.28, 0.36, 0.25)
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	terrain.material_override = material
	add_child(terrain)


func _add_terrain_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	for point in [a, b, c]:
		var tint := clampf(0.32 + point.y * 0.012, 0.18, 0.48)
		surface.set_color(Color(tint * 0.88, tint, tint * 0.78))
		surface.add_vertex(point)


func _create_forest() -> void:
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.16
	trunk_mesh.bottom_radius = 0.24
	trunk_mesh.height = 3.8
	trunk_mesh.radial_segments = 6
	var trunk_material := StandardMaterial3D.new()
	trunk_material.albedo_color = Color(0.25, 0.19, 0.13)
	trunk_material.roughness = 1.0
	var trunks := _make_multimesh(trunk_mesh, trunk_material, TREE_COUNT)

	var crown_mesh := SphereMesh.new()
	crown_mesh.radius = 1.65
	crown_mesh.height = 3.8
	crown_mesh.radial_segments = 6
	crown_mesh.rings = 4
	var crown_material := StandardMaterial3D.new()
	crown_material.albedo_color = Color(0.16, 0.27, 0.18)
	crown_material.roughness = 1.0
	var crowns := _make_multimesh(crown_mesh, crown_material, TREE_COUNT)

	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	for i in range(TREE_COUNT):
		var x := rng.randf_range(-WORLD_EXTENT + 8.0, WORLD_EXTENT - 8.0)
		var z := rng.randf_range(-WORLD_EXTENT + 8.0, WORLD_EXTENT - 8.0)
		if Vector2(x, z).length() < 15.0:
			x += 24.0
		var ground := _height_at(x, z)
		var scale := rng.randf_range(0.72, 1.35)
		var yaw := rng.randf_range(0.0, TAU)
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3(scale, scale, scale))
		var trunk_transform := Transform3D(basis, Vector3(x, ground + 1.9 * scale, z))
		var crown_transform := Transform3D(basis, Vector3(x, ground + 4.0 * scale, z))
		trunks.multimesh.set_instance_transform(i, trunk_transform)
		crowns.multimesh.set_instance_transform(i, crown_transform)

	add_child(trunks)
	add_child(crowns)


func _make_multimesh(mesh: Mesh, material: Material, count: int) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = count
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multi
	instance.material_override = material
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

	var visual := MeshInstance3D.new()
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.radius = 0.42
	capsule_mesh.height = 1.8
	visual.mesh = capsule_mesh
	var player_material := StandardMaterial3D.new()
	player_material.albedo_color = Color(0.45, 0.34, 0.22)
	player_material.roughness = 0.9
	visual.material_override = player_material
	player.add_child(visual)
	add_child(player)


func _create_camera() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 48.0
	camera.position = player.position + CAMERA_OFFSET
	camera.look_at(player.position, Vector3.UP)
	add_child(camera)


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
	hud_label.text = "WILDERNESS  •  TEST WORLD\nDrag on the left side to move"
	margin.add_child(hud_label)
	panel.add_child(margin)
	layer.add_child(panel)
	add_child(layer)


func _physics_process(delta: float) -> void:
	var direction := Vector3.ZERO
	var keyboard := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	direction.x = keyboard.x + touch_vector.x
	direction.z = keyboard.y + touch_vector.y
	direction = direction.limit_length(1.0)

	if direction.length_squared() > 0.001:
		direction = (camera.global_basis.x * direction.x + camera.global_basis.z * direction.z)
		direction.y = 0.0
		direction = direction.normalized()

	player.velocity.x = direction.x * PLAYER_SPEED
	player.velocity.z = direction.z * PLAYER_SPEED
	if not player.is_on_floor():
		player.velocity.y -= 24.0 * delta
	else:
		player.velocity.y = -0.1
	player.move_and_slide()

	camera.position = player.position + CAMERA_OFFSET
	camera.look_at(player.position, Vector3.UP)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and active_touch == -1 and event.position.x < get_viewport().get_visible_rect().size.x * 0.55:
			active_touch = event.index
			touch_origin = event.position
			touch_vector = Vector2.ZERO
		elif not event.pressed and event.index == active_touch:
			active_touch = -1
			touch_vector = Vector2.ZERO
	elif event is InputEventScreenDrag and event.index == active_touch:
		var delta := (event.position - touch_origin) / 90.0
		touch_vector = Vector2(clampf(delta.x, -1.0, 1.0), clampf(delta.y, -1.0, 1.0))
