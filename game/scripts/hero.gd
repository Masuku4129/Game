extends Node3D
## Путник: тело собрано из частей, ходит по джойстику; не идёт в глубокую воду, по отвесным обрывам и сквозь стволы.

var main: Node3D
var move_vec := Vector2.ZERO
var cam_yaw := 0.0
var speed := 3.6
var moving := false
var run_mag := 0.0
var phase := 0.0
var body := Node3D.new()
var torso := Node3D.new()
var leg_l := Node3D.new()
var leg_r := Node3D.new()
var knee_l := Node3D.new()
var knee_r := Node3D.new()
var arm_l := Node3D.new()
var arm_r := Node3D.new()
var elb_l := Node3D.new()
var elb_r := Node3D.new()
var vel := Vector3.ZERO
var sliding := 0.0
var lean := 0.0
var tilt := 0.0
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

func _ready() -> void:
	add_child(body)
	body.add_child(torso)
	torso.position = Vector3(0, 0.97, 0)
	var coat := Color(0.27, 0.20, 0.13)
	var pants := Color(0.17, 0.19, 0.22)
	var skin := Color(0.72, 0.55, 0.42)
	var wood := Color(0.36, 0.25, 0.15)
	var boot_c := Color(0.12, 0.09, 0.07)
	# ноги: бедро + колено + голень, стопа-эллипсоид
	for side in [-1.0, 1.0]:
		var leg: Node3D = leg_l if side < 0.0 else leg_r
		var knee: Node3D = knee_l if side < 0.0 else knee_r
		leg.position = Vector3(side * 0.1, 0.97, 0)
		body.add_child(leg)
		_part(leg, _capsule(0.088, 0.52), pants, Vector3(0, -0.23, 0))
		knee.position = Vector3(0, -0.46, 0)
		leg.add_child(knee)
		_part(knee, _capsule(0.07, 0.52), pants, Vector3(0, -0.23, 0))
		var foot := SphereMesh.new()
		foot.radius = 0.5
		foot.height = 1.0
		_ell(knee, foot, boot_c, Vector3(0, -0.47, 0.06), Vector3(0.15, 0.1, 0.3))
	# торс: овальный, с длинной полой кафтана и широкими плечами
	var skirt := CylinderMesh.new()
	skirt.top_radius = 0.2
	skirt.bottom_radius = 0.27
	skirt.height = 0.5
	skirt.radial_segments = 16
	_ell(torso, skirt, coat, Vector3(0, -0.05, 0), Vector3(1.0, 1.0, 0.8))
	_ell(torso, _capsule(0.5, 1.0), coat, Vector3(0, 0.36, 0), Vector3(0.45, 0.78, 0.34))
	var belt := CylinderMesh.new()
	belt.top_radius = 0.215
	belt.bottom_radius = 0.215
	belt.height = 0.07
	_ell(torso, belt, Color(0.12, 0.09, 0.06), Vector3(0, 0.07, 0), Vector3(1.0, 1.0, 0.82))
	var scarf := TorusMesh.new()
	scarf.inner_radius = 0.09
	scarf.outer_radius = 0.17
	_part(torso, scarf, Color(0.55, 0.14, 0.12), Vector3(0, 0.74, 0.01))
	# голова и шапка
	var neck := CylinderMesh.new()
	neck.top_radius = 0.055
	neck.bottom_radius = 0.065
	neck.height = 0.12
	_part(torso, neck, skin, Vector3(0, 0.78, 0))
	var head := SphereMesh.new()
	head.radius = 0.5
	head.height = 1.0
	_ell(torso, head, skin, Vector3(0, 0.92, 0.01), Vector3(0.28, 0.33, 0.3))
	var brim := CylinderMesh.new()
	brim.top_radius = 0.26
	brim.bottom_radius = 0.28
	brim.height = 0.025
	_part(torso, brim, Color(0.2, 0.15, 0.1), Vector3(0, 1.0, 0))
	var crown := SphereMesh.new()
	crown.radius = 0.5
	crown.height = 1.0
	_ell(torso, crown, Color(0.2, 0.15, 0.1), Vector3(0, 1.04, 0), Vector3(0.3, 0.2, 0.3))
	# рюкзак (овальный) и скатка
	_ell(torso, _capsule(0.5, 1.0), Color(0.36, 0.28, 0.18), Vector3(0, 0.38, -0.24), Vector3(0.34, 0.5, 0.2))
	var roll := CylinderMesh.new()
	roll.top_radius = 0.085
	roll.bottom_radius = 0.085
	roll.height = 0.46
	_part(torso, roll, Color(0.3, 0.33, 0.24), Vector3(0, 0.7, -0.27), Vector3(0, 0, PI * 0.5))
	# руки: плечо, локоть, предплечье, кисть
	for side in [-1.0, 1.0]:
		var arm: Node3D = arm_l if side < 0.0 else arm_r
		var elb: Node3D = elb_l if side < 0.0 else elb_r
		arm.position = Vector3(side * 0.27, 0.62, 0)
		torso.add_child(arm)
		var sh := SphereMesh.new()
		sh.radius = 0.5
		sh.height = 1.0
		_ell(arm, sh, coat, Vector3.ZERO, Vector3(0.15, 0.15, 0.15))
		_part(arm, _capsule(0.062, 0.36), coat, Vector3(0, -0.16, 0))
		elb.position = Vector3(0, -0.32, 0)
		arm.add_child(elb)
		_part(elb, _capsule(0.052, 0.34), coat, Vector3(0, -0.15, 0))
		var hand := SphereMesh.new()
		hand.radius = 0.5
		hand.height = 1.0
		_ell(elb, hand, skin, Vector3(0, -0.32, 0), Vector3(0.1, 0.12, 0.1))
	var handle := CylinderMesh.new()
	handle.top_radius = 0.02
	handle.bottom_radius = 0.025
	handle.height = 0.85
	_part(elb_r, handle, wood, Vector3(0, -0.3, 0.08), Vector3(0.25, 0, 0))
	var blade := BoxMesh.new()
	blade.size = Vector3(0.025, 0.15, 0.22)
	_part(elb_r, blade, Color(0.55, 0.57, 0.6), Vector3(0, 0.09, 0.2), Vector3(0.25, 0, 0))
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
	if y < main.WATER_Y - 0.9:
		return false
	if y - position.y > 0.75:
		return false
	var n: Vector3 = main.normal_at(p.x, p.z)
	if n.y < 0.66:
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
			f = clampf(1.0 + along * slope * 1.7, 0.3, 1.0)
		else:
			f = minf(1.0 + along * slope * 0.25, 1.2)
		target = d * speed * mag * f
	# крутой склон: человека тянет вниз, он теряет управление и катится
	var s := clampf((slope - 0.42) / 0.4, 0.0, 1.0)
	sliding = lerpf(sliding, s, minf(1.0, 4.0 * delta))
	var accel := 11.0 * (1.0 - sliding * 0.75)
	vel = vel.move_toward(target, accel * delta)
	vel += down * sliding * 9.0 * delta
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
	var ty := maxf(ground, main.WATER_Y - 0.35)
	position.y = lerpf(position.y, ty, minf(1.0, 14.0 * delta))
	# походка: фаза от пройденного пути, размах от скорости
	var sn := clampf(sp / speed, 0.0, 1.3)
	run_mag = lerpf(run_mag, sn, minf(1.0, 8.0 * delta))
	phase += sp * delta * 2.3
	var fwd := Vector3(sin(body.rotation.y), 0, cos(body.rotation.y))
	var incline := 0.0
	if sp > 0.1:
		incline = clampf(-fwd.dot(down) * slope, -0.8, 0.8)  # >0 вверх
	lean = lerpf(lean, 0.1 * run_mag + maxf(incline, 0.0) * 0.45 - maxf(-incline, 0.0) * 0.2, minf(1.0, 6.0 * delta))
	var amp := 0.55 * minf(run_mag, 1.1)
	var sw := sin(phase)
	var lift := 0.35 + maxf(incline, 0.0) * 0.6
	var sl := sliding
	leg_l.rotation.x = lerpf(sw * amp, -0.5, sl)
	leg_r.rotation.x = lerpf(-sw * amp, -0.9, sl)
	knee_l.rotation.x = lerpf(maxf(0.0, -cos(phase)) * amp * 1.4 * lift / 0.35 * 0.6, 0.3, sl)
	knee_r.rotation.x = lerpf(maxf(0.0, cos(phase)) * amp * 1.4 * lift / 0.35 * 0.6, 0.7, sl)
	arm_l.rotation.x = lerpf(-sw * amp * 0.9, -0.6, sl)
	arm_r.rotation.x = lerpf(sw * amp * 0.6 - 0.1, 0.4, sl)
	arm_l.rotation.z = lerpf(0.04, 0.5, sl)
	arm_r.rotation.z = lerpf(-0.04, -0.5, sl)
	elb_l.rotation.x = lerpf(-0.25 - amp * 0.4, -0.2, sl)
	elb_r.rotation.x = lerpf(-0.35 - amp * 0.3, -0.2, sl)
	torso.rotation.x = lerpf(lean, -0.35, sl)
	torso.rotation.y = -sw * 0.12 * run_mag
	body.position.y = absf(cos(phase)) * 0.045 * run_mag - sl * 0.12
