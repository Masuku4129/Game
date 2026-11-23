extends Node
## Инструменты героя.
##
## Состояние — одно и только здесь: рука (held), пояс (belt, до двух мест: нож, топор),
## спина (back: лук), брёвна на плече (logs, при held == "log") и связка на верёвке (bundle).
## Всё, что не в руке, не на поясе и не за спиной, лежит в коробе (main.inv). Кнопки HUD и
## модели берут положение вещи только из place_of(id); достать/убрать меняют состояние сразу,
## а движение руки к поясу — лишь вид (tr_*), его можно перебить новым нажатием.
##
## API: toggle(id) — кнопка пояса; draw(id) / holster() / to_belt(id) / to_pack(id) / give_long(id);
## place_of(id) → "hand" | "belt" | "back" | "pack" | ""; check() → "" или описание рассогласования.
## Удары: attack() (копьё — колющий, топор — рубящий, нож — режущий; урон через combat.gd → hunt).
## Прицел: aim_begin("spear" | "bow"), aim_release(скорость), aim_cancel() — ведёт combat.gd.
## Брёвна: на плечо до двух (logs), верёвкой — до восьми в связку (log_bundle.gd), волоком.
## Хват — пальцы сжаты вокруг рукояти, кисть по оси рукояти; копьё и лопата — двумя руками
## (двухзвенная ИК, как у короба в hero.gd); лук — в левой руке, тетива — правой.

const IT = preload("res://scripts/items.gd")
const TM = preload("res://scripts/tool_models.gd")
const SK = preload("res://scripts/skin.gd")
const BUNDLE = preload("res://scripts/log_bundle.gd")
const BELT_OK := ["knife", "axe"]
const BELT_MAX := 2
const BACK_OK := ["bow"]
const LONG := ["spear", "shovel"]
const CHOP_HIT := 0.18        # доля цикла TreeChopping, где топор бьёт
const THROW_REL := 0.31       # момент выпуска копья в OverhandThrow, с
const THROW_COCK := 0.24      # кадр OverhandThrow, где копьё отведено назад (прицел)
const TR_DUR := 0.5           # достать/убрать: рука к поясу и обратно (только вид)
const LOGS_MAX := 2
const BUNDLE_MAX := 8
## Удары: длительность, окно попадания (доли), урон (доля жизни косули), досягаемость, отрезки клипов UAL
## [клип, время от, время до, доля от, доля до]: замах медленнее, удар быстро, затем проводка.
const MELEE := {
	"spear": {"dur": 0.8, "h0": 0.42, "h1": 0.6, "dmg": 0.6, "reach": 2.2, "tip": 1.1},
	"axe": {"dur": 1.0, "h0": 0.3, "h1": 0.5, "dmg": 0.95, "reach": 1.35, "tip": 0.42,
		"seg": [["Sword_Regular_A", 0.22, 0.43, 0.0, 0.3], ["Sword_Regular_B", 0.0, 0.27, 0.3, 0.42], ["Sword_Regular_B", 0.27, 0.5, 0.42, 0.72]]},
	"knife": {"dur": 0.55, "h0": 0.25, "h1": 0.5, "dmg": 0.32, "reach": 1.05, "tip": 0.13,
		"seg": [["Punch_Cross", 0.05, 0.22, 0.0, 0.25], ["Punch_Cross", 0.22, 0.4, 0.25, 0.45], ["Punch_Cross", 0.4, 0.75, 0.45, 0.8]]},
}

var hero: Node3D
var sk: Skeleton3D
## Рука. Стройка (structures.deposit_held_log) кладёт бревно присваиванием held = "":
## из двух брёвен на плече при этом снимается одно.
var held := "":
	set(v):
		if held == "log" and v == "" and logs > 1:
			logs -= 1
			return
		logs = maxi(logs, 1) if v == "log" else 0
		held = v
var belt: Array = []          # что висит на поясе: knife, axe
var back := ""                # за спиной: bow
var logs := 0                 # брёвен на плече (1–2), когда held == "log"
var bundle: Node3D = null     # связка брёвен на верёвке (log_bundle.gd)
var nodes := {}               # id → MeshInstance3D (нож, топор)
var hand_att: BoneAttachment3D
var pelvis_att: BoneAttachment3D
var spine_att: BoneAttachment3D
var sheath_n: MeshInstance3D
var long_n := MeshInstance3D.new()
var log_ns: Array = []        # два бревна на плече
var bow_n := Node3D.new()     # лук: плечи + тетива из двух отрезков + наложенная стрела
var bow_m := MeshInstance3D.new()
var str_a := MeshInstance3D.new()
var str_b := MeshInstance3D.new()
var arrow_n := MeshInstance3D.new()
var G_r := Transform3D()      # рукоять в осях кисти (правая)
var G_l := Transform3D()
var belt_xf := {}
var back_xf := Transform3D()  # лук за спиной в осях spine_03
var bones := {}
var curl_r: Array = []        # [кость, ось, угол]
var curl_l: Array = []
var mod: GripMod
var hidden := false           # прятать вещь в руке (короб снят)
# вид перехода «достать/убрать»: вещь, откуда, куда, время
var tr_id := ""
var tr_from := ""
var tr_to := ""
var tr_t := 1.0
var drawk := 0.0              # натяжение тетивы 0..1 (вид)

# действие: chop, trunk, split, cut, hand, attack, throw, shoot, stick, take_long, take_log, drop_log, tie, untie, deposit
var act := ""
var act_t := 0.0
var act_dur := 0.0
var act_data := {}
var act_hits := 0
var _long_xf := Transform3D()

class GripMod extends SkeletonModifier3D:
	var tools: Node
	func _process_modification() -> void:
		tools._modify(get_skeleton())

func setup(h: Node3D, s: Skeleton3D) -> void:
	hero = h
	sk = s
	for bn in ["pelvis", "spine_01", "spine_02", "spine_03", "hand_r", "hand_l", "upperarm_r", "upperarm_l", "lowerarm_r", "lowerarm_l", "clavicle_r", "clavicle_l", "Head", "neck_01"]:
		bones[bn] = sk.find_bone(bn)
	G_r = _grip_of("r")
	G_l = _grip_of("l")
	curl_r = _curl_of("r")
	curl_l = _curl_of("l")
	hand_att = BoneAttachment3D.new()
	hand_att.bone_name = "hand_r"
	sk.add_child(hand_att)
	pelvis_att = BoneAttachment3D.new()
	pelvis_att.bone_name = "pelvis"
	sk.add_child(pelvis_att)
	spine_att = BoneAttachment3D.new()
	spine_att.bone_name = "spine_03"
	sk.add_child(spine_att)
	var pr := sk.get_bone_global_rest(bones["pelvis"])
	var hip := pr.origin.y
	# нож в ножнах на правом бедре: клинок вниз, кромка вперёд
	var kb := Basis(Vector3(0, 0.12, 1).normalized(), Vector3(0.06, -1, 0.1).normalized(), Vector3.ZERO)
	kb.z = kb.x.cross(kb.y).normalized()
	kb.x = kb.y.cross(kb.z).normalized()
	belt_xf["knife"] = pr.affine_inverse() * Transform3D(kb, Vector3(-0.222, hip + 0.115, 0.05))
	# топор на левом боку: петля пояса под клином, топорище вниз-назад вдоль бедра, лезвие назад
	var ay := Vector3(-0.12, 1, 0.2).normalized()
	var ax := (Vector3(0, 0, -1) - ay * ay.dot(Vector3(0, 0, -1))).normalized()
	belt_xf["axe"] = pr.affine_inverse() * Transform3D(Basis(ax, ay, ax.cross(ay)), Vector3(0.235, hip + 0.105 - 0.37, -0.09 - 0.37 * 0.2))
	# лук за спиной: наискось поверх короба, верхний конец над левым плечом, спинка наружу
	var s3 := sk.get_bone_global_rest(bones["spine_03"])
	var by := Vector3(0.55, 1.0, 0.0).normalized()
	var bx := Vector3(0, 0, -1)
	back_xf = s3.affine_inverse() * Transform3D(Basis(bx, by, bx.cross(by)), Vector3(0.0, s3.origin.y - 0.08, -0.36))
	sheath_n = MeshInstance3D.new()
	sheath_n.mesh = TM.sheath()
	pelvis_att.add_child(sheath_n)
	sheath_n.transform = belt_xf["knife"]
	sheath_n.visible = false
	for id in ["knife", "axe"]:
		var mi := MeshInstance3D.new()
		mi.mesh = TM.mesh_of(id)
		mi.visible = false
		pelvis_att.add_child(mi)
		nodes[id] = mi
	sk.add_child(long_n)
	long_n.visible = false
	for i in LOGS_MAX:
		var ln := MeshInstance3D.new()
		ln.mesh = TM.log_mesh(1.25, 0.13, Color(0.42, 0.33, 0.24), 5 + i)
		ln.visible = false
		sk.add_child(ln)
		log_ns.append(ln)
	bow_m.mesh = TM.bow()
	bow_n.add_child(bow_m)
	str_a.mesh = TM.string_seg()
	str_b.mesh = TM.string_seg()
	bow_n.add_child(str_a)
	bow_n.add_child(str_b)
	arrow_n.mesh = TM.arrow()
	arrow_n.visible = false
	bow_n.add_child(arrow_n)
	bow_n.visible = false
	spine_att.add_child(bow_n)
	_set_string(Vector3.INF)
	mod = GripMod.new()
	mod.tools = self
	sk.add_child(mod)

