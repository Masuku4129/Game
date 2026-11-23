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
	elif who == "hunt":
		_hunt()
	elif who == "build":
		_build_studio()
	elif who == "tools":
		_tools()
	elif who == "combat":
		_combat_studio()

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
	if bd_mode:
		_build_step()
		return
	if hu_mode:
		_hunt_step()
		return
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
		if t.size() > 8:
			_tools_pose(t[8])
	if subj != null and subj.tools != null and subj.tools.bundle != null:
		subj.tools.bundle.step(0.016, subj.tools.rope_anchor())
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

# ---------- STUDIO=hunt: туши до и после разделки, шкура и мясо, кости, кровь на снегу ----------
# HSCENES=через,запятую — какие сцены снять.

const HUNT := preload("res://scripts/hunt.gd")
const HMOD := preload("res://scripts/hunt_models.gd")
var hu_mode := false
var hu: Node3D
var hu_root: Node3D
var hu_scene := ""
var hu_look := Vector3.ZERO
var ground_mat: StandardMaterial3D

func _hunt() -> void:
	hu_mode = true
	fake = FakeMain.new()
	add_child(fake)
	fake.hero = Node3D.new()
	fake.add_child(fake.hero)
	for c in get_children():
		if c is MeshInstance3D and ground_mat == null:
			ground_mat = (c as MeshInstance3D).material_override
	hu = HUNT.new()
	hu.main = fake
	add_child(hu)
	hu.blood = hu.BloodMM.new()
	hu.add_child(hu.blood)
	hu.set_process(false)
	# [лист, сцена, ракурс, наклон, дистанция, высота взгляда, подпись]
	var all := {
		"roe": [["carcass_roe", 35, 30, 3.2, 0.2], ["carcass_roe", 120, 45, 3.4, 0.2], ["carcass_roe", 300, 60, 3.8, 0.1]],
		"roe_skin": [["carcass_roe", 35, 30, 3.2, 0.2], ["carcass_roe", 120, 45, 3.4, 0.2], ["carcass_roe", 300, 60, 3.8, 0.1], ["carcass_roe", 0, 75, 3.0, 0.0]],
		"roe_half": [["carcass_roe", 35, 30, 3.2, 0.2]],
		"moose_skin": [["carcass_big", 40, 38, 8.0, 0.4]],
		"moose": [["carcass_big", 40, 35, 6.0, 0.4]],
		"boar_skin": [["carcass_big", 40, 38, 4.8, 0.3]],
		"deer_skin": [["carcass_big", 40, 38, 6.5, 0.3]],
		"bear_skin": [["carcass_big", 40, 38, 6.0, 0.3]],
		"bones": [["carcass_big", 30, 40, 3.0, 0.1], ["carcass_big", 150, 55, 3.0, 0.1]],
		"items": [["items", 30, 45, 1.2, 0.0], ["items", 200, 60, 1.0, 0.0]],
		"snow": [["blood", 20, 40, 5.0, 0.0], ["blood", 0, 80, 7.0, 0.0], ["blood", 40, 25, 2.0, 0.0]],
		"earth": [["blood", 20, 40, 5.0, 0.0], ["blood", 40, 25, 2.0, 0.0]],
		"kneel": [],
	}
	for f in 14:
		all["kneel"].append(["kneel", 60, 12, 3.6, 0.7, f * 0.4])
	var want := OS.get_environment("HSCENES")
	var keys: Array = all.keys() if want == "" else Array(want.split(","))
	for k: String in keys:
		for v: Array in all[k]:
			tiles.append([v[0], k, v[1], v[2], v[3], v[4], v[5] if v.size() > 5 else 0.0])

func _hu_clear() -> void:
	if hu_root != null:
		hu_root.queue_free()
	hu_root = Node3D.new()
	add_child(hu_root)
	for pl: Dictionary in hu.piles:
		(pl["node"] as Node3D).queue_free()
	hu.piles.clear()
	hu.blood.used = 0
	hu.blood.head = 0
	hu.blood.mm.visible_instance_count = 0
	hu.force_snow = -1.0
	ground_mat.albedo_color = Color(0.3, 0.26, 0.18)

func _hu_animal(k: String, male: bool = true) -> Node3D:
	var a = ANIMAL.new()
	hu_root.add_child(a)
	a.setup(k, fake, null, Vector3.ZERO, 11, 1.0)
	if a.male != male:
		a.male = male
		a._build(false)
	a.heading = 0.0
	for i in 30:
		a._animate(1.0 / 60.0)
	a.kill()
	return a

