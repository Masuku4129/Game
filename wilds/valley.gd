extends Node2D
## Уровень 1 «Туманная долина»: хижина -> лесная тропа -> река с мостом -> берег -> арена с боссом.
## Земля, тропа и река рисуются текстурами из art/valley, лес расставляется по маске проходов.

const DATA = preload("res://art/valley/art_data.gd").DATA
const FogDrift := preload("res://fog_drift.gd")

const BOUNDS := Rect2(-1200.0, -3300.0, 5800.0, 4800.0)
const BRIDGE_POS := Vector2(2800.0, 330.0)
const ARENA := Vector2(3450.0, -2600.0)
const CELL := 60.0

var spawn := Vector2(0.0, 240.0)
var origin := Vector2.ZERO
var clear_color := Color(0.74, 0.80, 0.83)
var vignette := Color(0.56, 0.60, 0.76, 0.55)

var world: Node2D
var rng := RandomNumberGenerator.new()
var river: PackedVector2Array
var path_w: PackedVector2Array
var path_e: PackedVector2Array
var blocked := PackedByteArray()
var gw := 0
var gh := 0
var _shadow_tex: Texture2D


func build(world_node: Node2D) -> void:
	world = world_node
	rng.seed = 20261124
	river = _smooth([Vector2(2900, 1800), Vector2(2950, 1000), Vector2(2800, 330), Vector2(2830, -300),
		Vector2(2980, -900), Vector2(3060, -1500), Vector2(3000, -2300), Vector2(2900, -3500)], 30.0)
	path_w = _smooth([Vector2(0, 150), Vector2(350, 230), Vector2(800, 150), Vector2(1300, 290),
		Vector2(1800, 380), Vector2(2250, 300), Vector2(2560, 330)], 30.0)
	path_e = _smooth([Vector2(3040, 330), Vector2(3320, 200), Vector2(3430, -300), Vector2(3540, -900),
		Vector2(3600, -1500), Vector2(3540, -2100), Vector2(3460, -2500)], 30.0)

	_make_ground()
	_make_borders()
	_make_river_collision()
	_make_blocked_mask()
	_place_hut()
	_scatter()
	_arena_ring()
	_spawn_enemies()
	_make_side_paths()
	_make_fog()
	_make_bridge_trigger()


# ------------------------------------------------------------------ утилиты

func lift_at(_wp: Vector2) -> float:
	return 0.0


func preview_info() -> Dictionary:
	return {
		"center": BOUNDS.get_center(),
		"zoom": 0.15,
		"spots": [Vector2(0, 260), Vector2(1200, 300), Vector2(2800, 360), Vector2(3430, -500),
			Vector2(3450, -2300), Vector2(800, -900), Vector2(2900, -1500), Vector2(-400, 600)],
	}


func _tex(name: String) -> Texture2D:
	return load("res://art/valley/%s.png" % name)


func _smooth(pts: Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n - 1:
		var p0: Vector2 = pts[maxi(i - 1, 0)]
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[i + 1]
		var p3: Vector2 = pts[mini(i + 2, n - 1)]
		var cnt := maxi(2, int(p1.distance_to(p2) / step))
		for k in cnt:
			var t := float(k) / cnt
			out.append(0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
				+ (3.0 * p1 - p0 - 3.0 * p2 + p3) * t * t * t))
	out.append(pts[n - 1])
	return out


func _line(pts: PackedVector2Array, tex: Texture2D, width: float) -> Line2D:
	var l := Line2D.new()
	l.points = pts
	l.texture = tex
	l.texture_mode = Line2D.LINE_TEXTURE_TILE
	l.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	l.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	l.width = width
	l.joint_mode = Line2D.LINE_JOINT_ROUND
	l.begin_cap_mode = Line2D.LINE_CAP_ROUND
	l.end_cap_mode = Line2D.LINE_CAP_ROUND
	l.default_color = Color.WHITE
	return l


func _sprite(tex: Texture2D, pos: Vector2, pivot: Vector2, sc := 1.0) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.offset = -pivot
	s.position = pos
	s.scale = Vector2(sc, sc)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return s


