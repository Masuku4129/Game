extends Node3D
## Студия для утверждения моделей: существо с разных сторон и кадры анимаций,
## собранные в листы PNG. Запуск: SHOTS=папка STUDIO=hero godot res://scenes/studio.tscn

const HERO := preload("res://scripts/hero.gd")
var cam := Camera3D.new()
var subj: Node3D
var ap: AnimationPlayer
var sk: Skeleton3D
var seat: MeshInstance3D
var tiles: Array = []      # [имя листа, ракурс yaw, наклон, дистанция, высота взгляда, анимация, время, подпись]
var ti := 0
var wait := 0
var sheets := {}
const CW := 480
const CH := 640

func _ready() -> void:
	_env()
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	g.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.38, 0.27)
	gm.roughness = 1.0
	g.material_override = gm
	add_child(g)
	add_child(cam)
	cam.current = true
	cam.fov = 40.0
	var who := OS.get_environment("STUDIO")
	if who == "" or who == "hero":
		_hero()
	elif who == "species":
		_species()

	elif who == "beaver":
		_beaver()
	elif who == "pack":
		_pack()

## Бобр: ракурсы и позы (шаг, плавание, грызёт, хлопок хвостом). STUDIO=beaver
var bv: Node3D
var water: MeshInstance3D

func _beaver() -> void:
	bv = load("res://scripts/animal.gd").new()
	add_child(bv)
	bv.set_process(false)
	bv.kind = "beaver"
	bv.sp = preload("res://scripts/animal_model.gd").SPECIES["beaver"]
	bv.parts = preload("res://scripts/animal_model.gd").build(bv, "beaver", 1.0, true)
	water = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(12, 12)
	water.mesh = pm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.12, 0.28, 0.3, 0.8)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.material_override = wm
	water.position.y = 0.02
	water.visible = false
	add_child(water)
	for v: Array in [[0, 10, 2.0, "спереди"], [45, 15, 2.0, "три четверти"], [90, 5, 2.0, "сбоку"], [180, 15, 2.0, "сзади"], [60, 70, 2.4, "сверху"], [20, 5, 0.9, "морда"]]:
		tiles.append(["beaver_views", v[0], v[1], v[2], 0.2, "idle", 0.0, v[3]])
	for a: Array in [["walk", 0.0, "шаг"], ["walk", 1.6, "шаг"], ["swim", 0.0, "плывёт"], ["swim", 1.5, "плывёт"], ["gnaw", 0.0, "грызёт"], ["gnaw_low", 0.0, "грызёт ствол"], ["slap", 0.3, "хвост вверх"], ["slap", 0.62, "шлепок"]]:
		tiles.append(["beaver_anims", 70, 12, 2.2, 0.25, a[0], a[1], a[2]])

func _beaver_pose(pose: String, ph: float) -> void:
	bv.position = Vector3.ZERO
	bv.state = "wander"
	bv.speed = 0.0
	bv.swim_k = 0.0
	bv.gnaw_low = false
	bv.slap_t = 0.0
	water.visible = false
	match pose:
		"walk":
			bv.speed = 0.6
		"swim":
			bv.speed = 0.8
			bv.swim_k = 1.0
			bv.position.y = -0.32
			water.visible = true
		"gnaw", "gnaw_low":
			bv.state = "gnaw"
			bv.gnaw_low = pose == "gnaw_low"
		"slap":
			bv.swim_k = 1.0
			bv.position.y = -0.32
			water.visible = true
	for i in 30:
		bv._animate_beaver(0.1)
	if pose == "slap":
		bv.slap_t = 0.7 * (1.0 - ph)
		bv._animate_beaver(0.0001)
	else:
		bv.phase = ph
		bv._animate_beaver(0.0001)

func _hero() -> void:
	subj = HERO.new()
	add_child(subj)
	subj.set_process(false)
	ap = subj.m_ap
	sk = subj.m_sk
	seat = MeshInstance3D.new()
	seat.mesh = CylinderMesh.new()
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.42, 0.32, 0.22)
	seat.material_override = sm
	seat.visible = false
	add_child(seat)
	# лист 1: фигура с четырёх сторон, лицо, вид из игры
	for v: Array in [[0, 8, 4.6, 0.95, "спереди"], [40, 8, 4.6, 0.95, "три четверти"], [90, 8, 4.6, 0.95, "сбоку"], [180, 8, 4.6, 0.95, "сзади"],
			[0, 4, 1.25, 1.62, "лицо"], [35, 4, 1.25, 1.62, "лицо, 3/4"], [140, 20, 2.2, 1.3, "спина, короб"], [30, 45, 12.0, 0.9, "из игры (45°)"]]:
		tiles.append(["hero_views", v[0], v[1], v[2], v[3], "Idle", 0.3, v[4]])
	# лист 2: движения
	for a: Array in [["Walk", 0.0, "шаг"], ["Walk", 0.5, "шаг"], ["Jog_Fwd", 0.15, "бег"], ["Jog_Fwd", 0.45, "бег"],
			["Sprint", 0.2, "рывок"], ["Jump", 0.2, "прыжок"], ["Swim_Fwd", 0.2, "плавание"], ["Swim_Fwd", 0.7, "плавание"],
			["Sitting_Idle", 0.5, "сидит"], ["TreeChopping", 0.4, "рубит"], ["PickUp_Table", 0.5, "поднимает"], ["Death01", 3.0, "гибель"]]:
		tiles.append(["hero_anims", 60, 8, 4.6, 0.85, a[0], a[1], a[2]])