func _hu_build(sc: String, t: Array) -> void:
	_hu_clear()
	hu_look = Vector3.ZERO
	match sc:
		"roe", "roe_skin", "roe_half", "moose", "moose_skin", "boar_skin", "deer_skin", "bear_skin":
			var k := sc.split("_")[0]
			var a := _hu_animal(k)
			var Lk: float = clampf(float(a.parts["L"]) * 0.85, 0.45, 2.2)
			hu_look = hu.body_center(a) * Vector3(1, 0, 1) + (Vector3(0.15, 0, -(0.3 + Lk * 0.25)) if sc.ends_with("_skin") else Vector3.ZERO)
			hu.pool_at(hu.body_center(a), clampf(float(a.parts["L"]) * 0.25, 0.12, 0.6), 30.0)
			if sc.ends_with("_skin") or sc.ends_with("_half"):
				var ms: Array = HMOD.skin_carcass(a)
				for m: ShaderMaterial in ms:
					m.set_shader_parameter("skinned", 0.5 if sc.ends_with("_half") else 1.0)
			if sc.ends_with("_skin"):
				var L: float = clampf(float(a.parts["L"]) * 0.85, 0.45, 2.2)
				var cen: Vector3 = hu.body_center(a)
				var pl: Dictionary = hu._new_pile(cen + Vector3(0, 0, -(0.6 + L * 0.5)) + Vector3(0.3, 0, 0), 0.3)
				var cols: Array = hu._fur_cols(a)
				hu._add_hide(pl, L, cols[0], cols[1])
				hu._add_meat(pl, hu.meat_count(a))
				for i in 8:
					var an := randf() * TAU
					hu.splat(cen + Vector3(cos(an), 0, sin(an)) * randf_range(0.2, 0.8), randf_range(0.06, 0.14), 0.0 if i % 2 == 0 else 0.5, 30.0)
		"bones":
			var n := MeshInstance3D.new()
			n.mesh = HMOD.bones_mesh(1.3, 7, true)
			hu_root.add_child(n)
		"items":
			var pl2: Dictionary = hu._new_pile(Vector3.ZERO, 0.0)
			hu._add_meat(pl2, 3)
			hu._add_meat(pl2, 2, "meat_cooked")
			var pl3: Dictionary = hu._new_pile(Vector3(0.0, 0, -0.75), 0.4)
			hu._add_hide(pl3, 0.7, Color(0.93, 0.93, 0.92), Color(0.9, 0.9, 0.88))
		"snow", "earth":
			if sc == "snow":
				hu.force_snow = 0.2
				ground_mat.albedo_color = Color(0.66, 0.69, 0.74)
			# след подранка: капли по извилистой тропе, лужа там, где лежал, место гибели
			var p := Vector3(-3.0, 0, 3.0)
			for i in 60:
				var dirv := Vector3(sin(i * 0.12) * 0.6 + 0.6, 0, -0.8).normalized()
				p += dirv * randf_range(0.08, 0.2)
				if randf() < 0.55:
					hu.splat(p + Vector3(randf_range(-0.15, 0.15), 0, randf_range(-0.15, 0.15)), randf_range(0.1, 0.2), 0.0, 16.0)
			hu.splat(Vector3(0.6, 0, 0.6), 0.4, 0.5, 16.0, 0.6, 2.2)
			hu.pool_at(Vector3(1.5, 0, -1.0), 0.45, 30.0)
			hu.blood.set_time(1.0)
		"kneel":
			var h = HERO.new()
			hu_root.add_child(h)
			h.set_process(false)
			hu._build_overlays(h.m_sk)
			hu.hand_blood = 0.8
			hu.body_blood = 0.3
			hu._tick_overlays()
			subj = h
			ap = h.m_ap
	hu.blood.set_time(1.0)

func _hunt_step() -> void:
	if ti >= tiles.size():
		_save()
		get_tree().quit()
		return
	var t: Array = tiles[ti]
	var sc: String = t[1]
	if wait == 0:
		if sc != hu_scene or sc == "kneel":
			if sc != hu_scene:
				_hu_build(sc, t)
			hu_scene = sc
		if sc == "kneel":
			ap.play("Fixing_Kneeling", 0.0)
			ap.seek(float(t[6]), true)
			ap.speed_scale = 0.0
	var yaw := deg_to_rad(float(t[2]))
	var pitch := deg_to_rad(float(t[3]))
	var look := Vector3(0, float(t[5]), 0) + hu_look
	cam.position = look + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * float(t[4])
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
	var key: String = t[0] + "_" + sc if t[0] != "kneel" else "kneel"
	if not sheets.has(key):
		sheets[key] = []
	sheets[key].append(crop)
	print("studio ", key, " ", t[6])
	ti += 1

