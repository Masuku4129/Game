extends Node3D
## Постройки (main.camp). Стройка открывается кнопкой «Стройка» где угодно (лагеря нет). Здесь — данные построек, их столкновения, расчистка растительности, костры и печь,
## готовка, хранилища, тепло и укрытие от ветра, сон, лопата. Режим постановки — build_mode.gd,
## изба изнутри и мебель — cabin.gd, интерфейс — camp_ui.gd, геометрия — build_geo.gd.
##
## Публичное:
##   in_camp(p) — всегда true (лагеря больше нет)
##   list — постройки: {type, pos, yaw, node, store, cap, dur, ...}
##   warm_bonus() -> float, wind_k() -> float, hidden (герой спрятан в снежной пещере)
##   cleared(x, z) -> bool (трава не растёт), has_shovel(), actions() -> Array[[подпись, Callable]]
##   advance(hours) — прожить часы (сон): топливо, готовка, износ

const IT = preload("res://scripts/items.gd")
const GEO = preload("res://scripts/build_geo.gd")
const COLGEO = preload("res://scripts/colony_geo.gd")  # colony

## Что можно построить. cost — сразу при постановке; у избы — вносится на стройку.
const DEFS := {
	"campfire": {"name": "Костёр", "cost": {"pebble": 6, "twig": 3}, "desc": "Камни кольцом, хворост. Греет в 4 м, на вертеле жарят."},
	"leanto": {"name": "Шалаш-навес", "cost": {"branch": 5, "spruce_twigs": 8}, "desc": "Рогатины, жерди и лапник. Тепло +, ветер вдвое слабее, хранилище 20 кг.", "cap": 20.0, "warm": 0.12, "wind": 0.5, "decay": 0.004},
	"tree_shelter": {"name": "Шалаш у дерева", "cost": {"branch": 3, "spruce_twigs": 7}, "desc": "Коньковая жердь привязана к стволу. Прочнее вдвое, хранилище 40 кг.", "cap": 40.0, "warm": 0.15, "wind": 0.35, "decay": 0.002},
	"snow_shelter": {"name": "Снежная пещера", "cost": {"spruce_twigs": 3}, "desc": "Купол из снега (нужна лопата и глубокий снег). Очень тепло, ветра нет, звери не видят.", "cap": 15.0, "warm": 0.35, "wind": 0.0, "decay": 0.003},
	# --- core: схрон (звери почти не разоряют) и колода-верстак (утварь, доски) ---
	"cache": {"name": "Схрон", "cost": {"branch": 4, "spruce_twigs": 6, "pebble": 6}, "desc": "Яма под жердями, лапником и камнями. Хранилище 30 кг; звери почти не разоряют, не гниёт.", "cap": 30.0},
	"chop_block": {"name": "Колода", "cost": {"firewood": 2, "plank": 1}, "desc": "Чурбак и доска на чурках: верстак под небом. Утварь ножом, доски топором."},
	"cabin": {"name": "Изба", "cost": {}, "need": {"log": 24, "moss": 10, "clay": 8, "plank": 10, "pebble": 12}, "work": 3.0, "desc": "Сруб в обло с печью. Припасы вносят на стройку, затем «Строить».", "cap": 20.0},
	# --- colony: постройки острога. need — припасы со склада, work — часы работы строителя;
	# ставит их colony.build_confirm(), геометрию делает colony_geo.gd. ---
	"storehouse": {"name": "Амбар", "cost": {}, "need": {"log": 8, "plank": 3}, "work": 2.5, "desc": "Сруб на стойках: общий запас острога, добычу сносят сюда.", "cap": 200.0},
	"dugout": {"name": "Землянка", "cost": {}, "need": {"log": 6, "moss": 4, "spruce_twigs": 4}, "work": 2.2, "desc": "Врытая в землю клеть с печуркой: тепло и без ветра.", "cap": 40.0, "warm": 0.22, "wind": 0.2},
	"palisade": {"name": "Острожная стена", "cost": {}, "need": {"log": 4}, "work": 1.0, "desc": "Прясло стоячего тына: 3 м заострённых брёвен."},
	"tower": {"name": "Башня", "cost": {}, "need": {"log": 10, "plank": 3}, "work": 3.5, "desc": "Острожная башня с помостом: видно далеко."},
	"rack": {"name": "Сушило", "cost": {"branch": 3, "fiber": 2}, "desc": "Вялить рыбу и мясо впрок."},
}
## Чертежи: у здания несколько наборов припасов (какой ресурс есть — из того и строим).
const VARIANTS := {
	"storehouse": [
		{"name": "брёвна и доски", "need": {"log": 8, "plank": 3}},
		{"name": "только брёвна", "need": {"log": 12, "moss": 3}},
		{"name": "камень и брёвна", "need": {"log": 5, "pebble": 12, "plank": 2}},
	],
	"dugout": [
		{"name": "мох и лапник", "need": {"log": 6, "moss": 4, "spruce_twigs": 4}},
		{"name": "глиняная", "need": {"log": 4, "clay": 6, "branch": 4}},
		{"name": "каменная", "need": {"log": 4, "pebble": 14, "moss": 3}},
	],
	"tower": [
		{"name": "с досками", "need": {"log": 10, "plank": 3}},
		{"name": "из одних брёвен", "need": {"log": 16, "branch": 4}},
	],
	"palisade": [
		{"name": "брёвна", "need": {"log": 4}},
		{"name": "жерди и камень", "need": {"branch": 10, "pebble": 6}},
	],
}

const ORDER := ["campfire", "leanto", "tree_shelter", "snow_shelter", "cache", "chop_block", "cabin"]
## --- colony: порядок построек в листе острога ---
const ORDER_COLONY := ["campfire", "leanto", "dugout", "storehouse", "rack", "cache", "chop_block", "palisade", "tower", "cabin", "snow_shelter"]

var main: Node3D
var geo
var list: Array = []
var hidden := false
var ui
var build
var cabin_ctl
var _clear: Array = []       # [x, z, r] — где трава больше не растёт
var _t := 0.0
var _roof_snow_material: StandardMaterial3D

func _ready() -> void:
	geo = GEO.new(main.pv)
	for m in geo.weather_mats():
		if not main.pv.fade_list.has(m):
			main.pv.fade_list.append(m)
	build = preload("res://scripts/build_mode.gd").new()
	build.camp = self
	build.main = main
	add_child(build)
	cabin_ctl = preload("res://scripts/cabin.gd").new()
	cabin_ctl.camp = self
	cabin_ctl.main = main
	add_child(cabin_ctl)
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	ui = preload("res://scripts/camp_ui.gd").new()
	ui.camp = self
	ui.main = main
	layer.add_child(ui)
	_tdir = OS.get_environment("BUILD_TEST")

# ---------- лагерь ----------
# Механики «Разбить лагерь» больше нет: стройка открывается кнопкой «Стройка» где угодно.
# in_camp() оставлен для совместимости (всегда true) — им могут пользоваться другие команды.

func in_camp(_p: Vector3) -> bool:
	return true

func has_shovel() -> bool:
	var h = main.hero.get("held")
	if h != null and String(h) == "shovel":
		return true
	if main.hero.has_method("has_tool"):
		return bool(main.hero.has_tool("shovel"))
	return int(main.inv.get("shovel", 0)) > 0

func count(id: String) -> int:
	return int(main.inv.get(id, 0))

func take(id: String, n: int) -> void:
	if main.inventory != null:
		main.inventory.remove_item(id, mini(n, count(id)))
		return
	main.inv[id] = count(id) - n
	if int(main.inv[id]) <= 0:
		main.inv.erase(id)

func give(id: String, n: int) -> void:
	if main.inventory != null:
		main.inventory.add_item(id, n)
		return
	main.inv[id] = count(id) + n

## Станция ремесла рядом (для inventory.station_ok через main.station_near):
## "fire" — горящий костёр в 3 м или топящаяся печь в избе; "stove" — печь; "camp" — верстак.
## "rack" — сушило работает только через своё окно (нужно время), поэтому здесь false.
func station_near(st: String) -> bool:
	var hp: Vector3 = main.hero.position
	if cabin_ctl != null and cabin_ctl.inside:
		var c: Dictionary = cabin_ctl.cur
		match st:
			"fire", "stove":
				return bool(c.get("stove_lit", false))
			"camp":
				return cabin_ctl.has_furn(c, "workbench") or cabin_ctl.has_furn(c, "table")  # core: и стол
		return false
	for s: Dictionary in list:
		var d := Vector2(hp.x - (s["pos"] as Vector3).x, hp.z - (s["pos"] as Vector3).z).length()
		match st:
			"fire":
				if s["type"] == "campfire" and bool(s["lit"]) and d < 3.0:
					return true
			"stove":
				if s["type"] == "cabin" and bool(s.get("stove_lit", false)) and d < 4.0:
					return true
			"camp":
				if s["type"] == "cabin" and cabin_ctl != null and cabin_ctl.has_furn(s, "workbench") and d < 4.0:
					return true
				# core: колода-верстак под открытым небом
				if s["type"] == "chop_block" and d < 2.5:
					return true
	return false

func can_pay(cost: Dictionary) -> bool:
	if main != null and bool(main.get("creative_mode")):
		return true
	for k: String in cost:
		if count(k) < int(cost[k]):
			return false
	return true

