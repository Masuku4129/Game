extends Node3D
## Звери и птицы: расселение по биомам, логова, общий тик с уровнями детализации.

const Animal = preload("res://scripts/animal.gd")
const SHOW_R := 75.0
const NEAR_R := 95.0
const MID_R := 25.0   # perf: ближе — каждый кадр (камера видит ~25 м)
const MID_DT := 0.04  # perf: шаг для средних дистанций (25 раз в секунду)

var main: Node3D
var list: Array = []
var birds: Array = []
var groups := {}
var rng := RandomNumberGenerator.new()
var _far_acc := 0.0
var _bird_acc := 0.0
var _far_i := 0
var bird_mesh := {}
# сетка зверей (ячейка GC м), перестраивается раз в 0,5 с: соседей ищем только в ближних ячейках
const GC := 32.0
var grid := {}
var _grid_t := 0.0
# туши: убитые звери, на которых ещё есть мясо
var carcasses: Array = []
var fish: Node3D

func populate() -> void:
	rng.seed = 7741
	var start: Vector3 = main.hero.position
	# заяц: опушки и поляны
	for i in 50:
		_spawn("hare", _spot(func(x, z): return main.forest_density(x, z) < 0.55, start, 25.0), 1.0, -1)
	# белка: у деревьев
	for i in 80:
		var p := _spot(func(x, z): return main.nearest_tree(Vector3(x, 0, z), 6.0) != Vector3.INF, start, 15.0)
		_spawn("squirrel", p, 1.0, -1)
	for i in 12:
		_spawn("fox", _spot(func(x, z): return main.forest_density(x, z) < 0.6, start, 50.0), 1.0, -1)
	# первая встреча: пара косуль на опушке недалеко от старта
	var c0 := _spot(func(x, z): return main.forest_density(x, z) < 0.5 and Vector2(x - start.x, z - start.z).length() < 70.0, start, 35.0)
	for k in 2:
		_spawn("roe", _near(c0, 4.0), rng.randf_range(0.9, 1.05), 99)
	# водопои: звери держатся у реки
	for gi in 4:
		var c := _spot(func(x, z): return main.river_dist(x, z) < 32.0 and main.river_dist(x, z) > 20.0 and main.height(x, z) > main.WATER_Y + 0.4, start, 50.0)
		for k in rng.randi_range(2, 3):
			_spawn("roe", _near(c, 5.0), rng.randf_range(0.9, 1.05), 110 + gi)
	# косули — группы по 2–3, олени — стада 4–5
	for gi in 10:
		var c := _spot(func(x, z): return main.forest_density(x, z) < 0.7, start, 60.0)
		for k in rng.randi_range(2, 3):
			_spawn("roe", _near(c, 6.0), rng.randf_range(0.9, 1.05), 100 + gi)
	for gi in 5:
		var c := _spot(func(x, z): return main.forest_density(x, z) < 0.5 and main.normal_at(x, z).y > 0.9, start, 80.0)
		for k in rng.randi_range(4, 5):
			_spawn("deer", _near(c, 8.0), rng.randf_range(0.85, 1.05), 200 + gi)
	# кабаны с поросятами
	for gi in 7:
		var c := _spot(func(x, z): return main.forest_density(x, z) > 0.4, start, 70.0)
		_spawn("boar", c, 1.0, 300 + gi)
		_spawn("boar", _near(c, 4.0), 0.85, 300 + gi)
		for k in 3:
			_spawn("boar", _near(c, 4.0), 0.4, 300 + gi)
	# волчья стая с логовом вдали от старта
	var den := _spot(func(x, z): return main.forest_density(x, z) > 0.5 and main.normal_at(x, z).y > 0.85, start, 150.0)
	_den(den, 1.6, 0.9)
	for k in 5:
		var w = _spawn("wolf", _near(den, 5.0), rng.randf_range(0.9, 1.05) if k > 0 else 1.1, 400)
		w.home_r = 170.0
	var den2 := _spot(func(x, z): return main.forest_density(x, z) > 0.5 and main.normal_at(x, z).y > 0.85 and den.distance_to(Vector3(x, den.y, z)) > 180.0, start, 150.0)
	_den(den2, 1.6, 0.9)
	for k in 4:
		var w2 = _spawn("wolf", _near(den2, 5.0), rng.randf_range(0.9, 1.05) if k > 0 else 1.1, 401)
		w2.home_r = 170.0
	# медведи: берлоги в каменистой местности
	for bi in 3:
		var bden := _spot(func(x, z): return main.biome(x, z) > 0.2 and main.normal_at(x, z).y > 0.8, start, 100.0)
		_den(bden, 2.2, 1.3)
		_spawn("bear", _near(bden, 3.0), 1.0 if bi == 0 else 0.9, -1)
	# тигры: юго-восток
	for ti in 2:
		var tp := _spot(func(x, z): return x > 60.0 and z > 60.0, start, 120.0)
		_spawn("tiger", tp, 1.0, -1)
	# бобры: по 3 у каждой хатки (колонии — в beavers.gd)
	for ci in main.beavers.colonies.size():
		var col: Dictionary = main.beavers.colonies[ci]
		var lp: Vector3 = col["lodge"]
		for k in 3:
			var bv: Node3D = _spawn("beaver", _near(lp, 3.5), rng.randf_range(0.9, 1.05), 500 + ci)
			bv.home = lp
			bv.door = col.get("door", Vector3.INF)
			col["beavers"].append(bv)
	# птицы: стайки
	_make_bird_mesh()
	for gi in 28:
		var c := _spot(func(x, z): return true, start, 10.0)
		for k in rng.randi_range(4, 9):
			var b := Bird.new()
			b.setup(self, _near(c, 3.0), rng.randi())
			add_child(b)
			birds.append(b)

	_populate_taiga(start)
	_rebuild_grid()
	# рыба в реке
	fish = preload("res://scripts/fish.gd").new()
	fish.main = main
	add_child(fish)
	fish.setup()

