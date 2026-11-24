extends Node3D
## Тестовая сцена боевого управления Миты.
## Телефон: левый джойстик (слабый наклон = ходьба, сильный = бег), справа УДАР, ПРЫЖОК,
## ОТСКОК, РЫВОК, БЛОК (держать). Свайп по свободной правой части экрана вращает камеру.
## Компьютер: WASD, Shift = бег, Space/J = удар, K = прыжок, U = отскок, I = рывок,
## L = блок (держать), Q/E = поворот камеры.

const MODEL_PATH := "res://assets/kira_rigged.glb"
const KATANA_PATH := "res://assets/katana.glb"
const WALK_SPEED := 1.5
const RUN_SPEED := 6.2
const RUN_THRESHOLD := 0.65
const DEAD_ZONE := 0.18
const TURN_SPEED := 14.0
const ARENA_LIMIT := 36.0
const BLEND := 0.12
# камера: ближе и вращается
const CAM_DIST := 5.6
const CAM_PITCH_MIN := 18.0
const CAM_PITCH_MAX := 70.0
const CAM_DRAG_SENS := 0.25
# Положение катаны в системе правой кисти (прямой хват, под анимации)
const KATANA_POS := Vector3(-0.03431, -0.08436, 0.10592)
const KATANA_QUAT := Quaternion(0.58072, -0.40344, -0.58072, 0.40344)

# комбо: удар 3 (круговой) -> удар ногой с разворота -> апперкот -> финал
const COMBO_ROLES := ["slash", "slash2", "slash4", "kick", "slash5", "slash3"]
const COMBO_WINDOW := 0.30
const ATTACK_RANGE := 2.4
# [время попадания, рывок вперёд (м), множитель зоны, шлейф от, до (с), наклон плоскости волны (град), высота волны (м)]
const HIT_INFO := {
	"slash":  [0.21, 0.9, 1.0, 0.16, 0.30, 38.0, 1.0],
	"slash2": [0.22, 0.9, 1.0, 0.15, 0.31, -8.0, 1.0],
	"slash4": [0.30, 0.7, 1.35, 0.16, 0.40, 0.0, 0.55],
	"kick":   [0.28, 0.6, 1.0, -1.0, -1.0, 0.0, 0.9],
	"slash5": [0.26, 0.8, 1.1, 0.16, 0.34, -62.0, 1.1],
	"slash3": [0.30, 1.4, 1.3, 0.26, 0.38, 90.0, 1.2]}
const ALL_ROLES := ["idle", "walk", "run", "block", "jump", "dodge", "dash_in", "dash_out",
	"slash", "slash2", "slash4", "kick", "slash5", "slash3"]
const LOOPED := ["idle", "walk", "run", "block"]
# перемещения спецдвижений: [начало, конец (с), дистанция (м); минус = назад]
const JUMP_MOVE := [0.20, 0.93, 3.0]
const DODGE_MOVE := [0.06, 0.54, -3.4]
const DASH_DIST := 8.0
const DASH_TIME := 0.20

var player: Node3D
var model: Node3D
var skeleton: Skeleton3D
var anim: AnimationPlayer
var trail: SlashTrail
var cam: Camera3D
var cam_yaw := 0.0
var cam_pitch := 48.0
var ui: TouchUI
var hud: Label
var state := "idle"
var state_time := 0.0
var state_len := 1.0
var combo := 0
var combo_queued := false
var anim_of := {}
var problems: PackedStringArray = PackedStringArray()
var hit_done := false
var lunge_left := 0.0
var move_dir := Vector3.ZERO
var block_held := false
var fx_done := false
var dash_from := Vector3.ZERO
var dash_beam: Node3D
var hits_log := []
var sim_move := Vector2.ZERO
var sim_active := false
var cur_speed := 0.0


func _ready() -> void:
	_build_world()
	_build_player()
	_build_ui()
	_set_state("idle", true)
	_report()
	if "--selftest" in OS.get_cmdline_user_args():
		_run_selftest()


