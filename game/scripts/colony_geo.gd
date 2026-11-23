extends RefCounted
## --- colony: постройки острога из настоящих брёвен (на той же геометрии, что лагерь). ---
## Амбар на стойках, землянка, острожная стена (прясло), башня и сушило.
## Вход/перед каждой постройки смотрит в +Z, начало координат — на земле.
## prog < 1 — стройка: ставим только часть венцов и без кровли.
##
## Публичное:
##   make(geo, type, prog) -> Node3D   — узел постройки (prog 1.0 — готовая)
##   ghost(geo, type) -> Node3D        — призрак для постановки (готовый вид)

const GEO = preload("res://scripts/build_geo.gd")

static func make(geo, type: String, prog: float = 1.0) -> Node3D:
	match type:
		"storehouse":
			return storehouse(geo, prog)
		"dugout":
			return dugout(geo, prog)
		"palisade":
			return palisade(geo, prog)
		"tower":
			return tower(geo, prog)
		"rack":
			return rack(geo, prog)
	return null

## Призрак: тот же вид, что у готовой постройки (для старых — из build_geo).
static func ghost(geo, type: String) -> Node3D:
	match type:
		"campfire":
			return geo.campfire()
		"leanto":
			return geo.lean_to()
		"tree_shelter":
			return geo.tree_shelter()
		"snow_shelter":
			return geo.snow_shelter()
		"cache":
			return geo.cache()
		"chop_block":
			return geo.chop_block()
		"cabin":
			return geo.cabin(GEO.NC, 1.0, [])
	return make(geo, type, 1.0)

# ---------- амбар ----------

## Амбар: сруб 2,6×2,2 на четырёх стойках (от мышей и сырости), тёсовая кровля
## на два скат, дверца с жердяным засовом, лесенка.
static func storehouse(geo, prog: float) -> Node3D:
	geo.rng.seed = 2201
	var root := Node3D.new()
	var hx := 1.3
	var hz := 1.1
	var fy := 0.42                     # пол над землёй
	# стойки-чурбаки
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var c := Vector3(sx * (hx - 0.2), 0.0, sz * (hz - 0.18))
			geo.logp(c + Vector3(0, -0.12, 0), c + Vector3(0, fy, 0), 0.17, 0.16, GEO.C_LOG, "bark", true, 9, 0.05)
	# лаги и пол
	for k in 3:
		var x := -hx + 0.3 + k * (hx - 0.3)
		geo.logp(Vector3(x, fy + 0.07, -hz), Vector3(x, fy + 0.07, hz), 0.08, 0.08, GEO.C_LOG, "bark")
	for k in 7:
		var z := -hz + 0.1 + k * (hz * 2.0 - 0.2) / 6.0
		geo.box("wood", Transform3D(Basis(), Vector3(0, fy + 0.17, z)), Vector3(hx * 2.0, 0.05, 0.3), GEO.C_PLANK)
	# венцы в обло: полное число 7, на стройке — по доле готовности
	var crowns := int(clampf(prog / 0.8, 0.0, 1.0) * 7.0 + 0.001)
	var r := 0.11
	for i in crowns:
		var y := fy + 0.22 + float(i) * r * 1.85
		var col: Color = GEO.C_LOG.lerp(Color(0.55, 0.46, 0.36), geo.rng.randf() * 0.4)
		if i % 2 == 0:
			geo.logp(Vector3(-hx - 0.16, y, -hz), Vector3(hx + 0.16, y, -hz), r, r * 0.95, col, "bark")
			geo.logp(Vector3(-hx - 0.16, y, hz), Vector3(hx + 0.16, y, hz), r, r * 0.95, col, "bark")
		else:
			# передняя стена с проёмом двери
			geo.logp(Vector3(-hx, y, -hz - 0.16), Vector3(-hx, y, hz + 0.16), r, r * 0.95, col, "bark")
			geo.logp(Vector3(hx, y, -hz - 0.16), Vector3(hx, y, hz + 0.16), r, r * 0.95, col, "bark")
	geo.emit(root, "crib")
	if prog < 0.8:
		return root
	# дверца: тёсаные доски на жердяных навесах
	var dy := fy + 0.25
	for k in 3:
		geo.box("wood", Transform3D(Basis(), Vector3(-0.3 + k * 0.3, dy + 0.5, hz + 0.02)), Vector3(0.28, 1.0, 0.05), GEO.C_PLANK.darkened(0.08))
	geo.logp(Vector3(-0.46, dy + 0.85, hz + 0.06), Vector3(0.46, dy + 0.83, hz + 0.06), 0.03, 0.028, GEO.C_LOG, "bark")
	geo.logp(Vector3(-0.46, dy + 0.3, hz + 0.06), Vector3(0.46, dy + 0.32, hz + 0.06), 0.03, 0.028, GEO.C_LOG, "bark")
	# кровля: стропила и тёс в два ряда
	var top := fy + 0.22 + 7.0 * r * 1.85
	var ridge := top + 0.72
	for sz2: float in [-1.0, 1.0]:
		geo.logp(Vector3(-hx - 0.1, top, sz2 * hz), Vector3(-hx - 0.1, ridge, 0.0), 0.05, 0.04, GEO.C_LOG, "bark")
		geo.logp(Vector3(hx + 0.1, top, sz2 * hz), Vector3(hx + 0.1, ridge, 0.0), 0.05, 0.04, GEO.C_LOG, "bark")
	geo.logp(Vector3(-hx - 0.25, ridge, 0), Vector3(hx + 0.25, ridge, 0), 0.06, 0.055, GEO.C_LOG, "bark")
	for sz3: float in [-1.0, 1.0]:
		var n := 6
		for k in n:
			var x0 := -hx - 0.2 + (hx * 2.0 + 0.4) * float(k) / float(n)
			var x1 := x0 + (hx * 2.0 + 0.4) / float(n) + 0.03
			var a := Vector3(x0, ridge - 0.04, 0.0)
			var b := Vector3(x0, top - 0.06, sz3 * (hz + 0.28))
			geo.quad("wood", a, Vector3(x1, a.y, a.z), Vector3(x1, b.y, b.z), b, GEO.C_ROOF.lerp(GEO.C_PLANK, 0.5) * geo.rng.randf_range(0.9, 1.05))
	geo.emit(root, "roof")
	# лесенка-колода у входа
	geo.logp(Vector3(-0.1, -0.05, hz + 0.75), Vector3(-0.1, fy - 0.02, hz + 0.18), 0.12, 0.11, GEO.C_LOG, "bark")
	geo.logp(Vector3(0.22, -0.05, hz + 0.75), Vector3(0.22, fy - 0.02, hz + 0.18), 0.12, 0.11, GEO.C_LOG, "bark")
	geo.emit(root, "steps")
	return root

