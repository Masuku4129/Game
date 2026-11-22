extends Node3D
## Мир инструментов: валка деревьев топором (подруб, треск, падение с ускорением и отскоком),
## лежачие стволы (поваленные героем и бурелом из генерации) рубятся на брёвна; брёвна лежат
## на земле, их носят на плече и колют на дрова; копья и лопаты, воткнутые в землю или
## брошенные; полёт копья по дуге с попаданием в зверя (голова/корпус/ноги); сбор бересты,
## лыка, жердей и ягод ножом и руками.
## Деревья — экземпляры MultiMesh (main.tree_grid): при валке экземпляр прячется, а падает
## отдельный MeshInstance3D той же модели (как у бобров в beavers.gd).

const IT = preload("res://scripts/items.gd")
const TM = preload("res://scripts/tool_models.gd")
const SEG := 1.25            # длина бревна, м
const TRUNK_R0 := {"birch": 0.17, "aspen": 0.17, "rowan": 0.17, "larch": 0.17, "spruce": 0.24, "fir": 0.24, "pine": 0.28, "cedar": 0.28}
const TRUNK_R1 := {"birch": 0.05, "aspen": 0.05, "rowan": 0.05, "larch": 0.05, "spruce": 0.05, "fir": 0.05, "pine": 0.08, "cedar": 0.08}
# до какой доли высоты ствол чистый (выше — крона), у ели и пихты сначала обрубают лапник
const CLEAN := {"birch": 0.42, "aspen": 0.42, "rowan": 0.4, "larch": 0.42, "spruce": 0.8, "fir": 0.8, "pine": 0.62, "cedar": 0.32}
const BARK := {"birch": Color(0.86, 0.84, 0.78), "aspen": Color(0.6, 0.62, 0.55), "rowan": Color(0.42, 0.37, 0.32), "larch": Color(0.47, 0.33, 0.22),
	"spruce": Color(0.36, 0.27, 0.2), "fir": Color(0.36, 0.27, 0.2), "pine": Color(0.52, 0.36, 0.24), "cedar": Color(0.36, 0.27, 0.2)}
const WOOD := Color(0.9, 0.76, 0.52)
# что даёт куст ножом и руками
const FIBRE_KINDS := ["willow", "alder", "bush", "rose", "ernik", "cherry", "fireweed"]
const BERRY_KINDS := ["raspberry", "currant", "bilberry", "lingon", "cranberry", "cloudberry"]

var main: Node3D
var items: Array = []        # {"id", "node", "pos"} — копья, лопаты, брёвна на земле
var flying: Array = []       # {"node", "vel", "t"}
var fells := {}              # id дерева → FellTree
var trunks: Array = []       # лежачие стволы: FellTree (лёг) или GenTrunk
var uses := {}               # место сбора → [осталось, день восстановления]
var wounds: Array = []       # [зверь, мин. усталость, до (с)]
var chips: CPUParticles3D
var rng := RandomNumberGenerator.new()
var _t := 0.0

func _ready() -> void:
	rng.seed = 404
	chips = CPUParticles3D.new()
	chips.emitting = false
	chips.one_shot = true
	chips.amount = 14
	chips.lifetime = 1.1
	chips.explosiveness = 0.95
	chips.direction = Vector3(0, 0.6, 1)
	chips.spread = 55.0
	chips.initial_velocity_min = 1.6
	chips.initial_velocity_max = 3.4
	chips.gravity = Vector3(0, -9.8, 0)
	chips.angular_velocity_min = -400.0
	chips.angular_velocity_max = 400.0
	chips.scale_amount_min = 0.6
	chips.scale_amount_max = 1.4
	chips.local_coords = false
	var cm := BoxMesh.new()
	cm.size = Vector3(0.035, 0.008, 0.02)
	var mt := StandardMaterial3D.new()
	mt.albedo_color = WOOD
	mt.roughness = 1.0
	cm.material = mt
	chips.mesh = cm
	add_child(chips)

func _chips(p: Vector3, toward: Vector3) -> void:
	chips.global_position = p
	var d := toward - p
	d.y = 0.0
	chips.direction = (d.normalized() + Vector3(0, 0.7, 0)).normalized() if d.length() > 0.01 else Vector3.UP
	chips.restart()
	chips.emitting = true

func _snd(n: String, p: Vector3, db: float, pitch: float = 1.0) -> void:
	if main != null and main.sfx != null:
		main.sfx.play_at(n, p, db, pitch * rng.randf_range(0.93, 1.07))

func _give(id: String, n: int) -> int:
	var got := 0
	for i in n:
		if main.inventory != null and not main.inventory.can_add(id):
			break
		main.inv[id] = int(main.inv.get(id, 0)) + 1
		got += 1
	if got > 0:
		main._say("+%d %s" % [got, IT.name_of(id).to_lower()])
	elif n > 0:
		main._say("Короб полон")
	return got

# ---------- деревья ----------

static func kind_of(rec: Array) -> String:
	return String(rec[3]).rstrip("0123456789")

## Ближайшее стоящее дерево: ствол в пределах r от героя (с учётом толщины).
func find_tree(p: Vector3, r: float) -> Array:
	var best: Array = []
	var bd := 1e9
	var g := Vector2i(floori(p.x / 16.0), floori(p.z / 16.0))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var k := Vector2i(g.x + dx, g.y + dz)
			if not main.tree_grid.has(k):
				continue
			for rec: Array in main.tree_grid[k]:
				var xf: Transform3D = rec[2]
				if xf.origin.y < -100.0:
					continue
				var s := xf.basis.x.length()
				var tr: float = float(TRUNK_R0.get(kind_of(rec), 0.2)) * s
				var d := Vector2(xf.origin.x - p.x, xf.origin.z - p.z).length() - tr
				if d < r and d < bd:
					bd = d
					best = rec
	return best

func is_young(rec: Array) -> bool:
	return (rec[2] as Transform3D).basis.x.length() < 0.5

func tree_pos(rec: Array) -> Vector3:
	return (rec[2] as Transform3D).origin

