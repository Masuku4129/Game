extends Node3D
## Бой и прицел (main.combat).
##
## Удар ближнего боя (hero_tools.attack) проверяет путь острия: melee_sweep — отрезки, пройденные
## инструментом за кадр; не задел, но зверь прямо перед героем на длине удара — melee_assist.
## Попадание (impact): урон по инструменту и месту → main.hunt.hit_animal (кровь, бегство),
## стоп-кадр 60 мс, тряска камеры, звук удара, брызги, зверь вздрагивает (flinch).
##
## Прицел (begin_aim "spear" | "bow"): палец ведёт от точки касания в сторону броска,
## длина — сила; видна дуга полёта и место падения (красная — зверь на пути). Отпустить — бросок
## или выстрел, «Отмена» — опустить. Лук натягивается по силе (hero_tools.drawk).
##
## Стрелы в живом звере едут с ним (carry_arrow), у убитого — остаются, выпавшие — лежат: их подбирают.
## Проверка: COMBAT_TEST=1 (или папка — с кадрами) — пояс, брёвна, связка, удары, бросок, лук, присед.

const IT = preload("res://scripts/items.gd")
const INV = preload("res://scripts/inventory.gd")
const ZONE_K := {"head": 1.8, "body": 1.0, "legs": 0.6}
const DRAG_FULL := 320.0      # px: столько тянуть до полной силы

var main: Node3D
var ui: CanvasLayer
var pad: AimPad
var arc := MeshInstance3D.new()
var arc_mesh := ImmediateMesh.new()
var arc_mat := StandardMaterial3D.new()
var aim_kind := ""
var aim_dir := Vector3.FORWARD
var aim_pow := 0.0
var aim_pitch := 0.0
var aim_hit := false
var _shake := 0.0
var _shake_t := 0.0
var _stops := 0
var _flinch: Array = []       # [зверь, направление (от героя), время, сила]
var _carried: Array = []      # [стрела, зверь, стрела в осях зверя, время]
var _twang: AudioStreamWAV
var _blood: CPUParticles3D
var _rng := RandomNumberGenerator.new()

## Слой прицела: подсказка, черта от касания, сила; «Отмена».
class AimPad extends Control:
	var c: Node
	var touch := -1
	var start := Vector2.ZERO
	var cur := Vector2.ZERO
	var cancel_btn: Button
	func _ready() -> void:
		anchor_right = 1.0
		anchor_bottom = 1.0
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		cancel_btn = Button.new()
		cancel_btn.text = "Отмена"
		cancel_btn.anchor_left = 1.0
		cancel_btn.anchor_right = 1.0
		cancel_btn.anchor_top = 0.0
		cancel_btn.anchor_bottom = 0.0
		cancel_btn.offset_left = -330.0
		cancel_btn.offset_right = -80.0
		cancel_btn.offset_top = 130.0
		cancel_btn.offset_bottom = 240.0
		cancel_btn.focus_mode = Control.FOCUS_NONE
		INV.style_button(cancel_btn, 34)
		cancel_btn.pressed.connect(func() -> void: c.cancel_aim())
		add_child(cancel_btn)
	func _input(e: InputEvent) -> void:
		if not visible:
			return
		if e is InputEventScreenTouch:
			var st := e as InputEventScreenTouch
			if st.pressed and touch == -1:
				if cancel_btn.get_global_rect().has_point(st.position) or _on_joy(st.position):
					return
				touch = st.index
				start = st.position
				cur = st.position
				get_viewport().set_input_as_handled()
				queue_redraw()
			elif not st.pressed and st.index == touch:
				touch = -1
				get_viewport().set_input_as_handled()
				c.release_aim()
				queue_redraw()
		elif e is InputEventScreenDrag:
			var sd := e as InputEventScreenDrag
			if sd.index == touch:
				cur = sd.position
				c.drag_aim(cur - start)
				get_viewport().set_input_as_handled()
				queue_redraw()
	func _on_joy(p: Vector2) -> bool:
		var j: Control = c.main.get("joy")
		return j != null and j.visible and j.get_global_rect().has_point(p)
	func _draw() -> void:
		var f := ThemeDB.fallback_font
		var t := "Ведите пальцем в сторону броска: дальше — сильнее. Отпустите — %s" % ("выстрел" if c.aim_kind == "bow" else "бросок")
		var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x + 40.0
		var r := Rect2(size.x * 0.5 - w * 0.5, 70, w, 48)
		draw_rect(Rect2(r.position + Vector2(4, 5), r.size), Color(0, 0, 0, 0.25))
		draw_rect(r, Color(0.88, 0.8, 0.62, 0.88))
		draw_rect(r, Color(0.4, 0.28, 0.16, 0.95), false, 3.0)
		draw_string(f, r.position + Vector2(20, 33), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.24, 0.15, 0.08))
		if touch != -1:
			var v := cur - start
			var k := clampf(v.length() / DRAG_FULL, 0.0, 1.0)
			draw_circle(start, 22.0, Color(1, 0.95, 0.85, 0.5))
			draw_arc(start, DRAG_FULL, 0.0, TAU, 64, Color(1, 0.95, 0.85, 0.22), 3.0, true)
			var col := Color(0.95, 0.8, 0.35).lerp(Color(0.9, 0.3, 0.15), k)
			draw_line(start, start + v.limit_length(DRAG_FULL), col, 8.0, true)
			draw_circle(start + v.limit_length(DRAG_FULL), 16.0, col)
			# сила: дуга вокруг точки касания
			draw_arc(start, 46.0, -PI * 0.5, -PI * 0.5 + TAU * k, 40, col, 10.0, true)

