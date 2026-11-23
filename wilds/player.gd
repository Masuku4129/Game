extends CharacterBody2D
## Мита. Три ракурса как в Don't Starve: спереди, сзади, сбоку (влево зеркалится).
## Тело рисуется слоями, светящиеся части (глаза, клинок, дымка) вынесены в
## отдельный узел с аддитивным смешиванием: они светятся в темноте.

const SPEED := 230.0
const Y_SCALE := 0.75   # вертикальная скорость меньше (перспектива)

const FRONT := 0
const BACK := 1
const SIDE := 2

const INK := Color(0.03, 0.03, 0.06)
const CLOTH := Color(0.085, 0.08, 0.14)
const CLOTH_FAR := Color(0.055, 0.05, 0.095)
const CLOTH_LIGHT := Color(0.12, 0.11, 0.19)
const STRAP := Color(0.20, 0.18, 0.27)
const BOOT := Color(0.12, 0.11, 0.15)
const SKIN := Color(0.80, 0.78, 0.90)
const SKIN_SHADE := Color(0.52, 0.52, 0.72)
const HAIR := Color(0.045, 0.04, 0.085)
const RIM := Color(0.42, 0.45, 1.0, 0.8)
const RIM_SOFT := Color(0.42, 0.45, 1.0, 0.18)
const EYE := Color(0.25, 0.45, 1.0)
const HILT := Color(0.34, 0.13, 0.55)
const BLADE := Color(0.93, 0.91, 1.0)
const GLOW := Color(0.45, 0.35, 1.0)

var stick                       # джойстик, выставляется из main.gd
var world_radius := 2400.0
var debug := false              # для кадров предпросмотра: поза задаётся вручную
var face := FRONT
var sx := 1.0                   # -1: смотрит влево (только для SIDE)

var _t := 0.0                   # фаза шага
var _amp := 0.0                 # амплитуда шага 0..1
var _lag := 0.0                 # развевание волос 0..1
var _hair_t := 0.0
var _moving := false
var _glow: Node2D
var _blade := PackedVector2Array()
var _eyes: Array[Vector2] = []


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = 10.0
	cs.shape = sh
	add_child(cs)

	_glow = Node2D.new()
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_glow.material = m
	_glow.draw.connect(_draw_glow)
	add_child(_glow)


func set_pose(f: int, moving: bool, t: float) -> void:
	debug = true
	face = f
	sx = 1.0
	_moving = moving
	_t = t
	_amp = 1.0 if moving else 0.0
	_lag = 1.0 if moving else 0.0


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
			if absf(dir.x) > absf(dir.y) * 0.9:
				face = SIDE
				sx = signf(dir.x)
			else:
				face = FRONT if dir.y > 0.0 else BACK
			_t += delta * 11.0
		_amp = move_toward(_amp, 1.0 if _moving else 0.0, delta * 8.0)
		_lag = move_toward(_lag, 1.0 if _moving else 0.0, delta * 3.0)
		_hair_t += delta * (7.0 if _moving else 2.2)

	_update_pose()
	queue_redraw()
	_glow.queue_redraw()


# ---------------------------------------------------------------- общее

func _bob() -> float:
	return -absf(sin(_t)) * 2.5 * _amp + sin(_hair_t * 0.8) * 0.7 * (1.0 - _amp)


func _limb(a: Vector2, b: Vector2, w0: float, w1: float, col: Color) -> void:
	if a.distance_squared_to(b) < 0.01:
		b += Vector2(0.0, 0.1)
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	draw_colored_polygon(PackedVector2Array([
		a + n * w0 * 0.5, b + n * w1 * 0.5, b - n * w1 * 0.5, a - n * w0 * 0.5]), col)
	draw_circle(a, w0 * 0.5, col)
	draw_circle(b, w1 * 0.5, col)