## Хват кисти по позе покоя: ось рукояти — от мизинца к указательному, с наклоном к пальцам
## (рукоять лежит в ладони наискось); центр — в кулаке у ладони.
func _grip_of(side: String) -> Transform3D:
	var hb := sk.find_bone("hand_" + side)
	var hr := sk.get_bone_global_rest(hb)
	var h := hr.origin
	var m := sk.get_bone_global_rest(sk.find_bone("middle_01_" + side)).origin
	var ix := sk.get_bone_global_rest(sk.find_bone("index_01_" + side)).origin
	var pk := sk.get_bone_global_rest(sk.find_bone("pinky_01_" + side)).origin
	var f := (m - h).normalized()
	var a := (ix - pk).normalized()
	var p := Vector3(0, -1, 0)
	var A := (a + f * 0.36).normalized()
	var E := (f - A * f.dot(A)).normalized()
	var c := h + f * 0.088 + p * 0.03 + a * -0.004
	return hr.affine_inverse() * Transform3D(Basis(E, A, E.cross(A)), c)

## Сгиб пальцев в кулак: ось — поперёк пальца к ладони.
func _curl_of(side: String) -> Array:
	var out: Array = []
	var p := Vector3(0, -1, 0)
	for fn in ["index", "middle", "ring", "pinky", "thumb"]:
		for k in [1, 2, 3]:
			var b := sk.find_bone("%s_%02d_%s" % [fn, k, side])
			var nb := sk.find_bone("%s_%02d_%s" % [fn, k + 1, side])
			if b < 0:
				continue
			var g := sk.get_bone_global_rest(b)
			var o := g.origin
			var f: Vector3 = ((sk.get_bone_global_rest(nb).origin if nb >= 0 else o + g.basis.y) - o).normalized()
			var ax := f.cross(p).normalized()
			var ang: float = [1.05, 1.3, 0.85][k - 1]
			if fn == "thumb":
				ang = [0.15, 0.45, 0.5][k - 1]
			out.append([b, (g.basis.orthonormalized().inverse() * ax).normalized(), ang])
	return out

# ---------- состояние: рука, пояс, спина, короб ----------

func _inv(id: String) -> int:
	if hero.main == null:
		return 99
	return int(hero.main.inv.get(id, 0))

func has_tool(id: String) -> bool:
	return equipped_count(id) > 0 or _inv(id) > 0

## Сколько штук вещи занято рукой, поясом и спиной (в вес короба не входят).
func equipped_count(id: String) -> int:
	var n := 0
	if held == id:
		n += 1
	n += belt.count(id)
	if back == id:
		n += 1
	return n

## Где вещь: "hand", "belt", "back", "pack" (в коробе) или "" (нет).
func place_of(id: String) -> String:
	if held == id:
		return "hand"
	if belt.has(id):
		return "belt"
	if back == id:
		return "back"
	if _inv(id) > 0:
		return "pack"
	return ""

## Где вещь видна сейчас: в первой половине перехода — ещё там, откуда её берут.
func vis_place(id: String) -> String:
	if tr_id == id and tr_t < TR_DUR * 0.5:
		return tr_from
	return place_of(id)

func is_long(id: String) -> bool:
	return bool(IT.DEF.get(id, {}).get("hands", false))

## Свободны ли руки для другого дела (короб, бревно).
func hands_busy() -> bool:
	return held != "" or bundle != null

## Проверка согласованности (для теста): "" — всё сходится.
func check() -> String:
	for id: String in ["knife", "axe", "spear", "shovel", "bow"]:
		if equipped_count(id) > _inv(id):
			return "%s: занято %d, есть %d" % [id, equipped_count(id), _inv(id)]
	if belt.size() > BELT_MAX:
		return "на поясе %d" % belt.size()
	for id: String in belt:
		if not BELT_OK.has(id):
			return "%s на поясе" % id
	if back != "" and not BACK_OK.has(back):
		return "%s за спиной" % back
	if held == "log" and (logs < 1 or logs > LOGS_MAX):
		return "брёвен на плече %d" % logs
	if held != "log" and logs != 0:
		return "брёвна без руки"
	if tr_t >= TR_DUR and not hidden:
		for id: String in nodes:
			var mi: MeshInstance3D = nodes[id]
			var pl := place_of(id)
			if mi.visible != (pl == "hand" or pl == "belt"):
				return "%s: модель %s, место %s" % [id, "видна" if mi.visible else "скрыта", pl]
			if pl == "hand" and mi.get_parent() != hand_att:
				return "%s: в руке, а модель не в руке" % id
			if pl == "belt" and mi.get_parent() != pelvis_att:
				return "%s: на поясе, а модель не на поясе" % id
		var bp := place_of("bow")
		if bow_n.visible != (bp == "hand" or bp == "back"):
			return "лук: модель %s, место %s" % ["видна" if bow_n.visible else "скрыта", bp]
	return ""

## Согласовать с инвентарём: вещь, которой больше нет (выбросили, съели), — убрать из рук, с пояса, со спины.
func sync() -> void:
	if hero.main != null:
		if held != "" and held != "log" and _inv(held) < equipped_count(held):
			held = ""
		if back != "" and _inv(back) < equipped_count(back):
			back = ""
		for id in belt.duplicate():
			if _inv(id) < equipped_count(id):
				belt.erase(id)
	_refresh()

func _refresh() -> void:
	hero.held = held
	for id in nodes:
		var mi: MeshInstance3D = nodes[id]
		var pl := vis_place(id)
		var in_hand: bool = pl == "hand" and not hidden
		var on_belt: bool = pl == "belt"
		if in_hand and mi.get_parent() != hand_att:
			mi.reparent(hand_att, false)
		elif on_belt and mi.get_parent() != pelvis_att:
			mi.reparent(pelvis_att, false)
		if in_hand:
			mi.transform = G_r
		elif on_belt:
			mi.transform = belt_xf[id]
		mi.visible = in_hand or on_belt
	sheath_n.visible = belt.has("knife") or held == "knife"
	# лук: в руке — в осях скелета (ставит модификатор), за спиной — на spine_03
	var bp := vis_place("bow")
	if bp == "hand" and not hidden:
		if bow_n.get_parent() != sk:
			bow_n.reparent(sk, false)
		bow_n.visible = true
	elif bp == "back":
		if bow_n.get_parent() != spine_att:
			bow_n.reparent(spine_att, false)
			_set_string(Vector3.INF)
			arrow_n.visible = false
		bow_n.transform = back_xf
		bow_n.visible = true
	else:
		bow_n.visible = false
	if is_long(held) and not hidden:
		if long_n.mesh != TM.mesh_of(held):
			long_n.mesh = TM.mesh_of(held)
		long_n.visible = true
	elif act != "throw":
		long_n.visible = false
	var nl := logs if held == "log" else 0
	if act == "take_log" and float(act_data.get("u", 0.0)) >= 0.45:
		nl = maxi(nl, 1)
	for i in LOGS_MAX:
		(log_ns[i] as MeshInstance3D).visible = i < nl or (i == 0 and act == "drop_log")

