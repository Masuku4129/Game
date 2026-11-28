extends Node3D
## Охота: туши, разделка, кровь и запах крови.
## • Мелкую добычу (заяц, белка, глухарь) подбирают в короб тушкой; крупную разделывают на месте
##   ножом: герой встаёт на колено и работает (Fixing_Kneeling), шкура снимается — модель зверя
##   становится освежёванной тушей (carcass.gdshader), рядом расстилается шкура, на неё ложатся
##   куски мяса; остатки (мясо на костях) ещё долго привлекают падальщиков, объеденные — кости.
## • Кровь: капли и мазки за раненым зверем (по ним можно идти), лужа на месте гибели и разделки,
##   капли за раненым героем, кровь на руках и куртке героя (смывается водой и дождём).
## • Запах крови (animals.add_scent): кровь героя, место разделки, сырое мясо в коробе — хищники
##   поблизости приходят проверить.
## Публичное: hit_animal(зверь, урон, откуда) — попадание оружием; drop_item(id, точка) —
## выложить вещь на землю (модель + можно подобрать); on_kill/on_bitten/on_revive — из animal.gd.

const BloodMM = preload("res://scripts/blood.gd")
const HM = preload("res://scripts/hunt_models.gd")
const AM = preload("res://scripts/animal_model.gd")
const IT = preload("res://scripts/items.gd")

const SMALL := ["hare", "squirrel", "capercaillie"]
# кусков сырого мяса со взрослого зверя
const MEAT := {"roe": 4, "muskdeer": 3, "deer": 7, "boar": 6, "moose": 10, "bear": 9, "wolf": 3, "tiger": 8, "lynx": 2, "wolverine": 2, "fox": 1, "beaver": 2}
# живучесть к ударам оружием (косуля — 1)
const HP := {"moose": 2.6, "bear": 2.4, "tiger": 2.2, "deer": 1.7, "boar": 1.6, "wolf": 1.2, "lynx": 0.9, "wolverine": 0.9, "muskdeer": 0.7, "fox": 0.5, "beaver": 0.6, "hare": 0.3, "squirrel": 0.15, "capercaillie": 0.3}
const RU := {"roe": "косуля", "deer": "олень", "boar": "кабан", "moose": "лось", "bear": "медведь", "wolf": "волк", "tiger": "тигр",
	"lynx": "рысь", "wolverine": "росомаха", "fox": "лиса", "muskdeer": "кабарга", "beaver": "бобр", "hare": "заяц", "squirrel": "белка", "capercaillie": "глухарь"}
# кадры Fixing_Kneeling: опустился на колено, петля работы руками, подъём
const KNEEL_T := 1.15
const WORK_A := 1.6
const WORK_B := 3.3
const RISE_A := 4.45
const ANIM_END := 5.2
const DROP := 0.0
const SMEAR := 0.5
const POOL := 1.0

var main: Node3D
var blood: BloodMM
var t0 := 0.0                    # часы на старте: время пятен — от него (точность в шейдере)
var hp := {}                     # зверь → остаток жизни после ударов оружием
var wounds := {}                 # зверь → {bleed, last, gap, still, sc}
var carc := {}                   # туша крупного зверя → {p, done, meat0, mats, bones}
var piles: Array = []            # вещи на земле: {pos, items, node, hide, meats, r}
var bone_sets: Array = []        # [узел, до (ч)]
var hand_blood := 0.0
var body_blood := 0.0
var pressed := false             # рану без повязки уже зажимали
# работа героя над тушей
var job: Node3D = null
var job_t := 0.0
var job_rise := -1.0
var job_from := Vector3.ZERO
var job_to := Vector3.ZERO
var job_yaw0 := 0.0
var job_yaw := 0.0
var _splat_t := 0.0
var _scent_t := 0.0
var _carc_t := 0.0
var _hero_last := Vector3.INF
var _hero_gap := 1.0
var _hero_still := 0.0
var _refresh_i := 0
var overlays: Array = []         # [MeshInstance3D, ShaderMaterial, "hand" | "body"]
var carried: Node3D = null       # тушка на поясе героя
var debug := false
var _keys := {}
var rng := RandomNumberGenerator.new()
var traveler_seed := 0

func setup() -> void:
	rng.seed = 5150
	var traveler_rng := RandomNumberGenerator.new()
	traveler_rng.randomize()
	traveler_seed = traveler_rng.randi()
	t0 = now_h()
	blood = BloodMM.new()
	add_child(blood)
	# в начале игры с собой нож и пара повязок (если инвентарь ещё не выдал своё)
	if not main.inv.has("knife"):
		main.inv["knife"] = 1
	if not main.inv.has("bandage"):
		main.inv["bandage"] = 2
	debug = OS.get_environment("HUNT_DEBUG") != ""
	if main.hero != null and main.hero.get("m_sk") != null:
		_build_overlays(main.hero.m_sk)
	_spawn_rare_swamp_traveler()

## Редкая находка на болоте: один путник на карту, если сработал шанс генерации.
## Позиция детерминирована seed карты; при загрузке сохранения находка восстанавливается из loot pile.
func _spawn_rare_swamp_traveler() -> void:
	if (main.get("colony_mode") == true):
		return
	var srng := RandomNumberGenerator.new()
	srng.seed = traveler_seed
	if srng.randf() > 0.22:
		return
	var half := float(main.SIZE) * 0.5
	for attempt in 700:
		var x := srng.randf_range(-half + 8.0, half - 8.0)
		var z := srng.randf_range(-half + 8.0, half - 8.0)
		if int(main.zone(x, z)) != 2:
			continue
		var depth := float(main.swamp_depth_at(x, z))
		if depth < 0.12 or depth > 0.82:
			continue
		if main.normal_at(x, z).y < 0.97 or main.height(x, z) < main.WATER_Y - 0.2:
			continue
		var p := Vector3(x, surface_y(x, z), z)
		_create_traveler_pile(p, srng.randf() * TAU, srng.randi_range(3, 8))
		return

func _create_traveler_body(parent: Node3D) -> void:
	# Используем полноценную скелетную GLTF-модель человека и штатную систему одежды,
	# а не собираем силуэт путника из примитивных капсул.
	var palette := {
		"jacket": Color(0.25, 0.19, 0.12),
		"pants": Color(0.18, 0.19, 0.16),
		"boots": Color(0.16, 0.11, 0.07),
		"fur": Color(0.42, 0.34, 0.23),
		"hair": Color(0.25, 0.17, 0.11)
	}
	var built: Dictionary = preload("res://scripts/hero_skin.gd").build(parent, palette)
	var model: Node3D = built["model"]
	model.scale = Vector3(0.9, 0.9, 0.9)
	# Лежит лицом в мох, на спине виден вещмешок; голова направлена к южному краю.
	model.rotation.x = PI * 0.5
	model.position = Vector3(0.0, 0.08, -0.82)
	# Потёртый дорожный вещмешок остаётся на спине путника.
	var pack_mat := StandardMaterial3D.new()
	pack_mat.albedo_color = Color(0.19, 0.12, 0.07)
	pack_mat.roughness = 1.0
	var pack := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.34, 0.42, 0.19)
	pack.mesh = pm
	pack.material_override = pack_mat
	pack.position = Vector3(0.0, 1.12, -0.17)
	model.add_child(pack)
	var strap := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.035, 0.55, 0.025)
	strap.mesh = sm
	strap.material_override = pack_mat
	strap.rotation.z = -0.28
	strap.position = Vector3(0.18, 0.94, 0.0)
	model.add_child(strap)


