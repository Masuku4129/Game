extends RefCounted
## Procedural, physically motivated animation (locomotion + actions). See docs/ARCHITECTURE.md.
## * gait from dynamic similarity (Alexander): stride = 2.3*h*Fr^0.3, duty factor falls with speed
## * feet are planted in the world (no sliding), swing foot lands by Raibert's rule (hip + v*Ts/2)
## * pelvis height from stance-leg geometry (inverted-pendulum vaults, compressed spring when running)
## * lean from acceleration (a/g), centripetal roll in turns, spring-damper filters give inertia and weight

const RS = preload("res://scripts/rig_solver.gd")
const G := 9.81
const NAMES := ["pel", "prot", "spine", "head", "hr", "hl", "fl", "fr", "turn"]

class Spring:
	var x := Vector3.ZERO
	var v := Vector3.ZERO
	var w := 10.0
	var z := 1.0
	func _init(x0: Vector3 = Vector3.ZERO, omega: float = 10.0, zeta: float = 1.0) -> void:
		x = x0
		w = omega
		z = zeta
	func step(target: Vector3, dt: float) -> Vector3:
		var n := maxi(1, int(ceil(dt * w / 0.35)))
		var h := dt / float(n)
		for _i in n:
			var a := (target - x) * (w * w) - v * (2.0 * z * w)
			v += a * h
			x += v * h
		return x

class Foot:
	var planted := true
	var pin := Vector3.ZERO
	var pos := Vector3.ZERO
	var start := Vector3.ZERO
	var land := Vector3.ZERO
	var t := 0.0
	var T := 0.3
	var pitch := 0.0
	func _init(p: Vector3) -> void:
		pin = p
		pos = p
		start = p
		land = p

var solver
var actions := {}
var guard := {}

# state
var pos := Vector3.ZERO
var yaw := 0.0
var vel := Vector3.ZERO
var yaw_rate := 0.0
var phase := 0.0
var time := 0.0
var acc_f := 0.0
var speed_f := 0.0
var root_y := 0.0
var vy := 0.0
var state_name := "idle"

var hip_h := 1.135
var hipjoint_off := 0.1
var ankle_y := 0.16
var half_w := 0.085
var leg_max := 0.89
var arm_l := Vector2(0.18, 0.19)
var pel: Spring
var lean: Spring
var head_sp: Spring
var arm_sp: Array = []
var feet: Array = []

# action state
var act := {}                  # empty = none
var aw := 0.0
var sp := {}                   # action springs

func setup(solver_in) -> void:
	solver = solver_in
	var r = solver
	hip_h = r.rp("Hips").y
	hipjoint_off = r.rp("Hips").y - r.rp("LeftUpLeg").y
	ankle_y = 0.5 * (r.rp("LeftFoot").y + r.rp("RightFoot").y)
	half_w = 0.5 * (r.rp("LeftUpLeg").x - r.rp("RightUpLeg").x)
	leg_max = 0.5 * ((r.len_leg[0] as Vector2).x + (r.len_leg[0] as Vector2).y + (r.len_leg[1] as Vector2).x + (r.len_leg[1] as Vector2).y)
	arm_l = 0.5 * ((r.len_arm[0] as Vector2) + (r.len_arm[1] as Vector2))
	pel = Spring.new(Vector3(0, hip_h - 0.03, 0), 14.0, 0.85)
	lean = Spring.new(Vector3.ZERO, 9.0, 0.7)
	head_sp = Spring.new(Vector3.ZERO, 8.0, 0.6)
	arm_sp = [Spring.new(Vector3.ZERO, 12.0, 0.7), Spring.new(Vector3.ZERO, 12.0, 0.7)]
	feet = [Foot.new(Vector3(half_w, ankle_y, 0)), Foot.new(Vector3(-half_w, ankle_y, 0))]
	_load_actions()

func _load_actions() -> void:
	var f := FileAccess.open("res://assets/actions.json", FileAccess.READ)
	if f == null:
		push_error("actions.json missing")
		return
	var j = JSON.parse_string(f.get_as_text())
	actions = j["actions"]
	var g: Dictionary = j["guard"]
	for k in g.keys():
		guard[k] = _v3(g[k])

