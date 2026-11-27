extends Node3D
## Режим стройки: призрак выбранной постройки перед героем. Палец, коснувшийся призрака
## (или тап по земле), двигает его; кнопки ⟲ ⟳ поворачивают; зелёный — можно ставить,
## красный — мешают деревья, камни, валежник, другие постройки, вода, крутизна или даль (больше 30 м от героя). Лагеря нет — строить можно везде.
## У шалаша у дерева призрак сам прилипает к ближайшему стволу.

const GEO = preload("res://scripts/build_geo.gd")

var camp
var main: Node3D
var active := false
var kind := ""
var ghost: Node3D
var gpos := Vector3.ZERO
var gyaw := 0.0
var valid := false
var reason := ""
var _drag_id := -1
var _press_pos := Vector2.ZERO
var _press_t := 0
var _ok_mat := StandardMaterial3D.new()
var _bad_mat := StandardMaterial3D.new()
var _tree_r := 0.3
var _check_t := 0.0

func _ready() -> void:
	for m: StandardMaterial3D in [_ok_mat, _bad_mat]:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.no_depth_test = false
	_ok_mat.albedo_color = Color(0.45, 0.95, 0.45, 0.42)
	_bad_mat.albedo_color = Color(1.0, 0.3, 0.25, 0.45)

func start() -> void:
	active = true

func stop() -> void:
	active = false
	select("")

## Выбрать, что строить ("" — снять выбор).
func select(k: String) -> void:
	if ghost != null:
		ghost.queue_free()
		ghost = null
	kind = k
	if k == "":
		return
	var g = camp.geo
	match k:
		"campfire":
			ghost = g.campfire()
		"leanto":
			ghost = g.lean_to()
		"tree_shelter":
			ghost = g.tree_shelter()
		"snow_shelter":
			ghost = g.snow_shelter()
		"cache":
			ghost = g.cache()
		"chop_block":
			ghost = g.chop_block()
		"cabin":
			ghost = g.cabin(GEO.NC, 1.0, [])
	GEO.ghostify(ghost, _ok_mat)
	add_child(ghost)
	var hero: Node3D = main.hero
	var fwd := Vector3(sin(hero.body.rotation.y), 0, cos(hero.body.rotation.y))
	var d := 5.5 if k == "cabin" else 3.0
	gpos = hero.position + fwd * d
	gyaw = atan2(fwd.x, fwd.z) + PI
	_move(gpos)

func rotate_by(a: float) -> void:
	gyaw += a
	_move(gpos)

func _move(p: Vector3) -> void:
	gpos = p
	if kind == "tree_shelter":
		_snap_tree()
	gpos.y = _ground(gpos)
	if ghost != null:
		ghost.position = gpos
		ghost.rotation.y = gyaw
	_check()

## Высота установки: у избы — верх земли под углами (сруб на камнях), иначе середина.
func _ground(p: Vector3) -> float:
	var hs: Array = []
	for c: Vector3 in camp.world_circles(kind, Vector3(p.x, 0, p.z), gyaw):
		hs.append(main.height(c.x, c.y))
	if hs.is_empty():
		return main.height(p.x, p.z)
	if kind == "cabin":
		return hs.max() - 0.1
	var sum := 0.0
	for h: float in hs:
		sum += h
	return minf(sum / hs.size(), main.height(p.x, p.z))

## Прилипнуть к ближайшему стволу (в 4 м): шалаш уходит от ствола в сторону пальца.
func _snap_tree() -> void:
	var best := Vector3.INF
	var bd := 4.0
	var c := Vector2i(floori(gpos.x / 16.0), floori(gpos.z / 16.0))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for rec: Array in main.tree_grid.get(Vector2i(c.x + dx, c.y + dz), []):
				var t: Transform3D = rec[2]
				var s := t.basis.x.length()
				if s < 0.6:
					continue
				var d := Vector2(t.origin.x - gpos.x, t.origin.z - gpos.z).length()
				if d < bd:
					bd = d
					best = t.origin
					_tree_r = 0.3 * s
	if best != Vector3.INF:
		var away := Vector2(gpos.x - best.x, gpos.z - best.z)
		if away.length() > 0.3:
			gyaw = atan2(away.x, away.y)
		gpos = Vector3(best.x, gpos.y, best.z)
		set_meta("tree", true)
	else:
		set_meta("tree", false)

func _check() -> void:
	var r := _validate()
	valid = r[0]
	reason = r[1]
	if ghost != null:
		GEO.ghostify(ghost, _ok_mat if valid else _bad_mat)

