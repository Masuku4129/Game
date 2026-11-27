extends SceneTree
## FPS/draw-call overlay must not clutter ordinary gameplay; PERF enables it for diagnostics.
func _initialize() -> void:
	call_deferred("run_test")

func run_test() -> void:
	var world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	await process_frame
	var hidden_by_default: bool = not world.fps_lbl.visible
	print("UI_DEBUG_OVERLAY_TEST hidden_by_default=", hidden_by_default)
	world.queue_free()
	quit(0 if hidden_by_default else 1)
