extends Node3D
## Зверь: модель из animal_model.gd, походка по скорости (шаг, рысь, галоп, прыжки),
## поведение-автомат: отдых, пастьба, бродит, настороже, бегство, выслеживание, погоня, нападение.

const AM = preload("res://scripts/animal_model.gd")
const SK = preload("res://scripts/skin.gd")

# чутьё на человека (м), время активности, роль
const SENSE := {"hare": 14.0, "squirrel": 10.0, "fox": 26.0, "roe": 36.0, "deer": 45.0, "boar": 22.0, "wolf": 55.0, "bear": 26.0, "tiger": 40.0, "beaver": 12.0}
const ACTIVE := {"hare": "night", "fox": "dusk", "wolf": "night", "roe": "dusk", "deer": "dusk", "boar": "dusk", "bear": "day", "tiger": "dusk", "squirrel": "day", "beaver": "night"}
const PREY := ["hare", "squirrel", "roe", "deer", "beaver"]
const DAMAGE := {"wolf": 0.12, "bear": 0.4, "boar": 0.22, "tiger": 0.5}

var kind := ""
var sp: Dictionary
var parts: Dictionary
var main: Node3D
var mgr: Node
var home := Vector3.ZERO
var home_r := 60.0
var male := false
var scale_k := 1.0
var winter_skin := false

var state := "wander"
var state_t := 0.0
var target := Vector3.ZERO
var speed := 0.0
var want := 0.0
var heading := 0.0
var phase := 0.0
var think_t := 0.0
var threat: Node3D = null
var prey: Node3D = null
var leader: Node3D = null
var pack_slot := 0.0
var bites := 0
var attack_cd := 0.0
var dead := false
var respawn_at := 0.0
var head_pitch := 0.0
var rest_k := 0.0
var tree := Vector3.ZERO
var climb_h := 0.0
var far := false
var group := -1
var _acc := 0.0
var rng := RandomNumberGenerator.new()

func setup(k: String, m: Node3D, mg: Node, pos: Vector3, seed_v: int, sc: float = 1.0) -> void:
	kind = k
	main = m
	mgr = mg
	home = pos
	scale_k = sc
	rng.seed = seed_v
	male = rng.randf() < 0.5
	sp = AM.SPECIES[k]
	position = pos
	heading = rng.randf() * TAU
	home_r = {"hare": 40.0, "squirrel": 25.0, "fox": 90.0, "roe": 70.0, "deer": 110.0, "boar": 80.0, "wolf": 160.0, "bear": 120.0, "tiger": 200.0, "beaver": 18.0}[k]
	_build(false)
	_new_wander()

func _build(winter: bool) -> void:
	for c in get_children():
		c.queue_free()
	if SK.has(kind):
		parts = SK.build_animal(self, kind, scale_k, winter)
	else:
		parts = AM.build(self, kind, scale_k, male, winter)
	winter_skin = winter

## Активен ли вид сейчас (по времени суток).
func is_active() -> bool:
	var t: float = main.t_hours
	match ACTIVE.get(kind, "day"):
		"night":
			return t < 7.0 or t > 18.0
		"dusk":
			return t < 10.0 or t > 16.0
		_:
			return t > 6.0 and t < 21.0
	return true

func _new_wander() -> void:
	var a := rng.randf() * TAU
	var r := rng.randf_range(5.0, 25.0)
	target = position + Vector3(cos(a), 0, sin(a)) * r
	if target.distance_to(home) > home_r:
		target = home + (target - home).normalized() * home_r * 0.6
	state = "wander"
	state_t = rng.randf_range(8.0, 20.0)

func hero_dist() -> float:
	return Vector2(position.x - main.hero.position.x, position.z - main.hero.position.z).length()

