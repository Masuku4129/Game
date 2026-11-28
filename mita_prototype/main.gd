extends Node3D

# Mita Prototype 01: ground, 45-degree isometric camera, player and mobile touch joystick.
const MitaScript = preload("res://mita_character.gd")
var player: Node3D
var move_vector := Vector2.ZERO
var joystick_center := Vector2(110, 0)
var joystick_active := false
var joystick_touch := -1
var base_ui: Control
var stick: ColorRect

func _ready():
	_make_ground()
	_make_camera()
	_make_light()
	player = MitaScript.new()
	add_child(player)
	player.position = Vector3.ZERO
	_make_ui()

func _make_ground():
	var ground = MeshInstance3D.new()
	var mesh = PlaneMesh.new()
	mesh.size = Vector2(32, 32)
	ground.mesh = mesh
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.075, 0.065, 0.12)
	mat.roughness = 0.92
	ground.material_override = mat
	add_child(ground)

func _make_camera():
	var camera = Camera3D.new()
	camera.position = Vector3(0, 11, 11)
	camera.rotation_degrees = Vector3(-45, 0, 0)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 9
	add_child(camera)
	camera.current = true

func _make_light():
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52, -30, 0)
	light.light_color = Color(0.65, 0.58, 1.0)
	light.light_energy = 1.25
	add_child(light)
	var world = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.035, 0.02, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.28, 0.24, 0.48)
	env.ambient_light_energy = 0.8
	world.environment = env
	add_child(world)

func _make_ui():
	base_ui = Control.new()
	base_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base_ui.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(base_ui)
	var pad = ColorRect.new()
	pad.color = Color(0.14, 0.13, 0.2, 0.48)
	pad.size = Vector2(140, 140)
	pad.position = Vector2(30, -170)
	pad.anchor_top = 1
	pad.anchor_bottom = 1
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	base_ui.add_child(pad)
	var nub = ColorRect.new()
	nub.color = Color(0.5, 0.42, 0.8, 0.75)
	nub.size = Vector2(56, 56)
	nub.position = Vector2(72, -128)
	nub.anchor_top = 1
	nub.anchor_bottom = 1
	nub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	base_ui.add_child(nub)
	stick = nub
	var hint = Label.new()
	hint.text = "Touch joystick • Shift / RUN"
	hint.position = Vector2(18, 18)
	hint.add_theme_color_override("font_color", Color(0.68, 0.62, 0.85, 0.8))
	base_ui.add_child(hint)

func _input(event):
	if event is InputEventScreenTouch:
		if event.pressed and event.position.x < get_viewport().get_visible_rect().size.x * 0.45 and joystick_touch == -1:
			joystick_touch = event.index
			joystick_center = event.position
			joystick_active = true
			_update_stick(event.position)
		elif not event.pressed and event.index == joystick_touch:
			joystick_touch = -1
			joystick_active = false
			move_vector = Vector2.ZERO
			stick.position = Vector2(72, -128)
			player.set_move(Vector2.ZERO)
		elif event is InputEventScreenDrag and event.index == joystick_touch:
			_update_stick(event.position)
		elif event is InputEventKey:
			if event.keycode == KEY_SHIFT:
				player.set_running(event.pressed)

func _update_stick(pos: Vector2):
	var delta = pos - joystick_center
	if delta.length() > 58:
		delta = delta.normalized() * 58
	move_vector = Vector2(delta.x, delta.y) / 58.0
	stick.position = Vector2(72, -128) + delta
	player.set_move(move_vector)

func _process(delta):
	var keyboard = Vector2.ZERO
	keyboard.x = Input.get_axis("ui_left", "ui_right")
	keyboard.y = Input.get_axis("ui_up", "ui_down")
	if keyboard.length() > 0.1:
		player.set_move(keyboard.normalized())
	elif not joystick_active:
		player.set_move(Vector2.ZERO)
	player.set_running(Input.is_key_pressed(KEY_SHIFT))
	player.tick_animation(delta)
