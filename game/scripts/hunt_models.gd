extends RefCounted
## Модели охоты из геометрии (без «пластилина»): шкура, распластанная по земле (контур
## настоящей снятой шкуры — шея, передние и задние лапы, хвост — сетка внутри контура
## ложится по рельефу), кусок мяса (гранёная призма среза с полосой жира, у части — ребро),
## кости (позвонки, дуги рёбер, череп, таз и трубчатые кости), освежёванная туша — материал
## на модели самого зверя (carcass.gdshader).

static var _mats := {}

static func lin_c(c: Color) -> Color:
	return c

static func flesh_mat(key: String) -> ShaderMaterial:
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/flesh.gdshader")
	match key:
		"bone", "fat", "underside":
			m.set_shader_parameter("fibre", 0.0)
		"cooked":
			m.set_shader_parameter("cooked", 1.0)
		"dry":
			m.set_shader_parameter("dry", 1.0)
	_mats[key] = m
	return m

static func fur_mat() -> ShaderMaterial:
	if _mats.has("fur"):
		return _mats["fur"]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/paint/fur.gdshader")
	m.set_shader_parameter("use_vc", true)
	_mats["fur"] = m
	return m

# ---------- шкура ----------

# правая половина контура снятой шкуры (x ≥ 0), длина 1: z +0.56 — шея, −0.6 — хвост
const HIDE_R := [[0.0, 0.56], [0.05, 0.55], [0.07, 0.45], [0.12, 0.36], [0.3, 0.41], [0.44, 0.38], [0.47, 0.32],
	[0.4, 0.29], [0.24, 0.24], [0.2, 0.05], [0.21, -0.14], [0.26, -0.22], [0.42, -0.3], [0.47, -0.38],
	[0.42, -0.42], [0.24, -0.38], [0.1, -0.46], [0.05, -0.58], [0.0, -0.61]]