func _spot(cond: Callable, start: Vector3, min_d: float) -> Vector3:
	var half: float = main.SIZE * 0.5 - 20.0
	for t in 400:
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		if Vector2(x - start.x, z - start.z).length() < min_d:
			continue
		var y: float = main.height(x, z)
		if y < main.WATER_Y + 0.2 and not cond.call(x, z):
			continue
		if main.normal_at(x, z).y < 0.75 or main.blocked(x, z, 0.8):
			continue
		if cond.call(x, z):
			return Vector3(x, y, z)
	return Vector3(rng.randf_range(-half, half), 0, rng.randf_range(-half, half))

func _near(c: Vector3, r: float) -> Vector3:
	for t in 20:
		var a := rng.randf() * TAU
		var p := c + Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.5, r)
		if not main.blocked(p.x, p.z, 0.5):
			return p
	return c

func _spawn(k: String, p: Vector3, sc: float, grp: int) -> Node3D:
	var a := Animal.new()
	add_child(a)
	a.setup(k, main, self, Vector3(p.x, main.ground_at(p.x, p.z), p.z), rng.randi(), sc)
	a.group = grp
	list.append(a)
	if grp >= 0:
		if not groups.has(grp):
			groups[grp] = []
		groups[grp].append(a)
	return a

## Логово: холм из земли и камня с тёмным лазом.
func _den(p: Vector3, r: float, h: float) -> void:
	var y: float = main.ground_at(p.x, p.z)
	var mound := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = h * 2.0
	sm.radial_segments = 14
	sm.rings = 7
	mound.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.26, 0.2)
	m.albedo_texture = preload("res://scripts/animal_model.gd").fur_tex(false)
	m.uv1_scale = Vector3(4, 4, 4)
	m.roughness = 1.0
	mound.material_override = m
	mound.position = Vector3(p.x, y - h * 0.25, p.z)
	mound.visibility_range_end = 90.0
	add_child(mound)
	var hole := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = r * 0.32
	hm.height = r * 0.5
	hole.mesh = hm
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.03, 0.025, 0.02)
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hole.material_override = dm
	hole.position = Vector3(p.x + r * 0.82, y + h * 0.2, p.z)
	hole.scale = Vector3(0.35, 1.0, 1.0)
	hole.visibility_range_end = 60.0
	add_child(hole)
	main._add_solid([0, Vector3(p.x, y - h * 0.25, p.z), Vector3.ZERO, r * 0.95, h * 0.75])

