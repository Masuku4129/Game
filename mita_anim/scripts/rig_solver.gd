extends RefCounted
## Pose solver: FK with world-axis deltas + analytic two-bone IK for legs and arms.
## Character space: +Y up, +Z forward, +X = character's LEFT. Units: metres (the GLB skeleton is in cm, converted here).

class Pose:
	var hips_pos := Vector3.ZERO
	var hips_rot := Quaternion.IDENTITY
	var spine: Array[Quaternion] = [Quaternion.IDENTITY, Quaternion.IDENTITY, Quaternion.IDENTITY]
	var neck := Quaternion.IDENTITY
	var head := Quaternion.IDENTITY
	var hand: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]        # 0 = left, 1 = right
	var hand_pole: Array[Vector3] = [Vector3(0.3, -0.2, -1.0), Vector3(-0.3, -0.2, -1.0)]
	var foot: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	var foot_rot: Array[Quaternion] = [Quaternion.IDENTITY, Quaternion.IDENTITY]
	var knee_pole: Array[Vector3] = [Vector3(0.12, 0, 1.0), Vector3(-0.12, 0, 1.0)]
	var sword_dir := Vector3(0.08, -0.74, 0.67)

	func duplicate_pose() -> Pose:
		var p := Pose.new()
		p.hips_pos = hips_pos
		p.hips_rot = hips_rot
		p.spine = spine.duplicate()
		p.neck = neck
		p.head = head
		p.hand = hand.duplicate()
		p.hand_pole = hand_pole.duplicate()
		p.foot = foot.duplicate()
		p.foot_rot = foot_rot.duplicate()
		p.knee_pole = knee_pole.duplicate()
		p.sword_dir = sword_dir
		return p

const BONE_NAMES := ["Hips", "Spine02", "Spine01", "Spine", "neck", "Head", "head_end", "headfront",
	"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "RightShoulder", "RightArm", "RightForeArm", "RightHand",
	"LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase", "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"]

var skel: Skeleton3D
var to_root := Transform3D.IDENTITY          # skeleton space -> character space (metres)
var from_root := Transform3D.IDENTITY
var count := 0
var idx := {}                                 # name -> skeleton bone index
var parent: PackedInt32Array = PackedInt32Array()
var rest_rot: Array[Quaternion] = []           # global rest rotation (metres frame)
var rest_pos: Array[Vector3] = []              # global rest position (metres)
var D: Array[Quaternion] = []
var P: Array[Vector3] = []
var len_leg: Array = [Vector2.ZERO, Vector2.ZERO]
var len_arm: Array = [Vector2.ZERO, Vector2.ZERO]
var ok := false

static func rot_x(deg: float) -> Quaternion:
	return Quaternion(Vector3(1, 0, 0), deg_to_rad(deg))
static func rot_y(deg: float) -> Quaternion:
	return Quaternion(Vector3(0, 1, 0), deg_to_rad(deg))
static func rot_z(deg: float) -> Quaternion:
	return Quaternion(Vector3(0, 0, 1), deg_to_rad(deg))
static func rot3(pitch: float, yaw: float, roll: float) -> Quaternion:
	return rot_y(yaw) * rot_x(pitch) * rot_z(roll)

static func from_to(a: Vector3, b: Vector3) -> Quaternion:
	var an := a.normalized()
	var bn := b.normalized()
	var d := an.dot(bn)
	if d > 0.999999:
		return Quaternion.IDENTITY
	if d < -0.999999:
		var ax := an.cross(Vector3(1, 0, 0))
		if ax.length() < 1e-3:
			ax = an.cross(Vector3(0, 1, 0))
		return Quaternion(ax.normalized(), PI)
	var axis := an.cross(bn)
	var s := axis.length()
	return Quaternion(axis / s, atan2(s, d))