# ---------- землянка ----------

## Землянка: врытая в склон клеть, сверху земля и мох, передняя стена из стояков,
## низкий лаз с перекладиной, печурка-дымоход из камней.
static func dugout(geo, prog: float) -> Node3D:
	geo.rng.seed = 3301
	var root := Node3D.new()
	var hx := 1.6
	var hz := 1.3
	var wall := 1.15
	var nst := int(clampf(prog / 0.7, 0.0, 1.0) * 9.0 + 0.001)
	# стояки передней стены (с проёмом в середине)
	for k in nst:
		var x := -hx + 0.18 + float(k) * (hx * 2.0 - 0.36) / 8.0
		if absf(x) < 0.42:
			continue
		geo.logp(Vector3(x, -0.15, hz), Vector3(x + geo.rng.randf_range(-0.03, 0.03), wall, hz), 0.11, 0.1, GEO.C_LOG, "bark")
	if prog >= 0.7:
		geo.logp(Vector3(-0.62, wall - 0.12, hz), Vector3(0.62, wall - 0.12, hz), 0.08, 0.075, GEO.C_LOG, "bark")
		geo.logp(Vector3(-0.46, 0.02, hz + 0.1), Vector3(0.46, 0.02, hz + 0.1), 0.07, 0.07, GEO.C_LOG, "bark")
	geo.emit(root, "front")
	if prog < 0.7:
		return root
	# земляная насыпь: горбатый холм поверх клети, передний склон срезан
	var nu := 10
	for i in nu:
		var t0 := float(i) / float(nu)
		var t1 := float(i + 1) / float(nu)
		var x0 := lerpf(-hx - 0.3, hx + 0.3, t0)
		var x1 := lerpf(-hx - 0.3, hx + 0.3, t1)
		var h0 := wall + 0.5 * sqrt(maxf(1.0 - pow((x0 / (hx + 0.3)) * 1.0, 2.0), 0.0))
		var h1 := wall + 0.5 * sqrt(maxf(1.0 - pow((x1 / (hx + 0.3)) * 1.0, 2.0), 0.0))
		var zb := -hz - 0.7
		var col := Color(0.32, 0.26, 0.19)
		# скат к задней стороне и к передней
		geo.quad("paint", Vector3(x0, h0, hz - 0.1), Vector3(x1, h1, hz - 0.1), Vector3(x1, -0.1, zb), Vector3(x0, -0.1, zb), col)
		geo.quad("paint", Vector3(x0, h0, hz - 0.1), Vector3(x0, -0.05, hz + 0.45), Vector3(x1, -0.05, hz + 0.45), Vector3(x1, h1, hz - 0.1), col.lerp(Color(0.36, 0.3, 0.22), 0.5))
	geo.emit(root, "earth")
	# мох и камни по насыпи
	for k in 8:
		var a: float = geo.rng.randf() * TAU
		var d: float = geo.rng.randf_range(0.2, 1.2)
		geo.pv.rng.seed = 700 + k
		geo.pv.moss_pad(geo.S("moss"), geo.S("moss_card"), Vector3(cos(a) * d, wall + 0.42, sin(a) * d * 0.8 - 0.3), Vector3(0.32, 0.2, 0.32))
	geo.emit(root, "moss", false)
	for k in 5:
		geo.stone(Vector3(geo.rng.randf_range(-hx, hx), wall + 0.3, geo.rng.randf_range(-hz, hz * 0.3)), Vector3(0.16, 0.1, 0.14), geo.rng.randf() * TAU)
	# печурка: камни и дымоход сбоку
	geo.stone(Vector3(hx - 0.2, 0.3, -hz + 0.2), Vector3(0.3, 0.3, 0.28), 0.4)
	geo.stone(Vector3(hx - 0.2, 0.75, -hz + 0.2), Vector3(0.2, 0.22, 0.2), 0.9)
	geo.emit(root, "stones")
	# лапник у лаза
	for k in 4:
		geo.frond(Vector3(-0.5 + k * 0.32, 0.03, hz + 0.3), Vector3(geo.rng.randf_range(-0.4, 0.4), 0.0, 1.0).normalized(), Vector3.UP, 0.6, 0.22, 0.02)
	geo.emit(root, "boughs", false)
	return root

