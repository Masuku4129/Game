extends RefCounted
## Сборка моделей зверей кодом: гладкие лофты с цветами вершин (спина темнее, брюхо светлее),
## шерсть — шумовая текстура. Каждая модель — 10–12 частей (туловище, голова, 4 ноги по 2 звена, хвост).

const SPECIES := {
	"hare": {"taiga": true, "swalk": 1.4, "srun": 4.5, "len": 0.46, "h": 0.26, "gw": 0.1, "gh": 0.11, "neck": 0.07, "head": 0.075, "snout": 0.05, "ear": 0.12, "ear_w": 0.025, "tail": 0.05, "tail_r": 0.035, "leg": 0.022, "hind": 1.35,
		"col": Color(0.46, 0.37, 0.27), "belly": Color(0.78, 0.74, 0.66), "winter": Color(0.93, 0.93, 0.92), "gait": "bound", "walk": 1.2, "run": 9.0},
	"squirrel": {"taiga": true, "swalk": 1.4, "srun": 4.5, "len": 0.2, "h": 0.09, "gw": 0.045, "gh": 0.05, "neck": 0.03, "head": 0.035, "snout": 0.02, "ear": 0.035, "ear_w": 0.012, "tail": 0.2, "tail_r": 0.05, "leg": 0.01, "hind": 1.3,
		"col": Color(0.6, 0.3, 0.13), "belly": Color(0.85, 0.8, 0.7), "winter": Color(0.45, 0.42, 0.42), "gait": "bound", "walk": 1.0, "run": 4.5},
	"fox": {"len": 0.62, "h": 0.36, "gw": 0.1, "gh": 0.11, "neck": 0.12, "head": 0.08, "snout": 0.11, "ear": 0.08, "ear_w": 0.035, "tail": 0.42, "tail_r": 0.07, "leg": 0.025, "hind": 1.0,
		"col": Color(0.78, 0.38, 0.14), "belly": Color(0.9, 0.86, 0.8), "winter": Color(0.82, 0.42, 0.16), "gait": "trot", "walk": 1.4, "run": 11.0},
	"roe": {"len": 1.0, "h": 0.72, "gw": 0.16, "gh": 0.2, "neck": 0.32, "head": 0.1, "snout": 0.13, "ear": 0.13, "ear_w": 0.05, "tail": 0.04, "tail_r": 0.04, "leg": 0.03, "hind": 1.05,
		"col": Color(0.55, 0.37, 0.22), "belly": Color(0.82, 0.76, 0.68), "winter": Color(0.42, 0.37, 0.32), "gait": "walk", "walk": 1.3, "run": 13.0, "antler": 0.18},
	"deer": {"len": 1.7, "h": 1.25, "gw": 0.27, "gh": 0.34, "neck": 0.55, "head": 0.16, "snout": 0.22, "ear": 0.16, "ear_w": 0.06, "tail": 0.08, "tail_r": 0.05, "leg": 0.05, "hind": 1.05,
		"col": Color(0.47, 0.33, 0.22), "belly": Color(0.7, 0.62, 0.52), "winter": Color(0.4, 0.34, 0.28), "gait": "walk", "walk": 1.4, "run": 12.0, "antler": 0.75},
	"boar": {"taiga": true, "swalk": 1.3, "srun": 3.4, "len": 1.25, "h": 0.72, "gw": 0.3, "gh": 0.38, "neck": 0.12, "head": 0.17, "snout": 0.3, "ear": 0.1, "ear_w": 0.06, "tail": 0.2, "tail_r": 0.015, "leg": 0.05, "hind": 0.95,
		"col": Color(0.24, 0.2, 0.17), "belly": Color(0.3, 0.26, 0.22), "winter": Color(0.22, 0.19, 0.17), "gait": "trotgallop", "walk": 1.1, "run": 8.0, "tusk": true},
	"wolf": {"len": 1.05, "h": 0.78, "gw": 0.17, "gh": 0.22, "neck": 0.24, "head": 0.12, "snout": 0.15, "ear": 0.1, "ear_w": 0.045, "tail": 0.45, "tail_r": 0.06, "leg": 0.04, "hind": 1.0,
		"col": Color(0.46, 0.44, 0.41), "belly": Color(0.75, 0.72, 0.66), "winter": Color(0.55, 0.53, 0.5), "gait": "trot", "walk": 1.5, "run": 12.0},
	"bear": {"taiga": true, "swalk": 1.3, "srun": 3.4, "len": 1.75, "h": 1.0, "gw": 0.45, "gh": 0.5, "neck": 0.25, "head": 0.2, "snout": 0.2, "ear": 0.08, "ear_w": 0.07, "tail": 0.06, "tail_r": 0.05, "leg": 0.11, "hind": 0.95,
		"col": Color(0.3, 0.2, 0.13), "belly": Color(0.25, 0.17, 0.11), "winter": Color(0.3, 0.2, 0.13), "gait": "trotgallop", "walk": 1.1, "run": 10.0},
	"beaver": {"len": 0.7, "h": 0.16, "gw": 0.19, "gh": 0.17, "neck": 0.04, "head": 0.08, "snout": 0.05, "ear": 0.02, "ear_w": 0.015, "tail": 0.3, "tail_r": 0.07, "leg": 0.03, "hind": 1.0,
		"col": Color(0.42, 0.3, 0.2), "belly": Color(0.54, 0.43, 0.32), "winter": Color(0.42, 0.3, 0.2), "gait": "walk", "walk": 0.6, "run": 1.9, "flat_tail": true},
	"tiger": {"taiga": true, "swalk": 1.3, "srun": 4.4, "len": 1.9, "h": 0.92, "gw": 0.33, "gh": 0.4, "neck": 0.25, "head": 0.19, "snout": 0.14, "ear": 0.07, "ear_w": 0.06, "tail": 0.9, "tail_r": 0.06, "leg": 0.09, "hind": 1.0,
		"col": Color(0.86, 0.46, 0.16), "belly": Color(0.95, 0.92, 0.86), "winter": Color(0.86, 0.5, 0.2), "gait": "gallop", "walk": 1.3, "run": 13.0, "stripes": true},
	# модели на скелете: build_taiga(), походка — animal.gd _animate_rig();
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
	if kind == "beaver":
		return build_beaver(root, scale_k)
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

# ---------- Анатомические модели: одна сетка на скелете на каждого зверя ----------
# Тело — лофт анатомических сечений вдоль хребта от корня хвоста до носа (круп, впалый пах,
# глубокая грудь с килем, холка, шея, череп, морда); ноги — лофты мышечных профилей
# (лопатка/таз → плечо/бедро → предплечье/голень → пясть/плюсна → копыто/лапа), верх ноги
# входит в туловище и привязан к нему весами — шва нет. Уши, рога, кисточки, подгрудок —
# мелкие лофты той же сетки. Сетка и Skin строятся один раз на вид/пол/сезон (до ~3 тыс.
# треугольников, один материал = один вызов отрисовки), у особи — свой Skeleton3D.
# Кости в покое без поворота (только смещение), поэтому поворот кости по X — наклон звена
# в продольной плоскости: плюс — нижний конец уходит назад.

static var _an_cache := {}
static var _an_mats := {}

static func _an_mat(pattern: float, stripes: float = 0.0) -> ShaderMaterial:
	var key := "%s_%s" % [pattern, stripes]
	if _an_mats.has(key):
		return _an_mats[key]
	if _fur_sh == null:
		_fur_sh = load("res://shaders/paint/fur.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _fur_sh
	m.set_shader_parameter("spots", pattern)
	m.set_shader_parameter("stripes", stripes)
	_an_mats[key] = m
	return m

## Накопитель сетки со скелетом.
class SMB extends RefCounted:
	var names: Array = []
	var parents: Array = []
	var gpos: Array = []
	var v := PackedVector3Array()
	var cl := PackedColorArray()
	var uv := PackedVector2Array()
	var bo := PackedInt32Array()
	var we := PackedFloat32Array()
	var ix := PackedInt32Array()

	func bone(n: String, parent: String, p: Vector3) -> int:
		names.append(n)
		parents.append(names.find(parent) if parent != "" else -1)
		gpos.append(p)
		return names.size() - 1

	func b(n: String) -> int:
		return names.find(n)

	func vert(p: Vector3, col: Color, t: Vector2, w: Dictionary) -> int:
		v.append(p)
		cl.append(col)
		uv.append(t)
		var ks: Array = w.keys()
		ks.sort_custom(func(x, y): return float(w[x]) > float(w[y]))
		var sum := 0.0
		for i in mini(4, ks.size()):
			sum += float(w[ks[i]])
		for i in 4:
			if i < ks.size():
				bo.append(int(ks[i]))
				we.append(float(w[ks[i]]) / maxf(sum, 0.0001))
			else:
				bo.append(0)
				we.append(0.0)
		return v.size() - 1

	func tri(a: int, b2: int, c: int) -> void:
		ix.append(a)
		ix.append(b2)
		ix.append(c)

	## Сшивает кольца одинакового размера; cap0/cap1 — центральные вершины торцов (или -1).
	func stitch(rings: Array, cap0: int, cap1: int) -> void:
		for i in rings.size() - 1:
			var r0: Array = rings[i]
			var r1: Array = rings[i + 1]
			var n := r0.size()
			for j in n:
				var j1 := (j + 1) % n
				tri(r0[j], r1[j], r0[j1])
				tri(r0[j1], r1[j], r1[j1])
		var f: Array = rings[0]
		var l: Array = rings[rings.size() - 1]
		for j in f.size():
			var j1 := (j + 1) % f.size()
			if cap0 >= 0:
				tri(cap0, f[j], f[j1])
			if cap1 >= 0:
				tri(cap1, l[j1], l[j])

	func commit() -> ArrayMesh:
		var nr := PackedVector3Array()
		nr.resize(v.size())
		for t in range(0, ix.size(), 3):
			var a := v[ix[t]]
			var n := (v[ix[t + 2]] - a).cross(v[ix[t + 1]] - a)
			nr[ix[t]] += n
			nr[ix[t + 1]] += n
			nr[ix[t + 2]] += n
		for i in nr.size():
			nr[i] = nr[i].normalized() if nr[i].length() > 0.0000001 else Vector3.UP
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = nr
		arr[Mesh.ARRAY_COLOR] = cl
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_BONES] = bo
		arr[Mesh.ARRAY_WEIGHTS] = we
		arr[Mesh.ARRAY_INDEX] = ix
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m

## Цвет вершины: спина/брюхо по высоте сечения (sa: 1 — верх, −1 — низ), полоса, кончик.
static func _pcol(pc: Dictionary, sa: float, t: float) -> Color:
	var back: Color = pc.get("back", Color(0.5, 0.5, 0.5))
	var belly: Color = pc.get("belly", back)
	var c := belly.lerp(back, smoothstep(-0.55, 0.35, sa))
	if pc.has("band"):
		var lo: float = pc["band_lo"]
		var hi: float = pc["band_hi"]
		var bm := smoothstep(lo - 0.15, lo, sa) * (1.0 - smoothstep(hi, hi + 0.15, sa))
		var t0: float = pc.get("band_t0", -1.0)
		var t1: float = pc.get("band_t1", 2.0)
		bm *= smoothstep(t0 - 0.1, t0, t) * (1.0 - smoothstep(t1, t1 + 0.1, t))
		c = c.lerp(pc["band"], bm)
	if pc.has("tip"):
		var tt: float = pc["tip_t"]
		c = c.lerp(pc["tip"], smoothstep(tt, tt + 0.06, t))
	c.a = float(pc.get("pat", 0.0)) * smoothstep(-0.95, -0.3, sa)
	return c

static func _wmix(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	var w := {}
	for key in a:
		w[key] = float(a[key]) * (1.0 - k)
	for key in b:
		w[key] = float(w.get(key, 0.0)) + float(b[key]) * k
	return w

## Тело: сечения [z, y, верх, низ, ширина спины, ширина в середине, ширина низа, кость, палитра, челюсть].
## Центр сечения — на линии (z, y); сечение перпендикулярно линии, «верх» — к спине.
static func _loft_body(mb: SMB, st: Array, pal: Dictionary) -> void:
	# Более округлый контур туловища: плотнее кольца, плавнее переходы окраски.
	var seg := 24
	var n := st.size()
	var bw := []
	for i in n:
		var w := {}
		for k in [-1, 0, 1]:
			var ii := clampi(i + k, 0, n - 1)
			var r2: Array = st[ii]
			var bid := mb.b(r2[7])
			w[bid] = float(w.get(bid, 0.0)) + (0.5 if k == 0 else 0.25)
		bw.append(w)
	var jaw := mb.b("jaw")
	var rings := []
	var arc := 0.0
	var prev := Vector3.ZERO
	var dd0 := Vector3.ZERO
	var dd1 := Vector3.ZERO
	for i in n:
		var r: Array = st[i]
		var p := Vector3(0, r[1], r[0])
		var ra: Array = st[maxi(i - 1, 0)]
		var rb: Array = st[mini(i + 1, n - 1)]
		var dd := (Vector3(0, rb[1], rb[0]) - Vector3(0, ra[1], ra[0])).normalized()
		if i == 0:
			dd0 = dd
		dd1 = dd
		var u := Vector3(0, dd.z, -dd.y)
		var s := u.cross(dd)
		if i > 0:
			arc += p.distance_to(prev)
		prev = p
		var pc: Dictionary = pal[r[8] if r.size() > 8 else "body"]
		var has_jaw: bool = r.size() > 9 and r[9]
		var t := float(i) / float(n - 1)
		var ring := []
		for j in seg:
			var a := TAU * j / seg - PI * 0.5
			var ca := cos(a)
			var sa := sin(a)
			var x := 0.0
			var y := 0.0
			if sa >= 0.0:
				y = float(r[2]) * sa
				x = ca * lerpf(r[5], r[4], sa * sa)
			else:
				y = float(r[3]) * sa
				x = ca * lerpf(r[5], r[6], sa * sa)
			var w: Dictionary = bw[i]
			if has_jaw and jaw >= 0:
				w = _wmix(w, {jaw: 1.0}, smoothstep(-0.15, -0.45, sa))
			ring.append(mb.vert(p + s * x + u * y, _pcol(pc, sa, t), Vector2(float(j) / seg, arc * 3.0), w))
		rings.append(ring)
	var f: Array = st[0]
	var l: Array = st[n - 1]
	var c0 := mb.vert(Vector3(0, f[1], f[0]) - dd0 * float(f[2]) * 0.4, _pcol(pal[f[8] if f.size() > 8 else "body"], 0.0, 0.0), Vector2(0.5, -0.1), bw[0])
	var c1 := mb.vert(Vector3(0, l[1], l[0]) + dd1 * float(l[2]) * 0.4, _pcol(pal[l[8] if l.size() > 8 else "body"], 0.0, 1.0), Vector2(0.5, arc * 3.0 + 0.1), bw[n - 1])
	mb.stitch(rings, c0, c1)

## Цепь (нога, хвост): точки суставов pts, профиль [звено, доля, полуширина, полутолщина, сдвиг вперёд, палитра];
## bones[k] — кость звена k; parent_b — кость, в которую уходит верх цепи.
static func _loft_chain(mb: SMB, pts: Array, prof: Array, bones: Array, parent_b: int, pal: Dictionary, seg: int, embed: float) -> void:
	# Увеличиваем поперечную детализацию ног, хвостов и других звеньев модели.
	seg = clampi(seg + 2, 10, 14)
	var n := prof.size()
	var cs := []
	for e: Array in prof:
		var k: int = e[0]
		cs.append((pts[k] as Vector3).lerp(pts[k + 1], e[1]))
	var rings := []
	var arc := 0.0
	var d_first := Vector3.ZERO
	var d_last := Vector3.ZERO
	var ends := []
	for i in n:
		var e: Array = prof[i]
		var k: int = e[0]
		var t: float = e[1]
		var dd: Vector3 = (cs[mini(i + 1, n - 1)] as Vector3) - (cs[maxi(i - 1, 0)] as Vector3)
		dd = Vector3(0, dd.y, dd.z).normalized() if Vector2(dd.y, dd.z).length() > 0.0001 else Vector3.DOWN
		var u := Vector3(0, dd.z, -dd.y)
		var s := u.cross(dd)
		var c: Vector3 = (cs[i] as Vector3) + u * float(e[4])
		if i == 0:
			d_first = dd
		d_last = dd
		if i > 0:
			arc += c.distance_to(cs[i - 1])
		var w := {}
		var own: int = bones[k]
		var prv: int = parent_b if k == 0 else int(bones[k - 1])
		var nxt: int = int(bones[k + 1]) if k + 1 < bones.size() else -1
		var wp := 0.5 * (1.0 - smoothstep(0.0, 0.3, t))
		if k == 0:
			wp = lerpf(embed, embed * 0.3, t)
		var wn := 0.5 * smoothstep(0.7, 1.0, t) if nxt >= 0 else 0.0
		w[own] = 1.0 - wp - wn
		w[prv] = float(w.get(prv, 0.0)) + wp
		if wn > 0.0:
			w[nxt] = float(w.get(nxt, 0.0)) + wn
		var pc: Dictionary = pal[e[5] if e.size() > 5 else "leg"]
		if pc.has("band"):
			pc = pc.duplicate()
			pc.erase("band")
		var ring := []
		for j in seg:
			var a := TAU * j / seg - PI * 0.5
			var ca := cos(a)
			var sa := sin(a)
			ring.append(mb.vert(c + s * ca * float(e[2]) + u * sa * float(e[3]), _pcol(pc, 0.35 + 0.25 * sa, float(i) / float(n - 1)), Vector2(float(j) / seg, arc * 3.0), w))
		rings.append(ring)
		ends.append([c, w, pc, e])
	var e0: Array = ends[0]
	var e1: Array = ends[n - 1]
	var c0 := mb.vert((e0[0] as Vector3) - d_first * float(e0[3][3]) * 0.5, _pcol(e0[2], 0.0, 0.0), Vector2(0.5, -0.05), e0[1])
	var c1 := mb.vert((e1[0] as Vector3) + d_last * float(e1[3][3]) * 0.6, _pcol(e1[2], 0.0, 1.0), Vector2(0.5, arc * 3.0 + 0.05), e1[1])
	mb.stitch(rings, c0, c1)

## Мелкая деталь вдоль оси dir от точки o: кольца [z, rx, ry, сдвиг y]; вся — на кость bone.
static func _piece(mb: SMB, o: Vector3, bs: Basis, rings: Array, pc: Dictionary, w: Dictionary, seg: int = 8) -> void:
	var rs := []
	var n := rings.size()
	for i in n:
		var r: Array = rings[i]
		var c := o + bs.z * float(r[0]) + bs.y * float(r[3])
		var ring := []
		for j in seg:
			var a := TAU * j / seg - PI * 0.5
			ring.append(mb.vert(c + bs.x * cos(a) * float(r[1]) + bs.y * sin(a) * float(r[2]), _pcol(pc, sin(a), float(i) / float(n - 1)), Vector2(float(j) / seg, float(r[0]) * 3.0), w))
		rs.append(ring)
	var f: Array = rings[0]
	var l: Array = rings[n - 1]
	var c0 := mb.vert(o + bs.z * (float(f[0]) - 0.003), _pcol(pc, 0.0, 0.0), Vector2.ZERO, w)
	var c1 := mb.vert(o + bs.z * (float(l[0]) + 0.003) + bs.y * float(l[3]), _pcol(pc, 0.0, 1.0), Vector2.ZERO, w)
	mb.stitch(rs, c0, c1)

## Базис, у которого +Z смотрит по dir.
static func _aim(dir: Vector3, side: Vector3 = Vector3.UP) -> Basis:
	var z := dir.normalized()
	var up := side if absf(z.dot(side.normalized())) < 0.95 else Vector3.FORWARD
	var x := up.cross(z).normalized()
	var y := z.cross(x)
	return Basis(x, y, z)

static func _mirror(p: Vector3, sd: float) -> Vector3:
	return Vector3(p.x * sd, p.y, p.z)

## Сечение тела на высоте z: (центр y, верх, ширина в середине).
static func _body_at(st: Array, z: float) -> Vector3:
	for i in st.size() - 1:
		var a: Array = st[i]
		var b: Array = st[i + 1]
		if z >= float(a[0]) and z <= float(b[0]):
			var k := (z - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.0001)
			return Vector3(lerpf(a[1], b[1], k), lerpf(a[2], b[2], k), lerpf(a[5], b[5], k))
	var e: Array = st[0] if z < float(st[0][0]) else st[st.size() - 1]
	return Vector3(e[1], e[2], e[5])

## Сборка по описанию вида: кости, тело, ноги, хвост, детали → сетка, Skin, данные для походки.
static func _anat(sp: Dictionary) -> Dictionary:
	var mb := SMB.new()
	var bp: Dictionary = sp["bones"]
	mb.bone("root", "", bp["root"])
	mb.bone("pelvis", "root", bp["pelvis"])
	mb.bone("chest", "root", bp["chest"])
	mb.bone("neck1", "chest", bp["neck1"])
	mb.bone("neck2", "neck1", bp["neck2"])
	mb.bone("head", "neck2", bp["head"])
	mb.bone("jaw", "head", bp["jaw"])
	var tp: Array = sp["tail"]["pts"]
	var tb := []
	for i in tp.size() - 1:
		tb.append(mb.bone("tail%d" % i, "pelvis" if i == 0 else "tail%d" % (i - 1), tp[i]))
	var pal: Dictionary = sp["pal"]
	var legs := []
	var lspec: Dictionary = sp["legs"]
	# порядок: ЛП, ПП, ЛЗ, ПЗ
	for key in ["f", "h"]:
		if not lspec.has(key):
			continue
		var L: Dictionary = lspec[key]
		for sd in [-1.0, 1.0]:
			var nm := "%s%s" % [key, "l" if sd < 0.0 else "r"]
			var pts := []
			for p: Vector3 in L["pts"]:
				pts.append(_mirror(p, sd))
			# верх лопатки/таза — внутри туловища: не выше середины спины и не шире бока
			if not sp.has("bird"):
				var bt := _body_at(sp["body"], (pts[0] as Vector3).z)
				var p0: Vector3 = pts[0]
				p0.y = minf(p0.y, bt.x + bt.y * 0.35)
				p0.x = signf(p0.x) * minf(absf(p0.x), bt.z * 0.45)
				pts[0] = p0
			var bs := []
			var par: String = L.get("parent", "chest" if key == "f" else "pelvis")
			for k in pts.size() - 1:
				bs.append(mb.bone("%s%d" % [nm, k], par if k == 0 else "%s%d" % [nm, k - 1], pts[k]))
			_loft_chain(mb, pts, L["prof"], bs, mb.b(par), pal, L.get("seg", 10), L.get("embed", 0.85))
			var phi := []
			for k in pts.size() - 1:
				var a: Vector3 = pts[k]
				var c: Vector3 = pts[k + 1]
				phi.append(atan2(-(c.z - a.z), a.y - c.y))
			var rel := [phi[1], float(phi[2]) - float(phi[1]), float(phi[3]) - float(phi[2])] if phi.size() >= 4 else [phi[1], float(phi[2]) - float(phi[1]), 0.0]
			legs.append({"b": bs, "rel": rel, "front": key == "f"})
	# прочие цепи (крылья): {"name", "pts", "prof", "parent"} — зеркально с двух сторон
	var chains := {}
	for ch: Dictionary in sp.get("chains", []):
		var lst := []
		for sd in [-1.0, 1.0]:
			var nm := "%s%s" % [ch["name"], "l" if sd < 0.0 else "r"]
			var pts := []
			for p: Vector3 in ch["pts"]:
				pts.append(_mirror(p, sd))
			var bs := []
			for k in pts.size() - 1:
				bs.append(mb.bone("%s%d" % [nm, k], ch["parent"] if k == 0 else "%s%d" % [nm, k - 1], pts[k]))
			_loft_chain(mb, pts, ch["prof"], bs, mb.b(ch["parent"]), pal, ch.get("seg", 8), ch.get("embed", 0.5))
			lst.append({"sd": sd, "b": bs})
		chains[ch["name"]] = lst
	_loft_body(mb, sp["body"], pal)
	_loft_chain(mb, tp, sp["tail"]["prof"], tb, mb.b("pelvis"), pal, sp["tail"].get("seg", 8), 0.5)
	for pe: Array in sp.get("pieces", []):
		# [кость, начало, направление, кольца, палитра, зеркально]
		var sides: Array = [-1.0, 1.0] if pe.size() > 5 and pe[5] else [1.0]
		for sd: float in sides:
			var o: Vector3 = _mirror(pe[1], sd)
			var dr: Vector3 = _mirror(pe[2], sd)
			_piece(mb, o, _aim(dr), pe[3], pal[pe[4]], {mb.b(pe[0]): 1.0}, 10 if (pe[3] as Array).size() > 3 else 8)
	for pe: Array in sp.get("custom", []):
		# готовые детали со своим базисом: [кость, начало, базис, кольца, палитра]
		_piece(mb, pe[1], pe[2], pe[3], pal[pe[4]], {mb.b(pe[0]): 1.0}, pe[5] if pe.size() > 5 else 8)
	var skin := Skin.new()
	for i in mb.names.size():
		skin.add_bind(i, Transform3D(Basis(), -(mb.gpos[i] as Vector3)))
	var d := {"mesh": mb.commit(), "skin": skin, "names": mb.names, "parents": mb.parents, "gpos": mb.gpos, "legs": legs,
		"tails": tb, "tris": mb.ix.size() / 3, "chains": chains}
	for k in ["root", "pelvis", "chest", "neck1", "neck2", "head", "jaw"]:
		d[k] = mb.b(k)
	for k in sp:
		if not k in ["bones", "tail", "legs", "body", "pal", "pieces", "custom", "chains"]:
			d[k] = sp[k]
	d["H"] = (bp["root"] as Vector3).y
	return d

static func build_taiga(root: Node3D, kind: String, scale_k: float, male: bool, winter: bool) -> Dictionary:
	var key := "%s_%s_%s" % [kind, male, winter]
	if not _an_cache.has(key):
		_an_cache[key] = _anat(_spec(kind, male, winter))
	var d: Dictionary = _an_cache[key]
	var model := Node3D.new()
	model.scale = Vector3.ONE * scale_k
	root.add_child(model)
	var sk := Skeleton3D.new()
	model.add_child(sk)
	var names: Array = d["names"]
	var gp: Array = d["gpos"]
	var par: Array = d["parents"]
	for i in names.size():
		sk.add_bone(names[i])
	for i in names.size():
		var p: int = par[i]
		sk.set_bone_parent(i, p)
		var o: Vector3 = gp[i]
		if p >= 0:
			o -= gp[p] as Vector3
		sk.set_bone_rest(i, Transform3D(Basis(), o))
	sk.reset_bone_poses()
	var mi := MeshInstance3D.new()
	mi.mesh = d["mesh"]
	mi.skin = d["skin"]
	mi.material_override = d["mat"]
	sk.add_child(mi)
	mi.skeleton = NodePath("..")
	return {"rig": true, "model": model, "skel": sk, "mi": mi, "def": d, "sk": scale_k, "L": float(d["L"]) * scale_k, "H": float(d["H"]) * scale_k}

static func _spec(kind: String, male: bool, winter: bool) -> Dictionary:
	match kind:
		"moose":
			return _sp_moose(male, winter)
		"lynx":
			return _sp_lynx(winter)
		"wolverine":
			return _sp_wolverine()
		"muskdeer":
			return _sp_muskdeer(male)
		"capercaillie":
			return _sp_bird(male)
		"hare":
			return _sp_hare(winter)
		"squirrel":
			return _sp_squirrel(winter)
		"boar":
			return _sp_boar(male)
		"bear":
			return _sp_bear()
		"tiger":
			return _sp_tiger()
	return _sp_moose(male, winter)

# ----- описания видов: кости, сечения тела [z, y, верх, низ, шир. спины, шир. середины, шир. низа,
# кость, палитра, челюсть], ноги (точки суставов левой стороны и профиль мышц), хвост, детали -----

## Сечения копыта (общие для копытных): бабка → копыто → торец; k — масштаб.
static func _hoof(seg_k: int, k: float, legl: String = "legl") -> Array:
	return [[seg_k, 0.0, 0.046 * k, 0.052 * k, 0.0, legl], [seg_k, 0.4, 0.05 * k, 0.06 * k, 0.005 * k, "hoof"],
		[seg_k, 0.82, 0.062 * k, 0.078 * k, 0.0, "hoof"], [seg_k, 1.0, 0.045 * k, 0.055 * k, -0.01 * k, "hoof"]]

## Лось: самый крупный олень. Высокие ноги, короткое тело, горб на холке (остистые отростки),
## глубокая узкая грудь с килем, поджарый пах, короткая толстая шея, длинная горбоносая
## морда с нависающей верхней губой, «серьга» под горлом, у быка — лопатообразные рога.
static func _sp_moose(male: bool, winter: bool) -> Dictionary:
	var back := Color(0.48, 0.36, 0.25) if not winter else Color(0.52, 0.43, 0.34)
	var dark := Color(0.33, 0.25, 0.18)
	var pal := {
		"body": {"back": back, "belly": dark},
		"leg": {"back": back.lerp(Color(0.62, 0.56, 0.48), 0.35), "belly": back},
		"legl": {"back": Color(0.7, 0.64, 0.56)},
		"hoof": {"back": Color(0.13, 0.11, 0.09)},
		"head": {"back": Color(0.48, 0.36, 0.25), "belly": Color(0.36, 0.27, 0.19)},
		"muzzle": {"back": Color(0.3, 0.23, 0.17), "belly": Color(0.2, 0.15, 0.12)},
		"ear": {"back": back, "belly": Color(0.5, 0.44, 0.37)},
		"eye": {"back": Color(0.04, 0.03, 0.03)},
		"bell": {"back": dark},
		"antler": {"back": Color(0.64, 0.56, 0.44), "belly": Color(0.52, 0.45, 0.35), "tip": Color(0.8, 0.75, 0.66), "tip_t": 0.85},
	}
	var sp := {"mat": _an_mat(0.0), "pal": pal, "L": 2.7, "lie_y": 0.58, "graze": [0.85, 0.45], "flex": 0.06, "lie_f": [0.9, -2.35, 3.1]}
	sp["bones"] = {"root": Vector3(0, 1.46, -0.1), "pelvis": Vector3(0, 1.5, -0.6), "chest": Vector3(0, 1.52, 0.3),
		"neck1": Vector3(0, 1.6, 0.72), "neck2": Vector3(0, 1.7, 1.0), "head": Vector3(0, 1.82, 1.24), "jaw": Vector3(0, 1.72, 1.3)}
	sp["body"] = [
		[-1.04, 1.52, 0.06, 0.06, 0.05, 0.06, 0.05, "pelvis"],
		[-0.98, 1.5, 0.2, 0.24, 0.14, 0.18, 0.12, "pelvis"],
		[-0.88, 1.48, 0.27, 0.32, 0.2, 0.25, 0.16, "pelvis"],
		[-0.72, 1.46, 0.3, 0.34, 0.24, 0.3, 0.18, "pelvis"],
		[-0.5, 1.44, 0.3, 0.31, 0.26, 0.33, 0.2, "pelvis"],
		[-0.25, 1.44, 0.31, 0.39, 0.29, 0.38, 0.28, "root"],
		[0.0, 1.46, 0.33, 0.45, 0.3, 0.39, 0.27, "root"],
		[0.25, 1.49, 0.39, 0.5, 0.28, 0.36, 0.2, "chest"],
		[0.45, 1.52, 0.44, 0.53, 0.23, 0.32, 0.12, "chest"],
		[0.62, 1.56, 0.38, 0.47, 0.18, 0.25, 0.11, "chest"],
		[0.76, 1.6, 0.29, 0.38, 0.15, 0.19, 0.11, "neck1"],
		[0.9, 1.65, 0.23, 0.3, 0.13, 0.16, 0.11, "neck1"],
		[1.04, 1.71, 0.19, 0.24, 0.115, 0.135, 0.1, "neck2"],
		[1.16, 1.77, 0.16, 0.2, 0.1, 0.12, 0.09, "neck2"],
		[1.26, 1.82, 0.12, 0.16, 0.09, 0.105, 0.08, "head", "head"],
		[1.34, 1.77, 0.11, 0.15, 0.1, 0.11, 0.075, "head", "head", true],
		[1.43, 1.67, 0.09, 0.13, 0.085, 0.095, 0.07, "head", "head", true],
		[1.51, 1.56, 0.085, 0.12, 0.075, 0.085, 0.065, "head", "head", true],
		[1.58, 1.46, 0.105, 0.12, 0.085, 0.1, 0.07, "head", "head", true],
		[1.63, 1.38, 0.1, 0.1, 0.085, 0.095, 0.07, "head", "muzzle", true],
		[1.66, 1.32, 0.055, 0.06, 0.055, 0.06, 0.05, "head", "muzzle", true],
	]
	sp["tail"] = {"pts": [Vector3(0, 1.58, -1.0), Vector3(0, 1.52, -1.08), Vector3(0, 1.44, -1.12), Vector3(0, 1.39, -1.13)],
		"prof": [[0, 0.2, 0.05, 0.05, 0.0, "body"], [1, 0.5, 0.045, 0.04, 0.0, "body"], [2, 1.0, 0.02, 0.02, 0.0, "body"]], "seg": 6}
	var hf := _hoof(4, 1.0)
	sp["legs"] = {
		"f": {"pts": [Vector3(0.14, 1.85, 0.4), Vector3(0.21, 1.3, 0.6), Vector3(0.19, 0.98, 0.43), Vector3(0.17, 0.52, 0.46), Vector3(0.17, 0.12, 0.49), Vector3(0.17, 0.0, 0.6)],
			"prof": [[0, 0.0, 0.05, 0.16, 0.0, "body"], [0, 0.45, 0.1, 0.2, 0.0, "body"], [0, 0.85, 0.13, 0.18, 0.0, "body"],
				[1, 0.35, 0.13, 0.16, 0.0, "body"], [1, 0.8, 0.11, 0.12, 0.0, "leg"], [2, 0.1, 0.09, 0.1, -0.01, "leg"],
				[2, 0.35, 0.075, 0.085, 0.01, "leg"], [2, 0.8, 0.05, 0.055, 0.0, "legl"], [3, 0.0, 0.055, 0.056, 0.0, "legl"],
				[3, 0.3, 0.042, 0.044, 0.0, "legl"], [3, 0.85, 0.04, 0.042, 0.0, "legl"]] + hf},
		"h": {"pts": [Vector3(0.13, 1.78, -0.55), Vector3(0.2, 1.45, -0.74), Vector3(0.21, 1.07, -0.52), Vector3(0.16, 0.62, -0.82), Vector3(0.16, 0.13, -0.74), Vector3(0.16, 0.0, -0.63)],
			"prof": [[0, 0.0, 0.06, 0.14, 0.0, "body"], [0, 0.6, 0.12, 0.18, 0.02, "body"], [1, 0.15, 0.16, 0.21, 0.03, "body"],
				[1, 0.6, 0.15, 0.19, 0.02, "body"], [1, 0.95, 0.11, 0.13, 0.0, "leg"], [2, 0.2, 0.1, 0.13, -0.02, "leg"],
				[2, 0.6, 0.065, 0.08, -0.01, "leg"], [2, 0.92, 0.045, 0.07, -0.02, "legl"], [3, 0.12, 0.042, 0.05, 0.0, "legl"],
				[3, 0.85, 0.039, 0.042, 0.0, "legl"]] + hf},
	}
	var pieces := [
		["head", Vector3(0.08, 1.88, 1.24), Vector3(0.8, 0.5, -0.4), [[0.0, 0.035, 0.02, 0.0], [0.1, 0.055, 0.02, 0.0], [0.2, 0.035, 0.015, 0.0], [0.26, 0.004, 0.004, 0.0]], "ear", true],
		["head", Vector3(0.1, 1.79, 1.35), Vector3(0.5, 0.1, 0.85), [[0.0, 0.012, 0.01, 0.0], [0.015, 0.018, 0.015, 0.0], [0.03, 0.004, 0.004, 0.0]], "eye", true],
		["neck2", Vector3(0, 1.61, 1.18), Vector3(0, -1, -0.15), [[0.0, 0.03, 0.06, 0.0], [0.12, 0.035, 0.07, 0.0], [0.24 if male else 0.12, 0.02, 0.04, 0.0], [0.3 if male else 0.15, 0.005, 0.01, 0.0]], "bell", false],
	]
	sp["pieces"] = pieces
	if male:
		var custom := []
		for sd in [-1.0, 1.0]:
			# лопата: +Z — вбок и вверх, ширина — почти вертикально, лопата смотрит вперёд
			var z := Vector3(sd, 0.54, -0.04).normalized()
			var wa := Vector3(0, 0.96, -0.25)
			var x := (wa - z * wa.dot(z)).normalized() * -float(sd)
			var y := z.cross(x)
			var o := Vector3(sd * 0.07, 1.9, 1.26)
			custom.append(["head", o, Basis(x, y, z), [[0.0, 0.035, 0.035, 0.0], [0.2, 0.04, 0.03, 0.0], [0.28, 0.1, 0.025, 0.0], [0.42, 0.19, 0.022, 0.02], [0.56, 0.22, 0.02, 0.04], [0.66, 0.17, 0.018, 0.05], [0.7, 0.05, 0.012, 0.05]], "antler", 8])
			# отростки по верхнему краю лопаты
			var up := -float(sd)
			for ti in 6:
				var zt := 0.36 + ti * 0.065
				var w := 0.2 - absf(zt - 0.55) * 0.5
				var to := o + z * zt + x * (up * w)
				var dr := (x * up + z * (0.25 + ti * 0.15)).normalized()
				custom.append(["head", to, _aim(dr), [[0.0, 0.02, 0.013, 0.0], [0.08, 0.011, 0.009, 0.0], [0.14, 0.003, 0.003, 0.0]], "antler", 5])
			custom.append(["head", o + z * 0.3 - x * up * 0.06, _aim(-x * up * 0.5 + y * 0.6 + z * 0.6), [[0.0, 0.02, 0.013, 0.0], [0.08, 0.011, 0.009, 0.0], [0.14, 0.003, 0.003, 0.0]], "antler", 5])
		sp["custom"] = custom
	return sp


## Профиль лапы (пальцеходящей/стопоходящей): последнее звено идёт вперёд по земле.
static func _paw(seg_k: int, w: float, h: float, pal_k: String = "paw") -> Array:
	return [[seg_k, 0.0, w * 0.85, h * 1.5, 0.0, pal_k], [seg_k, 0.25, w, h * 1.1, h * 0.2, pal_k],
		[seg_k, 0.7, w * 1.02, h, h * 0.1, pal_k], [seg_k, 1.0, w * 0.6, h * 0.6, 0.0, pal_k]]

## Рысь: короткое тело, высокий зад, длинные ноги с широкими лапами, маленькая круглая голова,
## бакенбарды, кисточки на ушах, короткий хвост с чёрным концом; пятна.
static func _sp_lynx(winter: bool) -> Dictionary:
	var back := Color(0.66, 0.57, 0.46) if not winter else Color(0.72, 0.66, 0.58)
	var belly := Color(0.9, 0.86, 0.78)
	var pal := {
		"body": {"back": back, "belly": belly, "pat": 1.0},
		"leg": {"back": back, "belly": back.lerp(belly, 0.4), "pat": 1.0},
		"paw": {"back": back.lerp(belly, 0.3)},
		"head": {"back": back, "belly": belly, "pat": 0.6},
		"face": {"back": back.lerp(belly, 0.3), "belly": belly},
		"nose": {"back": Color(0.45, 0.3, 0.27), "belly": belly},
		"ear": {"back": Color(0.3, 0.25, 0.2), "belly": back},
		"tuft": {"back": Color(0.05, 0.04, 0.04)},
		"ruff": {"back": Color(0.78, 0.72, 0.62), "belly": Color(0.4, 0.34, 0.28)},
		"eye": {"back": Color(0.1, 0.08, 0.04)},
		"tail": {"back": back, "belly": belly, "tip": Color(0.06, 0.05, 0.05), "tip_t": 0.62},
	}
	var sp := {"arun": 0.55, "mat": _an_mat(1.0), "pal": pal, "L": 1.0, "lie_y": 0.17, "graze": [0.9, 0.3], "flex": 0.18, "lie_f": [0.5, -2.0, 0.1]}
	sp["bones"] = {"root": Vector3(0, 0.53, 0), "pelvis": Vector3(0, 0.58, -0.28), "chest": Vector3(0, 0.54, 0.22),
		"neck1": Vector3(0, 0.58, 0.4), "neck2": Vector3(0, 0.63, 0.48), "head": Vector3(0, 0.665, 0.55), "jaw": Vector3(0, 0.64, 0.58)}
	sp["body"] = [
		[-0.47, 0.6, 0.04, 0.04, 0.035, 0.04, 0.035, "pelvis"],
		[-0.43, 0.59, 0.09, 0.1, 0.07, 0.09, 0.06, "pelvis"],
		[-0.35, 0.58, 0.11, 0.13, 0.09, 0.11, 0.07, "pelvis"],
		[-0.22, 0.56, 0.11, 0.13, 0.1, 0.115, 0.075, "pelvis"],
		[-0.08, 0.53, 0.1, 0.12, 0.1, 0.11, 0.08, "root"],
		[0.06, 0.52, 0.11, 0.15, 0.105, 0.12, 0.08, "root"],
		[0.18, 0.52, 0.13, 0.18, 0.1, 0.12, 0.07, "chest"],
		[0.28, 0.53, 0.13, 0.18, 0.09, 0.11, 0.06, "chest"],
		[0.36, 0.56, 0.11, 0.14, 0.08, 0.09, 0.06, "chest"],
		[0.43, 0.6, 0.08, 0.1, 0.065, 0.075, 0.06, "neck1"],
		[0.49, 0.64, 0.065, 0.08, 0.055, 0.06, 0.05, "neck2"],
		[0.54, 0.67, 0.06, 0.065, 0.055, 0.065, 0.055, "head", "head"],
		[0.58, 0.68, 0.065, 0.075, 0.065, 0.08, 0.075, "head", "head"],
		[0.62, 0.68, 0.06, 0.068, 0.06, 0.08, 0.07, "head", "head", true],
		[0.66, 0.675, 0.048, 0.05, 0.05, 0.058, 0.045, "head", "face", true],
		[0.69, 0.665, 0.034, 0.034, 0.035, 0.04, 0.03, "head", "face", true],
		[0.705, 0.66, 0.018, 0.018, 0.018, 0.02, 0.016, "head", "nose", true],
	]
	sp["tail"] = {"pts": [Vector3(0, 0.64, -0.45), Vector3(0, 0.6, -0.52), Vector3(0, 0.55, -0.58), Vector3(0, 0.52, -0.62)],
		"prof": [[0, 0.1, 0.03, 0.03, 0.0, "tail"], [1, 0.3, 0.034, 0.034, 0.0, "tail"], [2, 0.5, 0.032, 0.032, 0.0, "tail"], [2, 1.0, 0.012, 0.012, 0.0, "tail"]], "seg": 6}
	sp["legs"] = {
		"f": {"pts": [Vector3(0.07, 0.68, 0.2), Vector3(0.1, 0.47, 0.3), Vector3(0.09, 0.36, 0.2), Vector3(0.08, 0.12, 0.22), Vector3(0.08, 0.04, 0.24), Vector3(0.08, 0.018, 0.33)],
			"prof": [[0, 0.0, 0.03, 0.08, 0.0, "body"], [0, 0.5, 0.06, 0.1, 0.0, "body"], [1, 0.2, 0.07, 0.09, 0.0, "body"], [1, 0.7, 0.06, 0.07, 0.0, "leg"],
				[2, 0.1, 0.05, 0.055, -0.005, "leg"], [2, 0.4, 0.045, 0.045, 0.005, "leg"], [2, 0.9, 0.032, 0.033, 0.0, "leg"], [3, 0.3, 0.03, 0.03, 0.0, "leg"]] + _paw(4, 0.045, 0.022)},
		"h": {"pts": [Vector3(0.07, 0.7, -0.22), Vector3(0.1, 0.55, -0.33), Vector3(0.1, 0.34, -0.17), Vector3(0.08, 0.17, -0.38), Vector3(0.08, 0.04, -0.33), Vector3(0.08, 0.018, -0.24)],
			"prof": [[0, 0.0, 0.04, 0.08, 0.0, "body"], [0, 0.6, 0.08, 0.12, 0.0, "body"], [1, 0.2, 0.09, 0.12, 0.0, "body"], [1, 0.7, 0.07, 0.08, 0.0, "leg"],
				[2, 0.2, 0.05, 0.065, -0.01, "leg"], [2, 0.6, 0.04, 0.045, -0.005, "leg"], [2, 0.95, 0.03, 0.04, -0.01, "leg"], [3, 0.3, 0.028, 0.03, 0.0, "leg"]] + _paw(4, 0.042, 0.02)},
	}
	var ed := Vector3(0.25, 1.0, -0.1).normalized()
	sp["pieces"] = [
		["head", Vector3(0.04, 0.72, 0.56), ed, [[0.0, 0.028, 0.01, 0.0], [0.05, 0.022, 0.009, 0.0], [0.07, 0.005, 0.004, 0.0]], "ear", true],
		["head", Vector3(0.04, 0.72, 0.56) + ed * 0.066, ed, [[0.0, 0.004, 0.004, 0.0], [0.045, 0.0015, 0.0015, 0.0]], "tuft", true],
		["head", Vector3(0.05, 0.65, 0.6), Vector3(0.5, -0.75, -0.4), [[0.0, 0.022, 0.012, 0.0], [0.035, 0.03, 0.014, 0.0], [0.065, 0.018, 0.008, 0.0], [0.08, 0.003, 0.003, 0.0]], "ruff", true],
		["head", Vector3(0.042, 0.69, 0.645), Vector3(0.4, 0.1, 0.9), [[0.0, 0.008, 0.008, 0.0], [0.01, 0.011, 0.01, 0.0], [0.02, 0.003, 0.003, 0.0]], "eye", true],
	]
	return sp

## Росомаха: приземистая, тяжёлая, медвежья; спина дугой (зад выше), короткие толстые ноги,
## широкие лапы, широкая голова, маленькие уши, пушистый хвост; светлая полоса по бокам от
## плеч к хвосту, светлый лоб.
static func _sp_wolverine() -> Dictionary:
	var back := Color(0.36, 0.25, 0.17)
	var dark := Color(0.27, 0.19, 0.14)
	var pal := {
		"body": {"back": back, "belly": dark, "band": Color(0.62, 0.48, 0.34), "band_lo": -0.15, "band_hi": 0.45, "band_t0": 0.1, "band_t1": 0.62},
		"leg": {"back": dark, "belly": dark},
		"paw": {"back": Color(0.2, 0.14, 0.11)},
		"head": {"back": Color(0.34, 0.25, 0.18), "belly": dark, "band": Color(0.64, 0.54, 0.42), "band_lo": 0.55, "band_hi": 1.1, "band_t0": 0.0, "band_t1": 0.5},
		"face": {"back": Color(0.24, 0.17, 0.12), "belly": dark},
		"nose": {"back": Color(0.06, 0.05, 0.05)},
		"ear": {"back": Color(0.5, 0.4, 0.3)},
		"eye": {"back": Color(0.04, 0.03, 0.03)},
		"tail": {"back": dark},
	}
	var sp := {"arun": 0.45, "mat": _an_mat(0.0), "pal": pal, "L": 0.85, "lie_y": 0.17, "graze": [0.6, 0.3], "flex": 0.2, "lie_f": [0.5, -2.0, 0.1]}
	sp["bones"] = {"root": Vector3(0, 0.34, 0), "pelvis": Vector3(0, 0.38, -0.2), "chest": Vector3(0, 0.33, 0.15),
		"neck1": Vector3(0, 0.33, 0.3), "neck2": Vector3(0, 0.34, 0.36), "head": Vector3(0, 0.35, 0.42), "jaw": Vector3(0, 0.33, 0.46)}
	sp["body"] = [
		[-0.36, 0.4, 0.04, 0.04, 0.04, 0.045, 0.04, "pelvis"],
		[-0.33, 0.4, 0.11, 0.12, 0.1, 0.12, 0.09, "pelvis"],
		[-0.26, 0.39, 0.14, 0.15, 0.13, 0.15, 0.11, "pelvis"],
		[-0.15, 0.37, 0.15, 0.16, 0.14, 0.16, 0.13, "pelvis"],
		[-0.03, 0.35, 0.14, 0.16, 0.14, 0.16, 0.13, "root"],
		[0.09, 0.33, 0.13, 0.16, 0.13, 0.15, 0.12, "chest"],
		[0.19, 0.32, 0.12, 0.16, 0.12, 0.14, 0.1, "chest"],
		[0.27, 0.32, 0.1, 0.13, 0.1, 0.11, 0.085, "chest"],
		[0.33, 0.33, 0.08, 0.1, 0.085, 0.095, 0.08, "neck1"],
		[0.38, 0.34, 0.075, 0.08, 0.08, 0.085, 0.075, "neck2"],
		[0.43, 0.35, 0.075, 0.075, 0.085, 0.095, 0.08, "head", "head"],
		[0.48, 0.35, 0.07, 0.068, 0.08, 0.09, 0.075, "head", "head", true],
		[0.53, 0.34, 0.05, 0.05, 0.055, 0.06, 0.05, "head", "face", true],
		[0.565, 0.33, 0.033, 0.033, 0.038, 0.04, 0.033, "head", "face", true],
		[0.58, 0.325, 0.017, 0.017, 0.017, 0.02, 0.016, "head", "nose", true],
	]
	sp["tail"] = {"pts": [Vector3(0, 0.46, -0.34), Vector3(0, 0.44, -0.42), Vector3(0, 0.4, -0.5), Vector3(0, 0.36, -0.56)],
		"prof": [[0, 0.1, 0.045, 0.045, 0.0, "tail"], [1, 0.3, 0.06, 0.06, 0.0, "tail"], [2, 0.4, 0.055, 0.055, 0.0, "tail"], [2, 1.0, 0.02, 0.02, 0.0, "tail"]], "seg": 7}
	sp["legs"] = {
		"f": {"pts": [Vector3(0.08, 0.4, 0.17), Vector3(0.11, 0.27, 0.23), Vector3(0.11, 0.18, 0.16), Vector3(0.1, 0.07, 0.19), Vector3(0.1, 0.03, 0.21), Vector3(0.1, 0.016, 0.3)],
			"prof": [[0, 0.0, 0.04, 0.07, 0.0, "body"], [0, 0.6, 0.07, 0.09, 0.0, "body"], [1, 0.3, 0.08, 0.08, 0.0, "body"], [1, 0.8, 0.065, 0.065, 0.0, "leg"],
				[2, 0.2, 0.065, 0.065, 0.0, "leg"], [2, 0.8, 0.05, 0.05, 0.0, "leg"], [3, 0.4, 0.046, 0.044, 0.0, "leg"]] + _paw(4, 0.052, 0.022)},
		"h": {"pts": [Vector3(0.08, 0.47, -0.17), Vector3(0.11, 0.36, -0.26), Vector3(0.11, 0.21, -0.14), Vector3(0.09, 0.09, -0.3), Vector3(0.09, 0.03, -0.26), Vector3(0.09, 0.016, -0.16)],
			"prof": [[0, 0.0, 0.05, 0.08, 0.0, "body"], [0, 0.6, 0.09, 0.12, 0.0, "body"], [1, 0.2, 0.1, 0.12, 0.0, "body"], [1, 0.7, 0.08, 0.08, 0.0, "leg"],
				[2, 0.2, 0.07, 0.075, -0.005, "leg"], [2, 0.7, 0.052, 0.058, -0.005, "leg"], [3, 0.4, 0.046, 0.046, 0.0, "leg"]] + _paw(4, 0.052, 0.022)},
	}
	sp["pieces"] = [
		["head", Vector3(0.06, 0.41, 0.43), Vector3(0.6, 0.8, -0.3), [[0.0, 0.022, 0.01, 0.0], [0.022, 0.02, 0.009, 0.0], [0.034, 0.004, 0.004, 0.0]], "ear", true],
		["head", Vector3(0.047, 0.375, 0.495), Vector3(0.4, 0.1, 0.9), [[0.0, 0.007, 0.007, 0.0], [0.008, 0.009, 0.009, 0.0], [0.016, 0.002, 0.002, 0.0]], "eye", true],
	]
	return sp

## Кабарга: маленький безрогий олень, сгорбленная спина, круп выше холки (задние ноги длиннее),
## маленькая голова с большими округлыми ушами, у самца — длинные клыки; тёмная, в светлых пятнах.
static func _sp_muskdeer(male: bool) -> Dictionary:
	var back := Color(0.48, 0.37, 0.27)
	var belly := Color(0.7, 0.6, 0.46)
	var pal := {
		"body": {"back": back, "belly": belly, "pat": 0.6},
		"leg": {"back": back, "belly": back, "pat": 0.4},
		"legl": {"back": Color(0.4, 0.3, 0.22)},
		"hoof": {"back": Color(0.1, 0.08, 0.07)},
		"neck": {"back": back, "belly": Color(0.85, 0.8, 0.7)},
		"head": {"back": Color(0.44, 0.34, 0.25), "belly": Color(0.6, 0.5, 0.38)},
		"muzzle": {"back": Color(0.2, 0.15, 0.12), "belly": Color(0.5, 0.42, 0.33)},
		"ear": {"back": Color(0.32, 0.26, 0.2), "belly": Color(0.65, 0.58, 0.48)},
		"eye": {"back": Color(0.04, 0.03, 0.03)},
		"tusk": {"back": Color(0.9, 0.86, 0.75)},
	}
	var sp := {"arun": 0.55, "mat": _an_mat(1.0), "pal": pal, "L": 0.85, "lie_y": 0.2, "graze": [1.0, 0.45], "flex": 0.14, "lie_f": [0.9, -2.35, 3.1]}
	sp["bones"] = {"root": Vector3(0, 0.5, -0.05), "pelvis": Vector3(0, 0.58, -0.25), "chest": Vector3(0, 0.48, 0.15),
		"neck1": Vector3(0, 0.48, 0.32), "neck2": Vector3(0, 0.54, 0.4), "head": Vector3(0, 0.61, 0.46), "jaw": Vector3(0, 0.595, 0.49)}
	sp["body"] = [
		[-0.42, 0.62, 0.04, 0.04, 0.035, 0.04, 0.035, "pelvis"],
		[-0.38, 0.61, 0.09, 0.11, 0.07, 0.09, 0.06, "pelvis"],
		[-0.3, 0.59, 0.11, 0.14, 0.09, 0.11, 0.07, "pelvis"],
		[-0.18, 0.56, 0.12, 0.15, 0.1, 0.12, 0.08, "pelvis"],
		[-0.05, 0.52, 0.12, 0.15, 0.105, 0.125, 0.09, "root"],
		[0.08, 0.49, 0.11, 0.15, 0.1, 0.12, 0.08, "chest"],
		[0.19, 0.47, 0.1, 0.15, 0.09, 0.105, 0.06, "chest"],
		[0.28, 0.47, 0.08, 0.12, 0.07, 0.085, 0.05, "chest"],
		[0.35, 0.5, 0.055, 0.07, 0.05, 0.055, 0.045, "neck1", "neck"],
		[0.39, 0.54, 0.045, 0.055, 0.04, 0.045, 0.038, "neck1", "neck"],
		[0.43, 0.58, 0.04, 0.05, 0.035, 0.04, 0.035, "neck2", "neck"],
		[0.46, 0.61, 0.04, 0.045, 0.035, 0.042, 0.035, "head", "head"],
		[0.5, 0.605, 0.04, 0.045, 0.035, 0.042, 0.034, "head", "head", true],
		[0.545, 0.585, 0.03, 0.035, 0.027, 0.032, 0.026, "head", "head", true],
		[0.58, 0.56, 0.022, 0.024, 0.02, 0.022, 0.018, "head", "muzzle", true],
		[0.595, 0.55, 0.011, 0.011, 0.01, 0.011, 0.01, "head", "muzzle", true],
	]
	sp["tail"] = {"pts": [Vector3(0, 0.62, -0.41), Vector3(0, 0.6, -0.44), Vector3(0, 0.57, -0.46)],
		"prof": [[0, 0.2, 0.02, 0.015, 0.0, "body"], [1, 1.0, 0.008, 0.008, 0.0, "body"]], "seg": 5}
	sp["legs"] = {
		"f": {"pts": [Vector3(0.05, 0.56, 0.18), Vector3(0.07, 0.4, 0.26), Vector3(0.06, 0.31, 0.19), Vector3(0.055, 0.15, 0.21), Vector3(0.055, 0.04, 0.22), Vector3(0.055, 0.0, 0.25)],
			"prof": [[0, 0.0, 0.03, 0.06, 0.0, "body"], [0, 0.6, 0.045, 0.07, 0.0, "body"], [1, 0.3, 0.05, 0.06, 0.0, "body"], [1, 0.8, 0.04, 0.045, 0.0, "leg"],
				[2, 0.2, 0.032, 0.035, 0.0, "leg"], [2, 0.8, 0.02, 0.022, 0.0, "legl"], [3, 0.0, 0.02, 0.021, 0.0, "legl"], [3, 0.8, 0.015, 0.016, 0.0, "legl"]] + _hoof(4, 0.33)},
		"h": {"pts": [Vector3(0.05, 0.68, -0.2), Vector3(0.07, 0.58, -0.32), Vector3(0.07, 0.36, -0.18), Vector3(0.055, 0.2, -0.38), Vector3(0.055, 0.04, -0.34), Vector3(0.055, 0.0, -0.3)],
			"prof": [[0, 0.0, 0.04, 0.07, 0.0, "body"], [0, 0.6, 0.06, 0.1, 0.0, "body"], [1, 0.2, 0.07, 0.1, 0.0, "body"], [1, 0.7, 0.05, 0.06, 0.0, "leg"],
				[2, 0.2, 0.035, 0.045, -0.005, "leg"], [2, 0.7, 0.022, 0.03, -0.005, "legl"], [2, 0.95, 0.018, 0.03, -0.008, "legl"], [3, 0.2, 0.016, 0.018, 0.0, "legl"],
				[3, 0.85, 0.015, 0.016, 0.0, "legl"]] + _hoof(4, 0.33)},
	}
	var pieces := [
		["head", Vector3(0.03, 0.645, 0.46), Vector3(0.75, 0.6, -0.45), [[0.0, 0.025, 0.01, 0.0], [0.04, 0.033, 0.01, 0.0], [0.07, 0.022, 0.008, 0.0], [0.085, 0.004, 0.004, 0.0]], "ear", true],
		["head", Vector3(0.034, 0.627, 0.505), Vector3(0.4, 0.1, 0.9), [[0.0, 0.007, 0.007, 0.0], [0.008, 0.01, 0.009, 0.0], [0.016, 0.002, 0.002, 0.0]], "eye", true],
	]
	if male:
		pieces.append(["head", Vector3(0.015, 0.56, 0.555), Vector3(0.1, -1.0, -0.15), [[0.0, 0.005, 0.006, 0.0], [0.035, 0.004, 0.004, 0.003], [0.06, 0.0015, 0.0015, 0.01]], "tusk", true])
	sp["pieces"] = pieces
	return sp

## Глухарь: крупная курообразная птица. Самец чёрно-сизый, грудь с зелёным отливом, красная
## бровь, светлый клюв, «борода», длинный хвост-веер; самка рыжевато-бурая с рябью.
static func _sp_bird(male: bool) -> Dictionary:
	var back := Color(0.42, 0.42, 0.47) if male else Color(0.52, 0.42, 0.31)
	var belly := Color(0.2, 0.2, 0.21) if male else Color(0.74, 0.66, 0.54)
	var pat := 0.0 if male else 1.0
	var pal := {
		"body": {"back": back, "belly": belly, "pat": pat},
		"breast": {"back": back, "belly": Color(0.12, 0.32, 0.22) if male else Color(0.7, 0.5, 0.32), "pat": pat},
		"neck": {"back": Color(0.38, 0.38, 0.42) if male else back, "belly": Color(0.14, 0.3, 0.22) if male else Color(0.72, 0.52, 0.34), "pat": pat},
		"headb": {"back": Color(0.34, 0.34, 0.38) if male else back, "belly": Color(0.2, 0.2, 0.22) if male else belly, "pat": pat},
		"beak": {"back": Color(0.86, 0.82, 0.68) if male else Color(0.3, 0.27, 0.24)},
		"wing": {"back": Color(0.5, 0.38, 0.25) if male else Color(0.52, 0.4, 0.28), "belly": Color(0.42, 0.32, 0.22) if male else Color(0.46, 0.36, 0.25), "pat": pat},
		"tailf": {"back": Color(0.16, 0.16, 0.17) if male else Color(0.55, 0.4, 0.27), "belly": Color(0.2, 0.2, 0.22) if male else Color(0.6, 0.44, 0.3), "pat": pat},
		"thigh": {"back": back.lerp(belly, 0.5), "pat": pat},
		"shank": {"back": Color(0.3, 0.27, 0.24) if male else Color(0.5, 0.4, 0.3)},
		"toe": {"back": Color(0.22, 0.2, 0.17)},
		"eye": {"back": Color(0.04, 0.03, 0.03)},
		"brow": {"back": Color(0.85, 0.08, 0.06)},
		"beard": {"back": Color(0.1, 0.1, 0.1)},
	}
	var sp := {"mat": _an_mat(0.0 if male else 2.0), "pal": pal, "L": 0.5, "lie_y": 0.17, "bird": true, "fan": 3.2}
	sp["bones"] = {"root": Vector3(0, 0.33, 0), "pelvis": Vector3(0, 0.34, -0.1), "chest": Vector3(0, 0.36, 0.1),
		"neck1": Vector3(0, 0.42, 0.21), "neck2": Vector3(0, 0.49, 0.25), "head": Vector3(0, 0.57, 0.29), "jaw": Vector3(0, 0.575, 0.36)}
	sp["body"] = [
		[-0.2, 0.36, 0.03, 0.03, 0.03, 0.035, 0.03, "pelvis"],
		[-0.16, 0.35, 0.07, 0.08, 0.07, 0.08, 0.06, "pelvis"],
		[-0.08, 0.33, 0.1, 0.12, 0.1, 0.12, 0.09, "pelvis"],
		[0.02, 0.33, 0.11, 0.13, 0.11, 0.125, 0.1, "root"],
		[0.11, 0.35, 0.1, 0.13, 0.1, 0.115, 0.09, "chest", "breast"],
		[0.18, 0.39, 0.08, 0.11, 0.08, 0.09, 0.075, "chest", "breast"],
		[0.23, 0.44, 0.05, 0.07, 0.05, 0.06, 0.05, "neck1", "neck"],
		[0.26, 0.5, 0.04, 0.055, 0.04, 0.045, 0.04, "neck2", "neck"],
		[0.28, 0.54, 0.035, 0.045, 0.035, 0.04, 0.035, "neck2", "neck"],
		[0.295, 0.575, 0.032, 0.04, 0.03, 0.036, 0.03, "head", "headb"],
		[0.32, 0.59, 0.034, 0.034, 0.03, 0.034, 0.028, "head", "headb"],
		[0.35, 0.585, 0.025, 0.025, 0.022, 0.025, 0.02, "head", "headb"],
		[0.365, 0.577, 0.016, 0.016, 0.013, 0.015, 0.012, "head", "beak", true],
		[0.39, 0.565, 0.01, 0.008, 0.008, 0.009, 0.007, "head", "beak", true],
		[0.405, 0.555, 0.003, 0.003, 0.003, 0.003, 0.003, "head", "beak", true],
	]
	var tl := 0.32 if male else 0.2
	sp["tail"] = {"pts": [Vector3(0, 0.37, -0.17), Vector3(0, 0.33, -0.17 - tl)],
		"prof": [[0, 0.0, 0.03, 0.012, 0.0, "tailf"], [0, 0.4, 0.055, 0.01, 0.0, "tailf"], [0, 0.85, 0.07, 0.008, 0.0, "tailf"], [0, 1.0, 0.04, 0.004, 0.0, "tailf"]], "seg": 8}
	sp["legs"] = {"f": {"parent": "pelvis", "seg": 6, "embed": 0.7,
		"pts": [Vector3(0.05, 0.3, 0.0), Vector3(0.06, 0.2, 0.04), Vector3(0.055, 0.1, -0.02), Vector3(0.055, 0.015, 0.01), Vector3(0.055, 0.006, 0.08)],
		"prof": [[0, 0.0, 0.035, 0.05, 0.0, "body"], [0, 0.6, 0.04, 0.05, 0.0, "thigh"], [1, 0.3, 0.025, 0.03, 0.0, "thigh"], [1, 0.9, 0.012, 0.012, 0.0, "shank"],
			[2, 0.2, 0.01, 0.01, 0.0, "shank"], [2, 0.95, 0.009, 0.009, 0.0, "shank"], [3, 0.2, 0.025, 0.005, 0.0, "toe"], [3, 1.0, 0.006, 0.003, 0.0, "toe"]]}}
	sp["chains"] = [{"name": "w", "parent": "chest", "seg": 8, "embed": 0.3,
		"pts": [Vector3(0.1, 0.39, 0.12), Vector3(0.125, 0.36, -0.04), Vector3(0.11, 0.32, -0.24)],
		"prof": [[0, 0.0, 0.015, 0.035, 0.0, "wing"], [0, 0.5, 0.02, 0.06, 0.0, "wing"], [1, 0.0, 0.018, 0.07, 0.0, "wing"], [1, 0.6, 0.012, 0.06, 0.0, "wing"], [1, 1.0, 0.004, 0.018, 0.0, "wing"]]}]
	var pieces := [["head", Vector3(0.03, 0.59, 0.325), Vector3(0.95, 0.1, 0.3), [[0.0, 0.006, 0.006, 0.0], [0.006, 0.008, 0.008, 0.0], [0.012, 0.002, 0.002, 0.0]], "eye", true]]
	if male:
		pieces.append(["head", Vector3(0.026, 0.603, 0.305), Vector3(0.2, 0.1, 1.0), [[0.0, 0.005, 0.01, 0.0], [0.02, 0.008, 0.012, 0.0], [0.035, 0.003, 0.005, 0.0]], "brow", true])
		pieces.append(["head", Vector3(0, 0.55, 0.34), Vector3(0, -1, 0.3), [[0.0, 0.02, 0.012, 0.0], [0.03, 0.022, 0.012, 0.0], [0.05, 0.004, 0.004, 0.0]], "beard", false])
	sp["pieces"] = pieces
	return sp

## Заяц-беляк: округлый корпус, спина дугой, короткие передние и длинные задние ноги с длинными
## ступнями (сидит на них), длинные уши с чёрными кончиками, белый хвостик; зимой белый.
static func _sp_hare(winter: bool) -> Dictionary:
	var back := Color(0.52, 0.43, 0.33) if not winter else Color(0.95, 0.95, 0.94)
	var belly := Color(0.86, 0.83, 0.77) if not winter else Color(0.97, 0.97, 0.96)
	var pal := {
		"body": {"back": back, "belly": belly}, "leg": {"back": back.lerp(belly, 0.3)}, "paw": {"back": back.lerp(belly, 0.5)},
		"head": {"back": back, "belly": belly}, "nose": {"back": Color(0.4, 0.3, 0.27)},
		"ear": {"back": back, "belly": back.lerp(belly, 0.4), "tip": Color(0.08, 0.07, 0.06), "tip_t": 0.78},
		"eye": {"back": Color(0.1, 0.06, 0.03)}, "tail": {"back": Color(0.97, 0.97, 0.96)},
	}
	var sp := {"arun": 0.6, "mat": _an_mat(0.0), "pal": pal, "L": 0.5, "lie_y": 0.085, "graze": [0.5, 0.45], "flex": 0.3, "lie_f": [0.5, -1.6, 0.0], "lie_h": [-0.9, 1.2, -0.9]}
	sp["bones"] = {"root": Vector3(0, 0.2, -0.02), "pelvis": Vector3(0, 0.21, -0.1), "chest": Vector3(0, 0.2, 0.07),
		"neck1": Vector3(0, 0.21, 0.13), "neck2": Vector3(0, 0.24, 0.17), "head": Vector3(0, 0.28, 0.2), "jaw": Vector3(0, 0.27, 0.23)}
	sp["body"] = [
		[-0.2, 0.2, 0.03, 0.03, 0.03, 0.035, 0.03, "pelvis"],
		[-0.17, 0.21, 0.08, 0.07, 0.06, 0.075, 0.06, "pelvis"],
		[-0.11, 0.22, 0.1, 0.09, 0.075, 0.09, 0.07, "pelvis"],
		[-0.04, 0.21, 0.1, 0.09, 0.075, 0.085, 0.065, "root"],
		[0.04, 0.2, 0.09, 0.09, 0.065, 0.075, 0.055, "chest"],
		[0.1, 0.2, 0.08, 0.085, 0.06, 0.065, 0.05, "chest"],
		[0.15, 0.22, 0.06, 0.06, 0.045, 0.05, 0.045, "neck1"],
		[0.18, 0.25, 0.05, 0.05, 0.04, 0.045, 0.04, "neck2"],
		[0.2, 0.28, 0.045, 0.045, 0.035, 0.045, 0.04, "head", "head"],
		[0.235, 0.285, 0.045, 0.04, 0.035, 0.045, 0.038, "head", "head", true],
		[0.27, 0.275, 0.035, 0.032, 0.028, 0.032, 0.026, "head", "head", true],
		[0.295, 0.26, 0.022, 0.02, 0.018, 0.02, 0.016, "head", "head", true],
		[0.305, 0.255, 0.01, 0.01, 0.008, 0.01, 0.008, "head", "nose", true],
	]
	sp["tail"] = {"pts": [Vector3(0, 0.24, -0.19), Vector3(0, 0.245, -0.22), Vector3(0, 0.24, -0.24)],
		"prof": [[0, 0.3, 0.022, 0.022, 0.0, "tail"], [1, 1.0, 0.012, 0.012, 0.0, "tail"]], "seg": 6}
	sp["legs"] = {
		"f": {"seg": 7, "pts": [Vector3(0.04, 0.24, 0.08), Vector3(0.05, 0.15, 0.12), Vector3(0.045, 0.11, 0.07), Vector3(0.04, 0.03, 0.09), Vector3(0.04, 0.012, 0.1), Vector3(0.04, 0.006, 0.14)],
			"prof": [[0, 0.0, 0.02, 0.04, 0.0, "body"], [0, 0.6, 0.03, 0.04, 0.0, "body"], [1, 0.4, 0.03, 0.03, 0.0, "body"], [2, 0.2, 0.02, 0.02, 0.0, "leg"],
				[2, 0.9, 0.013, 0.014, 0.0, "leg"], [3, 0.5, 0.013, 0.012, 0.0, "leg"]] + _paw(4, 0.016, 0.008)},
		"h": {"seg": 7, "pts": [Vector3(0.05, 0.27, -0.08), Vector3(0.06, 0.2, -0.13), Vector3(0.07, 0.12, -0.04), Vector3(0.05, 0.04, -0.17), Vector3(0.05, 0.012, -0.12), Vector3(0.05, 0.006, -0.01)],
			"prof": [[0, 0.0, 0.03, 0.05, 0.0, "body"], [0, 0.6, 0.05, 0.07, 0.0, "body"], [1, 0.3, 0.055, 0.07, 0.0, "body"], [1, 0.8, 0.04, 0.045, 0.0, "body"],
				[2, 0.3, 0.03, 0.035, 0.0, "leg"], [2, 0.9, 0.017, 0.02, 0.0, "leg"], [3, 0.5, 0.016, 0.014, 0.0, "leg"]] + _paw(4, 0.019, 0.01)},
	}
	sp["pieces"] = [
		["head", Vector3(0.022, 0.31, 0.21), Vector3(0.2, 1.0, -0.45), [[0.0, 0.016, 0.008, 0.0], [0.04, 0.022, 0.008, 0.0], [0.09, 0.018, 0.007, 0.0], [0.12, 0.004, 0.004, 0.0]], "ear", true],
		["head", Vector3(0.036, 0.29, 0.245), Vector3(0.9, 0.1, 0.4), [[0.0, 0.008, 0.008, 0.0], [0.006, 0.01, 0.01, 0.0], [0.012, 0.002, 0.002, 0.0]], "eye", true],
	]
	return sp

## Белка: лёгкое тело, длинные задние ноги, пушистый хвост изогнут над спиной, кисточки на ушах.
static func _sp_squirrel(winter: bool) -> Dictionary:
	var back := Color(0.62, 0.32, 0.14) if not winter else Color(0.48, 0.44, 0.43)
	var belly := Color(0.88, 0.84, 0.76)
	var pal := {
		"body": {"back": back, "belly": belly}, "leg": {"back": back}, "head": {"back": back, "belly": belly},
		"nose": {"back": Color(0.2, 0.12, 0.1)}, "ear": {"back": back}, "tuft": {"back": back.darkened(0.3)},
		"eye": {"back": Color(0.04, 0.03, 0.03)}, "tail": {"back": back.darkened(0.1), "belly": back.darkened(0.1)}, "paw": {"back": back.darkened(0.15)},
	}
	var sp := {"arun": 0.5, "mat": _an_mat(0.0), "pal": pal, "L": 0.2, "lie_y": 0.03, "graze": [0.5, 0.4], "flex": 0.3, "lie_f": [0.5, -1.6, 0.0], "lie_h": [-0.9, 1.2, -0.9]}
	sp["bones"] = {"root": Vector3(0, 0.08, -0.01), "pelvis": Vector3(0, 0.085, -0.05), "chest": Vector3(0, 0.08, 0.03),
		"neck1": Vector3(0, 0.083, 0.06), "neck2": Vector3(0, 0.093, 0.08), "head": Vector3(0, 0.105, 0.095), "jaw": Vector3(0, 0.1, 0.105)}
	sp["body"] = [
		[-0.1, 0.08, 0.015, 0.015, 0.014, 0.016, 0.014, "pelvis"],
		[-0.085, 0.085, 0.035, 0.035, 0.028, 0.034, 0.026, "pelvis"],
		[-0.05, 0.085, 0.04, 0.04, 0.032, 0.038, 0.03, "pelvis"],
		[-0.01, 0.08, 0.035, 0.037, 0.03, 0.034, 0.027, "root"],
		[0.03, 0.08, 0.033, 0.035, 0.027, 0.03, 0.024, "chest"],
		[0.06, 0.085, 0.028, 0.03, 0.022, 0.025, 0.02, "neck1"],
		[0.08, 0.095, 0.024, 0.025, 0.02, 0.022, 0.019, "neck2"],
		[0.095, 0.105, 0.022, 0.022, 0.019, 0.022, 0.019, "head", "head"],
		[0.11, 0.108, 0.022, 0.02, 0.018, 0.021, 0.018, "head", "head", true],
		[0.127, 0.103, 0.016, 0.014, 0.013, 0.015, 0.012, "head", "head", true],
		[0.14, 0.097, 0.009, 0.008, 0.008, 0.009, 0.007, "head", "head", true],
		[0.145, 0.095, 0.004, 0.004, 0.004, 0.004, 0.004, "head", "nose", true],
	]
	sp["tail"] = {"pts": [Vector3(0, 0.09, -0.1), Vector3(0, 0.1, -0.145), Vector3(0, 0.16, -0.155), Vector3(0, 0.21, -0.115)],
		"prof": [[0, 0.2, 0.02, 0.02, 0.0, "tail"], [1, 0.5, 0.034, 0.034, 0.0, "tail"], [2, 0.5, 0.04, 0.04, 0.0, "tail"], [2, 0.9, 0.036, 0.036, 0.0, "tail"], [2, 1.0, 0.018, 0.018, 0.0, "tail"]], "seg": 7}
	sp["legs"] = {
		"f": {"seg": 6, "pts": [Vector3(0.018, 0.1, 0.035), Vector3(0.022, 0.07, 0.05), Vector3(0.02, 0.05, 0.035), Vector3(0.018, 0.015, 0.045), Vector3(0.018, 0.005, 0.05), Vector3(0.018, 0.002, 0.065)],
			"prof": [[0, 0.0, 0.008, 0.015, 0.0, "body"], [0, 0.6, 0.012, 0.016, 0.0, "body"], [1, 0.4, 0.011, 0.012, 0.0, "body"], [2, 0.3, 0.008, 0.008, 0.0, "leg"],
				[2, 0.9, 0.006, 0.006, 0.0, "leg"], [3, 0.5, 0.005, 0.005, 0.0, "leg"]] + _paw(4, 0.007, 0.003)},
		"h": {"seg": 6, "pts": [Vector3(0.02, 0.11, -0.045), Vector3(0.024, 0.085, -0.065), Vector3(0.026, 0.055, -0.03), Vector3(0.02, 0.015, -0.075), Vector3(0.02, 0.005, -0.06), Vector3(0.02, 0.002, -0.025)],
			"prof": [[0, 0.0, 0.012, 0.02, 0.0, "body"], [0, 0.6, 0.018, 0.025, 0.0, "body"], [1, 0.3, 0.02, 0.024, 0.0, "body"], [1, 0.8, 0.015, 0.016, 0.0, "body"],
				[2, 0.3, 0.011, 0.012, 0.0, "leg"], [2, 0.9, 0.007, 0.007, 0.0, "leg"], [3, 0.5, 0.006, 0.005, 0.0, "leg"]] + _paw(4, 0.008, 0.003)},
	}
	var ed := Vector3(0.3, 1.0, -0.2).normalized()
	sp["pieces"] = [
		["head", Vector3(0.013, 0.12, 0.1), ed, [[0.0, 0.008, 0.004, 0.0], [0.015, 0.007, 0.003, 0.0], [0.022, 0.002, 0.002, 0.0]], "ear", true],
		["head", Vector3(0.013, 0.12, 0.1) + ed * 0.02, ed, [[0.0, 0.003, 0.003, 0.0], [0.015, 0.001, 0.001, 0.0]], "tuft", true],
		["head", Vector3(0.017, 0.113, 0.118), Vector3(0.9, 0.1, 0.4), [[0.0, 0.004, 0.004, 0.0], [0.003, 0.005, 0.005, 0.0], [0.006, 0.001, 0.001, 0.0]], "eye", true],
	]
	return sp

## Кабан: массивный перёд с высокой холкой и гривой, сжатое с боков тело, клиновидная голова
## с пятаком, тонкие ноги на копытцах; у секача — клыки.
static func _sp_boar(male: bool) -> Dictionary:
	var back := Color(0.47, 0.41, 0.35)
	var pal := {
		"body": {"back": back, "belly": Color(0.4, 0.35, 0.3)}, "leg": {"back": Color(0.34, 0.29, 0.25)}, "legl": {"back": Color(0.28, 0.24, 0.21)},
		"hoof": {"back": Color(0.08, 0.07, 0.06)}, "head": {"back": Color(0.45, 0.39, 0.34), "belly": Color(0.4, 0.35, 0.3)},
		"snout": {"back": Color(0.34, 0.29, 0.26)}, "disc": {"back": Color(0.32, 0.25, 0.24)}, "ear": {"back": Color(0.22, 0.19, 0.17)},
		"eye": {"back": Color(0.04, 0.03, 0.03)}, "tusk": {"back": Color(0.92, 0.88, 0.78)}, "tail": {"back": Color(0.2, 0.17, 0.15)},
	}
	var sp := {"arun": 0.4, "mat": _an_mat(0.0), "pal": pal, "L": 1.3, "lie_y": 0.32, "graze": [0.75, 0.55], "flex": 0.08}
	sp["bones"] = {"root": Vector3(0, 0.6, -0.05), "pelvis": Vector3(0, 0.63, -0.4), "chest": Vector3(0, 0.62, 0.2),
		"neck1": Vector3(0, 0.64, 0.4), "neck2": Vector3(0, 0.62, 0.5), "head": Vector3(0, 0.6, 0.58), "jaw": Vector3(0, 0.52, 0.66)}
	sp["body"] = [
		[-0.62, 0.62, 0.04, 0.04, 0.04, 0.045, 0.04, "pelvis"],
		[-0.57, 0.62, 0.13, 0.15, 0.1, 0.13, 0.09, "pelvis"],
		[-0.47, 0.61, 0.17, 0.2, 0.13, 0.17, 0.12, "pelvis"],
		[-0.3, 0.6, 0.18, 0.24, 0.15, 0.19, 0.15, "pelvis"],
		[-0.1, 0.6, 0.2, 0.27, 0.16, 0.2, 0.16, "root"],
		[0.1, 0.61, 0.23, 0.29, 0.16, 0.2, 0.14, "chest"],
		[0.28, 0.62, 0.26, 0.3, 0.15, 0.19, 0.12, "chest"],
		[0.42, 0.62, 0.24, 0.27, 0.14, 0.17, 0.12, "neck1"],
		[0.52, 0.6, 0.2, 0.22, 0.13, 0.15, 0.11, "neck2"],
		[0.6, 0.58, 0.17, 0.18, 0.11, 0.13, 0.1, "head", "head"],
		[0.7, 0.54, 0.13, 0.14, 0.09, 0.11, 0.085, "head", "head", true],
		[0.8, 0.49, 0.09, 0.1, 0.07, 0.085, 0.07, "head", "head", true],
		[0.9, 0.44, 0.06, 0.065, 0.055, 0.06, 0.05, "head", "snout", true],
		[0.97, 0.41, 0.045, 0.045, 0.045, 0.05, 0.045, "head", "snout", true],
		[1.0, 0.4, 0.045, 0.045, 0.045, 0.05, 0.045, "head", "disc", true],
		[1.005, 0.4, 0.02, 0.02, 0.02, 0.02, 0.02, "head", "disc", true],
	]
	sp["tail"] = {"pts": [Vector3(0, 0.75, -0.6), Vector3(0, 0.68, -0.65), Vector3(0, 0.58, -0.66), Vector3(0, 0.5, -0.65)],
		"prof": [[0, 0.2, 0.02, 0.02, 0.0, "tail"], [1, 0.5, 0.012, 0.012, 0.0, "tail"], [2, 0.6, 0.016, 0.016, 0.0, "tail"], [2, 1.0, 0.006, 0.006, 0.0, "tail"]], "seg": 5}
	sp["legs"] = {
		"f": {"pts": [Vector3(0.1, 0.78, 0.25), Vector3(0.15, 0.52, 0.36), Vector3(0.13, 0.38, 0.24), Vector3(0.12, 0.17, 0.27), Vector3(0.12, 0.05, 0.29), Vector3(0.12, 0.0, 0.35)],
			"prof": [[0, 0.0, 0.04, 0.12, 0.0, "body"], [0, 0.6, 0.08, 0.14, 0.0, "body"], [1, 0.3, 0.1, 0.12, 0.0, "body"], [1, 0.8, 0.08, 0.08, 0.0, "body"],
				[2, 0.2, 0.06, 0.065, 0.0, "leg"], [2, 0.8, 0.035, 0.04, 0.0, "leg"], [3, 0.0, 0.035, 0.036, 0.0, "legl"], [3, 0.8, 0.028, 0.03, 0.0, "legl"]] + _hoof(4, 0.6)},
		"h": {"pts": [Vector3(0.1, 0.78, -0.35), Vector3(0.14, 0.6, -0.48), Vector3(0.14, 0.36, -0.34), Vector3(0.11, 0.2, -0.52), Vector3(0.11, 0.05, -0.48), Vector3(0.11, 0.0, -0.42)],
			"prof": [[0, 0.0, 0.05, 0.12, 0.0, "body"], [0, 0.6, 0.1, 0.16, 0.0, "body"], [1, 0.2, 0.12, 0.17, 0.0, "body"], [1, 0.7, 0.09, 0.11, 0.0, "body"],
				[2, 0.2, 0.06, 0.07, -0.01, "leg"], [2, 0.7, 0.04, 0.045, 0.0, "leg"], [2, 0.95, 0.03, 0.04, -0.01, "legl"], [3, 0.3, 0.027, 0.029, 0.0, "legl"],
				[3, 0.85, 0.027, 0.029, 0.0, "legl"]] + _hoof(4, 0.6)},
	}
	var pieces := [
		["head", Vector3(0.07, 0.72, 0.6), Vector3(0.5, 0.8, 0.2), [[0.0, 0.04, 0.015, 0.0], [0.06, 0.04, 0.012, 0.0], [0.1, 0.006, 0.005, 0.0]], "ear", true],
		["head", Vector3(0.075, 0.63, 0.72), Vector3(0.6, 0.1, 0.8), [[0.0, 0.008, 0.008, 0.0], [0.008, 0.011, 0.01, 0.0], [0.016, 0.002, 0.002, 0.0]], "eye", true],
	]
	if male:
		pieces.append(["head", Vector3(0.04, 0.44, 0.88), Vector3(0.6, 0.6, -0.2), [[0.0, 0.01, 0.012, 0.0], [0.04, 0.007, 0.007, 0.003], [0.07, 0.002, 0.002, 0.01]], "tusk", true])
	sp["pieces"] = pieces
	return sp

## Бурый медведь: горб над лопатками, массивное тело, стопоходящие лапы с длинной ступнёй,
## широкая голова с вогнутым профилем, круглые уши, хвост почти не виден.
static func _sp_bear() -> Dictionary:
	var back := Color(0.4, 0.27, 0.17)
	var pal := {
		"body": {"back": back, "belly": Color(0.3, 0.2, 0.13)}, "leg": {"back": Color(0.28, 0.19, 0.12)}, "paw": {"back": Color(0.2, 0.14, 0.1)},
		"head": {"back": Color(0.44, 0.31, 0.2), "belly": Color(0.34, 0.24, 0.16)}, "face": {"back": Color(0.4, 0.3, 0.21), "belly": Color(0.34, 0.25, 0.17)},
		"nose": {"back": Color(0.08, 0.06, 0.05)}, "ear": {"back": Color(0.32, 0.22, 0.15)}, "eye": {"back": Color(0.03, 0.02, 0.02)}, "tail": {"back": back},
	}
	var sp := {"arun": 0.4, "mat": _an_mat(0.0), "pal": pal, "L": 2.0, "lie_y": 0.36, "graze": [0.8, 0.4], "flex": 0.08, "lie_f": [0.5, -2.0, 0.1]}
	sp["bones"] = {"root": Vector3(0, 0.78, -0.05), "pelvis": Vector3(0, 0.82, -0.55), "chest": Vector3(0, 0.8, 0.3),
		"neck1": Vector3(0, 0.82, 0.5), "neck2": Vector3(0, 0.82, 0.65), "head": Vector3(0, 0.83, 0.76), "jaw": Vector3(0, 0.76, 0.82)}
	sp["body"] = [
		[-0.85, 0.82, 0.05, 0.05, 0.05, 0.06, 0.05, "pelvis"],
		[-0.8, 0.81, 0.17, 0.2, 0.15, 0.18, 0.13, "pelvis"],
		[-0.68, 0.8, 0.22, 0.27, 0.21, 0.25, 0.18, "pelvis"],
		[-0.48, 0.79, 0.23, 0.31, 0.25, 0.3, 0.24, "pelvis"],
		[-0.25, 0.78, 0.24, 0.34, 0.28, 0.33, 0.28, "root"],
		[0.0, 0.79, 0.26, 0.36, 0.29, 0.34, 0.27, "root"],
		[0.22, 0.8, 0.3, 0.37, 0.27, 0.32, 0.22, "chest"],
		[0.4, 0.81, 0.32, 0.36, 0.24, 0.29, 0.2, "chest"],
		[0.55, 0.81, 0.24, 0.3, 0.2, 0.23, 0.17, "neck1"],
		[0.68, 0.82, 0.19, 0.24, 0.17, 0.19, 0.15, "neck2"],
		[0.78, 0.83, 0.16, 0.18, 0.15, 0.17, 0.13, "head", "head"],
		[0.88, 0.82, 0.15, 0.15, 0.14, 0.16, 0.12, "head", "head", true],
		[0.97, 0.79, 0.1, 0.1, 0.09, 0.1, 0.08, "head", "face", true],
		[1.04, 0.76, 0.07, 0.07, 0.065, 0.07, 0.06, "head", "face", true],
		[1.09, 0.745, 0.05, 0.05, 0.045, 0.05, 0.04, "head", "nose", true],
		[1.1, 0.74, 0.02, 0.02, 0.02, 0.02, 0.02, "head", "nose", true],
	]
	sp["tail"] = {"pts": [Vector3(0, 0.9, -0.82), Vector3(0, 0.86, -0.88), Vector3(0, 0.82, -0.9)],
		"prof": [[0, 0.2, 0.04, 0.04, 0.0, "tail"], [1, 1.0, 0.015, 0.015, 0.0, "tail"]], "seg": 6}
	sp["legs"] = {
		"f": {"pts": [Vector3(0.16, 1.05, 0.35), Vector3(0.24, 0.7, 0.48), Vector3(0.22, 0.48, 0.36), Vector3(0.2, 0.12, 0.42), Vector3(0.2, 0.05, 0.44), Vector3(0.2, 0.03, 0.6)],
			"prof": [[0, 0.0, 0.07, 0.18, 0.0, "body"], [0, 0.6, 0.13, 0.2, 0.0, "body"], [1, 0.3, 0.15, 0.18, 0.0, "body"], [1, 0.8, 0.13, 0.14, 0.0, "body"],
				[2, 0.2, 0.12, 0.12, 0.0, "leg"], [2, 0.6, 0.1, 0.1, 0.0, "leg"], [2, 0.95, 0.08, 0.08, 0.0, "leg"], [3, 0.5, 0.085, 0.07, 0.0, "leg"]] + _paw(4, 0.09, 0.035)},
		"h": {"pts": [Vector3(0.15, 1.0, -0.45), Vector3(0.22, 0.8, -0.6), Vector3(0.23, 0.45, -0.45), Vector3(0.2, 0.13, -0.62), Vector3(0.2, 0.05, -0.6), Vector3(0.2, 0.03, -0.38)],
			"prof": [[0, 0.0, 0.08, 0.18, 0.0, "body"], [0, 0.6, 0.16, 0.22, 0.0, "body"], [1, 0.2, 0.18, 0.24, 0.0, "body"], [1, 0.7, 0.15, 0.17, 0.0, "body"],
				[2, 0.2, 0.13, 0.14, 0.0, "leg"], [2, 0.7, 0.1, 0.1, 0.0, "leg"], [3, 0.5, 0.085, 0.08, 0.0, "leg"]] + _paw(4, 0.09, 0.035)},
	}
	sp["pieces"] = [
		["head", Vector3(0.11, 0.97, 0.78), Vector3(0.5, 0.85, 0.1), [[0.0, 0.04, 0.015, 0.0], [0.04, 0.045, 0.015, 0.0], [0.07, 0.01, 0.008, 0.0]], "ear", true],
		["head", Vector3(0.075, 0.88, 0.92), Vector3(0.5, 0.1, 0.85), [[0.0, 0.01, 0.01, 0.0], [0.01, 0.013, 0.012, 0.0], [0.02, 0.003, 0.003, 0.0]], "eye", true],
	]
	return sp

## Амурский тигр: длинное мощное тело, глубокая грудь, поджарый пах, широкие лапы, крупная
## круглая голова с белыми щеками, длинный хвост; полосы — в шейдере.
static func _sp_tiger() -> Dictionary:
	var back := Color(0.86, 0.48, 0.18)
	var belly := Color(0.95, 0.92, 0.86)
	var pal := {
		"body": {"back": back, "belly": belly}, "leg": {"back": back, "belly": back.lerp(belly, 0.5)}, "paw": {"back": back.lerp(belly, 0.4)},
		"head": {"back": back, "belly": belly}, "face": {"back": back.lerp(belly, 0.3), "belly": belly}, "nose": {"back": Color(0.6, 0.35, 0.3), "belly": belly},
		"ear": {"back": Color(0.2, 0.15, 0.12), "belly": belly}, "eye": {"back": Color(0.2, 0.16, 0.05)},
		"tail": {"back": back, "belly": belly, "tip": Color(0.08, 0.06, 0.05), "tip_t": 0.85},
	}
	var sp := {"arun": 0.5, "mat": _an_mat(0.0, 1.0), "pal": pal, "L": 2.0, "lie_y": 0.3, "graze": [0.9, 0.3], "flex": 0.18, "lie_f": [0.5, -2.0, 0.1]}
	sp["bones"] = {"root": Vector3(0, 0.72, -0.05), "pelvis": Vector3(0, 0.78, -0.55), "chest": Vector3(0, 0.73, 0.3),
		"neck1": Vector3(0, 0.76, 0.6), "neck2": Vector3(0, 0.82, 0.72), "head": Vector3(0, 0.86, 0.82), "jaw": Vector3(0, 0.82, 0.88)}
	sp["body"] = [
		[-0.9, 0.82, 0.05, 0.05, 0.05, 0.06, 0.05, "pelvis"],
		[-0.84, 0.81, 0.16, 0.18, 0.13, 0.16, 0.11, "pelvis"],
		[-0.72, 0.79, 0.19, 0.24, 0.17, 0.2, 0.14, "pelvis"],
		[-0.52, 0.76, 0.18, 0.25, 0.18, 0.21, 0.15, "pelvis"],
		[-0.3, 0.73, 0.18, 0.24, 0.18, 0.2, 0.15, "root"],
		[-0.05, 0.72, 0.2, 0.28, 0.19, 0.22, 0.16, "root"],
		[0.18, 0.72, 0.23, 0.32, 0.19, 0.22, 0.14, "chest"],
		[0.38, 0.73, 0.24, 0.32, 0.17, 0.2, 0.11, "chest"],
		[0.55, 0.76, 0.18, 0.24, 0.14, 0.16, 0.11, "chest"],
		[0.66, 0.8, 0.14, 0.17, 0.12, 0.13, 0.11, "neck1"],
		[0.75, 0.84, 0.12, 0.14, 0.11, 0.12, 0.1, "neck2"],
		[0.83, 0.86, 0.12, 0.13, 0.12, 0.14, 0.12, "head", "head"],
		[0.91, 0.86, 0.12, 0.12, 0.13, 0.15, 0.13, "head", "face", true],
		[0.99, 0.84, 0.09, 0.09, 0.1, 0.11, 0.09, "head", "face", true],
		[1.06, 0.82, 0.065, 0.065, 0.07, 0.075, 0.06, "head", "face", true],
		[1.1, 0.81, 0.04, 0.04, 0.04, 0.045, 0.035, "head", "nose", true],
		[1.11, 0.805, 0.015, 0.015, 0.015, 0.015, 0.015, "head", "nose", true],
	]
	sp["tail"] = {"pts": [Vector3(0, 0.88, -0.88), Vector3(0, 0.75, -1.05), Vector3(0, 0.5, -1.2), Vector3(0, 0.32, -1.38)],
		"prof": [[0, 0.1, 0.05, 0.05, 0.0, "tail"], [1, 0.5, 0.04, 0.04, 0.0, "tail"], [2, 0.5, 0.036, 0.036, 0.0, "tail"], [2, 0.9, 0.035, 0.035, 0.0, "tail"], [2, 1.0, 0.015, 0.015, 0.0, "tail"]], "seg": 7}
	sp["legs"] = {
		"f": {"pts": [Vector3(0.13, 1.0, 0.35), Vector3(0.18, 0.68, 0.52), Vector3(0.17, 0.5, 0.36), Vector3(0.15, 0.12, 0.4), Vector3(0.15, 0.05, 0.43), Vector3(0.15, 0.03, 0.58)],
			"prof": [[0, 0.0, 0.06, 0.15, 0.0, "body"], [0, 0.6, 0.11, 0.17, 0.0, "body"], [1, 0.3, 0.13, 0.15, 0.0, "body"], [1, 0.8, 0.11, 0.11, 0.0, "body"],
				[2, 0.15, 0.09, 0.1, 0.0, "leg"], [2, 0.5, 0.08, 0.08, 0.0, "leg"], [2, 0.95, 0.06, 0.06, 0.0, "leg"], [3, 0.5, 0.06, 0.055, 0.0, "leg"]] + _paw(4, 0.08, 0.03)},
		"h": {"pts": [Vector3(0.12, 0.98, -0.5), Vector3(0.17, 0.78, -0.66), Vector3(0.18, 0.5, -0.45), Vector3(0.15, 0.24, -0.72), Vector3(0.15, 0.05, -0.66), Vector3(0.15, 0.03, -0.52)],
			"prof": [[0, 0.0, 0.07, 0.15, 0.0, "body"], [0, 0.6, 0.13, 0.2, 0.0, "body"], [1, 0.2, 0.15, 0.21, 0.0, "body"], [1, 0.7, 0.12, 0.14, 0.0, "body"],
				[2, 0.2, 0.09, 0.11, -0.01, "leg"], [2, 0.6, 0.065, 0.07, 0.0, "leg"], [2, 0.95, 0.05, 0.06, -0.01, "leg"], [3, 0.3, 0.045, 0.045, 0.0, "leg"]] + _paw(4, 0.075, 0.028)},
	}
	sp["pieces"] = [
		["head", Vector3(0.1, 0.96, 0.84), Vector3(0.5, 0.85, 0.0), [[0.0, 0.04, 0.012, 0.0], [0.04, 0.04, 0.012, 0.0], [0.06, 0.008, 0.006, 0.0]], "ear", true],
		["head", Vector3(0.07, 0.91, 0.97), Vector3(0.5, 0.1, 0.85), [[0.0, 0.01, 0.01, 0.0], [0.01, 0.013, 0.012, 0.0], [0.02, 0.003, 0.003, 0.0]], "eye", true],
	]
	return sp

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