func _hide_tree(rec: Array) -> void:
	var o: Vector3 = (rec[2] as Transform3D).origin
	rec[2] = Transform3D(Basis().scaled(Vector3(0.0001, 0.0001, 0.0001)), Vector3(o.x, -500.0, o.z))
	(rec[0] as MultiMesh).set_instance_transform(rec[1], rec[2])
	main._update_near(true)

## Удар топором по стоящему дереву. true — дерево пошло падать (рубить больше нечего).
func chop_tree(rec: Array, hero_p: Vector3, hits: int) -> bool:
	var id: int = rec[4]
	var f: FellTree = fells.get(id, null)
	if f == null:
		if (rec[2] as Transform3D).origin.y < -100.0:
			return true
		var kind := kind_of(rec)
		f = FellTree.new()
		add_child(f)
		f.setup(main.near_mesh[rec[3]], rec[2], kind, main, hero_p)
		main.pv.fade_list.append(f.bm)
		fells[id] = f
		_hide_tree(rec)
	if f.phase != "stand":
		return true
	f.hit()
	var np := f.notch_world()
	_chips(np, hero_p + Vector3(0, 1.0, 0))
	_snd("chop", np, 2.0)
	if f.phase == "fall":
		_snd("crack", np + Vector3(0, 2, 0), 6.0, 1.0)
		main._say("Дерево падает!")
		return true
	return false

## Лежачий ствол рядом: {"obj": FellTree|GenTrunk} или {"spot": запись бурелома}.
func find_trunk(p: Vector3, r: float) -> Dictionary:
	var best := {}
	var bd := r
	for t: Node3D in trunks:
		if not t.has_logs():
			continue
		var d := _dist2(p, t.cut_point())
		if d < bd:
			bd = d
			best = {"obj": t}
	if main.get("fallen_spots") == null:
		return best
	var c := Vector2i(floori(p.x / 16.0), floori(p.z / 16.0))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var k := Vector2i(c.x + dx, c.y + dz)
			if not main.fallen_spots.has(k):
				continue
			for sp: Dictionary in main.fallen_spots[k]:
				if sp.get("done", false):
					continue
				var a: Vector3 = sp["a"]
				var b: Vector3 = sp["b"]
				var cut := a + (b - a).normalized() * minf(SEG * 0.5 + 0.3, a.distance_to(b) * 0.5)
				var d := _dist2(p, cut)
				if d < bd:
					bd = d
					best = {"spot": sp}
	return best

func trunk_cut_point(tr: Dictionary) -> Vector3:
	if tr.has("obj"):
		return (tr["obj"] as Node3D).cut_point()
	var sp: Dictionary = tr["spot"]
	var a: Vector3 = sp["a"]
	var b: Vector3 = sp["b"]
	return a + (b - a).normalized() * (SEG * 0.5 + 0.3)

func _dist2(p: Vector3, q: Vector3) -> float:
	return Vector2(p.x - q.x, p.z - q.z).length()

## Удар по лежачему стволу; каждые несколько ударов отваливается бревно. true — бревно готово.
func chop_trunk(tr: Dictionary, hits: int) -> bool:
	if not tr.has("obj"):
		var sp: Dictionary = tr["spot"]
		if sp.get("done", false):
			return true
		sp["done"] = true
		var g := GenTrunk.new()
		add_child(g)
		g.setup(sp, main)
		_unblock_spot(sp)
		trunks.append(g)
		tr["obj"] = g
	var t: Node3D = tr["obj"]
	if not t.has_logs():
		return true
	var cp: Vector3 = t.cut_point()
	_chips(cp + Vector3(0, 0.25, 0), main.hero.position + Vector3(0, 1, 0))
	_snd("chop", cp, 0.0, 0.92)
	var need: int = t.hits_per_log()
	if t is FellTree and t.limbs_left():
		if hits >= 3:
			t.delimb()
			_give("spruce_twigs", 3)
			main._say("Лапник обрублен")
			return true
		return false
	if hits >= need:
		var lg: Array = t.cut_log()
		if not lg.is_empty():
			_spawn_log(lg[0], lg[1], float(lg[2]), float(lg[3]), lg[4])
			_snd("thud", lg[0], -6.0, 1.6)
		return true
	return false

## Убрать препятствия бурелома из генерации (твёрдые тела, комель, сиденье), спрятать экземпляр.
func _unblock_spot(sp: Dictionary) -> void:
	var mm: MultiMesh = sp["mm"]
	var xf: Transform3D = sp["xf"]
	mm.set_instance_transform(int(sp["i"]), Transform3D(Basis().scaled(Vector3(0.0001, 0.0001, 0.0001)), xf.origin - Vector3(0, 500, 0)))
	var a: Vector3 = sp["a"]
	var b: Vector3 = sp["b"]
	var ext := a.distance_to(b) * 0.5 + 2.0
	var c := (a + b) * 0.5
	for gx in range(floori((c.x - ext) / 8.0), floori((c.x + ext) / 8.0) + 1):
		for gz in range(floori((c.z - ext) / 8.0), floori((c.z + ext) / 8.0) + 1):
			var k := Vector2i(gx, gz)
			if main.solids.has(k):
				var arr: Array = main.solids[k]
				for i in range(arr.size() - 1, -1, -1):
					var sd: Array = arr[i]
					if int(sd[0]) == 1 and _seg_dist(sd[1], a, b) < 0.8 and _seg_dist(sd[2], a, b) < 0.8:
						arr.remove_at(i)
			if main.blockers.has(k):
				var bl: Array = main.blockers[k]
				for i in range(bl.size() - 1, -1, -1):
					var q: Vector3 = bl[i]
					if _seg_dist(Vector3(q.x, a.y, q.y), a, b) < 0.6 and q.z >= 0.45:
						bl.remove_at(i)
			if main.seats.has(k):
				var st: Array = main.seats[k]
				for i in range(st.size() - 1, -1, -1):
					var s0: Vector3 = (st[i] as Array)[0]
					if _seg_dist(Vector3(s0.x, a.y, s0.z), a, b) < 0.5:
						st.remove_at(i)

