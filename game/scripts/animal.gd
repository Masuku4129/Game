extends Node3D
## Зверь: модель из animal_model.gd, походка по скорости (шаг, рысь, галоп, прыжки),
## поведение-автомат: отдых, пастьба, бродит, настороже, бегство, выслеживание, погоня, нападение.

const AM = preload("res://scripts/animal_model.gd")
const SK = preload("res://scripts/skin.gd")

# чутьё на человека (м), время активности, роль
const SENSE := {"hare": 14.0, "squirrel": 10.0, "fox": 26.0, "roe": 36.0, "deer": 45.0, "boar": 22.0, "wolf": 55.0, "bear": 26.0, "tiger": 40.0, "beaver": 8.0}
const ACTIVE := {"hare": "night", "fox": "dusk", "wolf": "night", "roe": "dusk", "deer": "dusk", "boar": "dusk", "bear": "day", "tiger": "dusk", "squirrel": "day", "beaver": "night"}
const PREY := ["hare", "squirrel", "roe", "deer", "beaver"]
const DAMAGE := {"wolf": 0.12, "bear": 0.4, "boar": 0.22, "tiger": 0.5}
# новые виды тайги: лось, рысь, росомаха, кабарга, глухарь
const TAIGA_SENSE := {"moose": 40.0, "lynx": 30.0, "wolverine": 28.0, "muskdeer": 30.0, "capercaillie": 22.0}
const TAIGA_ACTIVE := {"moose": "dusk", "lynx": "dusk", "wolverine": "day", "muskdeer": "dusk", "capercaillie": "day"}
const TAIGA_PREY := ["moose", "muskdeer", "capercaillie"]
const TAIGA_DAMAGE := {"moose": 0.3, "wolverine": 0.15}
const TAIGA_HOME := {"moose": 140.0, "lynx": 150.0, "wolverine": 200.0, "muskdeer": 60.0, "capercaillie": 50.0}
# кого ловят рысь и росомаха; на кого бросаются, если подойти вплотную (м)
const HUNTS := {"lynx": ["hare", "capercaillie", "muskdeer", "roe"], "wolverine": ["hare", "capercaillie", "muskdeer", "beaver"]}
const CHARGE := {"bear": 9.0, "boar": 6.0, "moose": 5.0, "wolverine": 3.5}

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
var trk := 0.0       # путь с последнего следа
var trk_side := 1.0
var rng := RandomNumberGenerator.new()
# бобр на работе (state "job" — идёт/плывёт к job_p, "gnaw" — грызёт, повернувшись к job_face)
var job_p := Vector3.ZERO
var job_face := Vector3.ZERO
var arrived := false
var gnaw_low := false
var carry: Node3D = null
var slap_t := 0.0
var dive_k := 0.0
var gnaw_k := 0.0

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
	home_r = TAIGA_HOME[k] if TAIGA_HOME.has(k) else {"hare": 40.0, "squirrel": 25.0, "fox": 90.0, "roe": 70.0, "deer": 110.0, "boar": 80.0, "wolf": 160.0, "bear": 120.0, "tiger": 200.0, "beaver": 18.0}[k]
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
	match TAIGA_ACTIVE.get(kind, ACTIVE.get(kind, "day")):
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
	# цель на другом ярусе уступа или в реке (для тех, кто не плавает) — ближе к дому
	var th: float = main.height(target.x, target.z)
	if absf(th - main.height(position.x, position.z)) > 4.0 or (th < main.WATER_Y - 0.3 and not swimmer()):
		target = home + Vector3(rng.randf_range(-8, 8), 0, rng.randf_range(-8, 8))
	state = "wander"
	state_t = rng.randf_range(8.0, 20.0)

func hero_dist() -> float:
	return Vector2(position.x - main.hero.position.x, position.z - main.hero.position.z).length()