# ---------- STUDIO=build: постройки лагеря ----------
# BUILD=через,запятую — какие листы снять (fire, leanto, tree, snow, cabin, stages, interior, furniture).

var bd_mode := false
var bd_geo
var bd_node: Node3D
var bd_ground: MeshInstance3D
var bd_cur := ""

func _build_studio() -> void:
	bd_mode = true
	bd_geo = load("res://scripts/build_geo.gd").new(load("res://scripts/pveg.gd").new())
	for c in get_children():
		if c is MeshInstance3D:
			bd_ground = c
	var want := OS.get_environment("BUILD")
	var all := ["fire", "leanto", "tree", "snow", "cabin", "stages", "interior", "furniture"]
	var kinds: Array = all if want == "" else Array(want.split(","))
	for k: String in kinds:
		match k:
			"fire":
				for v: Array in [[30, 25, 3.2, 0.3], [120, 35, 3.0, 0.3], [-60, 12, 2.6, 0.4], [0, 70, 3.4, 0.0]]:
					tiles.append(["b_fire", v[0], v[1], v[2], v[3], "fire", 0.0, ""])
			"leanto":
				for v: Array in [[20, 18, 6.0, 0.7], [70, 22, 6.0, 0.7], [160, 25, 6.0, 0.6], [-35, 45, 7.0, 0.5]]:
					tiles.append(["b_leanto", v[0], v[1], v[2], v[3], "leanto", 0.0, ""])
			"tree":
				for v: Array in [[40, 18, 8.0, 1.2], [110, 22, 8.0, 1.0], [-50, 15, 8.0, 1.2], [200, 35, 8.5, 1.0]]:
					tiles.append(["b_tree", v[0], v[1], v[2], v[3], "tree", 0.0, ""])
			"snow":
				for v: Array in [[15, 15, 6.0, 0.6], [80, 25, 6.0, 0.6], [180, 30, 6.0, 0.6], [-30, 60, 6.5, 0.4]]:
					tiles.append(["b_snow", v[0], v[1], v[2], v[3], "snow", 0.0, ""])
			"cabin":
				for v: Array in [[30, 15, 13.0, 2.0], [-40, 18, 13.0, 2.0], [120, 20, 13.0, 2.0], [200, 30, 14.0, 2.0], [10, 8, 6.0, 1.3], [60, 12, 5.5, 2.0]]:
					tiles.append(["b_cabin", v[0], v[1], v[2], v[3], "cabin", 0.0, ""])
			"stages":
				for st: float in [0.0, 3.0, 7.0, 11.0, 11.5, 11.8]:
					tiles.append(["b_stages", 35, 22, 13.0, 1.6, "stage", st, ""])
			"interior":
				for v: Array in [[0, 55, 9.5, 0.6], [35, 50, 9.0, 0.6], [-35, 48, 9.0, 0.6], [0, 80, 9.5, 0.3]]:
					tiles.append(["b_interior", v[0], v[1], v[2], v[3], "interior", 0.0, ""])
			"furniture":
				for f: String in ["bed", "table", "bench", "shelf", "chest", "rack", "workbench", "stove"]:
					tiles.append(["b_furniture", 35, 22, 3.6, 0.7, "furn", 0.0, f])

