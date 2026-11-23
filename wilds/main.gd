extends Node2D
## Точка входа: собирает мир из кода.
## Вид как в Don't Starve: плоские 2D-спрайты, камера 3/4 сверху,
## порядок отрисовки по Y (кто ниже на экране, тот ближе к камере).

const WORLD_RADIUS := 2400.0
const MIN_GAP := 90.0
const PROP_TRIES := 900

var world: Node2D
var player
var cam: Camera2D
var fps_label: Label


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261123

	var ground = preload("res://ground.gd").new()
	ground.radius = WORLD_RADIUS
	ground.seed_value = rng.seed
	add_child(ground)

	# узел с y_sort_enabled сортирует детей по position.y
	world = Node2D.new()
	world.y_sort_enabled = true
	add_child(world)

	_spawn_props(rng)

	player = preload("res://player.gd").new()
	player.world_radius = WORLD_RADIUS
	world.add_child(player)

	cam = Camera2D.new()
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 8.0
	player.add_child(cam)

	var ui := CanvasLayer.new()
	add_child(ui)
	ui.add_child(_make_vignette())
	var stick = preload("res://joystick.gd").new()
	ui.add_child(stick)
	player.stick = stick
	var buttons = preload("res://action_buttons.gd").new()
	buttons.player = player
	ui.add_child(buttons)

	fps_label = Label.new()
	fps_label.position = Vector2(12, 8)
	fps_label.add_theme_font_size_override("font_size", 18)
	ui.add_child(fps_label)

	var shots := OS.get_environment("SHOTS")
	if shots != "":
		_shots(shots)


func _process(_delta: float) -> void:
	fps_label.text = "FPS %d" % Engine.get_frames_per_second()


func _make_vignette() -> TextureRect:
	# затемнение по краям экрана: фокус на персонаже
	var g := Gradient.new()
	g.set_color(0, Color(0.0, 0.0, 0.05, 0.0))
	g.set_color(1, Color(0.01, 0.0, 0.06, 0.82))
	g.add_point(0.55, Color(0.0, 0.0, 0.05, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 256
	t.height = 256
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _spawn_props(rng: RandomNumberGenerator) -> void:
	var placed: Array[Vector2] = []
	var prop_script := preload("res://prop.gd")
	for i in PROP_TRIES:
		var ang := rng.randf() * TAU
		var dist := sqrt(rng.randf()) * (WORLD_RADIUS - 40.0)
		var pos := Vector2(cos(ang), sin(ang)) * dist
		# стартовая площадка свободна
		if absf(pos.x) < 420.0 and absf(pos.y) < 240.0:
			continue
		var ok := true
		for q in placed:
			if q.distance_squared_to(pos) < MIN_GAP * MIN_GAP:
				ok = false
				break
		if not ok:
			continue
		placed.append(pos)
		var p = prop_script.new()
		var roll := rng.randf()
		if roll < 0.45:
			p.kind = prop_script.TREE
		elif roll < 0.67:
			p.kind = prop_script.ROCK
		elif roll < 0.92:
			p.kind = prop_script.BUSH
		else:
			p.kind = prop_script.PILLAR
		p.variant = rng.randf_range(0.85, 1.25)
		p.flip = rng.randf() < 0.5
		p.position = pos
		world.add_child(p)


# Кадры предпросмотра для CI: общий вид и лист с позами Миты.
func _shots(dir: String) -> void:
	for i in 40:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir + "/world.png")

	cam.position_smoothing_enabled = false
	cam.zoom = Vector2(2.6, 2.6)
	var poses := [[0, false, 0.0], [1, false, 0.0], [2, false, 0.0], [3, false, 0.0],
		[4, false, 0.0], [5, false, 0.0], [6, false, 0.0], [7, false, 0.0],
		[0, true, 0.5], [0, true, 1.5], [0, true, 2.5], [2, true, 1.5], [6, true, 1.5]]
	var cw := 150
	var ch := 350
	var sheet: Image = null
	var idx := 0
	for p in poses:
		player.set_pose(p[0], p[1], p[2])
		for k in 12:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if sheet == null:
			sheet = Image.create(cw * poses.size(), ch, false, img.get_format())
		var x0 := img.get_width() / 2 - cw / 2
		var y0 := img.get_height() / 2 - 325
		sheet.blit_rect(img, Rect2i(x0, maxi(y0, 0), cw, ch), Vector2i(idx * cw, 0))
		idx += 1
	sheet.save_png(dir + "/mita_sheet.png")

	# кадры боя: 4 ряда по 5 кадров, камера ближе
	cam.zoom = Vector2(2.0, 2.0)
	var acw := 200
	var ach := 280
	var asheet := Image.create(acw * 8, ach * 4, false, Image.FORMAT_RGBA8)
	for r in 4:
		for c in 8:
			player.set_attack_pose(r, c * 2)
			for k in 4:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var im2 := get_viewport().get_texture().get_image()
			im2.convert(Image.FORMAT_RGBA8)
			var ax := im2.get_width() / 2 - acw / 2
			var ay := im2.get_height() / 2 - 230
			asheet.blit_rect(im2, Rect2i(ax, maxi(ay, 0), acw, ach), Vector2i(c * acw, r * ach))
	asheet.save_png(dir + "/attack_sheet.png")
	get_tree().quit()
