extends Node3D
## Изба изнутри: «Войти» — герой у порога внутри, своя камера сверху-спереди, кровля и верх
## передней стены спрятаны (разрез). Печь греет избу (без неё внутри холодно). Мебель ставится
## на сетку 25 см, её можно передвинуть и убрать; у каждой вещи своя польза.

const GEO = preload("res://scripts/build_geo.gd")
const IT = preload("res://scripts/items.gd")
const GRID := 0.25

const FURN := {
	"bed": {"name": "Кровать", "cost": {"plank": 6, "spruce_twigs": 4}, "size": Vector2(1.0, 2.0), "desc": "Спать до утра. В натопленной избе сон лечит."},
	"table": {"name": "Стол", "cost": {"plank": 4}, "size": Vector2(0.8, 1.3), "desc": "За столом еда сытнее на треть."},
	"bench": {"name": "Лавка", "cost": {"plank": 2}, "size": Vector2(0.36, 1.5), "desc": "Сидя на лавке, силы прибывают вдвое быстрее."},
	"shelf": {"name": "Полка", "cost": {"plank": 2}, "size": Vector2(0.32, 1.0), "desc": "Хранилище избы +15 кг."},
	"chest": {"name": "Сундук", "cost": {"plank": 5}, "size": Vector2(0.94, 0.54), "desc": "Хранилище избы +40 кг."},
	"rack": {"name": "Сушило", "cost": {"branch": 4, "fiber": 2}, "size": Vector2(0.7, 1.5), "desc": "Вялит мясо и рыбу, сушит шкуры — без огня."},
	"workbench": {"name": "Верстак", "cost": {"log": 1, "plank": 4}, "size": Vector2(0.7, 1.6), "desc": "Тесать доски из брёвен, мастерить лопату."},
}
const FURN_ORDER := ["bed", "table", "bench", "shelf", "chest", "rack", "workbench"]
## Рецепты верстака: [выход, сколько, {вход}].
const BENCH := [["plank", 3, {"log": 1}], ["shovel", 1, {"plank": 1, "handle": 1}], ["firewood", 4, {"log": 1}]]

var camp
var main: Node3D
var inside := false
var cur: Dictionary = {}
var cam := Camera3D.new()
var _prev_cam: Camera3D
# расстановка мебели
var placing := false
var p_kind := ""
var p_pos := Vector2.ZERO
var p_rot := 0
var p_valid := false
var p_move: Dictionary = {}   # передвигаемая вещь (её запись), {} — новая
var _ghost: Node3D
var _ok := StandardMaterial3D.new()
var _bad := StandardMaterial3D.new()

func _ready() -> void:
	cam.fov = 50.0
	cam.near = 0.1
	cam.far = 120.0
	add_child(cam)
	for m: StandardMaterial3D in [_ok, _bad]:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ok.albedo_color = Color(0.45, 0.95, 0.45, 0.45)
	_bad.albedo_color = Color(1.0, 0.3, 0.25, 0.5)

func _xf(s: Dictionary) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, float(s["yaw"])), s["pos"])

# ---------- вход и выход ----------

func enter(s: Dictionary) -> void:
	cur = s
	inside = true
	var hz := GEO.CD * 0.5
	var xf := _xf(s)
	var hero: Node3D = main.hero
	hero.position = xf * Vector3(0, GEO.floor_y(), hz - 0.7)
	hero.body.rotation.y = float(s["yaw"]) + PI
	hero.vel = Vector3.ZERO
	_set_cut(true)
	_prev_cam = get_viewport().get_camera_3d()
	cam.global_transform = Transform3D(Basis(), xf * Vector3(0.0, 6.2, 5.0))
	cam.look_at(xf * Vector3(0, 0.6, -0.4), Vector3.UP)
	cam.current = true
	for p in [main.weather.rain, main.weather.flakes]:
		if p != null:
			p.visible = false
	main._say("В избе" + ("" if bool(s.get("stove_lit", false)) else " холодно — затопите печь"))

func leave(teleport: bool = true) -> void:
	if not inside:
		return
	cancel_place()
	var s := cur
	inside = false
	_set_cut(false)
	var hero: Node3D = main.hero
	if hero.state == "sit":
		hero._stand_up()
	if teleport:
		var p := _xf(s) * Vector3(0, 0, GEO.CD * 0.5 + 1.5)
		p.y = main.height(p.x, p.z)
		hero.position = p
		hero.body.rotation.y = float(s["yaw"])
	if _prev_cam != null and is_instance_valid(_prev_cam):
		_prev_cam.current = true
	else:
		main.rig.cam.current = true
	for q in [main.weather.rain, main.weather.flakes]:
		if q != null:
			q.visible = true
	cur = {}