func setup(layer: CanvasLayer) -> void:
	ui = layer
	pad = AimPad.new()
	pad.c = self
	pad.visible = false
	ui.add_child(pad)

func _ready() -> void:
	_rng.seed = 909
	arc.mesh = arc_mesh
	arc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	arc_mat.no_depth_test = true
	arc_mat.vertex_color_use_as_albedo = true
	arc_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	arc.material_override = arc_mat
	arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arc.visible = false
	add_child(arc)
	_blood = CPUParticles3D.new()
	_blood.emitting = false
	_blood.one_shot = true
	_blood.amount = 18
	_blood.lifetime = 0.7
	_blood.explosiveness = 1.0
	_blood.spread = 40.0
	_blood.initial_velocity_min = 1.5
	_blood.initial_velocity_max = 3.2
	_blood.gravity = Vector3(0, -9.8, 0)
	_blood.scale_amount_min = 0.5
	_blood.scale_amount_max = 1.2
	_blood.local_coords = false
	var bm := BoxMesh.new()
	bm.size = Vector3(0.025, 0.025, 0.025)
	var mt := StandardMaterial3D.new()
	mt.albedo_color = Color(0.45, 0.04, 0.03)
	mt.roughness = 0.4
	bm.material = mt
	_blood.mesh = bm
	add_child(_blood)
	_twang = _make_twang()

func _tools() -> Node:
	if main == null or main.hero == null:
		return null
	return main.hero.tools

# ---------- удар ----------

## Путь инструмента за кадр: отрезки [[a, b], ...] в мире. Задел зверя — попадание.
func melee_sweep(tool: String, segs: Array) -> bool:
	var w: Node = main.get("tools_world")
	if w == null or main.animals == null:
		return false
	for a: Node3D in main.animals.near(main.hero.position, 4.5):
		if a.dead or not a.visible:
			continue
		for sg: Array in segs:
			var z: Array = w._hit_zone(a, sg[0], sg[1], 0.1)
			if not z.is_empty():
				impact(a, String(z[0]), tool, z[1])
				return true
	return false

## Удар не прошёл через зверя, но тот прямо перед героем на длине удара — засчитать по корпусу.
func melee_assist(tool: String) -> bool:
	var T := _tools()
	var m: Dictionary = T.MELEE[tool]
	var hp: Vector3 = main.hero.position
	var yaw: float = main.hero.body.rotation.y
	for a: Node3D in main.animals.near(hp, 4.5):
		if a.dead or not a.visible:
			continue
		var d: Vector3 = a.position - hp
		var dl := Vector2(d.x, d.z).length() - float(a.parts.get("L", 1.0)) * 0.35
		if dl > float(m["reach"]) or absf(d.y) > 1.4:
			continue
		if absf(wrapf(atan2(d.x, d.z) - yaw, -PI, PI)) > 0.75:
			continue
		var H: float = float(a.parts.get("H", 0.7))
		impact(a, "body", tool, a.position + Vector3(0, H * 0.6, 0))
		return true
	return false

## Попадание: урон, кровь (hunt), стоп-кадр, тряска, звук, зверь вздрагивает.
func impact(a: Node3D, zone: String, tool: String, p: Vector3) -> void:
	var T := _tools()
	var m: Dictionary = T.MELEE[tool]
	var dmg: float = float(m["dmg"]) * float(ZONE_K.get(zone, 1.0))
	var hero: Node3D = main.hero
	if main.get("hunt") != null and main.hunt != null:
		main.hunt.hit_animal(a, dmg, hero.position)
	else:
		a.bitten(hero)
	match tool:
		"axe":
			_snd("chop", p, 4.0, 0.72)
			_snd("thunk", p, 2.0, 0.7)
		"spear":
			_snd("thunk", p, 3.0, 0.85)
		_:
			_snd("cut", p, 0.0, 1.35)
			_snd("thunk", p, -4.0, 1.4)
	var away: Vector3 = a.position - hero.position
	away.y = 0.0
	_blood.global_position = p
	_blood.direction = (away.normalized() + Vector3(0, 0.6, 0)).normalized() if away.length() > 0.01 else Vector3.UP
	_blood.restart()
	_blood.emitting = true
	flinch(a, away, 1.0)
	shake({"axe": 0.11, "spear": 0.08}.get(tool, 0.05))
	hit_stop(0.06)
	var rn := String({"roe": "косуля"}.get(a.kind, a.kind))
	if main.get("hunt") != null and main.hunt != null:
		rn = String(main.hunt.RU.get(a.kind, rn))
	if a.dead:
		main._say("Добыча: %s" % rn)
	else:
		var fem: bool = a.kind in ["roe", "lynx", "wolverine", "fox", "muskdeer", "squirrel"]
		main._say("%s — %s %s" % [String({"head": "Удар в голову", "body": "Удар в бок", "legs": "Удар по ногам"}[zone]), rn, "ранена" if fem else "ранен"])

func _snd(n: String, p: Vector3, db: float, pitch: float) -> void:
	if main.sfx != null:
		main.sfx.play_at(n, p, db, pitch * _rng.randf_range(0.94, 1.06))

