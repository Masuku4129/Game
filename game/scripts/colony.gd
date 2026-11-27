extends Node3D
## --- colony: отряд землепроходцев (main.colony). ---
## Главный узел нового строя игры: три человека (unit.gd), общий запас острога,
## выбор и приказы пальцем, постановка построек, работы (jobs.gd), ход нужд,
## дальность прорисовки под изометрию и сценарий «Первая зима» (scenario.gd).
##
## Общий запас — это main.inv: так всё старое (стройка, готовка, ремесло, сохранение)
## работает без переделок, а короб героя превращается в амбар острога.
##
## Публичное:
##   units: Array[unit.gd], sel — выбранный, stock_point(), center()
##   count(id) / give(id, n) / spend(id, n) / food_count()
##   order(kind, hit) — приказ выбранному; on_tap / on_long_press — палец
##   build_begin(type) / build_move(p) / build_rotate(a) / build_confirm() / build_cancel()
##   nearest_building(p, types, r) / nearest_site(p, r) / is_store(s)
##   hurt_nearest(dmg, from, kind) — зовёт main.hurt
##   note(text) — строка сообщений

const UNIT = preload("res://scripts/unit.gd")
const NAV = preload("res://scripts/nav.gd")
const JOBS = preload("res://scripts/jobs.gd")
const CG = preload("res://scripts/colony_geo.gd")
const IT = preload("res://scripts/items.gd")
const GEO = preload("res://scripts/build_geo.gd")
const ZONES = preload("res://scripts/zones.gd")
const PLAN = preload("res://scripts/planner.gd")

## Трое: вожак (Ермолай) с топором, Семён с луком, Фёдор с топором.
const PEOPLE := [
	{"name": "Ермолай", "leader": true, "tool": "axe", "weapon": "spear",
		"pal": {"jacket": Color(0.46, 0.33, 0.22), "pants": Color(0.4, 0.38, 0.33), "fur": Color(0.78, 0.72, 0.6), "hair": Color(0.38, 0.27, 0.18)}},
	{"name": "Семён", "leader": false, "tool": "bow", "weapon": "bow",
		"pal": {"jacket": Color(0.33, 0.37, 0.3), "pants": Color(0.36, 0.33, 0.3), "fur": Color(0.7, 0.66, 0.56), "hair": Color(0.62, 0.52, 0.36)}},
	{"name": "Фёдор", "leader": false, "tool": "axe", "weapon": "spear",
		"pal": {"jacket": Color(0.4, 0.28, 0.3), "pants": Color(0.33, 0.31, 0.28), "fur": Color(0.74, 0.68, 0.55), "hair": Color(0.2, 0.17, 0.14)}},
]
const START_STOCK := {"axe": 2, "knife": 3, "bow": 1, "arrow": 16, "spear": 2, "rope": 2,
	"twig": 12, "bark": 8, "firewood": 6, "meat_dried": 8, "berry": 6, "pebble": 10}

## Заказы мастерской: что умеют делать. in — расход, out — сколько получится, tool — нужный инструмент.
const RECIPES := {
	"plank": {"in": {"log": 1}, "out": 2, "tool": "axe", "t": 4.0},
	"bow": {"in": {"branch": 1, "bark": 2}, "out": 1, "tool": "knife", "t": 6.0},
	"arrow": {"in": {"twig": 1, "pebble": 1}, "out": 3, "tool": "knife", "t": 3.0},
	"handle": {"in": {"branch": 1}, "out": 1, "tool": "knife", "t": 3.0},
	"shovel": {"in": {"plank": 1, "handle": 1}, "out": 1, "tool": "knife", "t": 5.0},
	"table": {"in": {"plank": 4, "log": 1}, "out": 1, "tool": "axe", "t": 8.0},
	"spoon": {"in": {"firewood": 1}, "out": 1, "tool": "knife", "t": 3.0},
	"mug": {"in": {"firewood": 1}, "out": 1, "tool": "knife", "t": 3.0},
	"bowl": {"in": {"firewood": 2}, "out": 1, "tool": "knife", "t": 3.5},
}
const RECIPE_ORDER := ["plank", "table", "bow", "arrow", "handle", "shovel", "spoon", "mug", "bowl"]
var orders := {}                # рецепт → сколько ещё сделать

func can_craft(id: String) -> bool:
	var r: Dictionary = RECIPES.get(id, {})
	if r.is_empty() or count(String(r["tool"])) < 1:
		return false
	for k: String in r["in"]:
		if count(k) < int(r["in"][k]):
			return false
	return true

func order_add(id: String, d: int) -> void:
	orders[id] = clampi(int(orders.get(id, 0)) + d, 0, 20)

## Первый заказ в очереди, который можно делать сейчас (не больше одного мастера на рецепт).
func next_order(me) -> String:
	for id: String in RECIPE_ORDER:
		if int(orders.get(id, 0)) <= 0 or not can_craft(id):
			continue
		var busy := false
		for o in units:
			if o != me and o.state != "dead" and String(o.job.get("kind", "")) == "craft" and String(o.job.get("recipe", "")) == id:
				busy = true
		if not busy:
			return id
	return ""

var main: Node3D
var nav
var jobs
var zones                       # zones.gd — разрешённая область
var planner                     # planner.gd — лист работ и метки
var units: Array = []
var sel                         # первый выбранный (unit.gd) или null
var sel_all: Array = []         # выбранные (рамкой можно несколько)
var tool_mode := ""             # "" | paint | erase | desig | undesig | box
var brush := 4.0                # радиус кисти области, м
var box_from := Vector2.INF     # рамка выбора (экран)
var box_to := Vector2.INF
var ui                          # colony_ui.gd
var scenario                    # scenario.gd
var rig                         # rts_camera.gd (он же main.rig)
var auto_work := true
var camp_center := Vector3.ZERO
var stats := {"days": 1, "trees": 0, "logs": 0, "firewood": 0, "meat": 0, "furs": 0, "wolves": 0, "built": 0}
var msg := ""
var msg_t := 0.0

