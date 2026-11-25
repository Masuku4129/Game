extends SceneTree
## Headless self test: runs every animation for a few seconds and checks numbers (no NaN, sane cloth, feet on ground).
## godot --headless --path . --script tests/selftest.gd

const Character = preload("res://scripts/character.gd")
var fails := 0

func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg)
		fails += 1

func _finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)

func _initialize() -> void:
	var ch: Node3D = Character.new()
	root.add_child(ch)
	await process_frame
	await process_frame
	_check(ch.ready_ok, "character loaded (skeleton, solver, cloak)")
	if not ch.ready_ok:
		quit(1)
		return
	var dt := 1.0 / 60.0
	var scenario := [
		["idle", Vector2.ZERO, 0.0, "", 120],
		["walk", Vector2(0, -1), 1.5, "", 240],
		["run", Vector2(0, -1), 4.8, "", 240],
		["sprint", Vector2(0, -1), 7.2, "", 240],
		["turn while running", Vector2(1, 0), 5.0, "", 180],
		["stop", Vector2.ZERO, 0.0, "", 150],
		["jump", Vector2.ZERO, 0.0, "jump", 150],
		["roll", Vector2(0, -1), 3.0, "roll", 90],
		["punch", Vector2.ZERO, 0.0, "punch", 80],
		["spin kick", Vector2.ZERO, 0.0, "spinkick", 120],
		["idle again", Vector2.ZERO, 0.0, "", 120],
	]
	for sc in scenario:
		var started := true
		if sc[3] != "":
			# wait until previous action ended
			var guard := 0
			while ch.busy() and guard < 600:
				ch._process(dt)
				guard += 1
			started = ch.do_action(sc[3])
		ch.input_dir = sc[1]
		ch.input_speed = sc[2]
		var max_disp := 0.0
		var min_hips := 99.0
		var max_hips := 0.0
		var bad := false
		var len_err := 0.0
		var min_knee := 999.0
		var min_elbow := 999.0
		var max_fist := 0.0
		for _i in int(sc[4]):
			ch._process(dt)
			max_fist = maxf(max_fist, ch.anim.fist)
			var sv = ch.solver
			for side in ["Left", "Right"]:
				var pu: Vector3 = sv.P[sv.idx[side + "UpLeg"]]
				var pk: Vector3 = sv.P[sv.idx[side + "Leg"]]
				var pf: Vector3 = sv.P[sv.idx[side + "Foot"]]
				var pa: Vector3 = sv.P[sv.idx[side + "Arm"]]
				var pe: Vector3 = sv.P[sv.idx[side + "ForeArm"]]
				var pw: Vector3 = sv.P[sv.idx[side + "Hand"]]
				len_err = maxf(len_err, absf((pu - pk).length() - (sv.rest_pos[sv.idx[side + "UpLeg"]] - sv.rest_pos[sv.idx[side + "Leg"]]).length()))
				len_err = maxf(len_err, absf((pk - pf).length() - (sv.rest_pos[sv.idx[side + "Leg"]] - sv.rest_pos[sv.idx[side + "Foot"]]).length()))
				len_err = maxf(len_err, absf((pa - pe).length() - (sv.rest_pos[sv.idx[side + "Arm"]] - sv.rest_pos[sv.idx[side + "ForeArm"]]).length()))
				len_err = maxf(len_err, absf((pe - pw).length() - (sv.rest_pos[sv.idx[side + "ForeArm"]] - sv.rest_pos[sv.idx[side + "Hand"]]).length()))
				min_knee = minf(min_knee, rad_to_deg((pu - pk).angle_to(pf - pk)))
				min_elbow = minf(min_elbow, rad_to_deg((pa - pe).angle_to(pw - pe)))
			max_disp = maxf(max_disp, ch.cloak.stat_max_disp)
			var hp: Vector3 = ch.solver.P[ch.solver.idx["Hips"]]
			min_hips = minf(min_hips, hp.y)
			max_hips = maxf(max_hips, hp.y)
			if not _finite(hp) or not _finite(ch.solver.P[ch.solver.idx["LeftFoot"]]) or not _finite(ch.solver.P[ch.solver.idx["RightHand"]]):
				bad = true
		print("[%s] state=%s pos=(%.1f, %.1f) speed=%.2f hips_y=%.2f..%.2f cloak_max=%.2f m  anim=%.2f ms cloak=%.2f ms" % [sc[0], ch.get_state(), ch.anim.pos.x, ch.anim.pos.z, ch.anim.vel.length(), min_hips, max_hips, max_disp, ch.anim_ms, ch.cloak_ms])
		_check(started, "action started")
		_check(not bad, "all poses finite")
		_check(max_disp < 0.8, "cloak displacement bounded")
		_check(min_hips > 0.2, "hips above ground")
		_check(len_err < 0.002, "bone lengths constant (err %.4f m)" % len_err)
		_check(min_knee > 15.0, "knee never over-folded (min %.0f deg)" % min_knee)
		_check(min_elbow > 15.0, "elbow never over-folded (min %.0f deg)" % min_elbow)
		if sc[3] == "punch" or sc[3] == "spinkick":
			_check(max_fist > 0.8, "fists clench during strike (max %.2f)" % max_fist)
		if sc[0] == "run":
			var sl: Vector3 = ch.solver.P[ch.solver.idx["LeftArm"]] - ch.solver.P[ch.solver.idx["RightArm"]]
			_check(sl.x < -0.15 and ch.anim.pos.z < -3.0, "runs facing -Z (left arm on -X): L-R=%s yaw=%.2f pos=%s" % [sl, ch.anim.yaw, ch.anim.pos])
	print("SELFTEST ", "PASSED" if fails == 0 else "FAILED (%d)" % fails)
	quit(0 if fails == 0 else 1)
