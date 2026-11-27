extends Node3D
## Этап 2: кусок тайги 512×512 м в стиле 4: рельеф с обрывами и рекой,
## деревья с ветками-геометрией и хвоей/листвой из текстур.

const SIZE := 512.0
const SEG := 384
const WATER_Y := -2.0
const CELL := 64.0
const FOREST_DENSITY_MULTIPLIER := 1.7
const FOREST_DENSITY_SPECIES := ["spruce", "pine", "birch", "larch", "aspen", "bare", "spruce_dead", "bush", "fern", "reeds", "twig", "berry", "bilberry", "mushroom", "fir", "cedar", "willow", "alder", "cherry", "rose", "horsetail", "hummock", "sedge", "juniper", "stlanik", "rowan", "anthill", "mossrock", "stump_rot", "stump_mush", "fungus_snag", "birch_dead", "mosslog", "ledum", "cloudberry", "cranberry", "cotton", "lingon", "ernik", "raspberry", "currant", "bells", "daisy", "angelica", "brushpile", "chanterelle", "cones"]

var n_hill := FastNoiseLite.new()
var n_cliff := FastNoiseLite.new()
var n_detail := FastNoiseLite.new()
var n_forest := FastNoiseLite.new()
var n_crag := FastNoiseLite.new()
var n_crag2 := FastNoiseLite.new()
var n_biome := FastNoiseLite.new()
var n_zone := FastNoiseLite.new()
var n_open := FastNoiseLite.new()
var n_wet := FastNoiseLite.new()
var n_glade := FastNoiseLite.new()
const RP := preload("res://scripts/river_path.gd")
## Озёра: [x, z, радиус, м]. Вдали от русла и от старта.
const LAKES := [[-150.0, -140.0, 34.0], [125.0, 160.0, 46.0], [-60.0, 205.0, 28.0], [185.0, -150.0, 30.0]]

var t_hours := 9.0
var day_count := 1
var day_factor := 1.0
var hero
var rig
var joy
var hud
var hunger := 0.85
var warmth := 0.8
var stamina := 1.0
var blockers := {}
var seats := {}
var act_btn: Button
var fps_lbl: Label
var _fps_t := 0.0
var weather
var sfx
var feet
var terrain_mat: ShaderMaterial
var health := 1.0
var thirst := 0.9
var bleed := 0.0
var injuries := {}
var inv := {}
var pickables := {}
var animals
var flash: ColorRect
var dead_lbl: Label
var dead_t := 0.0
var msg_t := 0.0
var msg := ""
var water_mat: ShaderMaterial
var beavers
var inventory  # короб: inventory.gd
# --- tools: инструменты, валка, брёвна, копья (world_tools.gd) ---
var tools_world
var res_spots := {}      # клетка 8 м → [[позиция, вид]] — кусты, ягодники (нож, руки)
var fallen_spots := {}   # клетка 16 м → [{kind, mm, i, xf, a, b, r}] — бурелом под топор
var hunt  # --- hunt: туши, разделка, кровь, запах крови (hunt.gd) ---
var camp  # --- build: лагерь и постройки (structures.gd) ---
var combat  # --- combat: удары, прицел, стрелы (combat.gd) ---
# --- colony: отряд землепроходцев, изометрическая камера, сценарий (colony.gd).
# colony_mode = true — новая игра про острог; false — старый режим героя с джойстиком
# (отладочный переключатель в настройках и переменная окружения HERO_MODE=1). ---
var colony
var colony_mode := true

