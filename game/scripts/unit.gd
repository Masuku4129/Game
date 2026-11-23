extends Node3D
## --- colony: землепроходец. ---
## Один человек отряда: своя модель (та же фигура, что у героя, но своя раскраска —
## куртка, портки, мех, волосы), свой путь по сетке (nav.gd), своё дело (jobs.gd),
## свои нужды (голод, тепло, усталость) и здоровье, своя ноша (бревно на плече,
## короб с добычей) и свой инструмент в руке (хват берём из позы кисти, чтобы топор
## не торчал криво).
##
## Публичное:
##   setup(col, pos, cfg)              — создать (cfg: name, pal, tool)
##   goto(p, run) -> bool              — идти в точку
##   stop()                            — бросить путь
##   tick(dt)                          — шаг (зовёт colony)
##   needs_tick(dh, warm)              — нужды за dh игровых часов
##   hurt(dmg, from, kind)             — урон
##   show_tool(id)                     — инструмент в руку ("" — пусто)
##   carry_add(id, n) / carry_total() / carry_clear()
##   work_anim = "chop" | "cut" | "gather" | "build" | "kneel" | "shoot" | "cook"

const HS = preload("res://scripts/hero_skin.gd")
const SK = preload("res://scripts/skin.gd")
const TM = preload("res://scripts/tool_models.gd")
const IT = preload("res://scripts/items.gd")

const SPEED := 1.65
const RUN := 3.1
const CARRY_KG := 32.0        # сколько человек несёт (кг); бревно — на плече, одно

var main: Node3D
var colony
var nav
var unit_name := ""
var pal := {}
var leader := false

var vel := Vector3.ZERO
var yaw := 0.0
var path: Array = []
var run := false
var state := "idle"            # idle | walk | work | sleep | dead
var work_anim := ""
var job: Dictionary = {}
var carry := {}                # id → число
var carry_kind := ""           # что видно на плече: "log" | "goods" | ""
var hold := ""                 # инструмент в руке
var weapon := ""               # чем охотится и отбивается: "bow" | "spear" | ""
var acc := 0.0                 # накопленный шаг (далёкие считаются реже)

var health := 1.0
var hunger := 0.9
var warmth := 0.75
var fatigue := 0.1
var bleed := 0.0
var moving := false
var speed_now := 0.0
var auto := true
var area_lock := false         # сидеть в разрешённой области (zones.gd)

var model: Node3D
var m_ap: AnimationPlayer
var m_sk: Skeleton3D
var m_cur := ""
var hand_att: BoneAttachment3D
var back_att: BoneAttachment3D
var tool_nodes := {}
var log_node: MeshInstance3D
var sack_node: MeshInstance3D
var ring: MeshInstance3D
var task_lbl: Label3D
var selected := false
var _grip := Transform3D()
var _repath := 0.0
var _goal := Vector3.INF
var _hspeed := 0.0
var _last_pos := Vector3.ZERO
var _step_acc := 0.0
var _stuck := 0.0
var _lean := 0.0
var _turn := 0.0
var _mrot := Vector3.ZERO      # поза модели в покое (крен считаем от неё)
var rng := RandomNumberGenerator.new()

func setup(col, pos: Vector3, cfg: Dictionary) -> void:
	colony = col
	main = col.main
	nav = col.nav
	unit_name = String(cfg.get("name", "Землепроходец"))
	pal = cfg.get("pal", {})
	leader = bool(cfg.get("leader", false))
	rng.seed = int(cfg.get("seed", 7))
	position = Vector3(pos.x, main.ground_at(pos.x, pos.z), pos.z)
	_last_pos = position
	_build()
	show_tool(String(cfg.get("tool", "")))