## Раз в 0,2 с: решения. Видимость человека зависит от его скорости, ночи и погоды.
func think() -> void:
	var hero: Node3D = main.hero
	var dh := hero_dist()
	var w = main.weather
	var sense: float = _sense() * (1.0 + float(hero.run_mag) * 0.6) * (0.6 + 0.4 * float(main.day_factor)) * (1.0 - float(w.precip) * 0.3)
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
		"wander", "graze", "rest", "alert", "job", "gnaw":
			# хищник: охота на добычу или на человека
			if (kind in ["fox", "wolf", "tiger"] or HUNTS.has(kind)) and (state != "rest" or rng.randf() < 0.05):
				_hunt_choice(dh, sense, hero_alive)
				if state == "stalk" or state == "chase":
					return
			if CHARGE.has(kind) and hero_alive and dh < float(CHARGE[kind]):
				state = "charge"
				state_t = 6.0
				return
			# добыча: бежит от человека и хищников
			var pred = mgr.nearest_predator(self, 30.0) if kind in PREY or kind in TAIGA_PREY or kind in ["fox", "lynx", "wolverine"] else null
			if pred != null:
				threat = pred
				state = "flee"
				state_t = 6.0
				return
			var busy := state == "job" or state == "gnaw"
			if dh < sense and not (kind in ["bear", "wolf", "tiger"] and hero_alive) and (not busy or dh < sense * 0.55):
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
			if state_t <= 0.0 and not busy:
				if not is_active():
					state = "rest"
					state_t = rng.randf_range(20.0, 60.0)
				elif rng.randf() < (0.5 if kind in ["roe", "deer", "hare", "boar", "beaver", "moose", "muskdeer", "capercaillie"] else 0.2):
					state = "graze"
					state_t = rng.randf_range(6.0, 16.0)
				else:
					_new_wander()
		"flee":
			if state_t <= 0.0 and (threat == null or position.distance_to(threat.position) > _sense() * 1.3):
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
	if HUNTS.has(kind):
		# рысь и росомаха: мелкая добыча, на человека не охотятся
		var hp = mgr.nearest_of(self, HUNTS[kind], 35.0)
		if hp != null and (hp.kind != "roe" or hp.scale_k < 0.95) and rng.randf() < 0.5:
			prey = hp
			state = "stalk"
			state_t = 20.0
		return
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
	var p = mgr.nearest_of(self, ["roe", "deer", "boar", "moose", "muskdeer"], 60.0)
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
	if state == "stalk" and d < (9.0 if kind in ["tiger", "lynx"] else 12.0):
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
			# бобр в воде бьёт хвостом по воде и уходит под воду
			if kind == "beaver" and swim_k > 0.5 and slap_t <= 0.0:
				slap_t = 0.7
	if state == "sleep":
		return
	if state == "gnaw" and job_face != Vector3.ZERO:
		heading = lerp_angle(heading, atan2(job_face.x - position.x, job_face.z - position.z), minf(1.0, delta * 5.0))
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
		"graze", "rest", "alert", "tree", "gnaw":
			want = 0.0
		"job":
			goal = job_p
			want = walk * (1.5 if swim_k > 0.5 else 1.0)
			var dj := Vector2(job_p.x - position.x, job_p.z - position.z).length()
			if dj < maxf(0.35, walk * 2.0 * delta):
				arrived = true
				want = 0.0
		"flee":
			if kind == "beaver":
				# бобр уходит к хатке
				goal = home
			elif threat != null:
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
	# глухарь: спугнутый — взлетает и летит низко над землёй, потом садится
	if kind == "capercaillie":
		var wet_below: bool = main.height(position.x, position.z) < main.WATER_Y - 0.2
		var up: bool = (state == "flee" and speed > sp["walk"] * 4.0) or wet_below
		climb_h = move_toward(climb_h, 4.5 if up else 0.0, delta * (3.0 if up else 1.6))
	# поворот к цели и разгон
	var to := goal - position
	to.y = 0
	if to.length() > 0.2 and want > 0.0:
		var hd := atan2(to.x, to.z)
		heading = lerp_angle(heading, hd, minf(1.0, delta * (3.0 + want * 0.4)))
	if swim_k > 0.3 and kind != "beaver":
		want *= 0.45
	speed = move_toward(speed, want, delta * (4.0 + want * 0.8))
	var flying: bool = kind == "capercaillie" and climb_h > 0.5
	if (climb_h <= 0.0 or kind == "capercaillie") and speed > 0.01:
		var dir := Vector3(sin(heading), 0, cos(heading))
		var np := position + dir * speed * delta
		# обход стволов и воды (кроме бобра)
		# крупные звери плывут, мелкие обходят воду; отвесный уступ не одолеть
		var gy: float = main.height(np.x, np.z)
		var g0: float = main.height(position.x, position.z)
		var wet: bool = gy < main.WATER_Y - 0.3 and not swimmer() and not flying
		var steep: bool = (gy - g0) > maxf(0.35, speed * delta * 1.6) and gy > main.WATER_Y and not flying
		if main.blocked(np.x, np.z, 0.2 * scale_k) or wet or steep or absf(np.x) > main.SIZE * 0.5 - 10.0 or absf(np.z) > main.SIZE * 0.5 - 10.0:
			heading += _turn_dir * 0.9
			speed *= 0.5
			_bump += 1
		else:
			position.x = np.x
			position.z = np.z
	_unstick(delta)
	var g: float = main.ground_at(position.x, position.z)
	var wl: float = main.water_level(position.x, position.z)
	swim_k = clampf((wl - 0.25 - g) / 0.6, 0.0, 1.0) if swimmer() else 0.0
	if kind == "beaver":
		# плывёт: над водой только голова и спина; испуганный ныряет у хатки
		var hide := state == "flee" and slap_t <= 0.0 and swim_k > 0.8
		dive_k = move_toward(dive_k, 1.0 if hide else 0.0, delta * 1.5)
		g = lerpf(g, wl - 0.32 * scale_k - dive_k * 0.4, swim_k)
	elif swim_k > 0.0:
		# плывёт: над водой голова и спина
		g = lerpf(g, wl - float(parts.get("H", 0.8)) * 0.55, swim_k)
	position.y = g + climb_h
	# на снегу: лёгкие бегут поверху, тяжёлые проваливаются; в снегу и грязи — следы
	if climb_h <= 0.0 and swim_k <= 0.0 and main.feet != null and g < main.height(position.x, position.z) + 0.1:
		position.y += main.feet.animal_step(self, speed * delta)
	rotation.y = heading
	if not far:
		_animate(delta)

