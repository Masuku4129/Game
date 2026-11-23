extends CharacterBody2D
## Мита: нарисованные спрайты.
## Движение: 8 направлений (5 видов + зеркало), покадровая ходьба сбоку, спереди, сзади.
## Бой: комбо из трёх ударов и рывок, кадры из art/anim, эффекты из art/vfx.
## Точка опоры каждого спрайта = центр стоп (art/sprite_data.gd, art/anim/anim_data.gd).

const ATK := preload("res://art/atk/atk_data.gd")

const SPEED := 230.0
const Y_SCALE := 0.75        # вертикальная скорость меньше (перспектива)
const DRAW_SCALE := 0.375    # спрайт 320 px -> 120 единиц мира
const WALK_FPS := 8.0
const ATTACK_FPS := [16.0, 19.0, 14.0]   # скорость ударов 1-3 (кадров в секунду)
const DASH_FPS := 20.0
const DASH_SPEED := 460.0
const DASH_FRAMES := [2, 3, 3, 3, 4, 5]  # кадры листа удара, которые играют в рывке

# сектор (0=вправо, по часовой на экране) -> [вид, зеркалить]
const SECTORS := [
	["e", false], ["se", false], ["s", false], ["se", true],
	["e", true], ["ne", true], ["n", false], ["ne", false]]
const WALK_SETS := ["e", "s", "n"]   # для этих видов есть кадры ходьбы

var stick                       # джойстик, выставляется из main.gd
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
var _dash_dir := Vector2.RIGHT
var _spr: Sprite2D
var _tex := {}
var _data := {}
var _atex := {}                 # вид -> [Texture2D x8]


func _ready() -> void:
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

	_spr = Sprite2D.new()
	_spr.centered = false
	_spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_spr)
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
	if not debug:
		match _state:
			"attack":
				_tick_attack(delta)
			"dash":
				_tick_dash(delta)
			_:
				_tick_move(delta)
		_refresh()
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


func _tick_attack(delta: float) -> void:
	_af += delta * ATTACK_FPS[_combo]
	if attack_requested:
		attack_requested = false
		_queued = true
	var f := int(_af)
	if f >= 2 and f <= 5:
		velocity = _aim_vec(_sector) * 140.0
		move_and_slide()
		_clamp_world()
	if not _vfx_done and f >= 3:
		_vfx_done = true
		_spawn_slash(_combo)
	if _queued and _combo < 2 and f >= 6:
		_combo += 1
		_start_attack()
	elif f >= 8:
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
	_af += delta * DASH_FPS
	var f := int(_af)
	if f >= 1 and f <= 5:
		velocity = _dash_dir * DASH_SPEED
		move_and_slide()
		_clamp_world()
	if f >= DASH_FRAMES.size():
		_state = "move"
		_moving = false


func _spawn_slash(combo: int, hold := -1.0) -> void:
	var s = preload("res://slash_fx.gd").new()
	var th := _sector * PI / 4.0
	var sgn := 1.0 if combo != 1 else -1.0
	s.a0 = th - 1.45 * sgn
	s.a1 = th + 1.45 * sgn
	s.rot = [-0.35, 0.35, 0.0][combo] * (-1.0 if cos(th) < -0.1 else 1.0)
	if combo == 2:
		s.rx = 90.0
		s.ry = 120.0
		s.a0 = th - 1.7 * sgn - PI * 0.5
		s.a1 = th + 1.1 * sgn - PI * 0.5
	s.hold = hold
	s.position = Vector2(0.0, -62.0)
	add_child(s)


# ---------------------------------------------------------------- отображение

func _refresh() -> void:
	if _state != "move":
		var av: String = SECTORS[_sector][0]
		var aflip: bool = SECTORS[_sector][1]
		var info = ATK.DATA[av]
		var f: int = clampi(int(_af), 0, 7)
		if _state == "dash":
			f = DASH_FRAMES[clampi(int(_af), 0, DASH_FRAMES.size() - 1)]
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
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 26.0, Color(0, 0, 0, 0.45))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
