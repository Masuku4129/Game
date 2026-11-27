extends Node3D
const RP := preload("res://scripts/river_path.gd")
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
const HUNTS := {"lynx": ["hare", "capercaillie", "muskdeer", "roe"], "wolverine": ["hare", "capercaillie", "muskdeer", "beaver"],
	"fox": ["hare", "squirrel", "capercaillie"]}
const CHARGE := {"bear": 9.0, "boar": 6.0, "moose": 5.0, "wolverine": 3.5}
# крупная добыча: волков/тигра (виды и сколько укусов выдерживает взрослый)
const BIG_PREY := {"wolf": ["roe", "deer", "moose", "muskdeer", "boar"], "tiger": ["boar", "deer", "moose", "roe"]}
const TOUGH := {"moose": 5, "deer": 3, "boar": 3, "roe": 2}
# скорость вплавь (м/с): копытные ~1, хищники ~0,8, мелкие ~0,5; бобр — отдельно (2–2,5)
const SWIM_V := {"moose": 1.2, "deer": 1.1, "roe": 1.0, "muskdeer": 0.9, "boar": 0.8, "wolf": 0.8, "bear": 0.8, "tiger": 1.0, "lynx": 0.7, "wolverine": 0.6, "fox": 0.6}
# у туши: кто кого отгоняет; падальщики — кто ищет туши
const RANK := {"tiger": 5.0, "bear": 4.0, "wolf": 3.0, "wolverine": 2.5, "lynx": 2.0, "fox": 1.0}
const SCAVENGE := {"bear": 110.0, "wolverine": 90.0, "fox": 60.0, "wolf": 70.0, "tiger": 60.0, "lynx": 30.0}
const DRINKERS := ["roe", "deer", "moose", "boar", "wolf", "bear", "fox", "lynx", "tiger", "wolverine"]
const HERD := ["roe", "deer", "moose", "boar", "muskdeer"]
# выносливость на бегу (с): кошки — короткий рывок, волк — долгая погоня
const ENDURE := {"lynx": 6.0, "tiger": 8.0, "fox": 10.0, "wolf": 45.0, "bear": 14.0}
# --- hunt: на сколько метров хищник чует свежую кровь силы 1 (animals.scent_near) ---
const SMELL := {"wolf": 70.0, "bear": 90.0, "tiger": 60.0, "wolverine": 70.0, "fox": 45.0, "lynx": 30.0}

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
var _acc := randf() * 0.05  # perf: сдвиг шага между зверями
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
# бобр: подводный вход в хатку (door — у основания со стороны русла); lodge_ok — может уйти в хатку
var door := Vector3.INF
var lodge_ok := true
# взаимодействия: усталость на бегу, укусы до гибели, мясо туши, корм, сытость, водопой, рыбалка
var tire := 0.0
var hp_left := 1
var meat := 0.0
var food: Node3D = null
var sated := 0.0
var drink_slot := -1
var cross := false
var face := Vector3.INF
var fish_cd := 0.0
var fish_n: Node3D = null
var fish_got := 0
var slot_a := 0.0
var _scan_t := 0.0

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
	hp_left = int(TOUGH.get(k, 1)) if sc > 0.75 else 1
	slot_a = rng.randf() * TAU
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
	# стадо держится вместе: не вожак — пасётся рядом с вожаком
	if mgr != null and group >= 0 and kind in HERD:
		var ld: Node3D = mgr.group_leader(group)
		if ld != null and ld != self and ld.position.distance_to(position) < 70.0:
			var a2 := rng.randf() * TAU
			target = ld.position + Vector3(cos(a2), 0, sin(a2)) * rng.randf_range(2.5, 8.0)
	# цель на другом ярусе уступа или в воде (воду обходят все, кроме бобра) — ближе к дому
	var th: float = main.height(target.x, target.z)
	if absf(th - main.height(position.x, position.z)) > 4.0 or (th < main.WATER_Y - 0.3 and kind != "beaver"):
		target = home + Vector3(rng.randf_range(-8, 8), 0, rng.randf_range(-8, 8))
	# на тот берег — редко и только вплавь (переправа); иначе цель зеркалится на свой берег
	cross = false
	if mgr != null and kind != "beaver" and _bank_side(target) != _bank_side(position) and main.river_dist(position.x, position.z) < 45.0:
		if swimmer() and rng.randf() < 0.3:
			cross = true
		else:
			var zc := _river_zc(target.x)
			target.z = zc + (zc - target.z)
	state = "wander"
	state_t = rng.randf_range(8.0, 20.0)

static func _river_zc(x: float) -> float:
	return RP.zc(x)

func _bank_side(p: Vector3) -> float:
	return signf(p.z - _river_zc(p.x))

