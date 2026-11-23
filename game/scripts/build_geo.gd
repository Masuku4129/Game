extends RefCounted
## Геометрия построек лагеря: костёр, шалаш-навес, шалаш у ели, снежная пещера (квинзи),
## изба-зимовьё (сруб «в обло», самцовая кровля с тёсом в два ряда, дверь, волоковое окно),
## русская печь и мебель. Всё — из настоящих деталей: брёвна с торцами, жерди, доски, лапник
## отдельными ветками, камни со сколами. Местные оси: вход/перед смотрит в +Z, начало — на земле.

const BUILD_SH := preload("res://shaders/paint/build.gdshader")
const FLAME_SH := preload("res://shaders/paint/flame.gdshader")
const EMBER_SH := preload("res://shaders/paint/ember.gdshader")

var pv                      # pveg.gd: хвоя, кора, камень, икосфера
var mats := {}
var rng := RandomNumberGenerator.new()
var _st := {}

# цвета (sRGB)
const C_LOG := Color(0.5, 0.43, 0.35)
const C_END := Color(0.78, 0.64, 0.45)
const C_PLANK := Color(0.7, 0.58, 0.44)
const C_ROOF := Color(0.46, 0.43, 0.39)
const C_MOSS := Color(0.44, 0.43, 0.24)
const C_PLASTER := Color(0.9, 0.88, 0.82)
const C_CLAY := Color(0.52, 0.44, 0.36)
const C_BRICK := Color(0.5, 0.33, 0.26)
const C_SOOT := Color(0.1, 0.09, 0.08)
const C_SNOW := Color(0.76, 0.8, 0.87)
const C_DARK := Color(0.07, 0.06, 0.05)
const C_LINEN := Color(0.8, 0.74, 0.6)
const C_IRON := Color(0.22, 0.22, 0.23)
const C_FIBER := Color(0.62, 0.52, 0.34)

func _init(p) -> void:
	pv = p
	rng.seed = 1
	for k: Array in [["wood", 1, true], ["wood_f", 1, false], ["end", 2, true], ["paint", 0, true], ["paint_f", 0, false], ["facet", 3, false], ["facet_n", 3, true]]:
		var m := ShaderMaterial.new()
		m.shader = BUILD_SH
		m.set_shader_parameter("mode", k[1])
		m.set_shader_parameter("no_fade", k[2])
		mats[k[0]] = m
	mats["facet"].set_shader_parameter("stroke_k", 0.08)
	mats["facet_n"].set_shader_parameter("stroke_k", 0.12)
	var st := ShaderMaterial.new()
	st.shader = load("res://shaders/paint/rock.gdshader")
	st.set_shader_parameter("moss_k", 0.15)
	mats["stone"] = st
	var fur := ShaderMaterial.new()
	fur.shader = load("res://shaders/paint/fur.gdshader")
	mats["fur"] = fur
	mats["bark"] = pv.mats["bark"]
	mats["spruce"] = pv.mats["fir"]
	mats["spruce_card"] = pv.mats["fir_card"]
	mats["moss"] = pv.mats["moss"]
	mats["moss_card"] = pv.mats["moss_card"]
	var fl := ShaderMaterial.new()
	fl.shader = FLAME_SH
	mats["flame"] = fl
	var em := ShaderMaterial.new()
	em.shader = EMBER_SH
	mats["ember"] = em

## Материалы, которым погода раздаёт снег и мокрость, а main — положение героя и камеры.
func weather_mats() -> Array:
	return [mats["wood"], mats["wood_f"], mats["end"], mats["paint"], mats["paint_f"], mats["facet"], mats["facet_n"], mats["stone"], mats["fur"]]

# ---------- сборка меша ----------

func S(key: String) -> SurfaceTool:
	if not _st.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[key] = st
	return _st[key]

## Собрать накопленные поверхности в меш и повесить на parent отдельным MeshInstance3D.
func emit(parent: Node3D, nm: String, shadow: bool = true) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	for key: String in _st:
		var st: SurfaceTool = _st[key]
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mats[key])
	_st = {}
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

func _v(st: SurfaceTool, p: Vector3, n: Vector3, uv: Vector2, c: Color) -> void:
	st.set_color(c)
	st.set_normal(n)
	st.set_uv(uv)
	st.add_vertex(p)

func tri(key: String, a: Vector3, b: Vector3, c: Vector3, col: Color, ua := Vector2.ZERO, ub := Vector2(1, 0), uc := Vector2(0, 1)) -> void:
	var st := S(key)
	var n := (b - a).cross(c - a).normalized()
	_v(st, a, n, ua, col)
	_v(st, b, n, ub, col)
	_v(st, c, n, uc, col)

func quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, uva := Vector2(0, 0), uvc := Vector2(1, 1)) -> void:
	tri(key, a, b, c, col, uva, Vector2(uvc.x, uva.y), uvc)
	tri(key, a, c, d, col, uva, uvc, Vector2(uva.x, uvc.y))

