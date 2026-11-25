extends RefCounted
## Проигрывание реальных mocap-клипов (CMU, переносены офлайн на скелет Миты: tools/export_clips.py).
## Поверх клипов: инерция движения (разгон/торможение), поворот корпуса, наклон в поворотах,
## синхронизация темпа шагов со скоростью (стопы не скользят), плавные переходы по фазе шага.
const RS = preload("res://scripts/rig_solver.gd")

const FPF := 59                     # float на кадр (см. tools/retarget_clips.pose_to_flat)
const ACTIONS := ["jump", "roll", "punch", "spinkick"]

class Clip:
	var data := PackedFloat32Array()
	var n := 0
	var dur := 1.0
	var loop := false
	var speed := 0.0                # скорость «беговой дорожки», м/с (у петель ходьбы/бега)

# параметры действий: темп, начало/конец толчка вперёд (доли клипа), скорость толчка, цель поворота
const ACT := {
	"jump": {"rate": 1.0, "push": [0.0, 0.0], "v": 0.0, "fist": 0.35},
	"roll": {"rate": 1.0, "push": [0.10, 0.72], "v": 3.8, "fist": 0.8},
	"punch": {"rate": 1.15, "push": [0.10, 0.45], "v": 0.7, "fist": 1.0},
	"spinkick": {"rate": 1.1, "push": [0.15, 0.55], "v": 0.9, "fist": 1.0},
}

var clips := {}
var pos := Vector3.ZERO
var vel := Vector3.ZERO
var yaw := 0.0
var state_name := "idle"
var fist := 0.0                      # 0..1 сжатие кулаков (шейдер)

var _mode := "loco"                  # loco | act
var _gait := "idle"
var _t := 0.0
var _act := ""
var _act_t := 0.0
var _act_yaw := 0.0
var _yaw_rate := 0.0
var _bank := 0.0
var _last_local: RS.Pose = null
var _last_world: RS.Pose = null
var _from: RS.Pose = null
var _blend_t := 1.0
var _blend_dur := 0.2
var _fist_target := 0.15

func setup(_solver) -> void:
	var f := FileAccess.open("res://assets/clips.json", FileAccess.READ)
	if f == null:
		push_error("clips.json missing")
		return
	var j = JSON.parse_string(f.get_as_text())
	var cd: Dictionary = j["clips"]
	for k in cd.keys():
		var c := Clip.new()
		var cj: Dictionary = cd[k]
		c.loop = bool(cj["loop"])
		c.dur = float(cj["dur"])
		c.speed = float(cj["speed"])
		var frames: Array = cj["frames"]
		c.n = frames.size()
		var arr := PackedFloat32Array()
		for fr in frames:
			for v in fr:
				arr.append(float(v))
		c.data = arr
		clips[k] = c
	_last_local = sample("idle", 0.0)
	_last_world = _to_world(_last_local, 0.0, Vector3.ZERO)

func busy() -> bool:
	return _mode == "act"

func yaw_q() -> Quaternion:
	return Quaternion(Vector3.UP, yaw)

# ---------------------------------------------------------------- выборка клипа
static func _q(d: PackedFloat32Array, o: int) -> Quaternion:
	return Quaternion(d[o], d[o + 1], d[o + 2], d[o + 3])

static func _v(d: PackedFloat32Array, o: int) -> Vector3:
	return Vector3(d[o], d[o + 1], d[o + 2])

func _decode(c: Clip, fr: int) -> RS.Pose:
	var d := c.data
	var o := fr * FPF
	var p := RS.Pose.new()
	p.hips_pos = _v(d, o)
	p.hips_rot = _q(d, o + 3)
	p.spine[0] = _q(d, o + 7)
	p.spine[1] = _q(d, o + 11)
	p.spine[2] = _q(d, o + 15)
	p.neck = _q(d, o + 19)
	p.head = _q(d, o + 23)
	p.hand[0] = _v(d, o + 27)
	p.hand_pole[0] = _v(d, o + 30)
	p.hand[1] = _v(d, o + 33)
	p.hand_pole[1] = _v(d, o + 36)
	p.foot[0] = _v(d, o + 39)
	p.foot_rot[0] = _q(d, o + 42)
	p.knee_pole[0] = _v(d, o + 46)
	p.foot[1] = _v(d, o + 49)
	p.foot_rot[1] = _q(d, o + 52)
	p.knee_pole[1] = _v(d, o + 56)
	return p