## Раз в 0,2 с: решения. Видимость человека зависит от его скорости, ночи и погоды.
func think() -> void:
	var hero: Node3D = main.hero
	var dh := hero_dist()
	var w = main.weather
	var sense: float = SENSE[kind] * (1.0 + float(hero.run_mag) * 0.6) * (0.6 + 0.4 * float(main.day_factor)) * (1.0 - float(w.precip) * 0.3)
	if hero.state == "sit":
		sense *= 0.5
	var hero_alive: bool = main.health > 0.0
	# смена шубки: заяц белеет, белка сереет
	if kind in ["hare", "squirrel"] and not far:
		var wint: bool = w.season_index() == 1 or float(w.snow) > 0.4
		if wint != winter_skin:
			_build(wint)
	# спячка медведя: зимой его нет
	if kind == "bear" and w.season_index() == 1:
		visible = false
		state = "sleep"
		return
	match state:
		"sleep":
			if not (kind == "bear" and w.season_index() == 1):
				visible = true
				_new_wander()
		"wander", "graze", "rest", "alert":
			# хищник: охота на добычу или на человека
			if kind in ["fox", "wolf", "tiger"] and (state != "rest" or rng.randf() < 0.05):
				_hunt_choice(dh, sense, hero_alive)
				if state == "stalk" or state == "chase":
					return
			if kind in ["bear", "boar"] and hero_alive and dh < (9.0 if kind == "bear" else 6.0):
				state = "charge"
				state_t = 6.0
				return
			# добыча: бежит от человека и хищников
			var pred = mgr.nearest_predator(self, 30.0) if kind in PREY or kind == "fox" else null
			if pred != null:
				threat = pred
				state = "flee"
				state_t = 6.0
				return
			if dh < sense and not (kind in ["bear", "wolf", "tiger"] and hero_alive):
				if dh < sense * 0.55 or state == "alert":
					threat = hero
					state = "flee"
					state_t = rng.randf_range(4.0, 7.0)
					if kind == "squirrel":
						var tp: Vector3 = main.nearest_tree(position, 15.0)
						if tp != Vector3.INF:
							tree = tp
							state = "to_tree"
					return
				state = "alert"
				state_t = 2.0
				return
			if state_t <= 0.0:
				if not is_active():
					state = "rest"
					state_t = rng.randf_range(20.0, 60.0)
				elif rng.randf() < (0.5 if kind in ["roe", "deer", "hare", "boar", "beaver"] else 0.2):
					state = "graze"
					state_t = rng.randf_range(6.0, 16.0)
				else:
					_new_wander()
		"flee":
			if state_t <= 0.0 and (threat == null or position.distance_to(threat.position) > SENSE[kind] * 1.3):
				threat = null
				_new_wander()
		"stalk", "chase":
			_update_hunt(dh, hero_alive)
		"attack":
			pass
		"retreat":
			if state_t <= 0.0:
				_new_wander()
		"charge":
			if state_t <= 0.0 or dh > 25.0 or not hero_alive:
				state = "retreat"
				state_t = 8.0
		"tree":
			if state_t <= 0.0 and dh > 12.0:
				state = "down_tree"

func _hunt_choice(dh: float, sense: float, hero_alive: bool) -> void:
	var w = main.weather
	var hungry_night: bool = not float(main.day_factor) > 0.5 or w.season_index() == 1
	if kind == "fox":
		var h = mgr.nearest_of(self, ["hare"], 30.0)
		if h != null:
			prey = h
			state = "stalk"
			state_t = 20.0
		return
	# волки и тигр: на человека — ночью или зимой; иначе на оленей и косуль
	if hero_alive and dh < sense and (hungry_night or kind == "tiger"):
		prey = main.hero
		state = "stalk"
		state_t = 25.0
		if kind == "wolf":
			mgr.pack_hunt(self, main.hero)
		return
	var p = mgr.nearest_of(self, ["roe", "deer", "boar"], 60.0)
	if p != null and rng.randf() < 0.3:
		prey = p
		state = "stalk"
		state_t = 25.0
		if kind == "wolf":
			mgr.pack_hunt(self, p)

func _update_hunt(dh: float, hero_alive: bool) -> void:
	if prey == null or (prey != main.hero and prey.dead) or (prey == main.hero and not hero_alive):
		prey = null
		_new_wander()
		return
	var d := position.distance_to(prey.position)
	if state_t <= 0.0 or d > 90.0:
		prey = null
		state = "retreat"
		state_t = 6.0
		return
	if state == "stalk" and d < (12.0 if kind != "tiger" else 9.0):
		state = "chase"
		state_t = 12.0