func pay(cost: Dictionary) -> void:
	if main != null and bool(main.get("creative_mode")):
		return
	for k: String in cost:
		take(k, int(cost[k]))

func can_carry(id: String) -> bool:
	if main.inventory == null:
		return true
	return main.inventory.can_add(id)

# ---------- следы построек: где стоят, что занимают ----------

## Площадь в местных координатах: круги Vector3(x, z, r).
static func footprint(type: String) -> Array:
	match type:
		"campfire":
			return [Vector3(0, 0, 0.8), Vector3(0, -1.3, 0.35)]
		"leanto":
			return _rect(1.35, 1.25, -0.3)
		"tree_shelter":
			return [Vector3(0, 1.3, 0.75), Vector3(0, 2.2, 0.85), Vector3(0, 3.1, 0.7)]
		"snow_shelter":
			return [Vector3(0, 0, 1.5), Vector3(0, 1.75, 0.5)]
		"cache":
			return [Vector3(0, 0, 0.85)]
		"chop_block":
			return [Vector3(0, 0, 0.4), Vector3(-0.45, 0.75, 0.35), Vector3(0.45, 0.75, 0.35)]
		"cabin":
			var a := _rect(2.55, 2.75, 0.0)
			a.append(Vector3(0, 2.95, 0.6))
			return a
		# --- colony ---
		"storehouse":
			return _rect(1.45, 1.25, 0.0)
		"dugout":
			return _rect(1.75, 1.5, -0.3)
		"palisade":
			return [Vector3(-1.2, 0, 0.34), Vector3(-0.6, 0, 0.34), Vector3(0, 0, 0.34), Vector3(0.6, 0, 0.34), Vector3(1.2, 0, 0.34)]
		"tower":
			return _rect(1.35, 1.35, 0.0)
		"rack":
			return [Vector3(-1.15, 0, 0.3), Vector3(1.15, 0, 0.3)]
		# --- /colony ---
	return [Vector3(0, 0, 1.0)]

static func _rect(hx: float, hz: float, cz: float) -> Array:
	var out: Array = []
	var nx := maxi(1, int(ceil(hx * 2.0 / 1.2)))
	var nz := maxi(1, int(ceil(hz * 2.0 / 1.2)))
	var r := maxf(hx * 2.0 / nx, hz * 2.0 / nz) * 0.6
	for i in nx:
		for j in nz:
			out.append(Vector3(-hx + hx * 2.0 * (i + 0.5) / nx, cz - hz + hz * 2.0 * (j + 0.5) / nz, r))
	return out

static func world_circles(type: String, pos: Vector3, yaw: float) -> Array:
	var out: Array = []
	var b := Basis(Vector3.UP, yaw)
	for c: Vector3 in footprint(type):
		var p := b * Vector3(c.x, 0, c.y)
		out.append(Vector3(pos.x + p.x, pos.z + p.z, c.z))
	return out

## Пересекается ли круг с уже стоящими постройками.
func overlaps(x: float, z: float, r: float, skip: Dictionary = {}) -> bool:
	for s: Dictionary in list:
		if s == skip:
			continue
		for c: Vector3 in world_circles(s["type"], s["pos"], s["yaw"]):
			if Vector2(c.x - x, c.y - z).length() < c.z + r - 0.1:
				return true
	return false

# ---------- постановка ----------

## Поставить постройку (проверки и плата — в build_mode). Возвращает запись.
func place(type: String, pos: Vector3, yaw: float, extra: Dictionary = {}) -> Dictionary:
	var d: Dictionary = DEFS[type]
	var s := {"type": type, "pos": pos, "yaw": yaw, "store": {}, "cap": float(d.get("cap", 0.0)), "dur": 1.0,
		"fuel": 0.0, "lit": false, "cook": {}, "blockers": [], "solids": [], "seats": [], "roof_snow": 0.0, "snow_piles": [0.0, 0.0]}
	s.merge(extra)
	if type == "cabin":
		s["stage"] = "site"
		s["have"] = {}
		s["prog"] = 0.0
		s["furn"] = []
		s["stove_fuel"] = 0.0
		s["stove_lit"] = false
	list.append(s)
	_clear_area(world_circles(type, pos, yaw), type != "snow_shelter")
	_rebuild(s)
	_register(s)
	return s

## Узел постройки по её состоянию.
func _rebuild(s: Dictionary) -> void:
	if s.get("node") != null:
		(s["node"] as Node3D).queue_free()
	var n: Node3D
	match String(s["type"]):
		"campfire":
			n = geo.campfire()
		"leanto":
			n = geo.lean_to()
		"tree_shelter":
			n = geo.tree_shelter()
		"snow_shelter":
			n = geo.snow_shelter()
		"cache":
			n = geo.cache()
		"chop_block":
			n = geo.chop_block()
		# --- colony: острог — амбар, землянка, стена, башня, сушило (colony_geo.gd) ---
		"storehouse", "dugout", "palisade", "tower", "rack":
			var stage_c := String(s.get("stage", "done"))
			var pr: float = 1.0 if stage_c == "done" else float(s.get("prog", 0.0))
			n = Node3D.new()
			var part: Node3D = COLGEO.make(geo, String(s["type"]), pr)
			if part != null:
				n.add_child(part)
			if stage_c != "done":
				n.add_child(geo.site_stock(s.get("have", {})))
		# --- /colony ---
		"cabin":
			n = Node3D.new()
			var gh := _cabin_gh(s)
			var stage: String = s["stage"]
			if stage == "site":
				n.add_child(geo.site_marks())
			if stage != "done":
				var left: Dictionary = s["have"]
				n.add_child(geo.site_stock(left))
			if stage == "building" or stage == "done":
				var p: float = s["prog"] if stage == "building" else 1.0
				var crowns := int(clampf(p / 0.75, 0.0, 1.0) * GEO.NC + 0.001)
				var roof := clampf((p - 0.75) / 0.25, 0.0, 1.0)
				var cb: Node3D = geo.cabin(crowns, roof, gh)
				cb.name = "cabin"
				n.add_child(cb)
				if stage == "done":
					_make_cabin_roof_snow(cb, s)
					var st: Node3D = geo.stove()
					st.name = "stove"
					n.add_child(st)
					var sm: GPUParticles3D = geo.smoke(0.7, 0.0)
					sm.name = "chimney"
					sm.position = GEO.chimney_top()
					n.add_child(sm)
	s["node"] = n
	add_child(n)
	n.position = s["pos"]
	n.rotation.y = s["yaw"]
	_refresh(s)
	if String(s["type"]) == "cabin" and String(s["stage"]) == "done" and cabin_ctl != null:
		cabin_ctl.furnish(s)

## Высоты земли под камнями избы (местные).
func _cabin_gh(s: Dictionary) -> Array:
	var out: Array = []
	var b := Basis(Vector3.UP, float(s["yaw"]))
	var p0: Vector3 = s["pos"]
	var hx := GEO.CW * 0.5
	var hz := GEO.CD * 0.5
	for v: Vector2 in [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(-hx, hz), Vector2(hx, hz), Vector2(0, -hz), Vector2(-hx, 0), Vector2(hx, 0)]:
		var w := p0 + b * Vector3(v.x, 0, v.y)
		out.append(main.height(w.x, w.z) - p0.y)
	return out

func _xf(s: Dictionary) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, float(s["yaw"])), s["pos"])

func _add_block(s: Dictionary, lp: Vector3, r: float) -> void:
	var w := _xf(s) * lp
	var v := Vector3(w.x, w.z, r)
	var k := Vector2i(floori(w.x / 8.0), floori(w.z / 8.0))
	if not main.blockers.has(k):
		main.blockers[k] = []
	main.blockers[k].append(v)
	s["blockers"].append([k, v])

func _add_seat(s: Dictionary, lp: Vector3, lyaw: float) -> void:
	var w := _xf(s) * lp
	var seat := [w, float(s["yaw"]) + lyaw]
	var k := Vector2i(floori(w.x / 8.0), floori(w.z / 8.0))
	if not main.seats.has(k):
		main.seats[k] = []
	main.seats[k].append(seat)
	s["seats"].append([k, seat])

func _add_solid(s: Dictionary, sd: Array) -> void:
	main._add_solid(sd)
	s["solids"].append(sd)

## Снять все столкновения постройки (перед перестройкой или разбором).
func _unregister(s: Dictionary) -> void:
	for e: Array in s["blockers"]:
		if main.blockers.has(e[0]):
			main.blockers[e[0]].erase(e[1])
	for e: Array in s["seats"]:
		if main.seats.has(e[0]):
			main.seats[e[0]].erase(e[1])
	for sd: Array in s["solids"]:
		for k in main.solids.keys():
			main.solids[k].erase(sd)
	s["blockers"] = []
	s["seats"] = []
	s["solids"] = []

