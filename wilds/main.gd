extends Node2D
## Точка входа: собирает мир из кода.
## Вид как в Don't Starve: плоские 2D-спрайты, камера 3/4 сверху,
## порядок отрисовки по Y (кто ниже на экране, тот ближе к камере).

const WORLD_RADIUS := 12000.0

var world: Node2D
var level
var player
var cam: Camera2D
var fps_label: Label
var kills := 0
var _snd: AudioStreamPlayer   # звуковой движок


func _ready() -> void:
	level = preload("res://valley.gd").new()
	RenderingServer.set_default_clear_color(level.clear_color)
	add_child(level)

	# узел с y_sort_enabled сортирует детей по position.y
	world = Node2D.new()
	world.y_sort_enabled = true
	add_child(world)
	level.build(world)

	player = preload("res://player.gd").new()
	player.world_radius = WORLD_RADIUS
	player.lift_fn = Callable(level, "lift_at")
	player.position = level.spawn
	player.spawn_pos = level.spawn
	world.add_child(player)

	cam = Camera2D.new()
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 8.0
	player.add_child(cam)

	var ui := CanvasLayer.new()
	add_child(ui)
	ui.add_child(_make_vignette(level.vignette))
	var stick = preload("res://joystick.gd").new()
	ui.add_child(stick)
	player.stick = stick
	var buttons = preload("res://action_buttons.gd").new()
	buttons.player = player
	ui.add_child(buttons)

	var hud = preload("res://hud.gd").new()
	hud.player = player
	hud.main = self
	ui.add_child(hud)

	fps_label = Label.new()
	fps_label.position = Vector2(12, 8)
	fps_label.add_theme_font_size_override("font_size", 18)
	ui.add_child(fps_label)

	# звуки
	_snd = AudioStreamPlayer.new()
	add_child(_snd)
	add_to_group("sound")

	var shots := OS.get_environment("SHOTS")
	if shots != "":
		_shots(shots)


func on_kill(_kind: String) -> void:
	kills += 1
	play_sound("kill")


## Воспроизводит процедурный звук по имени
func play_sound(name: String) -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.12
	_snd.stream = gen
	_snd.play()
	var pb := _snd.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb == null:
		return
	var frames := int(gen.mix_rate * gen.buffer_length)
	var buf := PackedVector2Array()
	buf.resize(frames)
	match name:
		"hit":        _gen_hit(buf, frames, gen.mix_rate)
		"kill":       _gen_kill(buf, frames, gen.mix_rate)
		"attack":     _gen_attack(buf, frames, gen.mix_rate)
		"skill":      _gen_skill(buf, frames, gen.mix_rate)
		"boss_rage":  _gen_boss_rage(buf, frames, gen.mix_rate)
		_:            _gen_hit(buf, frames, gen.mix_rate)
	pb.push_buffer(buf)


func _gen_hit(buf: PackedVector2Array, n: int, sr: float) -> void:
	# Короткий удар: белый шум + падающий тон
	for i in n:
		var t := float(i) / sr
		var env := exp(-t * 28.0)
		var tone := sin(TAU * (320.0 - t * 800.0) * t) * 0.4
		var noise := randf_range(-1.0, 1.0) * 0.3
		var v := (tone + noise) * env * 0.6
		buf[i] = Vector2(v, v)


func _gen_kill(buf: PackedVector2Array, n: int, sr: float) -> void:
	# Убийство: короткий glitch + нисходящий свист
	for i in n:
		var t := float(i) / sr
		var env := exp(-t * 15.0)
		var freq := 480.0 * exp(-t * 6.0)
		var v := sin(TAU * freq * t) * env * 0.55
		buf[i] = Vector2(v, v)


func _gen_attack(buf: PackedVector2Array, n: int, sr: float) -> void:
	# Выпад: короткий свист воздуха
	for i in n:
		var t := float(i) / sr
		var env := exp(-t * 20.0)
		var v := randf_range(-1.0, 1.0) * env * sin(TAU * 220.0 * t) * 0.4
		buf[i] = Vector2(v, v)


func _gen_skill(buf: PackedVector2Array, n: int, sr: float) -> void:
	# Умение: восходящий арпеджио
	var notes := [261.6, 329.6, 392.0, 523.3]
	for i in n:
		var t := float(i) / sr
		var idx := clampi(int(t / (gen_duration(buf, sr) / 4.0)), 0, 3)
		var env := sin(PI * t / gen_duration(buf, sr))
		var v := sin(TAU * notes[idx] * t) * env * 0.45
		buf[i] = Vector2(v, v)


func gen_duration(buf: PackedVector2Array, sr: float) -> float:
	return buf.size() / sr


func _gen_boss_rage(buf: PackedVector2Array, n: int, sr: float) -> void:
	# Вой босса: низкий рёв
	for i in n:
		var t := float(i) / sr
		var env := sin(PI * t / (n / sr))
		var v := (sin(TAU * 80.0 * t) + sin(TAU * 160.0 * t) * 0.5) * env * 0.5
		buf[i] = Vector2(v, v)


func on_skill_unlocked() -> void:
	# передаём HUD сигнал для показа сообщения
	for n in get_tree().get_nodes_in_group("hud"):
		if n.has_method("show_message"):
			n.show_message("Умение открыто!")


func _process(_delta: float) -> void:
	fps_label.text = "FPS %d" % Engine.get_frames_per_second()


func _make_vignette(col: Color) -> TextureRect:
	# затемнение по краям экрана: фокус на персонаже
	var g := Gradient.new()
	g.set_color(0, Color(col.r, col.g, col.b, 0.0))
	g.set_color(1, col)
	g.add_point(0.55, Color(col.r, col.g, col.b, 0.0))
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
	# обзор всей карты и места
	var info: Dictionary = level.preview_info()
	player.set_pose(2, false, 0.0)
	player.position = info["center"]
	cam.zoom = Vector2.ONE * float(info["zoom"])
	for k in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir + "/map_overview.png")

	cam.zoom = Vector2(0.75, 0.75)
	var places: Array = info["spots"]
	var pw := 640
	var ph := 360
	var pimg := Image.create(pw * 4, ph * 2, false, Image.FORMAT_RGBA8)
	for n in places.size():
		player.position = places[n]
		for k in 8:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var pi := get_viewport().get_texture().get_image()
		pi.convert(Image.FORMAT_RGBA8)
		pi.resize(pw, ph)
		pimg.blit_rect(pi, Rect2i(0, 0, pw, ph), Vector2i((n % 4) * pw, (n / 4) * ph))
	pimg.save_png(dir + "/places.png")
	get_tree().quit()
