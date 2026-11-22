extends Node3D
## Пробная сцена живописного стиля: участок 140×140 м с рекой, лесом, поляной и камнями.
## Снимает кадры с нескольких точек (камера 60°) в папку SHOTS и выходит.

const W := 140.0
const WATER_Y := -1.0
var pv = preload("res://scripts/pveg.gd").new()
var n_h := FastNoiseLite.new()
var n_f := FastNoiseLite.new()
var cam: Camera3D
var hero: Node3D
var tuft_mat: ShaderMaterial
var shots := [
	[Vector3(4, 0, 6), 14.0, 20.0, "1_polyana"],
	[Vector3(-2, 0, -30), 14.0, 160.0, "2_reka"],
	[Vector3(30, 0, 22), 14.0, 250.0, "3_les"],
	[Vector3(4, 0, 6), 22.0, 60.0, "4_daleko"],
]
var shot_i := 0
var wait := 0

func height(x: float, z: float) -> float:
	var h := n_h.get_noise_2d(x, z) * 5.0
	# русло реки поперёк участка
	var rz := -30.0 + sin(x * 0.04) * 8.0
	var d := absf(z - rz)
	h = lerpf(WATER_Y - 1.4, h, smoothstep(4.0, 11.0, d))
	if d >= 11.0:
		h = maxf(h, WATER_Y + 0.5)
	return h

func density(x: float, z: float) -> float:
	return clampf(n_f.get_noise_2d(x, z) * 1.6 + 0.45 + (0.35 if x > 15.0 else -0.1), 0.0, 1.0)

func _ready() -> void:
	n_h.seed = 3
	n_h.frequency = 0.02
	n_h.fractal_octaves = 3
	n_f.seed = 9
	n_f.frequency = 0.03
	_env()
	_ground()
	_water()
	_scatter()
	hero = preload("res://scripts/hero.gd").new()
	add_child(hero)
	cam = Camera3D.new()
	cam.fov = 45.0
	cam.far = 200.0
	add_child(cam)
	cam.current = true

func _env() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.55, 0.78)
	sky_mat.sky_horizon_color = Color(0.74, 0.8, 0.82)
	sky_mat.ground_horizon_color = Color(0.6, 0.66, 0.6)
	sky_mat.ground_bottom_color = Color(0.3, 0.36, 0.3)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.8, 0.84)
	env.fog_density = 0.006
	env.fog_sun_scatter = 0.25
	env.fog_aerial_perspective = 0.4
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.04
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.92, 0.78)
	sun.light_energy = 1.25
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.shadow_enabled = true
	sun.shadow_blur = 2.5
	sun.directional_shadow_max_distance = 40.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(sun)

func _ground() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 140
	var step := W / n
	for z in n + 1:
		for x in n + 1:
			var px := -W * 0.5 + x * step
			var pz := -W * 0.5 + z * step
			var e := 0.5
			var nrm := Vector3(height(px - e, pz) - height(px + e, pz), 2.0 * e, height(px, pz - e) - height(px, pz + e)).normalized()
			st.set_color(Color(density(px, pz), 0, 0, 1))
			st.set_normal(nrm)
			st.add_vertex(Vector3(px, height(px, pz), pz))
	for z in n:
		for x in n:
			var a := z * (n + 1) + x
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + n + 1)
			st.add_index(a + 1)
			st.add_index(a + n + 2)
			st.add_index(a + n + 1)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/paint/ground.gdshader")
	m.set_shader_parameter("water_y", WATER_Y)
	mi.material_override = m
	add_child(mi)

func _water() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(W, 40)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/paint/water.gdshader")
	mi.material_override = m
	mi.position = Vector3(0, WATER_Y, -30)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _place(meshes: Array, xs: Array, shadow: bool) -> void:
	var per: Array = []
	for m in meshes:
		per.append([])
	for t in xs:
		per[randi() % meshes.size()].append(t)
	for i in meshes.size():
		if per[i].is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[i][0]
		mm.instance_count = per[i].size()
		for k in per[i].size():
			mm.set_instance_transform(k, per[i][k])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)