func _register(s: Dictionary) -> void:
	_unregister(s)
	var p: Vector3 = s["pos"]
	match String(s["type"]):
		"campfire":
			_add_block(s, Vector3.ZERO, 0.45)
			var la := _xf(s) * Vector3(-0.75, 0.17, -1.35)
			var lb := _xf(s) * Vector3(0.8, 0.17, -1.32)
			_add_solid(s, [1, la, lb, 0.17, 0.0])
			_add_seat(s, Vector3(0, 0.36, -1.33), 0.0)
		"leanto":
			_add_block(s, Vector3(-1.25, 0, 0.75), 0.12)
			_add_block(s, Vector3(1.25, 0, 0.75), 0.12)
			for k in 5:
				_add_block(s, Vector3(-1.0 + k * 0.5, 0, -1.25), 0.2)
			_add_seat(s, Vector3(0, 0.4, -0.25), 0.0)
		"tree_shelter":
			_add_seat(s, Vector3(0, 0.4, 1.2), 0.0)
			for sx: float in [-1.0, 1.0]:
				for k in 4:
					_add_block(s, Vector3(sx * (1.0 - k * 0.15), 0, 0.8 + k * 0.75), 0.2)
		"snow_shelter":
			for k in 12:
				var a := TAU * (k + 0.5) / 12.0
				if absf(wrapf(a, -PI, PI)) < 0.45:
					continue
				_add_block(s, Vector3(sin(a) * 1.45, 0, cos(a) * 1.45), 0.3)
			_add_seat(s, Vector3(0, 0.42, -0.1), 0.0)
		"cache":
			_add_block(s, Vector3.ZERO, 0.6)
		"chop_block":
			_add_block(s, Vector3.ZERO, 0.32)
			_add_seat(s, Vector3(0, 0.36, 0.75), PI)
		# --- colony: столкновения построек острога ---
		"storehouse", "tower":
			var hh: float = 1.45 if String(s["type"]) == "storehouse" else 1.35
			var hd: float = 1.25 if String(s["type"]) == "storehouse" else 1.35
			var x2 := -hh
			while x2 <= hh + 0.01:
				_add_block(s, Vector3(x2, 0, -hd), 0.26)
				if absf(x2) > 0.5 or String(s["type"]) == "tower":
					_add_block(s, Vector3(x2, 0, hd), 0.26)
				x2 += 0.5
			var z2 := -hd
			while z2 <= hd + 0.01:
				_add_block(s, Vector3(-hh, 0, z2), 0.26)
				_add_block(s, Vector3(hh, 0, z2), 0.26)
				z2 += 0.5
		"dugout":
			for k in 7:
				_add_block(s, Vector3(-1.6 + k * 0.53, 0, 1.3), 0.26)
			for k in 5:
				_add_block(s, Vector3(-1.7, 0, -1.5 + k * 0.7), 0.3)
				_add_block(s, Vector3(1.7, 0, -1.5 + k * 0.7), 0.3)
			_add_seat(s, Vector3(0, 0.3, 0.2), 0.0)
		"palisade":
			for k in 9:
				_add_block(s, Vector3(-1.33 + k * 0.33, 0, 0.0), 0.22)
		"rack":
			_add_block(s, Vector3(-1.15, 0, 0), 0.12)
			_add_block(s, Vector3(1.15, 0, 0), 0.12)
		# --- /colony ---
		"cabin":
			if String(s["stage"]) == "done" or String(s["stage"]) == "building":
				var hx := GEO.CW * 0.5
				var hz := GEO.CD * 0.5
				var step := 0.45
				var x := -hx
				while x <= hx + 0.01:
					_add_block(s, Vector3(x, 0, -hz), 0.22)
					if absf(x) > GEO.DOOR.x + 0.05 or String(s["stage"]) != "done":
						_add_block(s, Vector3(x, 0, hz), 0.22)
					x += step
				var z := -hz
				while z <= hz + 0.01:
					_add_block(s, Vector3(-hx, 0, z), 0.22)
					_add_block(s, Vector3(hx, 0, z), 0.22)
					z += step
				if String(s["stage"]) == "done":
					# пол — набор низких цилиндров на высоте пола; крыльцо
					var fy: float = GEO.floor_y()
					for i in 3:
						for j in 3:
							var c := _xf(s) * Vector3(-1.2 + i * 1.2, 0, -1.35 + j * 1.35)
							_add_solid(s, [2, Vector3(c.x, p.y, c.z), Vector3.ZERO, 0.95, fy])
					var pc := _xf(s) * Vector3(0, 0, hz + 0.35)
					_add_solid(s, [2, Vector3(pc.x, p.y, pc.z), Vector3.ZERO, 0.5, fy - 0.04])
					cabin_ctl.register_furniture(s)

## Убрать мелкую растительность под постройкой: экземпляры MultiMesh (кроме деревьев и
## камней) сжимаются в ноль, траву под ней больше не сажаем; снег расчищаем.
func _clear_area(circles: Array, clear_snow: bool) -> void:
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for c: Vector3 in circles:
		_clear.append(c)
		lo = Vector2(minf(lo.x, c.x - c.z), minf(lo.y, c.y - c.z))
		hi = Vector2(maxf(hi.x, c.x + c.z), maxf(hi.y, c.y + c.z))
		if clear_snow and main.feet != null:
			main.feet.add_wear(c.x, c.y, c.z, 1.0, 0.9)
	var keep := {}
	for k in main.near_mmi:
		keep[main.near_mmi[k]] = true
	for m in main.cliff_mmi:
		keep[m] = true
	var aabb := AABB(Vector3(lo.x, -100, lo.y), Vector3(hi.x - lo.x, 300, hi.y - lo.y))
	var tree_mm := {}
	for gx in range(floori(lo.x / 16.0) - 1, floori(hi.x / 16.0) + 2):
		for gz in range(floori(lo.y / 16.0) - 1, floori(hi.y / 16.0) + 2):
			for rec: Array in main.tree_grid.get(Vector2i(gx, gz), []):
				tree_mm[rec[0]] = true
	for ch in main.get_children():
		if not (ch is MultiMeshInstance3D) or keep.has(ch):
			continue
		var mmi := ch as MultiMeshInstance3D
		var mm := mmi.multimesh
		if mm == null or tree_mm.has(mm) or mm.instance_count == 0:
			continue
		if not mm.get_aabb().intersects(aabb):
			continue
		# камни и крупное не трогаем: у них есть тень
		if mmi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			continue
		for i in mm.instance_count:
			var o := mm.get_instance_transform(i).origin
			for c: Vector3 in circles:
				if Vector2(o.x - c.x, o.z - c.y).length() < c.z:
					mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(0.001, 0.001, 0.001)), o - Vector3(0, 5, 0)))
					break
	# подбираемое под постройкой исчезает
	for k in main.pickables.keys():
		var arr: Array = main.pickables[k]
		for it in arr.duplicate():
			var q: Vector3 = it[0]
			for c: Vector3 in circles:
				if Vector2(q.x - c.x, q.z - c.y).length() < c.z:
					arr.erase(it)
					break
	# клетки травы перестроятся без травы под постройкой
	for k in main.grass_cells.keys():
		var x0: float = k.x * main.GCELL - main.SIZE * 0.5
		var z0: float = k.y * main.GCELL - main.SIZE * 0.5
		if hi.x >= x0 and lo.x <= x0 + main.GCELL and hi.y >= z0 and lo.y <= z0 + main.GCELL:
			main.grass_cells[k].queue_free()
			main.grass_cells.erase(k)

## Трава здесь не растёт (под постройкой).
func cleared(x: float, z: float) -> bool:
	for c: Vector3 in _clear:
		if absf(x - c.x) < c.z and absf(z - c.y) < c.z and Vector2(x - c.x, z - c.y).length() < c.z:
			return true
	return false

func remove(s: Dictionary) -> void:
	_unregister(s)
	if s.get("node") != null:
		(s["node"] as Node3D).queue_free()
	list.erase(s)

# ---------- состояние построек ----------

func _process(delta: float) -> void:
	if main == null or main.hero == null:
		return
	if _tdir != "":
		_run_test()
	var dh: float = delta / 75.0
	_step(dh, delta)
	_t -= delta
	if _t <= 0.0:
		_t = 0.25
		hidden = _hero_in("snow_shelter", true)

## Прожить dh игровых часов (dt — реальные секунды для анимации).
func _step(dh: float, dt: float) -> void:
	var w = main.weather
	_raid_step(dh)  # core
	for s: Dictionary in list.duplicate():
		var type: String = s["type"]
		if type == "campfire" or (type == "cabin" and String(s.get("stage", "")) == "done"):
			_burn(s, dh)
			_cook_step(s, dh)
		if type == "cabin":
			_build_step(s, dh)
			cabin_ctl.rack_step(s, dh)
		var d: Dictionary = DEFS[type]
		if d.has("decay"):
			var rate: float = d["decay"]
			if type == "snow_shelter":
				rate += maxf(float(w.temp) - 0.5, 0.0) * 0.02
			elif float(w.precip) > 0.3:
				rate *= 1.5
			s["dur"] = float(s["dur"]) - rate * dh
			if float(s["dur"]) <= 0.0:
				main._say("%s развалился" % String(d["name"]) if type != "snow_shelter" else "Снежная пещера растаяла")
				# вещи из хранилища остаются лежать на земле
				var hunt = main.get("hunt")
				if hunt != null and hunt.has_method("drop_item"):
					for id: String in s["store"]:
						for i in mini(int(s["store"][id]), 20):
							hunt.drop_item(id, (s["pos"] as Vector3) + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6)))
				remove(s)
				continue
		if dt > 0.0:
			_animate(s, dt)

