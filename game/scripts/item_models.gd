extends RefCounted
## --- core: 3D-модели всех вещей из items.gd (геометрия, не «капли»): для вещей на земле
## (hunt.drop_item) и для значков/миниатюр справочника (студия STUDIO=icons → res://icons).
## Инструменты — tool_models.gd, мясо и шкура — hunt_models.gd, остальное собрано здесь
## из примитивов build_geo.gd (тела вращения, жерди, бруски, гранёные камни).
## make(id) -> Node3D (начало координат — низ вещи, на земле).

const TM = preload("res://scripts/tool_models.gd")
const HM = preload("res://scripts/hunt_models.gd")
const GEO = preload("res://scripts/build_geo.gd")

const C_WOOD := Color(0.62, 0.47, 0.3)
const C_WOOD_D := Color(0.45, 0.32, 0.2)
const C_CLAY_F := Color(0.56, 0.34, 0.24)   # обожжённая глина
const C_CLAY := Color(0.55, 0.47, 0.38)     # сырая
const C_SOUP := Color(0.5, 0.33, 0.16)
const C_TEA := Color(0.55, 0.36, 0.12)
const C_WATER := Color(0.32, 0.45, 0.5)

var geo
var pv

func _init(p_pv) -> void:
	pv = p_pv
	geo = GEO.new(pv)

## Модель вещи (или null, если делать нечего).
func make(id: String) -> Node3D:
	var root := Node3D.new()
	geo.rng.seed = id.hash()
	var tm := TM.mesh_of(id)
	if tm != null:
		# инструмент лежит на боку
		var mi := MeshInstance3D.new()
		mi.mesh = tm
		mi.rotation = Vector3(0, 0, PI * 0.5)
		mi.position.y = 0.03
		root.add_child(mi)
		return root
	match id:
		"meat_raw", "meat_cooked":
			for i in 2:
				var mi2 := MeshInstance3D.new()
				mi2.mesh = HM.meat_mesh(11 + i, id == "meat_cooked")
				mi2.position = Vector3(i * 0.1 - 0.05, 0.0, i * 0.05)
				mi2.rotation.y = i * 1.3
				root.add_child(mi2)
			return root
		"hide", "fur":
			var mi3 := MeshInstance3D.new()
			var flat := func(_x: float, _z: float) -> float: return 0.0
			mi3.mesh = HM.hide_mesh(0.9, Color(0.5, 0.36, 0.24) if id == "hide" else Color(0.42, 0.3, 0.2), Color(0.8, 0.72, 0.6), 7, flat)
			root.add_child(mi3)
			return root
		"carcass_small":
			var n := Node3D.new()
			root.add_child(n)
			preload("res://scripts/animal_model.gd").build(n, "hare", 1.0, true, false)
			n.rotation = Vector3(0, 0.5, PI * 0.5)
			n.position.y = 0.07
			return root
	_build(id)
	geo.emit(root, id, true)
	return root