## Брусок: xf — положение и оси, size — полные размеры. UV.y идёт вдоль самой длинной оси (в метрах).
func box(key: String, xf: Transform3D, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var long_ax := 0
	if size.y > size[long_ax]:
		long_ax = 1
	if size.z > size[long_ax]:
		long_ax = 2
	var st := S(key)
	for ax in 3:
		for sgn: float in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[ax] = sgn
			var u := (ax + 1) % 3
			var w := (ax + 2) % 3
			if w == long_ax or (u != long_ax and w != long_ax):
				pass
			else:
				var t := u
				u = w
				w = t
			var corners: Array = []
			for k: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var p := Vector3.ZERO
				p[ax] = sgn * h[ax]
				p[u] = k.x * h[u]
				p[w] = k.y * h[w]
				corners.append([p, Vector2(p[u] + 7.3 * ax, p[w])])
			var nw := (xf.basis * n).normalized()
			var order: Array = [0, 1, 2, 0, 2, 3]
			var a0: Vector3 = corners[0][0]
			var a1: Vector3 = corners[1][0]
			var a2: Vector3 = corners[2][0]
			if (a1 - a0).cross(a2 - a0).dot(n) < 0.0:
				order = [0, 2, 1, 0, 3, 2]
			for i: int in order:
				_v(st, xf * (corners[i][0] as Vector3), nw, corners[i][1], col)

## Доска от a до b: ширина w поперёк (вдоль side), толщина t по up.
func plank(key: String, a: Vector3, b: Vector3, side: Vector3, w: float, t: float, col: Color) -> void:
	var z := (b - a)
	var L := z.length()
	z = z / L
	var x := (side - z * side.dot(z)).normalized()
	var y := z.cross(x).normalized()
	box(key, Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(w, t, L), col)

## Бревно или жердь от a до b: неровный круглый ствол с торцами (cap — светлый срез).
func logp(a: Vector3, b: Vector3, r0: float, r1: float, col: Color, key: String = "wood", cap: bool = true, rad: int = 9, bump: float = 0.06) -> void:
	var ax := b - a
	var L := ax.length()
	var tg := ax / L
	var ref := Vector3.UP if absf(tg.y) < 0.9 else Vector3.RIGHT
	var nn := tg.cross(ref).normalized()
	var bb := tg.cross(nn).normalized()
	var seg := maxi(1, int(ceil(L / 0.45)))
	var off := rng.randf() * 10.0
	var bend := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * L * 0.006
	bend -= tg * bend.dot(tg)
	var rows: Array = []
	for i in seg + 1:
		var t := float(i) / seg
		var c := a + ax * t + bend * sin(t * PI)
		var r := lerpf(r0, r1, t)
		var row: Array = []
		for j in rad + 1:
			var ang := TAU * j / rad
			var d := nn * cos(ang) + bb * sin(ang)
			var k := 1.0 + bump * (sin(ang * 3.0 + off + t * 5.0) * 0.6 + sin(ang * 7.0 + off * 2.0 + t * 11.0) * 0.4)
			row.append([c + d * r * k, d, Vector2(float(j) / rad * r * 6.3, t * L)])
		rows.append(row)
	var st := S(key)
	for i in seg:
		for j in rad:
			for v: Array in [rows[i][j], rows[i + 1][j], rows[i][j + 1], rows[i + 1][j], rows[i + 1][j + 1], rows[i][j + 1]]:
				_v(st, v[0], v[1], v[2], col)
	if cap:
		_cap(rows[0], a, -tg, r0)
		_cap(rows[seg], b, tg, r1)

func _cap(row: Array, c: Vector3, n: Vector3, r: float) -> void:
	var st := S("end")
	var nb := row.size() - 1
	var rr := maxf(r, 0.001)
	for j in nb:
		var p0: Vector3 = row[j][0]
		var p1: Vector3 = row[j + 1][0]
		var q0 := p0 - c
		var q1 := p1 - c
		var bx := q0.normalized()
		var by := n.cross(bx)
		var u0 := Vector2(0.5 + q0.dot(bx) / rr * 0.5, 0.5 + q0.dot(by) / rr * 0.5)
		var u1 := Vector2(0.5 + q1.dot(bx) / rr * 0.5, 0.5 + q1.dot(by) / rr * 0.5)
		var verts: Array = [[c, Vector2(0.5, 0.5)], [p0, u0], [p1, u1]]
		if (p0 - c).cross(p1 - c).dot(n) < 0.0:
			verts = [[c, Vector2(0.5, 0.5)], [p1, u1], [p0, u0]]
		for v: Array in verts:
			_v(st, v[0], n, v[1], C_END)

## Камень со сколами (как в pveg.rock): c — центр низа, size — полуразмеры.
func stone(c: Vector3, size: Vector3, yaw: float, shade: float = -1.0) -> void:
	var verts: Array = pv._ico[0]
	var faces: Array = pv._ico[1]
	pv.rng.seed = rng.randi()
	var cuts: Array = pv._cuts()
	var bs := Basis(Vector3.UP, yaw)
	var pts: Array = []
	for p: Vector3 in verts:
		var w: Vector3 = pv._chisel(p * (1.0 + rng.randf_range(-0.05, 0.05)), cuts)
		if w.y < -0.2:
			w.y = -0.2 + (w.y + 0.2) * 0.3
		pts.append(c + bs * (w * size + Vector3(0, size.y * 0.35, 0)))
	var st := S("stone")
	for f: Array in faces:
		var sh := shade if shade >= 0.0 else rng.randf()
		for k: int in [0, 2, 1]:
			_v(st, pts[f[k]], bs * (verts[f[k]] as Vector3), Vector2.ZERO, Color(sh, 0, 0, 1))

## Тело вращения (горшок, туесок): профиль [радиус, высота], ось вверх из c.
func lathe(key: String, c: Vector3, prof: Array, col: Color, seg: int = 12) -> void:
	var st := S(key)
	for i in prof.size() - 1:
		var p0: Vector2 = prof[i]
		var p1: Vector2 = prof[i + 1]
		var dn := Vector2(p1.y - p0.y, -(p1.x - p0.x)).normalized()
		for j in seg:
			var a0 := TAU * j / seg
			var a1 := TAU * (j + 1) / seg
			var d0 := Vector3(cos(a0), 0, sin(a0))
			var d1 := Vector3(cos(a1), 0, sin(a1))
			var v00 := c + d0 * p0.x + Vector3(0, p0.y, 0)
			var v01 := c + d1 * p0.x + Vector3(0, p0.y, 0)
			var v10 := c + d0 * p1.x + Vector3(0, p1.y, 0)
			var v11 := c + d1 * p1.x + Vector3(0, p1.y, 0)
			var n0 := (d0 * dn.x + Vector3(0, dn.y, 0)).normalized()
			var n1 := (d1 * dn.x + Vector3(0, dn.y, 0)).normalized()
			for v: Array in [[v00, n0, Vector2(a0, p0.y)], [v11, n1, Vector2(a1, p1.y)], [v10, n0, Vector2(a0, p1.y)], [v00, n0, Vector2(a0, p0.y)], [v01, n1, Vector2(a1, p0.y)], [v11, n1, Vector2(a1, p1.y)]]:
				_v(st, v[0], v[1], v[2], col)

## Еловая лапа: плоская перистая ветка — черенок и боковые веточки-хвоинки ёлочкой,
## по краю мазки хвои. base — где ветка срезана, dir — к кончику, up — верх лапы.
func frond(base: Vector3, dir: Vector3, up: Vector3, length: float, width: float, droop: float = 0.12) -> void:
	dir = dir.normalized()
	var side := dir.cross(up).normalized()
	var nup := side.cross(dir).normalized()
	var core := S("spruce")
	var cards := S("spruce_card")
	var tw := rng.randf_range(-0.15, 0.15)
	var n := 8
	var axis_pts: Array = []
	for i in n + 1:
		var t := float(i) / n
		axis_pts.append(base + dir * length * t - nup * droop * length * t * t + side * tw * t * t * length * 0.3)
	# черенок
	for i in n:
		_needle_strip(core, axis_pts[i], axis_pts[i + 1], nup, 0.018, 0.2)
	# боковые веточки: от оси вперёд-наружу, короче к кончику и к основанию
	for i in range(1, n):
		var t := float(i) / n
		var c: Vector3 = axis_pts[i]
		var w := width * pow(sin(PI * clampf(t * 0.9 + 0.1, 0.0, 1.0)), 0.6)
		for sgn: float in [-1.0, 1.0]:
			var o := c + dir * length * 0.03 * sgn
			var tip := o + side * sgn * w + dir * w * 0.75 - nup * w * 0.25
			_needle_strip(core, o, tip, nup, 0.045 * (1.0 - t * 0.3), rng.randf_range(0.3, 0.6))
			if i % 2 == 0:
				for corner: Array in [[0, 0], [1, 0], [1, 1], [0, 0], [1, 1], [0, 1]]:
					cards.set_color(Color(rng.randf_range(0.2, 0.6), 0, 0, 1))
					cards.set_normal((nup * 0.9 + side * sgn * 0.3).normalized())
					cards.set_uv(Vector2(corner[0], corner[1]))
					cards.set_uv2(Vector2(w * 0.45 + 0.02, rng.randf() * TAU))
					cards.add_vertex(o.lerp(tip, 0.6))
	# кончик
	_needle_strip(core, axis_pts[n], axis_pts[n] + dir * width * 0.6, nup, 0.04, 0.5)

## Полоска хвои вдоль веточки a→b: ромб с зубцами (иголки торчат в стороны).
func _needle_strip(st: SurfaceTool, a: Vector3, b: Vector3, up: Vector3, w: float, shade: float) -> void:
	var d := b - a
	var L := d.length()
	if L < 0.001:
		return
	var sd := d.cross(up).normalized()
	var m := a + d * 0.45 + up * w * 0.25
	var pts: Array = [a, m + sd * w, b, m - sd * w]
	var nrm := (up + Vector3(0, 0.2, 0)).normalized()
	for tr: Array in [[0, 1, 2], [0, 2, 3]]:
		for k: int in tr:
			st.set_color(Color(clampf(shade + rng.randf_range(-0.1, 0.1), 0.0, 1.0), 0, 0, 1))
			st.set_normal(nrm)
			st.add_vertex(pts[k])

## Обвязка лыком: несколько витков вокруг точки на оси.
func lashing(c: Vector3, axis: Vector3, r: float) -> void:
	axis = axis.normalized()
	for k in 3:
		var o := c + axis * (k - 1) * 0.025
		logp(o - axis * 0.011, o + axis * 0.011, r + 0.012, r + 0.012, C_FIBER, "paint", false, 8, 0.0)

# ---------- костёр ----------

## Костёр: кольцо камней, зола, шалашик дров, рогатины с вертелом, бревно-сиденье.
## Возвращает узел с частями: "wood_full", "wood_low", "flames", "ember", "spit", "food".
func campfire() -> Node3D:
	rng.seed = 501
	var root := Node3D.new()
	# камни: плотное кольцо, у каждого своя форма
	var n := 11
	for i in n:
		var a := TAU * i / n + rng.randf_range(-0.1, 0.1)
		var rr := 0.56 + rng.randf_range(-0.03, 0.04)
		var s := Vector3(rng.randf_range(0.13, 0.17), rng.randf_range(0.1, 0.14), rng.randf_range(0.1, 0.13))
		stone(Vector3(cos(a) * rr, -0.06, sin(a) * rr), s, a + PI * 0.5)
	emit(root, "stones")
	# зола и угли в очаге
	var em := S("ember")
	var ra := 0.46
	for i in 16:
		var a0 := TAU * i / 16.0
		var a1 := TAU * (i + 1) / 16.0
		for v: Array in [[Vector3(0, 0.035, 0), 1.0], [Vector3(cos(a0) * ra, 0.01, sin(a0) * ra), 0.0], [Vector3(cos(a1) * ra, 0.01, sin(a1) * ra), 0.0]]:
			_v(em, v[0], Vector3.UP, Vector2.ZERO, Color(v[1], 0, 0, 1))
	# мелкие угольки горкой
	for i in 9:
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.0, 0.22)
		var c := Vector3(cos(a) * d, 0.03, sin(a) * d)
		box("ember", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).rotated(Vector3.RIGHT, rng.randf_range(-0.3, 0.3)), c), Vector3(0.09, 0.05, 0.06), Color(1, 0, 0, 1))
	emit(root, "ember", false)
	# дрова шалашиком: колотые поленья сходятся к центру
	for i in 6:
		var a := TAU * i / 6.0 + 0.3
		var foot := Vector3(cos(a) * 0.34, 0.02, sin(a) * 0.34)
		var top := Vector3(cos(a) * 0.04, 0.5, sin(a) * 0.04)
		_split_wood(foot, top, 0.045)
	emit(root, "wood_full")
	# прогоревшие: обугленные поленья лежат в золе
	for i in 4:
		var a := TAU * i / 4.0 + 0.5
		var p0 := Vector3(cos(a) * 0.38, 0.05, sin(a) * 0.38)
		var p1 := Vector3(cos(a) * 0.04, 0.07, sin(a) * 0.04)
		logp(p0, p1, 0.045, 0.035, Color(0.16, 0.12, 0.1), "paint", true, 7, 0.1)
	emit(root, "wood_low")
	# рогатины и вертел
	for sx: float in [-1.0, 1.0]:
		var f := Vector3(sx * 0.74, 0, 0)
		logp(f + Vector3(0, -0.05, 0), f + Vector3(sx * 0.02, 0.62, 0), 0.026, 0.022, C_LOG, "bark")
		logp(f + Vector3(sx * 0.02, 0.6, 0), f + Vector3(sx * 0.1, 0.78, 0.02), 0.018, 0.012, C_LOG, "bark")
		logp(f + Vector3(sx * 0.02, 0.6, 0), f + Vector3(-sx * 0.05, 0.77, -0.02), 0.016, 0.012, C_LOG, "bark")
	logp(Vector3(-0.95, 0.66, 0), Vector3(0.9, 0.67, 0), 0.014, 0.012, C_LOG, "bark")
	# ручка вертела — загнутый сучок
	logp(Vector3(-0.95, 0.66, 0), Vector3(-1.0, 0.56, 0.06), 0.012, 0.01, C_LOG, "bark")
	emit(root, "spit")
	# бревно-сиденье позади
	logp(Vector3(-0.75, 0.17, -1.35), Vector3(0.8, 0.17, -1.32), 0.17, 0.15, C_LOG, "bark")
	emit(root, "seat_log")
	# пламя: три скрещённые карточки
	var flames := MeshInstance3D.new()
	flames.name = "flames"
	var fs := SurfaceTool.new()
	fs.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 4:
		var a := PI * k / 4.0
		var d := Vector3(cos(a), 0, sin(a)) * 0.34
		var off := Vector3(rng.randf_range(-0.04, 0.04), 0, rng.randf_range(-0.04, 0.04))
		var hgt := 0.95 + k * 0.05
		var ph := Color(float(k) / 4.0, 0, 0, 1)
		var pts: Array = [[off - d, Vector2(0, 0)], [off + d, Vector2(1, 0)], [off + d * 0.6 + Vector3(0, hgt, 0), Vector2(1, 1)], [off - d * 0.6 + Vector3(0, hgt, 0), Vector2(0, 1)]]
		for i: int in [0, 1, 2, 0, 2, 3]:
			_v(fs, pts[i][0], Vector3.UP, pts[i][1], ph)
	var fm := ArrayMesh.new()
	fs.commit(fm)
	fm.surface_set_material(0, mats["flame"])
	flames.mesh = fm
	flames.position.y = 0.03
	flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(flames)
	var lt := OmniLight3D.new()
	lt.name = "light"
	lt.light_color = Color(1.0, 0.62, 0.3)
	lt.omni_range = 7.0
	lt.light_energy = 2.0
	lt.position = Vector3(0, 0.6, 0)
	lt.shadow_enabled = false
	root.add_child(lt)
	root.add_child(smoke(0.5, 1.0))
	return root

