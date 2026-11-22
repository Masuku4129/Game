extends Node3D
## Этап 1: каркас. Свет, небо, туман, рельеф, вода и камера 60° с управлением пальцами.

const SIZE := 240.0
const SEG := 160
const WATER_Y := -1.2

var noise := FastNoiseLite.new()

func _ready() -> void:
	noise.seed = 1640
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	_make_environment()
	_make_terrain()
	_make_water()
	var rig := preload("res://scripts/camera_rig.gd").new()
	add_child(rig)
	var label := Label.new()
	label.text = "Тайга · этап 1: каркас"
	label.position = Vector2(24, 16)
	label.add_theme_font_size_override("font_size", 28)
	label.modulate = Color(1, 1, 1, 0.7)
	var ui := CanvasLayer.new()
	ui.add_child(label)
	add_child(ui)

func height(x: float, z: float) -> float:
	return noise.get_noise_2d(x, z) * 9.0

func _make_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.55, 0.63, 0.70)
	sky_mat.sky_horizon_color = Color(0.74, 0.77, 0.75)
	sky_mat.ground_horizon_color = Color(0.62, 0.64, 0.6)
	sky_mat.ground_bottom_color = Color(0.3, 0.32, 0.28)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.70, 0.74, 0.72)
	env.fog_density = 0.006
	env.fog_sky_affect = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.92, 0.80)
	sun.light_energy = 1.4
	sun.rotation_degrees = Vector3(-38, 35, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)

func _make_terrain() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := SIZE / SEG
	var half := SIZE * 0.5
	var moss := Color(0.33, 0.38, 0.22)
	var dry := Color(0.45, 0.42, 0.30)
	var mud := Color(0.28, 0.25, 0.20)
	for iz in SEG:
		for ix in SEG:
			var quad := [Vector2(ix, iz), Vector2(ix + 1, iz), Vector2(ix, iz + 1), Vector2(ix + 1, iz), Vector2(ix + 1, iz + 1), Vector2(ix, iz + 1)]
			for q in quad:
				var x: float = q.x * step - half
				var z: float = q.y * step - half
				var y := height(x, z)
				var c := moss.lerp(dry, clampf(noise.get_noise_2d(x * 3.0, z * 3.0) * 0.5 + 0.5, 0.0, 1.0) * 0.6)
				if y < WATER_Y + 0.8:
					c = c.lerp(mud, clampf((WATER_Y + 0.8 - y) / 0.8, 0.0, 1.0))
				st.set_color(c)
				st.set_uv(Vector2(x, z) * 0.25)
				st.add_vertex(Vector3(x, y, z))
	st.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	st.set_material(mat)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	add_child(mi)

func _make_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(SIZE, SIZE)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.20, 0.30, 0.30, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.05
	mat.metallic = 0.4
	plane.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.position.y = WATER_Y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
