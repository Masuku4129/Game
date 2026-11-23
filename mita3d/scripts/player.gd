class_name MitaPlayer
extends Node3D
## Управляемая Мита: движение, прыжок с сальто, рывок, блок/парирование, комбо 4 удара,
## 4 навыка. Анимации — покадровая интерполяция поз костей (FK), каждая поза продолжает предыдущую.

const R := 7.2
const G := 26.0
const BN := {"hip": "root", "sp": "spine03", "sp1": "spine01", "hd": "head", "uaR": "upperarm01.R", "laR": "lowerarm01.R",
	"uaL": "upperarm01.L", "laL": "lowerarm01.L", "ulR": "upperleg01.R", "llR": "lowerleg01.R", "ulL": "upperleg01.L",
	"llL": "lowerleg01.L", "ftR": "foot.R", "ftL": "foot.L"}
const STY := [
	{"n": "Свет", "c": Color(0.85, 0.88, 1.0), "dmg": 1.0, "spd": 1.0, "rad": 1.0, "lunge": 0.6, "spin": 360.0},
	{"n": "Молния", "c": Color(1.0, 0.95, 0.35), "dmg": 0.85, "spd": 1.45, "rad": 0.95, "lunge": 2.0, "spin": 360.0},
	{"n": "Огонь", "c": Color(1.0, 0.45, 0.12), "dmg": 1.5, "spd": 0.78, "rad": 1.1, "lunge": 0.3, "spin": 360.0},
	{"n": "Ветер", "c": Color(0.5, 1.0, 0.8), "dmg": 0.8, "spd": 1.1, "rad": 1.55, "lunge": 0.9, "spin": 720.0},
]
const STANCE := {"sp": Vector3(-5, 0, 0), "hip": Vector3(0, 0, 0), "hd": Vector3(6, 0, 0), "uaR": Vector3(0, 35, 10), "laR": Vector3(0, 70, 0),
	"uaL": Vector3(0, -40, -5), "laL": Vector3(0, -75, 0), "ulR": Vector3(12, 0, 6), "llR": Vector3(24, 0, 0), "ulL": Vector3(-18, 0, 0),
	"llL": Vector3(22, 0, 0), "ftR": Vector3(4, 0, 0), "ftL": Vector3(-4, 0, 0), "blade": Vector3(0.25, -0.35, -0.9)}

var model: MitaChar
var enemies: Array = []
var face := Vector3(0, 0, -1)
var move_in := Vector2.ZERO
var vel := Vector3.ZERO
var vy := 0.0
var grounded := true
var air_jumps := 1
var state := "idle"      # idle run attack air dash block skill hurt
var hp := 100.0
var ult := 0.0
var style := 0
var cd1 := 0.0
var cd2 := 0.0
var cd_style := 0.0
var cd_dash := 0.0
var combo := 0
var combo_t := 0.0
var queued := false
var invuln := 0.0
var blocking := false
var block_t := 0.0
var pose := {}
var frames: Array = []
var fi := 0
var ft := 0.0
var fprev := {}
var cur_anim := ""
var run_ph := 0.0
var air_t := 0.0
var air_dur := 0.7
var flip := false
var ghost_t := 0.0
var hurt_flash := 0.0
var hidden_skill := false
signal hit_landed

func _ready() -> void:
	model = MitaChar.new()
	add_child(model)
	pose = STANCE.duplicate()
	apply_style()

# ---------- анимация ----------
func P(d: Dictionary) -> Dictionary:
	var r := STANCE.duplicate()
	for k in d:
		r[k] = d[k]
	return r