## Кадр: движение, высота, поворот, анимация.
func tick(delta: float) -> void:
	if dead:
		if float(main.t_hours) + float(main.day_count) * 24.0 > respawn_at:
			dead = false
			visible = true
			position = home
			_new_wander()
		return
	state_t -= delta
	attack_cd -= delta
	think_t -= delta
	if think_t <= 0.0:
		think_t = 0.2 + rng.randf() * 0.1
		var was := state
		think()
		if state == "flee" and was != "flee" and threat != null:
			mgr.alarm(self, threat)
	if state == "sleep":
		return
	var run: float = sp["run"] * (1.0 if scale_k > 0.6 else 0.7)
	var walk: float = sp["walk"]
	var goal := target
	want = 0.0
	match state:
		"wander":
			want = walk
			if Vector2(goal.x - position.x, goal.z - position.z).length() < 1.0:
				state_t = 0.0
				want = 0.0
		"graze", "rest", "alert", "tree":
			want = 0.0
		"flee":
			if threat != null:
				var away := (position - threat.position)
				away.y = 0
				goal = position + away.normalized() * 10.0
				# заяц петляет
				if kind == "hare":
					goal += Vector3(sin(Time.get_ticks_msec() * 0.004), 0, cos(Time.get_ticks_msec() * 0.003)) * 4.0
			want = run
		"stalk":
			if prey != null:
				goal = prey.position + Vector3(cos(pack_slot), 0, sin(pack_slot)) * (6.0 if kind == "wolf" else 0.0)
			want = walk * 0.8
		"chase", "charge":
			var tg: Node3D = prey if state == "chase" else main.hero
			if tg != null:
				goal = tg.position
				var d := Vector2(goal.x - position.x, goal.z - position.z).length()
				want = run * (0.75 if state == "charge" and d > 10.0 else 1.0)
				if d < 0.6 + float(parts["L"]) * 0.55:
					_strike(tg)
		"retreat":
			var away2: Vector3 = position - main.hero.position
			away2.y = 0
			goal = position + away2.normalized() * 10.0
			want = run * 0.6
		"to_tree":
			goal = tree
			want = run
			var dt2 := Vector2(tree.x - position.x, tree.z - position.z)
			if dt2.length() < 1.3:
				position.x = tree.x - dt2.normalized().x * 0.3
				position.z = tree.z - dt2.normalized().y * 0.3
				state = "tree"
				state_t = rng.randf_range(15.0, 30.0)
		"down_tree":
			want = 0.0
	# беличье дерево: вверх по стволу и обратно
	if kind == "squirrel":
		if state == "tree":
			climb_h = minf(climb_h + delta * 2.0, 6.0)
		elif climb_h > 0.0:
			climb_h = maxf(climb_h - delta * 1.5, 0.0)
			if climb_h <= 0.0 and state == "down_tree":
				_new_wander()
	# поворот к цели и разгон
	var to := goal - position
	to.y = 0
	if to.length() > 0.2 and want > 0.0:
		var hd := atan2(to.x, to.z)
		heading = lerp_angle(heading, hd, minf(1.0, delta * (3.0 + want * 0.4)))
	speed = move_toward(speed, want, delta * (4.0 + want * 0.8))
	if climb_h <= 0.0 and speed > 0.01:
		var dir := Vector3(sin(heading), 0, cos(heading))
		var np := position + dir * speed * delta
		# обход стволов и воды (кроме бобра)
		var gy: float = main.height(np.x, np.z)
		var wet: bool = gy < main.WATER_Y - 0.3 and kind != "beaver"
		if main.blocked(np.x, np.z, 0.2 * scale_k) or wet or absf(np.x) > main.SIZE * 0.5 - 10.0 or absf(np.z) > main.SIZE * 0.5 - 10.0:
			heading += (1.0 if rng.randf() < 0.5 else -1.0) * 0.9
			speed *= 0.5
		else:
			position.x = np.x
			position.z = np.z
	var g: float = main.ground_at(position.x, position.z)
	if kind == "beaver":
		g = maxf(g, main.WATER_Y - 0.12)
	position.y = g + climb_h
	rotation.y = heading
	if not far:
		_animate(delta)

