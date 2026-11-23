extends Node
## --- colony: сценарий «Первая зима». ---
## Осень, день 1. Трое вышли к реке и ставят острог. Задачи идут одна за другой,
## но считаются все сразу: HUD показывает текущую и её ход.
## Случаи: волчья стая ночью, пурга, раненый, медведь у лагеря.
## Победа — к весне сдать воеводе меха. Проигрыш — весь отряд погиб.
##
## Публичное:
##   cur() -> Dictionary        — текущая задача {text, prog, done}
##   list() -> Array            — все задачи
##   over -> bool, won -> bool  — исход
##   restart()                  — заново

const SPRING_DAY := 25         # 12 дней осени + 12 зимы
const FROST_DAY := 6
const WINTER_DAY := 13
const NEED_FOOD := 24
const NEED_WOOD := 30
const NEED_FURS := 6
const NEED_WALL := 4

var main: Node3D
var colony
var over := false
var won := false
var end_text := ""
var step := 0
var event_t := 4.0             # игровых часов до следующего случая
var last_event := ""
var event_text := ""
var event_tt := 0.0
var storm := false
var _t := 0.0
var _day := 1
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.seed = 991

func day() -> int:
	return int(main.day_count)

func list() -> Array:
	var c = colony
	var out: Array = []
	out.append({"text": "Поставить укрытие до морозов (день %d)" % FROST_DAY,
		"prog": "%d/1" % c.shelter_count(), "done": c.shelter_count() >= 1})
	out.append({"text": "Запасти еду и дрова к зиме (день %d)" % WINTER_DAY,
		"prog": "еда %d/%d · дрова %d/%d" % [c.food_count(), NEED_FOOD, c.count("firewood"), NEED_WOOD],
		"done": c.food_count() >= NEED_FOOD and c.count("firewood") >= NEED_WOOD})
	out.append({"text": "Срубить избу и поставить стену",
		"prog": "изба %d/1 · прясел %d/%d" % [c.count_built("cabin"), c.count_built("palisade"), NEED_WALL],
		"done": c.count_built("cabin") >= 1 and c.count_built("palisade") >= NEED_WALL})
	out.append({"text": "Дожить до весны",
		"prog": "день %d/%d" % [day(), SPRING_DAY], "done": day() >= SPRING_DAY})
	out.append({"text": "Сдать воеводе меха",
		"prog": "%d/%d" % [c.furs(), NEED_FURS], "done": c.furs() >= NEED_FURS})
	return out

func cur() -> Dictionary:
	var all := list()
	for e: Dictionary in all:
		if not bool(e["done"]):
			return e
	return all[all.size() - 1]

func _process(delta: float) -> void:
	if over or colony == null or main == null:
		return
	_t -= delta
	event_tt = maxf(0.0, event_tt - delta)
	if _t > 0.0:
		return
	_t = 1.0
	var d := day()
	if d != _day:
		_day = d
		colony.stats["days"] = d
		_on_new_day(d)
	# победа: весна и меха сданы
	if d >= SPRING_DAY and colony.furs() >= NEED_FURS:
		win()
		return
	if colony.alive_count() == 0:
		lose("Весь отряд погиб")
		return
	# случаи: счётчик в игровых часах (игровой час — 75 секунд)
	event_t -= 1.0 / 75.0
	if event_t <= 0.0:
		_fire_event()

func _on_new_day(d: int) -> void:
	if d == FROST_DAY and colony.shelter_count() == 0:
		say("Первые морозы, а укрытия нет: люди мёрзнут")
		for u in colony.units:
			u.warmth = maxf(0.0, u.warmth - 0.25)
	if d == WINTER_DAY:
		say("Зима пришла. Волки подходят к лагерю ночами")
	if d == SPRING_DAY:
		if colony.furs() >= NEED_FURS:
			win()
		else:
			say("Весна! Воевода ждёт меха: %d из %d" % [colony.furs(), NEED_FURS])

