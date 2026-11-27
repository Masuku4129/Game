extends RefCounted
## Живописная растительность: кроны — округлые «облака» с мягкими нормалями (как пятна краски),
## ель — ярусы зубчатых юбок, камни — гранёные глыбы, трава — кочки из широких мазков.
## Деревья в 300–900 треугольников вместо 3–11 тысяч.

var rng := RandomNumberGenerator.new()
var mats := {}
var fade_list: Array = []
var _ico: Array = []
var _ico0: Array = []
## Лёгкая дальняя версия: без мазков-карточек, грубые облака.
var lod := false

func _init() -> void:
	_ico = _icosphere()
	_ico0 = _ico_base
	var fol := load("res://shaders/paint/foliage.gdshader")
	var brk := load("res://shaders/paint/bark.gdshader")
	for f in [
		["spruce", Color(0.10, 0.22, 0.13), Color(0.29, 0.46, 0.25), Color(0.50, 0.66, 0.37), 0.0],
		["pine", Color(0.12, 0.24, 0.13), Color(0.33, 0.51, 0.26), Color(0.57, 0.72, 0.40), 0.35],
		["birch", Color(0.12, 0.23, 0.09), Color(0.34, 0.48, 0.16), Color(0.69, 0.78, 0.31), 1.0],
		["leaf", Color(0.11, 0.22, 0.045), Color(0.29, 0.46, 0.09), Color(0.66, 0.76, 0.22), 1.0],
		["bush", Color(0.045, 0.12, 0.035), Color(0.19, 0.34, 0.085), Color(0.47, 0.63, 0.18), 0.8],
		["larch", Color(0.20, 0.29, 0.08), Color(0.48, 0.60, 0.18), Color(0.84, 0.82, 0.36), 1.0],
		["fir", Color(0.06, 0.14, 0.10), Color(0.18, 0.32, 0.18), Color(0.39, 0.55, 0.29), 0.0],
		["cedar", Color(0.07, 0.15, 0.08), Color(0.2, 0.35, 0.16), Color(0.42, 0.59, 0.29), 0.0],
		["willow", Color(0.13, 0.2, 0.09), Color(0.35, 0.48, 0.22), Color(0.69, 0.75, 0.44), 0.9],
		["rowan", Color(0.13, 0.18, 0.055), Color(0.39, 0.48, 0.12), Color(0.76, 0.75, 0.24), 1.0],
		["juniper", Color(0.08, 0.15, 0.11), Color(0.2, 0.32, 0.22), Color(0.42, 0.52, 0.34), 0.0],
		["fern", Color(0.1, 0.2, 0.08), Color(0.25, 0.42, 0.14), Color(0.5, 0.62, 0.22), 1.0],
		["berry", Color(0.3, 0.03, 0.04), Color(0.6, 0.08, 0.08), Color(0.85, 0.25, 0.2), 0.0],
		["cap_red", Color(0.45, 0.06, 0.04), Color(0.72, 0.14, 0.08), Color(0.9, 0.35, 0.2), 0.0],
		["cap_brown", Color(0.25, 0.14, 0.07), Color(0.45, 0.28, 0.14), Color(0.62, 0.45, 0.26), 0.0],
		["anthill", Color(0.18, 0.12, 0.07), Color(0.34, 0.24, 0.14), Color(0.5, 0.38, 0.22), 0.0],
		["alder", Color(0.055, 0.13, 0.045), Color(0.24, 0.38, 0.095), Color(0.56, 0.68, 0.2), 0.9],
		["rose", Color(0.1, 0.18, 0.08), Color(0.24, 0.36, 0.14), Color(0.48, 0.56, 0.24), 0.9],
		["cherry", Color(0.09, 0.16, 0.055), Color(0.31, 0.43, 0.11), Color(0.62, 0.72, 0.22), 1.0],
		["bilberry", Color(0.06, 0.14, 0.08), Color(0.14, 0.27, 0.13), Color(0.3, 0.42, 0.2), 0.6],
		["moss", Color(0.18, 0.26, 0.08), Color(0.38, 0.48, 0.14), Color(0.6, 0.66, 0.26), 0.3],
		["fireweed", Color(0.38, 0.08, 0.24), Color(0.68, 0.22, 0.46), Color(0.88, 0.5, 0.7), 0.0],
		["horsetail", Color(0.1, 0.2, 0.08), Color(0.24, 0.4, 0.14), Color(0.46, 0.58, 0.24), 0.5],
		["lichen", Color(0.4, 0.42, 0.32), Color(0.62, 0.64, 0.5), Color(0.8, 0.8, 0.66), 0.0],
		["raspberry", Color(0.09, 0.18, 0.08), Color(0.24, 0.38, 0.15), Color(0.5, 0.6, 0.27), 0.9],
		["currant", Color(0.07, 0.16, 0.07), Color(0.2, 0.34, 0.13), Color(0.42, 0.54, 0.22), 0.9],
		["ledum", Color(0.08, 0.13, 0.07), Color(0.18, 0.26, 0.13), Color(0.36, 0.42, 0.24), 0.2],
		["ernik", Color(0.12, 0.17, 0.07), Color(0.3, 0.38, 0.14), Color(0.55, 0.58, 0.24), 1.0],
		["sphag", Color(0.3, 0.12, 0.08), Color(0.55, 0.3, 0.16), Color(0.7, 0.55, 0.3), 0.0],
		["yagel", Color(0.5, 0.52, 0.44), Color(0.72, 0.74, 0.64), Color(0.88, 0.88, 0.8), 0.0],
		["white", Color(0.6, 0.6, 0.56), Color(0.86, 0.86, 0.82), Color(0.98, 0.98, 0.95), 0.0],
		["blue", Color(0.16, 0.2, 0.45), Color(0.32, 0.38, 0.72), Color(0.55, 0.6, 0.9), 0.0],
		["orange", Color(0.5, 0.25, 0.04), Color(0.82, 0.5, 0.12), Color(0.95, 0.72, 0.3), 0.0],
		["bracket", Color(0.3, 0.22, 0.14), Color(0.55, 0.44, 0.3), Color(0.76, 0.68, 0.52), 0.0],
		["cones", Color(0.22, 0.13, 0.07), Color(0.4, 0.26, 0.15), Color(0.56, 0.4, 0.24), 0.0],
	]:
		var m := ShaderMaterial.new()
		m.shader = fol
		m.set_shader_parameter("col_dark", f[1])
		m.set_shader_parameter("col_mid", f[2])
		m.set_shader_parameter("col_light", f[3])
		m.set_shader_parameter("autumn_k", f[4])
		mats[f[0]] = m
	for b in [["cut", Color(0.78, 0.64, 0.44), Color(0.6, 0.46, 0.3), 0.0], ["stem", Color(0.9, 0.86, 0.76), Color(0.75, 0.7, 0.6), 0.0], ["log", Color(0.42, 0.34, 0.26), Color(0.24, 0.19, 0.15), 0.0], ["bark", Color(0.36, 0.27, 0.2), Color(0.2, 0.15, 0.11), 0.0], ["bark_pine", Color(0.52, 0.36, 0.24), Color(0.32, 0.22, 0.16), 0.0], ["bark_birch", Color(0.9, 0.88, 0.82), Color(0.72, 0.7, 0.66), 1.0], ["bark_dead", Color(0.48, 0.44, 0.38), Color(0.3, 0.27, 0.24), 0.0], ["bark_aspen", Color(0.66, 0.67, 0.6), Color(0.44, 0.45, 0.4), 0.0], ["burnt", Color(0.16, 0.14, 0.13), Color(0.07, 0.06, 0.06), 0.0], ["roots", Color(0.36, 0.27, 0.18), Color(0.2, 0.14, 0.09), 0.0]]:
		var m := ShaderMaterial.new()
		m.shader = brk
		m.set_shader_parameter("col", b[1])
		m.set_shader_parameter("col2", b[2])
		m.set_shader_parameter("birch", b[3])
		# брёвна, пни, срезы и грибы не растворяются перед камерой
		m.set_shader_parameter("no_fade", b[0] in ["cut", "stem", "log"])
		mats[b[0]] = m
	var rk := ShaderMaterial.new()
	rk.shader = load("res://shaders/paint/rock.gdshader")
	mats["rock"] = rk
	var rd := ShaderMaterial.new()
	rd.shader = load("res://shaders/paint/grasscard.gdshader")
	rd.set_shader_parameter("col_root", Color(0.22, 0.28, 0.12))
	rd.set_shader_parameter("col_tip", Color(0.62, 0.6, 0.32))
	mats["reed"] = rd
	var tf := ShaderMaterial.new()
	tf.shader = load("res://shaders/paint/grasscard.gdshader")
	tf.set_shader_parameter("strokes_tex", _grass_tex())
	mats["tuft"] = tf
	# мазки листвы: те же цвета, что у сплошных крон
	var bt := _brush_tex()
	var lc := load("res://shaders/paint/leafcard.gdshader")
	for k in ["spruce", "pine", "birch", "leaf", "bush", "larch", "fern", "fir", "cedar", "willow", "rowan", "juniper", "alder", "rose", "cherry", "raspberry", "currant", "ernik", "bilberry", "ledum", "moss"]:
		var m := ShaderMaterial.new()
		m.shader = lc
		m.set_shader_parameter("brush", bt)
		for p in ["col_dark", "col_mid", "col_light", "autumn_k"]:
			m.set_shader_parameter(p, mats[k].get_shader_parameter(p))
		mats[k + "_card"] = m
	# черёмуха: белый цвет только поздней весной (blossom), летом зелёная, осенью багряная
	for k in ["cherry", "cherry_card"]:
		mats[k].set_shader_parameter("bloom_k", 1.0)
		mats[k].set_shader_parameter("col_autumn", Color(0.75, 0.28, 0.16))
	# лиственница желтеет ровно, без багрянца
	for k in ["larch", "larch_card"]:
		mats[k].set_shader_parameter("autumn_red", 0.0)

	rd.set_shader_parameter("strokes_tex", _grass_tex())
	for k in mats.keys():
		if k != "tuft":
			fade_list.append(mats[k])