func _create_traveler_pile(pos: Vector3, yaw: float, rounds: int, has_rifle: bool = true) -> void:
	var pl := _new_pile(pos, yaw)
	pl["corpse"] = true
	pl["r"] = 1.25
	var body := Node3D.new()
	body.position.y = 0.015
	(pl["node"] as Node3D).add_child(body)
	_create_traveler_body(body)
	if has_rifle:
		_drop_generic("rifle", pos + Vector3(0.55, 0.0, 0.15))
	for i in rounds:
		_drop_generic("rifle_round", pos + Vector3(0.55, 0.0, 0.15))

func now_h() -> float:
	return float(main.t_hours) + float(main.day_count) * 24.0

func _clock() -> float:
	return now_h() - t0

# ---------- земля ----------

## Высота видимой поверхности (сетка рельефа теми же треугольниками + снег − след).
func surface_y(x: float, z: float) -> float:
	var hs: Variant = main.get("terrain_hs")
	if hs == null:
		return float(main.ground_at(x, z)) + 0.012
	var y := _tri_h(x, z)
	var f: Node = main.get("feet")
	if f != null:
		var sd: float = f.snow_depth(x, z)
		var t: float = f.track_depth(x, z)
		y += sd - minf(t, sd + float(f.mud_depth(x, z))) + 0.015
	var so: float = main.solid_top(x, z)
	if so > y - 0.03:
		y = so + 0.005
	return y + 0.008

func _tri_h(x: float, z: float) -> float:
	var hs: PackedFloat32Array = main.terrain_hs
	var seg: int = main.SEG
	var n := seg + 1
	var st: float = main.SIZE / float(seg)
	var gx := clampf((x + main.SIZE * 0.5) / st, 0.0, seg - 0.001)
	var gz := clampf((z + main.SIZE * 0.5) / st, 0.0, seg - 0.001)
	var ix := int(gx)
	var iz := int(gz)
	var fx := gx - ix
	var fz := gz - iz
	var i := iz * n + ix
	var a := hs[i]
	var b := hs[i + 1]
	var c := hs[i + n]
	var d := hs[i + n + 1]
	if fx + fz <= 1.0:
		return a + fx * (b - a) + fz * (c - a)
	return d + (1.0 - fx) * (c - d) + (1.0 - fz) * (b - d)

var force_snow := -1.0          # студия: глубина снега везде

func snow_at(x: float, z: float) -> float:
	if force_snow >= 0.0:
		return force_snow
	var f: Node = main.get("feet")
	return float(f.snow_depth(x, z)) if f != null else 0.0

func _normal(x: float, z: float) -> Vector3:
	var e := 0.25
	return Vector3(surface_y(x - e, z) - surface_y(x + e, z), 2.0 * e, surface_y(x, z - e) - surface_y(x, z + e)).normalized()

## Пятно крови в точке p (высота берётся по земле/снегу).
func splat(p: Vector3, size: float, shape: float, life: float, yaw: float = -1.0, stretch: float = 1.0, power: float = 1.0) -> void:
	if blood == null:
		return
	var sd := snow_at(p.x, p.z)
	var n := _normal(p.x, p.z) if shape > 0.75 or size > 0.25 else Vector3.UP
	blood.add(Vector3(p.x, surface_y(p.x, p.z), p.z), n, size, shape, clampf(sd / 0.03, 0.0, 1.0), _clock(), life, yaw, stretch, power, sd)

## Лужа под тушей и брызги вокруг.
func pool_at(p: Vector3, r: float, life: float) -> void:
	splat(p, r * 2.0, POOL, life)
	for i in 5:
		var a := rng.randf() * TAU
		splat(p + Vector3(cos(a), 0, sin(a)) * r * rng.randf_range(0.9, 1.8), rng.randf_range(0.05, 0.12), DROP, life * 0.7)

# ---------- звери: удары, раны, гибель ----------

## Попадание оружием (копьё, нож). dmg — доля жизни косули: 0.3 — лёгкая рана, 0.6 — тяжёлая,
## 1+ — наповал. from — откуда удар (для брызг и бегства). Раненый зверь убегает, оставляя
## кровавый след, слабеет и может истечь кровью.
func hit_animal(a: Node3D, dmg: float, from: Vector3) -> void:
	if a == null or a.dead:
		return
	var tough := float(HP.get(a.kind, 1.0)) * clampf(float(a.scale_k), 0.4, 1.1)
	var cur: float = float(hp.get(a, 1.0)) - dmg / tough
	hp[a] = cur
	var away: Vector3 = a.position - from
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
	for i in 2 + int(clampf(dmg, 0.0, 1.0) * 5.0):
		var q: Vector3 = a.position + away * rng.randf_range(0.2, 1.2) + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
		splat(q, rng.randf_range(0.05, 0.11), DROP, 16.0)
	splat(a.position + away * 0.4, 0.22, SMEAR, 16.0, atan2(away.x, away.z), 2.0)
	main.animals.add_scent(a.position, 1.0, 120.0)
	if cur <= 0.0:
		a.kill()
		return
	var w: Dictionary = wounds.get(a, {"bleed": 0.0, "last": a.position, "gap": 0.5, "still": 0.0, "sc": 0.0})
	w["bleed"] = minf(1.5, float(w["bleed"]) + dmg * 2.0)
	wounds[a] = w
	# раненый: прочь от охотника; кабан, лось, медведь, тигр, росомаха вблизи могут броситься
	var hero: Node3D = main.hero
	if a.kind in ["bear", "boar", "tiger", "moose", "wolverine"] and rng.randf() < 0.5 and a.position.distance_to(hero.position) < 8.0:
		a.state = "charge"
		a.state_t = 6.0
	else:
		a._flee_from(hero, 14.0)
		if a.mgr != null:
			a.mgr.alarm(a, hero)

## Укус хищника (animal.gd bitten): брызги; уцелевший зверь кровит.
func on_bitten(a: Node3D, by: Node3D) -> void:
	for i in 3:
		splat(a.position + Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5)), rng.randf_range(0.05, 0.1), DROP, 16.0)
	if not a.dead:
		var w: Dictionary = wounds.get(a, {"bleed": 0.0, "last": a.position, "gap": 0.5, "still": 0.0, "sc": 0.0})
		w["bleed"] = minf(1.5, float(w["bleed"]) + 0.35)
		wounds[a] = w
	if by != null and main.get("animals") != null:
		main.animals.add_scent(a.position, 0.8, 90.0)

## Гибель зверя (animal.gd kill): лужа крови, запах; крупная туша — на учёт для разделки.
func on_kill(a: Node3D) -> void:
	hp.erase(a)
	wounds.erase(a)
	var L: float = float(a.parts.get("L", 0.6))
	pool_at(body_center(a), clampf(L * 0.28, 0.1, 0.7), 30.0)
	if main.get("animals") != null:
		main.animals.add_scent(a.position, 1.2, 240.0)
	if not (a.kind in SMALL):
		carc[a] = {"p": 0.0, "done": false, "meat0": float(a.meat), "mats": [], "bones": false}