# ================================================================ мир
func _checker_texture() -> ImageTexture:
	var img := Image.create(128, 128, true, Image.FORMAT_RGB8)
	for y in range(128):
		for x in range(128):
			var on := ((x / 64) + (y / 64)) % 2 == 0
			var base := 0.20 if on else 0.15
			img.set_pixel(x, y, Color(base * 0.9, base * 0.85, base * 1.25))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.04, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.42, 0.65)
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	sun.light_color = Color(0.85, 0.86, 1.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30.0
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(ARENA_LIMIT * 2.0 + 8.0, ARENA_LIMIT * 2.0 + 8.0)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = _checker_texture()
	gm.uv1_scale = Vector3(40.0, 40.0, 1.0)
	gm.roughness = 0.95
	ground.material_override = gm
	add_child(ground)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in range(18):
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(7.0, 24.0)
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(rng.randf_range(0.8, 2.2), rng.randf_range(0.6, 3.4), rng.randf_range(0.8, 2.2))
		box.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.22, 0.2, 0.3)
		m.roughness = 0.9
		box.material_override = m
		box.position = Vector3(cos(ang) * dist, bm.size.y * 0.5, sin(ang) * dist)
		box.rotation.y = rng.randf() * TAU
		add_child(box)
	cam = Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	cam.current = true


# ================================================================ персонаж
func _find_first(root: Node, type_name: String) -> Node:
	if root.get_class() == type_name:
		return root
	for c in root.get_children():
		var r := _find_first(c, type_name)
		if r != null:
			return r
	return null


func _build_player() -> void:
	player = Node3D.new()
	player.name = "Player"
	player.rotation.y = PI
	add_child(player)
	var scene := load(MODEL_PATH) as PackedScene
	if scene == null:
		problems.append("НЕТ МОДЕЛИ")
		return
	model = scene.instantiate() as Node3D
	model.position = Vector3(0.0, 1.0, 0.0)  # ноги модели стоят на y = -1
	player.add_child(model)
	skeleton = _find_first(model, "Skeleton3D") as Skeleton3D
	anim = _find_first(model, "AnimationPlayer") as AnimationPlayer
	if skeleton == null:
		problems.append("НЕТ Skeleton3D")
	if anim == null:
		problems.append("НЕТ AnimationPlayer")
		return
	for n in anim.get_animation_list():
		var role := String(n).to_lower().replace("-loop", "")
		if not (role in ALL_ROLES):
			continue
		anim_of[role] = n
		anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR if role in LOOPED else Animation.LOOP_NONE
	for role in ALL_ROLES:
		if not anim_of.has(role):
			problems.append("НЕТ анимации " + role)
	_attach_katana()


func _boost_emission(n: Node) -> void:
	var energy := {"blade": 2.0, "glow": 6.0, "glow2": 4.0}
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for i in range(mi.get_surface_override_material_count()):
			var m := mi.get_active_material(i) as StandardMaterial3D
			if m != null and energy.has(m.resource_name):
				m.emission_enabled = true
				m.emission_energy_multiplier = energy[m.resource_name]
	for c in n.get_children():
		_boost_emission(c)


func _attach_katana() -> void:
	if skeleton == null:
		return
	var ks := load(KATANA_PATH) as PackedScene
	if ks == null or skeleton.find_bone("mixamorig_RightHand") < 0:
		problems.append("НЕТ катаны или кости кисти")
		return
	var att := BoneAttachment3D.new()
	att.bone_name = "mixamorig_RightHand"
	skeleton.add_child(att)
	var katana := ks.instantiate() as Node3D
	att.add_child(katana)
	katana.transform = Transform3D(Basis(KATANA_QUAT), KATANA_POS)
	_boost_emission(katana)
	var tip := katana.find_child("TrailTip", true, false) as Node3D
	var base := katana.find_child("TrailBase", true, false) as Node3D
	if tip == null or base == null:
		problems.append("НЕТ меток шлейфа")
		return
	trail = SlashTrail.new()
	trail.tip_node = tip
	trail.base_node = base
	add_child(trail)


# ================================================================ ввод
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = TouchUI.new()
	layer.add_child(ui)
	ui.attack_pressed.connect(_on_attack)
	ui.jump_pressed.connect(_on_jump)
	ui.dodge_pressed.connect(_on_dodge)
	ui.dash_pressed.connect(_on_dash)
	ui.block_changed.connect(_on_block)
	ui.camera_drag.connect(_on_camera_drag)
	hud = Label.new()
	hud.position = Vector2(18.0, 10.0)
	hud.add_theme_font_size_override("font_size", 22)
	hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	hud.add_theme_constant_override("outline_size", 6)
	layer.add_child(hud)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if k.echo:
		return
	if k.pressed:
		match k.keycode:
			KEY_SPACE, KEY_J:
				_on_attack()
			KEY_K:
				_on_jump()
			KEY_U:
				_on_dodge()
			KEY_I:
				_on_dash()
			KEY_L:
				_on_block(true)
	elif k.keycode == KEY_L:
		_on_block(false)