func _validate() -> Array:
	if kind == "":
		return [false, ""]
	# лагеря нет: ставить можно где угодно, но не дальше 30 м от героя
	if Vector2(gpos.x - main.hero.position.x, gpos.z - main.hero.position.z).length() > 30.0:
		return [false, "Слишком далеко"]
	var d: Dictionary = camp.DEFS[kind]
	if kind != "cabin" and not camp.can_pay(d["cost"]):
		return [false, "Не хватает припасов"]
	if kind == "tree_shelter" and not bool(get_meta("tree", false)):
		return [false, "Нужно дерево рядом"]
	if kind == "snow_shelter":
		if not camp.has_shovel():
			return [false, "Нужна лопата"]
		if main.feet == null or main.feet.snow_depth(gpos.x, gpos.z) < 0.25:
			return [false, "Мало снега — нужен сугроб"]
	var circles: Array = camp.world_circles(kind, gpos, gyaw)
	var hmin := 1e9
	var hmax := -1e9
	for c: Vector3 in circles:
		for k in 5:
			var a := TAU * k / 5.0
			var px: float = c.x + cos(a) * c.z * (0.0 if k == 0 else 0.8)
			var pz: float = c.y + sin(a) * c.z * (0.0 if k == 0 else 0.8)
			var h: float = main.height(px, pz)
			hmin = minf(hmin, h)
			hmax = maxf(hmax, h)
			if h < main.water_level(px, pz) + 0.25:
				return [false, "Вода"]
		var rr: float = c.z * 0.85
		if kind == "tree_shelter" and Vector2(c.x - gpos.x, c.y - gpos.z).length() < _tree_r + c.z + 0.1:
			continue
		if main.blocked(c.x, c.y, rr):
			return [false, "Мешает дерево или камень"]
		if main.solid_top(c.x, c.y) > main.height(c.x, c.y) + 0.12:
			return [false, "Мешает камень или валежина"]
		if not main._occ_free(c.x, c.y, rr):
			return [false, "Место занято"]
		if camp.overlaps(c.x, c.y, c.z):
			return [false, "Мешает другая постройка"]
	var lim := 0.9 if kind == "cabin" else 0.6
	if hmax - hmin > lim:
		return [false, "Слишком круто"]
	return [true, ""]

## Поставить (если можно). Возвращает true при успехе.
func confirm() -> bool:
	_check()
	if not valid:
		main._say(reason)
		return false
	var d: Dictionary = camp.DEFS[kind]
	if kind != "cabin":
		camp.pay(d["cost"])
	var placed: Dictionary = camp.place(kind, gpos, gyaw)
	# В творческом режиме изба должна появляться готовой, а не оставаться площадкой.
	if kind == "cabin" and bool(main.get("creative_mode")):
		camp.start_building(placed)
	main._say(("Построено: " if kind != "cabin" or bool(main.get("creative_mode")) else "Заложена стройка: ") + String(d["name"]).to_lower())
	var k := kind
	select("")
	if k == "cabin" and not bool(main.get("creative_mode")):
		main._say("Вносите брёвна, мох, глину, доски и камни на стройку")
	return true

# ---------- касания ----------

func _process(delta: float) -> void:
	if not active or ghost == null:
		return
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = 0.5
		_check()   # припасы и снег могут меняться

func _unhandled_input(e: InputEvent) -> void:
	if not active or ghost == null:
		return
	if e is InputEventScreenTouch:
		var st := e as InputEventScreenTouch
		if st.pressed:
			var cam: Camera3D = get_viewport().get_camera_3d()
			var sp := cam.unproject_position(gpos + Vector3(0, 0.8, 0))
			_press_pos = st.position
			_press_t = Time.get_ticks_msec()
			if sp.distance_to(st.position) < 200.0:
				_drag_id = st.index
				get_viewport().set_input_as_handled()
		else:
			if st.index == _drag_id:
				_drag_id = -1
				get_viewport().set_input_as_handled()
			elif st.position.distance_to(_press_pos) < 20.0 and Time.get_ticks_msec() - _press_t < 300:
				# короткий тап по земле — призрак туда
				var hit := _ray(st.position)
				if hit != Vector3.INF:
					_move(hit)
	elif e is InputEventScreenDrag and (e as InputEventScreenDrag).index == _drag_id:
		var hit2 := _ray((e as InputEventScreenDrag).position)
		if hit2 != Vector3.INF:
			_move(hit2)
		get_viewport().set_input_as_handled()

## Луч из камеры до земли (шагами, затем делением пополам).
func _ray(sp: Vector2) -> Vector3:
	var cam: Camera3D = get_viewport().get_camera_3d()
	var o := cam.project_ray_origin(sp)
	var d := cam.project_ray_normal(sp)
	var t0 := 0.0
	var t := 0.0
	while t < 90.0:
		var p := o + d * t
		if p.y < main.height(p.x, p.z):
			var a := t0
			var b := t
			for i in 12:
				var m := (a + b) * 0.5
				var q := o + d * m
				if q.y < main.height(q.x, q.z):
					b = m
				else:
					a = m
			return o + d * b
		t0 = t
		t += 0.5
	return Vector3.INF