func _burn(s: Dictionary, dh: float) -> void:
	var key_f := "fuel" if s["type"] == "campfire" else "stove_fuel"
	var key_l := "lit" if s["type"] == "campfire" else "stove_lit"
	if not bool(s[key_l]):
		return
	var rain: float = main.weather.precip if float(main.weather.temp) > 0.5 else 0.0
	var rate := 1.0 + (rain * 1.5 if s["type"] == "campfire" else 0.0)
	s[key_f] = maxf(0.0, float(s[key_f]) - dh * rate)
	if float(s[key_f]) <= 0.0:
		s[key_l] = false
		main._say("Костёр прогорел" if s["type"] == "campfire" else "Печь остыла")
		_refresh(s)

## Сила огня 0..1.
func power(s: Dictionary) -> float:
	if s["type"] == "campfire":
		return clampf(float(s["fuel"]) / 1.5, 0.15, 1.0) if bool(s["lit"]) else 0.0
	return clampf(float(s["stove_fuel"]) / 1.5, 0.2, 1.0) if bool(s.get("stove_lit", false)) else 0.0

## Мерцание пламени и света, видимость дров и дыма.
func _animate(s: Dictionary, _dt: float) -> void:
	var n: Node3D = s.get("node")
	if n == null:
		return
	var t := Time.get_ticks_msec() * 0.001
	var pw := power(s)
	var night: float = 1.0 - float(main.day_factor) * 0.7
	if s["type"] == "campfire":
		var lt: OmniLight3D = n.get_node_or_null("light")
		if lt != null:
			lt.light_energy = pw * (1.4 + 0.35 * sin(t * 13.0) + 0.25 * sin(t * 7.3)) * night
	elif String(s.get("stage", "")) == "done":
		if s["type"] == "cabin":
			_update_cabin_roof_snow(s, _dt)
		var st: Node3D = n.get_node_or_null("stove")
		if st != null:
			var lt2: OmniLight3D = st.get_node_or_null("light")
			if lt2 != null:
				lt2.light_energy = pw * (1.2 + 0.2 * sin(t * 9.0))

## Обновить видимые части после смены состояния.
func _refresh(s: Dictionary) -> void:
	var n: Node3D = s.get("node")
	if n == null:
		return
	if s["type"] == "campfire":
		var lit: bool = s["lit"]
		var fuel: float = s["fuel"]
		n.get_node("flames").visible = lit
		n.get_node("light").visible = lit
		(n.get_node("smoke") as GPUParticles3D).emitting = lit
		n.get_node("wood_full").visible = fuel > 0.8
		n.get_node("wood_low").visible = fuel > 0.0 and fuel <= 0.8
		(geo.mats["ember"] as ShaderMaterial).set_shader_parameter("glow", 1.0 if lit else 0.15)
		(geo.mats["flame"] as ShaderMaterial).set_shader_parameter("power", power(s))
		n.get_node("flames").scale = Vector3.ONE * lerpf(0.55, 1.0, power(s))
		var old := n.get_node_or_null("food")
		if old != null:
			old.free()
		var ck: Dictionary = s["cook"]
		if not ck.is_empty():
			var f: Node3D = geo.spit_food(String(ck["in"]), clampf(float(ck["t"]) / float(ck["need"]), 0.0, 1.0))
			f.name = "food"
			n.add_child(f)
	elif s["type"] == "cabin" and String(s.get("stage", "")) == "done":
		var st: Node3D = n.get_node_or_null("stove")
		if st != null:
			var lit2: bool = s["stove_lit"]
			st.get_node("mouth_fire").visible = lit2
			st.get_node("light").visible = lit2
			(n.get_node("chimney") as GPUParticles3D).emitting = lit2

# Snow on the cabin roof: accumulation, melt, slide-off and eave drifts.
const ROOF_SNOW_MAX := 0.24
const ROOF_SNOW_TICK := 0.45

func _snow_material() -> StandardMaterial3D:
	if _roof_snow_material != null:
		return _roof_snow_material
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.82, 0.88, 0.96)
	m.roughness = 0.96
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	_roof_snow_material = m
	return m

func _make_cabin_roof_snow(cabin_node: Node3D, s: Dictionary) -> void:
	if cabin_node == null or cabin_node.get_node_or_null("roof_snow") != null:
		return
	var holder := Node3D.new()
	holder.name = "roof_snow"
	holder.set_meta("cut", true)
	cabin_node.add_child(holder)
	var sheet := MeshInstance3D.new()
	sheet.name = "snow_sheet"
	sheet.mesh = _roof_snow_mesh(float(s.get("roof_snow", 0.0)))
	sheet.material_override = _snow_material()
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	sheet.set_meta("cut", true)
	holder.add_child(sheet)
	var piles: Array[MeshInstance3D] = []
	var emitters: Array[GPUParticles3D] = []
	var hx := GEO.CW * 0.5
	var eave_x := hx + GEO.EAVE
	var eave_y := GEO.top_y() + GEO.LR + 0.12
	for side in [-1.0, 1.0]:
		var pile := MeshInstance3D.new()
		pile.name = "eave_drift_left" if side < 0.0 else "eave_drift_right"
		var sphere := SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 2.0
		sphere.radial_segments = 12
		sphere.rings = 6
		pile.mesh = sphere
		pile.material_override = _snow_material()
		pile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pile.visible = false
		pile.set_meta("cut", true)
		holder.add_child(pile)
		piles.append(pile)
		var burst := GPUParticles3D.new()
		burst.name = "roof_slide_snow_left" if side < 0.0 else "roof_slide_snow_right"
		burst.amount = 140
		burst.lifetime = 1.35
		burst.one_shot = true
		burst.emitting = false
		burst.local_coords = true
		burst.explosiveness = 0.92
		burst.position = Vector3(side * eave_x, eave_y, 0.0)
		burst.visibility_aabb = AABB(Vector3(-3.0, -3.0, -5.0), Vector3(6.0, 6.0, 10.0))
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(0.16, 0.08, 2.0)
		pm.direction = Vector3(side * 0.65, -1.0, 0.0)
		pm.spread = 42.0
		pm.initial_velocity_min = 1.4
		pm.initial_velocity_max = 3.8
		pm.gravity = Vector3(0.0, -5.8, 0.0)
		pm.scale_min = 0.55
		pm.scale_max = 1.5
		pm.damping_min = 0.25
		pm.damping_max = 0.7
		burst.process_material = pm
		var chunk_mesh := SphereMesh.new()
		chunk_mesh.radius = 0.07
		chunk_mesh.height = 0.12
		chunk_mesh.radial_segments = 6
		chunk_mesh.rings = 3
		burst.draw_pass_1 = chunk_mesh
		var chunk_mat := StandardMaterial3D.new()
		chunk_mat.albedo_color = Color(0.9, 0.94, 1.0)
		chunk_mat.roughness = 1.0
		chunk_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		burst.material_override = chunk_mat
		burst.set_meta("cut", true)
		holder.add_child(burst)
		emitters.append(burst)
	s["_roof_snow_nodes"] = {"sheet": sheet, "piles": piles, "emitters": emitters}
	s["_roof_snow_tick"] = 0.0
	s["_roof_snow_mesh_depth"] = -1.0
	s["_roof_snow_rng"] = RandomNumberGenerator.new()
	s["_roof_snow_rng"].seed = int(s["pos"].x * 173 + s["pos"].z * 311 + int(s["yaw"] * 1000.0)) + int(main.map_seed)
	_update_roof_snow_mesh(s)

func _roof_snow_mesh(depth: float) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx := GEO.CW * 0.5
	var hz := GEO.CD * 0.5 + 0.55
	var edge := hx + GEO.EAVE
	var pitch := GEO.ROOF_H / edge
	var ridge_y := GEO.top_y() + GEO.LR + GEO.ROOF_H
	var nx := 14
	var nz := 24
	var lift := 0.025 + clampf(depth, 0.0, ROOF_SNOW_MAX) * 0.72
	for side in [-1.0, 1.0]:
		var normal := Vector3(side * pitch, 1.0, 0.0).normalized()
		for ix in nx:
			for iz in nz:
				var u0 := float(ix) / nx
				var u1 := float(ix + 1) / nx
				var v0 := float(iz) / nz
				var v1 := float(iz + 1) / nz
				var x0: float = side * edge * u0
				var x1: float = side * edge * u1
				var y0 := ridge_y - edge * u0 * pitch
				var y1 := ridge_y - edge * u1 * pitch
				var z0 := -hz + hz * 2.0 * v0
				var z1 := -hz + hz * 2.0 * v1
				var wobble := 0.008 * sin(float(ix) * 1.7 + float(iz) * 0.61 + side) + 0.005 * cos(float(iz) * 0.37)
				var d := maxf(0.0, lift + wobble)
				var a := Vector3(x0, y0, z0) + normal * d
				var b := Vector3(x1, y1, z0) + normal * d
				var c := Vector3(x1, y1, z1) + normal * d
				var q := Vector3(x0, y0, z1) + normal * d
				var tint := 0.94 + 0.06 * sin(float(ix * 3 + iz) * 0.45)
				var snow_color := Color(tint * 0.91, tint * 0.96, tint, 1.0)
				for vtx in [a, c, b, a, q, c]:
					st.set_normal(normal)
					st.set_color(snow_color)
					st.add_vertex(vtx)
	st.commit(mesh)
	if mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, _snow_material())
	return mesh