## Редкие случаи: в зиму — чаще и злее.
func _fire_event() -> void:
	var winter: bool = day() >= WINTER_DAY and day() < SPRING_DAY
	event_t = rng.randf_range(5.0, 11.0) * (0.7 if winter else 1.0)
	var night: bool = float(main.day_factor) < 0.25
	var roll := rng.randf()
	if winter and night and roll < 0.45:
		_wolves(2 + int(rng.randf() * 2.0))
	elif roll < 0.6 and (winter or day() > 4):
		_storm()
	elif roll < 0.75:
		_wounded()
	elif roll < 0.85 and not winter:
		_bear()

func _wolves(n: int) -> void:
	if main.animals == null:
		return
	var c: Vector3 = colony.center()
	var a0 := rng.randf() * TAU
	var pack := 900 + int(rng.randf() * 50.0)
	var came := 0
	for i in n:
		var a := a0 + float(i) * 0.5
		var p := c + Vector3(cos(a), 0, sin(a)) * rng.randf_range(32.0, 46.0)
		if not colony.nav.passable(p.x, p.z):
			p = colony.nav.nearest_free(p, 10.0)
		var w: Node3D = main.animals._spawn("wolf", p, 1.0, pack)
		w.home = c
		w.home_r = 90.0
		w.prey = main.hero
		w.state = "chase"
		w.state_t = 90.0
		came += 1
	if came > 0:
		say("Волки! Стая идёт к лагерю")
		last_event = "wolves"
		# охотники берут оружие и встают навстречу
		for u in colony.units:
			if u.state == "dead" or u.weapon == "":
				continue
			u.show_tool(u.weapon)

func _bear() -> void:
	if main.animals == null:
		return
	var c: Vector3 = colony.center()
	var a := rng.randf() * TAU
	var p: Vector3 = colony.nav.nearest_free(c + Vector3(cos(a), 0, sin(a)) * 30.0, 10.0)
	var b: Node3D = main.animals._spawn("bear", p, 1.0, -1)
	b.home = p
	b.state = "charge"
	b.state_t = 25.0
	say("Медведь у лагеря!")
	last_event = "bear"

func _storm() -> void:
	var w = main.weather
	w.t_cloud = 1.0
	w.t_precip = 1.0
	w.t_wind = rng.randf_range(1.7, 2.2)
	w.t_fog = 0.3
	w.next_change = rng.randf_range(4.0, 8.0)
	storm = true
	last_event = "storm"
	say("Пурга! Всем в укрытие" if float(w.temp) < 1.0 else "Ливень с ветром")
	# люди бросают работу и идут к огню или в укрытие
	for u in colony.units:
		if u.state == "dead":
			continue
		var sh: Dictionary = colony.nearest_building(u.position, ["cabin", "dugout", "leanto", "tree_shelter", "snow_shelter"], 120.0)
		if sh.is_empty():
			sh = colony.nearest_building(u.position, ["campfire"], 120.0)
		if sh.is_empty():
			continue
		colony.jobs.cancel(u)
		colony.jobs.start(u, "warm" if String(sh["type"]) == "campfire" else "sleep", {"site": sh, "pos": sh["pos"]})

func _wounded() -> void:
	var live: Array = []
	for u in colony.units:
		if u.state != "dead":
			live.append(u)
	if live.is_empty():
		return
	var u2 = live[rng.randi() % live.size()]
	u2.bleed = minf(1.0, u2.bleed + 0.35)
	u2.health = maxf(0.15, u2.health - 0.12)
	say("%s зашибся на работе: кровь" % u2.unit_name)
	last_event = "wounded"

func say(t: String) -> void:
	event_text = t
	event_tt = 7.0
	colony.note(t)

func win() -> void:
	if over:
		return
	over = true
	won = true
	end_text = "Острог поставлен. Меха сданы воеводе."
	if colony.ui != null:
		colony.ui.show_end(true)

func lose(why: String) -> void:
	if over:
		return
	over = true
	won = false
	end_text = why
	if colony.ui != null:
		colony.ui.show_end(false)

func restart() -> void:
	# перезапуск сцены: самое надёжное — заново загрузить main.tscn
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func to_save() -> Dictionary:
	return {"over": over, "won": won, "step": step, "event_t": event_t, "day": _day}

func from_save(d: Dictionary) -> void:
	over = bool(d.get("over", false))
	won = bool(d.get("won", false))
	step = int(d.get("step", 0))
	event_t = float(d.get("event_t", 6.0))
	_day = int(d.get("day", 1))