## Зверь снова жив (animal.gd _revive, до переноса домой): на месте туши — кости, модель — обратно в шкуру.
func on_revive(a: Node3D) -> void:
	if carc.has(a):
		var e: Dictionary = carc[a]
		if not bool(e["bones"]) and a.dead:
			_spawn_bones(a)
		if not (e["mats"] as Array).is_empty():
			a._build(a.winter_skin)
		carc.erase(a)
	hp.erase(a)
	wounds.erase(a)
	if job == a:
		cancel()

## Середина тела лежащей туши (узел зверя стоит у ног, туша лежит на боку).
func body_center(a: Node3D) -> Vector3:
	if not a.dead:
		return a.position
	var H: float = float(a.parts.get("H", 0.5))
	var c: Vector3 = a.global_transform * Vector3(0, H * 0.55, 0)
	c.y = a.position.y
	return c

func _tick_wounds(delta: float) -> void:
	for a: Node3D in wounds.keys():
		if not is_instance_valid(a) or a.dead:
			wounds.erase(a)
			continue
		var w: Dictionary = wounds[a]
		var b: float = w["bleed"]
		var cur: float = float(hp.get(a, 1.0)) - b * 0.008 * delta
		hp[a] = cur
		w["bleed"] = maxf(0.0, b - 0.006 * delta)
		# слабеет: бежит медленнее (усталость зверя)
		a.tire = maxf(float(a.tire), clampf((1.0 - cur) * 1.1, 0.0, 0.95))
		if cur <= 0.0:
			wounds.erase(a)
			a.kill()
			continue
		if b <= 0.02:
			wounds.erase(a)
			continue
		var lp: Vector3 = w["last"]
		var d := Vector2(a.position.x - lp.x, a.position.z - lp.z).length()
		var gap: float = w["gap"]
		if d >= gap:
			var n := mini(int(d / gap), 8)
			for k in n:
				var q: Vector3 = lp.lerp(a.position, float(k + 1) / n) + Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15))
				splat(q, rng.randf_range(0.1, 0.16) + 0.08 * b, DROP, 16.0, -1.0, 1.0, clampf(0.5 + b * 0.5, 0.0, 1.0))
			w["last"] = a.position
			w["gap"] = rng.randf_range(0.7, 2.2) / clampf(b, 0.35, 1.5)
			w["still"] = 0.0
		else:
			w["still"] = float(w["still"]) + delta
			if float(w["still"]) > 3.0:
				w["still"] = 0.0
				splat(a.position + Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2)), 0.08 + 0.12 * b, POOL if b > 0.6 else DROP, 16.0)
		w["sc"] = float(w["sc"]) - delta
		if float(w["sc"]) <= 0.0:
			w["sc"] = 3.0
			main.animals.add_scent(a.position, 0.5 + b * 0.5, 60.0)

# ---------- туши: подобрать, разделать ----------

func _near_carcass(p: Vector3) -> Node3D:
	var best: Node3D = null
	var bd := 1e9
	for a: Node3D in main.animals.carcasses:
		if not a.dead or float(a.meat) <= 0.0 or not a.visible:
			continue
		var L: float = float(a.parts.get("L", 0.6))
		var c := body_center(a)
		var d := Vector2(c.x - p.x, c.z - p.z).length()
		if d < clampf(L * 0.55, 0.3, 1.4) + 0.9 and d < bd:
			bd = d
			best = a
	return best

func meat_count(a: Node3D) -> int:
	var sk: float = float(a.scale_k)
	return maxi(1, int(round(float(MEAT.get(a.kind, 2)) * clampf(sk * sk, 0.15, 1.2))))

func _work_time(a: Node3D) -> float:
	return clampf(4.0 + 1.1 * float(meat_count(a)), 5.0, 16.0)

func has_knife() -> bool:
	var h: Variant = main.hero.get("held")
	if h is String and String(h) == "knife":
		return true
	return int(main.inv.get("knife", 0)) > 0

## Надпись на кнопке действия (hero.action_label) или "".
func action_label() -> String:
	if main.hero.state == "butcher":
		return "Прервать"
	var p: Vector3 = main.hero.position
	var pl := _pile_near(p)
	if not pl.is_empty():
		return "Забрать: " + _pile_text(pl)
	var c := _near_carcass(p)
	if c != null:
		if c.kind in SMALL:
			return "Подобрать: " + String(RU.get(c.kind, "тушка"))
		var e: Dictionary = carc.get(c, {})
		if not bool(e.get("done", false)):
			return ("Разделать: " if float(e.get("p", 0.0)) <= 0.0 else "Дорезать: ") + String(RU.get(c.kind, ""))
	return ""

## Нажата кнопка действия с надписью lbl; true — обработано здесь.
func do_action(lbl: String) -> bool:
	if lbl == "Прервать":
		cancel()
		return true
	if lbl.begins_with("Забрать: "):
		_take_pile(_pile_near(main.hero.position))
		return true
	if lbl.begins_with("Подобрать: "):
		var c := _near_carcass(main.hero.position)
		if c == null:
			return true
		if main.inventory != null and not main.inventory.can_add("carcass_small"):
			main._say("Короб полон")
			return true
		main.inv["carcass_small"] = int(main.inv.get("carcass_small", 0)) + 1
		c.meat = 0.0
		c.visible = false
		main._say("Тушка (%s) — в короб" % String(RU.get(c.kind, "")))
		main.hero.land_t = 0.55
		main.hero.land_k = 0.85
		return true
	if lbl.begins_with("Разделать: ") or lbl.begins_with("Дорезать: "):
		var c2 := _near_carcass(main.hero.position)
		if c2 == null:
			return true
		if not has_knife():
			main._say("Нужен нож")
			return true
		_start_job(c2)
		return true
	return false

func _start_job(c: Node3D) -> void:
	var h: Node3D = main.hero
	if main.inventory != null:
		main.inventory.abort()
	if not carc.has(c):
		carc[c] = {"p": 0.0, "done": false, "meat0": float(c.meat), "mats": [], "bones": false}
	job = c
	job_t = 0.0
	job_rise = -1.0
	_splat_t = 0.0
	# встаёт на колено со стороны спины туши (ноги — с другой стороны), лицом к ней
	var cen := body_center(c)
	var back: Vector3 = cen - c.position
	back.y = 0.0
	back = back.normalized() if back.length() > 0.01 else (h.position - cen).normalized()
	if back.dot(h.position - cen) < -0.3 and (h.position - cen).length() > 0.1:
		# герой стоит со стороны ног — тогда у брюха, но дальше
		back = -back
	var H: float = float(c.parts.get("H", 0.5))
	var reach := clampf(H * 0.35, 0.12, 0.5) + 0.5
	job_from = h.position
	job_to = cen + back * reach
	job_to.y = h.position.y
	if main.blocked(job_to.x, job_to.z, 0.25):
		job_to = Vector3(h.position.x, h.position.y, h.position.z)
	job_yaw0 = float(h.body.rotation.y)
	var tc: Vector3 = cen - job_to
	job_yaw = atan2(tc.x, tc.z)
	h.state = "butcher"
	h.vel = Vector3.ZERO
	main._say("Разделываю: %s" % String(RU.get(c.kind, "")))