func _update_roof_snow_mesh(s: Dictionary) -> void:
	var nodes: Dictionary = s.get("_roof_snow_nodes", {})
	var sheet: MeshInstance3D = nodes.get("sheet")
	if sheet == null or not is_instance_valid(sheet):
		return
	var amount := float(s.get("roof_snow", 0.0))
	if absf(amount - float(s.get("_roof_snow_mesh_depth", -1.0))) < 0.003 and sheet.mesh != null:
		return
	sheet.mesh = _roof_snow_mesh(amount)
	sheet.visible = amount > 0.018
	s["_roof_snow_mesh_depth"] = amount

func _update_cabin_roof_snow(s: Dictionary, dt: float) -> void:
	if dt <= 0.0:
		return
	s["_roof_snow_tick"] = float(s.get("_roof_snow_tick", 0.0)) + dt
	if float(s["_roof_snow_tick"]) < ROOF_SNOW_TICK:
		return
	var step_dt := minf(float(s["_roof_snow_tick"]), 2.0)
	s["_roof_snow_tick"] = 0.0
	var w = main.weather
	var depth := clampf(float(s.get("roof_snow", 0.0)), 0.0, ROOF_SNOW_MAX)
	var piles: Array = s.get("snow_piles", [0.0, 0.0])
	if piles.size() < 2:
		piles = [0.0, 0.0]
	var snowfall := float(w.precip) if float(w.temp) <= 0.5 else 0.0
	var rain := float(w.precip) if float(w.temp) > 0.5 else 0.0
	var game_hours := step_dt / 75.0
	depth += snowfall * game_hours * 0.22 * (1.0 - clampf(float(w.wind) * 0.12, 0.0, 0.45))
	depth -= rain * game_hours * 0.16
	depth -= maxf(float(w.temp), 0.0) * game_hours * 0.012
	depth -= float(w.wind) * game_hours * 0.008
	if bool(s.get("stove_lit", false)):
		depth -= 0.018 * game_hours
	depth = clampf(depth, 0.0, ROOF_SNOW_MAX)
	var rng: RandomNumberGenerator = s.get("_roof_snow_rng")
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.seed = int(main.map_seed) + int(s["pos"].x * 137 + s["pos"].z * 271)
		s["_roof_snow_rng"] = rng
	var slide_chance := clampf((float(w.wind) * 0.15 + maxf(float(w.temp) + 2.0, 0.0) * 0.04) * game_hours, 0.0, 0.4)
	if depth > 0.105 and rng.randf() < slide_chance:
		var shed := depth * rng.randf_range(0.38, 0.68)
		depth -= shed
		var drift_gain := shed * 0.65
		piles[0] = minf(1.2, float(piles[0]) + drift_gain)
		piles[1] = minf(1.2, float(piles[1]) + drift_gain)
		var nodes: Dictionary = s.get("_roof_snow_nodes", {})
		var emitters: Array = nodes.get("emitters", [])
		for emitter in emitters:
			if emitter is GPUParticles3D and is_instance_valid(emitter):
				emitter.restart()
				emitter.emitting = true
		var distance := Vector2(main.rig.position.x - float(s["pos"].x), main.rig.position.z - float(s["pos"].z)).length() if main.rig != null else 999.0
		if distance < 45.0:
			main._say("Снег соскользнул с крыши избы")
	var pile_melt := (rain * 0.09 + maxf(float(w.temp), 0.0) * 0.006) * game_hours
	piles[0] = maxf(0.0, float(piles[0]) - pile_melt)
	piles[1] = maxf(0.0, float(piles[1]) - pile_melt)
	s["roof_snow"] = depth
	s["snow_piles"] = piles
	var nodes2: Dictionary = s.get("_roof_snow_nodes", {})
	var pile_nodes: Array = nodes2.get("piles", [])
	var edge := GEO.CW * 0.5 + GEO.EAVE + 0.35
	for idx in mini(pile_nodes.size(), 2):
		var side := -1.0 if idx == 0 else 1.0
		var local_eave := Vector3(side * edge, 0.0, 0.0)
		var world_eave: Vector3 = _xf(s) * local_eave
		var pile: MeshInstance3D = pile_nodes[idx]
		pile.position = Vector3(local_eave.x, main.height(world_eave.x, world_eave.z) - float(s["pos"].y) + 0.03, local_eave.z)
		var mound := float(piles[idx])
		pile.visible = mound > 0.02
		pile.scale = Vector3(0.24 + mound * 0.22, 0.025 + mound * 0.23, 0.38 + mound * 0.4)
	_update_roof_snow_mesh(s)

# ---------- огонь и готовка ----------

const FUEL := {"firewood": 1.5, "twig": 0.4, "bark": 0.2, "branch": 0.8}
const FUEL_MAX := 6.0

func add_fuel(s: Dictionary) -> void:
	var key := "fuel" if s["type"] == "campfire" else "stove_fuel"
	for id: String in ["firewood", "branch", "twig", "bark"]:
		if count(id) > 0 and float(s[key]) < FUEL_MAX - 0.1:
			take(id, 1)
			s[key] = minf(FUEL_MAX, float(s[key]) + float(FUEL[id]))
			main._say("В огонь: %s" % IT.name_of(id).to_lower())
			_refresh(s)
			return
	main._say("Нечего подбросить: нужны дрова или хворост")

func light(s: Dictionary) -> void:
	var key_f := "fuel" if s["type"] == "campfire" else "stove_fuel"
	var key_l := "lit" if s["type"] == "campfire" else "stove_lit"
	if float(s[key_f]) <= 0.0:
		add_fuel(s)
		if float(s[key_f]) <= 0.0:
			return
	if float(main.weather.precip) > 0.6 and float(main.weather.temp) > 0.5 and s["type"] == "campfire":
		main._say("Ливень — не разжечь")
		return
	# растопка: береста или хворост
	if count("bark") > 0:
		take("bark", 1)
	elif count("twig") > 0:
		take("twig", 1)
	else:
		main._say("Нужна растопка: береста или хворост")
		return
	s[key_l] = true
	main._say("Огонь разгорелся")
	_refresh(s)

func put_out(s: Dictionary) -> void:
	if s["type"] == "campfire":
		s["lit"] = false
	else:
		s["stove_lit"] = false
	_refresh(s)

## Рецепты, которые можно готовить на огне: [выход, вход].
func fire_recipes() -> Array:
	var out: Array = []
	for id: String in IT.DEF:
		var d: Dictionary = IT.DEF[id]
		if String(d.get("station", "")) == "fire" and d.has("craft"):
			var c: Dictionary = d["craft"]
			if c.size() == 1:
				out.append([id, c.keys()[0]])
	return out

func start_cook(s: Dictionary, out_id: String, in_id: String) -> void:
	if not (s["cook"] as Dictionary).is_empty():
		main._say("Вертел занят")
		return
	if count(in_id) <= 0:
		return
	take(in_id, 1)
	var need := 0.6 if in_id != "hide" else 2.0
	s["cook"] = {"in": in_id, "out": out_id, "t": 0.0, "need": need, "done": false}
	# запах жарева привлекает хищников (API команды охоты, если есть)
	if main.animals != null and main.animals.has_method("add_scent"):
		main.animals.add_scent(s["pos"], 1.0, 300.0)
	main._say("Готовится: %s" % IT.name_of(out_id).to_lower())
	_refresh(s)

func _cook_step(s: Dictionary, dh: float) -> void:
	var ck: Dictionary = s["cook"]
	if ck.is_empty() or bool(ck["done"]):
		return
	if power(s) <= 0.0:
		return
	var was := floori(float(ck["t"]) / float(ck["need"]) * 4.0)
	ck["t"] = float(ck["t"]) + dh
	if floori(float(ck["t"]) / float(ck["need"]) * 4.0) != was:
		_refresh(s)
	if float(ck["t"]) >= float(ck["need"]):
		ck["done"] = true
		main._say("Готово: %s" % IT.name_of(String(ck["out"])).to_lower())
		_refresh(s)

func take_cooked(s: Dictionary) -> void:
	var ck: Dictionary = s["cook"]
	if ck.is_empty():
		return
	var id := String(ck["out"]) if bool(ck["done"]) else String(ck["in"])
	if not can_carry(id):
		main._say("Короб полон")
		return
	give(id, 1)
	main._say("Снял с огня: %s" % IT.name_of(id).to_lower())
	s["cook"] = {}
	_refresh(s)

## Доля готовности на вертеле (для интерфейса).
func cook_k(s: Dictionary) -> float:
	var ck: Dictionary = s["cook"]
	if ck.is_empty():
		return 0.0
	return clampf(float(ck["t"]) / float(ck["need"]), 0.0, 1.0)

# ---------- изба: стройка ----------

## Что нужно стройке (любой тип: изба, амбар, башня …), а не только брёвна избы.
func need_of(s: Dictionary) -> Dictionary:
	var vs: Array = VARIANTS.get(String(s["type"]), [])
	var vi := int(s.get("var", 0))
	if not vs.is_empty() and vi >= 0 and vi < vs.size():
		return (vs[vi] as Dictionary)["need"]
	return DEFS.get(String(s["type"]), {}).get("need", {})

## Положить в стройку id в количестве n (не больше, чем нужно). Возвращает, сколько легло.
## Подходит любой нужный ресурс: брёвна, доски, мох, глина, камень …
func deposit_item(s: Dictionary, id: String, n: int) -> int:
	var need: Dictionary = need_of(s)
	if not need.has(id) or n <= 0:
		return 0
	var have: Dictionary = s["have"]
	var k := mini(n, int(need[id]) - int(have.get(id, 0)))
	if k <= 0:
		return 0
	have[id] = int(have.get(id, 0)) + k
	_rebuild(s)
	return k