func _make_blade(start: Vector2, ang: float, length: float, curve: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var p := start
	var n := 8
	var step := length / float(n)
	for i in n + 1:
		pts.append(p)
		var a := ang - curve * float(i) / float(n)
		p += Vector2(cos(a), sin(a)) * step
	return pts


func _hilt(a: Vector2, b: Vector2) -> void:
	draw_line(a, b, INK, 5.0)
	draw_line(a, b, HILT, 3.2)
	# оплётка: тёмные ромбики поперёк рукояти
	for i in 3:
		var p := a.lerp(b, (float(i) + 0.5) / 3.0)
		draw_circle(p, 1.0, Color(0.12, 0.05, 0.22))
	draw_circle(b, 3.0, INK)
	draw_circle(b, 1.8, Color(0.5, 0.45, 0.65))


func _update_pose() -> void:
	var bob := _bob()
	_eyes.clear()
	match face:
		SIDE:
			var hand := Vector2(13.0, -56.0 + bob)
			var tsuba := hand + Vector2(5.0, -3.0)
			var ang := deg_to_rad(26.0 + 10.0 * sin(_t) * _amp)
			_blade = _make_blade(tsuba, ang, 62.0, 0.35)
			_eyes.append(Vector2(7.8, -95.5 + bob))
		FRONT:
			var tsuba := Vector2(15.0, -49.0 + bob)
			_blade = _make_blade(tsuba, deg_to_rad(86.0), 52.0, -0.12)
			_eyes.append(Vector2(-4.6, -95.5 + bob))
			_eyes.append(Vector2(4.6, -95.5 + bob))
		_:
			var tsuba := Vector2(15.0, -49.0 + bob)
			_blade = _make_blade(tsuba, deg_to_rad(86.0), 52.0, -0.12)


func _draw() -> void:
	var fx := sx if face == SIDE else 1.0
	# тень на земле
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 24.0, Color(0, 0, 0, 0.4))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(fx, 1.0))
	match face:
		SIDE:
			_draw_side()
		FRONT:
			_draw_front()
		_:
			_draw_back()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---------------------------------------------------------------- вид сбоку

func _leg_side(hip: Vector2, s: float, lift: float, col: Color, strap: bool) -> void:
	var foot := Vector2(1.0 + s * 9.0, -lift)
	var knee := Vector2(2.0 + s * 5.0, -26.0 - lift * 0.5)
	_limb(hip, knee, 12.0, 11.0, col)
	_limb(knee, foot + Vector2(0.0, -7.0), 11.0, 8.5, col)
	draw_colored_polygon(PackedVector2Array([
		foot + Vector2(-4.5, -9.0), foot + Vector2(3.5, -9.0),
		foot + Vector2(10.0, -1.0), foot + Vector2(10.0, 0.5), foot + Vector2(-4.5, 0.5)]), BOOT)
	if strap:
		var p := hip.lerp(knee, 0.45)
		draw_line(p + Vector2(-6.0, 0.0), p + Vector2(6.0, 0.0), STRAP, 3.0)


