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
	"beaver": {"len": 0.72, "h": 0.2, "gw": 0.16, "gh": 0.15, "neck": 0.04, "head": 0.08, "snout": 0.05, "ear": 0.02, "ear_w": 0.015, "tail": 0.3, "tail_r": 0.07, "leg": 0.03, "hind": 1.0,
		"col": Color(0.33, 0.22, 0.14), "belly": Color(0.38, 0.27, 0.18), "winter": Color(0.33, 0.22, 0.14), "gait": "walk", "walk": 0.8, "run": 2.5, "flat_tail": true},
	"tiger": {"len": 1.9, "h": 0.92, "gw": 0.33, "gh": 0.4, "neck": 0.25, "head": 0.19, "snout": 0.14, "ear": 0.07, "ear_w": 0.06, "tail": 0.9, "tail_r": 0.06, "leg": 0.09, "hind": 1.0,
		"col": Color(0.86, 0.46, 0.16), "belly": Color(0.95, 0.92, 0.86), "winter": Color(0.86, 0.5, 0.2), "gait": "walk", "walk": 1.3, "run": 13.0, "stripes": true},
	# новые виды тайги: модель — build_taiga(), походка — animal.gd _animate_rig();
	# swalk/srun — длина шага в долях длины ноги на шагу и на полном бегу
	"moose": {"taiga": true, "gait": "trot", "walk": 1.4, "run": 11.0, "swalk": 1.25, "srun": 2.8},
	"lynx": {"taiga": true, "gait": "gallop", "walk": 1.1, "run": 12.0, "swalk": 1.3, "srun": 4.6},
	"wolverine": {"taiga": true, "gait": "bound", "walk": 1.0, "run": 7.5, "swalk": 1.4, "srun": 4.2},
	"muskdeer": {"taiga": true, "gait": "bound", "walk": 0.9, "run": 11.0, "swalk": 1.3, "srun": 5.5},
	"capercaillie": {"taiga": true, "gait": "bird", "walk": 0.6, "run": 8.0, "swalk": 1.6, "srun": 3.0},
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
	var sp: Dictionary = SPECIES[kind]
	if sp.has("taiga"):
		return build_taiga(root, kind, scale_k, male, winter)
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
	# шея от груди к голове (в координатах туловища: +Z меша смотрит на голову)
	nmi.basis = Basis.looking_at(nmi.position - head.position, Vector3.UP)
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

# ---------- Новые звери тайги: лось, рысь, росомаха, кабарга, глухарь ----------
# Меши строятся один раз на вид/пол/сезон в масштабе 1 и делятся между особями (размер особи —
# масштаб узла модели). Части, которые двигаются вместе, слиты в один меш (один вызов отрисовки).
# Нога — три звена (плечо/бедро, предплечье/голень, пясть/плюсна) и стопа; ось звена — вниз.

static var _tg_cache := {}
static var _tg_mats := {}

