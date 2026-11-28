extends Node3D
## Fixed elevated 45-degree camera: follows the player with stable framing.
## Camera rotation, pitch and zoom are intentionally locked.

const PITCH := 45.0
const DISTANCE := 12.0
const FOLLOW_XZ := 9.0
const FOLLOW_Y := 3.0
var target: Node3D
var cam := Camera3D.new()

func _ready() -> void:
	cam.fov = 45.0
	cam.near = 0.5
	cam.far = 150.0
	add_child(cam)
	_update()

func _process(delta: float) -> void:
	if target != null:
		var tp: Vector3 = target.position
		position.x = lerpf(position.x, tp.x, 1.0 - exp(-FOLLOW_XZ * delta))
		position.z = lerpf(position.z, tp.z, 1.0 - exp(-FOLLOW_XZ * delta))
		position.y = lerpf(position.y, tp.y, 1.0 - exp(-FOLLOW_Y * delta))
	# Fixed camera orientation; update only the rig position each frame.

func _update() -> void:
	cam.position = Vector3(0, sin(deg_to_rad(PITCH)) * DISTANCE, cos(deg_to_rad(PITCH)) * DISTANCE)
	cam.look_at(global_position + Vector3(0, 1.0, 0), Vector3.UP)