func _ready() -> void:
	_colony_pick_mode()
	_setup_noise()
	weather = preload("res://scripts/weather.gd").new()
	weather.main = self
	add_child(weather)
	_make_environment()
	_make_terrain()
	_make_water()
	_scatter_all()
	grass_mesh_vars = [pv.tuft(1500), pv.tuft(1503, 1.3), pv.tuft(1504, 0.8)]
	hero = preload("res://scripts/hero.gd").new()
	hero.main = self
	add_child(hero)
	feet = preload("res://scripts/footprints.gd").new()
	feet.main = self
	add_child(feet)
	hero.position = _find_start()
	# бобры: плотины, пруды и хатки (до зверей — бобров селят у хаток)
	beavers = preload("res://scripts/beavers.gd").new()
	beavers.main = self
	add_child(beavers)
	beavers.setup(hero.position)
	animals = preload("res://scripts/animals.gd").new()
	animals.main = self
	add_child(animals)
	animals.populate()
	sfx = preload("res://scripts/sfx.gd").new()
	sfx.main = self
	add_child(sfx)
	tools_world = preload("res://scripts/world_tools.gd").new()
	tools_world.main = self
	add_child(tools_world)
	# с собой только кремнёвый нож на поясе
	inv["knife"] = 1
	hero.tools.to_belt("knife")
	# --- colony: в режиме острога — изометрическая камера (rts_camera.gd) вместо
	# привязанной к герою; поля те же, поэтому старый код работает по-прежнему ---
	if colony_mode:
		rig = preload("res://scripts/rts_camera.gd").new()
		rig.main = self
		add_child(rig)
		rig.snap_to(hero.position, 30.0, 0.6)
		player_rig = rig
		hero.visible = false
		hero.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		rig = preload("res://scripts/camera_rig.gd").new()
		rig.target = hero
		add_child(rig)
		rig.position = hero.position
		player_rig = hero
	# --- /colony ---
	var ui := CanvasLayer.new()
	add_child(ui)
	if not colony_mode:
		hud = preload("res://scripts/hud.gd").new()
		hud.anchor_right = 1.0
		hud.anchor_bottom = 1.0
		ui.add_child(hud)
		joy = preload("res://scripts/joystick.gd").new()
		joy.anchor_top = 1.0
		joy.anchor_bottom = 1.0
		joy.offset_left = 40.0
		joy.offset_right = 400.0
		joy.offset_top = -400.0
		joy.offset_bottom = -40.0
		ui.add_child(joy)
	act_btn = Button.new()
	act_btn.anchor_left = 1.0
	act_btn.anchor_right = 1.0
	act_btn.anchor_top = 1.0
	act_btn.anchor_bottom = 1.0
	act_btn.offset_left = -330.0
	act_btn.offset_right = -60.0
	act_btn.offset_top = -230.0
	act_btn.offset_bottom = -90.0
	act_btn.add_theme_font_size_override("font_size", 40)
	act_btn.focus_mode = Control.FOCUS_NONE
	act_btn.visible = false
	act_btn.pressed.connect(func(): hero.do_action())
	ui.add_child(act_btn)
	if colony_mode:
		act_btn.visible = false
	else:
		# --- инвентарь (короб): кнопка «Рюкзак» на HUD, лист вещей, анимация снятия короба ---
		inventory = preload("res://scripts/inventory.gd").new()
		inventory.main = self
		ui.add_child(inventory)
		hud.setup(self)
	# --- hunt: разделка туш, кровь, запах крови (hunt.gd) ---
	hunt = preload("res://scripts/hunt.gd").new()
	hunt.main = self
	add_child(hunt)
	hunt.setup()
	# --- /hunt ---
	# --- combat: удары, прицел броска и лука, стрелы в звере (combat.gd) ---
	combat = preload("res://scripts/combat.gd").new()
	combat.main = self
	add_child(combat)
	combat.setup(ui)
	# --- /combat ---
	# --- build: лагерь, постройки, стройка (structures.gd + build_mode/cabin/camp_ui) ---
	camp = preload("res://scripts/structures.gd").new()
	camp.main = self
	add_child(camp)
	# --- /build ---
	# --- colony: лист лагеря (camp_ui) заменён листом острога ---
	if colony_mode and camp.ui != null:
		camp.ui.visible = false
		camp.ui.set_process(false)
		camp.ui.set_process_unhandled_input(false)
	# --- /colony ---
	fps_lbl = Label.new()
	fps_lbl.anchor_left = 0.5
	fps_lbl.anchor_right = 0.5
	fps_lbl.offset_left = -300.0
	fps_lbl.offset_right = 300.0
	fps_lbl.offset_top = 14.0
	fps_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fps_lbl.add_theme_font_size_override("font_size", 24)
	fps_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	fps_lbl.add_theme_constant_override("outline_size", 6)
	fps_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(fps_lbl)
	flash = ColorRect.new()
	flash.anchor_right = 1.0
	flash.anchor_bottom = 1.0
	flash.color = Color(0.6, 0.0, 0.0, 0.0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(flash)
	dead_lbl = Label.new()
	dead_lbl.anchor_right = 1.0
	dead_lbl.anchor_bottom = 1.0
	dead_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dead_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dead_lbl.add_theme_font_size_override("font_size", 64)
	dead_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	dead_lbl.add_theme_constant_override("outline_size", 10)
	dead_lbl.visible = false
	ui.add_child(dead_lbl)
	_update_sky()
	# --- core: настройки (качество, кадры, звук), сохранение, справочник, меню ---
	_core_setup(ui)
	# --- /core ---
	# --- colony: отряд, лист острога и сценарий «Первая зима» ---
	if colony_mode:
		fps_lbl.offset_top = 120.0
		fps_lbl.visible = false
		var cl := CanvasLayer.new()
		cl.layer = 3
		add_child(cl)
		colony = preload("res://scripts/colony.gd").new()
		colony.rig = rig
		add_child(colony)
		colony.setup(self, cl)
		rig.colony = colony
		if OS.get_environment("COLONY_TEST") != "" or OS.get_environment("COLONY_SHOTS") != "":
			var ct: Node = preload("res://scripts/colony_test.gd").new()
			ct.set("main", self)
			add_child(ct)
	var _hx := OS.get_environment("CHIDE")
	if "s" in _hx:
		sun.shadow_enabled = false
	if "f" in _hx:
		env.fog_enabled = false
		env.volumetric_fog_enabled = false
	if "g" in _hx:
		for k in grass_cells:
			grass_cells[k].visible = false
	if "c" in _hx:
		for m in cliff_mmi:
			m.visible = false
	if "a" in _hx:
		animals.visible = false
	# --- /colony ---
	_update_near(true)
	_grass_prebuild(player_rig.position)
	# --- perf: PERF=1 — замер нагрузки без экрана (perf.gd) ---
	if OS.get_environment("PERF") != "":
		var pf: Node = preload("res://scripts/perf.gd").new()
		pf.set("main", self)
		add_child(pf)

## --- colony: какой режим запускать. Старые проверки (бой, инструменты, охота, стройка,
## сохранение, кадры, замер) идут по-прежнему от героя, поэтому для них — режим героя. ---
func _colony_pick_mode() -> void:
	colony_mode = true
	var cf := ConfigFile.new()
	if cf.load("user://settings.cfg") == OK:
		colony_mode = not bool(cf.get_value("game", "hero_mode", false))
	for e: String in ["COMBAT_TEST", "TOOLS_TEST", "HUNT_TEST", "BUILD_TEST", "SAVE_TEST", "UI_SHOTS", "SHOTS", "PERF", "HERO_MODE"]:
		if OS.get_environment(e) != "":
			colony_mode = false
	for e2: String in ["COLONY_TEST", "COLONY_SHOTS"]:
		if OS.get_environment(e2) != "":
			colony_mode = true

func _find_start() -> Vector3:
	for r in range(0, 120, 3):
		for k in 16:
			var a := TAU * k / 16.0
			var x := cos(a) * r
			var z := sin(a) * r
			var y := height(x, z)
			if y > WATER_Y + 0.8 and normal_at(x, z).y > 0.93 and not blocked(x, z, 1.5):
				return Vector3(x, y, z)
	return Vector3(0, height(0, 0), 0)

func _add_blocker(x: float, z: float, r: float) -> void:
	var k := Vector2i(floori(x / 8.0), floori(z / 8.0))
	if not blockers.has(k):
		blockers[k] = []
	blockers[k].append(Vector3(x, z, r))

## Твёрдые тела, на которые можно встать: [вид, a, b, радиус, высота].
## 0 — купол камня (a — центр основания), 1 — бревно (ось a→b), 2 — пень-цилиндр.
var solids := {}

func _add_solid(sd: Array) -> void:
	var a: Vector3 = sd[1]
	var c := a
	var ext: float = sd[3] + 0.5
	if sd[0] == 1:
		var bb: Vector3 = sd[2]
		c = (a + bb) * 0.5
		ext += a.distance_to(bb) * 0.5
	for gx in range(floori((c.x - ext) / 8.0), floori((c.x + ext) / 8.0) + 1):
		for gz in range(floori((c.z - ext) / 8.0), floori((c.z + ext) / 8.0) + 1):
			var k := Vector2i(gx, gz)
			if not solids.has(k):
				solids[k] = []
			solids[k].append(sd)

## Верх твёрдого тела в точке (или -1e9, если его нет).
func solid_top(x: float, z: float) -> float:
	var k := Vector2i(floori(x / 8.0), floori(z / 8.0))
	if not solids.has(k):
		return -1e9
	var best := -1e9
	for sd in solids[k]:
		var a: Vector3 = sd[1]
		var r: float = sd[3]
		match int(sd[0]):
			0:
				var d := Vector2(x - a.x, z - a.z).length()
				if d < r:
					best = maxf(best, a.y + float(sd[4]) * sqrt(1.0 - (d / r) * (d / r)))
			1:
				var bb: Vector3 = sd[2]
				var ab := Vector2(bb.x - a.x, bb.z - a.z)
				var t := clampf(Vector2(x - a.x, z - a.z).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
				var cp := a.lerp(bb, t)
				var d := Vector2(x - cp.x, z - cp.z).length()
				if d < r:
					best = maxf(best, cp.y + sqrt(r * r - d * d))
			2:
				if Vector2(x - a.x, z - a.z).length() < r:
					best = maxf(best, a.y + float(sd[4]))
	return best

## Высота опоры: земля или камень/бревно/пень сверху.
func ground_at(x: float, z: float) -> float:
	return maxf(height(x, z), solid_top(x, z))

## perf: опора по сетке рельефа (для зверей — в разы быстрее ground_at, совпадает с видимой землёй).
func ground_fast(x: float, z: float) -> float:
	return maxf(grid_height(x, z), solid_top(x, z))

func ground_normal(x: float, z: float) -> Vector3:
	var e := 0.3
	return Vector3(ground_at(x - e, z) - ground_at(x + e, z), 2.0 * e, ground_at(x, z - e) - ground_at(x, z + e)).normalized()

func _add_seat(p: Vector3, yaw: float) -> void:
	var k := Vector2i(floori(p.x / 8.0), floori(p.z / 8.0))
	if not seats.has(k):
		seats[k] = []
	seats[k].append([p, yaw])

## Ближайшее место, где можно сесть (в радиусе 1,5 м): [точка сиденья, поворот] или [].
func find_seat(p: Vector3) -> Array:
	var c := Vector2i(floori(p.x / 8.0), floori(p.z / 8.0))
	var best: Array = []
	var bd := 1.5 * 1.5
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var k := Vector2i(c.x + dx, c.y + dz)
			if not seats.has(k):
				continue
			for s in seats[k]:
				var sp: Vector3 = s[0]
				var dd := Vector2(sp.x - p.x, sp.z - p.z).length_squared()
				if dd < bd:
					bd = dd
					best = s
	return best

func blocked(x: float, z: float, rad: float) -> bool:
	var c := Vector2i(floori(x / 8.0), floori(z / 8.0))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var k := Vector2i(c.x + dx, c.y + dz)
			if not blockers.has(k):
				continue
			for b in blockers[k]:
				var ddx: float = b.x - x
				var ddz: float = b.y - z
				var rr: float = b.z + rad
				if ddx * ddx + ddz * ddz < rr * rr:
					return true
	return false

func _setup_noise() -> void:
	n_hill.seed = 1640; n_hill.frequency = 0.004; n_hill.fractal_octaves = 4
	n_cliff.seed = 77; n_cliff.frequency = 0.0045; n_cliff.fractal_octaves = 2
	n_detail.seed = 5; n_detail.frequency = 0.05; n_detail.fractal_octaves = 3
	n_crag.seed = 31; n_crag.frequency = 0.16; n_crag.fractal_octaves = 4
	n_crag2.seed = 32; n_crag2.frequency = 0.55; n_crag2.fractal_octaves = 2
	n_biome.seed = 4242; n_biome.frequency = 0.0042; n_biome.fractal_octaves = 2
	n_forest.seed = 909; n_forest.frequency = 0.02; n_forest.fractal_octaves = 3
	n_zone.seed = 2024; n_zone.noise_type = FastNoiseLite.TYPE_CELLULAR; n_zone.frequency = 0.018
	n_zone.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE; n_zone.fractal_type = FastNoiseLite.FRACTAL_NONE
	n_open.seed = 313; n_open.frequency = 0.0055; n_open.fractal_octaves = 2
	n_wet.seed = 777; n_wet.frequency = 0.007; n_wet.fractal_octaves = 3
	n_glade.seed = 555; n_glade.frequency = 0.011; n_glade.fractal_octaves = 2

## Уровень воды в точке: у бобровых плотин выше (пруд) или ниже (после плотины).
func water_level(x: float, z: float) -> float:
	return WATER_Y + (beavers.level_off(x, z) if beavers != null else 0.0)

## Расстояние до русла по нормали к оси (на крутой излучине река не сужается).
func river_dist(x: float, z: float) -> float:
	var d: float = RP.dzc(x)
	return absf(z - RP.zc(x)) / sqrt(1.0 + d * d)

## 1 в центре озера, плавно к 0 у берега.
func lake_k(x: float, z: float) -> float:
	var k := 0.0
	for l in LAKES:
		var d := Vector2(x - float(l[0]), z - float(l[1])).length()
		var r: float = float(l[2]) * (1.0 + n_detail.get_noise_2d(x * 0.6 + float(l[0]), z * 0.6) * 0.35)
		k = maxf(k, 1.0 - smoothstep(r * 0.55, r, d))
	return k

## Болотистость низины (0..1): плоская мочажинная равнина с озерками.
func wet_k(x: float, z: float, h: float) -> float:
	return clampf((WATER_Y + 4.0 - h) / 3.0, 0.0, 1.0) * smoothstep(-0.08, 0.3, n_wet.get_noise_2d(x, z))

## Особые участки леса (ячейки ~90 м): 0 обычный, 1 гарь, 2 болото, 3 курумник, 4 бурелом.
func zone(x: float, z: float) -> int:
	var jx := x + n_detail.get_noise_2d(x * 0.7, z * 0.7) * 9.0
	var jz := z + n_detail.get_noise_2d(z * 0.7 + 50.0, x * 0.7) * 9.0
	var v := n_zone.get_noise_2d(jx, jz)
	var y := height(x, z)
	# зоны редкие и небольшие: ~1/3 прежней площади
	if v < -0.86:
		return 1
	if (v < -0.7 and y < WATER_Y + 4.0) or (y > WATER_Y + 0.1 and y < WATER_Y + 3.0 and wet_k(x, z, y) > 0.3):
		return 2
	# каменистые склоны и курумники: в скалистой части карты крупными пятнами
	if v > 0.88 or (v > 0.76 and biome(x, z) > 0.2) or (biome(x, z) > 0.42 and n_detail.get_noise_2d(x * 0.3, z * 0.3) > 0.1):
		return 3
	if v > 0.2 and v < 0.3:
		return 4
	return 0

func biome(x: float, z: float) -> float:
	return clampf(n_biome.get_noise_2d(x, z) * 2.2, -1.0, 1.0)

## Рельеф: пологие холмы и редкие отвесные скальные уступы 5–20 м.
## Уступ — уровень шума n_cliff; линия рвётся мелким шумом, поэтому край неровный.
func cliff_k(x: float, z: float) -> float:
	var c := n_cliff.get_noise_2d(x, z) + n_crag.get_noise_2d(x * 0.35, z * 0.35) * 0.03 + n_crag2.get_noise_2d(x, z) * 0.004
	var sharp := smoothstep(0.34, 0.355, c)
	# с части сторон уступ переходит в пологий подъём — наверх можно зайти
	var soft := smoothstep(0.16, 0.36, c)
	var g := smoothstep(-0.15, 0.15, n_biome.get_noise_2d(x * 2.3 - 500.0, z * 2.3))
	return lerpf(soft, sharp, g)

func cliff_h(x: float, z: float) -> float:
	return 5.0 + 15.0 * clampf(n_biome.get_noise_2d(x * 0.7 + 300.0, z * 0.7) * 1.4 + 0.5, 0.0, 1.0)

func height(x: float, z: float) -> float:
	var rocky := clampf(biome(x, z), 0.0, 1.0)
	var h := n_hill.get_noise_2d(x, z) * (3.0 + rocky * 2.0) + n_detail.get_noise_2d(x, z) * 0.35 + 2.5
	h += cliff_k(x, z) * cliff_h(x, z)
	h = maxf(h, WATER_Y + 0.6 + n_detail.get_noise_2d(x * 0.5, z * 0.5) * 0.3)
	# болотистая низина: ровная мочажина чуть выше воды, в ней озерки-окна
	var wk := wet_k(x, z, h)
	if wk > 0.0:
		h = lerpf(h, WATER_Y + 0.5 + n_detail.get_noise_2d(x * 0.8, z * 0.8) * 0.12, wk * 0.85)
		h = lerpf(h, WATER_Y - 0.9, smoothstep(0.5, 0.62, n_detail.get_noise_2d(x * 0.25 + 90.0, z * 0.25)) * wk)
	h = lerpf(h, WATER_Y - 2.2, lake_k(x, z))
	var r := 1.0 - smoothstep(7.0, 26.0, river_dist(x, z))
	return lerpf(h, WATER_Y - 2.5, r)

func normal_at(x: float, z: float) -> Vector3:
	var e := 1.0
	return Vector3(height(x - e, z) - height(x + e, z), 2.0 * e, height(x, z - e) - height(x, z + e)).normalized()

func forest_density(x: float, z: float) -> float:
	var b := biome(x, z)
	var d := n_forest.get_noise_2d(x, z) * 1.6 + 0.55
	if b > 0.0:
		d -= b * 0.75
	else:
		d += b * 0.5
	# густая тайга ↔ редколесье: широкое пятно открытости; поляны — округлые просветы
	d += n_open.get_noise_2d(x, z) * 0.55
	d *= 1.0 - smoothstep(0.5, 0.62, n_glade.get_noise_2d(x, z)) * 0.92
	return clampf(d, 0.0, 1.0)

var sky_mat: ProceduralSkyMaterial
var env: Environment
var sun: DirectionalLight3D
var moon: DirectionalLight3D

func _make_environment() -> void:
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 25.0
	sky_mat.sun_curve = 0.08
	var sky := Sky.new()
	sky.sky_material = sky_mat
	# небо меняется медленно: радиансу не нужно перерисовываться каждый кадр
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env = Environment.new()
	# трава вокруг героя (клетки 3×3 по 32 м) вырастает между 20 и 32 м
	pv.mats["tuft"].set_shader_parameter("grass_r", 34.0)
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# рассеянный свет — цвет неба, считаем сами (дешевле, чем свёртка неба на телефоне)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.1
	env.tonemap_white = 1.6
	env.fog_enabled = true
	env.fog_density = 1.0
	# дымка по глубине: дальний лес растворяется раньше, чем кончается дальность видимости
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 45.0
	env.fog_depth_end = 115.0
	env.fog_depth_curve = 1.6
	env.fog_sky_affect = 0.55
	env.fog_sun_scatter = 0.25
	# лёгкое свечение светлых мест (солнце в каплях, снег, закат)
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_strength = 0.9
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.05
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 0.0)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 0.6)
	env.set_glow_level(4, 0.3)
	env.adjustment_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 32.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.shadow_blur = 1.5
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.66, 0.95)
	moon.rotation_degrees = Vector3(-48, 200, 0)
	add_child(moon)
	_update_sky()