var marks: MultiMeshInstance3D
var _mark_t := 0.0
var _task_t := 0.0
var _butchered := {}
var _counted := {}              # уже засчитанные битые звери
var _need_t := 0.0
var _auto_t := 0.0
var _detail_t := 0.0
var _far_i := 0
var _us := 0                    # мкс на кадр (замер нагрузки)
var _us_avg := 0.0

# постановка постройки
var place_type := ""
var ghost: Node3D
var ghost_pos := Vector3.ZERO
var ghost_yaw := 0.0
var ghost_ok := false
var ghost_why := ""
var _ok_mat := StandardMaterial3D.new()
var _bad_mat := StandardMaterial3D.new()

func setup(m: Node3D, layer: CanvasLayer) -> void:
	main = m
	nav = NAV.new()
	nav.setup(m)
	jobs = JOBS.new()
	jobs.setup(self)
	zones = ZONES.new()
	add_child(zones)
	zones.setup(self)
	nav.area = zones
	for mt: StandardMaterial3D in [_ok_mat, _bad_mat]:
		mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mt.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ok_mat.albedo_color = Color(0.45, 0.95, 0.45, 0.42)
	_bad_mat.albedo_color = Color(1.0, 0.3, 0.25, 0.45)
	camp_center = main.hero.position
	for id: String in START_STOCK:
		main.inv[id] = int(main.inv.get(id, 0)) + int(START_STOCK[id])
	if "u" not in OS.get_environment("CB"):
		_spawn_units()
	planner = PLAN.new()
	planner.setup(self)
	_build_marks()
	# первый костёр: с него начинается зимовка
	var fp: Vector3 = nav.nearest_free(camp_center + Vector3(2.0, 0, 1.0), 6.0)
	if not main.camp.overlaps(fp.x, fp.z, 1.0) and OS.get_environment("NOFIRE") == "":
		var fire: Dictionary = main.camp.place("campfire", Vector3(fp.x, main.height(fp.x, fp.z), fp.z), 0.0)
		fire["fuel"] = 3.0
		fire["lit"] = true
		main.camp._refresh(fire)
	_clear_trees(camp_center, 11.0)
	nav.invalidate(camp_center.x, camp_center.z, 16.0)
	ui = preload("res://scripts/colony_ui.gd").new()
	ui.colony = self
	ui.main = main
	ui.anchor_right = 1.0
	ui.anchor_bottom = 1.0
	if "i" not in OS.get_environment("CB"):
		layer.add_child(ui)
	scenario = preload("res://scripts/scenario.gd").new()
	scenario.colony = self
	scenario.main = main
	add_child(scenario)
	if not units.is_empty():
		select(units[0])
	if main.saver != null:
		main.saver.register("colony", self, 60)

## Расчистить поляну: деревья у лагеря убираем, чтобы кроны не закрывали людей.
func _clear_trees(c: Vector3, r: float) -> void:
	var w: Node = main.tools_world
	var n := 0
	var x := -r
	while x <= r:
		var z := -r
		while z <= r:
			if Vector2(x, z).length() <= r:
				var rec: Array = w.find_tree(c + Vector3(x, 0, z), 2.2)
				if not rec.is_empty() and (rec[2] as Transform3D).origin.y > -100.0:
					w._hide_tree(rec)
					n += 1
			z += 2.5
		x += 2.5

func _spawn_units() -> void:
	var i := 0
	for cfg: Dictionary in PEOPLE:
		var a := TAU * float(i) / float(PEOPLE.size())
		var p: Vector3 = nav.nearest_free(camp_center + Vector3(cos(a), 0, sin(a)) * 2.6, 6.0)
		var u: Node3D = UNIT.new()
		add_child(u)
		var c := cfg.duplicate()
		c["seed"] = 100 + i * 7
		u.setup(self, p, c)
		u.weapon = String(cfg.get("weapon", ""))
		units.append(u)
		i += 1

# ---------- общий запас ----------

func count(id: String) -> int:
	return int(main.inv.get(id, 0))

func give(id: String, n: int) -> void:
	main.inv[id] = count(id) + n

func spend(id: String, n: int) -> bool:
	var have := count(id)
	if have < n:
		return false
	if have - n <= 0:
		main.inv.erase(id)
	else:
		main.inv[id] = have - n
	return true

func food_count() -> int:
	var n := 0
	for id: String in JOBS.FOOD:
		n += count(id)
	return n

const STOCK_BASE := 160.0       # кг без амбара (навес у костра)
const STOCK_PER := 260.0        # кг на каждый амбар
const STOCK_PER_CABIN := 120.0  # кг на избу

## Вместимость запаса растёт с амбарами (человек несёт свои 32 кг, а не 15 кг короба).
func stock_cap() -> float:
	return STOCK_BASE + STOCK_PER * float(count_built("storehouse")) + STOCK_PER_CABIN * float(count_built("cabin"))

func stock_weight() -> float:
	var w := 0.0
	for id: String in main.inv:
		if id in ["axe", "knife", "bow", "spear", "arrow", "rope"]:
			continue          # снаряжение отряда не считается
		w += IT.weight_of(id) * float(main.inv[id])
	return w

func stock_full() -> bool:
	return stock_weight() >= stock_cap()

## Сколько id стройке ещё нужно (с учётом уже принесённого).
func site_missing(s: Dictionary, id: String) -> int:
	var need: Dictionary = main.camp.need_of(s)
	return maxi(0, int(need.get(id, 0)) - int((s.get("have", {}) as Dictionary).get(id, 0)))

## Положить на стройку ресурс; когда всё собрано — стройка начинается.
func site_deposit(s: Dictionary, id: String, n: int) -> int:
	var put: int = main.camp.deposit_item(s, id, n)
	if put > 0 and String(s.get("stage", "")) == "site" and bool(main.camp.site_ready(s)):
		s["stage"] = "building"
		s["prog"] = 0.0
		s["_shown"] = -1
		main.camp._register(s)
		main.camp._rebuild(s)
		note("Всё на месте: можно строить")
	return put