## Прервать работу: герой встаёт, сделанное сохраняется на туше.
func cancel() -> void:
	if main.hero.state != "butcher":
		job = null
		return
	if job_rise < 0.0:
		job_rise = 0.0

## Кадр героя в состоянии "butcher" (вызов из hero.gd).
func hero_tick(delta: float) -> void:
	var h: Node3D = main.hero
	h.moving = false
	h.running = false
	h.vel = Vector3.ZERO
	job_t += delta
	var k := smoothstep(0.0, 0.7, job_t)
	h.position.x = lerpf(job_from.x, job_to.x, k)
	h.position.z = lerpf(job_from.z, job_to.z, k)
	h.body.rotation.y = lerp_angle(job_yaw0, job_yaw, k)
	if job_rise >= 0.0:
		job_rise += delta
		if job_rise >= ANIM_END - RISE_A:
			h.state = "walk"
			job = null
		return
	if job == null or not is_instance_valid(job) or not job.dead or float(job.meat) <= 0.0:
		job_rise = 0.0
		return
	if h.move_vec.length() > 0.6 and job_t > 0.4:
		main._say("Разделка прервана")
		job_rise = 0.0
		return
	if job_t < KNEEL_T:
		return
	var e: Dictionary = carc[job]
	var p0: float = e["p"]
	var p: float = minf(1.0, p0 + delta / _work_time(job))
	e["p"] = p
	hand_blood = minf(1.0, hand_blood + delta * 0.08)
	body_blood = minf(0.45, body_blood + delta * 0.01)
	var cen := body_center(job)
	var L: float = float(job.parts.get("L", 0.6))
	_splat_t -= delta
	if _splat_t <= 0.0:
		_splat_t = rng.randf_range(0.5, 1.0)
		var a := rng.randf() * TAU
		splat(cen + Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.1, L * 0.5), rng.randf_range(0.06, 0.16), DROP if rng.randf() < 0.6 else SMEAR, 30.0)
	if p0 <= 0.0:
		pool_at(cen, clampf(L * 0.25, 0.12, 0.6), 30.0)
	# 0–0.5: снимает шкуру (туша меняется от брюха к хребту), 0.5: шкура расстелена рядом,
	# 0.5–1: режет мясо — куски ложатся на шкуру
	if (e["mats"] as Array).is_empty():
		e["mats"] = HM.skin_carcass(job)
	var sk := clampf(p / 0.5, 0.0, 1.0)
	for m: ShaderMaterial in e["mats"]:
		m.set_shader_parameter("skinned", sk)
	var pl: Dictionary = e.get("pile", {})
	if p >= 0.5 and pl.is_empty():
		pl = _lay_hide(job)
		e["pile"] = pl
	if not pl.is_empty():
		var want := int(floor((p - 0.5) / 0.5 * float(meat_count(job)) + 0.001))
		var have: int = int(pl.get("cut", 0))
		while have < want:
			have += 1
			_add_meat(pl, 1)
		pl["cut"] = have
	if p >= 1.0:
		e["done"] = true
		# остатки: мясо на костях — ещё долго кормит падальщиков
		job.meat = maxf(20.0, float(e["meat0"]) * 0.35)
		e["meat0"] = float(job.meat)
		main.animals.add_scent(cen, 1.5, 600.0)
		main._say("Разделано: мясо %d, шкура" % meat_count(job))
		job_rise = 0.0

## Время в Fixing_Kneeling для кадра работы (hero.gd _animate_model).
func kneel_time() -> float:
	if job_rise >= 0.0:
		return minf(ANIM_END - 0.01, RISE_A + job_rise)
	if job_t < KNEEL_T:
		return job_t
	# пила: руки ходят туда-обратно по петле работы
	var u := fmod(job_t - KNEEL_T, (WORK_B - WORK_A) * 2.0)
	var w := u if u < WORK_B - WORK_A else (WORK_B - WORK_A) * 2.0 - u
	return lerpf(KNEEL_T, WORK_A + w, smoothstep(0.0, 0.4, job_t - KNEEL_T))

func _tick_carcasses() -> void:
	var now := now_h()
	for a: Node3D in carc.keys():
		if not is_instance_valid(a):
			carc.erase(a)
			continue
		var e: Dictionary = carc[a]
		if not a.dead:
			carc.erase(a)
			continue
		if bool(e["done"]) and not (e["mats"] as Array).is_empty():
			var dry := clampf(1.0 - float(a.meat) / maxf(float(e["meat0"]), 1.0), 0.0, 1.0)
			for m: ShaderMaterial in e["mats"]:
				m.set_shader_parameter("dry", dry)
		if float(a.meat) <= 0.0 and not bool(e["bones"]):
			_spawn_bones(a)
			e["bones"] = true
	for i in range(bone_sets.size() - 1, -1, -1):
		if float(bone_sets[i][1]) < now:
			(bone_sets[i][0] as Node3D).queue_free()
			bone_sets.remove_at(i)

func _spawn_bones(a: Node3D) -> void:
	if a.kind in SMALL:
		return
	var L: float = float(a.parts.get("L", 0.6))
	var c := body_center(a)
	var n := MeshInstance3D.new()
	n.mesh = HM.bones_mesh(L, rng.randi(), a.kind in ["deer", "moose"] and bool(a.male))
	add_child(n)
	var yaw: float = float(a.heading) + PI * 0.5
	var ny := _normal(c.x, c.z)
	var bs := Basis(Vector3.UP, yaw)
	var tilt := Quaternion(Vector3.UP, ny)
	n.transform = Transform3D(Basis(tilt) * bs, Vector3(c.x, surface_y(c.x, c.z) - 0.01, c.z))
	n.visibility_range_end = 70.0
	bone_sets.append([n, now_h() + 72.0])
	while bone_sets.size() > 10:
		(bone_sets[0][0] as Node3D).queue_free()
		bone_sets.remove_at(0)

# ---------- вещи на земле: шкура, мясо, тушки ----------

func _ground_fn(org: Vector3, b: Basis) -> Callable:
	return func(x: float, z: float) -> float:
		var w: Vector3 = org + b * Vector3(x, 0, z)
		return surface_y(w.x, w.z) - org.y

## Расстелить шкуру рядом с тушей (справа или слева от героя, где свободно).
func _lay_hide(a: Node3D) -> Dictionary:
	var L: float = clampf(float(a.parts.get("L", 0.8)) * 0.85, 0.45, 2.2)
	var f := Vector3(sin(job_yaw), 0, cos(job_yaw))
	var rt := Vector3(f.z, 0, -f.x)
	var pos := job_to + rt * (0.35 + L * 0.5)
	for side in [1.0, -1.0, 0.0]:
		var q: Vector3 = job_to + (rt * side * (0.35 + L * 0.5) if side != 0.0 else -f * (0.4 + L * 0.6))
		if not main.blocked(q.x, q.z, L * 0.35):
			pos = q
			break
	pos.y = surface_y(pos.x, pos.z)
	var cols := _fur_cols(a)
	var pl := _new_pile(pos, job_yaw + rng.randf_range(-0.25, 0.25))
	_add_hide(pl, L, cols[0], cols[1])
	return pl

