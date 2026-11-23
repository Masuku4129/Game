extends CharacterBody2D
## Мита: нарисованные спрайты.
## Движение: 8 направлений (5 видов + зеркало), покадровая ходьба сбоку, спереди, сзади.
## Бой: комбо из трёх ударов и рывок, кадры из art/anim, эффекты из art/vfx.
## Точка опоры каждого спрайта = центр стоп (art/sprite_data.gd, art/anim/anim_data.gd).

const ATK := preload("res://art/atk/atk_data.gd")
const M2 = preload("res://art/m2/m2_data.gd").DATA   # новые кадры вида сбоку (ходьба, ожидание, бой, рывок, урон, смерть)
# комбо вида сбоку: кадров, к/с, кадр взмаха, кадр попадания, рывок вперёд с-по, кадр для следующего удара
const A2 := [
	{"n": 12, "fps": 24.0, "slash": 6, "hit": 8, "l0": 6, "l1": 9, "q": 10},
	{"n": 11, "fps": 26.0, "slash": 5, "hit": 7, "l0": 5, "l1": 8, "q": 9},
	{"n": 11, "fps": 20.0, "slash": 2, "hit": 3, "l0": 2, "l1": 8, "q": 8}]

const SPEED := 230.0
const Y_SCALE := 0.75        # вертикальная скорость меньше (перспектива)
const DRAW_SCALE := 0.375    # спрайт 320 px -> 120 единиц мира
const WALK_FPS := 8.0
const ATTACK_FPS := [48.0, 57.0, 42.0]   # скорость ударов 1-3, кадров в секунду (24 кадра на удар)
const DASH_FPS := 20.0
const DASH_SPEED := 460.0
const DASH_FRAMES := [2, 3, 3, 3, 4, 5]  # кадры листа удара, которые играют в рывке

# сектор (0=вправо, по часовой на экране) -> [вид, зеркалить]
const SECTORS := [
	["e", false], ["se", false], ["s", false], ["se", true],
	["e", true], ["ne", true], ["n", false], ["ne", false]]
const WALK_SETS := ["e", "s", "n"]   # для этих видов есть кадры ходьбы

var stick                       # джойстик, выставляется из main.gd
var lift_fn := Callable()       # высота пола под ногами (лестницы, терраса)
var _lift := 0.0
var _holder: Node2D
var world_radius := 2400.0
var debug := false              # для кадров предпросмотра: поза задаётся вручную
var attack_requested := false
var dash_requested := false

var _state := "move"            # move / attack / dash
var _sector := 2
var _moving := false
var _wt := 0.0                  # фаза кадров ходьбы
var _bob_t := 0.0               # фаза подпрыгивания (диагонали)
var _amp := 0.0
var _idle_t := 0.0
var _face_x := 1.0              # куда смотрит в бою: 1 вправо, -1 влево
var _row := 0
var _af := 0.0                  # кадр анимации боя (дробный)
var _combo := 0
var _queued := false
var _vfx_done := false
var _hit_done := false
var _hold := 0.0               # остановка кадра в момент удара
var _shake := 0.0
var _punch := 0.0
var _ghost_t := 0.0
var _dash_dir := Vector2.RIGHT
var _spr: Sprite2D
var _tex := {}
var hp := 100.0
var max_hp := 100.0
var _inv := 0.0
var spawn_pos := Vector2.ZERO
var next_hits_fly := 0   # активное умение: сколько ударов выпускают летящие шлейфы
var _data := {}
var _m2tex := {}
var _hurt_t := 0.0
var _atex := {}                 # вид -> [Texture2D x8]


func _ready() -> void:
	add_to_group("player")
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = 10.0
	cs.shape = sh
	add_child(cs)

	_data = preload("res://art/sprite_data.gd").DATA
	for n in _data:
		_tex[n] = load("res://art/%s.png" % n)
	for v in ATK.DATA:
		var r := []
		for f in ATK.DATA[v]["frames"]:
			r.append(load("res://art/atk/" + f[0]))
		_atex[v] = r

	for n in M2:
		_m2tex[n] = load("res://art/m2/%s.png" % n)

	_holder = Node2D.new()
	add_child(_holder)
	_spr = Sprite2D.new()
	_spr.centered = false
	_spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_holder.add_child(_spr)
	_refresh()