func _set_cut(on: bool) -> void:
	var n: Node3D = cur.get("node")
	if n == null:
		return
	var cb := n.get_node_or_null("cabin")
	if cb == null:
		return
	for c in cb.get_children():
		if c.has_meta("cut") and bool(c.get_meta("cut")):
			c.visible = not on
	var rl := cb.get_node_or_null("room_light")
	if rl != null:
		rl.visible = on
	var ch := n.get_node_or_null("chimney")
	if ch != null:
		ch.visible = not on

func _process(_d: float) -> void:
	if not inside:
		return
	if cur.is_empty() or not camp.list.has(cur):
		inside = false
		return
	# вышел через дверь ногами — обычная камера
	var lp: Vector3 = _xf(cur).affine_inverse() * main.hero.position
	var ih := GEO.inner_half()
	if absf(lp.x) > ih.x + 0.4 or absf(lp.z) > ih.y + 0.4:
		leave(false)
		return
	# джойстик — относительно своей камеры
	main.rig.rotation.y = float(cur["yaw"])
	main.rig.position = main.hero.position

# ---------- мебель ----------

func _size(kind: String, rot: int) -> Vector2:
	var sz: Vector2 = FURN[kind]["size"]
	return Vector2(sz.y, sz.x) if rot % 2 == 1 else sz

## Все вещи в избе: узлы заново.
func furnish(s: Dictionary) -> void:
	var n: Node3D = s.get("node")
	if n == null:
		return
	var old := n.get_node_or_null("furn")
	if old != null:
		old.free()
	var holder := Node3D.new()
	holder.name = "furn"
	n.add_child(holder)
	for f: Dictionary in s["furn"]:
		var fn: Node3D = camp.geo.furniture(String(f["kind"]))
		fn.position = Vector3(f["x"], GEO.floor_y(), f["z"])
		fn.rotation.y = int(f["rot"]) * PI * 0.5
		holder.add_child(fn)
		f["node"] = fn

## Столкновения и сиденья мебели (вызывается из structures._register).
func register_furniture(s: Dictionary) -> void:
	for f: Dictionary in s["furn"]:
		var sz := _size(String(f["kind"]), int(f["rot"]))
		var long_x := sz.x > sz.y
		var r := minf(sz.x, sz.y) * 0.5
		var L := maxf(sz.x, sz.y)
		var n := maxi(1, int(ceil(L / (r * 2.0 + 0.01))))
		for i in n:
			var t := (float(i) + 0.5) / n - 0.5
			var lp := Vector3(f["x"], 0, f["z"]) + (Vector3(t * L, 0, 0) if long_x else Vector3(0, 0, t * L))
			camp._add_block(s, lp, r * 0.8)
		if String(f["kind"]) == "bench":
			var yaw := int(f["rot"]) * PI * 0.5 + PI * 0.5
			camp._add_seat(s, Vector3(f["x"], GEO.floor_y() + 0.47, f["z"]), yaw)

func extra_cap(s: Dictionary) -> float:
	var c := 0.0
	for f: Dictionary in s.get("furn", []):
		match String(f["kind"]):
			"shelf":
				c += 15.0
			"chest":
				c += 40.0
	return c

func has_furn(s: Dictionary, kind: String) -> bool:
	for f: Dictionary in s.get("furn", []):
		if String(f["kind"]) == kind:
			return true
	return false

func _rect(kind: String, x: float, z: float, rot: int) -> Rect2:
	var sz := _size(kind, rot)
	return Rect2(x - sz.x * 0.5, z - sz.y * 0.5, sz.x, sz.y)

## Можно ли поставить вещь в точку (местные координаты пола).
func _fits(kind: String, x: float, z: float, rot: int, skip: Dictionary) -> bool:
	var ih := GEO.inner_half()
	var r := _rect(kind, x, z, rot)
	if r.position.x < -ih.x - 0.01 or r.end.x > ih.x + 0.01 or r.position.y < -ih.y - 0.01 or r.end.y > ih.y + 0.01:
		return false
	# печь в заднем левом углу и проход у двери
	var stove := Rect2(-ih.x, -ih.y, 1.8, 1.75)
	var door := Rect2(-0.6, ih.y - 0.95, 1.2, 1.0)
	if r.intersects(stove) or r.intersects(door):
		return false
	for f: Dictionary in cur.get("furn", []):
		if f == skip:
			continue
		if r.grow(-0.02).intersects(_rect(String(f["kind"]), f["x"], f["z"], int(f["rot"]))):
			return false
	return true