## Короб: кадры снятия (opening) и надевания (closing). STUDIO=pack
var pk_mode := false

func _pack() -> void:
	_hero()
	tiles.clear()
	pk_mode = true
	subj.pack_open()
	var views := [[35, 14, 3.4, 0.8], [-80, 10, 3.4, 0.8]]
	var vi := OS.get_environment("PKVIEW")
	for v: Array in ([views[int(vi)]] if vi != "" else views):
		for u in [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]:
			tiles.append(["pack_open_%d" % int(v[0]), v[0], v[1], v[2], v[3], "opening", u, "u %.2f" % u])
		for u in [0.9, 0.5, 0.3, 0.15, 0.07, 0.0]:
			tiles.append(["pack_close_%d" % int(v[0]), v[0], v[1], v[2], v[3], "closing", u, "u %.2f" % u])

func _pack_pose(t: Array) -> void:
	var u: float = t[6]
	if t[5] == "opening":
		subj.pack_stage = "opening"
		subj.pack_t = u * subj.PK_OPEN_T
	else:
		subj.pack_stage = "closing"
		subj.pack_t = (1.0 - u) * subj.PK_CLOSE_T
	subj.state = "pack"
	subj._process_pack(0.0)
	subj.state = "pack"
	subj._animate_model(0.016)
	subj.position = Vector3.ZERO

func _env() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.55, 0.78)
	sky_mat.sky_horizon_color = Color(0.74, 0.8, 0.82)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.66, 0.64)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.sky = sky
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.92, 0.78)
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.shadow_enabled = true
	add_child(sun)

func _process(_d: float) -> void:
	if sp_mode:
		_species_step()
		return
	if ti >= tiles.size():
		_save()
		get_tree().quit()
		return
	var t: Array = tiles[ti]
	if pk_mode:
		_pack_pose(t)
	elif wait == 0 and bv != null:
		_beaver_pose(t[5], float(t[6]))
	elif wait == 0:
		var an: String = t[5]
		if ap.has_animation(an):
			ap.play(an, 0.0)
			ap.seek(float(t[6]), true)
			ap.speed_scale = 0.0
		else:
			print("studio: нет анимации ", an)
		subj.position = Vector3.ZERO
		var m: Node3D = subj.model
		m.position = Vector3.ZERO
		seat.visible = an.begins_with("Sitting")
	if wait == 1 and seat != null and seat.visible:
		var py: float = sk.get_bone_global_pose(sk.find_bone("pelvis")).origin.y
		seat.position = Vector3(0, (py - 0.1) * 0.5, -0.05)
		seat.scale = Vector3(0.35, (py - 0.1) * 0.5, 0.35)
	var yaw := deg_to_rad(float(t[1]))
	var pitch := deg_to_rad(float(t[2]))
	var look := Vector3(0, float(t[4]), 0)
	cam.position = look + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * float(t[3])
	cam.look_at(look, Vector3.UP)
	wait += 1
	if wait < 4:
		return
	wait = 0
	var img := get_viewport().get_texture().get_image()
	var w := img.get_width()
	var h := img.get_height()
	var cw := int(h * float(CW) / CH)
	var crop := img.get_region(Rect2i((w - cw) / 2, 0, cw, h))
	crop.resize(CW, CH, Image.INTERPOLATE_LANCZOS)
	var key: String = t[0]
	if not sheets.has(key):
		sheets[key] = []
	sheets[key].append(crop)
	print("studio ", key, " ", t[7])
	ti += 1

# ---------- STUDIO=species: новые звери тайги ----------
# Каждый вид — лист: ракурсы в покое, кадры шага и бега, кормёжка, нападение/взлёт.
# KINDS=через,запятую — какие виды снять (по умолчанию все новые).

const ANIMAL := preload("res://scripts/animal.gd")
var sp_mode := false
var sp_a: Node3D
var sp_kind := ""
var fake: FakeMain

## Заглушка мира для зверя: ровная земля, полдень.
class FakeMain extends Node3D:
	const SIZE := 512.0
	const WATER_Y := -100.0
	var t_hours := 12.0
	var day_count := 1
	var day_factor := 1.0
	var hero: Node3D = null
	var weather = null
	func ground_at(_x: float, _z: float) -> float:
		return 0.0
	func height(_x: float, _z: float) -> float:
		return 0.0

