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
var torch := OmniLight3D.new()

func _mat(c: Color, rough: float = 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m

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
	var kaftan := Color(0.17, 0.26, 0.31)
	var kaftan2 := Color(0.13, 0.21, 0.26)
	var pants := Color(0.24, 0.2, 0.16)
	var skin := Color(0.76, 0.58, 0.45)
	var fur := Color(0.62, 0.56, 0.47)
	var leather := Color(0.34, 0.22, 0.12)
	var boot_c := Color(0.16, 0.10, 0.07)
	var sash := Color(0.62, 0.15, 0.12)
	# ноги: штаны, высокие сапоги, голеностоп
	for side in [-1.0, 1.0]:
		var leg: Node3D = leg_l if side < 0.0 else leg_r
		var knee: Node3D = knee_l if side < 0.0 else knee_r
		var ank: Node3D = ank_l if side < 0.0 else ank_r
		leg.position = Vector3(side * 0.1, 0.97, 0)
		body.add_child(leg)
		_part(leg, _capsule(0.092, 0.54), pants, Vector3(0, -0.23, 0))
		knee.position = Vector3(0, -0.46, 0)
		leg.add_child(knee)
		_part(knee, _capsule(0.072, 0.4), pants, Vector3(0, -0.16, 0))
		_part(knee, _capsule(0.082, 0.42), boot_c, Vector3(0, -0.3, 0.005))
		_part(knee, _cyl(0.1, 0.085, 0.04), fur, Vector3(0, -0.1, 0))
		ank.position = Vector3(0, -0.5, 0)
		knee.add_child(ank)
		_ell(ank, _sph(), boot_c, Vector3(0, -0.02, 0.07), Vector3(0.17, 0.12, 0.34))
	# кафтан: подол с меховой оторочкой, красный кушак, пуговицы
	_ell(torso, _cyl(0.2, 0.33, 0.5), kaftan, Vector3(0, -0.02, 0), Vector3(1.0, 1.0, 0.95))
	_ell(torso, _tor(0.3, 0.35), fur, Vector3(0, -0.27, 0), Vector3(1.0, 1.0, 0.95))
	_ell(torso, _capsule(0.5, 1.0), kaftan, Vector3(0, 0.36, 0), Vector3(0.46, 0.8, 0.34))
	_part(torso, BoxMesh.new(), kaftan2, Vector3(0, 0.2, 0.15)).scale = Vector3(0.035, 0.9, 0.02)
	for i in 5:
		_ell(torso, _sph(), Color(0.7, 0.58, 0.28), Vector3(0, 0.0 + i * 0.12, 0.162), Vector3(0.03, 0.03, 0.03))
	_ell(torso, _cyl(0.215, 0.22, 0.1), sash, Vector3(0, 0.08, 0), Vector3(1.0, 1.0, 0.84))
	_part(torso, BoxMesh.new(), sash, Vector3(0.1, -0.12, 0.17), Vector3(0, 0, 0.1)).scale = Vector3(0.06, 0.3, 0.02)
	_ell(torso, _tor(0.1, 0.17), fur, Vector3(0, 0.71, 0.01), Vector3(1.0, 1.2, 1.0))
	# голова: лицо, борода, нос, глаза; меховая шапка с суконным верхом
	var neck := _cyl(0.055, 0.065, 0.12)
	_part(torso, neck, skin, Vector3(0, 0.76, 0))
	torso.add_child(head_n)
	head_n.position = Vector3(0, 0.9, 0.01)
	_ell(head_n, _sph(), skin, Vector3.ZERO, Vector3(0.27, 0.32, 0.3))
	_ell(head_n, _sph(), Color(0.28, 0.2, 0.14), Vector3(0, -0.1, 0.05), Vector3(0.24, 0.2, 0.22))
	_ell(head_n, _sph(), skin, Vector3(0, -0.01, 0.15), Vector3(0.045, 0.05, 0.05))
	for sd in [-1.0, 1.0]:
		_ell(head_n, _sph(), Color(0.08, 0.06, 0.05), Vector3(sd * 0.055, 0.04, 0.135), Vector3(0.025, 0.025, 0.02))
	_ell(head_n, _cyl(0.15, 0.19, 0.12), fur, Vector3(0, 0.11, 0), Vector3(1.0, 1.0, 1.0))
	_ell(head_n, _sph(), sash, Vector3(0, 0.19, 0), Vector3(0.3, 0.14, 0.3))
	# рюкзак с подсумками, скатка, пищаль за спиной
	_ell(torso, _capsule(0.5, 1.0), leather, Vector3(0, 0.34, -0.25), Vector3(0.36, 0.52, 0.2))
	_ell(torso, _sph(), Color(0.28, 0.2, 0.12), Vector3(0.14, 0.12, -0.31), Vector3(0.14, 0.16, 0.1))
	_part(torso, _cyl(0.085, 0.085, 0.5), Color(0.38, 0.4, 0.3), Vector3(0, 0.66, -0.28), Vector3(0, 0, PI * 0.5))
	# руки: плечо, локоть, предплечье, кисть, меховая манжета
	for side in [-1.0, 1.0]:
		var arm: Node3D = arm_l if side < 0.0 else arm_r
		var elb: Node3D = elb_l if side < 0.0 else elb_r
		arm.position = Vector3(side * 0.28, 0.63, 0)
		torso.add_child(arm)
		_ell(arm, _sph(), kaftan, Vector3.ZERO, Vector3(0.17, 0.17, 0.17))
		_part(arm, _capsule(0.066, 0.38), kaftan, Vector3(0, -0.16, 0))
		elb.position = Vector3(0, -0.32, 0)
		arm.add_child(elb)
		_part(elb, _capsule(0.056, 0.36), kaftan, Vector3(0, -0.15, 0))
		_part(elb, _cyl(0.07, 0.065, 0.05), fur, Vector3(0, -0.29, 0))
		_ell(elb, _sph(), skin, Vector3(0, -0.35, 0), Vector3(0.1, 0.13, 0.1))
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
	if y < main.WATER_Y - 0.9 and main.weather.ice < 0.85:
		return false
	if y - position.y > 1.1:
		return false
	var n: Vector3 = main.normal_at(p.x, p.z)
	if n.y < 0.42:
		return false
	return not main.blocked(p.x, p.z, 0.32)

func _process(delta: float) -> void:
	if main == null:
		return
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
		target = d * sp_base * mag * f * (1.0 - main.weather.snow * 0.3)
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
			vel = Vector3.ZERO
	position.x = p.x
	position.z = p.z
	var sp := vel.length()
	moving = sp > 0.25
	if moving and (mag > 0.12 or sliding > 0.2):
		var face: Vector3 = d if mag > 0.12 and sliding < 0.4 else vel.normalized()
		body.rotation.y = lerp_angle(body.rotation.y, atan2(face.x, face.z), minf(1.0, 9.0 * delta))
	var ground: float = main.height(position.x, position.z)
	var ty := maxf(ground, main.WATER_Y if main.weather.ice >= 0.85 else main.WATER_Y - 0.35)
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
	arm_l.rotation.x = -sw * amp * 0.75
	arm_r.rotation.x = sw * amp * 0.75
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
	torso.rotation.y = -sw * 0.09 * run_mag
	torso.rotation.z = sw * 0.03 * run_mag
	head_n.rotation.y = sw * 0.05 * run_mag
	body.position.y = (absf(cw) - 0.6) * 0.05 * run_mag + minf(slope, 1.0) * 0.08 - cl * 0.15