func _fur_cols(a: Node3D) -> Array:
	var sp: Dictionary = AM.SPECIES.get(a.kind, {})
	var c: Color = sp.get("col", Color(0.45, 0.33, 0.22))
	var b: Color = sp.get("belly", c.lightened(0.3))
	match a.kind:
		"moose":
			c = Color(0.28, 0.21, 0.15)
			b = Color(0.45, 0.38, 0.3)
		"lynx":
			c = Color(0.62, 0.52, 0.4)
			b = Color(0.85, 0.8, 0.72)
		"wolverine":
			c = Color(0.2, 0.14, 0.1)
			b = Color(0.55, 0.42, 0.28)
		"muskdeer":
			c = Color(0.38, 0.3, 0.22)
			b = Color(0.55, 0.47, 0.37)
	if bool(a.winter_skin) and sp.has("winter"):
		c = sp["winter"]
	# распластанная шкура видна сверху целиком: темнее модели не делать
	var k := clampf(0.42 / maxf(c.get_luminance(), 0.05), 1.0, 1.6)
	return [Color(c.r * k, c.g * k, c.b * k), b]

func _new_pile(pos: Vector3, yaw: float) -> Dictionary:
	var node := Node3D.new()
	add_child(node)
	node.position = pos
	node.rotation.y = yaw
	var pl := {"pos": pos, "items": {}, "node": node, "hide": null, "meats": [], "r": 0.5, "cut": 0, "L": 0.0, "corpse": false}
	piles.append(pl)
	return pl

func _add_hide(pl: Dictionary, L: float, col: Color, belly: Color) -> void:
	var node: Node3D = pl["node"]
	var mi := MeshInstance3D.new()
	mi.mesh = HM.hide_mesh(L, col, belly, rng.randi(), _ground_fn(node.position, node.basis))
	mi.visibility_range_end = 70.0
	node.add_child(mi)
	pl["hide"] = mi
	pl["L"] = L
	pl["r"] = maxf(float(pl["r"]), L * 0.5)
	var it: Dictionary = pl["items"]
	it["hide"] = int(it.get("hide", 0)) + 1

## Кусок мяса на кучу: на шкуре — по её середине, иначе — на земле рядом.
func _add_meat(pl: Dictionary, n: int, id: String = "meat_raw") -> void:
	var node: Node3D = pl["node"]
	var L: float = pl["L"]
	for k in n:
		var i: int = (pl["meats"] as Array).size()
		var mi := MeshInstance3D.new()
		mi.mesh = HM.meat_mesh(rng.randi(), id == "meat_cooked")
		mi.visibility_range_end = 50.0
		var lx: float
		var lz: float
		if L > 0.0:
			lx = (float(i % 2) - 0.5) * L * 0.2 + rng.randf_range(-0.02, 0.02)
			lz = (0.22 - float(i / 2) * 0.11) * L + rng.randf_range(-0.02, 0.02)
		else:
			var a := float(i) * 2.4
			lx = cos(a) * 0.09 * sqrt(float(i))
			lz = sin(a) * 0.09 * sqrt(float(i))
		var w: Vector3 = node.position + node.basis * Vector3(lx, 0, lz)
		var y := surface_y(w.x, w.z) - node.position.y + (0.012 + 0.008 + 0.006 * L + 0.006 * L if L > 0.0 else -0.004)
		mi.transform = Transform3D(Basis(Vector3.UP, rng.randf_range(-0.5, 0.5) + (PI * 0.5 if L > 0.0 else rng.randf() * TAU)), Vector3(lx, y, lz))
		node.add_child(mi)
		(pl["meats"] as Array).append([mi, id])
		var it: Dictionary = pl["items"]
		it[id] = int(it.get(id, 0)) + 1
	pl["r"] = maxf(float(pl["r"]), 0.35)

func _pile_near(p: Vector3) -> Dictionary:
	for pl: Dictionary in piles:
		var q: Vector3 = pl["pos"]
		if Vector2(q.x - p.x, q.z - p.z).length() < float(pl["r"]) + 0.8 and not (pl["items"] as Dictionary).is_empty():
			# пока на шкуре режут мясо — не забирать
			if job != null and main.hero.state == "butcher":
				continue
			return pl
	return {}

func _pile_text(pl: Dictionary) -> String:
	var parts := PackedStringArray()
	var it: Dictionary = pl["items"]
	for id: String in it.keys():
		var n: int = it[id]
		parts.append(IT.name_of(id).to_lower() + (" ×%d" % n if n > 1 else ""))
	return ", ".join(parts)

## Забрать из кучи в короб, сколько влезет.
func _take_pile(pl: Dictionary) -> void:
	if pl.is_empty():
		return
	var it: Dictionary = pl["items"]
	var got := {}
	var full := false
	for id: String in it.keys():
		while int(it[id]) > 0:
			if main.inventory != null and not main.inventory.can_add(id):
				full = true
				break
			main.inv[id] = int(main.inv.get(id, 0)) + 1
			it[id] = int(it[id]) - 1
			got[id] = int(got.get(id, 0)) + 1
			_remove_model(pl, id)
		if int(it[id]) <= 0:
			it.erase(id)
	var msg := PackedStringArray()
	for id: String in got.keys():
		msg.append(IT.name_of(id).to_lower() + (" ×%d" % int(got[id]) if int(got[id]) > 1 else ""))
	if msg.is_empty():
		main._say("Короб полон")
	else:
		main._say("В короб: " + ", ".join(msg) + (" — больше не влезает" if full else ""))
	main.hero.land_t = 0.55
	main.hero.land_k = 0.85
	if it.is_empty():
		(pl["node"] as Node3D).queue_free()
		piles.erase(pl)

func _remove_model(pl: Dictionary, id: String) -> void:
	if id == "hide" and pl["hide"] != null:
		(pl["hide"] as Node3D).queue_free()
		pl["hide"] = null
		# мясо со шкуры — на землю
		for m: Array in pl["meats"]:
			var mi: MeshInstance3D = m[0]
			var w: Vector3 = (pl["node"] as Node3D).to_global(mi.position)
			mi.position.y = surface_y(w.x, w.z) - (pl["node"] as Node3D).position.y - 0.004
		pl["L"] = 0.0
		return
	var ms: Array = pl["meats"]
	for i in range(ms.size() - 1, -1, -1):
		if String(ms[i][1]) == id:
			(ms[i][0] as Node3D).queue_free()
			ms.remove_at(i)
			return
	# --- core: модели прочих вещей ---
	var gens: Array = pl.get("gen", [])
	for i in range(gens.size() - 1, -1, -1):
		if String(gens[i][1]) == id:
			(gens[i][0] as Node3D).queue_free()
			gens.remove_at(i)
			return
	# --- /core ---
	var sm: Variant = pl.get("small")
	if id == "carcass_small" and sm != null:
		(sm as Node3D).queue_free()
		pl.erase("small")