## Распластанная шкура: L — длина (м), col/belly — цвет спины и брюха, ground(x, z) — высота
## земли под точкой в осях узла (шкура повторяет рельеф и снег). Поверхность 0 — мех, 1 — мездра.
static func hide_mesh(L: float, col: Color, belly: Color, seed_v: int, ground: Callable) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var outline := PackedVector2Array()
	var half: Array = []
	for p: Array in HIDE_R:
		half.append(Vector2(float(p[0]) + rng.randf_range(-0.015, 0.015) * (0.0 if float(p[0]) == 0.0 else 1.0), float(p[1]) + rng.randf_range(-0.015, 0.015)))
	for v: Vector2 in half:
		outline.append(v)
	for i in range(half.size() - 2, 0, -1):
		var v: Vector2 = half[i]
		outline.append(Vector2(-v.x + rng.randf_range(-0.012, 0.012), v.y + rng.randf_range(-0.012, 0.012)))
	# контур — с шагом ~3 см (в долях длины), чтобы треугольники не перескакивали выемки
	var dense := PackedVector2Array()
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		var n := maxi(1, int(ceil(a.distance_to(b) / 0.035)))
		for k in n:
			dense.append(a.lerp(b, float(k) / n))
	var pts := dense.duplicate()
	var nb := dense.size()
	var step := 0.05
	var y0 := -0.62
	while y0 < 0.6:
		var x0 := -0.5
		while x0 < 0.5:
			var q := Vector2(x0 + rng.randf_range(-0.01, 0.01), y0 + rng.randf_range(-0.01, 0.01))
			if Geometry2D.is_point_in_polygon(q, dense) and _edge_dist(q, dense) > 0.02:
				pts.append(q)
			x0 += step
		y0 += step * 0.87
	var tri := Geometry2D.triangulate_delaunay(pts)
	var keep := PackedInt32Array()
	for t in range(0, tri.size(), 3):
		var c := (pts[tri[t]] + pts[tri[t + 1]] + pts[tri[t + 2]]) / 3.0
		if Geometry2D.is_point_in_polygon(c, dense):
			# одинаковый обход: Делоне отдаёт треугольники вперемешку по и против часовой
			var p0 := pts[tri[t]]
			var e1 := pts[tri[t + 1]] - p0
			var e2 := pts[tri[t + 2]] - p0
			# верх (обход 0, 2, 1) смотрит вверх при таком знаке (проверено в студии)
			if e1.y * e2.x - e1.x * e2.y > 0.0:
				keep.append(tri[t]); keep.append(tri[t + 1]); keep.append(tri[t + 2])
			else:
				keep.append(tri[t]); keep.append(tri[t + 2]); keep.append(tri[t + 1])
	# высоты: по земле, лёгкие складки, края чуть загнуты вверх
	var th := 0.008 + 0.006 * L
	var tops := PackedVector3Array()
	var bots := PackedVector3Array()
	var cols := PackedColorArray()
	var ph := rng.randf() * TAU
	for i in pts.size():
		var q := pts[i]
		var x := q.x * L
		var z := q.y * L
		var e := 0.0 if i < nb else _edge_dist(q, dense)
		var fold := 0.012 * L * (sin(q.x * 9.0 + ph) * cos(q.y * 7.0 - ph) * 0.5 + 0.5)
		var curl := 0.018 * L * (1.0 - smoothstep(0.0, 0.07, e))
		var g: float = ground.call(x, z)
		var y := g + 0.012 + fold + curl
		bots.append(Vector3(x, y, z))
		tops.append(Vector3(x, y + th, z))
		# мех: вдоль хребта темнее, к краям — цвет брюха; ремень на хребте
		var k := smoothstep(0.06, 0.36, absf(q.x))
		var cc := col.lerp(belly, k * 0.85) * (0.85 if absf(q.x) < 0.035 else 1.0)
		cols.append(cc)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in range(0, keep.size(), 3):
		for k in [0, 2, 1]:
			var i: int = keep[t + k]
			st.set_color(cols[i])
			st.set_uv(Vector2(pts[i].x * 2.0, pts[i].y * 6.0))
			st.add_vertex(tops[i])
	st.index()
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, fur_mat())
	# мездра и срез по краю
	var sb := SurfaceTool.new()
	sb.begin(Mesh.PRIMITIVE_TRIANGLES)
	var under := Color(0.86, 0.74, 0.64, 0.45)
	for t in range(0, keep.size(), 3):
		for k in [0, 1, 2]:
			var i: int = keep[t + k]
			sb.set_color(under)
			sb.set_uv(pts[i] * 3.0)
			sb.add_vertex(bots[i])
	for i in nb:
		var j := (i + 1) % nb
		for v: Vector3 in [bots[i], tops[i], tops[j], bots[i], tops[j], bots[j], bots[i], tops[j], tops[i], bots[i], bots[j], tops[j]]:
			sb.set_color(Color(0.8, 0.62, 0.55, 0.5))
			sb.set_uv(Vector2(float(i) * 0.1, v.y))
			sb.add_vertex(v)
	sb.generate_normals()
	sb.commit(mesh)
	mesh.surface_set_material(1, flesh_mat("underside"))
	return mesh

static func _edge_dist(q: Vector2, poly: PackedVector2Array) -> float:
	var best := 1e9
	for i in poly.size():
		var cp := Geometry2D.get_closest_point_to_segment(q, poly[i], poly[(i + 1) % poly.size()])
		best = minf(best, q.distance_to(cp))
	return best

# ---------- мясо ----------

