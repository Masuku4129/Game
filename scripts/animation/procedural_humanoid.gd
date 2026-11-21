extends Node3D
## Lightweight procedural humanoid gait prototype.
## This is an articulated mesh rig, deliberately kept asset-free for CI testing.
## It can later be replaced by a retargeted Skeleton3D without changing the player API.

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


func _ready() -> void:
	_build_rig()


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
	var clothing := _material(Color(0.31, 0.25, 0.18))
	var trousers := _material(Color(0.22, 0.23, 0.19))
	var skin := _material(Color(0.63, 0.48, 0.36))
	var boots := _material(Color(0.12, 0.10, 0.08))

	torso = Node3D.new()
	torso.name = "Torso"
	add_child(torso)
	_add_capsule(torso, Vector3(0.0, 0.08, 0.0), Vector3(0.34, 0.58, 0.22), clothing)

	head = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0.0, 0.72, 0.0)
	torso.add_child(head)
	_add_sphere(head, Vector3(0.0, 0.0, 0.0), 0.19, skin)

	left_arm = _make_limb("LeftArm", Vector3(-0.39, 0.43, 0.0), Vector3(0.13, 0.48, 0.13), clothing)
	right_arm = _make_limb("RightArm", Vector3(0.39, 0.43, 0.0), Vector3(0.13, 0.48, 0.13), clothing)
	torso.add_child(left_arm)
	torso.add_child(right_arm)

	left_leg = _make_limb("LeftLeg", Vector3(-0.17, -0.43, 0.0), Vector3(0.17, 0.48, 0.18), trousers)
	right_leg = _make_limb("RightLeg", Vector3(0.17, -0.43, 0.0), Vector3(0.17, 0.48, 0.18), trousers)
	torso.add_child(left_leg)
	torso.add_child(right_leg)
	_add_box(left_leg, Vector3(0.0, -0.25, -0.045), Vector3(0.18, 0.12, 0.34), boots)
	_add_box(right_leg, Vector3(0.0, -0.25, -0.045), Vector3(0.18, 0.12, 0.34), boots)


func _make_limb(limb_name: String, pivot: Vector3, dimensions: Vector3, material: Material) -> Node3D:
	var limb := Node3D.new()
	limb.name = limb_name
	limb.position = pivot
	_add_capsule(limb, Vector3(0.0, -0.23, 0.0), dimensions, material)
	return limb


func _add_capsule(parent: Node3D, offset: Vector3, dimensions: Vector3, material: Material) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = dimensions.x
	mesh.height = maxf(dimensions.y, dimensions.x * 2.0)
	mesh_instance.mesh = mesh
	mesh_instance.position = offset
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)


func _add_sphere(parent: Node3D, offset: Vector3, radius: float, material: Material) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh_instance.mesh = mesh
	mesh_instance.position = offset
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)


func _add_box(parent: Node3D, offset: Vector3, dimensions: Vector3, material: Material) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	mesh_instance.mesh = mesh
	mesh_instance.position = offset
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	return material
