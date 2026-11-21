extends SceneTree

func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		printerr("ENVIRONMENT_TEST_FAIL: main scene missing")
		quit(1)
		return
	var game := packed.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame

	var particles := game.get("weather_particles") as GPUParticles3D
	var terrain_material := game.get("terrain_material") as ShaderMaterial
	if particles == null or terrain_material == null:
		printerr("ENVIRONMENT_TEST_FAIL: weather or terrain material not initialized")
		quit(1)
		return

	game.call("_set_weather", "snow")
	if not particles.emitting or float(terrain_material.get_shader_parameter("snow_cover")) < 0.1:
		printerr("ENVIRONMENT_TEST_FAIL: snowfall did not start or snow cover was not applied")
		quit(1)
		return

	var before := (game.get("footprint_nodes") as Array).size()
	game.call("_add_footprint", Vector3(1.0, 0.0, 1.0), Vector3.FORWARD)
	var after := (game.get("footprint_nodes") as Array).size()
	if after != before + 1:
		printerr("ENVIRONMENT_TEST_FAIL: snow footprint was not created")
		quit(1)
		return

	game.call("_set_weather", "rain")
	var simulation = game.get("surface_simulation")
	for index in range(50):
		simulation.step(0.16, "rain", Vector3.ZERO, 0.0)
	var rain_state: Dictionary = simulation.sample_surface(Vector3.ZERO)
	if not particles.emitting or float(rain_state["moisture"]) < 0.45:
		printerr("ENVIRONMENT_TEST_FAIL: rain did not saturate the local soil state")
		quit(1)
		return

	var puddles := game.get("puddle_nodes") as Array
	var wind_batches := game.get("wind_batches") as Array
	if puddles.is_empty() or wind_batches.is_empty():
		printerr("ENVIRONMENT_TEST_FAIL: terrain puddles or wind-animated vegetation were not created")
		quit(1)
		return

	for index in range(50):
		simulation.step(0.16, "rain", Vector3.ZERO, 0.0)
	game.call("_update_puddle_hydrology")
	game.call("_update_terrain_collision")
	var collision_shape := game.get("terrain_shape") as HeightMapShape3D
	if collision_shape == null or collision_shape.map_data.size() != 145 * 145:
		printerr("ENVIRONMENT_TEST_FAIL: surface displacement was not applied to terrain collision")
		quit(1)
		return
	var active_puddles := 0
	for puddle in puddles:
		if puddle.visible:
			active_puddles += 1
	if active_puddles == 0:
		printerr("ENVIRONMENT_TEST_FAIL: rain saturation did not activate terrain puddles")
		quit(1)
		return

	var mushroom_mesh := game.call("_load_environment_mesh", "mushroom_cluster") as Mesh
	if mushroom_mesh == null or mushroom_mesh.get_surface_count() < 3:
		printerr("ENVIRONMENT_TEST_FAIL: seasonal mushroom cluster mesh was not loaded with its materials")
		quit(1)
		return
	var distinct_colors: Array[Color] = []
	var colored_surfaces := 0
	for surface_index in range(mushroom_mesh.get_surface_count()):
		var material := mushroom_mesh.surface_get_material(surface_index) as StandardMaterial3D
		if material == null:
			continue
		colored_surfaces += 1
		var unique := true
		for existing_color in distinct_colors:
			if existing_color.is_equal_approx(material.albedo_color):
				unique = false
				break
		if unique:
			distinct_colors.append(material.albedo_color)
	if colored_surfaces < 3 or distinct_colors.size() < 3:
		printerr("ENVIRONMENT_TEST_FAIL: imported GLB materials lost their distinct base colors")
		quit(1)
		return

	game.call("_cycle_season")
	if String(game.get("active_season")) != "autumn":
		printerr("ENVIRONMENT_TEST_FAIL: runtime season switch did not advance to autumn")
		quit(1)
		return
	if (game.get("environment_instances") as Array).size() < 10:
		printerr("ENVIRONMENT_TEST_FAIL: seasonal switch did not rebuild forest and ground-cover instances")
		quit(1)
		return
	var autumn_mushrooms := game.call("_load_environment_mesh", "mushroom_cluster") as Mesh
	if autumn_mushrooms == null:
		printerr("ENVIRONMENT_TEST_FAIL: autumn mushroom model was not loaded")
		quit(1)
		return

	print("ENVIRONMENT_TEST_PASS: weather, footprints, hydrology, collision deformation, colored GLB materials, mushroom assets and runtime seasonal rebuild")
	quit(0)