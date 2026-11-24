class_name Valley
extends Node3D
## Туманная Долина: рельеф, лес, скалы, туман, коллизии. Всё строится кодом при запуске, без внешних моделей.
## Высота считается один раз в сетку, дальше везде берётся из сетки (быстро и точно совпадает с мешем).

const HALF := 60.0               # половина размера карты, м
const CELL := 1.25               # шаг сетки рельефа, м
const ARENA := 26.0              # граница поляны, дальше непроходимый лес
const PLAYER_R := 0.42
const HOUSE_POS := Vector3(0.0, 0.0, -15.0)
const START_POS := Vector3(0.0, 0.0, -8.5)
const RING_C := Vector2(0.0, 4.0)
const MAX_SLOPE := 1.15          # круче этого пешком не залезть (около 49 градусов)
const OBST_CELL := 8.0

var N := int(HALF * 2.0 / CELL)
var hgrid := PackedFloat32Array()
var obstacles := {}              # Vector2i -> Array из Vector3(x, z, r)
var focus: Node3D
var wisps: CPUParticles3D
var flies: CPUParticles3D
var rng := RandomNumberGenerator.new()

var mat_terrain: ShaderMaterial
var mat_tree: ShaderMaterial
var mat_grass: ShaderMaterial
var mat_rigid: ShaderMaterial
var mat_glow: ShaderMaterial


# ================================================================ шум и рельеф
func _h(ix: int, iz: int, s: int) -> float:
	var n: int = (ix * 374761393 + iz * 668265263 + s * 1013904223) & 0x7fffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
	n = n ^ (n >> 16)
	return float(n & 0xffff) / 32767.5 - 1.0


func _q(t: float) -> float:
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


func _vn(x: float, z: float, s: int) -> float:
	var ix := floori(x)
	var iz := floori(z)
	var fx := _q(x - float(ix))
	var fz := _q(z - float(iz))
	var a := _h(ix, iz, s)
	var b := _h(ix + 1, iz, s)
	var c := _h(ix, iz + 1, s)
	var d := _h(ix + 1, iz + 1, s)
	return (a * (1.0 - fx) + b * fx) * (1.0 - fz) + (c * (1.0 - fx) + d * fx) * fz


func _fbm(x: float, z: float, s: int, octaves: int) -> float:
	var a := 1.0
	var f := 1.0
	var t := 0.0
	var n := 0.0
	for i in range(octaves):
		t += _vn(x * f + float(i) * 17.3, z * f - float(i) * 9.1, s + i) * a
		n += a
		a *= 0.5
		f *= 2.03
	return t / n


func _blob(x: float, z: float, cx: float, cz: float, rx: float, rz: float, hgt: float) -> float:
	var dx := (x - cx) / rx
	var dz := (z - cz) / rz
	var d := sqrt(dx * dx + dz * dz) + _fbm(x * 0.21, z * 0.21, 51, 2) * 0.16
	var t := 1.0 - smoothstep(0.92, 1.08, d)
	return t * (hgt + _fbm(x * 0.35, z * 0.35, 52, 2) * 0.35)


func _height_raw(x: float, z: float) -> float:
	var r := sqrt(x * x + z * z)
	var dh := sqrt(x * x + (z + 15.0) * (z + 15.0) * 0.7)
	var hill := _fbm(x * 0.03, z * 0.03, 11, 3) * 1.4
	var h := hill * smoothstep(5.0, 12.0, r) * smoothstep(8.0, 14.0, dh)
	h += _blob(x, z, 17.0, -3.0, 6.0, 8.0, 3.4)          # скальный уступ на востоке
	h += _blob(x, z, -17.5, 6.0, 5.5, 6.5, 2.6)          # и на западе
	h += _fbm(x * 0.7, z * 0.7, 61, 2) * 0.10
	var rim := smoothstep(25.0, 50.0, r)
	h += rim * (9.0 + _fbm(x * 0.08, z * 0.08, 71, 2) * 5.0)
	return h


func _compute_grid() -> void:
	hgrid.resize((N + 1) * (N + 1))
	for j in range(N + 1):
		for i in range(N + 1):
			hgrid[j * (N + 1) + i] = _height_raw(-HALF + float(i) * CELL, -HALF + float(j) * CELL)


func _g(i: int, j: int) -> float:
	return hgrid[clampi(j, 0, N) * (N + 1) + clampi(i, 0, N)]


## высота земли в точке: точно по тем же треугольникам, что в меше
func height_at(x: float, z: float) -> float:
	var u := (x + HALF) / CELL
	var v := (z + HALF) / CELL
	var i := clampi(floori(u), 0, N - 1)
	var j := clampi(floori(v), 0, N - 1)
	var fx := clampf(u - float(i), 0.0, 1.0)
	var fz := clampf(v - float(j), 0.0, 1.0)
	var h00 := _g(i, j)
	var h10 := _g(i + 1, j)
	var h01 := _g(i, j + 1)
	var h11 := _g(i + 1, j + 1)
	if (i + j) % 2 == 0:
		if fz >= fx:
			return h00 + (h01 - h00) * fz + (h11 - h01) * fx
		return h00 + (h10 - h00) * fx + (h11 - h10) * fz
	if fx + fz <= 1.0:
		return h00 + (h10 - h00) * fx + (h01 - h00) * fz
	return h11 + (h01 - h11) * (1.0 - fx) + (h10 - h11) * (1.0 - fz)


