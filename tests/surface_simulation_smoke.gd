extends SceneTree

const SIMULATION = preload("res://scripts/environment/surface_simulation.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _height(x: float, _z: float) -> float:
	return x * 0.24


func _run_test() -> void:
	var simulation = SIMULATION.new()
	simulation.initialize(90.0, Callable(self, "_height"))
	for index in range(50):
		simulation.step(0.16, "snow", Vector3.ZERO, 0.0)
	var snowy: Dictionary = simulation.sample_surface(Vector3.ZERO)
	if float(snowy["snow"]) < 0.20:
		printerr("SURFACE_TEST_FAIL: snowfall did not accumulate in the surface grid")
		quit(1)
		return

	simulation.stamp_footstep(Vector3.ZERO, "snow")
	var compacted: Dictionary = simulation.sample_surface(Vector3.ZERO)
	if float(compacted["compaction"]) < 0.25 or float(compacted["snow"]) >= float(snowy["snow"]):
		printerr("SURFACE_TEST_FAIL: footstep did not compact and displace snow")
		quit(1)
		return

	for index in range(100):
		simulation.step(0.16, "rain", Vector3.ZERO, 0.0)
	var wet: Dictionary = simulation.sample_surface(Vector3.ZERO)
	if float(wet["moisture"]) < 0.55:
		printerr("SURFACE_TEST_FAIL: rainfall did not saturate soil")
		quit(1)
		return

	var maximum_runoff := 0.0
	for z in range(SIMULATION.RESOLUTION):
		for x in range(SIMULATION.RESOLUTION):
			var index := z * SIMULATION.RESOLUTION + x
			maximum_runoff = maxf(maximum_runoff, simulation.runoff[index])
	if maximum_runoff <= 0.0:
		printerr("SURFACE_TEST_FAIL: water did not route downhill")
		quit(1)
		return

	var texture := simulation.get_texture()
	if texture == null or texture.get_width() != SIMULATION.RESOLUTION:
		printerr("SURFACE_TEST_FAIL: terrain state texture was not produced")
		quit(1)
		return

	print("SURFACE_TEST_PASS: snow accumulation, foot compaction, soil saturation, downhill runoff and terrain texture")
	quit(0)