static func _v3(a) -> Vector3:
	if typeof(a) == TYPE_ARRAY:
		var arr: Array = a
		return Vector3(float(arr[0]), float(arr[1]) if arr.size() > 1 else 0.0, float(arr[2]) if arr.size() > 2 else 0.0)
	return Vector3(float(a), 0, 0)

static func smooth(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

static func interp(x: float, xs: Array, ys: Array) -> float:
	if x <= xs[0]:
		return ys[0]
	for i in range(1, xs.size()):
		if x <= xs[i]:
			var t: float = (x - xs[i - 1]) / (xs[i] - xs[i - 1])
			return lerpf(ys[i - 1], ys[i], t)
	return ys[ys.size() - 1]

static func wrap_pi(a: float) -> float:
	return fposmod(a + PI, TAU) - PI

func yaw_q() -> Quaternion:
	return Quaternion(Vector3.UP, yaw)

func busy() -> bool:
	return not act.is_empty() and act["phase"] != "done"

func gait_params(v: float) -> Array:
	var fr := v * v / (G * hip_h)
	var lam := 2.3 * hip_h * pow(maxf(fr, 1e-4), 0.3)
	var f := v / lam if v > 0.05 else 0.0
	var beta := interp(v, [0, 0.5, 1.4, 2.2, 3.4, 4.5, 6.5, 9], [0.70, 0.68, 0.62, 0.52, 0.42, 0.37, 0.31, 0.27])
	var g := smooth(2.2, 3.4, v)
	return [lam, f, beta, g]

# ---------------------------------------------------------------- public update
func update(dt: float, move_dir: Vector2, speed_target: float) -> RS.Pose:
	if act.is_empty():
		return _loco(dt, move_dir, speed_target)
	var a: Dictionary = actions[act["name"]]
	act["t"] += dt
	time += dt
	var pa: RS.Pose
	match a["type"]:
		"keys":
			pa = _step_keys(dt, a)
		"air":
			pa = _step_air(dt, a)
		_:
			pa = _step_roll(dt, a)
	if act["phase"] == "done":
		aw = maxf(0.0, aw - dt / 0.22)
	else:
		aw = minf(1.0, aw + dt / 0.09)
	if aw <= 0.0:
		act = {}
		return _loco(dt, move_dir, speed_target)
	if act["phase"] == "done":
		var pl := _loco(dt, move_dir, speed_target)
		return blend_pose(pl, pa, aw)
	return pa

func start(name: String) -> bool:
	if busy() or not actions.has(name):
		return false
	var a: Dictionary = actions[name]
	var ac := {"name": name, "t": 0.0, "k": 0, "kt": 0.0, "phase": "run", "impact": 0.0, "hz": Vector3.ZERO, "yaw0": yaw, "vz": 0.0, "t_air": 0.0}
	var fl := []
	for s in 2:
		fl.append({"planted": a["type"] != "keys", "pin": (feet[s] as Foot).pos, "pos": (feet[s] as Foot).pos})
	ac["feet"] = fl
	if a["type"] == "keys":
		var prev := {}
		for n in NAMES:
			prev[n] = guard[n] if n != "turn" else Vector3.ZERO
		ac["prev"] = prev
		sp = {}
		for n in NAMES:
			var hand: bool = (n == "hr" or n == "hl")
			sp[n] = Spring.new(prev[n], 38.0 if hand else 20.0, 0.62 if hand else 0.8)
		sp["vz"] = Spring.new(Vector3.ZERO, 18.0, 0.9)
	elif a["type"] == "air":
		ac["phase"] = "prep"
		sp = {"pel": Spring.new(Vector3.ZERO, 16.0, 0.75), "tuck": Spring.new(Vector3.ZERO, 18.0, 0.9), "arms": Spring.new(Vector3.ZERO, 14.0, 0.7)}
	else:
		sp = {"v": Spring.new(Vector3.ZERO, 20.0, 0.9)}
	act = ac
	state_name = name
	return true

# ---------------------------------------------------------------- pose blending
static func _qslerp_w(r1: Quaternion, r2: Quaternion, w: float) -> Quaternion:
	return r1.slerp(r2, w)

static func blend_pose(a: RS.Pose, b: RS.Pose, w: float) -> RS.Pose:
	if w <= 0.0:
		return a
	if w >= 1.0:
		return b
	var p := RS.Pose.new()
	p.hips_pos = a.hips_pos.lerp(b.hips_pos, w)
	p.hips_rot = a.hips_rot.slerp(b.hips_rot, w)
	for i in 3:
		p.spine[i] = a.spine[i].slerp(b.spine[i], w)
	p.neck = a.neck.slerp(b.neck, w)
	p.head = a.head.slerp(b.head, w)
	for s in 2:
		p.hand[s] = a.hand[s].lerp(b.hand[s], w)
		p.hand_pole[s] = a.hand_pole[s].lerp(b.hand_pole[s], w)
		p.foot[s] = a.foot[s].lerp(b.foot[s], w)
		p.foot_rot[s] = a.foot_rot[s].slerp(b.foot_rot[s], w)
		p.knee_pole[s] = a.knee_pole[s].lerp(b.knee_pole[s], w)
	return p

# ---------------------------------------------------------------- locomotion
func _loco(dt: float, move_dir: Vector2, speed_target: float) -> RS.Pose:
	time += dt
	var want := Vector3.ZERO
	if move_dir.length() > 0.001 and speed_target > 0.01:
		var md := move_dir.normalized()
		want = Vector3(md.x, 0, md.y) * speed_target
	var cur := vel
	var dv := want - cur
	var amax := 7.0 if want.length() > cur.length() else 9.0
	var nn := dv.length()
	if nn > amax * dt:
		dv = dv / nn * amax * dt
	var newv := cur + dv
	var acc := (newv - cur) / dt
	vel = newv
	pos += newv * dt
	var spd := vel.length()
	if spd > 0.3:
		var tgt := atan2(vel.x, vel.z)
		var d := wrap_pi(tgt - yaw)
		var rate_max := 9.0 if spd < 3.0 else 6.5
		yaw_rate = clampf(d * 8.0, -rate_max, rate_max)
	else:
		yaw_rate *= exp(-8.0 * dt)
	yaw += yaw_rate * dt
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var left := Vector3(cos(yaw), 0, -sin(yaw))
	var a_long := acc.dot(fwd)
	acc_f += (a_long - acc_f) * minf(1.0, dt * 8.0)
	speed_f = spd
	var gp := gait_params(spd)
	var f: float = gp[1]
	var beta: float = gp[2]
	var g: float = gp[3]
	if f > 0.0:
		phase = fmod(phase + f * dt, 1.0)
	var moving := spd > 0.12
	var Yaw := yaw_q()
	var Yinv := Yaw.inverse()
	var want_len := want.length()
	var Lmax := leg_max
	# ---- feet
	for s in 2:
		var ft: Foot = feet[s]
		var side := 1.0 if s == 0 else -1.0
		var off := 0.0 if s == 0 else 0.5
		var ph := fmod(phase + off, 1.0)
		var want_stance := (ph < beta) if moving else true
		if moving:
			if ft.planted and not want_stance:
				ft.planted = false
				ft.start = ft.pos
				ft.t = 0.0
				ft.T = maxf((1.0 - beta) / maxf(f, 1e-3), 0.12)
			elif (not ft.planted) and want_stance and ft.t >= ft.T * 0.85:
				ft.planted = true
				ft.pin = ft.pos
		else:
			var other: Foot = feet[1 - s]
			if (not ft.planted) and ft.t >= ft.T * 0.999:
				ft.planted = true
				ft.pin = ft.pos
			elif ft.planted and other.planted:
				var des := pos + Yaw * Vector3(side * half_w, 0, 0)
				var err := Vector2(ft.pin.x - des.x, ft.pin.z - des.z).length()
				var des_o := pos + Yaw * Vector3(-side * half_w, 0, 0)
				var err_o := Vector2(other.pin.x - des_o.x, other.pin.z - des_o.z).length()
				if err > 0.10 and err >= err_o:
					ft.planted = false
					ft.start = ft.pos
					ft.t = 0.0
					ft.T = 0.34
		if ft.planted:
			ft.pos = ft.pin
			ft.pitch += (0.0 - ft.pitch) * minf(1.0, dt * 10.0)
		else:
			ft.t += dt
			var u := minf(ft.t / ft.T, 1.0)
			var pred_pos := pos + vel * maxf(ft.T - ft.t, 0.0)
			var stance_travel := spd * beta / maxf(f, 1e-3) if f > 0.0 else 0.0
			var ahead := 0.5 * stance_travel
			var dirv := vel / spd if spd > 0.05 else fwd
			var lat := left * side * (half_w + 0.02 * smooth(0.0, 1.5, spd))
			var land := pred_pos + dirv * ahead + lat
			if not moving:
				land = pos + Yaw * Vector3(side * half_w, 0, 0)
			land.y = ankle_y
			ft.land = land
			var s5 := u * u * u * (10.0 - 15.0 * u + 6.0 * u * u)
			var p := ft.start + (ft.land - ft.start) * s5
			var clr := 0.045 + 0.13 * g + 0.02 * smooth(0.0, 1.4, spd)
			var h_ := clr * pow(sin(PI * minf(pow(u, 0.75), 1.0)), 1.2)
			p.y = ankle_y + h_
			ft.pos = p
			ft.pitch = -30.0 * pow(1.0 - u, 3.0) + 12.0 * u * u * u
	# ---- pelvis height from stance-leg geometry
	var Lc := Lmax * (0.985 - 0.05 * g - 0.01 * smooth(0.0, 1.0, spd))
	var hips_y := 0.0
	var have_y := false
	var anyp := false
	for s in 2:
		var ft: Foot = feet[s]
		if ft.planted:
			anyp = true
			var loc := Yinv * (ft.pos - pos)
			var hj := half_w * (1.0 if s == 0 else -1.0)
			var dxz := Vector2(loc.x - pel.x.x - hj, loc.z - pel.x.z).length()
			var hy := ft.pos.y + sqrt(maxf(Lc * Lc - dxz * dxz, 0.0)) + hipjoint_off
			if not have_y:
				hips_y = hy
				have_y = true
			else:
				hips_y = minf(hips_y, hy)
	if not have_y:
		hips_y = pel.x.y
	var tgt_y := hips_y
	if not anyp:
		tgt_y = hip_h - 0.03 + 0.06 * g
	var l_pl := 1.0 if (feet[0] as Foot).planted else 0.0
	var r_pl := 1.0 if (feet[1] as Foot).planted else 0.0
	var sway := 0.02 * smooth(0.3, 1.5, spd) * (l_pl - r_pl) * (1.0 - 0.5 * g)
	pel.w = 16.0
	pel.z = 0.8
	pel.step(Vector3(sway, tgt_y, 0.0), dt)
	# ---- upper body
	var lean_p := rad_to_deg(atan(acc_f / G)) * 0.9 + 1.1 * spd + 2.0 * g
	lean_p = clampf(lean_p, -12.0, 28.0)
	var lean_r := -rad_to_deg(atan(spd * yaw_rate / G)) * 0.8
	lean_r = clampf(lean_r, -18.0, 18.0)
	lean.step(Vector3(lean_p, lean_r, 0), dt)
	var fl_pos: Vector3 = (feet[0] as Foot).pos
	var fr_pos: Vector3 = (feet[1] as Foot).pos
	var zL := (Yinv * (fl_pos - pos)).z
	var zR := (Yinv * (fr_pos - pos)).z
	var yL := fl_pos.y - ankle_y
	var yR := fr_pos.y - ankle_y
	var stride_amp := zL - zR
	var move_k := smooth(0.1, 1.0, spd)
	var pel_yaw := -stride_amp * (7.0 + 3.0 * g) * move_k
	var pel_roll := -(yL - yR) * (28.0 + 20.0 * g) * move_k
	var pitch_total := lean.x.x
	var roll_total := lean.x.y
	var t := time
	var breath := sin(t * TAU * 0.26)
	var idle_k := 1.0 - move_k
	var pel_rot := RS.rot3(0.25 * pitch_total + 1.0 * idle_k * sin(t * 0.7) * 0.3, pel_yaw, pel_roll + 0.25 * roll_total)
	var sp_yaw := -0.6 * pel_yaw / 3.0
	var P := RS.Pose.new()
	for k in 3:
		P.spine[k] = RS.rot3(0.25 * pitch_total + 0.5 * idle_k * breath * (k + 1) * 0.35, sp_yaw * 1.9, 0.25 * roll_total - 0.2 * pel_roll)
	var head_pitch := -0.6 * pitch_total + 3.0
	var hs := head_sp.step(Vector3(head_pitch, 0, 0), dt)
	P.neck = RS.rot3(hs.x * 0.5, -0.5 * (pel_yaw * 0.6 + sp_yaw * 5.7) * 0.5, -0.4 * roll_total)
	P.head = RS.rot3(hs.x * 0.5, 0.0, -0.4 * roll_total)
	var hips_world := pos + Yaw * Vector3(pel.x.x, 0, pel.x.z)
	hips_world.y = pel.x.y
	P.hips_pos = hips_world
	P.hips_rot = Yaw * pel_rot
	for s in 2:
		var ft: Foot = feet[s]
		var side := 1.0 if s == 0 else -1.0
		P.foot[s] = ft.pos
		P.foot_rot[s] = Yaw * RS.rot_x(ft.pitch)
		P.knee_pole[s] = Yaw * Vector3(0.10 * side, 0.0, 1.0)
	# arms: counter swing, amplitude with speed, elbow flexion grows with run
	var sw_k := smooth(0.2, 1.3, spd)
	var zs := [zL, zR]
	var arm_ang: Array = []
	for s in 2:
		var zo: float = zs[1 - s] - zs[s]
		var theta := zo * (22.0 + 20.0 * g) * sw_k
		theta += 3.0 * idle_k
		var eps := 8.0 + 14.0 * sw_k + 70.0 * g
		arm_ang.append((arm_sp[s] as Spring).step(Vector3(theta, eps, 0), dt))
	_solve_arms(P, arm_ang)
	if spd < 0.2:
		state_name = "idle"
	elif spd < 2.6:
		state_name = "walk"
	elif spd < 5.6:
		state_name = "run"
	else:
		state_name = "sprint"
	return P

func _solve_arms(P: RS.Pose, ang: Array) -> void:
	P.hand = [P.hips_pos, P.hips_pos]
	solver.solve(P)
	var l1 := arm_l.x
	var l2 := arm_l.y
	var Dc: Quaternion = solver.D[solver.idx["Spine"]]
	var yaw_c := Basis(Dc).get_euler(EULER_ORDER_YXZ).y
	var Yc := Quaternion(Vector3.UP, yaw_c)
	for s in 2:
		var side := 1.0 if s == 0 else -1.0
		var arm_name := "LeftArm" if s == 0 else "RightArm"
		var S: Vector3 = solver.P[solver.idx[arm_name]]
		var a: Vector3 = ang[s]
		var th: float = a.x
		var ep: float = a.y
		var E := S + Yc * (RS.rot_x(-th) * Vector3(0, -l1, 0))
		var H := E + Yc * (RS.rot_x(-(th + ep)) * Vector3(0, -l2, 0))
		H += Yc * Vector3(0.035 * side, 0, 0)
		P.hand[s] = H
		P.hand_pole[s] = Yc * Vector3(0.35 * side, -0.15, -1.0)

# ---------------------------------------------------------------- keyed actions (punch, spin kick)
func _ease(kind: String, u: float) -> float:
	if kind == "in":
		return u * u
	if kind == "out":
		return 1.0 - (1.0 - u) * (1.0 - u)
	return u * u * (3.0 - 2.0 * u)

func _key_val(key: Dictionary, n: String) -> Vector3:
	if n == "turn":
		return Vector3(float(key["turn"]), 0, 0)
	return _v3(key[n])

func _step_keys(dt: float, a: Dictionary) -> RS.Pose:
	var keys: Array = a["keys"]
	var k: int = act["k"]
	if k >= keys.size():
		act["phase"] = "done"
		return _pose_keys(dt, {}, 0.0)
	var key: Dictionary = keys[k]
	act["kt"] += dt
	var u := minf(act["kt"] / float(key["t"]), 1.0)
	var e := _ease(key["ease"], u)
	var prm := {}
	var prev: Dictionary = act["prev"]
	for n in NAMES:
		prm[n] = (prev[n] as Vector3).lerp(_key_val(key, n), e)
	var vz: float = float(key["v"]) if u > 0.05 else float(act["vz"])
	act["vz"] = vz
	if u >= 1.0:
		var flags := [key["pl"], key["pr"]]
		for s in 2:
			var f: Dictionary = (act["feet"] as Array)[s]
			if flags[s] and not f["planted"]:
				f["planted"] = true
				f["pin"] = f["pos"]
			if (not flags[s]) and f["planted"]:
				f["planted"] = false
		var np := {}
		for n in NAMES:
			np[n] = _key_val(key, n)
		act["prev"] = np
		act["k"] += 1
		act["kt"] = 0.0
		if act["k"] >= keys.size():
			act["phase"] = "done"
	return _pose_keys(dt, prm, vz)

func _pose_keys(dt: float, prm: Dictionary, vz: float) -> RS.Pose:
	if prm.is_empty():
		prm = act["prev"]
	for n in NAMES:
		(sp[n] as Spring).step(prm[n], dt)
	yaw = float(act["yaw0"]) + deg_to_rad((sp["turn"] as Spring).x.x)
	var Yaw := yaw_q()
	(sp["vz"] as Spring).step(Vector3(vz, 0, 0), dt)
	vel = Yaw * Vector3(0, 0, (sp["vz"] as Spring).x.x)
	pos += vel * dt
	var root := pos
	var P := RS.Pose.new()
	var pl: Vector3 = (sp["pel"] as Spring).x
	var hp := root + Yaw * Vector3(pl.x, 0, pl.z)
	hp.y = hip_h + pl.y
	P.hips_pos = hp
	var pr: Vector3 = (sp["prot"] as Spring).x
	P.hips_rot = Yaw * RS.rot3(pr.x, pr.y, pr.z)
	var spn: Vector3 = (sp["spine"] as Spring).x
	var w3 := [0.25, 0.35, 0.40]
	for i in 3:
		P.spine[i] = RS.rot3(spn.x * w3[i], spn.y * w3[i], spn.z * w3[i])
	var hd: Vector3 = (sp["head"] as Spring).x
	P.neck = RS.rot3(hd.x * 0.4, hd.y * 0.4, 0)
	P.head = RS.rot3(hd.x * 0.6, hd.y * 0.6, 0)
	P.hand[1] = root + Yaw * (sp["hr"] as Spring).x
	P.hand[0] = root + Yaw * (sp["hl"] as Spring).x
	P.hand_pole[1] = Yaw * Vector3(-0.55, -0.45, -0.45)
	P.hand_pole[0] = Yaw * Vector3(0.55, -0.45, -0.45)
	var fnames := ["fl", "fr"]
	for s in 2:
		var f: Dictionary = (act["feet"] as Array)[s]
		var v: Vector3 = (sp[fnames[s]] as Spring).x
		if f["planted"]:
			f["pos"] = f["pin"]
		else:
			var tgt := root + Yaw * Vector3(v.x, 0, v.z)
			tgt.y = ankle_y + v.y
			var delta := tgt - (f["pos"] as Vector3)
			var np := (f["pos"] as Vector3) + delta * minf(1.0, dt * 14.0)
			np.y += 0.07 * minf(1.0, Vector2(delta.x, delta.z).length() * 4.0) * minf(1.0, dt * 14.0)
			np.y = maxf(ankle_y, np.y)
			f["pos"] = np
		var fp: Vector3 = f["pos"]
		P.foot[s] = fp
		var loc := Yaw.inverse() * (fp - root)
		var pitch := 0.0
		if loc.z < 0.0:
			pitch = -clampf((-loc.z - 0.15) * 70.0, 0.0, 28.0)
		var flat: bool = f["planted"] or fp.y > ankle_y + 0.2
		P.foot_rot[s] = Yaw * RS.rot_x(0.0 if flat else pitch)
		P.knee_pole[s] = Yaw * Vector3(0.10 * (1.0 if s == 0 else -1.0), 0, 1.0)
	_sync_loco(hp)
	return P

func _sync_loco(hp: Vector3) -> void:
	for s in 2:
		var ft: Foot = feet[s]
		ft.pos = (act["feet"] as Array)[s]["pos"]
		ft.pin = ft.pos
		ft.planted = true
	pel.x = Vector3(0, hp.y, 0)
	pel.v = Vector3.ZERO
	lean.x = Vector3.ZERO
	lean.v = Vector3.ZERO

# ---------------------------------------------------------------- roll
func _step_roll(dt: float, a: Dictionary) -> RS.Pose:
	var dur: float = a["dur"]
	var spd_r: float = a["speed"]
	var u := minf(float(act["t"]) / dur, 1.0)
	var Yaw := yaw_q()
	var tuck := smooth(0.10, 0.28, u) * (1.0 - smooth(0.74, 0.92, u))
	var th := 360.0 * smooth(0.16, 0.80, u)
	var vt := spd_r * smooth(0.0, 0.18, u) * (1.0 - 0.35 * smooth(0.75, 1.0, u))
	var v := (sp["v"] as Spring).step(Vector3(vt, 0, 0), dt).x
	vel = Yaw * Vector3(0, 0, v)
	pos += vel * dt
	var root := pos
	var stand := hip_h - 0.07
	var bump := 0.05 * sin(PI * clampf((u - 0.2) / 0.55, 0.0, 1.0))
	var hy := stand * (1.0 - tuck) + (0.50 + bump) * tuck
	var hp := root + Yaw * Vector3(0, 0, 0.10 * tuck)
	hp.y = hy
	var P := RS.Pose.new()
	P.hips_pos = hp
	var Hr := Yaw * RS.rot_x(th)
	P.hips_rot = Hr
	for i in 3:
		P.spine[i] = RS.rot_x(14.0 * tuck)
	P.neck = RS.rot_x(14.0 * tuck)
	P.head = RS.rot_x(10.0 * tuck)
	for s in 2:
		var side := 1.0 if s == 0 else -1.0
		var stand_foot := root + Yaw * Vector3(side * half_w, 0, 0.10 * side)
		stand_foot.y = ankle_y
		var tuck_foot := hp + Hr * Vector3(side * 0.13, -0.22, 0.32)
		P.foot[s] = stand_foot.lerp(tuck_foot, tuck)
		var r16 := smooth(0.0, 0.16, u)
		var stand_hand := hp + Yaw * Vector3(side * 0.30, 0.05 + 0.15 * r16, 0.10 + 0.30 * r16 * (1.0 - tuck))
		var tuck_hand := hp + Hr * Vector3(side * 0.24, 0.40, 0.34)
		P.hand[s] = stand_hand.lerp(tuck_hand, tuck)
		P.foot_rot[s] = Hr
		P.knee_pole[s] = Hr * Vector3(0.10 * side, 0.2, 1.0)
		P.hand_pole[s] = Hr * Vector3(side * 0.7, -0.2, -0.5)
	var fl: Array = act["feet"]
	for s in 2:
		(fl[s] as Dictionary)["pos"] = P.foot[s]
	if u >= 1.0:
		act["phase"] = "done"
		vel = Yaw * Vector3(0, 0, spd_r * 0.65)
	_sync_loco(hp)
	return P

# ---------------------------------------------------------------- jump
func _step_air(dt: float, a: Dictionary) -> RS.Pose:
	var Yaw := yaw_q()
	var ph: String = act["phase"]
	var pel_dy := 0.0
	var spine_p := 0.0
	var tuck := 0.0
	var arms := 0.0
	var fl: Array = act["feet"]
	if ph == "prep":
		var u := minf(float(act["t"]) / float(a["prep"]), 1.0)
		var e := u * u * (3.0 - 2.0 * u)
		pel_dy = -0.30 * e
		spine_p = 16.0 * e
		arms = -e
		if u >= 1.0:
			ph = "air"
			act["phase"] = "air"
			act["hz"] = vel + Yaw * Vector3(0, 0, float(a["vz"]))
			vy = float(a["vy"])
			root_y = 0.0
			act["t_air"] = 0.0
			for s in 2:
				(fl[s] as Dictionary)["planted"] = false
	if ph == "air":
		act["t_air"] += dt
		vy -= G * dt
		root_y += vy * dt
		pos += (act["hz"] as Vector3) * dt
		vel = act["hz"]
		var t_land := 9.0
		if vy < 3.0:
			t_land = (vy + sqrt(maxf(vy * vy + 2.0 * G * maxf(root_y, 0.0), 0.0))) / G
		var up := smooth(0.0, 0.18, act["t_air"])
		var ext := 1.0 - smooth(0.06, 0.22, t_land)
		tuck = up * ext * float(a["tuck"])
		spine_p = -4.0 + 8.0 * tuck
		arms = 0.6 * up * ext + 0.3
		if root_y <= 0.0 and vy < 0.0 and float(act["t_air"]) > 0.05:
			act["impact"] = -vy
			root_y = 0.0
			ph = "land"
			act["phase"] = "land"
			act["t"] = 0.0
			var offs := [Vector3(0.14, 0, 0.10), Vector3(-0.14, 0, -0.10)]
			for s in 2:
				var f: Dictionary = fl[s]
				f["planted"] = true
				var pin := pos + Yaw * (offs[s] as Vector3)
				pin.y = ankle_y
				f["pin"] = pin
			vel = (act["hz"] as Vector3) * 0.6
	if ph == "land":
		var u2 := minf(float(act["t"]) / float(a["land"]), 1.0)
		var imp := clampf(float(act["impact"]) / 6.0, 0.25, 1.0)
		var comp := 0.0
		if u2 < 0.35:
			comp = 0.30 * imp * sin(PI * minf(u2 / 0.35, 1.0) * 0.5)
		else:
			comp = 0.30 * imp * (1.0 - smooth(0.35, 1.0, u2))
		pel_dy = -comp
		spine_p = 14.0 * comp / 0.30 * imp
		arms = -0.2
		vel = vel * exp(-6.0 * dt)
		pos += vel * dt
		if u2 >= 1.0:
			act["phase"] = "done"
	var s_pel := (sp["pel"] as Spring).step(Vector3(0, pel_dy, 0), dt)
	var s_tuck := (sp["tuck"] as Spring).step(Vector3(tuck, 0, 0), dt).x
	var s_arms := (sp["arms"] as Spring).step(Vector3(arms, 0, 0), dt).x
	var root := pos
	var hp := root
	hp.y = hip_h + s_pel.y + root_y
	var P := RS.Pose.new()
	P.hips_pos = hp
	P.hips_rot = Yaw * RS.rot3(spine_p * 0.2, 0, 0)
	for i in 3:
		P.spine[i] = RS.rot3(spine_p * 0.27, 0, 0)
	P.neck = RS.rot3(-spine_p * 0.2, 0, 0)
	P.head = RS.rot3(-spine_p * 0.2, 0, 0)
	ph = act["phase"]
	for s in 2:
		var f: Dictionary = fl[s]
		var side := 1.0 if s == 0 else -1.0
		var fpos: Vector3
		if f["planted"] and (ph == "prep" or ph == "land"):
			var pin: Vector3 = f["pin"]
			pin.y = ankle_y
			f["pin"] = pin
			fpos = pin
		else:
			var lead := 1.0 if s == 0 else 0.6
			var zz := 0.30 * s_tuck * lead + 0.12 * (1.0 - s_tuck) * (1.0 if s == 0 else -0.6)
			fpos = root + Yaw * Vector3(side * (half_w - 0.02), 0, zz)
			fpos.y = maxf(ankle_y, root_y + ankle_y + 0.52 * s_tuck * (1.0 if s == 0 else 0.8))
		f["pos"] = fpos
		P.foot[s] = fpos
		P.foot_rot[s] = Yaw * RS.rot_x(-18.0 * s_tuck if ph == "air" else 0.0)
		P.knee_pole[s] = Yaw * Vector3(0.10 * side, 0, 1.0)
		var e2 := s_arms
		P.hand[s] = hp + Yaw * Vector3(side * (0.30 + 0.30 * maxf(e2, 0.0)), 0.42 + 0.22 * maxf(e2, 0.0) - 0.10 * maxf(-e2, 0.0), 0.05 + 0.10 * maxf(e2, 0.0) - 0.34 * maxf(-e2, 0.0))
		P.hand_pole[s] = Yaw * Vector3(side * 0.4, -0.3, -0.6)
	_sync_loco(hp)
	for s in 2:
		(feet[s] as Foot).planted = (ph != "air")
	return P
