extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	for i in 180:
		await process_frame
	var image := root.get_viewport().get_texture().get_image()
	var result := image.save_png("/tmp/taiga_visual.png")
	print("VISUAL_CAPTURE result=", result, " size=", image.get_size())
	quit(0 if result == OK else 1)