func _on_camera_drag(d: Vector2) -> void:
	cam_yaw -= d.x * CAM_DRAG_SENS
	cam_pitch = clampf(cam_pitch + d.y * CAM_DRAG_SENS * 0.6, CAM_PITCH_MIN, CAM_PITCH_MAX)


func _input_vector() -> Vector2:
	if sim_active:
		return sim_move
	var kv := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		kv.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		kv.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		kv.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		kv.x += 1.0
	if kv != Vector2.ZERO:
		return kv.normalized() * (1.0 if Input.is_key_pressed(KEY_SHIFT) else 0.45)
	return ui.move_vector


## направление на земле в мире с учётом поворота камеры
func _world_dir(v: Vector2) -> Vector3:
	var d := Vector3(v.x, 0.0, v.y)
	return d.rotated(Vector3.UP, deg_to_rad(cam_yaw))


func _face_input() -> void:
	var v := _input_vector()
	if v.length() > DEAD_ZONE:
		var d := _world_dir(v)
		player.rotation.y = atan2(d.x, d.z)


func _forward() -> Vector3:
	return Vector3(sin(player.rotation.y), 0.0, cos(player.rotation.y))


func _busy() -> bool:
	return state in ["attack", "jump", "dodge", "dash_in", "dash_beam", "dash_out"]


# ================================================================ состояния
func _play(role: String, blend: float) -> void:
	if anim == null or not anim_of.has(role):
		return
	anim.play(anim_of[role], blend)
	if not (role in LOOPED):
		state_len = anim.get_animation(anim_of[role]).length


func _set_state(new_state: String, force := false) -> void:
	if new_state == state and not force:
		return
	state = new_state
	state_time = 0.0
	fx_done = false
	if trail != null:
		trail.active = false
	match state:
		"idle", "walk", "run", "block", "jump", "dodge", "dash_in", "dash_out":
			_play(state, 0.06 if state in ["block", "jump", "dodge", "dash_in"] else BLEND)
		"attack":
			var role: String = COMBO_ROLES[combo]
			_play(role, 0.05)
			hit_done = false
			lunge_left = float(HIT_INFO[role][1])
			move_dir = _forward()
		"dash_beam":
			state_len = DASH_TIME


func _on_attack() -> void:
	if state == "attack":
		if state_time >= state_len * COMBO_WINDOW and combo < COMBO_ROLES.size() - 1:
			combo_queued = true
		return
	if _busy():
		return
	combo = 0
	combo_queued = false
	_face_input()
	_set_state("attack", true)


func _on_jump() -> void:
	if _busy():
		return
	_face_input()
	move_dir = _forward()
	_set_state("jump", true)


func _on_dodge() -> void:
	if _busy() and state != "attack":
		return
	_face_input()
	move_dir = _forward()
	_set_state("dodge", true)


func _on_dash() -> void:
	if _busy() and state != "attack":
		return
	_face_input()
	move_dir = _forward()
	_set_state("dash_in", true)


func _on_block(held: bool) -> void:
	block_held = held
	if held and not _busy():
		_set_state("block")
	elif not held and state == "block":
		_set_state("idle")


func _move(delta_pos: Vector3) -> void:
	var p := player.position + delta_pos
	p.x = clampf(p.x, -ARENA_LIMIT, ARENA_LIMIT)
	p.z = clampf(p.z, -ARENA_LIMIT, ARENA_LIMIT)
	player.position = p


## равномерное перемещение на dist за окно [t0, t1] анимации
func _move_window(delta: float, t0: float, t1: float, dist: float) -> void:
	var a := clampf(state_time - delta, t0, t1)
	var b := clampf(state_time, t0, t1)
	if b > a:
		_move(move_dir * dist * (b - a) / (t1 - t0))