func _strike(tg: Node3D) -> void:
	if attack_cd > 0.0:
		return
	attack_cd = 1.3
	_attack_t = 0.8
	if tg == main.hero:
		main.hurt(DAMAGE.get(kind, 0.1), position, kind)
		bites += 1
		# волк кусает пару раз и отходит; кабан бьёт и уходит
		if (kind == "wolf" and bites >= 2) or kind == "boar":
			bites = 0
			state = "retreat"
			state_t = rng.randf_range(5.0, 10.0)
	else:
		tg.kill()
		state = "graze"
		state_t = 30.0
		prey = null

func kill() -> void:
	dead = true
	visible = false
	respawn_at = float(main.t_hours) + float(main.day_count) * 24.0 + 24.0

## Походка: фазы ног по виду аллюра, наклон по склону, голова, хвост, отдых.
var goffs := [0.0, 0.5, 0.75, 0.25]
var r_s := 0.0
var _breath := 0.0

var _attack_t := 0.0

## Готовая модель: выбор анимации по состоянию и скорости, темп шага по реальной скорости.
func _animate_model(delta: float) -> void:
	var ap: AnimationPlayer = parts["ap"]
	_attack_t -= delta
	var walk: float = sp["walk"]
	var want_a := ""
	var sc := 1.0
	if _attack_t > 0.0:
		want_a = SK.find_anim(ap, ["Attack", "Attack_Headbutt"])
	elif speed > walk * 1.7:
		want_a = SK.find_anim(ap, ["Gallop"])
		sc = clampf(speed / (float(sp["run"]) * 0.75), 0.6, 1.6)
	elif speed > 0.08:
		want_a = SK.find_anim(ap, ["Walk"])
		sc = clampf(speed / walk, 0.4, 1.8)
	elif state == "graze":
		want_a = SK.find_anim(ap, ["Eating"])
	elif state in ["rest", "sleep"]:
		want_a = SK.find_anim(ap, ["Idle_Headlow", "Idle_2_HeadLow", "Idle"])
	elif state == "alert":
		want_a = SK.find_anim(ap, ["Idle_2", "Idle"])
	else:
		want_a = SK.find_anim(ap, ["Idle"])
	if want_a != "" and want_a != parts["cur"]:
		ap.play(want_a, 0.35)
		parts["cur"] = want_a
	ap.speed_scale = sc
	# наклон по склону
	var L: float = parts["L"]
	var fwd := Vector3(sin(heading), 0, cos(heading))
	var hf: float = main.ground_at(position.x + fwd.x * L * 0.4, position.z + fwd.z * L * 0.4)
	var hb: float = main.ground_at(position.x - fwd.x * L * 0.4, position.z - fwd.z * L * 0.4)
	var m: Node3D = parts["model"]
	m.rotation.x = lerpf(m.rotation.x, -atan2(hf - hb, L * 0.8), minf(1.0, delta * 6.0))