func deposit(s: Dictionary) -> void:
	var need: Dictionary = need_of(s)
	var have: Dictionary = s["have"]
	var moved := 0
	# брёвна, лежащие у стройки (принесённые на плече), — сразу в сруб
	if main.tools_world != null and need.has("log"):
		for it: Dictionary in main.tools_world.logs_near(s["pos"], 8.0):
			if int(have.get("log", 0)) >= int(need["log"]):
				break
			if main.tools_world.take_item(it):
				have["log"] = int(have.get("log", 0)) + 1
				moved += 1
	for id: String in need:
		var want := int(need[id]) - int(have.get(id, 0))
		var n := mini(want, count(id))
		if n > 0:
			take(id, n)
			have[id] = int(have.get(id, 0)) + n
			moved += n
	if moved > 0:
		main._say("Сложено на стройке: %d" % moved)
		_rebuild(s)
	else:
		main._say("Нечего вносить")

func site_ready(s: Dictionary) -> bool:
	if main != null and bool(main.get("creative_mode")):
		return true
	var need: Dictionary = need_of(s)
	for id: String in need:
		if int((s["have"] as Dictionary).get(id, 0)) < int(need[id]):
			return false
	return true

func start_building(s: Dictionary) -> void:
	if not site_ready(s):
		return
	if main != null and bool(main.get("creative_mode")):
		s["stage"] = "done"
		s["prog"] = 1.0
		s["have"] = {}
		s["_shown"] = 40
		_register(s)
		_rebuild(s)
		main._say("Постройка возведена мгновенно")
		return
	s["stage"] = "building"
	s["prog"] = 0.0
	s["_shown"] = -1
	main._say("Стройка началась: венец за венцом")
	_register(s)
	_rebuild(s)

## Изба растёт, пока герой рядом (в 20 м): ~3 игровых часа на сруб и кровлю.
func _build_step(s: Dictionary, dh: float) -> void:
	if String(s["stage"]) != "building":
		return
	# --- colony: стройку ведёт строитель отряда (colony.build_progress) ---
	if main.get("colony") != null and main.colony != null:
		return
	# --- /colony ---
	var hp: Vector3 = main.hero.position
	if Vector2(hp.x - s["pos"].x, hp.z - s["pos"].z).length() > 20.0:
		return
	s["prog"] = minf(1.0, float(s["prog"]) + dh / 3.0)
	var p: float = s["prog"]
	var have: Dictionary = s["have"]
	var need: Dictionary = need_of(s)
	# припасы убывают со стройкой
	for id: String in need:
		have[id] = int(round(float(need[id]) * (1.0 - p)))
	var shown := int(p * 40.0)
	if shown != int(s.get("_shown", -1)):
		s["_shown"] = shown
		if p >= 1.0:
			s["stage"] = "done"
			main._say("Изба готова! Затопите печь")
			_register(s)
		_rebuild(s)

## Сколько процентов стройки.
func build_k(s: Dictionary) -> float:
	return float(s.get("prog", 0.0))

# ---------- хранилища ----------

func store_weight(s: Dictionary) -> float:
	var w := 0.0
	var st: Dictionary = s["store"]
	for k: String in st:
		w += IT.weight_of(k) * int(st[k])
	return w

func store_cap(s: Dictionary) -> float:
	var c: float = s["cap"]
	if s["type"] == "cabin":
		c += cabin_ctl.extra_cap(s)
	return c

func to_store(s: Dictionary, id: String, n: int) -> void:
	var st: Dictionary = s["store"]
	var moved := 0
	for i in n:
		if count(id) <= 0 or store_weight(s) + IT.weight_of(id) > store_cap(s) + 0.001:
			break
		take(id, 1)
		st[id] = int(st.get(id, 0)) + 1
		moved += 1
	if moved == 0 and count(id) > 0:
		main._say("Хранилище полно")

func from_store(s: Dictionary, id: String, n: int) -> void:
	var st: Dictionary = s["store"]
	for i in n:
		if int(st.get(id, 0)) <= 0:
			break
		if not can_carry(id):
			main._say("Короб полон")
			break
		st[id] = int(st[id]) - 1
		if int(st[id]) <= 0:
			st.erase(id)
		give(id, 1)

# ---------- тепло, ветер, укрытие ----------

## Герой внутри постройки данного типа (sitting — только сидя).
func _hero_in(type: String, sitting: bool) -> bool:
	var hp: Vector3 = main.hero.position
	for s: Dictionary in list:
		if s["type"] != type:
			continue
		var lp: Vector3 = _xf(s).affine_inverse() * hp
		match type:
			"snow_shelter":
				if Vector2(lp.x, lp.z).length() < 1.2 and (not sitting or main.hero.state == "sit"):
					return true
			"leanto":
				if absf(lp.x) < 1.3 and lp.z > -1.3 and lp.z < 0.8:
					return true
			"tree_shelter":
				if absf(lp.x) < 1.0 and lp.z > 0.3 and lp.z < 3.2:
					return true
			"cabin":
				var ih: Vector2 = GEO.inner_half()
				if String(s["stage"]) == "done" and absf(lp.x) < ih.x and absf(lp.z) < ih.y:
					return true
	return false

func _cabin_at_hero() -> Dictionary:
	var hp: Vector3 = main.hero.position
	for s: Dictionary in list:
		if s["type"] == "cabin" and String(s["stage"]) == "done":
			var lp: Vector3 = _xf(s).affine_inverse() * hp
			var ih: Vector2 = GEO.inner_half()
			if absf(lp.x) < ih.x and absf(lp.z) < ih.y:
				return s
	return {}

## Прибавка к целевому теплу героя.
func warm_bonus() -> float:
	var b := 0.0
	var hp: Vector3 = main.hero.position
	for s: Dictionary in list:
		if s["type"] == "campfire" and bool(s["lit"]):
			var d := Vector2(hp.x - s["pos"].x, hp.z - s["pos"].z).length()
			b = maxf(b, 0.32 * power(s) * (1.0 - smoothstep(1.0, 4.5, d)))
	for type: String in ["leanto", "tree_shelter", "snow_shelter"]:
		if _hero_in(type, type == "snow_shelter"):
			b += float(DEFS[type]["warm"])
	var cb := _cabin_at_hero()
	if not cb.is_empty():
		b += 0.12 + 0.5 * power(cb)
	return b

## Множитель ветра для героя (1 — открыто, 0 — полное укрытие).
func wind_k() -> float:
	var k := 1.0
	for type: String in ["leanto", "tree_shelter", "snow_shelter"]:
		if _hero_in(type, type == "snow_shelter"):
			k = minf(k, float(DEFS[type]["wind"]))
	if not _cabin_at_hero().is_empty():
		k = 0.0
	return k

# ---------- сон ----------

## Поспать: до утра, если ночь, иначе три часа. quality — 0..1 (кровать в тёплой избе — 1).
func sleep(quality: float) -> void:
	var h: float = main.t_hours
	var hours := 3.0
	if h >= 19.0 or h < 6.0:
		hours = fposmod(7.0 - h, 24.0)
	main.weather.fast_forward(hours)
	advance(hours)
	main.stamina = 1.0
	main.hunger = maxf(0.0, float(main.hunger) - 0.02 * hours)
	main.thirst = maxf(0.0, float(main.thirst) - 0.025 * hours)
	main.health = minf(1.0, float(main.health) + 0.015 * hours * quality)
	main.warmth = clampf(float(main.warmth) + 0.2 * quality - 0.1, 0.05, 1.0)
	if ui != null:
		ui.fade_night()
	main._say("Проспал %d ч%s" % [int(round(hours)), "" if quality > 0.6 else " — сон беспокойный, холодно"])

func advance(hours: float) -> void:
	var left := hours
	while left > 0.0:
		var dh := minf(0.25, left)
		_step(dh, 0.0)
		left -= dh

func sleep_quality(s: Dictionary) -> float:
	match String(s["type"]):
		"cabin":
			return 0.55 + 0.45 * (1.0 if bool(s.get("stove_lit", false)) else 0.0)
		"snow_shelter":
			return 0.6
		_:
			return 0.4 + (0.3 if bool(main.weather.temp > 5.0) else 0.0)

# ---------- лопата ----------

func dig_snow() -> void:
	var hero: Node3D = main.hero
	var fwd := Vector3(sin(hero.body.rotation.y), 0, cos(hero.body.rotation.y))
	var p: Vector3 = hero.position + fwd * 0.9
	main.feet.add_wear(p.x, p.z, 1.0, 0.45, 1.0)
	hero.land_t = 0.9
	hero.land_k = 0.9
	main.stamina = maxf(0.0, float(main.stamina) - 0.04)

func snow_here() -> float:
	var hp: Vector3 = main.hero.position
	return main.feet.snow_depth(hp.x, hp.z) if main.feet != null else 0.0

# ---------- действия рядом с героем ----------

func nearest(max_d: float) -> Dictionary:
	var hp: Vector3 = main.hero.position
	var best: Dictionary = {}
	var bd := max_d
	for s: Dictionary in list:
		var lp: Vector3 = _xf(s).affine_inverse() * hp
		var d: float
		match String(s["type"]):
			"cabin":
				d = maxf(0.0, maxf(absf(lp.x) - 2.6, absf(lp.z) - 2.8))
			"tree_shelter":
				d = Vector2(lp.x, lp.z - 1.8).length() - 1.6
			"campfire":
				d = Vector2(lp.x, lp.z).length() - 0.7
			_:
				d = Vector2(lp.x, lp.z).length() - 1.5
		if d < bd:
			bd = d
			best = s
	return best