## Кусок мяса: гранёный срез (призма с фаской), с одной стороны полоса белого жира,
## у каждого третьего — торчащее ребро. Плоские нормали: видны грани разреза.
static func meat_mesh(seed_v: int, cooked: bool = false) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var n := rng.randi_range(6, 8)
	var rx := rng.randf_range(0.07, 0.11)
	var rz := rng.randf_range(0.045, 0.07)
	var h := rng.randf_range(0.035, 0.05)
	var ring: Array = []
	for i in n:
		var a := TAU * float(i) / n + rng.randf_range(-0.3, 0.3)
		var k := rng.randf_range(0.75, 1.15)
		ring.append(Vector3(cos(a) * rx * k, 0.0, sin(a) * rz * k))
	var red := Color(0.56, 0.17, 0.14, 0.55)
	var dark := Color(0.44, 0.13, 0.11, 0.45)
	var fat := Color(0.93, 0.87, 0.74, 0.6)
	if cooked:
		red = Color(0.45, 0.25, 0.13, 0.3)
		dark = Color(0.32, 0.17, 0.09, 0.2)
		fat = Color(0.72, 0.56, 0.32, 0.3)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Vector3(rng.randf_range(-0.015, 0.015), h + 0.014, rng.randf_range(-0.01, 0.01))
	var inset := 0.9
	for i in n:
		var a: Vector3 = ring[i]
		var b: Vector3 = ring[(i + 1) % n]
		var fat_side: bool = (a.x + b.x) > rx * 0.5
		var cw := fat if fat_side else dark
		var ct := red
		var a_t := Vector3(a.x * inset, h, a.z * inset)
		var b_t := Vector3(b.x * inset, h, b.z * inset)
		var a_m := Vector3(a.x, h * 0.78, a.z)
		var b_m := Vector3(b.x, h * 0.78, b.z)
		# верх (срез), фаска, бок, низ
		_tri(st, top, b_t, a_t, ct, Vector2(0.5, 0.5), Vector2(b.x * 6.0, b.z * 6.0), Vector2(a.x * 6.0, a.z * 6.0))
		_quad(st, a_t, b_t, b_m, a_m, fat if fat_side else red)
		_quad(st, a_m, b_m, b, a, cw)
		_tri(st, Vector3.ZERO, a, b, dark, Vector2(0.5, 0.5), Vector2(0, 0), Vector2(1, 0))
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, flesh_mat("cooked" if cooked else "meat"))
	if rng.randf() < 0.34:
		# ребро: косточка поперёк куска, концы торчат наружу
		var sb := SurfaceTool.new()
		sb.begin(Mesh.PRIMITIVE_TRIANGLES)
		var y := h * 0.55
		var z := rng.randf_range(-0.015, 0.015)
		_tube(sb, [Vector3(-rx * 1.12, y, z), Vector3(0, y + 0.004, z + 0.004), Vector3(rx * 1.1, y - 0.002, z)], [0.008, 0.0075, 0.007], 6, Color(0.9, 0.85, 0.74, 0.4))
		sb.generate_normals()
		sb.commit(mesh)
		mesh.surface_set_material(1, flesh_mat("bone"))
	return mesh

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	# лицевая сторона в Godot — по часовой, если смотреть на неё: пишем a, c, b
	st.set_color(col)
	st.set_uv(ua)
	st.add_vertex(a)
	st.set_uv(uc)
	st.add_vertex(c)
	st.set_uv(ub)
	st.add_vertex(b)

## Четырёхугольник a-b-c-d (наружу при обходе a→b→c→d по часовой, если смотреть снаружи).
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	var u0 := Vector2(0, a.y * 10.0)
	var u1 := Vector2(a.distance_to(b) * 10.0, a.y * 10.0)
	_tri(st, a, c, b, col, u0, Vector2(u1.x, c.y * 10.0), u1)
	_tri(st, a, d, c, col, u0, Vector2(0, d.y * 10.0), Vector2(u1.x, c.y * 10.0))

## Труба по точкам pts с радиусами rs, sides граней, с торцами.
static func _tube(st: SurfaceTool, pts: Array, rs: Array, sides: int, col: Color) -> void:
	var rows: Array = []
	var ref := Vector3.UP
	for i in pts.size():
		var p: Vector3 = pts[i]
		var tg: Vector3
		if i == 0:
			tg = (pts[1] as Vector3) - p
		elif i == pts.size() - 1:
			tg = p - (pts[i - 1] as Vector3)
		else:
			tg = (pts[i + 1] as Vector3) - (pts[i - 1] as Vector3)
		tg = tg.normalized()
		if absf(tg.dot(ref)) > 0.95:
			ref = Vector3.RIGHT
		var nn := tg.cross(ref).normalized()
		var bb := tg.cross(nn).normalized()
		ref = bb
		var row: Array = []
		for j in sides + 1:
			var a := TAU * float(j) / sides
			row.append(p + (nn * cos(a) + bb * sin(a)) * float(rs[i]))
		rows.append(row)
	st.set_color(col)
	for i in pts.size() - 1:
		for j in sides:
			var a: Vector3 = rows[i][j]
			var b: Vector3 = rows[i + 1][j]
			var c: Vector3 = rows[i + 1][j + 1]
			var d: Vector3 = rows[i][j + 1]
			st.set_uv(Vector2(float(j) / sides, float(i)))
			st.add_vertex(a)
			st.add_vertex(b)
			st.add_vertex(c)
			st.add_vertex(a)
			st.add_vertex(c)
			st.add_vertex(d)
	# торцы
	for e in [0, pts.size() - 1]:
		var cen: Vector3 = pts[e]
		for j in sides:
			var a: Vector3 = rows[e][j]
			var b: Vector3 = rows[e][j + 1]
			if e == 0:
				st.add_vertex(cen)
				st.add_vertex(a)
				st.add_vertex(b)
			else:
				st.add_vertex(cen)
				st.add_vertex(b)
				st.add_vertex(a)