## Колотое полено: трёхгранный клин (сердцевина, две плоскости раскола и кора).
func _split_wood(a: Vector3, b: Vector3, r: float) -> void:
	var tg := (b - a).normalized()
	var nn := tg.cross(Vector3.UP if absf(tg.y) < 0.9 else Vector3.RIGHT).normalized()
	var bb := tg.cross(nn)
	var rot := rng.randf() * TAU
	var c0 := Vector3.ZERO
	var pts: Array = []
	for k in 5:
		var ang := rot + (-0.9 + 1.8 * k / 4.0)
		pts.append((nn * cos(ang) + bb * sin(ang)) * r * 1.6)
	var tip := (nn * cos(rot) + bb * sin(rot)) * -r * 0.3
	# корка — дуга, раскол — две плоскости к сердцевине
	for k in 4:
		quad("wood", a + pts[k], a + pts[k + 1], b + pts[k + 1], b + pts[k], Color(0.34, 0.26, 0.18), Vector2(k * 0.1, 0), Vector2((k + 1) * 0.1, a.distance_to(b)))
	quad("wood", a + tip, a + pts[0], b + pts[0], b + tip, C_END, Vector2(0, 0), Vector2(0.1, a.distance_to(b)))
	quad("wood", a + pts[4], a + tip, b + tip, b + pts[4], C_END * 0.95, Vector2(0, 0), Vector2(0.1, a.distance_to(b)))
	for e: Vector3 in [a, b]:
		for k in 4:
			tri("end", e + tip, e + pts[k], e + pts[k + 1], C_END, Vector2(0.5, 0.5), Vector2(0.9, 0.4), Vector2(0.9, 0.6))
	c0 = c0

# --- core: схрон и колода-верстак ---

## Схрон: неглубокая яма, обложенная камнями, накрыта крест-накрест жердями и лапником,
## сверху придавлена камнями; рядом вешка из жерди с берестой.
func cache() -> Node3D:
	rng.seed = 515
	var root := Node3D.new()
	for k in 9:
		var a := TAU * k / 9.0 + rng.randf_range(-0.1, 0.1)
		stone(Vector3(cos(a) * 0.62, 0.04, sin(a) * 0.5), Vector3(0.16, 0.1, 0.13), a)
	for k in 5:
		var z := -0.45 + k * 0.22
		logp(Vector3(-0.75, 0.1, z), Vector3(0.75, 0.12, z + rng.randf_range(-0.06, 0.06)), 0.03, 0.022, C_LOG, "bark")
	for k in 4:
		var x := -0.5 + k * 0.33
		logp(Vector3(x, 0.15, -0.6), Vector3(x + rng.randf_range(-0.08, 0.08), 0.16, 0.6), 0.026, 0.02, C_LOG, "bark")
	for k in 7:
		var a2 := TAU * k / 7.0
		frond(Vector3(cos(a2) * 0.1, 0.2, sin(a2) * 0.1), Vector3(cos(a2), -0.15, sin(a2)), Vector3.UP, 0.72, 0.3, 0.1)
	stone(Vector3(0.18, 0.24, 0.05), Vector3(0.13, 0.08, 0.11), 0.3)
	stone(Vector3(-0.25, 0.23, -0.12), Vector3(0.11, 0.07, 0.1), 1.2)
	logp(Vector3(0.85, -0.1, 0.35), Vector3(0.88, 0.9, 0.36), 0.02, 0.015, C_LOG, "bark")
	box("paint", Transform3D(Basis(Vector3.UP, 0.3), Vector3(0.89, 0.78, 0.36)), Vector3(0.02, 0.16, 0.08), Color(0.9, 0.86, 0.76))
	emit(root, "cache")
	return root

## Колода-верстак: толстый чурбак с затёсом, рядом половина бревна на двух чурках.
func chop_block() -> Node3D:
	rng.seed = 616
	var root := Node3D.new()
	logp(Vector3(0, -0.05, 0), Vector3(0, 0.5, 0), 0.3, 0.28, C_LOG, "bark", true, 12, 0.04)
	tri("end", Vector3(-0.27, 0.505, 0), Vector3(0.27, 0.505, 0.05), Vector3(0, 0.505, 0.27), C_END)
	logp(Vector3(-0.15, 0.5, -0.05), Vector3(0.12, 0.62, 0.06), 0.012, 0.01, C_LOG, "bark")
	for sx: float in [-0.55, 0.55]:
		logp(Vector3(sx, -0.05, 0.75), Vector3(sx, 0.3, 0.75), 0.13, 0.12, C_LOG, "bark")
	box("wood", Transform3D(Basis(), Vector3(0, 0.33, 0.75)), Vector3(1.5, 0.06, 0.32), C_PLANK)
	emit(root, "block")
	return root
# --- /core ---

## Дым: мягкие серые клубы вверх, со сносом ветром.
func smoke(power: float, h: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "smoke"
	p.amount = 24
	p.lifetime = 5.0
	p.preprocess = 3.0
	p.position = Vector3(0, h, 0)
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.35
	pm.initial_velocity_max = 0.6
	pm.gravity = Vector3(0.12, 0.15, 0.05)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.12
	pm.scale_min = 0.6
	pm.scale_max = 1.0
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.25))
	sc.add_point(Vector2(1, 1.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.set_color(0, Color(0.55, 0.52, 0.5, 0.0))
	g.set_color(1, Color(0.7, 0.7, 0.72, 0.0))
	g.add_point(0.15, Color(0.5, 0.48, 0.46, 0.45 * power))
	g.add_point(0.6, Color(0.62, 0.62, 0.64, 0.22 * power))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.9)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _puff_tex()
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 8, 6))
	return p

var _puff: Texture2D
func _puff_tex() -> Texture2D:
	if _puff != null:
		return _puff
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var r := RandomNumberGenerator.new()
	r.seed = 9
	var blobs: Array = []
	for i in 6:
		blobs.append([Vector2(r.randf_range(0.3, 0.7), r.randf_range(0.3, 0.7)) * n, r.randf_range(0.18, 0.3) * n])
	for y in n:
		for x in n:
			var a := 0.0
			for b: Array in blobs:
				var d := Vector2(x, y).distance_to(b[0]) / float(b[1])
				a = maxf(a, clampf(1.0 - d, 0.0, 1.0))
			img.set_pixel(x, y, Color(1, 1, 1, smoothstep(0.0, 0.7, a)))
	_puff = ImageTexture.create_from_image(img)
	return _puff

## Что жарится на вертеле: кусок мяса, рыба или шкура (сушится рядом на рамке).
func spit_food(kind: String, done: float) -> Node3D:
	rng.seed = 77
	var root := Node3D.new()
	match kind:
		"meat_raw", "meat_cooked":
			var col := Color(0.6, 0.27, 0.22).lerp(Color(0.42, 0.24, 0.12), done)
			for i in 3:
				var c := Vector3(-0.16 + i * 0.16, 0.66, 0)
				var bs := Basis(Vector3.RIGHT, rng.randf_range(0, TAU)).rotated(Vector3.UP, rng.randf_range(-0.3, 0.3))
				stone_like("paint", c, Vector3(0.075, 0.06, 0.065), bs, col)
		"fish_raw", "fish_cooked":
			var col2 := Color(0.6, 0.62, 0.6).lerp(Color(0.66, 0.46, 0.22), done)
			# рыба насажена вдоль вертела: веретено с хвостом
			var prof: Array = []
			for i in 9:
				var t := float(i) / 8.0
				prof.append(Vector2(sin(PI * clampf(t * 1.1, 0.0, 1.0)) * 0.05 + 0.002, t * 0.42))
			var tmp := Node3D.new()
			lathe("paint", Vector3.ZERO, prof, col2, 10)
			var mi := emit(root, "fish")
			mi.transform = Transform3D(Basis(Vector3.BACK, PI * 0.5).scaled(Vector3(1.0, 1.0, 0.6)), Vector3(0.21, 0.66, 0))
			tmp.free()
			tri("paint", Vector3(-0.21, 0.66, 0), Vector3(-0.31, 0.72, 0), Vector3(-0.31, 0.6, 0), col2 * 0.85)
		"hide", "fur":
			# сушильная рамка из жердей рядом с костром, шкура растянута лыком
			var o := Vector3(0, 0, 0.95)
			logp(o + Vector3(-0.45, 0, 0), o + Vector3(-0.42, 1.05, -0.12), 0.02, 0.018, C_LOG, "bark")
			logp(o + Vector3(0.45, 0, 0), o + Vector3(0.42, 1.05, -0.12), 0.02, 0.018, C_LOG, "bark")
			logp(o + Vector3(-0.52, 0.98, -0.11), o + Vector3(0.52, 0.98, -0.11), 0.016, 0.016, C_LOG, "bark")
			logp(o + Vector3(-0.52, 0.2, -0.02), o + Vector3(0.52, 0.2, -0.02), 0.016, 0.016, C_LOG, "bark")
			var hc := Color(0.62, 0.48, 0.34).lerp(Color(0.48, 0.36, 0.24), done)
			var pts: Array = []
			for i in 10:
				var a := TAU * i / 10.0
				pts.append(o + Vector3(cos(a) * 0.36 * (1.0 + 0.1 * sin(a * 3.0)), 0.6 + sin(a) * 0.33, -0.065 - sin(a) * 0.04))
			for i in 10:
				tri("paint", o + Vector3(0, 0.6, -0.07), pts[i], pts[(i + 1) % 10], hc)
	if _st.size() > 0:
		emit(root, "food")
	return root

## Неровный кусок (мясо, ком глины): гранёная капля по осям basis.
func stone_like(key: String, c: Vector3, size: Vector3, bs: Basis, col: Color) -> void:
	var verts: Array = pv._ico[0]
	var faces: Array = pv._ico[1]
	var pts: Array = []
	var off := rng.randf() * 10.0
	for p: Vector3 in verts:
		pts.append(c + bs * (p * size * (1.0 + 0.12 * sin(p.x * 4.0 + off) * cos(p.z * 3.0 + off))))
	var st := S(key)
	for f: Array in faces:
		for k: int in [0, 2, 1]:
			_v(st, pts[f[k]], bs * (verts[f[k]] as Vector3), Vector2.ZERO, col)

# ---------- шалаши ----------