var swim_k := 0.0
var _bump := 0
var _turn_dir := 1.0
var _chk_t := 0.0
var _chk_p := Vector3.ZERO

func swimmer() -> bool:
	return kind != "hare" and kind != "squirrel" and kind != "capercaillie"

func _sense() -> float:
	return TAIGA_SENSE[kind] if TAIGA_SENSE.has(kind) else SENSE[kind]

## Застрял (упирается в склон, ствол или воду и почти не движется) — новая цель в сторону,
## откуда пришёл, со сменой направления обхода; долго не выходит — переносится к дому.
func _unstick(delta: float) -> void:
	_chk_t += delta
	if _chk_t < 2.0:
		return
	var moved := Vector2(position.x - _chk_p.x, position.z - _chk_p.z).length()
	var tried := want > 0.3
	_chk_t = 0.0
	_chk_p = position
	if not tried or moved > 0.8:
		_bump = 0
		return
	_turn_dir = -_turn_dir
	var back := heading + PI + rng.randf_range(-0.8, 0.8)
	target = position + Vector3(sin(back), 0, cos(back)) * rng.randf_range(8.0, 18.0)
	heading = back
	if state == "wander":
		state_t = rng.randf_range(6.0, 12.0)
	if _bump > 40:
		_bump = 0
		position = home + Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-6, 6))

func _strike(tg: Node3D) -> void:
	if attack_cd > 0.0:
		return
	attack_cd = 1.3
	_attack_t = 0.8
	if tg == main.hero:
		main.hurt(TAIGA_DAMAGE.get(kind, DAMAGE.get(kind, 0.1)), position, kind)
		bites += 1
		# волк кусает пару раз и отходит; кабан бьёт и уходит
		if (kind == "wolf" and bites >= 2) or kind in ["boar", "moose", "wolverine"]:
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
	elif swim_k > 0.5:
		want_a = SK.find_anim(ap, ["Walk"])
		sc = 0.7 if speed > 0.05 else 0.25
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
	m.rotation.x = lerpf(m.rotation.x, -atan2(hf - hb, L * 0.8) * (1.0 - swim_k), minf(1.0, delta * 6.0))

func _animate(delta: float) -> void:
	if parts.has("rig"):
		_animate_rig(delta)
		return
	if kind == "beaver":
		_animate_beaver(delta)
		return
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

