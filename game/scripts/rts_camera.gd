extends Node3D
## --- colony: изометрическая камера остро́га. ---
## Один палец по земле — тянет карту (как лист на столе), два пальца — щипок (приближение)
## и поворот. Наклон регулируется в пределах 30–56° для низкого обзора и изометрии.
## Движение сглажено: за пальцем едет цель, камера её догоняет (экспоненциально).
## Короткое касание без сдвига — не ход камеры, а тап: о нём сообщаем colony
## (on_tap / on_long_press / on_hover).
##
## Совместимость: подменяет main.rig (camera_rig.gd), поэтому держит те же поля —
## position, rotation.y, cam, distance, pitch, target.

const PITCH_MIN := 30.0
const PITCH_MAX := 56.0
const D_MIN := 9.0            # близко: виден человек
const D_MAX := 150.0          # далеко: видна вся долина
const TAP_PX := 18.0
const TAP_T := 0.35
const HOLD_T := 0.5

var main: Node3D
var colony
var target: Node3D            # не используется (совместимость с camera_rig)
var pitch := 52.0
var distance := 26.0
var cam := Camera3D.new()

var want_pos := Vector3.ZERO
var want_dist := 26.0
var want_yaw := 0.0
var touches := {}
var _down := {}               # индекс → [точка, время]
var _moved := {}
var _pinch := 0.0
var _angle := 0.0
var _hold_sent := false
var _mouse_drag := false
var _tool := false            # палец работает кистью/рамкой, а не тянет карту

func _ready() -> void:
	cam.fov = 48.0
	cam.near = 0.5
	cam.far = float(OS.get_environment("CFAR")) if OS.get_environment("CFAR") != "" else 520.0
	add_child(cam)
	want_pos = position
	want_dist = distance
	want_yaw = rotation.y
	_update()

## Поставить взгляд в точку (без рывка — плавно доедет).
func look_at_point(p: Vector3, dist: float = -1.0) -> void:
	want_pos = Vector3(p.x, 0.0, p.z)
	if dist > 0.0:
		want_dist = clampf(dist, D_MIN, D_MAX)

## Мгновенно (для кадров и загрузки).
func snap_to(p: Vector3, dist: float, yaw: float) -> void:
	want_pos = Vector3(p.x, 0.0, p.z)
	want_dist = clampf(dist, D_MIN, D_MAX)
	want_yaw = yaw
	distance = want_dist
	rotation.y = yaw
	position = Vector3(p.x, _ground(p.x, p.z), p.z)
	_update()

func zoom_k() -> float:
	return clampf((distance - D_MIN) / (D_MAX - D_MIN), 0.0, 1.0)

func _ground(x: float, z: float) -> float:
	if main == null:
		return 0.0
	return maxf(main.grid_height(x, z), main.WATER_Y)

func _process(delta: float) -> void:
	var half: float = (main.SIZE * 0.5 - 20.0) if main != null else 200.0
	want_pos.x = clampf(want_pos.x, -half, half)
	want_pos.z = clampf(want_pos.z, -half, half)
	var k := 1.0 - exp(-9.0 * delta)
	position.x = lerpf(position.x, want_pos.x, k)
	position.z = lerpf(position.z, want_pos.z, k)
	position.y = lerpf(position.y, _ground(position.x, position.z), 1.0 - exp(-5.0 * delta))
	distance = lerpf(distance, want_dist, 1.0 - exp(-8.0 * delta))
	rotation.y = lerp_angle(rotation.y, want_yaw, 1.0 - exp(-10.0 * delta))
	# далёкий взгляд — чуть круче: так видно больше долины
	pitch = lerpf(PITCH_MIN, PITCH_MAX, zoom_k())
	_update()
	# долгое нажатие на месте — радиальное меню
	if not _hold_sent and not _tool and _down.size() == 1 and colony != null:
		for i: int in _down:
			var e: Array = _down[i]
			var t0: float = e[1]
			if not bool(_moved.get(i, false)) and Time.get_ticks_msec() * 0.001 - t0 > HOLD_T:
				_hold_sent = true
				var p: Vector2 = e[0]
				colony.on_long_press(p)