## Текстура мазка листвы: десяток листьев-эллипсов в круге, рваный край, g — оттенок.
func _brush_tex() -> Texture2D:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := RandomNumberGenerator.new()
	r.seed = 77
	for i in 18:
		var a := r.randf() * TAU
		var d := sqrt(r.randf()) * 0.3
		var cx := 0.5 + cos(a) * d
		var cy := 0.5 + sin(a) * d
		var ang := r.randf() * PI
		var la := r.randf_range(0.1, 0.17)
		var lb := la * r.randf_range(0.4, 0.6)
		var g := clampf(0.55 - (cy - 0.5) * 1.2 + r.randf_range(-0.2, 0.2), 0.0, 1.0)
		var ca := cos(ang)
		var sa := sin(ang)
		for y in range(maxi(0, int((cy - la) * n)), mini(n, int((cy + la) * n) + 1)):
			for x in range(maxi(0, int((cx - la) * n)), mini(n, int((cx + la) * n) + 1)):
				var dx := float(x) / n - cx
				var dy := float(y) / n - cy
				var u := (dx * ca + dy * sa) / la
				var v := (-dx * sa + dy * ca) / lb
				if u * u + v * v < 1.0:
					img.set_pixel(x, y, Color(0, g, 0, 1))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## Текстура пучка травы: вертикальные сужающиеся мазки от низа.