static func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var t := clampf(Vector2(p.x - a.x, p.z - a.z).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return Vector2(p.x - a.x - ab.x * t, p.z - a.z - ab.y * t).length()

# ---------- брёвна и вещи на земле ----------

func _spawn_log(c: Vector3, axis: Vector3, L: float, r: float, bark: Color) -> void:
	var gy: float = main.ground_at(c.x, c.z)
	var ah := Vector3(axis.x, 0, axis.z).normalized()
	if ah.length() < 0.1:
		ah = Vector3.RIGHT
	var xf := Transform3D(Basis(Vector3.UP.cross(ah).normalized(), ah, Vector3.ZERO), Vector3(c.x, gy + r * 0.92, c.z))
	xf.basis.z = xf.basis.x.cross(xf.basis.y).normalized()
	var mi := MeshInstance3D.new()
	mi.mesh = TM.log_mesh(snappedf(L, 0.05), snappedf(r, 0.01), bark, rng.randi_range(1, 4))
	add_child(mi)
	mi.global_transform = xf
	items.append({"id": "log", "node": mi, "pos": xf.origin, "r": r, "bark": bark})

## Положить бревно с плеча на землю.
func drop_log(p: Vector3, yaw: float) -> void:
	var ax := Vector3(sin(yaw), 0, cos(yaw))
	_spawn_log(p, ax, 1.25, 0.13, Color(0.42, 0.33, 0.24))

func find_log(p: Vector3, r: float) -> Node3D:
	var best: Node3D = null
	var bd := r
	for it: Dictionary in items:
		if it["id"] != "log":
			continue
		var d := _dist2(p, it["pos"])
		if d < bd:
			bd = d
			best = it["node"]
	return best

## Брёвна рядом (для стройки): [{"node", "pos", "r"}].
func logs_near(p: Vector3, r: float) -> Array:
	var out: Array = []
	for it: Dictionary in items:
		if it["id"] == "log" and _dist2(p, it["pos"]) < r:
			out.append(it)
	return out

## Расколоть бревно на дрова: три удара.
func split_log(node: Node3D, hits: int) -> bool:
	var it := _item_of(node)
	if it.is_empty():
		return true
	_chips(node.global_position + Vector3(0, 0.15, 0), main.hero.position + Vector3(0, 1, 0))
	_snd("chop", node.global_position, 0.0, 1.12)
	if hits >= 3:
		items.erase(it)
		node.queue_free()
		_give("firewood", 4)
		return true
	return false

func _item_of(node: Node3D) -> Dictionary:
	for it: Dictionary in items:
		if it["node"] == node:
			return it
	return {}

func nearest_item(p: Vector3, r: float) -> Dictionary:
	var best := {}
	var bd := r
	for it: Dictionary in items:
		var q: Vector3 = it["pos"]
		if absf(q.y - p.y) > 2.5:
			continue
		var d := _dist2(p, q)
		if d < bd:
			bd = d
			best = it
	return best

func take_item(it: Dictionary) -> bool:
	if not items.has(it):
		return false
	items.erase(it)
	(it["node"] as Node3D).queue_free()
	return true

## Поставить вещь в мир (воткнутое копьё, лопата).
func place_item(id: String, xf: Transform3D, _lying: bool) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = TM.mesh_of(id)
	add_child(mi)
	mi.global_transform = xf
	items.append({"id": id, "node": mi, "pos": xf.origin + xf.basis.y * -0.6})

# ---------- копьё: бросок, удар ----------

## Цель для броска: ближайший зверь впереди (до 30 м, в пределах ±35°).
func aim_target(p: Vector3, yaw: float) -> Vector3:
	if main.animals == null:
		return Vector3.INF
	var best := Vector3.INF
	var bd := 30.0
	for a: Node3D in main.animals.list:
		if a.dead or not a.visible:
			continue
		var d: Vector3 = a.position - p
		var dl := Vector2(d.x, d.z).length()
		if dl > bd or dl < 1.0:
			continue
		if absf(wrapf(atan2(d.x, d.z) - yaw, -PI, PI)) > 0.62:
			continue
		bd = dl
		best = a.position + Vector3(0, float(a.parts.get("H", 0.6)) * 0.62, 0)
	return best

## Скорость броска: по цели — баллистика (пологая дуга), без цели — вперёд и чуть вверх.
func throw_velocity(o: Vector3, dir: Vector3, aim: Vector3) -> Vector3:
	var V := 18.0
	var g := 9.8
	var h := Vector3(dir.x, 0, dir.z).normalized()
	if aim == Vector3.INF:
		return (h * cos(0.14) + Vector3.UP * sin(0.14)) * V
	var dv := aim - o
	var dx := Vector2(dv.x, dv.z).length()
	h = Vector3(dv.x, 0, dv.z) / maxf(dx, 0.001)
	var disc := V * V * V * V - g * (g * dx * dx + 2.0 * dv.y * V * V)
	var th := PI * 0.25
	if disc >= 0.0:
		th = atan((V * V - sqrt(disc)) / (g * dx))
	return (h * cos(th) + Vector3.UP * sin(th)) * V

func throw_spear(xf: Transform3D, vel: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = TM.spear()
	add_child(mi)
	mi.global_transform = xf
	flying.append({"node": mi, "vel": vel, "t": 0.0, "pos": xf.origin})
	_snd("whoosh", xf.origin, -2.0)

func _spear_basis(d: Vector3) -> Basis:
	var A := d.normalized()
	var X := (Vector3.UP.cross(A)).normalized() if absf(A.y) < 0.98 else Vector3.RIGHT
	return Basis(X, A, X.cross(A))

## Тело зверя: капсула вдоль корпуса + ноги под ним. Возвращает зону попадания ("" — мимо).
func _hit_zone(a: Node3D, p0: Vector3, p1: Vector3, extra: float) -> Array:
	var L: float = float(a.parts.get("L", 1.0))
	var H: float = float(a.parts.get("H", 0.7))
	var hd: float = a.heading
	var fwd := Vector3(sin(hd), 0, cos(hd))
	var base: Vector3 = a.position
	var c := base + Vector3(0, H * 0.66, 0)
	var ba := c - fwd * L * 0.42
	var bb := c + fwd * L * 0.42
	var rad := maxf(H * 0.27, 0.09) + extra
	var cp := _closest_seg_seg(p0, p1, ba, bb)
	var hp: Vector3 = cp[0]
	var on_body := (cp[0] as Vector3).distance_to(cp[1]) < rad
	if not on_body:
		# ноги: узкий короб под корпусом
		var steps := 6
		on_body = false
		for i in steps + 1:
			var q := p0.lerp(p1, float(i) / steps)
			var rel := q - base
			var al := rel.dot(fwd)
			var lat := (rel - fwd * al)
			lat.y = 0.0
			if absf(al) < L * 0.42 and lat.length() < 0.14 + extra and rel.y > 0.02 and rel.y < H * 0.45:
				hp = q
				return ["legs", hp]
		return []
	var rel2 := hp - base
	var along := rel2.dot(fwd) / L
	var hh := rel2.y / H
	if along > 0.3 and hh > 0.55:
		return ["head", hp]
	if hh < 0.42:
		return ["legs", hp]
	return ["body", hp]

static func _closest_seg_seg(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> Array:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1e-6 and e <= 1e-6:
		return [p1, p2]
	if a <= 1e-6:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 1e-6:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var den := a * e - b * b
			if den != 0.0:
				s = clampf((b * f - c * e) / den, 0.0, 1.0)
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return [p1 + d1 * s, p2 + d2 * t]

## Урон: от скорости и места попадания. Голова — смертельно для мелких и средних,
## ноги — зверь хромает (медленнее бежит), корпус — ранен и убегает.
func _damage(a: Node3D, zone: String, speed: float) -> void:
	var mult: float = {"head": 2.6, "body": 1.3, "legs": 0.55}[zone]
	if main.get("hunt") != null:
		# охота (hunt.gd): доля жизни косули, крепость вида учитывается там; кровь и след — тоже там
		main.hunt.hit_animal(a, speed / 18.0 * mult * 0.85, main.hero.position)
	else:
		var pts := int(floor(speed / 12.0 * mult + 0.5))
		if zone != "legs":
			pts = maxi(pts, 1)
		for i in pts:
			if a.dead:
				break
			a.bitten(main.hero)
		if not a.dead and a.state != "flee":
			a._flee_from(main.hero, 8.0)
	if a.dead:
		main._say("Добыча! " + {"head": "Точно в голову", "body": "Под лопатку", "legs": "По ногам"}[zone])
	else:
		# ранен в ноги — хромает (медленнее бежит), в корпус — слабеет
		wounds.append([a, 0.95 if zone == "legs" else 0.6, _t + (70.0 if zone == "legs" else 45.0)])
		main._say({"head": "Попадание в голову — зверь ранен", "body": "Ранен в бок — уходит", "legs": "Ранен в ногу — хромает"}[zone])

## Удар копьём: острие tip, достаёт до зверя впереди.
func stab(p: Vector3, tip: Vector3, yaw: float) -> void:
	if main.animals == null:
		return
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var from := tip - fwd * 0.9
	for a: Node3D in main.animals.near(p, 4.0):
		if a.dead:
			continue
		var z: Array = _hit_zone(a, from, tip + fwd * 0.15, 0.08)
		if not z.is_empty():
			_snd("thunk", z[1], 0.0, 0.8)
			_damage(a, z[0], 11.0)
			return
	_snd("whoosh", tip, -8.0, 1.3)

func _process(delta: float) -> void:
	if main == null:
		return
	_t += delta
	if OS.get_environment("TOOLS_TEST") != "":
		_test(delta)
	for f: FellTree in fells.values():
		if f.phase == "fall":
			f.step(delta)
			if f.phase == "down":
				_snd("thud", f.landing_point(), 10.0)
				trunks.append(f)
	_fly(delta)
	for i in range(wounds.size() - 1, -1, -1):
		var w: Array = wounds[i]
		var a: Node3D = w[0]
		if a.dead or _t > float(w[2]):
			wounds.remove_at(i)
		else:
			a.tire = maxf(a.tire, float(w[1]))

func _fly(delta: float) -> void:
	for i in range(flying.size() - 1, -1, -1):
		var fl: Dictionary = flying[i]
		var p0: Vector3 = fl["pos"]
		var v: Vector3 = fl["vel"]
		v += Vector3(0, -9.8, 0) * delta
		v *= 1.0 - 0.02 * delta
		var p1 := p0 + v * delta
		fl["t"] = float(fl["t"]) + delta
		var tip_off := 1.1
		var dir := v.normalized()
		var t0 := p0 + dir * tip_off
		var t1 := p1 + dir * tip_off
		var node: MeshInstance3D = fl["node"]
		var stop := false
		# звери
		if main.animals != null:
			for a: Node3D in main.animals.near(t1, 5.0):
				if a.dead:
					continue
				var z: Array = _hit_zone(a, t0, t1, 0.0)
				if not z.is_empty():
					_snd("thunk", z[1], 4.0)
					_damage(a, z[0], v.length())
					# копьё падает рядом со зверем (у убитого остаётся торчать)
					var hp: Vector3 = z[1]
					if a.dead:
						_stick(node, hp, dir, 0.25)
					else:
						var gp := hp + Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4))
						gp.y = main.ground_at(gp.x, gp.z)
						_lie(node, gp, dir)
					stop = true
					break
		# стволы деревьев
		if not stop and t1.y - main.height(t1.x, t1.z) < 7.0 and main.blocked(t1.x, t1.z, 0.0):
			_stick(node, t1, dir, 0.12)
			_snd("thunk", t1, 2.0, 1.15)
			stop = true
		# земля
		if not stop:
			var gy: float = main.ground_at(t1.x, t1.z)
			if t1.y <= gy or float(fl["t"]) > 6.0:
				var hit := t1
				hit.y = gy
				_stick(node, hit, dir, 0.22 if dir.y < -0.25 else 0.08)
				_snd("thunk", hit, -2.0, 0.7)
				stop = true
		if stop:
			flying.remove_at(i)
			continue
		fl["pos"] = p1
		fl["vel"] = v
		node.global_transform = Transform3D(_spear_basis(dir), p1)

## Копьё вонзилось: острие на depth в цель.
func _stick(node: MeshInstance3D, hit: Vector3, dir: Vector3, depth: float) -> void:
	var o := hit - dir.normalized() * (1.1 - depth)
	node.global_transform = Transform3D(_spear_basis(dir), o)
	items.append({"id": "spear", "node": node, "pos": o})

## Копьё отскочило и легло на землю.
func _lie(node: MeshInstance3D, p: Vector3, dir: Vector3) -> void:
	var h := Vector3(dir.x, 0, dir.z).normalized()
	if h.length() < 0.1:
		h = Vector3.FORWARD
	h = h.rotated(Vector3.UP, rng.randf_range(-0.8, 0.8))
	node.global_transform = Transform3D(_spear_basis(h), p + Vector3(0, 0.02, 0) - h * 0.1)
	items.append({"id": "spear", "node": node, "pos": p})

# ---------- сбор: береста, лыко, жерди, ягоды ----------

func _spot_left(key: String, full: int) -> int:
	if not uses.has(key):
		return full
	var u: Array = uses[key]
	if int(u[0]) <= 0 and int(main.day_count) >= int(u[1]):
		uses.erase(key)
		return full
	return int(u[0])

func _spend(key: String, full: int) -> void:
	var left := _spot_left(key, full) - 1
	uses[key] = [left, int(main.day_count) + 2]

func _res_near(p: Vector3, r: float, kinds: Array) -> Array:
	if main.get("res_spots") == null:
		return []
	var best: Array = []
	var bd := r
	var c := Vector2i(floori(p.x / 8.0), floori(p.z / 8.0))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var k := Vector2i(c.x + dx, c.y + dz)
			if not main.res_spots.has(k):
				continue
			for s: Array in main.res_spots[k]:
				if not kinds.has(s[1]):
					continue
				var d := _dist2(p, s[0])
				if d < bd:
					bd = d
					best = s
	return best

## Что можно сделать ножом рядом: {"label", "pos", "type", ...}.
func knife_target(p: Vector3) -> Dictionary:
	var it: Array = main.find_pick(p)
	if not it.is_empty() and it[1] == "berry":
		return {"label": "Срезать ягоды", "pos": it[0], "type": "pick", "it": it}
	var bs := _res_near(p, 1.5, BERRY_KINDS)
	if not bs.is_empty() and _spot_left(_key(bs[0]), 3) > 0:
		return {"label": "Собрать ягоды", "pos": bs[0], "type": "berry", "key": _key(bs[0])}
	var t := find_tree(p, 1.2)
	if not t.is_empty():
		if is_young(t):
			return {"label": "Срезать жердь", "pos": tree_pos(t), "type": "young", "rec": t}
		if kind_of(t) == "birch" and _spot_left("t%d" % int(t[4]), 2) > 0:
			return {"label": "Снять бересту", "pos": tree_pos(t), "type": "bark", "key": "t%d" % int(t[4])}
	var fs := _res_near(p, 1.5, FIBRE_KINDS)
	if not fs.is_empty() and _spot_left(_key(fs[0]), 3) > 0:
		var lbl := "Нарезать лыко" if fs[1] in ["willow", "alder", "fireweed"] else "Нарезать прутья"
		return {"label": lbl, "pos": fs[0], "type": "fibre", "kind": fs[1], "key": _key(fs[0])}
	return {}

## Что можно сделать голыми руками (кнопка «Действие» при пустых руках).
func hand_target(p: Vector3) -> Dictionary:
	var t := find_tree(p, 1.0)
	if not t.is_empty() and is_young(t):
		return {"label": "Выломать жердь", "pos": tree_pos(t), "type": "young", "rec": t}
	var bs := _res_near(p, 1.4, BERRY_KINDS)
	if not bs.is_empty() and _spot_left(_key(bs[0]), 3) > 0:
		return {"label": "Собрать ягоды", "pos": bs[0], "type": "berry", "key": _key(bs[0])}
	var fs := _res_near(p, 1.4, ["willow", "alder"])
	if not fs.is_empty() and _spot_left(_key(fs[0]), 3) > 0:
		return {"label": "Надрать лыка", "pos": fs[0], "type": "fibre", "kind": fs[1], "key": _key(fs[0])}
	return {}

func _key(p: Vector3) -> String:
	return "%d_%d" % [int(round(p.x * 4.0)), int(round(p.z * 4.0))]

## Результат сбора (по концу движения). knife — ножом (быстрее и больше).
func harvest(r: Dictionary, knife: bool) -> void:
	match String(r["type"]):
		"pick":
			var it: Array = r["it"]
			var q: Vector3 = it[0]
			var k := Vector2i(floori(q.x / 8.0), floori(q.z / 8.0))
			if main.pickables.has(k) and (main.pickables[k] as Array).has(it):
				main.take_pick(it)
				if knife:
					_give("berry", 1)
		"berry":
			_spend(r["key"], 3)
			_give("berry", 2 if knife else 1)
			_snd("cut", r["pos"], -6.0)
		"bark":
			_spend(r["key"], 2)
			_give("bark", 1)
			_snd("cut", r["pos"], -4.0, 0.8)
		"young":
			var rec: Array = r["rec"]
			if (rec[2] as Transform3D).origin.y > -100.0:
				_hide_tree(rec)
				_give("branch", 1)
				_snd("crack", r["pos"], -10.0, 2.2)
		"fibre":
			_spend(r["key"], 3)
			var kind: String = r["kind"]
			if kind in ["willow", "alder"]:
				_give("fiber", 2 if knife else 1)
				if knife and rng.randf() < 0.5:
					_give("branch", 1)
			elif kind == "fireweed":
				_give("fiber", 1)
			else:
				_give("fiber", 1)
				_give("twig", 1)
			_snd("cut", r["pos"], -4.0)

# ======================================================================
## Срубаемое дерево: пень с подрубом, верх на шарнире, падение и разделка на брёвна.
class FellTree extends Node3D:
	var main: Node3D
	var kind := ""
	var xf := Transform3D()
	var s := 1.0
	var r0 := 0.2          # радиус ствола (в осях модели)
	var r1 := 0.05
	var H := 10.0          # высота модели
	var notch := 0.7       # высота подруба (в осях модели)
	var nh := 0.14
	var k := 0.0           # глубина подруба 0..1
	var need := 8
	var hits := 0
	var phase := "stand"   # stand, fall, down
	var face_a := 0.0      # угол стороны подруба (к герою) в осях модели
	var dir := Vector3.FORWARD
	var axis := Vector3.RIGHT
	var th := 0.0
	var w := 0.0
	var th_g := 1.5
	var bounce := 0
	var pivot := Node3D.new()
	var top := MeshInstance3D.new()
	var stump := MeshInstance3D.new()
	var upper := MeshInstance3D.new()
	var cap := MeshInstance3D.new()
	var bm: ShaderMaterial
	var clip := 0.0
	var limbs := false
	var bark := Color(0.4, 0.3, 0.2)
	var logs_cut := 0

	func setup(mesh: Mesh, t: Transform3D, kd: String, m: Node3D, hero_p: Vector3) -> void:
		main = m
		kind = kd
		xf = t
		s = t.basis.x.length()
		r0 = float(TRUNK_R0.get(kd, 0.2))
		r1 = float(TRUNK_R1.get(kd, 0.05))
		H = mesh.get_aabb().end.y
		bark = BARK.get(kd, Color(0.4, 0.3, 0.2))
		notch = 0.78 / s
		nh = 0.16 / s
		need = 4 + int(r0 * s * 22.0)
		limbs = kd in ["spruce", "fir"]
		var to_h := hero_p - t.origin
		to_h.y = 0.0
		if to_h.length() < 0.01:
			to_h = Vector3.FORWARD
		to_h = to_h.normalized()
		var lh := (t.basis.inverse() * to_h)
		face_a = atan2(lh.z, lh.x)
		# падает от героя, с разбросом
		dir = (-to_h).rotated(Vector3.UP, randf_range(-0.35, 0.35))
		axis = Vector3.UP.cross(dir).normalized()
		pivot.position = t * Vector3(0, notch, 0)
		add_child(pivot)
		top.mesh = mesh
		top.transform = Transform3D(t.basis, t.origin - pivot.position)
		bm = (mesh.surface_get_material(0) as ShaderMaterial).duplicate()
		clip = notch + nh
		bm.set_shader_parameter("clip_y", clip)
		top.set_surface_override_material(0, bm)
		pivot.add_child(top)
		upper.transform = top.transform
		upper.material_override = TM.mat()
		pivot.add_child(upper)
		stump.material_override = TM.mat()
		stump.transform = t
		add_child(stump)
		cap.mesh = _disc_mesh()
		cap.material_override = TM.mat()
		cap.visible = false
		top.add_child(cap)
		_rebuild()

	func _r_at(y: float) -> float:
		return lerpf(r0, r1, clampf(y / (H * 0.9), 0.0, 1.0))

	## Радиус с подрубом: клин со стороны героя.
	func _cut_r(y: float, a: float) -> float:
		var dy := absf(y - notch) / nh
		var depth := k * 0.8 * maxf(0.0, 1.0 - dy)
		var fa := clampf(cos(a - face_a) * 1.5 + 0.35, 0.0, 1.0)
		return _r_at(y) * (1.0 - depth * fa)

	func _ring_mesh(y0: float, y1: float, n_y: int) -> ArrayMesh:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var sides := 12
		var nv := 0
		for i in n_y + 1:
			var y := lerpf(y0, y1, float(i) / n_y)
			for j in sides + 1:
				var a := TAU * float(j) / sides
				var rr := _cut_r(y, a)
				var cut := 1.0 - rr / maxf(_r_at(y), 0.001)
				st.set_color(bark.lerp(WOOD, smoothstep(0.03, 0.12, cut)))
				st.set_uv(Vector2(float(j) / sides, y * s * 2.0))
				st.add_vertex(Vector3(cos(a) * rr, y, sin(a) * rr))
				nv += 1
		for i in n_y:
			for j in sides:
				var q := i * (sides + 1) + j
				for id in [q, q + sides + 1, q + 1, q + 1, q + sides + 1, q + sides + 2]:
					st.add_index(id)
		st.generate_normals()
		return st.commit()

	func _disc_mesh() -> ArrayMesh:
		var b := TM.B.new(3)
		for ring in 3:
			var ra := float(ring) / 3.0
			var rb := float(ring + 1) / 3.0
			var c := WOOD.darkened(0.06 * ring + (0.2 if ring == 2 else 0.0))
			for j in 10:
				var a0 := TAU * j / 10.0
				var a1 := TAU * (j + 1) / 10.0
				b.tri(Vector3(cos(a0) * ra, 0, sin(a0) * ra), Vector3(cos(a0) * rb, 0, sin(a0) * rb), Vector3(cos(a1) * rb, 0, sin(a1) * rb), c)
				if ring > 0:
					b.tri(Vector3(cos(a0) * ra, 0, sin(a0) * ra), Vector3(cos(a1) * rb, 0, sin(a1) * rb), Vector3(cos(a1) * ra, 0, sin(a1) * ra), c)
		return b.commit(TM.mat())

	func _rebuild() -> void:
		stump.mesh = _ring_mesh(-0.25 / s, notch, 5)
		upper.mesh = _ring_mesh(notch, notch + nh, 3)

	func notch_world() -> Vector3:
		var lp := Vector3(cos(face_a), 0, sin(face_a)) * r0 * 0.9 + Vector3(0, notch, 0)
		return xf * lp

	func hit() -> void:
		hits += 1
		k = clampf(float(hits) / need, 0.0, 1.0)
		_rebuild()
		if hits >= need:
			_start_fall()

	func _start_fall() -> void:
		phase = "fall"
		th = 0.025
		w = 0.03
		var L := H * s
		var d := L * 0.55
		var q := pivot.position + dir * d
		var gy: float = main.ground_at(q.x, q.z) if main != null else 0.0
		var drop := pivot.position.y - gy - r0 * s * 0.5
		th_g = clampf(PI * 0.5 + atan2(drop, d), 1.2, 1.9)

	## Падение: стержень на шарнире (ускорение растёт с наклоном), удар и затухающие отскоки.
	func step(delta: float) -> void:
		var L := H * s
		var dt := minf(delta, 0.05) * 0.5
		for i in 2:
			w += 1.5 * 9.8 / maxf(L * 0.9, 1.0) * sin(th) * dt
			th += w * dt
			if th >= th_g and w > 0.0:
				th = th_g
				bounce += 1
				w = -w * 0.26
				if bounce >= 3 or absf(w) < 0.1:
					w = 0.0
					phase = "down"
					_lay()
					break
		pivot.basis = Basis(axis, th)

	func landing_point() -> Vector3:
		return pivot.position + dir * H * s * 0.45

	## Лёг: ствол становится твёрдым (по нему можно пройти).
	var _solid: Array = []
	func _lay() -> void:
		_update_solid()

	func _update_solid() -> void:
		if main == null:
			return
		_remove_solid()
		var a := _world_y(clip + 0.3 / s)
		var b := _world_y(H * float(CLEAN.get(kind, 0.4)))
		if a.distance_to(b) < 0.5:
			return
		_solid = [1, a, b, _r_at(clip) * s * 0.9, 0.0]
		main._add_solid(_solid)

	func _remove_solid() -> void:
		if _solid.is_empty():
			return
		for arr: Array in main.solids.values():
			arr.erase(_solid)
		_solid = []

	func _world_y(y: float) -> Vector3:
		return top.global_transform * Vector3(0, y, 0)

	func limbs_left() -> bool:
		return limbs

	## Обрубить лапник: крона (хвоя) убирается, остаётся голый ствол.
	func delimb() -> void:
		limbs = false
		var src: Mesh = top.mesh
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, src.surface_get_arrays(0))
		top.mesh = m
		top.set_surface_override_material(0, bm)

	func hits_per_log() -> int:
		return 2 + int(_r_at(clip) * s * 12.0)

	func has_logs() -> bool:
		return phase == "down" and (limbs or clip + SEG / s < H * float(CLEAN.get(kind, 0.4)))

	func cut_point() -> Vector3:
		var y := clip + SEG / s * (0.5 if limbs else 1.0)
		var p := _world_y(minf(y, H * 0.5))
		return p

	## Отделить бревно: [центр, ось, длина, радиус, цвет коры] или [].
	func cut_log() -> Array:
		if not has_logs():
			return []
		var y0 := clip
		var y1 := clip + SEG / s
		var c := _world_y((y0 + y1) * 0.5)
		var ax := _world_y(y1) - _world_y(y0)
		clip = y1
		bm.set_shader_parameter("clip_y", clip)
		upper.visible = false
		cap.visible = true
		var rr := _r_at(clip)
		cap.transform = Transform3D(Basis().scaled(Vector3(rr, 1, rr)), Vector3(0, clip + 0.002, 0))
		logs_cut += 1
		_update_solid()
		return [c, ax.normalized(), SEG, _r_at((y0 + y1) * 0.5) * s, bark]

