extends Node3D

const WORLD_EXTENT := 90.0
const GRID_CELLS := 144
const TREE_COUNT := 420
const PLAYER_SPEED := 5.5
const CAMERA_OFFSET := Vector3(11.5, 12.5, 11.5)
const CAMERA_FOV := 48.0
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
	var terrain_shape := ConcavePolygonShape3D.new()
	terrain_shape.set_faces(terrain_mesh.get_faces())
	terrain_collision.shape = terrain_shape
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
		var scale := rng.randf_range(0.82, 1.42)
		var yaw := rng.randf_range(0.0, TAU)
		var ground := _height_at(x, z)
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3(scale, scale, scale))
		transforms[species].append(Transform3D(basis, Vector3(x, ground, z)))
		counts[species] += 1

	for species in range(4):
		if counts[species] == 0:
			continue
		var trunk_mesh := CylinderMesh.new()
		trunk_mesh.top_radius = 0.13 if species != 2 else 0.10
		trunk_mesh.bottom_radius = 0.22 if species != 2 else 0.16
		trunk_mesh.height = 4.2 if species != 2 else 4.8
		trunk_mesh.radial_segments = 8
		var trunk_material := StandardMaterial3D.new()
		trunk_material.albedo_color = Color(0.24, 0.17, 0.11) if species != 2 else Color(0.72, 0.68, 0.52)
		trunk_material.roughness = 1.0
		var trunks := _make_multimesh(trunk_mesh, trunk_material, counts[species])
		var crown_mesh: Mesh
		var crown_material := StandardMaterial3D.new()
		crown_material.roughness = 0.96
		match species:
			0:
				crown_mesh = _make_cone_mesh(1.45, 5.0, 9)
				crown_material.albedo_color = Color(0.10, 0.23, 0.15)
			1:
				crown_mesh = _make_cone_mesh(1.85, 3.8, 7)
				crown_material.albedo_color = Color(0.17, 0.29, 0.17)
			2:
				crown_mesh = _make_broadleaf_mesh()
				crown_material.albedo_color = Color(0.29, 0.38, 0.19)
			_:
				crown_mesh = _make_cone_mesh(1.55, 4.4, 8)
				crown_material.albedo_color = Color(0.24, 0.34, 0.20)
		var crowns := _make_multimesh(crown_mesh, crown_material, counts[species])
		for index in range(counts[species]):
			var base: Transform3D = transforms[species][index]
			var trunk_offset := 2.1 if species != 2 else 2.4
			var crown_offset := 4.3 if species != 2 else 5.0
			trunks.multimesh.set_instance_transform(index, Transform3D(base.basis, base.origin + Vector3.UP * trunk_offset * base.basis.get_scale().y))
			crowns.multimesh.set_instance_transform(index, Transform3D(base.basis, base.origin + Vector3.UP * crown_offset * base.basis.get_scale().y))
		add_child(trunks)
		add_child(crowns)


func _make_cone_mesh(radius: float, height: float, segments: int) -> Mesh:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.03
	cone.bottom_radius = radius
	cone.height = height
	cone.radial_segments = segments
	return cone


func _make_broadleaf_mesh() -> Mesh:
	var crown := SphereMesh.new()
	crown.radius = 1.65
	crown.height = 3.5
	crown.radial_segments = 12
	crown.rings = 8
	return crown


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

	player_visual = Node3D.new()
	player_visual.name = "ProceduralHumanoid"
	player_visual.set_script(HUMANOID_RIG)
	player.add_child(player_visual)
	add_child(player)


func _create_camera() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = CAMERA_FOV
	camera.near = 0.08
	camera.far = 180.0
	camera.position = player.position + CAMERA_OFFSET
	add_child(camera)
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
	hud_label.text = "WILDERNESS  •  FIELD TEST\nDrag left side to move"
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
		direction = camera.global_basis.x * direction.x + camera.global_basis.z * direction.y
		direction.y = 0.0
		direction = direction.normalized()

	player.velocity.x = direction.x * PLAYER_SPEED
	player.velocity.z = direction.z * PLAYER_SPEED
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

	var target_position := player.global_position + CAMERA_OFFSET
	camera.global_position = camera.global_position.lerp(target_position, 1.0 - exp(-delta * 5.5))
	camera.look_at(player.global_position + Vector3.UP * 0.7, Vector3.UP)


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
		var drag_delta: Vector2 = (event.position - touch_origin) / 90.0
		touch_vector = Vector2(clampf(drag_delta.x, -1.0, 1.0), clampf(drag_delta.y, -1.0, 1.0))
