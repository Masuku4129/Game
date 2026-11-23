extends CharacterBody2D
## Мита: нарисованные спрайты, 8 направлений.
## Есть 5 видов (спереди, спереди-3/4, сбоку, сзади-3/4, сзади), остальные три
## получаются зеркалом. Покадровая ходьба есть для сбоку, спереди и сзади;
## на диагоналях используется стоячий вид с подпрыгиванием.
## Точка опоры каждого спрайта = центр стоп (art/sprite_data.gd).

const SPEED := 230.0
const Y_SCALE := 0.75        # вертикальная скорость меньше (перспектива)
const DRAW_SCALE := 0.375    # спрайт 320 px -> 120 единиц мира
const WALK_FPS := 8.0

# сектор (0=вправо, по часовой на экране) -> [вид, зеркалить]
const SECTORS := [
	["e", false], ["se", false], ["s", false], ["se", true],
	["e", true], ["ne", true], ["n", false], ["ne", false]]
const WALK_SETS := ["e", "s", "n"]   # для этих видов есть кадры ходьбы

var stick                       # джойстик, выставляется из main.gd
var world_radius := 2400.0
var debug := false              # для кадров предпросмотра: поза задаётся вручную

var _sector := 2
var _moving := false
var _wt := 0.0                  # фаза кадров ходьбы
var _bob_t := 0.0               # фаза подпрыгивания (для диагоналей)
var _amp := 0.0
var _idle_t := 0.0
var _spr: Sprite2D
var _tex := {}
var _data := {}


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
	_spr = Sprite2D.new()
	_spr.centered = false
	_spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_spr)
	_refresh()


func set_pose(sector: int, moving: bool, wt: float) -> void:
	debug = true
	_sector = sector
	_moving = moving
	_wt = wt
	_bob_t = wt
	_amp = 1.0 if moving else 0.0
	_refresh()


func _physics_process(delta: float) -> void:
	if not debug:
		var dir := Vector2.ZERO
		if stick:
			dir = stick.value
		var k := Vector2(
			float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
			float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))
		if k != Vector2.ZERO:
			dir = k.normalized()

		velocity = Vector2(dir.x, dir.y * Y_SCALE) * SPEED
		move_and_slide()
		if position.length() > world_radius:
			position = position.normalized() * world_radius

		_moving = dir.length() > 0.05
		if _moving:
			_sector = posmod(roundi(dir.angle() / (PI / 4.0)), 8)
			_wt += delta * WALK_FPS
			_bob_t += delta * 11.0
		_amp = move_toward(_amp, 1.0 if _moving else 0.0, delta * 8.0)
		_idle_t += delta * 2.0
		_refresh()
	queue_redraw()


func _refresh() -> void:
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
