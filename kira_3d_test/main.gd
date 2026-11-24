extends Node3D
## Тестовая сцена управления персонажем: ходьба, бег, удар катаной.
## Телефон: левый джойстик (слабый наклон = ходьба, сильный = бег), справа кнопка УДАР.
## Компьютер: WASD или стрелки, Shift = бег, Space или J = удар.

const MODEL_PATH := "res://assets/kira_rigged.glb"
const KATANA_PATH := "res://assets/katana.glb"
const WALK_SPEED := 1.33
const RUN_SPEED := 3.7
const RUN_THRESHOLD := 0.65
const DEAD_ZONE := 0.18
const TURN_SPEED := 12.0
const ARENA_LIMIT := 36.0
const CAMERA_OFFSET := Vector3(0.0, 8.5, 7.5)
const BLEND := 0.18
# Положение катаны в системе правой кисти (под хват в анимациях)
const KATANA_POS := Vector3(-0.03431, -0.08436, -0.11899)
const KATANA_QUAT := Quaternion(0.58072, -0.40344, 0.58072, -0.40344)

var player: Node3D
var model: Node3D
var skeleton: Skeleton3D
var anim: AnimationPlayer
var trail: SlashTrail
var cam: Camera3D
var ui: TouchUI
var hud: Label
var state := "idle"
var attack_time := 0.0
var attack_len := 1.1
var combo := 0               # номер удара в комбо: 0, 1, 2
var combo_queued := false
const COMBO_ROLES := ["slash", "slash2", "slash4", "slash5", "slash3"]
const COMBO_WINDOW := 0.30
const ATTACK_RANGE := 2.4        # радиус зоны поражения (было ~1.6, +50%)
# для каждого удара: [время попадания (с), рывок вперёд (м), множитель радиуса ударной волны]
# для каждого удара: [время попадания, рывок вперёд (м), множитель радиуса волны, окно шлейфа от, до, наклон плоскости волны (град), высота волны (м)]
const HIT_INFO := {
	"slash":  [0.21, 0.9, 1.0, 0.16, 0.30, 38.0, 1.0],
	"slash2": [0.22, 0.9, 1.0, 0.15, 0.31, -8.0, 1.0],
	"slash4": [0.30, 0.7, 1.35, 0.16, 0.40, 0.0, 0.55],
	"slash5": [0.26, 0.8, 1.1, 0.16, 0.34, -62.0, 1.1],
	"slash3": [0.30, 1.4, 1.3, 0.26, 0.38, 90.0, 1.2]}
const JUMP_DIST := 1.9
var hit_done := false
var lunge_left := 0.0
var lunge_dir := Vector3.ZERO
var hits_log := []   # доля анимации, после которой повторное нажатие ставит следующий удар в очередь
var anim_of := {}            # роль -> имя анимации
var problems: PackedStringArray = PackedStringArray()
var sim_move := Vector2.ZERO # для самопроверки без экрана
var sim_active := false
var selftest := false
var cur_speed := 0.0


func _ready() -> void:
	selftest = "--selftest" in OS.get_cmdline_user_args()
	_build_world()
	_build_player()
	_build_ui()
	_set_state("idle", true)
	_report()
	if selftest:
		_run_selftest()


# ---------------------------------------------------------------- мир
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
		var dist := rng.randf_range(6.0, 24.0)
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
	cam.fov = 40.0
	add_child(cam)
	cam.current = true


# ---------------------------------------------------------------- персонаж
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
		problems.append("НЕТ МОДЕЛИ " + MODEL_PATH)
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
	else:
		for n in anim.get_animation_list():
			var low := String(n).to_lower()
			var a := anim.get_animation(n)
			var role := ""
			if low.contains("idle"): role = "idle"
			elif low.contains("walk"): role = "walk"
			elif low.contains("run"): role = "run"
			elif low == "jump": role = "jump"
			elif low == "slash5": role = "slash5"
			elif low == "slash4": role = "slash4"
			elif low == "slash3": role = "slash3"
			elif low == "slash2": role = "slash2"
			elif low == "slash": role = "slash"
			if role == "":
				continue
			anim_of[role] = n
			a.loop_mode = Animation.LOOP_NONE if (role.begins_with("slash") or role == "jump") else Animation.LOOP_LINEAR
		for role in ["idle", "walk", "run", "jump", "slash", "slash2", "slash4", "slash5", "slash3"]:
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
	if ks == null:
		problems.append("НЕТ КАТАНЫ")
		return
	if skeleton.find_bone("mixamorig_RightHand") < 0:
		problems.append("НЕТ кости mixamorig_RightHand")
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