## Шалаш-навес: две рогатины, перекладина, жерди к земле, лапник внахлёст снизу вверх,
## боковины из лапника, подстилка. Открытая сторона — +Z.
func lean_to() -> Node3D:
	rng.seed = 602
	var root := Node3D.new()
	var hw := 1.25
	var fz := 0.75
	var top := 1.5
	var bz := -1.35
	for sx: float in [-1.0, 1.0]:
		var p := Vector3(sx * hw, 0, fz)
		logp(p + Vector3(0, -0.1, 0), p + Vector3(sx * 0.03, top - 0.02, 0), 0.05, 0.042, C_LOG, "bark")
		# развилка
		logp(p + Vector3(sx * 0.03, top - 0.08, 0), p + Vector3(sx * 0.13, top + 0.14, 0.03), 0.03, 0.02, C_LOG, "bark")
		logp(p + Vector3(sx * 0.03, top - 0.08, 0), p + Vector3(-sx * 0.04, top + 0.13, -0.03), 0.03, 0.02, C_LOG, "bark")
		lashing(p + Vector3(sx * 0.03, top + 0.02, 0), Vector3.RIGHT, 0.045)
	logp(Vector3(-hw - 0.35, top + 0.03, fz), Vector3(hw + 0.3, top + 0.05, fz), 0.045, 0.04, C_LOG, "bark")
	# жерди-стропила
	var nr := 6
	var slope_dir := (Vector3(0, 0, bz) - Vector3(0, top, fz)).normalized()
	for i in nr:
		var x := lerpf(-hw + 0.05, hw - 0.05, float(i) / (nr - 1)) + rng.randf_range(-0.04, 0.04)
		var a := Vector3(x, top + 0.07, fz) - slope_dir * 0.25
		logp(a, Vector3(x * 1.02, -0.05, bz - 0.05), 0.032, 0.026, C_LOG, "bark")
	emit(root, "frame")
	# лапник рядами снизу вверх: каждый верхний ряд накрывает нижний
	var up_n := slope_dir.cross(Vector3.RIGHT).normalized()
	if up_n.y < 0.0:
		up_n = -up_n
	var slope_len := Vector3(0, top, fz).distance_to(Vector3(0, 0, bz))
	var rows := 9
	for r in rows:
		var t := 1.0 - float(r) / (rows - 1)
		var along := slope_len * (0.06 + t * 0.88)
		var cnt := 9
		for k in cnt:
			var x := lerpf(-hw - 0.1, hw + 0.1, (k + (0.5 if r % 2 == 1 else 0.0)) / float(cnt - 1)) + rng.randf_range(-0.06, 0.06)
			if absf(x) > hw + 0.2:
				continue
			var base := Vector3(x, top + 0.06, fz) + slope_dir * (slope_len - along - 0.1) + up_n * (0.06 + r * 0.012)
			var dir := (slope_dir + Vector3(rng.randf_range(-0.15, 0.15), 0, 0)).normalized()
			frond(base, dir, up_n, rng.randf_range(0.7, 0.9), rng.randf_range(0.2, 0.26), 0.03)
	# боковины: лапы стоят наклонно от перекладины к земле
	for sx: float in [-1.0, 1.0]:
		for k in 6:
			var zz := lerpf(fz - 0.2, bz + 0.25, float(k) / 5.0)
			var hh := top * (zz - bz) / (fz - bz)
			var base2 := Vector3(sx * (hw + 0.12), -0.02, zz)
			frond(base2, Vector3(-sx * 0.12, 1.0, rng.randf_range(-0.25, 0.25)), Vector3(sx, 0, 0), maxf(hh, 0.35) * 1.02, 0.22, -0.02)
	# подстилка: лапы ровно уложены «ёлочкой»
	for k in 10:
		var x2 := rng.randf_range(-hw + 0.25, hw - 0.25)
		var z2 := lerpf(fz - 0.1, bz + 0.6, float(k % 5) / 4.0)
		frond(Vector3(x2 - 0.35 * (1.0 if k < 5 else -1.0), 0.05, z2), Vector3(1.0 if k < 5 else -1.0, 0.0, rng.randf_range(-0.3, 0.3)), Vector3.UP, 0.7, 0.24, 0.0)
	emit(root, "boughs")
	return root

## Шалаш у ели: коньковая жердь привязана к стволу (опора — само дерево) и уходит к земле,
## рёбра-жерди по обе стороны, лапник внахлёст. Ствол — в начале координат, шалаш — в +Z.
func tree_shelter() -> Node3D:
	rng.seed = 707
	var root := Node3D.new()
	var tie := Vector3(0, 1.45, 0.2)
	var end := Vector3(0, -0.05, 3.5)
	logp(tie + Vector3(0, 0.08, -0.12), end, 0.05, 0.04, C_LOG, "bark")
	lashing(Vector3(0, 1.5, 0.0), Vector3.UP, 0.25)
	var ridge := (end - tie).normalized()
	var L := tie.distance_to(end)
	# рёбра: от коньковой жерди к земле
	var nr := 6
	for i in nr:
		var t := 0.08 + 0.8 * float(i) / (nr - 1)
		var p := tie.lerp(end, t)
		var w := maxf(p.y, 0.2) * 0.85 + 0.15
		for sx: float in [-1.0, 1.0]:
			logp(p + Vector3(-sx * 0.07, 0.05, 0), Vector3(sx * w, -0.05, p.z + rng.randf_range(-0.1, 0.1)), 0.026, 0.022, C_LOG, "bark")
	emit(root, "frame")
	# лапник внахлёст по скатам
	for sx: float in [-1.0, 1.0]:
		for r in 5:
			var down := 1.0 - float(r) / 4.0
			for k in 10:
				var t := 0.03 + 0.92 * float(k) / 9.0 + (0.04 if r % 2 == 1 else 0.0)
				var p := tie.lerp(end, t)
				var w := maxf(p.y, 0.2) * 0.85 + 0.15
				var foot := Vector3(sx * w, 0.0, p.z)
				var sd := (foot - p).normalized()
				var nrm := sd.cross(ridge).normalized() * sx
				if nrm.y < 0.0:
					nrm = -nrm
				var base := p.lerp(foot, 0.03 + down * 0.6) + nrm * (0.05 + (4 - r) * 0.015)
				frond(base, (sd + ridge * rng.randf_range(-0.15, 0.15)).normalized(), nrm, minf(p.distance_to(foot) * 0.62 + 0.25, 1.0), 0.24, 0.05)
	# подстилка
	for k in 7:
		frond(Vector3(rng.randf_range(-0.25, 0.25), 0.05, 0.7 + k * 0.32), Vector3(rng.randf_range(-1, 1), 0, 0.3).normalized(), Vector3.UP, 0.6, 0.22, 0.0)
	emit(root, "boughs")
	# короб-хранилище у ствола
	_bark_box(Vector3(0.35, 0, 0.55), 0.4)
	emit(root, "store")
	L = L
	return root

## Берестяной короб (хранилище в шалаше).
func _bark_box(c: Vector3, yaw: float) -> void:
	var bs := Basis(Vector3.UP, yaw)
	box("paint", Transform3D(bs, c + Vector3(0, 0.2, 0)), Vector3(0.42, 0.4, 0.3), Color(0.86, 0.8, 0.66))
	for k in 3:
		box("paint", Transform3D(bs, c + Vector3(0, 0.07 + k * 0.13, 0)), Vector3(0.43, 0.025, 0.31), Color(0.3, 0.22, 0.15))
	box("paint", Transform3D(bs, c + Vector3(0, 0.42, 0)), Vector3(0.46, 0.05, 0.34), Color(0.62, 0.47, 0.29))

## Снежная пещера (квинзи): насыпанный и выкопанный купол с неровной, срезанной лопатой
## поверхностью, лаз с аркой, отдушина наверху, внутри — лапник. Вход — +Z.
func snow_shelter() -> Node3D:
	rng.seed = 808
	var root := Node3D.new()
	var R := 1.45
	var H := 1.55
	var nu := 18
	var nv := 7
	var cuts: Array = []
	for i in 16:
		var nd := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.0, 1.0), rng.randf_range(-1, 1)).normalized()
		cuts.append([nd, rng.randf_range(0.9, 0.97)])
	var ent_half := 0.38   # полуширина лаза по углу
	var outer: Array = []
	for j in nv + 1:
		var row: Array = []
		var el := PI * 0.5 * float(j) / nv
		for i in nu + 1:
			var az := TAU * i / nu
			var d := Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el))
			var w: Vector3 = pv._chisel(d, cuts)
			row.append(Vector3(w.x * R, w.y * H - 0.08, w.z * R))
		outer.append(row)
	var col := C_SNOW
	for j in nv:
		for i in nu:
			var az0 := TAU * i / nu
			var az1 := TAU * (i + 1) / nu
			var amid := wrapf((az0 + az1) * 0.5, -PI, PI)
			if absf(amid) < ent_half and j < 3:
				continue
			var a: Vector3 = outer[j][i]
			var b: Vector3 = outer[j][i + 1]
			var c: Vector3 = outer[j + 1][i + 1]
			var d: Vector3 = outer[j + 1][i]
			_snowquad("facet", a, b, c, d, col, true)
	# внутренний свод (виден в лазе) — тёмный голубоватый
	var Ri := R - 0.32
	var Hi := H - 0.35
	var inner: Array = []
	for j in nv + 1:
		var row2: Array = []
		var el2 := PI * 0.5 * float(j) / nv
		for i in nu + 1:
			var az2 := TAU * i / nu
			row2.append(Vector3(sin(az2) * cos(el2) * Ri, sin(el2) * Hi, cos(az2) * cos(el2) * Ri))
		inner.append(row2)
	for j in nv:
		for i in nu:
			var amid2 := wrapf(TAU * (i + 0.5) / nu, -PI, PI)
			if absf(amid2) < ent_half and j < 3:
				continue
			var shade := lerpf(0.42, 0.62, float(j) / nv)
			_snowquad("facet_n", inner[j][i], inner[j][i + 1], inner[j + 1][i + 1], inner[j + 1][i], Color(shade * 0.85, shade * 0.9, shade, 0), false)
	# пол пещеры и кромка лаза: толща стены по обе стороны проёма
	var floor_c := Color(0.5, 0.53, 0.58, 0)
	for i in nu:
		var a0 := TAU * i / nu
		var a1 := TAU * (i + 1) / nu
		tri("facet_n", Vector3(0, 0.02, 0), Vector3(sin(a1) * Ri, 0.02, cos(a1) * Ri), Vector3(sin(a0) * Ri, 0.02, cos(a0) * Ri), floor_c)
	# лаз: арка-туннель от внешней стены наружу
	var arch: Array = []
	var na := 8
	for k in na + 1:
		var t := PI * k / na
		arch.append(Vector2(cos(t) * 0.42, sin(t) * 0.62))
	var z_in := Ri * 0.95
	var z_out := R + 0.42
	for k in na:
		var p0: Vector2 = arch[k]
		var p1: Vector2 = arch[k + 1]
		# свод лаза изнутри (тёмный)
		_snowquad("facet_n", Vector3(p0.x, p0.y, z_in), Vector3(p1.x, p1.y, z_in), Vector3(p1.x, p1.y, z_out), Vector3(p0.x, p0.y, z_out), Color(0.45, 0.5, 0.58, 0), false)
		# наружный горб над лазом
		var o0 := Vector3(p0.x * 1.55, p0.y * 1.35 + 0.05, 0)
		var o1 := Vector3(p1.x * 1.55, p1.y * 1.35 + 0.05, 0)
		_snowquad("facet", Vector3(o0.x, o0.y, R * 0.55), Vector3(o1.x, o1.y, R * 0.55), Vector3(o1.x, o1.y, z_out), Vector3(o0.x, o0.y, z_out), col, true)
		# торец арки — кольцо между лазом и горбом
		_snowquad("facet", Vector3(p0.x, p0.y, z_out), Vector3(p1.x, p1.y, z_out), Vector3(o1.x, o1.y, z_out + 0.02), Vector3(o0.x, o0.y, z_out + 0.02), col, true)
	# тёмная глубина за лазом
	for k in na:
		var p0b: Vector2 = arch[k]
		var p1b: Vector2 = arch[k + 1]
		tri("paint", Vector3(0, 0.05, z_in - 0.6), Vector3(p1b.x, p1b.y, z_in - 0.05), Vector3(p0b.x, p0b.y, z_in - 0.05), Color(0.13, 0.15, 0.2, 0))
	# отдушина у верха: тёмное отверстие с кромкой
	var vc := Vector3(0.25, H - 0.13, -0.3)
	for k in 8:
		var a0b := TAU * k / 8.0
		var a1b := TAU * (k + 1) / 8.0
		tri("paint", vc + Vector3(0, 0.02, 0), vc + Vector3(cos(a1b) * 0.07, 0.0, sin(a1b) * 0.07), vc + Vector3(cos(a0b) * 0.07, 0.0, sin(a0b) * 0.07), Color(0.1, 0.12, 0.16, 0))
	# мерные палочки (по ним выкапывают ровную стену): торчат концы
	for k in 7:
		var az3 := TAU * (k + 0.5) / 7.0 + 0.2
		var el3 := 0.45 + 0.4 * float(k % 3) / 2.0
		var dd := Vector3(sin(az3) * cos(el3), sin(el3), cos(az3) * cos(el3))
		if absf(wrapf(az3, -PI, PI)) < 0.6:
			continue
		var pp := Vector3(dd.x * R, dd.y * H - 0.08, dd.z * R) * 0.98
		logp(pp - dd * 0.05, pp + dd * 0.05, 0.008, 0.007, C_LOG, "bark", false, 4, 0.0)
	emit(root, "dome")
	# лапник на полу и у входа, лопата воткнута в снег
	for k in 6:
		frond(Vector3(rng.randf_range(-0.5, 0.5), 0.05, rng.randf_range(-0.6, 0.6)), Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), Vector3.UP, 0.6, 0.22, 0.0)
	frond(Vector3(-0.15, 0.04, R + 0.15), Vector3(0.2, 0, 1).normalized(), Vector3.UP, 0.55, 0.2, 0.0)
	_shovel(Vector3(0.85, 0, R + 0.35), 0.4)
	emit(root, "inside")
	return root