## Стройка ждёт ресурс, который есть в запасе: [id, сколько] или [].
func site_wanted(s: Dictionary) -> Array:
	if String(s.get("stage", "")) != "site":
		return []
	var need: Dictionary = main.camp.need_of(s)
	for id: String in need:
		var m := site_missing(s, id)
		if m > 0 and count(id) > 0:
			return [id, m]
	return []

func want_food() -> int:
	return 24

func want_firewood() -> int:
	return 30

func furs() -> int:
	return count("fur")

func stat_add(k: String, n: int) -> void:
	stats[k] = int(stats.get(k, 0)) + n

func note(t: String) -> void:
	msg = t
	msg_t = 3.5
	main._say(t)

## Можно ли человеку работать в этой точке (разрешённая область).
func can_work_at(u, p: Vector3) -> bool:
	if u == null or not u.area_lock or zones == null:
		return true
	return bool(zones.allowed(p.x, p.z))

# ---------- места ----------

func center() -> Vector3:
	return camp_center

## Куда сносят добычу: амбар, иначе костёр, иначе середина лагеря.
func stock_point() -> Vector3:
	var s: Dictionary = nearest_building(camp_center, ["storehouse"], 200.0)
	if s.is_empty():
		s = nearest_building(camp_center, ["cabin", "cache", "campfire"], 200.0)
	if s.is_empty():
		return camp_center
	var p: Vector3 = s["pos"]
	return Vector3(p.x, main.ground_fast(p.x, p.z), p.z)

func is_store(s: Dictionary) -> bool:
	return String(s["type"]) in ["storehouse", "cache", "cabin", "leanto", "tree_shelter", "dugout"]

func nearest_building(p: Vector3, types: Array, r: float) -> Dictionary:
	var best := {}
	var bd := r
	for s: Dictionary in main.camp.list:
		if not (String(s["type"]) in types):
			continue
		if String(s.get("stage", "done")) != "done":
			continue
		var q: Vector3 = s["pos"]
		var d := Vector2(q.x - p.x, q.z - p.z).length()
		if d < bd:
			bd = d
			best = s
	return best

## Недостроенная постройка, где уже можно работать (всё принесено).
func nearest_site(p: Vector3, r: float) -> Dictionary:
	var best := {}
	var bd := r
	for s: Dictionary in main.camp.list:
		if String(s.get("stage", "done")) != "building":
			continue
		var q: Vector3 = s["pos"]
		var d := Vector2(q.x - p.x, q.z - p.z).length()
		if d < bd:
			bd = d
			best = s
	return best

func shelter_count() -> int:
	var n := 0
	for s: Dictionary in main.camp.list:
		if String(s.get("stage", "done")) != "done":
			continue
		if String(s["type"]) in ["leanto", "tree_shelter", "dugout", "cabin", "snow_shelter"]:
			n += 1
	return n

func count_built(type: String) -> int:
	var n := 0
	for s: Dictionary in main.camp.list:
		if String(s["type"]) == type and String(s.get("stage", "done")) == "done":
			n += 1
	return n

## Тепло в точке: костёр рядом, укрытие, погода.
func warm_at(p: Vector3, inside: bool) -> float:
	var w = main.weather
	var t: float = w.temp
	var base := clampf(0.5 + t * 0.03 - float(w.wind) * 0.05 - float(w.precip) * 0.15, 0.04, 0.9)
	var add := 0.0
	for s: Dictionary in main.camp.list:
		var q: Vector3 = s["pos"]
		var d := Vector2(q.x - p.x, q.z - p.z).length()
		var type := String(s["type"])
		if type == "campfire" and bool(s.get("lit", false)) and d < 4.5:
			add = maxf(add, 0.4 * (1.0 - d / 4.5))
		if String(s.get("stage", "done")) != "done":
			continue
		var d2: Dictionary = main.camp.DEFS.get(type, {})
		if d2.has("warm") and d < 2.6:
			add = maxf(add, float(d2["warm"]) * 2.0)
		if type == "cabin" and d < 4.0:
			add = maxf(add, 0.45 if bool(s.get("stove_lit", false)) else 0.2)
	if inside:
		add += 0.1
	return clampf(base + add, 0.02, 1.0)

# ---------- поиск цели для работы ----------

func find_tree_near(p: Vector3, r: float) -> Array:
	var w: Node = main.tools_world
	var step := 6.0
	var d := 6.0
	while d < r:
		for k in 10:
			var a := TAU * float(k) / 10.0 + d
			var q := p + Vector3(cos(a), 0, sin(a)) * d
			var rec: Array = w.find_tree(q, 3.0)
			if not rec.is_empty() and not w.is_young(rec):
				return rec
		d += step
	return []

func find_res_near(p: Vector3, r: float) -> Dictionary:
	var w: Node = main.tools_world
	var d := 3.0
	while d < r:
		for k in 8:
			var a := TAU * float(k) / 8.0 + d * 0.7
			var q := p + Vector3(cos(a), 0, sin(a)) * d
			q.y = main.ground_fast(q.x, q.z)
			var t: Dictionary = w.knife_target(q)
			if not t.is_empty() and String(t["type"]) in ["berry", "moss", "bark", "fibre", "pick"]:
				return t
		d += 5.0
	return {}

func find_game_near(p: Vector3, r: float) -> Node3D:
	if main.animals == null:
		return null
	var best: Node3D = null
	var bd := r
	for a: Node3D in main.animals.list:
		if a.dead or not a.visible:
			continue
		if not (String(a.kind) in ["hare", "roe", "deer", "fox", "squirrel", "capercaillie", "muskdeer", "beaver"]):
			continue
		var d := Vector2(a.position.x - p.x, a.position.z - p.z).length()
		if d < bd:
			bd = d
			best = a
	return best

