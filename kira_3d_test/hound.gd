class_name Hound
extends Node3D
## Гончая бездны: появляется из тьмы у кромки леса, воет, преследует, бьёт лапой и прыгает.

const MODEL := "res://assets/hound.glb"
const SPEED := 4.4
const MAX_HP := 70.0
const SCALE := 1.25

var valley: Valley
var target: Node3D
var main: Node
var anim: AnimationPlayer
var names := {}
var state := "spawn"
var t := 0.0
var hp := MAX_HP
var vel := Vector3.ZERO
var hit_done := false
var cooldown := 1.0
var leap_dir := Vector3.ZERO
var mats: Array[ShaderMaterial] = []
var flash := 0.0
var dissolve := 1.0
var dead := false


func setup(v: Valley, tgt: Node3D, m: Node, pos: Vector3) -> void:
	valley = v
	target = tgt
	main = m
	position = Vector3(pos.x, v.height_at(pos.x, pos.z), pos.z)
	add_to_group("hounds")
	var sc := load(MODEL) as PackedScene
	if sc == null:
		return
	var model := sc.instantiate() as Node3D
	model.scale = Vector3.ONE * SCALE
	add_child(model)
	anim = _find(model, "AnimationPlayer") as AnimationPlayer
	_skin(model)
	if anim != null:
		for n in anim.get_animation_list():
			var key := String(n).to_lower()
			for role in ["idle", "walk", "run", "claw", "leap", "howl", "hurt", "death"]:
				if key.contains(role):
					names[role] = n
					anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR if role in ["idle", "walk", "run"] else Animation.LOOP_NONE
	_to("spawn")


func _find(n: Node, cls: String) -> Node:
	if n.get_class() == cls:
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r != null:
			return r
	return null


func _skin(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for i in range(mi.mesh.get_surface_count()):
			var old := mi.mesh.surface_get_material(i)
			var nm := String(old.resource_name).to_lower() if old != null else ""
			var sm := ShaderMaterial.new()
			if nm.contains("glow"):
				sm.shader = load("res://hound_glow.gdshader")
			elif nm.contains("smoke"):
				sm.shader = load("res://hound_smoke.gdshader")
			else:
				sm.shader = load("res://hound_body.gdshader")
			mi.set_surface_override_material(i, sm)
			mats.append(sm)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if false else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for c in n.get_children():
		_skin(c)


func _set_dissolve(d: float) -> void:
	dissolve = d
	for m in mats:
		m.set_shader_parameter("dissolve", d)


func _to(s: String) -> void:
	state = s
	t = 0.0
	hit_done = false
	var role := s
	match s:
		"spawn": role = "howl"
		"chase": role = "run"
		"windup": role = "idle"
		"dead": role = "death"
	if anim != null and names.has(role):
		anim.play(names[role], 0.12)


func _flat_to_target() -> Vector3:
	var d := target.position - position
	d.y = 0.0
	return d


func _face(d: Vector3, rate: float, delta: float) -> void:
	if d.length_squared() > 0.0001:
		rotation.y = lerp_angle(rotation.y, atan2(d.x, d.z), 1.0 - exp(-rate * delta))


func _fwd() -> Vector3:
	return Vector3(sin(rotation.y), 0.0, cos(rotation.y))


func _move(d: Vector3) -> void:
	var p := valley.move_xz(position, d)
	position.x = p.x
	position.z = p.z
	position.y = lerp(position.y, valley.height_at(p.x, p.z), 0.5)


func take_hit(dmg: float, from: Vector3, power: float) -> void:
	if dead or state == "spawn":
		return
	hp -= dmg
	flash = 1.0
	var dir := position - from
	dir.y = 0.0
	vel = dir.normalized() * power
	if hp <= 0.0:
		dead = true
		remove_from_group("hounds")
		_to("dead")
		main.call("on_hound_killed")
	elif state != "leap":
		_to("hurt")


func _process(delta: float) -> void:
	t += delta
	if flash > 0.0:
		flash = maxf(0.0, flash - delta * 6.0)
		for m in mats:
			m.set_shader_parameter("flash", flash)
	vel = vel.move_toward(Vector3.ZERO, 16.0 * delta)
	if vel.length() > 0.05:
		_move(vel * delta)
	var d := _flat_to_target()
	var dist := d.length()
	cooldown -= delta
	match state:
		"spawn":
			_set_dissolve(clampf(1.0 - t / 0.7, 0.0, 1.0))
			_face(d, 6.0, delta)
			if t >= 1.5:
				_to("chase")
		"chase":
			_face(d, 9.0, delta)
			var sp := SPEED
			_move(d.normalized() * sp * delta * (1.0 if dist > 1.6 else 0.0))
			_separate(delta)
			if anim != null and names.has("run"):
				anim.speed_scale = 1.0
			if dist < 2.2 and cooldown <= 0.0:
				_to("claw")
			elif dist > 4.5 and dist < 8.0 and cooldown <= 0.0 and randf() < delta * 0.9:
				leap_dir = d.normalized()
				_to("leap")
		"claw":
			_face(d, 5.0, delta)
			if not hit_done and t >= 0.45:
				hit_done = true
				if dist < 2.7 and _fwd().dot(d.normalized()) > 0.3:
					main.call("damage_player", 14.0, position)
			if t >= 1.0:
				cooldown = 0.9
				_to("chase")
		"leap":
			if t < 0.45:
				_face(d, 12.0, delta)
				leap_dir = _fwd()
			elif t < 0.95:
				_move(leap_dir * 11.0 * delta)
				if not hit_done and dist < 1.7:
					hit_done = true
					main.call("damage_player", 22.0, position)
			if t >= 1.35:
				cooldown = 1.6
				_to("chase")
		"hurt":
			if t >= 0.4:
				_to("chase")
		"dead":
			_set_dissolve(clampf((t - 0.6) / 0.6, 0.0, 1.0))
			if t >= 1.3:
				queue_free()


func _separate(delta: float) -> void:
	for o in get_tree().get_nodes_in_group("hounds"):
		if o == self:
			continue
		var dd: Vector3 = position - (o as Node3D).position
		dd.y = 0.0
		var l := dd.length()
		if l < 1.6 and l > 0.001:
			_move(dd / l * (1.6 - l) * 3.0 * delta)