# ---------- кости ----------

## Остатки туши: хребет из позвонков с отростками, дуги рёбер (верхние стоят аркой, нижние
## лежат на земле), череп, таз, трубчатые кости ног. L — длина зверя; вперёд — +Z.
static func bones_mesh(L: float, seed_v: int, antlers: bool = false) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bone := Color(0.84, 0.79, 0.68, 0.25)
	var dirty := Color(0.55, 0.32, 0.26, 0.55)
	var r0 := 0.03 * L
	var sy := r0 * 1.1
	# хребет: чуть изогнут, от таза (−) до шеи (+)
	var nv := 16
	var spine: Array = []
	for i in nv:
		var t := float(i) / (nv - 1)
		var z := lerpf(-0.36, 0.38, t) * L
		spine.append(Vector3(sin(t * 2.6 + 0.4) * 0.04 * L, sy, z))
	for i in nv:
		var p: Vector3 = spine[i]
		var dz := 0.018 * L
		var c := bone.lerp(dirty, rng.randf_range(0.2, 0.7))
		var rr := r0 * (0.7 if i > nv - 4 else 1.0)
		_tube(st, [p - Vector3(0, 0, dz), p + Vector3(0, 0, dz)], [rr, rr], 6, c)
		# остистый отросток: зверь лежит на боку — отросток вбок, вдоль земли
		_tube(st, [p, p + Vector3(-0.07 * L, 0.004, -0.008 * L)], [rr * 0.35, rr * 0.18], 4, c)
	# рёбра: середина хребта
	for i in 9:
		var p: Vector3 = spine[5 + i]
		var len_k := sin(float(i + 1) / 10.0 * PI) * 0.9 + 0.25
		var c := bone.lerp(dirty, rng.randf_range(0.0, 0.5))
		var rr := r0 * 0.38
		if rng.randf() < 0.88:
			# верхнее ребро — аркой над землёй к брюху
			var a := p + Vector3(0.1 * L, 0.2 * L * len_k, -0.02 * L)
			var b := p + Vector3(0.26 * L * len_k, 0.13 * L * len_k, -0.05 * L)
			var e := p + Vector3(0.34 * L * len_k, 0.01, -0.07 * L)
			_tube(st, [p, a, b, e], [rr, rr, rr * 0.85, rr * 0.7], 5, c)
		if rng.randf() < 0.75:
			# нижнее — придавлено к земле, разошлось веером
			var a2 := p + Vector3(-0.12 * L * len_k, 0.012, -0.03 * L)
			var e2 := p + Vector3(-0.3 * L * len_k, 0.008, -0.09 * L + rng.randf_range(-0.03, 0.03) * L)
			_tube(st, [p, a2, e2], [rr, rr * 0.85, rr * 0.7], 5, c)
	# череп: гранёный лофт от затылка к носу
	var hp: Vector3 = spine[nv - 1] + Vector3(0.03 * L, 0.0, 0.05 * L)
	var sk_len := 0.24 * L
	var rings := [[0.0, 0.07], [0.25, 0.075], [0.55, 0.05], [1.0, 0.025]]
	var spts: Array = []
	var srs: Array = []
	for rg: Array in rings:
		spts.append(hp + Vector3(0.03 * L * float(rg[0]), sy * 0.2, sk_len * float(rg[0])))
		srs.append(float(rg[1]) * L)
	_tube(st, spts, srs, 6, bone)
	# глазницы — тёмные провалы
	for sd in [-1.0, 1.0]:
		_tube(st, [hp + Vector3(sd * 0.05 * L, 0.06 * L, sk_len * 0.4), hp + Vector3(sd * 0.065 * L, 0.06 * L, sk_len * 0.45)], [0.022 * L, 0.018 * L], 5, Color(0.18, 0.12, 0.1, 0.1))
	if antlers:
		for sd in [-1.0, 1.0]:
			var base := hp + Vector3(sd * 0.04 * L, 0.07 * L, sk_len * 0.15)
			# череп лежит: рога легли на землю, одна ветвь задрана
			var lift := 0.1 if sd > 0.0 else 0.02
			_tube(st, [base, base + Vector3(sd * 0.16, lift, -0.12) * L, base + Vector3(sd * 0.28, lift * 0.6, -0.3) * L], [0.018 * L, 0.014 * L, 0.006 * L], 5, Color(0.6, 0.5, 0.38, 0.2))
			_tube(st, [base + Vector3(sd * 0.16, lift, -0.12) * L, base + Vector3(sd * 0.3, lift + 0.03, -0.02) * L], [0.012 * L, 0.005 * L], 5, Color(0.6, 0.5, 0.38, 0.2))
	# таз: две плоские пластины по бокам крестца
	var pp: Vector3 = spine[0]
	for sd in [-1.0, 1.0]:
		_tube(st, [pp + Vector3(sd * 0.02 * L, 0.0, 0.06 * L), pp + Vector3(sd * 0.09 * L, 0.01, -0.02 * L), pp + Vector3(sd * 0.1 * L, 0.0, -0.1 * L)], [0.035 * L, 0.03 * L, 0.02 * L], 4, bone.lerp(dirty, 0.3))
	# трубчатые кости ног с утолщениями на концах — растащены вокруг
	for i in 4:
		var a := rng.randf() * TAU
		var c := Vector3(cos(a), 0, sin(a)) * L * rng.randf_range(0.35, 0.6)
		var dir := Vector3(cos(a + rng.randf_range(-1.2, 1.2)), 0, sin(a + rng.randf_range(-1.2, 1.2)))
		var bl := L * rng.randf_range(0.18, 0.28)
		var rb := L * 0.016
		var p0 := c - dir * bl * 0.5 + Vector3(0, rb * 1.6, 0)
		var p3 := c + dir * bl * 0.5 + Vector3(0, rb * 1.6, 0)
		_tube(st, [p0, p0.lerp(p3, 0.12), p0.lerp(p3, 0.5), p0.lerp(p3, 0.88), p3], [rb * 1.7, rb, rb * 0.85, rb, rb * 1.6], 6, bone.lerp(dirty, rng.randf_range(0.0, 0.4)))
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, flesh_mat("bone"))
	return mesh