func sample(name: String, t: float) -> RS.Pose:
	var c: Clip = clips[name]
	var u := t * float(c.n) / c.dur if c.loop else t * float(c.n - 1) / c.dur
	var i0: int
	var fr: float
	if c.loop:
		u = fposmod(u, float(c.n))
		i0 = int(floor(u))
		fr = u - float(i0)
		i0 = i0 % c.n
		return blend_pose(_decode(c, i0), _decode(c, (i0 + 1) % c.n), fr)
	u = clampf(u, 0.0, float(c.n - 1))
	i0 = mini(int(floor(u)), c.n - 2)
	fr = u - float(i0)
	return blend_pose(_decode(c, i0), _decode(c, i0 + 1), fr)

# ---------------------------------------------------------------- вспомогательное
static func blend_pose(a: RS.Pose, b: RS.Pose, w: float) -> RS.Pose:
	var p := RS.Pose.new()
	p.hips_pos = a.hips_pos.lerp(b.hips_pos, w)
	p.hips_rot = a.hips_rot.slerp(b.hips_rot, w)
	for i in 3:
		p.spine[i] = a.spine[i].slerp(b.spine[i], w)
	p.neck = a.neck.slerp(b.neck, w)
	p.head = a.head.slerp(b.head, w)
	for s in 2:
		p.hand[s] = a.hand[s].lerp(b.hand[s], w)
		p.hand_pole[s] = a.hand_pole[s].lerp(b.hand_pole[s], w).normalized()
		p.foot[s] = a.foot[s].lerp(b.foot[s], w)
		p.foot_rot[s] = a.foot_rot[s].slerp(b.foot_rot[s], w)
		p.knee_pole[s] = a.knee_pole[s].lerp(b.knee_pole[s], w).normalized()
	return p

static func _to_world(p: RS.Pose, yaw_a: float, origin: Vector3) -> RS.Pose:
	var qy := Quaternion(Vector3.UP, yaw_a)
	var qi := qy.inverse()
	var q := RS.Pose.new()
	q.hips_pos = origin + qy * p.hips_pos
	q.hips_rot = qy * p.hips_rot * qi
	for i in 3:
		q.spine[i] = qy * p.spine[i] * qi
	q.neck = qy * p.neck * qi
	q.head = qy * p.head * qi
	for s in 2:
		q.hand[s] = origin + qy * p.hand[s]
		q.hand_pole[s] = qy * p.hand_pole[s]
		q.foot[s] = origin + qy * p.foot[s]
		q.foot_rot[s] = qy * p.foot_rot[s] * qi
		q.knee_pole[s] = qy * p.knee_pole[s]
	return q

static func wrap_pi(a: float) -> float:
	return fposmod(a + PI, TAU) - PI

