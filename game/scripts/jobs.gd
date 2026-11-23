extends RefCounted
## --- colony: работы отряда. ---
## Дело (job) — словарь: {kind, label, stage, pos, t, hits, ...}. Этапы одинаковы для всех:
##   move → work → haul (если взяли ношу) → deposit → done.
## Работы делают ту же работу, что и герой руками: валка и раскряжёвка — world_tools,
## сбор — world_tools.harvest, разделка — туши hunt.gd, стройка — structures.gd.
## Тут только порядок действий и выбор дела; сами действия уже написаны и проверены.
##
## Публичное:
##   start(u, kind, data) -> bool      — начать дело
##   tick(u, dt)                       — шаг дела
##   auto(u) -> bool                   — сам найти работу (если включено «сам»)
##   commands(hit) -> Array            — что можно приказать по цели: [[подпись, вид]]
##   label_of(kind) -> String

const IT = preload("res://scripts/items.gd")
const FUR_KINDS := ["fox", "hare", "squirrel", "wolf", "lynx", "wolverine", "beaver", "muskdeer"]
const FOOD := ["meat_cooked", "fish_cooked", "stew", "fish_soup", "meat_dried", "fish_dried", "berry", "mushroom", "meat_raw", "fish_raw"]
const FOOD_VAL := {"meat_cooked": 0.5, "fish_cooked": 0.42, "stew": 0.6, "fish_soup": 0.55, "meat_dried": 0.38,
	"fish_dried": 0.34, "berry": 0.12, "mushroom": 0.14, "meat_raw": 0.22, "fish_raw": 0.2}

const LABELS := {"move": "Идёт", "chop": "Рубит дерево", "cut": "Кряжует ствол", "split": "Колет дрова",
	"gather": "Собирает", "fish": "Ловит рыбу", "hunt": "Охотится", "butcher": "Разделывает",
	"haul": "Несёт", "build": "Строит", "refuel": "Топит огонь", "cook": "Готовит",
	"deposit": "Относит в амбар", "supply": "Несёт на стройку", "eat": "Ест", "sleep": "Спит", "defend": "Отбивается", "warm": "Греется"}

var main: Node3D
var colony

func setup(col) -> void:
	colony = col
	main = col.main

func label_of(kind: String) -> String:
	return String(LABELS.get(kind, "Занят"))

func _w() -> Node:
	return main.tools_world

# ---------- начало дела ----------

## data: tree/trunk/node/animal/site/res/pos — смотря по виду работы.
func start(u, kind: String, data: Dictionary) -> bool:
	if u.state == "dead":
		return false
	var j := {"kind": kind, "label": label_of(kind), "stage": "move", "t": 0.0, "hits": 0, "tries": 0}
	j.merge(data)
	var reach := 1.1
	var stand := Vector3.INF
	match kind:
		"move":
			stand = j["pos"]
			reach = 0.4
		"chop":
			var rec: Array = j["rec"]
			stand = _beside((rec[2] as Transform3D).origin, u.position, 1.6)
			reach = 2.8
			u.show_tool("axe")
		"cut", "split":
			stand = _beside(j["pos"], u.position, 1.2)
			reach = 2.4
			u.show_tool("axe")
		"gather", "fish":
			stand = _beside(j["pos"], u.position, 0.9)
			reach = 2.0
			u.show_tool("knife")
		"haul":
			stand = _beside(j["pos"], u.position, 0.8)
			reach = 1.9
			u.show_tool("")
		"hunt", "defend":
			var a: Node3D = j["animal"]
			stand = a.position
			u.show_tool(u.weapon if u.weapon != "" else "spear")
			reach = 13.0 if u.weapon == "bow" else 1.8
			j["range"] = reach
		"butcher":
			var c: Node3D = j["animal"]
			stand = _beside(c.position, u.position, 1.1)
			reach = 2.2
			u.show_tool("knife")
		"build":
			var s: Dictionary = j["site"]
			stand = _beside(s["pos"], u.position, 2.4)
			reach = 3.2
			u.show_tool("axe")
		"refuel", "cook", "eat", "warm":
			var s2: Dictionary = j["site"]
			stand = _beside(s2["pos"], u.position, 1.3)
			reach = 1.9
			u.show_tool("")
		"sleep":
			var s3: Dictionary = j["site"]
			stand = _beside(s3["pos"], u.position, 0.9)
			reach = 1.6
			u.show_tool("")
		"deposit":
			stand = colony.stock_point()
			reach = 2.0
		"supply":
			# сперва к запасу (взять), потом на стройку (положить)
			var ss: Dictionary = j["site"]
			if not main.camp.list.has(ss) or int(j.get("n", 0)) <= 0:
				return false
			stand = colony.stock_point()
			reach = 2.2
			u.show_tool("")
	if stand == Vector3.INF:
		return false
	var free: Vector3 = colony.nav.nearest_free(stand, 5.0)
	# за разрешённую область не выходим
	if not colony.can_work_at(u, free):
		return false
	j["stand"] = free
	j["reach"] = reach
	u.job = j
	u.work_anim = ""
	if not u.goto(free, kind == "defend"):
		# не дойти — хотя бы встанем лицом к цели
		if u.dist_to(free) > reach:
			u.job = {}
			return false
	return true