## Кнопки действий: [[подпись, Callable], ...].
func actions() -> Array:
	var out: Array = []
	var hero: Node3D = main.hero
	if hero.state == "dead" or build.active:
		return out
	if cabin_ctl.inside:
		return cabin_ctl.actions()
	var s := nearest(1.6)
	if not s.is_empty():
		match String(s["type"]):
			"campfire":
				var ck: Dictionary = s["cook"]
				if not ck.is_empty() and bool(ck["done"]):
					out.append(["Снять: " + IT.name_of(String(ck["out"])).to_lower(), take_cooked.bind(s)])
				if bool(s["lit"]):
					out.append(["Готовить", func(): ui.open_cook(s)])
					out.append(["Подбросить дров", add_fuel.bind(s)])
				else:
					out.append(["Разжечь", light.bind(s)])
					if float(s["fuel"]) < FUEL_MAX - 0.5:
						out.append(["Положить дрова", add_fuel.bind(s)])
			"cache":
				out.append(["Схрон", func(): ui.open_store(s)])
			"chop_block":
				if _logs_here().size() > 0 and _has_axe():
					out.append(["Тесать доски (бревно → 3)", hew_planks])
				out.append(["Ремесло: утварь", _open_craft])
			"leanto", "tree_shelter", "snow_shelter":
				if s["type"] == "snow_shelter" and hero.state != "sit":
					out.append(["Залезть внутрь", func(): _enter_snow(s)])
				out.append(["Хранилище", func(): ui.open_store(s)])
				out.append(["Спать", func(): sleep(sleep_quality(s))])
				if float(s["dur"]) < 0.7 and s["type"] != "snow_shelter":
					out.append(["Починить (лапник 2)", func(): _repair(s)])
			"cabin":
				match String(s["stage"]):
					"site":
						if _held_log() and int((s["have"] as Dictionary).get("log", 0)) < int(need_of(s).get("log", 0)):
							out.append(["Положить бревно на стройку", func(): deposit_held_log(s)])
						out.append(["Стройка избы", func(): ui.open_site(s)])
					"building":
						pass
					"done":
						if _near_door(s):
							out.append(["Войти", func(): cabin_ctl.enter(s)])
	# --- core: доски из бревна топором где угодно (у колоды — тоже) ---
	if (s.is_empty() or String(s["type"]) != "chop_block") and _has_axe() and hero.state == "walk" and (_logs_here().size() > 0 or _held_log()):
		out.append(["Тесать доски (бревно → 2)", hew_planks])
	# --- /core ---
	if out.size() < 3 and has_shovel() and snow_here() > 0.06 and hero.state == "walk":
		out.append(["Расчистить снег", dig_snow])
	return out

# --- core: доски, разорение хранилищ ---

func _has_axe() -> bool:
	var t = main.hero.get("tools")
	if t != null and String(t.held) == "axe":
		return true
	return main.hero.has_method("has_tool") and bool(main.hero.has_tool("axe"))

func _logs_here() -> Array:
	if main.tools_world == null:
		return []
	return main.tools_world.logs_near(main.hero.position, 2.0)

func _open_craft() -> void:
	if main.inventory != null:
		main.inventory.tab = 1
		main.inventory.open()

## Тесать доски из бревна (с земли или с плеча): у колоды 3 доски, без неё — 2.
func hew_planks() -> void:
	var at_block := false
	var s := nearest(1.6)
	if not s.is_empty() and String(s["type"]) == "chop_block":
		at_block = true
	if _held_log():
		var t: Node = main.hero.tools
		t.held = ""
		t._refresh()
	else:
		var logs := _logs_here()
		if logs.is_empty() or not main.tools_world.take_item(logs[0]):
			return
	var n := 3 if at_block else 2
	main.stamina = maxf(0.0, float(main.stamina) - 0.15)
	main.hero.land_t = 1.2
	main.hero.land_k = 1.0
	if main.sfx != null:
		main.sfx.play_at("chop", main.hero.position, 0.0, 1.05)
	var got := 0
	for i in n:
		if not can_carry("plank"):
			break
		give("plank", 1)
		got += 1
	# что не влезло — доски кладём рядом
	var hunt = main.get("hunt")
	for i in n - got:
		if hunt != null:
			hunt.drop_item("plank", main.hero.position + Vector3(0.6, 0, 0.3 * i))
	main._say("Вытесано досок: %d" % n)

## Звери разоряют хранилища с едой: ночью росомаха, лиса или медведь (летом) могут утащить
## часть съестного. Схрон почти не разоряют, избу — никогда. Шанс — за игровой час.
const RAID_CHANCE := {"leanto": 0.05, "tree_shelter": 0.04, "snow_shelter": 0.02, "cache": 0.004}
var _raid_acc := 0.0

func _raid_step(dh: float) -> void:
	_raid_acc += dh
	if _raid_acc < 1.0:
		return
	_raid_acc -= 1.0
	var h: float = main.t_hours
	if h > 6.0 and h < 20.0:
		return
	var hp: Vector3 = main.hero.position
	for s: Dictionary in list:
		var ch: float = float(RAID_CHANCE.get(String(s["type"]), 0.0))
		if ch <= 0.0 or Vector2(hp.x - s["pos"].x, hp.z - s["pos"].z).length() < 12.0:
			continue
		var st: Dictionary = s["store"]
		var food: Array = []
		for id: String in st:
			if IT.DEF.get(id, {}).has("eat") or id == "carcass_small":
				food.append(id)
		if food.is_empty() or randf() > ch:
			continue
		var lost := 0
		for id: String in food:
			var n := int(ceil(int(st[id]) * 0.5))
			st[id] = int(st[id]) - n
			lost += n
			if int(st[id]) <= 0:
				st.erase(id)
		main._say("Зверь разорил %s: пропало съестного %d" % [String(DEFS[s["type"]]["name"]).to_lower(), lost])
# --- /core ---

func _held_log() -> bool:
	var t = main.hero.get("tools")
	return t != null and String(t.held) == "log"

## Бревно с плеча — прямо в сруб.
func deposit_held_log(s: Dictionary) -> void:
	if not _held_log():
		return
	var t: Node = main.hero.tools
	t.held = ""
	t._refresh()
	if deposit_item(s, "log", 1) > 0:
		main._say("Бревно на стройке: %d из %d" % [int((s["have"] as Dictionary)["log"]), int(need_of(s).get("log", 0))])

func _near_door(s: Dictionary) -> bool:
	var lp: Vector3 = _xf(s).affine_inverse() * main.hero.position
	return absf(lp.x) < 1.3 and lp.z > GEO.CD * 0.5 - 0.2 and lp.z < GEO.CD * 0.5 + 2.2

func _enter_snow(s: Dictionary) -> void:
	var hero: Node3D = main.hero
	var seat: Vector3 = _xf(s) * Vector3(0, 0.42, -0.1)
	hero.seat = [seat, float(s["yaw"])]
	hero.stand_pos = _xf(s) * Vector3(0, 0, 2.2)
	hero.stand_pos.y = main.height(hero.stand_pos.x, hero.stand_pos.z)
	hero.state = "sit"
	hero.vel = Vector3.ZERO
	main._say("В пещере тихо и тепло")

func _repair(s: Dictionary) -> void:
	if count("spruce_twigs") < 2:
		main._say("Нужно 2 лапника")
		return
	take("spruce_twigs", 2)
	s["dur"] = 1.0
	main._say("Починил")

## Прочность в процентах для подписи.
func dur_text(s: Dictionary) -> String:
	return "прочность %d%%" % int(round(float(s["dur"]) * 100.0))

# ---------- проверка: BUILD_TEST=папка — лагерь, все постройки, готовка, изба, кадры ----------

var _tf := 0
var _tdir := ""
var _tcab: Dictionary = {}
var _tfire: Dictionary = {}
var _tcenter := Vector3.ZERO  # точка, вокруг которой тест ищет места

func _find_spot(kind: String, from: float = 3.0) -> bool:
	build.select(kind)
	var r := from
	while r < 23.0:
		for k in 20:
			var a := TAU * k / 20.0
			build.gyaw = a + PI
			build._move(_tcenter + Vector3(cos(a) * r, 0, sin(a) * r))
			if build.valid:
				return build.confirm()
		r += 1.5
	print("build test: нет места для ", kind, " (", build.reason, ")")
	build.select("")
	return false

func _shot(nm: String) -> void:
	get_viewport().get_texture().get_image().save_png(_tdir + "/" + nm + ".png")
	print("build test shot ", nm, " fps ", Engine.get_frames_per_second())

func _look(p: Vector3, yaw: float, dist: float, pitch: float) -> void:
	main.hero.position = Vector3(p.x, main.ground_at(p.x, p.z), p.z)
	main.rig.position = main.hero.position
	main.rig.rotation.y = yaw
	main.rig.distance = dist
	main.rig.pitch = pitch