# ---------- освежёванная туша ----------

## Перекрасить модель зверя в освежёванную тушу. Возвращает список материалов (для skinned/dry).
static func skin_carcass(a: Node3D) -> Array:
	var out: Array = []
	var sh: Shader = load("res://shaders/carcass.gdshader")
	var model: Node3D = a.parts.get("model", a)
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var bx := mi.mesh.get_aabb()
		var rig: bool = a.parts.has("rig")
		for s in mi.mesh.get_surface_count():
			var src: Material = mi.material_override if mi.material_override != null else mi.get_surface_override_material(s)
			var m := ShaderMaterial.new()
			m.shader = sh
			m.set_shader_parameter("box_pos", bx.position)
			m.set_shader_parameter("box_size", bx.size)
			m.set_shader_parameter("use_vc", rig)
			if src is ShaderMaterial:
				var tv: Variant = (src as ShaderMaterial).get_shader_parameter("tint")
				if tv is Vector3:
					var t3: Vector3 = tv
					m.set_shader_parameter("tint", t3)
				var vc: Variant = (src as ShaderMaterial).get_shader_parameter("use_vc")
				if vc is bool:
					m.set_shader_parameter("use_vc", vc)
			# голова у копытных на длинной шее — отрез ближе к лопаткам
			var hc := 0.78
			if a.kind in ["roe", "deer", "moose", "muskdeer"]:
				hc = 0.74
			elif a.kind in ["boar", "bear", "wolverine", "beaver"]:
				hc = 0.8
			m.set_shader_parameter("head_cut", hc)
			m.set_shader_parameter("leg_cut", 0.3 if a.kind in ["roe", "deer", "moose", "muskdeer"] else 0.2)
			m.set_shader_parameter("skinned", 0.0)
			if mi.material_override != null:
				mi.material_override = m
			else:
				mi.set_surface_override_material(s, m)
			out.append(m)
			if mi.material_override != null:
				break
	return out
