extends Node3D
## Путник: тело собрано из частей, ходит по джойстику; не идёт в глубокую воду, по отвесным обрывам и сквозь стволы.

var main: Node3D
var move_vec := Vector2.ZERO
var cam_yaw := 0.0
var speed := 3.1
var run_speed := 4.8
var running := false
var climbing := 0.0
var moving := false
var run_mag := 0.0
var phase := 0.0
var body := Node3D.new()
var torso := Node3D.new()
var leg_l := Node3D.new()
var leg_r := Node3D.new()
var knee_l := Node3D.new()
var knee_r := Node3D.new()
var ank_l := Node3D.new()
var ank_r := Node3D.new()
var head_n := Node3D.new()
var arm_l := Node3D.new()
var arm_r := Node3D.new()
var elb_l := Node3D.new()
var elb_r := Node3D.new()
var vel := Vector3.ZERO
var sliding := 0.0
var lean := 0.0
var tilt := 0.0
var last_sw := 0.0
# состояния: walk, sit, climb; плавание и брод внутри walk
var state := "walk"
var seat: Array = []
var stand_pos := Vector3.ZERO
var sitb := 0.0
var swimb := 0.0
var swim_spk := 0.0
var climbb := 0.0
var cphase := 0.0
var soaked := 0.0
var depth := 0.0
var vy := 0.0
var airborne := false
var fallb := 0.0
var land_t := 0.0
var land_k := 0.0
var last_impact := 0.0
var skirt_l := Node3D.new()
var skirt_r := Node3D.new()
var last_yaw := 0.0
var turn := 0.0
var arm_lx := 0.0
var arm_rx := 0.0
var cloth_tex: Texture2D
var torch := OmniLight3D.new()

## Живописный материал (тот же свет, что у мира).
var _pmats := {}
func _paint(c: Color) -> ShaderMaterial:
	var k := c.to_html()
	if _pmats.has(k):
		return _pmats[k]
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/paint/fur.gdshader")
	m.set_shader_parameter("use_vc", false)
	m.set_shader_parameter("tint", Vector3(c.r, c.g, c.b))
	_pmats[k] = m
	return m

