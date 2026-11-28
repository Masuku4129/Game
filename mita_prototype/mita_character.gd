extends Node3D
# Stylized articulated character prototype. Each limb is attached to a pivot so movement animation is real.
var move_dir := Vector2.ZERO
var running := false
var phase := 0.0
var torso: Node3D
var head: Node3D
var hair: Node3D
var left_leg: Node3D
var right_leg: Node3D
var left_arm: Node3D
var right_arm: Node3D

func _ready():
	_build_character()

func set_move(v: Vector2):
	move_dir = v
	if v.length() > 0.08:
		rotation.y = atan2(v.x, v.y)

func set_running(value: bool):
	running = value

func tick_animation(delta: float):
	var speed = 8.5 if running else 5.2
	if move_dir.length() > 0.08:
		phase += delta * speed
		var amp = 0.72 if running else 0.42
		left_leg.rotation.x = sin(phase) * amp
		right_leg.rotation.x = sin(phase + PI) * amp
		left_arm.rotation.x = sin(phase + PI) * amp * 0.7
		right_arm.rotation.x = sin(phase) * amp * 0.7
		torso.rotation.x = -0.13 if running else 0.02
		position.y = abs(sin(phase * 2.0)) * (0.07 if running else 0.035)
	else:
		phase += delta
		left_leg.rotation.x = lerp(left_leg.rotation.x, 0.0, delta * 8)
		right_leg.rotation.x = lerp(right_leg.rotation.x, 0.0, delta * 8)
		left_arm.rotation.x = lerp(left_arm.rotation.x, 0.0, delta * 5)
		right_arm.rotation.x = lerp(right_arm.rotation.x, 0.0, delta * 5)
		torso.rotation.x = sin(phase * 1.6) * 0.025
		position.y = sin(phase * 2.0) * 0.018
		head.rotation.x = sin(phase * 1.3) * 0.02
	if move_dir.length() > 0.08:
		position += Vector3(move_dir.x, 0, move_dir.y) * delta * (4.4 if running else 2.5)

func _build_character():
	# Root proportions are kept compact and readable from an overhead/isometric camera.
	torso = Node3D.new()
	torso.position.y = 1.15
	add_child(torso)
	var hoodie = _ellipsoid(Vector3(0, 0, 0), Vector3(0.36, 0.48, 0.24), Color(0.045, 0.04, 0.07))
	torso.add_child(hoodie)
	# Hood volume behind head, collar and seams.
	var hood = _ellipsoid(Vector3(0, 0.42, -0.08), Vector3(0.29, 0.28, 0.28), Color(0.025, 0.025, 0.045))
	torso.add_child(hood)
	var front_seam = _box(Vector3(0, -0.05, 0.245), Vector3(0.018, 0.32, 0.015), Color(0.16, 0.13, 0.23))
	torso.add_child(front_seam)
	# Neck, head and face
	var neck = _cylinder(Vector3(0, 0.52, 0.01), 0.11, 0.17, Color(0.72, 0.56, 0.52))
	torso.add_child(neck)
	head = Node3D.new()
	head.position.y = 0.73
	torso.add_child(head)
	var face = _ellipsoid(Vector3(0, 0, 0.04), Vector3(0.245, 0.32, 0.22), Color(0.78, 0.64, 0.62))
	head.add_child(face)
	# Eyes visible on camera-facing side, anime proportions.
	for x in [-0.105, 0.105]:
		var eye = _ellipsoid(Vector3(x, -0.045, 0.235), Vector3(0.052, 0.075, 0.025), Color(0.27, 0.18, 0.75))
		head.add_child(eye
		)
		var glint = _ellipsoid(Vector3(x - 0.012, -0.025, 0.26), Vector3(0.016, 0.025, 0.008), Color(0.9, 0.88, 1.0))
		head.add_child(glint)
	var fringe = _hair_shell(Vector3(0, 0.16, 0.04), Vector3(0.29, 0.22, 0.27), Color(0.015, 0.012, 0.03))
	head.add_child(fringe)
	# Long hair draping behind in separate locks.
	hair = Node3D.new()
	hair.position = Vector3(0, 0.16, -0.12)
	head.add_child(hair)
	for i in range(7):
		var x = (i - 3) * 0.075
		var lock = _ellipsoid(Vector3(x, -0.24 - abs(x)*0.25, -0.1), Vector3(0.055, 0.52, 0.08), Color(0.018, 0.014, 0.04))
		hair.add_child(lock)
		var highlight = _ellipsoid(Vector3(x + 0.02, -0.23, -0.015), Vector3(0.012, 0.42, 0.014), Color(0.09, 0.06, 0.24))
		hair.add_child(highlight)
	# Trousers, articulated legs and shoes
	left_leg = _limb(Vector3(-0.15, -0.48, 0), Vector3(0.13, 0.48, 0.14), Color(0.055, 0.05, 0.085))
	torso.add_child(left_leg)
	right_leg = _limb(Vector3(0.15, -0.48, 0), Vector3(0.13, 0.48, 0.14), Color(0.055, 0.05, 0.085))
	torso.add_child(right_leg)
	left_arm = _limb(Vector3(-0.4, 0.02, 0), Vector3(0.12, 0.4, 0.12), Color(0.045, 0.04, 0.07))
	left_arm.rotation.z = 0.12
	torso.add_child(left_arm)
	right_arm = _limb(Vector3(0.4, 0.02, 0), Vector3(0.12, 0.4, 0.12), Color(0.045, 0.04, 0.07))
	right_arm.rotation.z = -0.12
	torso.add_child(right_arm)
	# Hoodie drawstrings and cuffs.
	for x in [-0.045, 0.045]:
		var cord = _cylinder(Vector3(x, 0.22, 0.245), 0.009, 0.24, Color(0.45, 0.4, 0.55))
		torso.add_child(cord)
	var waist = _box(Vector3(0, -0.42, 0), Vector3(0.34, 0.07, 0.22), Color(0.025, 0.022, 0.04))
		torso.add_child(waist)

func _limb(offset: Vector3, size: Vector3, color: Color) -> Node3D:
	var pivot = Node3D.new()
	pivot.position = offset
	var mesh = _ellipsoid(Vector3(0, -size.y * 0.5, 0), size, color)
	pivot.add_child(mesh)
	return pivot

func _ellipsoid(pos: Vector3, scale: Vector3, color: Color) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var m = SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = 24
	m.rings = 12
	mi.mesh = m
	mi.position = pos
	mi.scale = scale * 2.0
	mi.material_override = _mat(color)
	return mi

func _hair_shell(pos: Vector3, scale: Vector3, color: Color) -> MeshInstance3D:
	var mi = _ellipsoid(pos, scale, color)
	mi.rotation.z = -0.12
	return mi

func _box(pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var m = BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.position = pos
	mi.material_override = _mat(color)
	return mi

func _cylinder(pos: Vector3, radius: float, height: float, color: Color) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var m = CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	mi.mesh = m
	mi.position = pos
	mi.material_override = _mat(color)
	return mi

func _mat(color: Color) -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.72
	return material
