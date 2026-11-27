extends Node3D
const RP := preload("res://scripts/river_path.gd")
## Бобровые колонии на реке. Плотина из брёвен, веток и ила поднимает воду перед собой
## и опускает после; хатка ниже по течению. Бобр-работник валит прибрежные деревья
## (лиственные — в первую очередь): подгрызает ствол «песочными часами», дерево падает
## с треском, отскакивает от земли; ствол разгрызается на чурки, их носят на плотину — она растёт.
## Уровень воды: water_level() в main.gd = WATER_Y + level_off(); на воде — полоса со своим уровнем.

const AM = preload("res://scripts/animal_model.gd")
const RISE := 0.8          # подъём воды перед полной плотиной
const DROP := 0.45         # спад после неё
const UP_LEN := 55.0       # длина пруда вверх по течению
const DOWN_LEN := 35.0     # длина обмелевшего участка ниже
const HALF_W := 30.0       # полуширина зоны от оси реки
const NOTCH_Y := 0.42      # высота надгрыза в координатах модели дерева
const NOTCH_H := 0.13
const TRUNK_R := 0.165     # радиус ствола (pveg.birch) на высоте надгрыза
const GNAW_T := 16.0
const LOGS := 3
const STEP := 0.05         # прирост плотины за чурку
const STICKS := 1500
const BOW := 1.2           # плотина выгнута против течения
const LODGE_STICKS := 50
# породы: лиственные — в первую очередь, хвойные — если рядом больше нечего (штраф к расстоянию)
const TREE_KEYS := {"birch": 0.0, "aspen": 0.0, "rowan": 0.0, "larch": 8.0, "spruce": 14.0, "fir": 14.0, "pine": 18.0, "cedar": 18.0}
const BARK_COL := {"birch": Color(0.86, 0.84, 0.78), "aspen": Color(0.6, 0.62, 0.55), "rowan": Color(0.42, 0.37, 0.32), "larch": Color(0.47, 0.33, 0.22),
	"spruce": Color(0.36, 0.27, 0.2), "fir": Color(0.36, 0.27, 0.2), "pine": Color(0.52, 0.36, 0.24), "cedar": Color(0.36, 0.27, 0.2)}
# радиус ствола у надгрыза (pveg: берёза 0.17, ель 0.24, сосна 0.28 у земли)
const TRUNK_RS := {"spruce": 0.225, "fir": 0.225, "pine": 0.26, "cedar": 0.26}
const WOOD := Color(0.93, 0.78, 0.52)
const LOGS_MAX := 48
# ветки: кора (серо-бурая, тёмная, серая, рыжеватая) и ошкуренные бобром — светлые
const STICK_BARK := [Color(0.46, 0.4, 0.33), Color(0.34, 0.29, 0.23), Color(0.55, 0.52, 0.46), Color(0.5, 0.38, 0.28), Color(0.42, 0.37, 0.31), Color(0.6, 0.57, 0.5)]
const STICK_PEEL := [Color(0.82, 0.74, 0.58), Color(0.74, 0.65, 0.5), Color(0.66, 0.59, 0.47)]
const MUD_STICK := Color(0.3, 0.25, 0.19)

const STICK_SHADER := """
shader_type spatial;
render_mode cull_disabled;
#include "res://shaders/paint/paint.gdshaderinc"
// ветка: цвет экземпляра (кора или ошкуренная древесина), продольные волокна, снег сверху
uniform float snow = 0.0;
varying vec3 wn;
void vertex() {
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	float s = vnoise(vec2(UV.x * 5.0, UV.y * 9.0)) * 0.6 + vnoise(vec2(UV.x * 13.0, UV.y * 26.0)) * 0.4;
	vec3 c = lin(COLOR.rgb) * mix(0.7, 1.15, s);
	c = mix(c, vec3(0.9, 0.93, 0.97), smoothstep(0.6, 0.9, wn.y) * snow);
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
"""