func _mat(c: Color, rough: float = 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m

## Материал ткани: цвет + шумовая фактура (переплетение, потёртости).
func _cloth(c: Color, sc: float = 7.0) -> StandardMaterial3D:
	if cloth_tex == null:
		var nz := FastNoiseLite.new()
		nz.frequency = 0.09
		nz.fractal_octaves = 4
		var g := Gradient.new()
		g.set_color(0, Color(0.72, 0.72, 0.72))
		g.set_color(1, Color(1.0, 1.0, 1.0))
		var nt := NoiseTexture2D.new()
		nt.width = 128
		nt.height = 128
		nt.seamless = true
		nt.noise = nz
		nt.color_ramp = g
		nt.generate_mipmaps = true
		cloth_tex = nt
	var m := _mat(c, 0.95)
	m.albedo_texture = cloth_tex
	m.uv1_scale = Vector3(sc, sc, sc)
	return m

## Лофт: гладкое тело вращения по сечениям-эллипсам [y, rx, rz, смещение z]. Ось вдоль Y.
func _loft(rings: Array, seg: int = 20, cap_top: bool = true, cap_bot: bool = true) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := rings.size()
	for i in n:
		var r: Array = rings[i]
		for j in seg + 1:
			var a := TAU * j / seg
			st.set_uv(Vector2(float(j) / seg, float(i) / (n - 1)))
			st.add_vertex(Vector3(cos(a) * r[1], r[0], sin(a) * r[2] + r[3]))
	for i in n - 1:
		for j in seg:
			var k := i * (seg + 1) + j
			st.add_index(k)
			st.add_index(k + 1)
			st.add_index(k + seg + 1)
			st.add_index(k + 1)
			st.add_index(k + seg + 2)
			st.add_index(k + seg + 1)
	var base := n * (seg + 1)
	if cap_bot:
		var r0: Array = rings[0]
		st.set_uv(Vector2(0.5, 0.0))
		st.add_vertex(Vector3(0, r0[0], r0[3]))
		for j in seg:
			st.add_index(base)
			st.add_index(j + 1)
			st.add_index(j)
		base += 1
	if cap_top:
		var r1: Array = rings[n - 1]
		st.set_uv(Vector2(0.5, 1.0))
		st.add_vertex(Vector3(0, r1[0], r1[3]))
		var o := (n - 1) * (seg + 1)
		for j in seg:
			st.add_index(base)
			st.add_index(o + j)
			st.add_index(o + j + 1)
	st.generate_normals()
	return st.commit()

func _lpart(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO, sc: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	mi.scale = sc
	parent.add_child(mi)
	return mi

func _part(parent: Node3D, mesh: Mesh, c: Color, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(c)
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi

func _ell(parent: Node3D, mesh: Mesh, c: Color, pos: Vector3, sc: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := _part(parent, mesh, c, pos, rot)
	mi.scale = sc
	return mi

func _capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 16
	m.rings = 6
	return m

func _sph() -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = 16
	m.rings = 8
	return m

func _cyl(rt: float, rb: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = rt
	m.bottom_radius = rb
	m.height = h
	m.radial_segments = 18
	return m

func _tor(i: float, o: float) -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius = i
	m.outer_radius = o
	m.ring_segments = 8
	return m

func _ready() -> void:
	add_child(body)
	body.add_child(torso)
	torso.position = Vector3(0, 0.97, 0)
	# Первопроходец: овчинная куртка-полушубок до середины бедра с откинутым капюшоном,
	# широкий кожаный пояс с ножом и сумкой, суконные штаны, сапоги с обмоткой,
	# короб за спиной со скаткой и котелком. Без шапки: тёмные вихры и борода.
	var coat := _paint(Color(0.47, 0.34, 0.22))
	var coat_d := _paint(Color(0.34, 0.24, 0.15))
	var shear := _paint(Color(0.86, 0.8, 0.68))
	var pants := _paint(Color(0.24, 0.26, 0.24))
	var belt := _paint(Color(0.2, 0.13, 0.08))
	var boot := _paint(Color(0.16, 0.11, 0.08))
	var wrap := _paint(Color(0.55, 0.5, 0.4))
	var skin := _paint(Color(0.74, 0.54, 0.42))
	var hair := _paint(Color(0.22, 0.15, 0.1))
	var wood := _paint(Color(0.5, 0.38, 0.24))
	var roll := _paint(Color(0.42, 0.18, 0.13))
	var metal := _paint(Color(0.3, 0.3, 0.3))
	var dark := _paint(Color(0.06, 0.05, 0.04))
	# --- ноги: бедро, голень в сапоге с обмоткой, стопа; полы куртки на бёдрах
	for side in [-1.0, 1.0]:
		var leg: Node3D = leg_l if side < 0.0 else leg_r
		var knee: Node3D = knee_l if side < 0.0 else knee_r
		var ank: Node3D = ank_l if side < 0.0 else ank_r
		var sk: Node3D = skirt_l if side < 0.0 else skirt_r
		leg.position = Vector3(side * 0.1, 0.97, 0)
		body.add_child(leg)
		_lpart(leg, _loft([[-0.48, 0.062, 0.066, 0.0], [-0.4, 0.072, 0.078, 0.008], [-0.25, 0.085, 0.092, 0.012], [-0.08, 0.095, 0.1, 0.005], [0.04, 0.1, 0.1, 0.0]], 16), pants)
		knee.position = Vector3(0, -0.46, 0)
		leg.add_child(knee)
		_lpart(knee, _loft([[0.04, 0.066, 0.07, 0.0], [-0.08, 0.07, 0.078, -0.012], [-0.2, 0.066, 0.074, -0.018], [-0.32, 0.056, 0.062, -0.01]], 14), pants)
		# сапог с отворотом и обмоткой ремешком
		_lpart(knee, _loft([[-0.47, 0.058, 0.064, 0.0], [-0.36, 0.06, 0.068, -0.008], [-0.24, 0.07, 0.078, -0.012], [-0.2, 0.078, 0.084, -0.01]], 14), boot)
		for i in 3:
			_lpart(knee, _tor(0.058 + i * 0.004, 0.072 + i * 0.004), wrap, Vector3(0, -0.42 + i * 0.07, -0.005), Vector3(0.12 * (1 - i), 0, 0.1), Vector3(1, 0.5, 1.08))
		ank.position = Vector3(0, -0.48, 0)
		knee.add_child(ank)
		_lpart(ank, _loft([[-0.06, 0.05, 0.055, -0.02], [-0.02, 0.06, 0.08, 0.02], [0.02, 0.055, 0.1, 0.05], [0.04, 0.04, 0.09, 0.06]], 14), boot, Vector3(0, -0.02, 0), Vector3(0, 0, 0))
		_lpart(ank, BoxMesh.new(), dark, Vector3(0, -0.075, 0.05), Vector3.ZERO, Vector3(0.1, 0.022, 0.26))
		# пола: от пояса до середины бедра, расширяется книзу, с меховой оторочкой
		sk.position = Vector3(side * 0.1, 0.97, 0)
		body.add_child(sk)
		_lpart(sk, _loft([[-0.38, 0.2, 0.21, 0.0], [-0.26, 0.18, 0.19, 0.0], [-0.12, 0.155, 0.165, 0.0], [0.04, 0.135, 0.15, 0.0]], 18, false, false), coat, Vector3(side * 0.03, 0, 0))
		_lpart(sk, _tor(0.18, 0.225), shear, Vector3(side * 0.03, -0.38, 0), Vector3.ZERO, Vector3(1.0, 0.8, 1.04))
	# --- торс: полушубок с запахом и меховой каймой по борту
	_lpart(torso, _loft([[-0.12, 0.215, 0.175, 0.0], [0.0, 0.2, 0.155, 0.0], [0.1, 0.185, 0.14, 0.0], [0.22, 0.195, 0.145, 0.012], [0.36, 0.215, 0.15, 0.02], [0.48, 0.225, 0.14, 0.01], [0.56, 0.2, 0.12, -0.005], [0.62, 0.13, 0.09, -0.01], [0.66, 0.08, 0.07, 0.0]], 24), coat)
	_lpart(torso, BoxMesh.new(), shear, Vector3(0.05, 0.3, 0.158), Vector3(0, 0, 0.12), Vector3(0.06, 0.62, 0.02))
	# пояс, пряжка, нож в ножнах, сумка
	_lpart(torso, _loft([[0.02, 0.2, 0.16, 0.0], [0.09, 0.198, 0.158, 0.0]], 22, false, false), belt)
	_lpart(torso, BoxMesh.new(), metal, Vector3(0.0, 0.055, 0.162), Vector3.ZERO, Vector3(0.05, 0.05, 0.012))
	_lpart(torso, _loft([[-0.22, 0.012, 0.025, 0.0], [-0.05, 0.022, 0.032, 0.0], [0.0, 0.024, 0.034, 0.0]], 8), belt, Vector3(0.19, 0.03, 0.06), Vector3(0, 0, 0.15))
	_lpart(torso, _cyl(0.012, 0.014, 0.08), wood, Vector3(0.2, 0.1, 0.06), Vector3(0, 0, 0.15))
	_lpart(torso, _sph(), belt, Vector3(-0.17, -0.03, 0.09), Vector3.ZERO, Vector3(0.1, 0.12, 0.06))
	# откинутый капюшон с меховой опушкой лежит на плечах
	_lpart(torso, _sph(), coat_d, Vector3(0, 0.6, -0.12), Vector3(-0.3, 0, 0), Vector3(0.26, 0.17, 0.16))
	_lpart(torso, _tor(0.075, 0.115), shear, Vector3(0, 0.655, -0.02), Vector3(0.35, 0, 0), Vector3(1.1, 1.3, 1.0))
	# --- голова: шея, череп, лоб, нос, скулы, уши, глаза, брови, вихры, борода, усы
	_lpart(torso, _cyl(0.05, 0.058, 0.1), skin, Vector3(0, 0.73, 0.0))
	torso.add_child(head_n)
	head_n.position = Vector3(0, 0.87, 0.01)
	_lpart(head_n, _loft([[-0.1, 0.06, 0.07, 0.02], [-0.06, 0.085, 0.095, 0.015], [0.0, 0.098, 0.11, 0.008], [0.06, 0.1, 0.115, 0.0], [0.1, 0.09, 0.105, -0.005], [0.13, 0.06, 0.075, -0.01], [0.145, 0.02, 0.03, -0.01]], 20), skin)
	_lpart(head_n, _loft([[0.0, 0.016, 0.014, 0.0], [0.035, 0.012, 0.01, 0.006], [0.05, 0.004, 0.004, 0.006]], 8), skin, Vector3(0, -0.005, 0.105), Vector3(1.9, 0, 0))
	_lpart(head_n, _sph(), skin, Vector3(0, 0.045, 0.098), Vector3.ZERO, Vector3(0.12, 0.03, 0.03))
	for sd in [-1.0, 1.0]:
		_lpart(head_n, _sph(), skin, Vector3(sd * 0.098, 0.005, 0.0), Vector3(0, sd * 0.3, 0), Vector3(0.022, 0.05, 0.035))
		_lpart(head_n, _sph(), skin, Vector3(sd * 0.055, -0.01, 0.085), Vector3.ZERO, Vector3(0.045, 0.035, 0.035))
		_lpart(head_n, _sph(), dark, Vector3(sd * 0.038, 0.022, 0.1), Vector3.ZERO, Vector3(0.016, 0.012, 0.008))
		_lpart(head_n, BoxMesh.new(), hair, Vector3(sd * 0.04, 0.045, 0.104), Vector3(0, 0, -sd * 0.18), Vector3(0.042, 0.011, 0.014))
	# вихры: несколько сросшихся прядей, чуть растрёпаны
	_lpart(head_n, _sph(), hair, Vector3(0, 0.1, -0.012), Vector3(-0.2, 0, 0), Vector3(0.225, 0.16, 0.245))
	for i in 7:
		var a := -1.2 + i * 0.4
		_lpart(head_n, _sph(), hair, Vector3(sin(a) * 0.08, 0.15 + cos(a * 2.0) * 0.01, cos(a) * 0.05 - 0.02), Vector3(0.4, a, 0.3 * sin(a * 3.0)), Vector3(0.06, 0.04, 0.1))
	_lpart(head_n, _sph(), hair, Vector3(0, 0.02, -0.075), Vector3.ZERO, Vector3(0.2, 0.17, 0.12))
	# борода лопатой и усы
	_lpart(head_n, _loft([[-0.12, 0.04, 0.03, 0.06], [-0.08, 0.08, 0.055, 0.06], [-0.035, 0.1, 0.075, 0.045], [0.0, 0.098, 0.09, 0.02], [0.02, 0.095, 0.085, 0.0]], 16), hair, Vector3(0, -0.04, 0.01))
	for sd in [-1.0, 1.0]:
		_lpart(head_n, _sph(), hair, Vector3(sd * 0.022, -0.04, 0.108), Vector3(0, 0, sd * 0.5), Vector3(0.04, 0.014, 0.018))
	# --- спина: берестяной короб на лямках, скатка сверху, котелок сбоку
	_lpart(torso, _loft([[0.0, 0.16, 0.085, 0.0], [0.42, 0.165, 0.09, 0.0], [0.45, 0.15, 0.08, 0.0]], 4), wood, Vector3(0, 0.08, -0.25), Vector3(0, PI * 0.25, 0))
	for sd in [-1.0, 1.0]:
		_lpart(torso, BoxMesh.new(), belt, Vector3(sd * 0.11, 0.42, 0.0), Vector3.ZERO, Vector3(0.04, 0.4, 0.32))
	_lpart(torso, _cyl(0.07, 0.07, 0.48), roll, Vector3(0, 0.6, -0.26), Vector3(0, 0, PI * 0.5))
	for sd in [-1.0, 1.0]:
		_lpart(torso, _tor(0.068, 0.08), belt, Vector3(sd * 0.15, 0.6, -0.26), Vector3(0, 0, PI * 0.5))
	_lpart(torso, _cyl(0.06, 0.055, 0.1), metal, Vector3(0.2, 0.2, -0.24))
	# --- руки: плечо, рукав, локоть, меховой обшлаг, кисть с пальцами
	for side in [-1.0, 1.0]:
		var arm: Node3D = arm_l if side < 0.0 else arm_r
		var elb: Node3D = elb_l if side < 0.0 else elb_r
		arm.position = Vector3(side * 0.24, 0.6, 0)
		torso.add_child(arm)
		_lpart(arm, _sph(), coat, Vector3(side * -0.02, -0.03, 0), Vector3.ZERO, Vector3(0.12, 0.11, 0.12))
		_lpart(arm, _loft([[-0.32, 0.052, 0.056, 0.0], [-0.15, 0.062, 0.066, 0.0], [0.0, 0.072, 0.072, 0.0]], 14), coat)
		elb.position = Vector3(0, -0.3, 0)
		arm.add_child(elb)
		_lpart(elb, _loft([[-0.25, 0.064, 0.064, 0.0], [-0.12, 0.056, 0.058, 0.0], [0.02, 0.055, 0.058, 0.0]], 14), coat)
		_lpart(elb, _tor(0.052, 0.082), shear, Vector3(0, -0.25, 0))
		_lpart(elb, _sph(), skin, Vector3(0, -0.31, 0.008), Vector3.ZERO, Vector3(0.05, 0.075, 0.07))
		for f in 4:
			_lpart(elb, _capsule(0.009, 0.06), skin, Vector3(side * -0.008, -0.36, -0.02 + f * 0.014), Vector3(0, 0, side * 0.1))
		_lpart(elb, _capsule(0.01, 0.05), skin, Vector3(side * -0.02, -0.31, 0.04), Vector3(0.6, 0, side * 0.5))
	_build_model()
	# факел-свет (ночью)
	torch.light_color = Color(1.0, 0.7, 0.4)
	torch.light_energy = 0.0
	torch.omni_range = 11.0
	torch.position = Vector3(0, 1.7, 0.5)
	add_child(torch)

func _can_walk(p: Vector3) -> bool:
	var half: float = main.SIZE * 0.5 - 8.0
	if absf(p.x) > half or absf(p.z) > half:
		return false
	var y: float = main.ground_at(p.x, p.z)
	if y - position.y > 1.1:
		return false
	# обрыв вниз: шагнуть можно — дальше герой падает
	if y < position.y - 0.6 or airborne:
		return not main.blocked(p.x, p.z, 0.32)
	var n: Vector3 = main.ground_normal(p.x, p.z)
	if n.y < 0.42:
		return false
	return not main.blocked(p.x, p.z, 0.32)

## Приземление: от скорости удара зависит, присядет ли герой, потеряет ли силы.
func _land(impact: float) -> void:
	last_impact = impact
	if depth > 1.0:
		return
	if impact > 3.0 and main.sfx != null:
		main.sfx.landed(impact)
	if impact > 5.0:
		land_t = clampf(impact * 0.07, 0.25, 1.2)
		land_k = clampf((impact - 5.0) / 8.0, 0.35, 1.0)
		vel *= 0.2
	if impact > 9.0:
		main.stamina = maxf(0.0, float(main.stamina) - (impact - 9.0) * 0.08)

## Подпись кнопки действия по обстановке ("" — кнопку скрыть).
func action_label() -> String:
	if state == "dead" or state == "climb":
		return ""
	if state == "sit":
		return "Встать"
	if swimb > 0.3:
		return ""
	if main.bleed > 0.02:
		return "Перевязать"
	var it: Array = main.find_pick(position)
	if not it.is_empty():
		return "Собрать: " + main.PICK_NAME[it[1]]
	if main.thirst < 0.95 and main.near_water(position):
		return "Пить"
	if not main.find_seat(position).is_empty():
		return "Сесть"
	return ""

func do_action() -> void:
	if state == "dead":
		return
	if state == "sit":
		_stand_up()
		return
	var lbl := action_label()
	if lbl == "Перевязать":
		main.bandage()
		land_t = 1.0
		land_k = 0.6
		return
	if lbl.begins_with("Собрать"):
		main.take_pick(main.find_pick(position))
		land_t = 0.55
		land_k = 0.85
		return
	if lbl == "Пить":
		main.drink()
		land_t = 1.1
		land_k = 1.0
		return
	var st: Array = main.find_seat(position)
	if st.is_empty():
		return
	seat = st
	stand_pos = position
	state = "sit"
	vel = Vector3.ZERO

## Гибель: герой оседает и ложится на бок.
var deadb := 0.0
func _process_dead(delta: float) -> void:
	deadb = minf(1.0, deadb + delta * 1.2)
	var k := deadb * deadb * (3.0 - 2.0 * deadb)
	body.rotation.z = lerpf(0.0, 1.5, k)
	body.position.y = lerpf(0.0, 0.18, k)
	knee_l.rotation.x = lerpf(knee_l.rotation.x, 0.8, delta * 3.0)
	knee_r.rotation.x = lerpf(knee_r.rotation.x, 0.4, delta * 3.0)
	arm_l.rotation.x = lerpf(arm_l.rotation.x, -0.6, delta * 3.0)
	arm_r.rotation.x = lerpf(arm_r.rotation.x, 0.3, delta * 3.0)
	torso.rotation.x = lerpf(torso.rotation.x, 0.3, delta * 3.0)

func revive(p: Vector3) -> void:
	state = "walk"
	deadb = 0.0
	body.rotation.z = 0.0
	position = p
	vel = Vector3.ZERO
	vy = 0.0
	airborne = false

func _stand_up() -> void:
	state = "walk"
	position = stand_pos

func _process(delta: float) -> void:
	_process_main(delta)
	_animate_model(delta)

func _process_main(delta: float) -> void:
	if main == null:
		return
	soaked = maxf(0.0, soaked - delta * 0.004 * (1.0 + maxf(float(main.weather.temp), 0.0) * 0.1))
	if state == "dead":
		_process_dead(delta)
		return
	if state == "sit":
		_process_sit(delta)
		return
	if state == "climb":
		_process_climb(delta)
		return
	sitb = maxf(0.0, sitb - delta * 4.0)
	climbb = maxf(0.0, climbb - delta * 4.0)
	leg_l.rotation.z = 0.0
	leg_r.rotation.z = 0.0
	var mag := minf(move_vec.length(), 1.0)
	var n: Vector3 = main.ground_normal(position.x, position.z)
	var down := Vector3(n.x, 0, n.z)
	var slope := down.length() / maxf(n.y, 0.01)
	if down.length() > 0.001:
		down = down.normalized()
	var d := Vector3.ZERO
	var target := Vector3.ZERO
	if mag > 0.12:
		d = Vector3(move_vec.x, 0, move_vec.y).normalized().rotated(Vector3.UP, cam_yaw)
		var along := d.dot(down)
		var f := 1.0
		if along < 0.0:
			f = clampf(1.0 + along * slope * 0.7, 0.5, 1.0)
		else:
			f = minf(1.0 + along * slope * 0.2, 1.15)
		var stam: float = main.stamina
		running = mag > 0.92 and stam > 0.08
		var sp_base := run_speed if running else speed
		var wf := 1.0
		if depth > 1.25:
			wf = 0.45
			running = false
		elif depth > 0.3:
			wf = 1.0 - (depth - 0.3) * 0.55
		target = d * sp_base * mag * f * wf * (1.0 - main.weather.snow * 0.3) * main.move_factor()
	else:
		running = false
	# крутой склон: человека тянет вниз, он теряет управление и катится
	var s := 0.0
	sliding = lerpf(sliding, s, minf(1.0, 4.0 * delta))
	var accel := 11.0 * (1.0 - sliding * 0.75)
	if airborne:
		accel = 0.5
		target = vel
	elif land_t > 0.0:
		target *= 0.2
	vel = vel.move_toward(target, accel * delta)
	vel.y = 0.0
	var step := vel * delta
	var p := position
	if step.length() > 0.00001:
		if _can_walk(p + step):
			p += step
		elif _can_walk(p + Vector3(step.x, 0, 0)):
			p.x += step.x
			vel.z = 0.0
		elif _can_walk(p + Vector3(0, 0, step.z)):
			p.z += step.z
			vel.x = 0.0
		else:
			# упёрлись в крутую стену: если это скала, а не дерево — начинаем лезть
			var q := position + d * 0.5
			var nq: Vector3 = main.ground_normal(q.x, q.z)
			if mag > 0.5 and nq.y < 0.42 and depth < 0.5 and not main.blocked(q.x, q.z, 0.2) and float(main.stamina) > 0.1:
				state = "climb"
			vel = Vector3.ZERO
	position.x = p.x
	position.z = p.z
	# стоим на круче без опоры — съезжаем вниз, набирая скорость
	if n.y < 0.4 and depth < 0.5 and not airborne:
		vel += down * 9.0 * (1.0 - n.y) * delta * 3.0
		position += down * minf(vel.length(), 6.0) * delta
	var sp := vel.length()
	moving = sp > 0.25
	if moving and (mag > 0.12 or sliding > 0.2):
		var face: Vector3 = d if mag > 0.12 and sliding < 0.4 else vel.normalized()
		body.rotation.y = lerp_angle(body.rotation.y, atan2(face.x, face.z), minf(1.0, 9.0 * delta))
	var ground: float = main.ground_at(position.x, position.z)
	var iced: bool = main.weather.ice >= 0.85
	var wl: float = main.water_level(position.x, position.z)
	depth = 0.0 if iced else maxf(0.0, wl - ground)
	var ty := ground
	if iced:
		ty = maxf(ground, wl)
	elif depth > 1.25:
		# на месте держится вертикально, над водой только голова и плечи; в гребке — спина у поверхности
		ty = wl - 1.0 - 0.5 * (1.0 - swim_spk) + sin(Time.get_ticks_msec() * 0.003) * 0.03
		soaked = 1.0
		# течение сносит вдоль реки
		position.x += 0.45 * delta
	elif depth > 0.6:
		soaked = maxf(soaked, 0.5)
	swimb = lerpf(swimb, 1.0 if depth > 1.25 else 0.0, minf(1.0, 4.0 * delta))
	# вертикаль: на подъёме ставим на опору; небольшой спуск — идём по земле;
	# обрыв — свободное падение с гравитацией и приземлением
	if ty >= position.y:
		if airborne:
			_land(-vy)
		position.y = ty
		vy = 0.0
		airborne = false
	elif not airborne and position.y - ty < 0.8 and depth <= 1.25:
		position.y = ty
		vy = 0.0
	elif depth > 1.25 and not airborne:
		position.y = lerpf(position.y, ty, minf(1.0, 6.0 * delta))
	else:
		airborne = true
		vy -= 9.8 * delta
		position.y += vy * delta
		if position.y <= ty:
			position.y = ty
			_land(-vy)
			vy = 0.0
			airborne = false
	fallb = lerpf(fallb, 1.0 if (airborne and vy < -4.5) else 0.0, minf(1.0, 5.0 * delta))
	land_t = maxf(0.0, land_t - delta)
	# походка: фаза от пройденного пути, размах от скорости
	var sn := clampf(sp / speed, 0.0, 1.6)
	run_mag = lerpf(run_mag, sn, minf(1.0, 8.0 * delta))
	var ph_prev := phase
	phase += sp * delta * 2.8
	# звук шага: каждый раз, когда нога касается земли (полупериод фазы)
	if floori(phase / PI) != floori(ph_prev / PI) and sp > 0.4 and (not airborne or swimb > 0.5) and main.sfx != null:
		main.sfx.step(swimb > 0.3, sp / speed)
	var fwd := Vector3(sin(body.rotation.y), 0, cos(body.rotation.y))
	var incline := 0.0
	if sp > 0.1:
		incline = clampf(-fwd.dot(down) * slope, -0.8, 0.8)  # >0 вверх
	# крутой подъём: карабкается, помогая руками
	var want_climb := 1.0 if (incline > 0.55 and sp > 0.1) else 0.0
	climbing = lerpf(climbing, want_climb, minf(1.0, 6.0 * delta))
	lean = lerpf(lean, 0.05 * run_mag + maxf(incline, 0.0) * 0.5 - maxf(-incline, 0.0) * 0.15, minf(1.0, 5.0 * delta))
	var amp := 0.5 * minf(run_mag, 1.5)
	var sw := sin(phase)
	if moving and signf(sw) != signf(last_sw) and main.feet != null and swimb < 0.2 and depth < 0.6:
		var side := 1.0 if sw > 0.0 else -1.0
		var rgt := Vector3(cos(body.rotation.y), 0, -sin(body.rotation.y))
		main.feet.stamp(position + rgt * side * 0.11, body.rotation.y)
	last_sw = sw
	var cw := cos(phase)
	var up := 1.0 + maxf(incline, 0.0) * 0.8
	var br := sin(Time.get_ticks_msec() * 0.0017) * 0.012 * (1.0 - run_mag)
	leg_l.rotation.x = sw * amp
	leg_r.rotation.x = -sw * amp
	knee_l.rotation.x = maxf(0.0, -cw) * amp * 1.5 * up + 0.04
	knee_r.rotation.x = maxf(0.0, cw) * amp * 1.5 * up + 0.04
	ank_l.rotation.x = -(leg_l.rotation.x + knee_l.rotation.x) * 0.7 + maxf(0.0, sw) * amp * 0.5
	ank_r.rotation.x = -(leg_r.rotation.x + knee_r.rotation.x) * 0.7 + maxf(0.0, -sw) * amp * 0.5
	# руки с инерцией: догоняют нужный угол, а не прыгают
	arm_lx = lerpf(arm_lx, -sw * amp * 0.8, minf(1.0, 12.0 * get_process_delta_time()))
	arm_rx = lerpf(arm_rx, sw * amp * 0.8, minf(1.0, 12.0 * get_process_delta_time()))
	arm_l.rotation.x = arm_lx
	arm_r.rotation.x = arm_rx
	arm_l.rotation.z = 0.05
	arm_r.rotation.z = -0.05
	elb_l.rotation.x = -0.2 - maxf(0.0, sw) * amp * 0.5
	elb_r.rotation.x = -0.2 - maxf(0.0, -sw) * amp * 0.5
	var cl := climbing
	if cl > 0.01:
		# руки тянутся вперёд-вверх и перехватывают склон, колени высоко
		arm_l.rotation.x = lerpf(arm_l.rotation.x, -1.6 - sw * 0.5, cl)
		arm_r.rotation.x = lerpf(arm_r.rotation.x, -1.6 + sw * 0.5, cl)
		elb_l.rotation.x = lerpf(elb_l.rotation.x, -0.5 - maxf(0.0, sw) * 0.6, cl)
		elb_r.rotation.x = lerpf(elb_r.rotation.x, -0.5 - maxf(0.0, -sw) * 0.6, cl)
		leg_l.rotation.x = lerpf(leg_l.rotation.x, sw * 0.45 - 0.45, cl)
		leg_r.rotation.x = lerpf(leg_r.rotation.x, -sw * 0.45 - 0.45, cl)
		knee_l.rotation.x = lerpf(knee_l.rotation.x, 0.6 + maxf(0.0, -cw) * 0.6, cl)
		knee_r.rotation.x = lerpf(knee_r.rotation.x, 0.6 + maxf(0.0, cw) * 0.6, cl)
	torso.rotation.x = lean + br + cl * 0.45
	# полы кафтана идут за ногой наполовину
	skirt_l.rotation.x = leg_l.rotation.x * 0.5
	skirt_r.rotation.x = leg_r.rotation.x * 0.5
	# крен в повороте, покачивание таза, голова держит горизонт
	var yaw_rate := wrapf(body.rotation.y - last_yaw, -PI, PI) / maxf(delta, 0.001)
	last_yaw = body.rotation.y
	turn = lerpf(turn, clampf(yaw_rate * 0.04 * run_mag, -0.18, 0.18), minf(1.0, 6.0 * delta))
	var idle := 1.0 - minf(run_mag * 2.0, 1.0)
	var t_ms := Time.get_ticks_msec() * 0.001
	torso.position.x = sw * 0.025 * run_mag + sin(t_ms * 0.4) * 0.015 * idle
	head_n.rotation.x = -(torso.rotation.x) * 0.6
	torso.rotation.y = -sw * 0.09 * run_mag
	torso.rotation.z = sw * 0.03 * run_mag - turn
	head_n.rotation.y = sw * 0.05 * run_mag
	body.position.y = (absf(cw) - 0.6) * 0.05 * run_mag + minf(slope, 1.0) * 0.08 - cl * 0.15
	# хромота: при ране ноги корпус проседает на больную сторону
	var limp: float = 1.0 - main.move_factor()
	if limp > 0.05:
		torso.rotation.z += maxf(0.0, sin(phase)) * 0.2 * limp * minf(run_mag * 2.0, 1.0)
		body.position.y -= maxf(0.0, sin(phase)) * 0.06 * limp
	_pose_fall_land()
	_pose_swim(delta, sp)

## Падение: руки в стороны и вверх, ноги поджаты. Приземление: глубокий присед.
func _pose_fall_land() -> void:
	var f := fallb
	if f > 0.01:
		# руки чуть вперёд и в стороны для равновесия, ноги готовятся к приземлению
		arm_l.rotation.x = lerpf(arm_l.rotation.x, -0.7, f)
		arm_r.rotation.x = lerpf(arm_r.rotation.x, -0.6, f)
		arm_l.rotation.z = lerpf(arm_l.rotation.z, 0.45, f)
		arm_r.rotation.z = lerpf(arm_r.rotation.z, -0.45, f)
		leg_l.rotation.x = lerpf(leg_l.rotation.x, -0.35, f)
		leg_r.rotation.x = lerpf(leg_r.rotation.x, 0.05, f)
		knee_l.rotation.x = lerpf(knee_l.rotation.x, 0.6, f)
		knee_r.rotation.x = lerpf(knee_r.rotation.x, 0.35, f)
		torso.rotation.x = lerpf(torso.rotation.x, 0.12, f)
	if land_t > 0.0:
		var k := clampf(land_t * 3.0, 0.0, 1.0) * land_k
		leg_l.rotation.x = lerpf(leg_l.rotation.x, -1.0, k)
		leg_r.rotation.x = lerpf(leg_r.rotation.x, -0.8, k)
		knee_l.rotation.x = lerpf(knee_l.rotation.x, 1.7, k)
		knee_r.rotation.x = lerpf(knee_r.rotation.x, 1.5, k)
		ank_l.rotation.x = lerpf(ank_l.rotation.x, -0.6, k)
		ank_r.rotation.x = lerpf(ank_r.rotation.x, -0.6, k)
		torso.rotation.x = lerpf(torso.rotation.x, 0.6, k)
		arm_l.rotation.x = lerpf(arm_l.rotation.x, -0.9, k)
		arm_r.rotation.x = lerpf(arm_r.rotation.x, -0.9, k)
		body.position.y -= 0.45 * k

## Плавание брассом: тело горизонтально, руки гребут, ноги толкаются.
func _pose_swim(delta: float, sp: float) -> void:
	var b := swimb
	if b < 0.01:
		body.rotation.x = 0.0
		body.position.x = 0.0
		body.position.z = 0.0
		return
	# брасс: гребок → подтягивание рук и ног → толчок ногами и скольжение; на месте — держится вертикально
	var spk := clampf(sp / 1.4, 0.0, 1.0)
	swim_spk = lerpf(swim_spk, spk, minf(1.0, delta * 3.0))
	spk = swim_spk
	cphase += delta * (1.5 + spk * 1.7)
	var ph := fposmod(cphase, TAU) / TAU
	var pull := smoothstep(0.0, 0.35, ph) * (1.0 - smoothstep(0.35, 0.6, ph))
	var tuck := smoothstep(0.3, 0.55, ph) * (1.0 - smoothstep(0.6, 0.72, ph))
	var glide := smoothstep(0.62, 0.75, ph)
	var pitch := b * lerpf(0.15, 1.35, spk)
	body.rotation.x = pitch
	var off := Vector3(0, 0.97 * (1.0 - cos(pitch)), -0.97 * sin(pitch))
	body.position = Basis(Vector3.UP, body.rotation.y) * off + Vector3(0, body.position.y * (1.0 - b) + pull * 0.05 * b, 0)
	var fwd := lerpf(-1.2, -2.8, spk)
	var ax := lerpf(fwd, -1.3, pull)
	var az := 0.15 + pull * 1.0 * (1.0 - tuck)
	var el := -pull * 1.3 - tuck * 0.6
	arm_l.rotation.x = lerpf(arm_l.rotation.x, ax, b)
	arm_r.rotation.x = lerpf(arm_r.rotation.x, ax, b)
	arm_l.rotation.z = lerpf(arm_l.rotation.z, az, b)
	arm_r.rotation.z = lerpf(arm_r.rotation.z, -az, b)
	elb_l.rotation.x = lerpf(elb_l.rotation.x, el, b)
	elb_r.rotation.x = lerpf(elb_r.rotation.x, el, b)
	var hip := -tuck * 0.7 + glide * 0.1
	var kn := tuck * 1.5
	leg_l.rotation.x = lerpf(leg_l.rotation.x, hip, b)
	leg_r.rotation.x = lerpf(leg_r.rotation.x, hip, b)
	leg_l.rotation.z = lerpf(leg_l.rotation.z, tuck * 0.35 + (1.0 - glide) * 0.1, b)
	leg_r.rotation.z = lerpf(leg_r.rotation.z, -tuck * 0.35 - (1.0 - glide) * 0.1, b)
	knee_l.rotation.x = lerpf(knee_l.rotation.x, kn, b)
	knee_r.rotation.x = lerpf(knee_r.rotation.x, kn, b)
	skirt_l.rotation.x = leg_l.rotation.x * 0.5
	skirt_r.rotation.x = leg_r.rotation.x * 0.5
	head_n.rotation.x = -pitch * 0.8

## Сидит на пне или бревне: ноги согнуты, руки на коленях, лёгкое дыхание.
func _process_sit(delta: float) -> void:
	if move_vec.length() > 0.6:
		_stand_up()
		return
	var sp: Vector3 = seat[0]
	var tgt := Vector3(sp.x, sp.y - 0.93, sp.z)
	position = position.lerp(tgt, minf(1.0, 8.0 * delta))
	body.rotation.y = lerp_angle(body.rotation.y, float(seat[1]), minf(1.0, 8.0 * delta))
	sitb = minf(1.0, sitb + delta * 3.0)
	moving = false
	running = false
	run_mag = 0.0
	climbing = 0.0
	var b := sitb
	var br := sin(Time.get_ticks_msec() * 0.0015)
	leg_l.rotation.x = lerpf(leg_l.rotation.x, -1.45, b)
	leg_r.rotation.x = lerpf(leg_r.rotation.x, -1.4, b)
	leg_l.rotation.z = -0.12 * b
	leg_r.rotation.z = 0.12 * b
	knee_l.rotation.x = lerpf(knee_l.rotation.x, 1.45, b)
	knee_r.rotation.x = lerpf(knee_r.rotation.x, 1.35, b)
	ank_l.rotation.x = lerpf(ank_l.rotation.x, 0.0, b)
	ank_r.rotation.x = lerpf(ank_r.rotation.x, 0.0, b)
	skirt_l.rotation.x = leg_l.rotation.x * 0.75
	skirt_r.rotation.x = leg_r.rotation.x * 0.75
	arm_l.rotation.x = lerpf(arm_l.rotation.x, -0.75, b)
	arm_r.rotation.x = lerpf(arm_r.rotation.x, -0.7, b)
	arm_l.rotation.z = 0.12
	arm_r.rotation.z = -0.12
	elb_l.rotation.x = lerpf(elb_l.rotation.x, -0.55, b)
	elb_r.rotation.x = lerpf(elb_r.rotation.x, -0.6, b)
	torso.rotation.x = 0.22 + br * 0.015
	torso.rotation.y = 0.0
	torso.rotation.z = 0.0
	torso.position.x = 0.0
	head_n.rotation.x = -0.15
	head_n.rotation.y = sin(Time.get_ticks_msec() * 0.0004) * 0.35
	body.position = Vector3.ZERO
	body.rotation.x = 0.0

## Лазание по скале: лицом к стене, руки перехватывают выше, ноги ищут упор.
func _process_climb(delta: float) -> void:
	var n: Vector3 = main.ground_normal(position.x, position.z)
	var up_dir := -Vector3(n.x, 0, n.z)
	if up_dir.length() < 0.05:
		state = "walk"
		return
	up_dir = up_dir.normalized()
	var right := up_dir.cross(Vector3.UP).normalized()
	var mag := minf(move_vec.length(), 1.0)
	var d := Vector3.ZERO
	if mag > 0.12:
		d = Vector3(move_vec.x, 0, move_vec.y).normalized().rotated(Vector3.UP, cam_yaw)
	var climb_in := d.dot(up_dir) * mag
	var side := d.dot(right) * mag
	var stam: float = main.stamina
	if stam <= 0.01:
		# силы кончились — срыв
		state = "walk"
		position -= up_dir * 0.6
		return
	var slope := Vector3(n.x, 0, n.z).length() / maxf(n.y, 0.05)
	var dy := climb_in * 0.85 * delta
	var p := position + up_dir * (dy / maxf(slope, 0.6)) + right * side * 0.6 * delta
	var nn: Vector3 = main.ground_normal(p.x, p.z)
	if nn.y > 0.08 and not main.blocked(p.x, p.z, 0.25):
		position.x = p.x
		position.z = p.z
	position.y = main.ground_at(position.x, position.z)
	cphase += absf(dy) * 7.0 + absf(side) * delta * 5.0
	moving = absf(climb_in) > 0.1 or absf(side) > 0.1
	climbing = 1.0
	running = false
	# выбрались наверх или спустились на пологое
	if nn.y >= 0.6 or main.ground_normal(position.x, position.z).y >= 0.6:
		state = "walk"
		position += up_dir * (0.4 if climb_in > 0.0 else -0.2)
		return
	body.rotation.y = lerp_angle(body.rotation.y, atan2(up_dir.x, up_dir.z), minf(1.0, 8.0 * delta))
	climbb = minf(1.0, climbb + delta * 4.0)
	var c := sin(cphase)
	var b := climbb
	arm_l.rotation.x = lerpf(arm_l.rotation.x, -2.5 - c * 0.45, b)
	arm_r.rotation.x = lerpf(arm_r.rotation.x, -2.5 + c * 0.45, b)
	arm_l.rotation.z = 0.15
	arm_r.rotation.z = -0.15
	elb_l.rotation.x = lerpf(elb_l.rotation.x, -0.5 - maxf(0.0, c) * 0.8, b)
	elb_r.rotation.x = lerpf(elb_r.rotation.x, -0.5 - maxf(0.0, -c) * 0.8, b)
	leg_l.rotation.x = lerpf(leg_l.rotation.x, -0.5 + c * 0.45, b)
	leg_r.rotation.x = lerpf(leg_r.rotation.x, -0.5 - c * 0.45, b)
	knee_l.rotation.x = lerpf(knee_l.rotation.x, 0.9 - c * 0.5, b)
	knee_r.rotation.x = lerpf(knee_r.rotation.x, 0.9 + c * 0.5, b)
	skirt_l.rotation.x = leg_l.rotation.x * 0.5
	skirt_r.rotation.x = leg_r.rotation.x * 0.5
	torso.rotation.x = 0.4
	torso.rotation.z = c * 0.05
	head_n.rotation.x = -0.6
	body.position = Vector3(0, -0.1, -0.15)
	body.rotation.x = 0.0


# ---------- готовая модель с анимациями (Quaternius, CC0) ----------
const SK = preload("res://scripts/skin.gd")
const HS = preload("res://scripts/hero_skin.gd")
var model: Node3D
var m_ap: AnimationPlayer
var m_cur := ""
var _last_pos := Vector3.ZERO
var _hspeed := 0.0
var m_sk: Skeleton3D

## Высота таза в текущем кадре анимации (в метрах модели).
func _pelvis_y() -> float:
	return m_sk.get_bone_global_pose(m_sk.find_bone("pelvis")).origin.y

func _build_model() -> void:
	var r := HS.build(self)
	model = r["model"]
	m_ap = r["ap"]
	body.visible = false
	var sk: Skeleton3D = r["sk"]
	m_sk = sk
	var tsk := Transform3D()
	var belt := HS.mat(Color(0.2, 0.13, 0.08))
	var wood := HS.mat(Color(0.5, 0.38, 0.24))
	var roll := HS.mat(Color(0.42, 0.18, 0.13))
	var metal := HS.mat(Color(0.3, 0.3, 0.3))
	var ty: float = sk.get_bone_global_rest(sk.find_bone("spine_02")).origin.y
	var hipy: float = sk.get_bone_global_rest(sk.find_bone("pelvis")).origin.y
	# пояс с ножом, короб за спиной со скаткой и котелком
	_attach(sk, tsk, "pelvis", _loft([[0.0, 0.2, 0.165, 0.0], [0.07, 0.195, 0.16, 0.0]], 22, false, false), belt, Vector3(0, hipy + 0.07, 0.0))
	_attach(sk, tsk, "pelvis", _cyl(0.014, 0.018, 0.22), belt, Vector3(0.21, hipy - 0.02, 0.07), Vector3(0, 0, 0.15))
	_attach(sk, tsk, "spine_03", _loft([[0.0, 0.16, 0.085, 0.0], [0.42, 0.165, 0.09, 0.0], [0.45, 0.15, 0.08, 0.0]], 4), wood, Vector3(0, ty - 0.12, -0.27), Vector3(0, PI * 0.25, 0))
	_attach(sk, tsk, "spine_03", _cyl(0.07, 0.07, 0.48), roll, Vector3(0, ty + 0.22, -0.33), Vector3(0, 0, PI * 0.5))
	_attach(sk, tsk, "spine_03", _cyl(0.06, 0.055, 0.1), metal, Vector3(0.21, ty, -0.26))

## Прикрепить меш к кости так, чтобы в позе покоя он стоял в точке pos (в метрах героя).
func _attach(sk: Skeleton3D, tsk: Transform3D, bone: String, mesh: Mesh, m: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, sc: Vector3 = Vector3.ONE) -> void:
	var bi := sk.find_bone(bone)
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	sk.add_child(ba)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	var want := Transform3D(Basis.from_euler(rot).scaled(sc), pos)
	mi.transform = (tsk * sk.get_bone_global_rest(bi)).affine_inverse() * want
	ba.add_child(mi)

func _play(n: String, sc: float = 1.0, blend: float = 0.25) -> void:
	var a := SK.find_anim(m_ap, [n])
	if a != "" and a != m_cur:
		m_ap.play(a, blend)
		m_cur = a
	m_ap.speed_scale = sc

func _animate_model(delta: float) -> void:
	if model == null:
		return
	var d := position - _last_pos
	_last_pos = position
	_hspeed = lerpf(_hspeed, Vector2(d.x, d.z).length() / maxf(delta, 0.001), minf(1.0, delta * 8.0))
	model.rotation = Vector3(body.rotation.x, body.rotation.y, body.rotation.z)
	model.position = Vector3.ZERO
	if state == "dead":
		_play("Death01", 1.0, 0.2)
		return
	if state == "sit":
		_play("Sitting_Idle", 1.0, 0.4)
		model.rotation = Vector3(0, body.rotation.y, 0)
		# таз точно над сиденьем: смещение позы анимации убираем
		var pl: Vector3 = m_sk.get_bone_global_pose(m_sk.find_bone("pelvis")).origin
		model.position = Vector3(0, 1.03, 0) - model.basis * Vector3(pl.x, pl.y, pl.z + 0.04)
		return
	if swimb > 0.5:
		# поза плавания уже в анимации: только поворот и высота над водой
		model.rotation = Vector3(0, body.rotation.y, 0)
		model.position = Vector3(0, main.water_level(position.x, position.z) - 0.12 - position.y - _pelvis_y(), 0)
		if _hspeed > 0.3:
			_play("Swim_Fwd", clampf(_hspeed / 1.6, 0.6, 1.3))
		else:
			_play("Swim_Idle")
		return
	if state == "climb":
		_play("Walk", 0.6)
		return
	if airborne and vy < -2.5:
		_play("Jump", 1.0, 0.15)
		return
	if _hspeed > 3.6:
		_play("Sprint" if _hspeed > 5.5 else "Jog_Fwd", clampf(_hspeed / (6.0 if _hspeed > 5.5 else 3.8), 0.7, 1.3))
	elif _hspeed > 0.25:
		_play("Walk", clampf(_hspeed / 1.5, 0.5, 1.6))
	else:
		_play("Idle")
