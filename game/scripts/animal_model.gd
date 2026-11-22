extends RefCounted
## Сборка моделей зверей кодом: гладкие лофты с цветами вершин (спина темнее, брюхо светлее),
## шерсть — шумовая текстура. Каждая модель — 10–12 частей (туловище, голова, 4 ноги по 2 звена, хвост).

const SPECIES := {
	"hare": {"len": 0.46, "h": 0.26, "gw": 0.1, "gh": 0.11, "neck": 0.07, "head": 0.075, "snout": 0.05, "ear": 0.12, "ear_w": 0.025, "tail": 0.05, "tail_r": 0.035, "leg": 0.022, "hind": 1.35,
		"col": Color(0.46, 0.37, 0.27), "belly": Color(0.78, 0.74, 0.66), "winter": Color(0.93, 0.93, 0.92), "gait": "bound", "walk": 1.2, "run": 9.0},
	"squirrel": {"len": 0.2, "h": 0.09, "gw": 0.045, "gh": 0.05, "neck": 0.03, "head": 0.035, "snout": 0.02, "ear": 0.035, "ear_w": 0.012, "tail": 0.2, "tail_r": 0.05, "leg": 0.01, "hind": 1.3,
		"col": Color(0.6, 0.3, 0.13), "belly": Color(0.85, 0.8, 0.7), "winter": Color(0.45, 0.42, 0.42), "gait": "bound", "walk": 1.0, "run": 4.5},
	"fox": {"len": 0.62, "h": 0.36, "gw": 0.1, "gh": 0.11, "neck": 0.12, "head": 0.08, "snout": 0.11, "ear": 0.08, "ear_w": 0.035, "tail": 0.42, "tail_r": 0.07, "leg": 0.025, "hind": 1.0,
		"col": Color(0.78, 0.38, 0.14), "belly": Color(0.9, 0.86, 0.8), "winter": Color(0.82, 0.42, 0.16), "gait": "trot", "walk": 1.4, "run": 11.0},
	"roe": {"len": 1.0, "h": 0.72, "gw": 0.16, "gh": 0.2, "neck": 0.32, "head": 0.1, "snout": 0.13, "ear": 0.13, "ear_w": 0.05, "tail": 0.04, "tail_r": 0.04, "leg": 0.03, "hind": 1.05,
		"col": Color(0.55, 0.37, 0.22), "belly": Color(0.82, 0.76, 0.68), "winter": Color(0.42, 0.37, 0.32), "gait": "walk", "walk": 1.3, "run": 13.0, "antler": 0.18},
	"deer": {"len": 1.7, "h": 1.25, "gw": 0.27, "gh": 0.34, "neck": 0.55, "head": 0.16, "snout": 0.22, "ear": 0.16, "ear_w": 0.06, "tail": 0.08, "tail_r": 0.05, "leg": 0.05, "hind": 1.05,
		"col": Color(0.47, 0.33, 0.22), "belly": Color(0.7, 0.62, 0.52), "winter": Color(0.4, 0.34, 0.28), "gait": "walk", "walk": 1.4, "run": 12.0, "antler": 0.75},
	"boar": {"len": 1.25, "h": 0.72, "gw": 0.3, "gh": 0.38, "neck": 0.12, "head": 0.17, "snout": 0.3, "ear": 0.1, "ear_w": 0.06, "tail": 0.2, "tail_r": 0.015, "leg": 0.05, "hind": 0.95,
		"col": Color(0.24, 0.2, 0.17), "belly": Color(0.3, 0.26, 0.22), "winter": Color(0.22, 0.19, 0.17), "gait": "trot", "walk": 1.1, "run": 8.0, "tusk": true},
	"wolf": {"len": 1.05, "h": 0.78, "gw": 0.17, "gh": 0.22, "neck": 0.24, "head": 0.12, "snout": 0.15, "ear": 0.1, "ear_w": 0.045, "tail": 0.45, "tail_r": 0.06, "leg": 0.04, "hind": 1.0,
		"col": Color(0.46, 0.44, 0.41), "belly": Color(0.75, 0.72, 0.66), "winter": Color(0.55, 0.53, 0.5), "gait": "trot", "walk": 1.5, "run": 12.0},
	"bear": {"len": 1.75, "h": 1.0, "gw": 0.45, "gh": 0.5, "neck": 0.25, "head": 0.2, "snout": 0.2, "ear": 0.08, "ear_w": 0.07, "tail": 0.06, "tail_r": 0.05, "leg": 0.11, "hind": 0.95,
		"col": Color(0.3, 0.2, 0.13), "belly": Color(0.25, 0.17, 0.11), "winter": Color(0.3, 0.2, 0.13), "gait": "walk", "walk": 1.1, "run": 10.0},
	"beaver": {"len": 0.7, "h": 0.16, "gw": 0.19, "gh": 0.17, "neck": 0.04, "head": 0.08, "snout": 0.05, "ear": 0.02, "ear_w": 0.015, "tail": 0.3, "tail_r": 0.07, "leg": 0.03, "hind": 1.0,
		"col": Color(0.42, 0.3, 0.2), "belly": Color(0.54, 0.43, 0.32), "winter": Color(0.42, 0.3, 0.2), "gait": "walk", "walk": 0.6, "run": 1.9, "flat_tail": true},
	"tiger": {"len": 1.9, "h": 0.92, "gw": 0.33, "gh": 0.4, "neck": 0.25, "head": 0.19, "snout": 0.14, "ear": 0.07, "ear_w": 0.06, "tail": 0.9, "tail_r": 0.06, "leg": 0.09, "hind": 1.0,
		"col": Color(0.86, 0.46, 0.16), "belly": Color(0.95, 0.92, 0.86), "winter": Color(0.86, 0.5, 0.2), "gait": "walk", "walk": 1.3, "run": 13.0, "stripes": true},
}