func lerp_pose(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var r := {}
	for k in BN:
		var va: Vector3 = a.get(k, Vector3.ZERO)
		var vb: Vector3 = b.get(k, Vector3.ZERO)
		r[k] = va.lerp(vb, t)
	for k in ["blade", "off", "spin"]:
		var va2: Vector3 = a.get(k, Vector3.ZERO)
		var vb2: Vector3 = b.get(k, Vector3.ZERO)
		r[k] = va2.lerp(vb2, t)
	return r

func play(name: String, fr: Array) -> void:
	cur_anim = name
	frames = fr
	fi = 0
	ft = 0.0
	fprev = pose.duplicate()
	if frames.size() > 0 and frames[0].size() > 2:
		_frame_event(frames[0][2])

func anim_done() -> bool:
	return frames.is_empty() or fi >= frames.size()

func _frame_event(ev) -> void:
	if ev is int and ev > 0:
		do_hit(ev)

func step_anim(dt: float) -> void:
	if frames.is_empty() or fi >= frames.size():
		return
	var spd: float = STY[style]["spd"]
	var f: Array = frames[fi]
	ft += dt * spd
	var dur: float = f[1]
	var t := clampf(ft / dur, 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	pose = lerp_pose(fprev, f[0], t)
	if ft >= dur:
		fprev = f[0]
		pose = f[0]
		fi += 1
		ft = 0.0
		if fi >= frames.size():
			var sp: Vector3 = pose.get("spin", Vector3.ZERO)
			pose["spin"] = Vector3(fmod(sp.x, 360.0), fmod(sp.y, 360.0), fmod(sp.z, 360.0))
		if fi < frames.size():
			if frames[fi].size() > 2:
				_frame_event(frames[fi][2])
			# окно отмены: на последнем кадре (восстановление) можно перейти в следующий удар
			if fi == frames.size() - 1 and cur_anim.begins_with("atk") and queued:
				queued = false
				next_attack()

func apply_pose() -> void:
	for k in BN:
		var v: Vector3 = pose.get(k, Vector3.ZERO)
		model.rot(BN[k], v.x, v.y, v.z)
	var b: Vector3 = pose.get("blade", STANCE["blade"])
	if b.length() > 0.01:
		model.blade_local = b.normalized()
	var o: Vector3 = pose.get("off", Vector3.ZERO)
	model.position = o
	var sp: Vector3 = pose.get("spin", Vector3.ZERO)
	model.rotation = Vector3(deg_to_rad(sp.x), deg_to_rad(sp.y), deg_to_rad(sp.z))

# ---------- набор поз ----------
func atk_frames(n: int) -> Array:
	var sp360: float = STY[style]["spin"]
	var lg: float = STY[style]["lunge"]
	match n:
		1:
			return [
				[P({"sp": Vector3(-4, -38, 0), "hip": Vector3(0, -14, 0), "uaR": Vector3(0, -25, -65), "laR": Vector3(0, 55, 0), "uaL": Vector3(0, -55, 0), "ulR": Vector3(10, 0, 6), "llR": Vector3(26, 0, 0), "ulL": Vector3(-26, 0, 0), "llL": Vector3(30, 0, 0), "blade": Vector3(0.6, 0.75, 0.3)}), 0.09],
				[P({"sp": Vector3(10, 46, 0), "hip": Vector3(0, 22, 0), "uaR": Vector3(0, 75, 8), "laR": Vector3(0, 20, 0), "uaL": Vector3(0, -20, -20), "ulL": Vector3(-38, 0, 0), "llL": Vector3(20, 0, 0), "ulR": Vector3(26, 0, 6), "llR": Vector3(36, 0, 0), "off": Vector3(0, 0, -lg * 0.15), "blade": Vector3(-0.65, -0.25, -0.75)}), 0.07, 1],
				[P({"sp": Vector3(0, 20, 0), "hip": Vector3(0, 8, 0), "blade": Vector3(-0.3, -0.5, -0.8)}), 0.16],
			]
		2:
			return [
				[P({"sp": Vector3(-12, 34, 0), "hip": Vector3(0, 18, 0), "uaR": Vector3(0, -40, -100), "laR": Vector3(0, 80, 0), "uaL": Vector3(0, -30, -30), "ulR": Vector3(18, 0, 6), "llR": Vector3(30, 0, 0), "ulL": Vector3(-30, 0, 0), "llL": Vector3(34, 0, 0), "blade": Vector3(-0.35, 0.95, 0.1)}), 0.1],
				[P({"sp": Vector3(28, -26, 0), "hip": Vector3(0, -18, 0), "uaR": Vector3(0, 55, 24), "laR": Vector3(0, 10, 0), "ulL": Vector3(-44, 0, 0), "llL": Vector3(30, 0, 0), "ulR": Vector3(32, 0, 6), "llR": Vector3(46, 0, 0), "off": Vector3(0, -0.12, -lg * 0.3), "blade": Vector3(0.3, -0.75, -0.75)}), 0.07, 2],
				[P({"sp": Vector3(14, -8, 0), "blade": Vector3(0.2, -0.6, -0.8)}), 0.16],
			]
		3:
			return [
				[P({"sp": Vector3(-8, -28, 0), "hip": Vector3(0, 0, 0), "off": Vector3(0, -0.12, 0), "ulL": Vector3(-45, 0, 0), "llL": Vector3(70, 0, 0), "ulR": Vector3(20, 0, 6), "llR": Vector3(40, 0, 0), "uaR": Vector3(0, 40, -30), "blade": Vector3(0.2, -0.4, -0.9)}), 0.08],
				[P({"sp": Vector3(0, -90, 0), "hip": Vector3(0, 0, 0), "off": Vector3(0, 0, -lg * 0.2), "spin": Vector3(0, -sp360 * 0.5, 0), "ulR": Vector3(-90, 0, 6), "llR": Vector3(8, 0, 0), "ftR": Vector3(-30, 0, 0), "ulL": Vector3(-10, 0, 0), "llL": Vector3(14, 0, 0), "uaR": Vector3(0, 80, -40), "laR": Vector3(0, 10, 0), "uaL": Vector3(0, -80, 40), "blade": Vector3(-0.9, -0.1, -0.5)}), 0.13, 3],
				[P({"sp": Vector3(0, 0, 0), "spin": Vector3(0, -sp360, 0), "ulR": Vector3(-40, 0, 6), "llR": Vector3(30, 0, 0), "blade": Vector3(0.3, -0.4, -0.9)}), 0.14],
			]
		_:
			return [
				[P({"sp": Vector3(-4, -60, 0), "hip": Vector3(0, -24, 0), "uaR": Vector3(0, -50, -40), "laR": Vector3(0, 40, 0), "uaL": Vector3(0, -60, 0), "ulR": Vector3(8, 0, 6), "llR": Vector3(26, 0, 0), "ulL": Vector3(-30, 0, 0), "llL": Vector3(34, 0, 0), "off": Vector3(0, -0.1, 0), "blade": Vector3(0.95, 0.05, 0.3)}), 0.12],
				[P({"sp": Vector3(6, 70, 0), "hip": Vector3(0, 30, 0), "spin": Vector3(0, -sp360 * 0.55, 0), "uaR": Vector3(0, 85, 0), "laR": Vector3(0, 5, 0), "uaL": Vector3(0, -20, -10), "ulR": Vector3(30, 0, 8), "llR": Vector3(40, 0, 0), "ulL": Vector3(-40, 0, 0), "llL": Vector3(18, 0, 0), "blade": Vector3(-1.0, 0.0, -0.15)}), 0.14, 4],
				[P({"sp": Vector3(0, 20, 0), "spin": Vector3(0, -sp360, 0), "blade": Vector3(-0.5, -0.3, -0.8)}), 0.2],
			]

func next_attack() -> void:
	combo = combo % 4 + 1
	state = "attack"
	queued = false
	var near = nearest_enemy(4.5)
	if near != null:
		var tv: Vector3 = near.global_position - global_position
		tv.y = 0
		if tv.length() > 0.1:
			face = tv.normalized()
	var lg: float = STY[style]["lunge"]
	vel = face * lg * 6.0
	play("atk%d" % combo, atk_frames(combo))

func nearest_enemy(maxd: float):
	var best = null
	var bd := maxd
	for e in enemies:
		if is_instance_valid(e) and not e.dead:
			var d: float = e.global_position.distance_to(global_position)
			if d < bd:
				bd = d
				best = e
	return best

func hits_in_cone(r: float, half_deg: float) -> Array:
	var out := []
	for e in enemies:
		if not is_instance_valid(e) or e.dead:
			continue
		var to: Vector3 = e.global_position - global_position
		to.y = 0
		var d := to.length()
		if d > r:
			continue
		if half_deg >= 180.0 or d < 0.6 or rad_to_deg(face.angle_to(to / d)) <= half_deg:
			out.append(e)
	return out

func hit_enemy(e, dmg: float, dir: Vector3, dist: float, stun_t: float) -> void:
	var s: Dictionary = STY[style]
	e.hit(dmg * s["dmg"], dir, dist, stun_t)
	if style == 2:
		e.burn = 3.0
	if style == 1:
		# цепная молния: ближайший сосед получает часть урона
		var best = null
		var bd := 4.0
		for o in enemies:
			if o != e and is_instance_valid(o) and not o.dead:
				var dd: float = o.global_position.distance_to(e.global_position)
				if dd < bd:
					bd = dd
					best = o
		if best != null:
			best.hit(dmg * 0.4, (best.global_position - e.global_position), 0.6, 0.2)
			spark(best.global_position + Vector3(0, 1, 0), s["c"], 0.5)
	spark(e.global_position + Vector3(0, 1.0, 0), s["c"], 0.7)
	ult = minf(100.0, ult + 4.0)
	hit_landed.emit()

func do_hit(kind: int) -> void:
	var s: Dictionary = STY[style]
	var rad: float = s["rad"]
	var targets := []
	var dmg := 8.0
	var kb := 1.2
	var st := 0.25
	match kind:
		1:
			targets = hits_in_cone(2.4 * rad, 55.0)
		2:
			targets = hits_in_cone(2.6 * rad, 60.0)
			dmg = 10.0
			kb = 1.5
		3:
			targets = hits_in_cone(2.5 * rad, 180.0)
			dmg = 12.0
			kb = 2.5
			st = 0.45
		_:
			targets = hits_in_cone(3.3 * rad, 180.0)
			dmg = 18.0
			kb = 4.0
			st = 0.8
	slash_fx(kind)
	for e in targets:
		hit_enemy(e, dmg, e.global_position - global_position, kb, st)
	if targets.size() > 0:
		hitstop(0.06 if kind < 4 else 0.11)

func slash_fx(kind: int) -> void:
	var s: Dictionary = STY[style]
	var m := MeshInstance3D.new()
	var tm := TorusMesh.new()
	var r: float = (1.7 if kind < 3 else 2.2) * float(s["rad"])
	tm.inner_radius = r - 0.07
	tm.outer_radius = r
	m.mesh = tm
	var mt := StandardMaterial3D.new()
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mt.albedo_color = Color(s["c"].r, s["c"].g, s["c"].b, 0.85)
	m.material_override = mt
	get_parent().add_child(m)
	m.global_position = global_position + Vector3(0, 1.0, 0) + face * 0.5
	if kind == 1:
		m.rotation = Vector3(deg_to_rad(80), 0, deg_to_rad(-35))
	elif kind == 2:
		m.rotation = Vector3(deg_to_rad(20), 0, deg_to_rad(50))
	else:
		m.rotation = Vector3(0, 0, 0)
	m.scale = Vector3(0.5, 0.5, 0.5)
	var tw := m.create_tween()
	tw.tween_property(m, "scale", Vector3(1, 1, 1) * (1.0 if kind < 3 else 1.25), 0.16)
	tw.parallel().tween_property(mt, "albedo_color:a", 0.0, 0.16)
	tw.tween_callback(m.queue_free)

func spark(pos: Vector3, col: Color, sz: float) -> void:
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.2 * sz
	sm.height = 0.4 * sz
	m.mesh = sm
	var mt := StandardMaterial3D.new()
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mt.albedo_color = Color(col.r, col.g, col.b, 0.9)
	m.material_override = mt
	get_parent().add_child(m)
	m.global_position = pos
	var tw := m.create_tween()
	tw.tween_property(m, "scale", Vector3(2.6, 2.6, 2.6), 0.14)
	tw.parallel().tween_property(mt, "albedo_color:a", 0.0, 0.14)
	tw.tween_callback(m.queue_free)

func hitstop(t: float) -> void:
	Engine.time_scale = 0.06
	await get_tree().create_timer(t, true, false, true).timeout
	Engine.time_scale = 1.0

func apply_style() -> void:
	model.set_style_color(STY[style]["c"])

# ---------- ввод ----------
func press_attack() -> void:
	if state == "idle" or state == "run":
		if combo_t <= 0.0:
			combo = 0
		next_attack()
	elif state == "attack":
		queued = true
	elif state == "air" and not grounded:
		pass

func press_jump() -> void:
	if state == "skill" or state == "dash":
		return
	if grounded:
		grounded = false
		vy = 9.5
		air_t = 0.0
		air_dur = 2.0 * vy / G
		flip = move_in.length() > 0.3
		state = "air"
		air_jumps = 1
		frames = []
	elif air_jumps > 0:
		air_jumps -= 1
		vy = 8.0
		air_t = 0.0
		air_dur = 2.0 * vy / G
		flip = false
		state = "air"
		play("pirouette", [
			[P({"spin": Vector3(0, -180, 0), "ulR": Vector3(-70, 0, 0), "llR": Vector3(90, 0, 0), "ulL": Vector3(-40, 0, 0), "llL": Vector3(100, 0, 0), "uaR": Vector3(0, 60, -60), "uaL": Vector3(0, -60, 60), "sp": Vector3(-10, 0, 0), "blade": Vector3(0.5, 0.2, -0.8)}), 0.22],
			[P({"spin": Vector3(0, -360, 0), "ulR": Vector3(-30, 0, 0), "llR": Vector3(40, 0, 0), "ulL": Vector3(-20, 0, 0), "llL": Vector3(40, 0, 0), "uaR": Vector3(0, 40, -20), "blade": Vector3(0.3, -0.2, -0.9)}), 0.22],
		])

func press_dash() -> void:
	if cd_dash > 0.0 or state == "skill":
		return
	cd_dash = 0.45
	var d := Vector3(move_in.x, 0, move_in.y)
	if d.length() > 0.2:
		face = d.normalized()
	state = "dash"
	invuln = 0.22
	vel = face * 22.0
	queued = false
	play("dash", [
		[P({"sp": Vector3(32, 0, 0), "hip": Vector3(18, 0, 0), "ulR": Vector3(-55, 0, 0), "llR": Vector3(70, 0, 0), "ulL": Vector3(40, 0, 0), "llL": Vector3(10, 0, 0), "uaR": Vector3(0, 20, 50), "laR": Vector3(0, 0, 0), "uaL": Vector3(0, -30, -50), "blade": Vector3(0.2, -0.1, 0.95), "off": Vector3(0, -0.15, 0)}), 0.07],
		[P({"sp": Vector3(28, 0, 0), "hip": Vector3(14, 0, 0), "ulR": Vector3(-30, 0, 0), "llR": Vector3(50, 0, 0), "ulL": Vector3(30, 0, 0), "llL": Vector3(20, 0, 0), "blade": Vector3(0.2, -0.1, 0.95)}), 0.15],
	])

func press_block(down: bool) -> void:
	if down and state != "skill" and state != "dash":
		blocking = true
		block_t = 0.0
		state = "block"
		frames = []
	elif not down and blocking:
		blocking = false
		if state == "block":
			state = "idle"

func take_hit(dmg: float, from: Vector3) -> void:
	if invuln > 0.0 or state == "skill":
		return
	var away := global_position - from
	away.y = 0
	away = away.normalized()
	if blocking:
		if block_t < 0.22:
			# парирование
			spark(global_position + Vector3(0, 1.2, 0) + face * 0.7, Color(1, 1, 1), 1.6)
			for e in enemies:
				if is_instance_valid(e) and not e.dead and e.global_position.distance_to(global_position) < 3.0:
					e.hit(0.0, e.global_position - global_position, 3.0, 1.4)
			ult = minf(100.0, ult + 10.0)
			hitstop(0.08)
			return
		hp -= dmg * 0.2
		vel = away * 4.0
		spark(global_position + Vector3(0, 1.2, 0) + face * 0.7, Color(0.6, 0.7, 1.0), 0.8)
		return
	hp -= dmg
	hurt_flash = 0.25
	vel = away * 8.0
	invuln = 0.5
	if state == "attack":
		frames = []
		state = "idle"

# ---------- навыки ----------
func skill1() -> void:
	if cd1 > 0.0 or state == "skill":
		return
	cd1 = 5.0
	state = "skill"
	vel = Vector3.ZERO
	var c: Color = STY[style]["c"]
	play("s1", [
		[P({"sp": Vector3(-6, -50, 0), "hip": Vector3(0, -20, 0), "uaR": Vector3(0, -30, -70), "laR": Vector3(0, 60, 0), "blade": Vector3(0.7, 0.5, 0.2)}), 0.14],
		[P({"sp": Vector3(4, 50, 0), "hip": Vector3(0, 20, 0), "uaR": Vector3(0, 80, 0), "laR": Vector3(0, 10, 0), "blade": Vector3(-0.9, 0, -0.4)}), 0.08],
		[P({"sp": Vector3(-4, -50, 0), "hip": Vector3(0, -20, 0), "uaR": Vector3(0, 70, 0), "blade": Vector3(0.9, 0, -0.4)}), 0.1],
		[P({"sp": Vector3(20, 0, 0), "uaR": Vector3(0, -20, -110), "laR": Vector3(0, 80, 0), "blade": Vector3(0, 1, 0)}), 0.1],
		[P({"sp": Vector3(30, 0, 0), "uaR": Vector3(0, 60, 20), "blade": Vector3(0, -0.4, -0.9)}), 0.08],
		[P({}), 0.2],
	])
	for i in 3:
		await get_tree().create_timer(0.14 if i == 0 else 0.13).timeout
		var tr := Trail.new()
		tr.player = self
		tr.color = c
		tr.dmg = 9.0 + i * 3.0
		var yaw := (-32.0 if i == 0 else (32.0 if i == 1 else 0.0))
		var d := face.rotated(Vector3.UP, deg_to_rad(yaw))
		tr.dir = d
		tr.vertical = i == 2
		tr.half = Vector3(2.2, 1.6 if i == 2 else 0.6, 2.2)
		tr.speed = 34.0
		tr.life = 0.45
		get_parent().add_child(tr)
		tr.global_position = global_position + Vector3(0, 1.2, 0) + d * 1.0
		tr.look_at(tr.global_position + d, Vector3.UP)
	await get_tree().create_timer(0.4).timeout
	if state == "skill":
		state = "idle"
		frames = []

func skill2() -> void:
	if cd2 > 0.0 or state == "skill":
		return
	var list: Array = []
	for e in enemies:
		if is_instance_valid(e) and not e.dead:
			list.append(e)
	if list.is_empty():
		return
	list.sort_custom(func(a, b): return a.global_position.distance_to(global_position) < b.global_position.distance_to(global_position))
	cd2 = 7.0
	state = "skill"
	invuln = 5.0
	frames = []
	hidden_skill = true
	var c: Color = STY[style]["c"]
	var pos := global_position
	for i in mini(4, list.size()):
		var e = list[i]
		if not is_instance_valid(e) or e.dead:
			continue
		var tgt: Vector3 = e.global_position
		var dir := (tgt - pos)
		dir.y = 0
		var dist := dir.length()
		dir = dir.normalized() if dist > 0.01 else face
		streak(pos + Vector3(0, 1, 0), tgt - dir * 0.9 + Vector3(0, 1, 0), c)
		await get_tree().create_timer(0.12).timeout
		if not is_instance_valid(e):
			continue
		pos = e.global_position - dir * 1.0
		global_position = pos
		face = dir
		rotation.y = atan2(-dir.x, -dir.z)
		hidden_skill = false
		model.blade_local = Vector3(-0.5, -0.4, -0.8)
		hit_enemy(e, 14.0, dir, 3.0, 0.7)
		spark(e.global_position + Vector3(0, 1, 0), c, 1.4)
		hitstop(0.05)
		await get_tree().create_timer(0.08).timeout
		hidden_skill = true
	var back := pos
	streak(back + Vector3(0, 1, 0), Vector3(0, 1, 0), c)
	await get_tree().create_timer(0.14).timeout
	global_position = Vector3.ZERO
	hidden_skill = false
	invuln = 0.3
	state = "idle"

func streak(a: Vector3, b: Vector3, c: Color) -> void:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.14, 0.14, maxf(a.distance_to(b), 0.1))
	m.mesh = bm
	var mt := StandardMaterial3D.new()
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mt.albedo_color = Color(c.r, c.g, c.b, 0.95)
	m.material_override = mt
	get_parent().add_child(m)
	m.global_position = (a + b) * 0.5
	if a.distance_to(b) > 0.05:
		m.look_at(b, Vector3.UP)
	var tw := m.create_tween()
	tw.tween_property(mt, "albedo_color:a", 0.0, 0.3)
	tw.tween_callback(m.queue_free)

func skill3() -> void:
	if cd_style > 0.0:
		return
	cd_style = 0.5
	style = (style + 1) % STY.size()
	apply_style()
	var c: Color = STY[style]["c"]
	spark(global_position + Vector3(0, 1.0, 0), c, 3.0)
	if state == "idle" or state == "run":
		state = "attack"
		combo = 0
		play("atkstyle", [
			[P({"uaR": Vector3(0, -10, -120), "laR": Vector3(0, 70, 0), "sp": Vector3(-10, 0, 0), "blade": Vector3(0, 1, 0)}), 0.12],
			[P({"uaR": Vector3(0, 60, 10), "sp": Vector3(10, 0, 0), "blade": Vector3(0, -0.3, -0.9)}), 0.14],
			[P({}), 0.1],
		])

func skill4() -> void:
	if ult < 100.0 or state == "skill":
		return
	ult = 0.0
	state = "skill"
	invuln = 3.0
	vel = Vector3.ZERO
	var c: Color = STY[style]["c"]
	play("ult", [
		[P({"sp": Vector3(-14, 0, 0), "uaR": Vector3(0, -10, -140), "laR": Vector3(0, 90, 0), "uaL": Vector3(0, -10, 140), "laL": Vector3(0, 60, 0), "ulR": Vector3(10, 0, 10), "ulL": Vector3(-10, 0, -10), "off": Vector3(0, 0.55, 0), "blade": Vector3(0, 1, 0)}), 0.35],
		[P({"sp": Vector3(-20, 0, 0), "uaR": Vector3(0, -10, -150), "laR": Vector3(0, 100, 0), "off": Vector3(0, 0.7, 0), "blade": Vector3(0, 1, 0)}), 0.3],
		[P({"sp": Vector3(24, 0, 0), "uaR": Vector3(0, 70, 10), "laR": Vector3(0, 10, 0), "off": Vector3(0, 0.1, 0), "blade": Vector3(0, -0.3, -0.9)}), 0.14],
		[P({}), 0.25],
	])
	await get_tree().create_timer(0.62).timeout
	var tips := []
	for e in enemies:
		if is_instance_valid(e) and not e.dead:
			tips.append(e)
	var n := 7
	var from := global_position + Vector3(0, 2.6, 0)
	for i in n:
		var target_pos: Vector3
		var e = null
		if tips.size() > 0:
			e = tips[i % tips.size()]
			target_pos = e.global_position + Vector3(0, 1, 0)
		else:
			target_pos = global_position + Vector3(0, 1, 0) + Vector3(0, 0, -1).rotated(Vector3.UP, TAU * float(i) / n) * 5.0
		var orb := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.22
		sm.height = 0.44
		orb.mesh = sm
		var mt := StandardMaterial3D.new()
		mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mt.albedo_color = c.lerp(Color(1, 1, 1), 0.6)
		orb.material_override = mt
		get_parent().add_child(orb)
		orb.global_position = from
		var tw := orb.create_tween()
		tw.tween_property(orb, "global_position", target_pos, 0.22 + i * 0.03)
		tw.tween_callback(_ult_hit.bind(e, orb, c))
	await get_tree().create_timer(0.35).timeout
	state = "idle"
	frames = []

func _ult_hit(e, orb: Node3D, c: Color) -> void:
	var pos := orb.global_position
	orb.queue_free()
	spark(pos, c, 1.6)
	if is_instance_valid(e) and not e.dead:
		var dir: Vector3 = e.global_position - global_position
		e.hit(10.0, dir, 5.0 * 1.8, 1.6)   # 5 длин тела
		hitstop(0.04)
		await get_tree().create_timer(1.0).timeout
		if is_instance_valid(e):
			explode(e.global_position + Vector3(0, 0.8, 0), c)
	else:
		await get_tree().create_timer(0.8).timeout
		explode(pos, c)

func explode(pos: Vector3, c: Color) -> void:
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	m.mesh = sm
	var mt := StandardMaterial3D.new()
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mt.albedo_color = Color(c.r, c.g, c.b, 0.75)
	m.material_override = mt
	get_parent().add_child(m)
	m.global_position = pos
	m.scale = Vector3(0.2, 0.2, 0.2)
	var tw := m.create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_SINE)
	tw.tween_property(m, "scale", Vector3(3.6, 3.6, 3.6), 0.5)
	tw.parallel().tween_property(mt, "albedo_color:a", 0.0, 0.5)
	tw.tween_callback(m.queue_free)
	for e in enemies:
		if is_instance_valid(e) and not e.dead and e.global_position.distance_to(pos) < 3.8:
			e.hit(22.0, e.global_position - pos, 1.5, 0.8)