## Ближний хищник, опасный для зверя a.
func nearest_predator(a: Node3D, r: float) -> Node3D:
	var preds: Array = {"hare": ["fox", "wolf", "tiger"], "squirrel": ["fox"], "roe": ["wolf", "tiger", "bear"], "deer": ["wolf", "tiger", "bear"], "beaver": ["wolf", "fox"], "fox": ["wolf", "tiger"], "boar": ["tiger"]}.get(a.kind, []) + TAIGA_PREDS.get(a.kind, [])
	if preds.is_empty():
		return null
	var best: Node3D = null
	var bd := r
	for o in near(a.position, r):
		if o.dead or not (o.kind in preds) or o.state == "sleep" or o.state == "inlodge":
			continue
		# в погоне хищник заметен издалека, подкрадывающийся — вполовину, в засаде — почти нет
		var k := 0.4
		match o.state:
			"chase":
				k = 1.0
			"stalk":
				k = 0.55
			"ambush":
				k = 0.15
		var d: float = a.position.distance_to(o.position)
		if d < bd * k:
			bd = d / k
			best = o
	return best

func nearest_of(a: Node3D, kinds: Array, r: float) -> Node3D:
	var best: Node3D = null
	var bd := r
	for o in near(a.position, r):
		if o == a or o.dead or not (o.kind in kinds) or o.scale_k < 0.5 and a.kind == "fox":
			continue
		if o.state == "inlodge" or o.climb_h > 1.0:
			continue
		var d: float = a.position.distance_to(o.position)
		if d < bd:
			bd = d
			best = o
	return best

func pack_hunt(a: Node3D, prey: Node3D) -> void:
	if a.group < 0 or not groups.has(a.group):
		return
	var g: Array = groups[a.group]
	for i in g.size():
		var w = g[i]
		if w.dead or w == a:
			continue
		w.prey = prey
		w.state = "stalk"
		w.state_t = 25.0
		w.pack_slot = TAU * float(i) / float(g.size())

## Стая перешла на бег: все, кто подкрадывался к той же добыче, — в погоню.
func pack_chase(a: Node3D, prey: Node3D) -> void:
	if a.group < 0 or not groups.has(a.group):
		return
	for w in groups[a.group]:
		if w != a and not w.dead and w.state == "stalk" and w.prey == prey:
			w.state = "chase"
			w.state_t = 25.0

## Вожак группы: первый живой.
func group_leader(g: int) -> Node3D:
	if not groups.has(g):
		return null
	for o in groups[g]:
		if not o.dead:
			return o
	return null

func group_has(g: int, st: String) -> bool:
	if not groups.has(g):
		return false
	for o in groups[g]:
		if not o.dead and o.state == st:
			return true
	return false

## Стадо идёт на водопой за вожаком: каждый — к своему месту у воды рядом.
func group_drink(a: Node3D, spot: Vector3, slot: int) -> void:
	var i := 0
	for o in groups[a.group]:
		if o == a or o.dead or not (o.state in ["wander", "graze", "rest", "watch"]):
			continue
		i += 1
		var x: float = spot.x + (float(i) * 1.6 + 0.8) * (1.0 if i % 2 == 0 else -1.0)
		var p: Vector3 = o._bank_spot(x, o._bank_side(spot))
		if p != Vector3.INF:
			o._go_drink(p, slot)