# ---------- Походка зверей на скелете (модели build_taiga) ----------
# Поворачиваются кости: нога (лопатка/таз, плечо/бедро, предплечье/голень, пясть/плюсна,
# копыто/лапа), таз и грудь (хребет гнётся на галопе и прыжках), два звена шеи, голова,
# челюсть, хвост. Порядок постановки ног — как на съёмках Майбриджа: шаг — латеральная
# последовательность ЛЗ, ЛП, ПЗ, ПП; рысь — диагональные пары; галоп — у кошек вращательный
# (ЛЗ, ПЗ, ПП, ЛП), у копытных поперечный (ЛЗ, ПЗ, ЛП, ПП); прыжки куньих и зайца — задние
# почти вместе, передние почти вместе. Опора — половина цикла: нога идёт назад; перенос —
# нога сгибается (запястье, скакательный сустав), копыто/лапа держится вдоль земли.

var _rig_t := 0.0
var _gait_offs := [0.5, 0.0, 0.75, 0.25]
var _lie_k := 0.0
var _feed_k := 0.0
var _alert_k := 0.0

static func _bx(skel: Skeleton3D, b: int, a: float) -> void:
	skel.set_bone_pose_rotation(b, Quaternion(Vector3.RIGHT, a))

static func _be(skel: Skeleton3D, b: int, e: Vector3) -> void:
	skel.set_bone_pose_rotation(b, Basis.from_euler(e).get_rotation_quaternion())