## Время суток и года: солнце, луна, цвета неба, рассеянный свет, дымка, туман в низинах,
## цветокоррекция по сезону и погоде, свет факела у героя.
func _update_sky() -> void:
	var e := sin((t_hours / 24.0) * TAU - PI * 0.5)
	var d := smoothstep(-0.05, 0.25, e)
	var dusk := clampf(1.0 - absf(e) * 4.0, 0.0, 1.0)
	var lowsun := 1.0 - smoothstep(0.02, 0.45, e)
	var cl: float = weather.cloud if weather != null else 0.0
	var wet_air: float = weather.precip if weather != null else 0.0
	var fogv: float = weather.fogv if weather != null else 0.0
	var mist: float = weather.mist if weather != null else 0.0
	# сезон: 0 осень, 1 зима, 2 весна, 3 лето; летом солнце выше и теплее, зимой низкое и бледное
	var yp: float = weather.year_pos() if weather != null else 0.0
	var summer := clampf(cos((yp - 0.875) * TAU) * 0.5 + 0.5, 0.0, 1.0)
	var winter := clampf(cos((yp - 0.375) * TAU) * 0.5 + 0.5, 0.0, 1.0)
	var autumn: float = weather.autumn * (1.0 - winter) if weather != null else 0.0
	var max_elev := lerpf(34.0, 64.0, summer)
	var elev := clampf(e, 0.0, 1.0) * max_elev + 5.0
	sun.rotation_degrees = Vector3(-elev, 40.0 + (t_hours - 12.0) * 15.0, 0)
	sun.light_energy = 1.55 * smoothstep(-0.03, 0.2, e) * (1.0 - cl * 0.7) * (1.0 - fogv * 0.3)
	var noon := Color(1.0, 0.95, 0.86).lerp(Color(0.95, 0.96, 1.0), winter * 0.6)
	sun.light_color = Color(1.0, 0.52, 0.27).lerp(Color(1.0, 0.76, 0.52), smoothstep(0.0, 0.2, e)).lerp(noon, smoothstep(0.18, 0.5, e))
	sun.visible = e > -0.02
	# в пасмурную погоду тени мягкие и бледные
	sun.shadow_opacity = clampf(1.0 - cl * 0.55 - fogv * 0.3, 0.3, 1.0)
	moon.light_energy = 0.32 * (1.0 - d) * (1.0 - cl * 0.6)
	moon.visible = d < 0.98
	var day_top := Color(0.40, 0.56, 0.74).lerp(Color(0.52, 0.6, 0.7), winter * 0.5)
	var day_hor := Color(0.74, 0.79, 0.8)
	var night_top := Color(0.012, 0.022, 0.055)
	var night_hor := Color(0.04, 0.06, 0.11)
	var top := night_top.lerp(day_top, d).lerp(Color(0.28, 0.3, 0.46), dusk * 0.55)
	var hor := night_hor.lerp(day_hor, d).lerp(Color(0.95, 0.56, 0.32), dusk * 0.75)
	var grey := Color(0.5, 0.53, 0.56) * (0.12 + d * 0.88)
	top = top.lerp(grey, cl * 0.8)
	hor = hor.lerp(grey.lightened(0.15), cl * 0.6)
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = hor
	sky_mat.ground_horizon_color = hor.darkened(0.15)
	sky_mat.ground_bottom_color = hor.darkened(0.6)
	sky_mat.sun_angle_max = lerpf(25.0, 8.0, cl)
	# дымка: тёплая к закату, сизая днём, тёмно-синяя ночью; в дождь и туман светлее и серее
	var haze := hor.lerp(top, 0.25).darkened(0.05)
	haze = haze.lerp(Color(0.62, 0.65, 0.67) * (0.15 + d * 0.85), maxf(fogv, wet_air) * 0.5)
	env.fog_light_color = haze
	env.fog_sun_scatter = 0.3 * d * (1.0 - cl) + dusk * 0.2
	# рассеянный свет: днём от неба (голубой сверху + зелёный отсвет леса), ночью — лунный сизый
	var amb_day := top.lerp(hor, 0.45).lerp(Color(0.5, 0.58, 0.42), 0.18)
	var amb_night := Color(0.16, 0.2, 0.34)
	env.ambient_light_color = amb_night.lerp(amb_day, d)
	env.ambient_light_energy = lerpf(0.7, 1.6, d) * (1.0 + cl * 0.2)
	# цветокоррекция: осень теплее и насыщеннее, зима и дождь — приглушённее, ночь — бледнее
	env.adjustment_saturation = clampf(0.96 + autumn * 0.02 + summer * 0.03 - winter * 0.12 - wet_air * 0.14 - fogv * 0.1 - (1.0 - d) * 0.2, 0.6, 1.2)
	env.adjustment_contrast = 1.04 + lowsun * d * 0.04 - fogv * 0.05
	env.adjustment_brightness = 1.0 + (1.0 - d) * 0.06
	env.glow_intensity = 0.25 + dusk * 0.25 + winter * 0.1
	if weather != null:
		# глубинная дымка: в тумане и дождь начинается ближе и гуще
		# камера ниже — видно дальше: дымка ближе, чтобы дальний край мира не появлялся на глазах
		var low: float = clampf((45.0 - float(rig.pitch)) / 20.0, 0.0, 1.0) if rig != null else 0.0
		env.fog_depth_begin = 45.0 - low * 17.0 - fogv * 36.0 - wet_air * 14.0 - mist * 8.0
		env.fog_depth_end = 100.0 - low * 18.0 - fogv * 62.0 - wet_air * 24.0
		# туман в низинах: высотная дымка над рекой и в лощинах (утром и после дождя)
		env.fog_height = WATER_Y + 1.6 + mist * 1.6
		env.fog_height_density = mist * 0.22
	if hero != null:
		hero.torch.light_energy = 2.2 * (1.0 - d) * (1.6 if lamp_lit else 1.0)  # core: жирник
		hero.torch.omni_range = 17.0 if lamp_lit else 11.0
	# --- colony: на отъезде дымка отступает — видна вся долина ---
	if colony != null:
		colony.fog_adjust()
	# --- /colony ---
	day_factor = d

var hmap_tex: ImageTexture
var terrain_hs := PackedFloat32Array()
var terrain_cols := PackedColorArray()

func _make_terrain() -> void:
	var n := SEG + 1
	var step := SIZE / SEG
	var half := SIZE * 0.5
	var verts := PackedVector3Array(); verts.resize(n * n)
	var norms := PackedVector3Array(); norms.resize(n * n)
	var cols := PackedColorArray(); cols.resize(n * n)
	var hs := PackedFloat32Array(); hs.resize(n * n)
	var zuv := PackedVector2Array(); zuv.resize(n * n)
	var zuv2 := PackedVector2Array(); zuv2.resize(n * n)
	for iz in n:
		for ix in n:
			hs[iz * n + ix] = height(ix * step - half, iz * step - half)
	for iz in n:
		for ix in n:
			var x := ix * step - half
			var z := iz * step - half
			var i := iz * n + ix
			var y := hs[i]
			verts[i] = Vector3(x, y, z)
			var hl := hs[iz * n + maxi(ix - 1, 0)]
			var hr := hs[iz * n + mini(ix + 1, n - 1)]
			var hd := hs[maxi(iz - 1, 0) * n + ix]
			var hu := hs[mini(iz + 1, n - 1) * n + ix]
			norms[i] = Vector3(hl - hr, 2.0 * step, hd - hu).normalized()
			var fd := forest_density(x, z)
			var grass := clampf(1.0 - fd * 1.4, 0.0, 1.0)
			grass *= 1.0 - smoothstep(0.08, 0.22, 1.0 - norms[i].y)
			var mud := clampf((WATER_Y + 1.2 - y) / 1.5, 0.0, 1.0)
			var leaves := clampf(n_detail.get_noise_2d(x * 2.0, z * 2.0) * 0.8 + fd * 0.5, 0.0, 1.0)
			cols[i] = Color(fd, mud, leaves)
			var zn := zone(x, z)
			zuv[i] = Vector2(1.0 if zn == 1 else 0.0, 1.0 if zn == 2 else 0.0)
			zuv2[i] = Vector2(1.0 if zn == 3 else 0.0, 1.0 if zn == 4 else 0.0)
	var himg := Image.create_from_data(n, n, false, Image.FORMAT_RF, hs.to_byte_array())
	hmap_tex = ImageTexture.create_from_image(himg)
	var zb := PackedByteArray(); zb.resize(n * n * 4)
	for i in n * n:
		zb[i * 4] = int(zuv[i].x * 255.0); zb[i * 4 + 1] = int(zuv[i].y * 255.0)
		zb[i * 4 + 2] = int(zuv2[i].x * 255.0); zb[i * 4 + 3] = int(zuv2[i].y * 255.0)
	var zone_tex := ImageTexture.create_from_image(Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, zb))
	terrain_hs = hs
	terrain_cols = cols
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/paint/ground.gdshader")
	mat.set_shader_parameter("water_y", WATER_Y)
	mat.set_shader_parameter("zone_tex", zone_tex)
	terrain_mat = mat
	# земля кусками 32×32 клетки: камера отсекает невидимые куски
	var CH := 32
	for cz in SEG / CH:
		for cx in SEG / CH:
			var m := CH + 1
			var v2 := PackedVector3Array(); v2.resize(m * m)
			var n2 := PackedVector3Array(); n2.resize(m * m)
			var c2 := PackedColorArray(); c2.resize(m * m)
			var u2 := PackedVector2Array(); u2.resize(m * m)
			var u3 := PackedVector2Array(); u3.resize(m * m)
			for jz in m:
				for jx in m:
					var i := (cz * CH + jz) * n + cx * CH + jx
					u2[jz * m + jx] = zuv[i]
					u3[jz * m + jx] = zuv2[i]
					v2[jz * m + jx] = verts[i]
					n2[jz * m + jx] = norms[i]
					c2[jz * m + jx] = cols[i]
			var idx := PackedInt32Array()
			for iz in CH:
				for ix in CH:
					var a := iz * m + ix
					idx.append_array([a, a + 1, a + m, a + 1, a + m + 1, a + m])
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = v2
			arr[Mesh.ARRAY_NORMAL] = n2
			arr[Mesh.ARRAY_COLOR] = c2
			arr[Mesh.ARRAY_INDEX] = idx
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			mesh.surface_set_material(0, mat)
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.extra_cull_margin = 2.0  # снег поднимает поверхность в шейдере
			add_child(mi)

func _make_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(SIZE, SIZE)
	plane.subdivide_width = 2
	plane.subdivide_depth = 2
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/paint/water.gdshader")
	mat.set_shader_parameter("hmap", hmap_tex)
	mat.set_shader_parameter("zone_tex", terrain_mat.get_shader_parameter("zone_tex"))
	mat.set_shader_parameter("hsize", SIZE)
	plane.material = mat
	water_mat = mat
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.position.y = WATER_Y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

# ---------- растительность ----------

var veg = preload("res://scripts/veg.gd").new()
var pv = preload("res://scripts/pveg.gd").new()
var player_rig: Node3D
var grass_mesh_vars: Array = []
var grass_cells := {}
var grass_timer := 0.0
var _sky_timer := 0.0
## Трава клетками 32 м вокруг героя (3×3): меньше вызовов отрисовки, чем 5×5 клеток по 16 м;
## клетка строится по частям за несколько кадров, без рывка.
const GCELL := 32.0
const GRADIUS := 2
var _gb := {}

var _shot_n := 0
## Режим кадров для проверки в облаке: SHOTS=папка — снять несколько ракурсов и выйти.
var _shot_kinds: Array = []

