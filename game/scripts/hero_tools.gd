extends Node
## Инструменты героя: что в руке (held), что на поясе (belt); модели в руке и на поясе;
## хват — пальцы сжаты вокруг рукояти, кисть по оси рукояти; копьё и лопата — двумя руками
## (двухзвенная ИК, как у короба в hero.gd); действия инструментом с анимациями.
## Инвентарь: инструменты лежат в main.inv как обычные вещи; то, что в руке и на поясе, в вес
## короба не входит (inventory.gd). Копьё и лопата (hands) — только в руках: их втыкают в землю
## рядом (world_tools.gd) и берут снова.

const IT = preload("res://scripts/items.gd")
const TM = preload("res://scripts/tool_models.gd")
const BELT_OK := ["knife", "axe"]
const LONG := ["spear", "shovel"]
const CHOP_HIT := 0.18        # доля цикла TreeChopping, где топор бьёт
const THROW_REL := 0.31       # момент выпуска копья в OverhandThrow, с

var hero: Node3D
var sk: Skeleton3D
var held := ""                # knife, axe, spear, shovel, log или ""
var belt: Array = []          # что на поясе: knife, axe
var nodes := {}               # id → MeshInstance3D
var hand_att: BoneAttachment3D
var pelvis_att: BoneAttachment3D
var sheath_n: MeshInstance3D
var long_n := MeshInstance3D.new()
var log_n := MeshInstance3D.new()
var G_r := Transform3D()      # рукоять в осях кисти (правая)
var G_l := Transform3D()
var belt_xf := {}
var bones := {}
var curl_r: Array = []        # [кость, ось, угол]
var curl_l: Array = []
var mod: GripMod
var hidden := false           # прятать вещь в руке (короб снят)

# действие: chop, trunk, split, cut, hand, stab, throw, stick, take_long, take_log, drop_log, draw, holster
var act := ""
var act_t := 0.0
var act_dur := 0.0
var act_data := {}
var act_hits := 0
var _cyc := 0.0
var _long_xf := Transform3D()
var _stick_to := Transform3D()

class GripMod extends SkeletonModifier3D:
	var tools: Node
	func _process_modification() -> void:
		tools._modify(get_skeleton())

func setup(h: Node3D, s: Skeleton3D) -> void:
	hero = h
	sk = s
	for bn in ["pelvis", "spine_01", "spine_02", "spine_03", "hand_r", "hand_l", "upperarm_r", "upperarm_l", "lowerarm_r", "lowerarm_l", "clavicle_r", "Head"]:
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
	sk.add_child(log_n)
	log_n.mesh = TM.log_mesh(1.25, 0.13, Color(0.42, 0.33, 0.24))
	log_n.visible = false
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

# ---------- данные ----------

func has_tool(id: String) -> bool:
	if held == id or belt.has(id):
		return true
	return hero.main != null and int(hero.main.inv.get(id, 0)) > 0

## Сколько штук вещи занято руками и поясом (в вес короба не входят).
func equipped_count(id: String) -> int:
	var n := 0
	if held == id:
		n += 1
	if belt.has(id):
		n += 1
	return n

func is_long(id: String) -> bool:
	return bool(IT.DEF.get(id, {}).get("hands", false))

## Свободны ли руки для другого дела (короб, бревно).
func hands_busy() -> bool:
	return held != ""

## Согласовать с инвентарём: вещь, которой больше нет (выбросили, съели), — убрать из рук и с пояса.
func sync() -> void:
	if hero.main == null:
		return
	var inv: Dictionary = hero.main.inv
	for id in belt.duplicate():
		if int(inv.get(id, 0)) < equipped_count(id):
			belt.erase(id)
	if held != "" and held != "log" and int(inv.get(held, 0)) < equipped_count(held):
		held = ""
	_refresh()

func _refresh() -> void:
	hero.held = held
	for id in nodes:
		var mi: MeshInstance3D = nodes[id]
		var in_hand: bool = held == id and not hidden
		var on_belt: bool = belt.has(id) and held != id
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
	if is_long(held) and not hidden:
		if long_n.mesh != TM.mesh_of(held):
			long_n.mesh = TM.mesh_of(held)
		long_n.visible = true
	elif act != "throw":
		long_n.visible = false
	log_n.visible = held == "log" or act == "take_log" or act == "drop_log"

# ---------- что в руке ----------