func _grass_tex() -> Texture2D:
	var w := 64
	var h := 96
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := RandomNumberGenerator.new()
	r.seed = 91
	for i in 16:
		var x0 := r.randf_range(0.12, 0.88)
		var bend := r.randf_range(-0.25, 0.25)
		var top := r.randf_range(0.05, 0.5)
		var wd := r.randf_range(0.03, 0.06)
		var g := r.randf()
		for y in h:
			var t := float(y) / h
			if t < top:
				continue
			var k := (1.0 - t) / (1.0 - top)
			var cx := x0 + bend * k * k
			var half := wd * (1.0 - k) + 0.004
			for x in range(maxi(0, int((cx - half) * w)), mini(w, int((cx + half) * w) + 1)):
				img.set_pixel(x, y, Color(0, g, 0, 1))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## Облако из мазков: сплошное ядро + карточки-мазки по поверхности (рваный край).
func leafblob(core: SurfaceTool, cards: SurfaceTool, c: Vector3, sc: Vector3, shade: float) -> void:
	if cards == null:
		blob(core, c, sc * 0.92, shade * 0.8)
		return
	blob(core, c, sc * 0.58, shade * 0.48)
	var verts: Array = _ico[0]
	var sz := (sc.x + sc.y + sc.z) / 3.0 * 0.78
	for p in verts:
		var q: Vector3 = p
		var pos := c + Vector3(q.x * sc.x, q.y * sc.y * (0.7 if q.y < 0 else 1.0), q.z * sc.z) * CR(0.85, 1.0)
		var nrm := (q + Vector3(0, 0.35, 0)).normalized()
		var rot := CR(0, TAU)
		var sh := clampf(shade + CR(-0.2, 0.2), 0.0, 1.0)
		var s2 := sz * CR(0.48, 0.86)
		for corner in [[0, 0], [1, 0], [1, 1], [0, 0], [1, 1], [0, 1]]:
			cards.set_color(Color(sh, 0, 0, 1))
			cards.set_normal(nrm)
			cards.set_uv(Vector2(corner[0], corner[1]))
			cards.set_uv2(Vector2(s2, rot))
			cards.add_vertex(pos)