func _animate_rig(delta: float) -> void:
	_attack_t -= delta
	_rig_t += delta
	var d: Dictionary = parts["def"]
	if d.has("bird"):
		_animate_bird(delta)
		return
	var skel: Skeleton3D = parts["skel"]
	var sk: float = parts["sk"]
	var walk: float = sp["walk"]
	var run: float = sp["run"]
	var gait: String = sp["gait"]
	var r := clampf((speed - walk) / maxf(run - walk, 0.1), 0.0, 1.0)
	var mv := clampf(speed / (walk * 0.4), 0.0, 1.0)
	# доли фазы ног [ЛП, ПП, ЛЗ, ПЗ]: нога ставится, когда её фаза проходит −π/2
	var offs := [0.5, 0.0, 0.75, 0.25]
	if speed > walk * 1.5:
		var gal := [0.5, 0.6, 0.0, 0.9] if kind in ["lynx", "tiger"] else [0.6, 0.5, 0.0, 0.9]
		match gait:
			"trot":
				offs = [0.0, 0.5, 0.5, 0.0]
			"trotgallop", "gallop":
				offs = [0.0, 0.5, 0.5, 0.0] if r < (0.45 if gait == "trotgallop" else 0.2) else gal
			_:
				offs = [0.55, 0.45, 0.0, 0.95]
	var gk := minf(1.0, delta * 3.0)
	for i in 4:
		var dd := wrapf(float(offs[i]) - float(_gait_offs[i]), -0.5, 0.5)
		_gait_offs[i] = float(_gait_offs[i]) + dd * gk
	r_s = lerpf(r_s, r, minf(1.0, delta * 4.0))
	r = r_s
	var leg_h: float = float(d["H"]) * sk
	var stride := leg_h * lerpf(float(sp.get("swalk", 1.3)), float(sp.get("srun", 4.0)), r)
	phase += speed / maxf(stride, 0.05) * TAU * delta
	var amp := (0.28 + r * float(d.get("arun", 0.3))) * mv
	_lie_k = lerpf(_lie_k, 1.0 if state in ["rest", "sleep"] and speed < 0.1 else 0.0, minf(1.0, delta * 1.5))
	_feed_k = lerpf(_feed_k, 1.0 if state == "graze" and speed < 0.1 else 0.0, minf(1.0, delta * 2.5))
	_alert_k = lerpf(_alert_k, 1.0 if state == "alert" else 0.0, minf(1.0, delta * 4.0))
	var atk := 0.0
	if _attack_t > 0.0:
		atk = sin(clampf(_attack_t / 0.8, 0.0, 1.0) * PI)
	var pred: bool = kind in ["lynx", "wolverine", "tiger", "bear"]
	var rear: bool = kind == "moose"
	var lie := _lie_k
	var lie_f: Array = d.get("lie_f", [1.2, -2.5, 2.4])
	var lie_h: Array = d.get("lie_h", [-1.45, 2.6, -2.3])
	var legs: Array = d["legs"]
	var fsum := 0.0
	var hsum := 0.0
	for i in legs.size():
		var lg: Dictionary = legs[i]
		var bs: Array = lg["b"]
		var rel: Array = lg["rel"]
		var front: bool = lg["front"]
		var ph: float = phase + float(_gait_offs[i]) * TAU
		var s := sin(ph)
		var lift := maxf(0.0, -cos(ph))
		lift = lift * lift * (3.0 - 2.0 * lift) * mv
		var d0 := amp * s
		var d1 := 0.0
		var d2 := 0.0
		if front:
			d0 -= lift * (0.15 + r * 0.1)
			d1 -= lift * (0.35 + r * 0.3)
			d2 += lift * (1.1 + r * 0.5)
			fsum += s * mv
		else:
			d0 -= lift * (0.3 + r * 0.2)
			d1 += lift * (0.55 + r * 0.3)
			d2 -= lift * (0.7 + r * 0.3)
			hsum += s * mv
		var T: Array = lie_f if front else lie_h
		d0 = lerpf(d0, float(T[0]) - float(rel[0]), lie)
		d1 = lerpf(d1, float(T[1]) - float(rel[1]), lie)
		d2 = lerpf(d2, float(T[2]) - float(rel[2]), lie)
		# бросок хищника: передние вперёд, задние толкаются; лось — на дыбы, бьёт копытами;
		# кабарга и кабан — бьют передней ногой / поддевают
		if atk > 0.0:
			if pred or rear:
				if front:
					d0 -= atk * (1.0 if pred else 1.3)
					d1 += atk * (0.2 if pred else 1.1)
				else:
					d0 += atk * (0.6 if pred else 0.15)
			elif i == 0:
				d0 -= atk * 0.7
				d1 -= atk * 0.6
				d2 += atk * 1.2
		var sc := amp * s * (0.3 if front else 0.12) * (1.0 - lie)
		_bx(skel, bs[0], sc)
		_bx(skel, bs[1], d0 - sc)
		_bx(skel, bs[2], d1)
		_bx(skel, bs[3], d2)
		if bs.size() > 4:
			_bx(skel, bs[4], -(d0 + d1 + d2) * (1.0 - lie) + lift * (0.8 if front else -0.5))
	# туловище: подскок и качание по аллюру, изгиб хребта, наклон по склону, лёжка
	var L: float = parts["L"]
	var fwd := Vector3(sin(heading), 0, cos(heading))
	var hf: float = main.ground_at(position.x + fwd.x * L * 0.4, position.z + fwd.z * L * 0.4)
	var hb: float = main.ground_at(position.x - fwd.x * L * 0.4, position.z - fwd.z * L * 0.4)
	var slope := -atan2(hf - hb, L * 0.8) * (1.0 - swim_k)
	var H0: float = d["H"]
	var fast: bool = gait != "trot" and speed > walk * 1.5 and r > 0.2
	var bounce := 0.0
	var rock := 0.0
	var flex := 0.0
	if fast:
		bounce = maxf(0.0, sin(phase + 0.8)) * 0.07 * r
		rock = sin(phase + 0.6) * 0.08 * r
		flex = (hsum - fsum) * 0.5 * float(d.get("flex", 0.12)) * r
	else:
		bounce = absf(sin(phase)) * (0.012 + 0.03 * r)
	var dy := H0 * bounce * (1.0 - lie) - (H0 - float(d["lie_y"])) * lie
	var pitch := rock
	if atk > 0.0:
		pitch -= atk * (0.3 if pred else (0.55 if rear else -0.1))
		dy += atk * H0 * (0.12 if pred else 0.0)
		if rear:
			var gp: Array = d["gpos"]
			dy += sin(atk * 0.55) * 0.8 * absf((gp[d["pelvis"]] as Vector3).z - (gp[d["root"]] as Vector3).z)
	var root: int = d["root"]
	var rp: Vector3 = (d["gpos"] as Array)[root]
	skel.set_bone_pose_position(root, rp + Vector3(0, dy, 0))
	_be(skel, root, Vector3(pitch, 0, sin(phase) * 0.025 * mv * (1.0 - r)))
	_bx(skel, d["pelvis"], -flex)
	_bx(skel, d["chest"], flex * 0.6 + sin(_rig_t * 1.6) * 0.008 * (1.0 - mv))
	var m: Node3D = parts["model"]
	var tilt := slope
	if kind == "squirrel" and climb_h > 0.0:
		tilt = -1.45
	m.rotation.x = lerpf(m.rotation.x, tilt, minf(1.0, delta * 6.0))
	# шея и голова: кивок на шагу, вниз к корму, вверх настороже, вперёд на бегу
	var G: Array = d.get("graze", [1.1, 0.35])
	var nod := sin(phase * 2.0) * 0.06 * mv * (1.0 - r)
	var chew := sin(_rig_t * 3.0 + float(rng.seed % 7)) * 0.06 * _feed_k
	var nd := nod + float(G[0]) * _feed_k - 0.35 * _alert_k + 0.3 * r - 0.15 * lie + chew
	var hd := -nod * 0.5 + float(G[1]) * _feed_k + 0.15 * _alert_k - 0.2 * r
	var jaw := maxf(0.0, sin(_rig_t * 6.0)) * 0.12 * _feed_k
	if atk > 0.0:
		nd += atk * (0.25 if pred else (0.9 if rear else 0.5))
		hd += atk * (-0.35 if pred else 0.2)
		jaw += atk * (0.5 if pred else 0.0)
	var yaw := 0.0
	if _alert_k > 0.05 and main.hero != null:
		var to: Vector3 = main.hero.position - position
		yaw = clampf(wrapf(atan2(to.x, to.z) - heading, -PI, PI), -1.0, 1.0) * 0.6 * _alert_k
	else:
		yaw = sin(_rig_t * 0.4 + float(rng.seed % 5)) * 0.3 * lie
	_be(skel, d["neck1"], Vector3(nd * 0.6, yaw * 0.6, 0))
	_be(skel, d["neck2"], Vector3(nd * 0.4, yaw * 0.4, 0))
	_bx(skel, d["head"], hd)
	_bx(skel, d["jaw"], jaw)
	var tails: Array = d["tails"]
	var tl := -(0.3 * r if pred or kind == "wolverine" else 0.0) + sin(phase * 2.0) * 0.06 * mv
	var tw := sin(_rig_t * 2.2) * 0.15 * (1.0 - mv)
	for k in tails.size():
		_be(skel, tails[k], Vector3(tl * (1.0 if k == 0 else 0.4), tw * (0.6 + k * 0.3), 0))