func normal_at(x: float, z: float) -> Vector3:
	var e := 0.6
	var dx := height_at(x + e, z) - height_at(x - e, z)
	var dz := height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-dx, 2.0 * e, -dz).normalized()


# ================================================================ коллизии
func add_obstacle(x: float, z: float, r: float, top := 99.0) -> void:
	var key := Vector2i(floori(x / OBST_CELL), floori(z / OBST_CELL))
	if not obstacles.has(key):
		obstacles[key] = []
	(obstacles[key] as Array).append(Vector4(x, z, r, height_at(x, z) + top))


## свободна ли точка от препятствий в радиусе rad
func is_free(x: float, z: float, rad: float) -> bool:
	var cx := floori(x / OBST_CELL)
	var cz := floori(z / OBST_CELL)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var key := Vector2i(cx + dx, cz + dz)
			if not obstacles.has(key):
				continue
			for o in (obstacles[key] as Array):
				var ov: Vector4 = o
				var ddx := x - ov.x
				var ddz := z - ov.y
				var rr := ov.z + rad
				if ddx * ddx + ddz * ddz < rr * rr:
					return false
	return true


## выталкивает точку из деревьев, камней, брёвен и стен дома (в прыжке выше препятствия - пролетает над ним)
func push(p: Vector3, pr: float) -> Vector3:
	var cx := floori(p.x / OBST_CELL)
	var cz := floori(p.z / OBST_CELL)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var key := Vector2i(cx + dx, cz + dz)
			if not obstacles.has(key):
				continue
			for o in (obstacles[key] as Array):
				var ov: Vector4 = o
				if p.y > ov.w:
					continue
				var rr := ov.z + pr
				var ddx := p.x - ov.x
				var ddz := p.z - ov.y
				var d2 := ddx * ddx + ddz * ddz
				if d2 < rr * rr:
					if d2 > 1e-8:
						var d := sqrt(d2)
						p.x += ddx / d * (rr - d)
						p.z += ddz / d * (rr - d)
					else:
						p.x += rr
	return p


func _walkable(p: Vector3, q: Vector3, step: float) -> bool:
	if Vector2(q.x, q.z).length() > ARENA:
		return false
	var hq := height_at(q.x, q.z)
	if p.y >= hq - 0.12:
		return true                      # в воздухе выше уступа: можно перелететь
	var hp := height_at(p.x, p.z)
	return (hq - hp) / maxf(step, 0.001) <= MAX_SLOPE


func _step(p: Vector3, d: Vector3) -> Vector3:
	var cands: Array[Vector3] = [d, Vector3(d.x, 0.0, 0.0), Vector3(0.0, 0.0, d.z)]
	for c in cands:
		if c.length_squared() < 1e-10:
			continue
		var q := p + c
		if _walkable(p, q, c.length()):
			return push(q, PLAYER_R)
	return p


## перемещение с учётом отвесных скал, деревьев, камней и границы карты (скользит вдоль препятствий)
func move_xz(from: Vector3, delta: Vector3) -> Vector3:
	var steps := maxi(1, int(ceil(delta.length() / 0.2)))
	var d := delta / float(steps)
	var p := from
	for s in range(steps):
		p = _step(p, d)
	return p


# ================================================================ построитель мешей (плоская заливка, без пластилина)
class MeshBuilder:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()

	func tri(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color, hint: Vector3) -> void:
		var n := (b - a).cross(c - a)
		if n.dot(hint) > 0.0:
			var tv := b
			b = c
			c = tv
			var tc := cb
			cb = cc
			cc = tc
			n = (b - a).cross(c - a)
		if n.length_squared() < 1e-12:
			return
		var out := -n.normalized()
		verts.append(a)
		verts.append(b)
		verts.append(c)
		norms.append(out)
		norms.append(out)
		norms.append(out)
		cols.append(ca)
		cols.append(cb)
		cols.append(cc)

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, hint: Vector3) -> void:
		tri(a, b, c, col, col, col, hint)
		tri(a, c, d, col, col, col, hint)

	func build() -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_COLOR] = cols
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m


# ================================================================ сборка
func build() -> void:
	rng.seed = 4242
	mat_terrain = _shader_mat("res://terrain.gdshader")
	mat_tree = _shader_mat("res://foliage.gdshader")
	mat_tree.set_shader_parameter("sway", 0.45)
	mat_tree.set_shader_parameter("height_ref", 14.0)
	mat_grass = _shader_mat("res://foliage.gdshader")
	mat_grass.set_shader_parameter("sway", 0.14)
	mat_grass.set_shader_parameter("height_ref", 1.0)
	mat_rigid = _shader_mat("res://foliage.gdshader")
	mat_rigid.set_shader_parameter("sway", 0.0)
	mat_glow = _shader_mat("res://glow.gdshader")
	_compute_grid()
	_build_terrain()
	_scatter()
	_build_mountains()
	_build_fx()


func _shader_mat(path: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path)
	return m


func _path_mask(x: float, z: float) -> float:
	var n := _vn(x * 0.3, z * 0.3, 8) * 0.5 + 0.5
	var xc := 1.6 * sin(z * 0.13)
	var d := absf(x - xc)
	var m := 1.0 - smoothstep(0.9 + 0.5 * n, 1.9 + 0.7 * n, d)
	return m * smoothstep(-12.6, -11.0, z) * (1.0 - smoothstep(12.0, 16.0, z))