func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo:
		if k.keycode == KEY_J:
			attack_requested = true
		elif k.keycode == KEY_K:
			dash_requested = true


func set_pose(sector: int, moving: bool, wt: float) -> void:
	debug = true
	_state = "move"
	_sector = sector
	_moving = moving
	_wt = wt
	_bob_t = wt
	_amp = 1.0 if moving else 0.0
	_refresh()


func set_attack_pose(sector: int, frame: int) -> void:
	debug = true
	_state = "attack"
	_sector = sector
	_af = float(frame)
	_refresh()


func _physics_process(delta: float) -> void:
	_inv = maxf(_inv - delta, 0.0)
	_hurt_t = maxf(_hurt_t - delta, 0.0)
	if _spr:
		_spr.modulate = Color(1.0, 0.7, 0.75) if (_inv > 0.0 and int(_inv * 20.0) % 2 == 0 and _state != "dead") else Color.WHITE
	if not debug:
		match _state:
			"attack":
				_tick_attack(delta)
			"dash":
				_tick_dash(delta)
			"dead":
				_tick_dead(delta)
			_:
				_tick_move(delta)
		_refresh()
	if lift_fn.is_valid():
		_lift = lift_fn.call(global_position)
	_holder.position.y = -_lift
	var cam := get_viewport().get_camera_2d()
	if cam:
		_shake = move_toward(_shake, 0.0, delta * 60.0)
		cam.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake
		if not debug:
			_punch = move_toward(_punch, 0.0, delta * 4.0)
			cam.zoom = Vector2.ONE * (1.0 + _punch * 0.07)
	queue_redraw()


# ---------------------------------------------------------------- движение

func _input_dir() -> Vector2:
	var dir := Vector2.ZERO
	if stick:
		dir = stick.value
	var k := Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))
	if k != Vector2.ZERO:
		dir = k.normalized()
	return dir


func _tick_move(delta: float) -> void:
	var dir := _input_dir()
	if attack_requested:
		attack_requested = false
		dash_requested = false
		_combo = 0
		_start_attack()
		return
	if dash_requested:
		dash_requested = false
		_start_dash(dir)
		return

	velocity = Vector2(dir.x, dir.y * Y_SCALE) * SPEED
	move_and_slide()
	_clamp_world()

	_moving = dir.length() > 0.05
	if _moving:
		_sector = posmod(roundi(dir.angle() / (PI / 4.0)), 8)
		if absf(dir.x) > 0.25:
			_face_x = signf(dir.x)
		_wt += delta * WALK_FPS
		_bob_t += delta * 11.0
	_amp = move_toward(_amp, 1.0 if _moving else 0.0, delta * 8.0)
	_idle_t += delta * 2.0


func _clamp_world() -> void:
	if position.length() > world_radius:
		position = position.normalized() * world_radius


# ---------------------------------------------------------------- бой

func _aim_vec(sector: int) -> Vector2:
	var a := sector * PI / 4.0
	return Vector2(cos(a), sin(a) * Y_SCALE)


func _start_attack() -> void:
	var dir := _input_dir()
	if dir.length() > 0.3:
		_sector = posmod(roundi(dir.angle() / (PI / 4.0)), 8)
	_state = "attack"
	_row = _combo
	_af = 0.0
	_queued = false
	_vfx_done = false
	_hit_done = false


func _is_side() -> bool:
	return SECTORS[_sector][0] == "e"


func _atk_spec() -> Dictionary:
	if _is_side():
		return A2[_combo]
	var key: Array = ATK.DATA[SECTORS[_sector][0]]["key"]
	return {"n": 24, "fps": ATTACK_FPS[_combo], "slash": key[3], "hit": key[4], "l0": key[2], "l1": key[5], "q": key[6]}


