extends RefCounted
## --- colony: лист работ и метки (как вкладка «Работы» в RimWorld). ---
## Таблица: люди × роды работ, в клетке важность 1–4 или «нет». Человек без приказа
## берёт работу с наименьшим числом (1 — первым делом), а среди равных — ближнюю.
## Метки: игрок помечает деревья в рубку, кусты в сбор, зверя в охоту. Помеченное
## попадает в лист работ и разбирается само.
##
## Публичное:
##   pri_of(u, col) -> int / set_pri(u, col, v) / cycle(u, col)
##   pick(u) -> bool                   — взять лучшую работу
##   designate(hit) -> bool            — пометить цель
##   undesignate(p, r) -> bool         — снять метки рядом
##   clear_desig()
##   desig: Array                      — метки [{col, pos, ...}]

const COLS := [
	{"id": "chop", "name": "Рубить"},
	{"id": "build", "name": "Строить"},
	{"id": "haul", "name": "Носить"},
	{"id": "gather", "name": "Собирать"},
	{"id": "hunt", "name": "Охота"},
	{"id": "fish", "name": "Рыба"},
	{"id": "cook", "name": "Варить"},
	{"id": "fire", "name": "Костёр"},
]
## Кто к чему сноровистее (1 — первым делом, 0 — не его дело).
const DEFAULTS := {
	"Ермолай": {"chop": 1, "build": 2, "haul": 3, "gather": 3, "hunt": 2, "fish": 0, "cook": 2, "fire": 1},
	"Семён": {"chop": 3, "build": 3, "haul": 3, "gather": 2, "hunt": 1, "fish": 1, "cook": 2, "fire": 2},
	"Фёдор": {"chop": 1, "build": 1, "haul": 2, "gather": 2, "hunt": 3, "fish": 2, "cook": 3, "fire": 2},
}
const BASE := {"chop": 2, "build": 2, "haul": 3, "gather": 2, "hunt": 3, "fish": 3, "cook": 3, "fire": 2}

var colony
var main: Node3D
var jobs
var pri := {}                   # имя → {род: 0..4}
var desig: Array = []           # метки игрока

func setup(col) -> void:
	colony = col
	main = col.main
	jobs = col.jobs
	for u in colony.units:
		var nm: String = u.unit_name
		var d: Dictionary = DEFAULTS.get(nm, BASE)
		pri[nm] = d.duplicate()

# ---------- таблица ----------

func pri_of(u, col: String) -> int:
	var row: Dictionary = pri.get(u.unit_name, {})
	return int(row.get(col, 0))

func set_pri(u, col: String, v: int) -> void:
	if not pri.has(u.unit_name):
		pri[u.unit_name] = BASE.duplicate()
	(pri[u.unit_name] as Dictionary)[col] = clampi(v, 0, 4)

## Тап по клетке: 0 → 1 → 2 → 3 → 4 → 0.
func cycle(u, col: String) -> void:
	set_pri(u, col, (pri_of(u, col) + 1) % 5)

func col_name(col: String) -> String:
	for e: Dictionary in COLS:
		if String(e["id"]) == col:
			return String(e["name"])
	return col

# ---------- метки ----------

## hit — из colony.pick. true — метка поставлена.
func designate(hit: Dictionary) -> bool:
	var what := String(hit.get("what", ""))
	var p: Vector3 = hit.get("pos", Vector3.ZERO)
	match what:
		"tree":
			return _add("chop", p)
		"trunk":
			return _add("chop", p)
		"log":
			return _add("haul", p, {"node": hit["node"]})
		"res":
			return _add("gather", p)
		"animal":
			var a: Node3D = hit["animal"]
			return _add("hunt" if not a.dead else "butcher", p, {"animal": a})
		"water":
			return _add("fish", p)
		"build":
			var s: Dictionary = hit["site"]
			if String(s.get("stage", "done")) != "done":
				return _add("build", p, {"site": s})
	return false