## Точка «встать рядом» с цели: со стороны, откуда идёт человек.
func _beside(p: Vector3, from: Vector3, r: float) -> Vector3:
	var d := Vector3(from.x - p.x, 0.0, from.z - p.z)
	if d.length() < 0.01:
		d = Vector3(1, 0, 0)
	var q := p + d.normalized() * r
	return Vector3(q.x, main.ground_fast(q.x, q.z), q.z)

# ---------- шаг дела ----------

func tick(u, dt: float) -> void:
	var j: Dictionary = u.job
	if j.is_empty():
		return
	var kind := String(j["kind"])
	match String(j["stage"]):
		"move":
			var stand: Vector3 = j["stand"]
			if kind == "hunt" or kind == "defend":
				_chase(u, j, dt)
				return
			if u.dist_to(stand) <= float(j["reach"]):
				_begin_work(u, j)
			elif u.arrived():
				j["tries"] = int(j["tries"]) + 1
				if int(j["tries"]) > 2 or not u.goto(stand, false):
					_face(u, stand)
					if u.dist_to(stand) <= float(j["reach"]) + 1.0:
						_begin_work(u, j)
					else:
						done(u, false)
		"work":
			_work(u, j, dt)
		"deliver":
			_deliver(u, j)
		"haul":
			var sp: Vector3 = colony.stock_point()
			if u.dist_to(sp) <= 2.2:
				_deposit(u)
			elif u.arrived():
				j["tries"] = int(j["tries"]) + 1
				var free2: Vector3 = colony.nav.nearest_free(sp, 6.0)
				if int(j["tries"]) > 3 or not u.goto(free2, false):
					_deposit(u)

func _begin_work(u, j: Dictionary) -> void:
	j["stage"] = "work"
	j["t"] = 0.0
	u.stop()
	u.state = "work"
	var kind := String(j["kind"])
	match kind:
		"chop", "cut", "split":
			u.work_anim = "chop"
		"gather", "fish":
			u.work_anim = "gather"
		"butcher":
			u.work_anim = "kneel"
		"build":
			u.work_anim = "build"
		"refuel", "cook", "eat":
			u.work_anim = "cook"
		"sleep":
			u.state = "sleep"
			u.work_anim = ""
		"warm":
			u.work_anim = "cook"
		"move":
			done(u, true)
			return
		"supply":
			_take_for_site(u, j)
			return
		_:
			u.work_anim = ""
	var fp: Vector3 = j.get("pos", j["stand"])
	_face(u, fp)

## У запаса: берём нужный ресурс (по силам и по нужде стройки) и идём на стройку.
func _take_for_site(u, j: Dictionary) -> void:
	var id := String(j["id"])
	var s: Dictionary = j["site"]
	var missing: int = colony.site_missing(s, id)
	var n: int = mini(mini(int(j["n"]), missing), mini(colony.count(id), u.carry_room(id)))
	if n <= 0:
		done(u, false)
		return
	colony.spend(id, n)
	u.carry_add(id, n)
	j["n"] = n
	j["stage"] = "deliver"
	j["tries"] = 0
	j["label"] = "Несёт на стройку: %s" % IT.name_of(id).to_lower()
	var sp: Vector3 = _beside(s["pos"], u.position, 2.4)
	j["stand"] = colony.nav.nearest_free(sp, 6.0)
	if not u.goto(j["stand"], false):
		colony.give(id, n)
		u.carry_clear()
		done(u, false)

