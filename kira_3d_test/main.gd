extends Node3D
## Тестовая сцена боевого управления Миты.
## Телефон: левый джойстик (слабый наклон = ходьба, сильный = бег), справа УДАР, ПРЫЖОК,
## ОТСКОК, РЫВОК, БЛОК (держать). Свайп по свободной правой части экрана вращает камеру.
## Компьютер: WASD, Shift = бег, Space/J = удар, K = прыжок, U = отскок, I = рывок,
## L = блок (держать), Q/E = поворот камеры.

const MODEL_PATH := "res://assets/kira_rigged.glb"
const KATANA_PATH := "res://assets/katana.glb"
const WALK_SPEED := 1.9
const RUN_SPEED := 7.6
const RUN_THRESHOLD := 0.65
const DEAD_ZONE := 0.18
const TURN_SPEED := 14.0
const BLEND := 0.12
# камера: закреплена сверху под 40 градусов, без вращения
const CAM_DIST := 60.0
const CAM_PITCH := 36.0
const CAM_ORTHO := 15.0         # высота кадра в метрах: изометрия как в 2D-играх
const MAX_HP := 100.0
const WAVE_PAUSE := 3.0
# Положение катаны в системе правой кисти (прямой хват, под анимации)
const KATANA_POS := Vector3(-0.03431, -0.08436, 0.10592)
const KATANA_QUAT := Quaternion(0.58072, -0.40344, -0.58072, 0.40344)

# комбо: удары выбираются из набора AtkData по направлению стика, концовка - один из финишеров
const COMBO_WINDOW := 0.08
const CHAIN_AFTER_HIT := 0.05
const ATTACK_RANGE := 2.4
const MAX_COMBO := 6
const GAME_SPEED := 0.85
const A_CHAIN := ["slash", "slash2", "slash4", "slash5", "slash3"]
const A_START := ["slash"]
const A_FWD := A_CHAIN
const A_BACK := ["kick"]
const A_LEFT := A_CHAIN
const A_RIGHT := A_CHAIN
const A_MID := A_CHAIN
const A_FIN := ["slash3"]
const A_AIR := ["slash3", "slash5"]
const BASE_ROLES := ["idle", "walk", "run", "block", "jump", "dodge", "dash_in", "dash_out"]
const LOOPED := ["idle", "walk", "run", "block"]
# перемещения спецдвижений: [начало, конец (с), дистанция (м); минус = назад]
# прыжок: баллистика. взлёт на 0.24 с анимации, приземление на 1.22 с; высота и дальность задаются здесь
const JUMP_MOVE := [0.24, 1.22, 7.0]
const JUMP_HEIGHT := 4.0
const DODGE_MOVE := [0.06, 0.54, -5.0]
const DASH_DIST := 8.0
const DASH_TIME := 0.20

var player: Node3D
var model: Node3D
var skeleton: Skeleton3D
var anim: AnimationPlayer
var trail: SlashTrail
var cam: Camera3D
var cam_yaw := 25.0
var hp := MAX_HP
var wave := 0
var alive_hounds := 0
var waves_enabled := true
var wave_timer := 3.0
var invuln := 0.0
var dead_timer := 0.0
var hp_fill: ColorRect
var hp_label: Label
var kills := 0
var post_mat: ShaderMaterial
var hurt_v := 0.0
var flash_v := 0.0
var katana_light: OmniLight3D
var hit_light: OmniLight3D
var hitstop_active := false
var shake := 0.0
var waves: Array = []
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
var hit_idx := 0
var cur_atk := "slash"
var last_atk := ""
var lunge_sign := 1.0
var atk_rel := Vector2.ZERO
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
var vel := Vector3.ZERO          # инерция: текущая скорость тела
var lean := Vector2.ZERO         # наклон корпуса (x - вперёд, y - вбок)
var lean_v := Vector2.ZERO
var prev_state := "idle"
var land_fx := false
var valley: Valley
var jump_y0 := 0.0
var vy := 0.0
const GRAVITY := 30.0
var attack_buffered := false
const ACCEL := 24.0
const DECEL := 14.0
const LOCO_WALK_REF := 1.9
const LOCO_RUN_REF := 7.6