## Место для рыбалки: мелкая вода (не под льдом) рядом.
func find_water_near(p: Vector3, r: float) -> Vector3:
	if float(main.weather.ice) > 0.5:
		return Vector3.INF
	var d := 6.0
	while d < r:
		for k in 12:
			var a := TAU * float(k) / 12.0 + d * 0.5
			var q := p + Vector3(cos(a), 0, sin(a)) * d
			var depth: float = main.water_level(q.x, q.z) - main.height(q.x, q.z)
			if depth > 0.15 and depth < 1.1:
				q.y = main.ground_fast(q.x, q.z)
				return q
		d += 6.0
	return Vector3.INF

func find_carcass_near(p: Vector3, r: float) -> Node3D:
	if main.animals == null:
		return null
	for a: Node3D in main.animals.list:
		if not a.dead or _butchered.has(a) or float(a.meat) <= 0.0:
			continue
		if String(a.kind) in ["hare", "squirrel", "capercaillie"]:
			continue
		if Vector2(a.position.x - p.x, a.position.z - p.z).length() < r:
			return a
	return null

func mark_butchered(a: Node3D) -> void:
	_butchered[a] = true

# ---------- выбор и приказы ----------

func select(u) -> void:
	sel_all = [u] if u != null else []
	_refresh_sel()

## Добавить в выбор (рамкой или кнопкой «Все»).
func select_add(u) -> void:
	if u == null or u.state == "dead":
		return
	if not sel_all.has(u):
		sel_all.append(u)
	_refresh_sel()

func select_all() -> void:
	sel_all = []
	for u in units:
		if u.state != "dead":
			sel_all.append(u)
	_refresh_sel()

func _refresh_sel() -> void:
	var live: Array = []
	for u in sel_all:
		if u != null and u.state != "dead":
			live.append(u)
	sel_all = live
	sel = sel_all[0] if not sel_all.is_empty() else null
	for o in units:
		o.set_selected(sel_all.has(o))
	if ui != null:
		ui.refresh_units()

func select_next() -> void:
	if units.is_empty():
		return
	var i := units.find(sel)
	for k in units.size():
		i = (i + 1) % units.size()
		if units[i].state != "dead":
			select(units[i])
			return

# ---------- палец: кисть области, метки, рамка ----------

## Что делает палец при протяжке: "" — тянет карту.
func drag_tool() -> String:
	return tool_mode

func set_tool(mode: String) -> void:
	tool_mode = mode
	box_from = Vector2.INF
	box_to = Vector2.INF
	if zones != null:
		zones.show_overlay(mode == "paint" or mode == "erase")
	if ui != null:
		ui.tool_changed()

## Палец ведёт по экрану (кисть, метки или рамка).
func on_drag(screen: Vector2, pressed: bool) -> void:
	match tool_mode:
		"paint", "erase":
			var p: Vector3 = ground_point(screen)
			if p != Vector3.INF:
				zones.paint(p, brush, tool_mode == "paint")
		"desig":
			var hit: Dictionary = pick(screen)
			if not hit.is_empty() and planner.designate(hit):
				_mark_t = 0.0
		"undesig":
			var p2: Vector3 = ground_point(screen)
			if p2 != Vector3.INF and planner.undesignate(p2, 3.0):
				_mark_t = 0.0
		"box":
			if pressed and box_from == Vector2.INF:
				box_from = screen
			box_to = screen

## Палец отпустили.
func on_drag_end() -> void:
	if tool_mode == "box":
		_box_select()
		set_tool("")
	elif tool_mode == "desig" or tool_mode == "undesig":
		pass

func _box_select() -> void:
	if box_from == Vector2.INF or box_to == Vector2.INF:
		return
	var r := Rect2(box_from, box_to - box_from).abs()
	var cam: Camera3D = rig.cam
	var got: Array = []
	for u in units:
		if u.state == "dead":
			continue
		var sp := cam.unproject_position(u.position + Vector3(0, 0.9, 0))
		if r.has_point(sp):
			got.append(u)
	if got.is_empty():
		return
	sel_all = got
	_refresh_sel()
	note("Выбрано: %d" % got.size())

## Палец коснулся и отпустил, не сдвинув: выбрать или приказать.
func on_tap(screen: Vector2) -> void:
	if place_type != "":
		var g: Dictionary = pick(screen)
		if g.has("pos"):
			build_move(g["pos"])
		return
	if tool_mode == "desig" or tool_mode == "undesig" or tool_mode == "paint" or tool_mode == "erase":
		on_drag(screen, true)
		return
	var hit: Dictionary = pick(screen)
	if hit.is_empty():
		return
	if String(hit["what"]) == "unit":
		select(hit["unit"])
		return
	if sel == null or sel.state == "dead":
		select_next()
	if sel == null:
		return
	var cmds: Array = jobs.commands(hit)
	if cmds.is_empty():
		return
	var first: Array = cmds[0]
	order(String(first[1]), hit)

## Долгое нажатие: кольцо приказов (если их несколько).
func on_long_press(screen: Vector2) -> void:
	if place_type != "" or tool_mode != "":
		return
	var hit: Dictionary = pick(screen)
	if hit.is_empty() or ui == null:
		return
	if String(hit["what"]) == "unit":
		select(hit["unit"])
		return
	var cmds: Array = jobs.commands(hit)
	if cmds.size() <= 1:
		if not cmds.is_empty():
			order(String((cmds[0] as Array)[1]), hit)
		return
	ui.open_radial(screen, cmds, hit)

## Кнопка «Приказ»: кольцо по цели под выбранным (или под серединой лагеря).
func open_orders() -> void:
	if ui == null or rig == null:
		return
	var p: Vector3 = sel.position if sel != null else camp_center
	var sp: Vector2 = (rig.cam as Camera3D).unproject_position(p + Vector3(0, 1.0, 0))
	var cmds: Array = [["Стоять", "stop"], ["Все сюда", "gather_here"]]
	if sel != null:
		cmds.append(["Только область" if not sel.area_lock else "Вся карта", "area"])
	ui.open_radial(sp, cmds, {"what": "self", "pos": p})