## Точка у кромки воды на своём берегу (напротив x), или INF.
func _bank_spot(x: float, side: float) -> Vector3:
	var zc := _river_zc(x)
	var d := 30.0
	var last := Vector3.INF
	while d > 4.0:
		var z := zc + side * d
		var hh: float = main.height(x, z)
		if hh < main.water_level(x, z) + 0.05:
			return last
		if not main.blocked(x, z, 0.4):
			last = Vector3(x, hh, z)
		d -= 0.7
	return last

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
	# --- combat: присевшего замечают позже ---
	if hero.get("crouch") == true:
		sense *= 0.55
	# --- /combat ---
	# build: в снежной пещере человека не видно и не слышно
	if main.get("camp") != null and main.camp.hidden:
		sense *= 0.15
	# дозорный в стаде смотрит дальше
	if state == "watch":
		sense *= 1.4
	var hero_alive: bool = main.health > 0.0
	# смена шубки: заяц белеет, белка сереет
	if kind in ["hare", "squirrel"] and not far:
		var wint: bool = w.season_index() == 1 or float(w.snow) > 0.4
		if wint != winter_skin:
			_build(wint)
	# спячка медведя: зимой его нет
	if kind == "bear" and w.season_index() == 1:
		_drop_fish()
		visible = false
		state = "sleep"
		return
	# в воде без нужды (не бегство, не погоня, не переправа) — к своему берегу
	if swim_k > 0.5 and kind != "beaver" and not cross and state in ["wander", "graze", "rest", "watch", "alert", "to_drink", "drink", "feed", "wait", "retreat", "ambush"]:
		var bs := _bank_spot(position.x, _bank_side(position))
		if bs != Vector3.INF:
			target = bs
			state = "wander"
			cross = true
			state_t = 40.0
			return
	match state:
		"sleep":
			if not (kind == "bear" and w.season_index() == 1):
				visible = true
				_new_wander()
		"inlodge":
			# бобр в хатке: выходит, когда отдохнул (днём — реже)
			if state_t <= 0.0 and dh > 8.0 and (is_active() or not lodge_ok or rng.randf() < 0.2):
				_emerge()
		"wander", "graze", "rest", "alert", "job", "gnaw", "watch", "investigate":
			# хищник: охота на добычу или на человека (сытый не охотится)
			if (kind in ["wolf", "tiger"] or HUNTS.has(kind)) and sated <= 0.0 and (state != "rest" or rng.randf() < 0.05):
				_hunt_choice(dh, sense, hero_alive)
				if state == "stalk" or state == "chase" or state == "ambush":
					return
			if CHARGE.has(kind) and hero_alive and dh < float(CHARGE[kind]):
				state = "charge"
				state_t = 6.0
				return
			var busy := state == "job" or state == "gnaw"
			if _danger(dh, sense, hero_alive, busy):
				return
			# падальщики чуют тушу издалека
			if SCAVENGE.has(kind) and sated <= 0.0 and not busy and rng.randf() < 0.12:
				var cc: Node3D = mgr.carcass_near(position, float(SCAVENGE[kind]))
				if cc != null:
					food = cc
					state = "feed"
					state_t = rng.randf_range(40.0, 90.0)
					return
			# --- hunt: хищник учуял свежую кровь — идёт проверить ---
			if SMELL.has(kind) and sated <= 0.0 and not busy and state != "investigate" and rng.randf() < 0.1:
				var bp: Vector3 = mgr.scent_near(position, float(SMELL[kind]))
				if bp != Vector3.INF and bp.distance_to(position) > 3.0:
					target = bp + Vector3(rng.randf_range(-2.0, 2.0), 0, rng.randf_range(-2.0, 2.0))
					state = "investigate"
					state_t = 90.0
					return
			# --- /hunt ---
			if state_t <= 0.0 and not busy:
				_idle_choice()
		"ambush":
			# рысь в засаде: ждёт, пока добыча подойдёт на бросок
			if _danger(dh, sense * 0.6, hero_alive, false):
				return
			var ap = mgr.nearest_of(self, HUNTS[kind], 13.0)
			if ap != null:
				prey = ap
				state = "chase"
				state_t = 6.0
			elif state_t <= 0.0:
				_new_wander()
		"flee":
			if state_t <= 0.0 and (threat == null or position.distance_to(threat.position) > _sense() * 1.3):
				threat = null
				_new_wander()
		"stalk", "chase":
			_update_hunt(dh, hero_alive)
		"feed", "wait":
			_think_feed(dh, hero_alive)
		"to_drink", "drink":
			if _danger(dh, sense, hero_alive, false):
				return
			if CHARGE.has(kind) and hero_alive and dh < float(CHARGE[kind]):
				state = "charge"
				state_t = 6.0
		"to_fish", "fish", "fish_bank", "eat":
			if hero_alive and dh < float(CHARGE.get(kind, 0.0)):
				_drop_fish()
				state = "charge"
				state_t = 6.0
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
			if state_t <= 0.0 and dh > 12.0 and (mgr == null or mgr.nearest_predator(self, 20.0) == null):
				state = "down_tree"

## Опасность: хищник рядом или человек близко — бегство (белка — на дерево, бобр — в хатку).
func _danger(dh: float, sense: float, hero_alive: bool, busy: bool) -> bool:
	var pred: Node3D = mgr.nearest_predator(self, 30.0)
	if pred != null:
		_flee_from(pred, 6.0)
		return true
	if dh < sense and not (kind in ["bear", "wolf", "tiger"] and hero_alive) and (not busy or dh < sense * 0.55):
		if dh < sense * 0.55 or state == "alert":
			_flee_from(main.hero, rng.randf_range(4.0, 7.0))
			return true
		state = "alert"
		state_t = 2.0
		return true
	return false

func _flee_from(t: Node3D, tm: float) -> void:
	_drop_fish()
	food = null
	threat = t
	state = "flee"
	state_t = tm
	if kind == "squirrel":
		var tp: Vector3 = main.nearest_tree(position, 15.0)
		if tp != Vector3.INF:
			tree = tp
			state = "to_tree"