func _snowquad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, outward: bool) -> void:
	var n := (b - a).cross(c - a).normalized()
	var mid := (a + b + c + d) * 0.25
	var want := mid.normalized() if outward else -mid.normalized()
	if n.dot(want) < 0.0:
		var t := b
		b = d
		d = t
	quad(key, a, b, c, d, col)

## Деревянная лопата, воткнутая в снег.
func _shovel(p: Vector3, yaw: float) -> void:
	var bs := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -0.25)
	var up := bs * Vector3.UP
	logp(p + up * 0.25, p + up * 1.25, 0.018, 0.016, C_PLANK, "wood")
	box("wood", Transform3D(bs, p + up * 0.08), Vector3(0.24, 0.36, 0.025), C_PLANK)

# ---------- изба ----------

const CW := 4.0       # сруб по осям брёвен, X
const CD := 4.4       # сруб по осям брёвен, Z
const LR := 0.135     # радиус бревна
const CH := 0.215     # шаг венца
const NC := 11        # венцов
const OV := 0.3       # остаток (выпуск) бревна за угол
const Y0 := 0.32      # низ окладного венца над землёй (на камнях)
const DOOR := Vector2(0.44, 7.0)   # полуширина проёма, до какого венца
const WIN := Vector2(0.3, 0.0)     # полуширина окна (боковая стена +X), венцы 6–7
const ROOF_H := 1.75
const EAVE := 0.65

## Высота пола в избе (по местной оси).
static func floor_y() -> float:
	return Y0 + LR * 2.0 + 0.1

## Внутренние полуразмеры избы (чистые стены).
static func inner_half() -> Vector2:
	return Vector2(CW * 0.5 - LR - 0.02, CD * 0.5 - LR - 0.02)

static func top_y() -> float:
	return Y0 + LR + (NC - 1) * CH + CH * 0.5

## Изба: crowns — сколько венцов уже сложено (0..NC), roof — 0..1 доля кровли.
## gh — высоты земли под углами относительно начала (для камней под углы).
## Части: "base", "front_hi" (верх передней стены с дверью — прячется в интерьере), "roof", "floor".
func cabin(crowns: int, roof: float, gh: Array) -> Node3D:
	rng.seed = 909
	var root := Node3D.new()
	var hx := CW * 0.5
	var hz := CD * 0.5
	# камни под углами и серединами стен
	var pads := [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(-hx, hz), Vector2(hx, hz), Vector2(0, -hz), Vector2(-hx, 0), Vector2(hx, 0)]
	for i in pads.size():
		var p: Vector2 = pads[i]
		var g: float = gh[mini(i, gh.size() - 1)] if gh.size() > 0 else 0.0
		var hh := maxf(Y0 - g + 0.05, 0.15)
		stone(Vector3(p.x, g - 0.1, p.y), Vector3(0.4, hh * 0.62, 0.36), rng.randf() * TAU, 0.4)
	emit(root, "pads")
	var built := mini(crowns, NC)
	# два прохода: всё, кроме верха передней стены, и верх передней стены (прячется в интерьере)
	for pass_i in 2:
		for i in built:
			var ys := Y0 + LR + i * CH
			var yf := ys + CH * 0.5
			if pass_i == 0:
				# боковые стены (вдоль Z) на x = ±hx; окно в правой
				for sx: float in [-1.0, 1.0]:
					var col := C_LOG * rng.randf_range(0.92, 1.06)
					if sx > 0.0 and (i == 6 or i == 7):
						_log_split(Vector3(sx * hx, ys, -hz - OV), Vector3(sx * hx, ys, hz + OV), -WIN.x, WIN.x, col, 2)
					else:
						logp(Vector3(sx * hx, ys, -hz - OV), Vector3(sx * hx, ys, hz + OV), LR * 1.02, LR * 0.96, col, "wood", true, 11)
					# мох в пазах: виден в щелях между брёвнами
					box("paint", Transform3D(Basis(), Vector3(sx * hx, ys + CH * 0.5, 0)), Vector3(0.08, 0.05, CD - 0.1), C_MOSS)
				# задняя стена на полвенца выше
				logp(Vector3(-hx - OV, yf, -hz), Vector3(hx + OV, yf, -hz), LR * 0.98, LR * 1.02, C_LOG * rng.randf_range(0.92, 1.06))
				box("paint", Transform3D(Basis(), Vector3(0, yf + CH * 0.5, -hz)), Vector3(CW - 0.1, 0.05, 0.08), C_MOSS)
			if (i < 2) == (pass_i == 0):
				var col2 := C_LOG * rng.randf_range(0.92, 1.06)
				if i >= 1 and float(i) <= DOOR.y:
					_log_split(Vector3(-hx - OV, yf, hz), Vector3(hx + OV, yf, hz), -DOOR.x, DOOR.x, col2, 0)
				else:
					logp(Vector3(-hx - OV, yf, hz), Vector3(hx + OV, yf, hz), LR * 0.98, LR * 1.02, col2)
				box("paint", Transform3D(Basis(), Vector3(0, yf + CH * 0.5, hz)), Vector3(CW - 0.1, 0.05, 0.08), C_MOSS)
		if pass_i == 1 and built > int(DOOR.y):
			_door_parts()
		if _st.size() > 0:
			var mi := emit(root, "walls" if pass_i == 0 else "front_hi")
			mi.set_meta("cut", pass_i == 1)
	if built > 7:
		_window_parts()
		emit(root, "window")
	if built > 0:
		_floor()
		# крыльцо: бревно-ступень и площадка из доски
		logp(Vector3(-0.55, 0.16, hz + 0.45), Vector3(0.55, 0.16, hz + 0.45), 0.15, 0.15, C_LOG)
		box("wood", Transform3D(Basis(), Vector3(0, floor_y() - 0.07, hz + 0.22)), Vector3(1.1, 0.06, 0.45), C_PLANK)
		emit(root, "floor")
	if built >= NC and roof > 0.0:
		_roof(roof)
		var rm := emit(root, "roof")
		rm.set_meta("cut", true)
		# свет в избе — когда смотрим изнутри (кровля снята)
		var rl := OmniLight3D.new()
		rl.name = "room_light"
		rl.light_color = Color(1.0, 0.9, 0.75)
		rl.omni_range = 5.5
		rl.light_energy = 0.9
		rl.position = Vector3(0.6, top_y() - 0.2, 0.5)
		rl.visible = false
		root.add_child(rl)
	return root

## Бревно с проёмом: два отрезка с торцами у краёв проёма. axis 0 — X, 2 — Z.
func _log_split(a: Vector3, b: Vector3, lo: float, hi: float, col: Color, axis: int) -> void:
	var p_lo := a
	var p_hi := b
	p_lo[axis] = lo
	p_hi[axis] = hi
	logp(a, p_lo, LR, LR * 0.99, col)
	logp(p_hi, b, LR * 0.99, LR * 0.97, col)

func _door_parts() -> void:
	var hz := CD * 0.5
	var y_bot := Y0 + LR + CH * 0.5 + CH * 0.5
	var y_top := Y0 + LR + (DOOR.y + 1.0) * CH + CH * 0.5 - LR
	var dw := DOOR.x
	# косяки — толстые тёсаные брусья по краям проёма, связывают торцы брёвен
	for sx: float in [-1.0, 1.0]:
		box("wood", Transform3D(Basis(), Vector3(sx * (dw - 0.04), (y_bot + y_top) * 0.5, hz)), Vector3(0.09, y_top - y_bot, LR * 2.2), C_PLANK * 0.92)
	# притолока
	box("wood", Transform3D(Basis(), Vector3(0, y_top - 0.04, hz)), Vector3(dw * 2.0 + 0.04, 0.09, LR * 2.2), C_PLANK * 0.9)
	# порог
	box("wood", Transform3D(Basis(), Vector3(0, y_bot + 0.03, hz)), Vector3(dw * 2.0, 0.07, LR * 2.3), C_PLANK * 0.85)
	# полотно: вертикальные доски на двух шпонках с раскосом, деревянная ручка
	var z0 := hz + LR * 0.6
	var nb := 4
	var bw := (dw * 2.0 - 0.1) / nb
	for k in nb:
		var x := -dw + 0.05 + bw * (k + 0.5)
		box("wood", Transform3D(Basis(), Vector3(x, (y_bot + y_top) * 0.5 + 0.02, z0)), Vector3(bw - 0.008, y_top - y_bot - 0.1, 0.045), C_PLANK * rng.randf_range(0.85, 1.0))
	for yy: float in [y_bot + 0.25, y_top - 0.3]:
		box("wood", Transform3D(Basis(), Vector3(0, yy, z0 + 0.04)), Vector3(dw * 2.0 - 0.14, 0.1, 0.035), C_PLANK * 0.8)
	var dl := Vector3(-dw + 0.12, y_bot + 0.3, z0 + 0.04)
	var dh := Vector3(dw - 0.12, y_top - 0.35, z0 + 0.04)
	plank("wood", dl, dh, Vector3(0, 0, 1).cross(dh - dl), 0.09, 0.035, C_PLANK * 0.78)
	box("wood", Transform3D(Basis(), Vector3(dw - 0.18, (y_bot + y_top) * 0.5, z0 + 0.09)), Vector3(0.05, 0.28, 0.05), C_PLANK * 0.6)
	# тёмный проём за дверью (щели)
	box("paint", Transform3D(Basis(), Vector3(0, (y_bot + y_top) * 0.5, hz - 0.02)), Vector3(dw * 2.0 - 0.08, y_top - y_bot - 0.06, 0.02), Color(C_DARK, 0))

