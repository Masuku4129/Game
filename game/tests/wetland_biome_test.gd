extends SceneTree
## Sample the seeded world and assert that wetlands and standing-water pockets exist.
func _initialize() -> void:
	call_deferred("run_test")

func run_test() -> void:
	var world := load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	await process_frame
	var total := 0
	var wetland := 0
	var wetland_pools := 0
	for z in range(-240, 241, 10):
		for x in range(-240, 241, 10):
			var zone_id: int = world.zone(float(x), float(z))
			total += 1
			if zone_id == 2:
				wetland += 1
				if world.height(float(x), float(z)) < world.WATER_Y - 0.05:
					wetland_pools += 1
	var coverage := float(wetland) / maxf(float(total), 1.0)
	print("WETLAND_SAMPLE total=", total, " wetland=", wetland, " pools=", wetland_pools, " coverage=", coverage)
	world.queue_free()
	if coverage < 0.04 or coverage > 0.25 or wetland_pools < 1:
		quit(1)
	else:
		quit(0)