func _build() -> void:
	var r := HS.build(self, pal)
	model = r["model"]
	m_ap = r["ap"]
	m_sk = r["sk"]
	m_ap.playback_default_blend_time = 0.22
	_grip = _grip_of("r")
	hand_att = BoneAttachment3D.new()
	hand_att.bone_name = "hand_r"
	m_sk.add_child(hand_att)
	back_att = BoneAttachment3D.new()
	back_att.bone_name = "spine_03"
	m_sk.add_child(back_att)
	# бревно на плече и короб с добычей за спиной
	log_node = MeshInstance3D.new()
	log_node.mesh = TM.log_mesh(1.3, 0.12, Color(0.44, 0.34, 0.25), 3)
	log_node.visible = false
	back_att.add_child(log_node)
	var s3 := m_sk.get_bone_global_rest(m_sk.find_bone("spine_03"))
	var lb := Basis(Vector3.UP, 0.0)
	lb.y = Vector3(0.1, 0.06, 1.0).normalized()
	lb.x = Vector3(1, 0, 0)
	lb.z = lb.x.cross(lb.y).normalized()
	lb.x = lb.y.cross(lb.z).normalized()
	# бревно лежит на правом плече вдоль взгляда (как у героя в hero_tools._pose_log)
	log_node.transform = s3.affine_inverse() * Transform3D(lb, Vector3(-0.22, s3.origin.y + 0.18, 0.0))
	sack_node = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.34, 0.4, 0.26)
	sack_node.mesh = bm
	sack_node.material_override = HS.mat(Color(0.74, 0.62, 0.42))
	sack_node.visible = false
	back_att.add_child(sack_node)
	sack_node.transform = s3.affine_inverse() * Transform3D(Basis(), Vector3(0.0, s3.origin.y - 0.05, -0.28))
	# кольцо выбора под ногами
	ring = MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.42
	tor.outer_radius = 0.52
	tor.rings = 5
	tor.ring_segments = 20
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(1.0, 0.86, 0.5, 0.85)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.cull_mode = BaseMaterial3D.CULL_DISABLED
	tor.material = rm
	ring.mesh = tor
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position.y = 0.06
	ring.visible = false
	add_child(ring)
	_mrot = model.rotation
	# подпись над головой: что человек делает сейчас
	task_lbl = Label3D.new()
	task_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	task_lbl.font_size = 44
	task_lbl.outline_size = 14
	task_lbl.pixel_size = 0.0042
	task_lbl.modulate = Color(1.0, 0.95, 0.84)
	task_lbl.outline_modulate = Color(0.06, 0.04, 0.02, 0.8)
	task_lbl.position.y = 2.2
	task_lbl.visible = false
	task_lbl.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	add_child(task_lbl)
	m_ap.play("Idle")
	m_cur = "Idle"

## Хват кисти по позе покоя (как в hero_tools): рукоять лежит в ладони наискось.
func _grip_of(side: String) -> Transform3D:
	var hb := m_sk.find_bone("hand_" + side)
	var hr := m_sk.get_bone_global_rest(hb)
	var h := hr.origin
	var m := m_sk.get_bone_global_rest(m_sk.find_bone("middle_01_" + side)).origin
	var ix := m_sk.get_bone_global_rest(m_sk.find_bone("index_01_" + side)).origin
	var pk := m_sk.get_bone_global_rest(m_sk.find_bone("pinky_01_" + side)).origin
	var f := (m - h).normalized()
	var a := (ix - pk).normalized()
	var p := Vector3(0, -1, 0)
	var A := (a + f * 0.36).normalized()
	var E := (f - A * f.dot(A)).normalized()
	var c := h + f * 0.088 + p * 0.03 + a * -0.004
	return hr.affine_inverse() * Transform3D(Basis(E, A, E.cross(A)), c)

## Инструмент в руку: нож, топор, копьё, лук ("" — пусто).
func show_tool(id: String) -> void:
	hold = id
	for k: String in tool_nodes:
		(tool_nodes[k] as MeshInstance3D).visible = k == id
	if id == "" or tool_nodes.has(id):
		return
	var mi := MeshInstance3D.new()
	var msh := TM.mesh_of(id)
	if msh == null:
		return
	mi.mesh = msh
	hand_att.add_child(mi)
	mi.transform = _grip
	tool_nodes[id] = mi
	mi.visible = true

## Подпись над головой: дело или имя ("" — спрятать).
func set_task(t: String) -> void:
	if task_lbl == null:
		return
	if t == "":
		task_lbl.visible = false
		return
	if task_lbl.text != t:
		task_lbl.text = t
	task_lbl.visible = true

func set_selected(on: bool) -> void:
	selected = on
	ring.visible = on and state != "dead"

# ---------- ноша ----------

func carry_total() -> int:
	var n := 0
	for k: String in carry:
		n += int(carry[k])
	return n

func carry_add(id: String, n: int) -> void:
	carry[id] = int(carry.get(id, 0)) + n
	_refresh_carry()

func carry_clear() -> void:
	carry = {}
	_refresh_carry()