func _window_parts() -> void:
	var hx := CW * 0.5
	var y_lo := Y0 + LR + 6.0 * CH - LR + 0.02
	var y_hi := Y0 + LR + 7.0 * CH + LR - 0.02
	var w := WIN.x
	# оконная коробка
	for sz: float in [-1.0, 1.0]:
		box("wood", Transform3D(Basis(), Vector3(hx, (y_lo + y_hi) * 0.5, sz * (w - 0.03))), Vector3(LR * 2.2, y_hi - y_lo, 0.07), C_PLANK * 0.9)
	box("wood", Transform3D(Basis(), Vector3(hx, y_lo, 0)), Vector3(LR * 2.3, 0.06, w * 2.0), C_PLANK * 0.88)
	box("wood", Transform3D(Basis(), Vector3(hx, y_hi, 0)), Vector3(LR * 2.3, 0.06, w * 2.0), C_PLANK * 0.88)
	# слюда/пузырь — тёплое мутное стекло; переплёт крестом
	box("paint", Transform3D(Basis(), Vector3(hx, (y_lo + y_hi) * 0.5, 0)), Vector3(0.02, y_hi - y_lo - 0.06, w * 2.0 - 0.1), Color(0.42, 0.36, 0.24, 0))
	box("wood", Transform3D(Basis(), Vector3(hx + 0.02, (y_lo + y_hi) * 0.5, 0)), Vector3(0.03, y_hi - y_lo - 0.05, 0.035), C_PLANK * 0.7)
	box("wood", Transform3D(Basis(), Vector3(hx + 0.02, (y_lo + y_hi) * 0.5, 0)), Vector3(0.03, 0.035, w * 2.0 - 0.08), C_PLANK * 0.7)
	# наличник с «кокошником» сверху
	var xo := hx + LR + 0.02
	for sz2: float in [-1.0, 1.0]:
		box("wood", Transform3D(Basis(), Vector3(xo, (y_lo + y_hi) * 0.5, sz2 * (w + 0.05))), Vector3(0.03, y_hi - y_lo + 0.2, 0.1), C_PLANK * 1.05)
	box("wood", Transform3D(Basis(), Vector3(xo, y_lo - 0.08, 0)), Vector3(0.04, 0.08, w * 2.0 + 0.3), C_PLANK * 1.05)
	var yt := y_hi + 0.08
	tri("wood", Vector3(xo, yt, -w - 0.15), Vector3(xo, yt, w + 0.15), Vector3(xo, yt + 0.2, 0), C_PLANK * 1.08)
	box("wood", Transform3D(Basis(), Vector3(xo, yt, 0)), Vector3(0.04, 0.05, w * 2.0 + 0.34), C_PLANK)

func _floor() -> void:
	var ih := inner_half()
	var fy := floor_y()
	var n := int(ceil(ih.x * 2.0 / 0.24))
	var bw := ih.x * 2.0 / n
	for k in n:
		var x := -ih.x + bw * (k + 0.5)
		box("wood", Transform3D(Basis(), Vector3(x, fy - 0.025, 0)), Vector3(bw - 0.006, 0.05, ih.y * 2.0 + 0.1), Color(C_PLANK * rng.randf_range(0.95, 1.12), 0.0))
	# лаги под полом (видны у порога)
	for zz: float in [-1.2, 0.0, 1.2]:
		logp(Vector3(-ih.x, fy - 0.15, zz), Vector3(ih.x, fy - 0.15, zz), 0.08, 0.08, C_LOG * 0.8, "wood", false, 7)

## Кровля: самцы (фронтоны из укорачивающихся брёвен), слеги, тёс в два ряда, охлупень,
## причелины, печная труба. k — доля готовности (снизу вверх).
func _roof(k: float) -> void:
	var hx := CW * 0.5
	var hz := CD * 0.5
	var ytop := top_y() + LR
	var ng := 7
	var pitch := ROOF_H / (hx + EAVE)
	# самцы на передней и задней стене
	for sz: float in [-1.0, 1.0]:
		for g in ng:
			var yy := ytop + g * CH + CH * 0.5
			var half := (ROOF_H - (yy - ytop) - 0.05) / pitch - EAVE * 0.25
			if half < 0.25:
				break
			if float(g) / ng > k * 1.4:
				break
			logp(Vector3(-half, yy, sz * hz), Vector3(half, yy, sz * hz), LR * 0.95, LR * 0.95, C_LOG * rng.randf_range(0.9, 1.04))
	if k < 0.3:
		return
	# слеги: на концах самцов, вдоль избы с выпуском
	var zl := hz + 0.55
	for g in range(0, ng, 2):
		var yy2 := ytop + g * CH + CH * 0.5 + LR * 0.9
		var half2 := (ROOF_H - (yy2 - ytop)) / pitch - EAVE * 0.25 - 0.1
		if half2 < 0.2:
			continue
		for sx: float in [-1.0, 1.0]:
			logp(Vector3(sx * half2, yy2, -zl), Vector3(sx * half2, yy2, zl), 0.1, 0.09, C_LOG * 0.95)
	var ridge_y := ytop + ROOF_H
	logp(Vector3(0, ridge_y - 0.12, -zl), Vector3(0, ridge_y - 0.12, zl), 0.11, 0.1, C_LOG * 0.95)
	if k < 0.55:
		return
	# тёс: от конька к свесу, нижний ряд с зазорами, верхний закрывает зазоры
	var slope_len := sqrt((hx + EAVE) * (hx + EAVE) + ROOF_H * ROOF_H) + 0.05
	var nboard := int((zl * 2.0 + 0.2) / 0.24)
	var cover := clampf((k - 0.55) / 0.35, 0.0, 1.0)
	for sx: float in [-1.0, 1.0]:
		var top := Vector3(sx * 0.02, ridge_y, 0)
		var dn := Vector3(sx * (hx + EAVE), -ROOF_H, 0).normalized()
		var nrm := Vector3(sx * ROOF_H, hx + EAVE, 0).normalized()
		for layer in 2:
			for b in nboard:
				if float(b) / nboard > cover * 1.05:
					continue
				var z := -zl - 0.1 + 0.24 * (b + 0.5 + 0.5 * layer)
				if z > zl + 0.1:
					continue
				var len_k := slope_len + rng.randf_range(-0.06, 0.04)
				var a := top + Vector3(0, 0, z) + nrm * (0.03 + layer * 0.035)
				var e := a + dn * len_k
				plank("wood_f", a, e, Vector3(0, 0, 1), 0.2 if layer == 0 else 0.15, 0.03, C_ROOF * rng.randf_range(0.85, 1.08))
	if k < 0.95:
		return
	# охлупень: толстое бревно на коньке
	logp(Vector3(0, ridge_y + 0.08, -zl - 0.25), Vector3(0, ridge_y + 0.08, zl + 0.3), 0.15, 0.14, C_LOG * 0.9, "wood_f")
	# причелины по краям кровли и «полотенце» у конька
	for sz2: float in [-1.0, 1.0]:
		for sx2: float in [-1.0, 1.0]:
			var a2 := Vector3(0, ridge_y + 0.05, sz2 * (zl + 0.06))
			var e2 := Vector3(sx2 * (hx + EAVE + 0.05), ridge_y - ROOF_H - 0.02, sz2 * (zl + 0.06))
			plank("wood_f", a2, e2, Vector3(0, 0, 1).cross(e2 - a2), 0.2, 0.04, C_PLANK * 0.8)
		box("wood_f", Transform3D(Basis(), Vector3(0, ridge_y - 0.35, sz2 * (zl + 0.07))), Vector3(0.14, 0.6, 0.04), C_PLANK * 0.82)
	# печная труба (кирпич, побелена снизу) над задним левым углом
	var cx := -1.15
	var cz := -1.2
	var yb := ridge_y - (hx + EAVE - absf(cx)) * 0.0 - absf(cx) * pitch - 0.4
	box("paint_f", Transform3D(Basis(), Vector3(cx, (yb + ridge_y + 0.55) * 0.5, cz)), Vector3(0.46, ridge_y + 0.55 - yb, 0.46), C_BRICK)
	box("paint_f", Transform3D(Basis(), Vector3(cx, ridge_y + 0.58, cz)), Vector3(0.56, 0.07, 0.56), C_BRICK * 0.85)
	for k2 in 6:
		box("paint_f", Transform3D(Basis(), Vector3(cx, yb + 0.25 + k2 * 0.2, cz)), Vector3(0.465, 0.012, 0.465), Color(0.7, 0.66, 0.6))

## Где у избы выходит дым (местные координаты).
static func chimney_top() -> Vector3:
	return Vector3(-1.15, top_y() + LR + ROOF_H + 0.65, -1.2)

# ---------- печь ----------