static func two_bone(S: Vector3, T: Vector3, l1: float, l2: float, pole: Vector3) -> Array:
	var d := T - S
	var dist := d.length()
	dist = clampf(dist, absf(l1 - l2) + 1e-4, (l1 + l2) * 0.9995)
	var dirn := d.normalized()
	var a := (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var pp := pole - dirn * pole.dot(dirn)
	if pp.length() < 1e-5:
		pp = dirn.cross(Vector3(1, 0, 0))
	pp = pp.normalized()
	return [S + dirn * a + pp * h, S + dirn * dist]

func setup(skeleton: Skeleton3D, root: Node3D) -> bool:
	skel = skeleton
	count = skel.get_bone_count()
	to_root = root.global_transform.affine_inverse() * skel.global_transform
	from_root = to_root.affine_inverse()
	var sbasis := to_root.basis.orthonormalized()
	for nm in BONE_NAMES:
		var i := skel.find_bone(nm)
		if i < 0:
			push_error("RigSolver: bone not found: " + nm)
			return false
		idx[nm] = i
	parent.resize(count)
	rest_rot.resize(count)
	rest_pos.resize(count)
	D.resize(count)
	P.resize(count)
	var gl: Array[Transform3D] = []
	gl.resize(count)
	var done: Array[bool] = []
	done.resize(count)
	for i in count:
		parent[i] = skel.get_bone_parent(i)
		done[i] = false
	var guard := 0
	var left := count
	while left > 0 and guard < 200:
		guard += 1
		for i in count:
			if done[i]:
				continue
			var par := parent[i]
			if par >= 0 and not done[par]:
				continue
			var loc := skel.get_bone_rest(i)
			gl[i] = loc if par < 0 else gl[par] * loc
			done[i] = true
			left -= 1
	for i in count:
		rest_pos[i] = to_root * gl[i].origin
		var gb := gl[i].basis.orthonormalized()
		rest_rot[i] = (sbasis * gb).get_rotation_quaternion().normalized()
		D[i] = Quaternion.IDENTITY
		P[i] = rest_pos[i]
	for s in 2:
		var side := "Left" if s == 0 else "Right"
		len_leg[s] = Vector2(_rl(side + "UpLeg", side + "Leg"), _rl(side + "Leg", side + "Foot"))
		len_arm[s] = Vector2(_rl(side + "Arm", side + "ForeArm"), _rl(side + "ForeArm", side + "Hand"))
	ok = true
	return true

func _rl(a: String, b: String) -> float:
	return (rest_pos[idx[a]] - rest_pos[idx[b]]).length()

func rp(name: String) -> Vector3:
	return rest_pos[idx[name]]

func _off(child: String, par: String) -> Vector3:
	return rest_pos[idx[child]] - rest_pos[idx[par]]

func _place(name: String, par: String, d: Quaternion) -> void:
	var b: int = idx[name]
	var pa: int = idx[par]
	D[b] = d * D[pa]
	P[b] = P[pa] + D[pa] * _off(name, par)

func _aim(name: String, par: String, child: String, target_dir: Vector3) -> void:
	var b: int = idx[name]
	var pa: int = idx[par]
	var rest_dir := rest_pos[idx[child]] - rest_pos[b]
	var cur := D[pa] * rest_dir
	D[b] = from_to(cur, target_dir) * D[pa]
	P[b] = P[pa] + D[pa] * _off(name, par)

func solve(p: Pose) -> void:
	var hips: int = idx["Hips"]
	D[hips] = p.hips_rot
	P[hips] = p.hips_pos
	_place("Spine02", "Hips", p.spine[0])
	_place("Spine01", "Spine02", p.spine[1])
	_place("Spine", "Spine01", p.spine[2])
	_place("neck", "Spine", p.neck)
	_place("Head", "neck", p.head)
	_place("head_end", "Head", Quaternion.IDENTITY)
	_place("headfront", "Head", Quaternion.IDENTITY)
	for s in 2:
		var side := "Left" if s == 0 else "Right"
		var sh := side + "Shoulder"
		var arm := side + "Arm"
		var fa := side + "ForeArm"
		var hand := side + "Hand"
		_place(sh, "Spine", Quaternion.IDENTITY)
		# --- arm IK
		_place(arm, sh, Quaternion.IDENTITY)
		var S: Vector3 = P[idx[arm]]
		var la: Vector2 = len_arm[s]
		var T: Vector3 = p.hand[s]
		var res := two_bone(S, T, la.x, la.y, p.hand_pole[s])
		var E: Vector3 = res[0]
		var Tc: Vector3 = res[1]
		_aim(arm, sh, fa, E - S)
		_aim(fa, arm, hand, Tc - E)
		D[idx[hand]] = D[idx[fa]]
		P[idx[hand]] = Tc
		# --- leg IK
		var up := side + "UpLeg"
		var leg := side + "Leg"
		var foot := side + "Foot"
		var toe := side + "ToeBase"
		_place(up, "Hips", Quaternion.IDENTITY)
		S = P[idx[up]]
		var ll: Vector2 = len_leg[s]
		res = two_bone(S, p.foot[s], ll.x, ll.y, p.knee_pole[s])
		E = res[0]
		Tc = res[1]
		_aim(up, "Hips", leg, E - S)
		_aim(leg, up, foot, Tc - E)
		D[idx[foot]] = p.foot_rot[s]
		P[idx[foot]] = Tc
		_place(toe, foot, Quaternion.IDENTITY)
		D[idx[toe]] = p.foot_rot[s]

## Writes the solved pose into the Skeleton3D (local rotations + hips translation).
func apply() -> void:
	var gq: Array[Quaternion] = []
	gq.resize(count)
	var done: Array[bool] = []
	done.resize(count)
	for i in count:
		done[i] = false
	# bones not driven by the solver keep their rest pose
	var driven := {}
	for nm in BONE_NAMES:
		driven[idx[nm]] = true
	var left := count
	var guard := 0
	while left > 0 and guard < 200:
		guard += 1
		for i in count:
			if done[i]:
				continue
			var par := parent[i]
			if par >= 0 and not done[par]:
				continue
			if driven.has(i):
				gq[i] = D[i] * rest_rot[i]
				var lq: Quaternion = gq[i] if par < 0 else gq[par].inverse() * gq[i]
				skel.set_bone_pose_rotation(i, lq.normalized())
			else:
				gq[i] = rest_rot[i] if par < 0 else gq[par] * (rest_rot[par].inverse() * rest_rot[i])
			done[i] = true
			left -= 1
	var hi: int = idx["Hips"]
	skel.set_bone_pose_position(hi, from_root * P[hi])