func _draw_side() -> void:
	var bob := _bob()
	var s0 := sin(_t) * _amp
	var l0 := maxf(0.0, cos(_t)) * 4.0 * _amp
	var l1 := maxf(0.0, -cos(_t)) * 4.0 * _amp
	var hip := Vector2(0.0, -46.0 + bob)

	# волосы сзади
	var tipx := -24.0 - 12.0 * _lag + sin(_hair_t) * 3.0 * (0.4 + _lag)
	var tipy := -52.0 - 12.0 * _lag + bob
	var hair := PackedVector2Array([
		Vector2(8, -100 + bob), Vector2(0, -108 + bob), Vector2(-12, -103 + bob),
		Vector2(-18, -90 + bob), Vector2(tipx - 5.0, tipy), Vector2(tipx + 3.0, tipy + 8.0),
		Vector2(-5, -76 + bob), Vector2(1, -84 + bob), Vector2(7, -90 + bob)])
	draw_colored_polygon(hair, HAIR)
	for k in 3:
		var kf := float(k)
		draw_polyline(PackedVector2Array([
			Vector2(-3.0 - 3.0 * kf, -105 + bob), Vector2(-14.0 - 2.0 * kf, -92 + bob),
			Vector2(lerpf(-15.0, tipx, 0.5) - kf * 2.0, -72 + bob),
			Vector2(tipx + kf * 3.0, tipy + 4.0)]), RIM_SOFT, 1.2, true)

	# дальняя рука и нога
	_limb(Vector2(-2, -79 + bob), Vector2(3, -65 + bob), 7.0, 6.0, CLOTH_FAR)
	_limb(Vector2(3, -65 + bob), Vector2(11, -58 + bob), 6.0, 4.5, CLOTH_FAR)
	_leg_side(hip, -s0, l1, CLOTH_FAR, false)

	# торс (куртка)
	var torso := PackedVector2Array([
		Vector2(-8, -82 + bob), Vector2(7, -82 + bob),
		Vector2(10, -46 + bob), Vector2(-12, -46 + bob)])
	draw_colored_polygon(torso, CLOTH)
	draw_polyline(PackedVector2Array([Vector2(-8, -82 + bob), Vector2(-12, -46 + bob)]), RIM, 1.6, true)
	draw_line(Vector2(-11, -49 + bob), Vector2(9, -49 + bob), STRAP, 3.0)
	draw_circle(Vector2(8, -49 + bob), 2.0, HILT)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-7, -83 + bob), Vector2(7, -83 + bob),
		Vector2(6, -91 + bob), Vector2(-6, -91 + bob)]), CLOTH_LIGHT)

	# ближняя нога
	_leg_side(hip, s0, l0, CLOTH, true)

	# шея и голова
	_limb(Vector2(1, -89 + bob), Vector2(1, -83 + bob), 5.0, 5.0, SKIN_SHADE)
	var c := Vector2(2.0, -95.0 + bob)
	draw_circle(c, 10.5, SKIN)
	draw_circle(c + Vector2(4.5, 6.0), 5.5, SKIN)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(10, -1), c + Vector2(13.5, 3), c + Vector2(9.5, 3.5)]), SKIN)
	draw_circle(c + Vector2(5.8, -0.5), 2.4, INK)                       # глазница
	draw_line(c + Vector2(2, -4.5), c + Vector2(9.5, -3.2), INK, 2.0)   # веко
	draw_line(c + Vector2(2.5, -7.5), c + Vector2(9.5, -6.2), HAIR, 1.6)
	draw_line(c + Vector2(7, 6.5), c + Vector2(9.2, 6.2), Color(0.5, 0.25, 0.35), 1.2)
	# чёлка и прядь у лица
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(10.5, -4), c + Vector2(8, -11), c + Vector2(0, -14),
		c + Vector2(-9, -10), c + Vector2(-11, 0), c + Vector2(-5, -3),
		c + Vector2(1, -6.5), c + Vector2(6, -6.5)]), HAIR)
	draw_polyline(PackedVector2Array([
		c + Vector2(-1, -4), c + Vector2(0, 6), c + Vector2(-2, 14)]), HAIR, 3.2, true)
	draw_polyline(PackedVector2Array([
		c + Vector2(8, -11), c + Vector2(0, -14), c + Vector2(-9, -10)]), RIM_SOFT, 1.4, true)

	# ближняя рука и рукоять
	_limb(Vector2(0, -79 + bob), Vector2(6, -64 + bob), 7.0, 6.0, CLOTH)
	_limb(Vector2(6, -64 + bob), Vector2(13, -56 + bob), 6.0, 4.5, CLOTH)
	draw_circle(Vector2(13, -56 + bob), 2.7, SKIN)
	_hilt(Vector2(8, -53 + bob), Vector2(18, -59 + bob))


# ---------------------------------------------------------------- вид спереди

func _boot_front(f: Vector2) -> void:
	draw_colored_polygon(PackedVector2Array([
		f + Vector2(-4.5, -9), f + Vector2(4.5, -9), f + Vector2(7, 1), f + Vector2(-7, 1)]), BOOT)


func _legs_front(bob: float) -> void:
	var s0 := sin(_t) * _amp
	var l0 := maxf(0.0, cos(_t)) * 4.0 * _amp
	var l1 := maxf(0.0, -cos(_t)) * 4.0 * _amp
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var s := s0 * side
		var lift := l0 if i == 0 else l1
		var hip := Vector2(side * 5.5, -46.0 + bob)
		var knee := Vector2(side * 6.5, -26.0 + s * 1.5 - lift * 0.5)
		var foot := Vector2(side * 7.0, s * 3.0 - lift)
		_limb(hip, knee, 11.0, 11.0, CLOTH)
		_limb(knee, foot + Vector2(0.0, -7.0), 11.0, 9.0, CLOTH)
		_boot_front(foot)
		if side > 0.0:
			var p := hip.lerp(knee, 0.45)
			draw_line(p + Vector2(-5.5, 0.0), p + Vector2(5.5, 0.0), STRAP, 3.0)