## Русская печь в заднем левом углу: опечек, побелённое тело, шесток, устье аркой,
## печурки, лежанка, труба до потолка. Возвращает узел: "body", "mouth_fire" (пламя в устье).
func stove() -> Node3D:
	rng.seed = 1001
	var root := Node3D.new()
	var fy := floor_y()
	var ih := inner_half()
	var x0 := -ih.x + 0.02
	var x1 := x0 + 1.35
	var z0 := -ih.y + 0.02
	var z1 := z0 + 1.65
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	# опечек — сруб из брусьев под печью
	box("wood", Transform3D(Basis(), Vector3(cx, fy + 0.2, cz)), Vector3(x1 - x0, 0.4, z1 - z0), C_PLANK * 0.75)
	# тело печи, слегка неровное, с выступом-карнизом
	_lumpy_box(Vector3(cx, fy + 0.4, cz), Vector3(x1 - x0 - 0.04, 1.05, z1 - z0 - 0.04), C_PLASTER)
	_lumpy_box(Vector3(cx, fy + 1.45, cz), Vector3(x1 - x0 + 0.04, 0.08, z1 - z0 + 0.04), C_PLASTER * 0.97)
	# шесток перед устьем (смотрит в +Z)
	_lumpy_box(Vector3(cx, fy + 0.4, z1 - 0.02), Vector3(x1 - x0 - 0.1, 0.45, 0.35), C_PLASTER)
	# устье: тёмная арка в лицевой стене над шестком
	var mz := z1 - 0.02 + 0.001
	var mc := Vector3(cx, fy + 0.86, mz)
	var nseg := 9
	for k in nseg:
		var a0 := PI * k / nseg
		var a1 := PI * (k + 1) / nseg
		var p0 := mc + Vector3(cos(a0) * 0.26, sin(a0) * 0.28, 0)
		var p1 := mc + Vector3(cos(a1) * 0.26, sin(a1) * 0.28, 0)
		tri("paint", mc, p0, p1, Color(C_SOOT, 0))
		# закопчённый ободок
		var q0 := mc + Vector3(cos(a0) * 0.33, sin(a0) * 0.35, 0.003)
		var q1 := mc + Vector3(cos(a1) * 0.33, sin(a1) * 0.35, 0.003)
		quad("paint", p0 + Vector3(0, 0, 0.004), q0, q1, p1 + Vector3(0, 0, 0.004), Color(0.45, 0.42, 0.38, 0))
	box("paint", Transform3D(Basis(), Vector3(cx, fy + 0.83, mz - 0.001)), Vector3(0.52, 0.06, 0.01), Color(C_SOOT, 0))
	# заслонка прислонена рядом
	box("paint", Transform3D(Basis(Vector3.RIGHT, -0.15), Vector3(cx + 0.45, fy + 0.85 + 0.17, mz + 0.06)), Vector3(0.36, 0.38, 0.02), C_IRON)
	# печурки — ниши для сушки рукавиц
	for k2 in 2:
		var nc := Vector3(x1 - 0.02 + 0.001, fy + 1.05, z0 + 0.45 + k2 * 0.5)
		quad("paint", nc + Vector3(0, -0.1, -0.1), nc + Vector3(0, -0.1, 0.1), nc + Vector3(0, 0.1, 0.1), nc + Vector3(0, 0.1, -0.1), Color(0.3, 0.28, 0.25, 0))
	# труба до потолка
	_lumpy_box(Vector3(cx + 0.25, fy + 1.49, z0 + 0.35), Vector3(0.5, 2.2, 0.5), C_PLASTER * 0.98)
	# дрова у печи
	for k3 in 5:
		var y := fy + 0.05 + (k3 / 3) * 0.1
		_split_wood(Vector3(x1 + 0.12 + (k3 % 3) * 0.12, y, z1 - 0.1), Vector3(x1 + 0.12 + (k3 % 3) * 0.12, y, z1 - 0.55), 0.045)
	emit(root, "body")
	# огонь в устье
	var fl := MeshInstance3D.new()
	fl.name = "mouth_fire"
	var fs := SurfaceTool.new()
	fs.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k4 in 2:
		var d := Vector3(0.18, 0, 0.08 * (k4 - 0.5))
		var pts: Array = [[-d, Vector2(0, 0)], [d, Vector2(1, 0)], [d * 0.7 + Vector3(0, 0.3, 0), Vector2(1, 1)], [-d * 0.7 + Vector3(0, 0.3, 0), Vector2(0, 1)]]
		for i: int in [0, 1, 2, 0, 2, 3]:
			_v(fs, pts[i][0], Vector3.UP, pts[i][1], Color(k4 * 0.5, 0, 0, 1))
	var fm := ArrayMesh.new()
	fs.commit(fm)
	fm.surface_set_material(0, mats["flame"])
	fl.mesh = fm
	fl.position = Vector3(cx, fy + 0.86, mz - 0.03)
	fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(fl)
	var lt := OmniLight3D.new()
	lt.name = "light"
	lt.light_color = Color(1.0, 0.6, 0.3)
	lt.omni_range = 4.5
	lt.light_energy = 1.4
	lt.position = Vector3(cx, fy + 1.0, mz + 0.4)
	root.add_child(lt)
	return root

## Мазаная глыба: брусок с чуть неровными гранями (как оштукатурено руками).
func _lumpy_box(base_c: Vector3, size: Vector3, col: Color) -> void:
	var nx := maxi(2, int(size.x / 0.3))
	var ny := maxi(2, int(size.y / 0.3))
	var nz := maxi(2, int(size.z / 0.3))
	var h := size * 0.5
	var c := base_c + Vector3(0, h.y, 0)
	var off := rng.randf() * 10.0
	var jit := func(p: Vector3) -> Vector3:
		var e := Vector3(sin(p.y * 7.0 + p.z * 5.0 + off), sin(p.x * 6.0 + p.z * 8.0 + off), sin(p.x * 5.0 + p.y * 9.0 + off)) * 0.012
		return p + e
	for ax in 3:
		for sgn: float in [-1.0, 1.0]:
			var u := (ax + 1) % 3
			var w := (ax + 2) % 3
			var nu: int = [nx, ny, nz][u]
			var nw: int = [nx, ny, nz][w]
			for i in nu:
				for j in nw:
					var pts: Array = []
					for k: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
						var p := Vector3.ZERO
						p[ax] = sgn * h[ax]
						p[u] = -h[u] + size[u] * float(i + k.x) / nu
						p[w] = -h[w] + size[w] * float(j + k.y) / nw
						pts.append(jit.call(c + p))
					var n := Vector3.ZERO
					n[ax] = sgn
					var a: Vector3 = pts[0]
					var b: Vector3 = pts[1]
					var d: Vector3 = pts[2]
					if (b - a).cross(d - a).dot(n) < 0.0:
						quad("paint", pts[0], pts[3], pts[2], pts[1], Color(col, 0))
					else:
						quad("paint", pts[0], pts[1], pts[2], pts[3], Color(col, 0))

# ---------- мебель ----------

## Мебель: начало — середина основания на полу, лицом в +Z.
func furniture(kind: String) -> Node3D:
	rng.seed = kind.hash()
	var root := Node3D.new()
	match kind:
		"bed":
			# нары: брусья-ножки, царги, настил из досок, меховое одеяло, подушка
			for sx: float in [-0.45, 0.45]:
				for sz: float in [-0.95, 0.95]:
					box("wood", Transform3D(Basis(), Vector3(sx, 0.2, sz)), Vector3(0.08, 0.4, 0.08), C_PLANK * 0.8)
			for sx2: float in [-0.47, 0.47]:
				box("wood", Transform3D(Basis(), Vector3(sx2, 0.36, 0)), Vector3(0.05, 0.12, 2.0), C_PLANK * 0.85)
			for k in 8:
				box("wood", Transform3D(Basis(), Vector3(0, 0.425, -0.94 + k * 0.27)), Vector3(0.98, 0.035, 0.25), C_PLANK * rng.randf_range(0.85, 1.0))
			_fur_blanket(Vector3(0, 0.45, 0.2), Vector2(0.96, 1.4))
			_lumpy_box(Vector3(0, 0.45, -0.75), Vector3(0.6, 0.12, 0.32), C_LINEN)
		"table":
			for k in 3:
				box("wood", Transform3D(Basis(), Vector3(-0.27 + k * 0.27, 0.74, 0)), Vector3(0.26, 0.05, 1.25), C_PLANK * rng.randf_range(0.88, 1.02))
			for sz: float in [-0.48, 0.48]:
				# крестовина-козлы
				plank("wood", Vector3(-0.3, 0.0, sz), Vector3(0.28, 0.71, sz), Vector3(0, 0, 1).cross(Vector3(0.58, 0.71, 0)), 0.07, 0.06, C_PLANK * 0.8)
				plank("wood", Vector3(0.3, 0.0, sz), Vector3(-0.28, 0.71, sz), Vector3(0, 0, 1).cross(Vector3(-0.58, 0.71, 0)), 0.07, 0.06, C_PLANK * 0.8)
				box("wood", Transform3D(Basis(), Vector3(0, 0.69, sz)), Vector3(0.72, 0.05, 0.08), C_PLANK * 0.75)
			box("wood", Transform3D(Basis(), Vector3(0, 0.36, 0)), Vector3(0.06, 0.06, 1.0), C_PLANK * 0.75)
			# на столе: миска, кружка-туесок
			lathe("paint", Vector3(0.1, 0.765, 0.25), [Vector2(0.05, 0), Vector2(0.1, 0.04), Vector2(0.11, 0.06), Vector2(0.09, 0.055), Vector2(0.0, 0.02)], Color(0.55, 0.38, 0.22))
			lathe("paint", Vector3(-0.15, 0.765, -0.3), [Vector2(0.045, 0), Vector2(0.045, 0.11), Vector2(0.04, 0.11), Vector2(0.0, 0.01)], Color(0.85, 0.78, 0.62))
		"bench":
			box("wood", Transform3D(Basis(), Vector3(0, 0.44, 0)), Vector3(0.34, 0.06, 1.5), C_PLANK * rng.randf_range(0.9, 1.02))
			for sz: float in [-0.55, 0.55]:
				box("wood", Transform3D(Basis(), Vector3(0, 0.205, sz)), Vector3(0.3, 0.41, 0.06), C_PLANK * 0.82)
				box("paint", Transform3D(Basis(), Vector3(0, 0.06, sz)), Vector3(0.12, 0.12, 0.062), Color(C_DARK, 0))
		"shelf":
			for sz: float in [-0.4, 0.4]:
				box("wood", Transform3D(Basis(), Vector3(0, 1.32, sz - 0.0)), Vector3(0.3, 0.05, 0.05), C_PLANK * 0.8)
				plank("wood", Vector3(-0.12, 1.12, sz), Vector3(0.12, 1.31, sz), Vector3(0, 0, 1), 0.05, 0.04, C_PLANK * 0.8)
			box("wood", Transform3D(Basis(), Vector3(0, 1.37, 0)), Vector3(0.3, 0.04, 1.0), C_PLANK)
			box("wood", Transform3D(Basis(), Vector3(0, 1.75, 0)), Vector3(0.28, 0.04, 1.0), C_PLANK * 0.95)
			for sz2: float in [-0.4, 0.4]:
				box("wood", Transform3D(Basis(), Vector3(-0.12, 1.56, sz2)), Vector3(0.04, 0.38, 0.04), C_PLANK * 0.8)
			# горшки, туесок, миски
			lathe("paint", Vector3(0, 1.39, -0.25), [Vector2(0.06, 0), Vector2(0.1, 0.08), Vector2(0.09, 0.16), Vector2(0.07, 0.19), Vector2(0.08, 0.2), Vector2(0.0, 0.2)], Color(0.52, 0.34, 0.2))
			lathe("paint", Vector3(0.02, 1.39, 0.05), [Vector2(0.07, 0), Vector2(0.07, 0.17), Vector2(0.0, 0.17)], Color(0.86, 0.8, 0.66))
			lathe("paint", Vector3(0, 1.39, 0.3), [Vector2(0.05, 0), Vector2(0.11, 0.05), Vector2(0.0, 0.05)], Color(0.48, 0.32, 0.18))
			lathe("paint", Vector3(0, 1.77, -0.1), [Vector2(0.05, 0), Vector2(0.08, 0.1), Vector2(0.06, 0.18), Vector2(0.0, 0.18)], Color(0.45, 0.3, 0.2))
		"chest":
			for k in 3:
				box("wood", Transform3D(Basis(), Vector3(0, 0.08 + k * 0.15, 0)), Vector3(0.9, 0.145, 0.5), C_PLANK * rng.randf_range(0.7, 0.85))
			box("wood", Transform3D(Basis(), Vector3(0, 0.52, 0)), Vector3(0.94, 0.07, 0.54), C_PLANK * 0.72)
			for sx: float in [-0.3, 0.0, 0.3]:
				box("paint", Transform3D(Basis(), Vector3(sx, 0.28, 0)), Vector3(0.05, 0.58, 0.56), C_IRON)
			box("paint", Transform3D(Basis(), Vector3(0, 0.42, 0.28)), Vector3(0.08, 0.1, 0.02), C_IRON * 1.4)
		"rack":
			# сушило: две рогатины-козлы, жерди, вяленая рыба и растянутая шкура
			for sz: float in [-0.65, 0.65]:
				logp(Vector3(-0.3, 0, sz), Vector3(0.02, 1.6, sz), 0.03, 0.025, C_LOG, "bark")
				logp(Vector3(0.3, 0, sz), Vector3(-0.02, 1.6, sz), 0.03, 0.025, C_LOG, "bark")
			for yy: float in [1.5, 1.0]:
				var hw := (1.6 - yy) / 1.6 * 0.3
				logp(Vector3(hw * 0.0, yy, -0.75), Vector3(0, yy, 0.75), 0.02, 0.02, C_LOG, "bark")
				hw = hw
			for k in 4:
				var z := -0.45 + k * 0.3
				logp(Vector3(0, 1.5, z), Vector3(0, 1.38, z), 0.004, 0.004, C_FIBER, "paint", false, 4, 0.0)
				var prof: Array = []
				for i in 7:
					var t := float(i) / 6.0
					prof.append(Vector2(sin(PI * clampf(t * 1.1, 0.0, 1.0)) * 0.045 + 0.002, -t * 0.36))
				lathe("paint", Vector3(0, 1.38, z), prof, Color(0.62, 0.48, 0.26), 8)
				tri("paint", Vector3(0, 1.02, z), Vector3(0, 0.95, z - 0.05), Vector3(0, 0.95, z + 0.05), Color(0.55, 0.42, 0.24))
			var hc := Color(0.6, 0.46, 0.32)
			quad("paint", Vector3(0.05, 0.96, -0.6), Vector3(0.05, 0.96, 0.6), Vector3(0.12, 0.45, 0.55), Vector3(0.12, 0.45, -0.55), hc)
		"workbench":
			box("wood", Transform3D(Basis(), Vector3(0, 0.82, 0)), Vector3(0.65, 0.09, 1.6), C_PLANK * 0.92)
			for sx: float in [-0.26, 0.26]:
				for sz: float in [-0.68, 0.68]:
					box("wood", Transform3D(Basis(), Vector3(sx, 0.39, sz)), Vector3(0.1, 0.78, 0.1), C_PLANK * 0.78)
				box("wood", Transform3D(Basis(), Vector3(sx, 0.18, 0)), Vector3(0.06, 0.08, 1.3), C_PLANK * 0.75)
			for sz2: float in [-0.68, 0.68]:
				box("wood", Transform3D(Basis(), Vector3(0, 0.18, sz2)), Vector3(0.5, 0.08, 0.06), C_PLANK * 0.75)
			# тиски-клин и упор
			box("wood", Transform3D(Basis(), Vector3(0.33, 0.72, 0.6)), Vector3(0.08, 0.3, 0.22), C_PLANK * 0.7)
			logp(Vector3(0.38, 0.75, 0.6), Vector3(0.55, 0.75, 0.6), 0.025, 0.025, C_PLANK * 0.6, "wood")
			# рубанок и стружка
			box("wood", Transform3D(Basis(Vector3.UP, 0.3), Vector3(-0.05, 0.9, -0.3)), Vector3(0.07, 0.07, 0.28), C_PLANK * 0.6)
			for k in 7:
				var c := Vector3(rng.randf_range(-0.25, 0.25), 0.875, rng.randf_range(-0.1, 0.5))
				box("wood", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).rotated(Vector3.FORWARD, rng.randf_range(-0.4, 0.4)), c), Vector3(0.05, 0.012, 0.14), C_END)
			for k2 in 6:
				var c2 := Vector3(rng.randf_range(-0.4, 0.4), 0.01, rng.randf_range(-0.7, 0.7))
				box("wood", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), c2), Vector3(0.05, 0.012, 0.12), C_END)
	emit(root, "mesh")
	return root