func _ground_color(p: Vector3, nrm: Vector3) -> Color:
	var r := Vector2(p.x, p.z).length()
	var rock := 1.0 - smoothstep(0.62, 0.82, nrm.y)
	var n1 := _vn(p.x * 0.09, p.z * 0.09, 5) * 0.5 + 0.5
	var n2 := _vn(p.x * 0.31 + 9.0, p.z * 0.31, 6) * 0.5 + 0.5
	var moss := Color(0.050, 0.140, 0.100).lerp(Color(0.085, 0.185, 0.105), n1)
	moss = moss.lerp(Color(0.140, 0.100, 0.065), smoothstep(0.58, 0.82, n2) * 0.75)       # хвойная подстилка
	moss = moss.lerp(Color(0.125, 0.115, 0.205), smoothstep(0.66, 0.92, n1) * 0.45)       # фиолетовый мох
	var ring_d := Vector2(p.x - RING_C.x, p.z - RING_C.y).length()
	moss = moss.lerp(Color(0.185, 0.160, 0.150), (1.0 - smoothstep(7.5, 10.5, ring_d)) * 0.8)   # боевая площадка, утоптанная земля
	moss = moss.lerp(Color(0.210, 0.170, 0.130), _path_mask(p.x, p.z) * 0.9)                    # тропа от дома
	var dh := Vector2(p.x - HOUSE_POS.x, p.z - HOUSE_POS.z).length()
	moss = moss.lerp(Color(0.180, 0.150, 0.125), (1.0 - smoothstep(6.0, 9.5, dh)) * 0.6)       # двор
	moss = moss.lerp(Color(0.040, 0.075, 0.060), smoothstep(21.0, 29.0, r))                    # лесная подстилка темнее
	var stone := Color(0.165, 0.175, 0.230).lerp(Color(0.095, 0.100, 0.150), n2)
	var c := moss.lerp(stone, rock)
	var j := 0.9 + 0.2 * (_h(floori(p.x * 3.1), floori(p.z * 3.1), 3) * 0.5 + 0.5)
	return Color(c.r * j * 1.5, c.g * j * 1.5, c.b * j * 1.5, rock)


func _build_terrain() -> void:
	var mb := MeshBuilder.new()
	var up := Vector3.UP
	for j in range(N):
		for i in range(N):
			var x0 := -HALF + float(i) * CELL
			var z0 := -HALF + float(j) * CELL
			var x1 := x0 + CELL
			var z1 := z0 + CELL
			var p00 := Vector3(x0, _g(i, j), z0)
			var p10 := Vector3(x1, _g(i + 1, j), z0)
			var p01 := Vector3(x0, _g(i, j + 1), z1)
			var p11 := Vector3(x1, _g(i + 1, j + 1), z1)
			var t1: Array[Vector3]
			var t2: Array[Vector3]
			if (i + j) % 2 == 0:
				t1 = [p00, p01, p11]
				t2 = [p00, p11, p10]
			else:
				t1 = [p00, p01, p10]
				t2 = [p10, p01, p11]
			for t in [t1, t2]:
				var a: Vector3 = t[0]
				var b: Vector3 = t[1]
				var c: Vector3 = t[2]
				var nrm := (b - a).cross(c - a)
				if nrm.y < 0.0:
					nrm = -nrm
				nrm = nrm.normalized()
				var col := _ground_color((a + b + c) / 3.0, nrm)
				mb.tri(a, b, c, col, col, col, up)
	var mesh := mb.build()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat_terrain
	add_child(mi)
	# физическое тело для лучей, врагов и снарядов
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shp := ConcavePolygonShape3D.new()
	shp.backface_collision = true
	shp.set_faces(mb.verts)
	cs.shape = shp
	body.add_child(cs)
	add_child(body)


# ================================================================ деревья, камни, трава
func _tree_color(f: float, dark: float) -> Color:
	var base := Color(0.030, 0.080, 0.080)
	var top := Color(0.100, 0.230, 0.170)
	var c := base.lerp(top, f)
	return Color(c.r * dark, c.g * dark, c.b * dark, 1.0)