func _build(id: String) -> void:
	var g = geo
	match id:
		"berry":
			for k in 9:
				var a := k * 2.4
				var d := 0.025 * sqrt(float(k))
				g.stone_like("paint", Vector3(cos(a) * d, 0.012 + (0.01 if k < 3 else 0.0), sin(a) * d), Vector3(0.011, 0.011, 0.011), Basis(), Color(0.7, 0.1, 0.12))
			for k in 3:
				var a2 := k * 2.1
				g.tri("paint", Vector3(0, 0.02, 0), Vector3(cos(a2) * 0.07, 0.01, sin(a2) * 0.07), Vector3(cos(a2 + 0.4) * 0.05, 0.015, sin(a2 + 0.4) * 0.05), Color(0.25, 0.42, 0.18))
		"mushroom", "amanita":
			var red := id == "amanita"
			g.lathe("paint", Vector3.ZERO, [Vector2(0.018, 0), Vector2(0.016, 0.06), Vector2(0.012, 0.075), Vector2(0.0, 0.075)], Color(0.94, 0.9, 0.82), 10)
			var cap := Color(0.78, 0.12, 0.08) if red else Color(0.5, 0.31, 0.16)
			g.lathe("paint", Vector3(0, 0.06, 0), [Vector2(0.0, 0.0), Vector2(0.045, 0.004), Vector2(0.05, 0.015), Vector2(0.038, 0.04), Vector2(0.0, 0.05)], cap, 14)
			if red:
				for k in 6:
					var a3 := k * 1.1
					g.stone_like("paint", Vector3(cos(a3) * 0.03, 0.098 - 0.006 * (k % 2), sin(a3) * 0.03), Vector3(0.005, 0.003, 0.005), Basis(), Color(0.97, 0.95, 0.9))
		"twig":
			for k in 4:
				var a4 := k * 0.5 - 0.7
				g.logp(Vector3(-0.22, 0.012 + k * 0.012, a4 * 0.1), Vector3(0.22, 0.015 + k * 0.01, -a4 * 0.08), 0.009, 0.006, Color(0.42, 0.3, 0.2), "bark", true, 5, 0.1)
		"pebble":
			g.stone_like("facet_n", Vector3(0, 0.035, 0), Vector3(0.07, 0.04, 0.055), Basis(Vector3.UP, 0.4), Color(0.55, 0.55, 0.52))
			g.stone_like("facet_n", Vector3(0.08, 0.025, 0.04), Vector3(0.04, 0.028, 0.035), Basis(), Color(0.46, 0.46, 0.44))
		"flint":
			g.stone_like("facet", Vector3(0, 0.02, 0), Vector3(0.06, 0.022, 0.035), Basis(Vector3.UP, 0.8), Color(0.33, 0.3, 0.29))
		"bark":
			# свёрнутая лента бересты
			for k in 10:
				var t0 := k / 10.0
				var t1 := (k + 1) / 10.0
				var a0 := t0 * PI * 1.4
				var a1 := t1 * PI * 1.4
				var r0 := 0.05 - t0 * 0.015
				var r1 := 0.05 - t1 * 0.015
				var p0 := Vector3(cos(a0) * r0, 0.05 + sin(a0) * r0, 0)
				var p1 := Vector3(cos(a1) * r1, 0.05 + sin(a1) * r1, 0)
				g.quad("paint", p0 + Vector3(0, 0, -0.12), p1 + Vector3(0, 0, -0.12), p1 + Vector3(0, 0, 0.12), p0 + Vector3(0, 0, 0.12), Color(0.93, 0.9, 0.82) if k % 3 != 1 else Color(0.8, 0.76, 0.68))
		"fiber":
			for k in 7:
				var o := (k - 3) * 0.008
				g.logp(Vector3(-0.2, 0.01 + absf(o), o), Vector3(0.2, 0.012, o * 1.4), 0.004, 0.003, Color(0.66, 0.56, 0.36).darkened(k * 0.03), "paint", true, 4, 0.0)
			g.lashing(Vector3(0, 0.012, 0), Vector3.RIGHT, 0.02)
		"branch":
			g.logp(Vector3(-0.7, 0.025, 0), Vector3(0.7, 0.02, 0.02), 0.025, 0.016, GEO.C_LOG, "bark")
			g.logp(Vector3(0.2, 0.025, 0.0), Vector3(0.32, 0.03, 0.12), 0.01, 0.006, GEO.C_LOG, "bark")
		"spruce_twigs":
			for k in 3:
				g.frond(Vector3(-0.3, 0.03 + k * 0.02, (k - 1) * 0.1), Vector3(1, 0.05, (k - 1) * 0.15), Vector3.UP, 0.6, 0.22)
		"log":
			g.logp(Vector3(-0.62, 0.13, 0), Vector3(0.62, 0.13, 0), 0.13, 0.12, GEO.C_LOG, "bark")
		"firewood":
			for k in 3:
				var y := 0.05 + (0.07 if k == 2 else 0.0)
				var z := (k - 0.5) * 0.09 if k < 2 else 0.0
				g._split_wood(Vector3(-0.2, y, z), Vector3(0.2, y, z), 0.04)
		"plank":
			g.box("wood", Transform3D(Basis(), Vector3(0, 0.02, 0)), Vector3(1.2, 0.04, 0.22), GEO.C_PLANK)
			g.box("wood", Transform3D(Basis(Vector3.UP, 0.15), Vector3(0.05, 0.06, 0.04)), Vector3(1.1, 0.04, 0.2), GEO.C_PLANK * 0.93)
		"clay":
			g.stone_like("paint", Vector3(0, 0.05, 0), Vector3(0.09, 0.05, 0.08), Basis(Vector3.UP, 0.3), C_CLAY)
			g.stone_like("paint", Vector3(0.07, 0.03, 0.05), Vector3(0.05, 0.03, 0.045), Basis(), C_CLAY * 0.92)
		"moss":
			pv.moss_pad(g.S("moss"), g.S("moss_card"), Vector3(0, 0.03, 0), Vector3(0.16, 0.1, 0.14))
		"bandage":
			g.lathe("paint", Vector3.ZERO, [Vector2(0.0, 0.0), Vector2(0.035, 0.0), Vector2(0.038, 0.06), Vector2(0.035, 0.12), Vector2(0.0, 0.12)], GEO.C_LINEN, 12)
			g.quad("paint", Vector3(0.036, 0.0, -0.02), Vector3(0.036, 0.0, 0.02), Vector3(0.16, 0.0, 0.03), Vector3(0.16, 0.0, -0.03), GEO.C_LINEN * 0.95)
		"fish_raw", "fish_cooked", "fish_dried":
			var col := Color(0.6, 0.62, 0.6) if id == "fish_raw" else (Color(0.66, 0.46, 0.22) if id == "fish_cooked" else Color(0.55, 0.42, 0.26))
			# веретено на боку: голова → спина → хвост, хвостовой плавник
			g.logp(Vector3(-0.18, 0.04, 0), Vector3(-0.02, 0.045, 0), 0.02, 0.042, col, "paint", true, 10, 0.02)
			g.logp(Vector3(-0.02, 0.045, 0), Vector3(0.15, 0.04, 0), 0.042, 0.012, col, "paint", true, 10, 0.02)
			g.tri("paint", Vector3(0.14, 0.04, 0), Vector3(0.22, 0.08, 0), Vector3(0.22, 0.0, 0), col * 0.85)
			g.tri("paint", Vector3(0.14, 0.04, 0), Vector3(0.22, 0.0, 0), Vector3(0.22, 0.08, 0), col * 0.85)
			g.tri("paint", Vector3(-0.04, 0.08, 0), Vector3(0.04, 0.1, 0), Vector3(0.06, 0.075, 0), col * 0.8)
		"meat_dried":
			for k in 3:
				g.box("paint", Transform3D(Basis(Vector3.UP, k * 0.3), Vector3(k * 0.04, 0.01 + k * 0.012, k * 0.02)), Vector3(0.22, 0.012, 0.05), Color(0.42, 0.18, 0.12))
			g.lashing(Vector3(0.03, 0.03, 0.02), Vector3.FORWARD, 0.02)
		"fur_hat":
			g.lathe("fur", Vector3.ZERO, [Vector2(0.0, 0.0), Vector2(0.12, 0.0), Vector2(0.13, 0.05), Vector2(0.11, 0.12), Vector2(0.06, 0.17), Vector2(0.0, 0.18)], Color(0.45, 0.33, 0.22), 14)
			g.lathe("fur", Vector3(0, 0.0, 0), [Vector2(0.11, 0.0), Vector2(0.15, 0.01), Vector2(0.15, 0.05), Vector2(0.11, 0.06)], Color(0.55, 0.42, 0.3), 14)
		"fur_coat":
			g.lathe("fur", Vector3.ZERO, [Vector2(0.0, 0.0), Vector2(0.3, 0.0), Vector2(0.26, 0.4), Vector2(0.22, 0.75), Vector2(0.12, 0.82), Vector2(0.0, 0.82)], Color(0.44, 0.32, 0.22), 14)
			for sx: float in [-1.0, 1.0]:
				g.logp(Vector3(sx * 0.2, 0.74, 0), Vector3(sx * 0.42, 0.3, 0.05), 0.08, 0.07, Color(0.42, 0.31, 0.21), "fur")
			g.box("paint", Transform3D(Basis(), Vector3(0, 0.45, 0.24)), Vector3(0.03, 0.75, 0.02), Color(0.3, 0.2, 0.12))
		"fur_boots":
			for sx2: float in [-0.09, 0.09]:
				g.logp(Vector3(sx2, 0.0, -0.02), Vector3(sx2, 0.26, -0.02), 0.06, 0.055, Color(0.45, 0.33, 0.22), "fur")
				g.logp(Vector3(sx2, 0.04, -0.02), Vector3(sx2, 0.04, 0.14), 0.045, 0.04, Color(0.38, 0.28, 0.18), "fur")
		# ---------- деревянная утварь ----------
		"handle":
			g.logp(Vector3(-0.3, 0.025, 0), Vector3(0.0, 0.022, 0.0), 0.02, 0.018, C_WOOD, "wood")
			g.logp(Vector3(0.0, 0.022, 0), Vector3(0.28, 0.03, 0.04), 0.018, 0.024, C_WOOD, "wood")
		"spoon":
			g.lathe("wood", Vector3(0.09, 0.0, 0), [Vector2(0.0, 0.0), Vector2(0.025, 0.004), Vector2(0.032, 0.014), Vector2(0.028, 0.016), Vector2(0.0, 0.008)], C_WOOD, 10)
			g.logp(Vector3(0.06, 0.012, 0), Vector3(-0.12, 0.03, 0), 0.007, 0.008, C_WOOD, "wood", true, 6, 0.0)
		"mug":
			_cup(Vector3.ZERO, 0.045, 0.1, C_WOOD, "wood")
			g.logp(Vector3(0.05, 0.03, 0), Vector3(0.075, 0.05, 0), 0.008, 0.008, C_WOOD_D, "wood", true, 6, 0.0)
			g.logp(Vector3(0.075, 0.05, 0), Vector3(0.05, 0.08, 0), 0.008, 0.008, C_WOOD_D, "wood", true, 6, 0.0)
		"bowl", "clay_bowl":
			var cb := C_WOOD if id == "bowl" else C_CLAY_F
			var key := "wood" if id == "bowl" else "paint"
			g.lathe(key, Vector3.ZERO, [Vector2(0.0, 0.0), Vector2(0.05, 0.0), Vector2(0.1, 0.04), Vector2(0.11, 0.065), Vector2(0.1, 0.065), Vector2(0.085, 0.03), Vector2(0.0, 0.012)], cb, 16)
		"ladle":
			g.lathe("wood", Vector3(0.0, 0.0, 0), [Vector2(0.0, 0.0), Vector2(0.04, 0.005), Vector2(0.05, 0.035), Vector2(0.045, 0.04), Vector2(0.0, 0.012)], C_WOOD, 12)
			g.logp(Vector3(0.045, 0.035, 0), Vector3(0.32, 0.12, 0), 0.009, 0.008, C_WOOD, "wood", true, 6, 0.0)
		# ---------- глина ----------
		"clay_pot":
			g.lathe("paint", Vector3.ZERO, [Vector2(0.0, 0.0), Vector2(0.07, 0.0), Vector2(0.11, 0.07), Vector2(0.105, 0.14), Vector2(0.08, 0.17), Vector2(0.09, 0.185), Vector2(0.08, 0.185), Vector2(0.07, 0.17), Vector2(0.0, 0.06)], C_CLAY_F, 16)
			for k in 2:
				g.lathe("paint", Vector3(0, 0.1 + k * 0.025, 0), [Vector2(0.108, 0.0), Vector2(0.112, 0.004), Vector2(0.108, 0.008)], C_CLAY_F * 0.8, 16)
		"jug", "water":
			g.lathe("paint", Vector3.ZERO, [Vector2(0.0, 0.0), Vector2(0.06, 0.0), Vector2(0.09, 0.08), Vector2(0.075, 0.15), Vector2(0.035, 0.2), Vector2(0.03, 0.25), Vector2(0.04, 0.26), Vector2(0.025, 0.26), Vector2(0.0, 0.2)], C_CLAY_F, 14)
			g.logp(Vector3(0.03, 0.235, 0), Vector3(0.095, 0.2, 0), 0.01, 0.01, C_CLAY_F * 0.9, "paint", true, 6, 0.0)
			g.logp(Vector3(0.095, 0.2, 0), Vector3(0.08, 0.11, 0), 0.01, 0.01, C_CLAY_F * 0.9, "paint", true, 6, 0.0)
			if id == "water":
				g.lathe("paint", Vector3(0, 0.25, 0), [Vector2(0.0, 0.0), Vector2(0.026, 0.0)], C_WATER, 10)
		"oil_lamp":
			g.lathe("paint", Vector3.ZERO, [Vector2(0.0, 0.0), Vector2(0.04, 0.0), Vector2(0.07, 0.03), Vector2(0.065, 0.04), Vector2(0.05, 0.02), Vector2(0.0, 0.015)], C_CLAY_F, 14)
			g.tri("paint", Vector3(0.05, 0.035, -0.02), Vector3(0.11, 0.04, 0.0), Vector3(0.05, 0.035, 0.02), C_CLAY_F * 0.9)
			g.logp(Vector3(0.09, 0.035, 0), Vector3(0.1, 0.055, 0), 0.004, 0.004, GEO.C_FIBER, "paint", true, 5, 0.0)
			g.stone_like("paint_f", Vector3(0.1, 0.07, 0), Vector3(0.008, 0.02, 0.008), Basis(), Color(1.0, 0.75, 0.3))
		"fat":
			g.lathe("paint", Vector3.ZERO, [Vector2(0.0, 0.0), Vector2(0.06, 0.0), Vector2(0.065, 0.03), Vector2(0.0, 0.04)], Color(0.92, 0.88, 0.74), 12)
		"stew", "fish_soup":
			g.lathe("paint", Vector3.ZERO, [Vector2(0.0, 0.0), Vector2(0.05, 0.0), Vector2(0.1, 0.04), Vector2(0.11, 0.065), Vector2(0.1, 0.065), Vector2(0.085, 0.03), Vector2(0.0, 0.012)], C_CLAY_F, 16)
			g.lathe("paint", Vector3(0, 0.05, 0), [Vector2(0.0, 0.0), Vector2(0.098, 0.0)], C_SOUP if id == "stew" else Color(0.75, 0.66, 0.42), 16)
			for k in 4:
				var a5 := k * 1.6
				g.stone_like("paint", Vector3(cos(a5) * 0.05, 0.055, sin(a5) * 0.05), Vector3(0.018, 0.01, 0.015), Basis(), Color(0.45, 0.24, 0.15) if id == "stew" else Color(0.85, 0.8, 0.7))
		"broth", "tea":
			_cup(Vector3.ZERO, 0.045, 0.1, C_WOOD, "wood")
			g.lathe("paint", Vector3(0, 0.085, 0), [Vector2(0.0, 0.0), Vector2(0.04, 0.0)], C_TEA if id == "tea" else C_SOUP, 12)
			if id == "tea":
				g.frond(Vector3(0.02, 0.09, 0.0), Vector3(0.6, 1.0, 0.1), Vector3.FORWARD, 0.05, 0.025)
		_:
			g.stone_like("paint", Vector3(0, 0.04, 0), Vector3(0.06, 0.04, 0.06), Basis(), Color(0.5, 0.42, 0.3))


## Кружка/туесок: стенка снаружи и внутри, дно.
func _cup(c: Vector3, r: float, h: float, col: Color, key: String) -> void:
	geo.lathe(key, c, [Vector2(0.0, 0.0), Vector2(r, 0.0), Vector2(r * 1.05, h), Vector2(r * 0.88, h), Vector2(r * 0.85, h * 0.15), Vector2(0.0, h * 0.15)], col, 14)