## Чем заняться: спать/отдыхать, водопой на заре и закате, рыбалка, дозор, пастьба, бродить.
func _idle_choice() -> void:
	var t: float = main.t_hours
	if kind == "beaver" and door != Vector3.INF and lodge_ok and (not is_active() or rng.randf() < 0.15):
		state = "to_lodge"
		state_t = 40.0
		return
	if not is_active():
		state = "rest"
		state_t = rng.randf_range(20.0, 60.0)
		return
	# водопой: на рассвете и в сумерках, раз за зарю; стадо идёт за вожаком
	var slot: int = int(main.day_count) * 2 + (0 if t < 12.0 else 1)
	var dawn := (t > 4.5 and t < 8.5) or (t > 17.5 and t < 21.5)
	if dawn and kind in DRINKERS and drink_slot != slot and main.river_dist(position.x, position.z) < 140.0:
		var ld: Node3D = mgr.group_leader(group) if group >= 0 else null
		if ld == null or ld == self:
			var sp2 := _bank_spot(position.x + rng.randf_range(-6.0, 6.0), _bank_side(position))
			if sp2 != Vector3.INF:
				_go_drink(sp2, slot)
				if group >= 0:
					mgr.group_drink(self, sp2, slot)
				return
	# медведь: летом и осенью — на перекат за рыбой
	if kind == "bear" and sated <= 0.0 and rng.randf() < 0.35 and mgr.fish != null:
		var fs: Vector3 = mgr.fish.spot_near(position, 150.0)
		if fs != Vector3.INF:
			target = fs
			state = "to_fish"
			state_t = 90.0
			fish_got = 0
			return
	# рысь: засада у тропы
	if kind == "lynx" and sated <= 0.0 and rng.randf() < 0.4:
		state = "ambush"
		state_t = rng.randf_range(30.0, 70.0)
		return
	# стадо: один стоит дозорным, пока другие пасутся
	if kind in HERD and group >= 0 and rng.randf() < 0.5 and not mgr.group_has(group, "watch"):
		state = "watch"
		state_t = rng.randf_range(6.0, 14.0)
		return
	if rng.randf() < (0.5 if kind in ["roe", "deer", "hare", "boar", "beaver", "moose", "muskdeer", "capercaillie"] else 0.2):
		state = "graze"
		state_t = rng.randf_range(6.0, 16.0)
	else:
		_new_wander()

func _go_drink(p: Vector3, slot: int) -> void:
	target = p
	drink_slot = slot
	state = "to_drink"
	state_t = 60.0

func _hunt_choice(dh: float, sense: float, hero_alive: bool) -> void:
	var w = main.weather
	var hungry_night: bool = not float(main.day_factor) > 0.5 or w.season_index() == 1
	if HUNTS.has(kind):
		# рысь, росомаха, лиса: мелкая добыча, на человека не охотятся
		var hp = mgr.nearest_of(self, HUNTS[kind], 35.0)
		if hp != null and (hp.kind != "roe" or hp.scale_k < 0.95) and rng.randf() < 0.5:
			prey = hp
			state = "stalk"
			state_t = 20.0
		return
	# волки и тигр: на человека — ночью или зимой; иначе на копытных (слабых — охотнее)
	if hero_alive and dh < sense and (hungry_night or kind == "tiger" or float(main.bleed) > 0.05):  # hunt: кровь героя
		prey = main.hero
		state = "stalk"
		state_t = 25.0
		if kind == "wolf":
			mgr.pack_hunt(self, main.hero)
		return
	var p = mgr.nearest_of(self, BIG_PREY[kind], 60.0)
	if p != null and rng.randf() < (0.15 if p.scale_k > 0.8 and p.kind == "moose" else 0.3):
		prey = p
		state = "stalk"
		state_t = 30.0
		if kind == "wolf":
			mgr.pack_hunt(self, p)

func _update_hunt(dh: float, hero_alive: bool) -> void:
	if prey != null and prey != main.hero and prey.dead:
		# добыча убита (своим или стаей) — к туше
		if prey.meat > 0.0 and position.distance_to(prey.position) < 40.0:
			food = prey
			prey = null
			state = "feed"
			state_t = rng.randf_range(40.0, 80.0)
			return
	if prey == null or (prey != main.hero and (prey.dead or prey.state == "inlodge" or prey.climb_h > 1.0)) or (prey == main.hero and not hero_alive):
		prey = null
		_new_wander()
		return
	var d := position.distance_to(prey.position)
	# кошки бросаются коротко: выдохлись — отстают
	if state_t <= 0.0 or d > 90.0 or (state == "chase" and tire > 0.9 and kind in ["lynx", "tiger", "fox"]):
		var was_hero: bool = prey == main.hero
		prey = null
		if was_hero:
			state = "retreat"
			state_t = 6.0
		else:
			_new_wander()
		return
	if state == "stalk" and d < (9.0 if kind in ["tiger", "lynx"] else 14.0):
		state = "chase"
		state_t = 25.0 if kind == "wolf" else 12.0
		if kind == "wolf":
			mgr.pack_chase(self, prey)