func _shots() -> void:
	_shot_n += 1
	var dir := OS.get_environment("SHOTS")
	var plan := [[20, 0.6, 7.5], [40, 0.0, 12.0], [60, 2.2, 12.0], [80, 4.0, 16.0]]
	if _shot_n == 2:
		# крупный план: по одному зверю каждого вида с готовой моделью рядом с героем
		var k := 0
		for a in animals.list:
			if a.kind in ["roe", "deer", "wolf", "fox"] and k < 4 and not (a.kind in _shot_kinds):
				_shot_kinds.append(a.kind)
				var ang := 0.6 + k * 0.9
				a.position = hero.position + Vector3(cos(ang), 0, sin(ang)) * (3.0 + k * 1.2)
				a.home = a.position
				a.state = "graze" if k % 2 == 0 else "wander"
				a.position.y = ground_at(a.position.x, a.position.z)
				a.rotation.y = ang + PI * 0.5
				a.visible = true
				if a.parts.has("ap"):
					a.parts["ap"].active = true
					a.speed = 0.0
					a._animate_model(0.016)
				k += 1
		# звери замирают на месте, чтобы попасть в кадр (анимации идут)
		animals.set_process(false)
	for p in plan:
		if _shot_n == p[0] - 12:
			rig.rotation.y = p[1]
			rig.distance = p[2]
		if _shot_n == p[0]:
			get_viewport().get_texture().get_image().save_png(dir + "/game_%d.png" % p[0])
			print("shot game ", p[0], " tris ", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), " draws ", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	# замер: сколько треугольников дают звери и птицы
	if _shot_n == 81:
		animals.visible = false
	if _shot_n == 83:
		print("shot no-animals tris ", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		hero.visible = false
	if _shot_n == 85:
		print("shot no-hero tris ", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		for k in grass_cells:
			grass_cells[k].visible = false
		for m in cliff_mmi:
			m.visible = false
	if _shot_n == 87:
		print("shot no-cliff-no-grass tris ", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		sun.shadow_enabled = false
	if _shot_n == 89:
		print("shot no-shadow tris ", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	if _shot_n > 90:
		get_tree().quit()

var _dbgf := 0
func _process(delta: float) -> void:
	_dbgf += 1
	if hero == null or (joy == null and colony == null):
		return
	if OS.get_environment("SHOTS") != "":
		_shots()
	# --- colony: далёкая камера — растворение растений считаем от середины взгляда,
	# а не от камеры: иначе на отъезде пропала бы вся долина ---
	var hp: Vector3 = hero.position + Vector3(0, 1.0, 0)
	var cp: Vector3 = rig.cam.global_position
	if colony != null:
		hp = Vector3(0, -1000.0, 0)
		cp = colony.veg_focus()
	# --- /colony ---
	for m in veg.fade_list:
		m.set_shader_parameter("hero_pos", hp)
		m.set_shader_parameter("cam_pos", cp)
	for m in pv.fade_list:
		m.set_shader_parameter("hero_pos", hp)
		m.set_shader_parameter("cam_pos", cp)
	pv.mats["tuft"].set_shader_parameter("hero_pos", hp)
	pv.mats["tuft"].set_shader_parameter("cam_pos", cp)
	pv.mats["tuft"].set_shader_parameter("grass_now", Time.get_ticks_msec() * 0.001)
	water_mat.set_shader_parameter("hero_pos", hero.position)
	water_mat.set_shader_parameter("swim", hero.swimb if colony == null else 0.0)
	water_mat.set_shader_parameter("swim_move", clampf(hero.run_mag, 0.0, 1.0))
	_fps_t -= delta
	if _fps_t <= 0.0:
		_fps_t = 0.5
		fps_lbl.text = "FPS %d · вызовов %d · треуг. %.1f тыс." % [Engine.get_frames_per_second(), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0]
	flash.color.a = maxf(0.0, flash.color.a - delta * 0.6)
	if dead_t > 0.0:
		dead_t -= delta
		if dead_t <= 0.0:
			_respawn()
	_near_t -= delta
	if _near_t <= 0.0:
		_near_t = 0.25
		_update_near()
	if joy != null:
		hero.move_vec = joy.value if health > 0.0 else Vector2.ZERO
		hero.cam_yaw = rig.rotation.y
	# время суток: 1 игровой час за 75 секунд
	t_hours += delta / 75.0
	weather.step(delta / 75.0)
	weather.update_visual(rig.position)
	if t_hours >= 24.0:
		t_hours -= 24.0
		day_count += 1
	_sky_timer -= delta
	if _sky_timer <= 0.0:
		_sky_timer = 0.25
		_update_sky()
		_update_stats(0.25)
		_core_tick(0.25)  # core
		weather.apply(veg.fade_list + pv.fade_list, terrain_mat, pv.mats["tuft"], water_mat)
		if joy != null:
			var lbl: String = hero.action_label()
			act_btn.visible = lbl != ""
			act_btn.text = lbl
	if player_rig == null:
		return
	# недостроенная клетка травы: следующая полоса за кадр
	if not _gb.is_empty():
		_grass_step()
		return
	grass_timer -= delta
	if grass_timer > 0.0:
		return
	grass_timer = 0.1
	var c := Vector2i(floori((player_rig.position.x + SIZE * 0.5) / GCELL), floori((player_rig.position.z + SIZE * 0.5) / GCELL))
	# удалить далёкие клетки
	for k in grass_cells.keys():
		if absi(k.x - c.x) > GRADIUS + 1 or absi(k.y - c.y) > GRADIUS + 1:
			grass_cells[k].queue_free()
			grass_cells.erase(k)
	# построить одну недостающую клетку за раз: ближайшую, а из равных — ту, что впереди по
	# взгляду камеры и по ходу героя (туда, куда смотрим, трава должна быть готова заранее)
	var fwd := Vector2(-sin(rig.rotation.y), -cos(rig.rotation.y))
	var hv: Vector3 = hero.vel
	var mv := Vector2(hv.x, hv.z)
	if mv.length() > 0.5:
		fwd = (fwd + mv.normalized() * 1.5).normalized()
	var best := Vector2i.ZERO
	var best_d := 1e9
	for dz in range(-GRADIUS, GRADIUS + 1):
		for dx in range(-GRADIUS, GRADIUS + 1):
			var k := Vector2i(c.x + dx, c.y + dz)
			if grass_cells.has(k) or k.x < 0 or k.y < 0 or k.x >= int(SIZE / GCELL) or k.y >= int(SIZE / GCELL):
				continue
			var d := float(dx * dx + dz * dz) - Vector2(dx, dz).dot(fwd) * 1.2
			if d < best_d:
				best_d = d
				best = k
	if best_d < 1e9:
		_grass_begin(best)

## Проверка сезонов: тап по часам в правом верхнем углу перематывает время на 2 дня вперёд.
func _unhandled_input(e: InputEvent) -> void:
	if colony != null:
		return  # colony: палец разбирают камера и лист острога
	if e is InputEventScreenTouch and e.pressed:
		var vs := get_viewport().get_visible_rect().size
		if e.position.x > vs.x - 520.0 and e.position.y < 90.0:
			weather.fast_forward(48.0)
			get_viewport().set_input_as_handled()

func _update_stats(dt: float) -> void:
	# --- colony: голод, тепло и усталость — у каждого свои (unit.needs_tick) ---
	if colony != null:
		msg_t -= dt
		return
	# --- /colony ---
	hunger = maxf(0.0, hunger - 0.0004 * dt)
	thirst = maxf(0.0, thirst - 0.0007 * dt * (1.5 if hero.running else 1.0))
	var gh := dt / 75.0
	if health > 0.0:
		# кровотечение, голод, жажда, холод — урон; сытый и в тепле — заживает
		health -= bleed * 0.004 * dt
		bleed = maxf(0.0, bleed - 0.0015 * dt)
		if hunger <= 0.0 or thirst <= 0.0:
			health -= 0.0012 * dt
		if warmth < 0.1:
			health -= 0.001 * dt
		if bleed <= 0.01 and hunger > 0.2 and thirst > 0.2:
			health = minf(1.0, health + gh * (0.02 if hero.state != "sit" else 0.035))
		for k in injuries.keys():
			injuries[k] = float(injuries[k]) - gh
			if injuries[k] <= 0.0:
				injuries.erase(k)
		if health <= 0.0:
			health = 0.0
			_die("")
	msg_t -= dt
	var tc: float = weather.temp
	var soak: float = maxf(float(weather.wet) * 0.6, float(hero.soaked))
	var target_w := clampf(0.55 + tc * 0.025 - soak * 0.35 - weather.wind * 0.05 - (0.25 if hero.swimb > 0.5 else 0.0), 0.02, 0.95)
	# --- build: костёр, шалаш, изба с печью греют; укрытие ослабляет ветер ---
	if camp != null:
		target_w = clampf(target_w + camp.warm_bonus() + weather.wind * 0.05 * (1.0 - camp.wind_k()), 0.02, 0.98)
	# --- /build ---
	warmth = lerpf(warmth, target_w, 0.01 * dt * 4.0)
	if hero.moving:
		# шаг почти не утомляет; бег, лазание и плавание — заметно
		var drain := 0.0015
		if hero.running:
			drain = 0.018
		if hero.climbing > 0.5:
			drain = 0.02
		if hero.state == "climb":
			drain = 0.035
		if hero.swimb > 0.5:
			drain = 0.012
		# по колено в снегу или грязи — тяжело, по пояс — очень тяжело
		var sk: float = hero.sink + hero.mud_sink * 1.5
		drain = drain * (1.0 + sk * 3.0) + sk * 0.01
		stamina = maxf(0.0, stamina - drain * dt)
	else:
		stamina = minf(1.0, stamina + (0.14 if hero.state == "sit" else 0.07) * dt)
	var hh := int(t_hours)
	var mm := int((t_hours - hh) * 60.0)
	var temp := int(round(tc))
	var info := ""
	if bleed > 0.02:
		info += "Кровотечение! "
	if not injuries.is_empty():
		info += ", ".join(PackedStringArray(injuries.keys())) + " "
	if msg_t > 0.0:
		info = msg + "   " + info
	hud.set_state([health, hunger, thirst, warmth, stamina], "%s, день %d · %02d:%02d · %d°C · %s" % [weather.season_name(), day_count, hh, mm, temp, weather.kind], info)

## Высота видимой земли: билинейно по сетке рельефа (как её рисует сетка, в десятки раз быстрее height()).
func grid_height(x: float, z: float) -> float:
	var n := SEG + 1
	var fx := clampf((x + SIZE * 0.5) / (SIZE / SEG), 0.0, SEG - 0.001)
	var fz := clampf((z + SIZE * 0.5) / (SIZE / SEG), 0.0, SEG - 0.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * n + ix
	return lerpf(lerpf(terrain_hs[i], terrain_hs[i + 1], tx), lerpf(terrain_hs[i + n], terrain_hs[i + n + 1], tx), tz)

## Трава вокруг точки заранее, пока игрок не видит карту (при старте), без «вырастания» на глазах.
func _grass_prebuild(c: Vector3) -> void:
	var ck := Vector2i(floori((c.x + SIZE * 0.5) / GCELL), floori((c.z + SIZE * 0.5) / GCELL))
	for r in range(0, GRADIUS + 1):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var k := Vector2i(ck.x + dx, ck.y + dz)
				if grass_cells.has(k) or k.x < 0 or k.y < 0 or k.x >= int(SIZE / GCELL) or k.y >= int(SIZE / GCELL):
					continue
				_grass_begin(k)
				while not _gb.is_empty():
					_grass_step()

func _grass_begin(k: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = k.y * 7919 + k.x * 104729 + 13
	var per_var := []
	for v in grass_mesh_vars:
		per_var.append([])
	_gb = {"k": k, "rng": rng, "pv": per_var, "z": 0.0}
	_grass_step()

## Полоса клетки травы глубиной 8 м; после последней — собрать MultiMesh.
func _grass_step() -> void:
	var k: Vector2i = _gb["k"]
	var rng: RandomNumberGenerator = _gb["rng"]
	var per_var: Array = _gb["pv"]
	var x0 := k.x * GCELL - SIZE * 0.5
	var z0 := k.y * GCELL - SIZE * 0.5
	var step := 0.92
	var z: float = _gb["z"]
	var z_end := minf(z + 8.0, GCELL)
	while z < z_end:
		var x := 0.0
		while x < GCELL:
			var px := x0 + x + rng.randf_range(-0.4, 0.4)
			var pz := z0 + z + rng.randf_range(-0.4, 0.4)
			x += step
			# высоты — из сетки рельефа (быстро и ровно по видимой земле), без шума на каждую точку
			var y := grid_height(px, pz)
			if y < water_level(px, pz) + 0.15:
				continue
			if camp != null and camp.cleared(px, pz):  # build: под постройкой травы нет
				continue
			var fd := forest_density(px, pz)
			var h1 := grid_height(px + 1.0, pz)
			var h2 := grid_height(px - 1.0, pz)
			var h3 := grid_height(px, pz + 1.0)
			var h4 := grid_height(px, pz - 1.0)
			var slope := 1.0 - Vector3(h2 - h1, 2.0, h4 - h3).normalized().y
			# сплошной ковёр: на лугу густо, в лесу реже; пятна шума меняют только высоту
			var patch := n_detail.get_noise_2d(px * 3.0, pz * 3.0) + n_forest.get_noise_2d(px * 6.0, pz * 6.0) * 0.5
			if slope > 0.22 or rng.randf() > (1.0 - fd) * 0.75 + 0.25:
				continue
			if maxf(maxf(h1, h2), maxf(h3, h4)) - minf(minf(h1, h2), minf(h3, h4)) > 1.0:
				continue
			var s := rng.randf_range(1.1, 1.6)
			var tall := clampf(0.8 + patch * 0.6, 0.55, 1.4) * rng.randf_range(0.85, 1.15)
			var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * tall, s))
			per_var[rng.randi() % grass_mesh_vars.size()].append(Transform3D(b, Vector3(px, y - 0.03, pz)))
		z += step
	_gb["z"] = z
	if z < GCELL:
		return
	_gb = {}
	var holder := Node3D.new()
	for vi in grass_mesh_vars.size():
		var xs: Array = per_var[vi]
		if xs.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = grass_mesh_vars[vi][0]
		mm.use_custom_data = true
		mm.instance_count = xs.size()
		# время постройки клетки: шейдер по нему плавно выращивает траву
		var born := Color(0.0, 0.0, -100.0, 0.0)  # уже выросла: трава не «вырастает» на глазах
		for i in xs.size():
			mm.set_instance_transform(i, xs[i])
			mm.set_instance_custom_data(i, born)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# клетка видна целиком, пока трава в ней не ушла за grass_r (там шейдер её уже убрал)
		mmi.visibility_range_end = 72.0
		holder.add_child(mmi)
	add_child(holder)
	grass_cells[k] = holder

## Варианты: [mesh, высота]. Несколько вариантов на породу, чтобы лес не повторялся.
func _variants(kind: String) -> Array:
	# ближние модели леса — текстурированные GLB; дальняя версия деревьев (pv.lod) остаётся лёгкой процедурной
	if not pv.lod:
		var glb: Array = pv.model_variants(kind)
		if glb.size() > 0:
			return glb
	var out := []
	match kind:
		"spruce":
			for i in 6: out.append(pv.spruce(100 + i))
		"spruce_dead":
			for i in 2: out.append(pv.dead_tree(200 + i))
		"pine":
			for i in 5: out.append(pv.pine(300 + i))
		"birch":
			for i in 5: out.append(pv.birch(400 + i))
		"bare":
			for i in 2: out.append(pv.dead_tree(500 + i))
			out.append(pv.dead_tree(510))
		"bush":
			for i in 5: out.append(pv.bush(600 + i))
		"larch":
			for i in 5: out.append(pv.birch(1400 + i, "larch"))
		"aspen":
			for i in 5: out.append(pv.birch(1500 + i, "leaf"))
		"berry":
			for i in 3: out.append(pv.berry_bush(1600 + i))
		"mushroom":
			for i in 2: out.append(pv.mushroom(1700 + i, true))
			for i in 3: out.append(pv.mushroom(1710 + i, false))
		"anthill":
			out.append(pv.anthill(1800))
		"fir":
			for i in 5: out.append(pv.spruce(1900 + i, "fir"))
		"cedar":
			for i in 5: out.append(pv.pine(2000 + i, "cedar"))
		"willow":
			for i in 4: out.append(pv.bush(2100 + i, "willow"))
		"juniper":
			for i in 4: out.append(pv.bush(2200 + i, "juniper"))
		"rowan":
			for i in 2: out.append(pv.birch(2300 + i, "rowan"))
		"fern":
			for i in 5: out.append(pv.fern(700 + i))
		"grass":
			for i in 4: out.append(veg.grass(800 + i))
		"rock":
			for i in 8: out.append(pv.rock(900 + i))
		"pebble":
			for i in 3: out.append(pv.rock(950 + i))
		"reeds":
			for i in 3: out.append(pv.reeds(1200 + i))
		"twig":
			for i in 4: out.append(pv.twig(1300 + i))
		"stump":
			out.append(pv.stump(1000))
		"fallen0":
			for i in 3: out.append(pv.fallen(3000 + i, 0))
		"fallen1":
			for i in 3: out.append(pv.fallen(3100 + i, 1))
		"snag":
			for i in 3: out.append(pv.snag(3200 + i, false))
		"snag_b":
			for i in 3: out.append(pv.snag(3300 + i, true))
		"windfall":
			for i in 2: out.append(pv.windfall(3400 + i))
		"rose":
			for i in 3: out.append(pv.shrub(3500 + i, "rose"))
		"alder":
			for i in 5: out.append(pv.shrub(3600 + i, "alder"))
		"cherry":
			for i in 2: out.append(pv.cherry(3700 + i))
		"bilberry":
			for i in 3: out.append(pv.bilberry(3800 + i))
		"hummock":
			for i in 3: out.append(pv.hummock(3900 + i))
		"horsetail":
			for i in 3: out.append(pv.horsetail(4000 + i))
		"fireweed":
			for i in 3: out.append(pv.fireweed(4100 + i))
		"stlanik":
			for i in 3: out.append(pv.stlanik(4200 + i))
		"sedge":
			for i in 2: out.append(pv.tuft(4300 + i, 2.2))
		"slab":
			for i in 4: out.append(pv.rock(4400 + i))
		"mossrock":
			for i in 6: out.append(pv.mossrock(5000 + i))
		"split_rock":
			for i in 2: out.append(pv.split_rock(5100 + i))
		"outcrop":
			for i in 3: out.append(pv.outcrop(5200 + i))
		"scree":
			for i in 3: out.append(pv.scree(5300 + i))
		"stump_rot":
			for i in 4: out.append(pv.stump2(5400 + i, false))
		"stump_mush":
			for i in 4: out.append(pv.stump2(5500 + i, true))
		"fungus_snag":
			for i in 3: out.append(pv.fungus_snag(5600 + i, false))
		"birch_dead":
			for i in 2: out.append(pv.fungus_snag(5700 + i, true))
		"mosslog":
			for i in 5: out.append(pv.mosslog(5800 + i))
		"ledum":
			for i in 2: out.append(pv.low_patch(5900 + i, "ledum", "white", 14, 0.45))
		"cloudberry":
			for i in 2: out.append(pv.low_patch(6000 + i, "bilberry", "orange", 10, 0.15))
		"yagel":
			for i in 5: out.append(pv.low_patch(6100 + i, "yagel", "", 0, 0.12))
		"sphagnum":
			for i in 5: out.append(pv.low_patch(6200 + i, "sphag", "", 0, 0.1))
		"lingon":
			for i in 2: out.append(pv.low_patch(6300 + i, "moss", "berry", 16, 0.12))
		"cranberry":
			for i in 2: out.append(pv.low_patch(6400 + i, "moss", "berry", 12, 0.08))
		"ernik":
			for i in 3: out.append(pv.shrub(6500 + i, "ernik"))
		"raspberry":
			for i in 3: out.append(pv.shrub(6600 + i, "raspberry"))
		"currant":
			for i in 2: out.append(pv.shrub(6700 + i, "currant"))
		"cotton":
			for i in 2: out.append(pv.cotton(6800 + i))
		"bells":
			for i in 2: out.append(pv.flowers(6900 + i, "blue"))
		"daisy":
			for i in 2: out.append(pv.flowers(7000 + i, "white"))
		"angelica":
			for i in 2: out.append(pv.angelica(7100 + i))
		"brushpile":
			for i in 2: out.append(pv.brushpile(7200 + i))
		"chanterelle":
			for i in 2: out.append(pv.chanterelles(7300 + i))
		"cones":
			for i in 2: out.append(pv.cones(7400 + i))
		"bones":
			out.append(pv.bones(7500))
	return out

const TREE_KINDS := ["spruce", "pine", "birch", "larch", "aspen", "fir", "cedar", "rowan"]
const NEAR_R := 36.0
var tree_grid := {}
var near_mesh := {}
var near_mmi := {}
var _near_at := Vector3(1e9, 0, 0)
var _near_t := 0.0
var _tree_id := 0

## Детальные деревья только вблизи: в радиусе NEAR_R дерево берётся из полной модели.
## Дальняя лёгкая модель на краю круга не прячется щелчком, а перетекает в детальную
## дизерингом (шейдер сравнивает расстояние до near_c), поэтому смены моделей не видно.
func _update_near(force: bool = false) -> void:
	var c: Vector3 = rig.position
	if not force and Vector2(c.x - _near_at.x, c.z - _near_at.z).length() < 2.5:
		return
	_near_at = c
	var by_key := {}
	var r2 := NEAR_R * NEAR_R
	var g0 := Vector2i(floori((c.x - NEAR_R) / 16.0), floori((c.z - NEAR_R) / 16.0))
	var g1 := Vector2i(floori((c.x + NEAR_R) / 16.0), floori((c.z + NEAR_R) / 16.0))
	for gz in range(g0.y, g1.y + 1):
		for gx in range(g0.x, g1.x + 1):
			var gk := Vector2i(gx, gz)
			if not tree_grid.has(gk):
				continue
			for rec in tree_grid[gk]:
				var t: Transform3D = rec[2]
				if (t.origin.x - c.x) * (t.origin.x - c.x) + (t.origin.z - c.z) * (t.origin.z - c.z) > r2:
					continue
				var key: String = rec[3]
				if not by_key.has(key):
					by_key[key] = []
				by_key[key].append(t)
	for m in veg.fade_list + pv.fade_list:
		m.set_shader_parameter("near_c", c)
		m.set_shader_parameter("near_r", NEAR_R)
	for key in near_mmi.keys():
		if not by_key.has(key):
			near_mmi[key].visible = false
	for key in by_key.keys():
		if not near_mmi.has(key):
			var mmi := MultiMeshInstance3D.new()
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = near_mesh[key]
			mmi.multimesh = mm
			add_child(mmi)
			near_mmi[key] = mmi
		var mi: MultiMeshInstance3D = near_mmi[key]
		var xs: Array = by_key[key]
		mi.multimesh.instance_count = xs.size()
		for i in xs.size():
			mi.multimesh.set_instance_transform(i, xs[i])
			mi.multimesh.set_instance_custom_data(i, Color(0.0, 1.0, 0.0, 0.0))
		mi.visible = true

const PICK := ["berry", "mushroom", "twig", "pebble"]
const PICK_NAME := {"berry": "ягоды", "mushroom": "гриб", "amanita": "мухомор", "twig": "хворост", "pebble": "камень", "flint": "кремень"}

func _add_pick(p: Vector3, kind: String, mm: MultiMesh, i: int) -> void:
	var k := Vector2i(floori(p.x / 8.0), floori(p.z / 8.0))
	if not pickables.has(k):
		pickables[k] = []
	pickables[k].append([p, kind, mm, i])

## Ближайшее, что можно подобрать (до 1,4 м).
func find_pick(p: Vector3) -> Array:
	var c := Vector2i(floori(p.x / 8.0), floori(p.z / 8.0))
	var best: Array = []
	var bd := 1.4 * 1.4
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var k := Vector2i(c.x + dx, c.y + dz)
			if not pickables.has(k):
				continue
			for it in pickables[k]:
				var q: Vector3 = it[0]
				var dd := Vector2(q.x - p.x, q.z - p.z).length_squared()
				if dd < bd:
					bd = dd
					best = it
	return best

func take_pick(it: Array) -> void:
	if inventory != null and not inventory.can_add(String(it[1])):
		_say("Короб полон")
		return
	var q: Vector3 = it[0]
	var k := Vector2i(floori(q.x / 8.0), floori(q.z / 8.0))
	pickables[k].erase(it)
	var mm: MultiMesh = it[2]
	mm.set_instance_transform(it[3], Transform3D(Basis().scaled(Vector3(0.001, 0.001, 0.001)), q - Vector3(0, 5, 0)))
	var kind: String = it[1]
	# съедобное теперь кладём в короб (есть — из инвентаря), если хватает места
	if inventory != null and kind in ["berry", "mushroom", "amanita"]:
		inv[kind] = int(inv.get(kind, 0)) + 1
		_say("+1 %s — в короб" % PICK_NAME[kind])
		return
	match kind:
		"berry":
			hunger = minf(1.0, hunger + 0.05)
			thirst = minf(1.0, thirst + 0.03)
			_say("Съел горсть ягод")
		"mushroom":
			hunger = minf(1.0, hunger + 0.07)
			_say("Съел гриб")
		"amanita":
			health = maxf(0.05, health - 0.2)
			hunger = maxf(0.0, hunger - 0.05)
			flash.color.a = 0.25
			_say("Мухомор! Отравление")
		_:
			inv[kind] = int(inv.get(kind, 0)) + 1
			_say("+1 %s" % PICK_NAME[kind])

func near_water(p: Vector3) -> bool:
	for a in 8:
		var v := Vector3(cos(a * TAU / 8.0), 0, sin(a * TAU / 8.0)) * 1.3
		if height(p.x + v.x, p.z + v.z) < water_level(p.x + v.x, p.z + v.z) - 0.05:
			return true
	return false

func drink() -> void:
	thirst = minf(1.0, thirst + 0.35)
	# --- core: кувшины наполняются у воды (3 глотка на кувшин) ---
	var jugs := int(inv.get("jug", 0))
	if jugs > 0 and int(inv.get("water", 0)) < jugs * 3:
		inv["water"] = jugs * 3
		_say("Напился и набрал воды в кувшин")
		return
	# --- /core ---
	_say("Напился")

func bandage() -> void:
	# --- hunt: повязка из короба; без неё — только зажать рану (hunt.gd) ---
	if hunt != null and hunt.bandage():
		return
	# --- /hunt ---
	bleed = 0.0
	for k in injuries.keys():
		if k != "перелом ноги":
			injuries[k] = minf(float(injuries[k]), 24.0)
	_say("Раны перевязаны")

# --- build: станции ремесла (inventory.station_ok) — костёр "fire", печь "stove", верстак "camp" ---
func station_near(st: String) -> bool:
	return camp != null and bool(camp.station_near(st))
# --- /build ---

func _say(t: String) -> void:
	msg = t
	msg_t = 3.0

## Ближайший ствол (по сетке препятствий) или INF.
func nearest_tree(p: Vector3, r: float) -> Vector3:
	var c := Vector2i(floori(p.x / 8.0), floori(p.z / 8.0))
	var best := Vector3.INF
	var bd := r * r
	var n := int(ceil(r / 8.0))
	for dz in range(-n, n + 1):
		for dx in range(-n, n + 1):
			var k := Vector2i(c.x + dx, c.y + dz)
			if not blockers.has(k):
				continue
			for b in blockers[k]:
				var dd: float = (b.x - p.x) * (b.x - p.x) + (b.y - p.z) * (b.y - p.z)
				if dd < bd:
					bd = dd
					best = Vector3(b.x, 0, b.y)
	return best

## Удар зверя: часть тела, кровотечение, переломы, отбрасывание.
func hurt(amount: float, from: Vector3, kind: String) -> void:
	# --- colony: бьют не героя, а того из отряда, кто ближе и слабее ---
	if colony != null:
		colony.hurt_nearest(amount, from, kind)
		return
	# --- /colony ---
	if health <= 0.0:
		return
	var big := kind in ["bear", "tiger"]
	var roll := randf()
	var part := "нога"
	if roll < (0.2 if big else 0.06):
		part = "голова"
	elif roll < (0.45 if big else 0.2):
		part = "грудь"
	elif roll < 0.65:
		part = "рука"
	var dmg := amount * (1.7 if big and part in ["голова", "грудь"] else 1.0)
	if hero.state == "sit":
		hero._stand_up()
	if inventory != null:
		inventory.abort()
	health = maxf(0.0, health - dmg)
	bleed = minf(1.0, bleed + dmg * 0.6)
	# --- hunt: брызги крови, кровь на одежде, разделка прерывается ---
	if hunt != null:
		hunt.on_hero_hurt(dmg, part, from)
	# --- /hunt ---
	var key := "рана: " + part
	injuries[key] = float(injuries.get(key, 0.0)) + 24.0 + dmg * 80.0
	if part == "нога" and (big or kind == "boar") and randf() < 0.35:
		injuries["перелом ноги"] = 96.0
	var away: Vector3 = hero.position - from
	away.y = 0
	hero.vel += away.normalized() * (6.0 if big else 3.0)
	hero.land_t = 0.4
	hero.land_k = 0.5
	flash.color.a = clampf(0.25 + dmg, 0.0, 0.6)
	if health <= 0.0:
		_die(kind)

func _die(kind: String) -> void:
	hero.state = "dead"
	dead_t = 6.0
	var who: String = {"wolf": "волки", "bear": "медведь", "tiger": "тигр", "boar": "кабан", "moose": "лось", "wolverine": "росомаха"}.get(kind, "")
	dead_lbl.text = "Вы погибли" + ("\n" + who if who != "" else "")
	dead_lbl.visible = true

func _respawn() -> void:
	dead_lbl.visible = false
	health = 0.6
	bleed = 0.0
	injuries.clear()
	hunger = maxf(hunger, 0.5)
	thirst = maxf(thirst, 0.5)
	warmth = maxf(warmth, 0.5)
	stamina = 1.0
	for k in inv.keys():
		if not preload("res://scripts/items.gd").DEF.get(k, {}).has("tool"):
			inv[k] = int(inv[k]) / 2
	hero.revive(_find_start())

## Множитель скорости от ран: хромота при ранах ноги, сильнее при переломе.
func move_factor() -> float:
	var f := 1.0
	if injuries.has("перелом ноги"):
		f = 0.5
	elif injuries.has("рана: нога"):
		f = 0.78
	return f * (0.6 + 0.4 * clampf(health * 2.0, 0.0, 1.0))

const BLOCK_R := {"fungus_snag": 0.22, "birch_dead": 0.2, "snag": 0.25, "snag_b": 0.25, "cherry": 0.15, "fir": 0.36, "cedar": 0.38, "rowan": 0.2, "spruce": 0.4, "pine": 0.32, "birch": 0.28, "bare": 0.3, "spruce_dead": 0.3, "stump": 0.45, "rock": 0.5, "boulder": 0.6, "larch": 0.32, "aspen": 0.26}

func _scatter_all() -> void:
	# вид, попыток на клетку 32 м, масштаб, дальность видимости, тень, правило
	var rules := [
		["spruce", 43, Vector2(0.95, 1.45), 110.0, true, "spruce_t"],
		["pine", 23, Vector2(1.05, 1.45), 115.0, true, "pine_t"],
		["birch", 25, Vector2(1.0, 1.4), 115.0, true, "birch_t"],
		["birch", 5, Vector2(1.0, 1.4), 115.0, true, "edge"],
		["birch", 22, Vector2(0.22, 0.4), 70.0, false, "burnt_z"],
		["bare", 3, Vector2(0.9, 1.3), 110.0, true, "edge"],
		["spruce_dead", 2, Vector2(0.9, 1.3), 110.0, true, "tree"],
		["spruce", 8, Vector2(0.18, 0.35), 75.0, true, "under"],
		["bush", 48, Vector2(0.8, 1.5), 75.0, false, "under"],
		["fern", 90, Vector2(0.7, 1.2), 62.0, false, "fern"],
		["reeds", 14, Vector2(0.8, 1.4), 110.0, false, "reed"],
		["twig", 90, Vector2(0.8, 1.3), 45.0, false, "under"],
		["pebble", 40, Vector2(0.15, 0.45), 55.0, false, "pebble"],
		["rock", 12, Vector2(0.5, 2.2), 115.0, true, "rock"],
		["rock", 14, Vector2(1.8, 4.6), 125.0, true, "boulder"],
		["rock", 45, Vector2(0.6, 2.4), 115.0, true, "rocky_z"],
		["slab", 20, Vector2(1.2, 2.6), 110.0, true, "rocky_z"],
		["stump", 3, Vector2(0.8, 1.2), 75.0, true, "under"],
		["fallen0", 2, Vector2(0.9, 1.2), 100.0, true, "under"],
		["fallen1", 2, Vector2(0.9, 1.2), 100.0, true, "under"],
		["fallen0", 9, Vector2(0.9, 1.2), 100.0, true, "windfall_z"],
		["fallen1", 7, Vector2(0.9, 1.2), 100.0, true, "windfall_z"],
		["windfall", 2, Vector2(0.9, 1.2), 85.0, true, "under"],
		["windfall", 10, Vector2(0.9, 1.3), 85.0, true, "windfall_z"],
		["snag", 3, Vector2(0.9, 1.2), 100.0, true, "tree"],
		["snag", 8, Vector2(0.9, 1.3), 100.0, true, "windfall_z"],
		["snag_b", 26, Vector2(0.9, 1.4), 105.0, true, "burnt_z"],
		["fallen1", 4, Vector2(0.9, 1.2), 100.0, true, "burnt_z"],
		["fireweed", 60, Vector2(0.8, 1.3), 70.0, false, "burnt_z"],
		["fireweed", 8, Vector2(0.8, 1.2), 70.0, false, "meadow"],
		["larch", 11, Vector2(1.05, 1.45), 115.0, true, "larch_t"],
		["aspen", 11, Vector2(1.0, 1.4), 115.0, true, "edge"],
		["berry", 25, Vector2(0.7, 1.3), 55.0, false, "under"],
		["bilberry", 42, Vector2(0.9, 1.5), 55.0, false, "under"],
		["mushroom", 14, Vector2(0.8, 1.4), 40.0, false, "under"],
		["fir", 15, Vector2(1.05, 1.45), 110.0, true, "fir_t"],
		["cedar", 8, Vector2(1.05, 1.5), 110.0, true, "cedar_t"],
		["willow", 22, Vector2(0.8, 1.3), 75.0, true, "river"],
		["alder", 18, Vector2(0.9, 1.4), 80.0, true, "river"],
		["cherry", 4, Vector2(0.9, 1.3), 90.0, true, "river"],
		["cherry", 2, Vector2(0.9, 1.3), 90.0, true, "edge"],
		["rose", 12, Vector2(0.8, 1.2), 65.0, false, "edge"],
		["horsetail", 30, Vector2(0.8, 1.3), 45.0, false, "bank"],
		["horsetail", 30, Vector2(0.8, 1.3), 45.0, false, "bog_z"],
		["hummock", 55, Vector2(0.9, 1.7), 50.0, false, "bog_z"],
		["sedge", 40, Vector2(0.9, 1.4), 45.0, false, "bog_z"],
		["reeds", 24, Vector2(0.9, 1.4), 14.0, false, "bog_z"],
		["juniper", 10, Vector2(0.7, 1.2), 60.0, false, "rocky"],
		["stlanik", 16, Vector2(0.8, 1.3), 80.0, true, "rocky_z"],
		["rowan", 4, Vector2(0.9, 1.3), 90.0, true, "edge"],
		["anthill", 1, Vector2(0.8, 1.2), 65.0, true, "under"],
		["mossrock", 9, Vector2(0.6, 1.6), 100.0, true, "under"],
		["split_rock", 1, Vector2(1.2, 2.2), 110.0, true, "rock"],
		["outcrop", 3, Vector2(1.5, 2.8), 110.0, true, "rocky"],
		["scree", 10, Vector2(0.8, 1.4), 60.0, false, "rocky_z"],
		["stump_rot", 4, Vector2(0.8, 1.2), 70.0, true, "under"],
		["stump_mush", 3, Vector2(0.8, 1.1), 60.0, true, "under"],
		["fungus_snag", 2, Vector2(0.9, 1.2), 100.0, true, "tree"],
		["birch_dead", 2, Vector2(0.9, 1.2), 100.0, true, "edge"],
		["mosslog", 5, Vector2(0.9, 1.2), 90.0, true, "under"],
		["ledum", 36, Vector2(0.8, 1.3), 45.0, false, "bog_z"],
		["ledum", 6, Vector2(0.8, 1.2), 45.0, false, "under"],
		["cloudberry", 30, Vector2(0.8, 1.3), 40.0, false, "bog_z"],
		["cranberry", 32, Vector2(0.8, 1.3), 40.0, false, "bog_z"],
		["cotton", 25, Vector2(0.8, 1.3), 45.0, false, "bog_z"],
		["lingon", 32, Vector2(0.8, 1.4), 40.0, false, "under"],
		["ernik", 32, Vector2(0.7, 1.2), 55.0, false, "bog_z"],
		["raspberry", 30, Vector2(0.8, 1.2), 60.0, false, "burnt_z"],
		["raspberry", 5, Vector2(0.8, 1.2), 60.0, false, "edge"],
		["currant", 8, Vector2(0.8, 1.2), 60.0, false, "river"],
		["bells", 14, Vector2(0.8, 1.2), 40.0, false, "meadow"],
		["daisy", 14, Vector2(0.8, 1.2), 40.0, false, "meadow"],
		["angelica", 10, Vector2(0.8, 1.2), 60.0, false, "bank"],
		["brushpile", 4, Vector2(0.8, 1.2), 60.0, false, "burnt_z"],
		["chanterelle", 8, Vector2(0.8, 1.3), 35.0, false, "under"],
		["cones", 30, Vector2(0.8, 1.2), 30.0, false, "under"],
		["bones", 1, Vector2(0.9, 1.1), 40.0, false, "under"],
	]
	var cache := {}
	var cache_lod := {}
	for r in rules:
		if not cache.has(r[0]):
			cache[r[0]] = _variants(r[0])
			if r[0] in TREE_KINDS:
				pv.lod = true
				cache_lod[r[0]] = _variants(r[0])
				pv.lod = false
	_cliff_rocks(cache["rock"])
	var cells := int(SIZE / CELL)
	for cz in cells:
		for cx in cells:
			var rng := RandomNumberGenerator.new()
			rng.seed = cz * 1000 + cx
			var x0 := cx * CELL - SIZE * 0.5
			var z0 := cz * CELL - SIZE * 0.5
			for r in rules:
				var vars: Array = cache[r[0]]
				var per_var := []
				for v in vars:
					per_var.append([])
				var pick_kind: String = r[0] if r[0] in PICK else ""
				var attempt_multiplier := 4
				if r[0] in FOREST_DENSITY_SPECIES:
					attempt_multiplier = int(round(4.0 * FOREST_DENSITY_MULTIPLIER))
				for k in int(r[1]) * attempt_multiplier:
					var x := x0 + rng.randf() * CELL
					var z := z0 + rng.randf() * CELL
					if not _accept(r[5], x, z, rng):
						continue
					var vi := rng.randi() % vars.size()
					var sc: Vector2 = r[2]
					var s := rng.randf_range(sc.x, sc.y)
					var kind: String = r[0]
					var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.1), s))
					if kind == "slab":
						b = b.scaled(Vector3(1.0, 0.35, 1.0))
					# место занято (ствол, камень, поваленное дерево) — не ставим
					var occ_r := _occ_radius(kind, vars[vi], s)
					var by: float = height(x, z) - 0.05
					var o := Vector3(x, by, z)
					# широкие вещи не висят над склоном: опора — самая низкая точка под ними
					var foot: float = FOOT_R.get(kind, 0.0) * s
					if kind in ROCKISH:
						var rv: Vector3 = vars[vi][2]
						foot = (rv.x + rv.z) * 0.35 * s
					if foot > 0.0:
						var hm := by + 0.05
						for k2 in 6:
							var a2 := TAU * k2 / 6.0
							hm = minf(hm, height(x + cos(a2) * foot, z + sin(a2) * foot))
						o.y = hm - 0.05
					# плоские мелочи ложатся по склону
					if kind in HUG:
						var nrm := normal_at(x, z)
						if nrm.y < 0.999:
							b = Basis(Quaternion(Vector3.UP, nrm)) * b
					var fall_len := 0.0
					if kind == "fallen0" or kind == "fallen1":
						var fv: Array = vars[vi]
						fall_len = float(fv[1]) * s
						var ax0: Vector3 = b.x.normalized()
						var x0f: float = float(fv[4]) * s
						var pr := o + ax0 * x0f
						var pt := o + ax0 * (x0f + fall_len)
						if not _occ_free_line(pr, pt, float(fv[2]) * s + 0.3):
							continue
						var hr := height(pr.x, pr.z)
						var ht := height(pt.x, pt.z)
						b = Basis(ax0.cross(Vector3.UP).normalized(), atan2(ht - hr, fall_len)) * b
						o.y = hr - 0.05
					elif kind == "mosslog":
						var hl: float = float(vars[vi][1]) * 0.5 * s
						var axm: Vector3 = b.x.normalized()
						if not _occ_free_line(o - axm * hl, o + axm * hl, float(vars[vi][2]) * s + 0.3):
							continue
						var ha := height(o.x - axm.x * hl, o.z - axm.z * hl)
						var hb2 := height(o.x + axm.x * hl, o.z + axm.z * hl)
						b = Basis(axm.cross(Vector3.UP).normalized(), atan2(hb2 - ha, hl * 2.0)) * b
						o.y = (ha + hb2) * 0.5 - 0.08
					elif occ_r > 0.0:
						if not _occ_free(x, z, occ_r):
							continue
						_occ_add(x, z, occ_r)
					per_var[vi].append(Transform3D(b, o))
					if kind in ROCKISH:
						# камень — твёрдый купол: на него можно встать или залезть
						var rsc: Vector3 = vars[vi][2]
						var hr2: float = (rsc.x + rsc.z) * 0.6 * s
						var ht2: float = rsc.y * 0.9 * b.y.length()
						if ht2 > 0.12:
							_add_solid([0, o, Vector3.ZERO, hr2, ht2])
						# высокий камень (выше пояса) — преграда для людей и зверей; низкий можно перешагнуть
						if ht2 > 0.85:
							_add_blocker(o.x, o.z, maxf(hr2 * 0.82, 0.4))
					elif kind == "stump":
						_add_solid([2, o, Vector3.ZERO, 0.45 * s, 0.75 * s])
						_add_seat(Vector3(x, height(x, z) + 0.7 * s, z), rng.randf() * TAU)
					elif kind == "stump_rot" or kind == "stump_mush":
						var sh: float = float(vars[vi][1]) * s
						_add_solid([2, o, Vector3.ZERO, 0.42 * s, sh])
						_add_seat(Vector3(x, height(x, z) + sh - 0.05, z), rng.randf() * TAU)
					elif kind == "mosslog":
						# колода: по ней можно пройти и на неё сесть
						var xl := Transform3D(b, o)
						var hl2: float = float(vars[vi][1]) * 0.5
						var rl: float = float(vars[vi][2])
						var la := xl * Vector3(-hl2, rl * 0.8, 0)
						var lb := xl * Vector3(hl2, rl * 0.7, 0)
						_add_solid([1, la, lb, rl * s * 0.95, 0.0])
						_occ_add_line(la, lb, rl * s + 0.2)
						var lm := la.lerp(lb, 0.5)
						var axl: Vector3 = b.x.normalized()
						_add_seat(Vector3(lm.x, solid_top(lm.x, lm.z), lm.z), atan2(axl.z, -axl.x))
					elif fall_len > 0.0:
						# по стволу можно пройти: две капсулы (комель толще), сиденье у комля
						var fv2: Array = vars[vi]
						var xf := Transform3D(b, o)
						var r0: float = float(fv2[2]) * s
						var yb: float = float(fv2[3])
						var x0b: float = float(fv2[4])
						var Lm: float = float(fv2[1])
						var pa := xf * Vector3(x0b, yb - r0 / s * 0.2, 0)
						var pm := xf * Vector3(x0b + Lm * 0.5, r0 / s * 0.9 + 0.08 - r0 / s * 0.2, 0)
						var pe := xf * Vector3(x0b + Lm * 0.85, 0.12, 0)
						_add_solid([1, pa, pm, r0 * 0.95, 0.0])
						_add_solid([1, pm, pe, r0 * 0.55, 0.0])
						_occ_add_line(pa, pe, r0 + 0.2)
						var ax: Vector3 = b.x.normalized()
						_add_blocker(pa.x - ax.x * 0.3, pa.z - ax.z * 0.3, 1.0 if kind == "fallen0" else 0.5)
						var ps := xf * Vector3(x0b + Lm * 0.3, 0, 0)
						_add_seat(Vector3(ps.x, solid_top(ps.x, ps.z), ps.z), atan2(ax.z, -ax.x))
					else:
						var br: float = BLOCK_R.get(kind, 0.0)
						if br > 0.0 and not (kind in ["spruce", "birch"] and s < 0.5):
							_add_blocker(x, z, br * s)
				# мелочь у земли — не больше двух вариантов в клетке: каждый вариант это отдельные
				# вызовы отрисовки, а различие мелких кустиков в кадре почти не видно
				# (камни и прочее — не больше четырёх)
				var nv: int = 2 if float(r[3]) <= 66.0 else 4
				if pick_kind == "" and not cache_lod.has(r[0]) and vars.size() > nv:
					for vi in range(nv, vars.size()):
						per_var[vi % nv].append_array(per_var[vi])
						per_var[vi] = []
				for vi in vars.size():
					if per_var[vi].is_empty():
						continue
					var is_tree: bool = cache_lod.has(r[0])
					# мелочь — клетками 32 м (лучше отсекается камерой), деревья — 64 м (меньше вызовов)
					var fine: bool = true
					# мелочь у земли (дальность по правилу до 66 м) тает к 44 м: дальше её не разглядеть,
					# а при низкой камере там уже дымка; так в кадре вдвое меньше клеток мелочи
					# всё остальное тает к 95 м — там уже сплошная дымка (fog_depth_end ≤ 100)
					# кусты и стланик (до 85 м) — к 62 м
					var far: float = minf(float(r[3]), 95.0) if float(r[3]) > 85.0 else (minf(float(r[3]), 62.0) if float(r[3]) > 66.0 else minf(float(r[3]), 44.0))
					for xs: Array in _split_cell(per_var[vi], x0, z0, fine):
						var mm := _vis_multimesh(cache_lod[r[0]][vi][0] if is_tree else vars[vi][0], xs, far, is_tree)
						var mmi := MultiMeshInstance3D.new()
						mmi.multimesh = mm
						# клетка видна, пока хоть один её экземпляр может быть виден; каждый экземпляр
						# растворяется сам по своей дальности (шейдер), поэтому клетки не «щёлкают»
						mmi.visibility_range_end = far + (23.0 if fine else 46.0)
						# тени только у крупного (деревья, валуны, стволы); мелочь без теней — вдвое меньше вызовов
						# у деревьев тень бросает детальная ближняя модель (_update_near), дальняя — нет:
						# дальше NEAR_R теней всё равно нет (directional_shadow_max_distance)
						var shadow: bool = r[4] and float(r[3]) > 80.0 and not is_tree
						mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
						add_child(mmi)
						_place_cell_records(mm, xs, r, vi, vars, is_tree, pick_kind)

## Разбить экземпляры клетки 64 м на четыре клетки 32 м (fine) или оставить одной группой.
func _split_cell(xs: Array, x0: float, z0: float, fine: bool) -> Array:
	if not fine:
		return [xs]
	var g: Array = [[], [], [], []]
	for t: Transform3D in xs:
		var qx := 1 if t.origin.x - x0 >= CELL * 0.5 else 0
		var qz := 1 if t.origin.z - z0 >= CELL * 0.5 else 0
		g[qz * 2 + qx].append(t)
	return g.filter(func(a: Array) -> bool: return not a.is_empty())

## MultiMesh с плавным исчезновением по дальности: в custom.x — дальность, custom.y = -1 у
## лёгкой дальней версии дерева (вблизи она перетекает в детальную, см. fade.gdshaderinc).
func _vis_multimesh(mesh: Mesh, xs: Array, far: float, lod_tree: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = xs.size()
	var cd := Color(far, -1.0 if lod_tree else 0.0, 0.0, 0.0)
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
		mm.set_instance_custom_data(i, cd)
	return mm

func _place_cell_records(mm: MultiMesh, xs: Array, r: Array, vi: int, vars: Array, is_tree: bool, pick_kind: String) -> void:
	if is_tree:
		var key: String = r[0] + str(vi)
		near_mesh[key] = vars[vi][0]
		for i in xs.size():
			var o: Vector3 = xs[i].origin
			var gk := Vector2i(floori(o.x / 16.0), floori(o.z / 16.0))
			if not tree_grid.has(gk):
				tree_grid[gk] = []
			_tree_id += 1
			tree_grid[gk].append([mm, i, xs[i], key, _tree_id])
	if pick_kind != "":
		var pk := pick_kind
		if pk == "mushroom" and vi < 2:
			pk = "amanita"
		for i in xs.size():
			var po: Vector3 = xs[i].origin
			# --- tools: среди камней на скалистом месте попадается кремень
			var pki := pk
			if pk == "pebble" and (cliff_k(po.x, po.z) > 0.15 or posmod(int(po.x * 7.3) + int(po.z * 3.1), 4) == 0):
				pki = "flint"
			_add_pick(po, pki, mm, i)
	_tools_records(mm, xs, String(r[0]), vars[vi])

## --- tools: места сбора (кусты, ягодники) и бурелом под топор.
func _tools_records(mm: MultiMesh, xs: Array, kind: String, v: Array) -> void:
	# --- core: замшелые камни, гнилые пни и валежины — места сбора мха (world_tools.MOSS_KINDS) ---
	if kind in ["mossrock", "stump_rot", "stump_mush", "mosslog"]:
		for t: Transform3D in xs:
			var mk := Vector2i(floori(t.origin.x / 8.0), floori(t.origin.z / 8.0))
			if not res_spots.has(mk):
				res_spots[mk] = []
			res_spots[mk].append([t.origin, kind])
	# --- /core ---
	if kind in ["bush", "willow", "alder", "rose", "ernik", "cherry", "fireweed", "raspberry", "currant", "bilberry", "lingon", "cranberry", "cloudberry"]:
		for t: Transform3D in xs:
			var k := Vector2i(floori(t.origin.x / 8.0), floori(t.origin.z / 8.0))
			if not res_spots.has(k):
				res_spots[k] = []
			res_spots[k].append([t.origin, kind])
	elif kind in ["fallen0", "fallen1", "mosslog"]:
		for i in xs.size():
			var t: Transform3D = xs[i]
			var s := t.basis.x.length()
			var a := Vector3.ZERO
			var b := Vector3.ZERO
			var r := 0.3
			if kind == "mosslog":
				var hl: float = float(v[1]) * 0.5
				r = float(v[2]) * s
				a = t * Vector3(-hl, float(v[2]) * 0.8, 0)
				b = t * Vector3(hl, float(v[2]) * 0.7, 0)
			else:
				r = float(v[2]) * s
				a = t * Vector3(float(v[4]), float(v[3]), 0)
				b = t * Vector3(float(v[4]) + float(v[1]) * 0.85, 0.12, 0)
			var k := Vector2i(floori((a.x + b.x) * 0.5 / 16.0), floori((a.z + b.z) * 0.5 / 16.0))
			if not fallen_spots.has(k):
				fallen_spots[k] = []
			fallen_spots[k].append({"kind": kind, "mm": mm, "i": i, "xf": t, "a": a, "b": b, "r": r})

# ---------- занятость места: стволы, камни и поваленные деревья не пересекаются ----------
var occ := {}
const FOOT_R := {"scree": 1.2, "brushpile": 0.9, "bones": 0.8, "cones": 0.9, "windfall": 1.5, "stump": 0.4, "stump_rot": 0.5, "stump_mush": 0.45, "anthill": 0.6, "hummock": 0.4, "berry": 0.3, "bilberry": 0.6, "ledum": 0.6, "cloudberry": 0.6, "cranberry": 0.6, "lingon": 0.6, "bush": 0.4, "juniper": 0.5, "stlanik": 0.8}
const HUG := ["scree", "brushpile", "bones", "cones", "chanterelle", "twig", "pebble", "bilberry", "ledum", "cloudberry", "cranberry", "lingon", "hummock", "mushroom"]
const ROCKISH := ["rock", "slab", "mossrock", "split_rock", "outcrop"]
var cliff_mmi: Array = []

func _occ_radius(kind: String, v: Array, s: float) -> float:
	if kind in TREE_KINDS or kind in ["bare", "spruce_dead", "snag", "snag_b"]:
		return (0.5 if s > 0.5 else 0.0) * s
	if kind in ROCKISH:
		var rsc: Vector3 = v[2]
		return (rsc.x + rsc.z) * 0.62 * s
	if kind in ["fungus_snag", "birch_dead"]:
		return 0.4 * s
	match kind:
		"stump", "anthill", "stump_rot", "stump_mush", "brushpile":
			return 0.6 * s
		"scree":
			return 1.3 * s
		"windfall":
			return 2.2 * s
		"bush", "willow", "alder", "juniper", "stlanik", "rose", "berry", "cherry", "raspberry", "currant", "ernik", "angelica":
			return 0.35 * s
	return 0.0

func _occ_free(x: float, z: float, r: float) -> bool:
	var gx := floori(x / 4.0)
	var gz := floori(z / 4.0)
	var reach := int(ceil((r + 3.0) / 4.0))
	for ix in range(gx - reach, gx + reach + 1):
		for iz in range(gz - reach, gz + reach + 1):
			var k := Vector2i(ix, iz)
			if not occ.has(k):
				continue
			for e: Vector3 in occ[k]:
				if Vector2(x - e.x, z - e.y).length() < r + e.z:
					return false
	return true

func _occ_add(x: float, z: float, r: float) -> void:
	var k := Vector2i(floori(x / 4.0), floori(z / 4.0))
	if not occ.has(k):
		occ[k] = []
	occ[k].append(Vector3(x, z, minf(r, 3.0)))

func _occ_free_line(a: Vector3, b: Vector3, r: float) -> bool:
	var n := int(ceil(a.distance_to(b) / 1.2)) + 1
	for i in n:
		var p := a.lerp(b, float(i) / float(n - 1))
		if not _occ_free(p.x, p.z, r):
			return false
	return true

func _occ_add_line(a: Vector3, b: Vector3, r: float) -> void:
	var n := int(ceil(a.distance_to(b) / 1.2)) + 1
	for i in n:
		var p := a.lerp(b, float(i) / float(n - 1))
		_occ_add(p.x, p.z, r)

## Скальные стены уступов: высокие глыбы вдоль обрыва и осыпь камней у подножия.
func _cliff_rocks(vars: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var per_var := []
	for v in vars:
		per_var.append([])
	var half := SIZE * 0.5 - 4.0
	var step := 3.2
	var z := -half
	while z < half:
		var x := -half
		while x < half:
			var px := x + rng.randf_range(-0.8, 0.8)
			var pz := z + rng.randf_range(-0.8, 0.8)
			var gx := height(px + 1.0, pz) - height(px - 1.0, pz)
			var gz := height(px, pz + 1.0) - height(px, pz - 1.0)
			var g := Vector2(gx, gz)
			if g.length() > 3.0:
				var up := g.normalized()
				var hb := height(px - up.x * 2.5, pz - up.y * 2.5)
				var ht := height(px + up.x * 2.5, pz + up.y * 2.5)
				var dh := ht - hb
				if dh > 3.0:
					var vi := rng.randi() % vars.size()
					var rsc: Vector3 = vars[vi][2]
					var sxz := rng.randf_range(2.0, 3.2)
					var sy := dh * rng.randf_range(0.75, 1.05) / rsc.y
					var b := Basis(Vector3.UP, atan2(up.x, up.y) + rng.randf_range(-0.5, 0.5)).scaled(Vector3(sxz, sy, sxz * 0.8))
					var o := Vector3(px - up.x * 0.6, hb - 0.4, pz - up.y * 0.6)
					per_var[vi].append(Transform3D(b, o))
					_add_blocker(o.x, o.z, sxz * 0.72)
					_occ_add(o.x, o.z, sxz * 0.9)
					# осыпь у подножия
					for k in 2:
						if rng.randf() < 0.4:
							var d := rng.randf_range(1.8, 4.5)
							var sx2 := px - up.x * d + rng.randf_range(-1.5, 1.5)
							var sz2 := pz - up.y * d + rng.randf_range(-1.5, 1.5)
							var s2 := rng.randf_range(0.3, 1.1)
							var vj := rng.randi() % vars.size()
							per_var[vj].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s2, s2, s2)), Vector3(sx2, height(sx2, sz2) - 0.08, sz2)))
			x += step
		z += step
	for vi in vars.size():
		var xs: Array = per_var[vi]
		if xs.is_empty():
			continue
		# по клеткам 64 м: одна сетка на всю карту не отсекалась и рисовалась целиком
		var groups := {}
		for t: Transform3D in xs:
			var gk := Vector2i(floori(t.origin.x / CELL), floori(t.origin.z / CELL))
			if not groups.has(gk):
				groups[gk] = []
			groups[gk].append(t)
		for gk in groups:
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = _vis_multimesh(vars[vi][0], groups[gk], 95.0, false)
			mmi.visibility_range_end = 141.0
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)
			cliff_mmi.append(mmi)
	print("cliff rocks ", per_var.reduce(func(acc, a): return acc + a.size(), 0))