func _ready() -> void:
	Engine.time_scale = GAME_SPEED
	_build_world()
	_build_player()
	player.position = Vector3(Valley.START_POS.x, valley.height_at(Valley.START_POS.x, Valley.START_POS.z), Valley.START_POS.z)
	valley.focus = player
	_build_ui()
	_set_state("idle", true)
	_report()
	_prewarm()
	if "--selftest" in OS.get_cmdline_user_args():
		waves_enabled = false
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
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)
	valley = Valley.new()
	add_child(valley)
	valley.build()
	valley.setup_atmosphere(we, sun)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = CAM_ORTHO
	cam.near = 2.0
	cam.far = 200.0
	cam.position = Vector3(Valley.START_POS.x, 12.0, Valley.START_POS.z + 11.0)
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
	katana_light = OmniLight3D.new()
	katana_light.position = Vector3(0.0, 1.5, 0.4)
	katana_light.omni_range = 7.0
	katana_light.light_color = Color(0.62, 0.40, 1.0)
	katana_light.light_energy = 0.7
	katana_light.shadow_enabled = false
	player.add_child(katana_light)
	hit_light = OmniLight3D.new()
	hit_light.omni_range = 8.0
	hit_light.light_color = Color(0.85, 0.55, 1.0)
	hit_light.light_energy = 0.0
	hit_light.shadow_enabled = false
	add_child(hit_light)
	skeleton = _find_first(model, "Skeleton3D") as Skeleton3D
	anim = _find_first(model, "AnimationPlayer") as AnimationPlayer
	if skeleton == null:
		problems.append("НЕТ Skeleton3D")
	if anim == null:
		problems.append("НЕТ AnimationPlayer")
		return
	for n in anim.get_animation_list():
		var role := String(n).to_lower().replace("-loop", "")
		if not (role in all_roles()):
			continue
		anim_of[role] = n
		anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR if role in LOOPED else Animation.LOOP_NONE
	for role in all_roles():
		if not anim_of.has(role):
			problems.append("НЕТ анимации " + role)
	_attach_katana()


func all_roles() -> Array:
	var r: Array = BASE_ROLES.duplicate()
	r.append_array(AtkData.D.keys())
	return r


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
	var post_layer := CanvasLayer.new()
	post_layer.layer = 0
	add_child(post_layer)
	var pr := ColorRect.new()
	pr.set_anchors_preset(Control.PRESET_FULL_RECT)
	pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_mat = ShaderMaterial.new()
	post_mat.shader = load("res://post.gdshader")
	pr.material = post_mat
	post_layer.add_child(pr)
	var layer := CanvasLayer.new()
	layer.layer = 2
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
	var back := ColorRect.new()
	back.color = Color(0, 0, 0, 0.55)
	back.position = Vector2(18.0, 100.0)
	back.size = Vector2(360.0, 26.0)
	layer.add_child(back)
	hp_fill = ColorRect.new()
	hp_fill.color = Color(0.75, 0.2, 0.55, 0.95)
	hp_fill.position = Vector2(21.0, 103.0)
	hp_fill.size = Vector2(354.0, 20.0)
	layer.add_child(hp_fill)
	hp_label = Label.new()
	hp_label.position = Vector2(390.0, 96.0)
	hp_label.add_theme_font_size_override("font_size", 22)
	hp_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	hp_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(hp_label)


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


func _on_camera_drag(_d: Vector2) -> void:
	pass                                    # камера закреплена


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


func _can_act() -> bool:
	if state == "dash_out":
		return state_time > 0.06
	if state == "jump":
		return state_time > JUMP_MOVE[1] + 0.10
	if state == "dodge":
		return state_time > 0.58
	return not _busy()


func _busy() -> bool:
	return state in ["attack", "jump", "dodge", "dash_in", "dash_beam", "dash_out"]