## У туши: ест, пока не сыт; сильный отгоняет слабого (медведь — волков, волки — лису и росомаху).
func _think_feed(dh: float, hero_alive: bool) -> void:
	if food == null or not food.dead or food.meat <= 0.0:
		food = null
		sated = 240.0
		_new_wander()
		return
	# медведь защищает тушу от человека
	if kind == "bear" and hero_alive and dh < 16.0:
		state = "charge"
		state_t = 6.0
		return
	if dh < _sense() * 0.4 and not (kind in ["bear", "wolf", "tiger"] and hero_alive):
		_flee_from(main.hero, 5.0)
		return
	var pred: Node3D = mgr.nearest_predator(self, 20.0)
	if pred != null and pred.state != "feed":
		_flee_from(pred, 6.0)
		return
	var rival: Node3D = mgr.rival_at(food, self)
	if state == "feed":
		if rival != null:
			state = "wait"
			state_t = rng.randf_range(15.0, 35.0)
		elif state_t <= 0.0:
			food = null
			sated = 300.0
			_new_wander()
	elif rival == null:
		state = "feed"
		state_t = rng.randf_range(20.0, 50.0)
	elif state_t <= 0.0:
		food = null
		_new_wander()

## Бобр уходит в хатку: нырок у основания и подводный лаз.
func _hide_in_lodge() -> void:
	state = "inlodge"
	state_t = rng.randf_range(40.0, 120.0) if not is_active() else rng.randf_range(12.0, 40.0)
	visible = false
	position = home
	speed = 0.0
	threat = null

func _emerge() -> void:
	position = Vector3(door.x, main.water_level(door.x, door.z) - 0.6, door.z)
	dive_k = 1.0
	visible = true
	heading = atan2(door.x - home.x, door.z - home.z)
	_new_wander()

## Рыба в пасти медведя — бросить (испуган, ушёл в спячку).
func _drop_fish() -> void:
	if fish_n != null:
		fish_n.queue_free()
		fish_n = null

