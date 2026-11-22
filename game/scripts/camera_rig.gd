extends Node3D
## Изометрическая камера под 60°: один палец двигает, два пальца приближают и вращают.

var pitch := 60.0
var distance := 32.0
var bounds := 200.0
var height_func: Callable
var touches := {}
var last_pinch := 0.0
var last_angle := 0.0
var cam := Camera3D.new()

func _ready() -> void:
	cam.fov = 40.0
	cam.near = 0.5
	cam.far = 400.0
	add_child(cam)
	_update()

func _update() -> void:
	position.x = clampf(position.x, -bounds, bounds)
	position.z = clampf(position.z, -bounds, bounds)
	if height_func.is_valid():
		position.y = height_func.call(position.x, position.z)
	cam.position = Vector3(0, sin(deg_to_rad(pitch)) * distance, cos(deg_to_rad(pitch)) * distance)
	cam.look_at(global_position, Vector3.UP)

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
			var k := distance * 0.0015
			var move := Vector3(-e.relative.x, 0, -e.relative.y) * k
			position += move.rotated(Vector3.UP, rotation.y)
			_update()
		elif touches.size() == 2:
			var p: Array = touches.values()
			var d: float = p[0].distance_to(p[1])
			var a: float = (p[1] - p[0]).angle()
			if last_pinch > 0.0:
				distance = clampf(distance * last_pinch / d, 8.0, 70.0)
			rotation.y -= a - last_angle
			last_pinch = d
			last_angle = a
			_update()
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(8.0, distance * 0.9)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(70.0, distance * 1.1)
		_update()