func _refresh_carry() -> void:
	var logs := int(carry.get("log", 0))
	carry_kind = "log" if logs > 0 else ("goods" if carry_total() > 0 else "")
	log_node.visible = carry_kind == "log"
	sack_node.visible = carry_kind == "goods"

func carry_weight() -> float:
	var w := 0.0
	for k: String in carry:
		w += IT.weight_of(k) * float(carry[k])
	return w

## Сколько штук id ещё влезет в ношу (бревно — одно на плечо).
func carry_room(id: String) -> int:
	if id == "log":
		return 0 if carry_total() > 0 else 1
	if int(carry.get("log", 0)) > 0:
		return 0
	return int(floor((CARRY_KG - carry_weight()) / maxf(IT.weight_of(id), 0.05)))

func carry_full() -> bool:
	return carry_weight() >= CARRY_KG - 0.5 or int(carry.get("log", 0)) > 0

# ---------- путь ----------

## Идти в точку. false — пути нет.
func goto(p: Vector3, hurry: bool = false) -> bool:
	if state == "dead":
		return false
	run = hurry
	_goal = p
	var pts: Array = nav.find_path(position, p, area_lock)
	if pts.is_empty():
		# рядом цель или путь не нашёлся — попробуем прямо
		if Vector2(p.x - position.x, p.z - position.z).length() < 3.0:
			path = [p]
			state = "walk"
			return true
		path = []
		return false
	path = pts
	state = "walk"
	_repath = 0.0
	return true

func stop() -> void:
	path = []
	_goal = Vector3.INF
	if state == "walk":
		state = "idle"

func arrived() -> bool:
	return path.is_empty()

func dist_to(p: Vector3) -> float:
	return Vector2(p.x - position.x, p.z - position.z).length()

# ---------- шаг ----------

func tick(dt: float) -> void:
	if state == "dead":
		_animate(dt)
		return
	if state == "walk":
		_walk(dt)
	else:
		vel = vel.move_toward(Vector3.ZERO, 14.0 * dt)
		moving = false
		_turn = lerpf(_turn, 0.0, minf(1.0, dt * 8.0))
	position.y = main.ground_fast(position.x, position.z)
	_animate(dt)

func _walk(dt: float) -> void:
	if path.is_empty():
		state = "idle"
		moving = false
		return
	var tgt: Vector3 = path[0]
	var to := Vector2(tgt.x - position.x, tgt.z - position.z)
	var d := to.length()
	if d < (0.5 if path.size() > 1 else 0.35):
		path.remove_at(0)
		if path.is_empty():
			state = "idle"
			vel = Vector3.ZERO
			moving = false
			return
		tgt = path[0]
		to = Vector2(tgt.x - position.x, tgt.z - position.z)
		d = to.length()
	var dir := to / maxf(d, 0.001)
	# не наступать друг на друга: расходимся в стороны
	var push := Vector2.ZERO
	for u in colony.units:
		if u == self or u.state == "dead":
			continue
		var dv := Vector2(position.x - u.position.x, position.z - u.position.z)
		var dl := dv.length()
		if dl < 0.9 and dl > 0.001:
			push += dv / dl * (0.9 - dl) * 1.6
	dir = (dir + push).normalized()
	var sp := (RUN if run else SPEED)
	sp *= clampf(0.45 + health * 0.55, 0.4, 1.0) * (1.0 - clampf(fatigue, 0.0, 1.0) * 0.3)
	if carry_kind == "log":
		sp *= 0.72
	var snow: float = main.weather.snow if main.weather != null else 0.0
	sp *= 1.0 - clampf(snow, 0.0, 1.0) * 0.28
	var want := Vector3(dir.x, 0, dir.y) * sp
	vel = vel.move_toward(want, 9.0 * dt)
	vel.y = 0.0
	var step := vel * dt
	var np := position + step
	if _can_walk(np):
		position.x = np.x
		position.z = np.z
	elif _can_walk(position + Vector3(step.x, 0, 0)):
		position.x += step.x
	elif _can_walk(position + Vector3(0, 0, step.z)):
		position.z += step.z
	else:
		# упёрлись: ищем путь заново (не чаще раза в полсекунды)
		vel = Vector3.ZERO
		_repath -= dt
		if _repath <= 0.0:
			_repath = 0.5
			if _goal != Vector3.INF:
				var pts: Array = nav.find_path(position, _goal, area_lock)
				if pts.is_empty():
					path = []
					state = "idle"
				else:
					path = pts
	speed_now = Vector2(vel.x, vel.z).length()
	moving = speed_now > 0.2
	# застряли (ствол или камень вплотную): ищем путь заново, потом считаем, что пришли
	if moving:
		_stuck = 0.0
	else:
		_stuck += dt
		if _stuck > 1.0:
			_stuck = 0.0
			var pts2: Array = nav.find_path(position, path[path.size() - 1], area_lock)
			if pts2.is_empty() or pts2.size() > 24:
				path = []
				state = "idle"
			else:
				path = pts2
	if moving:
		# поворот с пределом по скорости: разворот плавный, без рывка
		var want_yaw := atan2(dir.x, dir.y)
		var dyaw := wrapf(want_yaw - yaw, -PI, PI)
		var rate: float = clampf(dyaw * 6.0, -3.4, 3.4)
		_turn = lerpf(_turn, rate, minf(1.0, dt * 10.0))
		yaw = wrapf(yaw + _turn * dt, -PI, PI)
		rotation.y = yaw
	# тропа: ноги утаптывают снег (как у героя)
	if main.feet != null and moving:
		_step_acc += speed_now * dt
		if _step_acc > 0.7:
			_step_acc = 0.0
			main.feet.add_wear(position.x, position.z, 0.7, 0.014, 0.75)
			# шаги слышно у вожака (он же герой для звука и следов)
			if leader and main.sfx != null:
				main.sfx.step(false, speed_now / 1.6)

