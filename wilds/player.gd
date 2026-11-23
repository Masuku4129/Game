extends CharacterBody2D
## Мита: нарисованные спрайты.
## Движение: 8 направлений (5 видов + зеркало), покадровая ходьба сбоку, спереди, сзади.
## Бой: комбо из трёх ударов и рывок, кадры из art/anim, эффекты из art/vfx.
## Точка опоры каждого спрайта = центр стоп (art/sprite_data.gd, art/anim/anim_data.gd).

const ANIM := preload("res://art/anim/anim_data.gd")

const SPEED := 230.0
const Y_SCALE := 0.75        # вертикальная скорость меньше (перспектива)
const DRAW_SCALE := 0.375    # спрайт 320 px -> 120 единиц мира
const WALK_FPS := 8.0
const ATTACK_FPS := 22.0
const DASH_FPS := 24.0
const DASH_SPEED := 420.0
const COMBO_ROWS := [0, 1, 2]     # ряды листа анимаций для ударов 1-3
const DASH_ROW := 3               # ряд листа для рывка
const VFX_ROWS := [0, 1, 3]       # ряды эффектов для ударов 1-3

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
var _atex := []                 # [ряд][кадр] -> Texture2D
var _vfx_tex: Texture2D


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
	for row in ANIM.ROWS:
		var r := []
		for f in row:
			r.append(load("res://art/anim/" + f[0]))
		_atex.append(r)
	_vfx_tex = load("res://art/vfx/vfx_light1.png")

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


func set_attack_pose(row: int, frame: int) -> void:
	debug = true
	_state = "attack"
	_row = row
	_af = float(frame)
	_face_x = 1.0
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

func _start_attack() -> void:
	_state = "attack"
	_row = COMBO_ROWS[_combo]
	_af = 0.0
	_queued = false
	_vfx_done = false


func _tick_attack(delta: float) -> void:
	_af += delta * ATTACK_FPS
	if attack_requested:
		attack_requested = false
		_queued = true
	var n: int = ANIM.ROWS[_row].size()
	var f := int(_af)
	# выпад вперёд на ударных кадрах
	if f >= 3 and f <= 8:
		velocity = Vector2(_face_x * 110.0, 0.0)
		move_and_slide()
		_clamp_world()
	if not _vfx_done and f >= 4:
		_vfx_done = true
		_spawn_vfx(VFX_ROWS[_combo])
	if _queued and _combo + 1 < COMBO_ROWS.size() and f >= n - 4:
		_combo += 1
		_start_attack()
	elif f >= n:
		_combo = 0
		_state = "move"
		_moving = false


func _start_dash(dir: Vector2) -> void:
	_state = "dash"
	_row = DASH_ROW
	_af = 0.0
	if dir.length() > 0.2:
		_dash_dir = Vector2(dir.x, dir.y * Y_SCALE).normalized()
		if absf(dir.x) > 0.25:
			_face_x = signf(dir.x)
	else:
		_dash_dir = Vector2(_face_x, 0.0)


func _tick_dash(delta: float) -> void:
	_af += delta * DASH_FPS
	var f := int(_af)
	if f >= 2 and f <= 9:
		velocity = _dash_dir * DASH_SPEED
		move_and_slide()
		_clamp_world()
	if f >= ANIM.ROWS[_row].size():
		_state = "move"
		_moving = false


func _spawn_vfx(row: int) -> void:
	var s = preload("res://vfx_once.gd").new()
	s.texture = _vfx_tex
	s.hframes = 13
	s.vframes = 4
	s.row = row
	s.frame = row * 13
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	s.material = m
	s.position = Vector2(_face_x * 58.0, -64.0)
	s.scale = Vector2(_face_x * 1.0, 1.0)
	add_child(s)


# ---------------------------------------------------------------- отображение

func _refresh() -> void:
	if _state != "move":
		var frames: Array = ANIM.ROWS[_row]
		var f: int = clampi(int(_af), 0, frames.size() - 1)
		_spr.texture = _atex[_row][f]
		_spr.offset = Vector2(-frames[f][1], -frames[f][2])
		_spr.position = Vector2.ZERO
		_spr.rotation = 0.0
		_spr.scale = Vector2(_face_x * ANIM.SCALE, ANIM.SCALE)
		return

	var view: String = SECTORS[_sector][0]
	var flip: bool = SECTORS[_sector][1]
	var key := "idle_" + view
	var walking := _moving and view in WALK_SETS
	if walking:
		key = "walk_%s_%d" % [view, int(_wt) % 4]
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