# ================================================================ состояния
func _play(role: String, blend: float) -> void:
	if anim == null or not anim_of.has(role):
		return
	if anim.current_animation == anim_of[role] and anim.is_playing() and not (role in LOOPED):
		anim.seek(0.0, true)      # тот же клип подряд (второй отскок, повтор удара): проигрывать заново
	else:
		anim.play(anim_of[role], blend)
	if not (role in LOOPED):
		state_len = anim.get_animation(anim_of[role]).length


func _blend_for(old: String, new: String) -> float:
	if new == "attack":
		return 0.13 if old == "attack" else 0.12
	if new == "idle":
		return 0.32 if old in ["attack", "jump", "dodge", "dash_out", "block"] else 0.22
	if new in ["walk", "run"]:
		return 0.22 if old in ["idle", "walk", "run"] else 0.30
	if new == "block":
		return 0.16
	if new == "jump" or new == "dodge":
		return 0.10
	if new == "dash_in":
		return 0.10
	return BLEND


func _set_state(new_state: String, force := false) -> void:
	if new_state == state and not force:
		return
	prev_state = state
	land_fx = false
	state = new_state
	state_time = 0.0
	fx_done = false
	if trail != null:
		trail.active = false
	match state:
		"idle", "walk", "run", "block", "jump", "dodge", "dash_in", "dash_out":
			_play(state, _blend_for(prev_state, state))
		"attack":
			_play(cur_atk, _blend_for(prev_state, "attack"))
			hit_done = false
			hit_idx = 0
			var lg: float = AtkData.D[cur_atk]["lunge"]
			lunge_left = absf(lg)
			lunge_sign = -1.0 if lg < 0.0 else 1.0
			move_dir = _forward() * lunge_sign
		"dash_beam":
			state_len = DASH_TIME


func _on_attack() -> void:
	if state == "attack":
		if state_time >= state_len * COMBO_WINDOW and combo < MAX_COMBO - 1:
			combo_queued = true
			atk_rel = _input_rel()
		return
	if state in ["dash_in", "dash_beam"]:
		attack_buffered = true      # нажал во время рывка: удар вылетит сразу на выходе
		return
	if state == "jump" and state_time > JUMP_MOVE[0] + 0.08 and state_time < JUMP_MOVE[1] - 0.12 and player.position.y > valley.height_at(player.position.x, player.position.z) + 0.7:
		attack_buffered = false
		combo = 0
		combo_queued = false
		cur_atk = A_AIR[randi() % A_AIR.size()]
		last_atk = cur_atk
		vy = 0.0
		_set_state("attack", true)
		return
	if not _can_act():
		return
	attack_buffered = false
	combo = 0
	combo_queued = false
	_begin_attack(_input_rel())


func _begin_attack(rel: Vector2) -> void:
	cur_atk = _pick_attack(rel)
	last_atk = cur_atk
	_set_state("attack", true)


## вход стика относительно текущего взгляда: x - влево, y - вперёд (до поворота корпуса)
func _input_rel() -> Vector2:
	var v := _input_vector()
	if v.length() <= DEAD_ZONE:
		return Vector2.ZERO
	var d := _world_dir(v).normalized()
	var f := _forward()
	var left := Vector3(f.z, 0.0, -f.x)
	return Vector2(d.dot(left), d.dot(f))


func _pick_attack(rel: Vector2) -> String:
	if rel.length() > 0.5 and rel.y < -0.55:
		return "kick"
	return A_CHAIN[combo % A_CHAIN.size()]


func _on_attack_from_dash() -> void:
	attack_buffered = false
	combo = 0
	combo_queued = false
	_begin_attack(Vector2.ZERO)


func _on_jump() -> void:
	if not _can_act():
		return
	_face_input()
	move_dir = _forward()
	jump_y0 = player.position.y
	vy = 0.0
	_set_state("jump", true)


func _on_dodge() -> void:
	if not _can_act() and state != "attack":
		return
	_face_input()
	move_dir = _forward()
	_set_state("dodge", true)