func _run_test() -> void:
	_tf += 1
	var w = main.weather
	if _tf < 120:
		w.next_change = 100.0
		w.t_precip = 0.0
		w.precip = 0.0
		main.t_hours = 12.0
	match _tf:
		60:
			main.inv.merge({"pebble": 40, "twig": 20, "branch": 30, "spruce_twigs": 40, "firewood": 12, "meat_raw": 3, "fish_raw": 2, "hide": 1, "log": 30, "moss": 12, "clay": 10, "plank": 40, "fiber": 6, "bark": 4, "shovel": 1}, true)
			# поляна рядом: редкий лес, ровно, не у воды
			var best: Vector3 = main.hero.position
			var found := false
			for rr in range(0, 160, 6):
				for kk in 24:
					var ang := TAU * kk / 24.0
					var x: float = main.hero.position.x + cos(ang) * rr
					var z: float = main.hero.position.z + sin(ang) * rr
					if main.forest_density(x, z) < 0.12 and main.normal_at(x, z).y > 0.97 and main.height(x, z) > main.WATER_Y + 1.5 and main.zone(x, z) == 0:
						best = Vector3(x, main.height(x, z), z)
						found = true
						break
				if found:
					break
			main.hero.position = best
			_tcenter = main.hero.position
			build.start()
			for k: String in ["campfire", "leanto", "tree_shelter"]:
				print("build test place ", k, " -> ", _find_spot(k, 3.0))
			print("build test place cabin -> ", _find_spot("cabin", 8.0))
			build.stop()
			for s: Dictionary in list:
				if s["type"] == "campfire":
					_tfire = s
				if s["type"] == "cabin":
					_tcab = s
			print("build test structures ", list.size())
		70:
			if not _tfire.is_empty():
				light(_tfire)
				add_fuel(_tfire)
				add_fuel(_tfire)
				start_cook(_tfire, "meat_cooked", "meat_raw")
				print("build test fire lit=", _tfire["lit"], " fuel=", _tfire["fuel"])
				advance(0.3)
				_refresh(_tfire)
				var p: Vector3 = _tfire["pos"]
				_look(p + Vector3(0, 0, 1.6), 0.4, 5.0, 30.0)
				main.hero.position = p + Vector3(1.3, 0, 1.3)
				main.hero.position.y = main.height(main.hero.position.x, main.hero.position.z)
				print("build test warm near fire ", warm_bonus(), " actions ", actions().map(func(a: Array) -> String: return a[0]))
		100:
			_shot("t_fire")
			advance(0.4)
			print("build test cooked done=", _tfire["cook"].get("done"))
			take_cooked(_tfire)
			print("build test inv cooked ", main.inv.get("meat_cooked", 0))
			for s: Dictionary in list:
				if s["type"] == "leanto":
					to_store(s, "firewood", 3)
					print("build test store ", s["store"], " w ", store_weight(s))
					_look(s["pos"] + Basis(Vector3.UP, s["yaw"]) * Vector3(0, 0, 3.0), float(s["yaw"]) + 0.5, 8.0, 30.0)
		130:
			_shot("t_leanto")
			for s: Dictionary in list:
				if s["type"] == "tree_shelter":
					_look(s["pos"] + Basis(Vector3.UP, s["yaw"]) * Vector3(0, 0, 4.0), float(s["yaw"]) + 0.8, 9.0, 32.0)
		160:
			_shot("t_tree")
			if not _tcab.is_empty():
				_look(_tcab["pos"] + Basis(Vector3.UP, _tcab["yaw"]) * Vector3(0, 0, 4.0), float(_tcab["yaw"]) + 0.5, 14.0, 35.0)
				if main.tools_world != null:
					main.tools_world.drop_log(_xf(_tcab) * Vector3(3.5, 0.15, 0), 0.0)
					main.tools_world.drop_log(_xf(_tcab) * Vector3(3.8, 0.15, 1.0), 0.0)
				main.inv["log"] = maxi(0, count("log") - 3)
				var ht: Node = main.hero.get("tools")
				if ht != null:
					ht.held = "log"
					deposit_held_log(_tcab)
					print("build test held log deposited, held=", ht.held, " have ", _tcab["have"].get("log", 0))
				deposit(_tcab)
				print("build test site ready ", site_ready(_tcab), " have ", _tcab["have"])
		190:
			_shot("t_site")
			start_building(_tcab)
			advance(1.5)
		220:
			_shot("t_building")
			advance(2.0)
			print("build test cabin stage ", _tcab["stage"])
		250:
			_shot("t_cabin")
			main.hero.position = _xf(_tcab) * Vector3(0, 0, GEO.CD * 0.5 + 1.0)
			print("build test door actions ", actions().map(func(a: Array) -> String: return a[0]))
			cabin_ctl.enter(_tcab)
			light(_tcab)
			add_fuel(_tcab)
			for k: String in ["bed", "table", "bench", "shelf", "chest", "rack", "workbench"]:
				cabin_ctl.begin_place(k)
				print("build test furn ", k, " ok=", cabin_ctl.confirm_place(), " at ", cabin_ctl.p_pos)
			print("build test inside warm ", warm_bonus(), " wind ", wind_k(), " cap ", store_cap(_tcab))
			print("build test inside actions ", actions().map(func(a: Array) -> String: return a[0]))
			print("build test stations fire=", main.station_near("fire"), " stove=", main.station_near("stove"), " camp=", main.station_near("camp"), " rack=", main.station_near("rack"))
		290:
			_shot("t_interior")
			ui.open_store(_tcab)
		300:
			_shot("t_ui_store")
			ui.close_panel()
			sleep(1.0)
			print("build test slept, hour ", main.t_hours, " stove fuel ", _tcab["stove_fuel"])
			cabin_ctl.leave()
		320:
			# зима: снежная пещера, лопата, тропа
			w.snow = 1.0
			w.temp = -15.0
			main.day_count = 20
			main.t_hours = 12.0
		340:
			build.start()
			print("build test place snow_shelter -> ", _find_spot("snow_shelter", 3.0))
			build.select("leanto")
			build._move(_tcenter + Vector3(2, 0, 2))
			ui._fill_build_cards()
			var sn: Dictionary = {}
			for s: Dictionary in list:
				if s["type"] == "snow_shelter":
					sn = s
			if not sn.is_empty():
				_look(sn["pos"] + Basis(Vector3.UP, sn["yaw"]) * Vector3(0, 0, 3.5), float(sn["yaw"]) + 0.4, 8.0, 30.0)
				main.hero.position = sn["pos"] + Basis(Vector3.UP, sn["yaw"]) * Vector3(1.5, 0, 3.0)
		380:
			_shot("t_snow_build_ui")
			build.stop()
			var sd0: float = main.feet.snow_depth(main.hero.position.x, main.hero.position.z)
			for i in 4:
				dig_snow()
			main.hero.body.rotation.y += 1.0
			for i in 3:
				dig_snow()
			print("build test dig snow ", sd0, " -> ", main.feet.snow_depth(main.hero.position.x + sin(main.hero.body.rotation.y) * 0.9, main.hero.position.z + cos(main.hero.body.rotation.y) * 0.9))
			for i in 40:
				main.feet.add_wear(main.hero.position.x - 6.0 + i * 0.3, main.hero.position.z + 2.0, 0.7, 0.018, 0.75)
		420:
			_shot("t_winter")
		440:
			get_tree().quit()

# ======================================================================
# --- core: сохранение (save.gd, раздел «camp»): постройки, хранилища, огонь и готовка,
# стройка и изба (стадия, внесённое, мебель, печь, сушило), прочность ---
const _SKEEP := ["store", "dur", "fuel", "lit", "cook", "stage", "have", "prog", "furn", "stove_fuel", "stove_lit", "rack", "roof_snow", "snow_piles"]

func to_save() -> Dictionary:
	var SV = preload("res://scripts/save.gd")
	var out: Array = []
	for s: Dictionary in list:
		var e := {"type": s["type"], "pos": SV.enc(s["pos"]), "yaw": float(s["yaw"])}
		for k: String in _SKEEP:
			if s.has(k):
				e[k] = SV.enc(s[k])
		out.append(e)
	return {"list": out}

func from_save(d: Dictionary) -> void:
	var SV = preload("res://scripts/save.gd")
	for s: Dictionary in list.duplicate():
		remove(s)
	for e: Dictionary in d.get("list", []):
		var type := String(e["type"])
		if not DEFS.has(type):
			continue
		var s := place(type, SV.dec(e["pos"]), float(e["yaw"]))
		for k: String in _SKEEP:
			if e.has(k):
				s[k] = SV.dec(e[k])
		s["store"] = SV.int_dict(s.get("store", {}))
		if s.has("have"):
			s["have"] = SV.int_dict(s["have"])
		for k2: String in ["dur", "fuel", "prog", "stove_fuel"]:
			if s.has(k2):
				s[k2] = float(s[k2])
		var ck: Dictionary = s.get("cook", {})
		if not ck.is_empty():
			ck["t"] = float(ck["t"])
			ck["need"] = float(ck["need"])
		var fl: Array = []
		for f: Dictionary in s.get("furn", []):
			var f2 := f.duplicate()
			f2["x"] = float(f2.get("x", 0.0))
			f2["z"] = float(f2.get("z", 0.0))
			f2["rot"] = int(f2.get("rot", 0))
			f2["kind"] = String(f2.get("kind", ""))
			fl.append(f2)
		if s.has("furn"):
			s["furn"] = fl
		_register(s)
		_rebuild(s)
# --- /core ---