func _mesh_spruce(tiers: int, base_r: float, height: float, sides: int, trunk_col: Color) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var trunk_h := height * 0.97
	var tr := 0.30
	for k in range(6):
		var a0 := TAU * float(k) / 6.0
		var a1 := TAU * float(k + 1) / 6.0
		var b0 := Vector3(cos(a0) * tr, 0.0, sin(a0) * tr)
		var b1 := Vector3(cos(a1) * tr, 0.0, sin(a1) * tr)
		var t0 := Vector3(cos(a0) * 0.06, trunk_h, sin(a0) * 0.06)
		var t1 := Vector3(cos(a1) * 0.06, trunk_h, sin(a1) * 0.06)
		var mid := Vector3(cos((a0 + a1) * 0.5), 0.0, sin((a0 + a1) * 0.5))
		mb.quad(b0, b1, t1, t0, trunk_col, mid)
	for t in range(tiers):
		var f := float(t) / float(tiers)
		var y0 := height * (0.15 + 0.72 * f)
		var th := height * (0.30 - 0.13 * f)
		var r := base_r * (1.0 - 0.80 * f)
		var ring: Array[Vector3] = []
		for k in range(sides):
			var a := TAU * float(k) / float(sides) + float(t) * 0.45
			var even := k % 2 == 0
			var rr := r * (1.0 if even else 0.66)
			var yy := y0 - (0.0 if even else 0.20 * r)
			ring.append(Vector3(cos(a) * rr, yy, sin(a) * rr))
		var tip := Vector3(0.0, y0 + th, 0.0)
		var under := Vector3(0.0, y0 + th * 0.25, 0.0)
		var cb := _tree_color(f, 0.75)
		var ct := _tree_color(minf(f + 0.45, 1.0), 1.0)
		var cu := _tree_color(f, 0.35)
		for k in range(sides):
			var a_pt: Vector3 = ring[k]
			var b_pt: Vector3 = ring[(k + 1) % sides]
			var mid2 := (a_pt + b_pt) * 0.5
			mb.tri(a_pt, tip, b_pt, cb, ct, cb, Vector3(mid2.x, 0.45 * r, mid2.z))
			mb.tri(a_pt, b_pt, under, cu, cu, cu, Vector3(0.0, -1.0, 0.0))
	return mb.build()


func _mesh_dead(height: float) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var col := Color(0.140, 0.120, 0.120)
	var col2 := Color(0.085, 0.075, 0.090)
	for k in range(5):
		var a0 := TAU * float(k) / 5.0
		var a1 := TAU * float(k + 1) / 5.0
		var b0 := Vector3(cos(a0) * 0.26, 0.0, sin(a0) * 0.26)
		var b1 := Vector3(cos(a1) * 0.26, 0.0, sin(a1) * 0.26)
		var t0 := Vector3(cos(a0) * 0.04 + 0.25, height, sin(a0) * 0.04)
		var t1 := Vector3(cos(a1) * 0.04 + 0.25, height, sin(a1) * 0.04)
		var mid := Vector3(cos((a0 + a1) * 0.5), 0.0, sin((a0 + a1) * 0.5))
		mb.tri(b0, b1, t1, col, col, col2, mid)
		mb.tri(b0, t1, t0, col, col2, col2, mid)
	for k in range(7):
		var yb := height * (0.30 + 0.09 * float(k))
		var ang := float(k) * 2.4
		var dir := Vector3(cos(ang), 0.55, sin(ang)).normalized()
		var base := Vector3(0.25 * (yb / height), yb, 0.0)
		var tipp := base + dir * (1.7 - 0.16 * float(k))
		var side := dir.cross(Vector3.UP).normalized() * 0.07
		mb.tri(base - side, base + side, tipp, col, col, col2, Vector3(dir.x, 0.8, dir.z))
		mb.tri(base + side, base - side, tipp, col, col, col2, Vector3(-dir.x, -0.8, -dir.z))
	return mb.build()


func _ico(sub: int) -> Array:
	var t := (1.0 + sqrt(5.0)) * 0.5
	var v: Array[Vector3] = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	for i in range(v.size()):
		v[i] = v[i].normalized()
	var f: Array = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2],
		[10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11],
		[6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for s in range(sub):
		var nf: Array = []
		for tri in f:
			var a: Vector3 = v[tri[0]]
			var b: Vector3 = v[tri[1]]
			var c: Vector3 = v[tri[2]]
			var ab := (a + b).normalized()
			var bc := (b + c).normalized()
			var ca := (c + a).normalized()
			var ia := v.size()
			v.append(ab)
			v.append(bc)
			v.append(ca)
			nf.append([tri[0], ia, ia + 2])
			nf.append([tri[1], ia + 1, ia])
			nf.append([tri[2], ia + 2, ia + 1])
			nf.append([ia, ia + 1, ia + 2])
		f = nf
	return [v, f]


func _mesh_boulder(seed_v: int) -> ArrayMesh:
	var ico := _ico(1)
	var v: Array = ico[0]
	var f: Array = ico[1]
	var pts: Array[Vector3] = []
	for p in v:
		var pv: Vector3 = p
		var k := 0.78 + 0.34 * (_h(floori(pv.x * 50.0) + seed_v, floori(pv.y * 50.0), floori(pv.z * 50.0) + seed_v) * 0.5 + 0.5)
		pts.append(Vector3(pv.x * k, pv.y * k * 0.72, pv.z * k))
	var mb := MeshBuilder.new()
	for tri in f:
		var a: Vector3 = pts[tri[0]]
		var b: Vector3 = pts[tri[1]]
		var c: Vector3 = pts[tri[2]]
		var cen := (a + b + c) / 3.0
		var nrm := (b - a).cross(c - a)
		var up_amt := absf(nrm.normalized().y)
		var col := Color(0.150, 0.160, 0.215).lerp(Color(0.085, 0.180, 0.130), smoothstep(0.55, 0.9, up_amt) * float(cen.y > 0.0))
		col = col * (0.85 + 0.3 * (_h(floori(cen.x * 40.0), floori(cen.z * 40.0), seed_v) * 0.5 + 0.5))
		col.a = 1.0
		mb.tri(a, b, c, col, col, col, cen)
	return mb.build()


func _mesh_log() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var ln := 6.0
	var r := 0.5
	var sides := 7
	for k in range(sides):
		var a0 := TAU * float(k) / float(sides)
		var a1 := TAU * float(k + 1) / float(sides)
		var p0 := Vector3(-ln * 0.5, sin(a0) * r, cos(a0) * r)
		var p1 := Vector3(-ln * 0.5, sin(a1) * r, cos(a1) * r)
		var q0 := Vector3(ln * 0.5, sin(a0) * r * 0.85, cos(a0) * r * 0.85)
		var q1 := Vector3(ln * 0.5, sin(a1) * r * 0.85, cos(a1) * r * 0.85)
		var mid := Vector3(0.0, sin((a0 + a1) * 0.5), cos((a0 + a1) * 0.5))
		var top := smoothstep(0.2, 1.0, mid.y)
		var col := Color(0.120, 0.085, 0.065).lerp(Color(0.070, 0.170, 0.110), top)
		mb.quad(p0, p1, q1, q0, col, mid)
	return mb.build()


func _mesh_grass() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var cb := Color(0.030, 0.070, 0.070)
	var ct := Color(0.140, 0.300, 0.190)
	for k in range(6):
		var ang := TAU * float(k) / 6.0 + float(k) * 0.4
		var dist := 0.10 + 0.08 * float(k % 3)
		var base := Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)
		var h := 0.26 + 0.14 * float(k % 2) + 0.06 * float(k % 3)
		var lean := Vector3(cos(ang) * 0.10, 0.0, sin(ang) * 0.10)
		var side := Vector3(-sin(ang), 0.0, cos(ang)) * 0.06
		var tp := base + lean + Vector3(0.0, h, 0.0)
		mb.tri(base - side, base + side, tp, cb, cb, ct, Vector3(cos(ang), 0.2, sin(ang)))
		mb.tri(base + side, base - side, tp, cb, cb, ct, Vector3(-cos(ang), 0.2, -sin(ang)))
	return mb.build()