func _fur_blanket(c: Vector3, sz: Vector2) -> void:
	var st := S("fur")
	var nx := 6
	var nz := 8
	var pts: Array = []
	for j in nz + 1:
		var row: Array = []
		for i in nx + 1:
			var x := -sz.x * 0.5 + sz.x * i / nx
			var z := -sz.y * 0.5 + sz.y * j / nz
			var edge := 1.0 if (i == 0 or i == nx) else 0.0
			row.append(c + Vector3(x * (1.0 + edge * 0.02), 0.03 + sin(z * 7.0 + x * 3.0) * 0.015 - edge * 0.07, z))
		pts.append(row)
	for j in nz:
		for i in nx:
			var a: Vector3 = pts[j][i]
			var b: Vector3 = pts[j][i + 1]
			var cc: Vector3 = pts[j + 1][i + 1]
			var d: Vector3 = pts[j + 1][i]
			var n := (d - a).cross(b - a).normalized()
			if n.y < 0.0:
				n = -n
			var col := Color(0.42, 0.3, 0.2)
			for v: Array in [[a, Vector2(i, j)], [cc, Vector2(i + 1, j + 1)], [b, Vector2(i + 1, j)], [a, Vector2(i, j)], [d, Vector2(i, j + 1)], [cc, Vector2(i + 1, j + 1)], [a, Vector2(i, j)], [b, Vector2(i + 1, j)], [cc, Vector2(i + 1, j + 1)], [a, Vector2(i, j)], [cc, Vector2(i + 1, j + 1)], [d, Vector2(i, j + 1)]]:
				_v(st, v[0], n, (v[1] as Vector2) * 0.3, col)

## Призрак постройки: тот же узел, все поверхности — полупрозрачный цвет допустимости.
static func ghostify(n: Node, mat: Material) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).material_override = mat
			(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif c is Light3D or c is GPUParticles3D:
			c.visible = false
		ghostify(c, mat)

## Площадка под избу: колышки по углам с бечёвкой и камни под углы.
func site_marks() -> Node3D:
	rng.seed = 1201
	var root := Node3D.new()
	var hx := CW * 0.5 + 0.2
	var hz := CD * 0.5 + 0.2
	var cs := [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]
	for i in 4:
		var p: Vector3 = cs[i]
		logp(p + Vector3(0, -0.1, 0), p + Vector3(0, 0.55, 0), 0.025, 0.02, C_LOG, "bark")
		var q: Vector3 = cs[(i + 1) % 4]
		logp(p + Vector3(0, 0.45, 0), q + Vector3(0, 0.45, 0), 0.004, 0.004, C_FIBER, "paint", false, 4, 0.0)
	emit(root, "stakes")
	return root

## Припасы у стройки: штабель брёвен на лагах, доски, мох, глина, камни — по числу внесённого.
func site_stock(have: Dictionary) -> Node3D:
	rng.seed = 1301
	var root := Node3D.new()
	var ox := CW * 0.5 + 1.4
	var nlog := int(have.get("log", 0))
	if nlog > 0:
		logp(Vector3(ox - 0.5, 0.06, -1.6), Vector3(ox + 0.5, 0.06, -1.6), 0.07, 0.07, C_LOG, "bark")
		logp(Vector3(ox - 0.5, 0.06, 1.6), Vector3(ox + 0.5, 0.06, 1.6), 0.07, 0.07, C_LOG, "bark")
	var per := 4
	for k in nlog:
		var row := k / per
		var col := k % per
		var w := per - (row % 2) * 0.5
		var x := ox - 0.42 + (col + (0.5 if row % 2 == 1 else 0.0)) * 0.27
		if row % 2 == 1 and col == per - 1:
			x = ox - 0.42 + col * 0.27
		var y := 0.2 + row * 0.235
		logp(Vector3(x, y, -2.0 + rng.randf_range(-0.1, 0.1)), Vector3(x, y, 2.0 + rng.randf_range(-0.1, 0.1)), 0.13, 0.12, C_LOG * rng.randf_range(0.85, 1.05), "bark")
		w = w
	var npl := int(have.get("plank", 0))
	for k2 in npl:
		box("wood", Transform3D(Basis(), Vector3(-CW * 0.5 - 1.2 + (k2 % 2) * 0.3, 0.04 + (k2 / 2) * 0.045, 0)), Vector3(0.26, 0.04, 2.6), C_PLANK * rng.randf_range(0.85, 1.02))
	var nmoss := int(have.get("moss", 0))
	for k3 in mini(nmoss, 12):
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.0, 0.35)
		pv.rng.seed = 40 + k3
		pv.moss_pad(S("moss"), S("moss_card"), Vector3(-CW * 0.5 - 1.1 + cos(a) * d, 0.08 + k3 * 0.012, CD * 0.5 + 0.9 + sin(a) * d), Vector3(0.26, 0.2, 0.26))
	var ncl := int(have.get("clay", 0))
	for k4 in mini(ncl, 14):
		var a2 := rng.randf() * TAU
		var d2 := rng.randf_range(0.0, 0.3)
		stone_like("paint", Vector3(CW * 0.5 + 1.3 + cos(a2) * d2, 0.08 + (k4 / 5) * 0.1, CD * 0.5 + 1.0 + sin(a2) * d2), Vector3(0.14, 0.09, 0.12), Basis(Vector3.UP, rng.randf() * TAU), C_CLAY)
	var npb := int(have.get("pebble", 0))
	for k5 in mini(npb, 20):
		var a3 := rng.randf() * TAU
		var d3 := rng.randf_range(0.0, 0.45)
		stone(Vector3(-CW * 0.5 - 1.2 + cos(a3) * d3, -0.04 + (k5 / 8) * 0.1, -CD * 0.5 - 0.8 + sin(a3) * d3), Vector3(0.12, 0.09, 0.1), rng.randf() * TAU)
	if _st.size() > 0:
		emit(root, "stock")
	return root
