extends CharacterBody2D
## Враг «чужище»/«стрелок»/«гончая»: спрайты GPT, ИИ и анимация позами (покачивание, наклон, вспышка урона).

const DATA = preload("res://art/valley/art_data.gd").DATA
const Y_SCALE := 0.75
const STRIP_FRAMES := 8   # кадров в стрипе

var kind := "ch"            # ch ближний, sh дальнобойный, hd босс, wr призрак
var hp := 60.0
var max_hp := 60.0
var speed := 105.0
var sc := 0.82
var aggro := 700.0
var dmg := 10.0
var reach := 120.0
var dead := false
var player
var _state := "idle"
var _t := 0.0
var _cd := 0.0
var _kb := Vector2.ZERO
var _wt := randf() * 6.0
var _face := 1.0
var _view := "side"
var _spr: Sprite2D
var _sh: Sprite2D
var _flash := 0.0
var _hit_done := false
var _tex := {}


func setup(k: String) -> void:
	kind = k
	match k:
		"ch":
			hp = 60.0; speed = 115.0; sc = 0.82; dmg = 9.0; reach = 115.0
		"sh":
			hp = 38.0; speed = 95.0; sc = 0.78; dmg = 8.0; reach = 520.0
		"hd":
			hp = 900.0; speed = 190.0; sc = 0.78; dmg = 22.0; reach = 260.0; aggro = 1500.0
		"wr":
			hp = 50.0; speed = 80.0; sc = 0.80; dmg = 12.0; reach = 450.0; aggro = 600.0
	max_hp = hp


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	add_to_group("enemy")
	var c := CollisionShape2D.new()
	var s := CircleShape2D.new()
	s.radius = 70.0 if kind == "hd" else (28.0 if kind == "wr" else 22.0)
	c.shape = s
	add_child(c)
	var g := Gradient.new()
	g.set_color(0, Color(0.06, 0.04, 0.14, 0.5))
	g.set_color(1, Color(0.06, 0.04, 0.14, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128
	gt.height = 128
	_sh = Sprite2D.new()
	_sh.texture = gt
	var w := (420.0 if kind == "hd" else (110.0 if kind == "wr" else 90.0))
	_sh.scale = Vector2(w / 64.0, w * 0.3 / 64.0)
	add_child(_sh)
	_spr = Sprite2D.new()
	_spr.centered = false
	_spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_spr)
	var all_poses := ["side","front","back","windup","strike","hit","crouch","death",
		"charge","shoot","recoil","run","run2","run3","leap","paw","howl","walk",
		"spin","claw","cast","throw","death"]
	for n in all_poses:
		var p := "res://art/en/%s_%s.png" % [kind, n]
		if ResourceLoader.exists(p):
			var t: Texture2D = load(p)
			_tex[n] = t
	# определяем стартовую позу
	var start_pose := "walk" if _tex.has("walk") else ("run" if _tex.has("run") else "side")
	_pose(start_pose)


func _pose(n: String, frame: int = 0) -> void:
	var key := "en_%s_%s" % [kind, n]
	if not _tex.has(n) or not DATA.has(key):
		return
	var d: Array = DATA[key]
	var t: Texture2D = _tex[n]
	if _spr.texture != t:
		_spr.texture = t
		# стрип — ширина в 8 раз больше высоты → используем hframes
		if t.get_width() > t.get_height() * 2:
			_spr.hframes = STRIP_FRAMES
			_spr.vframes = 1
		else:
			_spr.hframes = 1
			_spr.vframes = 1
	_spr.frame = clampi(frame, 0, _spr.hframes - 1)
	_spr.offset = Vector2(-d[0], -d[1])


func hurt(amount: float, from_dir: Vector2, knock := 260.0) -> void:
	if dead:
		return
	hp -= amount
	_flash = 0.14
	_kb = from_dir.normalized() * knock * (0.25 if kind == "hd" else 1.0)
	if hp <= 0.0:
		dead = true
		_t = 0.0
		collision_layer = 0
		_pose("death" if _tex.has("death") else "side", 0)
		var main = get_tree().current_scene
		if main.has_method("on_kill"):
			main.on_kill(kind)
	elif kind != "hd":
		_state = "hit"
		_t = 0.0
		_hit_done = true
		_pose("hit" if _tex.has("hit") else "side")


func _physics_process(delta: float) -> void:
	_wt += delta
	_flash = maxf(_flash - delta, 0.0)
	_spr.modulate = Color(1.7, 1.45, 1.9) if _flash > 0.0 else Color.WHITE
	if dead:
		_t += delta
		_spr.modulate.a = clampf(1.0 - (_t - 0.6) / 0.8, 0.0, 1.0)
		# прокручиваем кадры смерти
		if _spr.hframes > 1:
			var df := clampi(int(_t / 0.8 * STRIP_FRAMES), 0, STRIP_FRAMES - 1)
			_spr.frame = df
		_spr.scale = Vector2(_face * sc, sc)
		_sh.modulate.a = _spr.modulate.a
		if _t > 1.5:
			queue_free()
		return
	if player == null:
		var ps := get_tree().get_nodes_in_group("player")
		if ps.size() > 0:
			player = ps[0]
		return
	_t += delta
	_cd = maxf(_cd - delta, 0.0)
	var to: Vector2 = player.global_position - global_position
	var dist := Vector2(to.x, to.y / Y_SCALE).length()
	var dir := to.normalized()
	var move := Vector2.ZERO
	match _state:
		"idle":
			if dist < aggro:
				_state = "chase"
		"chase":
			move = _chase(dist, dir, to)
		"windup":
			_face = 1.0 if to.x >= 0.0 else -1.0
			var wu_dur := 0.55 if kind == "wr" else 0.42
			var cast_frame := int(_t / wu_dur * STRIP_FRAMES) % STRIP_FRAMES
			if kind == "wr":
				_pose("cast", cast_frame)
			if _t > wu_dur:
				_state = "strike"
				_t = 0.0
				_hit_done = false
				if kind == "sh":
					_pose("shoot")
					_fire(dir)
				elif kind == "wr":
					_pose("throw", 0)
					_fire_orb(dir)
				else:
					_pose("strike")
		"strike":
			if kind == "ch":
				move = dir * 330.0
				if not _hit_done and _t > 0.06 and dist < reach + 40.0:
					_hit_done = true
					player.hurt(dmg, global_position)
			if kind == "wr":
				var throw_frame := int(_t / 0.4 * STRIP_FRAMES) % STRIP_FRAMES
				_pose("throw", throw_frame)
			var str_dur := 0.4 if kind == "wr" else (0.22 if kind == "ch" else 0.3)
			if _t > str_dur:
				_state = "chase"
				_cd = (2.8 if kind == "wr" else (1.4 if kind == "ch" else 2.2))
				_t = 0.0
		"hit":
			if _t > 0.28:
				_state = "chase"
				_t = 0.0
	velocity = move + _kb
	_kb = _kb.move_toward(Vector2.ZERO, 900.0 * delta)
	velocity.y *= Y_SCALE
	move_and_slide()
	_animate(move)


func _chase(dist: float, dir: Vector2, to: Vector2) -> Vector2:
	if kind == "sh":
		if dist < reach and _cd <= 0.0:
			_state = "windup"
			_t = 0.0
			_pose("charge")
			return Vector2.ZERO
		if dist < 330.0:
			return -dir * speed
		if dist > 480.0:
			return dir * speed
		return Vector2(-dir.y, dir.x) * speed * 0.5
	if kind == "wr":
		# держится на дистанции, стреляет орбами
		if dist < reach and _cd <= 0.0:
			_state = "windup"
			_t = 0.0
			_face = 1.0 if to.x >= 0.0 else -1.0
			_pose("cast", 0)
			return Vector2.ZERO
		if dist < 200.0:
			return -dir * speed  # убегает если слишком близко
		if dist > reach * 0.8:
			return dir * speed * 0.6
		return Vector2(-dir.y, dir.x) * speed * 0.4  # кружит
	if dist < reach and _cd <= 0.0:
		_state = "windup"
		_t = 0.0
		_pose("windup")
		return Vector2.ZERO
	return dir * speed if dist > reach * 0.8 else Vector2.ZERO


func _fire(dir: Vector2) -> void:
	var p = preload("res://orb.gd").new()
	p.position = global_position + Vector2(_face * 28.0, -85.0)
	p.vel = (player.global_position + Vector2(0, -50.0) - p.position).normalized() * 300.0
	p.dmg = dmg
	get_parent().add_child(p)


func _fire_orb(dir: Vector2) -> void:
	# призрак выпускает 2 орба веером
	var orb_positions := [Vector2(_face * 20.0, -110.0), Vector2(_face * 40.0, -90.0)]
	var angles := [-0.15, 0.15]
	for i in 2:
		var p = preload("res://orb.gd").new()
		p.position = global_position + orb_positions[i]
		var base_dir := (player.global_position + Vector2(0, -50.0) - p.position).normalized()
		var rotated := base_dir.rotated(angles[i])
		p.vel = rotated * 260.0
		p.dmg = dmg
		get_parent().add_child(p)


func _animate(move: Vector2) -> void:
	var sp := move.length() > 5.0
	# кадр анимации (для стрипов)
	var run_frame := int(_wt * 8.0) % STRIP_FRAMES
	var walk_frame := int(_wt * 6.0) % STRIP_FRAMES

	if _state == "chase" or _state == "idle":
		if sp:
			if absf(move.x) > absf(move.y) * 1.2:
				_face = 1.0 if move.x > 0 else -1.0
				if kind == "wr":
					_view = "side" if _tex.has("side") else "walk"
					_pose(_view, walk_frame)
				elif _tex.has("run"):
					_view = "run"
					_pose("run", run_frame)
				else:
					_view = "side"
					_pose("side", run_frame)
			elif move.y > 0:
				_view = "front"
				_pose("front", walk_frame)
			else:
				_view = "back"
				_pose("back" if _tex.has("back") else "side", walk_frame)
		else:
			if _view in ["run", "run2", "run3"]:
				_view = "side" if _tex.has("side") else "walk"
			var idle_frame := int(_wt * 4.0) % STRIP_FRAMES
			_pose(_view, idle_frame)

	var sx := _face if (_view in ["side","run","run2","run3","walk"]) else 1.0
	# плавный наклон при движении
	var tilt := sin(_wt * 9.0) * 0.055 * sx if sp else 0.0
	var squash := 1.0 + (sin(_wt * 18.0) * 0.03 if sp else sin(_wt * 2.5) * 0.012)
	var bob := absf(sin(_wt * 9.0)) * 4.0 if sp else sin(_wt * 2.0) * 1.5
	_spr.scale = Vector2(sx * sc / squash, sc * squash)
	_spr.rotation = tilt
	_spr.position.y = -bob