func _mesh_crystal() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var sides := 6
	var rr := 0.13
	var top := Vector3(0.0, 1.0, 0.0)
	var bot := Vector3(0.0, -0.15, 0.0)
	var cc := Color(0.75, 0.55, 1.0)
	var cd := Color(0.35, 0.18, 0.70)
	for k in range(sides):
		var a0 := TAU * float(k) / float(sides)
		var a1 := TAU * float(k + 1) / float(sides)
		var p0 := Vector3(cos(a0) * rr, 0.25, sin(a0) * rr)
		var p1 := Vector3(cos(a1) * rr, 0.25, sin(a1) * rr)
		var mid := Vector3(cos((a0 + a1) * 0.5), 0.3, sin((a0 + a1) * 0.5))
		mb.tri(p0, top, p1, cd, cc, cd, mid)
		mb.tri(p0, p1, bot, cd, cd, cd, Vector3(mid.x, -0.5, mid.z))
	return mb.build()


func _mesh_mushroom() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var sides := 7
	var stem := Color(0.55, 0.50, 0.65)
	var cap := Color(0.60, 1.0, 0.95)
	var cap2 := Color(0.15, 0.55, 0.65)
	var top := Vector3(0.0, 0.32, 0.0)
	for k in range(sides):
		var a0 := TAU * float(k) / float(sides)
		var a1 := TAU * float(k + 1) / float(sides)
		var s0 := Vector3(cos(a0) * 0.03, 0.0, sin(a0) * 0.03)
		var s1 := Vector3(cos(a1) * 0.03, 0.0, sin(a1) * 0.03)
		var s2 := Vector3(cos(a1) * 0.03, 0.2, sin(a1) * 0.03)
		var s3 := Vector3(cos(a0) * 0.03, 0.2, sin(a0) * 0.03)
		var mid := Vector3(cos((a0 + a1) * 0.5), 0.0, sin((a0 + a1) * 0.5))
		mb.quad(s0, s1, s2, s3, stem, mid)
		var c0 := Vector3(cos(a0) * 0.16, 0.18, sin(a0) * 0.16)
		var c1 := Vector3(cos(a1) * 0.16, 0.18, sin(a1) * 0.16)
		mb.tri(c0, top, c1, cap2, cap, cap2, Vector3(mid.x, 0.5, mid.z))
		mb.tri(c0, c1, Vector3(0.0, 0.2, 0.0), cap2, cap2, cap2, Vector3(0.0, -1.0, 0.0))
	return mb.build()


func _monolith() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var sides := 5
	var col := Color(0.120, 0.125, 0.170)
	var col2 := Color(0.075, 0.075, 0.115)
	for k in range(sides):
		var a0 := TAU * float(k) / float(sides) + 0.3
		var a1 := TAU * float(k + 1) / float(sides) + 0.3
		var b0 := Vector3(cos(a0) * 0.62, -0.3, sin(a0) * 0.62)
		var b1 := Vector3(cos(a1) * 0.62, -0.3, sin(a1) * 0.62)
		var t0 := Vector3(cos(a0) * 0.36 + 0.12, 3.3, sin(a0) * 0.36)
		var t1 := Vector3(cos(a1) * 0.36 + 0.12, 3.3, sin(a1) * 0.36)
		var mid := Vector3(cos((a0 + a1) * 0.5), 0.0, sin((a0 + a1) * 0.5))
		mb.tri(b0, b1, t1, col2, col2, col, mid)
		mb.tri(b0, t1, t0, col2, col, col, mid)
		mb.tri(t0, t1, Vector3(0.12, 3.5, 0.0), col, col, col, Vector3(0.0, 1.0, 0.0))
	return mb.build()