## Бурелом из генерации, превращённый в рубимый ствол: прямой отрезок a→b с корой.
class GenTrunk extends Node3D:
	var a := Vector3.ZERO
	var b := Vector3.ZERO
	var r0 := 0.3
	var r1 := 0.1
	var cur := 0.0
	var L := 1.0
	var mi := MeshInstance3D.new()
	var bark := Color(0.4, 0.33, 0.26)
	var main: Node3D
	var _solid: Array = []

	func setup(sp: Dictionary, m: Node3D) -> void:
		main = m
		a = sp["a"]
		b = sp["b"]
		r0 = float(sp["r"])
		r1 = r0 * 0.35
		L = a.distance_to(b)
		bark = Color(0.36, 0.3, 0.24) if sp["kind"] != "mosslog" else Color(0.34, 0.33, 0.24)
		add_child(mi)
		_rebuild()

	func _r(t: float) -> float:
		return lerpf(r0, r1, t / maxf(L, 0.01))

	func _rebuild() -> void:
		var bd := TM.B.new(9)
		var ax := (b - a).normalized()
		var pts: Array = []
		var rs: Array = []
		var cs: Array = []
		var n := 8
		for i in n + 1:
			var t := lerpf(cur, L, float(i) / n)
			pts.append(a + ax * t)
			rs.append(_r(t))
			cs.append(bark.darkened(0.08 * sin(t * 3.7)))
		bd.tube(pts, rs, cs, 10, false, 1.5)
		# торец свежего среза — светлое дерево с кольцами
		var c0: Vector3 = pts[0]
		var rr: float = rs[0]
		var ref := Vector3.UP if absf(ax.y) < 0.9 else Vector3.RIGHT
		var u := ax.cross(ref).normalized()
		var v := ax.cross(u).normalized()
		for ring in 3:
			var ra := rr * float(ring) / 3.0
			var rb := rr * float(ring + 1) / 3.0
			var col := (WOOD if cur > 0.0 else bark.darkened(0.2)).darkened(0.06 * ring)
			for j in 10:
				var a0 := TAU * j / 10.0
				var a1 := TAU * (j + 1) / 10.0
				bd.tri(c0 + (u * cos(a0) + v * sin(a0)) * ra, c0 + (u * cos(a1) + v * sin(a1)) * rb, c0 + (u * cos(a0) + v * sin(a0)) * rb, col)
				if ring > 0:
					bd.tri(c0 + (u * cos(a0) + v * sin(a0)) * ra, c0 + (u * cos(a1) + v * sin(a1)) * ra, c0 + (u * cos(a1) + v * sin(a1)) * rb, col)
		mi.mesh = bd.commit(TM.mat())
		if main != null:
			for arr: Array in main.solids.values():
				arr.erase(_solid)
			_solid = []
			if L - cur > 0.6:
				_solid = [1, a + ax * cur, b, _r(cur) * 0.9, 0.0]
				main._add_solid(_solid)

	func hits_per_log() -> int:
		return 2 + int(_r(cur) * 12.0)

	func has_logs() -> bool:
		return L - cur > SEG + 0.4

	func cut_point() -> Vector3:
		return a + (b - a).normalized() * (cur + SEG)

	func cut_log() -> Array:
		if not has_logs():
			return []
		var ax := (b - a).normalized()
		var c := a + ax * (cur + SEG * 0.5)
		var r := _r(cur + SEG * 0.5)
		cur += SEG
		_rebuild()
		return [c, ax, SEG, r, bark]