func _animate(delta: float) -> void:
	if parts.has("ap"):
		_animate_model(delta)
		return
	var body: Node3D = parts["body"]
	var head: Node3D = parts["head"]
	var legs: Array = parts["legs"]
	var H: float = parts["H"]
	var L: float = parts["L"]
	var run: float = sp["run"]
	var r := clampf(speed / run, 0.0, 1.0)
	var gait: String = sp["gait"]
	var offs := [0.0, 0.5, 0.75, 0.25]
	if r > 0.35:
		if gait == "bound":
			offs = [0.0, 0.05, 0.5, 0.55]
		else:
			offs = [0.0, 0.12, 0.55, 0.67]
	elif gait == "trot" or (r > 0.15 and gait == "walk"):
		offs = [0.0, 0.5, 0.5, 0.0]
	if gait == "bound" and r > 0.02:
		offs = [0.0, 0.05, 0.5, 0.55]
	# фазы ног меняются плавно, без рывка при смене аллюра
	var gk := minf(1.0, delta * 3.0)
	for i in 4:
		var dd := wrapf(float(offs[i]) - float(goffs[i]), -0.5, 0.5)
		goffs[i] = float(goffs[i]) + dd * gk
	offs = goffs
	r_s = lerpf(r_s, r, minf(1.0, delta * 4.0))
	r = r_s
	var stride := H * (1.4 + r * 2.6)
	phase += speed / maxf(stride, 0.05) * TAU * delta
	var amp := 0.3 + r * 0.55
	var mv := clampf(speed * 3.0, 0.0, 1.0)
	rest_k = lerpf(rest_k, 1.0 if state == "rest" else 0.0, minf(1.0, delta * 2.0))
	for i in 4:
		var lg: Dictionary = legs[i]
		var hip: Node3D = lg["hip"]
		var knee: Node3D = lg["knee"]
		var ph: float = phase + float(offs[i]) * TAU
		var front: bool = lg["front"]
		var sw := sin(ph) * amp * mv
		hip.rotation.x = lerpf(sw, (-1.3 if front else 1.1), rest_k)
		var bend := maxf(0.0, cos(ph)) * amp * 1.3 * mv
		knee.rotation.x = lerpf((bend if front else -bend * 0.8 - 0.15 * mv), (2.4 if front else -2.2), rest_k)
	# наклон тела по склону, подпрыгивание
	var fwd := Vector3(sin(heading), 0, cos(heading))
	var hf: float = main.ground_at(position.x + fwd.x * L * 0.4, position.z + fwd.z * L * 0.4)
	var hb: float = main.ground_at(position.x - fwd.x * L * 0.4, position.z - fwd.z * L * 0.4)
	var pitch := -atan2(hf - hb, L * 0.8)
	var bob := absf(sin(phase * (1.0 if gait != "bound" else 1.0))) * H * (0.03 + r * (0.18 if gait == "bound" else 0.06)) * mv
	body.position.y = lerpf(H + bob, H * 0.45, rest_k)
	_breath += delta * (1.4 + r * 4.0)
	body.rotation.x = lerpf(body.rotation.x, pitch + (sin(phase) * 0.18 * r if gait == "bound" else 0.0), minf(1.0, delta * 8.0))
	# покачивание корпуса с шагом и дыхание в покое
	body.rotation.z = sin(phase) * 0.035 * mv * (1.0 - r * 0.5)
	body.scale = Vector3(1.0 + sin(_breath) * 0.012 * (1.0 - mv), 1.0 + sin(_breath) * 0.018 * (1.0 - mv), 1.0)
	if kind == "squirrel" and climb_h > 0.0:
		body.rotation.x = -1.45
		body.position.y = H + 0.1
	# голова: пасётся — вниз, настороже — вверх, на бегу вытянута
	var hp := 0.0
	if state == "graze":
		hp = 0.9 + sin(Time.get_ticks_msec() * 0.002 + float(rng.seed % 7)) * 0.15
	elif state == "alert":
		hp = -0.35
	elif r > 0.4:
		hp = 0.25
	head_pitch = lerpf(head_pitch, hp, minf(1.0, delta * 4.0))
	head.rotation.x = head_pitch + sin(phase * 2.0) * 0.04 * mv
	if state == "alert" and main.hero != null:
		var to: Vector3 = main.hero.position - position
		head.rotation.y = clampf(wrapf(atan2(to.x, to.z) - heading, -PI, PI), -0.9, 0.9)
	else:
		head.rotation.y = lerpf(head.rotation.y, 0.0, minf(1.0, delta * 3.0))
	var tail: Node3D = parts["tail"]
	tail.rotation.x = sin(phase * 2.0) * 0.1 * mv + (0.4 if r > 0.5 else 0.0)
	tail.rotation.y = sin(Time.get_ticks_msec() * 0.003) * 0.15 * (1.0 - mv)