func _accept(kind: String, x: float, z: float, rng: RandomNumberGenerator) -> bool:
	var y := height(x, z)
	if kind == "boulder":
		return (1.0 - normal_at(x, z).y) > 0.3 and y > WATER_Y + 0.5 and rng.randf() < 0.35
	if kind == "reed":
		return y > WATER_Y - 0.5 and y < WATER_Y + 0.35 and rng.randf() < 0.9
	if kind == "pebble":
		return y > WATER_Y - 0.6 and y < WATER_Y + 1.2 or rng.randf() < 0.15
	if y < WATER_Y + 0.3:
		return kind == "rock" and y > WATER_Y - 0.8 and rng.randf() < 0.3
	var slope := 1.0 - normal_at(x, z).y
	var fd := forest_density(x, z)
	var bio := biome(x, z)
	var zn := zone(x, z)
	match kind:
		"burnt_z":
			return zn == 1 and slope < 0.35 and rng.randf() < 0.85
		"windfall_z":
			return zn == 4 and slope < 0.3 and rng.randf() < 0.8
		"bog_z":
			return zn == 2 and slope < 0.2 and rng.randf() < 0.9
		"rocky_z":
			return zn == 3 and rng.randf() < 0.85
		"meadow":
			return zn == 0 and slope < 0.2 and rng.randf() < (1.0 - fd) * 0.8
		"bank":
			return slope < 0.3 and y < WATER_Y + 0.9 and river_dist(x, z) < 22.0 and rng.randf() < 0.8
	# на гари, болоте и курумнике живого леса мало
	var zk: float = [1.0, 0.06, 0.25, 0.3, 0.7][zn]
	if kind.ends_with("_t") or kind in ["tree", "edge", "under", "fern"]:
		if rng.randf() > zk:
			return false
	match kind:
		"spruce_t":
			return slope < 0.25 and rng.randf() < fd * fd * clampf(1.0 - bio * 0.8 - 0.2, 0.15, 1.0)
		"pine_t":
			return slope < 0.25 and rng.randf() < fd * clampf(0.3 + bio * 0.8, 0.05, 1.0)
		"birch_t":
			return slope < 0.25 and rng.randf() < fd * clampf(0.15 - bio * 0.9, 0.0, 1.0)
		"fir_t":
			# пихтач: тёмные сырые низины
			return slope < 0.25 and y < WATER_Y + 6.0 and rng.randf() < fd * fd * clampf(0.5 - bio * 0.8, 0.0, 1.0)
		"cedar_t":
			# кедрач: возвышенности
			return slope < 0.3 and y > WATER_Y + 6.0 and rng.randf() < fd * clampf(0.15 + bio * 0.5, 0.0, 0.6)
		"river":
			return slope < 0.35 and river_dist(x, z) < 16.0 and rng.randf() < 0.6
		"rocky":
			return rng.randf() < clampf(bio, 0.0, 1.0) * 0.8 + slope * 0.5
		"larch_t":
			return slope < 0.3 and rng.randf() < fd * clampf(0.2 + bio * 0.6, 0.05, 0.8)
		"tree":
			return slope < 0.25 and rng.randf() < fd * fd
		"edge":
			return slope < 0.25 and rng.randf() < fd * (1.0 - fd) * 3.0
		"under":
			return slope < 0.3 and rng.randf() < fd * 0.8
		"fern":
			return slope < 0.3 and rng.randf() < fd * 0.7
		"grass":
			return slope < 0.32 and rng.randf() < (1.0 - fd) * 0.9 + 0.15
		"rock":
			return slope > 0.15 or rng.randf() < 0.15 + maxf(bio, 0.0) * 0.6
		"boulder":
			return slope > 0.3 and rng.randf() < 0.3
	return true