## Выложить вещь на землю (из инвентаря): шкура, мясо, тушка — с моделью; true — выложено.
## Рядом с другой кучей — в неё.
func drop_item(id: String, pos: Vector3) -> bool:
	# --- core: прочие вещи (утварь, глина, доски…) ложатся моделью из item_models.gd ---
	if not (id in ["hide", "fur", "meat_raw", "meat_cooked", "carcass_small"]):
		return _drop_generic(id, pos)
	# --- /core ---
	var pl := {}
	for p2: Dictionary in piles:
		if (p2["pos"] as Vector3).distance_to(pos) < 1.0:
			pl = p2
			break
	if pl.is_empty():
		pos.y = surface_y(pos.x, pos.z)
		pl = _new_pile(pos, rng.randf() * TAU)
	match id:
		"hide", "fur":
			if pl["hide"] == null:
				_add_hide(pl, 0.9, Color(0.5, 0.36, 0.24), Color(0.8, 0.72, 0.6))
				if id == "fur":
					var it: Dictionary = pl["items"]
					it.erase("hide")
					it["fur"] = int(it.get("fur", 0)) + 1
			else:
				var it2: Dictionary = pl["items"]
				it2[id] = int(it2.get(id, 0)) + 1
		"meat_raw", "meat_cooked":
			_add_meat(pl, 1, id)
		"carcass_small":
			if not pl.has("small"):
				var n := Node3D.new()
				(pl["node"] as Node3D).add_child(n)
				AM.build(n, "hare", 1.0, true, false)
				n.rotation = Vector3(0, rng.randf() * TAU, PI * 0.5)
				n.position.y = 0.07
				pl["small"] = n
			var it3: Dictionary = pl["items"]
			it3[id] = int(it3.get(id, 0)) + 1
	return true

# ---------- герой: кровь, повязка ----------

## Удар зверя по герою (main.hurt): брызги, кровь на одежде, работа прерывается.
func on_hero_hurt(dmg: float, part: String, from: Vector3) -> void:
	pressed = false
	cancel()
	var p: Vector3 = main.hero.position
	var away: Vector3 = p - from
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
	for i in 3 + int(dmg * 10.0):
		splat(p + away * rng.randf_range(0.0, 1.0) + Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4)), rng.randf_range(0.04, 0.1), DROP, 20.0)
	if dmg > 0.15:
		splat(p, 0.35, POOL, 20.0)
	body_blood = minf(1.0, body_blood + dmg * 2.0)
	if part == "рука":
		hand_blood = minf(1.0, hand_blood + 0.6)

## Перевязать (main.bandage): повязка из короба останавливает кровь; без неё можно только
## зажать рану — кровь слабее вдвое, один раз на рану. true — главное сделано здесь.
func bandage() -> bool:
	if int(main.inv.get("bandage", 0)) > 0:
		main.inv["bandage"] = int(main.inv["bandage"]) - 1
		if int(main.inv["bandage"]) <= 0:
			main.inv.erase("bandage")
		return false
	if pressed:
		main._say("Нужна повязка (лыко ×2)")
		return true
	pressed = true
	main.bleed = float(main.bleed) * 0.5
	main._say("Нет повязки — зажал рану")
	return true

func _tick_hero(delta: float) -> void:
	var h: Node3D = main.hero
	var b: float = main.bleed
	if b > 0.02 and h.state != "dead":
		if _hero_last == Vector3.INF:
			_hero_last = h.position
		var d := Vector2(h.position.x - _hero_last.x, h.position.z - _hero_last.z).length()
		if d >= _hero_gap:
			_hero_last = h.position
			_hero_gap = rng.randf_range(0.8, 2.4) / clampf(b * 2.0, 0.4, 2.0)
			_hero_still = 0.0
			splat(h.position + Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2)), rng.randf_range(0.09, 0.14) + 0.06 * b, DROP, 16.0)
		else:
			_hero_still += delta
			if _hero_still > 4.0 / clampf(b * 3.0, 0.5, 3.0):
				_hero_still = 0.0
				splat(h.position + Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25)), rng.randf_range(0.04, 0.08), DROP, 16.0)
		body_blood = maxf(body_blood, minf(0.6, b))
	else:
		_hero_last = Vector3.INF
	# смывается в воде и под дождём, понемногу стирается само
	var wash := 0.0004
	if float(h.swimb) > 0.3 or float(h.depth) > 0.5:
		wash = 0.15
	elif main.weather != null and float(main.weather.precip) > 0.3:
		wash = 0.004
	hand_blood = maxf(0.0, hand_blood - wash * delta * (0.0 if h.state == "butcher" else 1.0))
	body_blood = maxf(0.0, body_blood - wash * delta * 0.7)

func _tick_scent() -> void:
	var an: Node = main.animals
	var hp_: Vector3 = main.hero.position
	if float(main.bleed) > 0.02:
		an.add_scent(hp_, 0.5 + float(main.bleed), 90.0)
	var meat := int(main.inv.get("meat_raw", 0)) + 2 * int(main.inv.get("carcass_small", 0))
	if meat > 0:
		an.add_scent(hp_, minf(1.0, 0.2 + 0.07 * meat), 30.0)
	if hand_blood > 0.3:
		an.add_scent(hp_, 0.25, 20.0)
	for pl: Dictionary in piles:
		if int((pl["items"] as Dictionary).get("meat_raw", 0)) > 0:
			an.add_scent(pl["pos"], 0.7, 30.0)
	if job != null and is_instance_valid(job):
		an.add_scent(job.position, 1.3, 300.0)

## Кровь на руках и куртке: слои поверх модели героя из той же сетки (как одежда в
## hero_skin.gd), с теми же костями; рисунок пятен — шум по вершинам.
func _build_overlays(sk: Skeleton3D) -> void:
	var body: MeshInstance3D = sk.find_child("SuperHero_Male", false, false)
	if body == null:
		return
	var sh: Shader = load("res://shaders/blood_layer.gdshader")
	var jacket: MeshInstance3D = null
	for c in sk.get_children():
		if c is MeshInstance3D and c != body and (c as MeshInstance3D).skin != null:
			var arr := (c as MeshInstance3D).mesh.surface_get_arrays(0)
			var cl: Variant = arr[Mesh.ARRAY_COLOR]
			if cl is PackedColorArray and (cl as PackedColorArray).size() > 0:
				var c0: Color = (cl as PackedColorArray)[0]
				if absf(c0.r - 0.5) < 0.02 and absf(c0.g - 0.41) < 0.02:
					jacket = c
	_overlay(sk, body, "hand", 0.0025, sh)
	if jacket != null:
		_overlay(sk, jacket, "body", 0.004, sh)