## Глухарь: шаг с кивками головы, пробежка, взлёт и полёт с частыми взмахами и планированием,
## клюёт с земли, токует (хвост веером, шея вверх, крылья опущены), сидит.
func _animate_bird(delta: float) -> void:
	var d: Dictionary = parts["def"]
	var skel: Skeleton3D = parts["skel"]
	var sk: float = parts["sk"]
	var walk: float = sp["walk"]
	var fly := clampf(climb_h / 1.5, 0.0, 1.0)
	var r := clampf((speed - walk) / (float(sp["run"]) - walk), 0.0, 1.0)
	var mv := clampf(speed / (walk * 0.4), 0.0, 1.0) * (1.0 - fly)
	var stride := float(d["H"]) * sk * lerpf(float(sp["swalk"]), float(sp["srun"]) * 2.0, r)
	phase += speed / maxf(stride, 0.05) * TAU * delta * (1.0 - fly)
	_lie_k = lerpf(_lie_k, 1.0 if state in ["rest", "sleep"] and speed < 0.1 else 0.0, minf(1.0, delta * 1.5))
	_feed_k = lerpf(_feed_k, 1.0 if state == "graze" and speed < 0.1 and not _lekking() else 0.0, minf(1.0, delta * 3.0))
	_alert_k = lerpf(_alert_k, 1.0 if state == "alert" else 0.0, minf(1.0, delta * 4.0))
	var disp := 1.0 if (_attack_t > 0.0 or _lekking()) and fly < 0.1 else 0.0
	parts["disp"] = lerpf(float(parts.get("disp", 0.0)), disp, minf(1.0, delta * 3.0))
	var dk: float = parts["disp"]
	var lie := _lie_k
	var legs: Array = d["legs"]
	for i in legs.size():
		var bs: Array = (legs[i] as Dictionary)["b"]
		var ph: float = phase + float(i) * PI
		var s := sin(ph)
		var lift := maxf(0.0, -cos(ph))
		lift = lift * lift * (3.0 - 2.0 * lift) * mv
		var a0 := s * (0.45 + r * 0.3) * mv - lift * 0.4
		var a1 := lift * 0.9
		var a2 := -lift * 0.5
		# в полёте лапы поджаты назад; сидя — подогнуты
		a0 = lerpf(lerpf(a0, 1.1, fly), -0.6, lie)
		a1 = lerpf(lerpf(a1, 1.3, fly), 1.6, lie)
		a2 = lerpf(a2, -1.0, lie)
		_bx(skel, bs[0], a0)
		_bx(skel, bs[1], a1)
		_bx(skel, bs[2], a2)
		if bs.size() > 3:
			_bx(skel, bs[3], -(a0 + a1 + a2) * (1.0 - fly) + lift * 0.8 + fly * 1.0)
	var H0: float = d["H"]
	var bob := absf(sin(phase)) * 0.03 * mv
	var root: int = d["root"]
	var rp: Vector3 = (d["gpos"] as Array)[root]
	skel.set_bone_pose_position(root, rp + Vector3(0, H0 * bob - (H0 - float(d["lie_y"])) * lie, 0))
	parts["pitch"] = lerpf(float(parts.get("pitch", 0.0)), 0.25 * r * (1.0 - fly) + 0.15 * fly - 0.15 * dk + 0.3 * _feed_k, minf(1.0, delta * 6.0))
	_be(skel, root, Vector3(float(parts["pitch"]), 0, sin(phase) * 0.06 * mv))
	# голова «ходит» взад-вперёд на каждом шаге
	var pump := sin(phase * 2.0) * 0.18 * mv * (1.0 - r)
	var peck := maxf(0.0, sin(_rig_t * 5.0 + float(rng.seed % 9))) * 0.3 * _feed_k
	var nd := pump + (0.9 + peck) * _feed_k + 0.4 * r * (1.0 - fly) + 0.5 * fly - 0.3 * _alert_k - 0.4 * dk + 0.15 * lie
	var yaw := sin(_rig_t * 0.9 + float(rng.seed % 5)) * 0.35 * (1.0 - mv) * (1.0 - _feed_k)
	_be(skel, d["neck1"], Vector3(nd * 0.5, yaw * 0.5, 0))
	_be(skel, d["neck2"], Vector3(nd * 0.5, yaw * 0.5, 0))
	_bx(skel, d["head"], -pump * 0.8 + 0.5 * _feed_k - 0.3 * r - 0.5 * fly - 0.5 * dk)
	_bx(skel, d["jaw"], 0.25 * dk * maxf(0.0, sin(_rig_t * 7.0)))
	# хвост: сложен; на току — поднят и раскрыт веером; в полёте — раскрыт
	var t0: int = (d["tails"] as Array)[0]
	var spread := maxf(dk, fly * 0.7)
	_bx(skel, t0, lerpf(-0.1 * fly, 1.4, dk))
	skel.set_bone_pose_scale(t0, Vector3(lerpf(1.0, float(d["fan"]), spread), 1.0, 1.0))
	# крылья: сложены вдоль боков; в полёте раскрыты и машут; на току приспущены
	var flap := sin(_rig_t * 22.0)
	var glide := 1.0 if fmod(_rig_t, 2.4) < 1.5 else 0.15
	for w: Dictionary in (d["chains"] as Dictionary)["w"]:
		var sd: float = w["sd"]
		var b0: int = w["b"][0]
		var b1: int = w["b"][1]
		# плечо: разворот наружу (по Y), взмах (по Z); кисть: доворот
		var yw := -sd * lerpf(0.04 + 0.12 * dk, PI * 0.5, fly)
		var fl := lerpf(sd * 0.25 * dk, -sd * (flap * 0.8 * glide + 0.1), fly)
		# порядок: крен пера (сложено — вертикально, в полёте — горизонтально), разворот, взмах
		var q := Quaternion(Vector3.BACK, fl) * Quaternion(Vector3.UP, yw) * Quaternion(Vector3.BACK, sd * PI * 0.5 * fly)
		skel.set_bone_pose_rotation(b0, q)
		_be(skel, b1, Vector3(0.0, -sd * 0.15 * fly, -sd * flap * 0.3 * glide * fly))

