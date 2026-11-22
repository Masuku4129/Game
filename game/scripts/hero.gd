extends Node3D
## Путник: тело собрано из частей, ходит по джойстику; не идёт в глубокую воду, по отвесным обрывам и сквозь стволы.

var main: Node3D
var move_vec := Vector2.ZERO
var cam_yaw := 0.0
var speed := 3.1
var run_speed := 4.8
var running := false
var climbing := 0.0
var moving := false
var run_mag := 0.0
var phase := 0.0
var body := Node3D.new()
var torso := Node3D.new()
var leg_l := Node3D.new()
var leg_r := Node3D.new()
var knee_l := Node3D.new()
var knee_r := Node3D.new()
var ank_l := Node3D.new()
var ank_r := Node3D.new()
var head_n := Node3D.new()
var arm_l := Node3D.new()
var arm_r := Node3D.new()
var elb_l := Node3D.new()
var elb_r := Node3D.new()
var vel := Vector3.ZERO
var sliding := 0.0
var lean := 0.0
var tilt := 0.0
var last_sw := 0.0
# состояния: walk, sit, climb; плавание и брод внутри walk
var state := "walk"
var seat: Array = []
var stand_pos := Vector3.ZERO
var sitb := 0.0
var swimb := 0.0
var climbb := 0.0
var cphase := 0.0
var soaked := 0.0
var depth := 0.0
var skirt_l := Node3D.new()
var skirt_r := Node3D.new()
var last_yaw := 0.0
var turn := 0.0
var arm_lx := 0.0
var arm_rx := 0.0
var cloth_tex: Texture2D
var torch := OmniLight3D.new()