# ---------- основной цикл ----------
func _physics_process(dt: float) -> void:
	cd1 = maxf(0.0, cd1 - dt)
	cd2 = maxf(0.0, cd2 - dt)
	cd_style = maxf(0.0, cd_style - dt)
	cd_dash = maxf(0.0, cd_dash - dt)
	invuln = maxf(0.0, invuln - dt)
	hurt_flash = maxf(0.0, hurt_flash - dt)
	if combo_t > 0.0 and state != "attack":
		combo_t -= dt
	var mv := Vector3(move_in.x, 0, move_in.y)
	if mv.length() > 1.0:
		mv = mv.normalized()
	var spd := 6.5
	if state == "attack":
		combo_t = 0.4
		spd = 0.0
	elif state == "block":
		spd = 2.4
		block_t += dt
	elif state == "skill" or state == "dash":
		spd = 0.0
	if mv.length() > 0.1 and spd > 0.0:
		if state != "block":
			face = face.lerp(mv.normalized(), minf(1.0, 18.0 * dt)).normalized()
		vel = vel.lerp(mv * spd, minf(1.0, 14.0 * dt))
	elif state == "idle" or state == "run" or state == "block" or state == "air":
		vel = vel.lerp(Vector3.ZERO, minf(1.0, 12.0 * dt))
	elif state == "attack":
		vel = vel.lerp(Vector3.ZERO, minf(1.0, 9.0 * dt))
	# вертикаль
	if not grounded:
		vy -= G * dt
		position.y += vy * dt
		air_t += dt
		if position.y <= 0.0:
			position.y = 0.0
			grounded = true
			vy = 0.0
			frames = []
			if state == "air":
				state = "idle"
	if state == "dash":
		ghost_t -= dt
		if ghost_t <= 0.0:
			ghost_t = 0.035
			afterimage()
		vel = vel.lerp(face * 22.0, 0.5)
		if anim_done():
			state = "idle"
			frames = []
	position += Vector3(vel.x, 0, vel.z) * dt
	if Vector2(position.x, position.z).length() > R:
		var q := Vector3(position.x, 0, position.z).normalized() * R
		position.x = q.x
		position.z = q.z
	rotation.y = atan2(-face.x, -face.z)
	# конечный автомат поз
	if anim_done() and state != "skill":
		frames = []
		if state == "attack" or state == "dash":
			state = "idle"
	if not frames.is_empty():
		step_anim(dt)
	else:
		procedural_pose(dt, mv)
	apply_pose()
	# мерцание при уроне
	model.visible = not hidden_skill and not (hurt_flash > 0.0 and int(hurt_flash * 40.0) % 2 == 0)