## Приказ выбранным. Общие приказы ("stop", "area") — без цели.
func order(kind: String, hit: Dictionary) -> void:
	if kind == "stop":
		for u in selected():
			jobs.cancel(u)
			u.stop()
		note("Стоять")
		return
	if kind == "area":
		for u in selected():
			u.area_lock = not u.area_lock
		note("Область: %s" % ("только своя" if sel != null and sel.area_lock else "вся карта"))
		return
	if kind == "gather_here":
		var c: Vector3 = hit.get("pos", camp_center)
		var i := 0
		for u in selected():
			var q: Vector3 = nav.nearest_free(c + Vector3(cos(float(i)) * 1.6, 0, sin(float(i)) * 1.6), 6.0)
			jobs.cancel(u)
			jobs.start(u, "move", {"pos": q})
			i += 1
		return
	# «supply:id» — отнести конкретный ресурс на стройку
	if kind.begins_with("supply:"):
		hit = hit.duplicate()
		hit["supply_id"] = kind.substr(7)
		kind = "supply"
	var data: Dictionary = jobs.data_of(hit, kind)
	if data.is_empty() and kind != "deposit":
		return
	var done := 0
	var i2 := 0
	var base: Vector3 = data.get("pos", camp_center)
	for u in selected():
		if u.state == "dead":
			continue
		if not can_work_at(u, hit.get("pos", u.position)):
			note("%s: это вне разрешённой области" % u.unit_name)
			continue
		jobs.cancel(u)
		if kind == "hunt" or kind == "defend":
			u.show_tool(u.weapon if u.weapon != "" else "spear")
		# за дело берётся первый выбранный, остальные встают рядом
		var spread: Vector3 = base
		if i2 > 0:
			var a := TAU * float(i2) / 6.0
			spread = nav.nearest_free(base + Vector3(cos(a), 0, sin(a)) * 1.9, 6.0)
		if kind == "move":
			if jobs.start(u, "move", {"pos": spread}):
				done += 1
		elif i2 == 0 or kind == "supply":
			if jobs.start(u, kind, data):
				done += 1
		elif jobs.start(u, "move", {"pos": spread}):
			done += 1
		i2 += 1
	if done > 0:
		note("%s: %s" % [sel.unit_name if sel != null else "Отряд", jobs.label_of(kind).to_lower()])
		if ui != null:
			ui.mark_order(hit.get("pos", camp_center))

## Выбранные (живые). Если никого — вожак.
func selected() -> Array:
	var out: Array = []
	for u in sel_all:
		if u != null and u.state != "dead":
			out.append(u)
	if out.is_empty() and sel != null and sel.state != "dead":
		out.append(sel)
	return out

# ---------- палец → цель в мире ----------

## Что под точкой экрана: {"what", "pos", ...}. Люди и звери — по близости на экране,
## остальное — по точке на земле под пальцем.
func pick(screen: Vector2) -> Dictionary:
	var cam: Camera3D = rig.cam
	for u in units:
		if u.state == "dead":
			continue
		var sp := cam.unproject_position(u.position + Vector3(0, 0.9, 0))
		if sp.distance_to(screen) < 70.0:
			return {"what": "unit", "unit": u, "pos": u.position}
	var gp := ground_point(screen)
	if gp == Vector3.INF:
		return {}
	if main.animals != null:
		var best: Node3D = null
		var bd := 80.0
		for a: Node3D in main.animals.list:
			if not a.visible:
				continue
			if Vector2(a.position.x - gp.x, a.position.z - gp.z).length() > 14.0:
				continue
			var sp2 := cam.unproject_position(a.position + Vector3(0, float(a.parts.get("H", 0.6)) * 0.5, 0))
			var d := sp2.distance_to(screen)
			if d < bd:
				bd = d
				best = a
		if best != null:
			return {"what": "animal", "animal": best, "pos": best.position}
	# постройки
	for s: Dictionary in main.camp.list:
		for c: Vector3 in main.camp.world_circles(String(s["type"]), s["pos"], float(s["yaw"])):
			if Vector2(c.x - gp.x, c.y - gp.z).length() < c.z + 0.8:
				return {"what": "build", "site": s, "pos": s["pos"]}
	var w: Node = main.tools_world
	var lg: Node3D = w.find_log(gp, 1.8)
	if lg != null:
		return {"what": "log", "node": lg, "pos": lg.global_position}
	var rec: Array = w.find_tree(gp, 1.8)
	if not rec.is_empty() and not w.is_young(rec):
		return {"what": "tree", "rec": rec, "pos": (rec[2] as Transform3D).origin}
	var tr: Dictionary = w.find_trunk(gp, 2.4)
	if not tr.is_empty():
		return {"what": "trunk", "trunk": tr, "pos": w.trunk_cut_point(tr)}
	var res: Dictionary = w.knife_target(gp)
	if not res.is_empty() and String(res["type"]) in ["berry", "moss", "bark", "fibre", "pick"]:
		return {"what": "res", "res": res, "pos": res["pos"]}
	var depth: float = main.water_level(gp.x, gp.z) - main.height(gp.x, gp.z)
	if depth > 0.1 and depth < 1.2 and float(main.weather.ice) < 0.5:
		return {"what": "water", "pos": gp}
	return {"what": "ground", "pos": gp}