func _mm(mesh: Mesh, mat: Material, xf: Array, custom: Array, shadow: bool) -> void:
	if xf.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for i in range(xf.size()):
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_custom_data(i, custom[i])
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)


func _tint(lo: float, hi: float) -> Color:
	return Color(rng.randf_range(lo, hi), rng.randf_range(lo, hi), rng.randf_range(lo, hi), 1.0)


func _scatter() -> void:
	var meshes: Array[ArrayMesh] = [
		_mesh_spruce(8, 1.7, 14.0, 9, Color(0.080, 0.060, 0.055)),
		_mesh_spruce(5, 2.5, 9.0, 10, Color(0.090, 0.065, 0.055)),
		_mesh_dead(10.0),
		_mesh_spruce(4, 1.3, 4.6, 8, Color(0.080, 0.060, 0.055))]
	var txf: Array = [[], [], [], []]
	var tcu: Array = [[], [], [], []]

	# --- 1) круг древних камней (боевая площадка), дом строится отдельно
	var house := House.new()
	add_child(house)
	house.build(self, Vector3(HOUSE_POS.x, height_at(HOUSE_POS.x, HOUSE_POS.z), HOUSE_POS.z))
	var sxf: Array = []
	var scu: Array = []
	var rxf: Array = []
	var rcu: Array = []
	for k in range(8):
		var a := TAU * float(k) / 8.0 + 0.2
		var x := RING_C.x + cos(a) * 10.0
		var z := RING_C.y + sin(a) * 10.0
		var s := rng.randf_range(0.85, 1.15)
		var bs := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3(1, 0, 0), rng.randf_range(-0.05, 0.05))
		bs = bs.scaled(Vector3(s, s, s))
		var y := height_at(x, z)
		sxf.append(Transform3D(bs, Vector3(x, y, z)))
		scu.append(_tint(0.9, 1.1))
		add_obstacle(x, z, 0.72 * s, 3.4 * s)
		rxf.append(Transform3D(Basis(Vector3.UP, a).scaled(Vector3(1.5, 1.5, 1.5)), Vector3(x + 0.12, y + 3.45 * s, z)))
		rcu.append(Color(0.75, 0.35, 1.0, 1.0))
	_mm(_monolith(), mat_rigid, sxf, scu, true)

	# --- 2) валуны: группами у уступов и по краям поляны
	var bm: Array[ArrayMesh] = [_mesh_boulder(1), _mesh_boulder(2), _mesh_boulder(3)]
	var bxf: Array = [[], [], []]
	var bcu: Array = [[], [], []]
	var centers: Array[Vector2] = [Vector2(12.0, -9.0), Vector2(12.5, 5.0), Vector2(-12.5, 0.0), Vector2(-12.0, 12.5), Vector2(6.0, 18.0), Vector2(-7.0, 19.0),
		Vector2(20.0, 10.0), Vector2(-20.0, -8.0), Vector2(8.0, -21.0), Vector2(-9.0, -22.0)]
	for cc in centers:
		for q in range(rng.randi_range(3, 5)):
			var x := cc.x + rng.randf_range(-3.0, 3.0)
			var z := cc.y + rng.randf_range(-3.0, 3.0)
			if Vector2(x, z).length() > ARENA - 1.0 or Vector2(x - START_POS.x, z - START_POS.z).length() < 4.5 or _path_mask(x, z) > 0.3:
				continue
			if not is_free(x, z, 1.4):
				continue
			var s := rng.randf_range(0.8, 2.0) if rng.randf() < 0.8 else rng.randf_range(2.0, 3.0)
			var k := rng.randi() % 3
			var bs := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.15), s))
			(bxf[k] as Array).append(Transform3D(bs, Vector3(x, height_at(x, z) + 0.12 * s, z)))
			(bcu[k] as Array).append(_tint(0.85, 1.15))
			add_obstacle(x, z, 1.02 * s, 1.5 * s)
	for i in range(3):
		_mm(bm[i], mat_rigid, bxf[i], bcu[i], true)

	# --- 3) поваленные брёвна у кромки леса
	var lxf: Array = []
	var lcu: Array = []
	var tries := 0
	while lxf.size() < 8 and tries < 400:
		tries += 1
		var a := rng.randf() * TAU
		var rr := rng.randf_range(19.0, 24.0)
		var x := cos(a) * rr
		var z := sin(a) * rr
		if normal_at(x, z).y < 0.95 or not is_free(x, z, 3.2):
			continue
		var s := rng.randf_range(0.8, 1.2)
		var yaw := rng.randf() * TAU
		var bs := Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s))
		lxf.append(Transform3D(bs, Vector3(x, height_at(x, z) + 0.32 * s, z)))
		lcu.append(_tint(0.85, 1.15))
		var dir := Vector3(cos(yaw), 0.0, -sin(yaw))
		for q in range(-3, 4):
			add_obstacle(x + dir.x * float(q) * 0.9 * s, z + dir.z * float(q) * 0.9 * s, 0.6 * s, 0.9 * s)
	_mm(_mesh_log(), mat_rigid, lxf, lcu, true)

	# --- 4) деревья: несколько у дома, а за краем поляны плотная непроходимая стена леса
	var fixed: Array[Vector3] = [Vector3(-9.5, -12.0, 0), Vector3(9.5, -13.5, 1), Vector3(-11.5, -19.0, 0), Vector3(11.0, -20.0, 0), Vector3(-4.5, -22.5, 1), Vector3(5.5, -23.0, 0), Vector3(-18.0, -15.0, 0), Vector3(18.5, -16.0, 1)]
	var cand: Array[Vector3] = []
	for f in fixed:
		cand.append(f)
	var gx := -52.0
	while gx < 52.0:
		var gz := -52.0
		while gz < 52.0:
			var x := gx + rng.randf_range(-1.0, 1.0)
			var z := gz + rng.randf_range(-1.0, 1.0)
			gz += 2.5
			var r := sqrt(x * x + z * z)
			if r < 22.0 or r > 52.0:
				continue
			var p := smoothstep(22.0, 27.0, r) * 0.97
			if rng.randf() > p:
				continue
			cand.append(Vector3(x, z, -1))
		gx += 2.5
	for c in cand:
		var x := c.x
		var z := c.y
		if c.z >= 0.0:
			x = c.x
			z = c.y
		var r2 := sqrt(x * x + z * z)
		if r2 < 22.0 and c.z < 0.0:
			continue
		if not is_free(x, z, 1.5):
			continue
		if r2 < 27.0 and normal_at(x, z).y < 0.93:
			continue                                # на поляне не ставим деревья на склоны и в скалы
		var u := rng.randf()
		var sp := 0 if u < 0.45 else (1 if u < 0.72 else (3 if u < 0.93 else 2))
		var s := rng.randf_range(0.85, 1.35)
		var bs := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3(1, 0, 0), rng.randf_range(-0.05, 0.05))
		bs = bs.scaled(Vector3(s, s * rng.randf_range(0.9, 1.2), s))
		(txf[sp] as Array).append(Transform3D(bs, Vector3(x, height_at(x, z) - 0.2, z)))
		(tcu[sp] as Array).append(_tint(0.82, 1.18))
		add_obstacle(x, z, 0.48 * s, 99.0)
	for i in range(4):
		_mm(meshes[i], mat_tree, txf[i], tcu[i], false)

	# --- 5) трава: невысокая, пятнами, не на тропе и не на площадке
	var gxf: Array = []
	var gcu: Array = []
	tries = 0
	while gxf.size() < 750 and tries < 9000:
		tries += 1
		var x := rng.randf_range(-ARENA, ARENA)
		var z := rng.randf_range(-ARENA, ARENA)
		if Vector2(x, z).length() > ARENA - 1.0 or normal_at(x, z).y < 0.9:
			continue
		if _vn(x * 0.12, z * 0.12, 13) < 0.0 or _path_mask(x, z) > 0.15:
			continue
		if Vector2(x - RING_C.x, z - RING_C.y).length() < 8.5 or not is_free(x, z, 0.2):
			continue
		var s := rng.randf_range(0.6, 1.1)
		var bs := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s))
		gxf.append(Transform3D(bs, Vector3(x, height_at(x, z) - 0.02, z)))
		var warm := rng.randf()
		gcu.append(Color(0.8 + 0.5 * warm, 0.9 + 0.2 * rng.randf(), 0.8 + 0.3 * (1.0 - warm), 1.0))
	_mm(_mesh_grass(), mat_grass, gxf, gcu, false)

	# --- 6) светящиеся грибы у кромки леса и камней, кристаллы на скалах
	var mxf: Array = []
	var mcu: Array = []
	var cols: Array[Color] = [Color(0.25, 1.0, 0.95), Color(0.75, 0.35, 1.0), Color(0.95, 0.40, 0.85)]
	tries = 0
	while mxf.size() < 70 and tries < 3000:
		tries += 1
		var a := rng.randf() * TAU
		var rr := rng.randf_range(15.0, 25.0)
		var cx := cos(a) * rr
		var cz := sin(a) * rr
		if normal_at(cx, cz).y < 0.9 or _path_mask(cx, cz) > 0.1:
			continue
		var cc2: Color = cols[rng.randi() % 3]
		for q in range(rng.randi_range(2, 5)):
			var x := cx + rng.randf_range(-0.9, 0.9)
			var z := cz + rng.randf_range(-0.9, 0.9)
			if not is_free(x, z, 0.1):
				continue
			var s := rng.randf_range(0.7, 1.6)
			mxf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(x, height_at(x, z) - 0.02, z)))
			mcu.append(Color(cc2.r, cc2.g, cc2.b, 1.0))
	_mm(_mesh_mushroom(), mat_glow, mxf, mcu, false)
	var kxf: Array = rxf.duplicate()
	var kcu: Array = rcu.duplicate()
	tries = 0
	var shards := 0
	while shards < 40 and tries < 6000:
		tries += 1
		var x := rng.randf_range(-ARENA, ARENA)
		var z := rng.randf_range(-ARENA, ARENA)
		var nrm := normal_at(x, z)
		if nrm.y > 0.55 or Vector2(x, z).length() > ARENA - 1.0 or Vector2(x, z).length() < 9.0:
			continue
		var cc3: Color = cols[1] if rng.randf() < 0.65 else cols[0]
		for q in range(rng.randi_range(2, 3)):
			var s := rng.randf_range(0.5, 1.3)
			var dir := (nrm + Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(0.0, 0.7), rng.randf_range(-0.5, 0.5))).normalized()
			var bs := Basis(Quaternion(Vector3.UP, dir)).scaled(Vector3(s, s, s))
			kxf.append(Transform3D(bs, Vector3(x + rng.randf_range(-0.4, 0.4), height_at(x, z) + 0.05, z + rng.randf_range(-0.4, 0.4))))
			kcu.append(Color(cc3.r, cc3.g, cc3.b, 1.0))
		shards += 1
	_mm(_mesh_crystal(), mat_glow, kxf, kcu, false)