func _build_scene(t: Array) -> void:
	var kind: String = t[5]
	var key := kind + str(t[6]) + String(t[7])
	if key == bd_cur:
		return
	bd_cur = key
	if bd_node != null:
		bd_node.queue_free()
	bd_node = Node3D.new()
	add_child(bd_node)
	var snow := 0.0
	var gcol := Color(0.36, 0.38, 0.27)
	match kind:
		"fire":
			var f: Node3D = bd_geo.campfire()
			f.get_node("wood_low").visible = false
			bd_node.add_child(f)
			bd_node.add_child(bd_geo.spit_food("meat_raw", 0.6))
		"leanto":
			bd_node.add_child(bd_geo.lean_to())
		"tree":
			var sp: Array = bd_geo.pv.pine(301)
			var tm := MeshInstance3D.new()
			tm.mesh = sp[0]
			tm.scale = Vector3.ONE * 1.2
			bd_node.add_child(tm)
			bd_node.add_child(bd_geo.tree_shelter())
		"snow":
			snow = 1.0
			gcol = Color(0.86, 0.89, 0.95)
			bd_node.add_child(bd_geo.snow_shelter())
		"cabin":
			var cb: Node3D = bd_geo.cabin(11, 1.0, [0.0, -0.1, 0.05, -0.2, 0.0, 0.0, -0.1])
			bd_node.add_child(cb)
			var sm: GPUParticles3D = bd_geo.smoke(0.6, 0.0)
			sm.position = bd_geo.chimney_top()
			bd_node.add_child(sm)
			var fire: Node3D = bd_geo.campfire()
			fire.position = Vector3(3.5, 0, 4.5)
			bd_node.add_child(fire)
		"stage":
			var crowns := int(t[6])
			var roof := clampf((float(t[6]) - 11.0) * 2.0, 0.0, 1.0)
			if t[6] == 11.8:
				roof = 0.75
			bd_node.add_child(bd_geo.site_marks())
			if crowns > 0:
				bd_node.add_child(bd_geo.cabin(crowns, roof, [0.0, -0.1, 0.05, -0.2, 0.0, 0.0, -0.1]))
			var left := 1.0 - float(t[6]) / 12.0
			bd_node.add_child(bd_geo.site_stock({"log": int(24 * left), "plank": int(10 * left), "moss": int(10 * left), "clay": int(8 * left), "pebble": int(12 * left)}))
		"interior":
			var cb2: Node3D = bd_geo.cabin(11, 1.0, [0.0, -0.1, 0.05, -0.2, 0.0, 0.0, -0.1])
			for c in cb2.get_children():
				if c.has_meta("cut") and bool(c.get_meta("cut")):
					c.visible = false
				if c.name == "room_light":
					c.visible = true
			bd_node.add_child(cb2)
			var stv: Node3D = bd_geo.stove()
			bd_node.add_child(stv)
			var fy: float = bd_geo.floor_y()
			for fp: Array in [["bed", Vector3(1.38, fy, -1.05), 0.0], ["table", Vector3(1.2, fy, 0.95), 0.0], ["bench", Vector3(1.68, fy, 1.0), 0.0], ["shelf", Vector3(-1.72, fy, 1.0), 0.0], ["chest", Vector3(-1.5, fy, 0.05), PI * 0.5], ["workbench", Vector3(-0.2, fy, 1.7), PI * 0.5], ["rack", Vector3(0.25, fy, -1.0), 0.0]]:
				var fn: Node3D = bd_geo.furniture(fp[0])
				fn.position = fp[1]
				fn.rotation.y = fp[2]
				bd_node.add_child(fn)
		"furn":
			if String(t[7]) == "stove":
				var s2: Node3D = bd_geo.stove()
				s2.position = Vector3(0.9, -bd_geo.floor_y(), 1.0)
				bd_node.add_child(s2)
			else:
				bd_node.add_child(bd_geo.furniture(t[7]))
	(bd_ground.material_override as StandardMaterial3D).albedo_color = gcol
	for m: ShaderMaterial in bd_geo.weather_mats() + [bd_geo.pv.mats["spruce"], bd_geo.pv.mats["spruce_card"], bd_geo.pv.mats["bark"]]:
		m.set_shader_parameter("snow", snow)

func _build_step() -> void:
	if ti >= tiles.size():
		_save()
		get_tree().quit()
		return
	var t: Array = tiles[ti]
	if wait == 0:
		_build_scene(t)
	var yaw := deg_to_rad(float(t[1]))
	var pitch := deg_to_rad(float(t[2]))
	var look := Vector3(0, float(t[4]), 0)
	cam.position = look + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * float(t[3])
	cam.look_at(look, Vector3.UP)
	wait += 1
	if wait < 8:
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
	print("studio ", key, " ", t[5], " ", t[7])
	ti += 1

# ---------- STUDIO=tools: нож, топор, копьё в руке и на поясе; бревно на плече; падение дерева ----------
var fell: Node3D