func _draw_front() -> void:
	var bob := _bob()
	var sw := sin(_hair_t) * 2.5 * (0.4 + _lag)

	# волосы сзади (видны по бокам и ниже плеч)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-13, -100 + bob), Vector2(-9, -108 + bob), Vector2(0, -110 + bob),
		Vector2(9, -108 + bob), Vector2(13, -100 + bob), Vector2(15, -80 + bob),
		Vector2(14 + sw, -60 + bob), Vector2(8, -62 + bob), Vector2(0, -84 + bob),
		Vector2(-8, -62 + bob), Vector2(-14 + sw, -60 + bob), Vector2(-15, -80 + bob)]), HAIR)

	_legs_front(bob)

	# торс
	draw_colored_polygon(PackedVector2Array([
		Vector2(-10, -82 + bob), Vector2(10, -82 + bob),
		Vector2(12.5, -47 + bob), Vector2(-12.5, -47 + bob)]), CLOTH)
	draw_line(Vector2(0, -84 + bob), Vector2(0, -48 + bob), STRAP, 1.3)
	draw_polyline(PackedVector2Array([Vector2(-10, -82 + bob), Vector2(-12.5, -47 + bob)]), RIM, 1.6, true)
	draw_line(Vector2(-12, -50 + bob), Vector2(12, -50 + bob), STRAP, 3.2)
	draw_circle(Vector2(0, -50 + bob), 2.2, HILT)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-8, -83 + bob), Vector2(8, -83 + bob),
		Vector2(8, -90 + bob), Vector2(-8, -90 + bob)]), CLOTH_LIGHT)

	# руки
	_limb(Vector2(-11, -79 + bob), Vector2(-15, -64 + bob), 7.0, 6.0, CLOTH)
	_limb(Vector2(-15, -64 + bob), Vector2(-14, -51 + bob), 6.0, 4.5, CLOTH)
	draw_circle(Vector2(-14, -49 + bob), 2.7, SKIN)
	_limb(Vector2(11, -79 + bob), Vector2(16, -64 + bob), 7.0, 6.0, CLOTH)
	_limb(Vector2(16, -64 + bob), Vector2(15, -53 + bob), 6.0, 4.5, CLOTH)
	draw_circle(Vector2(15, -50 + bob), 2.7, SKIN)
	_hilt(Vector2(15, -49 + bob), Vector2(15.5, -62 + bob))

	# голова
	_limb(Vector2(0, -89 + bob), Vector2(0, -83 + bob), 5.0, 5.0, SKIN_SHADE)
	var c := Vector2(0.0, -95.0 + bob)
	draw_circle(c, 10.5, SKIN)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-8, 4), c + Vector2(0, 13), c + Vector2(8, 4)]), SKIN)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		draw_circle(c + Vector2(side * 4.6, -0.5), 2.4, INK)
		draw_line(c + Vector2(side * 8.2, -3.8), c + Vector2(side * 1.8, -3.2), INK, 1.9)
		draw_line(c + Vector2(side * 8.5, -6.8), c + Vector2(side * 2.0, -6.0), HAIR, 1.5)
		# чёлка с пробором и длинные пряди у лица
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(side * 11.5, 3), c + Vector2(side * 12, -6), c + Vector2(side * 7, -12.5),
			c + Vector2(0, -13.5), c + Vector2(side * -1, -9), c + Vector2(side * 2, -6.5),
			c + Vector2(side * 5, -3), c + Vector2(side * 7, 1.5)]), HAIR)
		draw_polyline(PackedVector2Array([
			c + Vector2(side * 10.5, 0), c + Vector2(side * 12, 12 + bob * 0.0),
			c + Vector2(side * 13 + sw * side * 0.5, 26)]), HAIR, 3.4, true)
	draw_line(c + Vector2(-1.5, 7.5), c + Vector2(1.5, 7.5), Color(0.55, 0.3, 0.4), 1.3)
	draw_polyline(PackedVector2Array([
		c + Vector2(-9, -9), c + Vector2(0, -13.5), c + Vector2(9, -9)]), RIM_SOFT, 1.4, true)


# ---------------------------------------------------------------- вид сзади