func _can_walk(p: Vector3) -> bool:
	if not nav.passable(p.x, p.z):
		return false
	if area_lock and colony.zones != null and not bool(colony.zones.allowed(p.x, p.z)):
		return false
	return not main.blocked(p.x, p.z, 0.22)

# ---------- вид ----------

func _play(n: String, sc: float = 1.0, blend: float = 0.22) -> void:
	var a := SK.find_anim(m_ap, [n])
	if a == "":
		return
	if a != m_cur:
		m_ap.play(a, blend)
		m_cur = a
	m_ap.speed_scale = sc

func _animate(dt: float) -> void:
	var d := position - _last_pos
	_last_pos = position
	_hspeed = lerpf(_hspeed, Vector2(d.x, d.z).length() / maxf(dt, 0.001), minf(1.0, dt * 8.0))
	# крен в поворот: корпус чуть наклоняется внутрь дуги (и выпрямляется стоя)
	var want_lean := 0.0
	if state == "walk" and moving:
		want_lean = clampf(-_turn * 0.05 * clampf(_hspeed / 1.6, 0.0, 1.6), -0.13, 0.13)
	_lean = lerpf(_lean, want_lean, minf(1.0, dt * 6.0))
	if model != null:
		model.rotation = _mrot + Vector3(0.0, 0.0, _lean)
	if state == "dead":
		_play("Death01", 1.0, 0.2)
		return
	if state == "sleep":
		_play("Sitting_Idle", 1.0, 0.35)
		return
	if state == "work":
		match work_anim:
			"chop", "cut", "split":
				_play("TreeChopping", 1.0, 0.18)
			"build":
				_play("Farm_Harvest", 1.1, 0.2)
			"gather":
				_play("Farm_Harvest", 0.85, 0.2)
			"kneel":
				_play("Fixing_Kneeling", 0.0, 0.2)
				m_ap.seek(_kneel_time(), true)
			"cook":
				_play("Fixing_Kneeling", 0.0, 0.2)
				m_ap.seek(_kneel_time(), true)
			"shoot":
				_play("OverhandThrow", 0.8, 0.15)
			_:
				_play("Interact", 1.0, 0.2)
		return
	if _hspeed > 2.3:
		_play("Jog_Fwd", clampf(_hspeed / 3.1, 0.75, 1.2))
	elif _hspeed > 0.2:
		if carry_kind == "log":
			_play("Walk_Carry", clampf(_hspeed / 1.2, 0.7, 1.3))
		else:
			_play("Walk", clampf(_hspeed / 1.6, 0.65, 1.25))
	else:
		if carry_kind == "log":
			_play("Walk_Carry", 0.0)
		elif fatigue > 0.75:
			_play("Idle_FoldArms")
		else:
			_play("Idle")