func _tools() -> void:
	_hero()
	tiles.clear()
	var v2 := [[25, 6, 1.6, 1.05, "3/4 справа"], [-70, 10, 1.6, 1.05, "слева"]]
	# в руке: крупно с двух сторон
	for id in ["knife", "axe"]:
		for v: Array in v2:
			tiles.append(["tools_hand", float(v[0]) - 60.0, v[1], 1.3, 1.0, "Idle", 0.3, id, {"held": id, "belt": []}])
	# на поясе
	for v: Array in [[-90, 8, 1.6, 0.95], [100, 8, 1.6, 0.95], [180, 8, 1.8, 0.95], [40, 8, 1.8, 0.95]]:
		tiles.append(["tools_belt", v[0], v[1], v[2], v[3], "Idle", 0.3, "пояс", {"held": "", "belt": ["knife", "axe"]}])
	tiles.append(["tools_belt", -90, 8, 1.8, 0.95, "Walk", 0.3, "шаг", {"held": "", "belt": ["knife", "axe"]}])
	tiles.append(["tools_belt", 100, 8, 1.8, 0.95, "Walk", 0.95, "шаг", {"held": "", "belt": ["knife", "axe"]}])
	tiles.append(["tools_belt", 30, 8, 3.0, 0.95, "Walk", 0.5, "нож в руке", {"held": "knife", "belt": ["axe"]}])
	tiles.append(["tools_belt", 30, 8, 3.0, 0.95, "Walk", 0.5, "топор в руке", {"held": "axe", "belt": ["knife"]}])
	# копьё и действия
	for v: Array in [[40, 8, 3.4, 1.0], [-80, 8, 3.4, 1.0]]:
		tiles.append(["tools_spear", v[0], v[1], v[2], v[3], "Idle", 0.3, "копьё", {"held": "spear", "belt": ["knife"]}])
	tiles.append(["tools_spear", 70, 8, 3.4, 1.0, "Walk", 0.4, "копьё, шаг", {"held": "spear", "belt": ["knife"]}])
	tiles.append(["tools_spear", 70, 8, 3.6, 1.0, "Idle", 0.3, "удар", {"held": "spear", "act": "stab", "u": 0.45}])
	tiles.append(["tools_spear", 70, 8, 3.6, 1.1, "OverhandThrow", 0.2, "замах", {"held": "spear", "act": "throw", "t": 0.2}])
	tiles.append(["tools_spear", 70, 8, 3.6, 1.0, "Idle", 0.3, "воткнуто", {"held": "spear", "act": "stick", "u": 0.6}])
	tiles.append(["tools_spear", 70, 8, 3.4, 1.0, "TreeChopping", 0.05, "замах топором", {"held": "axe", "act": "chop"}])
	tiles.append(["tools_spear", 70, 8, 3.4, 1.0, "TreeChopping", 0.18, "удар топором", {"held": "axe", "act": "chop"}])
	tiles.append(["tools_log", 60, 8, 3.4, 1.1, "Walk", 0.4, "бревно", {"held": "log"}])
	tiles.append(["tools_log", -60, 8, 3.4, 1.1, "Idle", 0.4, "бревно", {"held": "log"}])
	# падение дерева
	for th: float in [0.0, 0.35, 0.8, 1.2, 1.5]:
		tiles.append(["tools_fall", 75, 12, 13.0, 3.0, "TreeChopping", 0.18, "падение %.2f" % th, {"held": "axe", "act": "chop", "fall": th}])