## Свист замаха.
func swish(tool: String, p: Vector3) -> void:
	_snd("whoosh", p, {"axe": -3.0, "spear": -5.0}.get(tool, -8.0), {"axe": 0.8, "spear": 1.0}.get(tool, 1.35))

## Стоп-кадр: мир замирает на миг (время — настоящее, не игровое).
func hit_stop(sec: float) -> void:
	_stops += 1
	Engine.time_scale = 0.05
	await get_tree().create_timer(sec, true, false, true).timeout
	_stops -= 1
	if _stops <= 0:
		_stops = 0
		Engine.time_scale = 1.0

func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)
	_shake_t = 0.0

## Зверь вздрагивает: наклон прочь от удара и обратно.
func flinch(a: Node3D, away: Vector3, k: float) -> void:
	if a == null or a.dead:
		return
	for f: Array in _flinch:
		if f[0] == a:
			f[1] = away
			f[2] = 0.0
			f[3] = k
			return
	_flinch.append([a, away, 0.0, k])

## Стрела в живом звере: едет с ним; зверь убит — остаётся, иначе выпадает через 8 с.
func carry_arrow(node: Node3D, a: Node3D) -> void:
	_carried.append([node, a, a.global_transform.affine_inverse() * node.global_transform, 0.0])

## Звон тетивы.
func twang(p: Vector3) -> void:
	var pl := AudioStreamPlayer3D.new()
	pl.stream = _twang
	pl.volume_db = -4.0
	pl.pitch_scale = _rng.randf_range(0.95, 1.08)
	add_child(pl)
	pl.global_position = p
	pl.play()
	pl.finished.connect(pl.queue_free)