func _tick_attack(delta: float) -> void:
	if _hold > 0.0:
		_hold -= delta
		return
	var sp := _atk_spec()
	_af += delta * sp["fps"]
	if attack_requested:
		attack_requested = false
		_queued = true
	var f := int(_af)
	if f >= sp["l0"] and f <= sp["l1"]:
		velocity = _aim_vec(_sector) * 300.0
		_ghost_t -= delta
		if _ghost_t <= 0.0:
			_ghost_t = 0.035
			_ghost()
		move_and_slide()
		_clamp_world()
	if not _hit_done and f >= sp["hit"]:
		_hit_done = true
		_hold = 0.07
		_shake = 9.0
		_punch = 1.0
		_deal_damage()
	if not _vfx_done and f >= sp["slash"]:
		_vfx_done = true
		_spawn_slash(_combo)
	if _queued and _combo < 2 and f >= sp["q"]:
		_combo += 1
		_start_attack()
	elif f >= sp["n"]:
		_combo = 0
		_state = "move"
		_moving = false


func _start_dash(dir: Vector2) -> void:
	_state = "dash"
	_af = 0.0
	if dir.length() > 0.3:
		_sector = posmod(roundi(dir.angle() / (PI / 4.0)), 8)
	_dash_dir = _aim_vec(_sector).normalized()


func _tick_dash(delta: float) -> void:
	var side := _is_side()
	_af += delta * (26.0 if side else DASH_FPS)
	var f := int(_af)
	if f >= 1 and f <= (6 if side else 5):
		velocity = _dash_dir * DASH_SPEED
		move_and_slide()
		_clamp_world()
	if f >= (8 if side else DASH_FRAMES.size()):
		_state = "move"
		_moving = false


func _tick_dead(delta: float) -> void:
	_af += delta * 7.0
	if _af >= 11.0:
		hp = max_hp
		global_position = spawn_pos
		_state = "move"
		_inv = 1.5


func _m2set(name: String, flip: bool) -> void:
	var d: Array = M2[name]
	_spr.texture = _m2tex[name]
	_spr.offset = Vector2(-d[0], -d[1])
	_spr.position = Vector2.ZERO
	_spr.rotation = 0.0
	var fx := -1.0 if flip else 1.0
	_spr.scale = Vector2(fx * d[2], d[2])


func _fx(rx: float, ry: float, rot: float, a0: float, a1: float, wm: float, dl: float, hold: float, off: Vector2) -> void:
	var s = preload("res://slash_fx.gd").new()
	s.rx = rx
	s.ry = ry
	s.rot = rot
	s.a0 = a0
	s.a1 = a1
	s.wmul = wm
	s.delay = dl
	s.hold = hold
	s.position = off + Vector2(0.0, -_lift)
	add_child(s)


func _spawn_slash(combo: int, hold := -1.0) -> void:
	var th := _sector * PI / 4.0
	var fl := -1.0 if cos(th) < -0.1 else 1.0
	var fwd := Vector2(cos(th) * 18.0, sin(th) * 12.0 - 70.0)
	var body := Vector2(0.0, -70.0)
	match combo:
		0:
			_fx(175.0, 120.0, -0.35 * fl, th - 1.6, th + 1.6, 1.0, 0.0, hold, fwd)
			_fx(140.0, 95.0, -0.35 * fl, th - 1.5, th + 1.5, 0.55, 0.03, hold, fwd)
		1:
			_fx(180.0, 125.0, 0.35 * fl, th + 1.6, th - 1.6, 1.0, 0.0, hold, fwd)
			_fx(145.0, 100.0, 0.35 * fl, th + 1.5, th - 1.5, 0.55, 0.03, hold, fwd)
		_:
			# вихрь вокруг тела и большая вертикальная дуга
			_fx(140.0, 100.0, 0.0, th - 1.2, th - 1.2 + TAU * 1.1, 1.2, 0.0, hold, body)
			_fx(200.0, 145.0, 0.0, th - 2.0, th - 2.0 + TAU * 0.85, 0.6, 0.06, hold, body)


func _ghost() -> void:
	var g := Sprite2D.new()
	g.texture = _spr.texture
	g.centered = false
	g.offset = _spr.offset
	g.scale = _spr.scale
	g.position = position + Vector2(0.0, -_lift)
	g.modulate = Color(0.75, 0.65, 1.0, 0.45)
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	g.material = m
	get_parent().add_child(g)
	var tw := g.create_tween()
	tw.tween_property(g, "modulate:a", 0.0, 0.2)
	tw.tween_callback(g.queue_free)