func _on_dash() -> void:
	if not _can_act() and state != "attack":
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
	var p := valley.move_xz(player.position, delta_pos)
	player.position.x = p.x
	player.position.z = p.z


## вертикаль: плавное следование рельефу, падение со скал под действием гравитации
func _apply_ground(delta: float) -> void:
	var gh := valley.height_at(player.position.x, player.position.z)
	var y := player.position.y
	if y > gh + 0.05:
		vy -= GRAVITY * delta
		y += vy * delta
		if y <= gh:
			y = gh
			vy = 0.0
	else:
		vy = 0.0
		y = lerpf(y, gh, 1.0 - exp(-28.0 * delta))
		if absf(y - gh) < 0.003:
			y = gh
	player.position.y = y


## равномерное перемещение на dist за окно [t0, t1] анимации
func _move_window(delta: float, t0: float, t1: float, dist: float) -> void:
	var a := (clampf(state_time - delta, t0, t1) - t0) / (t1 - t0)
	var b := (clampf(state_time, t0, t1) - t0) / (t1 - t0)
	if b > a:
		# плавный разгон и торможение (smoothstep), а не равномерный сдвиг
		var sa := a * a * (3.0 - 2.0 * a)
		var sb := b * b * (3.0 - 2.0 * b)
		_move(move_dir * dist * (sb - sa))


func _process(delta: float) -> void:
	state_time += delta
	var v := _input_vector()
	var mag := v.length()
	cur_speed = 0.0
	match state:
		"attack":
			_process_attack(delta, v, mag)
		"jump":
			var t_air: float = JUMP_MOVE[1] - JUMP_MOVE[0]
			var tau := clampf(state_time - JUMP_MOVE[0], 0.0, t_air)
			var g := 8.0 * JUMP_HEIGHT / (t_air * t_air)
			var v0 := g * t_air * 0.5
			var prev_tau := clampf(state_time - delta - JUMP_MOVE[0], 0.0, t_air)
			_move(move_dir * JUMP_MOVE[2] * (tau - prev_tau) / t_air)
			var gh_j := valley.height_at(player.position.x, player.position.z)
			if state_time < JUMP_MOVE[1]:
				player.position.y = maxf(gh_j, jump_y0 + maxf(0.0, v0 * tau - 0.5 * g * tau * tau))
			if not fx_done and state_time >= JUMP_MOVE[0]:
				fx_done = true
				_spawn_ripple(player.global_position + Vector3(0.0, 0.05, 0.0), 3.2, true)
				_spawn_ripple(player.global_position + Vector3(0.0, 1.0, 0.0), 2.4, false)
			if not land_fx and state_time >= JUMP_MOVE[1]:
				land_fx = true
				_spawn_ripple(player.global_position + Vector3(0.0, 0.05, 0.0), 2.6, true)
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
			if attack_buffered:
				_on_attack_from_dash()
				return
			_move_window(delta, 0.0, 0.09, 0.3)
			if state_time > 0.07 and _input_vector().length() > DEAD_ZONE:
				vel = _forward() * RUN_SPEED * 0.85
				_set_state("run", true)
			elif state_time >= state_len:
				_set_state("idle", true)
		_:
			if block_held:
				vel = vel.move_toward(Vector3.ZERO, DECEL * 1.6 * delta)
				_move(vel * delta)
				_set_state("block")
			elif mag > DEAD_ZONE:
				var dir := _world_dir(v).normalized()
				player.rotation.y = lerp_angle(player.rotation.y, atan2(dir.x, dir.z), 1.0 - exp(-TURN_SPEED * delta))
				var running := mag >= RUN_THRESHOLD
				var target := RUN_SPEED if running else WALK_SPEED
				vel = vel.move_toward(dir * target, ACCEL * delta)
				_move(vel * delta)
				cur_speed = vel.length()
				_set_state("run" if cur_speed > 3.4 or (running and cur_speed > 2.6) else "walk")
			else:
				vel = vel.move_toward(Vector3.ZERO, DECEL * delta)
				_move(vel * delta)
				cur_speed = vel.length()
				if cur_speed > 0.5:
					_set_state("run" if cur_speed > 4.0 else "walk")
				else:
					_set_state("idle")
			if anim != null:
				if state == "walk":
					anim.speed_scale = clampf(cur_speed / LOCO_WALK_REF, 0.6, 1.25)
				elif state == "run":
					anim.speed_scale = clampf(cur_speed / LOCO_RUN_REF, 0.65, 1.15)
				else:
					anim.speed_scale = 1.0
	if state != "jump" or state_time >= JUMP_MOVE[1]:
		_apply_ground(delta)
	if state in ["attack", "jump", "dodge", "dash_in", "dash_out"]:
		if anim != null:
			anim.speed_scale = 1.0
		vel = vel.move_toward(Vector3.ZERO, 14.0 * delta)
		_move(vel * delta * 0.5)
	_update_lean(delta)
	_update_game(delta)
	_update_fx(delta)
	_update_camera(delta)
	_update_hud()