## Щипок струны (Карплус — Стронг) с глухим ударом плеча лука.
func _make_twang() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.45)
	var per := int(rate / 98.0)
	var buf := PackedFloat32Array()
	buf.resize(per)
	var r := RandomNumberGenerator.new()
	r.seed = 5
	for i in per:
		buf[i] = r.randf_range(-1.0, 1.0)
	var data := PackedByteArray()
	data.resize(n * 2)
	var idx := 0
	for i in n:
		var a := buf[idx]
		var b := buf[(idx + 1) % per]
		buf[idx] = (a + b) * 0.5 * 0.996
		idx = (idx + 1) % per
		var t := float(i) / rate
		var thump := sin(TAU * 70.0 * t) * exp(-t * 40.0) * 0.6
		var v := clampf((a * exp(-t * 7.0) * 0.55 + thump), -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w

# ---------- прицел ----------

func begin_aim(kind: String) -> bool:
	var T := _tools()
	if T == null or aim_kind != "":
		return false
	if not T.aim_begin(kind):
		return false
	aim_kind = kind
	var yaw: float = main.hero.body.rotation.y
	aim_dir = Vector3(sin(yaw), 0, cos(yaw))
	aim_pow = 0.55
	# зверь впереди — прицел сразу на него
	var w: Node = main.get("tools_world")
	if w != null:
		var tg: Vector3 = w.aim_target(main.hero.position, yaw)
		if tg != Vector3.INF:
			var d: Vector3 = tg - main.hero.position
			d.y = 0.0
			aim_dir = d.normalized()
			aim_pow = _pow_for(tg)
	T.aim_face(aim_dir)
	_update_pitch()
	pad.visible = true
	pad.queue_redraw()
	arc.visible = true
	return true

## Сила, при которой дуга проходит ближе всего к точке tg (перебор).
func _pow_for(tg: Vector3) -> float:
	var best := 0.5
	var bd := 1e9
	for i in 41:
		var k := float(i) / 40.0
		for q: Vector3 in _simulate(k, false):
			var dl := q.distance_to(tg)
			if dl < bd:
				bd = dl
				best = k
	return best

func drag_aim(v: Vector2) -> void:
	if aim_kind == "" or v.length() < 6.0:
		return
	var yaw: float = main.rig.rotation.y if main.get("rig") != null else 0.0
	aim_dir = Vector3(v.x, 0, v.y).normalized().rotated(Vector3.UP, yaw)
	aim_pow = clampf(v.length() / DRAG_FULL, 0.0, 1.0)
	_update_pitch()
	var T := _tools()
	if T != null:
		T.aim_face(aim_dir)

func release_aim() -> void:
	if aim_kind == "":
		return
	if aim_pow < 0.08:
		return
	var T := _tools()
	if T != null:
		T.aim_release(aim_vel())
	_end_aim()

func cancel_aim() -> void:
	var T := _tools()
	if T != null:
		T.aim_cancel()
	_end_aim()

func _end_aim() -> void:
	aim_kind = ""
	pad.touch = -1
	pad.visible = false
	arc.visible = false

func _update_pitch() -> void:
	if aim_kind == "bow":
		aim_pitch = deg_to_rad(lerpf(2.0, 8.0, aim_pow))
	else:
		aim_pitch = deg_to_rad(lerpf(8.0, 15.0, aim_pow))

func _speed(k: float) -> float:
	return lerpf(16.0, 44.0, k) if aim_kind == "bow" else lerpf(8.0, 21.0, k)

func aim_vel() -> Vector3:
	return (aim_dir * cos(aim_pitch) + Vector3.UP * sin(aim_pitch)) * _speed(aim_pow)

## Полёт как в world_tools._fly: точки дуги до земли, ствола или зверя (aim_hit — зверь).
func _simulate(k: float, mark: bool) -> Array:
	var T := _tools()
	var save_pow := aim_pow
	var save_pitch := aim_pitch
	aim_pow = k
	_update_pitch()
	var v := aim_vel()
	aim_pow = save_pow
	aim_pitch = save_pitch
	var p: Vector3 = T.launch_point(aim_kind)
	var tip := 0.74 if aim_kind == "bow" else 1.1
	var drag := 0.01 if aim_kind == "bow" else 0.02
	var w: Node = main.get("tools_world")
	var pts: Array = [p]
	if mark:
		aim_hit = false
	var dt := 1.0 / 30.0
	for i in 150:
		v += Vector3(0, -9.8, 0) * dt
		v *= 1.0 - drag * dt
		var p1 := p + v * dt
		var t1 := p1 + v.normalized() * tip
		if mark and w != null and main.animals != null:
			for a: Node3D in main.animals.near(t1, 5.0):
				if a.dead or not a.visible:
					continue
				if not (w._hit_zone(a, p + v.normalized() * tip, t1, 0.0) as Array).is_empty():
					aim_hit = true
					pts.append(t1)
					return pts
		var gy: float = main.ground_at(t1.x, t1.z)
		if t1.y <= gy:
			pts.append(Vector3(t1.x, gy, t1.z))
			return pts
		if i > 2 and t1.y - main.height(t1.x, t1.z) < 7.0 and main.blocked(t1.x, t1.z, 0.0):
			pts.append(t1)
			return pts
		p = p1
		pts.append(p + v.normalized() * tip)
	return pts

## Дуга: пунктир-лента лицом к камере и кольцо там, где снаряд упадёт.
func _draw_arc() -> void:
	arc_mesh.clear_surfaces()
	var pts := _simulate(aim_pow, true)
	if pts.size() < 2:
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	var cp := cam.global_position if cam != null else Vector3(0, 50, 0)
	var col := Color(1.0, 0.92, 0.6, 0.85) if not aim_hit else Color(1.0, 0.35, 0.2, 0.9)
	arc_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var along := 0.0
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var sl := a.distance_to(b)
		along += sl
		if int(along / 0.45) % 2 == 1:
			continue
		var d := (b - a).normalized()
		var s := d.cross((cp - a).normalized()).normalized() * 0.045
		var c2 := col
		c2.a *= clampf(1.0 - float(i) / pts.size() * 0.4, 0.4, 1.0)
		for q: Vector3 in [a - s, a + s, b + s, a - s, b + s, b - s]:
			arc_mesh.surface_set_color(c2)
			arc_mesh.surface_add_vertex(q)
	var e: Vector3 = pts[pts.size() - 1]
	var gy: float = main.ground_at(e.x, e.z)
	var ctr := Vector3(e.x, maxf(gy, e.y - 0.05) + 0.06, e.z)
	for j in 28:
		var a0 := TAU * j / 28.0
		var a1 := TAU * (j + 1) / 28.0
		for rr: Array in [[0.32, 0.42]]:
			var r0: float = rr[0]
			var r1: float = rr[1]
			var p00 := ctr + Vector3(cos(a0) * r0, 0, sin(a0) * r0)
			var p01 := ctr + Vector3(cos(a1) * r0, 0, sin(a1) * r0)
			var p10 := ctr + Vector3(cos(a0) * r1, 0, sin(a0) * r1)
			var p11 := ctr + Vector3(cos(a1) * r1, 0, sin(a1) * r1)
			for q2: Vector3 in [p00, p10, p11, p00, p11, p01]:
				arc_mesh.surface_set_color(col)
				arc_mesh.surface_add_vertex(q2)
	arc_mesh.surface_end()

func _process(delta: float) -> void:
	if main == null:
		return
	var rd := delta / maxf(Engine.time_scale, 0.01)
	# прицел: держится, пока герой держит копьё или лук наготове
	if aim_kind != "":
		var T := _tools()
		if T == null or not (T.act in ["throw", "shoot"]) or not T.act_data.get("aiming", false):
			_end_aim()
		else:
			_draw_arc()
	# тряска камеры
	if main.get("rig") != null and main.rig != null:
		var cam: Camera3D = main.rig.cam
		if _shake > 0.0:
			_shake_t += rd
			var k := maxf(0.0, 1.0 - _shake_t / 0.28)
			var a := _shake * k * k
			cam.h_offset = sin(_shake_t * 71.0) * a
			cam.v_offset = cos(_shake_t * 57.0) * a * 0.8
			if k <= 0.0:
				_shake = 0.0
				cam.h_offset = 0.0
				cam.v_offset = 0.0
	# зверь вздрагивает
	for i in range(_flinch.size() - 1, -1, -1):
		var f: Array = _flinch[i]
		var a2: Node3D = f[0]
		f[2] = float(f[2]) + rd
		var t: float = f[2]
		if not is_instance_valid(a2) or t > 0.34:
			if is_instance_valid(a2):
				a2.rotation.x = 0.0
				a2.rotation.z = 0.0
			_flinch.remove_at(i)
			continue
		var kk := (t / 0.05) if t < 0.05 else 1.0 - smoothstep(0.05, 0.34, t)
		var away: Vector3 = f[1]
		var loc := away.normalized().rotated(Vector3.UP, -a2.rotation.y) if away.length() > 0.01 else Vector3.ZERO
		var tilt := 0.2 * float(f[3]) * kk
		a2.rotation.x = loc.z * tilt
		a2.rotation.z = -loc.x * tilt
	# стрелы в звере
	var w: Node = main.get("tools_world")
	for i2 in range(_carried.size() - 1, -1, -1):
		var c: Array = _carried[i2]
		var node: Node3D = c[0]
		var an: Node3D = c[1]
		c[3] = float(c[3]) + delta
		if not is_instance_valid(node):
			_carried.remove_at(i2)
			continue
		if not is_instance_valid(an) or not an.visible or float(c[3]) > 8.0:
			var gp := node.global_position
			gp.y = main.ground_at(gp.x, gp.z)
			w._lie(node, gp, node.global_transform.basis.y, "arrow")
			_carried.remove_at(i2)
			continue
		node.global_transform = an.global_transform * (c[2] as Transform3D)
		if an.dead:
			w.items.append({"id": "arrow", "node": node, "pos": node.global_position})
			_carried.remove_at(i2)
	if OS.get_environment("COMBAT_TEST") != "":
		_test(delta)

# ---------- проверка: COMBAT_TEST=1 или папка для кадров ----------

var _tt := 0.0
var _tn := 0
var _fails: Array = []
var _td := {}

func _ok(cond: bool, what: String) -> void:
	if not cond:
		_fails.append(what)
		print("CT FAIL ", what)

func _hud_ok(T: Node) -> String:
	var hud: Node = main.hud
	hud._ui_t = 0.0
	hud._process(0.0)
	for id: String in hud.belt_btns:
		var b: Control = hud.belt_btns[id]
		if b.visible != (T.place_of(id) != ""):
			return "%s: кнопка %s, место «%s»" % [id, "видна" if b.visible else "скрыта", T.place_of(id)]
		if bool(b.get("hot")) != (T.held == id):
			return "%s: кнопка %s, в руке «%s»" % [id, "горит" if b.get("hot") else "не горит", T.held]
	return ""

func _steps(T: Node, n: int) -> void:
	for i in n:
		T.process(1.0 / 60.0)

## Повернуть героя туда, где на dist метров нет стволов и кустов (для проверки бросков).
func _clear_yaw(dist: float) -> void:
	var hero: Node3D = main.hero
	for k in 24:
		var yaw := TAU * k / 24.0
		var ok := true
		var d := 1.0
		while d < dist + 1.5:
			var q: Vector3 = hero.position + Vector3(sin(yaw), 0, cos(yaw)) * d
			if main.blocked(q.x, q.z, 0.3) or main.ground_at(q.x, q.z) < main.WATER_Y + 0.3 or absf(main.ground_at(q.x, q.z) - hero.position.y) > 2.0:
				ok = false
				break
			d += 0.5
		if ok:
			hero.body.rotation.y = yaw
			return

func _foe_in_front(dist: float) -> Node3D:
	var hero: Node3D = main.hero
	for x: Node3D in main.animals.list:
		if not x.dead and x.kind in ["roe", "deer", "boar", "moose"] and x.position.y > main.WATER_Y + 0.5:
			var yaw: float = hero.body.rotation.y
			x.position = hero.position + Vector3(sin(yaw), 0, cos(yaw)) * dist
			x.position.y = main.ground_at(x.position.x, x.position.z)
			x.heading = yaw + PI * 0.5
			x.state = "rest"
			_td["an"] = x
			_td["an_p"] = x.position
			return x
	return null

func _shot(n: String) -> void:
	var dir := OS.get_environment("COMBAT_TEST")
	if dir.length() <= 1:
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir + "/" + n + ".png")
	print("CT shot ", n)

