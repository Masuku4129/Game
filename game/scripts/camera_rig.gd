extends Node3D
## Изометрическая камера под 60°: следует за героем; палец вне джойстика вращает,
## два пальца приближают и вращают.

var pitch := 60.0
var distance := 13.0
var target: Node3D
var touches := {}
var last_pinch := 0.0
var last_angle := 0.0
var cam := Camera3D.new()

func _ready() -> void:
	cam.fov = 45.0
	cam.near = 0.5
	cam.far = 150.0
	add_child(cam)
	_update()

func _process(delta: float) -> void:
	if target != null:
		position = position.lerp(target.position, 1.0 - exp(-9.0 * delta))
	_update()

func _update() -> void:
	cam.position = Vector3(0, sin(deg_to_rad(pitch)) * distance, cos(deg_to_rad(pitch)) * distance)
	cam.look_at(global_position + Vector3(0, 1.0, 0), Vector3.UP)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			touches[e.index] = e.position
		else:
			touches.erase(e.index)
		if touches.size() == 2:
			var p: Array = touches.values()
			last_pinch = p[0].distance_to(p[1])
			last_angle = (p[1] - p[0]).angle()
	elif e is InputEventScreenDrag:
		touches[e.index] = e.position
		if touches.size() == 1:
			rotation.y -= e.relative.x * 0.006
		elif touches.size() == 2:
			var p: Array = touches.values()
			var d: float = p[0].distance_to(p[1])
			var a: float = (p[1] - p[0]).angle()
			if last_pinch > 0.0:
				distance = clampf(distance * last_pinch / d, 5.0, 22.0)
			rotation.y -= a - last_angle
			last_pinch = d
			last_angle = a
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(5.0, distance * 0.9)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(22.0, distance * 1.1)
