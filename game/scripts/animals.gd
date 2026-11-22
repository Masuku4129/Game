extends Node3D
## Звери и птицы: расселение по биомам, логова, общий тик с уровнями детализации.

const Animal = preload("res://scripts/animal.gd")
const SHOW_R := 75.0
const NEAR_R := 95.0

var main: Node3D
var list: Array = []
var birds: Array = []
var groups := {}
var rng := RandomNumberGenerator.new()
var _far_acc := 0.0
var _far_i := 0
var bird_mesh := {}

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
		var c := _spot(func(x, z): return main.river_dist(x, z) < 14.0 and main.river_dist(x, z) > 4.0, start, 50.0)
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
	# бобры: хатка на реке
	for gi in 4:
		var bp := _spot(func(x, z): return main.river_dist(x, z) < 9.0 and main.height(x, z) < main.WATER_Y + 0.6 and main.height(x, z) > main.WATER_Y - 1.2, start, 40.0)
		_lodge(bp)
		for k in 2:
			_spawn("beaver", _near(bp, 3.0), 1.0, 500 + gi)
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

## Бобровая хатка: конус из веток у воды.
func _lodge(p: Vector3) -> void:
	var y: float = maxf(main.ground_at(p.x, p.z), main.WATER_Y - 0.4)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.25
	cm.bottom_radius = 1.6
	cm.height = 1.4
	cm.radial_segments = 10
	mi.mesh = cm
	mi.material_override = main.veg.mats["bark_dead"]
	mi.position = Vector3(p.x, y + 0.5, p.z)
	mi.visibility_range_end = 80.0
	add_child(mi)
	for i in 9:
		var st := MeshInstance3D.new()
		var sc := CylinderMesh.new()
		sc.top_radius = 0.03
		sc.bottom_radius = 0.04
		sc.height = 1.6
		sc.radial_segments = 4
		st.mesh = sc
		st.material_override = main.veg.mats["bark_dead"]
		var a := TAU * i / 9.0
		st.position = Vector3(p.x + cos(a) * 0.9, y + 0.55, p.z + sin(a) * 0.9)
		st.rotation = Vector3(0, -a, 0.9)
		st.visibility_range_end = 50.0
		add_child(st)
	main._add_solid([0, Vector3(p.x, y, p.z), Vector3.ZERO, 1.5, 1.2])

## Ближний хищник, опасный для зверя a.
func nearest_predator(a: Node3D, r: float) -> Node3D:
	var preds: Array = {"hare": ["fox", "wolf", "tiger"], "squirrel": ["fox"], "roe": ["wolf", "tiger", "bear"], "deer": ["wolf", "tiger", "bear"], "beaver": ["wolf", "fox"], "fox": ["wolf", "tiger"], "boar": ["tiger"]}.get(a.kind, []) + TAIGA_PREDS.get(a.kind, [])
	if preds.is_empty():
		return null
	var best: Node3D = null
	var bd := r
	for o in list:
		if o.dead or not (o.kind in preds) or o.state == "sleep":
			continue
		var hunting: bool = o.state in ["stalk", "chase"]
		var d: float = a.position.distance_to(o.position)
		if d < (bd if hunting else bd * 0.4):
			bd = d
			best = o
	return best

func nearest_of(a: Node3D, kinds: Array, r: float) -> Node3D:
	var best: Node3D = null
	var bd := r
	for o in list:
		if o == a or o.dead or not (o.kind in kinds) or o.scale_k < 0.5 and a.kind == "fox":
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

## Тревога в стаде: все бегут вместе.
func alarm(a: Node3D, threat: Node3D) -> void:
	if a.group < 0 or not groups.has(a.group):
		return
	for o in groups[a.group]:
		if o != a and not o.dead and o.state != "flee" and not (o.kind in ["wolf", "boar"] and o.scale_k > 0.6):
			o.threat = threat
			o.state = "flee"
			o.state_t = 5.0

func _process(delta: float) -> void:
	if main == null or main.hero == null:
		return
	var hp: Vector3 = main.rig.position
	# ближние — каждый кадр, дальние — по кругу, несколько за кадр
	_far_acc += delta
	var n := list.size()
	for a in list:
		var d := Vector2(a.position.x - hp.x, a.position.z - hp.z).length()
		var was_far: bool = a.far
		a.far = d > NEAR_R
		if not a.far:
			a.tick(delta)
			a._acc = 0.0
		else:
			a._acc += delta
		if was_far and not a.far:
			a._acc = 0.0
		a.visible = d < SHOW_R and not a.dead and a.state != "sleep"
		if a.parts.has("ap"):
			a.parts["ap"].active = a.visible
	var per := maxi(1, n / 20)
	for k in per:
		if n == 0:
			break
		_far_i = (_far_i + 1) % n
		var a = list[_far_i]
		if a.far and a._acc > 0.0:
			a.tick(minf(a._acc, 2.0))
			a._acc = 0.0
	for b in birds:
		var d := Vector2(b.position.x - hp.x, b.position.z - hp.z).length()
		b.visible = d < 60.0
		if d < 90.0:
			b.tick(delta)

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
			if dh < scare or t <= 0.0:
				_take_off(dh < scare)
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
		var hero: Node3D = main.hero
		var away := (position - hero.position)
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
		if tr != Vector3.INF and rng.randf() < 0.55:
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