static var _tex := {}

static func fur_tex(stripes: bool) -> Texture2D:
	var key := "s" if stripes else "f"
	if _tex.has(key):
		return _tex[key]
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var nz := FastNoiseLite.new()
	nz.frequency = 0.12
	for y in 64:
		for x in 64:
			# короткие штрихи шерсти вдоль тела
			var v := 0.82 + nz.get_noise_2d(x * 0.35, y * 2.0) * 0.25
			if stripes:
				var st := sin(x * 0.55 + nz.get_noise_2d(x, y) * 4.0)
				if st > 0.55:
					v *= 0.18
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex[key] = t
	return t

static var _fur_sh: Shader = null
static var _flat := {}

static func material(sp: Dictionary) -> ShaderMaterial:
	if _fur_sh == null:
		_fur_sh = load("res://shaders/paint/fur.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _fur_sh
	m.set_shader_parameter("stripes", 1.0 if sp.has("stripes") else 0.0)
	return m

## Однотонный живописный материал (нос, глаза, рога, клыки).
static func flat(c: Color) -> ShaderMaterial:
	var key := c.to_html()
	if _flat.has(key):
		return _flat[key]
	if _fur_sh == null:
		_fur_sh = load("res://shaders/paint/fur.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _fur_sh
	m.set_shader_parameter("use_vc", false)
	m.set_shader_parameter("tint", Vector3(c.r, c.g, c.b))
	_flat[key] = m
	return m

## Лофт вдоль оси Z: кольца [z, rx, ry, сдвиг y]; цвет — спина col, брюхо belly.
static func loft_z(rings: Array, col: Color, belly: Color, seg: int = 12) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := rings.size()
	for i in n:
		var r: Array = rings[i]
		for j in seg + 1:
			var a := TAU * j / seg
			var y := sin(a)
			st.set_color(belly.lerp(col, smoothstep(-0.6, 0.3, y)))
			st.set_uv(Vector2(float(j) / seg, float(i) / maxf(n - 1, 1) * 2.0))
			st.add_vertex(Vector3(cos(a) * r[1], y * r[2] + r[3], r[0]))
	for i in n - 1:
		for j in seg:
			var k := i * (seg + 1) + j
			st.add_index(k)
			st.add_index(k + seg + 1)
			st.add_index(k + 1)
			st.add_index(k + 1)
			st.add_index(k + seg + 1)
			st.add_index(k + seg + 2)
	st.generate_normals()
	return st.commit()

## Лофт вдоль -Y (нога): кольца [y, r].
static func loft_y(rings: Array, col: Color, seg: int = 8) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := rings.size()
	for i in n:
		var r: Array = rings[i]
		for j in seg + 1:
			var a := TAU * j / seg
			st.set_color(col)
			st.set_uv(Vector2(float(j) / seg, float(i)))
			st.add_vertex(Vector3(cos(a) * r[1], r[0], sin(a) * r[1] * float(r[2] if r.size() > 2 else 1.0)))
	for i in n - 1:
		for j in seg:
			var k := i * (seg + 1) + j
			st.add_index(k)
			st.add_index(k + 1)
			st.add_index(k + seg + 1)
			st.add_index(k + 1)
			st.add_index(k + seg + 2)
			st.add_index(k + seg + 1)
	st.generate_normals()
	return st.commit()

static func _mi(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if mesh.get_aabb().size.length() > 0.12 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

## Собирает зверя в узел a (у узла должны быть поля body, head, legs, tail, mats). Возвращает словарь узлов.
static func build(root: Node3D, kind: String, scale_k: float, male: bool, winter: bool = false) -> Dictionary:
	if kind == "beaver":
		return build_beaver(root, scale_k)
	var sp: Dictionary = SPECIES[kind]
	var L: float = sp["len"] * scale_k
	var H: float = sp["h"] * scale_k
	var gw: float = sp["gw"] * scale_k
	var gh: float = sp["gh"] * scale_k
	var col: Color = sp["winter"] if winter else sp["col"]
	var belly: Color = sp["belly"]
	if winter and kind == "hare":
		belly = Color(0.97, 0.97, 0.96)
	var m := material(sp)
	var out := {"mat": m}
	var body := Node3D.new()
	body.position = Vector3(0, H, 0)
	root.add_child(body)
	out["body"] = body
	# туловище: от крупа к груди; у кабана и медведя перёд массивнее
	var front_k := 1.15 if kind in ["boar", "bear", "tiger"] else 1.0
	# профиль: круп, впадина за рёбрами, грудная клетка, холка, переход к шее
	var hk := 1.08 if kind in ["hare", "squirrel"] else 1.0
	var bm := loft_z([
		[-L * 0.56, gw * 0.25, gh * 0.3, gh * 0.08],
		[-L * 0.52, gw * 0.62, gh * 0.68, gh * 0.04],
		[-L * 0.44, gw * 0.88 * hk, gh * 0.9 * hk, gh * 0.02],
		[-L * 0.32, gw * 0.95 * hk, gh * 0.98 * hk, 0.0],
		[-L * 0.16, gw * 0.88, gh * 0.92, -gh * 0.06],
		[L * 0.0, gw * 0.9, gh * 0.96, -gh * 0.1],
		[L * 0.16, gw * 0.98 * front_k, gh * 1.02 * front_k, -gh * 0.08],
		[L * 0.3, gw * 1.0 * front_k, gh * 1.04 * front_k, -gh * 0.02],
		[L * 0.42, gw * 0.9 * front_k, gh * 0.95 * front_k, gh * 0.08],
		[L * 0.5, gw * 0.7 * front_k, gh * 0.72 * front_k, gh * 0.18],
		[L * 0.56, gw * 0.42, gh * 0.45, gh * 0.26],
	], col, belly, 16)
	_mi(body, bm, m)
	# шея и голова
	var neck_len: float = sp["neck"] * scale_k
	var head := Node3D.new()
	var neck_up := 0.9 if kind in ["roe", "deer"] else (0.15 if kind in ["boar", "bear"] else 0.5)
	head.position = Vector3(0, gh * 0.35 + neck_len * neck_up, L * 0.5 + neck_len * (1.0 - neck_up * 0.6))
	body.add_child(head)
	out["head"] = head
	var nk := loft_z([[0.0, gw * 0.45, gh * 0.5, 0.0], [1.0, gw * 0.35, gh * 0.4, 0.0]], col, belly, 10)
	var nmi := _mi(body, nk, m, Vector3(0, gh * 0.2, L * 0.45))
	nmi.look_at_from_position(nmi.position, head.position, Vector3.UP)
	nmi.rotate_object_local(Vector3.UP, PI)
	nmi.scale = Vector3(1, 1, nmi.position.distance_to(head.position))
	var hs: float = sp["head"] * scale_k
	var sn: float = sp["snout"] * scale_k
	var hm := loft_z([
		[-hs * 0.9, hs * 0.55, hs * 0.6, 0.0],
		[-hs * 0.3, hs * 0.85, hs * 0.85, 0.0],
		[hs * 0.4, hs * 0.75, hs * 0.7, -hs * 0.05],
		[hs * 0.4 + sn * 0.5, hs * 0.45, hs * 0.42, -hs * 0.2],
		[hs * 0.4 + sn, hs * 0.28, hs * 0.28, -hs * 0.28],
		[hs * 0.42 + sn, hs * 0.08, hs * 0.08, -hs * 0.28],
	], col, belly, 12)
	_mi(head, hm, m)
	var dark := flat(Color(0.05, 0.04, 0.035))
	# нос и глаза
	var ns := SphereMesh.new()
	ns.radius = hs * 0.17
	ns.height = hs * 0.3
	ns.radial_segments = 8
	ns.rings = 4
	_mi(head, ns, dark, Vector3(0, -hs * 0.26, hs * 0.42 + sn))
	var ey := SphereMesh.new()
	ey.radius = hs * 0.11
	ey.height = hs * 0.22
	ey.radial_segments = 8
	ey.rings = 4
	for sd in [-1.0, 1.0]:
		_mi(head, ey, dark, Vector3(sd * hs * 0.62, hs * 0.25, hs * 0.25))
	# уши
	var ear_l: float = sp["ear"] * scale_k
	var ew: float = sp["ear_w"] * scale_k
	var em := loft_y([[0.0, ew, 0.45], [ear_l * 0.5, ew * 0.9, 0.4], [ear_l, ew * 0.2, 0.4]], col, 6)
	for sd in [-1.0, 1.0]:
		_mi(head, em, m, Vector3(sd * hs * 0.5, hs * 0.6, -hs * 0.35), Vector3(-0.3, 0, -sd * (0.5 if kind != "hare" else 0.15)))
	# рога
	if sp.has("antler") and male:
		var am := flat(Color(0.55, 0.47, 0.36))
		var al: float = sp["antler"] * scale_k
		var tm := loft_y([[0.0, 0.025 * scale_k], [al, 0.008 * scale_k]], Color.WHITE, 5)
		for sd in [-1.0, 1.0]:
			var a := Node3D.new()
			a.position = Vector3(sd * hs * 0.35, hs * 0.75, -hs * 0.2)
			a.rotation = Vector3(-0.5, 0, -sd * 0.45)
			head.add_child(a)
			_mi(a, tm, am)
			for t in [0.35, 0.6, 0.85]:
				if al < 0.3 and t > 0.4:
					continue
				var tine := _mi(a, tm, am, Vector3(0, al * t, 0), Vector3(0.9, 0, sd * 0.25))
				tine.scale = Vector3(0.7, 0.35, 0.7)
	# клыки кабана
	if sp.has("tusk"):
		var tm2 := flat(Color(0.9, 0.86, 0.76))
		var tk := loft_y([[0.0, 0.012 * scale_k], [0.07 * scale_k, 0.003]], Color.WHITE, 5)
		for sd in [-1.0, 1.0]:
			_mi(head, tk, tm2, Vector3(sd * hs * 0.32, -hs * 0.3, hs * 0.3 + sn * 0.8), Vector3(0.3, 0, sd * 0.6))
	# хвост
	var tl: float = sp["tail"] * scale_k
	var tr: float = sp["tail_r"] * scale_k
	var tail := Node3D.new()
	tail.position = Vector3(0, gh * 0.25, -L * 0.53)
	body.add_child(tail)
	out["tail"] = tail
	var tmz := loft_z([[0.0, tr * 0.5, tr * 0.5, 0.0], [-tl * 0.4, tr, tr, 0.0], [-tl * 0.85, tr * 0.85, tr * 0.85, 0.0], [-tl, tr * 0.2, tr * 0.2, 0.0]], col, belly, 8)
	var tmi := _mi(tail, tmz, m, Vector3.ZERO, Vector3(-0.6 if kind in ["fox", "wolf", "tiger"] else -1.2 if kind == "squirrel" else 0.3, 0, 0))
	if sp.has("flat_tail"):
		tmi.rotation = Vector3(0.1, 0, 0)
		tmi.scale = Vector3(1.4, 0.3, 1.0)
	# ноги: бедро/плечо и голень, копыто/лапа
	var legs := []
	var lr: float = sp["leg"] * scale_k
	var hind_k: float = sp["hind"]
	var leg_col := col.darkened(0.25) if kind in ["fox", "roe", "deer", "wolf"] else col
	for i in 4:
		var front := i < 2
		var sd := -1.0 if i % 2 == 0 else 1.0
		var len_k := (1.0 if front else hind_k)
		var up_len := H * 0.52 * (len_k if not front else 1.0)
		var lo_len := H * 0.5
		var hip := Node3D.new()
		hip.position = Vector3(sd * gw * 0.6, -gh * 0.15, (L * 0.36) if front else (-L * 0.36))
		body.add_child(hip)
		var thick := lr * (2.2 if not front else 1.8)
		var um := loft_y([[0.0, thick, 1.2], [-up_len * 0.5, thick * 0.8, 1.1], [-up_len, lr * 1.1, 1.0]], leg_col, 8)
		_mi(hip, um, m)
		var knee := Node3D.new()
		knee.position = Vector3(0, -up_len, 0)
		hip.add_child(knee)
		var lm := loft_y([[0.0, lr * 1.1], [-lo_len * 0.85, lr * 0.85], [-lo_len, lr * 1.25]], leg_col.darkened(0.15), 6)
		_mi(knee, lm, m)
		legs.append({"hip": hip, "knee": knee, "front": front, "up": up_len, "lo": lo_len})
	out["legs"] = legs
	out["L"] = L
	out["H"] = H
	return out

# ---------- бобр ----------
## Сетка из кусков с цветами вершин. Один кусок — один вызов отрисовки.
class MB extends RefCounted:
	var v := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()

	## Лофт вдоль Z: кольца [z, rx, ry, сдвиг y]; цвет — спина col, брюхо belly.
	func loft(rings: Array, col: Color, belly: Color, seg: int, xf: Transform3D = Transform3D.IDENTITY) -> void:
		var base := v.size()
		var n := rings.size()
		for i in n:
			var r: Array = rings[i]
			for j in seg + 1:
				var a := TAU * j / seg
				var y := sin(a)
				v.append(xf * Vector3(cos(a) * float(r[1]), y * float(r[2]) + float(r[3]), float(r[0])))
				c.append(belly.lerp(col, smoothstep(-0.6, 0.3, y)))
				uv.append(Vector2(float(j) / seg, float(i) / maxf(n - 1, 1) * 2.0))
		for i in n - 1:
			for j in seg:
				var k := base + i * (seg + 1) + j
				idx.append_array([k, k + seg + 1, k + 1, k + 1, k + seg + 1, k + seg + 2])

	## Эллипсоид; pattern > 0 — шахматка тёмных «чешуек».
	func ell(ctr: Vector3, rad: Vector3, col: Color, xf: Transform3D = Transform3D.IDENTITY, seg: int = 8, rings: int = 5, pattern: float = 0.0) -> void:
		var base := v.size()
		for i in rings + 1:
			var th := PI * float(i) / rings
			for j in seg + 1:
				var a := TAU * j / seg
				var d := Vector3(sin(th) * cos(a), cos(th), sin(th) * sin(a))
				v.append(xf * (ctr + d * rad))
				c.append(col.darkened(pattern) if pattern > 0.0 and (i + j) % 2 == 0 else col)
				uv.append(Vector2(float(j) / seg, float(i) / rings))
		for i in rings:
			for j in seg:
				var k := base + i * (seg + 1) + j
				idx.append_array([k, k + seg + 1, k + 1, k + 1, k + seg + 1, k + seg + 2])

	## Тело вращения вокруг Y: кольца [y, r, цвет]; cap — закрыть верх точкой.
	func lathe(rings: Array, seg: int, xf: Transform3D, cap: bool) -> void:
		var base := v.size()
		var n := rings.size()
		for i in n:
			var r: Array = rings[i]
			for j in seg + 1:
				var a := TAU * j / seg
				v.append(xf * Vector3(cos(a) * float(r[1]), float(r[0]), sin(a) * float(r[1])))
				c.append(r[2])
				uv.append(Vector2(float(j) / seg, float(r[0]) * 2.0))
		for i in n - 1:
			for j in seg:
				var k := base + i * (seg + 1) + j
				idx.append_array([k, k + 1, k + seg + 1, k + 1, k + seg + 2, k + seg + 1])
		if cap:
			var last: Array = rings[n - 1]
			var ci := v.size()
			v.append(xf * Vector3(0, float(last[0]), 0))
			c.append(last[2])
			uv.append(Vector2(0.5, 0.5))
			var k0 := base + (n - 1) * (seg + 1)
			for j in seg:
				idx.append_array([k0 + j, k0 + j + 1, ci])

	func tri(a: Vector3, b: Vector3, d: Vector3, col: Color) -> void:
		var base := v.size()
		v.append_array([a, b, d])
		c.append_array([col, col, col])
		uv.append_array([Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(d.x, d.z)])
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 1])

	## Готовая сетка: гладкие нормали (SurfaceTool, как у остальных зверей).
	func commit() -> ArrayMesh:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in v.size():
			st.set_color(c[i])
			st.set_uv(uv[i])
			st.add_vertex(v[i])
		for i in idx:
			st.add_index(i)
		st.generate_normals()
		return st.commit()

## Бобр ~1,1 м с хвостом: грузное грушевидное тело (зад шире), маленькая голова с рыжими резцами,
## крошечные уши, плоский чешуйчатый хвост-весло, большие перепончатые задние лапы.
## Семь частей (тело, голова, хвост, 4 лапы) — семь вызовов отрисовки, всё на цветах вершин.
static func build_beaver(root: Node3D, sk: float) -> Dictionary:
	var sp: Dictionary = SPECIES["beaver"]
	var col: Color = sp["col"]
	var belly: Color = sp["belly"]
	var m := material(sp)
	var H := 0.145 * sk
	var S := Transform3D(Basis().scaled(Vector3(sk, sk, sk)), Vector3.ZERO)
	var body := Node3D.new()
	body.position = Vector3(0, H, 0)
	root.add_child(body)
	var b := MB.new()
	b.loft([
		[-0.39, 0.03, 0.03, 0.03],
		[-0.36, 0.11, 0.1, 0.04],
		[-0.29, 0.17, 0.155, 0.05],
		[-0.18, 0.2, 0.18, 0.055],
		[-0.06, 0.195, 0.175, 0.05],
		[0.05, 0.17, 0.16, 0.04],
		[0.14, 0.135, 0.13, 0.035],
		[0.21, 0.105, 0.105, 0.04],
		[0.26, 0.09, 0.09, 0.045],
		[0.3, 0.04, 0.04, 0.045],
	], col, belly, 14, S)
	var bmi := _mi(body, b.commit(), m)
	bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# голова: круглая, тупая морда, щёки, нос, глаза, ушки, оранжевые резцы
	var head := Node3D.new()
	head.position = Vector3(0, 0.045, 0.275) * sk
	body.add_child(head)
	var hcol := col.darkened(0.08)
	var h := MB.new()
	h.loft([
		[-0.06, 0.035, 0.035, 0.0],
		[-0.04, 0.085, 0.08, 0.0],
		[0.0, 0.095, 0.088, 0.0],
		[0.05, 0.086, 0.074, -0.01],
		[0.09, 0.068, 0.058, -0.022],
		[0.115, 0.054, 0.044, -0.03],
		[0.132, 0.03, 0.028, -0.034],
	], hcol, belly, 12, S)
	h.ell(Vector3(0, -0.036, 0.06), Vector3(0.07, 0.04, 0.065), belly.darkened(0.1), S, 8, 4)
	var black := Color(0.04, 0.03, 0.03)
	h.ell(Vector3(0, -0.018, 0.13), Vector3(0.026, 0.017, 0.013), black, S, 6, 3)
	for sd in [-1.0, 1.0]:
		h.ell(Vector3(sd * 0.056, 0.04, 0.05), Vector3(0.012, 0.012, 0.012), black, S, 6, 3)
		h.ell(Vector3(sd * 0.064, 0.066, -0.02), Vector3(0.02, 0.022, 0.011), col.darkened(0.35), S, 6, 3)
		h.ell(Vector3(sd * 0.008, -0.06, 0.118), Vector3(0.0075, 0.02, 0.0045), Color(0.9, 0.45, 0.08), S, 4, 2)
	_mi(head, h.commit(), m).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# хвост: мохнатый корень и плоское тёмное весло в чешуйках
	var tail := Node3D.new()
	tail.position = Vector3(0, -0.03, -0.36) * sk
	body.add_child(tail)
	var t := MB.new()
	t.ell(Vector3(0, 0, -0.02), Vector3(0.05, 0.035, 0.05), col, S, 8, 4)
	t.ell(Vector3(0, 0, -0.18), Vector3(0.068, 0.013, 0.155), Color(0.13, 0.11, 0.1), S, 16, 10, 0.35)
	_mi(tail, t.commit(), m).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# лапы: передние короткие с ладошками, задние — мощные бёдра и широкие перепончатые ступни
	var legs := []
	var dark := Color(0.12, 0.09, 0.08)
	for i in 4:
		var front := i < 2
		var sd := -1.0 if i % 2 == 0 else 1.0
		var hip := Node3D.new()
		hip.position = (Vector3(sd * 0.09, -0.06, 0.13) if front else Vector3(sd * 0.14, -0.035, -0.17)) * sk
		body.add_child(hip)
		var l := MB.new()
		if front:
			l.ell(Vector3(0, -0.03, 0.0), Vector3(0.034, 0.045, 0.034), col.darkened(0.1), S, 6, 4)
			l.ell(Vector3(0, -0.07, 0.02), Vector3(0.026, 0.012, 0.032), dark, S, 6, 3)
		else:
			l.ell(Vector3(0, 0.0, 0.0), Vector3(0.07, 0.08, 0.09), col, S, 8, 5)
			l.ell(Vector3(0, -0.06, -0.01), Vector3(0.035, 0.04, 0.035), col.darkened(0.1), S, 6, 4)
			l.ell(Vector3(0, -0.1, 0.055), Vector3(0.055, 0.011, 0.1), dark, S, 10, 3)
		var lmi := _mi(hip, l.commit(), m)
		lmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# лапы мелкие: издали не рисуем
		lmi.visibility_range_end = 35.0
		legs.append({"hip": hip, "knee": hip, "front": front, "up": 0.06 * sk, "lo": 0.06 * sk})
	return {"mat": m, "body": body, "head": head, "tail": tail, "legs": legs, "L": 0.7 * sk, "H": H}