func _scatter() -> void:
	seed(5)
	var sp := []
	var pn := []
	var bi := []
	var bu := []
	var rk := []
	var tf := []
	var spr := [pv.spruce(1), pv.spruce(2), pv.spruce(3)]
	var pin := [pv.pine(11), pv.pine(12)]
	var bir := [pv.birch(21), pv.birch(22), pv.birch(23, "leaf")]
	var bus := [pv.bush(31), pv.bush(32)]
	var roc := [pv.rock(41), pv.rock(42), pv.rock(43), pv.rock(44)]
	var tuf := [pv.tuft(51), pv.tuft(52), pv.tuft(53, 1.4)]
	for i in 2600:
		var x := randf_range(-W * 0.5, W * 0.5)
		var z := randf_range(-W * 0.5, W * 0.5)
		var y := height(x, z)
		if y < WATER_Y + 0.3:
			continue
		var d := density(x, z)
		var r := randf()
		var b := Basis(Vector3.UP, randf() * TAU)
		if r < d * 0.09:
			var s := randf_range(0.8, 1.2)
			var k := randf()
			var t := Transform3D(b.scaled(Vector3(s, s, s)), Vector3(x, y - 0.1, z))
			if k < 0.55:
				sp.append(t)
			elif k < 0.75:
				pn.append(t)
			else:
				bi.append(t)
		elif r < 0.12 + d * 0.06 and r > 0.1:
			bu.append(Transform3D(b.scaled(Vector3.ONE * randf_range(0.7, 1.4)), Vector3(x, y, z)))
		elif r > 0.985:
			rk.append(Transform3D(b.scaled(Vector3.ONE * randf_range(0.4, 2.5)), Vector3(x, y - 0.1, z)))
	# камни у реки
	for i in 50:
		var x := randf_range(-W * 0.5, W * 0.5)
		var z := -30.0 + sin(x * 0.04) * 8.0 + randf_range(-9.0, 9.0)
		rk.append(Transform3D(Basis(Vector3.UP, randf() * TAU).scaled(Vector3.ONE * randf_range(0.3, 1.6)), Vector3(x, height(x, z) - 0.1, z)))
	# кочки травы: гуще на поляне, редко в лесу
	for i in 9000:
		var x := randf_range(-W * 0.5, W * 0.5)
		var z := randf_range(-W * 0.5, W * 0.5)
		var y := height(x, z)
		if y < WATER_Y + 0.15:
			continue
		if randf() > (1.0 - density(x, z)) * 0.9 + 0.08:
			continue
		var s := randf_range(0.7, 1.5)
		tf.append(Transform3D(Basis(Vector3.UP, randf() * TAU).scaled(Vector3(s, s * randf_range(0.8, 1.3), s)), Vector3(x, y - 0.02, z)))
	_place(spr, sp, true)
	_place(pin, pn, true)
	_place(bir, bi, true)
	_place(bus, bu, true)
	_place(roc, rk, true)
	_place(tuf, tf, false)

func _process(_d: float) -> void:
	if shot_i >= shots.size():
		get_tree().quit()
		return
	var s: Array = shots[shot_i]
	var p: Vector3 = s[0]
	p.y = height(p.x, p.z)
	hero.position = p
	var dist: float = s[1]
	var yaw := deg_to_rad(float(s[2]))
	var pitch := deg_to_rad(60.0)
	cam.position = p + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	cam.look_at(p + Vector3(0, 1.0, 0), Vector3.UP)
	wait += 1
	if wait < 8:
		return
	wait = 0
	var dir := OS.get_environment("SHOTS")
	if dir == "":
		dir = "user://"
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir + "/" + str(s[3]) + ".png")
	print("shot ", s[3], " FPS est ", Engine.get_frames_per_second(), " tris ", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	shot_i += 1