## На стройке: положить принесённое. Что не легло — обратно в запас.
func _deliver(u, j: Dictionary) -> void:
	var s: Dictionary = j["site"]
	var stand: Vector3 = j["stand"]
	if not main.camp.list.has(s):
		_return_carry(u)
		done(u, false)
		return
	if u.dist_to(stand) > 3.3:
		if u.arrived():
			j["tries"] = int(j["tries"]) + 1
			if int(j["tries"]) > 2 or not u.goto(stand, false):
				_return_carry(u)
				done(u, false)
		return
	var id := String(j["id"])
	var n: int = int(u.carry.get(id, 0))
	var put: int = colony.site_deposit(s, id, n)
	if put > 0:
		colony.note("%s: на стройку %s ×%d" % [u.unit_name, IT.name_of(id).to_lower(), put])
	_return_carry(u)
	done(u, true)

func _return_carry(u) -> void:
	for k: String in u.carry:
		colony.give(k, int(u.carry[k]))
	u.carry_clear()

func _face(u, p: Vector3) -> void:
	var d := Vector3(p.x - u.position.x, 0.0, p.z - u.position.z)
	if d.length() > 0.05:
		u.yaw = atan2(d.x, d.z)
		u.rotation.y = u.yaw

## Работа на месте: раз в period делаем один «удар» или шаг работы.
const WORK_K := 1.5             # темп работы: быстрее, чтобы дело не тянулось
func _work(u, j: Dictionary, dt: float) -> void:
	j["t"] = float(j["t"]) + dt * WORK_K
	var kind := String(j["kind"])
	var w: Node = _w()
	match kind:
		"chop":
			if not _every(j, 0.8):
				return
			# экземпляр дерева прячется с первого удара (падает отдельная модель),
			# поэтому о конце валки сообщает сам world_tools.chop_tree
			var rec: Array = j["rec"]
			j["hits"] = int(j["hits"]) + 1
			if bool(w.chop_tree(rec, u.position, int(j["hits"]))):
				colony.note("%s свалил дерево" % u.unit_name)
				colony.stat_add("trees", 1)
				colony.nav.invalidate(u.position.x, u.position.z, 14.0)
				done(u, true)
		"cut":
			if not _every(j, 0.75):
				return
			var tr: Dictionary = j["trunk"]
			j["hits"] = int(j["hits"]) + 1
			if bool(w.chop_trunk(tr, int(j["hits"]))):
				j["hits"] = 0
				# бревно легло рядом — берём его и несём
				var lg: Node3D = w.find_log(u.position, 4.0)
				if lg != null and bool(w.take_item(w._item_of(lg))):
					u.carry_add("log", 1)
					colony.stat_add("logs", 1)
					_to_haul(u, j)
					return
				done(u, true)
		"split":
			if not _every(j, 0.7):
				return
			var node: Node3D = j["node"]
			if not is_instance_valid(node):
				done(u, false)
				return
			j["hits"] = int(j["hits"]) + 1
			var hits := int(j["hits"])
			var res := {"d": false}
			_grab(u, func() -> void: res["d"] = w.split_log(node, hits))
			if bool(res["d"]):
				colony.stat_add("firewood", u.carry_total())
				_to_haul(u, j)
		"gather":
			if float(j["t"]) < 2.2:
				return
			var r: Dictionary = j["res"]
			_grab(u, func() -> void: w.harvest(r, true))
			_to_haul(u, j)
		"fish":
			if float(j["t"]) < 4.0:
				return
			var fp: Vector3 = j["pos"]
			_grab(u, func() -> void: w.harvest({"type": "fish", "pos": fp}, true))
			_to_haul(u, j)
		"butcher":
			if float(j["t"]) < 5.5:
				return
			_butcher(u, j)
		"build":
			var s: Dictionary = j["site"]
			if not main.camp.list.has(s):
				done(u, false)
				return
			colony.build_progress(s, dt)
			if String(s.get("stage", "done")) == "done":
				colony.note("Готово: %s" % String(main.camp.DEFS[s["type"]]["name"]))
				done(u, true)
		"refuel":
			if float(j["t"]) < 1.6:
				return
			var s2: Dictionary = j["site"]
			main.camp.add_fuel(s2)
			if not bool(s2.get("lit", false)):
				main.camp.light(s2)
			done(u, true)
		"cook":
			if float(j["t"]) < 3.0:
				return
			var s3: Dictionary = j["site"]
			var ck: Dictionary = s3.get("cook", {})
			if ck.is_empty():
				if colony.count("meat_raw") > 0:
					main.camp.start_cook(s3, "meat_cooked", "meat_raw")
				elif colony.count("fish_raw") > 0:
					main.camp.start_cook(s3, "fish_cooked", "fish_raw")
				done(u, true)
			elif bool(ck.get("done", false)):
				main.camp.take_cooked(s3)
				done(u, true)
			else:
				j["t"] = 2.0
		"eat":
			if float(j["t"]) < 1.8:
				return
			_eat_now(u)
			done(u, true)
		"warm":
			if float(j["t"]) < 2.0:
				return
			if u.warmth > 0.6 or not bool((j["site"] as Dictionary).get("lit", false)):
				done(u, true)
			else:
				j["t"] = 0.5
		"sleep":
			# спит, пока не рассвело или не отдохнул
			if main.day_factor > 0.35 or u.fatigue < 0.08:
				done(u, true)
		"hunt", "defend":
			_chase(u, j, dt)
		_:
			done(u, true)

