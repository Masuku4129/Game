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
var leg_l := Node3D.new()
var leg_r := Node3D.new()
var arm_l := Node3D.new()
var arm_r := Node3D.new()
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

func _capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 12
	m.rings = 4
	return m

func _ready() -> void:
	add_child(body)
	var coat := Color(0.27, 0.20, 0.13)
	var pants := Color(0.17, 0.19, 0.22)
	var skin := Color(0.72, 0.55, 0.42)
	var wood := Color(0.36, 0.25, 0.15)
	# ноги: вращаются от бедра
	for side in [-1.0, 1.0]:
		var leg: Node3D = leg_l if side < 0.0 else leg_r
		leg.position = Vector3(side * 0.11, 0.92, 0)
		body.add_child(leg)
		_part(leg, _capsule(0.095, 0.95), pants, Vector3(0, -0.42, 0))
		var boot := BoxMesh.new()
		boot.size = Vector3(0.17, 0.16, 0.3)
		_part(leg, boot, Color(0.12, 0.09, 0.07), Vector3(0, -0.86, 0.05))
	# торс, пояс, шарф
	_part(body, _capsule(0.23, 0.78), coat, Vector3(0, 1.32, 0))
	var belt := CylinderMesh.new()
	belt.top_radius = 0.235
	belt.bottom_radius = 0.235
	belt.height = 0.07
	_part(body, belt, Color(0.12, 0.09, 0.06), Vector3(0, 1.02, 0))
	var scarf := TorusMesh.new()
	scarf.inner_radius = 0.1
	scarf.outer_radius = 0.2
	_part(body, scarf, Color(0.55, 0.14, 0.12), Vector3(0, 1.68, 0.02))
	# голова, шляпа
	var head := SphereMesh.new()
	head.radius = 0.15
	head.height = 0.3
	_part(body, head, skin, Vector3(0, 1.84, 0.01))
	var brim := CylinderMesh.new()
	brim.top_radius = 0.27
	brim.bottom_radius = 0.27
	brim.height = 0.03
	_part(body, brim, Color(0.2, 0.15, 0.1), Vector3(0, 1.93, 0))
	var crown := CylinderMesh.new()
	crown.top_radius = 0.13
	crown.bottom_radius = 0.16
	crown.height = 0.17
	_part(body, crown, Color(0.2, 0.15, 0.1), Vector3(0, 2.02, 0))
	# рюкзак и скатка
	var pack := BoxMesh.new()
	pack.size = Vector3(0.38, 0.5, 0.2)
	_part(body, pack, Color(0.36, 0.28, 0.18), Vector3(0, 1.36, -0.27))
	var roll := CylinderMesh.new()
	roll.top_radius = 0.09
	roll.bottom_radius = 0.09
	roll.height = 0.46
	_part(body, roll, Color(0.3, 0.33, 0.24), Vector3(0, 1.66, -0.3), Vector3(0, 0, PI * 0.5))
	# руки: вращаются от плеча; в правой топор
	for side in [-1.0, 1.0]:
		var arm: Node3D = arm_l if side < 0.0 else arm_r
		arm.position = Vector3(side * 0.31, 1.58, 0)
		body.add_child(arm)
		_part(arm, _capsule(0.07, 0.68), coat, Vector3(0, -0.28, 0))
		var hand := SphereMesh.new()
		hand.radius = 0.065
		hand.height = 0.13
		_part(arm, hand, skin, Vector3(0, -0.62, 0))
	var handle := CylinderMesh.new()
	handle.top_radius = 0.022
	handle.bottom_radius = 0.026
	handle.height = 0.9
	_part(arm_r, handle, wood, Vector3(0, -0.62, 0.1), Vector3(0.2, 0, 0))
	var blade := BoxMesh.new()
	blade.size = Vector3(0.04, 0.17, 0.26)
	_part(arm_r, blade, Color(0.55, 0.57, 0.6), Vector3(0, -0.22, 0.2), Vector3(0.2, 0, 0))
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
	moving = false
	if mag > 0.12:
		var d := Vector3(move_vec.x, 0, move_vec.y).normalized().rotated(Vector3.UP, cam_yaw)
		var step := d * speed * mag * delta
		var p := position
		if _can_walk(p + step):
			p += step
		elif _can_walk(p + Vector3(step.x, 0, 0)):
			p.x += step.x
		elif _can_walk(p + Vector3(0, 0, step.z)):
			p.z += step.z
		moving = (Vector2(p.x, p.z) - Vector2(position.x, position.z)).length() > 0.0005
		position.x = p.x
		position.z = p.z
		body.rotation.y = lerp_angle(body.rotation.y, atan2(d.x, d.z), minf(1.0, 12.0 * delta))
	run_mag = lerpf(run_mag, mag if moving else 0.0, minf(1.0, 10.0 * delta))
	var ground: float = main.height(position.x, position.z)
	position.y = lerpf(position.y, maxf(ground, main.WATER_Y - 0.35), minf(1.0, 18.0 * delta))
	phase += delta * 9.0 * run_mag
	var sw := sin(phase) * 0.75 * run_mag
	leg_l.rotation.x = sw
	leg_r.rotation.x = -sw
	arm_l.rotation.x = -sw * 0.8
	arm_r.rotation.x = sw * 0.5 - 0.15
	body.position.y = absf(sin(phase)) * 0.05 * run_mag
