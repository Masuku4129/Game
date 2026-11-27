extends Node3D
## Изолированная Godot-сцена для проверки импортируемых GLB-моделей тайги.
## Не меняет основную игровую сцену и не подменяет штатный генератор леса.

const ASSETS := [
	{"kind": "spruce", "label": "ЕЛЬ", "x": -15.0, "z": -5.0, "scale": 0.85},
	{"kind": "pine", "label": "СОСНА", "x": -9.0, "z": -5.0, "scale": 0.7},
	{"kind": "larch", "label": "ЛИСТВЕННИЦА", "x": -3.0, "z": -5.0, "scale": 0.75},
	{"kind": "cedar", "label": "КЕДР", "x": 3.0, "z": -5.0, "scale": 0.8},
	{"kind": "birch", "label": "БЕРЁЗА", "x": 9.0, "z": -5.0, "scale": 0.9},
	{"kind": "aspen", "label": "ОСИНА", "x": 15.0, "z": -5.0, "scale": 0.8},
	{"kind": "alder", "label": "ОЛЬХА", "x": -15.0, "z": 5.0, "scale": 1.0},
	{"kind": "bush", "label": "КУСТ", "x": -9.0, "z": 5.0, "scale": 1.5},
	{"kind": "stump", "label": "ПЕНЬ", "x": -3.0, "z": 5.0, "scale": 1.4},
]

func _ready() -> void:
	_make_stage()
	var pv = preload("res://scripts/pveg.gd").new()
	var loaded := 0
	for spec in ASSETS:
		var built: Array = pv.model_mesh(str(spec.kind))
		if built.is_empty():
			push_error("GLB model failed: " + str(spec.kind))
			continue
		var model := MeshInstance3D.new()
		model.mesh = built[0]
		model.position = Vector3(float(spec.x), 0.0, float(spec.z))
		model.scale = Vector3.ONE * float(spec.scale)
		add_child(model)
		loaded += 1
		var label := Label3D.new()
		label.text = str(spec.label)
		label.position = Vector3(float(spec.x), 0.12, float(spec.z) + 3.0)
		label.font_size = 48
		label.pixel_size = 0.008
		label.modulate = Color(0.94, 0.91, 0.78)
		label.outline_size = 8
		label.no_depth_test = true
		add_child(label)
	print("TAIGA_ASSET_GALLERY loaded=", loaded)
	if OS.get_environment("ASSET_GALLERY_SHOTS") != "":
		await get_tree().process_frame
		await get_tree().process_frame
		var output := OS.get_environment("ASSET_GALLERY_SHOTS")
		var image := get_viewport().get_texture().get_image()
		var error := image.save_png(output)
		print("TAIGA_ASSET_GALLERY screenshot=", output, " error=", error)
		get_tree().quit()

func _make_stage() -> void:
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(46.0, 24.0)
	floor.mesh = plane
	var ground := StandardMaterial3D.new()
	ground.albedo_color = Color(0.19, 0.23, 0.18)
	ground.roughness = 1.0
	floor.material_override = ground
	floor.position = Vector3(0.0, -0.08, 0.0)
	add_child(floor)

	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.34, 0.42, 0.46)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.78, 0.82, 0.76)
	environment.ambient_light_energy = 0.8
	world.environment = environment
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	add_child(sun)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 26.0
	camera.position = Vector3(0.0, 20.0, 34.0)
	add_child(camera)
	camera.look_at(Vector3(0.0, 2.0, 0.0), Vector3.UP)
	camera.current = true