static func _tg_mat(pattern: float) -> ShaderMaterial:
	var key := str(pattern)
	if _tg_mats.has(key):
		return _tg_mats[key]
	if _fur_sh == null:
		_fur_sh = load("res://shaders/paint/fur.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _fur_sh
	m.set_shader_parameter("spots", pattern)
	_tg_mats[key] = m
	return m

## Трубка вдоль +Z: кольца [z, rx, ry, сдвиг y, множитель низа, сдвиг x].
## Окраска pc: back, belly; полоса band (band_lo..band_hi по высоте сечения, band_t0..band_t1 вдоль);
## кончик tip с tip_t; pat — маска узора шейдера (пятна/рябь).
static func tube(rings: Array, pc: Dictionary, seg: int = 12) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := rings.size()
	var back: Color = pc.get("back", Color(0.5, 0.5, 0.5))
	var belly: Color = pc.get("belly", back)
	var z0: float = rings[0][0]
	var z1: float = rings[n - 1][0]
	var pat: float = pc.get("pat", 0.0)
	for i in n:
		var r: Array = rings[i]
		var t := (float(r[0]) - z0) / maxf(z1 - z0, 0.0001)
		var bk: float = r[4] if r.size() > 4 else 1.0
		var xo: float = r[5] if r.size() > 5 else 0.0
		for j in seg + 1:
			var a := TAU * j / seg - PI * 0.5
			var y := sin(a)
			var ry: float = float(r[2]) * (bk if y < 0.0 else 1.0)
			var c := belly.lerp(back, smoothstep(-0.55, 0.35, y))
			if pc.has("band"):
				var lo: float = pc["band_lo"]
				var hi: float = pc["band_hi"]
				var t0: float = pc.get("band_t0", -1.0)
				var t1: float = pc.get("band_t1", 2.0)
				var bm := smoothstep(lo - 0.15, lo, y) * (1.0 - smoothstep(hi, hi + 0.15, y))
				bm *= smoothstep(t0 - 0.1, t0, t) * (1.0 - smoothstep(t1, t1 + 0.1, t))
				c = c.lerp(pc["band"], bm)
			if pc.has("tip"):
				var tt: float = pc["tip_t"]
				c = c.lerp(pc["tip"], smoothstep(tt, tt + 0.08, t))
			c.a = pat * smoothstep(-0.95, -0.3, y)
			st.set_color(c)
			st.set_uv(Vector2(float(j) / seg, float(r[0]) * 3.0))
			st.add_vertex(Vector3(cos(a) * float(r[1]) + xo, y * ry + float(r[3]), r[0]))
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

## Плоский веер (хвост глухаря): полукруг в плоскости XZ к -Z, с двух сторон.
static func fan(rad: float, col: Color, tip: Color, pat: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 12
	for side in [1.0, -1.0]:
		for i in n:
			var a0 := PI * (0.08 + 0.84 * float(i) / n)
			var a1 := PI * (0.08 + 0.84 * float(i + 1) / n)
			# перо чуть изогнуто вверх к краю
			var p0 := Vector3(0, 0, 0)
			var p1 := Vector3(cos(a0) * rad, rad * 0.06, -sin(a0) * rad)
			var p2 := Vector3(cos(a1) * rad, rad * 0.06, -sin(a1) * rad)
			var nn := Vector3(0, side, 0)
			var cs := [col, tip, tip]
			var ps := [p0, p1, p2] if side > 0.0 else [p0, p2, p1]
			if side < 0.0:
				cs = [col, tip, tip]
			for k in 3:
				var c: Color = cs[k]
				c.a = pat
				st.set_color(c)
				st.set_normal(nn)
				var pp: Vector3 = ps[k]
				st.set_uv(Vector2(pp.x * 3.0, pp.z * 3.0))
				st.add_vertex(pp + Vector3(0, -0.002 * side, 0))
	return st.commit()

## Базис, у которого +Z смотрит по dir (для деталей-трубок).
static func _aim(dir: Vector3, side: Vector3 = Vector3.UP) -> Basis:
	var z := dir.normalized()
	var up := side if absf(z.dot(side.normalized())) < 0.95 else Vector3.FORWARD
	var x := up.cross(z).normalized()
	var y := z.cross(x)
	return Basis(x, y, z)

## Сливает детали [меш, Transform3D] в один меш.
static func _merge(pieces: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for pc: Array in pieces:
		var m: Mesh = pc[0]
		st.append_from(m, 0, pc[1])
	return st.commit()

static func _ell(ln: float, rx: float, ry: float, pc: Dictionary, seg: int = 8) -> ArrayMesh:
	return tube([[0.0, rx * 0.25, ry * 0.25, 0.0], [ln * 0.15, rx * 0.8, ry * 0.8, 0.0], [ln * 0.5, rx, ry, 0.0], [ln * 0.85, rx * 0.8, ry * 0.8, 0.0], [ln, rx * 0.2, ry * 0.2, 0.0]], pc, seg)

static func _tf(b: Basis, o: Vector3) -> Transform3D:
	return Transform3D(b, o)

## Звено ноги: кольца [доля длины, rx, rz(спереди-сзади), сдвиг вперёд] → трубка вниз.
static func _leg_seg(ln: float, rs: Array, pc: Dictionary) -> ArrayMesh:
	# скруглённое начало звена заходит в сустав — без щели на сгибе
	var r0: Array = rs[0]
	var rings := [[-float(r0[1]) * 0.9, float(r0[1]) * 0.6, float(r0[2]) * 0.6, 0.0], [-float(r0[1]) * 0.45, float(r0[1]) * 0.95, float(r0[2]) * 0.95, 0.0]]
	for r: Array in rs:
		rings.append([float(r[0]) * ln, r[1], r[2], r[3] if r.size() > 3 else 0.0])
	var m := tube(rings, pc, 8)
	# трубка вдоль +Z → вдоль -Y (передняя сторона трубки — +Z)
	return _merge([[m, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)]])

static func build_taiga(root: Node3D, kind: String, scale_k: float, male: bool, winter: bool) -> Dictionary:
	var key := "%s_%s_%s" % [kind, male, winter]
	if not _tg_cache.has(key):
		match kind:
			"moose":
				_tg_cache[key] = _def_moose(male, winter)
			"lynx":
				_tg_cache[key] = _def_lynx(winter)
			"wolverine":
				_tg_cache[key] = _def_wolverine()
			"muskdeer":
				_tg_cache[key] = _def_muskdeer(male)
			"capercaillie":
				_tg_cache[key] = _def_bird(male)
	var d: Dictionary = _tg_cache[key]
	var model := Node3D.new()
	model.scale = Vector3.ONE * scale_k
	root.add_child(model)
	var mat: Material = d["mat"]
	var out := {"rig": true, "model": model, "mat": mat, "def": d, "sk": scale_k}
	var body := Node3D.new()
	body.position = Vector3(0, d["H"], 0)
	model.add_child(body)
	out["body"] = body
	var tm := _mi(body, d["torso"], mat)
	tm.rotation.x = d.get("tilt", 0.0)
	# шея и голова
	var neck := Node3D.new()
	neck.position = d["neck_pos"]
	neck.rotation.x = d["neck_pitch"]
	body.add_child(neck)
	_mi(neck, d["neck"], mat)
	var head := Node3D.new()
	head.position = Vector3(0, 0, d["neck_len"])
	head.rotation.x = d["head_pitch"]
	neck.add_child(head)
	_mi(head, d["head"], mat)
	out["neck"] = neck
	out["head"] = head
	# хвост
	var tail := Node3D.new()
	tail.position = d["tail_pos"]
	tail.rotation.x = d["tail_pitch"]
	body.add_child(tail)
	_mi(tail, d["tail"], mat)
	out["tail"] = tail
	# ноги
	var legs := []
	for lg: Dictionary in d["legs"]:
		var j := []
		var parent: Node3D = body
		var pos: Vector3 = lg["pos"]
		var segs: Array = lg["segs"]
		for k in 3:
			var nd := Node3D.new()
			nd.position = pos if k == 0 else Vector3(0, -float(segs[k - 1]), 0)
			nd.rotation.x = lg["rest"][k]
			parent.add_child(nd)
			var mi := _mi(nd, lg["meshes"][k], mat)
			if k > 0:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			j.append(nd)
			parent = nd
		var foot := Node3D.new()
		foot.position = Vector3(0, -float(segs[2]), 0)
		parent.add_child(foot)
		if lg["foot"] != null:
			var fm := _mi(foot, lg["foot"], mat)
			fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		j.append(foot)
		legs.append({"j": j, "rest": lg["rest"], "front": lg["front"]})
	out["legs"] = legs
	# крылья птицы: плечо (взмах) → разворот (сложено/раскрыто) → меш (крен)
	if d.has("wing"):
		var wings := []
		for sd in [-1.0, 1.0]:
			var f := Node3D.new()
			f.position = Vector3(sd * d["wing_x"], d["wing_y"], d["wing_z"])
			body.add_child(f)
			var w := Node3D.new()
			f.add_child(w)
			var wm := _mi(w, d["wing"], mat)
			wm.rotation = Vector3(0, PI, 0)
			wings.append({"f": f, "w": w, "m": wm, "sd": sd})
		out["wings"] = wings
	out["L"] = float(d["L"]) * scale_k
	out["H"] = float(d["H"]) * scale_k
	return out

## Ставит ноги: высота туловища по передним ногам, задние ноги подгоняются по длине.
static func _fit_legs(d: Dictionary) -> void:
	var legs: Array = d["legs"]
	var sole: float = d.get("sole", 0.0)
	var fr: Dictionary = legs[0]
	var H := _reach(fr) + sole - float((fr["pos"] as Vector3).y)
	d["H"] = H
	for lg: Dictionary in legs:
		if lg["front"]:
			continue
		var need := H + float((lg["pos"] as Vector3).y) - sole
		var k := need / _reach(lg)
		var segs: Array = lg["segs"]
		for i in 3:
			segs[i] = float(segs[i]) * k

static func _reach(lg: Dictionary) -> float:
	var cum := 0.0
	var h := 0.0
	for i in 3:
		cum += float(lg["rest"][i])
		h += float(lg["segs"][i]) * cos(cum)
	return h

## Пара ног: меши звеньев по профилям, стопа (лапа) — общий меш.
static func _legs(d: Dictionary, front: bool, pos: Vector3, segs: Array, rest: Array, profs: Array, pcs: Array, foot: Mesh) -> void:
	if not d.has("legs"):
		d["legs"] = []
	for sd in [-1.0, 1.0]:
		d["legs"].append({"pos": Vector3(pos.x * sd, pos.y, pos.z), "segs": segs.duplicate(), "rest": rest, "profs": profs, "pcs": pcs, "foot": foot, "front": front})

static func _leg_meshes(d: Dictionary) -> void:
	_fit_legs(d)
	var cache := {}
	for lg: Dictionary in d["legs"]:
		var key := "f" if lg["front"] else "h"
		if not cache.has(key):
			var ms := []
			for i in 3:
				ms.append(_leg_seg(float(lg["segs"][i]), lg["profs"][i], lg["pcs"][i]))
			cache[key] = ms
		lg["meshes"] = cache[key]

static func _eye(r: float) -> ArrayMesh:
	return _ell(r * 1.6, r, r * 0.9, {"back": Color(0.04, 0.03, 0.03)}, 6)

# ----- лось: высокий, горбатая холка, длинная горбоносая морда, «серьга», лопатообразные рога -----
static func _def_moose(male: bool, winter: bool) -> Dictionary:
	var d := {"mat": _tg_mat(0.0), "L": 2.7}
	var back := Color(0.44, 0.33, 0.23) if not winter else Color(0.48, 0.4, 0.32)
	var dark := Color(0.3, 0.22, 0.16)
	var legc := Color(0.7, 0.64, 0.56)
	var pc := {"back": back, "belly": dark}
	d["torso"] = tube([
		[-0.95, 0.06, 0.08, 0.06], [-0.9, 0.2, 0.26, 0.06], [-0.78, 0.29, 0.36, 0.04], [-0.55, 0.32, 0.4, 0.02, 1.05],
		[-0.25, 0.35, 0.42, 0.0, 1.1], [0.05, 0.37, 0.44, 0.0, 1.12], [0.32, 0.36, 0.47, 0.03, 1.08], [0.55, 0.31, 0.5, 0.08, 1.0],
		[0.72, 0.25, 0.46, 0.14, 0.95], [0.85, 0.17, 0.34, 0.18, 0.9], [0.93, 0.07, 0.14, 0.2]], pc, 16)
	d["neck_pos"] = Vector3(0, 0.2, 0.72)
	d["neck_pitch"] = -0.5
	d["neck_len"] = 0.58
	d["neck"] = tube([[0.0, 0.18, 0.3, 0.02], [0.2, 0.16, 0.25, 0.04], [0.42, 0.13, 0.18, 0.02], [0.62, 0.11, 0.14, 0.0]], {"back": dark, "belly": back}, 12)
	d["head_pitch"] = 1.05
	var hpc := {"back": Color(0.5, 0.38, 0.26), "belly": Color(0.4, 0.3, 0.21), "tip": Color(0.2, 0.15, 0.12), "tip_t": 0.86}
	var hm := tube([[-0.1, 0.08, 0.1, 0.0], [0.0, 0.11, 0.13, 0.0], [0.12, 0.12, 0.14, -0.01], [0.28, 0.1, 0.12, -0.03], [0.42, 0.085, 0.11, -0.05],
		[0.55, 0.095, 0.12, -0.07], [0.64, 0.1, 0.115, -0.08], [0.71, 0.08, 0.085, -0.09], [0.745, 0.03, 0.035, -0.1]], hpc, 12)
	var parts := [[hm, Transform3D()]]
	var ear := tube([[0.0, 0.035, 0.02, 0.0], [0.1, 0.055, 0.02, 0.0], [0.2, 0.035, 0.015, 0.0], [0.26, 0.004, 0.004, 0.0]], {"back": back, "belly": Color(0.45, 0.4, 0.34)}, 8)
	var bell := tube([[0.0, 0.03, 0.05, 0.0], [0.12, 0.035, 0.06, 0.0], [0.24 if male else 0.14, 0.02, 0.035, 0.0], [0.3 if male else 0.17, 0.005, 0.008, 0.0]], {"back": dark}, 8)
	parts.append([bell, _tf(_aim(Vector3(0, -1, -0.5)), Vector3(0, -0.11, 0.12))])
	for sd in [-1.0, 1.0]:
		parts.append([ear, _tf(_aim(Vector3(sd * 0.8, 0.45, -0.5)), Vector3(sd * 0.08, 0.09, -0.02))])
		parts.append([_eye(0.018), _tf(_aim(Vector3(sd * 0.3, 0, 1)), Vector3(sd * 0.095, 0.04, 0.16))])
		parts.append([_ell(0.04, 0.02, 0.012, {"back": Color(0.05, 0.04, 0.035)}), _tf(_aim(Vector3(sd * 0.4, -0.2, 1)), Vector3(sd * 0.05, -0.08, 0.7))])
	if male:
		var apc := {"back": Color(0.62, 0.54, 0.42), "belly": Color(0.5, 0.43, 0.33), "tip": Color(0.78, 0.72, 0.62), "tip_t": 0.9}
		var palm := tube([[0.0, 0.035, 0.035, 0.0], [0.2, 0.04, 0.03, 0.0], [0.28, 0.1, 0.025, 0.0], [0.42, 0.19, 0.022, 0.02], [0.56, 0.22, 0.02, 0.04], [0.66, 0.17, 0.018, 0.05], [0.7, 0.05, 0.012, 0.05]], apc, 10)
		var tine := tube([[0.0, 0.022, 0.014, 0.0], [0.08, 0.012, 0.01, 0.0], [0.14, 0.003, 0.003, 0.0]], apc, 6)
		for sd in [-1.0, 1.0]:
			# +Z рога — вбок; ширина лопаты — почти вертикально (верхний край лопаты — x = -sd);
			# лопата смотрит вперёд, отростки — по верхнему и наружному краю
			var up := -float(sd)
			var ap := [[palm, Transform3D()]]
			for ti in 6:
				var zt := 0.36 + ti * 0.065
				var w := 0.2 - absf(zt - 0.55) * 0.5
				ap.append([tine, _tf(_aim(Vector3(up, 0.0, 0.25 + ti * 0.15)), Vector3(up * w, 0.0, zt))])
			ap.append([tine, _tf(_aim(Vector3(-up * 0.5, 0.6, 0.6)), Vector3(-up * 0.06, 0.0, 0.3))])
			var z := Vector3(sd * 1.0, 0.45, -0.3).normalized()
			var fwd := Vector3(0, 0.7, -0.7)
			var x := (fwd - z * fwd.dot(z)).normalized() * -float(sd)
			var y := z.cross(x)
			parts.append([_merge(ap), _tf(Basis(x, y, z), Vector3(sd * 0.07, 0.12, 0.02))])
	d["head"] = _merge(parts)
	d["tail_pos"] = Vector3(0, 0.22, -0.9)
	d["tail_pitch"] = 2.6
	d["tail"] = tube([[0.0, 0.04, 0.03, 0.0], [0.08, 0.035, 0.025, 0.0], [0.12, 0.005, 0.005, 0.0]], {"back": back}, 6)
	var lp := {"back": legc}
	var hoof := {"back": legc, "tip": Color(0.1, 0.09, 0.08), "tip_t": 0.86}
	var up := {"back": back, "belly": back, "tip": legc, "tip_t": 0.85}
	_legs(d, true, Vector3(0.19, -0.1, 0.55), [0.48, 0.52, 0.47], [0.35, -0.35, 0.0],
		[[[0.0, 0.13, 0.17], [0.6, 0.1, 0.12], [1.0, 0.065, 0.075]], [[0.0, 0.065, 0.075], [0.15, 0.065, 0.07], [0.85, 0.045, 0.045], [1.0, 0.05, 0.05]], [[0.0, 0.05, 0.05], [0.12, 0.042, 0.045], [0.78, 0.038, 0.04], [0.86, 0.048, 0.05, 0.01], [0.97, 0.06, 0.075, 0.02], [1.0, 0.03, 0.04, 0.02]]],
		[up, lp, hoof], null)
	_legs(d, false, Vector3(0.18, -0.02, -0.62), [0.5, 0.55, 0.5], [-0.5, 1.05, -0.5],
		[[[0.0, 0.17, 0.26, 0.02], [0.5, 0.13, 0.18], [1.0, 0.07, 0.08]], [[0.0, 0.07, 0.08], [0.2, 0.06, 0.08, -0.02], [0.85, 0.042, 0.05], [1.0, 0.05, 0.06, -0.02]], [[0.0, 0.05, 0.06], [0.12, 0.042, 0.045], [0.8, 0.038, 0.04], [0.88, 0.048, 0.05, 0.01], [0.97, 0.06, 0.075, 0.02], [1.0, 0.03, 0.04, 0.02]]],
		[up, lp, hoof], null)
	_leg_meshes(d)
	d["lie_y"] = 0.42
	return d

## Лапа кошки или куньего: подушка, вытянутая вперёд.
static func _paw(ln: float, w: float, h: float, col: Color) -> ArrayMesh:
	var m := _ell(ln, w, h, {"back": col}, 8)
	return _merge([[m, Transform3D(Basis(), Vector3(0, -h * 0.4, -ln * 0.3))]])

# ----- рысь: высокие ноги, широкие лапы, короткий хвост с чёрным концом, кисточки, баки -----
static func _def_lynx(winter: bool) -> Dictionary:
	var d := {"mat": _tg_mat(1.0), "L": 1.0, "sole": 0.035}
	var back := Color(0.66, 0.57, 0.46) if not winter else Color(0.72, 0.66, 0.58)
	var belly := Color(0.9, 0.86, 0.78)
	var pc := {"back": back, "belly": belly, "pat": 1.0}
	d["torso"] = tube([
		[-0.45, 0.04, 0.05, 0.04], [-0.42, 0.1, 0.12, 0.03], [-0.34, 0.135, 0.155, 0.02], [-0.18, 0.125, 0.145, 0.0, 1.0],
		[0.0, 0.12, 0.15, -0.01, 1.05], [0.15, 0.13, 0.17, 0.0, 1.1], [0.3, 0.13, 0.17, 0.02, 1.05], [0.4, 0.11, 0.15, 0.04],
		[0.47, 0.07, 0.1, 0.06], [0.5, 0.03, 0.04, 0.07]], pc, 14)
	d["neck_pos"] = Vector3(0, 0.06, 0.4)
	d["neck_pitch"] = -0.55
	d["neck_len"] = 0.17
	d["neck"] = tube([[0.0, 0.09, 0.115, 0.0], [0.1, 0.085, 0.1, 0.0], [0.19, 0.075, 0.085, 0.0]], {"back": back, "belly": belly, "pat": 1.0}, 10)
	d["head_pitch"] = 0.55
	var hm := tube([[-0.05, 0.055, 0.06, 0.0], [0.0, 0.075, 0.075, 0.0], [0.06, 0.08, 0.072, 0.0], [0.11, 0.062, 0.055, -0.012], [0.15, 0.04, 0.038, -0.025], [0.172, 0.02, 0.02, -0.03]],
		{"back": back, "belly": belly, "pat": 0.5}, 12)
	var parts := [[hm, Transform3D()]]
	var ear := tube([[0.0, 0.03, 0.012, 0.0], [0.05, 0.024, 0.01, 0.0], [0.075, 0.006, 0.005, 0.0]], {"back": Color(0.3, 0.25, 0.2), "belly": back}, 6)
	var tuft := tube([[0.0, 0.005, 0.005, 0.0], [0.05, 0.002, 0.002, 0.0]], {"back": Color(0.05, 0.04, 0.04)}, 4)
	var ruff := tube([[0.0, 0.03, 0.02, 0.0], [0.05, 0.05, 0.025, 0.0], [0.1, 0.03, 0.015, 0.0], [0.12, 0.005, 0.005, 0.0]], {"back": Color(0.82, 0.78, 0.7), "belly": Color(0.3, 0.26, 0.22)}, 8)
	for sd in [-1.0, 1.0]:
		var eb := _aim(Vector3(sd * 0.25, 1.0, -0.15))
		parts.append([ear, _tf(eb, Vector3(sd * 0.045, 0.05, -0.01))])
		parts.append([tuft, _tf(eb, Vector3(sd * 0.045, 0.05, -0.01) + eb.z * 0.072)])
		parts.append([ruff, _tf(_aim(Vector3(sd * 0.7, -0.7, -0.35)), Vector3(sd * 0.05, -0.02, 0.04))])
		parts.append([_eye(0.012), _tf(_aim(Vector3(sd * 0.3, 0, 1)), Vector3(sd * 0.04, 0.025, 0.075))])
	parts.append([_ell(0.025, 0.015, 0.01, {"back": Color(0.25, 0.15, 0.13)}), _tf(_aim(Vector3(0, -0.3, 1)), Vector3(0, -0.015, 0.165))])
	d["head"] = _merge(parts)
	d["tail_pos"] = Vector3(0, 0.07, -0.43)
	d["tail_pitch"] = 2.6
	d["tail"] = tube([[0.0, 0.028, 0.03, 0.0], [0.06, 0.034, 0.034, 0.0], [0.13, 0.03, 0.03, 0.0], [0.16, 0.008, 0.008, 0.0]], {"back": back, "belly": belly, "tip": Color(0.06, 0.05, 0.05), "tip_t": 0.6}, 8)
	var lp := {"back": back, "belly": back, "pat": 1.0}
	var paw := _paw(0.1, 0.042, 0.03, back.lerp(belly, 0.3))
	_legs(d, true, Vector3(0.075, -0.03, 0.3), [0.17, 0.19, 0.12], [0.45, -0.55, 0.1],
		[[[0.0, 0.07, 0.09], [0.6, 0.058, 0.07], [1.0, 0.045, 0.05]], [[0.0, 0.045, 0.05], [0.5, 0.04, 0.043], [1.0, 0.033, 0.034]], [[0.0, 0.033, 0.034], [1.0, 0.032, 0.032]]],
		[lp, lp, lp], paw)
	_legs(d, false, Vector3(0.075, 0.0, -0.33), [0.2, 0.21, 0.16], [-0.6, 1.25, -0.55],
		[[[0.0, 0.075, 0.12, 0.01], [0.5, 0.065, 0.09], [1.0, 0.045, 0.05]], [[0.0, 0.045, 0.055], [0.4, 0.038, 0.045], [1.0, 0.03, 0.032]], [[0.0, 0.03, 0.032], [1.0, 0.03, 0.03]]],
		[lp, lp, lp], paw)
	_leg_meshes(d)
	d["lie_y"] = 0.14
	return d

# ----- росомаха: приземистая, выгнутая спина, светлая полоса по бокам, пушистый хвост -----
static func _def_wolverine() -> Dictionary:
	var d := {"mat": _tg_mat(0.0), "L": 0.95, "sole": 0.03}
	var back := Color(0.36, 0.25, 0.17)
	var dark := Color(0.3, 0.21, 0.15)
	var band := Color(0.78, 0.62, 0.42)
	var pc := {"back": back, "belly": dark, "band": band, "band_lo": -0.05, "band_hi": 0.55, "band_t0": 0.12, "band_t1": 0.78}
	d["torso"] = tube([
		[-0.4, 0.04, 0.05, 0.05], [-0.37, 0.1, 0.11, 0.05], [-0.3, 0.14, 0.15, 0.05], [-0.15, 0.15, 0.16, 0.04],
		[0.0, 0.15, 0.15, 0.02], [0.15, 0.15, 0.15, 0.0, 1.05], [0.27, 0.14, 0.15, -0.005], [0.36, 0.11, 0.12, 0.0],
		[0.42, 0.06, 0.07, 0.01], [0.44, 0.02, 0.03, 0.01]], pc, 14)
	d["neck_pos"] = Vector3(0, 0.02, 0.36)
	d["neck_pitch"] = -0.2
	d["neck_len"] = 0.1
	d["neck"] = tube([[0.0, 0.1, 0.105, 0.0], [0.12, 0.08, 0.08, 0.0]], {"back": back, "belly": dark}, 10)
	d["head_pitch"] = 0.3
	var hm := tube([[-0.04, 0.06, 0.06, 0.0], [0.02, 0.075, 0.07, 0.0], [0.08, 0.07, 0.06, -0.005], [0.13, 0.045, 0.04, -0.015], [0.16, 0.025, 0.025, -0.02], [0.172, 0.01, 0.012, -0.02]],
		{"back": Color(0.34, 0.25, 0.18), "belly": dark, "band": Color(0.66, 0.56, 0.44), "band_lo": 0.55, "band_hi": 1.1, "band_t0": 0.15, "band_t1": 0.5}, 12)
	var parts := [[hm, Transform3D()]]
	var ear := tube([[0.0, 0.022, 0.01, 0.0], [0.022, 0.02, 0.009, 0.0], [0.034, 0.004, 0.004, 0.0]], {"back": Color(0.4, 0.32, 0.24)}, 6)
	for sd in [-1.0, 1.0]:
		parts.append([ear, _tf(_aim(Vector3(sd * 0.7, 0.7, -0.3)), Vector3(sd * 0.05, 0.04, 0.0))])
		parts.append([_eye(0.01), _tf(_aim(Vector3(sd * 0.3, 0, 1)), Vector3(sd * 0.04, 0.025, 0.075))])
	parts.append([_ell(0.025, 0.017, 0.012, {"back": Color(0.04, 0.03, 0.03)}), _tf(_aim(Vector3(0, -0.2, 1)), Vector3(0, -0.012, 0.16))])
	d["head"] = _merge(parts)
	d["tail_pos"] = Vector3(0, 0.08, -0.37)
	d["tail_pitch"] = 2.75
	d["tail"] = tube([[0.0, 0.04, 0.04, 0.0], [0.07, 0.055, 0.055, 0.0], [0.17, 0.05, 0.05, 0.0], [0.23, 0.015, 0.015, 0.0]], {"back": dark}, 8)
	var lp := {"back": dark}
	var paw := _paw(0.1, 0.045, 0.032, Color(0.18, 0.13, 0.1))
	_legs(d, true, Vector3(0.09, -0.04, 0.27), [0.1, 0.11, 0.06], [0.4, -0.45, 0.05],
		[[[0.0, 0.07, 0.09], [0.6, 0.055, 0.065], [1.0, 0.04, 0.045]], [[0.0, 0.04, 0.045], [1.0, 0.033, 0.035]], [[0.0, 0.033, 0.035], [1.0, 0.03, 0.03]]],
		[lp, lp, lp], paw)
	_legs(d, false, Vector3(0.09, 0.0, -0.27), [0.13, 0.12, 0.07], [-0.6, 1.2, -0.5],
		[[[0.0, 0.08, 0.11], [0.5, 0.065, 0.08], [1.0, 0.04, 0.045]], [[0.0, 0.04, 0.045], [1.0, 0.032, 0.035]], [[0.0, 0.032, 0.035], [1.0, 0.03, 0.03]]],
		[lp, lp, lp], paw)
	_leg_meshes(d)
	d["lie_y"] = 0.13
	return d

# ----- кабарга: маленький безрогий олень, круп выше холки, большие уши, у самца клыки -----
static func _def_muskdeer(male: bool) -> Dictionary:
	var d := {"mat": _tg_mat(1.0), "L": 0.85, "tilt": 0.12}
	var back := Color(0.48, 0.37, 0.27)
	var belly := Color(0.7, 0.6, 0.46)
	var pc := {"back": back, "belly": belly, "pat": 0.6}
	d["torso"] = tube([
		[-0.38, 0.04, 0.05, 0.06], [-0.35, 0.1, 0.12, 0.05], [-0.27, 0.13, 0.15, 0.04], [-0.12, 0.13, 0.15, 0.02, 1.05],
		[0.03, 0.12, 0.14, 0.0, 1.05], [0.17, 0.11, 0.14, 0.0], [0.28, 0.09, 0.12, 0.01], [0.35, 0.06, 0.08, 0.02], [0.38, 0.03, 0.03, 0.03]], pc, 14)
	d["neck_pos"] = Vector3(0, 0.0, 0.3)
	d["neck_pitch"] = -0.75
	d["neck_len"] = 0.2
	d["neck"] = tube([[0.0, 0.06, 0.075, 0.0], [0.1, 0.05, 0.06, 0.0], [0.22, 0.04, 0.045, 0.0]],
		{"back": back, "belly": belly, "band": Color(0.85, 0.8, 0.7), "band_lo": -1.3, "band_hi": -0.75}, 10)
	d["head_pitch"] = 1.05
	var hm := tube([[-0.03, 0.04, 0.045, 0.0], [0.02, 0.05, 0.05, 0.0], [0.07, 0.045, 0.045, -0.005], [0.12, 0.03, 0.032, -0.015], [0.155, 0.02, 0.022, -0.02], [0.167, 0.008, 0.008, -0.02]],
		{"back": Color(0.44, 0.34, 0.25), "belly": Color(0.6, 0.5, 0.38), "tip": Color(0.12, 0.09, 0.07), "tip_t": 0.88}, 10)
	var parts := [[hm, Transform3D()]]
	var ear := tube([[0.0, 0.03, 0.01, 0.0], [0.05, 0.036, 0.01, 0.0], [0.08, 0.022, 0.008, 0.0], [0.095, 0.004, 0.004, 0.0]], {"back": Color(0.3, 0.24, 0.18), "belly": Color(0.65, 0.58, 0.48)}, 6)
	for sd in [-1.0, 1.0]:
		parts.append([ear, _tf(_aim(Vector3(sd * 0.75, 0.6, -0.45)), Vector3(sd * 0.03, 0.035, -0.005))])
		parts.append([_eye(0.011), _tf(_aim(Vector3(sd * 0.3, 0, 1)), Vector3(sd * 0.036, 0.02, 0.055))])
		if male:
			var tusk := tube([[0.0, 0.006, 0.007, 0.0], [0.035, 0.005, 0.005, 0.004], [0.065, 0.002, 0.002, 0.012]], {"back": Color(0.9, 0.86, 0.75)}, 5)
			parts.append([tusk, _tf(_aim(Vector3(sd * 0.1, -1.0, -0.15)), Vector3(sd * 0.016, -0.03, 0.105))])
	d["head"] = _merge(parts)
	d["tail_pos"] = Vector3(0, 0.08, -0.37)
	d["tail_pitch"] = 2.4
	d["tail"] = tube([[0.0, 0.02, 0.015, 0.0], [0.04, 0.012, 0.01, 0.0], [0.05, 0.003, 0.003, 0.0]], {"back": back}, 5)
	var lp := {"back": Color(0.4, 0.3, 0.22)}
	var hoof := {"back": Color(0.4, 0.3, 0.22), "tip": Color(0.07, 0.06, 0.05), "tip_t": 0.86}
	var up := {"back": back, "belly": back, "pat": 0.6}
	_legs(d, true, Vector3(0.06, -0.05, 0.24), [0.12, 0.15, 0.14], [0.3, -0.35, 0.05],
		[[[0.0, 0.05, 0.065], [0.6, 0.035, 0.04], [1.0, 0.022, 0.025]], [[0.0, 0.022, 0.025], [1.0, 0.015, 0.016]], [[0.0, 0.016, 0.016], [0.75, 0.012, 0.013], [0.9, 0.016, 0.018, 0.004], [1.0, 0.012, 0.016, 0.006]]],
		[up, lp, hoof], null)
	_legs(d, false, Vector3(0.065, 0.04, -0.26), [0.18, 0.2, 0.18], [-0.55, 1.15, -0.5],
		[[[0.0, 0.065, 0.1, 0.01], [0.5, 0.05, 0.07], [1.0, 0.025, 0.028]], [[0.0, 0.025, 0.03], [1.0, 0.016, 0.018]], [[0.0, 0.016, 0.017], [0.75, 0.012, 0.013], [0.9, 0.016, 0.018, 0.004], [1.0, 0.012, 0.016, 0.006]]],
		[up, lp, hoof], null)
	_leg_meshes(d)
	d["lie_y"] = 0.12
	return d

# ----- глухарь: самец чёрно-сизый с зелёным зобом, красной бровью и веерным хвостом;
# самка (глухарка) рыжевато-бурая с рябью -----
static func _def_bird(male: bool) -> Dictionary:
	var d := {"mat": _tg_mat(0.0 if male else 2.0), "L": 0.5, "tilt": -0.25, "sole": 0.012, "bird": true}
	var back := Color(0.36, 0.36, 0.4) if male else Color(0.52, 0.42, 0.31)
	var belly := Color(0.2, 0.2, 0.21) if male else Color(0.74, 0.66, 0.54)
	var wingc := Color(0.5, 0.38, 0.25) if male else Color(0.52, 0.4, 0.28)
	var pat := 0.0 if male else 1.0
	var pc := {"back": back, "belly": belly, "pat": pat}
	if male:
		pc.merge({"band": Color(0.12, 0.32, 0.22), "band_lo": -0.4, "band_hi": 0.6, "band_t0": 0.62, "band_t1": 1.2})
	else:
		pc.merge({"band": Color(0.7, 0.5, 0.32), "band_lo": -0.6, "band_hi": 0.3, "band_t0": 0.62, "band_t1": 1.2})
	d["torso"] = tube([[-0.22, 0.03, 0.03, 0.02], [-0.19, 0.08, 0.07, 0.02], [-0.12, 0.115, 0.105, 0.0], [0.0, 0.13, 0.125, -0.01, 1.1],
		[0.1, 0.12, 0.125, 0.0, 1.1], [0.17, 0.09, 0.1, 0.01], [0.21, 0.05, 0.06, 0.02], [0.23, 0.02, 0.02, 0.02]], pc, 14)
	d["neck_pos"] = Vector3(0, 0.07, 0.15)
	d["neck_pitch"] = -1.0
	d["neck_len"] = 0.13
	var npc := {"back": Color(0.38, 0.38, 0.42) if male else back, "belly": Color(0.12, 0.3, 0.2) if male else Color(0.7, 0.5, 0.32), "pat": pat}
	d["neck"] = tube([[-0.02, 0.065, 0.07, 0.0], [0.07, 0.05, 0.055, 0.0], [0.14, 0.04, 0.045, 0.0]], npc, 10)
	d["head_pitch"] = 0.95
	var hpc := {"back": Color(0.34, 0.34, 0.38) if male else back, "belly": Color(0.2, 0.2, 0.22) if male else belly, "pat": pat}
	var hm := tube([[-0.035, 0.03, 0.03, 0.0], [0.0, 0.038, 0.04, 0.0], [0.04, 0.034, 0.036, 0.0], [0.065, 0.02, 0.022, -0.003], [0.075, 0.008, 0.01, -0.005]], hpc, 10)
	var parts := [[hm, Transform3D()]]
	var beak := tube([[0.0, 0.016, 0.02, 0.0], [0.025, 0.012, 0.014, -0.002], [0.042, 0.004, 0.005, -0.01]], {"back": Color(0.86, 0.82, 0.68) if male else Color(0.3, 0.27, 0.24)}, 6)
	parts.append([beak, _tf(Basis(), Vector3(0, -0.005, 0.06))])
	for sd in [-1.0, 1.0]:
		parts.append([_eye(0.007), _tf(_aim(Vector3(sd, 0, 0.3)), Vector3(sd * 0.03, 0.01, 0.03))])
		if male:
			var brow := tube([[0.0, 0.005, 0.01, 0.0], [0.02, 0.008, 0.012, 0.0], [0.035, 0.003, 0.005, 0.0]], {"back": Color(0.85, 0.08, 0.06)}, 5)
			parts.append([brow, _tf(_aim(Vector3(sd * 0.2, 0.1, 1.0)), Vector3(sd * 0.03, 0.02, 0.015))])
	if male:
		var beard := tube([[0.0, 0.02, 0.012, 0.0], [0.03, 0.022, 0.012, 0.0], [0.05, 0.004, 0.004, 0.0]], {"back": Color(0.08, 0.08, 0.08)}, 6)
		parts.append([beard, _tf(_aim(Vector3(0, -1, 0.3)), Vector3(0, -0.03, 0.02))])
	d["head"] = _merge(parts)
	d["tail_pos"] = Vector3(0, 0.05, -0.18)
	d["tail_pitch"] = -0.4
	d["tail"] = fan(0.32 if male else 0.2, Color(0.16, 0.16, 0.17) if male else Color(0.55, 0.4, 0.27), Color(0.26, 0.26, 0.28) if male else Color(0.62, 0.46, 0.3), pat)
	d["wing"] = tube([[0.0, 0.02, 0.05, 0.0], [0.06, 0.03, 0.085, -0.01], [0.2, 0.025, 0.08, -0.015], [0.34, 0.015, 0.055, -0.01], [0.4, 0.004, 0.01, 0.0]], {"back": wingc, "pat": pat}, 8)
	d["wing_x"] = 0.085
	d["wing_y"] = 0.06
	d["wing_z"] = 0.1
	var legc := Color(0.28, 0.25, 0.22) if male else Color(0.5, 0.4, 0.3)
	var toe := tube([[0.0, 0.007, 0.006, 0.0], [0.05, 0.005, 0.004, 0.0], [0.06, 0.002, 0.002, 0.0]], {"back": Color(0.2, 0.18, 0.15)}, 4)
	var fp := []
	for a in [-0.45, 0.0, 0.45]:
		fp.append([toe, _tf(_aim(Vector3(sin(a), -0.1, cos(a))), Vector3(0, -0.005, 0))])
	fp.append([toe, _tf(_aim(Vector3(0, -0.1, -1)), Vector3(0, -0.005, 0))])
	var foot := _merge(fp)
	var lp := {"back": legc}
	var thigh := {"back": back.lerp(belly, 0.5), "pat": pat}
	# у птицы две ноги: передней пары нет — список ног из двух
	d["legs"] = []
	for sd in [-1.0, 1.0]:
		d["legs"].append({"pos": Vector3(sd * 0.05, -0.05, 0.0), "segs": [0.1, 0.12, 0.02], "rest": [-0.5, 1.0, -0.5], "front": true,
			"profs": [[[0.0, 0.045, 0.05], [0.6, 0.035, 0.04], [1.0, 0.018, 0.018]], [[0.0, 0.014, 0.014], [1.0, 0.01, 0.01]], [[0.0, 0.01, 0.01], [1.0, 0.008, 0.008]]],
			"pcs": [thigh, lp, lp], "foot": foot})
	_leg_meshes(d)
	d["lie_y"] = 0.1
	return d