func _tr(id: String, from: String, to: String) -> void:
	tr_id = id
	tr_from = from
	tr_to = to
	var reach := from in ["belt", "back"] or to in ["belt", "back"]
	tr_t = 0.0 if reach and not hidden and hero.main != null else TR_DUR

## Убрать вещь из руки на её место: нож и топор — на пояс, лук — за спину, иначе в короб.
func _stow(id: String) -> String:
	held = ""
	if BELT_OK.has(id) and belt.size() < BELT_MAX and _inv(id) > equipped_count(id):
		belt.append(id)
		return "belt"
	if BACK_OK.has(id) and back == "":
		back = id
		return "back"
	return "pack"

func _put_away(id: String) -> void:
	if held == id:
		_stow(id)

## Кнопка пояса: вещь не в руке — достать, в руке — убрать.
func toggle(id: String) -> bool:
	if held == id:
		return holster()
	return draw(id)

## Взять в руку (с пояса, из-за спины или из короба). Копьё в руках при этом втыкается рядом.
func draw(id: String) -> bool:
	if hero.main == null or held == id:
		return held == id
	var from := place_of(id)
	if from == "":
		return false
	if from == "pack" and _inv(id) <= equipped_count(id):
		return false
	if act in ["throw", "shoot", "stick", "take_long", "take_log", "drop_log", "tie", "untie", "deposit"]:
		return false
	if held == "log":
		_say("Сначала положите бревно")
		return false
	if bundle != null:
		_say("Сначала отвяжите связку")
		return false
	_cancel()
	if is_long(held):
		_stick_now()
	elif held != "":
		_stow(held)
	if from == "belt":
		belt.erase(id)
	elif from == "back":
		back = ""
	held = id
	_tr(id, from, "hand")
	_refresh()
	return true

## Старое имя: взять в руку.
func take(id: String) -> bool:
	return draw(id)

## Убрать из руки: нож и топор — на пояс, лук — за спину, иначе в короб; копьё и лопату — воткнуть рядом.
func holster() -> bool:
	if held == "" or held == "log" or act in ["throw", "shoot", "stick", "take_long", "take_log", "drop_log"]:
		return false
	if is_long(held):
		if can_stick():
			stick()
			return true
		return false
	_cancel()
	var id := held
	var to := _stow(id)
	_tr(id, "hand", to)
	if to == "pack":
		_say("%s — в короб" % IT.name_of(id))
	_refresh()
	return true

## Повесить на пояс (из короба или из руки).
func to_belt(id: String) -> bool:
	if not BELT_OK.has(id) or (belt.has(id) and held != id):
		return false
	if held == id:
		if act != "":
			_cancel()
		held = ""
	if belt.size() >= BELT_MAX or _inv(id) <= equipped_count(id):
		_refresh()
		return false
	belt.append(id)
	_refresh()
	return true

## Закинуть лук за спину (из короба или из руки).
func to_back(id: String) -> bool:
	if not BACK_OK.has(id) or (back != "" and back != id):
		return false
	if held == id:
		if act != "":
			_cancel()
		held = ""
	elif _inv(id) <= equipped_count(id):
		return false
	back = id
	_refresh()
	return true

## Убрать с пояса, из руки, со спины в короб.
func to_pack(id: String) -> void:
	if held == id:
		if act != "":
			_cancel()
		held = ""
	belt.erase(id)
	if back == id:
		back = ""
	_refresh()

## Новое копьё (после ремесла, с земли): сразу в руки.
func give_long(id: String) -> void:
	if held == "log":
		_drop_logs_now()
	if bundle != null:
		_say("%s — в короб: руки заняты верёвкой" % IT.name_of(id))
		return
	if act != "":
		_cancel()
	draw(id)

## Освободить руки (перед коробом): нож и топор — на пояс, копьё — воткнуть рядом, бревно — положить.
func free_hands() -> void:
	_cancel()
	if held == "log":
		_drop_logs_now()
	elif is_long(held):
		_stick_now()
	elif held != "":
		_stow(held)
	tr_t = TR_DUR
	_refresh()

func _say(t: String) -> void:
	if hero.main != null:
		hero.main._say(t)

# ---------- действия ----------

func busy() -> bool:
	return act != ""

## Множитель скорости ходьбы: бревно на плече, связка волоком.
func speed_factor() -> float:
	if bundle != null:
		return lerpf(0.75, 0.6, clampf(float(bundle.count() - 1) / float(BUNDLE_MAX - 1), 0.0, 1.0))
	if held == "log":
		return 0.8 if logs <= 1 else 0.65
	if is_long(held):
		return 0.95
	return 1.0

func can_run() -> bool:
	return held != "log" and bundle == null

## Можно ли присесть (с бревном и связкой — нет).
func can_crouch() -> bool:
	return held != "log" and bundle == null

func _start(a: String, dur: float, data: Dictionary = {}) -> void:
	act = a
	act_t = 0.0
	act_dur = dur
	act_data = data
	act_hits = 0

func _cancel() -> void:
	act = ""
	act_data = {}
	drawk = 0.0

func _world() -> Node:
	if hero.main == null:
		return null
	return hero.main.get("tools_world")

func _combat() -> Node:
	if hero.main == null:
		return null
	return hero.main.get("combat")

## Подпись кнопки «Действие» инструментом по обстановке ("" — нечего делать).
func use_label() -> String:
	if act != "" or hero.state != "walk" or hero.swimb > 0.3:
		return ""
	var w := _world()
	if w == null:
		return ""
	var p: Vector3 = hero.position
	var foe := _foe(2.6)
	match held:
		"axe":
			if foe != null:
				return "Ударить"
			var at: Array = _axe_target(w, p)
			if not at.is_empty():
				return String(at[0])
			return "Ударить"
		"knife":
			if foe != null:
				return "Ударить"
			var r: Dictionary = w.knife_target(p)
			if not r.is_empty():
				return String(r["label"])
			return "Ударить"
		"spear":
			return "Ударить"
		"":
			if bundle != null:
				return ""
			var r2: Dictionary = w.hand_target(p)
			if not r2.is_empty():
				return String(r2["label"])
	return ""

## Нажали «Действие» инструментом.
func use() -> void:
	var lbl := use_label()
	if lbl == "":
		return
	if lbl == "Ударить":
		attack()
		return
	var w := _world()
	var p: Vector3 = hero.position
	match held:
		"axe":
			var at: Array = _axe_target(w, p)
			match String(at[1]):
				"young":
					_start("cut", 1.8, {"res": {"type": "young", "rec": at[2], "pos": w.tree_pos(at[2])}, "anim": "TreeChopping", "speed": 1.0})
					_face(w.tree_pos(at[2]))
				"tree":
					_start("chop", 999.0, {"tree": at[2]})
					_face(w.tree_pos(at[2]))
				"trunk":
					_start("trunk", 999.0, {"trunk": at[2]})
					_face(w.trunk_cut_point(at[2]))
				"log":
					_start("split", 999.0, {"log": at[2]})
					_face((at[2] as Node3D).global_position)
		"knife":
			var r: Dictionary = w.knife_target(p)
			if not r.is_empty():
				_start("cut", 1.9, {"res": r, "anim": "Farm_Harvest", "speed": 1.35})
				_face(r["pos"])
		"":
			var r2: Dictionary = w.hand_target(p)
			if not r2.is_empty():
				_start("hand", 2.6, {"res": r2, "anim": "Farm_Harvest", "speed": 0.95})
				_face(r2["pos"])