## true — прошёл очередной удар (время дела сбрасывается).
func _every(j: Dictionary, period: float) -> bool:
	if float(j["t"]) >= period:
		j["t"] = 0.0
		return true
	return false

## Положить ношу и пойти с ней в амбар (или закончить, если нести нечего).
func _to_haul(u, j: Dictionary) -> void:
	if u.carry_total() <= 0:
		done(u, true)
		return
	j["stage"] = "haul"
	j["tries"] = 0
	j["label"] = "Несёт в амбар"
	u.work_anim = ""
	var sp: Vector3 = colony.nav.nearest_free(colony.stock_point(), 6.0)
	if not u.goto(sp, false):
		_deposit(u)

## То, что действие положило в общий запас, отдаём человеку в руки (понесёт в амбар).
func _grab(u, fn: Callable) -> void:
	var before := {}
	for k: String in main.inv:
		before[k] = int(main.inv[k])
	fn.call()
	for k: String in main.inv.keys():
		var d := int(main.inv[k]) - int(before.get(k, 0))
		if d > 0:
			u.carry_add(k, d)
			var left := int(before.get(k, 0))
			if left > 0:
				main.inv[k] = left
			else:
				main.inv.erase(k)

func _deposit(u) -> void:
	u.stop()
	var n: int = u.carry_total()
	if n > 0:
		for k: String in u.carry:
			colony.give(k, int(u.carry[k]))
		colony.note("%s: в амбар %d" % [u.unit_name, n])
		u.carry_clear()
	done(u, true)

## Разделка: мясо, шкура, мех — в руки; туша остаётся объедками для падальщиков.
func _butcher(u, j: Dictionary) -> void:
	var a: Node3D = j["animal"]
	if not is_instance_valid(a) or not a.dead:
		done(u, false)
		return
	var hunt: Node = main.hunt
	var n := 2
	if hunt != null:
		n = maxi(1, int(hunt.meat_count(a)))
	u.carry_add("meat_raw", mini(n, 6))
	u.carry_add("hide", 1)
	if String(a.kind) in FUR_KINDS:
		u.carry_add("fur", 1)
		colony.stat_add("furs", 1)
	colony.stat_add("meat", mini(n, 6))
	a.meat = maxf(10.0, float(a.meat) * 0.3)
	colony.mark_butchered(a)
	if hunt != null:
		hunt.pool_at(hunt.body_center(a), 0.3, 24.0)
	colony.note("%s разделал добычу" % u.unit_name)
	_to_haul(u, j)

