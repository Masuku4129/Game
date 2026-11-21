extends SceneTree

func _material_appearance_color(material: StandardMaterial3D) -> Color:
	var color := material.albedo_color
	# GLB export may bake foliage tint into albedo textures and leave the
	# material's base-color factor white. Sample the texture so the test checks
	# the appearance that is actually rendered, not only the factor.
	if material.albedo_texture != null:
		var image := material.albedo_texture.get_image()
		if image != null and image.get_width() > 0 and image.get_height() > 0:
			var total := Color(0, 0, 0, 0)
			var samples := 0
			for y in range(0, image.get_height(), max(1, image.get_height() / 8)):
				for x in range(0, image.get_width(), max(1, image.get_width() / 8)):
					total += image.get_pixel(x, y)
					samples += 1
			if samples > 0:
				var average := total / float(samples)
				color = Color(color.r * average.r, color.g * average.g, color.b * average.b, color.a * average.a)
	return color


func _mesh_has_distinct_colors(mesh: Mesh, minimum: int) -> bool:
	var colors: Array[Color] = []
	for surface_index in range(mesh.get_surface_count()):
		var material := mesh.surface_get_material(surface_index) as StandardMaterial3D
		if material == null:
			continue
		var appearance := _material_appearance_color(material)
		var unique := true
		for existing in colors:
			if existing.is_equal_approx(appearance):
				unique = false
				break
		if unique:
			colors.append(appearance)
	return colors.size() >= minimum


func _mesh_has_albedo_texture(mesh: Mesh) -> bool:
	for surface_index in range(mesh.get_surface_count()):
		var material := mesh.surface_get_material(surface_index) as StandardMaterial3D
		if material != null and material.albedo_texture != null:
			return true
	return false


func _find_node_type(node: Node, type_name: String) -> Node:
	if node.get_class() == type_name:
		return node
	for child in node.get_children():
		var found := _find_node_type(child, type_name)
		if found != null:
			return found
	return null

func _has_node_type(node: Node, type_name: String) -> bool:
	return _find_node_type(node, type_name) != null


func _has_animation_clip(clips: PackedStringArray, fragment: String) -> bool:
	for clip in clips:
		if String(clip).contains(fragment):
			return true
	return false


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
	var ground_normal := terrain_material.get_shader_parameter("ground_normal") as Texture2D
	if ground_normal == null or ground_normal.get_width() < 256:
		printerr("ENVIRONMENT_TEST_FAIL: detailed ground normal texture missing")
		quit(1)
		return
	var camera := game.get("camera") as Camera3D
	var player := game.get("player") as CharacterBody3D
	if camera == null or player == null:
		printerr("ENVIRONMENT_TEST_FAIL: gameplay camera or player missing")
		quit(1)
		return
	var camera_offset := camera.global_position - player.global_position
	var camera_elevation := rad_to_deg(asin(camera_offset.y / camera_offset.length()))
	if camera_offset.length() < 25.0 or camera_elevation < 55.0 or camera_elevation > 65.0:
		printerr("ENVIRONMENT_TEST_FAIL: camera must be about twice as far and elevated around 60 degrees")
		quit(1)
		return

	# Guard the intended dense landscape against regressions back to a sparse
	# handful of trees and isolated props. First four batches are the forest
	# species; all remaining batches are ground-cover families.
	var environment_batches := game.get("environment_instances") as Array
	var forest_instances := 0
	var total_environment_instances := 0
	for batch_index in range(environment_batches.size()):
		var batch := environment_batches[batch_index] as MultiMeshInstance3D
		if batch == null or batch.multimesh == null:
			continue
		var count := batch.multimesh.instance_count
		total_environment_instances += count
		if batch_index < 4:
			forest_instances += count
	if forest_instances < 1000 or total_environment_instances < 5000:
		printerr("ENVIRONMENT_TEST_FAIL: forest/ground-cover density regressed: forest=", forest_instances, " total=", total_environment_instances)
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

	var character_visual := game.get("player_visual") as Node3D
	var explorer_anim := _find_node_type(character_visual, "AnimationPlayer") as AnimationPlayer if character_visual != null else null
	if character_visual == null or not _has_node_type(character_visual, "Skeleton3D") or explorer_anim == null:
		printerr("ENVIRONMENT_TEST_FAIL: rigged explorer skeleton or animation player missing")
		quit(1)
		return
	var clips := explorer_anim.get_animation_list()
	if not _has_animation_clip(clips, "Walk") or not _has_animation_clip(clips, "Run"):
		printerr("ENVIRONMENT_TEST_FAIL: imported explorer walk/run animation clips unavailable: ", clips)
		quit(1)
		return
	var skeleton := _find_node_type(character_visual, "Skeleton3D") as Skeleton3D
	if skeleton == null or skeleton.get_bone_count() < 12:
		printerr("ENVIRONMENT_TEST_FAIL: imported explorer skeleton is incomplete")
		quit(1)
	character_visual.call("set_motion", 2.0, 0.0)
	# Assert the controller selection synchronously: the scene physics loop may
	# legitimately overwrite this synthetic request on the next frame.
	if not String(character_visual.get("current_clip")).contains("Walk"):
		printerr("ENVIRONMENT_TEST_FAIL: controller did not select walk animation")
		quit(1)
	character_visual.call("set_motion", 8.0, 0.0)
	if not String(character_visual.get("current_clip")).contains("Run"):
		printerr("ENVIRONMENT_TEST_FAIL: controller did not select run animation")
		quit(1)
	character_visual.call("set_motion", 0.0, 0.0)
	if not String(character_visual.get("current_clip")).contains("Idle"):
		printerr("ENVIRONMENT_TEST_FAIL: controller did not return to idle animation")
		quit(1)
	for asset_name in ["tree_spruce", "tree_birch", "fern_cluster", "grass_tuft", "mushroom_cluster"]:
		var colored_mesh := game.call("_load_environment_mesh", asset_name) as Mesh
		var minimum_colors := 1 if asset_name == "fern_cluster" else 2
		if colored_mesh == null or not _mesh_has_distinct_colors(colored_mesh, minimum_colors):
			printerr("ENVIRONMENT_TEST_FAIL: GLB material colors missing for " + asset_name)
			quit(1)
			return
	var grass_mesh := game.call("_load_environment_mesh", "grass_tuft") as Mesh
	if grass_mesh == null or not _mesh_has_albedo_texture(grass_mesh):
		printerr("ENVIRONMENT_TEST_FAIL: seasonal grass blade texture missing from imported GLB")
		quit(1)
		return

	game.call("_cycle_season")
	if String(game.get("active_season")) != "autumn":
		printerr("ENVIRONMENT_TEST_FAIL: runtime season switch did not advance to autumn")
		quit(1)
		return
	if String(character_visual.get("last_season")) != "autumn":
		printerr("ENVIRONMENT_TEST_FAIL: character visual clothing did not receive the active season")
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

	print("ENVIRONMENT_TEST_PASS: weather, footprints, hydrology, collision deformation, camera elevation/distance, ground normal map, textured grass, colored GLB materials, rigged humanoid skeleton/animation and runtime seasonal rebuild")
	quit(0)