## Ближайший живой зверь впереди в пределах r (±70°) или null.
func _foe(r: float) -> Node3D:
	if hero.main == null or hero.main.get("animals") == null:
		return null
	var best: Node3D = null
	var bd := r
	var yaw: float = hero.body.rotation.y
	for a: Node3D in hero.main.animals.near(hero.position, r + 1.0):
		if a.dead or not a.visible:
			continue
		var d: Vector3 = a.position - hero.position
		var dl := Vector2(d.x, d.z).length() - float(a.parts.get("L", 1.0)) * 0.3
		if dl > bd or absf(d.y) > 1.6:
			continue
		if absf(wrapf(atan2(d.x, d.z) - yaw, -PI, PI)) > 1.25:
			continue
		bd = dl
		best = a
	return best

## Удар тем, что в руке: копьё — колющий выпад, топор — рубящий сверху наискось, нож — режущий.
func attack() -> bool:
	if not MELEE.has(held) or act != "" or hero.state != "walk":
		return false
	var m: Dictionary = MELEE[held]
	var foe := _foe(float(m["reach"]) + 1.2)
	_start("attack", float(m["dur"]), {"tool": held})
	if foe != null:
		_face(foe.position)
	return true

## Отрезок инструмента в мире: [рукоять, острие].
func tool_seg(id: String) -> Array:
	if id == "spear":
		var g := sk.global_transform * _long_xf
		return [g * Vector3(0, -0.2, 0), g * Vector3(0, 1.1, 0)]
	var gh := sk.get_bone_global_pose(bones["hand_r"])
	var hx := sk.global_transform * Transform3D(gh.basis.orthonormalized(), gh.origin) * Transform3D(G_r.basis.orthonormalized(), G_r.origin * gh.basis.get_scale())
	var tip := Vector3(0.05, 0.42, 0) if id == "axe" else Vector3(0, 0.13, 0)
	return [hx * Vector3(0, 0.0, 0), hx * tip]

## Цель топора: ближайшее из дерева, лежачего ствола и бревна. [подпись, вид, цель] или [].
func _axe_target(w: Node, p: Vector3) -> Array:
	var best: Array = []
	var bd := 1e9
	var t: Array = w.find_tree(p, 1.6)
	if not t.is_empty():
		var tp: Vector3 = w.tree_pos(t)
		bd = Vector2(tp.x - p.x, tp.z - p.z).length() - 0.3
		best = ["Срубить жердь", "young", t] if w.is_young(t) else ["Срубить", "tree", t]
	var tr: Dictionary = w.find_trunk(p, 2.2)
	if not tr.is_empty():
		var cp: Vector3 = w.trunk_cut_point(tr)
		var d := Vector2(cp.x - p.x, cp.z - p.z).length()
		if d < bd:
			bd = d
			best = ["Рубить на брёвна", "trunk", tr]
	var lg: Node3D = w.find_log(p, 1.6)
	if lg != null:
		var lp := lg.global_position
		var d2 := Vector2(lp.x - p.x, lp.z - p.z).length()
		if d2 < bd:
			best = ["Колоть дрова", "log", lg]
	return best

# ---------- бросок копья и стрельба из лука (прицел ведёт combat.gd) ----------

func can_throw() -> bool:
	return held == "spear" and act == "" and hero.state == "walk" and hero.swimb < 0.3

func can_shoot() -> bool:
	return held == "bow" and act == "" and hero.state == "walk" and hero.swimb < 0.3 and _inv("arrow") > 0

## Бросок без прицела: ближайший зверь впереди или вперёд (для проверок и клавиатуры).
func throw() -> void:
	if not can_throw():
		return
	var aim := Vector3.INF
	var w := _world()
	if w != null:
		aim = w.aim_target(hero.position, hero.body.rotation.y)
	if aim != Vector3.INF:
		_face(aim)
	_start("throw", 1.2, {"aim": aim})

## Начать прицел: копьё отводится назад, лук натягивается по силе.
func aim_begin(kind: String) -> bool:
	if kind == "spear" and can_throw():
		_start("throw", 1.2, {"aiming": true, "aim": Vector3.INF})
		return true
	if kind == "bow" and can_shoot():
		_start("shoot", 999.0, {"aiming": true})
		return true
	return false

## Повернуться по прицелу (горизонтальное направление).
func aim_face(dir: Vector3) -> void:
	if act in ["throw", "shoot"] and Vector2(dir.x, dir.z).length() > 0.01:
		act_data["yaw"] = atan2(dir.x, dir.z)

## Отпустить: скорость снаряда — от прицела.
func aim_release(vel: Vector3) -> void:
	if act == "throw" and act_data.get("aiming", false):
		act_data["aiming"] = false
		act_data["vel"] = vel
		act_t = maxf(act_t, THROW_COCK)
	elif act == "shoot" and act_data.get("aiming", false):
		act_data["aiming"] = false
		act_data["vel"] = vel
		act_data["rel"] = act_t

func aim_cancel() -> void:
	if act in ["throw", "shoot"] and act_data.get("aiming", false):
		_cancel()
		_refresh()

## Откуда полетит снаряд (для траектории в прицеле).
func launch_point(kind: String) -> Vector3:
	var yaw: float = hero.body.rotation.y
	var f := Vector3(sin(yaw), 0, cos(yaw))
	var r := Vector3(-cos(yaw), 0, sin(yaw))
	if kind == "bow":
		return hero.position + Vector3(0, 1.42, 0) + f * 0.35 + r * 0.05
	return hero.position + Vector3(0, 1.72, 0) + f * 0.25 + r * 0.22

func can_stick() -> bool:
	return is_long(held) and act == "" and hero.state == "walk" and hero.swimb < 0.3 and hero.depth < 0.3

func stick() -> void:
	if can_stick():
		_start("stick", 0.8, {"id": held})

# ---------- брёвна: плечо, связка ----------

func _has_rope() -> bool:
	return _inv("rope") > 0

func _logs_around(r: float) -> Array:
	var w := _world()
	if w == null:
		return []
	return w.logs_near(hero.position, r)

## Стройка избы рядом, куда ещё нужны брёвна ({} — нет).
func _site_near() -> Dictionary:
	if hero.main == null or hero.main.get("camp") == null:
		return {}
	var camp: Node = hero.main.camp
	if not camp.has_method("nearest"):
		return {}
	var s: Dictionary = camp.nearest(3.5)
	if s.is_empty() or String(s.get("type", "")) != "cabin" or String(s.get("stage", "")) != "site":
		return {}
	var need := int(camp.need_of(s).get("log", 0))
	if int((s["have"] as Dictionary).get("log", 0)) >= need:
		return {}
	return s

## Подпись основной кнопки (брёвна, связка, подобрать воткнутое копьё) — "" если нечего.
func action_label() -> String:
	if act != "" or hero.state != "walk":
		return ""
	var w := _world()
	if w == null:
		return ""
	if bundle != null:
		if not _site_near().is_empty():
			return "Сложить связку на стройку"
		return "Развязать связку"
	var near := _logs_around(2.4)
	if held == "log":
		if logs < LOGS_MAX and not near.is_empty() and w.find_log(hero.position, 1.5) != null:
			return "Взять второе бревно"
		if _has_rope() and not near.is_empty():
			return "Связать брёвна"
		return "Положить брёвна" if logs > 1 else "Положить бревно"
	var it: Dictionary = w.nearest_item(hero.position, 1.5)
	if not it.is_empty():
		if it["id"] == "log":
			if _has_rope() and near.size() >= 2 and not is_long(held):
				return "Связать брёвна"
			return "Взять бревно на плечо"
		return "Взять: " + IT.name_of(String(it["id"])).to_lower()
	return ""

func do_action() -> bool:
	var lbl := action_label()
	if lbl == "":
		return false
	var w := _world()
	match lbl:
		"Сложить связку на стройку":
			_start("deposit", 1.0, {"site": _site_near()})
			return true
		"Развязать связку":
			_start("untie", 1.1, {})
			return true
		"Связать брёвна":
			if held != "" and held != "log":
				if is_long(held):
					_stick_now()
				else:
					_stow(held)
			_start("tie", 1.3, {})
			return true
		"Положить бревно", "Положить брёвна":
			_start("drop_log", 0.9, {})
			return true
	var it: Dictionary = w.nearest_item(hero.position, 1.5)
	if it.is_empty():
		return false
	if it["id"] == "log":
		if held != "" and held != "log":
			if is_long(held):
				_stick_now()
			else:
				_stow(held)
		_face(it["node"].global_position)
		_start("take_log", 1.1, {"item": it})
	else:
		_face(it["node"].global_position)
		_start("take_long", 0.75, {"item": it})
	return true

