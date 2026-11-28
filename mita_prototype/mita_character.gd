extends Node3D
# Procedural stylized Mita character. Segmented limbs, layered hair, hoodie details and locomotion.
var move_dir := Vector2.ZERO
var running := false
var phase := 0.0
var torso: Node3D
var head: Node3D
var left_leg: Node3D
var right_leg: Node3D
var left_arm: Node3D
var right_arm: Node3D
var left_knee: Node3D
var right_knee: Node3D

func _ready():
	_build_character()

func set_move(v: Vector2):
	move_dir = v
	if v.length() > 0.08:
		rotation.y = atan2(v.x, v.y)

func set_running(value: bool):
	running = value

func tick_animation(delta: float):
	if move_dir.length() > 0.08:
		phase += delta * (10.0 if running else 6.2)
		var amp = 0.68 if running else 0.38
		left_leg.rotation.x = sin(phase) * amp
		right_leg.rotation.x = sin(phase + PI) * amp
		left_knee.rotation.x = max(0.0, -sin(phase)) * (0.8 if running else 0.35)
		right_knee.rotation.x = max(0.0, -sin(phase + PI)) * (0.8 if running else 0.35)
		left_arm.rotation.x = sin(phase + PI) * amp * 0.72
		right_arm.rotation.x = sin(phase) * amp * 0.72
		torso.rotation.x = -0.12 if running else 0.015
		position.y = abs(sin(phase * 2.0)) * (0.075 if running else 0.035)
		position += Vector3(move_dir.x, 0, move_dir.y) * delta * (4.8 if running else 2.7)
	else:
		phase += delta
		left_leg.rotation.x = lerp(left_leg.rotation.x, 0.0, delta * 8)
		right_leg.rotation.x = lerp(right_leg.rotation.x, 0.0, delta * 8)
		left_knee.rotation.x = lerp(left_knee.rotation.x, 0.0, delta * 8)
		right_knee.rotation.x = lerp(right_knee.rotation.x, 0.0, delta * 8)
		left_arm.rotation.x = lerp(left_arm.rotation.x, 0.0, delta * 5)
		right_arm.rotation.x = lerp(right_arm.rotation.x, 0.0, delta * 5)
		torso.rotation.x = sin(phase * 1.5) * 0.02
		position.y = sin(phase * 2.0) * 0.016
		head.rotation.x = sin(phase * 1.25) * 0.02
		head.rotation.y = sin(phase * 0.75) * 0.025

func _build_character():
	torso = Node3D.new()
	torso.position.y = 1.05
	add_child(torso)
	# Body silhouette and oversized dark hoodie
	torso.add_child(_ellipsoid(Vector3(0, 0.0, 0), Vector3(0.34, 0.43, 0.24), Color(0.045,0.038,0.065)))
	torso.add_child(_ellipsoid(Vector3(0, 0.28, -0.12), Vector3(0.29,0.25,0.28), Color(0.025,0.024,0.042))) # hood behind
	torso.add_child(_ellipsoid(Vector3(0,-0.36,0), Vector3(0.31,0.13,0.23), Color(0.028,0.025,0.045)))
	# Collar, seams, pocket, strings
	torso.add_child(_ellipsoid(Vector3(0,0.37,0.015), Vector3(0.18,0.09,0.16), Color(0.035,0.03,0.055)))
	torso.add_child(_box(Vector3(0,-0.13,0.242), Vector3(0.26,0.13,0.012), Color(0.065,0.055,0.095)))
	torso.add_child(_box(Vector3(0,-0.06,0.245), Vector3(0.012,0.43,0.014), Color(0.12,0.09,0.19)))
	for x in [-0.05,0.05]:
		torso.add_child(_cylinder(Vector3(x,0.22,0.25),0.008,0.22,Color(0.48,0.42,0.62)))
	# Neck and head
	torso.add_child(_cylinder(Vector3(0,0.48,0),0.085,0.16,Color(0.74,0.59,0.59)))
	head = Node3D.new()
	head.position.y = 0.62
	torso.add_child(head)
	head.add_child(_ellipsoid(Vector3(0,0.02,0.035),Vector3(0.22,0.28,0.19),Color(0.79,0.67,0.66)))
	# Ears
	for x in [-0.21,0.21]:
		head.add_child(_ellipsoid(Vector3(x,0.02,0.0),Vector3(0.055,0.09,0.045),Color(0.73,0.57,0.58)))
	# Eyes, brows and subtle nose/mouth
	for x in [-0.095,0.095]:
		head.add_child(_ellipsoid(Vector3(x,-0.025,0.205),Vector3(0.042,0.066,0.022),Color(0.16,0.12,0.36)))
		head.add_child(_ellipsoid(Vector3(x-0.01,-0.005,0.226),Vector3(0.013,0.021,0.008),Color(0.95,0.91,1.0)))
		head.add_child(_box(Vector3(x,-0.105,0.202),Vector3(0.06,0.012,0.01),Color(0.22,0.16,0.28)))
	head.add_child(_ellipsoid(Vector3(0,-0.08,0.22),Vector3(0.018,0.025,0.012),Color(0.7,0.49,0.5)))
	head.add_child(_box(Vector3(0,-0.16,0.205),Vector3(0.045,0.008,0.009),Color(0.4,0.22,0.28)))
	# Crown cap and front bangs as layered pointed mesh locks
	head.add_child(_ellipsoid(Vector3(0,0.19,-0.015),Vector3(0.24,0.19,0.22),Color(0.018,0.014,0.034)))
	for i in range(5):
		var x = (i-2)*0.085
		var bang = _hair_lock(Vector3(x,0.115,0.19),Vector3(x*0.9,-0.12,0.225),Vector3(x*0.7,-0.27,0.18),Color(0.02,0.015,0.045))
		head.add_child(bang)
	# Back hair: 8 flowing, tapered locks with blue-violet sheen
	for i in range(8):
		var x = (i-3.5)*0.062
		var top = Vector3(x,0.12,-0.13)
		var mid = Vector3(x*1.12,-0.28,-0.15)
		var end = Vector3(x*1.22,-0.68-abs(x)*0.25,-0.11)
		head.add_child(_hair_lock(top,mid,end,Color(0.018,0.014,0.038)))
		head.add_child(_hair_lock(top+Vector3(0.012,0.0,0.018),mid+Vector3(0.014,0.01,0.018),end+Vector3(0.012,0.04,0.02),Color(0.075,0.045,0.19)))
	# Pants and two-piece legs with knee joints, socks/shoes
	left_leg = _leg(Vector3(-0.13,-0.40,0))
	right_leg = _leg(Vector3(0.13,-0.40,0))
	torso.add_child(left_leg)
	torso.add_child(right_leg)
	left_knee = left_leg.get_node("Knee")
	right_knee = right_leg.get_node("Knee")
	# Sleeves, forearms, hands
	left_arm = _arm(Vector3(-0.36,0.13,0))
	right_arm = _arm(Vector3(0.36,0.13,0))
	torso.add_child(left_arm)
	torso.add_child(right_arm)