## Взять в руку (с пояса или из короба). Копьё в руках при этом втыкается рядом.
func take(id: String) -> bool:
	if act != "" or held == id:
		return false
	if hero.main != null and int(hero.main.inv.get(id, 0)) <= equipped_count(id) and not belt.has(id):
		return false
	if held == "log":
		_say("Сначала положите бревно")
		return false
	if is_long(held):
		_stick_now()
	elif held != "":
		_put_away(held)
	if belt.has(id):
		belt.erase(id)
		_start("draw", 0.55, {"id": id})
	else:
		held = id
	_refresh()
	return true

## Убрать из руки: на пояс, если можно, иначе в короб.
func holster() -> void:
	if act != "" or held == "" or held == "log" or is_long(held):
		return
	var id := held
	if BELT_OK.has(id) and not belt.has(id):
		_start("holster", 0.55, {"id": id})
	else:
		held = ""
		_refresh()
		_say("%s — в короб" % IT.name_of(id))

func _put_away(id: String) -> void:
	held = ""
	if BELT_OK.has(id) and not belt.has(id):
		belt.append(id)

## Повесить на пояс из короба (из инвентаря).
func to_belt(id: String) -> bool:
	if not BELT_OK.has(id) or belt.has(id):
		return false
	if held == id:
		held = ""
	belt.append(id)
	_refresh()
	return true

## Убрать с пояса/из руки в короб.
func to_pack(id: String) -> void:
	belt.erase(id)
	if held == id:
		held = ""
	_refresh()

## Новое копьё (после ремесла): сразу в руки.
func give_long(id: String) -> void:
	if held == "log":
		_drop_log_now()
	elif is_long(held):
		_stick_now()
	elif held != "":
		_put_away(held)
	held = id
	_refresh()

## Освободить руки (перед коробом): нож и топор — на пояс, копьё — воткнуть рядом, бревно — положить.
func free_hands() -> void:
	_cancel()
	if held == "log":
		_drop_log_now()
	elif is_long(held):
		_stick_now()
	elif held != "":
		_put_away(held)
	_refresh()

func _say(t: String) -> void:
	if hero.main != null:
		hero.main._say(t)

# ---------- действия ----------

func busy() -> bool:
	return act != "" and not (act in ["draw", "holster"])

## Множитель скорости ходьбы: бревно на плече тяжёлое.
func speed_factor() -> float:
	if held == "log":
		return 0.55
	if is_long(held):
		return 0.95
	return 1.0

func can_run() -> bool:
	return held != "log"

func _start(a: String, dur: float, data: Dictionary = {}) -> void:
	act = a
	act_t = 0.0
	act_dur = dur
	act_data = data
	act_hits = 0
	_cyc = 0.0

func _cancel() -> void:
	if act == "draw":
		held = act_data["id"]
	elif act == "holster":
		_put_away(act_data["id"])
	act = ""
	act_data = {}

func _world() -> Node:
	if hero.main == null:
		return null
	return hero.main.get("tools_world")

## Подпись кнопки «Действие» инструментом по обстановке ("" — нечего делать).
func use_label() -> String:
	if act != "" or hero.state != "walk" or hero.swimb > 0.3:
		return ""
	var w := _world()
	if w == null:
		return ""
	var p: Vector3 = hero.position
	match held:
		"axe":
			var at: Array = _axe_target(w, p)
			if not at.is_empty():
				return String(at[0])
		"knife":
			var r: Dictionary = w.knife_target(p)
			if not r.is_empty():
				return String(r["label"])
		"spear":
			return "Ударить"
		"":
			var r2: Dictionary = w.hand_target(p)
			if not r2.is_empty():
				return String(r2["label"])
	return ""

## Нажали «Действие» инструментом.
func use() -> void:
	var lbl := use_label()
	if lbl == "":
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
		"spear":
			_start("stab", 0.75, {})
		"":
			var r2: Dictionary = w.hand_target(p)
			if not r2.is_empty():
				_start("hand", 2.6, {"res": r2, "anim": "Farm_Harvest", "speed": 0.95})
				_face(r2["pos"])

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

func can_throw() -> bool:
	return held == "spear" and act == "" and hero.state == "walk" and hero.swimb < 0.3

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

func can_stick() -> bool:
	return is_long(held) and act == "" and hero.state == "walk" and hero.swimb < 0.3 and hero.depth < 0.3

func stick() -> void:
	if can_stick():
		_start("stick", 0.8, {"id": held})