func _mat(c: Color, rough: float = 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m

## Материал ткани: цвет + шумовая фактура (переплетение, потёртости).
func _cloth(c: Color, sc: float = 7.0) -> StandardMaterial3D:
	if cloth_tex == null:
		var nz := FastNoiseLite.new()
		nz.frequency = 0.09
		nz.fractal_octaves = 4
		var g := Gradient.new()
		g.set_color(0, Color(0.72, 0.72, 0.72))
		g.set_color(1, Color(1.0, 1.0, 1.0))
		var nt := NoiseTexture2D.new()
		nt.width = 128
		nt.height = 128
		nt.seamless = true
		nt.noise = nz
		nt.color_ramp = g
		nt.generate_mipmaps = true
		cloth_tex = nt
	var m := _mat(c, 0.95)
	m.albedo_texture = cloth_tex
	m.uv1_scale = Vector3(sc, sc, sc)
	return m

## Лофт: гладкое тело вращения по сечениям-эллипсам [y, rx, rz, смещение z]. Ось вдоль Y.
func _loft(rings: Array, seg: int = 20, cap_top: bool = true, cap_bot: bool = true) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := rings.size()
	for i in n:
		var r: Array = rings[i]
		for j in seg + 1:
			var a := TAU * j / seg
			st.set_uv(Vector2(float(j) / seg, float(i) / (n - 1)))
			st.add_vertex(Vector3(cos(a) * r[1], r[0], sin(a) * r[2] + r[3]))
	for i in n - 1:
		for j in seg:
			var k := i * (seg + 1) + j
			st.add_index(k)
			st.add_index(k + 1)
			st.add_index(k + seg + 1)
			st.add_index(k + 1)
			st.add_index(k + seg + 2)
			st.add_index(k + seg + 1)
	var base := n * (seg + 1)
	if cap_bot:
		var r0: Array = rings[0]
		st.set_uv(Vector2(0.5, 0.0))
		st.add_vertex(Vector3(0, r0[0], r0[3]))
		for j in seg:
			st.add_index(base)
			st.add_index(j + 1)
			st.add_index(j)
		base += 1
	if cap_top:
		var r1: Array = rings[n - 1]
		st.set_uv(Vector2(0.5, 1.0))
		st.add_vertex(Vector3(0, r1[0], r1[3]))
		var o := (n - 1) * (seg + 1)
		for j in seg:
			st.add_index(base)
			st.add_index(o + j)
			st.add_index(o + j + 1)
	st.generate_normals()
	return st.commit()

func _lpart(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO, sc: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	mi.scale = sc
	parent.add_child(mi)
	return mi

func _part(parent: Node3D, mesh: Mesh, c: Color, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(c)
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi

func _ell(parent: Node3D, mesh: Mesh, c: Color, pos: Vector3, sc: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := _part(parent, mesh, c, pos, rot)
	mi.scale = sc
	return mi

func _capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 16
	m.rings = 6
	return m

func _sph() -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = 16
	m.rings = 8
	return m

func _cyl(rt: float, rb: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = rt
	m.bottom_radius = rb
	m.height = h
	m.radial_segments = 18
	return m

func _tor(i: float, o: float) -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius = i
	m.outer_radius = o
	m.ring_segments = 8
	return m

func _ready() -> void:
	add_child(body)
	body.add_child(torso)
	torso.position = Vector3(0, 0.97, 0)
	var kaftan := _cloth(Color(0.2, 0.29, 0.34), 6.0)
	var trim := _cloth(Color(0.14, 0.2, 0.24), 6.0)
	var pants := _cloth(Color(0.27, 0.23, 0.18), 8.0)
	var fur := _cloth(Color(0.55, 0.47, 0.37), 14.0)
	var sash := _cloth(Color(0.6, 0.15, 0.12), 9.0)
	var leather := _cloth(Color(0.33, 0.21, 0.12), 5.0)
	var boot := _cloth(Color(0.17, 0.11, 0.08), 5.0)
	boot.roughness = 0.6
	var skin := _mat(Color(0.66, 0.48, 0.37), 0.75)
	var hair := _cloth(Color(0.2, 0.14, 0.1), 16.0)
	var roll := _cloth(Color(0.36, 0.37, 0.28), 10.0)
	# --- ноги: штанина, голенище сапога, стопа; полы кафтана висят на бедре
	for side in [-1.0, 1.0]:
		var leg: Node3D = leg_l if side < 0.0 else leg_r
		var knee: Node3D = knee_l if side < 0.0 else knee_r
		var ank: Node3D = ank_l if side < 0.0 else ank_r
		var sk: Node3D = skirt_l if side < 0.0 else skirt_r
		leg.position = Vector3(side * 0.1, 0.97, 0)
		body.add_child(leg)
		_lpart(leg, _loft([[-0.5, 0.068, 0.072, 0.0], [-0.3, 0.08, 0.085, 0.005], [-0.1, 0.095, 0.1, 0.0], [0.04, 0.1, 0.1, 0.0]]), pants)
		knee.position = Vector3(0, -0.46, 0)
		leg.add_child(knee)
		_lpart(knee, _loft([[-0.47, 0.06, 0.065, 0.0], [-0.3, 0.068, 0.075, -0.01], [-0.15, 0.078, 0.085, -0.015], [0.02, 0.085, 0.09, 0.0], [0.04, 0.09, 0.095, 0.0]]), boot)
		ank.position = Vector3(0, -0.48, 0)
		knee.add_child(ank)
		_lpart(ank, _sph(), boot, Vector3(0, -0.015, 0.06), Vector3.ZERO, Vector3(0.11, 0.085, 0.27))
		_lpart(ank, BoxMesh.new(), _mat(Color(0.1, 0.07, 0.05), 0.8), Vector3(0, -0.05, 0.06), Vector3.ZERO, Vector3(0.1, 0.02, 0.26))
		# полы: половина подола на каждой ноге, качается с ней наполовину
		sk.position = Vector3(side * 0.1, 0.97, 0)
		body.add_child(sk)
		_lpart(sk, _loft([[-0.56, 0.19, 0.2, 0.0], [-0.35, 0.165, 0.18, 0.0], [-0.12, 0.14, 0.155, 0.0], [0.04, 0.13, 0.15, 0.0]], 18, false, false), kaftan, Vector3(side * 0.035, 0, 0))
		_lpart(sk, _tor(0.17, 0.215), fur, Vector3(side * 0.035, -0.55, 0), Vector3.ZERO, Vector3(1.0, 1.0, 1.05))
	# --- торс: таз, талия, грудь, плечи (кафтан), кушак
	_lpart(torso, _loft([[-0.12, 0.215, 0.17, 0.0], [0.0, 0.2, 0.15, 0.0], [0.1, 0.175, 0.13, 0.0], [0.25, 0.19, 0.14, 0.015], [0.4, 0.205, 0.145, 0.02], [0.53, 0.21, 0.13, 0.0], [0.6, 0.18, 0.11, -0.01], [0.66, 0.09, 0.08, 0.0]], 22), kaftan)
	_lpart(torso, BoxMesh.new(), trim, Vector3(0.03, 0.3, 0.155), Vector3(0, 0, 0.02), Vector3(0.05, 0.6, 0.015))
	for i in 5:
		_ell(torso, _sph(), Color(0.62, 0.5, 0.25), Vector3(0.03, 0.16 + i * 0.09, 0.168), Vector3(0.025, 0.025, 0.02))
	_lpart(torso, _loft([[0.03, 0.19, 0.145, 0.0], [0.08, 0.185, 0.14, 0.0], [0.13, 0.18, 0.135, 0.0]], 20, false, false), sash)
	_lpart(torso, BoxMesh.new(), sash, Vector3(0.12, -0.04, 0.13), Vector3(0.1, 0.3, 0.12), Vector3(0.06, 0.22, 0.015))
	_lpart(torso, _tor(0.075, 0.13), fur, Vector3(0, 0.67, 0.0), Vector3(0.15, 0, 0), Vector3(1.05, 1.5, 1.0))
	# --- голова: шея, череп, нос, уши, брови, глаза, волосы, борода, усы; шапка
	_lpart(torso, _cyl(0.05, 0.06, 0.1), skin, Vector3(0, 0.73, 0.0))
	torso.add_child(head_n)
	head_n.position = Vector3(0, 0.87, 0.01)
	_lpart(head_n, _sph(), skin, Vector3.ZERO, Vector3.ZERO, Vector3(0.2, 0.25, 0.23))
	_lpart(head_n, _sph(), skin, Vector3(0, -0.005, 0.118), Vector3(0.35, 0, 0), Vector3(0.035, 0.06, 0.04))
	for sd in [-1.0, 1.0]:
		_lpart(head_n, _sph(), skin, Vector3(sd * 0.1, 0.0, 0.0), Vector3.ZERO, Vector3(0.03, 0.06, 0.045))
		_lpart(head_n, _sph(), _mat(Color(0.95, 0.93, 0.9), 0.4), Vector3(sd * 0.04, 0.03, 0.098), Vector3.ZERO, Vector3(0.028, 0.018, 0.015))
		_lpart(head_n, _sph(), _mat(Color(0.12, 0.08, 0.05), 0.3), Vector3(sd * 0.04, 0.03, 0.105), Vector3.ZERO, Vector3(0.012, 0.014, 0.008))
		_lpart(head_n, BoxMesh.new(), hair, Vector3(sd * 0.042, 0.058, 0.1), Vector3(0, 0, -sd * 0.15), Vector3(0.045, 0.01, 0.012))
	_lpart(head_n, _sph(), hair, Vector3(0, 0.03, -0.03), Vector3.ZERO, Vector3(0.21, 0.2, 0.22))
	_lpart(head_n, _sph(), hair, Vector3(0, -0.075, 0.055), Vector3(0.25, 0, 0), Vector3(0.17, 0.15, 0.13))
	_lpart(head_n, _sph(), hair, Vector3(0, -0.035, 0.112), Vector3.ZERO, Vector3(0.07, 0.018, 0.02))
	_lpart(head_n, _loft([[0.0, 0.115, 0.125, -0.005], [0.07, 0.12, 0.13, -0.005], [0.1, 0.115, 0.125, -0.005]], 20), fur, Vector3(0, 0.075, 0))
	_lpart(head_n, _loft([[0.0, 0.1, 0.11, 0.0], [0.06, 0.095, 0.1, -0.01], [0.11, 0.06, 0.065, -0.03], [0.13, 0.01, 0.01, -0.04]], 18), sash, Vector3(0, 0.16, 0))
	# --- спина: заплечный мешок с ремнями и скатка
	_lpart(torso, _loft([[0.0, 0.15, 0.08, 0.0], [0.15, 0.17, 0.1, 0.0], [0.38, 0.16, 0.095, 0.0], [0.45, 0.1, 0.06, 0.0]], 16), leather, Vector3(0, 0.12, -0.23))
	for sd in [-1.0, 1.0]:
		_lpart(torso, BoxMesh.new(), leather, Vector3(sd * 0.11, 0.45, 0.02), Vector3(0.0, 0, 0), Vector3(0.04, 0.42, 0.3))
	_lpart(torso, _cyl(0.075, 0.075, 0.46), roll, Vector3(0, 0.6, -0.24), Vector3(0, 0, PI * 0.5))
	# --- руки: плечо, рукав, локоть, обшлаг, рукавица
	for side in [-1.0, 1.0]:
		var arm: Node3D = arm_l if side < 0.0 else arm_r
		var elb: Node3D = elb_l if side < 0.0 else elb_r
		arm.position = Vector3(side * 0.24, 0.6, 0)
		torso.add_child(arm)
		_lpart(arm, _sph(), kaftan, Vector3(side * 0.01, -0.01, 0), Vector3.ZERO, Vector3(0.15, 0.14, 0.14))
		_lpart(arm, _loft([[-0.32, 0.05, 0.055, 0.0], [-0.15, 0.06, 0.065, 0.0], [0.0, 0.07, 0.07, 0.0]]), kaftan)
		elb.position = Vector3(0, -0.3, 0)
		arm.add_child(elb)
		_lpart(elb, _loft([[-0.27, 0.06, 0.06, 0.0], [-0.12, 0.055, 0.058, 0.0], [0.02, 0.055, 0.058, 0.0]]), kaftan)
		_lpart(elb, _tor(0.05, 0.075), fur, Vector3(0, -0.26, 0))
		_lpart(elb, _sph(), leather, Vector3(0, -0.33, 0.01), Vector3.ZERO, Vector3(0.085, 0.12, 0.06))
		_lpart(elb, _sph(), leather, Vector3(side * -0.035, -0.31, 0.03), Vector3(0, 0, side * 0.6), Vector3(0.03, 0.06, 0.03))
	# факел-свет (ночью)
	torch.light_color = Color(1.0, 0.7, 0.4)
	torch.light_energy = 0.0
	torch.omni_range = 11.0
	torch.position = Vector3(0, 1.7, 0.5)
	add_child(torch)

func _can_walk(p: Vector3) -> bool:
	var half: float = main.SIZE * 0.5 - 8.0
	if absf(p.x) > half or absf(p.z) > half:
		return false
	var y: float = main.height(p.x, p.z)
	if y - position.y > 1.1:
		return false
	var n: Vector3 = main.normal_at(p.x, p.z)
	if n.y < 0.42:
		return false
	return not main.blocked(p.x, p.z, 0.32)

## Подпись кнопки действия по обстановке ("" — кнопку скрыть).
func action_label() -> String:
	if state == "sit":
		return "Встать"
	if state == "walk" and swimb < 0.3 and not main.find_seat(position).is_empty():
		return "Сесть"
	return ""

func do_action() -> void:
	if state == "sit":
		_stand_up()
		return
	var st: Array = main.find_seat(position)
	if st.is_empty():
		return
	seat = st
	stand_pos = position
	state = "sit"
	vel = Vector3.ZERO

func _stand_up() -> void:
	state = "walk"
	position = stand_pos

func _process(delta: float) -> void:
	if main == null:
		return
	soaked = maxf(0.0, soaked - delta * 0.004 * (1.0 + maxf(float(main.weather.temp), 0.0) * 0.1))
	if state == "sit":
		_process_sit(delta)
		return
	if state == "climb":
		_process_climb(delta)
		return
	sitb = maxf(0.0, sitb - delta * 4.0)
	climbb = maxf(0.0, climbb - delta * 4.0)
	leg_l.rotation.z = 0.0
	leg_r.rotation.z = 0.0
	var mag := minf(move_vec.length(), 1.0)
	var n: Vector3 = main.normal_at(position.x, position.z)
	var down := Vector3(n.x, 0, n.z)
	var slope := down.length() / maxf(n.y, 0.01)
	if down.length() > 0.001:
		down = down.normalized()
	var d := Vector3.ZERO
	var target := Vector3.ZERO
	if mag > 0.12:
		d = Vector3(move_vec.x, 0, move_vec.y).normalized().rotated(Vector3.UP, cam_yaw)
		var along := d.dot(down)
		var f := 1.0
		if along < 0.0:
			f = clampf(1.0 + along * slope * 0.7, 0.5, 1.0)
		else:
			f = minf(1.0 + along * slope * 0.2, 1.15)
		var stam: float = main.stamina
		running = mag > 0.92 and stam > 0.08
		var sp_base := run_speed if running else speed
		var wf := 1.0
		if depth > 1.25:
			wf = 0.45
			running = false
		elif depth > 0.3:
			wf = 1.0 - (depth - 0.3) * 0.55
		target = d * sp_base * mag * f * wf * (1.0 - main.weather.snow * 0.3)
	else:
		running = false
	# крутой склон: человека тянет вниз, он теряет управление и катится
	var s := 0.0
	sliding = lerpf(sliding, s, minf(1.0, 4.0 * delta))
	var accel := 11.0 * (1.0 - sliding * 0.75)
	vel = vel.move_toward(target, accel * delta)
	vel.y = 0.0
	var step := vel * delta
	var p := position
	if step.length() > 0.00001:
		if _can_walk(p + step):
			p += step
		elif _can_walk(p + Vector3(step.x, 0, 0)):
			p.x += step.x
			vel.z = 0.0
		elif _can_walk(p + Vector3(0, 0, step.z)):
			p.z += step.z
			vel.x = 0.0
		else:
			# упёрлись в крутую стену: если это скала, а не дерево — начинаем лезть
			var q := position + d * 0.5
			var nq: Vector3 = main.normal_at(q.x, q.z)
			if mag > 0.5 and nq.y < 0.42 and depth < 0.5 and not main.blocked(q.x, q.z, 0.2) and float(main.stamina) > 0.1:
				state = "climb"
			vel = Vector3.ZERO
	position.x = p.x
	position.z = p.z
	# стоим на круче без опоры (сорвались) — съезжаем вниз
	if n.y < 0.4 and depth < 0.5:
		position += down * 5.0 * delta
	var sp := vel.length()
	moving = sp > 0.25
	if moving and (mag > 0.12 or sliding > 0.2):
		var face: Vector3 = d if mag > 0.12 and sliding < 0.4 else vel.normalized()
		body.rotation.y = lerp_angle(body.rotation.y, atan2(face.x, face.z), minf(1.0, 9.0 * delta))
	var ground: float = main.height(position.x, position.z)
	var iced: bool = main.weather.ice >= 0.85
	depth = 0.0 if iced else maxf(0.0, main.WATER_Y - ground)
	var ty := ground
	if iced:
		ty = maxf(ground, main.WATER_Y)
	elif depth > 1.25:
		ty = main.WATER_Y - 1.0 + sin(Time.get_ticks_msec() * 0.003) * 0.03
		soaked = 1.0
		# течение сносит вдоль реки
		position.x += 0.45 * delta
	elif depth > 0.6:
		soaked = maxf(soaked, 0.5)
	swimb = lerpf(swimb, 1.0 if depth > 1.25 else 0.0, minf(1.0, 4.0 * delta))
	# на подъёме ставим сразу на землю (не тонет), вниз опускаем быстро и плавно
	if ty > position.y:
		position.y = ty
	else:
		position.y = lerpf(position.y, ty, minf(1.0, 20.0 * delta))
	# походка: фаза от пройденного пути, размах от скорости
	var sn := clampf(sp / speed, 0.0, 1.6)
	run_mag = lerpf(run_mag, sn, minf(1.0, 8.0 * delta))
	phase += sp * delta * 2.8
	var fwd := Vector3(sin(body.rotation.y), 0, cos(body.rotation.y))
	var incline := 0.0
	if sp > 0.1:
		incline = clampf(-fwd.dot(down) * slope, -0.8, 0.8)  # >0 вверх
	# крутой подъём: карабкается, помогая руками
	var want_climb := 1.0 if (incline > 0.55 and sp > 0.1) else 0.0
	climbing = lerpf(climbing, want_climb, minf(1.0, 6.0 * delta))
	lean = lerpf(lean, 0.05 * run_mag + maxf(incline, 0.0) * 0.5 - maxf(-incline, 0.0) * 0.15, minf(1.0, 5.0 * delta))
	var amp := 0.5 * minf(run_mag, 1.5)
	var sw := sin(phase)
	if moving and signf(sw) != signf(last_sw) and main.feet != null:
		var side := 1.0 if sw > 0.0 else -1.0
		var rgt := Vector3(cos(body.rotation.y), 0, -sin(body.rotation.y))
		main.feet.stamp(position + rgt * side * 0.11, body.rotation.y)
	last_sw = sw
	var cw := cos(phase)
	var up := 1.0 + maxf(incline, 0.0) * 0.8
	var br := sin(Time.get_ticks_msec() * 0.0017) * 0.012 * (1.0 - run_mag)
	leg_l.rotation.x = sw * amp
	leg_r.rotation.x = -sw * amp
	knee_l.rotation.x = maxf(0.0, -cw) * amp * 1.5 * up + 0.04
	knee_r.rotation.x = maxf(0.0, cw) * amp * 1.5 * up + 0.04
	ank_l.rotation.x = -(leg_l.rotation.x + knee_l.rotation.x) * 0.7 + maxf(0.0, sw) * amp * 0.5
	ank_r.rotation.x = -(leg_r.rotation.x + knee_r.rotation.x) * 0.7 + maxf(0.0, -sw) * amp * 0.5
	# руки с инерцией: догоняют нужный угол, а не прыгают
	arm_lx = lerpf(arm_lx, -sw * amp * 0.8, minf(1.0, 12.0 * get_process_delta_time()))
	arm_rx = lerpf(arm_rx, sw * amp * 0.8, minf(1.0, 12.0 * get_process_delta_time()))
	arm_l.rotation.x = arm_lx
	arm_r.rotation.x = arm_rx
	arm_l.rotation.z = 0.05
	arm_r.rotation.z = -0.05
	elb_l.rotation.x = -0.2 - maxf(0.0, sw) * amp * 0.5
	elb_r.rotation.x = -0.2 - maxf(0.0, -sw) * amp * 0.5
	var cl := climbing
	if cl > 0.01:
		# руки тянутся вперёд-вверх и перехватывают склон, колени высоко
		arm_l.rotation.x = lerpf(arm_l.rotation.x, -1.6 - sw * 0.5, cl)
		arm_r.rotation.x = lerpf(arm_r.rotation.x, -1.6 + sw * 0.5, cl)
		elb_l.rotation.x = lerpf(elb_l.rotation.x, -0.5 - maxf(0.0, sw) * 0.6, cl)
		elb_r.rotation.x = lerpf(elb_r.rotation.x, -0.5 - maxf(0.0, -sw) * 0.6, cl)
		leg_l.rotation.x = lerpf(leg_l.rotation.x, sw * 0.45 - 0.45, cl)
		leg_r.rotation.x = lerpf(leg_r.rotation.x, -sw * 0.45 - 0.45, cl)
		knee_l.rotation.x = lerpf(knee_l.rotation.x, 0.6 + maxf(0.0, -cw) * 0.6, cl)
		knee_r.rotation.x = lerpf(knee_r.rotation.x, 0.6 + maxf(0.0, cw) * 0.6, cl)
	torso.rotation.x = lean + br + cl * 0.45
	# полы кафтана идут за ногой наполовину
	skirt_l.rotation.x = leg_l.rotation.x * 0.5
	skirt_r.rotation.x = leg_r.rotation.x * 0.5
	# крен в повороте, покачивание таза, голова держит горизонт
	var yaw_rate := wrapf(body.rotation.y - last_yaw, -PI, PI) / maxf(delta, 0.001)
	last_yaw = body.rotation.y
	turn = lerpf(turn, clampf(yaw_rate * 0.04 * run_mag, -0.18, 0.18), minf(1.0, 6.0 * delta))
	var idle := 1.0 - minf(run_mag * 2.0, 1.0)
	var t_ms := Time.get_ticks_msec() * 0.001
	torso.position.x = sw * 0.025 * run_mag + sin(t_ms * 0.4) * 0.015 * idle
	head_n.rotation.x = -(torso.rotation.x) * 0.6
	torso.rotation.y = -sw * 0.09 * run_mag
	torso.rotation.z = sw * 0.03 * run_mag - turn
	head_n.rotation.y = sw * 0.05 * run_mag
	body.position.y = (absf(cw) - 0.6) * 0.05 * run_mag + minf(slope, 1.0) * 0.08 - cl * 0.15
	_pose_swim(delta, sp)

## Плавание брассом: тело горизонтально, руки гребут, ноги толкаются.
func _pose_swim(delta: float, sp: float) -> void:
	var b := swimb
	if b < 0.01:
		body.rotation.x = 0.0
		body.position.x = 0.0
		body.position.z = 0.0
		return
	cphase += delta * (2.2 + sp * 1.5)
	var c := sin(cphase)
	var pitch := b * 1.2
	body.rotation.x = pitch
	var off := Vector3(0, 0.97 * (1.0 - cos(pitch)), -0.97 * sin(pitch))
	body.position = Basis(Vector3.UP, body.rotation.y) * off + Vector3(0, body.position.y * (1.0 - b), 0)
	arm_l.rotation.x = lerpf(arm_l.rotation.x, -2.4 + c * 0.7, b)
	arm_r.rotation.x = lerpf(arm_r.rotation.x, -2.4 + c * 0.7, b)
	arm_l.rotation.z = lerpf(arm_l.rotation.z, 0.3 + maxf(0.0, c) * 0.9, b)
	arm_r.rotation.z = lerpf(arm_r.rotation.z, -0.3 - maxf(0.0, c) * 0.9, b)
	elb_l.rotation.x = lerpf(elb_l.rotation.x, -0.3 - maxf(0.0, -c) * 1.0, b)
	elb_r.rotation.x = lerpf(elb_r.rotation.x, -0.3 - maxf(0.0, -c) * 1.0, b)
	leg_l.rotation.x = lerpf(leg_l.rotation.x, 0.15 + c * 0.25, b)
	leg_r.rotation.x = lerpf(leg_r.rotation.x, 0.15 + c * 0.25, b)
	knee_l.rotation.x = lerpf(knee_l.rotation.x, 0.3 + maxf(0.0, -c) * 0.9, b)
	knee_r.rotation.x = lerpf(knee_r.rotation.x, 0.3 + maxf(0.0, -c) * 0.9, b)
	skirt_l.rotation.x = leg_l.rotation.x * 0.5
	skirt_r.rotation.x = leg_r.rotation.x * 0.5
	head_n.rotation.x = -pitch * 0.8

## Сидит на пне или бревне: ноги согнуты, руки на коленях, лёгкое дыхание.
func _process_sit(delta: float) -> void:
	if move_vec.length() > 0.6:
		_stand_up()
		return
	var sp: Vector3 = seat[0]
	var tgt := Vector3(sp.x, sp.y - 0.93, sp.z)
	position = position.lerp(tgt, minf(1.0, 8.0 * delta))
	body.rotation.y = lerp_angle(body.rotation.y, float(seat[1]), minf(1.0, 8.0 * delta))
	sitb = minf(1.0, sitb + delta * 3.0)
	moving = false
	running = false
	run_mag = 0.0
	climbing = 0.0
	var b := sitb
	var br := sin(Time.get_ticks_msec() * 0.0015)
	leg_l.rotation.x = lerpf(leg_l.rotation.x, -1.45, b)
	leg_r.rotation.x = lerpf(leg_r.rotation.x, -1.4, b)
	leg_l.rotation.z = -0.12 * b
	leg_r.rotation.z = 0.12 * b
	knee_l.rotation.x = lerpf(knee_l.rotation.x, 1.45, b)
	knee_r.rotation.x = lerpf(knee_r.rotation.x, 1.35, b)
	ank_l.rotation.x = lerpf(ank_l.rotation.x, 0.0, b)
	ank_r.rotation.x = lerpf(ank_r.rotation.x, 0.0, b)
	skirt_l.rotation.x = leg_l.rotation.x * 0.75
	skirt_r.rotation.x = leg_r.rotation.x * 0.75
	arm_l.rotation.x = lerpf(arm_l.rotation.x, -0.75, b)
	arm_r.rotation.x = lerpf(arm_r.rotation.x, -0.7, b)
	arm_l.rotation.z = 0.12
	arm_r.rotation.z = -0.12
	elb_l.rotation.x = lerpf(elb_l.rotation.x, -0.55, b)
	elb_r.rotation.x = lerpf(elb_r.rotation.x, -0.6, b)
	torso.rotation.x = 0.22 + br * 0.015
	torso.rotation.y = 0.0
	torso.rotation.z = 0.0
	torso.position.x = 0.0
	head_n.rotation.x = -0.15
	head_n.rotation.y = sin(Time.get_ticks_msec() * 0.0004) * 0.35
	body.position = Vector3.ZERO
	body.rotation.x = 0.0

## Лазание по скале: лицом к стене, руки перехватывают выше, ноги ищут упор.
func _process_climb(delta: float) -> void:
	var n: Vector3 = main.normal_at(position.x, position.z)
	var up_dir := -Vector3(n.x, 0, n.z)
	if up_dir.length() < 0.05:
		state = "walk"
		return
	up_dir = up_dir.normalized()
	var right := up_dir.cross(Vector3.UP).normalized()
	var mag := minf(move_vec.length(), 1.0)
	var d := Vector3.ZERO
	if mag > 0.12:
		d = Vector3(move_vec.x, 0, move_vec.y).normalized().rotated(Vector3.UP, cam_yaw)
	var climb_in := d.dot(up_dir) * mag
	var side := d.dot(right) * mag
	var stam: float = main.stamina
	if stam <= 0.01:
		# силы кончились — срыв
		state = "walk"
		position -= up_dir * 0.6
		return
	var slope := Vector3(n.x, 0, n.z).length() / maxf(n.y, 0.05)
	var dy := climb_in * 0.85 * delta
	var p := position + up_dir * (dy / maxf(slope, 0.6)) + right * side * 0.6 * delta
	var nn: Vector3 = main.normal_at(p.x, p.z)
	if nn.y > 0.08 and not main.blocked(p.x, p.z, 0.25):
		position.x = p.x
		position.z = p.z
	position.y = main.height(position.x, position.z)
	cphase += absf(dy) * 7.0 + absf(side) * delta * 5.0
	moving = absf(climb_in) > 0.1 or absf(side) > 0.1
	climbing = 1.0
	running = false
	# выбрались наверх или спустились на пологое
	if nn.y >= 0.6 or main.normal_at(position.x, position.z).y >= 0.6:
		state = "walk"
		position += up_dir * (0.4 if climb_in > 0.0 else -0.2)
		return
	body.rotation.y = lerp_angle(body.rotation.y, atan2(up_dir.x, up_dir.z), minf(1.0, 8.0 * delta))
	climbb = minf(1.0, climbb + delta * 4.0)
	var c := sin(cphase)
	var b := climbb
	arm_l.rotation.x = lerpf(arm_l.rotation.x, -2.5 - c * 0.45, b)
	arm_r.rotation.x = lerpf(arm_r.rotation.x, -2.5 + c * 0.45, b)
	arm_l.rotation.z = 0.15
	arm_r.rotation.z = -0.15
	elb_l.rotation.x = lerpf(elb_l.rotation.x, -0.5 - maxf(0.0, c) * 0.8, b)
	elb_r.rotation.x = lerpf(elb_r.rotation.x, -0.5 - maxf(0.0, -c) * 0.8, b)
	leg_l.rotation.x = lerpf(leg_l.rotation.x, -0.5 + c * 0.45, b)
	leg_r.rotation.x = lerpf(leg_r.rotation.x, -0.5 - c * 0.45, b)
	knee_l.rotation.x = lerpf(knee_l.rotation.x, 0.9 - c * 0.5, b)
	knee_r.rotation.x = lerpf(knee_r.rotation.x, 0.9 + c * 0.5, b)
	skirt_l.rotation.x = leg_l.rotation.x * 0.5
	skirt_r.rotation.x = leg_r.rotation.x * 0.5
	torso.rotation.x = 0.4
	torso.rotation.z = c * 0.05
	head_n.rotation.x = -0.6
	body.position = Vector3(0, -0.1, -0.15)
	body.rotation.x = 0.0