## корпус наклоняется по ускорению и в поворотах (пружина с затуханием) - даёт ощущение веса
func _update_lean(delta: float) -> void:
	if model == null:
		return
	var local_v := player.global_transform.basis.inverse() * vel
	var target := Vector2(0.0, 0.0)
	if state in ["walk", "run"]:
		target = Vector2(clampf(local_v.z * 0.012, -0.12, 0.14), clampf(-local_v.x * 0.02, -0.1, 0.1))
	var acc := (target - lean) * 90.0 - lean_v * 13.0
	lean_v += acc * delta
	lean += lean_v * delta
	model.rotation.x = lean.x
	model.rotation.z = lean.y


func _process_attack(delta: float, v: Vector2, mag: float) -> void:
	var data: Dictionary = AtkData.D[cur_atk]
	var hits: Array = data["hits"]
	var t_last: float = float((hits[hits.size() - 1] as Array)[0])
	if mag > DEAD_ZONE and state_time < 0.34 and lunge_sign > 0.0:
		var d := _world_dir(v)
		player.rotation.y = lerp_angle(player.rotation.y, atan2(d.x, d.z), 1.0 - exp(-16.0 * delta))
		move_dir = _forward()
	var t_first: float = float((hits[0] as Array)[0])
	var l0 := t_first * 0.3
	if state_time >= l0 and state_time < t_first + 0.06 and lunge_left > 0.0:
		var u := clampf((state_time - l0) / (t_first + 0.06 - l0), 0.0, 1.0)
		var w := 6.0 * u * (1.0 - u) + 0.15     # колоколообразный профиль скорости рывка
		var step := minf(lunge_left, absf(float(data["lunge"])) * delta / (t_first + 0.06 - l0) * w)
		lunge_left -= step
		_move(move_dir * step)
	if trail != null:
		var on := false
		for h in hits:
			var ha: Array = h
			if float(ha[3]) >= 0.0 and state_time >= float(ha[3]) and state_time <= float(ha[4]):
				on = true
		trail.active = on
	if hit_idx < hits.size() and state_time >= float((hits[hit_idx] as Array)[0]):
		var hi: Array = hits[hit_idx]
		hit_idx += 1
		if hit_idx >= hits.size():
			hit_done = true
		hits_log.append(cur_atk)
		_hit_hounds(cur_atk, float(data["zone"]))
		_apply_fx(String(data["fx"]), hi, float(data["zone"]))
		if cur_atk == "kick":
			_spawn_ripple(player.global_position + _forward() * 1.1 + Vector3(0.0, 0.9, 0.0), 2.0, false)
		else:
			_spawn_crescent(float(data["zone"]), float(hi[1]), float(hi[2]))
	if hit_done and state_time >= t_last + CHAIN_AFTER_HIT and combo_queued:
		combo += 1
		combo_queued = false
		_begin_attack(atk_rel)
	elif state_time >= state_len:
		combo = 0
		_set_state("idle", true)


