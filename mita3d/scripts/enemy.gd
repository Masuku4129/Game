class_name Enemy
extends Node3D
## Тёмный противник: преследует, замахивается, отлетает от ударов (затухающая скорость).

const K := 4.0                 # затухание отбрасывания: дистанция = v0 / K
var player: Node3D
var arena_r := 7.4
var maxhp := 60.0
var hp := 60.0
var vel := Vector3.ZERO
var stun := 0.0
var wind := 0.0
var cool := 1.5
var burn := 0.0
var dead := false
var body: Node3D
var bar: MeshInstance3D
var mats: Array = []
var flash := 0.0

func _ready() -> void:
	body = Node3D.new()
	add_child(body)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.16, 0.05, 0.12)
	m.emission_enabled = true
	m.emission = Color(0.35, 0.05, 0.2)
	m.emission_energy_multiplier = 0.6
	mats.append(m)
	var cm := CapsuleMesh.new()
	cm.radius = 0.38
	cm.height = 1.7
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = m
	mi.position.y = 0.85
	body.add_child(mi)
	var hm := SphereMesh.new()
	hm.radius = 0.24
	hm.height = 0.48
	var hd := MeshInstance3D.new()
	hd.mesh = hm
	hd.material_override = m
	hd.position.y = 1.85
	body.add_child(hd)
	var em := StandardMaterial3D.new()
	em.albedo_color = Color(1, 0.2, 0.3)
	em.emission_enabled = true
	em.emission = Color(1, 0.15, 0.3)
	em.emission_energy_multiplier = 3.0
	for sx in [-1.0, 1.0]:
		var e := MeshInstance3D.new()
		var es := SphereMesh.new()
		es.radius = 0.05
		es.height = 0.1
		e.mesh = es
		e.material_override = em
		e.position = Vector3(sx * 0.1, 1.88, -0.2)
		body.add_child(e)
	var bm := QuadMesh.new()
	bm.size = Vector2(1.0, 0.09)
	bar = MeshInstance3D.new()
	bar.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.albedo_color = Color(1, 0.3, 0.4)
	bmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bmat.no_depth_test = true
	bar.material_override = bmat
	bar.position.y = 2.35
	add_child(bar)

func hit(dmg: float, dir: Vector3, dist: float, stun_t: float) -> void:
	if dead:
		return
	hp -= dmg
	vel = Vector3(dir.x, 0, dir.z).normalized() * dist * K
	stun = maxf(stun, stun_t)
	wind = 0.0
	flash = 0.12
	if hp <= 0.0:
		dead = true
		var tw := create_tween()
		tw.tween_property(body, "scale", Vector3(1.2, 0.0, 1.2), 0.35)
		tw.parallel().tween_property(bar, "scale", Vector3(0.01, 1, 1), 0.2)
		tw.tween_callback(queue_free)

func _process(dt: float) -> void:
	if dead:
		return
	flash = maxf(0.0, flash - dt)
	for m in mats:
		m.emission_energy_multiplier = 0.6 + (6.0 if flash > 0.0 else 0.0) + (2.0 if wind > 0.0 else 0.0)
	bar.scale.x = maxf(0.01, hp / maxhp)
	if burn > 0.0:
		burn -= dt
		hp -= 6.0 * dt
		if hp <= 0.0:
			hit(0.0, Vector3.ZERO, 0.0, 0.0)
	position += vel * dt
	vel *= exp(-K * dt)
	var p := position
	if p.length() > arena_r:
		position = p.normalized() * arena_r
		vel = Vector3.ZERO
	var to := player.global_position - global_position
	to.y = 0
	var d := to.length()
	if d > 0.01:
		body.rotation.y = lerp_angle(body.rotation.y, atan2(-to.x, -to.z), 10.0 * dt)
	if stun > 0.0:
		stun -= dt
		body.rotation.x = -0.25
		return
	body.rotation.x = 0.0
	if wind > 0.0:
		wind -= dt
		body.rotation.x = 0.35
		if wind <= 0.0:
			body.position = Vector3.ZERO
			if d < 2.1:
				player.take_hit(8.0, global_position)
			cool = 2.0 + randf()
		return
	if d > 1.7:
		position += to / d * 2.2 * dt
	else:
		cool -= dt
		if cool <= 0.0:
			wind = 0.5