func _draw_back() -> void:
	var bob := _bob()
	var sw := sin(_hair_t) * 2.5 * (0.4 + _lag)

	_legs_front(bob)

	# торс и капюшон
	draw_colored_polygon(PackedVector2Array([
		Vector2(-10, -82 + bob), Vector2(10, -82 + bob),
		Vector2(12.5, -47 + bob), Vector2(-12.5, -47 + bob)]), CLOTH)
	draw_line(Vector2(0, -80 + bob), Vector2(0, -48 + bob), CLOTH_LIGHT, 1.3)
	draw_line(Vector2(-12, -50 + bob), Vector2(12, -50 + bob), STRAP, 3.2)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-9, -81 + bob), Vector2(9, -81 + bob),
		Vector2(8, -92 + bob), Vector2(-8, -92 + bob)]), CLOTH_LIGHT)

	# руки
	_limb(Vector2(-11, -79 + bob), Vector2(-15, -64 + bob), 7.0, 6.0, CLOTH)
	_limb(Vector2(-15, -64 + bob), Vector2(-14, -51 + bob), 6.0, 4.5, CLOTH)
	draw_circle(Vector2(-14, -49 + bob), 2.7, SKIN)
	_limb(Vector2(11, -79 + bob), Vector2(16, -64 + bob), 7.0, 6.0, CLOTH)
	_limb(Vector2(16, -64 + bob), Vector2(15, -53 + bob), 6.0, 4.5, CLOTH)
	draw_circle(Vector2(15, -50 + bob), 2.7, SKIN)
	_hilt(Vector2(15, -49 + bob), Vector2(15.5, -62 + bob))

	# голова и длинные волосы закрывают спину
	draw_circle(Vector2(0, -95 + bob), 11.0, HAIR)
	var hair := PackedVector2Array([
		Vector2(-13, -100 + bob), Vector2(-9, -108 + bob), Vector2(0, -110 + bob),
		Vector2(9, -108 + bob), Vector2(13, -100 + bob), Vector2(14.5, -80 + bob),
		Vector2(13 + sw, -58 + bob), Vector2(7, -52 + bob), Vector2(0, -56 + bob),
		Vector2(-7, -52 + bob), Vector2(-13 + sw, -58 + bob), Vector2(-14.5, -80 + bob)])
	draw_colored_polygon(hair, HAIR)
	for k in 4:
		var x := -9.0 + 6.0 * float(k)
		draw_polyline(PackedVector2Array([
			Vector2(x * 0.7, -106 + bob), Vector2(x, -90 + bob),
			Vector2(x * 1.05 + sw * 0.5, -72 + bob), Vector2(x * 1.1 + sw, -57 + bob)]),
			RIM_SOFT, 1.2, true)
	draw_polyline(PackedVector2Array([
		Vector2(-9, -106 + bob), Vector2(0, -110 + bob), Vector2(9, -106 + bob)]), RIM, 1.5, true)


# ---------------------------------------------------------------- свечение

func _draw_glow() -> void:
	var fx := sx if face == SIDE else 1.0
	_glow.draw_set_transform(Vector2.ZERO, 0.0, Vector2(fx, 1.0))
	# слабая фиолетовая дымка вокруг фигуры
	_glow.draw_circle(Vector2(0, -50), 78.0, Color(0.22, 0.16, 0.55, 0.035))
	_glow.draw_circle(Vector2(0, -50), 54.0, Color(0.22, 0.16, 0.55, 0.045))
	# глаза
	for e in _eyes:
		_glow.draw_circle(e, 4.6, Color(0.15, 0.25, 1.0, 0.10))
		_glow.draw_circle(e, 3.0, Color(0.2, 0.35, 1.0, 0.22))
		_glow.draw_circle(e, 1.7, EYE)
		_glow.draw_circle(e + Vector2(-0.4, -0.5), 0.6, Color(0.8, 0.9, 1.0))
	# клинок
	if _blade.size() > 1:
		_glow.draw_polyline(_blade, Color(GLOW.r, GLOW.g, GLOW.b, 0.10), 9.0, true)
		_glow.draw_polyline(_blade, Color(GLOW.r, GLOW.g, GLOW.b, 0.22), 5.5, true)
		_glow.draw_polyline(_blade, Color(0.65, 0.55, 1.0, 0.85), 2.4, true)
		_glow.draw_polyline(_blade, BLADE, 1.1, true)
	_glow.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
