extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	for i in 240:
		await process_frame
	var viewport := root.get_viewport()
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty() or image.get_width() < 320 or image.get_height() < 180:
		push_error("VISUAL_CAPTURE invalid viewport image")
		quit(1)
		return
	var result := image.save_png("/tmp/taiga_visual.png")
	print("VISUAL_CAPTURE result=", result, " size=", image.get_size(), " bytes=", FileAccess.get_file_as_bytes("/tmp/taiga_visual.png").size())
	quit(0 if result == OK and FileAccess.file_exists("/tmp/taiga_visual.png") else 1)
