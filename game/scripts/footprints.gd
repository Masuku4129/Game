extends MultiMeshInstance3D
## Следы героя в снегу и грязи: кольцевой буфер плоских отпечатков, тают со временем.

const MAX := 320
var main: Node3D
var ages := PackedFloat32Array()
var life := PackedFloat32Array()
var base_cols := PackedColorArray()
var idx := 0
var _t := 0.0

func _ready() -> void:
	var img := Image.create(32, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 32:
			var u := (x + 0.5) / 32.0 - 0.5
			var v := (y + 0.5) / 64.0
			# носок (широкий овал) и каблук (меньший овал)
			var toe := pow(u / 0.42, 2.0) + pow((v - 0.33) / 0.3, 2.0)
			var heel := pow(u / 0.34, 2.0) + pow((v - 0.8) / 0.16, 2.0)
			var a := clampf(1.0 - minf(toe, heel), 0.0, 1.0)
			a = smoothstep(0.0, 0.35, a)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	var q := QuadMesh.new()
	q.size = Vector2(0.13, 0.3)
	q.orientation = PlaneMesh.FACE_Y
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	q.material = m
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = q
	mm.instance_count = MAX
	ages.resize(MAX)
	life.resize(MAX)
	base_cols.resize(MAX)
	for i in MAX:
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -1000, 0)))
		mm.set_instance_color(i, Color(0, 0, 0, 0))
		ages[i] = 1e9
		life[i] = 1.0
	multimesh = mm
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## Отпечаток стопы в точке p, направление yaw.
func stamp(p: Vector3, yaw: float) -> void:
	var w = main.weather
	var y: float = main.height(p.x, p.z)
	var snow: float = w.snow
	var mud := clampf((main.WATER_Y + 1.3 - y) / 1.3, 0.0, 1.0)
	var wet: float = w.wet
	var col := Color()
	var lf := 0.0
	if snow > 0.25:
		col = Color(0.55, 0.6, 0.72, 0.55 * smoothstep(0.25, 0.6, snow))
		lf = 240.0
	elif (wet > 0.35 or mud > 0.3) and w.temp > 0.0:
		col = Color(0.16, 0.12, 0.09, 0.5 * maxf(wet, mud))
		lf = 160.0
	else:
		return
	var n: Vector3 = main.normal_at(p.x, p.z)
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var right := fwd.cross(n).normalized()
	var f2 := n.cross(right).normalized()
	var b := Basis(right, n, -f2)
	multimesh.set_instance_transform(idx, Transform3D(b, Vector3(p.x, y + 0.025, p.z)))
	multimesh.set_instance_color(idx, col)
	ages[idx] = 0.0
	life[idx] = lf
	base_cols[idx] = col
	idx = (idx + 1) % MAX

func _process(delta: float) -> void:
	_t += delta
	if _t < 0.5:
		return
	var dt := _t
	_t = 0.0
	var w = main.weather
	# снегопад и дождь заметают следы быстрее
	var k: float = 1.0 + w.precip * 4.0
	for i in MAX:
		if ages[i] > life[i]:
			continue
		ages[i] += dt * k
		var c := base_cols[i]
		c.a *= clampf(1.0 - ages[i] / life[i], 0.0, 1.0)
		multimesh.set_instance_color(i, c)
