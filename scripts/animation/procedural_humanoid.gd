extends Node3D
## Articulated 19th-century field explorer with layered clothing and seasonal gear.

const LIMB_SWING := 0.62
const STEP_LIFT := 0.16
const IDLE_BREATH := 0.018

var phase := 0.0
var gait_weight := 0.0
var target_speed := 0.0
var target_slope := 0.0
var torso: Node3D
var head: Node3D
var left_arm: Node3D
var right_arm: Node3D
var left_leg: Node3D
var right_leg: Node3D
var clothing: StandardMaterial3D
var trousers: StandardMaterial3D
var scarf: StandardMaterial3D
var scarf_mesh: MeshInstance3D
var fur_collar: MeshInstance3D


func _ready() -> void:
	set_process(true)
	_build_rig()


func set_season(season: String) -> void:
	if clothing == null:
		return
	match season:
		"spring":
			clothing.albedo_color = Color(0.34, 0.29, 0.21)
			trousers.albedo_color = Color(0.25, 0.25, 0.21)
			scarf_mesh.visible = false
			fur_collar.visible = false
		"summer":
			clothing.albedo_color = Color(0.43, 0.37, 0.27)
			trousers.albedo_color = Color(0.31, 0.30, 0.24)
			scarf_mesh.visible = false
			fur_collar.visible = false
		"autumn":
			clothing.albedo_color = Color(0.29, 0.23, 0.17)
			trousers.albedo_color = Color(0.22, 0.22, 0.19)
			scarf_mesh.visible = true
			fur_collar.visible = false
		"winter":
			clothing.albedo_color = Color(0.22, 0.23, 0.22)
			trousers.albedo_color = Color(0.19, 0.20, 0.19)
			scarf_mesh.visible = true
			fur_collar.visible = true


func set_motion(horizontal_speed: float, slope: float) -> void:
	target_speed = clampf(horizontal_speed / 7.0, 0.0, 1.0)
	target_slope = clampf(slope, -1.0, 1.0)


func _process(delta: float) -> void:
	gait_weight = move_toward(gait_weight, target_speed, delta * 5.0)
	if gait_weight > 0.01:
		phase = fposmod(phase + delta * lerpf(2.0, 9.0, gait_weight), TAU)
	var stride := sin(phase)
	var counter_stride := sin(phase + PI)
	var lift_left := maxf(0.0, cos(phase))
	var lift_right := maxf(0.0, cos(phase + PI))
	var swing := LIMB_SWING * gait_weight
	var breath := sin(Time.get_ticks_msec() * 0.0018) * IDLE_BREATH
	torso.position.y = breath + absf(stride) * 0.035 * gait_weight
	torso.rotation.x = -target_slope * 0.18 * gait_weight
	head.rotation.x = -torso.rotation.x * 0.45
	left_leg.rotation.x = stride * swing
	right_leg.rotation.x = counter_stride * swing
	left_leg.position.y = -0.43 + lift_left * STEP_LIFT * gait_weight * (1.0 + absf(target_slope))
	right_leg.position.y = -0.43 + lift_right * STEP_LIFT * gait_weight * (1.0 + absf(target_slope))
	left_arm.rotation.x = counter_stride * swing * 0.72
	right_arm.rotation.x = stride * swing * 0.72
	left_arm.rotation.z = -0.08 * gait_weight
	right_arm.rotation.z = 0.08 * gait_weight


