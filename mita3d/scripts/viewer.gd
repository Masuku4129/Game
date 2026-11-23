extends Node3D
## Просмотр модели с разных сторон + ракурс игровой камеры (45° сверху). Сохраняет PNG в out=.

var out := "/tmp/m3d"
var model: MitaModel
var cam: Camera3D
var shots := [
	["front", Vector3(0, 0.95, -4.2), Vector3(0, 0.88, 0)],
	["side", Vector3(4.2, 0.95, 0), Vector3(0, 0.88, 0)],
	["back", Vector3(0, 0.95, 4.2), Vector3(0, 0.88, 0)],
	["three_q", Vector3(-3.0, 1.6, -3.0), Vector3(0, 0.85, 0)],
	["game45", Vector3(0, 5.2, -5.2), Vector3(0, 0.6, 0)],
	["face", Vector3(0.5, 1.7, -1.6), Vector3(0, 1.58, 0)],
]
var i := 0
var wait := 0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(out)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.1, 0.3)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.38, 0.8)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(0.6, 0.65, 1.0)
	sun.light_energy = 0.9
	sun.rotation_degrees = Vector3(-40, 150, 0)
	add_child(sun)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	fl.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.1, 0.09, 0.22)
	fl.material_override = fm
	add_child(fl)
	model = MitaChar.new()
	add_child(model)
	cam = Camera3D.new()
	cam.fov = 30.0
	add_child(cam)
	cam.make_current()

func _process(_dt: float) -> void:
	if i >= shots.size():
		get_tree().quit()
		return
	var s: Array = shots[i]
	cam.position = s[1]
	cam.look_at(s[2], Vector3.UP)
	wait += 1
	if wait == 4:
		get_viewport().get_texture().get_image().save_png("%s/%d_%s.png" % [out, i, s[0]])
		i += 1
		wait = 0