func _add(col: String, p: Vector3, extra: Dictionary = {}) -> bool:
	for e: Dictionary in desig:
		if String(e["col"]) == col and (e["pos"] as Vector3).distance_to(p) < 1.2:
			return false
	var e2 := {"col": col, "pos": p, "by": null}
	e2.merge(extra)
	desig.append(e2)
	return true

## Снять метки в круге. true — что-то сняли.
func undesignate(p: Vector3, r: float) -> bool:
	var n := desig.size()
	var out: Array = []
	for e: Dictionary in desig:
		var q: Vector3 = e["pos"]
		if Vector2(q.x - p.x, q.z - p.z).length() > r:
			out.append(e)
	desig = out
	return desig.size() != n

func clear_desig() -> void:
	desig = []

func desig_count(col: String) -> int:
	var n := 0
	for e: Dictionary in desig:
		if String(e["col"]) == col:
			n += 1
	return n

## Метки для покраски на экране и для работ: сначала проверяем, цела ли цель.
func live_desig() -> Array:
	var out: Array = []
	var w: Node = main.tools_world
	for e: Dictionary in desig:
		var col := String(e["col"])
		var p: Vector3 = e["pos"]
		var keep := true
		match col:
			"chop":
				keep = not w.find_tree(p, 2.2).is_empty() or not w.find_trunk(p, 3.0).is_empty()
			"haul":
				keep = w.find_log(p, 3.0) != null
			"gather":
				keep = not w.knife_target(p).is_empty()
			"hunt":
				var a = e.get("animal")
				keep = a != null and is_instance_valid(a) and not a.dead
			"butcher":
				var a2 = e.get("animal")
				keep = a2 != null and is_instance_valid(a2) and a2.dead and float(a2.meat) > 12.0
			"build":
				var s: Dictionary = e.get("site", {})
				keep = main.camp.list.has(s) and String(s.get("stage", "done")) != "done"
		if keep:
			out.append(e)
	if out.size() != desig.size():
		desig = out
	return out

func _free(e: Dictionary) -> bool:
	var by = e.get("by")
	if by == null:
		return true
	if by.state == "dead" or by.job.is_empty():
		e["by"] = null
		return true
	return false

# ---------- выбор работы ----------

## Берём работу: сперва по важности (1 вперёд), среди равных — ближнюю.
func pick(u) -> bool:
	if u.state == "dead" or not u.job.is_empty():
		return false
	var opts: Array = []
	var live := live_desig()
	for e: Dictionary in COLS:
		var col := String(e["id"])
		var pr := pri_of(u, col)
		if pr <= 0:
			continue
		var o: Dictionary = _best(u, col, live)
		if o.is_empty():
			continue
		o["pri"] = pr
		o["d"] = u.dist_to(o.get("pos", u.position))
		opts.append(o)
	# разделка — всегда следом за охотой (мясо пропадёт)
	opts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["pri"]) != int(b["pri"]):
			return int(a["pri"]) < int(b["pri"])
		return float(a["d"]) < float(b["d"]))
	for o: Dictionary in opts:
		var kind := String(o["kind"])
		var data: Dictionary = o["data"]
		if not colony.can_work_at(u, o.get("pos", u.position)):
			continue
		if jobs.start(u, kind, data):
			var mark = o.get("mark")
			if mark != null:
				(mark as Dictionary)["by"] = u
			return true
	return false