## Кадр: движение, высота, поворот, анимация.
func tick(delta: float) -> void:
	if dead:
		if float(main.t_hours) + float(main.day_count) * 24.0 > respawn_at:
			_revive()
		return
	state_t -= delta
	attack_cd -= delta
	think_t -= delta
	sated -= delta
	if think_t <= 0.0:
		think_t = 0.2 + rng.randf() * 0.1
		var was := state
		think()
		if state == "flee" and was != "flee" and threat != null:
			mgr.alarm(self, threat)
			# бобр в воде бьёт хвостом по воде и уходит под воду
			if kind == "beaver" and swim_k > 0.5 and slap_t <= 0.0:
				slap_t = 0.7
	if state == "sleep" or state == "inlodge":
		return
	if state == "gnaw" and job_face != Vector3.ZERO:
		heading = lerp_angle(heading, atan2(job_face.x - position.x, job_face.z - position.z), minf(1.0, delta * 5.0))
	var walk: float = sp["walk"]
	# усталость: долгий бег на пределе замедляет (волки догоняют выдохшихся, кошки — только рывком)
	if speed > walk * 2.5:
		tire = minf(1.0, tire + delta / float(ENDURE.get(kind, 14.0)))
	else:
		tire = maxf(0.0, tire - delta / 25.0)
	var run: float = sp["run"] * (1.0 if scale_k > 0.6 else 0.7) * (1.0 - 0.35 * tire)
	var goal := target
	want = 0.0
	face = Vector3.INF
	match state:
		"wander":
			want = walk
			if Vector2(goal.x - position.x, goal.z - position.z).length() < 1.0:
				state_t = 0.0
				want = 0.0
		"graze", "rest", "alert", "tree", "gnaw", "watch", "ambush":
			want = 0.0
		# --- hunt: идёт на запах крови, на месте — принюхивается ---
		"investigate":
			want = walk * 1.6
			if Vector2(goal.x - position.x, goal.z - position.z).length() < 1.5:
				want = 0.0
				state_t = minf(state_t, 6.0)
		# --- /hunt ---
		"job":
			goal = job_p
			want = walk * (1.5 if swim_k > 0.5 else 1.0)
			var dj := Vector2(job_p.x - position.x, job_p.z - position.z).length()
			if dj < maxf(0.35, walk * 2.0 * delta):
				arrived = true
				want = 0.0
		"flee":
			if kind == "beaver":
				# бобр уходит к хатке и ныряет в лаз
				goal = door if door != Vector3.INF else home
				if Vector2(goal.x - position.x, goal.z - position.z).length() < 1.3:
					state = "dive_in"
					state_t = 1.2
			elif threat != null:
				var away := (position - threat.position)
				away.y = 0
				goal = position + away.normalized() * 10.0
				# заяц петляет
				if kind == "hare":
					goal += Vector3(sin(Time.get_ticks_msec() * 0.004), 0, cos(Time.get_ticks_msec() * 0.003)) * 4.0
			want = run
		"to_lodge":
			goal = door if door != Vector3.INF else home
			want = walk
			if Vector2(goal.x - position.x, goal.z - position.z).length() < 1.3:
				state = "dive_in"
				state_t = 1.2
			elif state_t <= 0.0:
				_new_wander()
		"dive_in":
			goal = home
			want = walk * 0.8
			if state_t <= 0.0:
				_hide_in_lodge()
				return
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
		"feed":
			if food != null:
				var fp := food.position
				var reach: float = float(food.parts.get("L", 1.0)) * 0.4 + float(parts["L"]) * 0.45
				goal = fp + Vector3(cos(slot_a), 0, sin(slot_a)) * reach
				var df := Vector2(goal.x - position.x, goal.z - position.z).length()
				if df > 0.45:
					want = walk * (2.2 if df > 12.0 else 1.0)
				else:
					face = fp
					food.meat -= delta
		"wait":
			if food != null:
				var fp2 := food.position
				var aw := Vector3(position.x - fp2.x, 0, position.z - fp2.z)
				goal = fp2 + aw.normalized() * 14.0
				if Vector2(goal.x - position.x, goal.z - position.z).length() > 1.5:
					want = walk
				else:
					face = fp2
		"to_drink", "to_fish", "fish_bank":
			want = walk * (1.2 if state == "to_fish" else 1.0)
			if Vector2(goal.x - position.x, goal.z - position.z).length() < 0.8:
				want = 0.0
				match state:
					"to_drink":
						state = "drink"
						state_t = rng.randf_range(10.0, 22.0)
					"to_fish":
						state = "fish"
						state_t = rng.randf_range(40.0, 90.0)
						fish_cd = rng.randf_range(2.0, 5.0)
					_:
						_eat_fish()
			elif state_t <= 0.0:
				if state == "fish_bank":
					_eat_fish()
				else:
					_new_wander()
		"drink", "fish", "eat":
			if state != "eat":
				face = Vector3(position.x, position.y, _river_zc(position.x))
			if state == "fish":
				fish_cd -= delta
				if fish_cd <= 0.0:
					_swipe()
			if state_t <= 0.0:
				if state == "eat":
					_drop_fish()
					fish_got += 1
					if fish_got < 3 and rng.randf() < 0.7:
						state = "to_fish"
						target = mgr.fish.spot_near(position, 40.0)
						state_t = 60.0
						if target == Vector3.INF:
							_new_wander()
					else:
						sated = 400.0
						_new_wander()
				else:
					_new_wander()
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
	if face != Vector3.INF and want <= 0.0:
		heading = lerp_angle(heading, atan2(face.x - position.x, face.z - position.z), minf(1.0, delta * 4.0))
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
		var wet_below: bool = main.grid_height(position.x, position.z) < main.WATER_Y - 0.2
		var up: bool = (state == "flee" and speed > sp["walk"] * 4.0) or wet_below
		climb_h = move_toward(climb_h, 4.5 if up else 0.0, delta * (3.0 if up else 1.6))
	# вплавь: бобр быстр и вёрток (до 2,5 м/с); остальные плывут медленно (0,5–1,2 м/с)
	var agile := 1.0
	if kind == "beaver":
		if swim_k > 0.5 and want > 0.0:
			var bw: float = {"job": 1.8, "flee": 2.4, "to_lodge": 1.6, "dive_in": 1.2}.get(state, 1.0)
			want = bw
			agile = 2.5
	elif swim_k > 0.05:
		var sv: float = float(SWIM_V.get(kind, 0.5)) * (0.75 + 0.25 * minf(scale_k, 1.0))
		want = minf(want, lerpf(want, sv, clampf(swim_k * 1.5, 0.0, 1.0)))
	# поворот к цели и разгон
	var to := goal - position
	to.y = 0
	if to.length() > 0.2 and want > 0.0:
		var hd := atan2(to.x, to.z)
		heading = lerp_angle(heading, hd, minf(1.0, delta * (3.0 + want * 0.4) * agile))
	speed = move_toward(speed, want, delta * (4.0 + want * 0.8))
	var flying: bool = kind == "capercaillie" and climb_h > 0.5
	if (climb_h <= 0.0 or kind == "capercaillie") and speed > 0.01:
		var dir := Vector3(sin(heading), 0, cos(heading))
		var np := position + dir * speed * delta
		# обход стволов и воды; мелкие воду обходят всегда, крупные плывут только
		# спасаясь, в погоне или на переправе; отвесный уступ не одолеть
		var desired := atan2(to.x, to.z)
		var chosen := heading
		var best_score := -INF
		var step_len := maxf(0.18, speed * delta)
		# Try the direct path first, then progressively wider arcs. This avoids
		# the old fixed-angle bounce that trapped animals against the same blocker.
		var offsets := [0.0, 0.38, -0.38, 0.78, -0.78, 1.25, -1.25, 1.85, -1.85, PI]
		var found := false
		for off in offsets:
			var candidate: float = lerp_angle(heading, desired, 0.35) + float(off)
			var cd := Vector3(sin(candidate), 0.0, cos(candidate))
			var probe: Vector3 = position + cd * step_len
			# Sample the full movement segment; mid-distance ticks may be long enough
			# to otherwise cross narrow obstacles when only the endpoint is checked.
			if not _can_move_segment(position, probe, flying):
				continue
			var align := cd.dot(to.normalized())
			var turn_cost := absf(wrapf(candidate - heading, -PI, PI)) * 0.08
			var score := align - turn_cost
			if score > best_score:
				best_score = score
				chosen = candidate
				found = true
		if found:
			heading = lerp_angle(heading, chosen, minf(1.0, delta * 7.0))
			var move_dir := Vector3(sin(heading), 0.0, cos(heading))
			var np2 := position + move_dir * step_len
			if _can_move_segment(position, np2, flying):
				position.x = np2.x
				position.z = np2.z
				_bump = maxi(0, _bump - 1)
		else:
			speed *= 0.35
			_bump += 1
	_unstick(delta)
	# бобр у хатки ныряет под неё (купол хатки — опора только для человека)
	var g: float = main.grid_height(position.x, position.z) if state == "dive_in" else main.ground_fast(position.x, position.z)
	var wl: float = main.water_level(position.x, position.z)
	swim_k = clampf((wl - 0.25 - g) / 0.6, 0.0, 1.0) if swimmer() else 0.0
	if kind == "beaver":
		# плывёт: над водой только голова и спина; испуганный ныряет у хатки
		var hide := (state == "flee" and slap_t <= 0.0 and swim_k > 0.8) or state == "dive_in"
		dive_k = move_toward(dive_k, 1.0 if hide else 0.0, delta * (2.0 if hide else 0.8))
		g = lerpf(g, wl - 0.32 * scale_k - dive_k * 0.5, swim_k)
	elif swim_k > 0.0:
		# плывёт: тело под водой, над водой голова и верх спины
		g = lerpf(g, wl - float(parts.get("H", 0.8)) * (1.0 if parts.has("rig") else 0.8), swim_k)
	position.y = g + climb_h
	# на снегу: лёгкие бегут поверху, тяжёлые проваливаются; в снегу и грязи — следы
	if climb_h <= 0.0 and swim_k <= 0.0 and main.feet != null and g < main.grid_height(position.x, position.z) + 0.1:
		position.y += main.feet.animal_step(self, speed * delta)
	rotation.y = heading
	# perf: невидимых не анимируем
	if not far and visible:
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
## Проверка короткого шага: коллизии, вода, границы карты и непроходимый подъём.
func _obstacle_radius() -> float:
	# Approximate animal footprint by body length; prevents large species from
	# squeezing through visually impassable gaps while keeping small animals agile.
	return clampf(float(parts.get("L", 0.5)) * 0.18, 0.18, 0.75)