func _build_rig() -> void:
	clothing = _material(Color(0.31, 0.25, 0.18))
	trousers = _material(Color(0.22, 0.23, 0.19))
	var skin := _material(Color(0.63, 0.48, 0.36))
	var boots := _material(Color(0.12, 0.10, 0.08))
	var leather := _material(Color(0.19, 0.12, 0.075))
	var brass := _material(Color(0.52, 0.39, 0.22))
	scarf = _material(Color(0.29, 0.20, 0.14))
	var hair := _material(Color(0.095, 0.065, 0.045))
	var pack := _material(Color(0.27, 0.22, 0.15))
	var dark := _material(Color(0.055, 0.045, 0.035))

	torso = Node3D.new()
	torso.name = "Torso"
	add_child(torso)
	_add_capsule(torso, Vector3(0, 0.08, 0), Vector3(0.34, 0.58, 0.22), clothing)
	_add_cylinder(torso, Vector3(0, -0.18, 0), 0.29, 0.35, 0.38, clothing)
	_add_cylinder(torso, Vector3(0, -0.12, 0), 0.31, 0.32, 0.075, leather)
	_add_box(torso, Vector3(0, -0.12, -0.325), Vector3(0.105, 0.085, 0.035), brass)
	_add_box(torso, Vector3(-0.19, 0.02, -0.218), Vector3(0.13, 0.16, 0.035), leather)
	_add_box(torso, Vector3(0.19, 0.02, -0.218), Vector3(0.13, 0.16, 0.035), leather)
	for button_y in [0.27, 0.13, -0.01]:
		_add_sphere(torso, Vector3(0, button_y, -0.226), 0.022, brass)

	scarf_mesh = _add_cylinder(torso, Vector3(0, 0.49, 0), 0.17, 0.19, 0.13, scarf)
	fur_collar = _add_sphere(torso, Vector3(0, 0.48, 0), 0.205, brass)
	fur_collar.scale = Vector3(1.0, 0.38, 1.0)
	fur_collar.visible = false

	# Canvas pack, leather straps, pockets and a rolled bedroll.
	_add_box(torso, Vector3(0, 0.08, 0.255), Vector3(0.40, 0.50, 0.19), pack)
	_add_box(torso, Vector3(0, -0.12, 0.365), Vector3(0.29, 0.19, 0.045), leather)
	_add_box(torso, Vector3(-0.225, 0.08, 0.18), Vector3(0.07, 0.46, 0.07), leather)
	_add_box(torso, Vector3(0.225, 0.08, 0.18), Vector3(0.07, 0.46, 0.07), leather)
	_add_box(torso, Vector3(-0.22, -0.06, 0.12), Vector3(0.12, 0.18, 0.12), pack)
	_add_box(torso, Vector3(0.22, -0.06, 0.12), Vector3(0.12, 0.18, 0.12), pack)
	var bedroll := _add_cylinder(torso, Vector3(0, 0.39, 0.39), 0.105, 0.105, 0.52, scarf)
	bedroll.rotation.z = PI * 0.5

	head = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.72, 0)
	torso.add_child(head)
	_add_sphere(head, Vector3.ZERO, 0.19, skin)
	_add_sphere(head, Vector3(0, -0.12, -0.055), 0.125, hair)
	_add_sphere(head, Vector3(0, 0.095, 0.035), 0.175, hair)
	_add_sphere(head, Vector3(0, -0.015, -0.174), 0.038, skin)
	_add_sphere(head, Vector3(-0.067, 0.04, -0.153), 0.018, dark)
	_add_sphere(head, Vector3(0.067, 0.04, -0.153), 0.018, dark)
	_add_sphere(head, Vector3(-0.18, 0, 0), 0.047, skin)
	_add_sphere(head, Vector3(0.18, 0, 0), 0.047, skin)
	_add_cylinder(head, Vector3(0, 0.16, 0), 0.205, 0.205, 0.045, leather)
	_add_cylinder(head, Vector3(0, 0.245, 0.015), 0.135, 0.16, 0.16, leather)
	_add_box(head, Vector3(0, 0.17, -0.18), Vector3(0.16, 0.035, 0.12), leather)

	left_arm = _make_limb("LeftArm", Vector3(-0.39, 0.43, 0), Vector3(0.13, 0.48, 0.13), clothing)
	right_arm = _make_limb("RightArm", Vector3(0.39, 0.43, 0), Vector3(0.13, 0.48, 0.13), clothing)
	torso.add_child(left_arm)
	torso.add_child(right_arm)
	for arm in [left_arm, right_arm]:
		_add_cylinder(arm, Vector3(0, -0.40, 0), 0.13, 0.14, 0.09, leather)
		_add_sphere(arm, Vector3(0, -0.53, -0.015), 0.095, boots)

	left_leg = _make_limb("LeftLeg", Vector3(-0.17, -0.43, 0), Vector3(0.17, 0.48, 0.18), trousers)
	right_leg = _make_limb("RightLeg", Vector3(0.17, -0.43, 0), Vector3(0.17, 0.48, 0.18), trousers)
	torso.add_child(left_leg)
	torso.add_child(right_leg)
	for leg in [left_leg, right_leg]:
		_add_box(leg, Vector3(0, -0.10, -0.165), Vector3(0.20, 0.14, 0.035), leather)
		_add_box(leg, Vector3(0, -0.25, -0.045), Vector3(0.19, 0.15, 0.34), boots)
		_add_box(leg, Vector3(0, -0.33, -0.08), Vector3(0.205, 0.045, 0.37), dark)
		for lace_y in [-0.22, -0.26, -0.30]:
			_add_box(leg, Vector3(0, lace_y, -0.221), Vector3(0.10, 0.012, 0.012), brass)


func _make_limb(limb_name: String, pivot: Vector3, dimensions: Vector3, material: Material) -> Node3D:
	var limb := Node3D.new()
	limb.name = limb_name
	limb.position = pivot
	_add_capsule(limb, Vector3(0, -0.23, 0), dimensions, material)
	return limb


func _add_capsule(parent: Node3D, offset: Vector3, dimensions: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = dimensions.x
	mesh.height = maxf(dimensions.y, dimensions.x * 2.0)
	mesh.radial_segments = 12
	mesh.rings = 6
	instance.mesh = mesh
	instance.position = offset
	instance.material_override = material
	parent.add_child(instance)
	return instance


func _add_sphere(parent: Node3D, offset: Vector3, radius: float, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 8
	instance.mesh = mesh
	instance.position = offset
	instance.material_override = material
	parent.add_child(instance)
	return instance


func _add_box(parent: Node3D, offset: Vector3, dimensions: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	instance.mesh = mesh
	instance.position = offset
	instance.material_override = material
	parent.add_child(instance)
	return instance


func _add_cylinder(parent: Node3D, offset: Vector3, top_radius: float, bottom_radius: float, height: float, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = 16
	instance.mesh = mesh
	instance.position = offset
	instance.material_override = material
	parent.add_child(instance)
	return instance


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	return material
