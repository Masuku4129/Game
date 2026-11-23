extends Node3D
## Арена: тёмная руина, фиксированная камера ~45°, волны врагов. Автотест: -- autotest=/tmp/bot

var player: MitaPlayer
var enemies: Array = []
var wave := 0
var cam: Camera3D
var hud: Hud
var bot_dir := ""
var spawn_cd := 0.0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("autotest="):
			bot_dir = a.substr(9)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.05, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.42, 0.85)
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(0.6, 0.66, 1.0)
	sun.light_energy = 0.9
	sun.rotation_degrees = Vector3(-55, 160, 0)
	add_child(sun)
	_build_arena()
	player = MitaPlayer.new()
	player.enemies = enemies
	add_child(player)
	cam = Camera3D.new()
	cam.fov = 42.0
	cam.position = Vector3(0, 10.8, 8.4)
	add_child(cam)
	cam.look_at(Vector3(0, 0, -0.9), Vector3.UP)
	cam.make_current()
	var cl := CanvasLayer.new()
	add_child(cl)
	hud = Hud.new()
	hud.player = player
	cl.add_child(hud)
	spawn_wave()
	if bot_dir != "":
		DirAccess.make_dir_recursive_absolute(bot_dir)
		_bot()

func _build_arena() -> void:
	var fl := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 7.8
	cm.bottom_radius = 7.8
	cm.height = 0.3
	fl.mesh = cm
	fl.position.y = -0.15
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.13, 0.12, 0.3)
	fl.material_override = fm
	add_child(fl)
	var em := StandardMaterial3D.new()
	em.albedo_color = Color(0.4, 0.45, 1.0)
	em.emission_enabled = true
	em.emission = Color(0.35, 0.4, 1.0)
	em.emission_energy_multiplier = 1.6
	for r in [7.5, 4.2, 1.7]:
		var tm := TorusMesh.new()
		tm.inner_radius = r - 0.05
		tm.outer_radius = r
		var t := MeshInstance3D.new()
		t.mesh = tm
		t.scale.y = 0.2
		t.position.y = 0.02
		t.material_override = em
		add_child(t)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.09, 0.08, 0.2)
	for i in 16:
		var a := TAU * float(i) / 16.0 + rng.randf() * 0.2
		var rr := 8.8 + rng.randf() * 3.0
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.9 + rng.randf() * 0.8, 2.0 + rng.randf() * 4.0, 0.9 + rng.randf() * 0.8)
		b.mesh = bm
		b.material_override = pm
		b.position = Vector3(sin(a) * rr, bm.size.y * 0.4 - 0.3, -cos(a) * rr)
		b.rotation = Vector3(rng.randf() * 0.25 - 0.12, rng.randf() * 3.0, rng.randf() * 0.25 - 0.12)
		add_child(b)

func spawn_wave() -> void:
	wave += 1
	var n := mini(3 + wave, 8)
	for i in n:
		var e := Enemy.new()
		e.player = player
		e.maxhp = 50.0 + wave * 10.0
		e.hp = e.maxhp
		var a := TAU * float(i) / n + randf() * 0.5
		e.position = Vector3(sin(a), 0, -cos(a)) * (6.0 + randf() * 1.0)
		add_child(e)
		enemies.append(e)

func _process(dt: float) -> void:
	for i in range(enemies.size() - 1, -1, -1):
		if not is_instance_valid(enemies[i]):
			enemies.remove_at(i)
	var alive := 0
	for e in enemies:
		if not e.dead:
			alive += 1
	if alive == 0:
		spawn_cd += dt
		if spawn_cd > 2.0:
			spawn_cd = 0.0
			spawn_wave()
	if player.hp <= 0.0:
		player.hp = 100.0
		player.ult = 0.0
		player.global_position = Vector3.ZERO
		for e in enemies:
			if is_instance_valid(e):
				e.queue_free()
		enemies.clear()
		wave = 0
		spawn_wave()
	# клавиатура для отладки на ПК
	var k := Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
	if k != Vector2.ZERO:
		player.move_in = k

func _unhandled_key_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_J: player.press_attack()
			KEY_SPACE: player.press_jump()
			KEY_K: player.press_dash()
			KEY_1: player.skill1()
			KEY_2: player.skill2()
			KEY_3: player.skill3()
			KEY_4: player.skill4()
			KEY_L: player.press_block(true)
	elif ev is InputEventKey and not ev.pressed and ev.keycode == KEY_L:
		player.press_block(false)

func shot(name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [bot_dir, name])

func wait(t: float) -> void:
	await get_tree().create_timer(t).timeout

func _bot() -> void:
	await wait(1.0)
	await shot("00_idle")
	player.move_in = Vector2(0.7, 0.7)
	await wait(0.6)
	await shot("01_run")
	player.move_in = Vector2.ZERO
	await wait(0.3)
	for i in 4:
		player.press_attack()
		await wait(0.17)
		await shot("02_atk%d" % (i + 1))
		await wait(0.12)
	await wait(0.8)
	player.press_jump()
	player.move_in = Vector2(0, -1)
	await wait(0.3)
	await shot("03_jump")
	player.press_jump()
	await wait(0.15)
	await shot("04_pirouette")
	await wait(0.8)
	player.move_in = Vector2.ZERO
	player.press_dash()
	await wait(0.1)
	await shot("05_dash")
	await wait(0.5)
	player.press_block(true)
	await wait(0.5)
	await shot("06_block")
	player.press_block(false)
	player.skill1()
	await wait(0.45)
	await shot("07_skill1")
	await wait(1.0)
	player.skill2()
	await wait(0.4)
	await shot("08_skill2")
	await wait(1.2)
	player.skill3()
	await wait(0.1)
	player.press_attack()
	await wait(0.2)
	await shot("09_style")
	await wait(0.6)
	player.ult = 100.0
	player.skill4()
	await wait(0.5)
	await shot("10_ult_charge")
	await wait(1.0)
	await shot("11_ult_fly")
	await wait(1.2)
	await shot("12_ult_boom")
	print("BOT enemies=", enemies.size(), " hp=", player.hp, " style=", player.style, " state=", player.state)
	get_tree().quit()