# ---------- STUDIO=combat: удары копьём, топором, ножом; лук; два бревна; присед ----------
func _combat_studio() -> void:
	_hero()
	tiles.clear()
	for u in [0.3, 0.42, 0.5]:
		tiles.append(["combat_stab", 70, 8, 3.6, 1.0, "Idle", 0.3, "копьё %.2f" % u, {"held": "spear", "act": "attack", "u": u, "data": {"tool": "spear"}}])
	tiles.append(["combat_stab", 20, 8, 3.6, 1.0, "Idle", 0.3, "копьё спереди", {"held": "spear", "act": "attack", "u": 0.5, "data": {"tool": "spear"}}])
	for at: Array in [["Sword_Regular_A", 0.3, 0.1], ["Sword_Regular_A", 0.43, 0.3], ["Sword_Regular_B", 0.12, 0.36], ["Sword_Regular_B", 0.27, 0.42]]:
		tiles.append(["combat_axe", 60, 8, 3.4, 1.0, at[0], at[1], "топор", {"held": "axe", "act": "attack", "u": at[2], "data": {"tool": "axe"}}])
	for at2: Array in [["Punch_Cross", 0.15, 0.2], ["Punch_Cross", 0.28, 0.35], ["Punch_Cross", 0.36, 0.45], ["Punch_Cross", 0.5, 0.55]]:
		tiles.append(["combat_knife", 25, 35, 2.8, 1.1, at2[0], at2[1], "нож", {"held": "knife", "act": "attack", "u": at2[2], "data": {"tool": "knife"}}])
	for v: Array in [[90, 3.0], [40, 3.0], [-60, 3.0], [140, 2.4]]:
		tiles.append(["combat_bow", v[0], 6, v[1], 1.3, "Idle", 0.3, "натяжение", {"held": "bow", "act": "shoot", "u": 0.5, "t": 1.0, "drawk": 1.0, "data": {"aiming": true}}])
	tiles.append(["combat_bow", 60, 8, 3.2, 1.0, "Idle", 0.3, "лук в руке", {"held": "bow", "belt": ["knife"]}])
	tiles.append(["combat_bow", 60, 8, 3.2, 1.0, "Walk", 0.4, "лук в руке, шаг", {"held": "bow", "belt": ["knife"]}])
	tiles.append(["combat_bow", 160, 12, 3.0, 1.1, "Idle", 0.3, "лук за спиной", {"back": "bow", "belt": ["knife", "axe"]}])
	tiles.append(["combat_bow", -120, 12, 3.0, 1.1, "Walk", 0.4, "лук за спиной", {"back": "bow", "belt": ["knife", "axe"]}])
	tiles.append(["combat_logs", 60, 8, 3.6, 1.1, "Walk", 0.4, "два бревна", {"held": "log", "logs": 2}])
	tiles.append(["combat_logs", -50, 10, 3.6, 1.1, "Idle", 0.4, "два бревна", {"held": "log", "logs": 2}])
	tiles.append(["combat_logs", 70, 8, 3.2, 0.8, "Crouch_Idle", 0.5, "присед", {"held": "knife", "belt": ["axe"]}])
	tiles.append(["combat_drag", 75, 22, 5.5, 0.7, "Walk", 0.3, "волок", {"bundle": 6}])
	tiles.append(["combat_drag", 140, 25, 5.0, 0.6, "Walk", 0.6, "волок", {"bundle": 6}])
	tiles.append(["combat_drag", 30, 18, 5.0, 0.8, "Walk", 0.9, "волок", {"bundle": 8}])
	tiles.append(["combat_drag", -100, 30, 5.0, 0.6, "Walk", 0.2, "волок", {"bundle": 3}])
	tiles.append(["combat_logs", 70, 8, 3.2, 0.8, "Crouch_Fwd", 0.5, "присед, шаг", {"held": "", "belt": ["knife", "axe"]}])

func _tools_pose(cfg: Dictionary) -> void:
	var T: Node = subj.tools
	T.act = String(cfg.get("act", ""))
	T.held = String(cfg.get("held", ""))
	T.belt = cfg.get("belt", []).duplicate()
	T.act_dur = 1.0 if T.act != "throw" else 1.2
	T.act_t = float(cfg.get("u", 0.0)) * T.act_dur
	if cfg.has("t"):
		T.act_t = float(cfg["t"])
	T.act_data = (cfg.get("data", {}) as Dictionary).duplicate()
	T.back = String(cfg.get("back", ""))
	T.drawk = float(cfg.get("drawk", 0.0))
	if cfg.has("logs"):
		T.logs = int(cfg["logs"])
	T.tr_t = 9.0
	if T.bundle != null:
		T.bundle.queue_free()
		T.bundle = null
	if cfg.has("bundle"):
		var list: Array = []
		for i in int(cfg["bundle"]):
			list.append({"r": 0.13 + 0.01 * (i % 3), "bark": Color(0.42, 0.33, 0.24).lightened(0.05 * (i % 2)), "L": 1.25})
		T.bundle = load("res://scripts/log_bundle.gd").new()
		add_child(T.bundle)
		T.bundle.setup(list, Vector3.ZERO, Vector3(0, 0, 1))
	T._refresh()
	if cfg.has("fall"):
		if fell == null:
			var pv = load("res://scripts/pveg.gd").new()
			var r: Array = pv.birch(401)
			var WT = load("res://scripts/world_tools.gd")
			fell = WT.FellTree.new()
			add_child(fell)
			fell.setup(r[0], Transform3D(Basis().scaled(Vector3(1.1, 1.1, 1.1)), Vector3(0, 0, 1.15)), "birch", null, Vector3.ZERO)
			for i in 9:
				fell.hit()
		fell.phase = "fall"
		fell.th = float(cfg["fall"])
		fell.pivot.basis = Basis(fell.axis, fell.th)