# ================================================================ далёкие горы
func _build_mountains() -> void:
	var mb := MeshBuilder.new()
	for k in range(26):
		var a := TAU * float(k) / 26.0 + rng.randf_range(-0.08, 0.08)
		var dist := rng.randf_range(120.0, 170.0)
		var w := rng.randf_range(32.0, 60.0)
		var h := rng.randf_range(45.0, 95.0)
		var cx := cos(a) * dist
		var cz := sin(a) * dist
		var sides := 7
		var ring: Array[Vector3] = []
		for q in range(sides):
			var aa := TAU * float(q) / float(sides)
			var rr := w * rng.randf_range(0.75, 1.1)
			ring.append(Vector3(cx + cos(aa) * rr, -10.0, cz + sin(aa) * rr))
		var tip := Vector3(cx + rng.randf_range(-6.0, 6.0), h, cz + rng.randf_range(-6.0, 6.0))
		var cb := Color(0.055, 0.060, 0.100)
		var ct := Color(0.140, 0.150, 0.240)
		for q in range(sides):
			var pa: Vector3 = ring[q]
			var pb: Vector3 = ring[(q + 1) % sides]
			var mid := (pa + pb) * 0.5
			var shade := 0.8 + 0.4 * rng.randf()
			mb.tri(pa, tip, pb, cb * shade, ct * shade, cb * shade, Vector3(mid.x - cx, 0.4, mid.z - cz))
	var mi := MeshInstance3D.new()
	mi.mesh = mb.build()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ================================================================ атмосфера и частицы
