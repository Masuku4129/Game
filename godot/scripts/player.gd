extends CharacterBody3D

const SPEED=5.0
const GRAVITY=18.0
var joystick_ui:Control
var touch_vector:=Vector2.ZERO
var camera:Camera3D
var walk_phase:=0.0

func _ready() -> void:
	_build_body()
	_build_camera()

func _build_body() -> void:
	var skin:=StandardMaterial3D.new()
	skin.albedo_color=Color(0.66,0.42,0.28)
	var jacket:=StandardMaterial3D.new()
	jacket.albedo_color=Color(0.28,0.25,0.18)
	var pants:=StandardMaterial3D.new()
	pants.albedo_color=Color(0.19,0.21,0.18)
	_add_capsule(Vector3(0,0.92,0),0.26,0.58,jacket)
	_add_sphere(Vector3(0,1.45,0),0.22,skin)
	_add_capsule(Vector3(-0.15,0.48,0),0.10,0.5,pants)
	_add_capsule(Vector3(0.15,0.48,0),0.10,0.5,pants)
	_add_capsule(Vector3(-0.31,0.95,0),0.10,0.46,jacket)
	_add_capsule(Vector3(0.31,0.95,0),0.10,0.46,jacket)
	# Decorative overlapping geometry makes a coherent silhouette with no visible seams.
	for i in range(52):
		var angle=float(i)*TAU/52.0
		var p:=Vector3(cos(angle)*0.12,0.92+sin(angle)*0.16,0.02)
		_add_sphere(p,0.055,jacket)
	var collision:=CollisionShape3D.new()
	var shape:=CapsuleShape3D.new()
	shape.radius=0.26
	shape.height=1.65
	collision.shape=shape
	collision.position.y=0.85
	add_child(collision)

func _add_capsule(pos:Vector3,r:float,h:float,mat:Material)->void:
	var m:=MeshInstance3D.new()
	var mesh:=CapsuleMesh.new()
	mesh.radius=r
	mesh.height=h
	m.mesh=mesh
	m.position=pos
	m.material_override=mat
	add_child(m)

func _add_sphere(pos:Vector3,r:float,mat:Material)->void:
	var m:=MeshInstance3D.new()
	var mesh:=SphereMesh.new()
	mesh.radius=r
	mesh.height=r*2
	m.mesh=mesh
	m.position=pos
	m.material_override=mat
	add_child(m)

func _build_camera()->void:
	camera=Camera3D.new()
	camera.current=true
	camera.position=Vector3(0,12,14)
	camera.rotation_degrees=Vector3(-40,0,0)
	add_child(camera)

func _process(delta:float)->void:
	var move:=Vector2.ZERO
	if joystick_ui:
		move=_read_joystick()
	move.x+=Input.get_action_strength("move_right")-Input.get_action_strength("move_left")
	move.y+=Input.get_action_strength("move_down")-Input.get_action_strength("move_up")
	if move.length()>1: move=move.normalized()
	var dir:=Vector3(move.x,0,move.y)
	velocity.x=dir.x*SPEED
	velocity.z=dir.z*SPEED
	if not is_on_floor(): velocity.y-=GRAVITY*delta
	else: velocity.y=0
	move_and_slide()
	if dir.length()>0.08:
		look_at(global_position+dir,Vector3.UP)
		walk_phase+=delta*9.0
		# Lightweight leg swing for movement feedback.
		if has_node("LegL"): get_node("LegL").rotation.x=sin(walk_phase)*0.35
		if has_node("LegR"): get_node("LegR").rotation.x=-sin(walk_phase)*0.35
	if camera:
		camera.global_position=global_position+Vector3(0,11,13)
		camera.look_at(global_position+Vector3(0,0.7,0),Vector3.UP)

func _read_joystick()->Vector2:
	if not joystick_ui: return Vector2.ZERO
	var viewport_size=joystick_ui.get_viewport_rect().size
	var center=Vector2(155,565)
	var radius=75.0
	var active=Vector2.ZERO
	for i in range(Input.get_touch_count()):
		var touch=Input.get_touch_position(i)
		if touch.distance_to(center)<140 or touch.x<310 and touch.y>420:
			active=(touch-center)/radius
			if active.length()>1:active=active.normalized()
			break
	return active