func _process(delta: float) -> void:
	state_time += delta
	var v := _input_vector()
	var mag := v.length()
	cur_speed = 0.0
	match state:
		"attack":
			_process_attack(delta, v, mag)
		"jump":
			_move_window(delta, JUMP_MOVE[0], JUMP_MOVE[1], JUMP_MOVE[2])
			if not fx_done and state_time >= 0.19:
				fx_done = true
				_spawn_ripple(player.global_position + Vector3(0.0, 0.05, 0.0), 3.2, true)
				_spawn_ripple(player.global_position + Vector3(0.0, 1.0, 0.0), 2.4, false)
			if state_time >= state_len:
				_set_state("idle", true)
		"dodge":
			_move_window(delta, DODGE_MOVE[0], DODGE_MOVE[1], DODGE_MOVE[2])
			if state_time >= state_len:
				_set_state("idle", true)
		"dash_in":
			_move_window(delta, 0.05, 0.20, 0.5)
			if state_time >= state_len:
				_start_beam()
		"dash_beam":
			_move_window(delta, 0.0, DASH_TIME, DASH_DIST)
			if dash_beam != null:
				dash_beam.call("set_head", player.global_position + Vector3(0.0, 1.0, 0.0))
			if state_time >= DASH_TIME:
				_end_beam()
		"dash_out":
			_move_window(delta, 0.0, 0.18, 0.45)
			if state_time >= state_len:
				_set_state("idle", true)
		_:
			if block_held:
				_set_state("block")
			elif mag > DEAD_ZONE:
				var dir := _world_dir(v).normalized()
				player.rotation.y = lerp_angle(player.rotation.y, atan2(dir.x, dir.z), 1.0 - exp(-TURN_SPEED * delta))
				var running := mag >= RUN_THRESHOLD
				cur_speed = RUN_SPEED if running else WALK_SPEED
				_move(dir * cur_speed * delta)
				_set_state("run" if running else "walk")
			else:
				_set_state("idle")
	_update_camera(delta)
	_update_hud()


func _process_attack(delta: float, v: Vector2, mag: float) -> void:
	var role: String = COMBO_ROLES[combo]
	var info: Array = HIT_INFO[role]
	if mag > DEAD_ZONE and state_time < state_len * 0.2:
		var d := _world_dir(v)
		player.rotation.y = lerp_angle(player.rotation.y, atan2(d.x, d.z), 1.0 - exp(-12.0 * delta))
		move_dir = _forward()
	var t_hit := float(info[0])
	if state_time < t_hit + 0.06 and lunge_left > 0.0:
		var step := minf(lunge_left, float(info[1]) * delta / (t_hit + 0.06))
		lunge_left -= step
		_move(move_dir * step)
	if trail != null:
		trail.active = state_time >= float(info[3]) and state_time <= float(info[4])
	if not hit_done and state_time >= t_hit:
		hit_done = true
		hits_log.append(role)
		if role == "kick":
			_spawn_ripple(player.global_position + _forward() * 1.1 + Vector3(0.0, 0.9, 0.0), 2.0, false)
		else:
			_spawn_crescent(float(info[2]), float(info[5]), float(info[6]))
	if state_time >= state_len * 0.90 and combo_queued:
		combo += 1
		combo_queued = false
		_face_input()
		_set_state("attack", true)
	elif state_time >= state_len:
		combo = 0
		_set_state("idle", true)


func _update_camera(delta: float) -> void:
	if Input.is_key_pressed(KEY_Q):
		cam_yaw += 90.0 * delta
	if Input.is_key_pressed(KEY_E):
		cam_yaw -= 90.0 * delta
	var target := player.position + Vector3(0.0, 1.0, 0.0)
	var pr := deg_to_rad(cam_pitch)
	var off := Vector3(0.0, sin(pr), cos(pr)) * CAM_DIST
	var want := target + off.rotated(Vector3.UP, deg_to_rad(cam_yaw))
	cam.position = cam.position.lerp(want, 1.0 - exp(-10.0 * delta))
	cam.look_at(target, Vector3.UP)


# ================================================================ эффекты
func _spawn_crescent(scale_f: float, roll_deg: float, height: float) -> void:
	# Волна-полумесяц в плоскости удара: вылетает вперёд, расширяется и рассыпается.
	var size := ATTACK_RANGE * scale_f * 2.0
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	mi.mesh = quad
	var mat := ShaderMaterial.new()
	mat.shader = load("res://crescent.gdshader")
	mat.set_shader_parameter("progress", 0.0)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	add_child(mi)
	var fwd := _forward()
	var base := Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0))
	var b := Basis(Vector3.UP, player.rotation.y) * Basis(Vector3(0, 0, 1), deg_to_rad(roll_deg)) * base
	var start := player.global_position + fwd * 0.5 + Vector3(0.0, height, 0.0)
	mi.global_transform = Transform3D(b, start)
	var tw := create_tween()
	tw.tween_method(func(p: float) -> void:
		mat.set_shader_parameter("progress", p)
		var s := lerpf(0.55, 1.0, ease(p, 0.35))
		mi.global_transform = Transform3D(b.scaled(Vector3(s, s, s)), start + fwd * (ATTACK_RANGE * 0.8 * p)), 0.0, 1.0, 0.42)
	tw.tween_callback(mi.queue_free)