func _update() -> void:
	var r := deg_to_rad(pitch)
	cam.position = Vector3(0, sin(r) * distance, cos(r) * distance)
	cam.look_at(global_position + Vector3(0, 1.0, 0), Vector3.UP)

## Сдвиг карты: пиксели пальца → метры по земле (с учётом поворота и наклона).
func _pan(rel: Vector2) -> void:
	var vs := get_viewport().get_visible_rect().size
	var r := deg_to_rad(pitch)
	var mpp := 2.0 * distance * tan(deg_to_rad(cam.fov * 0.5)) / maxf(vs.y, 1.0)
	var dx := -rel.x * mpp
	var dz := -rel.y * mpp / maxf(sin(r), 0.3)
	var fwd := Vector2(sin(rotation.y), cos(rotation.y))
	var rgt := Vector2(fwd.y, -fwd.x)
	want_pos.x += rgt.x * dx + fwd.x * dz
	want_pos.z += rgt.y * dx + fwd.y * dz

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		var st := e as InputEventScreenTouch
		if st.pressed:
			touches[st.index] = st.position
			_down[st.index] = [st.position, Time.get_ticks_msec() * 0.001]
			_moved[st.index] = false
			_hold_sent = false
			# кисть области, метки, рамка выбора: палец не тянет карту
			_tool = colony != null and String(colony.drag_tool()) != ""
			if _tool and touches.size() == 1:
				colony.on_drag(st.position, true)
			if touches.size() == 2:
				var p: Array = touches.values()
				var a: Vector2 = p[0]
				var b: Vector2 = p[1]
				_pinch = a.distance_to(b)
				_angle = (b - a).angle()
		else:
			var was: Array = _down.get(st.index, [])
			touches.erase(st.index)
			_down.erase(st.index)
			var moved: bool = bool(_moved.get(st.index, true))
			_moved.erase(st.index)
			if _tool and touches.is_empty() and colony != null:
				colony.on_drag_end()
				_tool = colony != null and String(colony.drag_tool()) != ""
				return
			if not was.is_empty() and not moved and not _hold_sent and colony != null:
				var t0: float = was[1]
				if Time.get_ticks_msec() * 0.001 - t0 < TAP_T + 0.4:
					var p0: Vector2 = was[0]
					colony.on_tap(p0)
	elif e is InputEventScreenDrag:
		var dg := e as InputEventScreenDrag
		touches[dg.index] = dg.position
		var st0: Array = _down.get(dg.index, [])
		if not st0.is_empty():
			var p0: Vector2 = st0[0]
			if p0.distance_to(dg.position) > TAP_PX:
				_moved[dg.index] = true
		if touches.size() == 1:
			if _tool and colony != null:
				colony.on_drag(dg.position, true)
			elif bool(_moved.get(dg.index, false)):
				_pan(dg.relative)
		elif touches.size() == 2:
			var p: Array = touches.values()
			var a: Vector2 = p[0]
			var b: Vector2 = p[1]
			var d: float = a.distance_to(b)
			var ang: float = (b - a).angle()
			if _pinch > 0.0 and d > 1.0:
				want_dist = clampf(want_dist * _pinch / d, D_MIN, D_MAX)
			want_yaw -= wrapf(ang - _angle, -PI, PI)
			_pinch = d
			_angle = ang
			for i: int in _moved:
				_moved[i] = true
	elif e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			want_dist = clampf(want_dist * 0.88, D_MIN, D_MAX)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			want_dist = clampf(want_dist * 1.14, D_MIN, D_MAX)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_mouse_drag = mb.pressed
	elif e is InputEventMouseMotion and _mouse_drag:
		_pan((e as InputEventMouseMotion).relative)
	elif e is InputEventKey:
		var kv := e as InputEventKey
		if kv.pressed and colony != null and kv.keycode == KEY_TAB:
			colony.select_next()