# ---------------------------------------------------------------- отображение

func _refresh() -> void:
	if _state == "dead":
		_m2set("death_%d" % clampi(int(_af), 0, 7), _face_x < 0.0)
		return
	if _state == "attack" and _is_side():
		var sp: Dictionary = A2[_combo]
		_m2set("a%d_%d" % [_combo, clampi(int(_af), 0, sp["n"] - 1)], SECTORS[_sector][1])
		return
	if _state == "dash" and _is_side():
		_m2set("dash_%d" % clampi(int(_af), 0, 7), SECTORS[_sector][1])
		return
	if _state == "move" and _hurt_t > 0.0:
		_m2set("hurt_%d" % clampi(int((0.45 - _hurt_t) / 0.45 * 8.0), 0, 7), _face_x < 0.0)
		return
	if _state != "move":
		var av: String = SECTORS[_sector][0]
		var aflip: bool = SECTORS[_sector][1]
		var info = ATK.DATA[av]
		var f: int = clampi(int(_af), 0, 23)
		if _state == "dash":
			f = info["key"][DASH_FRAMES[clampi(int(_af), 0, DASH_FRAMES.size() - 1)]]
		_spr.texture = _atex[av][f]
		var fr = info["frames"][f]
		_spr.offset = Vector2(-fr[1], -fr[2])
		_spr.position = Vector2.ZERO
		_spr.rotation = 0.0
		var sc: float = info["scale"]
		_spr.scale = Vector2(-sc if aflip else sc, sc)
		return

	var view: String = SECTORS[_sector][0]
	var flip: bool = SECTORS[_sector][1]
	var key := "idle_" + view
	var wview := view
	if view == "se" or view == "ne":
		wview = "e"      # диагонали: кадры ходьбы вбок, корпус не меняем
	if wview == "e":
		if _moving:
			_m2set("walk_%d" % (int(_wt) % 7), flip)
			if view != "e":
				_spr.rotation = 0.0
			return
		if view == "e":
			_m2set("idle_%d" % (int(_idle_t * 2.0) % 8), flip)
			return
	var walking := _moving and wview in WALK_SETS
	if walking:
		key = "walk_%s_%d" % [wview, int(_wt) % 4]
	var d: Array = _data[key]
	_spr.texture = _tex[key]
	_spr.offset = Vector2(-d[0], -d[1])

	# подпрыгивание только когда нет покадровой ходьбы
	var bob := 0.0
	var sway := 0.0
	if _moving and not walking:
		bob = absf(sin(_bob_t)) * 4.0
		sway = sin(_bob_t) * 0.04
	var breath := sin(_idle_t) * 0.008 * (1.0 - _amp)
	var fx := -1.0 if flip else 1.0
	_spr.position = Vector2(0.0, -bob)
	_spr.rotation = sway * fx
	_spr.scale = Vector2(fx * DRAW_SCALE, DRAW_SCALE * (1.0 + breath))


func _draw() -> void:
	# тень на земле: сплюснутый эллипс
	draw_set_transform(Vector2(0.0, -_lift), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 26.0, Color(0, 0, 0, 0.45))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---------------------------------------------------------------- урон
func hurt(amount: float, from: Vector2) -> void:
	if _inv > 0.0 or _state == "dash" or _state == "dead":
		return
	hp -= amount
	_inv = 0.7
	_shake = 8.0
	_hurt_t = 0.45
	if hp <= 0.0:
		hp = 0.0
		_state = "dead"
		_af = 0.0


func _deal_damage() -> void:
	var th := _sector * PI / 4.0
	var aim := Vector2(cos(th), sin(th))
	var spin := _combo == 2
	var reach := 215.0 if spin else 200.0
	var dmg := 34.0 if spin else 20.0
	for e in get_tree().get_nodes_in_group("enemy"):
		if e.dead:
			continue
		var d: Vector2 = e.global_position - global_position
		d.y /= Y_SCALE
		var rr := reach + (70.0 if e.kind == "hd" else 0.0)
		if d.length() > rr:
			continue
		if not spin and d.length() > 40.0 and aim.dot(d.normalized()) < 0.2:
			continue
		e.hurt(dmg, d, 330.0 if spin else 240.0)