var crng := RandomNumberGenerator.new()
func CR(a: float, b: float) -> float:
	return crng.randf_range(a, b)

func R(a: float, b: float) -> float:
	return rng.randf_range(a, b)

var _ico_base: Array = []
## Икосфера 1-го уровня: 42 вершины, 80 граней.
func _icosphere() -> Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v: Array = [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	for i in v.size():
		v[i] = v[i].normalized()
	var f: Array = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	_ico_base = [v.duplicate(), f]
	var mid := {}
	var out: Array = []
	for tri in f:
		var m: Array = []
		for e in [[tri[0], tri[1]], [tri[1], tri[2]], [tri[2], tri[0]]]:
			var key := Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))
			if not mid.has(key):
				v.append(((v[e[0]] + v[e[1]]) * 0.5).normalized())
				mid[key] = v.size() - 1
			m.append(mid[key])
		out.append([tri[0], m[0], m[2]])
		out.append([tri[1], m[1], m[0]])
		out.append([tri[2], m[2], m[1]])
		out.append([m[0], m[1], m[2]])
	return [v, out]

## Пятно кроны: 2–3 сросшихся облака дают неровный «живописный» край.
var cards: SurfaceTool = null

func clump(st: SurfaceTool, c: Vector3, sc: Vector3, shade: float) -> void:
	# Многослойная органичная крона: ядро, внутренние крупные листовые массы,
	# и асимметричный внешний контур без одинаковых сферических шаров.
	leafblob(st, cards, c, sc * Vector3(0.88, 0.78, 0.88), shade * 0.88)
	var lobes := rng.randi_range(5, 7)
	var phase := R(-0.45, 0.45)
	for i in lobes:
		var a := TAU * float(i) / float(lobes) + phase + R(-0.24, 0.24)
		var radial := R(0.38, 0.78)
		var o := Vector3(cos(a) * radial, R(-0.22, 0.32), sin(a) * radial) * sc
		var sat := Vector3(R(0.42, 0.72), R(0.34, 0.62), R(0.42, 0.72))
		leafblob(st, cards, c + o, sc * sat, clampf(shade + R(-0.22, 0.22), 0.0, 1.0))
		# Небольшие вложенные подушки сглаживают переход между ядром и краем.
		if i % 2 == 0:
			var inner := o * R(0.42, 0.68) + Vector3(0, R(-0.08, 0.12), 0)
			leafblob(st, cards, c + inner, sc * sat * R(0.48, 0.62), clampf(shade + R(-0.12, 0.16), 0.0, 1.0))