func _can_move_segment(from: Vector3, to: Vector3, flying: bool = false) -> bool:
	var distance := Vector2(to.x - from.x, to.z - from.z).length()
	var steps := maxi(1, ceili(distance / 0.6))
	for i in range(1, steps + 1):
		var sample := from.lerp(to, float(i) / float(steps))
		if not _can_step(sample, flying):
			return false
	return true

func _can_step(p: Vector3, flying: bool = false) -> bool:
	if absf(p.x) > main.SIZE * 0.5 - 10.0 or absf(p.z) > main.SIZE * 0.5 - 10.0:
		return false
	if main.blocked(p.x, p.z, _obstacle_radius()):
		return false
	var gy: float = main.grid_height(p.x, p.z)
	# купол камня, бревно или пень выше полуметра — зверь не взбирается, а обходит
	if not flying and main.solid_top(p.x, p.z) - gy > 0.45:
		return false
	var g0: float = main.grid_height(position.x, position.z)
	if gy < main.WATER_Y - 0.3 and not swimmer() and not flying:
		return false
	if swimmer() and kind != "beaver" and not flying and swim_k < 0.2 and not cross and not (state in ["flee", "chase", "charge"]):
		if main.water_level(p.x, p.z) - gy > 0.6:
			return false
	if (gy - g0) > 0.35 and gy > main.WATER_Y and not flying:
		return false
	return true


## Зверь оказался внутри ствола или камня (родился, построили рядом) — вытолкнуть к ближайшему свободному месту.
func _push_out() -> void:
	if not main.blocked(position.x, position.z, _obstacle_radius()) and main.solid_top(position.x, position.z) - main.grid_height(position.x, position.z) <= 0.45:
		return
	# Search wider and more densely so animals can escape tree/rock gaps.
	for r in [0.5, 0.9, 1.3, 1.8, 2.4, 3.2, 4.2, 5.4]:
		for k in 24:
			var a := TAU * float(k) / 24.0 + float(r) * 0.31
			var q: Vector3 = position + Vector3(sin(a), 0.0, cos(a)) * float(r)
			if _can_step(q):
				position.x = q.x
				position.z = q.z
				return

func _unstick(delta: float) -> void:
	_chk_t += delta
	if _chk_t < 1.2:
		return
	_push_out()
	var moved := Vector2(position.x - _chk_p.x, position.z - _chk_p.z).length()
	var tried := want > 0.3
	_chk_t = 0.0
	_chk_p = position
	if not tried or moved > 0.5:
		_bump = 0
		return
	_turn_dir = -_turn_dir
	var back := heading + PI + rng.randf_range(-0.8, 0.8)
	heading = back
	if state in ["to_drink", "to_fish", "fish_bank", "to_lodge", "feed", "wait"]:
		# путь к цели не находится — бросить затею
		if _bump > 12:
			_drop_fish()
			food = null
			_new_wander()
	else:
		target = position + Vector3(sin(back), 0, cos(back)) * rng.randf_range(8.0, 18.0)
	if state == "wander":
		state_t = rng.randf_range(6.0, 12.0)
	if _bump > 40:
		# Never teleport wildlife: abandon the unreachable destination and
		# choose a nearby point on valid ground, preserving the current position.
		_bump = 0
		var escape := heading + rng.randf_range(-PI * 0.75, PI * 0.75)
		var recovered := false
		for radius in [4.0, 7.0, 11.0, 16.0]:
			for turn in range(8):
				var ang := escape + TAU * float(turn) / 8.0
				var probe: Vector3 = position + Vector3(sin(ang), 0.0, cos(ang)) * float(radius)
				if _can_step(probe):
					target = probe
					recovered = true
					break
			if recovered:
				break
		if not recovered:
			state_t = 0.0
			want = 0.0

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
		tg.bitten(self)
		if tg.dead:
			# добыча повалена — есть тут же; стая подтянется (_update_hunt)
			food = tg
			prey = null
			state = "feed"
			state_t = rng.randf_range(40.0, 80.0)

