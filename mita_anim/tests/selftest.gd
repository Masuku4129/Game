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
	# --- diagnostics: does the skeleton really follow the solver?
	var sk: Skeleton3D = ch.skel
	print("[diag] mesh skin=", ch.mesh_inst.skin != null, " skeleton path=", ch.mesh_inst.skeleton, " mesh class=", ch.mesh_inst.mesh.get_class(), " sk_global_scale=", sk.global_transform.basis.get_scale())
	print("[diag] AnimationPlayers left: ", ch.model.find_children("*", "AnimationPlayer", true, false).size(), " modifier_cb=", sk.modifier_callback_mode_process)
	ch.input_dir = Vector2(0, -1)
	ch.input_speed = 4.8
	for _i in 120:
		ch._process(1.0 / 60.0)
	for nm in ["LeftArm", "LeftHand", "RightHand", "LeftFoot", "RightFoot", "Hips"]:
		var bi: int = ch.solver.idx[nm]
		var gp: Vector3 = ch.solver.to_root * sk.get_bone_global_pose(bi).origin
		var tp: Vector3 = ch.solver.P[bi]
		print("[diag] ", nm, " skel_global=", gp, " solver=", tp, " pose_rot=", sk.get_bone_pose_rotation(bi), " rest_rot=", sk.get_bone_rest(bi).basis.get_rotation_quaternion())
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
		for _i in int(sc[4]):
			ch._process(dt)
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
	print("SELFTEST ", "PASSED" if fails == 0 else "FAILED (%d)" % fails)
	quit(0 if fails == 0 else 1)