func afterimage() -> void:
	var m := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.3
	cm.height = 1.7
	m.mesh = cm
	var c: Color = STY[style]["c"]
	var mt := StandardMaterial3D.new()
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mt.albedo_color = Color(c.r * 0.6, c.g * 0.6, c.b, 0.5)
	m.material_override = mt
	get_parent().add_child(m)
	m.global_position = global_position + Vector3(0, 0.85, 0)
	var tw := m.create_tween()
	tw.tween_property(mt, "albedo_color:a", 0.0, 0.28)
	tw.tween_callback(m.queue_free)

func procedural_pose(dt: float, mv: Vector3) -> void:
	var tgt := STANCE.duplicate()
	var t := Time.get_ticks_msec() / 1000.0
	if state == "air":
		var k := clampf(air_t / air_dur, 0.0, 1.0)
		var tuck := sin(k * PI)
		tgt["ulR"] = Vector3(-40 * tuck, 0, 6)
		tgt["llR"] = Vector3(60 * tuck, 0, 0)
		tgt["ulL"] = Vector3(-25 * tuck, 0, 0)
		tgt["llL"] = Vector3(50 * tuck, 0, 0)
		tgt["uaR"] = Vector3(0, 40, -30)
		tgt["blade"] = Vector3(0.3, -0.2, -0.9)
		if flip:
			tgt["spin"] = Vector3(-360.0 * k, 0, 0)
			tgt["off"] = Vector3(0, 0.9 * tuck, 0)
	elif state == "block":
		var par := block_t < 0.22
		tgt["uaR"] = Vector3(0, 50, -40)
		tgt["laR"] = Vector3(0, 95, 0)
		tgt["uaL"] = Vector3(0, -60, 20)
		tgt["laL"] = Vector3(0, -100, 0)
		tgt["sp"] = Vector3(-2, -14, 0)
		tgt["ulL"] = Vector3(-24, 0, 0)
		tgt["llL"] = Vector3(34, 0, 0)
		tgt["ulR"] = Vector3(20, 0, 6)
		tgt["llR"] = Vector3(40, 0, 0)
		tgt["blade"] = Vector3(0.85, 0.35, -0.4) if par else Vector3(0.2, 0.9, -0.3)
		if mv.length() < 0.1:
			tgt["off"] = Vector3(0, -0.06, 0)
	elif (mv.length() > 0.15 or vel.length() > 1.5) and (state == "idle" or state == "run"):
		state = "run"
		run_ph += dt * 12.0 * clampf(vel.length() / 6.5, 0.4, 1.2)
		var s1 := sin(run_ph)
		var s2 := sin(run_ph + PI)
		tgt["ulR"] = Vector3(-45 * s1, 0, 6)
		tgt["llR"] = Vector3(10 + 50 * maxf(0.0, -s1 + 0.0), 0, 0)
		tgt["ulL"] = Vector3(-45 * s2, 0, 0)
		tgt["llL"] = Vector3(10 + 50 * maxf(0.0, -s2), 0, 0)
		tgt["sp"] = Vector3(10, -12 * s1, 0)
		tgt["hip"] = Vector3(0, 6 * s1, 0)
		tgt["uaL"] = Vector3(-30 * s1, -45, -5)
		tgt["off"] = Vector3(0, 0.05 * absf(sin(run_ph)), 0)
		tgt["blade"] = Vector3(0.25, -0.2, -0.95)
	else:
		if state == "run":
			state = "idle"
		var br := sin(t * 2.2)
		tgt["sp"] = Vector3(-5 + br * 1.5, 0, 0)
		tgt["off"] = Vector3(0, br * 0.01, 0)
		tgt["uaR"] = Vector3(br * 2.0, 35, 10)
	pose = lerp_pose(pose, tgt, minf(1.0, 14.0 * dt))