# ---------- проверка: TOOLS_TEST=папка (или 1) — валка, брёвна, бросок, ремесло; кадры, если папка ----------
var _tt := 0.0
var _tn := 0
var _tdata := {}
func _test(delta: float) -> void:
	_tt += delta
	var dir := OS.get_environment("TOOLS_TEST")
	var hero: Node3D = main.hero
	var T: Node = hero.tools
	var plan := [[3.0, "tree"], [3.3, "chop"], [30.0, "shot_fall"], [33.0, "trunk"], [60.0, "take"], [62.5, "carry"], [64.0, "drop"], [66.0, "split"], [74.0, "spear"], [75.0, "throw"], [78.0, "craft"], [79.0, "report"], [79.5, "quit"]]
	if _tdata.has("an_p"):
		var anx: Node3D = _tdata["an"]
		anx.position = _tdata["an_p"]
		anx.heading = 0.0
		anx.state = "rest"
	if _tn >= plan.size() or _tt < float(plan[_tn][0]):
		if _tdata.has("fall") and dir.length() > 1:
			var f: FellTree = _tdata["fall"]
			if f.phase == "fall" and f.th > 0.5 and not _tdata.has("shot1"):
				_tdata["shot1"] = true
				_shot(dir, "fall_mid")
		return
	var a: String = plan[_tn][1]
	_tn += 1
	match a:
		"tree":
			main.inv["axe"] = 1
			T.take("axe")
			var best: Array = []
			var bd := 1e9
			for k in main.tree_grid:
				for rec: Array in main.tree_grid[k]:
					var o: Vector3 = (rec[2] as Transform3D).origin
					if kind_of(rec) != "birch" or is_young(rec) or o.y < -100:
						continue
					var d := o.distance_to(hero.position)
					if d < bd and main.normal_at(o.x, o.z).y > 0.95:
						bd = d
						best = rec
			var o2: Vector3 = (best[2] as Transform3D).origin
			hero.position = o2 + Vector3(0.95, 0, 0)
			hero.position.y = main.ground_at(hero.position.x, hero.position.z)
			main.rig.position = hero.position
			_tdata["rec"] = best
			print("TT tree at ", o2, " label=", T.use_label(), " held=", hero.held)
		"chop":
			T.use()
			print("TT chop act=", T.act)
		"shot_fall":
			var f2: FellTree = fells.get(int(_tdata["rec"][4]), null)
			print("TT fell phase=", f2.phase if f2 != null else "none", " hits=", f2.hits if f2 != null else 0, " trunks=", trunks.size())
			if dir.length() > 1:
				_shot(dir, "fallen")
		"trunk":
			var tr := find_trunk(hero.position, 6.0)
			print("TT trunk found=", not tr.is_empty())
			if not tr.is_empty():
				var cp := trunk_cut_point(tr)
				hero.position = cp + Vector3(0, 0, 0.9).rotated(Vector3.UP, 0.0)
				hero.position.y = main.ground_at(hero.position.x, hero.position.z)
				print("TT trunk label=", T.use_label())
				T.use()
				_tdata["trunk"] = true
		"take":
			if dir.length() > 1:
				_shot(dir, "trunk_cut")
			print("TT items=", items.size(), " act=", T.act)
			var lg := find_log(hero.position, 6.0)
			if lg != null:
				hero.position = lg.global_position + Vector3(0.9, 0, 0)
				hero.position.y = main.ground_at(hero.position.x, hero.position.z)
				print("TT action=", hero.action_label())
				hero.do_action()
		"carry":
			print("TT held=", hero.held, " speed=", T.speed_factor())
			if dir.length() > 1:
				_shot(dir, "carry")
		"drop":
			hero.do_action()
		"split":
			print("TT after drop held=", hero.held, " items=", items.size())
			T.act = ""
			T.belt.erase("axe")
			T.held = "axe"
			T._refresh()
			print("TT split label=", T.use_label())
			T.use()
		"spear":
			print("TT firewood=", main.inv.get("firewood", 0))
			main.inv["spear"] = 1
			T.act = ""
			T.give_long("spear")
			# зверь перед героем
			var an: Node3D = null
			for x: Node3D in main.animals.list:
				if not x.dead and x.kind in ["roe", "deer", "moose", "boar"] and x.position.y > main.WATER_Y + 0.5:
					an = x
					break
			if an != null:
				hero.position = an.position + Vector3(0, 0, -9.0)
				hero.position.y = main.ground_at(hero.position.x, hero.position.z)
				hero.body.rotation.y = 0.0
				_tdata["an"] = an
				_tdata["an_p"] = an.position
				print("TT target ", an.kind, " hp=", an.hp_left)
			if dir.length() > 1:
				_shot(dir, "spear_carry")
		"throw":
			T.act = ""
			print("TT can_throw=", T.can_throw(), " state=", hero.state, " swim=", hero.swimb)
			T.throw()
		"craft":
			for it: Dictionary in items:
				print("TT item ", it["id"], " at ", it["pos"])
			if _tdata.has("an"):
				print("TT animal at ", (_tdata["an"] as Node3D).position, " aim=", aim_target(hero.position, hero.body.rotation.y), " H=", (_tdata["an"] as Node3D).parts.get("H"))
				var an2: Node3D = _tdata["an"]
				print("TT after throw: dead=", an2.dead, " hp=", an2.hp_left, " flying=", flying.size(), " items=", items.size())
			main.inv.merge({"flint": 2, "twig": 1, "fiber": 3, "pebble": 2})
			print("TT missing axe=", main.inventory.missing("axe"))
			print("TT craft axe=", main.inventory.craft("axe"), " craft flint=", main.inventory.craft("flint"), " inv=", main.inv)
		"report":
			print("TT knife target=", knife_target(hero.position), " belt=", T.belt, " held=", T.held)
		"quit":
			get_tree().quit()

func _shot(dir: String, n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir + "/" + n + ".png")
	print("TT shot ", n)
