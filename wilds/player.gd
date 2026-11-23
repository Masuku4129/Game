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
	if not debug:
		match _state:
			"attack":
				_tick_attack(delta)
			"dash":
				_tick_dash(delta)
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


func _tick_attack(delta: float) -> void:
	if _hold > 0.0:
		_hold -= delta
		return
	_af += delta * ATTACK_FPS[_combo]
	if attack_requested:
		attack_requested = false
		_queued = true
	var f := int(_af)
	var key: Array = ATK.DATA[SECTORS[_sector][0]]["key"]
	if f >= key[2] and f <= key[5]:
		velocity = _aim_vec(_sector) * 300.0
		_ghost_t -= delta
		if _ghost_t <= 0.0:
			_ghost_t = 0.035
			_ghost()
		move_and_slide()
		_clamp_world()
	if not _hit_done and f >= key[4]:
		_hit_done = true
		_hold = 0.07
		_shake = 9.0
		_punch = 1.0
	if not _vfx_done and f >= key[3]:
		_vfx_done = true
		_spawn_slash(_combo)
	if _queued and _combo < 2 and f >= key[6]:
		_combo += 1
		_start_attack()
	elif f >= 24:
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