# ======================================================================
# --- core: сохранение (save.gd), настройки (settings.gd), справочник (guide.gd), меню,
# утварь (миска, ложка, горячее), жирник. ---

var saver            # save.gd: реестр разделов, автосохранение
var settings         # settings.gd: качество, кадры, звук; панель
var guide            # guide.gd: «Справочник»
var core_ui: CanvasLayer  # слой справочника, настроек и меню
var lamp_lit := false
var _lamp_h := 0.0

func _core_setup(_ui: CanvasLayer) -> void:
	# свой слой поверх листов лагеря (camp_ui — слой 2)
	var ui := CanvasLayer.new()
	ui.layer = 5
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui)
	core_ui = ui
	settings = preload("res://scripts/settings.gd").new()
	settings.main = self
	ui.add_child(settings)
	guide = preload("res://scripts/guide.gd").new()
	guide.main = self
	ui.add_child(guide)
	saver = preload("res://scripts/save.gd").new()
	saver.main = self
	add_child(saver)
	saver.register("main", self, 10)
	saver.register("weather", weather, 20)
	saver.register("feet", feet, 30)
	saver.register("tools", tools_world, 40)
	saver.register("camp", camp, 50)
	saver.register("animals", animals, 80)
	saver.register("hunt", hunt, 90)
	# меню «Продолжить / Новая игра» (без экрана и в тестах — сразу в игру)
	var auto := OS.get_environment("SAVE_AUTO")
	if OS.get_environment("UI_SHOTS") != "":
		var us: Node = preload("res://scripts/ui_shots.gd").new()
		us.set("main", self)
		add_child(us)
	if OS.get_environment("SAVE_TEST") != "":
		var st: Node = preload("res://scripts/save_test.gd").new()
		st.set("main", self)
		st.set("mode", OS.get_environment("SAVE_TEST"))
		add_child(st)
	if DisplayServer.get_name() == "headless" or OS.get_environment("SHOTS") != "" or OS.get_environment("COLONY_SHOTS") != "" or OS.get_environment("COLONY_TEST") != "" or OS.get_environment("UI_SHOTS") != "" or auto != "":
		if auto == "load":
			saver.load_game()
		saver.enabled = auto != ""
		return
	var menu: Control = preload("res://scripts/start_menu.gd").new()
	menu.main = self
	ui.add_child(menu)