## Подпись основной кнопки (подобрать воткнутое копьё, бревно) — "" если нечего.
func action_label() -> String:
	if act != "" or hero.state != "walk":
		return ""
	var w := _world()
	if w == null:
		return ""
	if held == "log":
		return "Положить бревно"
	var it: Dictionary = w.nearest_item(hero.position, 1.5)
	if not it.is_empty():
		if it["id"] == "log":
			return "Взять бревно на плечо"
		return "Взять: " + IT.name_of(String(it["id"])).to_lower()
	return ""

func do_action() -> bool:
	var lbl := action_label()
	if lbl == "":
		return false
	var w := _world()
	if held == "log":
		_start("drop_log", 0.9, {})
		return true
	var it: Dictionary = w.nearest_item(hero.position, 1.5)
	if it["id"] == "log":
		if held != "":
			if is_long(held):
				_stick_now()
			else:
				_put_away(held)
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
	sync()
	if act == "":
		return
	if hero.state != "walk":
		_cancel()
		_refresh()
		return
	act_t += delta
	if act_data.has("yaw"):
		hero.body.rotation.y = lerp_angle(hero.body.rotation.y, float(act_data["yaw"]), minf(1.0, delta * 10.0))
	# циклы рубки прерываются джойстиком
	if act in ["chop", "trunk", "split"] and hero.move_vec.length() > 0.5:
		act = ""
		return
	var w := _world()
	match act:
		"draw":
			if act_t >= act_dur * 0.5 and held != act_data["id"]:
				held = act_data["id"]
				_refresh()
		"holster":
			if act_t >= act_dur * 0.5 and held == act_data["id"]:
				_put_away(held)
				_refresh()
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
		"stab":
			if act_t >= act_dur * 0.42 and not act_data.has("hit"):
				act_data["hit"] = true
				var tip := sk.global_transform * (_long_xf * Vector3(0, 1.0, 0))
				w.stab(hero.position, tip, hero.body.rotation.y)
			if act_t >= act_dur:
				act = ""
		"throw":
			if act_t >= THROW_REL and not act_data.has("gone"):
				act_data["gone"] = true
				var gx := sk.global_transform * _long_xf
				var dir: Vector3 = gx.basis.y.normalized()
				var aim: Vector3 = act_data["aim"]
				var v: Vector3 = w.throw_velocity(gx.origin, dir, aim)
				w.throw_spear(gx, v)
				hero.main.inv["spear"] = int(hero.main.inv.get("spear", 0)) - 1
				if int(hero.main.inv["spear"]) <= 0:
					hero.main.inv.erase("spear")
				held = ""
				long_n.visible = false
				_refresh()
			if act_t >= act_dur:
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
					held = "log"
					_refresh()
			if act_t >= act_dur:
				act = ""
		"drop_log":
			if act_t >= act_dur * 0.6 and held == "log":
				_drop_log_now()
			if act_t >= act_dur:
				act = ""
	_refresh()

## Воткнуть копьё (лопату) рядом с собой: справа-спереди, древком в землю.
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
	var up := Vector3(0, 1, 0).rotated(rgt, 0.1)
	var x := rgt
	var b := Basis(x, up, x.cross(up).normalized())
	var depth := 0.18 if id == "spear" else 0.1
	var lo: float = -0.82 if id == "spear" else -0.88
	w.place_item(id, Transform3D(b, p - up * (lo + depth)), false)
	hero.main.inv[id] = int(hero.main.inv.get(id, 0)) - 1
	if int(hero.main.inv[id]) <= 0:
		hero.main.inv.erase(id)
	_refresh()

func _drop_log_now() -> void:
	if held != "log":
		return
	held = ""
	var w := _world()
	if w != null and hero.main != null:
		var yaw: float = hero.body.rotation.y
		var fwd := Vector3(sin(yaw), 0, cos(yaw))
		var p: Vector3 = hero.position + fwd * 0.9
		w.drop_log(p, yaw + PI * 0.5)
	_refresh()

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
			hero._play("OverhandThrow", 1.0, 0.12)
			return true
		"take_log", "drop_log", "take_long":
			hero._play("Farm_Harvest", 2.2, 0.15)
			return true
		"stab", "stick":
			hero._play("Idle", 1.0, 0.2)
			return true
	return false

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
func _hold(side: String, grip: Vector3, axis: Vector3, eref: Vector3, w: float) -> void:
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
	hero._pk_ik(sk, side, gh.origin.lerp(target, w), sh + Vector3(sx * 0.45, -0.35, -0.3), w)
	_set_grot(hb, Hd.get_rotation_quaternion(), w)