## Токование: самец весной на рассвете (и в студии — по сигналу броска).
func _lekking() -> bool:
	if not male or state != "graze":
		return false
	var t: float = main.t_hours
	return t < 9.0 and main.weather != null and main.weather.season_index() == 2

## Бобр: вперевалку на суше, гребёт задними лапами в воде (над водой голова и спина),
## встаёт на хвост и грызёт ствол, бьёт хвостом по воде при тревоге.
func _animate_beaver(delta: float) -> void:
	var body: Node3D = parts["body"]
	var head: Node3D = parts["head"]
	var tail: Node3D = parts["tail"]
	var legs: Array = parts["legs"]
	var H: float = parts["H"]
	var t := Time.get_ticks_msec() * 0.001 + float(rng.seed % 100)
	var sw := swim_k
	var mv := clampf(speed * 4.0, 0.0, 1.0)
	phase += speed * lerpf(26.0, 11.0, sw) / scale_k * delta
	gnaw_k = move_toward(gnaw_k, 1.0 if state == "gnaw" else 0.0, delta * 3.0)
	var gk := smoothstep(0.0, 1.0, gnaw_k)
	var up := gk * (0.0 if gnaw_low else 1.0)
	var low := gk * (1.0 if gnaw_low else 0.0)
	# корпус: на суше — покачивание с боку на бок; вплавь — нос чуть вверх
	var roll := sin(phase) * 0.11 * mv * (1.0 - sw)
	var pitch := -0.35 * sw + sin(phase) * 0.03 * mv * sw
	var bob := absf(sin(phase)) * 0.012 * mv * (1.0 - sw) + sin(t * 1.7) * 0.004
	body.position.y = H + bob + up * 0.15 * scale_k
	body.rotation = Vector3(lerpf(pitch, -0.75, up) + low * 0.3, sin(phase) * 0.06 * mv * (1.0 - sw), roll * (1.0 - gk))
	# хлопок хвостом: поднять — шлёпнуть
	var slap := 0.0
	if slap_t > 0.0:
		var u := 1.0 - slap_t / 0.7
		var was := slap_t
		slap_t -= delta
		slap = 1.6 * smoothstep(0.0, 0.5, u) * (1.0 - smoothstep(0.55, 0.68, u)) - 0.35 * smoothstep(0.55, 0.68, u) * (1.0 - smoothstep(0.8, 1.0, u))
		if was > 0.7 * 0.38 and slap_t <= 0.7 * 0.38 and main != null and main.sfx != null:
			main.sfx.play_at("slap", position, 6.0, rng.randf_range(0.9, 1.1))
		# зад поднимается над водой, хвост — вверх, затем нырок носом вниз
		body.rotation.x += 0.7 * smoothstep(0.0, 0.3, u) * (1.0 - smoothstep(0.85, 1.0, u)) + 0.3 * smoothstep(0.6, 0.9, u)
	# хвост: на суше волочится, в воде — руль и лёгкие взмахи, при грызении — опора
	tail.rotation.x = lerpf(-0.3 + sin(phase) * 0.04 * mv, sin(phase) * 0.2, sw) * (1.0 - up) + up * 0.78 - low * 0.3 + slap
	tail.rotation.y = lerpf(-sin(phase) * 0.18 * mv, sin(t * 1.3) * 0.12, sw) * (1.0 - gk)
	# лапы: на суше диагональная походка; вплавь — передние прижаты, задние гребут вместе
	for i in 4:
		var lg: Dictionary = legs[i]
		var hip: Node3D = lg["hip"]
		var front: bool = lg["front"]
		var off: float = [0.0, 0.5, 0.5, 0.0][i]
		var land := sin(phase + off * TAU) * 0.6 * mv
		var swim := (1.0 if front else 0.6 + sin(phase) * 0.7)
		var a := lerpf(land, swim, sw)
		if front:
			a = lerpf(a, -1.25, up)
			a = lerpf(a, -0.25 + sin(t * 9.0) * 0.1, low)
		else:
			a = lerpf(a, 0.75, up)
			a = lerpf(a, -0.3, low)
		hip.rotation.x = a
	# голова: грызёт — частые движения челюстью и наклоны набок
	var chew := sin(t * 23.0) * 0.07
	var look := sin(t * 0.5) * 0.25 * (1.0 - mv) * (1.0 - gk)
	head.rotation = Vector3(sin(phase * 2.0) * 0.03 * mv + (0.55 + chew) * up + (0.35 + chew) * low - 0.08 * sw,
		look + sin(t * 0.9) * 0.3 * gk, sin(t * 0.7) * 0.35 * gk)