## Укус хищника: крупного зверя валят не с первого раза.
func bitten(by: Node3D) -> void:
	hp_left -= 1
	# --- hunt: брызги крови, рана кровит ---
	var hn: Variant = main.get("hunt")
	if hn != null:
		hn.on_bitten(self, by)
	# --- /hunt ---
	if hp_left <= 0:
		kill()
	elif state != "flee":
		_flee_from(by, 6.0)

## Гибель: туша остаётся лежать на боку, пока её не съедят (падальщики, вороны), через сутки — новый зверь.
func kill() -> void:
	dead = true
	_drop_fish()
	if carry != null:
		carry.queue_free()
		carry = null
	food = null
	prey = null
	speed = 0.0
	state = "dead"
	climb_h = 0.0
	meat = clampf(float(parts.get("L", 0.5)), 0.25, 3.0) * 60.0
	respawn_at = float(main.t_hours) + float(main.day_count) * 24.0 + 24.0
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	position.y = main.ground_at(position.x, position.z) + float(parts.get("H", 0.5)) * 0.22
	rotation = Vector3(0.0, heading, side * PI * 0.5)
	if parts.has("ap"):
		(parts["ap"] as AnimationPlayer).active = false
	if mgr != null:
		mgr.add_carcass(self)
	# --- hunt: лужа крови, туша на учёт для разделки ---
	var hn: Variant = main.get("hunt")
	if hn != null:
		hn.on_kill(self)
	# --- /hunt ---

func _revive() -> void:
	# --- hunt: на месте туши — кости, модель снова в шкуре ---
	var hn: Variant = main.get("hunt")
	if hn != null:
		hn.on_revive(self)
	# --- /hunt ---
	dead = false
	meat = 0.0
	tire = 0.0
	hp_left = int(TOUGH.get(kind, 1)) if scale_k > 0.75 else 1
	rotation = Vector3(0.0, heading, 0.0)
	visible = true
	position = door if door != Vector3.INF else home
	if mgr != null:
		mgr.carcasses.erase(self)
	_new_wander()

## Медведь бьёт лапой по воде; поймал — несёт рыбу на берег.
func _swipe() -> void:
	fish_cd = rng.randf_range(3.0, 7.0)
	_attack_t = 0.8
	var fwd := Vector3(sin(heading), 0, cos(heading))
	var p := position + fwd * float(parts["L"]) * 0.6
	if main.sfx != null and not far:
		main.sfx.play_at("splash", p, 2.0, rng.randf_range(0.8, 1.1))
	if mgr.fish == null or not mgr.fish.catch_at(p, 0.35):
		return
	fish_n = mgr.fish.make_fish()
	add_child(fish_n)
	var L: float = parts["L"]
	var H: float = parts["H"]
	fish_n.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, H * 1.05, L * 0.55))
	var side := _bank_side(position)
	var bs := _bank_spot(position.x, side)
	target = (bs + Vector3(0, 0, side * 3.0)) if bs != Vector3.INF else position + Vector3(0, 0, side * 6.0)
	state = "fish_bank"
	state_t = 12.0

## На берегу: рыба на земле перед мордой, медведь ест (поза кормёжки).
func _eat_fish() -> void:
	state = "eat"
	state_t = rng.randf_range(9.0, 15.0)
	if fish_n != null:
		var L: float = parts["L"]
		fish_n.transform = Transform3D(Basis(Vector3.FORWARD, PI * 0.5) * Basis(Vector3.UP, 0.6), Vector3(0, 0.04, L * 0.62))

## Походка: фазы ног по виду аллюра, наклон по склону, голова, хвост, отдых.
var goffs := [0.0, 0.5, 0.75, 0.25]
var r_s := 0.0
var _breath := 0.0