## Петля работы руками в Fixing_Kneeling (как у разделки героя).
func _kneel_time() -> float:
	var t: float = float(job.get("t", 0.0))
	if t < 1.15:
		return t
	var u := fmod(t - 1.15, 3.4)
	var w := u if u < 1.7 else 3.4 - u
	return 1.6 + w

# ---------- нужды ----------

## dh — прошедшие игровые часы, warm — целевое тепло в этом месте (0..1).
func needs_tick(dh: float, warm: float) -> void:
	if state == "dead":
		return
	var work: float = 1.6 if state == "work" else (1.2 if moving else 0.7)
	hunger = maxf(0.0, hunger - 0.022 * dh * work)
	warmth = lerpf(warmth, warm, clampf(dh * 1.6, 0.0, 1.0))
	if state == "sleep":
		fatigue = maxf(0.0, fatigue - 0.14 * dh)
	else:
		fatigue = minf(1.4, fatigue + 0.022 * dh * work)
	if bleed > 0.0:
		health -= bleed * 0.06 * dh
		bleed = maxf(0.0, bleed - 0.12 * dh)
	if hunger <= 0.02:
		health -= 0.03 * dh
	if warmth < 0.12:
		health -= 0.05 * dh
	if fatigue > 1.2:
		health -= 0.01 * dh
	if hunger > 0.3 and warmth > 0.3 and bleed <= 0.01:
		health = minf(1.0, health + 0.02 * dh)
	if health <= 0.0:
		die()

func eat(id: String, value: float) -> void:
	hunger = minf(1.0, hunger + value)
	if id in ["meat_cooked", "fish_cooked", "stew", "fish_soup", "tea", "broth"]:
		warmth = minf(1.0, warmth + 0.12)

func hurt(dmg: float, from: Vector3, _kind: String) -> void:
	if state == "dead":
		return
	health = maxf(0.0, health - dmg)
	bleed = minf(1.2, bleed + dmg * 0.7)
	var away := position - from
	away.y = 0.0
	if away.length() > 0.01:
		position += away.normalized() * 0.25
	if main.get("hunt") != null and main.hunt != null:
		main.hunt.splat(position, 0.14, 0.5, 14.0)
	if health <= 0.0:
		die()

func die() -> void:
	if state == "dead":
		return
	health = 0.0
	state = "dead"
	job = {}
	path = []
	carry_clear()
	show_tool("")
	ring.visible = false
	rotation.y = yaw
	if colony != null:
		colony.on_unit_died(self)

func revive(p: Vector3) -> void:
	state = "idle"
	health = 0.5
	hunger = maxf(hunger, 0.5)
	warmth = 0.5
	fatigue = 0.3
	bleed = 0.0
	position = Vector3(p.x, main.ground_at(p.x, p.z), p.z)
	m_cur = ""
	_play("Idle")

func status() -> String:
	if state == "dead":
		return "погиб"
	if not job.is_empty():
		return String(job.get("label", "занят"))
	return "ждёт"

# ---------- сохранение ----------

func to_save() -> Dictionary:
	var SV = preload("res://scripts/save.gd")
	return {"name": unit_name, "pos": SV.enc(position), "yaw": yaw, "health": health,
		"hunger": hunger, "warmth": warmth, "fatigue": fatigue, "bleed": bleed,
		"state": state if state != "walk" else "idle", "hold": hold,
		"carry": carry.duplicate(), "auto": auto, "lock": area_lock}

func from_save(d: Dictionary) -> void:
	var SV = preload("res://scripts/save.gd")
	var p: Vector3 = SV.dec(d.get("pos", SV.enc(position)))
	position = Vector3(p.x, main.ground_at(p.x, p.z), p.z)
	yaw = float(d.get("yaw", 0.0))
	rotation.y = yaw
	health = float(d.get("health", 1.0))
	hunger = float(d.get("hunger", 0.9))
	warmth = float(d.get("warmth", 0.7))
	fatigue = float(d.get("fatigue", 0.1))
	bleed = float(d.get("bleed", 0.0))
	auto = bool(d.get("auto", true))
	area_lock = bool(d.get("lock", false))
	carry = {}
	var c: Dictionary = d.get("carry", {})
	for k: String in c:
		carry[k] = int(c[k])
	_refresh_carry()
	show_tool(String(d.get("hold", "")))
	state = String(d.get("state", "idle"))
	if state == "dead":
		die()
	else:
		path = []
		job = {}