## Точка на земле под точкой экрана (шагами по луч camera → земля).
func ground_point(screen: Vector2) -> Vector3:
	var cam: Camera3D = rig.cam
	var o := cam.project_ray_origin(screen)
	var d := cam.project_ray_normal(screen)
	if d.y > -0.01:
		return Vector3.INF
	# первая оценка — пересечение с плоскостью взгляда, потом уточняем по рельефу
	var t := (position.y - o.y) / d.y
	t = clampf(t, 1.0, 600.0)
	var p := o + d * t
	for i in 12:
		var g: float = maxf(main.grid_height(p.x, p.z), main.water_level(p.x, p.z) - 0.4)
		var dy := p.y - g
		if absf(dy) < 0.05:
			break
		t += dy / maxf(-d.y, 0.05)
		p = o + d * t
	p.y = main.ground_fast(p.x, p.z)
	var half: float = main.SIZE * 0.5 - 6.0
	if absf(p.x) > half or absf(p.z) > half:
		return Vector3.INF
	return p

# ---------- стройка ----------

var place_var := 0
func build_begin(type: String, vi: int = 0) -> void:
	build_cancel()
	place_var = vi
	place_type = type
	ghost = CG.ghost(main.camp.geo, type)
	if ghost == null:
		place_type = ""
		return
	GEO.ghostify(ghost, _ok_mat)
	add_child(ghost)
	var p := camp_center
	if sel != null:
		p = sel.position + Vector3(sin(sel.yaw), 0, cos(sel.yaw)) * 3.0
	ghost_yaw = rig.rotation.y + PI
	build_move(p)

func build_move(p: Vector3) -> void:
	if place_type == "":
		return
	ghost_pos = Vector3(p.x, 0.0, p.z)
	ghost_pos.y = _ghost_y()
	if ghost != null:
		ghost.position = ghost_pos
		ghost.rotation.y = ghost_yaw
	_check_ghost()

func build_rotate(a: float) -> void:
	ghost_yaw += a
	build_move(ghost_pos)

func _ghost_y() -> float:
	var hs: Array = []
	for c: Vector3 in main.camp.world_circles(place_type, Vector3(ghost_pos.x, 0, ghost_pos.z), ghost_yaw):
		hs.append(main.height(c.x, c.y))
	if hs.is_empty():
		return main.height(ghost_pos.x, ghost_pos.z)
	var sum := 0.0
	for h: float in hs:
		sum += float(h)
	if place_type in ["cabin", "storehouse", "tower"]:
		var mx: float = hs.max()
		return float(mx) - 0.1
	return minf(sum / float(hs.size()), main.height(ghost_pos.x, ghost_pos.z))

func _check_ghost() -> void:
	var r := _validate()
	ghost_ok = bool(r[0])
	ghost_why = String(r[1])
	if ghost != null:
		GEO.ghostify(ghost, _ok_mat if ghost_ok else _bad_mat)

func _validate() -> Array:
	if place_type == "":
		return [false, ""]
	var circles: Array = main.camp.world_circles(place_type, Vector3(ghost_pos.x, 0, ghost_pos.z), ghost_yaw)
	for c: Vector3 in circles:
		var y: float = main.height(c.x, c.y)
		if y < main.water_level(c.x, c.y) + 0.25:
			return [false, "вода"]
		if main.normal_at(c.x, c.y).y < 0.86:
			return [false, "крутой склон"]
		if main.blocked(c.x, c.y, c.z * 0.65):
			return [false, "мешают деревья и камни"]
		if main.camp.overlaps(c.x, c.y, c.z):
			return [false, "уже занято"]
		if absf(y - ghost_pos.y) > 1.1:
			return [false, "неровное место"]
	var def: Dictionary = main.camp.DEFS[place_type]
	var need: Dictionary = def.get("need", {})
	var vl: Array = main.camp.VARIANTS.get(place_type, [])
	if not vl.is_empty():
		need = (vl[clampi(place_var, 0, vl.size() - 1)] as Dictionary)["need"]
	var cost: Dictionary = def.get("cost", {})
	if not main.camp.can_pay(cost):
		return [false, "нет припасов"]
	if not need.is_empty():
		var any := false
		for k: String in need:
			if count(k) > 0:
				any = true
		if not any and count("log") <= 0:
			return [true, "припасы принесут на стройку"]
	return [true, ""]

## Поставить: простые постройки встают сразу, срубы — стройкой (припасы и работа).
func build_confirm() -> bool:
	if place_type == "" or not ghost_ok:
		return false
	var type := place_type
	var d: Dictionary = main.camp.DEFS[type]
	main.camp.pay(d.get("cost", {}))
	var pos := Vector3(ghost_pos.x, _ghost_y(), ghost_pos.z)
	var s: Dictionary = main.camp.place(type, pos, ghost_yaw)
	if bool(main.get("creative_mode")) and not (d.get("need", {}) as Dictionary).is_empty() and type != "cabin":
		# Creative bypass: skip site/material/work stages and complete the structure immediately.
		main.camp.start_building(s)
	else:
		if not (d.get("need", {}) as Dictionary).is_empty() and type != "cabin":
			s["stage"] = "site"
			s["var"] = place_var
			s["have"] = {}
			s["prog"] = 0.0
			main.camp._rebuild(s)
			main.camp._register(s)
	nav.invalidate(pos.x, pos.z, 8.0)
	build_cancel()
	note("Начато: %s" % String(d["name"]))
	# ближний свободный — на стройку
	var site_stage := String(s.get("stage", "done"))
	if site_stage != "done":
		var best = null
		var bd := 1e9
		for u in units:
			if u.state == "dead" or not u.job.is_empty():
				continue
			var dd: float = u.dist_to(pos)
			if dd < bd:
				bd = dd
				best = u
		if best != null:
			var want: Array = site_wanted(s)
			if not want.is_empty():
				jobs.start(best, "supply", {"site": s, "pos": pos, "id": String(want[0]), "n": 99})
			else:
				jobs.start(best, "build", {"site": s, "pos": pos})
	else:
		stat_add("built", 1)
	return true

func build_cancel() -> void:
	place_type = ""
	if ghost != null:
		ghost.queue_free()
		ghost = null