func _shadow() -> Texture2D:
	if _shadow_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(0.06, 0.05, 0.14, 0.55))
		g.set_color(1, Color(0.06, 0.05, 0.14, 0.0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 128
		t.height = 128
		_shadow_tex = t
	return _shadow_tex


# ------------------------------------------------------------------ земля, река, тропа

func _make_ground() -> void:
	var under := Node2D.new()
	add_child(under)
	var g := Sprite2D.new()
	g.texture = _tex("grass")
	g.centered = false
	g.region_enabled = true
	g.region_rect = Rect2(Vector2.ZERO, BOUNDS.size)
	g.position = BOUNDS.position
	g.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	g.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	under.add_child(g)
	# пятна: тёмный подлесок и светлые поляны
	for i in 110:
		var s := Sprite2D.new()
		s.texture = _tex("patch_dark" if rng.randf() < 0.65 else "patch_light")
		s.position = Vector2(rng.randf_range(BOUNDS.position.x, BOUNDS.end.x), rng.randf_range(BOUNDS.position.y, BOUNDS.end.y))
		var k := rng.randf_range(1.6, 3.6)
		s.scale = Vector2(k, k * 0.7)
		s.modulate.a = rng.randf_range(0.4, 0.8)
		under.add_child(s)
	under.add_child(_line(river, _tex("bank"), 560.0))
	var w := _line(river, _tex("water"), 340.0)
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nuniform float speed = 0.05;\nvoid fragment() {\n\tvec2 uv = UV;\n\tuv.x -= TIME * speed;\n\tCOLOR = texture(TEXTURE, uv);\n}\n"
	var mat := ShaderMaterial.new()
	mat.shader = sh
	w.material = mat
	under.add_child(w)
	for k in 2:
		under.add_child(_line(path_w, _tex("path"), 190.0))
		under.add_child(_line(path_e, _tex("path"), 190.0))
	# мост
	var b := _sprite(_tex("bridge"), BRIDGE_POS + Vector2(0, 45), Vector2(260, 135))
	under.add_child(b)
	# мягкий тёплый свет у хижины
	var pool := _sprite(_tex("glow_warm"), Vector2(-40, 30), Vector2(64, 64), 5.0)
	pool.scale = Vector2(5.5, 2.2)
	pool.modulate = Color(1.0, 0.86, 0.55, 0.28)
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	pool.material = m
	under.add_child(pool)


func _body(shape: Shape2D, pos: Vector2, rot := 0.0) -> void:
	var b := StaticBody2D.new()
	var c := CollisionShape2D.new()
	c.shape = shape
	c.position = pos
	c.rotation = rot
	b.add_child(c)
	add_child(b)


func _make_borders() -> void:
	var t := 300.0
	var r := BOUNDS
	for q in [
		[Vector2(r.size.x + 2.0 * t, t), Vector2(r.get_center().x, r.position.y - t * 0.5)],
		[Vector2(r.size.x + 2.0 * t, t), Vector2(r.get_center().x, r.end.y + t * 0.5)],
		[Vector2(t, r.size.y), Vector2(r.position.x - t * 0.5, r.get_center().y)],
		[Vector2(t, r.size.y), Vector2(r.end.x + t * 0.5, r.get_center().y)]]:
		var sh := RectangleShape2D.new()
		sh.size = q[0]
		_body(sh, q[1])


func _make_river_collision() -> void:
	var i := 0
	while i + 3 < river.size():
		var a := river[i]
		var b := river[i + 3]
		var mid := (a + b) * 0.5
		if mid.distance_to(BRIDGE_POS) > 300.0:
			var sh := RectangleShape2D.new()
			sh.size = Vector2(a.distance_to(b) + 14.0, 300.0)
			_body(sh, mid, (b - a).angle())
		i += 3
	# перила моста держат Миту на настиле
	for sy in [-78.0, 78.0]:
		var sh2 := RectangleShape2D.new()
		sh2.size = Vector2(580.0, 36.0)
		_body(sh2, BRIDGE_POS + Vector2(0, sy))


func _make_blocked_mask() -> void:
	gw = int(BOUNDS.size.x / CELL) + 1
	gh = int(BOUNDS.size.y / CELL) + 1
	blocked.resize(gw * gh)
	_mark(river, 340.0)
	_mark(path_w, 190.0)
	_mark(path_e, 190.0)
	_mark(PackedVector2Array([Vector2(0, 0), Vector2(0, 120)]), 400.0)
	_mark(PackedVector2Array([ARENA, ARENA + Vector2(0, 1)]), 600.0)


func _mark(poly: PackedVector2Array, radius: float) -> void:
	var rc := int(radius / CELL) + 1
	for p in poly:
		var cx := int((p.x - BOUNDS.position.x) / CELL)
		var cy := int((p.y - BOUNDS.position.y) / CELL)
		for dy in range(-rc, rc + 1):
			for dx in range(-rc, rc + 1):
				var x := cx + dx
				var y := cy + dy
				if x < 0 or y < 0 or x >= gw or y >= gh:
					continue
				var q := Vector2(dx, dy) * CELL
				if q.length() <= radius:
					blocked[y * gw + x] = 1


func _is_blocked(p: Vector2) -> bool:
	var x := int((p.x - BOUNDS.position.x) / CELL)
	var y := int((p.y - BOUNDS.position.y) / CELL)
	if x < 0 or y < 0 or x >= gw or y >= gh:
		return true
	return blocked[y * gw + x] == 1


# ------------------------------------------------------------------ объекты

func _prop(name: String, pos: Vector2, sc0: float, flip: bool, with_shadow := true) -> void:
	var sc := sc0
	if name.begins_with("t_"):
		sc *= 0.66
	elif name.begins_with("r_"):
		sc *= 0.8
	var d: Array = DATA[name]
	var body := StaticBody2D.new()
	body.position = pos
	if with_shadow:
		var sh := Sprite2D.new()
		sh.texture = _shadow()
		var w := 190.0 * sc
		if name.begins_with("r_"):
			w = 200.0 * sc
		elif name.begins_with("b_") or name.begins_with("f_") or name == "mush" or name == "stump":
			w = 120.0 * sc
		sh.scale = Vector2(w / 64.0, w * 0.34 / 64.0)
		body.add_child(sh)
	var s := _sprite(_tex(name), Vector2.ZERO, Vector2(d[0], d[1]), sc)
	if flip:
		s.scale.x = -sc
	body.add_child(s)
	if d[2] > 0:
		var c := CollisionShape2D.new()
		var cs := CircleShape2D.new()
		cs.radius = float(d[2]) * sc
		c.shape = cs
		body.add_child(c)
	world.add_child(body)


func _place_hut() -> void:
	var d: Array = DATA["hut1"]
	var body := StaticBody2D.new()
	body.position = Vector2.ZERO
	var sh := Sprite2D.new()
	sh.texture = _shadow()
	sh.scale = Vector2(4.4, 1.0)
	sh.position = Vector2(0, 8)
	body.add_child(sh)
	body.add_child(_sprite(_tex("hut1"), Vector2.ZERO, Vector2(d[0], d[1])))
	var c := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(330.0, 100.0)
	c.shape = r
	c.position = Vector2(0, -55)
	body.add_child(c)
	# свет окна
	var g := Sprite2D.new()
	g.texture = _tex("glow_warm")
	g.position = Vector2(-49, -200)
	g.scale = Vector2(1.6, 1.4)
	g.modulate = Color(1.0, 0.85, 0.5, 0.55)
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	g.material = m
	body.add_child(g)
	world.add_child(body)


func _scatter() -> void:
	var kinds := [["t_oak1", 0.06], ["t_oak2", 0.06], ["t_oak3", 0.05], ["t_pine1", 0.06], ["t_pine2", 0.06], ["t_pine3", 0.05],
		["t_birch1", 0.05], ["t_birch2", 0.05], ["t_dead", 0.01], ["b_1", 0.06], ["b_2", 0.05], ["b_3", 0.05],
		["r_1", 0.02], ["r_2", 0.02], ["r_3", 0.02], ["r_4", 0.02], ["f_1", 0.08], ["f_2", 0.07],
		["stump", 0.02], ["log", 0.015], ["mush", 0.015]]
	var grid := {}
	var placed := 0
	for t in 7000:
		var p := Vector2(rng.randf_range(BOUNDS.position.x + 80.0, BOUNDS.end.x - 80.0),
			rng.randf_range(BOUNDS.position.y + 80.0, BOUNDS.end.y - 80.0))
		if _is_blocked(p):
			continue
		var roll := rng.randf()
		var name := "f_1"
		var acc := 0.0
		for k in kinds:
			acc += k[1]
			if roll <= acc:
				name = k[0]
				break
		var gap := 135.0
		if name.begins_with("b_") or name.begins_with("r_") or name == "stump" or name == "log":
			gap = 105.0
		elif name.begins_with("f_") or name == "mush":
			gap = 65.0
		var key := Vector2i(int(p.x / 170.0), int(p.y / 170.0))
		var ok := true
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var arr = grid.get(Vector2i(key.x + dx, key.y + dy))
				if arr == null:
					continue
				for q in arr:
					if q.distance_squared_to(p) < gap * gap:
						ok = false
		if not ok:
			continue
		if not grid.has(key):
			grid[key] = []
		grid[key].append(p)
		placed += 1
		_prop(name, p, rng.randf_range(0.78, 1.1), rng.randf() < 0.5)
	print("valley props: ", placed)


func _arena_ring() -> void:
	# кольцо валунов вокруг арены; вход с юга свободен
	for i in 22:
		var a := TAU * float(i) / 22.0
		var dir := Vector2(cos(a), sin(a))
		if dir.y > 0.75:
			continue
		var p := ARENA + dir * Vector2(680.0, 560.0)
		_prop("r_1" if i % 2 == 0 else "r_2", p, rng.randf_range(1.1, 1.5), rng.randf() < 0.5)


func _make_fog() -> void:
	var layer := Node2D.new()
	layer.z_index = 20
	add_child(layer)
	for i in 70:
		var s := FogDrift.new()
		s.texture = _tex("fog%d" % (i % 3))
		s.position = Vector2(rng.randf_range(BOUNDS.position.x, BOUNDS.end.x), rng.randf_range(BOUNDS.position.y, BOUNDS.end.y))
		var k := rng.randf_range(3.0, 6.0)
		s.scale = Vector2(k, k * 0.8)
		s.modulate.a = rng.randf_range(0.06, 0.13)
		s.vel = Vector2(rng.randf_range(6.0, 16.0), rng.randf_range(-2.0, 2.0))
		s.area = BOUNDS
		layer.add_child(s)
	# гуще у воды
	for i in range(0, river.size(), 12):
		var s2 := FogDrift.new()
		s2.texture = _tex("fog%d" % (i % 3))
		s2.position = river[i] + Vector2(rng.randf_range(-120, 120), rng.randf_range(-60, 60))
		s2.scale = Vector2(4.5, 3.0)
		s2.modulate.a = 0.15
		s2.vel = Vector2(rng.randf_range(4.0, 9.0), 0.0)
		s2.area = BOUNDS
		layer.add_child(s2)


func _spawn_enemies() -> void:
	var groups := [
		[Vector2(1050, 210), "ch", 2], [Vector2(1850, 330), "ch", 3], [Vector2(2250, 280), "ch", 2],
		[Vector2(3250, 150), "sh", 2], [Vector2(3350, -150), "ch", 2],
		[Vector2(3480, -900), "ch", 3], [Vector2(3540, -1000), "sh", 2],
		[Vector2(3560, -1750), "sh", 2], [Vector2(3500, -1850), "ch", 3],
		# враги в боковых ответвлениях
		[Vector2(900, -450), "ch", 2], [Vector2(700, -700), "sh", 1],
		[Vector2(1800, 800), "ch", 3],
		# призраки-маги на мистических участках
		[Vector2(2800, 100), "wr", 1], [Vector2(3100, -300), "wr", 2],
		[Vector2(750, -600), "wr", 1]]
	for g in groups:
		for i in g[2]:
			var e = preload("res://enemy.gd").new()
			e.setup(g[1])
			e.position = g[0] + Vector2(rng.randf_range(-110, 110), rng.randf_range(-80, 80))
			world.add_child(e)


# ------------------------------------------------------------------ боковые тропки
func _make_side_paths() -> void:
	# -- северная боковая тропа (секрет) --
	# уходит с главной тропы на север у x≈1200, заканчивается полянкой
	var north_path := _smooth([
		Vector2(1200, 290), Vector2(1050, 100), Vector2(900, -150),
		Vector2(820, -400), Vector2(750, -680)], 25.0)
	var under := get_child(0)   # under = первый ребёнок, добавленный в _make_ground
	under.add_child(_line(north_path, _tex("path"), 130.0))
	# несколько камней и пней на секретной полянке
	for ox in [-90.0, 0.0, 90.0]:
		_prop("r_3", Vector2(750, -680) + Vector2(ox, rng.randf_range(-40, 40)),
			rng.randf_range(0.9, 1.3), rng.randf() < 0.5)
	for ox in [-50.0, 50.0, 0.0, -80.0]:
		_prop("f_2", Vector2(750, -680) + Vector2(ox, rng.randf_range(-60, 60)),
			rng.randf_range(0.8, 1.1), rng.randf() < 0.5)
	_prop("stump", Vector2(760, -700), 1.1, false)
	# светлячки-огоньки намекают на секрет
	for i in 5:
		var gp := Sprite2D.new()
		gp.texture = _tex("glow_warm")
		gp.position = Vector2(750, -680) + Vector2(rng.randf_range(-120, 120), rng.randf_range(-80, 80))
		gp.scale = Vector2(0.4, 0.3)
		gp.modulate = Color(0.6, 1.0, 0.7, 0.4)
		var m2 := CanvasItemMaterial.new()
		m2.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		gp.material = m2
		under.add_child(gp)
	# -- южная боковая тропа (укрытие у реки) --
	var south_path := _smooth([
		Vector2(1800, 380), Vector2(1900, 600), Vector2(2050, 760),
		Vector2(2200, 820)], 20.0)
	under.add_child(_line(south_path, _tex("path"), 110.0))
	# упавшее бревно перекрывает дальний конец
	_prop("log", Vector2(2210, 820), 1.3, false)
	_prop("r_2", Vector2(2170, 840), 1.0, true)
	# -- изломанная тропа на востоке (после моста не прямо, а с петлёй) --
	var east_loop := _smooth([
		Vector2(3040, 330), Vector2(3200, 100), Vector2(3380, -50),
		Vector2(3450, -300), Vector2(3350, -500), Vector2(3300, -700),
		Vector2(3400, -900), Vector2(3540, -900)], 25.0)
	under.add_child(_line(east_loop, _tex("path"), 155.0))
	# враги на петле уже в _spawn_enemies


# ------------------------------------------------------------------ триггер моста
func _make_bridge_trigger() -> void:
	# Area2D — когда игрок наступает на мост первый раз, открывает умение
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 4   # слой игрока (layer 4 нет — используем сигнал от body_shape)
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(500.0, 160.0)
	cs.shape = rect
	cs.position = BRIDGE_POS
	area.add_child(cs)
	# при наложении любого тела проверяем что это игрок
	area.body_entered.connect(_on_bridge_body(area))
	add_child(area)


func _on_bridge_body(area: Area2D) -> Callable:
	return func(body: Node2D) -> void:
		if not body.is_in_group("player"):
			return
		if body.skill_unlocked:
			return
		body.skill_unlocked = true
		area.set_deferred("monitoring", false)
		# уведомление — HUD покажет "Умение открыто!"
		var main := get_tree().current_scene
		if main.has_method("on_skill_unlocked"):
			main.on_skill_unlocked()