func _species() -> void:
	sp_mode = true
	fake = FakeMain.new()
	add_child(fake)
	fake.hero = Node3D.new()
	fake.hero.position = Vector3(0, 0, 30)
	fake.add_child(fake.hero)
	var kinds := ["moose", "lynx", "wolverine", "capercaillie", "muskdeer", "hare", "squirrel", "boar", "bear", "tiger"]
	var ke := OS.get_environment("KINDS")
	if ke != "":
		kinds = Array(ke.split(","))
	for k: String in kinds:
		var bird := k == "capercaillie"
		# [лист, вид, самец, ракурс, наклон, состояние, скорость (доля бега), время, подпись]
		for v: Array in [[90, 6, "сбоку"], [35, 10, "три четверти"], [0, 6, "спереди"], [150, 14, "сзади, 3/4"]]:
			tiles.append([k, k, true, v[0], v[1], "idle", 0.0, 1.0, v[2]])
		for f in 3:
			tiles.append([k, k, true, 90, 4, "walk", 0.0, 2.0 + f * 0.27, "шаг %d" % (f + 1)])
		for f in 3:
			tiles.append([k, k, true, 160 if bird else 90, 35 if bird else 4, "run", 1.0, 2.0 + f * 0.11, ("полёт %d" if bird else "бег %d") % (f + 1)])
		tiles.append([k, k, true, 60, 10, "graze", 0.0, 3.0, "кормится"])
		tiles.append([k, k, true, 60, 8, "attack", 0.0, 0.35, "токует" if bird else ("угроза" if k in ["moose", "muskdeer"] else "нападение")])
		tiles.append([k, k, true, 60, 10, "rest", 0.0, 4.0, "отдыхает"])
		tiles.append([k, k, false, 40, 8, "idle", 0.0, 1.0, "самка" if k in ["moose", "capercaillie", "muskdeer"] else "молодой"])

func _species_step() -> void:
	if ti >= tiles.size():
		_save()
		get_tree().quit()
		return
	var t: Array = tiles[ti]
	if wait == 0:
		if sp_a != null:
			sp_a.queue_free()
		var a = ANIMAL.new()
		add_child(a)
		var male: bool = t[2]
		var sc := 1.0 if male or t[1] in ["moose", "capercaillie", "muskdeer"] else 0.6
		a.setup(t[1], fake, null, Vector3.ZERO, 5, sc)
		a.male = male
		a._build(false)
		if a.parts.has("def"):
			print("studio tris ", t[1], " ", a.parts["def"]["tris"])
		a.heading = 0.0
		var st: String = t[5]
		var run: float = a.sp["run"]
		var walk: float = a.sp["walk"]
		a.state = {"idle": "wander", "walk": "wander", "run": "flee", "graze": "graze", "attack": "wander", "rest": "rest"}[st]
		a.speed = run if st == "run" else (walk if st == "walk" else 0.0)
		a.want = a.speed
		if st == "run" and t[1] == "capercaillie":
			a.climb_h = 2.0
		# прогон анимации до нужного момента
		var steps := int(float(t[7]) * 60.0)
		for i in steps:
			if st == "attack" and i == steps - 20:
				a._attack_t = 0.8
			a._animate(1.0 / 60.0)
		a.position = Vector3(0, a.climb_h, 0)
		a.rotation.y = 0.0
		sp_a = a
	var L: float = sp_a.parts["L"]
	var H: float = sp_a.parts["H"]
	var size := maxf(L * 1.25, H * 2.1) + 0.3
	var yaw := deg_to_rad(float(t[3]))
	var pitch := deg_to_rad(float(t[4]))
	var look := Vector3(0, H * 0.8 + sp_a.climb_h, 0)
	cam.position = look + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * size * 2.2
	cam.look_at(look, Vector3.UP)
	wait += 1
	if wait < 4:
		return
	wait = 0
	var img := get_viewport().get_texture().get_image()
	var w := img.get_width()
	var h := img.get_height()
	var cw := int(h * float(CW) / CH)
	var crop := img.get_region(Rect2i((w - cw) / 2, 0, cw, h))
	crop.resize(CW, CH, Image.INTERPOLATE_LANCZOS)
	_label(crop, String(t[8]))
	var key: String = t[0]
	if not sheets.has(key):
		sheets[key] = []
	sheets[key].append(crop)
	print("studio ", key, " ", t[8])
	ti += 1

## Подпись кадра: тёмная полоса внизу (текст не рисуем — достаточно порядка кадров).
func _label(im: Image, _txt: String) -> void:
	im.fill_rect(Rect2i(0, CH - 6, CW, 6), Color(0.1, 0.1, 0.1))

func _save() -> void:
	var dir := OS.get_environment("SHOTS")
	if dir == "":
		dir = "user://"
	for key: String in sheets:
		var arr: Array = sheets[key]
		var cols := 4
		var rows := (arr.size() + cols - 1) / cols
		var sheet := Image.create(CW * cols, CH * rows, false, Image.FORMAT_RGB8)
		for i in arr.size():
			var im: Image = arr[i]
			im.convert(Image.FORMAT_RGB8)
			sheet.blit_rect(im, Rect2i(0, 0, CW, CH), Vector2i((i % cols) * CW, (i / cols) * CH))
		sheet.save_png(dir + "/" + key + ".png")
		print("studio saved ", key)