## Ход стройки: припасы со склада на место, затем работа строителя.
func build_progress(s: Dictionary, dt: float) -> void:
	var type := String(s["type"])
	var d: Dictionary = main.camp.DEFS[type]
	var need: Dictionary = main.camp.need_of(s)
	var stage := String(s.get("stage", "done"))
	if stage == "done":
		return
	if stage == "site":
		# брёвна, принесённые на место и лежащие рядом, идут в сруб;
		# остальное несут отдельными рейсами из запаса (jobs «supply»)
		if main.tools_world != null and int(need.get("log", 0)) > 0:
			for it: Dictionary in main.tools_world.logs_near(s["pos"], 6.0):
				if site_missing(s, "log") <= 0:
					break
				if bool(main.tools_world.take_item(it)):
					site_deposit(s, "log", 1)
		return
	# работа: «work» — сколько игровых часов нужно строителю
	var work: float = float(d.get("work", 3.0))
	var dh := dt / 75.0
	s["prog"] = minf(1.0, float(s.get("prog", 0.0)) + dh / maxf(work, 0.2))
	var p: float = s["prog"]
	var have2: Dictionary = s.get("have", {})
	for id: String in need:
		have2[id] = int(round(float(need[id]) * (1.0 - p)))
	var shown := int(p * 8.0)
	if shown != int(s.get("_shown", -1)):
		s["_shown"] = shown
		if p >= 1.0:
			s["stage"] = "done"
			stat_add("built", 1)
			nav.invalidate((s["pos"] as Vector3).x, (s["pos"] as Vector3).z, 8.0)
			main.camp._register(s)
		main.camp._rebuild(s)

# ---------- метки работ ----------

func _build_marks() -> void:
	marks = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var tor := TorusMesh.new()
	tor.inner_radius = 0.5
	tor.outer_radius = 0.68
	tor.rings = 4
	tor.ring_segments = 14
	var mt := StandardMaterial3D.new()
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.albedo_color = Color(1.0, 0.6, 0.18, 0.85)
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.cull_mode = BaseMaterial3D.CULL_DISABLED
	tor.material = mt
	mm.mesh = tor
	mm.instance_count = 0
	marks.multimesh = mm
	marks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(marks)

## Кольца на помеченных целях (рубить, собирать, охота).
func _update_marks() -> void:
	if marks == null or planner == null:
		return
	var live: Array = planner.live_desig()
	var mm: MultiMesh = marks.multimesh
	if mm.instance_count != live.size():
		mm.instance_count = live.size()
	for i in live.size():
		var e: Dictionary = live[i]
		var p: Vector3 = e["pos"]
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(p.x, main.ground_fast(p.x, p.z) + 0.1, p.z)))

# ---------- урон ----------

## Удар зверя: достаётся слабейшему рядом (волки валят слабого).
func hurt_nearest(dmg: float, from: Vector3, kind: String) -> void:
	var best = null
	var bs := 1e9
	for u in units:
		if u.state == "dead":
			continue
		var d: float = u.dist_to(from)
		if d > 3.5:
			continue
		var score: float = u.health * 10.0 + d
		if score < bs:
			bs = score
			best = u
	if best == null:
		for u in units:
			if u.state == "dead":
				continue
			var d2: float = u.dist_to(from)
			if d2 < bs:
				bs = d2
				best = u
	if best == null:
		return
	best.hurt(dmg, from, kind)
	if main.flash != null:
		main.flash.color.a = clampf(0.12 + dmg * 0.5, 0.0, 0.4)
	# отбиваемся: ближние бросают работу и бьют зверя
	var foe: Node3D = _foe_at(from)
	if foe != null:
		for u in units:
			if u.state == "dead" or u == best:
				continue
			if u.dist_to(from) < 14.0 and (u.job.is_empty() or String(u.job.get("kind", "")) != "defend"):
				u.show_tool(u.weapon if u.weapon != "" else "spear")
				jobs.cancel(u)
				jobs.start(u, "defend", {"animal": foe, "pos": foe.position})

func _foe_at(p: Vector3) -> Node3D:
	if main.animals == null:
		return null
	var best: Node3D = null
	var bd := 4.0
	for a: Node3D in main.animals.list:
		if a.dead:
			continue
		var d := Vector2(a.position.x - p.x, a.position.z - p.z).length()
		if d < bd:
			bd = d
			best = a
	return best

func on_unit_died(u) -> void:
	note("%s погиб" % u.unit_name)
	if sel == u:
		select_next()
	if alive_count() == 0 and scenario != null:
		scenario.lose("Весь отряд погиб")

func alive_count() -> int:
	var n := 0
	for u in units:
		if u.state != "dead":
			n += 1
	return n

# ---------- кадр ----------