func begin_place(kind: String, move: Dictionary = {}) -> void:
	cancel_place()
	placing = true
	p_kind = kind
	p_move = move
	p_rot = int(move.get("rot", 0))
	if not move.is_empty():
		p_pos = Vector2(move["x"], move["z"])
		(move["node"] as Node3D).visible = false
	else:
		p_pos = _first_free(kind)
	_ghost = camp.geo.furniture(kind)
	GEO.ghostify(_ghost, _ok)
	(cur["node"] as Node3D).add_child(_ghost)
	_update_ghost()

func _first_free(kind: String) -> Vector2:
	var ih := GEO.inner_half()
	var z := ih.y - 0.3
	while z > -ih.y:
		var x := ih.x - 0.3
		while x > -ih.x:
			for rot in 2:
				var sz := _size(kind, rot)
				var px := snappedf(clampf(x, -ih.x + sz.x * 0.5, ih.x - sz.x * 0.5), GRID * 0.5)
				var pz := snappedf(clampf(z, -ih.y + sz.y * 0.5, ih.y - sz.y * 0.5), GRID * 0.5)
				if _fits(kind, px, pz, rot, p_move):
					p_rot = rot
					return Vector2(px, pz)
			x -= GRID
		z -= GRID
	return Vector2.ZERO

func rotate_piece() -> void:
	p_rot = (p_rot + 1) % 4
	_update_ghost()

func _update_ghost() -> void:
	var ih := GEO.inner_half()
	var sz := _size(p_kind, p_rot)
	p_pos.x = clampf(snappedf(p_pos.x - sz.x * 0.5, GRID) + sz.x * 0.5, -ih.x + sz.x * 0.5, ih.x - sz.x * 0.5)
	p_pos.y = clampf(snappedf(p_pos.y - sz.y * 0.5, GRID) + sz.y * 0.5, -ih.y + sz.y * 0.5, ih.y - sz.y * 0.5)
	p_valid = _fits(p_kind, p_pos.x, p_pos.y, p_rot, p_move)
	if _ghost != null:
		_ghost.position = Vector3(p_pos.x, GEO.floor_y() + 0.01, p_pos.y)
		_ghost.rotation.y = p_rot * PI * 0.5
		GEO.ghostify(_ghost, _ok if p_valid else _bad)

func confirm_place() -> bool:
	if not placing:
		return false
	if not p_valid:
		main._say("Здесь не встанет")
		return false
	if p_move.is_empty():
		var cost: Dictionary = FURN[p_kind]["cost"]
		if not camp.can_pay(cost):
			main._say("Не хватает припасов")
			return false
		camp.pay(cost)
		cur["furn"].append({"kind": p_kind, "x": p_pos.x, "z": p_pos.y, "rot": p_rot})
		main._say("Поставлено: " + String(FURN[p_kind]["name"]).to_lower())
	else:
		p_move["x"] = p_pos.x
		p_move["z"] = p_pos.y
		p_move["rot"] = p_rot
	_finish_place()
	return true

func cancel_place() -> void:
	if not placing:
		return
	if not p_move.is_empty() and p_move.get("node") != null:
		(p_move["node"] as Node3D).visible = true
	placing = false
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null

func _finish_place() -> void:
	placing = false
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	furnish(cur)
	camp._register(cur)

func remove_piece(f: Dictionary) -> void:
	cur["furn"].erase(f)
	var cost: Dictionary = FURN[String(f["kind"])]["cost"]
	for k: String in cost:
		camp.give(k, maxi(1, int(cost[k]) / 2))
	main._say("Разобрано, вернулась половина припасов")
	furnish(cur)
	camp._register(cur)

func _unhandled_input(e: InputEvent) -> void:
	if not placing or not inside:
		return
	var pos := Vector2.INF
	if e is InputEventScreenTouch and (e as InputEventScreenTouch).pressed:
		pos = (e as InputEventScreenTouch).position
	elif e is InputEventScreenDrag:
		pos = (e as InputEventScreenDrag).position
	if pos == Vector2.INF:
		return
	# луч из камеры избы на плоскость пола
	var o := cam.project_ray_origin(pos)
	var d := cam.project_ray_normal(pos)
	var fy: float = float(cur["pos"].y) + GEO.floor_y()
	if absf(d.y) < 0.01:
		return
	var t := (fy - o.y) / d.y
	if t <= 0.0:
		return
	var lp := _xf(cur).affine_inverse() * (o + d * t)
	var ih := GEO.inner_half()
	if absf(lp.x) > ih.x + 0.8 or absf(lp.z) > ih.y + 0.8:
		return
	p_pos = Vector2(lp.x, lp.z)
	_update_ghost()
	get_viewport().set_input_as_handled()

# ---------- действия внутри ----------