# --- hunt: запах крови (hunt.gd добавляет: кровь героя, разделка, мясо в коробе) ---
# [позиция, сила 0..2, до (с)]; хищник, учуяв, идёт проверить (animal.gd, состояние investigate)
var scents: Array = []

func add_scent(p: Vector3, strength: float, ttl: float) -> void:
	var now := Time.get_ticks_msec() * 0.001
	for s: Array in scents:
		if (s[0] as Vector3).distance_to(p) < 6.0:
			s[0] = p
			s[1] = maxf(float(s[1]), strength)
			s[2] = maxf(float(s[2]), now + ttl)
			return
	if scents.size() >= 48:
		scents.pop_front()
	scents.append([p, strength, now + ttl])

## Кровь, которую зверь в точке p учуял (r — чутьё при силе 1), или INF. Чем слабее и дальше — тем реже.
func scent_near(p: Vector3, r: float) -> Vector3:
	var now := Time.get_ticks_msec() * 0.001
	var best := Vector3.INF
	var bk := 0.0
	for i in range(scents.size() - 1, -1, -1):
		var s: Array = scents[i]
		if float(s[2]) < now:
			scents.remove_at(i)
			continue
		var d := (s[0] as Vector3).distance_to(p)
		var R := r * float(s[1])
		if d < R:
			var k := float(s[1]) * (1.0 - d / R)
			if k > bk:
				bk = k
				best = s[0]
	if best != Vector3.INF and rng.randf() > 0.3 * bk:
		return Vector3.INF
	return best
# --- /hunt ---

## Туши.
func add_carcass(a: Node3D) -> void:
	if not carcasses.has(a):
		carcasses.append(a)

func carcass_near(p: Vector3, r: float) -> Node3D:
	var best: Node3D = null
	var bd := r
	for c in carcasses:
		if c.meat <= 0.0:
			continue
		var d: float = p.distance_to(c.position)
		if d < bd:
			bd = d
			best = c
	return best

## Кто сильнее у этой туши (ест в 7 м от неё): медведь отгоняет волков, волки — лису и росомаху.
func rival_at(food: Node3D, me: Node3D) -> Node3D:
	var my: float = Animal.RANK.get(me.kind, 1.0)
	for o in near(food.position, 8.0):
		if o == me or o.dead or o.food != food or o.state != "feed":
			continue
		if float(Animal.RANK.get(o.kind, 1.0)) > my and o.position.distance_to(food.position) < 7.0:
			return o
	return null

## Хищник на ходу рядом с точкой (птицы взлетают).
func moving_predator_near(p: Vector3, r: float) -> Node3D:
	for o in near(p, r):
		if not o.dead and o.speed > 1.2 and Animal.RANK.has(o.kind) and Vector2(o.position.x - p.x, o.position.z - p.z).length() < r:
			return o
	return null

func _rebuild_grid() -> void:
	grid.clear()
	for a in list:
		if a.dead or a.state == "inlodge":
			continue
		var k := Vector2i(floori(a.position.x / GC), floori(a.position.z / GC))
		if not grid.has(k):
			grid[k] = []
		grid[k].append(a)

## Звери в ячейках, перекрывающих круг радиуса r (без точной проверки расстояния).
func near(p: Vector3, r: float) -> Array:
	var out: Array = []
	for gz in range(floori((p.z - r) / GC), floori((p.z + r) / GC) + 1):
		for gx in range(floori((p.x - r) / GC), floori((p.x + r) / GC) + 1):
			var k := Vector2i(gx, gz)
			if grid.has(k):
				out.append_array(grid[k])
	return out

