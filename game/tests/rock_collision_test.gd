extends SceneTree
## Validate that tall rock collision blockers extend past the visual footprint for the player's body.
func _initialize() -> void:
	call_deferred("run_test")

func run_test() -> void:
	var world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	await process_frame
	var seen := {}
	var tested := 0
	var edge_hits := 0
	for bucket in world.solids.values():
		for sd in bucket:
			if int(sd[0]) != 0 or float(sd[4]) <= 0.85:
				continue
			var center: Vector3 = sd[1]
			var key := Vector2i(roundi(center.x * 10.0), roundi(center.z * 10.0))
			if seen.has(key):
				continue
			seen[key] = true
			var r: float = float(sd[3])
			var edge_probe := Vector2(center.x + r + 0.2, center.z)
			if world.blocked(edge_probe.x, edge_probe.y, 0.32):
				edge_hits += 1
				tested += 1
		print("ROCK_COLLISION_TEST tall_rocks=", tested, " edge_clearance_hits=", edge_hits)
	world.queue_free()
	if tested < 10 or edge_hits < 5:
		quit(1)
	else:
		quit(0)