func _near_piece(max_d: float) -> Dictionary:
	var lp: Vector3 = _xf(cur).affine_inverse() * main.hero.position
	var best: Dictionary = {}
	var bd := max_d
	for f: Dictionary in cur.get("furn", []):
		var r := _rect(String(f["kind"]), f["x"], f["z"], int(f["rot"]))
		var dx := maxf(0.0, maxf(r.position.x - lp.x, lp.x - r.end.x))
		var dz := maxf(0.0, maxf(r.position.y - lp.z, lp.z - r.end.y))
		var d := Vector2(dx, dz).length()
		if d < bd:
			bd = d
			best = f
	return best

func _near_stove() -> bool:
	var lp: Vector3 = _xf(cur).affine_inverse() * main.hero.position
	var ih := GEO.inner_half()
	return lp.x < -ih.x + 2.4 and lp.z < -ih.y + 2.6

func actions() -> Array:
	var out: Array = []
	if placing:
		return out
	var s := cur
	var lp: Vector3 = _xf(s).affine_inverse() * main.hero.position
	if lp.z > GEO.inner_half().y - 1.1 and absf(lp.x) < 0.9:
		out.append(["Выйти", leave])
	if _near_stove():
		out.append(["Печь", func(): camp.ui.open_stove(s)])
	var f := _near_piece(0.7)
	if not f.is_empty():
		match String(f["kind"]):
			"bed":
				out.append(["Спать", func(): camp.sleep(camp.sleep_quality(s) + 0.15)])
			"table":
				out.append(["Поесть за столом", func(): camp.ui.open_table()])
			"workbench":
				out.append(["Верстак", func(): camp.ui.open_bench()])
			"rack":
				out.append(["Сушило", func(): camp.ui.open_rack(s)])
	out.append(["Обстановка", func(): camp.ui.open_furn(s)])
	if out.size() < 5:
		out.append(["Хранилище", func(): camp.ui.open_store(s)])
	return out

# ---------- сушило ----------

## Что можно вялить: [выход, вход].
func rack_recipes() -> Array:
	var out: Array = [["fur", "hide"]]
	for id: String in IT.DEF:
		var d: Dictionary = IT.DEF[id]
		if String(d.get("station", "")) == "rack" and d.has("craft"):
			out.append([id, (d["craft"] as Dictionary).keys()[0]])
	return out

func rack_put(s: Dictionary, out_id: String, in_id: String) -> void:
	var rk: Dictionary = s.get("rack", {})
	if not rk.is_empty():
		main._say("Сушило занято")
		return
	if camp.count(in_id) <= 0:
		return
	camp.take(in_id, 1)
	s["rack"] = {"in": in_id, "out": out_id, "t": 0.0, "need": 4.0, "done": false}
	main._say("На сушиле: " + IT.name_of(in_id).to_lower())

func rack_step(s: Dictionary, dh: float) -> void:
	var rk: Dictionary = s.get("rack", {})
	if rk.is_empty() or bool(rk["done"]):
		return
	# в натопленной избе сохнет вдвое быстрее
	rk["t"] = float(rk["t"]) + dh * (2.0 if bool(s.get("stove_lit", false)) else 1.0)
	if float(rk["t"]) >= float(rk["need"]):
		rk["done"] = true
		main._say("Высохло: " + IT.name_of(String(rk["out"])).to_lower())

func rack_take(s: Dictionary) -> void:
	var rk: Dictionary = s.get("rack", {})
	if rk.is_empty():
		return
	var id := String(rk["out"]) if bool(rk["done"]) else String(rk["in"])
	if not camp.can_carry(id):
		main._say("Короб полон")
		return
	camp.give(id, 1)
	s["rack"] = {}

# ---------- верстак и стол ----------

func bench_make(r: Array) -> void:
	var cost: Dictionary = r[2]
	if not camp.can_pay(cost):
		main._say("Не хватает припасов")
		return
	camp.pay(cost)
	camp.give(String(r[0]), int(r[1]))
	main._say("Сделано: %s ×%d" % [IT.name_of(String(r[0])).to_lower(), int(r[1])])

## Поесть за столом: сытость на треть больше.
func eat_at_table(id: String) -> void:
	var d: Dictionary = IT.DEF.get(id, {})
	if not d.has("eat") or camp.count(id) <= 0:
		return
	var e: Array = d["eat"]
	main.hunger = clampf(float(main.hunger) + float(e[0]) * (1.33 if float(e[0]) > 0.0 else 1.0), 0.0, 1.0)
	main.thirst = clampf(float(main.thirst) + float(e[1]), 0.0, 1.0)
	main.health = clampf(float(main.health) + float(e[2]), 0.05, 1.0)
	camp.take(id, 1)
	main._say("Поел за столом: " + IT.name_of(id).to_lower())