## Лучшая цель в этом роде работ (сперва меченое игроком, потом своим умом).
func _best(u, col: String, live: Array) -> Dictionary:
	var p: Vector3 = u.position
	var w: Node = main.tools_world
	if colony.stock_full() and col in ["chop", "gather", "hunt", "fish"]:
		return {}
	# помеченное игроком
	var best: Dictionary = {}
	var bd := 1e9
	for e: Dictionary in live:
		var ec := String(e["col"])
		if not _col_match(col, ec):
			continue
		if not _free(e):
			continue
		var q: Vector3 = e["pos"]
		var d: float = u.dist_to(q)
		if d > 160.0 or d >= bd:
			continue
		var o: Dictionary = _from_mark(u, e)
		if o.is_empty():
			continue
		o["mark"] = e
		bd = d
		best = o
	if not best.is_empty():
		return best
	# своим умом: что нужно острогу
	match col:
		"chop":
			var tr: Dictionary = w.find_trunk(p, 45.0)
			if not tr.is_empty():
				return {"kind": "cut", "data": {"trunk": tr, "pos": w.trunk_cut_point(tr)}, "pos": w.trunk_cut_point(tr)}
			if colony.count("firewood") < colony.want_firewood() and colony.count("log") >= 4:
				var lg2: Node3D = w.find_log(p, 40.0)
				if lg2 != null:
					return {"kind": "split", "data": {"node": lg2, "pos": lg2.global_position}, "pos": lg2.global_position}
			if colony.count("log") + colony.count("firewood") < colony.want_firewood():
				var rec: Array = colony.find_tree_near(colony.center(), 70.0)
				if not rec.is_empty():
					var tp: Vector3 = (rec[2] as Transform3D).origin
					return {"kind": "chop", "data": {"rec": rec, "pos": tp}, "pos": tp}
		"build":
			var s: Dictionary = colony.nearest_site(p, 140.0)
			if not s.is_empty():
				return {"kind": "build", "data": {"site": s, "pos": s["pos"]}, "pos": s["pos"]}
		"haul":
			# стройка ждёт ресурс, а он лежит в запасе: несём отдельным рейсом
			var sup: Dictionary = _supply_for(u)
			if not sup.is_empty():
				return sup
			var lg: Node3D = w.find_log(p, 45.0)
			if lg != null:
				return {"kind": "haul", "data": {"node": lg, "pos": lg.global_position}, "pos": lg.global_position}
		"gather":
			if colony.food_count() < colony.want_food():
				var r: Dictionary = colony.find_res_near(p, 45.0)
				if not r.is_empty():
					return {"kind": "gather", "data": {"res": r, "pos": r["pos"]}, "pos": r["pos"]}
		"hunt":
			var cc: Node3D = colony.find_carcass_near(p, 60.0)
			if cc != null:
				return {"kind": "butcher", "data": {"animal": cc, "pos": cc.position}, "pos": cc.position}
			if u.weapon != "" and colony.food_count() < colony.want_food():
				var a: Node3D = colony.find_game_near(p, 60.0)
				if a != null:
					return {"kind": "hunt", "data": {"animal": a, "pos": a.position}, "pos": a.position}
		"fish":
			if colony.food_count() < colony.want_food():
				var fp: Vector3 = colony.find_water_near(p, 60.0)
				if fp != Vector3.INF:
					return {"kind": "fish", "data": {"pos": fp}, "pos": fp}
		"cook":
			if colony.count("meat_raw") + colony.count("fish_raw") > 0:
				var fire: Dictionary = colony.nearest_building(p, ["campfire"], 120.0)
				if not fire.is_empty() and bool(fire.get("lit", false)):
					return {"kind": "cook", "data": {"site": fire, "pos": fire["pos"]}, "pos": fire["pos"]}
		"fire":
			var f2: Dictionary = colony.nearest_building(p, ["campfire"], 120.0)
			if not f2.is_empty() and float(f2.get("fuel", 0.0)) < 1.4 and colony.count("firewood") + colony.count("twig") > 0:
				return {"kind": "refuel", "data": {"site": f2, "pos": f2["pos"]}, "pos": f2["pos"]}
	return {}

## Стройка в ожидании: берём ближайшую, где нужного ресурса ещё нет на месте и он есть в запасе.
## Один ресурс на стройку несёт один человек за раз (чтобы не ломились втроём за одним).
func _supply_for(u) -> Dictionary:
	var best: Dictionary = {}
	var bd := 1e9
	for s: Dictionary in main.camp.list:
		var want: Array = colony.site_wanted(s)
		if want.is_empty():
			continue
		if _supplied(s, String(want[0]), u):
			continue
		var q: Vector3 = s["pos"]
		var d: float = u.dist_to(q)
		if d < bd:
			bd = d
			best = {"kind": "supply", "data": {"site": s, "pos": q, "id": String(want[0]), "n": 99}, "pos": q}
	return best