# ---------------------------------------------------------------- интерфейс
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = TouchUI.new()
	layer.add_child(ui)
	ui.attack_pressed.connect(_on_attack)
	ui.jump_pressed.connect(_on_jump)
	hud = Label.new()
	hud.position = Vector2(18.0, 10.0)
	hud.add_theme_font_size_override("font_size", 22)
	hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	hud.add_theme_constant_override("outline_size", 6)
	layer.add_child(hud)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and (k.keycode == KEY_SPACE or k.keycode == KEY_J):
			_on_attack()
		if k.pressed and not k.echo and k.keycode == KEY_K:
			_on_jump()


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
		var run := Input.is_key_pressed(KEY_SHIFT)
		return kv.normalized() * (1.0 if run else 0.45)
	return ui.move_vector


# ---------------------------------------------------------------- логика
func _play(role: String, blend: float) -> void:
	if anim == null or not anim_of.has(role):
		return
	anim.play(anim_of[role], blend)


func _set_state(new_state: String, force := false) -> void:
	if new_state == state and not force:
		return
	state = new_state
	match state:
		"idle":
			_play("idle", BLEND)
		"walk":
			_play("walk", BLEND)
		"run":
			_play("run", BLEND)
		"jump":
			_play("jump", 0.06)
			if anim_of.has("jump"):
				attack_len = anim.get_animation(anim_of["jump"]).length
		"attack":
			_play(COMBO_ROLES[combo], 0.05)
			hit_done = false
			lunge_left = HIT_INFO[COMBO_ROLES[combo]][1]
			lunge_dir = Vector3(sin(player.rotation.y), 0.0, cos(player.rotation.y))
			if anim_of.has(COMBO_ROLES[combo]):
				attack_len = anim.get_animation(anim_of[COMBO_ROLES[combo]]).length


func _on_jump() -> void:
	if state == "attack" or state == "jump":
		return
	var v := _input_vector()
	if v.length() > DEAD_ZONE:
		player.rotation.y = atan2(v.x, v.y)
	attack_time = 0.0
	lunge_dir = Vector3(sin(player.rotation.y), 0.0, cos(player.rotation.y))
	_set_state("jump", true)


func _on_attack() -> void:
	if state == "jump":
		return
	if state == "attack":
		if attack_time >= attack_len * COMBO_WINDOW and combo < COMBO_ROLES.size() - 1:
			combo_queued = true
		return
	combo = 0
	combo_queued = false
	var v := _input_vector()
	if v.length() > DEAD_ZONE:  # удар в сторону, куда направлен джойстик
		player.rotation.y = atan2(v.x, v.y)
	attack_time = 0.0
	_set_state("attack")


func _process(delta: float) -> void:
	var v := _input_vector()
	var mag := v.length()
	cur_speed = 0.0
	if state == "jump":
		attack_time += delta
		# вперёд на время полёта (самая активная часть анимации 0.16..0.62 с)
		if attack_time > 0.16 and attack_time < 0.62:
			var js := JUMP_DIST * delta / 0.46
			var jp := player.position + lunge_dir * js
			jp.x = clampf(jp.x, -ARENA_LIMIT, ARENA_LIMIT)
			jp.z = clampf(jp.z, -ARENA_LIMIT, ARENA_LIMIT)
			player.position = jp
		if attack_time >= attack_len:
			_set_state("idle", true)
	elif state == "attack":
		attack_time += delta
		# в начале удара можно довернуть персонажа джойстиком
		if mag > DEAD_ZONE and attack_time < attack_len * 0.25:
			player.rotation.y = lerp_angle(player.rotation.y, atan2(v.x, v.y), 1.0 - exp(-10.0 * delta))
		# рывок вперёд до момента попадания и ударная волна-полумесяц на земле
		var info: Array = HIT_INFO[COMBO_ROLES[combo]]
		if attack_time < float(info[0]) + 0.06 and lunge_left > 0.0:
			var step := minf(lunge_left, float(info[1]) * delta / (float(info[0]) + 0.06))
			lunge_left -= step
			var np := player.position + lunge_dir * step
			np.x = clampf(np.x, -ARENA_LIMIT, ARENA_LIMIT)
			np.z = clampf(np.z, -ARENA_LIMIT, ARENA_LIMIT)
			player.position = np
		if trail != null:
			trail.active = attack_time >= float(info[3]) and attack_time <= float(info[4])
		if not hit_done and attack_time >= float(info[0]):
			hit_done = true
			_spawn_crescent(float(info[2]), float(info[5]), float(info[6]))
			hits_log.append(COMBO_ROLES[combo])
		if attack_time >= attack_len * 0.90 and combo_queued:
			combo += 1
			combo_queued = false
			attack_time = 0.0
			if mag > DEAD_ZONE:
				player.rotation.y = atan2(v.x, v.y)
			_set_state("attack", true)
		elif attack_time >= attack_len:
			combo = 0
			_set_state("idle", true)
	elif mag > DEAD_ZONE:
		if trail != null:
			trail.active = false
		var dir := Vector3(v.x, 0.0, v.y).normalized()
		var target_yaw := atan2(dir.x, dir.z)
		player.rotation.y = lerp_angle(player.rotation.y, target_yaw, 1.0 - exp(-TURN_SPEED * delta))
		var running := mag >= RUN_THRESHOLD
		cur_speed = RUN_SPEED if running else WALK_SPEED
		var p := player.position + dir * cur_speed * delta
		p.x = clampf(p.x, -ARENA_LIMIT, ARENA_LIMIT)
		p.z = clampf(p.z, -ARENA_LIMIT, ARENA_LIMIT)
		player.position = p
		_set_state("run" if running else "walk")
	else:
		if trail != null:
			trail.active = false
		_set_state("idle")
	# камера сверху под 45°
	var target := player.position + Vector3(0.0, 1.0, 0.0)
	var want := target + CAMERA_OFFSET
	cam.position = cam.position.lerp(want, 1.0 - exp(-8.0 * delta))
	cam.look_at(target, Vector3.UP)
	_update_hud()