## Тревога в стаде: все бегут вместе.
func alarm(a: Node3D, threat: Node3D) -> void:
	if a.group < 0 or not groups.has(a.group):
		return
	for o in groups[a.group]:
		if o != a and not o.dead and o.state != "flee" and o.state != "inlodge" and not (o.kind in ["wolf", "boar"] and o.scale_k > 0.6):
			o._flee_from(threat, 5.0)

func _process(delta: float) -> void:
	if main == null or main.hero == null:
		return
	var hp: Vector3 = main.rig.position
	_grid_t -= delta
	if _grid_t <= 0.0:
		_grid_t = 0.5
		_rebuild_grid()
		for c in carcasses.duplicate():
			if c.meat <= 0.0:
				carcasses.erase(c)
	# ближние — каждый кадр, дальние — по кругу, несколько за кадр
	_far_acc += delta
	var n := list.size()
	for a in list:
		var d := Vector2(a.position.x - hp.x, a.position.z - hp.z).length()
		var was_far: bool = a.far
		a.far = d > NEAR_R
		# perf: вблизи (до MID_R) — каждый кадр; дальше в пределах NEAR_R — ~20 раз в секунду
		# со сдвигом по зверям (накопленным шагом), чтобы не грелся телефон
		if not a.far:
			a._acc += delta
			if d < MID_R or a._acc >= MID_DT:
				a.tick(a._acc)
				a._acc = 0.0
		else:
			a._acc += delta
		if was_far and not a.far:
			a._acc = 0.0
		a.visible = d < (40.0 if a.kind in ["hare", "squirrel", "beaver"] else SHOW_R) and (not a.dead or a.meat > 0.0) and a.state != "sleep" and a.state != "inlodge"
		if a.parts.has("ap"):
			a.parts["ap"].active = a.visible and not a.dead
	# perf: дальние (за NEAR_R) — по кругу, каждый примерно раз в секунду
	var per := maxi(1, n / 60)
	for k in per:
		if n == 0:
			break
		_far_i = (_far_i + 1) % n
		var a = list[_far_i]
		if a.far and a._acc > 0.0:
			a.tick(minf(a._acc, 2.0))
			a._acc = 0.0
	# perf: птицы вблизи — каждый кадр, дальше 50 м — раз в 0,2 с (накопленным шагом)
	_bird_acc += delta
	var bird_slow := _bird_acc >= 0.2
	if bird_slow:
		_bird_acc = 0.0
	for b in birds:
		var d := Vector2(b.position.x - hp.x, b.position.z - hp.z).length()
		b.visible = d < 45.0
		if d < 50.0:
			b.tick(delta)
		elif d < 90.0 and bird_slow:
			b.tick(0.2)

func _make_bird_mesh() -> void:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	var body := SphereMesh.new()
	body.radius = 0.06
	body.height = 0.11
	body.radial_segments = 8
	body.rings = 4
	var head := SphereMesh.new()
	head.radius = 0.035
	head.height = 0.07
	head.radial_segments = 6
	head.rings = 3
	var wing := BoxMesh.new()
	wing.size = Vector3(0.16, 0.008, 0.08)
	var tail := BoxMesh.new()
	tail.size = Vector3(0.05, 0.006, 0.09)
	bird_mesh = {"body": body, "head": head, "wing": wing, "tail": tail}
	var cols := [Color(0.25, 0.22, 0.2), Color(0.42, 0.33, 0.24), Color(0.55, 0.5, 0.42), Color(0.15, 0.15, 0.17)]
	bird_mesh["mats"] = []
	for c in cols:
		var mm := m.duplicate()
		mm.vertex_color_use_as_albedo = false
		mm.albedo_color = c
		bird_mesh["mats"].append(mm)