var _dbgc := 0
func _process(delta: float) -> void:
	_dbgc += 1
	var t0 := Time.get_ticks_usec()
	if main == null or rig == null:
		return
	msg_t = maxf(0.0, msg_t - delta)
	var cen := Vector3.ZERO
	var n := 0
	for i in units.size():
		var u = units[i]
		# далёкие (за краем взгляда) — втрое реже, но накопленным шагом: на телефоне
		# три человека дёшевы, зато правило готово для большего отряда
		var far: bool = u.dist_to(rig.position) > 95.0
		u.acc += delta
		if not far or (Engine.get_frames_drawn() + i) % 3 == 0:
			var dt: float = u.acc
			u.acc = 0.0
			u.tick(dt)
			if not u.job.is_empty():
				jobs.tick(u, dt)
		if u.state != "dead":
			cen += u.position
			n += 1
	if n > 0:
		camp_center = camp_center.lerp(cen / float(n), minf(1.0, delta * 0.2))
	# герой стоит там же, где вожак: звери, следы и погода работают по-старому
	_sync_hero()
	# нужды раз в четверть секунды
	_need_t -= delta
	if _need_t <= 0.0:
		_need_t = 0.25
		var dh := 0.25 / 75.0
		for u in units:
			if u.state == "dead":
				continue
			var inside: bool = String(u.job.get("kind", "")) in ["sleep", "warm"]
			u.needs_tick(dh, warm_at(u.position, inside))
		if ui != null:
			ui.refresh_units()
	# «сам найдёт работу»
	_auto_t -= delta
	if _auto_t <= 0.0:
		_auto_t = 0.6
		if auto_work:
			for u in units:
				if u.state == "dead":
					continue
				# нужда невмоготу — бросает работу (есть, греться, спать)
				if not u.job.is_empty():
					jobs.interrupt(u)
					continue
				if u.auto:
					if not jobs.auto(u):
						_idle_near_camp(u)
		else:
			for u in units:
				if u.state != "dead" and u.job.is_empty():
					_idle_near_camp(u)
		_count_kills()
	_detail_t -= delta
	if _detail_t <= 0.0:
		_detail_t = 0.3
		_zoom_detail()
	# подписи над головами и кольца на метках
	_task_t -= delta
	if _task_t <= 0.0:
		_task_t = 0.35
		var show_task: bool = rig.zoom_k() < 0.55
		for u in units:
			if u.state == "dead" or not show_task:
				u.set_task("")
			else:
				u.set_task("%s · %s" % [u.unit_name, u.status()])
	_mark_t -= delta
	if _mark_t <= 0.0:
		_mark_t = 0.5
		_update_marks()
	_us = Time.get_ticks_usec() - t0
	_us_avg = lerpf(_us_avg, float(_us), 0.05)

## Битые у лагеря волки — в итоги сценария.
func _count_kills() -> void:
	if main.animals == null:
		return
	for a: Node3D in main.animals.list:
		if not a.dead or _counted.has(a):
			continue
		if Vector2(a.position.x - camp_center.x, a.position.z - camp_center.z).length() > 70.0:
			continue
		_counted[a] = true
		if String(a.kind) in ["wolf", "bear", "wolverine", "lynx", "tiger"]:
			stat_add("wolves", 1)

func script_us() -> float:
	return _us_avg

func _idle_near_camp(u) -> void:
	if u.dist_to(camp_center) > 26.0 and u.arrived():
		var p: Vector3 = nav.nearest_free(camp_center + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)), 8.0)
		u.goto(p, false)

func _sync_hero() -> void:
	var h: Node3D = main.hero
	if h == null:
		return
	var lead = sel
	for u in units:
		if u.leader and u.state != "dead":
			lead = u
			break
	if lead == null:
		return
	h.position = lead.position
	h.body.rotation.y = lead.yaw
	h.vel = lead.vel
	h.moving = lead.moving
	h.state = "walk"
	h.swimb = 0.0
	h.depth = 0.0
	h.airborne = false
	h.run_mag = 0.0
	var best := 0.0
	var bl := 0.0
	for u in units:
		if u.state == "dead":
			continue
		best = maxf(best, u.health)
		bl = maxf(bl, u.bleed)
	main.health = best
	main.bleed = bl
	main.hunger = lead.hunger
	main.warmth = lead.warmth
	main.stamina = 1.0 - clampf(lead.fatigue, 0.0, 1.0)

## Точка, от которой шейдеры считают дальность растворения: середина взгляда.
func veg_focus() -> Vector3:
	return rig.position + Vector3(0, 1.5, 0)

## Дальний взгляд: трава не нужна, дымка дальше, тени шире.
func _zoom_detail() -> void:
	var k: float = rig.zoom_k()
	var gr := lerpf(34.0, 0.0, smoothstep(0.18, 0.45, k))
	main.pv.mats["tuft"].set_shader_parameter("grass_r", gr)
	var show_grass := gr > 3.0
	for key in main.grass_cells:
		var hold: Node3D = main.grass_cells[key]
		if hold.visible != show_grass:
			hold.visible = show_grass
	main.sun.directional_shadow_max_distance = lerpf(32.0, 64.0, k)

## Дымка под изометрию: вблизи как было, вдали — вся долина в дымке у горизонта.
func fog_adjust() -> void:
	var k: float = rig.zoom_k() if rig != null else 0.0
	var w = main.weather
	var fogv: float = w.fogv if w != null else 0.0
	var wet: float = w.precip if w != null else 0.0
	main.env.fog_depth_begin = lerpf(40.0, 190.0, k) - fogv * 30.0 - wet * 12.0
	main.env.fog_depth_end = lerpf(115.0, 430.0, k) - fogv * 55.0 - wet * 25.0

# ---------- сохранение ----------

func to_save() -> Dictionary:
	var us: Array = []
	for u in units:
		us.append(u.to_save())
	return {"units": us, "stats": stats.duplicate(), "auto": auto_work,
		"center": preload("res://scripts/save.gd").enc(camp_center),
		"zones": zones.to_save() if zones != null else {},
		"plan": planner.to_save() if planner != null else {}, "orders": orders.duplicate(),
		"scenario": scenario.to_save() if scenario != null else {}}

func from_save(d: Dictionary) -> void:
	var SV = preload("res://scripts/save.gd")
	var us: Array = d.get("units", [])
	for i in mini(us.size(), units.size()):
		var e: Dictionary = us[i]
		units[i].from_save(e)
	var st: Dictionary = d.get("stats", {})
	for k: String in st:
		stats[k] = int(st[k])
	auto_work = bool(d.get("auto", true))
	orders = {}
	for k: String in (d.get("orders", {}) as Dictionary):
		orders[k] = int(d["orders"][k])
	camp_center = SV.dec(d.get("center", SV.enc(camp_center)))
	if zones != null:
		zones.from_save(d.get("zones", {}))
	if planner != null:
		planner.from_save(d.get("plan", {}))
	if scenario != null:
		scenario.from_save(d.get("scenario", {}))
	nav.chunks.clear()
	if rig != null:
		rig.snap_to(camp_center, 30.0, 0.0)