func _supplied(s: Dictionary, id: String, me) -> bool:
	var carried := 0
	for o in colony.units:
		if o == me or o.state == "dead" or o.job.is_empty():
			continue
		if String(o.job.get("kind", "")) == "supply" and o.job.get("site") == s and String(o.job.get("id", "")) == id:
			carried += int(o.job.get("n", 0)) if String(o.job.get("stage", "")) == "deliver" else 0
			if String(o.job.get("stage", "")) != "deliver":
				return true
	return carried >= colony.site_missing(s, id)

## Метка «разделать» идёт по охоте, «кряжевать» — по рубке.
func _col_match(col: String, mark_col: String) -> bool:
	if col == mark_col:
		return true
	if col == "hunt" and mark_col == "butcher":
		return true
	return false

func _from_mark(u, e: Dictionary) -> Dictionary:
	var w: Node = main.tools_world
	var p: Vector3 = e["pos"]
	match String(e["col"]):
		"chop":
			var rec: Array = w.find_tree(p, 2.2)
			if not rec.is_empty() and not w.is_young(rec):
				var tp: Vector3 = (rec[2] as Transform3D).origin
				return {"kind": "chop", "data": {"rec": rec, "pos": tp}, "pos": tp}
			var tr: Dictionary = w.find_trunk(p, 3.0)
			if not tr.is_empty():
				var cp: Vector3 = w.trunk_cut_point(tr)
				return {"kind": "cut", "data": {"trunk": tr, "pos": cp}, "pos": cp}
		"haul":
			var lg: Node3D = w.find_log(p, 3.0)
			if lg != null:
				return {"kind": "haul", "data": {"node": lg, "pos": lg.global_position}, "pos": lg.global_position}
		"gather":
			var r: Dictionary = w.knife_target(p)
			if not r.is_empty():
				return {"kind": "gather", "data": {"res": r, "pos": r["pos"]}, "pos": r["pos"]}
		"fish":
			return {"kind": "fish", "data": {"pos": p}, "pos": p}
		"hunt":
			var a = e.get("animal")
			if a != null and is_instance_valid(a) and not a.dead and u.weapon != "":
				return {"kind": "hunt", "data": {"animal": a, "pos": a.position}, "pos": a.position}
		"butcher":
			var a2 = e.get("animal")
			if a2 != null and is_instance_valid(a2) and a2.dead:
				return {"kind": "butcher", "data": {"animal": a2, "pos": a2.position}, "pos": a2.position}
		"build":
			var s: Dictionary = e.get("site", {})
			if main.camp.list.has(s) and String(s.get("stage", "done")) == "building":
				return {"kind": "build", "data": {"site": s, "pos": s["pos"]}, "pos": s["pos"]}
			var want: Array = colony.site_wanted(s) if main.camp.list.has(s) else []
			if not want.is_empty():
				return {"kind": "supply", "data": {"site": s, "pos": s["pos"], "id": String(want[0]), "n": 99}, "pos": s["pos"]}
	return {}

# ---------- сохранение ----------

func to_save() -> Dictionary:
	var rows := {}
	for nm: String in pri:
		rows[nm] = (pri[nm] as Dictionary).duplicate()
	var ds: Array = []
	var SV = preload("res://scripts/save.gd")
	for e: Dictionary in desig:
		if String(e["col"]) in ["chop", "haul", "gather", "fish"]:
			ds.append({"col": e["col"], "pos": SV.enc(e["pos"])})
	return {"pri": rows, "desig": ds}

func from_save(d: Dictionary) -> void:
	var SV = preload("res://scripts/save.gd")
	var rows: Dictionary = d.get("pri", {})
	for nm: String in rows:
		var row: Dictionary = rows[nm]
		var out := {}
		for k: String in row:
			out[k] = int(row[k])
		pri[nm] = out
	desig = []
	for e: Dictionary in d.get("desig", []):
		desig.append({"col": String(e["col"]), "pos": SV.dec(e["pos"]), "by": null})