func _face(p: Vector3) -> void:
	var d: Vector3 = p - hero.position
	if Vector2(d.x, d.z).length() > 0.05:
		act_data["yaw"] = atan2(d.x, d.z)

## Шаг действий (из hero._process).
func process(delta: float) -> void:
	if hero.main == null:
		return
	hidden = hero.state == "pack"
	tr_t += delta
	sync()
	if bundle != null:
		bundle.step(delta, rope_anchor())
	if act == "":
		return
	if hero.state != "walk":
		_cancel()
		_refresh()
		return
	act_t += delta
	act_data["u"] = act_t / maxf(act_dur, 0.001)
	if act_data.has("yaw"):
		hero.body.rotation.y = lerp_angle(hero.body.rotation.y, float(act_data["yaw"]), minf(1.0, delta * 10.0))
	# циклы рубки прерываются джойстиком
	if act in ["chop", "trunk", "split"] and hero.move_vec.length() > 0.5:
		act = ""
		return
	var w := _world()
	match act:
		"chop", "trunk", "split":
			var L := 0.97
			var ph := fposmod(act_t, L) / L
			var prev := fposmod(act_t - delta, L) / L
			if prev < CHOP_HIT and ph >= CHOP_HIT and act_t > 0.1:
				act_hits += 1
				var done := true
				if act == "chop":
					done = w.chop_tree(act_data["tree"], hero.position, act_hits)
				elif act == "trunk":
					done = w.chop_trunk(act_data["trunk"], act_hits)
				else:
					done = w.split_log(act_data["log"], act_hits)
				if done:
					act_dur = act_t + 0.6
					act_data["ending"] = true
			if act_data.has("ending") and act_t >= act_dur:
				act = ""
		"cut", "hand":
			if act_t >= act_dur:
				w.harvest(act_data["res"], act == "cut")
				act = ""
		"attack":
			_attack_step(delta)
		"throw":
			if act_data.get("aiming", false):
				act_t = minf(act_t, THROW_COCK)
			elif act_t >= THROW_REL and not act_data.has("gone"):
				act_data["gone"] = true
				var gx := sk.global_transform * _long_xf
				var v: Vector3
				if act_data.has("vel"):
					v = act_data["vel"]
				else:
					v = w.throw_velocity(gx.origin, gx.basis.y.normalized(), act_data["aim"])
				w.throw_spear(gx, v)
				_spend("spear")
				held = ""
				long_n.visible = false
				_refresh()
			if act_t >= act_dur:
				act = ""
		"shoot":
			if act_data.get("aiming", false):
				var c := _combat()
				var want: float = 0.25 + 0.75 * float(c.aim_pow) if c != null else 1.0
				drawk = move_toward(drawk, want, delta * 2.2)
			elif not act_data.has("gone"):
				act_data["gone"] = true
				var ax := arrow_n.global_transform
				var v2: Vector3 = act_data["vel"]
				# вылет — из точки, по которой считана дуга прицела (стрела срывается с тетивы вперёд)
				w.shoot_arrow(Transform3D(w._spear_basis(v2), launch_point("bow")), v2)
				_spend("arrow")
				var cb := _combat()
				if cb != null:
					cb.twang(ax.origin)
				drawk = 0.0
				act_dur = act_t + 0.45
			if act_data.has("gone") and act_t >= act_dur:
				act = ""
		"stick":
			if act_t >= act_dur * 0.62 and not act_data.has("done"):
				act_data["done"] = true
				_stick_now()
			if act_t >= act_dur:
				act = ""
		"take_long":
			if act_t >= act_dur * 0.45 and not act_data.has("done"):
				act_data["done"] = true
				var it: Dictionary = act_data["item"]
				if w.take_item(it):
					var id: String = it["id"]
					hero.main.inv[id] = int(hero.main.inv.get(id, 0)) + 1
					if is_long(id):
						give_long(id)
					else:
						_say("+1 %s" % IT.name_of(id).to_lower())
			if act_t >= act_dur:
				act = ""
		"take_log":
			if act_t >= act_dur * 0.45 and not act_data.has("done"):
				act_data["done"] = true
				var it2: Dictionary = act_data["item"]
				if w.take_item(it2):
					if held == "log":
						logs = mini(logs + 1, LOGS_MAX)
					else:
						held = "log"
			if act_t >= act_dur:
				act = ""
		"drop_log":
			if act_t >= act_dur * 0.6 and held == "log":
				_drop_logs_now()
			if act_t >= act_dur:
				act = ""
		"tie":
			if act_t >= act_dur * 0.6 and not act_data.has("done"):
				act_data["done"] = true
				_tie_now()
			if act_t >= act_dur:
				act = ""
		"untie":
			if act_t >= act_dur * 0.55 and not act_data.has("done"):
				act_data["done"] = true
				_untie_now()
			if act_t >= act_dur:
				act = ""
		"deposit":
			if act_t >= act_dur * 0.55 and not act_data.has("done"):
				act_data["done"] = true
				_deposit_now(act_data["site"])
			if act_t >= act_dur:
				act = ""
	if act == "":
		act_data = {}
	_refresh()

func _spend(id: String) -> void:
	hero.main.inv[id] = int(hero.main.inv.get(id, 0)) - 1
	if int(hero.main.inv[id]) <= 0:
		hero.main.inv.erase(id)

## Удар: свист в начале удара, проверка попадания острием по пути инструмента; не задел — подсказка рядом.
func _attack_step(delta: float) -> void:
	var tool: String = act_data["tool"]
	var m: Dictionary = MELEE[tool]
	var c := _combat()
	var h0 := act_dur * float(m["h0"])
	var h1 := act_dur * float(m["h1"])
	if act_t >= h0 - 0.06 and not act_data.has("sw"):
		act_data["sw"] = true
		if c != null:
			c.swish(tool, hero.position + Vector3(0, 1.2, 0))
	if act_t >= h0 - delta and act_t <= h1 + delta and not act_data.has("hit"):
		var seg := tool_seg(tool)
		if act_data.has("ptip") and c != null:
			if c.melee_sweep(tool, [[act_data["ptip"], seg[1]], [seg[0], seg[1]]]):
				act_data["hit"] = true
		act_data["ptip"] = seg[1]
	if act_t > h1 and not act_data.has("hit") and not act_data.has("assist"):
		act_data["assist"] = true
		if c != null and c.melee_assist(tool):
			act_data["hit"] = true
	# выпад копьём: шаг вперёд на ударе
	if tool == "spear":
		var u := act_t / act_dur
		var lunge := (smoothstep(0.4, 0.55, u) - smoothstep(0.4, 0.55, (act_t - delta) / act_dur)) * 0.35
		if lunge > 0.0:
			var yaw: float = hero.body.rotation.y
			var p: Vector3 = hero.position + Vector3(sin(yaw), 0, cos(yaw)) * lunge
			if hero._can_walk(p):
				hero.position.x = p.x
				hero.position.z = p.z
	if act_t >= act_dur:
		act = ""

## Воткнуть копьё (лопату) рядом с собой: справа-спереди. Копьё — наконечником в землю,
## древко чуть наклонено от героя; лопата — лопастью вниз.
func _stick_now() -> void:
	var id := held
	if not is_long(id):
		return
	held = ""
	var w := _world()
	if w == null or hero.main == null:
		_refresh()
		return
	var yaw: float = hero.body.rotation.y
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var rgt := Vector3(-cos(yaw), 0, sin(yaw))
	var p: Vector3 = hero.position + fwd * 0.55 + rgt * 0.3
	p.y = hero.main.ground_at(p.x, p.z)
	if id == "spear":
		# ось копья (+Y — к острию) смотрит вниз и чуть от героя: острие в земле на 0,2 м, древко торчит вверх
		var down := Vector3(0, -1, 0).rotated(fwd, 0.16).rotated(rgt, -0.1).normalized()
		var x := rgt - down * rgt.dot(down)
		x = x.normalized()
		var b := Basis(x, down, x.cross(down).normalized())
		var tip := 1.12
		var depth := 0.2
		w.place_item(id, Transform3D(b, p - down * (tip - depth)), false)
	else:
		var up := Vector3(0, 1, 0).rotated(rgt, 0.1)
		var b2 := Basis(rgt, up, rgt.cross(up).normalized())
		w.place_item(id, Transform3D(b2, p - up * (-0.88 + 0.1)), false)
	_spend(id)
	_refresh()