## Птица: клюёт на земле или сидит на ветке, вспархивает от человека, летит дугой, садится.
class Bird extends Node3D:
	var mgr: Node3D
	var main: Node3D
	var state := "perch"
	var t := 0.0
	var a := Vector3.ZERO
	var b := Vector3.ZERO
	var fly_t := 0.0
	var fly_d := 1.0
	var wl := Node3D.new()
	var wr := Node3D.new()
	var body := Node3D.new()
	var rng := RandomNumberGenerator.new()
	var on_tree := false
	var scan_t := 0.0
	var from := Vector3.ZERO

	func setup(m: Node3D, p: Vector3, s: int) -> void:
		mgr = m
		main = m.main
		rng.seed = s
		var bm: Dictionary = m.bird_mesh
		var mat: Material = bm["mats"][rng.randi() % bm["mats"].size()]
		add_child(body)
		var bi := MeshInstance3D.new()
		bi.mesh = bm["body"]
		bi.material_override = mat
		bi.scale = Vector3(0.9, 0.85, 1.5)
		bi.position.y = 0.07
		bi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(bi)
		var hi := MeshInstance3D.new()
		hi.mesh = bm["head"]
		hi.material_override = mat
		hi.position = Vector3(0, 0.12, 0.075)
		hi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(hi)
		var ti := MeshInstance3D.new()
		ti.mesh = bm["tail"]
		ti.material_override = mat
		ti.position = Vector3(0, 0.08, -0.12)
		ti.rotation.x = -0.3
		ti.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(ti)
		for sd in [-1.0, 1.0]:
			var w: Node3D = wl if sd < 0 else wr
			w.position = Vector3(sd * 0.04, 0.1, 0)
			body.add_child(w)
			var wi := MeshInstance3D.new()
			wi.mesh = bm["wing"]
			wi.material_override = mat
			wi.position = Vector3(sd * 0.08, 0, 0)
			wi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			w.add_child(wi)
		for gi: GeometryInstance3D in find_children("*", "GeometryInstance3D", true, false):
			gi.visibility_range_end = 70.0
		position = Vector3(p.x, main.ground_at(p.x, p.z), p.z)
		rotation.y = rng.randf() * TAU
		t = rng.randf_range(3.0, 12.0)

	func tick(delta: float) -> void:
		t -= delta
		var hero: Node3D = main.hero
		var dh := Vector2(position.x - hero.position.x, position.z - hero.position.z).length()
		if state == "perch":
			wl.rotation.z = -1.3
			wr.rotation.z = 1.3
			if not on_tree:
				# клюёт и подпрыгивает
				var pk := maxf(0.0, sin(Time.get_ticks_msec() * 0.006 + rng.seed % 10))
				body.rotation.x = pk * 0.6
				if rng.randf() < delta * 0.5:
					rotation.y += rng.randf_range(-1.2, 1.2)
					var f := Vector3(sin(rotation.y), 0, cos(rotation.y)) * 0.12
					position += f
					position.y = main.ground_at(position.x, position.z)
			else:
				body.rotation.x = 0.0
			var scare := 9.0 * (1.0 + float(hero.run_mag))
			from = hero.position
			var scared := dh < scare
			# хищник на ходу рядом — стайка срывается
			scan_t -= delta
			if not scared and scan_t <= 0.0:
				scan_t = 0.4 + rng.randf() * 0.3
				var pr: Node3D = mgr.moving_predator_near(position, 10.0)
				if pr != null:
					scared = true
					from = pr.position
			if scared or t <= 0.0:
				_take_off(scared)
		else:
			fly_t += delta
			var k := clampf(fly_t / fly_d, 0.0, 1.0)
			var p := a.lerp(b, k)
			p.y += sin(k * PI) * (3.0 + fly_d * 1.5)
			var dir := b - a
			rotation.y = atan2(dir.x, dir.z)
			position = p
			var flap := sin(fly_t * 38.0)
			var glide := 1.0 if k < 0.85 else 0.4
			wl.rotation.z = flap * 1.1 * glide
			wr.rotation.z = -flap * 1.1 * glide
			body.rotation.x = -0.15
			if k >= 1.0:
				state = "perch"
				t = rng.randf_range(6.0, 25.0)

	func _take_off(scared: bool) -> void:
		var away := (position - from)
		away.y = 0
		var ang := atan2(away.x, away.z) if scared else rng.randf() * TAU
		ang += rng.randf_range(-0.6, 0.6)
		var dist := rng.randf_range(18.0, 40.0)
		var tp := position + Vector3(sin(ang), 0, cos(ang)) * dist
		var half: float = main.SIZE * 0.5 - 15.0
		tp.x = clampf(tp.x, -half, half)
		tp.z = clampf(tp.z, -half, half)
		on_tree = false
		var tr: Vector3 = main.nearest_tree(tp, 8.0)
		# вороньё слетается к туше
		var cc: Node3D = mgr.carcass_near(position, 60.0) if not scared and rng.randf() < 0.5 else null
		if cc != null:
			var ca := rng.randf() * TAU
			tp = cc.position + Vector3(cos(ca), 0, sin(ca)) * rng.randf_range(0.8, 2.0)
			tp.y = main.ground_at(tp.x, tp.z)
		elif tr != Vector3.INF and rng.randf() < 0.55:
			tp = Vector3(tr.x + 0.4, main.ground_at(tr.x, tr.z) + rng.randf_range(4.0, 7.0), tr.z)
			on_tree = true
		else:
			tp.y = maxf(main.ground_at(tp.x, tp.z), main.WATER_Y + 0.05)
		a = position
		b = tp
		fly_t = 0.0
		fly_d = a.distance_to(b) / 7.0
		state = "fly"