func _overlay(sk: Skeleton3D, src: MeshInstance3D, mode: String, off: float, sh: Shader) -> void:
	var mesh: ArrayMesh = src.mesh
	var arr := mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var ws: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var per: int = bones.size() / maxi(vs.size(), 1)
	var skin: Skin = src.skin
	var bname: Array = []
	for i in skin.get_bind_count():
		var nm := String(skin.get_bind_name(i))
		if nm == "":
			nm = sk.get_bone_name(skin.get_bind_bone(i))
		bname.append(nm)
	var nz := FastNoiseLite.new()
	nz.seed = 31
	nz.frequency = 9.0
	var wt := PackedFloat32Array()
	wt.resize(vs.size())
	var cols := PackedColorArray()
	cols.resize(vs.size())
	var nv := PackedVector3Array()
	nv.resize(vs.size())
	for i in vs.size():
		var best := 0
		var bw := -1.0
		for k in per:
			if ws[i * per + k] > bw:
				bw = ws[i * per + k]
				best = bones[i * per + k]
		var b: String = bname[best] if best < bname.size() else ""
		var hand := b.begins_with("hand") or b.begins_with("index") or b.begins_with("middle") or b.begins_with("ring") or b.begins_with("pinky") or b.begins_with("thumb")
		var w := 0.0
		if mode == "hand":
			w = 1.0 if hand else 0.0
		else:
			# куртка: перед и рукава ниже локтя — больше всего
			w = 0.35
			if b.begins_with("lowerarm"):
				w = 0.9
			elif ns[i].z > 0.3 and vs[i].y < 1.35:
				w = 0.8
		wt[i] = w
		var nval := nz.get_noise_3dv(vs[i]) * 0.5 + 0.5
		cols[i] = Color(nval, w, 0, 1)
		nv[i] = vs[i] + ns[i] * off
	var tris := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		if wt[idx[t]] > 0.0 and wt[idx[t + 1]] > 0.0 and wt[idx[t + 2]] > 0.0:
			tris.append(idx[t]); tris.append(idx[t + 1]); tris.append(idx[t + 2])
	if tris.is_empty():
		return
	var a2 := arr.duplicate()
	a2[Mesh.ARRAY_VERTEX] = nv
	a2[Mesh.ARRAY_COLOR] = cols
	a2[Mesh.ARRAY_INDEX] = tris
	a2[Mesh.ARRAY_TANGENT] = null
	var fmt := mesh.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	var m2 := ArrayMesh.new()
	m2.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a2, [], {}, fmt)
	var mi := MeshInstance3D.new()
	mi.mesh = m2
	mi.skin = skin
	sk.add_child(mi)
	mi.skeleton = mi.get_path_to(sk)
	var m := ShaderMaterial.new()
	m.shader = sh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	overlays.append([mi, m, mode])

func _tick_overlays() -> void:
	for o: Array in overlays:
		var amt: float = hand_blood if String(o[2]) == "hand" else body_blood
		(o[0] as MeshInstance3D).visible = amt > 0.02
		(o[1] as ShaderMaterial).set_shader_parameter("amount", amt)

## Тушка на поясе героя, пока в коробе есть хоть одна.
func _update_carried() -> void:
	var want := int(main.inv.get("carcass_small", 0)) > 0
	if want == (carried != null):
		return
	if not want:
		carried.queue_free()
		carried = null
		return
	var sk: Skeleton3D = main.hero.get("m_sk")
	if sk == null:
		return
	var ba := BoneAttachment3D.new()
	ba.bone_name = "pelvis"
	sk.add_child(ba)
	var holder := Node3D.new()
	ba.add_child(holder)
	# заяц висит на поясе вниз головой у левого бедра (подвязан за задние лапы)
	var rest := sk.get_bone_global_rest(sk.find_bone("pelvis"))
	var want_t := Transform3D(Basis(Vector3.RIGHT, PI * 0.5) * Basis(Vector3.UP, PI * 0.5), Vector3(0.22, rest.origin.y + 0.05, 0.02))
	holder.transform = rest.affine_inverse() * want_t
	AM.build(holder, "hare", 0.85, true, false)
	carried = ba

# ---------- обновление ----------

func _process(delta: float) -> void:
	if main == null or main.hero == null or blood == null:
		return
	blood.set_time(_clock())
	_tick_wounds(delta)
	_tick_hero(delta)
	_scent_t -= delta
	if _scent_t <= 0.0:
		_scent_t = 2.0
		_tick_scent()
	_carc_t -= delta
	if _carc_t <= 0.0:
		_carc_t = 0.5
		_tick_carcasses()
		_tick_overlays()
		_update_carried()
	_refresh_blood()
	if debug:
		_debug_keys()
	if _test != "":
		_run_test(delta)

## По кругу: пятна, которые занесло снегом, — убрать; при таянии — опустить на землю.
func _refresh_blood() -> void:
	var now := _clock()
	for k in 24:
		_refresh_i = (_refresh_i + 1) % BloodMM.CAP
		var inf: Variant = blood.info[_refresh_i]
		if inf == null:
			continue
		var a: Array = inf
		if float(a[4]) < now:
			blood.info[_refresh_i] = null
			continue
		var x: float = a[0]
		var z: float = a[1]
		var sd := snow_at(x, z)
		if sd > float(a[2]) + 0.025:
			blood.hide_one(_refresh_i)
			continue
		if sd < float(a[2]) - 0.01:
			var t := blood.mm.get_instance_transform(_refresh_i)
			t.origin.y = surface_y(x, z)
			blood.mm.set_instance_transform(_refresh_i, t)
			a[2] = sd

# ---------- отладка (HUNT_DEBUG=1): K — ранить ближнего зверя, J — убить ----------

func _debug_keys() -> void:
	for key: int in [KEY_K, KEY_J]:
		var down := Input.is_physical_key_pressed(key)
		if down and not bool(_keys.get(key, false)):
			var a := _nearest_animal(30.0)
			if a != null:
				hit_animal(a, 0.45 if key == KEY_K else 9.0, main.hero.position)
				main._say("Отладка: %s — %s" % [String(RU.get(a.kind, a.kind)), "ранен" if key == KEY_K else "убит"])
		_keys[key] = down

func _nearest_animal(r: float) -> Node3D:
	var best: Node3D = null
	var bd := r
	for a: Node3D in main.animals.list:
		if a.dead or a.state == "inlodge" or a.state == "sleep":
			continue
		var d: float = a.position.distance_to(main.hero.position)
		if d < bd:
			bd = d
			best = a
	return best

# ---------- проверка без экрана (HUNT_TEST=1) ----------

var _test := OS.get_environment("HUNT_TEST")
var _tt := 0.0
var _ts := 0
var _ta: Node3D = null

func _tlog(s: String) -> void:
	print("HUNT_TEST ", s)

func _place(a: Node3D, p: Vector3) -> void:
	a.position = Vector3(p.x, main.ground_at(p.x, p.z), p.z)
	a.home = a.position
	a.far = false