## Положить с плеча все брёвна: рядом, поперёк взгляда.
func _drop_logs_now() -> void:
	if held != "log":
		return
	var n := logs
	logs = 0
	held = ""
	var w := _world()
	if w != null and hero.main != null:
		var yaw: float = hero.body.rotation.y
		var fwd := Vector3(sin(yaw), 0, cos(yaw))
		var rgt := Vector3(-cos(yaw), 0, sin(yaw))
		for i in n:
			var p: Vector3 = hero.position + fwd * (0.9 + 0.3 * i) + rgt * 0.1 * i
			w.drop_log(p, yaw + PI * 0.5)
	_refresh()

## Связать брёвна рядом (и с плеча) верёвкой: до восьми.
func _tie_now() -> void:
	var w := _world()
	if w == null or not _has_rope():
		return
	var list: Array = []
	if held == "log":
		for i in logs:
			list.append({"r": 0.13, "bark": Color(0.42, 0.33, 0.24), "L": 1.25})
		logs = 0
		held = ""
	for it: Dictionary in _logs_around(2.6):
		if list.size() >= BUNDLE_MAX:
			break
		var node: Node3D = it["node"]
		var L := 1.25
		var mi := node as MeshInstance3D
		if mi != null and mi.mesh != null:
			L = mi.mesh.get_aabb().size.y
		var r := float(it.get("r", 0.13))
		var bark: Color = it.get("bark", Color(0.42, 0.33, 0.24))
		if w.take_item(it):
			list.append({"r": r, "bark": bark, "L": L})
	if list.is_empty():
		return
	_spend("rope")
	bundle = BUNDLE.new()
	bundle.main = hero.main
	w.add_child(bundle)
	var yaw: float = hero.body.rotation.y
	bundle.setup(list, hero.position, Vector3(sin(yaw), 0, cos(yaw)))
	_say("Связка: %d %s — волоком" % [list.size(), "бревно" if list.size() == 1 else ("бревна" if list.size() < 5 else "брёвен")])

## Развязать: брёвна остаются лежать, верёвка — в короб.
func _untie_now() -> void:
	if bundle == null:
		return
	bundle.untie(_world())
	bundle = null
	hero.main.inv["rope"] = int(hero.main.inv.get("rope", 0)) + 1
	_say("Связка развязана, верёвка в коробе")

## Связку — на стройку избы: сколько нужно, остальное остаётся в связке.
func _deposit_now(s: Dictionary) -> void:
	if bundle == null or s.is_empty() or hero.main.get("camp") == null:
		return
	var camp: Node = hero.main.camp
	var need := int(camp.need_of(s).get("log", 0))
	var have: Dictionary = s["have"]
	var k := mini(need - int(have.get("log", 0)), bundle.count())
	if k <= 0:
		return
	camp.deposit_item(s, "log", k)
	bundle.remove(k)
	if bundle.count() == 0:
		bundle.queue_free()
		bundle = null
		hero.main.inv["rope"] = int(hero.main.inv.get("rope", 0)) + 1
	camp._rebuild(s)
	_say("Брёвна на стройке: %d из %d" % [int(have["log"]), need])

## Где верёвка связки в руках: у правого плеча (в мире).
func rope_anchor() -> Vector3:
	var cl := sk.get_bone_global_pose(bones["clavicle_r"]).origin
	return sk.global_transform * (cl + Vector3(-0.12, 0.08, -0.08))

## Анимация тела для действия; true — проигрыватель занят действием.
func anim_override() -> bool:
	match act:
		"chop", "trunk", "split":
			hero._play("TreeChopping", 1.0, 0.15)
			return true
		"cut", "hand":
			hero._play(String(act_data.get("anim", "Farm_Harvest")), float(act_data.get("speed", 1.0)), 0.2)
			return true
		"throw":
			_drive("OverhandThrow", act_t, 0.12)
			return true
		"take_log", "drop_log", "take_long", "tie", "untie", "deposit":
			hero._play("Farm_Harvest", 2.2, 0.15)
			return true
		"stick", "shoot":
			hero._play("Idle", 1.0, 0.2)
			return true
		"attack":
			var tool: String = act_data["tool"]
			var m: Dictionary = MELEE[tool]
			if not m.has("seg"):
				hero._play("Idle", 1.0, 0.2)
				return true
			var u := act_t / act_dur
			for sg: Array in m["seg"]:
				if u <= float(sg[4]):
					var k := inverse_lerp(float(sg[3]), float(sg[4]), u)
					_drive(String(sg[0]), lerpf(float(sg[1]), float(sg[2]), clampf(k, 0.0, 1.0)), 0.1)
					return true
			hero._play("Idle", 1.0, 0.28)
			return true
	return false

## Вести клип к нужному моменту: скорость проигрывателя подбирается так, чтобы догнать время want.
func _drive(clip: String, want: float, blend: float) -> void:
	var ap: AnimationPlayer = hero.m_ap
	var a := SK.find_anim(ap, [clip])
	if a == "":
		return
	if a != hero.m_cur or ap.current_animation != a:
		ap.play(a, blend)
		ap.seek(want, true)
		hero.m_cur = a
		ap.speed_scale = 1.0
		return
	var dl := maxf(get_process_delta_time(), 0.001)
	ap.speed_scale = clampf((want - ap.current_animation_position) / dl, 0.0, 8.0)

# ---------- поза: модификатор скелета ----------

func _ss(a: float, b: float, x: float) -> float:
	return smoothstep(a, b, x)

func _gpose(b: String) -> Transform3D:
	return sk.get_bone_global_pose(bones[b])

## Повернуть кость так, чтобы её поворот в осях скелета стал q.
func _set_grot(b: int, q: Quaternion, w: float = 1.0) -> void:
	var par := sk.get_bone_global_pose(sk.get_bone_parent(b)).basis.get_rotation_quaternion()
	var cur := sk.get_bone_pose_rotation(b)
	sk.set_bone_pose_rotation(b, cur.slerp((par.inverse() * q).normalized(), w))

func _curl(list: Array, w: float) -> void:
	if w <= 0.001:
		return
	for c: Array in list:
		var b: int = c[0]
		var q := sk.get_bone_rest(b).basis.get_rotation_quaternion() * Quaternion(c[1], c[2])
		sk.set_bone_pose_rotation(b, sk.get_bone_pose_rotation(b).slerp(q, w))

## Повернуть кисть так, чтобы рукоять легла по оси axis, а пальцы смотрели к eref; ИК руки к хвату.
func _hold(side: String, grip: Vector3, axis: Vector3, eref: Vector3, w: float, pole: Vector3 = Vector3.INF) -> void:
	if w <= 0.001:
		return
	var G := G_r if side == "r" else G_l
	var A := axis.normalized()
	var E := (eref - A * eref.dot(A)).normalized()
	var F := Basis(E, A, E.cross(A))
	var Hd := (F * G.basis.orthonormalized().inverse()).orthonormalized()
	var hb: int = bones["hand_" + side]
	var gh := sk.get_bone_global_pose(hb)
	var off := Hd * (G.origin * gh.basis.get_scale())
	var target := grip - off
	var sh := _gpose("upperarm_" + side).origin
	var sx := -1.0 if side == "r" else 1.0
	hero._pk_ik(sk, side, gh.origin.lerp(target, w), sh + Vector3(sx * 0.45, -0.35, -0.3) if pole == Vector3.INF else pole, w)
	_set_grot(hb, Hd.get_rotation_quaternion(), w)