static func _smooth(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

# положение стоп относительно таза: по нему подбираем фазу шага при смене клипа
func _match_phase(name: String, ref: RS.Pose) -> float:
	var c: Clip = clips[name]
	var r0 := ref.foot[0] - ref.hips_pos
	var r1 := ref.foot[1] - ref.hips_pos
	var best := 1e9
	var bi := 0
	for i in c.n:
		var p := _decode(c, i)
		var e := (p.foot[0] - p.hips_pos - r0).length_squared() + (p.foot[1] - p.hips_pos - r1).length_squared()
		if e < best:
			best = e
			bi = i
	return float(bi) / float(c.n) * c.dur

func _begin_blend(dur: float) -> void:
	_from = _last_world
	_blend_t = 0.0
	_blend_dur = maxf(dur, 0.01)

# ---------------------------------------------------------------- действия
func start(name: String) -> bool:
	if _mode == "act" or not ACTIONS.has(name):
		return false
	_begin_blend(0.14)
	_mode = "act"
	_act = name
	_act_t = 0.0
	_act_yaw = yaw
	_fist_target = ACT[name]["fist"]
	state_name = name
	return true

# ---------------------------------------------------------------- главный шаг
func update(dt: float, move_dir: Vector2, speed_target: float) -> RS.Pose:
	var local: RS.Pose
	var prev_yaw := yaw
	if _mode == "act":
		local = _step_action(dt, move_dir, speed_target)
	else:
		local = _step_loco(dt, move_dir, speed_target)
	_yaw_rate = lerpf(_yaw_rate, wrap_pi(yaw - prev_yaw) / maxf(dt, 1e-4), 1.0 - exp(-12.0 * dt))
	_last_local = local
	var w := _to_world(local, yaw, Vector3(pos.x, 0.0, pos.z))
	# наклон корпуса к центру поворота (центростремительное ускорение)
	var spd := Vector2(vel.x, vel.z).length()
	var bank_t := 0.0
	if _mode == "loco" and spd > 1.0:
		bank_t = clampf(atan(spd * _yaw_rate / 9.81) * 0.85, -0.38, 0.38)
	_bank = lerpf(_bank, bank_t, 1.0 - exp(-8.0 * dt))
	if absf(_bank) > 0.002:
		var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
		w.hips_rot = Quaternion(fwd, -_bank) * w.hips_rot
	# плавный переход от предыдущей позы
	if _blend_t < _blend_dur and _from != null:
		_blend_t += dt
		w = blend_pose(_from, w, _smooth(_blend_t / _blend_dur))
	_last_world = w
	fist = lerpf(fist, _fist_target, 1.0 - exp(-14.0 * dt))
	return w

func _step_loco(dt: float, move_dir: Vector2, speed_target: float) -> RS.Pose:
	var want := Vector3.ZERO
	if move_dir.length() > 0.1 and speed_target > 0.01:
		want = Vector3(move_dir.x, 0.0, move_dir.y).normalized() * speed_target
	var dv := want - vel
	var acc := 7.5 if want.length() > vel.length() else 10.0
	var step := acc * dt
	vel = want if dv.length() <= step else vel + dv.normalized() * step
	pos += vel * dt
	var v := vel.length()
	# поворот корпуса по направлению движения
	if v > 0.3:
		var ty := atan2(vel.x, vel.z)
		var diff := wrap_pi(ty - yaw)
		var rate := clampf(diff * 9.0, -13.0, 13.0)
		yaw = wrap_pi(yaw + rate * dt)
	elif move_dir.length() > 0.1:
		var diff2 := wrap_pi(atan2(move_dir.x, move_dir.y) - yaw)
		yaw = wrap_pi(yaw + clampf(diff2 * 8.0, -10.0, 10.0) * dt)
	# выбор шага (гистерезис)
	var g := _gait
	if g == "idle":
		if v > 0.35:
			g = "walk"
	elif g == "walk":
		if v < 0.2:
			g = "idle"
		elif v > 3.1:
			g = "run"
	else:
		if v < 2.3:
			g = "walk"
	if g != _gait:
		var old := _gait
		_gait = g
		_begin_blend(0.28 if g == "idle" else 0.22)
		_t = 0.0 if g == "idle" else _match_phase(g, _last_local)
		if old == "idle" and g == "walk":
			_t = _match_phase(g, _last_local)
	var c: Clip = clips[_gait]
	if _gait == "idle":
		_t = fposmod(_t + dt, c.dur)
		_fist_target = 0.12
	else:
		var rate2 := clampf(v / c.speed, 0.25, 1.9 if _gait == "run" else 1.7)
		_t = fposmod(_t + dt * rate2, c.dur)
		_fist_target = 0.45 if _gait == "run" else 0.2
	state_name = _gait
	if _gait == "run" and v > 6.0:
		state_name = "sprint"
	return sample(_gait, _t)

func _step_action(dt: float, move_dir: Vector2, speed_target: float) -> RS.Pose:
	var prm: Dictionary = ACT[_act]
	var c: Clip = clips[_act]
	_act_t += dt * float(prm["rate"])
	var u := _act_t / c.dur
	# разворот к направлению ввода в начале действия
	if _act_t < 0.14 and move_dir.length() > 0.3 and _act != "jump":
		_act_yaw = atan2(move_dir.x, move_dir.y)
	var diff := wrap_pi(_act_yaw - yaw)
	if absf(diff) > 0.001 and _act != "jump":
		yaw = wrap_pi(yaw + clampf(diff * 16.0, -16.0, 16.0) * dt)
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	var push: Array = prm["push"]
	if _act == "jump":
		# в полёте сохраняем импульс, управление слабое
		var want := Vector3.ZERO
		if move_dir.length() > 0.1:
			want = Vector3(move_dir.x, 0.0, move_dir.y).normalized() * minf(speed_target, 4.5)
		vel = vel.move_toward(want, 2.5 * dt)
		if u < 0.12 or u > 0.78:
			vel = vel.move_toward(Vector3.ZERO, 6.0 * dt)
	elif u >= float(push[0]) and u <= float(push[1]):
		var k := (u - float(push[0])) / (float(push[1]) - float(push[0]))
		vel = fwd * float(prm["v"]) * sin(k * PI)
	else:
		vel = vel.move_toward(Vector3.ZERO, 12.0 * dt)
	pos += vel * dt
	# кулаки сжаты только на время самого действия
	var tgt: float = prm["fist"]
	if _act == "punch" or _act == "spinkick":
		tgt = tgt * (_smooth(u / 0.12) * (1.0 - _smooth((u - 0.82) / 0.18)))
	_fist_target = tgt
	var local := sample(_act, minf(_act_t, c.dur))
	if _act_t >= c.dur:
		_mode = "loco"
		_begin_blend(0.25)
		var spd := vel.length()
		_gait = "walk" if spd > 0.5 else "idle"
		_t = _match_phase(_gait, local) if _gait != "idle" else 0.0
		state_name = _gait
	return local