# ---------- острожная стена ----------

## Прясло стены: стоячий тын из заострённых брёвен (3 м), две связи-жерди изнутри.
static func palisade(geo, prog: float) -> Node3D:
	geo.rng.seed = 4401
	var root := Node3D.new()
	var half := 1.5
	var n := 9
	var full := int(clampf(prog / 0.85, 0.0, 1.0) * float(n) + 0.001)
	for k in full:
		var x := -half + 0.17 + float(k) * (half * 2.0 - 0.34) / float(n - 1)
		var h: float = 2.55 + geo.rng.randf_range(-0.07, 0.07)
		var r := 0.115
		geo.logp(Vector3(x, -0.3, geo.rng.randf_range(-0.02, 0.02)), Vector3(x, h - 0.22, 0.0), r, r * 0.95, GEO.C_LOG * geo.rng.randf_range(0.9, 1.08), "bark")
		# заострённый верх
		geo.logp(Vector3(x, h - 0.24, 0.0), Vector3(x, h, 0.0), r * 0.95, 0.012, GEO.C_END, "wood")
	if prog >= 0.85:
		for y: float in [0.85, 1.9]:
			geo.logp(Vector3(-half, y, -0.16), Vector3(half, y + geo.rng.randf_range(-0.03, 0.03), -0.16), 0.055, 0.05, GEO.C_LOG, "bark")
	geo.emit(root, "wall")
	return root

# ---------- башня ----------