## Еда и питьё из короба: из миски (и ложкой) сытнее, горячее греет. Возвращает [сытость, жажда, здоровье].
func core_eat(id: String, e: Array) -> Array:
	var d: Dictionary = preload("res://scripts/items.gd").DEF.get(id, {})
	var k := 1.0
	var cooked: bool = bool(d.get("bowl", false)) or id in ["meat_cooked", "fish_cooked"]
	if cooked and float(e[0]) > 0.0 and (int(inv.get("bowl", 0)) > 0 or int(inv.get("clay_bowl", 0)) > 0):
		k = 1.25 + (0.1 if int(inv.get("spoon", 0)) > 0 else 0.0)
	if d.has("warm"):
		warmth = minf(1.0, warmth + float(d["warm"]))
	return [float(e[0]) * k, e[1], e[2]]

## Раз в 0,25 с: жирник ночью горит, пока есть жир (кусок — на 6 игровых часов).
func _core_tick(dt: float) -> void:
	var want: bool = int(inv.get("oil_lamp", 0)) > 0 and day_factor < 0.5 and (int(inv.get("fat", 0)) > 0 or _lamp_h > 0.0)
	if want:
		_lamp_h -= dt / 75.0
		if _lamp_h <= 0.0:
			if int(inv.get("fat", 0)) > 0:
				inv["fat"] = int(inv["fat"]) - 1
				if int(inv["fat"]) <= 0:
					inv.erase("fat")
				_lamp_h = 6.0
			else:
				want = false
	if want != lamp_lit:
		lamp_lit = want
		if want:
			_say("Жирник зажжён")