func setup_atmosphere(we: WorldEnvironment, sun: DirectionalLight3D) -> void:
	var env := we.environment
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.050, 0.070, 0.170)
	sky_mat.sky_horizon_color = Color(0.300, 0.300, 0.470)
	sky_mat.sky_curve = 0.22
	sky_mat.ground_horizon_color = Color(0.300, 0.300, 0.470)
	sky_mat.ground_bottom_color = Color(0.080, 0.090, 0.160)
	sky_mat.sun_angle_max = 25.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.340, 0.380, 0.560)
	env.ambient_light_energy = 0.85
	env.fog_enabled = true
	env.fog_light_color = Color(0.300, 0.340, 0.500)
	env.fog_density = 0.016
	env.fog_sky_affect = 0.55
	env.fog_height = 5.0
	env.fog_height_density = 0.05
	sun.rotation_degrees = Vector3(-32.0, -50.0, 0.0)
	sun.light_color = Color(0.80, 0.82, 1.0)
	sun.light_energy = 1.05
	sun.directional_shadow_max_distance = 40.0


func _build_fx() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	wisps = CPUParticles3D.new()
	wisps.amount = 70
	wisps.lifetime = 16.0
	wisps.preprocess = 16.0
	wisps.local_coords = false
	wisps.mesh = quad
	wisps.material_override = _shader_mat("res://mist.gdshader")
	wisps.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	wisps.emission_box_extents = Vector3(34.0, 1.6, 34.0)
	wisps.direction = Vector3(1.0, 0.0, 0.3)
	wisps.spread = 20.0
	wisps.initial_velocity_min = 0.25
	wisps.initial_velocity_max = 0.7
	wisps.gravity = Vector3.ZERO
	wisps.scale_amount_min = 9.0
	wisps.scale_amount_max = 17.0
	wisps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var g1 := Gradient.new()
	g1.offsets = PackedFloat32Array([0.0, 0.25, 0.75, 1.0])
	g1.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	wisps.color_ramp = g1
	add_child(wisps)
	flies = CPUParticles3D.new()
	flies.amount = 55
	flies.lifetime = 7.0
	flies.preprocess = 7.0
	flies.local_coords = false
	flies.mesh = quad
	flies.material_override = _shader_mat("res://fly.gdshader")
	flies.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	flies.emission_box_extents = Vector3(16.0, 2.2, 16.0)
	flies.direction = Vector3(0.0, 1.0, 0.0)
	flies.spread = 180.0
	flies.initial_velocity_min = 0.15
	flies.initial_velocity_max = 0.55
	flies.gravity = Vector3.ZERO
	flies.linear_accel_min = -0.2
	flies.linear_accel_max = 0.2
	flies.scale_amount_min = 0.07
	flies.scale_amount_max = 0.13
	flies.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var g2 := Gradient.new()
	g2.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	g2.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	flies.color_ramp = g2
	add_child(flies)


func _process(_delta: float) -> void:
	if focus == null:
		return
	var p := focus.global_position
	if wisps != null:
		wisps.global_position = Vector3(p.x, p.y + 1.4, p.z)
	if flies != null:
		flies.global_position = Vector3(p.x, p.y + 1.6, p.z)