## Кратчайший поворот кисти от позы анимации, чтобы рукоять легла по оси ax.
func _hand_axis(side: String, ax: Vector3) -> void:
	var G := G_r if side == "r" else G_l
	var hg := _gpose("hand_" + side)
	var hq := hg.basis.get_rotation_quaternion()
	var cur_a := (hq * G.basis.orthonormalized().y).normalized()
	var Hd := Basis(Quaternion(cur_a, ax.normalized()) * hq)
	_set_grot(bones["hand_" + side], Hd.get_rotation_quaternion(), 1.0)

func _modify(s: Skeleton3D) -> void:
	if hero.state == "dead" or hero.pack_stage != "":
		return
	var tm := Time.get_ticks_msec() * 0.001
	var u := act_t / maxf(act_dur, 0.001)
	var tu := clampf(tr_t / TR_DUR, 0.0, 1.0)
	var trn := tr_t < TR_DUR and not hidden
	# --- нож и топор в правой руке: кулак сжат; в покое — лезвием вперёд-вниз, у бедра
	var r_tool := vis_place("knife") == "hand" or vis_place("axe") == "hand"
	if (held in ["knife", "axe"] or (trn and tr_id in BELT_OK)) and not hidden:
		_curl(curl_r, 1.0 if r_tool else _ss(0.3, 0.5, tu))
		if held in ["knife", "axe"] and not (act in ["chop", "trunk", "split", "cut", "attack"]) and not trn:
			_hand_axis("r", Vector3(-0.12, -0.55, 1.0) if held == "knife" else Vector3(-0.1, -0.6, 0.8))
	# --- достать/убрать: кисть к поясу и обратно (переход только для вида)
	if trn and tr_id in BELT_OK and (tr_from == "belt" or tr_to == "belt"):
		var bt: Transform3D = _gpose("pelvis") * belt_xf[tr_id]
		var reach := sin(PI * tu)
		var gp := bt.origin + bt.basis.y.normalized() * (0.02 if tr_id == "knife" else 0.36)
		_hold("r", gp, -bt.basis.y if tr_id == "knife" else bt.basis.y, Vector3(0, 0, 1), reach * 0.9)
	# --- лук: снять из-за спины / закинуть за спину — левая рука к плечу
	if trn and tr_id == "bow" and (tr_from == "back" or tr_to == "back"):
		var cl := _gpose("clavicle_l").origin
		hero._pk_ik(sk, "l", cl + Vector3(0.02, 0.22, -0.12), cl + Vector3(0.5, -0.2, 0.2), sin(PI * tu) * 0.95)
		_curl(curl_l, sin(PI * tu))
	# --- копьё/лопата
	if (is_long(held) or act == "throw") and not hidden:
		_pose_long(tm, u)
	# --- лук в левой руке
	if bow_n.get_parent() == sk and bow_n.visible:
		_pose_bow()
	# --- брёвна на плече
	if held == "log" or act in ["take_log", "drop_log"]:
		_pose_log(u)
	# --- связка: верёвка через правое плечо, обе руки тянут у груди, корпус вперёд
	if bundle != null and act == "":
		_pose_drag()
	# --- рубка лежачего: наклон корпуса, чтобы топор доставал до ствола
	if act in ["trunk", "split"]:
		var bend := 0.55 * _ss(0.0, 0.25, act_t)
		hero._pk_rot(sk, bones["spine_01"], Quaternion(Vector3.RIGHT, bend * 0.45))
		hero._pk_rot(sk, bones["spine_02"], Quaternion(Vector3.RIGHT, bend * 0.55))
	# --- нож: выпад рукой (Punch_Jab), клинок режет дугой справа налево поперёк выпада
	if act == "attack" and String(act_data.get("tool", "")) == "knife":
		var sweep := _ss(0.22, 0.5, u)
		var kax := Vector3(-0.9, 0.35, 0.45).lerp(Vector3(0.85, 0.05, 0.7), sweep)
		var kw := _ss(0.0, 0.15, u) * (1.0 - _ss(0.75, 1.0, u))
		if kw > 0.01:
			var hq0 := sk.get_bone_pose_rotation(bones["hand_r"])
			_hand_axis("r", kax)
			sk.set_bone_pose_rotation(bones["hand_r"], hq0.slerp(sk.get_bone_pose_rotation(bones["hand_r"]), kw))
	# --- удар топором и ножом: корпус доворачивается в удар
	if act == "attack" and String(act_data.get("tool", "")) != "spear":
		var k := _ss(0.0, 0.25, u) * (1.0 - _ss(0.7, 1.0, u))
		var hit := _ss(0.28, 0.45, u)
		hero._pk_rot(sk, bones["spine_02"], Quaternion(Vector3.RIGHT, 0.12 * hit * k))

func _pose_long(tm: float, u: float) -> void:
	var pel := _gpose("pelvis").origin
	var run: float = clampf(hero._hspeed / 3.0, 0.0, 1.0)
	var sw: float = sin(hero.phase) * 0.05 * clampf(hero._hspeed / 1.6, 0.0, 1.0)
	# ношение: древко у правого бедра почти вертикально, на бегу — наклон вперёд
	var grip := pel + Vector3(-0.27, 0.02 + sin(tm * 1.3) * 0.004, 0.13 + sw)
	var axis := Vector3(0.02, 1.0, 0.1 + 0.6 * run).normalized()
	var eref := Vector3(0, 0, 1)
	var lw := 0.0
	var lgrip := Vector3.ZERO
	var leref := Vector3.ZERO
	var rw := 1.0
	if act == "attack":
		# к бою: древко у пояса, острие вперёд, левая рука впереди; отвести назад — и резкий выпад
		var ready_g := pel + Vector3(-0.1, 0.2, 0.02)
		var ready_a := Vector3(0.38, 0.12, 0.92).normalized()
		var k := _ss(0.0, 0.28, u) * (1.0 - _ss(0.78, 1.0, u))
		var pull := _ss(0.18, 0.42, u) * (1.0 - _ss(0.42, 0.5, u))
		var thrust := _ss(0.42, 0.52, u) * (1.0 - _ss(0.64, 0.88, u))
		grip = grip.lerp(ready_g + ready_a * (0.62 * thrust - 0.22 * pull), k)
		axis = axis.slerp(ready_a, k)
		eref = eref.lerp(Vector3(0.7, -0.6, 0.0), k)
		lw = k
		# задняя рука толкает, передняя направляет древко
		lgrip = ready_g + ready_a * (0.36 + 0.12 * thrust - 0.08 * pull)
		leref = Vector3(-0.6, -0.6, 0.0)
		hero._pk_rot(sk, bones["spine_02"], Quaternion(Vector3.UP, 0.28 * k - 0.32 * thrust + 0.12 * pull))
		hero._pk_rot(sk, bones["spine_01"], Quaternion(Vector3.RIGHT, 0.3 * thrust - 0.08 * pull))
	elif act == "stick":
		# перехватить древко, развернуть острием вниз и вогнать в землю
		var k2 := _ss(0.0, 0.6, u)
		grip = grip + Vector3(-0.03, 0.1 * k2 - 0.25 * _ss(0.45, 0.62, u), 0.32 * k2)
		axis = axis.slerp(Vector3(0.1, -1.0, 0.16).normalized(), _ss(0.0, 0.45, u))
		rw = 1.0 - _ss(0.62, 0.9, u)
	elif act == "throw":
		# копьё в поднятой руке по анимации броска: наконечник вперёд-вверх
		var hb: int = bones["hand_r"]
		var gh := sk.get_bone_global_pose(hb)
		var k3 := _ss(0.0, 0.18, act_t)
		axis = axis.slerp(Vector3(0.02, 0.22, 1.0).normalized(), k3)
		eref = eref.lerp(Vector3(1.0, 0.0, 0.0), k3)
		var A := axis.normalized()
		var E := (eref - A * eref.dot(A)).normalized()
		var Hd := (Basis(E, A, E.cross(A)) * G_r.basis.orthonormalized().inverse()).orthonormalized()
		var anim_grip := gh.origin + Hd * (G_r.origin * gh.basis.get_scale())
		grip = grip.lerp(anim_grip, k3)
		if act_data.has("gone"):
			_curl(curl_r, 1.0 - _ss(THROW_REL, THROW_REL + 0.15, act_t))
			return
		if k3 < 1.0:
			_hold("r", grip, axis, eref, 1.0)
		else:
			_set_grot(hb, Hd.get_rotation_quaternion(), 1.0)
		_curl(curl_r, 1.0)
		_long_xf = _long_basis(grip, axis)
		long_n.transform = _long_xf
		long_n.visible = true
		return
	elif act == "take_long":
		rw = _ss(0.3, 0.45, u)
	_long_xf = _long_basis(grip, axis)
	if rw > 0.0 and is_long(held):
		long_n.transform = _long_xf
	_hold("r", grip, axis, eref, rw)
	_curl(curl_r, rw)
	if lw > 0.001:
		_hold("l", lgrip, axis, leref, lw)
		_curl(curl_l, lw)