## Содрогание воздуха: кольцо искажения (горизонтальное у земли или обращённое к камере)
func _spawn_ripple(pos: Vector3, size: float, flat: bool) -> void:
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	mi.mesh = quad
	var mat := ShaderMaterial.new()
	mat.shader = load("res://ripple.gdshader")
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	add_child(mi)
	if flat:
		mi.global_transform = Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)), pos)
	else:
		mi.global_position = pos
		mi.look_at(cam.global_position, Vector3.UP)
		mi.rotate_object_local(Vector3.UP, PI)
	var tw := create_tween()
	tw.tween_method(func(p: float) -> void:
		mat.set_shader_parameter("progress", p), 0.0, 1.0, 0.38)
	tw.tween_callback(mi.queue_free)


func _start_beam() -> void:
	_set_state("dash_beam", true)
	if model != null:
		model.visible = false
	dash_from = player.global_position + Vector3(0.0, 1.0, 0.0)
	dash_beam = DashBeam.new()
	add_child(dash_beam)
	dash_beam.call("setup", dash_from, _forward())
	_spawn_ripple(dash_from, 2.2, false)


func _end_beam() -> void:
	if dash_beam != null:
		dash_beam.call("finish")
		dash_beam = null
	if model != null:
		model.visible = true
	_spawn_ripple(player.global_position + Vector3(0.0, 1.0, 0.0), 2.0, false)
	_set_state("dash_out", true)


# ================================================================ HUD и самопроверка
func _update_hud() -> void:
	var cur := anim.current_animation if anim != null else "-"
	var tip := trail.get_tip_speed() if trail != null else 0.0
	var txt := "состояние: %s   анимация: %s\nскорость: %.2f   кончик меча: %.1f   FPS: %d" % [state, cur, cur_speed, tip, Engine.get_frames_per_second()]
	if problems.size() > 0:
		txt += "\nПРОБЛЕМЫ: " + ", ".join(problems)
	hud.text = txt


func _report() -> void:
	print("KIRA_CHECK anims=", anim_of.keys(), " skeleton=", skeleton != null, " trail=", trail != null, " problems=", problems)


func _log(tag: String) -> void:
	print("KIRA_TEST ", tag, " state=", state, " anim=", anim.current_animation if anim != null else "-", " pos=", player.position.snapped(Vector3(0.01, 0.01, 0.01)))


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _run_selftest() -> void:
	sim_active = true
	await _wait(0.4)
	_log("idle")
	sim_move = Vector2(0.0, -0.4)
	await _wait(0.6)
	_log("walk")
	sim_move = Vector2(0.0, -1.0)
	await _wait(0.6)
	_log("run")
	sim_move = Vector2.ZERO
	await _wait(0.3)
	# жмём удар часто, как игрок: комбо должно пройти все 6 ударов
	var seen := []
	for i in range(60):
		_on_attack()
		if state == "attack" and not (COMBO_ROLES[combo] in seen):
			seen.append(COMBO_ROLES[combo])
		await _wait(0.08)
	await _wait(1.0)
	print("KIRA_TEST combo_seen=", seen, " hits=", hits_log)
	_log("after_combo")
	_on_jump()
	await _wait(0.5)
	_log("jump_mid")
	await _wait(1.0)
	_log("after_jump")
	_on_dodge()
	await _wait(0.3)
	_log("dodge_mid")
	await _wait(0.8)
	_log("after_dodge")
	_on_block(true)
	await _wait(0.4)
	_log("block")
	_on_block(false)
	await _wait(0.2)
	_on_dash()
	await _wait(0.3)
	_log("dash_mid")
	await _wait(0.8)
	_log("after_dash")
	if seen.size() < COMBO_ROLES.size():
		problems.append("комбо прошло не полностью")
	print("KIRA_TEST_DONE problems=", problems)
	get_tree().quit(1 if problems.size() > 0 else 0)