func _apply_fx(fx: String, hi: Array, zone: float) -> void:
	match fx:
		"wave":
			_fire_wave(float(hi[1]), float(hi[2]), zone)
		"slam":
			_aoe(5.5, 30.0, 13.0)
			shake = 0.9
			_spawn_ripple(player.global_position + Vector3(0.0, 0.08, 0.0), 8.0, true)
			_spawn_ripple(player.global_position + _forward() * 1.2 + Vector3(0.0, 0.1, 0.0), 5.0, true)
		"slam_s":
			_aoe(3.4, 20.0, 9.0)
			shake = 0.4
			_spawn_ripple(player.global_position + _forward() * 1.2 + Vector3(0.0, 0.08, 0.0), 4.5, true)
		"burst":
			_aoe(4.2, 14.0, 8.0)
			shake = 0.25
			_spawn_ripple(player.global_position + Vector3(0.0, 0.1, 0.0), 6.5, true)


func _aoe(radius: float, dmg: float, power: float) -> void:
	for h in get_tree().get_nodes_in_group("hounds"):
		var hh := h as Hound
		var off := hh.position - player.position
		off.y = 0.0
		if off.length() < radius:
			hh.take_hit(dmg, player.position, power)
			_impact(hh.position, dmg > 25.0)


## световая волна катаны: летит вперёд и рубит всех на пути
func _fire_wave(tilt: float, height: float, zone: float) -> void:
	var size := ATTACK_RANGE * zone * 2.6
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
	var base := Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0))
	var b := Basis(Vector3.UP, player.rotation.y) * Basis(Vector3(0, 0, 1), deg_to_rad(tilt)) * base
	var pos := player.global_position + _forward() * 0.8 + Vector3(0.0, height, 0.0)
	mi.global_transform = Transform3D(b, pos)
	waves.append({"node": mi, "mat": mat, "basis": b, "pos": pos, "dir": _forward(), "t": 0.0, "hit": []})


func _update_waves(delta: float) -> void:
	for i in range(waves.size() - 1, -1, -1):
		var w: Dictionary = waves[i]
		w["t"] = float(w["t"]) + delta
		var t: float = w["t"]
		var dir: Vector3 = w["dir"]
		var pos: Vector3 = w["pos"]
		pos += dir * 15.0 * delta
		w["pos"] = pos
		var node: MeshInstance3D = w["node"]
		var p := clampf(t / 0.75, 0.0, 1.0)
		(w["mat"] as ShaderMaterial).set_shader_parameter("progress", p)
		var s := lerpf(0.7, 1.1, p)
		node.global_transform = Transform3D((w["basis"] as Basis).scaled(Vector3(s, s, s)), pos)
		var hitl: Array = w["hit"]
		for h in get_tree().get_nodes_in_group("hounds"):
			var hh := h as Hound
			if hitl.has(hh):
				continue
			var off := hh.position - pos
			off.y = 0.0
			if off.length() < 1.9:
				hitl.append(hh)
				hh.take_hit(20.0, pos - dir * 2.0, 8.0)
				_impact(hh.position, false)
		if t >= 0.75:
			node.queue_free()
			waves.remove_at(i)


func _hit_hounds(role: String, zone: float) -> void:
	var fwd := _forward()
	var dmg := 24.0
	if role in ["slash3", "mo_cut6"]:
		dmg = 38.0
	elif role in ["x_cut", "flurry3", "flick"]:
		dmg = 16.0
	for h in get_tree().get_nodes_in_group("hounds"):
		var hh := h as Hound
		var off := hh.position - player.position
		off.y = 0.0
		var dist := off.length()
		if dist > ATTACK_RANGE * zone + 0.8:
			continue
		if dist > 0.5 and fwd.dot(off / dist) < -0.1:
			continue
		hh.take_hit(dmg, player.position, 7.0 if dmg > 30.0 else 5.0)
		_impact(hh.position, dmg > 30.0)
		hits_log.append("hound_hit")


