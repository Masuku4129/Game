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
const COMBO_ROLES := ["slash", "slash2", "slash3"]
const COMBO_WINDOW := 0.45   # доля анимации, после которой повторное нажатие ставит следующий удар в очередь
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
	env.ambient_light_energy = 0.9
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
			elif low == "slash3": role = "slash3"
			elif low == "slash2": role = "slash2"
			elif low == "slash": role = "slash"
			if role == "":
				continue
			anim_of[role] = n
			a.loop_mode = Animation.LOOP_NONE if role.begins_with("slash") else Animation.LOOP_LINEAR
		for role in ["idle", "walk", "run", "slash", "slash2", "slash3"]:
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
		"attack":
			_play(COMBO_ROLES[combo], 0.07)
			if anim_of.has(COMBO_ROLES[combo]):
				attack_len = anim.get_animation(anim_of[COMBO_ROLES[combo]]).length


func _on_attack() -> void:
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
	if state == "attack":
		attack_time += delta
		# в начале удара можно довернуть персонажа джойстиком
		if mag > DEAD_ZONE and attack_time < attack_len * 0.25:
			player.rotation.y = lerp_angle(player.rotation.y, atan2(v.x, v.y), 1.0 - exp(-10.0 * delta))
		if attack_time >= attack_len * 0.92 and combo_queued:
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
		_set_state("idle")
	# камера сверху под 45°
	var target := player.position + Vector3(0.0, 1.0, 0.0)
	var want := target + CAMERA_OFFSET
	cam.position = cam.position.lerp(want, 1.0 - exp(-8.0 * delta))
	cam.look_at(target, Vector3.UP)
	_update_hud()


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
	await get_tree().create_timer(0.45).timeout
	log.call("attack1_mid")
	_on_attack()
	await get_tree().create_timer(0.95).timeout
	log.call("attack2_expected")
	_on_attack()
	await get_tree().create_timer(0.8).timeout
	log.call("attack3_expected")
	await get_tree().create_timer(1.6).timeout
	log.call("after_combo")
	print("KIRA_TEST_DONE problems=", problems)
	get_tree().quit(1 if problems.size() > 0 else 0)