func _leg(offset: Vector3) -> Node3D:
	var hip = Node3D.new()
	hip.position = offset
	hip.add_child(_capsule(Vector3(0,-0.22,0),0.115,0.43,Color(0.055,0.05,0.082)))
	var knee = Node3D.new()
	knee.name = "Knee"
	knee.position.y = -0.42
	hip.add_child(knee)
	knee.add_child(_capsule(Vector3(0,-0.2,0),0.105,0.39,Color(0.045,0.04,0.07)))
	knee.add_child(_ellipsoid(Vector3(0,-0.38,0.035),Vector3(0.13,0.07,0.20),Color(0.025,0.022,0.038)))
	knee.add_child(_box(Vector3(0,-0.385,0.12),Vector3(0.13,0.018,0.035),Color(0.17,0.14,0.22)))
	return hip

func _arm(offset: Vector3) -> Node3D:
	var shoulder = Node3D.new()
	shoulder.position = offset
	shoulder.rotation.z = -0.12 if offset.x < 0 else 0.12
	shoulder.add_child(_capsule(Vector3(0,-0.2,0),0.105,0.4,Color(0.05,0.044,0.073)))
	shoulder.add_child(_ellipsoid(Vector3(0,-0.39,0),Vector3(0.09,0.1,0.09),Color(0.055,0.05,0.08)))
	shoulder.add_child(_ellipsoid(Vector3(0,-0.46,0.035),Vector3(0.075,0.085,0.07),Color(0.74,0.57,0.56)))
	shoulder.add_child(_box(Vector3(0,-0.34,0),Vector3(0.18,0.07,0.15),Color(0.07,0.06,0.10)))
	return shoulder

func _hair_lock(a: Vector3,b: Vector3,c: Vector3,color: Color) -> MeshInstance3D:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(_mat(color))
	# tapered ribbon with a slight outward thickness, three faces
	st.add_vertex(a+Vector3(-0.045,0,0))
	st.add_vertex(a+Vector3(0.045,0,0))
	st.add_vertex(b+Vector3(0.035,0,0))
	st.add_vertex(a+Vector3(-0.045,0,0))
	st.add_vertex(b+Vector3(0.035,0,0))
	st.add_vertex(b+Vector3(-0.035,0,0))
	st.add_vertex(b+Vector3(-0.035,0,0))
	st.add_vertex(b+Vector3(0.035,0,0))
	st.add_vertex(c)
	st.generate_normals()
	var mesh = st.commit()
	var inst = MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = _mat(color)
	return inst

func _ellipsoid(pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var m = SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = 24
	m.rings = 12
	mi.mesh = m
	mi.position = pos
	mi.scale = size*2.0
	mi.material_override = _mat(color)
	return mi

func _capsule(pos: Vector3, radius: float, height: float, color: Color) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var m = CapsuleMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = 16
	m.rings = 6
	mi.mesh = m
	mi.position = pos
	mi.material_override = _mat(color)
	return mi

func _box(pos: Vector3,size: Vector3,color: Color) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var m = BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.position = pos
	mi.material_override = _mat(color)
	return mi

func _cylinder(pos: Vector3,radius: float,height: float,color: Color) -> MeshInstance3D:
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
	material.roughness = 0.68
	material.metallic = 0.0
	return material
