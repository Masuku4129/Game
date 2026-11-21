extends SceneTree

func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		printerr("MOVEMENT_TEST_FAIL: main scene could not be loaded")
		quit(1)
		return

	var game := packed.instantiate()
	root.add_child(game)
	await process_frame
	await physics_frame

	var player := game.get_node_or_null("Player") as CharacterBody3D
	var joystick := game.find_child("MovementJoystick", true, false) as Control
	if player == null or joystick == null:
		printerr("MOVEMENT_TEST_FAIL: player or joystick node missing")
		quit(1)
		return

	var start_position := Vector2(player.global_position.x, player.global_position.z)
	var center := joystick.get_global_rect().get_center()
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.position = center
	press.pressed = true
	joystick._input(press)
	await process_frame

	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = center + Vector2(0.0, -60.0)
	drag.relative = Vector2(0.0, -60.0)
	joystick._input(drag)
	await process_frame

	var joystick_value: Vector2 = joystick.get_value()
	if joystick_value.length() < 0.4:
		printerr("MOVEMENT_TEST_FAIL: touch input did not reach joystick; value=", joystick_value)
		quit(1)
		return

	for frame in range(90):
		await physics_frame
		if frame % 15 == 0:
			print("MOVEMENT_TRACE frame=", frame, " position=", player.global_position, " velocity=", player.velocity, " floor=", player.is_on_floor(), " collisions=", player.get_slide_collision_count())

	var end_position := Vector2(player.global_position.x, player.global_position.z)
	var distance := start_position.distance_to(end_position)
	if distance < 2.0:
		printerr("MOVEMENT_TEST_FAIL: joystick input registered but player did not move; distance=", distance, " velocity=", player.velocity)
		quit(1)
		return

	var release := InputEventScreenTouch.new()
	release.index = 0
	release.position = drag.position
	release.pressed = false
	joystick._input(release)
	print("MOVEMENT_TEST_PASS: joystick=", joystick_value, " displacement=", distance)
	quit(0)