# ---------- Новые звери тайги: лось, рысь, росомаха, кабарга, глухарь ----------
# Каждого вида — несколько групп по всей карте и хотя бы одна группа в 60–120 м от старта,
# чтобы их можно было найти. Места — по образу жизни вида.

const TAIGA_PREDS := {"hare": ["lynx", "wolverine"], "roe": ["lynx"], "beaver": ["wolverine"], "moose": ["wolf", "tiger", "bear"],
	"muskdeer": ["wolf", "lynx", "wolverine", "tiger"], "capercaillie": ["fox", "lynx", "wolverine"],
	"lynx": ["wolf", "tiger"], "wolverine": ["wolf", "tiger", "bear"]}

func _populate_taiga(start: Vector3) -> void:
	# лоси: поймы, болотистые берега и редколесье; быки поодиночке, лосихи с лосятами
	var mc := _spot_ring(func(x, z): return main.forest_density(x, z) < 0.65, start, 60.0, 110.0)
	_taiga_moose(mc, 700)
	for gi in 9:
		var c := _spot(func(x, z): return main.river_dist(x, z) < 35.0 or main.forest_density(x, z) < 0.4, start, 80.0)
		_taiga_moose(c, 701 + gi)
	# рыси: густой лес, поодиночке
	_spawn("lynx", _spot_ring(func(x, z): return main.forest_density(x, z) > 0.45, start, 70.0, 120.0), 1.0, -1)
	for i in 5:
		_spawn("lynx", _spot(func(x, z): return main.forest_density(x, z) > 0.55, start, 100.0), rng.randf_range(0.9, 1.05), -1)
	# росомахи: каменистые гривы и глухая тайга, поодиночке, ходят далеко
	_spawn("wolverine", _spot_ring(func(x, z): return main.biome(x, z) > 0.0 or main.forest_density(x, z) > 0.55, start, 80.0, 120.0), 1.0, -1)
	for i in 4:
		_spawn("wolverine", _spot(func(x, z): return main.biome(x, z) > 0.15, start, 120.0), rng.randf_range(0.9, 1.05), -1)
	# кабарга: крутые каменистые склоны и скалы, по одной-две
	var kc := _spot_ring(func(x, z): return main.biome(x, z) > 0.1 or main.normal_at(x, z).y < 0.93, start, 60.0, 120.0)
	_spawn_sex("muskdeer", kc, 1.0, 900, true)
	_spawn_sex("muskdeer", _near(kc, 5.0), 0.95, 900, false)
	for gi in 6:
		var c := _spot(func(x, z): return main.biome(x, z) > 0.2 and main.normal_at(x, z).y < 0.96, start, 60.0)
		for k in rng.randi_range(1, 2):
			_spawn_sex("muskdeer", _near(c, 5.0), rng.randf_range(0.92, 1.05), 901 + gi, k == 0)
	# глухари: токовища в хвойном лесу — петух и 2–3 глухарки
	for gi in 9:
		var c := _spot_ring(func(x, z): return main.forest_density(x, z) > 0.45, start, 60.0, 110.0) if gi < 2 else _spot(func(x, z): return main.forest_density(x, z) > 0.5, start, 50.0)
		_spawn_sex("capercaillie", c, rng.randf_range(0.95, 1.05), 800 + gi, true)
		for k in rng.randi_range(2, 3):
			_spawn_sex("capercaillie", _near(c, 6.0), rng.randf_range(0.68, 0.76), 800 + gi, false)