func _long_basis(grip: Vector3, axis: Vector3) -> Transform3D:
	var A := axis.normalized()
	var X := (Vector3(1, 0, 0) - A * A.x).normalized()
	return Transform3D(Basis(X, A, X.cross(A)), grip)

## Лук: в покое — в опущенной левой руке, верхним плечом вперёд; в прицеле — левая рука к цели,
## корпус боком, правая тянет тетиву к подбородку; стрела лежит на полке у рукояти.
func _pose_bow() -> void:
	var aiming := act == "shoot"
	var gh: Transform3D
	if aiming:
		var c := _combat()
		var pitch := 0.0
		if c != null:
			pitch = float(c.aim_pitch)
		var D := Vector3(0, sin(pitch), cos(pitch))
		var k := _ss(0.0, 0.25, act_t)
		if act_data.has("gone"):
			k = 1.0 - _ss(float(act_data.get("rel", 0.0)) + 0.15, float(act_data.get("rel", 0.0)) + 0.45, act_t)
		# корпус боком к цели: левое плечо вперёд
		hero._pk_rot(sk, bones["spine_01"], Quaternion(Vector3.UP, -0.35 * k))
		hero._pk_rot(sk, bones["spine_02"], Quaternion(Vector3.UP, -0.3 * k))
		var shl := _gpose("upperarm_l").origin
		var grip := shl + D * 0.62 + Vector3(0, 0.06, 0)
		var up := (Vector3.UP - D * D.y).normalized()
		var bax := up.rotated(D, 0.12)
		_hold("l", grip, bax, D, k, shl + Vector3(0.35, -0.35, 0.0))
		_curl(curl_l, k)
		gh = _gpose("hand_l")
		var bx := _bow_xf(gh)
		# тетива: от покоя до подбородка по натяжению
		var rest := bx * Vector3(TM.bow_x(0.0) - 0.17, 0.0, 0.0)
		var nock := rest - D * 0.5 * drawk
		var shr := _gpose("upperarm_r").origin
		hero._pk_ik(sk, "r", nock - D * 0.06 + Vector3(-0.02, -0.03, 0), shr + Vector3(-0.35, 0.05, -0.35), k)
		_curl(curl_r, 0.55 * k)
		bow_n.transform = bx
		if act_data.has("gone"):
			_set_string(Vector3.INF)
			arrow_n.visible = false
		else:
			var nl := bx.affine_inverse() * nock
			_set_string(nl if k > 0.05 else Vector3.INF)
			# стрела: ушко на тетиве, острие — мимо рукояти вперёд
			var rest_l := Vector3(0.02, 0.025, 0.014)
			var dir := (rest_l - nl).normalized()
			var ax := Vector3(0, 0, 1) - dir * dir.z
			ax = ax.normalized()
			arrow_n.transform = Transform3D(Basis(dir.cross(ax).normalized(), dir, ax), nl)
			arrow_n.visible = k > 0.3
	else:
		_hand_axis("l", Vector3(0.3, 0.85, 0.42))
		_curl(curl_l, 1.0)
		gh = _gpose("hand_l")
		bow_n.transform = _bow_xf(gh)
		_set_string(Vector3.INF)
		arrow_n.visible = false

func _bow_xf(gh: Transform3D) -> Transform3D:
	return Transform3D(gh.basis.orthonormalized(), gh.origin) * Transform3D(G_l.basis.orthonormalized(), G_l.origin * gh.basis.get_scale())

## Тетива: два отрезка от ушек к точке натяжения (INF — прямая между ушками).
func _set_string(nock: Vector3) -> void:
	var a := TM.bow_tip(true)
	var b := TM.bow_tip(false)
	var n := (a + b) * 0.5 if nock == Vector3.INF else nock
	for pair: Array in [[str_a, a], [str_b, b]]:
		var mi: MeshInstance3D = pair[0]
		var p0: Vector3 = pair[1]
		var d := n - p0
		var L := maxf(d.length(), 0.001)
		var y := d / L
		var x := y.cross(Vector3(0, 0, 1)).normalized()
		mi.transform = Transform3D(Basis(x, y * L, x.cross(y).normalized()), p0)

## Брёвна на правом плече вдоль взгляда; правая рука придерживает спереди, левая — снизу.
## Второе бревно — поверх первого, чуть наружу.
func _pose_log(u: float) -> void:
	var cl := _gpose("clavicle_r").origin
	var on := Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0.08, 1).normalized(), Vector3.ZERO), cl + Vector3(-0.25, 0.15, 0.0))
	on.basis.z = on.basis.x.cross(on.basis.y).normalized()
	var k := 1.0
	if act == "take_log":
		k = _ss(0.45, 0.95, u) if logs == 0 or held != "log" else 1.0
	elif act == "drop_log":
		k = 1.0 - _ss(0.15, 0.6, u)
	var gnd := Transform3D(Basis(Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)), Vector3(0, 0.13, 0.85))
	var xf := gnd.interpolate_with(on, k)
	(log_ns[0] as MeshInstance3D).transform = xf
	var two := held == "log" and logs >= 2
	var x2 := Transform3D(xf.basis, xf.origin + Vector3(-0.07, 0.235, 0.02))
	if act == "take_log" and held == "log" and logs == 1:
		x2 = gnd.interpolate_with(x2, _ss(0.45, 0.95, u))
		two = u >= 0.45
	(log_ns[1] as MeshInstance3D).transform = x2
	(log_ns[1] as MeshInstance3D).visible = two or (act == "take_log" and held == "log" and logs == 1 and u >= 0.45)
	var w := clampf(k * 1.5, 0.0, 1.0)
	var front := xf * Vector3(0, 0.42, 0) + Vector3(0, 0.02, 0)
	if two:
		front += Vector3(-0.03, 0.12, 0.0)
	hero._pk_ik(sk, "r", front + Vector3(0.02, -0.03, -0.06), cl + Vector3(-0.4, -0.3, 0.1), w)
	_curl(curl_r, w * 0.7)
	var under := xf * Vector3(0, 0.12, 0) + Vector3(0.0, -0.1, 0.02)
	hero._pk_ik(sk, "l", under, _gpose("upperarm_l").origin + Vector3(0.3, -0.4, 0.0), w)
	_curl(curl_l, w * 0.5)

## Волок: верёвка через правое плечо, кисти у груди сжимают её, корпус подался вперёд.
func _pose_drag() -> void:
	var cl := _gpose("clavicle_r").origin
	hero._pk_rot(sk, bones["spine_01"], Quaternion(Vector3.RIGHT, 0.14))
	hero._pk_rot(sk, bones["spine_02"], Quaternion(Vector3.RIGHT, 0.1))
	var cl2 := _gpose("clavicle_r").origin
	var rh := cl2 + Vector3(0.02, -0.2, 0.2)
	var lh := cl2 + Vector3(0.14, -0.3, 0.24)
	hero._pk_ik(sk, "r", rh, cl2 + Vector3(-0.4, -0.35, -0.1), 1.0)
	hero._pk_ik(sk, "l", lh, _gpose("upperarm_l").origin + Vector3(0.4, -0.35, -0.1), 1.0)
	_curl(curl_r, 0.85)
	_curl(curl_l, 0.85)
	if bundle != null:
		bundle.hands = [sk.global_transform * (rh + Vector3(0, 0.05, 0.04)), sk.global_transform * (cl2 + Vector3(-0.1, 0.09, -0.04))]
	if cl.y < 0.0:
		pass
