extends Node3D
## Изолированная Godot-сцена для проверки импортируемых GLB-моделей тайги.
## Не меняет основную игровую сцену и не подменяет штатный генератор леса.

const ASSETS := [
	{"file": "taiga_spruce.glb", "label": "ЕЛЬ", "x": -47.5, "scale": 0.9},
	{"file": "taiga_pine.glb", "label": "СОСНА", "x": -42.5, "scale": 0.9},
	{"file": "taiga_birch.glb", "label": "БЕРЁЗА", "x": -37.5, "scale": 0.9},
	{"file": "taiga_bush.glb", "label": "КУСТ", "x": -32.5, "scale": 1.7},
	{"file": "taiga_rock.glb", "label": "КАМЕНЬ", "x": -27.5, "scale": 0.9},
	{"file": "taiga_fallen_log.glb", "label": "ВАЛЕЖНИК", "x": -22.5, "scale": 0.9},
	{"file": "taiga_larch.glb", "label": "ЛИСТВЕННИЦА", "x": -17.5, "scale": 0.9},
	{"file": "taiga_cedar.glb", "label": "КЕДР", "x": -12.5, "scale": 0.9},
	{"file": "taiga_aspen.glb", "label": "ОСИНА", "x": -7.5, "scale": 0.9},
	{"file": "taiga_alder.glb", "label": "ОЛЬХА", "x": -2.5, "scale": 0.9},
	{"file": "taiga_willow.glb", "label": "ИВА", "x": 2.5, "scale": 0.9},
	{"file": "taiga_fern.glb", "label": "ПАПОРОТНИК", "x": 7.5, "scale": 0.9},
	{"file": "taiga_grass.glb", "label": "ТРАВА", "x": 12.5, "scale": 1.4},
	{"file": "taiga_moss.glb", "label": "МОХ", "x": 17.5, "scale": 1.1},
	{"file": "taiga_stump.glb", "label": "ПЕНЬ", "x": 22.5, "scale": 0.9},
	{"file": "taiga_juniper.glb", "label": "МОЖЖЕВЕЛЬНИК", "x": 27.5, "scale": 1.15},
	{"file": "taiga_reed.glb", "label": "КАМЫШ", "x": 32.5, "scale": 0.9},
	{"file": "taiga_cranberry.glb", "label": "КЛЮКВА", "x": 37.5, "scale": 1.1},
	{"file": "taiga_dead_snag.glb", "label": "СУХОСТОЙ", "x": 42.5, "scale": 0.9},
	{"file": "taiga_lichen_rock.glb", "label": "ЛИШАЙНИК НА КАМНЕ", "x": 47.5, "scale": 0.9},
	{"file": "taiga_style_spruce.glb", "label": "ИГРОВОЙ СТИЛЬ · ЕЛЬ", "x": 50.0, "scale": 0.9},
	{"file": "taiga_style_pine.glb", "label": "ИГРОВОЙ СТИЛЬ · СОСНА", "x": 55.0, "scale": 0.9},
	{"file": "taiga_style_birch.glb", "label": "ИГРОВОЙ СТИЛЬ · БЕРЁЗА", "x": 60.0, "scale": 0.9},
	{"file": "taiga_style_bush.glb", "label": "ИГРОВОЙ СТИЛЬ · КУСТ", "x": 65.0, "scale": 1.0},
	{"file": "taiga_style_rock.glb", "label": "ИГРОВОЙ СТИЛЬ · КАМЕНЬ", "x": 70.0, "scale": 0.9},
]

func _ready() -> void:
	_make_stage()
	var loaded := 0
	for spec in ASSETS:
		var path := "res://models/environment/%s" % spec.file
		var packed := load(path) as PackedScene
		if packed == null:
			push_error("GLB import failed: " + path)
			continue
		var model := packed.instantiate() as Node3D
		if model == null:
			push_error("GLB root is not Node3D: " + path)
			continue
		model.position = Vector3(float(spec.x), 0.0, 0.0)
		model.scale = Vector3.ONE * float(spec.scale)
		add_child(model)
		loaded += 1
		var label := Label3D.new()
		label.text = str(spec.label)
		label.position = Vector3(float(spec.x), 0.12, 3.0)
		label.font_size = 48
		label.pixel_size = 0.008
		label.modulate = Color(0.94, 0.91, 0.78)
		label.outline_size = 8
		label.no_depth_test = true
		add_child(label)
	print("TAIGA_ASSET_GALLERY loaded=", loaded, " expected=", ASSETS.size())
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
	plane.size = Vector2(150.0, 18.0)
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
	camera.size = 75.0
	camera.position = Vector3(0.0, 38.0, 72.0)
	camera.look_at(Vector3(0.0, 3.2, 0.0), Vector3.UP)
	add_child(camera)
	camera.current = true