## Острожная башня: нижняя клеть в обло, помост, перила и шатёр из тёса.
static func tower(geo, prog: float) -> Node3D:
	geo.rng.seed = 5501
	var root := Node3D.new()
	var h := 1.15
	var r := 0.12
	var crowns := int(clampf(prog / 0.7, 0.0, 1.0) * 12.0 + 0.001)
	for i in crowns:
		var y := -0.1 + float(i) * r * 1.85
		var col: Color = GEO.C_LOG * geo.rng.randf_range(0.92, 1.06)
		if i % 2 == 0:
			geo.logp(Vector3(-h - 0.16, y, -h), Vector3(h + 0.16, y, -h), r, r * 0.95, col, "bark")
			geo.logp(Vector3(-h - 0.16, y, h), Vector3(h + 0.16, y, h), r, r * 0.95, col, "bark")
		else:
			geo.logp(Vector3(-h, y, -h - 0.16), Vector3(-h, y, h + 0.16), r, r * 0.95, col, "bark")
			geo.logp(Vector3(h, y, -h - 0.16), Vector3(h, y, h + 0.16), r, r * 0.95, col, "bark")
	geo.emit(root, "crib")
	if prog < 0.7:
		return root
	var fy := -0.1 + 12.0 * r * 1.85
	# помост
	for k in 7:
		var z := -h + 0.1 + float(k) * (h * 2.0 - 0.2) / 6.0
		geo.box("wood", Transform3D(Basis(), Vector3(0, fy + 0.08, z)), Vector3(h * 2.4, 0.06, 0.32), GEO.C_PLANK)
	# перила и стойки шатра
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			geo.logp(Vector3(sx * h * 1.1, fy + 0.1, sz * h * 1.1), Vector3(sx * h * 0.95, fy + 1.35, sz * h * 0.95), 0.06, 0.05, GEO.C_LOG, "bark")
	for sz2: float in [-1.0, 1.0]:
		geo.logp(Vector3(-h * 1.05, fy + 0.62, sz2 * h * 1.05), Vector3(h * 1.05, fy + 0.62, sz2 * h * 1.05), 0.04, 0.038, GEO.C_LOG, "bark")
	for sx2: float in [-1.0, 1.0]:
		geo.logp(Vector3(sx2 * h * 1.05, fy + 0.62, -h * 1.05), Vector3(sx2 * h * 1.05, fy + 0.62, h * 1.05), 0.04, 0.038, GEO.C_LOG, "bark")
	# шатёр: четыре тёсаных скатa к шпилю
	var apex := Vector3(0, fy + 2.25, 0)
	var e: Array = [Vector3(-h * 1.25, fy + 1.35, -h * 1.25), Vector3(h * 1.25, fy + 1.35, -h * 1.25), Vector3(h * 1.25, fy + 1.35, h * 1.25), Vector3(-h * 1.25, fy + 1.35, h * 1.25)]
	for i in 4:
		var a: Vector3 = e[i]
		var b: Vector3 = e[(i + 1) % 4]
		var nseg := 4
		for k in nseg:
			var t0 := float(k) / float(nseg)
			var t1 := float(k + 1) / float(nseg)
			var p0 := a.lerp(b, t0)
			var p1 := a.lerp(b, t1)
			geo.tri("wood", p0, p1, apex, GEO.C_ROOF * geo.rng.randf_range(0.92, 1.06))
	geo.emit(root, "roof")
	return root

# ---------- сушило ----------

## Сушило: две рогатины, перекладина, на ней вялятся рыба и полоски мяса.
static func rack(geo, prog: float) -> Node3D:
	geo.rng.seed = 6601
	var root := Node3D.new()
	var half := 1.15
	for sx: float in [-1.0, 1.0]:
		var p := Vector3(sx * half, 0, 0)
		geo.logp(p + Vector3(0, -0.2, 0), p + Vector3(sx * 0.04, 1.75, 0), 0.055, 0.045, GEO.C_LOG, "bark")
		geo.logp(p + Vector3(sx * 0.04, 1.62, 0), p + Vector3(sx * 0.14, 1.9, 0.04), 0.03, 0.02, GEO.C_LOG, "bark")
		geo.logp(p + Vector3(sx * 0.04, 1.62, 0), p + Vector3(-sx * 0.05, 1.88, -0.04), 0.03, 0.02, GEO.C_LOG, "bark")
	geo.logp(Vector3(-half - 0.22, 1.78, 0), Vector3(half + 0.22, 1.8, 0), 0.045, 0.04, GEO.C_LOG, "bark")
	geo.logp(Vector3(-half - 0.18, 1.1, 0.02), Vector3(half + 0.18, 1.12, 0.02), 0.035, 0.03, GEO.C_LOG, "bark")
	geo.emit(root, "frame")
	if prog < 0.9:
		return root
	# рыба и мясо на жердях
	for k in 7:
		var x := -half + 0.2 + float(k) * (half * 2.0 - 0.4) / 6.0
		var hang := Vector3(x, 1.72, 0.0)
		geo.logp(hang, hang + Vector3(0, -0.12, 0), 0.006, 0.006, GEO.C_FIBER, "paint", false, 4, 0.0)
		if k % 2 == 0:
			# рыбка: плоская карточка-ромб
			var c := hang + Vector3(0, -0.34, 0)
			geo.quad("paint", c + Vector3(-0.07, 0.22, 0), c + Vector3(0.07, 0.22, 0), c + Vector3(0.05, -0.2, 0.01), c + Vector3(-0.05, -0.2, 0.01), Color(0.64, 0.6, 0.52))
		else:
			var c2 := hang + Vector3(0, -0.3, 0)
			geo.box("paint", Transform3D(Basis(Vector3.UP, geo.rng.randf_range(-0.2, 0.2)), c2), Vector3(0.1, 0.34, 0.03), Color(0.5, 0.21, 0.17))
	geo.emit(root, "goods", false)
	return root