func _modify(s: Skeleton3D) -> void:
	if hero.state == "dead" or hero.pack_stage != "":
		return
	var tm := Time.get_ticks_msec() * 0.001
	var u := act_t / maxf(act_dur, 0.001)
	# --- нож и топор в правой руке: кулак сжат
	if (held in ["knife", "axe"] or act == "draw") and not hidden:
		_curl(curl_r, 1.0 if held != "" else _ss(0.3, 0.5, u))
	# --- достать/убрать: кисть к поясу и обратно
	if act in ["draw", "holster"]:
		var id: String = act_data["id"]
		var bt: Transform3D = _gpose("pelvis") * belt_xf[id]
		var reach := sin(PI * clampf(u, 0.0, 1.0))
		var gp := bt.origin + bt.basis.y.normalized() * (0.02 if id == "knife" else 0.36)
		_hold("r", gp, -bt.basis.y if id == "knife" else bt.basis.y, Vector3(0, 0, 1), reach * 0.9)
		if act == "holster":
			_curl(curl_r, 1.0 - _ss(0.5, 0.7, u))
	# --- копьё/лопата
	if (is_long(held) or act == "throw") and not hidden:
		_pose_long(tm, u)
	# --- бревно на плече
	if held == "log" or act in ["take_log", "drop_log"]:
		_pose_log(u)
	# --- рубка лежачего: наклон корпуса, чтобы топор доставал до ствола
	if act in ["trunk", "split"]:
		var bend := 0.55 * _ss(0.0, 0.25, act_t)
		hero._pk_rot(sk, bones["spine_01"], Quaternion(Vector3.RIGHT, bend * 0.45))
		hero._pk_rot(sk, bones["spine_02"], Quaternion(Vector3.RIGHT, bend * 0.55))

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
	if act == "stab":
		# к бою: древко горизонтально у пояса, левая рука впереди; выпад вперёд и назад
		var ready_g := pel + Vector3(-0.17, 0.12, -0.02)
		var ready_a := Vector3(0.06, 0.12, 1.0).normalized()
		var k := _ss(0.0, 0.3, u) * (1.0 - _ss(0.75, 1.0, u))
		var thrust := _ss(0.3, 0.42, u) * (1.0 - _ss(0.55, 0.8, u))
		grip = grip.lerp(ready_g + ready_a * 0.42 * thrust, k)
		axis = axis.slerp(ready_a, k)
		eref = eref.lerp(Vector3(0.7, -0.6, 0.0), k)
		lw = k
		lgrip = grip + axis * (0.5 - 0.15 * thrust)
		leref = Vector3(-0.6, -0.6, 0.0)
		hero._pk_rot(sk, bones["spine_02"], Quaternion(Vector3.UP, 0.25 * k - 0.2 * thrust))
	elif act == "stick":
		var k2 := _ss(0.0, 0.6, u)
		grip = grip + Vector3(-0.03, -0.12 * k2, 0.3 * k2)
		axis = axis.slerp(Vector3(-0.1, 1.0, 0.0).normalized(), k2)
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

## Бревно на правом плече вдоль взгляда; правая рука придерживает спереди, левая — снизу.
func _pose_log(u: float) -> void:
	var s3 := _gpose("spine_03")
	var cl := _gpose("clavicle_r").origin
	var on := Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0.25, 1).normalized(), Vector3.ZERO), cl + Vector3(-0.13, 0.12, 0.05))
	on.basis.z = on.basis.x.cross(on.basis.y).normalized()
	var k := 1.0
	if act == "take_log":
		k = _ss(0.45, 0.95, u)
	elif act == "drop_log":
		k = 1.0 - _ss(0.15, 0.6, u)
	var gnd := Transform3D(Basis(Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)), Vector3(0, 0.13, 0.85))
	if act == "take_log" and u < 0.45:
		log_n.visible = false
	var xf := gnd.interpolate_with(on, k)
	log_n.transform = xf
	var w := clampf(k * 1.5, 0.0, 1.0)
	var front := xf * Vector3(0, 0.42, 0) + Vector3(0, 0.02, 0)
	hero._pk_ik(sk, "r", front + Vector3(0.02, -0.03, -0.06), cl + Vector3(-0.4, -0.3, 0.1), w)
	_curl(curl_r, w * 0.7)
	var under := xf * Vector3(0, 0.12, 0) + Vector3(0.0, -0.1, 0.02)
	hero._pk_ik(sk, "l", under, _gpose("upperarm_l").origin + Vector3(0.3, -0.4, 0.0), w)
	_curl(curl_l, w * 0.5)
	if s3.origin.y < 0.0:
		pass