const SPILL_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;
// вода переливается через низкие места гребня: белые струйки бегут вниз по низовому откосу
uniform float ice = 0.0;
float h21(vec2 p) {
	p = mod(p, 1024.0);
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	float edge = smoothstep(0.0, 0.3, UV.x) * smoothstep(1.0, 0.7, UV.x);
	float n = vn(vec2(UV.x * 7.0, UV.y * 2.5 - TIME * 2.4)) * 0.6 + vn(vec2(UV.x * 17.0, UV.y * 6.0 - TIME * 3.3)) * 0.4;
	float a = smoothstep(0.3, 0.72, n) * edge * COLOR.a * (1.0 - ice);
	ALBEDO = vec3(0.9, 0.95, 0.96);
	ALPHA = a * 0.85;
}
"""

var main: Node3D
var colonies: Array = []
var strip_mat: ShaderMaterial
var mud_mat: ShaderMaterial
var stick_mesh: CylinderMesh
var stick_mat: ShaderMaterial
var spill_mat: ShaderMaterial
var chips: CPUParticles3D
var rng := RandomNumberGenerator.new()
var _sync_t := 0.0
## Проверка кадрами: BEAVER_SHOTS=папка — снять работу бобров у первой колонии и выйти.
var _shot_dir := OS.get_environment("BEAVER_SHOTS")
var _shot_f := 0
var _shot_done := {}

func setup(start: Vector3) -> void:
	rng.seed = int(main.get("map_seed")) + 3131
	mud_mat = AM.material({})
	stick_mesh = CylinderMesh.new()
	stick_mesh.top_radius = 0.045
	stick_mesh.bottom_radius = 0.06
	stick_mesh.height = 1.0
	stick_mesh.radial_segments = 5
	stick_mesh.rings = 1
	stick_mesh.cap_top = false
	stick_mesh.cap_bottom = false
	var ssh := Shader.new()
	ssh.code = STICK_SHADER
	stick_mat = ShaderMaterial.new()
	stick_mat.shader = ssh
	stick_mesh.material = stick_mat
	var psh := Shader.new()
	psh.code = SPILL_SHADER
	spill_mat = ShaderMaterial.new()
	spill_mat.shader = psh
	strip_mat = main.water_mat.duplicate()
	strip_mat.set_shader_parameter("strip", 1.0)
	for m: ShaderMaterial in [strip_mat, main.water_mat]:
		m.set_shader_parameter("up_len", UP_LEN)
		m.set_shader_parameter("down_len", DOWN_LEN)
		m.set_shader_parameter("half_w", HALF_W)
	# первая колония — в двух десятках метров ниже старта, остальные — вдоль реки
	var xs: Array[float] = [start.x + 22.0]
	for cand: float in [start.x - 92.0, start.x + 122.0, start.x - 206.0, start.x + 232.0]:
		if xs.size() < 4 and absf(cand) < 212.0:
			xs.append(cand)
	for x in xs:
		_colony(x, colonies.size() == 0)
	_push_levels()
	chips = CPUParticles3D.new()
	chips.amount = 16
	chips.lifetime = 0.9
	chips.emitting = false
	var cm := BoxMesh.new()
	cm.size = Vector3(0.03, 0.006, 0.022)
	var chm := StandardMaterial3D.new()
	chm.albedo_color = WOOD
	chm.roughness = 1.0
	cm.material = chm
	chips.mesh = cm
	chips.direction = Vector3(0, 1, 0)
	chips.spread = 70.0
	chips.initial_velocity_min = 0.5
	chips.initial_velocity_max = 1.3
	chips.gravity = Vector3(0, -7, 0)
	chips.angular_velocity_min = -300.0
	chips.angular_velocity_max = 300.0
	chips.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(chips)

## Смещение уровня воды от плотин в точке (м).
func level_off(x: float, z: float) -> float:
	var o := 0.0
	for c: Dictionary in colonies:
		var cp: Vector3 = c["c"]
		var t: Vector3 = c["t"]
		var u := (x - cp.x) * t.x + (z - cp.z) * t.z
		if u <= -UP_LEN or u >= DOWN_LEN:
			continue
		var rd: float = main.river_dist(x, z)
		if rd >= HALF_W:
			continue
		var pr: float = c["prog"]
		var lat := 1.0 - smoothstep(HALF_W - 6.0, HALF_W, rd)
		if u < 0.0:
			o += RISE * pr * smoothstep(-UP_LEN, -UP_LEN * 0.35, u) * lat
		else:
			o -= DROP * pr * (1.0 - smoothstep(2.0, DOWN_LEN, u)) * lat
	return o

func _push_levels() -> void:
	var a := PackedVector4Array()
	var b := PackedVector4Array()
	for i in 4:
		if i < colonies.size():
			var c: Dictionary = colonies[i]
			var cp: Vector3 = c["c"]
			var t: Vector3 = c["t"]
			var pr: float = c["prog"]
			a.append(Vector4(cp.x, cp.z, RISE * pr, DROP * pr))
			b.append(Vector4(t.x, t.z, 1.0, 0.0))
		else:
			a.append(Vector4.ZERO)
			b.append(Vector4.ZERO)
	for m: ShaderMaterial in [strip_mat, main.water_mat]:
		m.set_shader_parameter("dams", a)
		m.set_shader_parameter("dams_t", b)

## Колония: створ плотины поперёк реки, полоса воды, хатка ниже по течению, деревья для работы.
func _colony(x: float, first: bool) -> void:
	var zc: float = RP.zc(x, main.map_seed)
	var t := Vector3(1.0, 0.0, RP.dzc(x, main.map_seed)).normalized()
	var across := Vector3(-t.z, 0.0, t.x)
	var cp := Vector3(x, 0.0, zc)
	var crest_full: float = main.WATER_Y + RISE + 0.25
	var ends: Array[Vector3] = []
	for sd: float in [-1.0, 1.0]:
		var d := 2.0
		while d < 30.0:
			var p := cp + across * d * sd
			if main.height(p.x, p.z) > crest_full + 0.15:
				break
			d += 0.5
		ends.append(cp + across * (d + 1.5) * sd)
	var c := {"c": cp, "t": t, "across": across, "a": ends[0], "b": ends[1], "prog": 0.45 if not first else 0.55,
		"phase": "rest", "tm": 4.0 if first else rng.randf_range(10.0, 30.0), "beavers": [], "stumps": [], "logs": [], "fell": {},
		"goal": Vector3.ZERO, "next": "", "go_t": 0.0, "felled": 0, "snd_t": 0.0, "mud_dirty": false}
	# хатка: ниже по течению у кромки воды, наполовину на берегу
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	var lc := cp + t * 17.0
	var low: float = main.WATER_Y - DROP
	var d2 := 2.0
	while d2 < 25.0:
		var q := lc + across * d2 * side
		if main.height(q.x, q.z) > low - 0.6:
			break
		d2 += 0.5
	var lp := lc + across * (d2 - 0.6) * side
	var gmin := minf(main.height(lp.x, lp.z), low - 0.5)
	lp.y = gmin
	c["lodge"] = lp
	c["lodge_top"] = low + 1.25
	# подводный лаз: у основания хатки со стороны русла (бобр ныряет здесь и пропадает внутри)
	c["door"] = lp - across * side * 2.6
	# низкие места гребня, где переливается вода; неровность гребня — своя у каждой плотины
	var nn: Array = []
	for k in rng.randi_range(3, 4):
		nn.append([rng.randf_range(0.18, 0.82), rng.randf_range(0.025, 0.05)])
	c["notches"] = nn
	c["seed"] = rng.randf() * 100.0
	main._add_solid([0, Vector3(lp.x, gmin, lp.z), Vector3.ZERO, 1.6, c["lodge_top"] - gmin])
	# проход по гребню плотины: четыре отрезка по дуге
	var sl: Array = []
	for k in 4:
		var sd := [1, _dam_pt(c, k / 4.0), _dam_pt(c, (k + 1) / 4.0), 1.2, 0.0]
		main._add_solid(sd)
		sl.append(sd)
	c["solids"] = sl
	_update_solid(c)
	_make_strip(c)
	_make_sticks(c)
	_find_trees(c)
	var mi := MeshInstance3D.new()
	mi.material_override = mud_mat
	mi.visibility_range_end = 140.0
	add_child(mi)
	c["mud"] = mi
	_rebuild_mud(c)
	colonies.append(c)

func _crest(prog: float) -> float:
	return main.WATER_Y + RISE * prog + 0.25

## Точка на оси плотины (s = 0..1 от берега до берега), с выгибом против течения.
func _dam_pt(c: Dictionary, s: float) -> Vector3:
	var a: Vector3 = c["a"]
	var b: Vector3 = c["b"]
	var t: Vector3 = c["t"]
	return a.lerp(b, s) - t * sin(s * PI) * BOW

func _update_solid(c: Dictionary) -> void:
	var y := _crest(c["prog"]) - 1.2
	for k in 4:
		var sd: Array = c["solids"][k]
		var p0 := _dam_pt(c, k / 4.0)
		var p1 := _dam_pt(c, (k + 1) / 4.0)
		sd[1] = Vector3(p0.x, y, p0.z)
		sd[2] = Vector3(p1.x, y, p1.z)

## Полоса воды у плотины: ряды вершин поперёк реки, ряд у створа — уровень меняется ступенькой.
func _make_strip(c: Dictionary) -> void:
	var cp: Vector3 = c["c"]
	var t: Vector3 = c["t"]
	var across: Vector3 = c["across"]
	var us: Array[float] = []
	var u := -UP_LEN - 6.0
	while u < -4.0:
		us.append(u)
		u += 4.0
	us.append_array([-3.0, -1.5, -0.3, 0.3, 1.5, 3.0])
	u = 6.0
	while u < DOWN_LEN + 6.0:
		us.append(u)
		u += 4.0
	us.append(DOWN_LEN + 6.0)
	var vs: Array[float] = []
	var v := -HALF_W - 16.0
	while v <= HALF_W + 16.0:
		vs.append(v)
		v += 4.0
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for uu in us:
		# поперечные ряды вдоль оси реки: центр ряда — на русле
		var p0 := cp + t * uu
		var zc: float = RP.zc(p0.x, main.map_seed)
		for vv in vs:
			var p := Vector3(p0.x, 0.0, zc) + across * vv
			verts.append(p)
	var nv := vs.size()
	for i in us.size() - 1:
		for j in nv - 1:
			var k := i * nv + j
			idx.append_array([k, k + 1, k + nv, k + 1, k + nv + 1, k + nv])
	var nr := PackedVector3Array()
	nr.resize(verts.size())
	nr.fill(Vector3.UP)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = nr
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, strip_mat)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position.y = main.WATER_Y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bb := m.get_aabb()
	mi.custom_aabb = AABB(bb.position - Vector3(0, 1.5, 0), bb.size + Vector3(0, 3.0, 0))
	add_child(mi)

static func _stick_xf(p: Vector3, dir: Vector3, r: float, len: float) -> Transform3D:
	var yb := dir.normalized()
	var xb := yb.cross(Vector3.UP if absf(yb.y) < 0.9 else Vector3.RIGHT).normalized()
	var zb := xb.cross(yb)
	return Transform3D(Basis(xb * r, yb * len, zb * r), p)

## Гребень плотины в точке s (0..1 от берега до берега) при постройке pr: неровный, с низкими
## местами, через которые переливается вода (там гребень чуть ниже воды в пруду).
func _crest_at(c: Dictionary, s: float, pr: float) -> float:
	var sd: float = c["seed"]
	var y := _crest(pr) + sin(s * 37.0 + sd) * 0.05 + sin(s * 13.0 + sd * 1.7) * 0.06 + sin(s * 83.0 + sd * 0.3) * 0.03
	var pond: float = main.WATER_Y + RISE * pr
	for nt: Array in c["notches"]:
		var k := 1.0 - smoothstep(0.0, float(nt[1]), absf(s - float(nt[0])))
		y = lerpf(y, pond - 0.04, k)
	return y

## Поперечный профиль (u — вниз по течению): верховой откос пологий, из ила;
## гребень узкий; низовой откос круче — его закрывают ветки.
const DAM_PROF := [[-3.0, -9.0], [-2.1, -0.78], [-1.2, -0.36], [-0.5, -0.09], [0.0, 0.0], [0.35, -0.05], [0.9, -0.38], [1.5, -0.85], [2.2, -9.0]]

func _dam_surf(c: Dictionary, s: float, u: float, pr: float) -> float:
	var p := _dam_pt(c, s)
	var g: float = main.height(p.x, p.z) - 0.4
	var cr := _crest_at(c, s, pr)
	for j in DAM_PROF.size() - 1:
		var a: Array = DAM_PROF[j]
		var b: Array = DAM_PROF[j + 1]
		if u <= float(b[0]) or j == DAM_PROF.size() - 2:
			var k := clampf((u - float(a[0])) / (float(b[0]) - float(a[0])), 0.0, 1.0)
			var ya: float = g if float(a[1]) < -5.0 else cr + float(a[1])
			var yb: float = g if float(b[1]) < -5.0 else cr + float(b[1])
			return maxf(lerpf(ya, yb, k), g)
	return g

## Ветки и жерди: сначала хатка (видна всегда), потом плотина по слоям — видно столько, сколько построено.
## Плотина: переплетённые ветки под разными углами (часть ошкурена — светлая), на низовом откосе
## торчат комлями вниз по течению, на гребне — вверх; с верховой стороны — утоплены в ил.
func _make_sticks(c: Dictionary) -> void:
	var xs: Array[Transform3D] = []
	var cols: Array[Color] = []
	var lp: Vector3 = c["lodge"]
	var top: float = c["lodge_top"]
	var hh := top - lp.y
	for i in LODGE_STICKS:
		var a := rng.randf() * TAU
		var e := rng.randf_range(0.05, 1.25)
		var n := Vector3(cos(a) * cos(e), sin(e), sin(a) * cos(e))
		var p := Vector3(lp.x, lp.y, lp.z) + Vector3(n.x * 1.65, n.y * hh, n.z * 1.65)
		var tang := n.cross(Vector3.UP if absf(n.y) < 0.95 else Vector3.RIGHT).normalized()
		tang = tang.rotated(n.normalized(), rng.randf_range(-1.2, 1.2))
		var dir := (tang + n * rng.randf_range(-0.1, 0.35)).normalized()
		xs.append(_stick_xf(p, dir, rng.randf_range(0.6, 1.3), rng.randf_range(0.9, 1.9)))
		cols.append(_stick_col(0.25))
	var a0: Vector3 = c["a"]
	var b0: Vector3 = c["b"]
	var t: Vector3 = c["t"]
	var along := (b0 - a0).normalized()
	# слои плотины: порядок = порядок постройки
	var prs: Array[float] = []
	c["stick_pr"] = prs
	for i in STICKS:
		# первые слои — гуще: недостроенная плотина уже вся в ветках
		var pr := 0.2 + 0.8 * pow(float(i) / STICKS, 1.5)
		var s := rng.randf_range(0.03, 0.97)
		var z := rng.randf()
		var u: float
		var dir: Vector3
		var col: Color
		var sink := 0.0
		if z < 0.45:
			# низовой откос: ветки лежат по склону, комлями вниз по течению, веером
			u = rng.randf_range(0.05, 1.55)
			var el := rng.randf_range(-0.55, 0.3)
			dir = (t * cos(el) + Vector3.UP * sin(el)).rotated(Vector3.UP, rng.randf_range(-1.0, 1.0)).normalized()
			col = _stick_col(0.12)
		elif z < 0.75:
			# тело и гребень: переплетены вдоль плотины, наискось
			u = rng.randf_range(-0.35, 0.6)
			dir = (along.rotated(Vector3.UP, rng.randf_range(-0.8, 0.8)) + Vector3.UP * rng.randf_range(-0.4, 0.4)).normalized()
			col = _stick_col(0.1)
			sink = rng.randf_range(0.0, 0.12)
		elif z < 0.9:
			# торчат из гребня круто вверх
			u = rng.randf_range(-0.2, 0.9)
			dir = (Vector3.UP * rng.randf_range(0.6, 1.3) + t * rng.randf_range(0.1, 0.8) + along * rng.randf_range(-0.6, 0.6)).normalized()
			col = _stick_col(0.2)
		else:
			# верховой откос: утоплены в ил
			u = rng.randf_range(-1.7, -0.3)
			dir = (along.rotated(Vector3.UP, rng.randf_range(-1.2, 1.2)) + Vector3.UP * rng.randf_range(-0.15, 0.15)).normalized()
			col = MUD_STICK.lerp(_stick_col(0.1), rng.randf_range(0.0, 0.5))
			sink = 0.04
		var p := _dam_pt(c, s) + t * u
		var g: float = main.height(p.x, p.z)
		var y := _dam_surf(c, s, u, pr) + 0.03 - sink
		if y < g - 0.15:
			continue
		p.y = y
		var ln := rng.randf_range(0.6, 2.1)
		# ветка лежит на откосе: середина приподнята по направлению ветки
		p += dir * ln * 0.15 * rng.randf_range(-1.0, 1.0)
		xs.append(_stick_xf(p, dir, rng.randf_range(0.6, 1.6), ln))
		cols.append(col)
		prs.append(pr)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = stick_mesh
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
		mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.visibility_range_end = 120.0
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	c["sticks"] = mm
	_show_sticks(c)
	# чурки, принесённые бобрами: толще веток, кладутся поперёк гребня (свои с начала — по прогрессу)
	var lm := MultiMesh.new()
	lm.transform_format = MultiMesh.TRANSFORM_3D
	lm.use_colors = true
	lm.mesh = stick_mesh
	lm.instance_count = LOGS_MAX
	lm.visible_instance_count = 0
	var lmi := MultiMeshInstance3D.new()
	lmi.multimesh = lm
	lmi.visibility_range_end = 120.0
	lmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lmi)
	c["dam_logs"] = lm
	for k in int(float(c["prog"]) / STEP * 0.4):
		_add_dam_log(c, rng.randf_range(0.15, 0.85), STICK_BARK[rng.randi() % STICK_BARK.size()])

func _stick_col(peel: float) -> Color:
	if rng.randf() < peel:
		return STICK_PEEL[rng.randi() % STICK_PEEL.size()]
	var b: Color = STICK_BARK[rng.randi() % STICK_BARK.size()]
	return b.darkened(rng.randf_range(0.0, 0.15))

## Принесённая чурка ложится на гребень (чуть наискось, ошкуренная — светлее коры).
func _add_dam_log(c: Dictionary, s: float, bark: Color) -> void:
	var lm: MultiMesh = c["dam_logs"]
	var n := lm.visible_instance_count
	if n >= LOGS_MAX:
		n = rng.randi() % LOGS_MAX
	else:
		lm.visible_instance_count = n + 1
	var t: Vector3 = c["t"]
	var a0: Vector3 = c["a"]
	var b0: Vector3 = c["b"]
	var along := (b0 - a0).normalized()
	var u := rng.randf_range(-0.2, 0.7)
	var p := _dam_pt(c, s) + t * u
	p.y = _dam_surf(c, s, u, float(c["prog"])) + 0.05
	var dir := (along.rotated(Vector3.UP, rng.randf_range(-0.7, 0.7)) + Vector3.UP * rng.randf_range(-0.2, 0.25)).normalized()
	lm.set_instance_transform(n, _stick_xf(p, dir, rng.randf_range(1.8, 2.6), rng.randf_range(0.7, 0.95)))
	lm.set_instance_color(n, bark.lerp(WOOD, rng.randf_range(0.2, 0.6)))

func _show_sticks(c: Dictionary) -> void:
	var n := LODGE_STICKS
	var prs: Array = c.get("stick_pr", [])
	var pr: float = c["prog"]
	for p: float in prs:
		if p <= pr + 0.001:
			n += 1
	var mm: MultiMesh = c["sticks"]
	mm.visible_instance_count = mini(n, mm.instance_count)

## Деревья для работы: берёза, осина, рябина, лиственница у воды, ближе к плотине — раньше.
func _find_trees(c: Dictionary) -> void:
	var cp: Vector3 = c["c"]
	var found: Array = []
	var g0 := Vector2i(floori((cp.x - 52.0) / 16.0), floori((cp.z - 52.0) / 16.0))
	for gz in range(g0.y, g0.y + 8):
		for gx in range(g0.x, g0.x + 8):
			var gk := Vector2i(gx, gz)
			if not main.tree_grid.has(gk):
				continue
			for rec: Array in main.tree_grid[gk]:
				var key: String = rec[3]
				var kind := key.rstrip("0123456789")
				if not TREE_KEYS.has(kind):
					continue
				var xf: Transform3D = rec[2]
				var o := xf.origin
				var d := Vector2(o.x - cp.x, o.z - cp.z).length()
				if d > 50.0 or main.river_dist(o.x, o.z) > 26.0 or main.normal_at(o.x, o.z).y < 0.86 or main.cliff_k(o.x, o.z) > 0.3:
					continue
				found.append([d + float(TREE_KEYS[kind]), rec])
	found.sort_custom(func(p: Array, q: Array) -> bool: return float(p[0]) < float(q[0]))
	var trees: Array = []
	for f: Array in found:
		if trees.size() < 10:
			trees.append(f[1])
	c["trees"] = trees

# ---------- ил и пни: одна сетка на колонию ----------

func _rebuild_mud(c: Dictionary) -> void:
	var b := AM.MB.new()
	var a0: Vector3 = c["a"]
	var b0: Vector3 = c["b"]
	var t: Vector3 = c["t"]
	var pr: float = c["prog"]
	var pond: float = main.WATER_Y + RISE * pr
	var len := a0.distance_to(b0)
	var n := int(len / 0.35) + 1
	var us: Array[float] = [-3.0, -2.5, -2.1, -1.6, -1.2, -0.8, -0.5, -0.25, 0.0, 0.18, 0.35, 0.6, 0.9, 1.2, 1.5, 1.85, 2.2]
	var base := b.v.size()
	var mud_wet := Color(0.22, 0.18, 0.14)
	var mud_dry := Color(0.4, 0.35, 0.28)
	var twig_c := Color(0.5, 0.44, 0.35)
	for i in n + 1:
		var s := float(i) / n
		var p := _dam_pt(c, s)
		var g: float = main.height(p.x, p.z) - 0.4
		for j in us.size():
			var u: float = us[j]
			var sl := s * len
			var y := _dam_surf(c, s, u, pr)
			# комья ила и выпирающие ветки: мелкие бугры
			if y > g + 0.05:
				y += sin(sl * 5.1 + u * 3.3) * 0.05 + sin(sl * 2.3 - u * 4.1) * 0.05 + sin(sl * 11.7 + u * 7.0) * 0.03
			var q := p + t * (u + sin(sl * 1.3 + float(j)) * 0.08)
			b.v.append(Vector3(q.x, y, q.z))
			# верховой откос: мокрый блестящий ил у воды, выше — подсохший; гребень и низ — в ветках
			var wet := clampf((pond + 0.12 - y) * 3.0, 0.0, 1.0) if u < 0.0 else 0.55
			var twig := (0.25 + 0.3 * sin(sl * 1.9 + float(j) * 2.9) + 0.2 * sin(sl * 6.3 - float(j) * 1.3)) * smoothstep(-0.6, 0.2, u)
			b.c.append(mud_dry.lerp(mud_wet, wet).lerp(twig_c, clampf(twig, 0.0, 1.0)))
			b.uv.append(Vector2(sl * 0.6, u * 0.6))
	var np := us.size()
	for i in n:
		for j in np - 1:
			var k := base + i * np + j
			b.idx.append_array([k, k + 1, k + np, k + 1, k + np + 1, k + np])
	_rebuild_spill(c)
	var mud_dry2 := Color(0.33, 0.29, 0.23)
	# хатка: приплюснутый купол из ила с бугорками
	var lp: Vector3 = c["lodge"]
	var top: float = c["lodge_top"]
	var hh := top - lp.y
	var rings: Array = []
	for i in 7:
		var e := PI * 0.5 * float(i) / 6.0
		rings.append([sin(e) * hh, cos(e) * 1.7, mud_dry2.lerp(Color(0.3, 0.24, 0.17), float(i) / 6.0)])
	b.lathe(rings, 14, Transform3D(Basis(), lp), true)
	# пни с надгрызом и россыпью щепы
	for st: Array in c["stumps"]:
		_stump_geo(b, st[0], 1.0, st[1], true, st[2])
	c["mud"].mesh = b.commit()

## Перелив: в низких местах гребня белые струйки сбегают по низовому откосу и расходятся пеной.
func _rebuild_spill(c: Dictionary) -> void:
	if not c.has("spill"):
		var mi := MeshInstance3D.new()
		mi.material_override = spill_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 90.0
		add_child(mi)
		c["spill"] = mi
	var pr: float = c["prog"]
	var lowy: float = main.WATER_Y - DROP * pr
	var a0: Vector3 = c["a"]
	var b0: Vector3 = c["b"]
	var t: Vector3 = c["t"]
	var along := (b0 - a0).normalized()
	var len := a0.distance_to(b0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nv := 0
	for nt: Array in c["notches"]:
		var s0: float = nt[0]
		var w0: float = maxf(0.3, len * float(nt[1]) * 0.9)
		var pts: Array[Vector3] = []
		var ws: Array[float] = []
		var u := -0.4
		var on_water := 0.0
		while u < 3.6 and on_water < 1.2:
			var p := _dam_pt(c, s0) + t * u
			var y := _dam_surf(c, s0, u, pr)
			if y <= lowy + 0.01 and u > 0.3:
				y = lowy
				on_water += 0.2
			p.y = y + 0.035
			pts.append(p)
			ws.append(w0 * (0.75 + 0.35 * sin(u * 3.0 + s0 * 20.0)) * (1.0 + on_water * 1.4))
			u += 0.2
		var dist := 0.0
		for k in pts.size():
			if k > 0:
				dist += pts[k].distance_to(pts[k - 1])
			var a := clampf((float(k) + 0.5) / 2.0, 0.0, 1.0) * clampf((float(pts.size() - 1 - k)) / 3.0, 0.0, 1.0)
			for sd in 2:
				st.set_color(Color(1, 1, 1, a))
				st.set_uv(Vector2(float(sd), dist))
				st.add_vertex(pts[k] + along * ws[k] * (float(sd) - 0.5))
			if k > 0:
				var i0 := nv + (k - 1) * 2
				st.add_index(i0)
				st.add_index(i0 + 1)
				st.add_index(i0 + 2)
				st.add_index(i0 + 1)
				st.add_index(i0 + 3)
				st.add_index(i0 + 2)
		nv += pts.size() * 2
	var mi2: MeshInstance3D = c["spill"]
	if nv > 0:
		mi2.mesh = st.commit()
	else:
		mi2.mesh = null

## Пень (координаты модели дерева): кора до надгрыза, светлый конус «песочных часов», щепа вокруг.
func _stump_geo(b: AM.MB, xf: Transform3D, k: float, bark: Color, chips_ring: bool, tr: float) -> void:
	var rm := tr * (1.0 - 0.85 * k)
	b.lathe([[-0.2, tr * 1.15, bark], [0.0, tr * 1.05, bark], [NOTCH_Y - NOTCH_H, tr, bark],
		[NOTCH_Y - NOTCH_H * 0.5, lerpf(tr, rm, 0.6), WOOD.darkened(0.1)], [NOTCH_Y, rm, WOOD]], 8, xf, true)
	if chips_ring:
		var o := xf.origin
		var s := xf.basis.get_scale().x
		for i in 14:
			var a := float(i) * 2.4
			var r := (0.25 + fmod(float(i) * 0.37, 0.45)) * s
			var p := o + Vector3(cos(a) * r, 0.0, sin(a) * r)
			p.y = main.height(p.x, p.z) + 0.02
			var d := Vector3(cos(a * 3.0), 0, sin(a * 3.0)) * 0.035
			b.tri(p - d, p + d.rotated(Vector3.UP, 1.7), p + d.rotated(Vector3.UP, -1.6), WOOD.darkened(fmod(float(i) * 0.13, 0.3)))

# ---------- работа бобров ----------

## Работник колонии: живой и не в хатке (прежний — пока может); работник днём в хатку не уходит.
func _worker(c: Dictionary) -> Node3D:
	var w: Node3D = c.get("w", null)
	if w == null or w.dead or w.state in ["inlodge", "dive_in"]:
		w = null
		for b: Node3D in c["beavers"]:
			if not b.dead and not (b.state in ["inlodge", "dive_in"]):
				w = b
				break
		c["w"] = w
	for b: Node3D in c["beavers"]:
		b.lodge_ok = b != w
	return w

func _send(w: Node3D, p: Vector3) -> void:
	w.job_p = p
	w.arrived = false
	w.gnaw_low = false
	w.state = "job"

func _go(c: Dictionary, p: Vector3, next: String) -> void:
	c["goal"] = p
	c["next"] = next
	c["phase"] = "go"
	c["go_t"] = 0.0
	var w := _worker(c)
	if w != null:
		_send(w, p)

func _calm(w: Node3D) -> bool:
	return w.state in ["wander", "graze", "rest"]

func _process(delta: float) -> void:
	if main == null or main.hero == null:
		return
	strip_mat.set_shader_parameter("hero_pos", main.water_mat.get_shader_parameter("hero_pos"))
	strip_mat.set_shader_parameter("swim", main.water_mat.get_shader_parameter("swim"))
	strip_mat.set_shader_parameter("swim_move", main.water_mat.get_shader_parameter("swim_move"))
	_sync_t -= delta
	if _sync_t <= 0.0:
		_sync_t = 0.3
		strip_mat.set_shader_parameter("ice", main.water_mat.get_shader_parameter("ice"))
		strip_mat.set_shader_parameter("rain", main.water_mat.get_shader_parameter("rain"))
	if _shot_dir != "":
		_shots()
	var hp: Vector3 = main.hero.position
	var any_gnaw := false
	for c: Dictionary in colonies:
		var cp: Vector3 = c["c"]
		var near := Vector2(cp.x - hp.x, cp.z - hp.z).length() < 110.0
		var fell: Dictionary = c["fell"]
		if not fell.is_empty() and fell["phase"] == "fall":
			_fall_step(c, fell, delta)
		if near:
			if _tick_colony(c, delta):
				any_gnaw = true
		if c["mud_dirty"]:
			c["mud_dirty"] = false
			_rebuild_mud(c)
	chips.emitting = any_gnaw
	if _sync_t >= 0.29 and main.weather != null:
		stick_mat.set_shader_parameter("snow", main.weather.snow)
		spill_mat.set_shader_parameter("ice", main.weather.ice)

## Шаг работы колонии; true — сейчас грызёт дерево (летят щепки).
func _tick_colony(c: Dictionary, delta: float) -> bool:
	var w := _worker(c)
	if w == null:
		return false
	var ph: String = c["phase"]
	match ph:
		"rest":
			c["tm"] = float(c["tm"]) - delta
			if float(c["tm"]) <= 0.0 and _calm(w):
				var trees: Array = c["trees"]
				if trees.is_empty() or int(c["felled"]) >= 10:
					c["tm"] = 60.0
					return false
				var rec: Array = trees.pop_front()
				var xf: Transform3D = rec[2]
				var o := xf.origin
				# встать со стороны реки, к стволу мордой
				var zc: float = RP.zc(o.x, main.map_seed)
				var to_r := Vector3(0, 0, signf(zc - o.z) if absf(zc - o.z) > 0.1 else 1.0)
				var s := xf.basis.get_scale().x
				c["fell"] = {"rec": rec, "xf": xf, "o": o, "s": s, "k": 0.0, "dir": to_r.rotated(Vector3.UP, rng.randf_range(-0.5, 0.5)), "phase": "stand", "vis": false}
				var kr := float(TRUNK_RS.get(String(rec[3]).rstrip("0123456789"), TRUNK_R))
				var stand := o + to_r * (kr * s + 0.42)
				c["fell"]["stand"] = stand
				_go(c, stand, "gnaw")
		"go":
			c["go_t"] = float(c["go_t"]) + delta
			var goal: Vector3 = c["goal"]
			if w.state == "job" and w.arrived:
				w.position.x = goal.x
				w.position.z = goal.z
				_enter(c, w, c["next"])
			elif _calm(w):
				_send(w, goal)
			elif float(c["go_t"]) > 45.0 and w.hero_dist() > 30.0:
				# застрял: переносим к цели, пока никто не видит
				w.position = Vector3(goal.x, main.ground_at(goal.x, goal.z), goal.z)
				c["go_t"] = 0.0
		"gnaw":
			var f: Dictionary = c["fell"]
			if w.state != "gnaw":
				if _calm(w):
					_go(c, f["stand"], "gnaw")
				return false
			f["k"] = minf(1.0, float(f["k"]) + delta / GNAW_T)
			c["snd_t"] = float(c["snd_t"]) - delta
			if float(c["snd_t"]) <= 0.0:
				c["snd_t"] = 0.75
				_update_notch(f)
				main.sfx.play_at("gnaw", w.position, -6.0, rng.randf_range(0.9, 1.15))
			var o: Vector3 = f["o"]
			var s: float = f["s"]
			var fr: float = f.get("r", TRUNK_R)
			chips.global_position = Vector3(o.x, o.y + NOTCH_Y * s, o.z) + (w.position - o).normalized() * fr * s
			if float(f["k"]) >= 1.0:
				_update_notch(f)
				_start_fall(c, f)
				# отбегает от падающего дерева
				var dir: Vector3 = f["dir"]
				_send(w, w.position - dir * 2.5)
				c["phase"] = "falling"
			return true
		"falling":
			var f2: Dictionary = c["fell"]
			if f2["phase"] == "down":
				c["tm"] = float(c["tm"]) - delta
				if float(c["tm"]) <= 0.0:
					var mid := _trunk_point(f2, 0.3)
					var axis: Vector3 = f2["axis"]
					_go(c, mid + axis * 0.45, "cut")
		"cut":
			if w.state != "gnaw":
				if _calm(w):
					var f3: Dictionary = c["fell"]
					var axis3: Vector3 = f3["axis"]
					_go(c, _trunk_point(f3, 0.3) + axis3 * 0.45, "cut")
				return false
			c["tm"] = float(c["tm"]) - delta
			c["snd_t"] = float(c["snd_t"]) - delta
			if float(c["snd_t"]) <= 0.0:
				c["snd_t"] = 0.75
				main.sfx.play_at("gnaw", w.position, -6.0, rng.randf_range(0.9, 1.15))
			if float(c["tm"]) <= 0.0:
				_cut_logs(c)
				_next_log(c, w)
	return false

## Начало фазы по прибытии работника.
func _enter(c: Dictionary, w: Node3D, what: String) -> void:
	var f: Dictionary = c["fell"]
	match what:
		"gnaw":
			if not f["vis"]:
				_begin_tree(c, f)
			w.state = "gnaw"
			w.gnaw_low = false
			w.job_face = f["o"]
			c["phase"] = "gnaw"
		"cut":
			w.state = "gnaw"
			w.gnaw_low = true
			w.job_face = _trunk_point(f, 0.3)
			c["phase"] = "cut"
			c["tm"] = 7.0
		"pick":
			var logs: Array = c["logs"]
			if logs.is_empty():
				_next_log(c, w)
				return
			var lg: Node3D = logs.pop_front()
			lg.get_parent().remove_child(lg)
			w.parts["head"].add_child(lg)
			lg.transform = Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0, -0.04, 0.12))
			w.carry = lg
			var a0: Vector3 = c["a"]
			var b0: Vector3 = c["b"]
			var t: Vector3 = c["t"]
			var p := a0.lerp(b0, rng.randf_range(0.3, 0.7)) - t * 1.0
			_go(c, p, "drop")
		"drop":
			if w.carry != null:
				w.carry.queue_free()
				w.carry = null
			c["prog"] = minf(1.0, float(c["prog"]) + STEP)
			# чурка ложится на гребень там, куда её принесли
			var a1: Vector3 = c["a"]
			var b1: Vector3 = c["b"]
			var sd := clampf((w.position - a1).dot(b1 - a1) / maxf(a1.distance_squared_to(b1), 0.01), 0.05, 0.95)
			_add_dam_log(c, sd, c["fell"].get("bark", STICK_BARK[0]) if not c["fell"].is_empty() else STICK_BARK[0])
			_update_solid(c)
			_show_sticks(c)
			_push_levels()
			c["mud_dirty"] = true
			_next_log(c, w)

func _next_log(c: Dictionary, w: Node3D) -> void:
	var logs: Array = c["logs"]
	if logs.is_empty():
		# крона уходит в землю (бобры обглодали ветки), отдых до следующего дерева
		var f: Dictionary = c["fell"]
		if f.has("pivot"):
			var pv: Node3D = f["pivot"]
			var tw := create_tween()
			tw.tween_property(pv, "position:y", pv.position.y - 2.5, 4.0)
			tw.tween_callback(pv.queue_free)
		main.pv.fade_list.erase(f.get("bm"))
		c["fell"] = {}
		c["phase"] = "rest"
		c["tm"] = rng.randf_range(12.0, 30.0)
		w.state = "wander"
		w.state_t = 5.0
		return
	var lg: Node3D = logs[0]
	_go(c, lg.global_position, "pick")

# ---------- дерево: надгрыз, падение, разделка ----------

func _begin_tree(c: Dictionary, f: Dictionary) -> void:
	f["vis"] = true
	var rec: Array = f["rec"]
	var xf: Transform3D = f["xf"]
	var key: String = rec[3]
	var o: Vector3 = f["o"]
	var kind := key.rstrip("0123456789")
	f["bark"] = BARK_COL.get(kind, Color(0.5, 0.45, 0.4))
	f["r"] = float(TRUNK_RS.get(kind, TRUNK_R))
	# прячем дерево в общем лесу (дальний MultiMesh и ближний набор)
	rec[2] = Transform3D(Basis().scaled(Vector3(0.0001, 0.0001, 0.0001)), Vector3(o.x, -500.0, o.z))
	rec[0].set_instance_transform(rec[1], rec[2])
	main._update_near(true)
	_remove_blocker(o)
	# пень с надгрызом — своя маленькая сетка, пока грызут
	var stump := MeshInstance3D.new()
	stump.material_override = mud_mat
	add_child(stump)
	f["stump"] = stump
	# верх дерева на шарнире у надгрыза; кора ниже надгрыза срезана шейдером
	var mesh: Mesh = main.near_mesh[key]
	var pivot := Node3D.new()
	pivot.position = xf * Vector3(0, NOTCH_Y, 0)
	add_child(pivot)
	var top := MeshInstance3D.new()
	top.mesh = mesh
	top.transform = Transform3D(xf.basis, xf.origin - pivot.position)
	var bm: ShaderMaterial = mesh.surface_get_material(0).duplicate()
	bm.set_shader_parameter("clip_y", NOTCH_Y + NOTCH_H)
	top.set_surface_override_material(0, bm)
	main.pv.fade_list.append(bm)
	pivot.add_child(top)
	var upper := MeshInstance3D.new()
	upper.material_override = mud_mat
	upper.transform = top.transform
	pivot.add_child(upper)
	f["pivot"] = pivot
	f["top"] = top
	f["upper"] = upper
	f["bm"] = bm
	f["L"] = mesh.get_aabb().end.y * float(f["s"])
	_update_notch(f)

func _update_notch(f: Dictionary) -> void:
	if not f["vis"]:
		return
	var k: float = f["k"]
	var b := AM.MB.new()
	var tr: float = f["r"]
	_stump_geo(b, f["xf"], k, f["bark"], k > 0.3, tr)
	var stump: MeshInstance3D = f["stump"]
	stump.mesh = b.commit()
	var rm := tr * (1.0 - 0.85 * k)
	var bark: Color = f["bark"]
	var u := AM.MB.new()
	u.lathe([[NOTCH_Y + NOTCH_H, tr, bark], [NOTCH_Y + NOTCH_H * 0.5, lerpf(tr, rm, 0.6), WOOD.darkened(0.1)], [NOTCH_Y, rm, WOOD]], 8, Transform3D.IDENTITY, true)
	var upper: MeshInstance3D = f["upper"]
	upper.mesh = u.commit()

func _remove_blocker(o: Vector3) -> void:
	var k := Vector2i(floori(o.x / 8.0), floori(o.z / 8.0))
	if not main.blockers.has(k):
		return
	var arr: Array = main.blockers[k]
	for i in arr.size():
		var bl: Vector3 = arr[i]
		if absf(bl.x - o.x) < 0.01 and absf(bl.y - o.z) < 0.01:
			arr.remove_at(i)
			return

func _start_fall(c: Dictionary, f: Dictionary) -> void:
	var dir: Vector3 = f["dir"]
	f["axis"] = Vector3.UP.cross(dir).normalized()
	f["th"] = 0.03
	f["w"] = 0.04
	f["bounce"] = 0
	f["phase"] = "fall"
	# угол, на котором ствол ляжет на землю (или на воду)
	var pv: Node3D = f["pivot"]
	var L: float = f["L"]
	var d := L * 0.55
	var q := pv.position + dir * d
	var gy := maxf(main.ground_at(q.x, q.z), main.water_level(q.x, q.z) - 0.2)
	var drop := pv.position.y - gy - 0.15
	f["th_g"] = clampf(PI * 0.5 + atan2(drop, d), 1.25, 1.85)
	main.sfx.play_at("crack", pv.position + Vector3(0, 2, 0), 8.0, rng.randf_range(0.9, 1.05))
	c["felled"] = int(c["felled"]) + 1

## Падение: ускорение как у стержня на шарнире, удар о землю, пара затухающих отскоков.
func _fall_step(c: Dictionary, f: Dictionary, delta: float) -> void:
	var L: float = f["L"]
	var th: float = f["th"]
	var w: float = f["w"]
	var dt := minf(delta, 0.05) * 0.5
	for i in 2:
		w += 1.5 * 9.8 / maxf(L * 0.9, 1.0) * sin(th) * dt
		th += w * dt
		var tg: float = f["th_g"]
		if th >= tg and w > 0.0:
			th = tg
			var nb: int = int(f["bounce"])
			if nb == 0:
				var pv0: Node3D = f["pivot"]
				var fd: Vector3 = f["dir"]
				main.sfx.play_at("thud", pv0.position + fd * L * 0.4, 10.0, rng.randf_range(0.85, 1.0))
			f["bounce"] = nb + 1
			w = -w * 0.28
			if nb >= 2 or absf(w) < 0.12:
				w = 0.0
				f["phase"] = "down"
				# пень остаётся в общей сетке ила; щепа вокруг
				c["stumps"].append([f["xf"], f["bark"], f["r"]])
				var st: MeshInstance3D = f["stump"]
				st.queue_free()
				c["mud_dirty"] = true
				c["tm"] = 2.5
				break
	f["th"] = th
	f["w"] = w
	var pv: Node3D = f["pivot"]
	var ax: Vector3 = f["axis"]
	pv.basis = Basis(ax, th)

## Точка на лежащем стволе на доле k длины от шарнира (на земле).
func _trunk_point(f: Dictionary, k: float) -> Vector3:
	var pv: Node3D = f["pivot"]
	var L: float = f["L"]
	var dir: Vector3 = f["dir"]
	var p: Vector3 = pv.position + dir * L * k
	return Vector3(p.x, main.ground_at(p.x, p.z), p.z)

## Ствол разгрызен: низ ствола — чурки на земле, крона остаётся лежать (кора ниже кроны срезана).
func _cut_logs(c: Dictionary) -> void:
	var f: Dictionary = c["fell"]
	var s: float = f["s"]
	var L: float = f["L"]
	var dir: Vector3 = f["dir"]
	var pv: Node3D = f["pivot"]
	var bm: ShaderMaterial = f["bm"]
	var cut_l := minf(LOGS * 1.0 + 0.4, L * 0.45)
	bm.set_shader_parameter("clip_y", NOTCH_Y + cut_l / s)
	var upper: Node3D = f["upper"]
	upper.visible = false
	var tr: float = f["r"]
	var lm := CylinderMesh.new()
	lm.top_radius = tr * s * 0.95
	lm.bottom_radius = tr * s
	lm.height = 0.85
	lm.radial_segments = 7
	lm.rings = 1
	var top: MeshInstance3D = f["top"]
	lm.material = top.mesh.surface_get_material(0)
	var logs: Array = []
	for i in LOGS:
		var p: Vector3 = pv.position + dir * (0.6 + float(i) * (cut_l - 0.4) / LOGS)
		var gy := maxf(main.ground_at(p.x, p.z), main.water_level(p.x, p.z) - 0.1)
		var lg := MeshInstance3D.new()
		lg.mesh = lm
		add_child(lg)
		var ax: Vector3 = f["axis"]
		lg.global_transform = Transform3D(Basis(ax, PI * 0.5).rotated(Vector3.UP, rng.randf_range(-0.3, 0.3)), Vector3(p.x, gy + tr * s, p.z))
		logs.append(lg)
	c["logs"] = logs

func _snap(name_s: String) -> void:
	if _shot_done.has(name_s):
		return
	_shot_done[name_s] = true
	get_viewport().get_texture().get_image().save_png(_shot_dir + "/" + name_s + ".png")
	var c: Dictionary = colonies[0]
	print("beaver shot ", name_s, " draws ", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), " phase ", c["phase"], " prog ", c["prog"], " logs ", c["logs"].size())

## Камера смотрит на точку p (герой отходит в сторону, чтобы не спугнуть и не заслонять).
func _view(p: Vector3, yaw: float, dist: float, pitch: float) -> void:
	main.rig.target = null
	main.hero.position = Vector3(p.x + 30.0, main.ground_at(p.x + 30.0, p.z), p.z)
	main.rig.position = Vector3(p.x, maxf(main.ground_at(p.x, p.z), main.water_level(p.x, p.z)), p.z)
	main.rig.rotation.y = yaw
	main.rig.distance = dist
	main.rig.pitch = pitch

func _shots() -> void:
	_shot_f += 1
	var c: Dictionary = colonies[0]
	var f: Dictionary = c["fell"]
	var w := _worker(c)
	if _shot_f == 5:
		Engine.time_scale = 3.0
		main.t_hours = 11.0
		c["tm"] = 0.0
		print("beaver trees ", c["trees"].size(), " colonies ", colonies.size(), " lodge ", c["lodge"], " dam ", c["c"])
	if _shot_f > 6 and _shot_f < 400 and not f.is_empty() and not _shot_done.has("b_down"):
		var o: Vector3 = f["o"]
		var dir: Vector3 = f["dir"]
		var side := dir.cross(Vector3.UP)
		_view(o + dir * 1.0 + Vector3(0, 0.5, 0), atan2(side.x, side.z), 7.0, 18.0)
		if c["phase"] == "go" and _shot_f > 20 and float(c["go_t"]) > 1.0:
			# поторопить: работник сразу у дерева
			w.position = c["goal"]
		if c["phase"] == "gnaw" and float(f["k"]) > 0.6:
			_snap("b_gnaw")
		if f.get("phase", "") == "fall" and float(f.get("th", 0.0)) > 0.7:
			_snap("b_fall")
		if f.get("phase", "") == "down":
			_snap("b_down")
			_shot_f = 400
	if _shot_f == 400:
		var lp: Vector3 = c["lodge"]
		var cp: Vector3 = c["c"]
		var t: Vector3 = c["t"]
		var a0: Vector3 = c["a"]
		var b0: Vector3 = c["b"]
		var al := (b0 - a0).normalized()
		_view(a0.lerp(b0, 0.5), atan2(t.x, t.z) + 0.5, 15.0, 30.0)
		for b: Node3D in c["beavers"]:
			if b != w:
				b.position = lp + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
	if _shot_f == 430:
		_snap("b_dam")
	if _shot_f == 431:
		var lp2: Vector3 = c["lodge"]
		var cp3: Vector3 = c["c"]
		var tl := (lp2 - cp3).normalized()
		_view(lp2 - tl * 3.0, atan2(-tl.x, -tl.z), 9.0, 30.0)
	if _shot_f == 460:
		_snap("b_lodge")
	if _shot_f == 461:
		var cp2: Vector3 = c["c"]
		var t2: Vector3 = c["t"]
		_view(cp2 - t2 * 14.0, atan2(-t2.x, -t2.z), 16.0, 40.0)
	if _shot_f == 490:
		_snap("b_pond")
		# рыба: ближний к плотине косяк сверху
		var fsh: Node3D = main.animals.fish
		var cp4: Vector3 = c["c"]
		var best: Dictionary = fsh.schools[0]
		for sc: Dictionary in fsh.schools:
			if absf(float(sc["x"]) - cp4.x) < absf(float(best["x"]) - cp4.x):
				best = sc
		best["x"] = cp4.x + 40.0
		var fx: float = best["x"]
		var fp := Vector3(fx, 0.0, fsh._zc(fx) + float(best["l"]))
		_view(fp, 0.6, 5.0, 50.0)
	if _shot_f == 520:
		_snap("b_fish")
		# вплавь: лось и косуля переплывают реку ниже плотины
		var cp5: Vector3 = c["c"]
		var t5: Vector3 = c["t"]
		var sw := cp5 + t5 * 48.0
		var k := 0
		for a: Node3D in main.animals.list:
			if a.dead or not (a.kind in ["moose", "roe"]) or k >= 2:
				continue
			if a.kind == "roe" and k == 0:
				continue
			a.position = sw + Vector3(0, 0, -3.0 + float(k) * 4.0) + t5 * float(k) * 2.0
			a.target = a.position + Vector3(0, 0, 30.0)
			a.state = "wander"
			a.state_t = 30.0
			a.cross = true
			k += 1
		_view(sw, PI * 0.5, 7.0, 14.0)
	if _shot_f > 521 and _shot_f < 560:
		# камера следит за плывущим лосем
		for a: Node3D in main.animals.list:
			if a.kind == "moose" and a.cross and a.swim_k > 0.5:
				main.rig.position = a.position
				main.rig.rotation.y = a.heading + 1.9
				main.rig.distance = 5.5
				main.rig.pitch = 16.0
				break
	if _shot_f == 560:
		_snap("b_swim")
		# медведь рыбачит на мелководье
		var fsh2: Node3D = main.animals.fish
		var cp6: Vector3 = c["c"]
		var bs: Vector3 = fsh2.spot_near(cp6 + Vector3(60, 0, 0), 200.0)
		for a: Node3D in main.animals.list:
			if a.kind == "bear" and bs != Vector3.INF:
				main.weather.ice = 0.0
				a.visible = true
				a.position = bs
				a.state = "fish"
				a.state_t = 60.0
				a.fish_cd = 0.6
				_view(bs, 0.9, 6.0, 20.0)
				break
	if _shot_f == 590:
		_snap("b_bear")
		get_tree().quit()
	if _shot_f > 2500:
		_snap("b_timeout")
		get_tree().quit()