func _look(p: Vector3, yaw: float, dist: float, pitch: float) -> void:
	main.rig.position = p
	main.rig.rotation.y = yaw
	main.rig.distance = dist
	main.rig.pitch = pitch

func _test(delta: float) -> void:
	_tt += delta
	var hero: Node3D = main.hero
	var T: Node = hero.tools
	var w: Node = main.tools_world
	if _td.has("an_p"):
		var anx: Node3D = _td["an"]
		if not anx.dead:
			anx.position = _td["an_p"]
			anx.state = "rest"
	if _td.has("look"):
		var lk: Array = _td["look"]
		_look(lk[0], lk[1], lk[2], lk[3])
	var plan := [[3.0, "belt"], [3.5, "logs"], [5.0, "carry2"], [6.5, "carry2_shot"], [7.0, "tie"], [8.6, "drag"], [11.5, "drag_check"], [11.6, "site"], [13.5, "untie"],
		[15.0, "spear_stick"], [16.2, "stick_check"], [16.4, "place_knife"], [16.8, "melee_knife"], [17.6, "place_axe"], [18.0, "melee_axe"], [18.8, "place_spear"], [19.2, "melee_spear"],
		[20.0, "place_far"], [20.4, "aim_spear"], [20.6, "aim_shot"], [21.8, "aim_release"],
		[23.0, "bow"], [23.2, "place_bow"], [23.6, "bow_aim"], [24.3, "bow_shot"], [24.5, "bow_release"], [26.5, "bow_check"], [26.7, "crouch"], [27.5, "report"]]
	if _tn >= plan.size() or _tt < float(plan[_tn][0]):
		if _td.has("drag_t"):
			# волок: герой идёт по кругу, связка — следом
			var dt: float = float(_td["drag_t"]) + delta
			_td["drag_t"] = dt
			var c0: Vector3 = _td["drag_c"]
			var ang := dt * 0.45
			var np := c0 + Vector3(sin(ang), 0, cos(ang)) * 4.0
			np.y = main.ground_at(np.x, np.z)
			var dv := np - hero.position
			hero.position = np
			if dv.length() > 0.001:
				hero.body.rotation.y = atan2(dv.x, dv.z)
			var bd: Node3D = T.bundle
			if bd != null:
				var fd := Vector2(bd.front.x - hero.position.x, bd.front.z - hero.position.z).length()
				_td["drag_max"] = maxf(float(_td.get("drag_max", 0.0)), fd)
		return
	var a: String = plan[_tn][1]
	_tn += 1
	match a:
		"belt":
			main.inv.merge({"axe": 1, "bow": 1, "arrow": 12, "rope": 2, "spear": 1}, true)
			var ids := ["knife", "axe", "bow"]
			var r := RandomNumberGenerator.new()
			r.seed = 77
			var bad := 0
			for i in 300:
				var op := r.randi_range(0, 9)
				var id: String = ids[r.randi_range(0, 2)]
				var was: String = T.held
				match op:
					0, 1, 2, 3, 4:
						T.toggle(id)
						if was == id:
							_ok(T.held != id, "toggle %s: осталась в руке" % id)
						else:
							_ok(T.held == id, "toggle %s: не в руке (было «%s», место «%s»)" % [id, was, T.place_of(id)])
					5:
						T.holster()
					6:
						T.to_belt(id)
					7:
						T.to_pack(id)
					8:
						T.draw(id)
					9:
						main.hud._belt_pressed(id)
				_steps(T, r.randi_range(0, 40))
				var e1: String = T.check()
				var e2 := _hud_ok(T)
				if e1 != "" or e2 != "":
					bad += 1
					if bad < 6:
						_ok(false, "пояс шаг %d: %s %s" % [i, e1, e2])
				# после перехода — модели на своих местах
				if i % 10 == 0:
					_steps(T, 40)
					var e3: String = T.check()
					if e3 != "":
						bad += 1
						_ok(false, "пояс после перехода %d: %s" % [i, e3])
			print("CT belt ops=300 bad=", bad, " held=", T.held, " belt=", T.belt, " back=", T.back)
			_td["home"] = hero.position
			# поляна: без стволов и кустов на 7 м вокруг, ровно, не вода — для кадров и бросков
			var h0: Vector3 = hero.position
			for ring in range(0, 40):
				var found := false
				for k in 16:
					var q: Vector3 = h0 + Vector3(sin(TAU * k / 16.0), 0, cos(TAU * k / 16.0)) * ring * 4.0
					q.y = main.ground_at(q.x, q.z)
					if main.blocked(q.x, q.z, 7.0) or q.y < main.WATER_Y + 1.0 or main.ground_normal(q.x, q.z).y < 0.95:
						continue
					hero.position = q
					_td["home"] = q
					found = true
					break
				if found:
					break
			print("CT clearing at ", hero.position - h0)
			T.to_pack("bow")
			T.holster()
			_steps(T, 40)
		"logs":
			var yaw: float = hero.body.rotation.y
			var f := Vector3(sin(yaw), 0, cos(yaw))
			var rg := Vector3(-cos(yaw), 0, sin(yaw))
			for i in 6:
				w.drop_log(hero.position + f * 0.9 + rg * (float(i) - 2.5) * 0.3, yaw + PI * 0.5)
			print("CT logs near=", w.logs_near(hero.position, 2.6).size(), " label=", hero.action_label())
			main.inv.erase("rope")
			_ok(T.action_label() == "Взять бревно на плечо", "метка бревна: " + T.action_label())
			T.do_action()
			_steps(T, 75)
		"carry2":
			_ok(T.held == "log" and T.logs == 1, "одно бревно: %s %d" % [T.held, T.logs])
			_ok(absf(T.speed_factor() - 0.8) < 0.01, "скорость 1 бревно %.2f" % T.speed_factor())
			_ok(T.action_label() == "Взять второе бревно", "метка второго: " + T.action_label())
			T.do_action()
			_steps(T, 75)
		"carry2_shot":
			_ok(T.logs == 2, "два бревна: %d" % T.logs)
			_ok(absf(T.speed_factor() - 0.65) < 0.01, "скорость 2 бревна %.2f" % T.speed_factor())
			_td["look"] = [hero.position + Vector3(0, 0.3, 0), hero.body.rotation.y + 1.2, 4.2, 20.0]
			_shot("carry_2logs")
		"tie":
			_td.erase("look")
			main.inv["rope"] = 2
			_ok(T.action_label() == "Связать брёвна", "метка связать: " + T.action_label())
			T.do_action()
			_steps(T, 85)
		"drag":
			_ok(T.bundle != null, "связка есть")
			if T.bundle != null:
				print("CT bundle n=", T.bundle.count(), " speed=", T.speed_factor(), " held=", T.held, " rope=", main.inv.get("rope", 0))
				_ok(T.bundle.count() == 6, "в связке 6: %d" % T.bundle.count())
			_ok(T.held == "" and T.logs == 0, "руки пусты после связки")
			_td["drag_t"] = 0.0
			_td["drag_c"] = hero.position - Vector3(0, 0, 4.0)
		"drag_check":
			var bd2: Node3D = T.bundle
			print("CT drag max rope=", _td.get("drag_max", 0.0))
			_ok(float(_td.get("drag_max", 9.0)) < bd2.ROPE + 0.25, "повод тянется: %.2f" % float(_td.get("drag_max", 9.0)))
			var rd2 := Vector2(bd2.rear.x - bd2.front.x, bd2.rear.z - bd2.front.z).length()
			_ok(absf(rd2 - bd2.L) < 0.05, "зад связки на длине: %.2f" % rd2)
			var gy: float = main.ground_at(bd2.rear.x, bd2.rear.z)
			_ok(absf(bd2.rear.y - gy - 0.13) < 0.05, "зад по земле: %.2f" % (bd2.rear.y - gy))
			_td.erase("drag_t")
			var bax: Vector3 = bd2.front - bd2.rear
			_td["look"] = [(hero.position + bd2.rear) * 0.5, atan2(bax.x, bax.z) + PI * 0.5, 7.5, 38.0]
			_shot("drag_bundle")
		"site":
			_td.erase("look")
			if main.get("camp") != null and main.camp != null:
				var yaw2: float = hero.body.rotation.y
				var sp: Vector3 = hero.position + Vector3(sin(yaw2), 0, cos(yaw2)) * 4.0
				sp.y = main.ground_at(sp.x, sp.z)
				var s: Dictionary = main.camp.place("cabin", sp, 0.0)
				hero.position = sp - Vector3(sin(yaw2), 0, cos(yaw2)) * 3.0
				hero.position.y = main.ground_at(hero.position.x, hero.position.z)
				T.bundle.step(0.016, T.rope_anchor())
				var lb: String = T.action_label()
				_ok(lb == "Сложить связку на стройку", "метка стройки: " + lb)
				if lb == "Сложить связку на стройку":
					T.do_action()
					_steps(T, 70)
					_ok(int((s["have"] as Dictionary).get("log", 0)) == 6, "на стройке 6: %d" % int((s["have"] as Dictionary).get("log", 0)))
					_ok(T.bundle == null, "связка ушла на стройку")
		"untie":
			# новая связка из двух брёвен: развязать — брёвна на землю, верёвка в короб
			hero.position = _td["home"]
			var yaw3: float = hero.body.rotation.y
			for i in 2:
				w.drop_log(hero.position + Vector3(sin(yaw3), 0, cos(yaw3)) * 0.9 + Vector3(0.3 * i, 0, 0), yaw3 + PI * 0.5)
			var n0: int = w.logs_near(hero.position, 6.0).size()
			var rope0 := int(main.inv.get("rope", 0))
			T.do_action()
			_steps(T, 90)
			_ok(T.bundle != null and T.bundle.count() == 2, "связка из двух")
			_ok(T.action_label() == "Развязать связку", "метка развязать: " + T.action_label())
			T.do_action()
			_steps(T, 80)
			_ok(T.bundle == null, "развязана")
			_ok(w.logs_near(hero.position, 6.0).size() == n0, "брёвна на земле: %d из %d" % [w.logs_near(hero.position, 6.0).size(), n0])
			_ok(int(main.inv.get("rope", 0)) == rope0, "верёвка вернулась")
			for it: Dictionary in w.logs_near(hero.position, 6.0):
				w.take_item(it)
		"spear_stick":
			main.inv["spear"] = 1
			T.draw("spear")
			_ok(T.held == "spear", "копьё в руках")
			T.stick()
		"stick_check":
			var sp2: Dictionary = {}
			for it: Dictionary in w.items:
				if it["id"] == "spear":
					sp2 = it
			_ok(not sp2.is_empty(), "копьё воткнуто")
			if not sp2.is_empty():
				var nd: Node3D = sp2["node"]
				var ax: Vector3 = nd.global_transform.basis.y.normalized()
				var tipw: Vector3 = nd.global_transform * Vector3(0, 1.1, 0)
				var gyt: float = main.ground_at(tipw.x, tipw.z)
				print("CT spear axis=", ax, " tip below ground=", gyt - tipw.y)
				_ok(ax.y < -0.9 and ax.y > -0.995, "копьё острием вниз с наклоном: %.3f" % ax.y)
				_ok(gyt - tipw.y > 0.1, "острие в земле")
				_td["look"] = [nd.global_position + Vector3(0, -0.4, 0), hero.body.rotation.y + 0.6, 3.6, 38.0]
				_shot("spear_stuck")
		"place_knife", "place_axe", "place_spear":
			# зверь ставится заранее: сетка зверей (animals.near) обновляется в их шаге
			_td.erase("look")
			var tool0 := a.substr(6)
			if tool0 == "spear":
				var it3: Dictionary = w.nearest_item(hero.position, 3.0)
				if not it3.is_empty() and it3["id"] == "spear":
					w.take_item(it3)
				main.inv["spear"] = 1
			T.act = ""
			T.draw(tool0)
			_steps(T, 35)
			_foe_in_front(1.1 if tool0 != "spear" else 1.9)
		"melee_knife", "melee_axe", "melee_spear":
			var tool := a.substr(6)
			var an: Node3D = _td.get("an")
			if an == null:
				_ok(false, "нет зверя")
				return
			var hp0: float = float(main.hunt.hp.get(an, 1.0))
			_ok(T.use_label() == "Ударить", "метка удара %s: %s" % [tool, T.use_label()])
			T.use()
			_ok(T.act == "attack", "удар начался")
			var t0 := Time.get_ticks_msec()
			for i in 80:
				T.process(1.0 / 60.0)
				main.hero._animate_model(1.0 / 60.0)
				if T.act == "":
					break
			var hp1: float = float(main.hunt.hp.get(an, 1.0))
			print("CT melee ", tool, " hp ", hp0, " -> ", hp1, " dead=", an.dead, " ms=", Time.get_ticks_msec() - t0)
			_ok(hp1 < hp0 or an.dead, "удар %s засчитан" % tool)
			if an.dead:
				an.call("_revive")
			main.hunt.hp.erase(an)
			_td.erase("an_p")
		"place_far":
			T.act = ""
			main.inv["spear"] = 1
			if T.held != "spear":
				T.draw("spear")
			_clear_yaw(11.0)
			_foe_in_front(11.0)
		"aim_spear":
			var an2: Node3D = _td.get("an")
			_ok(begin_aim("spear"), "прицел копья")
			print("CT aim pow=", aim_pow, " dir=", aim_dir, " vel=", aim_vel())
			for kk in [0.0, 0.5, 1.0]:
				var pp := _simulate(kk, false)
				var e: Vector3 = pp[pp.size() - 1]
				print("CT sim k=", kk, " n=", pp.size(), " end=", e - hero.position, " gy=", main.ground_at(e.x, e.z), " blocked=", main.blocked(e.x, e.z, 0.0))
			print("CT an rel=", an2.position - hero.position if an2 != null else Vector3.ZERO, " launch=", T.launch_point("spear") - hero.position)
			_td["look"] = [hero.position + aim_dir * 4.5, atan2(aim_dir.x, aim_dir.z) + PI + 0.9, 12.0, 45.0]
			_td["an2"] = an2
		"aim_shot":
			if aim_kind == "":
				print("CT aim lost: act=", T.act, " data=", T.act_data, " state=", hero.state)
				T.act = ""
				begin_aim("spear")
			_draw_arc()
			_ok(arc.visible and aim_hit, "дуга видна и ведёт в зверя: %s" % str(aim_hit))
			_shot("aim_arc")
		"aim_release":
			_td.erase("look")
			pad.cur = pad.start + Vector2(0, -aim_pow * DRAG_FULL)
			release_aim()
			_ok(T.act == "throw" and not T.act_data.get("aiming", true), "бросок пошёл")
		"bow":
			var an3: Node3D = _td.get("an2")
			if an3 != null:
				print("CT after spear: dead=", an3.dead, " hp=", main.hunt.hp.get(an3, 1.0))
				_ok(an3.dead or float(main.hunt.hp.get(an3, 1.0)) < 1.0, "копьё по прицелу попало")
				if an3.dead:
					an3.call("_revive")
				main.hunt.hp.erase(an3)
			T.act = ""
			T.draw("bow")
			_ok(T.held == "bow", "лук в руке")
		"place_bow":
			_clear_yaw(24.0)
			_foe_in_front(24.0)
		"bow_aim":
			var d5: Vector3 = (_td["an"] as Node3D).position - hero.position
			hero.body.rotation.y = atan2(d5.x, d5.z)
			_ok(begin_aim("bow"), "прицел лука")
			var an5: Node3D = _td["an"]
			aim_dir = Vector3(d5.x, 0, d5.z).normalized()
			aim_pow = _pow_for(an5.position + Vector3(0, float(an5.parts.get("H", 0.7)) * 0.62, 0))
			_update_pitch()
			print("CT bow aim pow=", aim_pow)
			var pb := _simulate(aim_pow, true)
			print("CT bow sim end=", (pb[pb.size() - 1] as Vector3) - hero.position, " hit=", aim_hit, " an=", (_td["an"] as Node3D).position - hero.position)
			_td["look"] = [hero.position + Vector3(0, 1.0, 0), hero.body.rotation.y + 1.9, 3.6, 8.0]
		"bow_shot":
			print("CT bow draw=", T.drawk)
			_ok(T.drawk > 0.3, "тетива натянута: %.2f" % T.drawk)
			_shot("bow_draw_game")
		"bow_release":
			_td.erase("look")
			var ar0 := int(main.inv.get("arrow", 0))
			release_aim()
			_steps(T, 3)
			_ok(int(main.inv.get("arrow", 0)) == ar0 - 1, "стрела ушла")
			_td["ar_fly"] = w.flying.size()
		"bow_check":
			var n_ar := 0
			for it: Dictionary in w.items:
				if it["id"] == "arrow":
					n_ar += 1
			var an4: Node3D = _td.get("an")
			for it: Dictionary in w.items:
				if it["id"] == "arrow":
					print("CT arrow at ", (it["pos"] as Vector3) - hero.position)
			print("CT arrows items=", n_ar, " carried=", _carried.size(), " flying=", w.flying.size(), " an dead=", an4.dead if an4 != null else false, " hp=", main.hunt.hp.get(an4, 1.0) if an4 != null else 1.0)
			_ok(n_ar + _carried.size() >= 1, "стрела застряла")
			_ok(an4 != null and (an4.dead or _carried.size() > 0), "стрела попала")
		"crouch":
			_td.erase("an_p")
			T.holster()
			_steps(T, 40)
			hero.toggle_crouch()
			_ok(hero.crouch, "присел")
			hero._animate_model(0.016)
			_ok(String(hero.m_cur).contains("Crouch"), "анимация приседа: " + String(hero.m_cur))
			hero.toggle_crouch()
			_ok(not hero.crouch, "встал")
		"report":
			print("CT result fails=", _fails.size(), " ", "OK" if _fails.is_empty() else str(_fails))
			get_tree().quit()