func _spawn_crescent(scale_f: float, roll_deg: float, height: float) -> void:
	# Волна-полумесяц в плоскости удара: вылетает вперёд, расширяется и рассыпается.
	# Её размер = зона поражения (ATTACK_RANGE * scale_f).
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
	var fwd := Vector3(sin(player.rotation.y), 0.0, cos(player.rotation.y))
	# плоскость лежит горизонтально (нормаль вверх), затем наклоняется вокруг направления удара
	var base := Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0))
	var yaw_b := Basis(Vector3.UP, player.rotation.y)
	var roll_b := Basis(Vector3(0, 0, 1), deg_to_rad(roll_deg))
	var b := yaw_b * roll_b * base
	var start := player.global_position + fwd * 0.5 + Vector3(0.0, height, 0.0)
	mi.global_transform = Transform3D(b, start)
	var tw := create_tween()
	tw.tween_method(func(p: float) -> void:
		mat.set_shader_parameter("progress", p)
		var s := lerpf(0.55, 1.0, ease(p, 0.35))
		mi.global_transform = Transform3D(b.scaled(Vector3(s, s, s)), start + fwd * (ATTACK_RANGE * 0.8 * p)), 0.0, 1.0, 0.42)
	tw.tween_callback(mi.queue_free)


func _update_hud() -> void:
	var cur := anim.current_animation if anim != null else "-"
	var tip := trail.get_tip_speed() if trail != null else 0.0
	var txt := "состояние: %s   анимация: %s\nскорость: %.2f   кончик меча: %.1f   FPS: %d" % [state, cur, cur_speed, tip, Engine.get_frames_per_second()]
	if problems.size() > 0:
		txt += "\nПРОБЛЕМЫ: " + ", ".join(problems)
	hud.text = txt


func _report() -> void:
	print("KIRA_CHECK anims=", anim_of, " skeleton=", skeleton != null, " trail=", trail != null, " problems=", problems)
	if anim != null:
		print("KIRA_CHECK animation_list=", anim.get_animation_list())
	if skeleton != null:
		print("KIRA_CHECK bones=", skeleton.get_bone_count())


# ---------------------------------------------------------------- самопроверка (CI)
func _run_selftest() -> void:
	var log := func(tag: String) -> void:
		print("KIRA_TEST ", tag, " state=", state, " anim=", anim.current_animation if anim != null else "-", " pos=", player.position)
	sim_active = true
	await get_tree().create_timer(0.5).timeout
	log.call("idle")
	sim_move = Vector2(0.0, -0.4)
	await get_tree().create_timer(0.8).timeout
	log.call("walk")
	sim_move = Vector2(0.0, -1.0)
	await get_tree().create_timer(0.8).timeout
	log.call("run")
	sim_move = Vector2.ZERO
	await get_tree().create_timer(0.4).timeout
	_on_attack()
	for i in range(4):
		await get_tree().create_timer(0.30).timeout
		_on_attack()
		await get_tree().create_timer(0.30).timeout
		log.call("attack%d" % (i + 1))
	await get_tree().create_timer(1.2).timeout
	log.call("after_combo")
	print("KIRA_TEST hits=", hits_log)
	_on_jump()
	await get_tree().create_timer(0.4).timeout
	log.call("jump_mid")
	await get_tree().create_timer(0.9).timeout
	log.call("after_jump")
	print("KIRA_TEST_DONE problems=", problems)
	get_tree().quit(1 if problems.size() > 0 else 0)