## Охота и оборона: догнать, выстрелить или ударить.
func _chase(u, j: Dictionary, dt: float) -> void:
	var a: Node3D = j["animal"]
	if not is_instance_valid(a):
		done(u, false)
		return
	if a.dead:
		done(u, true)
		if String(j["kind"]) == "hunt":
			start(u, "butcher", {"animal": a, "pos": a.position})
		return
	var d: float = u.dist_to(a.position)
	var rng_r: float = float(j.get("range", 13.0))
	if d > 70.0:
		colony.note("%s упустил добычу" % u.unit_name)
		done(u, false)
		return
	j["t"] = float(j["t"]) + dt
	if d > rng_r:
		u.work_anim = ""
		j["cd"] = 0.0
		var rp := float(j.get("rp", 0.0)) - dt
		if rp <= 0.0 or u.arrived():
			j["rp"] = 0.7
			var sp2: Vector3 = colony.nav.nearest_free(_beside(a.position, u.position, rng_r * 0.7), 6.0)
			u.goto(sp2, true)
		else:
			j["rp"] = rp
		return
	# в пределах выстрела: стоим и бьём
	u.stop()
	u.state = "work"
	u.work_anim = "shoot"
	_face(u, a.position)
	var cd := float(j.get("cd", 0.0)) - dt
	if cd > 0.0:
		j["cd"] = cd
		return
	j["cd"] = 2.2 if u.weapon == "bow" else 1.4
	_strike(u, a)

func _strike(u, a: Node3D) -> void:
	var w: Node = _w()
	var hunt: Node = main.hunt
	var aim: Vector3 = a.position + Vector3(0, float(a.parts.get("H", 0.7)) * 0.6, 0)
	if hunt != null:
		aim = hunt.body_center(a)
		aim.y += float(a.parts.get("H", 0.7)) * 0.35
	var o: Vector3 = u.position + Vector3(0, 1.3, 0)
	var dir := (aim - o).normalized()
	if u.weapon == "bow":
		var vel: Vector3 = w.throw_velocity(o, dir, aim)
		var b := Basis()
		var A := vel.normalized()
		var X := Vector3.UP.cross(A).normalized() if absf(A.y) < 0.98 else Vector3.RIGHT
		b = Basis(X, A, X.cross(A))
		w.shoot_arrow(Transform3D(b, o + dir * 0.4), vel)
		colony.spend("arrow", 1)
	elif u.weapon == "spear":
		w.stab(u.position, o + dir * 1.6, u.yaw)
	else:
		# без оружия: кулаком и ножом
		if hunt != null:
			hunt.hit_animal(a, 0.3, u.position)

func _eat_now(u) -> void:
	for id: String in FOOD:
		if colony.count(id) > 0:
			colony.spend(id, 1)
			u.eat(id, float(FOOD_VAL.get(id, 0.2)))
			colony.note("%s поел: %s" % [u.unit_name, IT.name_of(id).to_lower()])
			return
	colony.note("%s голоден: нет еды" % u.unit_name)

func done(u, _ok: bool) -> void:
	u.job = {}
	u.work_anim = ""
	if u.state == "work" or u.state == "sleep":
		u.state = "idle"
	u.stop()

func cancel(u) -> void:
	done(u, false)

# ---------- приказы по цели ----------

## hit — что нашли под пальцем (colony.pick): {"what": ..., ...}.
## Возвращает список [[подпись, вид работы]] — первый годится для простого тапа.
func commands(hit: Dictionary) -> Array:
	var out: Array = []
	match String(hit.get("what", "")):
		"tree":
			out.append(["Рубить", "chop"])
		"trunk":
			out.append(["Кряжевать", "cut"])
		"log":
			out.append(["Нести бревно", "haul"])
			out.append(["Колоть на дрова", "split"])
		"res":
			var r: Dictionary = hit["res"]
			out.append([String(r.get("label", "Собрать")), "gather"])
		"water":
			out.append(["Ловить рыбу", "fish"])
		"animal":
			var a: Node3D = hit["animal"]
			if a.dead:
				out.append(["Разделать", "butcher"])
			else:
				out.append(["Охотиться", "hunt"])
		"build":
			var s: Dictionary = hit["site"]
			var type := String(s["type"])
			if String(s.get("stage", "done")) == "site":
				for id: String in main.camp.need_of(s):
					if colony.site_missing(s, id) > 0 and colony.count(id) > 0:
						out.append(["Нести: %s" % IT.name_of(id).to_lower(), "supply:" + id])
			elif String(s.get("stage", "done")) == "building":
				out.append(["Строить", "build"])
			if type == "campfire":
				out.append(["Подбросить дров", "refuel"])
				out.append(["Готовить", "cook"])
				out.append(["Погреться", "warm"])
			if colony.is_store(s):
				out.append(["Сложить ношу", "deposit"])
			if type in ["leanto", "tree_shelter", "dugout", "cabin", "snow_shelter"]:
				out.append(["Спать", "sleep"])
		"ground":
			out.append(["Идти", "move"])
	return out

