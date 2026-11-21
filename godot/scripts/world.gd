extends Node3D

const PLAYER_SCRIPT = preload("res://scripts/player.gd")
const TREE_SCRIPT = preload("res://scripts/tree.gd")

var player: CharacterBody3D
var weather_timer := 0.0
var weather_phase := 0
var rain_particles: GPUParticles3D
var sky_material: ProceduralSkyMaterial
var weather_label: Label

func _ready() -> void:
	_setup_environment()
	_create_ground()
	_spawn_forest()
	_create_player()
	_create_ui()
	_change_weather(0)

func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_material = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.23, 0.43, 0.66)
	sky_material.sky_horizon_color = Color(0.73, 0.78, 0.79)
	sky.sky_material = sky_material
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.69, 0.76, 0.73)
	env.fog_density = 0.006
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -28, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)

func _create_ground() -> void:
	var ground := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(220, 220)
	ground.mesh = mesh
	ground.rotation_degrees.x = 0
	ground.position.y = -0.08
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.20, 0.28, 0.18)
	mat.roughness = 1.0
	ground.material_override = mat
	add_child(ground)
	var floor_body := StaticBody3D.new()
	floor_body.name = "GroundCollision"
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(220, 0.2, 220)
	floor_shape.shape = floor_box
	floor_shape.position.y = -0.18
	floor_body.add_child(floor_shape)
	add_child(floor_body)
	# A subtle patchwork of broad, overlapping natural color layers avoids hard tile seams.
	for i in range(48):
		var patch := MeshInstance3D.new()
		var pmesh := SphereMesh.new()
		pmesh.radius = randf_range(2.5, 8.0)
		pmesh.height = pmesh.radius * 0.12
		patch.mesh = pmesh
		patch.scale = Vector3(1.0, 0.25, randf_range(0.7, 1.6))
		patch.position = Vector3(randf_range(-95,95), -0.025, randf_range(-95,95))
		var pm := StandardMaterial3D.new()
		pm.albedo_color = [Color(0.18,0.26,0.16),Color(0.24,0.31,0.19),Color(0.28,0.32,0.20),Color(0.16,0.23,0.15)][randi()%4]
		pm.roughness=1.0
		patch.material_override=pm
		add_child(patch)

func _spawn_forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	# Create dense but navigable forest; central clearing around the player.
	for i in range(270):
		var pos := Vector3(rng.randf_range(-96,96),0,rng.randf_range(-96,96))
		if pos.length() < 9.0: continue
		var tree := Node3D.new()
		tree.set_script(TREE_SCRIPT)
		tree.position = pos
		tree.scale = Vector3.ONE * rng.randf_range(0.75,1.35)
		tree.set("seed_value", rng.randi())
		add_child(tree)
	# Bushes, rocks, ground clutter spread through the clear areas too.
	for i in range(210):
		var pos := Vector3(rng.randf_range(-96,96),0,rng.randf_range(-96,96))
		var shrub := _make_shrub(rng)
		shrub.position = pos
		add_child(shrub)

func _make_shrub(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var base_color: Color = [Color(0.13,0.28,0.12),Color(0.18,0.33,0.15),Color(0.24,0.38,0.18)][rng.randi_range(0,2)]
	for j in range(6):
		var b := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = rng.randf_range(0.22,0.38)
		mesh.height = mesh.radius*2.0
		b.mesh=mesh
		b.position=Vector3(rng.randf_range(-0.35,0.35),rng.randf_range(0.18,0.48),rng.randf_range(-0.35,0.35))
		b.scale=Vector3(1.0, rng.randf_range(0.8,1.3),1.0)
		var m:=StandardMaterial3D.new()
		m.albedo_color=base_color.lightened(rng.randf_range(0.0,0.16))
		m.roughness=1.0
		b.material_override=m
		root.add_child(b)
	return root

func _create_player() -> void:
	player=CharacterBody3D.new()
	player.set_script(PLAYER_SCRIPT)
	player.name="Player"
	add_child(player)
	player.position=Vector3(0,0.0,0)

func _create_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	var pad := TouchScreenButton.new()
	pad.name="MovePad"
	pad.position=Vector2(60,480)
	pad.custom_minimum=Vector2(180,180)
	pad.texture_normal=null
	pad.texture_pressed=null
	root.add_child(pad)
	var panel := Panel.new()
	panel.position=Vector2(20,430)
	panel.size=Vector2(280,260)
	panel.modulate=Color(0.16,0.2,0.15,0.5)
	root.add_child(panel)
	var title:=Label.new()
	title.text="MOVE"
	title.position=Vector2(115,540)
	title.add_theme_font_size_override("font_size",24)
	root.add_child(title)
	weather_label=Label.new()
	weather_label.position=Vector2(24,24)
	weather_label.add_theme_font_size_override("font_size",26)
	root.add_child(weather_label)
	var weather_button:=Button.new()
	weather_button.text="WEATHER"
	weather_button.position=Vector2(1040,30)
	weather_button.size=Vector2(190,64)
	weather_button.add_theme_font_size_override("font_size",24)
	weather_button.pressed.connect(_next_weather)
	root.add_child(weather_button)
	var joy:=Control.new()
	joy.name="TouchJoystick"
	joy.set_script(preload("res://scripts/joystick.gd"))
	joy.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(joy)
	player.set("joystick_ui",joy)

func _process(delta: float) -> void:
	weather_timer += delta
	if weather_timer > 65.0:
		weather_timer=0.0
		_next_weather()

func _next_weather() -> void:
	weather_phase=(weather_phase+1)%4
	_change_weather(weather_phase)

func _change_weather(phase:int) -> void:
	var env=get_node("WorldEnvironment").environment
	if rain_particles:
		rain_particles.queue_free()
		rain_particles=null
	match phase:
		0:
			weather_label.text="CLEAR · DAY"
			env.fog_density=0.004
			sky_material.sky_top_color=Color(0.23,0.43,0.66)
			sky_material.sky_horizon_color=Color(0.73,0.78,0.79)
		1:
			weather_label.text="CLOUDY"
			env.fog_density=0.008
			sky_material.sky_top_color=Color(0.34,0.39,0.45)
			sky_material.sky_horizon_color=Color(0.60,0.63,0.65)
		2:
			weather_label.text="RAIN"
			env.fog_density=0.015
			sky_material.sky_top_color=Color(0.19,0.24,0.29)
			sky_material.sky_horizon_color=Color(0.42,0.47,0.50)
			_make_rain()
		3:
			weather_label.text="FOG"
			env.fog_density=0.035
			sky_material.sky_top_color=Color(0.54,0.59,0.61)
			sky_material.sky_horizon_color=Color(0.67,0.71,0.71)

func _make_rain() -> void:
	rain_particles=GPUParticles3D.new()
	rain_particles.amount=650
	rain_particles.lifetime=1.4
	rain_particles.position=Vector3(0,12,0)
	rain_particles.emitting=true
	rain_particles.visibility_aabb=AABB(Vector3(-24,-2,-24),Vector3(48,24,48))
	var process:=ParticleProcessMaterial.new()
	process.gravity=Vector3(0,-22,0)
	process.initial_velocity_min=18
	process.initial_velocity_max=25
	process.scale_min=0.035
	process.scale_max=0.07
	process.emission_shape=ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents=Vector3(20,8,20)
	rain_particles.process_material=process
	var quad:=QuadMesh.new()
	quad.size=Vector2(0.04,0.6)
	var mat:=StandardMaterial3D.new()
	mat.albedo_color=Color(0.55,0.65,0.75,0.55)
	mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material=mat
	rain_particles.draw_pass_1=quad
	add_child(rain_particles)
