class_name DashBeam
extends Node3D
## Луч тёмно-фиолетового пламени для рывка.
## Тело луча тянется от точки старта до "головы" (текущей позиции Миты),
## на голове горит сгусток пламени, за ним сыплются языки и искры. После выхода луч гаснет.

const RADIUS := 0.32

var _from := Vector3.ZERO
var _dir := Vector3.FORWARD
var _body: MeshInstance3D
var _core: MeshInstance3D
var _head: MeshInstance3D
var _flames: CPUParticles3D
var _sparks: CPUParticles3D
var _mat_body: ShaderMaterial
var _mat_core: ShaderMaterial


func _soft_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


func _particles(additive: bool, amount: int, life: float, col_a: Color, col_b: Color, size_min: float, size_max: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = RADIUS
	p.direction = Vector3(0, 1, 0)
	p.spread = 180.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 1.4
	p.gravity = Vector3(0, 1.2, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.scale_amount_min = size_min
	p.scale_amount_max = size_max
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.6))
	curve.add_point(Vector2(0.25, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, col_a)
	grad.set_color(1, col_b)
	p.color_ramp = grad
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_texture()
	quad.material = m
	p.mesh = quad
	return p


func _cylinder(mat: ShaderMaterial, r: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 1.0
	cm.radial_segments = 16
	cm.rings = 8
	mi.mesh = cm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func setup(from: Vector3, dir: Vector3) -> void:
	top_level = true
	_from = from
	_dir = dir.normalized()
	var sh := load("res://flame.gdshader") as Shader
	_mat_body = ShaderMaterial.new()
	_mat_body.shader = sh
	_mat_core = ShaderMaterial.new()
	_mat_core.shader = sh
	_mat_core.set_shader_parameter("col_dark", Vector3(0.35, 0.08, 0.75))
	_mat_core.set_shader_parameter("speed", 10.0)
	_body = _cylinder(_mat_body, RADIUS)
	_core = _cylinder(_mat_core, RADIUS * 0.4)
	_head = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = RADIUS * 1.35
	sm.height = RADIUS * 2.7
	_head.mesh = sm
	_head.material_override = _mat_body
	add_child(_head)
	_flames = _particles(false, 90, 0.45, Color(0.30, 0.05, 0.60, 0.85), Color(0.05, 0.0, 0.10, 0.0), 0.35, 0.75)
	_sparks = _particles(true, 40, 0.30, Color(0.85, 0.70, 1.0, 1.0), Color(0.45, 0.15, 0.9, 0.0), 0.06, 0.14)
	add_child(_flames)
	add_child(_sparks)
	set_head(from)


func _place(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var length := maxf(a.distance_to(b), 0.05)
	var up := _dir
	var side := up.cross(Vector3.UP)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	var fwd := side.cross(up).normalized()
	var bs := Basis(side, up * length, fwd)
	mi.global_transform = Transform3D(bs, (a + b) * 0.5)


func set_head(pos: Vector3) -> void:
	_place(_body, _from, pos)
	_place(_core, _from, pos)
	_head.global_position = pos
	_flames.global_position = pos
	_sparks.global_position = pos


func finish() -> void:
	_flames.emitting = false
	_sparks.emitting = false
	var tw := create_tween()
	tw.tween_method(func(f: float) -> void:
		_mat_body.set_shader_parameter("fade", f)
		_mat_core.set_shader_parameter("fade", f), 1.0, 0.0, 0.35)
	tw.tween_interval(0.3)
	tw.tween_callback(queue_free)