## Раздел «main» сохранения: время, герой, статы, короб, рука и пояс.
func to_save() -> Dictionary:
	var SV = preload("res://scripts/save.gd")
	var t: Node = hero.tools
	return {"t_hours": t_hours, "day": day_count, "hunger": hunger, "thirst": thirst, "warmth": warmth,
		"stamina": stamina, "health": health, "bleed": bleed, "injuries": injuries.duplicate(),
		"inv": inv.duplicate(), "pos": SV.enc(hero.position), "yaw": float(hero.body.rotation.y),
		"cam_yaw": float(rig.rotation.y), "held": String(t.held) if t != null else "",
		"belt": (t.belt as Array).duplicate() if t != null else [], "lamp_h": _lamp_h,
		"back": String(t.get("back")) if t != null and t.get("back") != null else "",
		"logs": int(t.get("logs")) if t != null and t.get("logs") != null else 0,
		"bundle": _bundle_save(t)}

## Связка брёвен на верёвке (hero_tools.bundle, log_bundle.gd): брёвна [{r, L, bark}].
func _bundle_save(t: Node) -> Array:
	var SV = preload("res://scripts/save.gd")
	var out: Array = []
	if t == null or t.get("bundle") == null:
		return out
	for lg: Dictionary in t.bundle.logs:
		out.append({"r": float(lg["r"]), "L": float(lg["L"]), "bark": SV.enc(lg["bark"])})
	return out

func from_save(d: Dictionary) -> void:
	var SV = preload("res://scripts/save.gd")
	t_hours = float(d.get("t_hours", t_hours))
	day_count = int(d.get("day", day_count))
	hunger = float(d.get("hunger", hunger))
	thirst = float(d.get("thirst", thirst))
	warmth = float(d.get("warmth", warmth))
	stamina = float(d.get("stamina", stamina))
	health = maxf(0.05, float(d.get("health", health)))
	bleed = float(d.get("bleed", 0.0))
	_lamp_h = float(d.get("lamp_h", 0.0))
	injuries = {}
	var inj: Dictionary = d.get("injuries", {})
	for k: String in inj:
		injuries[k] = float(inj[k])
	inv = SV.int_dict(d.get("inv", {}))
	var p: Vector3 = SV.dec(d.get("pos", SV.enc(hero.position)))
	hero.position = p
	hero.vel = Vector3.ZERO
	hero.body.rotation.y = float(d.get("yaw", 0.0))
	rig.rotation.y = float(d.get("cam_yaw", rig.rotation.y))
	rig.position = p
	var t: Node = hero.tools
	if t != null:
		t.held = String(d.get("held", ""))
		var b: Array = []
		for x: Variant in d.get("belt", []):
			b.append(String(x))
		t.belt = b
		# combat: спина, брёвна на плече, связка на верёвке
		if t.get("back") != null:
			t.back = String(d.get("back", ""))
		if t.get("logs") != null:
			t.logs = int(d.get("logs", 0))
			if t.held == "log" and t.logs <= 0:
				t.logs = 1
		if "bundle" in t and t.bundle != null:
			t.bundle.queue_free()
			t.bundle = null
		var bl: Array = d.get("bundle", [])
		if not bl.is_empty() and "bundle" in t:
			var list: Array = []
			for e: Dictionary in bl:
				list.append({"r": float(e["r"]), "L": float(e["L"]), "bark": SV.dec(e["bark"])})
			var bn: Node3D = preload("res://scripts/log_bundle.gd").new()
			bn.set("main", self)
			tools_world.add_child(bn)
			var yaw: float = hero.body.rotation.y
			bn.call("setup", list, hero.position, Vector3(sin(yaw), 0, cos(yaw)))
			t.bundle = bn
		t.sync()
	_update_near(true)
	_update_sky()
# --- /core ---