## Данные для работы по найденной цели.
func data_of(hit: Dictionary, kind: String) -> Dictionary:
	match kind:
		"chop":
			return {"rec": hit["rec"], "pos": hit["pos"]}
		"cut":
			return {"trunk": hit["trunk"], "pos": hit["pos"]}
		"haul", "split":
			return {"node": hit["node"], "pos": hit["pos"]}
		"gather":
			return {"res": hit["res"], "pos": hit["pos"]}
		"fish":
			return {"pos": hit["pos"]}
		"hunt", "defend", "butcher":
			return {"animal": hit["animal"], "pos": hit["pos"]}
		"build", "refuel", "cook", "deposit", "sleep", "warm":
			return {"site": hit["site"], "pos": hit["pos"]}
		"move":
			return {"pos": hit["pos"]}
		"supply":
			var ss: Dictionary = hit["site"]
			return {"site": ss, "pos": hit["pos"], "id": String(hit.get("supply_id", "")), "n": 99}
	return {}

# ---------- нужды и «сам найдёт работу» ----------

## Нужды: ношу в амбар, поесть, погреться, поспать. true — дело начато.
func needs(u) -> bool:
	if u.state == "dead" or not u.job.is_empty():
		return false
	var p: Vector3 = u.position
	# ноша в руках — сперва в амбар
	if u.carry_total() > 0:
		if start(u, "deposit", {}):
			u.job["stage"] = "haul"
			u.job["label"] = "Несёт в амбар"
			return true
	var fire: Dictionary = colony.nearest_building(p, ["campfire"], 120.0)
	if u.hunger < 0.35 and colony.food_count() > 0:
		var ff: Dictionary = fire if not fire.is_empty() else colony.nearest_building(p, ["cabin"], 120.0)
		if not ff.is_empty() and start(u, "eat", {"site": ff, "pos": ff["pos"]}):
			return true
	if u.warmth < 0.3 and not fire.is_empty() and bool(fire.get("lit", false)):
		if start(u, "warm", {"site": fire, "pos": fire["pos"]}):
			return true
	if u.fatigue > 1.0 and main.day_factor < 0.3:
		var sh: Dictionary = colony.nearest_building(p, ["cabin", "dugout", "leanto", "tree_shelter"], 90.0)
		if not sh.is_empty() and start(u, "sleep", {"site": sh, "pos": sh["pos"]}):
			return true
	return false

## Нужда невмоготу: бросаем работу и идём есть, греться или спать.
## true — работу прервали.
func interrupt(u) -> bool:
	if u.state == "dead" or u.job.is_empty():
		return false
	var kind := String(u.job.get("kind", ""))
	if kind in ["eat", "warm", "sleep", "defend", "deposit"]:
		return false
	var crit := false
	if u.hunger < 0.12 and colony.food_count() > 0:
		crit = true
	if u.warmth < 0.18:
		crit = true
	if u.fatigue > 1.2 and main.day_factor < 0.35:
		crit = true
	if not crit:
		return false
	var carried: Dictionary = u.carry.duplicate()
	cancel(u)
	u.carry = carried
	if needs(u):
		return true
	return false

## Сам найдёт работу: сперва нужды, потом лист работ (planner.gd).
func auto(u) -> bool:
	if u.state == "dead" or not u.job.is_empty():
		return false
	if needs(u):
		return true
	if colony.planner != null:
		return bool(colony.planner.pick(u))
	return false
