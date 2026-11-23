extends Node2D
## Точка входа: собирает мир из кода.
## Вид как в Don't Starve: плоские 2D-спрайты, камера 3/4 сверху,
## порядок отрисовки по Y (кто ниже на экране, тот ближе к камере).

const G := preload("res://geo.gd")
const WORLD_RADIUS := 12000.0

var world: Node2D
var level
var player
var cam: Camera2D
var fps_label: Label


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.01, 0.01, 0.035))
	level = preload("res://level.gd").new()
	add_child(level)

	# узел с y_sort_enabled сортирует детей по position.y
	world = Node2D.new()
	world.y_sort_enabled = true
	add_child(world)
	level.build(world)

	player = preload("res://player.gd").new()
	player.world_radius = WORLD_RADIUS
	player.lift_fn = Callable(level, "lift_at")
	player.position = Vector2.ZERO
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


# Кадры предпросмотра для CI: общий вид и лист с позами Миты.
func _shots(dir: String) -> void:
	for i in 40:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir + "/world.png")

	cam.position_smoothing_enabled = false
	# обзор всей карты
	player.set_pose(2, false, 0.0)
	var mid: Vector2 = Vector2(G.GW * G.W * 0.5, G.GH * G.H * 0.5) + level.origin
	player.position = mid
	cam.zoom = Vector2(0.135, 0.135)
	for k in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir + "/map_overview.png")

	# места: ворота, зал, мост, лестница, библиотека, терраса, камеры, снаружи
	cam.zoom = Vector2(0.75, 0.75)
	var places := [[45.0, 46.0], [45.0, 10.0], [68.0, 33.0], [81.5, 24.0],
		[14.0, 31.0], [79.0, 13.0], [12.0, 52.0], [50.0, 55.0]]
	var pw := 640
	var ph := 360
	var pimg := Image.create(pw * 4, ph * 2, false, Image.FORMAT_RGBA8)
	for n in places.size():
		player.position = Vector2(places[n][0] * G.W, places[n][1] * G.H) + level.origin
		for k in 8:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var pi := get_viewport().get_texture().get_image()
		pi.convert(Image.FORMAT_RGBA8)
		pi.resize(pw, ph)
		pimg.blit_rect(pi, Rect2i(0, 0, pw, ph), Vector2i((n % 4) * pw, (n / 4) * ph))
	pimg.save_png(dir + "/places.png")
	get_tree().quit()