func on_hound_killed() -> void:
	alive_hounds -= 1
	kills += 1


func damage_player(amount: float, from: Vector3) -> void:
	if hp <= 0.0 or invuln > 0.0:
		return
	if state in ["dodge", "dash_in", "dash_beam"]:
		return
	var k := 1.0
	if state == "block":
		k = 0.25
	hp = maxf(0.0, hp - amount * k)
	invuln = 0.35
	hurt_v = 1.0
	var away := player.position - from
	away.y = 0.0
	if away.length() > 0.01:
		vel += away.normalized() * (3.0 if k < 1.0 else 7.0)
	_spawn_ripple(player.global_position + Vector3(0.0, 1.0, 0.0), 1.6, false)
	if hp <= 0.0:
		dead_timer = 2.0


func _spawn_wave() -> void:
	wave += 1
	var n := mini(2 + wave, 7)
	for i in range(n):
		var dz := (12.0 + randf() * 6.0) * (1.0 if randf() < 0.5 else -1.0)
		var pz := clampf(player.position.z + dz, -32.0, 33.0)
		if absf(pz - player.position.z) < 8.0:
			pz = clampf(player.position.z - signf(dz) * 14.0, -32.0, 33.0)
		var pos := Vector3(randf_range(-2.0, 2.0), 0.0, pz)
		var h := Hound.new()
		add_child(h)
		h.setup(valley, player, self, pos)
		alive_hounds += 1


func _update_fx(delta: float) -> void:
	_update_waves(delta)
	shake = maxf(0.0, shake - delta * 2.2)
	hurt_v = maxf(0.0, hurt_v - delta * 2.4)
	flash_v = maxf(0.0, flash_v - delta * 6.0)
	if post_mat != null:
		post_mat.set_shader_parameter("hurt", hurt_v)
		post_mat.set_shader_parameter("flash", flash_v)
		post_mat.set_shader_parameter("low_hp", 1.0 if hp < MAX_HP * 0.3 and hp > 0.0 else 0.0)
	if katana_light != null:
		var target := 0.7
		if state == "attack":
			target = 2.6
		elif state in ["dash_beam", "dash_in"]:
			target = 3.2
		katana_light.light_energy = lerpf(katana_light.light_energy, target, 1.0 - exp(-14.0 * delta))
	if hit_light != null and hit_light.light_energy > 0.01:
		hit_light.light_energy = maxf(0.0, hit_light.light_energy - delta * 22.0)


## удар по врагу: короткая остановка времени, вспышка света и искры
func _impact(pos: Vector3, strong: bool) -> void:
	flash_v = 1.0 if strong else 0.5
	hit_light.global_position = pos + Vector3(0.0, 0.4, 0.0)
	hit_light.light_energy = 7.0 if strong else 4.0
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 22 if strong else 12
	p.lifetime = 0.45
	p.local_coords = false
	var q := QuadMesh.new()
	q.size = Vector2(0.18, 0.18)
	p.mesh = q
	var fm := ShaderMaterial.new()
	fm.shader = load("res://fly.gdshader")
	fm.set_shader_parameter("glow", Color(0.85, 0.5, 1.0))
	p.material_override = fm
	p.direction = Vector3(0.0, 1.0, 0.0)
	p.spread = 180.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 8.0
	p.gravity = Vector3(0.0, -9.0, 0.0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.5
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.global_position = pos + Vector3(0.0, 0.9, 0.0)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)
	if not hitstop_active:
		hitstop_active = true
		Engine.time_scale = 0.12
		await get_tree().create_timer(0.07 if strong else 0.045, true, false, true).timeout
		Engine.time_scale = GAME_SPEED
		hitstop_active = false