func _run_test(delta: float) -> void:
	_tt += delta
	var h: Node3D = main.hero
	match _ts:
		0:
			if _tt < 1.0:
				return
			Engine.time_scale = 4.0
			# косуля рядом с героем: ранить — должна убежать, оставляя кровь
			for a: Node3D in main.animals.list:
				if a.kind == "roe" and not a.dead and a.scale_k > 0.8:
					_ta = a
					break
			_place(_ta, h.position + Vector3(5, 0, 0))
			hit_animal(_ta, 0.4, h.position)
			_tlog("ранена %s state=%s hp=%.2f bleed=%.2f пятен=%d" % [_ta.kind, _ta.state, float(hp[_ta]), float(wounds[_ta]["bleed"]), blood.used])
			_ts = 1
			_tt = 0.0
		1:
			if _tt < 6.0:
				return
			_tlog("через 6 с: state=%s ушла на %.1f м, hp=%.2f, пятен=%d, запахов=%d" % [_ta.state, _ta.position.distance_to(h.position), float(hp.get(_ta, 0.0)), blood.used, main.animals.scents.size()])
			hit_animal(_ta, 5.0, h.position)
			_place(_ta, h.position + Vector3(1.2, 0, 0.0))
			_tlog("убита: dead=%s meat=%.0f туша учтена=%s ярлык=«%s»" % [_ta.dead, float(_ta.meat), carc.has(_ta), action_label()])
			_ta.position = h.position + Vector3(1.2, 0, 0)
			_ta.position.y = main.ground_at(_ta.position.x, _ta.position.z) + float(_ta.parts.get("H", 0.5)) * 0.22
			_ts = 2
			_tt = 0.0
		2:
			if _tt < 0.5:
				return
			var lbl: String = h.action_label()
			_tlog("ярлык героя: «%s», нож=%s" % [lbl, has_knife()])
			h.do_action()
			_tlog("состояние героя: %s" % h.state)
			_ts = 3
			_tt = 0.0
		3:
			if h.state == "butcher":
				if _tt > 40.0:
					_tlog("ОШИБКА: разделка не закончилась")
					_ts = 9
				return
			var e: Dictionary = carc.get(_ta, {})
			_tlog("разделка: p=%.2f done=%s остаток мяса=%.0f куч=%d руки=%.2f" % [float(e.get("p", -1.0)), e.get("done", false), float(_ta.meat), piles.size(), hand_blood])
			if not piles.is_empty():
				var pl: Dictionary = piles[0]
				_tlog("куча: %s" % str(pl["items"]))
				h.position = Vector3((pl["pos"] as Vector3).x, h.position.y, (pl["pos"] as Vector3).z)
			_ts = 4
			_tt = 0.0
		4:
			if _tt < 0.3:
				return
			var lbl2: String = h.action_label()
			h.do_action()
			_tlog("«%s» → короб: %s" % [lbl2, str(main.inv)])
			# объели остатки — кости
			_ta.meat = 0.0
			_ts = 5
			_tt = 0.0
		5:
			if _tt < 1.5:
				return
			_tlog("кости: %d" % bone_sets.size())
			# заяц: убить и подобрать
			var hr: Node3D = null
			for a: Node3D in main.animals.list:
				if a.kind == "hare" and not a.dead:
					hr = a
					break
			_place(hr, h.position + Vector3(0.6, 0, 0.6))
			hit_animal(hr, 3.0, h.position)
			h.position.x += 0.0
			_ta = hr
			_ts = 6
			_tt = 0.0
		6:
			if _tt < 0.5:
				return
			var lbl3: String = h.action_label()
			h.do_action()
			_tlog("«%s» → тушек: %d, на поясе: %s" % [lbl3, int(main.inv.get("carcass_small", 0)), carried != null])
			# волк рядом: запах свежей крови — должен пойти проверить
			for a: Node3D in main.animals.list:
				if a.kind == "wolf" and not a.dead:
					_ta = a
					break
			_place(_ta, h.position + Vector3(40, 0, 25))
			_ta.sated = 0.0
			_ta.state = "wander"
			_ta.state_t = 30.0
			main.animals.add_scent(h.position + Vector3(10, 0, 0), 1.5, 120.0)
			_ts = 7
			_tt = 0.0
		7:
			if _ta.state == "investigate" or _tt > 30.0:
				_tlog("волк: state=%s (ждали investigate), до запаха %.0f м" % [_ta.state, _ta.position.distance_to(h.position + Vector3(10, 0, 0))])
				# ранить героя: кровь, повязка
				main.hurt(0.12, h.position + Vector3(1, 0, 0), "wolf")
				_ts = 8
				_tt = 0.0
		8:
			if _tt < 3.0:
				return
			var before: float = main.bleed
			var nb: int = int(main.inv.get("bandage", 0))
			main.bandage()
			_tlog("герой кровил %.2f, пятен %d, куртка %.2f; повязка: %d→%d, кровь %.2f" % [before, blood.used, body_blood, nb, int(main.inv.get("bandage", 0)), float(main.bleed)])
			var ok := drop_item("meat_raw", h.position + Vector3(0, 0, 1.5)) and drop_item("hide", h.position + Vector3(0, 0, 1.6))
			_tlog("выложено: %s, куч %d" % [ok, piles.size()])
			_ts = 9
		9:
			Engine.time_scale = 1.0
			_tlog("готово")
			_ts = 10

# --- core: вещь на землю моделью (item_models.gd) ---
var _imodels = null
func _drop_generic(id: String, pos: Vector3) -> bool:
	if not IT.DEF.has(id) or id == "log":
		return false
	var pl := {}
	for p2: Dictionary in piles:
		if (p2["pos"] as Vector3).distance_to(pos) < 1.0:
			pl = p2
			break
	if pl.is_empty():
		pos.y = surface_y(pos.x, pos.z)
		pl = _new_pile(pos, rng.randf() * TAU)
	if _imodels == null:
		_imodels = preload("res://scripts/item_models.gd").new(main.pv)
	var gens: Array = pl.get("gen", [])
	pl["gen"] = gens
	var it: Dictionary = pl["items"]
	it[id] = int(it.get(id, 0)) + 1
	# одна модель на вид и не больше 6 моделей в куче
	var shown := false
	for g: Array in gens:
		if String(g[1]) == id:
			shown = true
	if not shown and gens.size() < 6:
		var n: Node3D = _imodels.make(id)
		var k := gens.size()
		n.position = Vector3(cos(k * 2.4) * 0.18 * sqrt(float(k)), 0.0, sin(k * 2.4) * 0.18 * sqrt(float(k)))
		n.rotation.y = rng.randf() * TAU
		(pl["node"] as Node3D).add_child(n)
		gens.append([n, id])
	pl["r"] = maxf(float(pl["r"]), 0.4)
	return true

# --- core: сохранение (save.gd, раздел «hunt»): вещи на земле (кучи) и разделка туш ---
func to_save() -> Dictionary:
	var SV = preload("res://scripts/save.gd")
	var ps: Array = []
	for pl: Dictionary in piles:
		if not (pl["items"] as Dictionary).is_empty():
			ps.append({"pos": SV.enc(pl["pos"]), "items": (pl["items"] as Dictionary).duplicate(), "corpse": bool(pl.get("corpse", false)), "yaw": float((pl["node"] as Node3D).rotation.y)})
	var cs: Array = []
	if main.animals != null:
		for a in carc.keys():
			if is_instance_valid(a):
				var i: int = main.animals.list.find(a)
				if i >= 0:
					cs.append({"i": i, "p": float(carc[a]["p"]), "done": bool(carc[a]["done"])})
	return {"piles": ps, "carc": cs, "traveler_seed": traveler_seed}

func from_save(d: Dictionary) -> void:
	var SV = preload("res://scripts/save.gd")
	traveler_seed = int(d.get("traveler_seed", main.get("map_seed")))
	for pl: Dictionary in piles:
		(pl["node"] as Node3D).queue_free()
	piles.clear()
	for e: Dictionary in d.get("piles", []):
		var pos: Vector3 = SV.dec(e["pos"])
		var it := SV.int_dict(e.get("items", {}))
		if bool(e.get("corpse", false)):
			var rounds := int(it.get("rifle_round", 0))
			_create_traveler_pile(pos, float(e.get("yaw", 0.0)), rounds, int(it.get("rifle", 0)) > 0)
			it.erase("rifle_round")
			it.erase("rifle")
		for id: String in it:
			for k in mini(int(it[id]), 40):
				drop_item(id, pos)
	if main.animals != null:
		for e: Dictionary in d.get("carc", []):
			var i := int(e["i"])
			if i >= 0 and i < main.animals.list.size():
				var a = main.animals.list[i]
				if carc.has(a):
					carc[a]["p"] = float(e["p"])
					carc[a]["done"] = bool(e["done"])
# --- /core ---
