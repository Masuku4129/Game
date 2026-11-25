extends Node3D
## Demo scene: ground, light, orbit camera, touch controls, HUD.

const Character = preload("res://scripts/character.gd")

var ch: Node3D
var cam: Camera3D
var cam_yaw := 0.0
var cam_pitch := 0.32
var cam_dist := 5.2
var cam_focus := Vector3(0, 1.1, 0)
var stick_id := -1
var stick_origin := Vector2.ZERO
var stick := Vector2.ZERO
var look_id := -1
var sprint := false
var wind_on := false
var hud: Label
var joy: Control
var fps_smooth := 60.0

func _ready() -> void:
	_build_world()
	ch = Character.new()
	add_child(ch)
	_build_ui()

func _build_world() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.20, 0.30, 0.50)
	sm.sky_horizon_color = Color(0.62, 0.66, 0.74)
	sm.ground_horizon_color = Color(0.45, 0.47, 0.52)
	sm.ground_bottom_color = Color(0.18, 0.19, 0.22)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 35, 0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30.0
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	ground.mesh = pm
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 g = abs(fract(wpos.xz - 0.5) - 0.5) / fwidth(wpos.xz);
	float line = 1.0 - min(min(g.x, g.y), 1.0);
	vec2 g5 = abs(fract(wpos.xz / 5.0 - 0.5) - 0.5) / fwidth(wpos.xz / 5.0);
	float line5 = 1.0 - min(min(g5.x, g5.y), 1.0);
	vec3 base = vec3(0.30, 0.32, 0.35);
	ALBEDO = mix(base, vec3(0.50, 0.52, 0.56), line * 0.55 + line5 * 0.45);
	ROUGHNESS = 0.95;
}
"""
	var gm := ShaderMaterial.new()
	gm.shader = sh
	ground.material_override = gm
	add_child(ground)
	cam = Camera3D.new()
	cam.fov = 55.0
	cam.far = 600.0
	cam.current = true
	add_child(cam)

func _mk_btn(text: String, pos: Vector2, size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 26)
	return b

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(16, 10)
	hud.add_theme_font_size_override("font_size", 22)
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_theme_constant_override("outline_size", 6)
	layer.add_child(hud)
	joy = Control.new()
	joy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	joy.draw.connect(_draw_joy)
	layer.add_child(joy)
	var b_jump := _mk_btn("Прыжок", Vector2(1120, 470), Vector2(140, 110))
	var b_roll := _mk_btn("Кувырок", Vector2(960, 560), Vector2(140, 110))
	var b_punch := _mk_btn("Удар\nкулаком", Vector2(1120, 590), Vector2(140, 110))
	var b_kick := _mk_btn("Удар ногой\nс разворота", Vector2(940, 430), Vector2(160, 110))
	var b_sprint := _mk_btn("Ускорение", Vector2(1120, 350), Vector2(140, 100))
	b_sprint.toggle_mode = true
	var b_cloak := _mk_btn("Плащ: физика", Vector2(16, 90), Vector2(190, 64))
	b_cloak.toggle_mode = true
	b_cloak.button_pressed = true
	var b_wind := _mk_btn("Ветер", Vector2(16, 164), Vector2(190, 64))
	b_wind.toggle_mode = true
	for b in [b_jump, b_roll, b_punch, b_kick, b_sprint, b_cloak, b_wind]:
		layer.add_child(b)
	b_jump.pressed.connect(func(): _do("jump"))
	b_roll.pressed.connect(func(): _do("roll"))
	b_punch.pressed.connect(func(): _do("punch"))
	b_kick.pressed.connect(func(): _do("spinkick"))
	b_sprint.toggled.connect(func(on: bool): sprint = on)
	b_cloak.toggled.connect(func(on: bool): ch.cloak_enabled = on)
	b_wind.toggled.connect(func(on: bool): wind_on = on)

func _do(name: String) -> void:
	if not ch.ready_ok:
		return
	if (name == "punch" or name == "spinkick" or name == "roll") and stick.length() > 0.2:
		var d := _stick_world()
		ch.anim.yaw = atan2(d.x, d.y)
	ch.do_action(name)

func _stick_world() -> Vector2:
	var f := Vector2(-sin(cam_yaw), -cos(cam_yaw))
	var r := Vector2(-f.y, f.x)
	var v := f * stick.y + r * stick.x
	return v.normalized() if v.length() > 0.001 else Vector2.ZERO

func _draw_joy() -> void:
	if stick_id < 0:
		joy.draw_arc(Vector2(170, 540), 80, 0, TAU, 48, Color(1, 1, 1, 0.25), 4.0)
		return
	joy.draw_arc(stick_origin, 90, 0, TAU, 48, Color(1, 1, 1, 0.45), 4.0)
	joy.draw_circle(stick_origin + stick * 90.0, 34, Color(1, 1, 1, 0.55))

func _unhandled_input(ev: InputEvent) -> void:
	var vp := get_viewport().get_visible_rect().size
	if ev is InputEventScreenTouch:
		var e: InputEventScreenTouch = ev
		if e.pressed:
			if e.position.x < vp.x * 0.45 and stick_id < 0:
				stick_id = e.index
				stick_origin = e.position
				stick = Vector2.ZERO
			elif look_id < 0:
				look_id = e.index
		else:
			if e.index == stick_id:
				stick_id = -1
				stick = Vector2.ZERO
			if e.index == look_id:
				look_id = -1
		joy.queue_redraw()
	elif ev is InputEventScreenDrag:
		var e2: InputEventScreenDrag = ev
		if e2.index == stick_id:
			var d := (e2.position - stick_origin) / 90.0
			stick = Vector2(d.x, -d.y)
			if stick.length() > 1.0:
				stick = stick.normalized()
			joy.queue_redraw()
		elif e2.index == look_id:
			cam_yaw -= e2.relative.x * 0.006
			cam_pitch = clampf(cam_pitch + e2.relative.y * 0.004, -0.15, 1.1)

func _process(delta: float) -> void:
	# keyboard fallback (desktop testing)
	var kb := Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_down", "ui_up"))
	var st := stick if stick_id >= 0 else kb
	var m := st.length()
	var saved := stick
	stick = st
	var dirw := _stick_world()
	stick = saved
	var spd := 0.0
	if m > 0.1:
		if m < 0.5:
			spd = lerpf(0.6, 2.0, (m - 0.1) / 0.4)
		else:
			spd = lerpf(2.0, 7.2 if sprint else 5.2, (m - 0.5) / 0.5)
	ch.input_dir = dirw
	ch.input_speed = spd
	if wind_on:
		ch.set_wind(Vector3(-3.0, 0.0, 1.5))
	else:
		ch.set_wind(Vector3.ZERO)
	# camera
	var tgt: Vector3 = ch.world_pos() + Vector3(0, 1.15, 0)
	cam_focus = cam_focus.lerp(tgt, 1.0 - exp(-8.0 * delta))
	var off := Vector3(sin(cam_yaw) * cos(cam_pitch), sin(cam_pitch), cos(cam_yaw) * cos(cam_pitch)) * cam_dist
	cam.global_position = cam_focus + off
	cam.look_at(cam_focus, Vector3.UP)
	fps_smooth = lerpf(fps_smooth, 1.0 / maxf(delta, 0.0001), 0.05)
	if ch.ready_ok:
		hud.text = "%s   v=%.1f м/с\nFPS %.0f  аним %.1f мс  плащ %.1f мс" % [ch.get_state(), ch.anim.vel.length(), fps_smooth, ch.anim_ms, ch.cloak_ms]
	else:
		hud.text = "Загрузка / ошибка модели (см. лог)"