var _attack_t := 0.0
var _gallop_mode := false

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
		# вплавь: ноги гребут под водой в спокойном темпе
		want_a = SK.find_anim(ap, ["Walk"])
		sc = 0.85 if speed > 0.05 else 0.5
	elif speed > walk * (1.7 if not _gallop_mode else 1.52):
		_gallop_mode = true
		want_a = SK.find_anim(ap, ["Gallop"])
		sc = clampf(speed / float(sp["run"]), 0.7, 1.35)
	elif speed > 0.08:
		_gallop_mode = false
		want_a = SK.find_anim(ap, ["Walk"])
		sc = clampf(speed / walk, 0.45, 1.4)
	elif state in ["graze", "feed", "drink", "eat"]:
		want_a = SK.find_anim(ap, ["Eating"])
	elif state in ["rest", "sleep", "ambush"]:
		want_a = SK.find_anim(ap, ["Idle_Headlow", "Idle_2_HeadLow", "Idle"])
	elif state in ["alert", "watch"]:
		want_a = SK.find_anim(ap, ["Idle_2", "Idle"])
	else:
		_gallop_mode = false
		want_a = SK.find_anim(ap, ["Idle"])
	if want_a != "" and want_a != parts["cur"]:
		# Плавное переключение циклов, без резкого среза позы при смене аллюра.
		var blend := clampf(0.22 + absf(speed - walk) * 0.035, 0.22, 0.42)
		ap.play(want_a, blend)
		parts["cur"] = want_a
	ap.speed_scale = lerpf(ap.speed_scale, sc, clampf(delta * 6.0, 0.0, 1.0))
	# наклон по склону
	var L: float = parts["L"]
	var fwd := Vector3(sin(heading), 0, cos(heading))
	var hf: float = main.ground_at(position.x + fwd.x * L * 0.4, position.z + fwd.z * L * 0.4)
	var hb: float = main.ground_at(position.x - fwd.x * L * 0.4, position.z - fwd.z * L * 0.4)
	var m: Node3D = parts["model"]
	m.rotation.x = lerpf(m.rotation.x, -atan2(hf - hb, L * 0.8) * (1.0 - swim_k) - 0.18 * swim_k, minf(1.0, delta * 6.0))

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
	# Небольшое живое движение сохраняется и в неподвижной позе:
	# дыхание не должно выглядеть как масштабирование всей модели.
	var idle_k := 1.0 - mv
	body.rotation.z = sin(phase) * 0.035 * mv * (1.0 - r * 0.5) + sin(_breath * 0.48) * 0.012 * idle_k
	body.rotation.x = lerpf(body.rotation.x, pitch + (sin(phase) * 0.18 * r if gait == "bound" else 0.0) + sin(_breath) * 0.008 * idle_k, minf(1.0, delta * 8.0))
	body.scale = Vector3(1.0 + sin(_breath) * 0.004 * idle_k, 1.0 + sin(_breath) * 0.009 * idle_k, 1.0)
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
		head.rotation.y = lerpf(head.rotation.y, sin(_breath * 0.31 + float(rng.seed % 13)) * 0.035 * (1.0 - mv), minf(1.0, delta * 2.4))
	var tail: Node3D = parts["tail"]
	var tail_idle := sin(_breath * 0.72 + float(rng.seed % 17)) * 0.10
	var tail_gait := sin(phase * 2.0) * 0.1 * mv
	tail.rotation.x = tail_gait + (0.4 if r > 0.5 else 0.0) + tail_idle * (1.0 - mv)
	tail.rotation.y = sin(_breath * 0.53 + float(rng.seed % 11)) * 0.12 * (1.0 - mv) + sin(phase * 1.4) * 0.035 * mv

# ---------- Походка зверей на скелете (модели build_taiga) ----------
# Поворачиваются кости: нога (лопатка/таз, плечо/бедро, предплечье/голень, пясть/плюсна,
# копыто/лапа), таз и грудь (хребет гнётся на галопе и прыжках), два звена шеи, голова,
# челюсть, хвост. Порядок постановки ног — как на съёмках Майбриджа: шаг — латеральная
# последовательность ЛЗ, ЛП, ПЗ, ПП; рысь — диагональные пары; галоп — у кошек вращательный
# (ЛЗ, ПЗ, ПП, ЛП), у копытных поперечный (ЛЗ, ПЗ, ЛП, ПП); прыжки куньих и зайца — задние
# почти вместе, передние почти вместе. Опора — половина цикла: нога идёт назад; перенос —
# нога сгибается (запястье, скакательный сустав), копыто/лапа держится вдоль земли.

var _rig_t := 0.0
var _swim_ph := 0.0
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
	_lie_k = lerpf(_lie_k, 1.0 if state in ["rest", "sleep", "ambush"] and speed < 0.1 and swim_k < 0.1 else 0.0, minf(1.0, delta * 1.5))
	_feed_k = lerpf(_feed_k, 1.0 if state in ["graze", "feed", "drink", "eat"] and speed < 0.1 and swim_k < 0.3 else 0.0, minf(1.0, delta * 2.5))
	_alert_k = lerpf(_alert_k, 1.0 if state in ["alert", "watch"] else 0.0, minf(1.0, delta * 4.0))
	# вплавь: «по-собачьи» — ноги гребут под водой в своём ритме, голова поднята, тело низко
	var swm := smoothstep(0.3, 0.8, swim_k)
	_swim_ph += delta * TAU * (0.8 + speed * 0.5) * swm
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
		if swm > 0.0:
			var ps: float = _swim_ph + (0.0 if i == 0 or i == 3 else PI)
			var reach := sin(ps)
			var lf := maxf(0.0, -cos(ps))
			if front:
				d0 = lerpf(d0, -0.35 + reach * 0.75, swm)
				d1 = lerpf(d1, -lf * 0.9, swm)
				d2 = lerpf(d2, lf * 1.3, swm)
			else:
				d0 = lerpf(d0, 0.15 + reach * 0.6, swm)
				d1 = lerpf(d1, lf * 0.8, swm)
				d2 = lerpf(d2, -lf * 0.9, swm)
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
	var pitch := rock - 0.14 * swm + sin(_swim_ph * 2.0) * 0.025 * swm
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
	var nd := nod + float(G[0]) * _feed_k - 0.35 * _alert_k + 0.3 * r - 0.15 * lie + chew - 0.45 * swm
	var hd := -nod * 0.5 + float(G[1]) * _feed_k + 0.15 * _alert_k - 0.2 * r + 0.2 * swm
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