## Лосиная группа: бык-одиночка, лосиха с лосёнком или все трое.
func _taiga_moose(c: Vector3, grp: int) -> void:
	var t := rng.randi() % 3
	if t != 1:
		_spawn_sex("moose", c, rng.randf_range(0.95, 1.05), grp, true)
	if t != 0:
		_spawn_sex("moose", _near(c, 6.0), rng.randf_range(0.85, 0.92), grp, false)
		_spawn_sex("moose", _near(c, 4.0), rng.randf_range(0.5, 0.6), grp, false)

func _spawn_sex(k: String, p: Vector3, sc: float, grp: int, is_male: bool) -> Node3D:
	var a = _spawn(k, p, sc, grp)
	if a.male != is_male:
		a.male = is_male
		a._build(false)
	return a

## Место в кольце r0..r1 от старта (для встреч недалеко от начала игры).
func _spot_ring(cond: Callable, start: Vector3, r0: float, r1: float) -> Vector3:
	for t in 400:
		var ang := rng.randf() * TAU
		var r := rng.randf_range(r0, r1)
		var x := start.x + cos(ang) * r
		var z := start.z + sin(ang) * r
		var half: float = main.SIZE * 0.5 - 20.0
		if absf(x) > half or absf(z) > half:
			continue
		if main.height(x, z) < main.WATER_Y + 0.2 or main.normal_at(x, z).y < 0.75 or main.blocked(x, z, 0.8):
			continue
		if cond.call(x, z):
			return Vector3(x, main.height(x, z), z)
	return _spot(cond, start, r0)

# --- core: сохранение (save.gd, раздел «animals»): где звери, кто убит, сколько мяса осталось.
# Порядок зверей в list задаётся генерацией (одинаков при каждом запуске). ---
func to_save() -> Dictionary:
	var SV = preload("res://scripts/save.gd")
	var out: Array = []
	for a in list:
		var e := {"p": SV.enc(a.position), "h": float(a.heading)}
		if a.dead:
			e["dead"] = true
			e["meat"] = float(a.meat)
			e["resp"] = float(a.respawn_at)
		out.append(e)
	return {"n": list.size(), "list": out}

func from_save(d: Dictionary) -> void:
	var SV = preload("res://scripts/save.gd")
	var arr: Array = d.get("list", [])
	if int(d.get("n", -1)) != list.size():
		return
	for i in arr.size():
		var a = list[i]
		var e: Dictionary = arr[i]
		a.position = SV.dec(e["p"])
		a.heading = float(e.get("h", 0.0))
		a.rotation.y = a.heading
		if bool(e.get("dead", false)):
			if not a.dead:
				a.kill()
			a.meat = float(e.get("meat", a.meat))
			a.respawn_at = float(e.get("resp", a.respawn_at))
# --- /core ---