func _update_game(delta: float) -> void:
	invuln = maxf(0.0, invuln - delta)
	if hp <= 0.0:
		dead_timer -= delta
		if dead_timer <= 0.0:
			for h in get_tree().get_nodes_in_group("hounds"):
				h.queue_free()
			alive_hounds = 0
			hp = MAX_HP
			wave = 0
			wave_timer = 2.0
			vel = Vector3.ZERO
			player.position = Vector3(Valley.START_POS.x, valley.height_at(Valley.START_POS.x, Valley.START_POS.z), Valley.START_POS.z)
			_set_state("idle", true)
		return
	if waves_enabled and alive_hounds <= 0:
		wave_timer -= delta
		if wave_timer <= 0.0:
			_spawn_wave()
			wave_timer = WAVE_PAUSE


func _update_camera(delta: float) -> void:
	var target := player.position + Vector3(0.0, 1.0, 0.0)
	var pr := deg_to_rad(CAM_PITCH)
	var off := Vector3(0.0, sin(pr), cos(pr)) * CAM_DIST
	var want := target + off.rotated(Vector3.UP, deg_to_rad(cam_yaw))
	cam.position = cam.position.lerp(want, 1.0 - exp(-10.0 * delta))
	if shake > 0.0:
		cam.position += Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake * 0.3
	cam.look_at(target, Vector3.UP)


# ================================================================ эффекты
## Прогрев: при первом показе шейдера/частиц телефон компилирует их и кадр зависает (микрофриз).
## Поэтому всё это один раз рисуется крошечным перед камерой на старте и сразу удаляется.
func _prewarm() -> void:
	var holder := Node3D.new()
	add_child(holder)
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05)
	for path in ["res://crescent.gdshader", "res://ripple.gdshader"]:
		var mi := MeshInstance3D.new()
		mi.mesh = q
		var mat := ShaderMaterial.new()
		mat.shader = load(path)
		mat.set_shader_parameter("progress", 0.5)
		mi.material_override = mat
		holder.add_child(mi)
		mi.global_position = cam.global_position + Vector3(0.0, -0.5, -3.0)
	var beam := DashBeam.new()
	holder.add_child(beam)
	var p0 := player.global_position + Vector3(0.0, 1.0, 0.0)
	beam.call("setup", p0, Vector3(0.0, 0.0, 1.0))
	beam.call("set_head", p0 + Vector3(0.0, 0.0, 0.05))
	beam.scale = Vector3(0.05, 0.05, 0.05)
	await get_tree().create_timer(0.35).timeout
	holder.queue_free()


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
	if state == "attack":
		cur = "%s (%d)" % [cur_atk, combo + 1]
	var txt := "состояние: %s   анимация: %s\nскорость: %.2f   кончик меча: %.1f   FPS: %d" % [state, cur, cur_speed, tip, Engine.get_frames_per_second()]
	if problems.size() > 0:
		txt += "\nПРОБЛЕМЫ: " + ", ".join(problems)
	hud.text = txt
	if hp_fill != null:
		hp_fill.size.x = 354.0 * clampf(hp / MAX_HP, 0.0, 1.0)
		hp_label.text = "Волна %d   Врагов: %d   %s" % [wave, maxi(alive_hounds, 0), "ПАЛА - возрождение..." if hp <= 0.0 else ""]


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
		if state == "attack" and not (cur_atk in seen):
			seen.append(cur_atk)
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
	# враг: появляется рядом, должен получить урон от ударов
	var th := Hound.new()
	add_child(th)
	th.setup(valley, player, self, player.position + Vector3(0.0, 0.0, -4.0))
	alive_hounds += 1
	await _wait(1.8)
	_log("hound_" + th.state)
	for i in range(40):
		_face_input()
		if is_instance_valid(th):
			var dd := th.position - player.position
			player.rotation.y = atan2(dd.x, dd.z)
		_on_attack()
		await _wait(0.1)
	await _wait(1.0)
	print("KIRA_TEST hound_killed=", kills, " player_hp=", hp, " hits=", hits_log.count("hound_hit"))
	if kills < 1:
		problems.append("гончая не убита")
	if seen.size() < 5:
		problems.append("комбо прошло не полностью")
	print("KIRA_TEST_DONE problems=", problems)
	get_tree().quit(1 if problems.size() > 0 else 0)
