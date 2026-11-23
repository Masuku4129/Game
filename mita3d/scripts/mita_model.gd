class_name MitaModel
extends Node3D
## Модель Миты: взрослая женщина ~1.72 м, лицом к -Z, правая рука = +X.
## Тело собрано из плавных «лофтов» (сечения-эллипсы вдоль оси), суставы лежат в J для FK-анимации.

const SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 albedo : source_color = vec4(0.05, 0.04, 0.1, 1.0);
uniform vec4 rim_color : source_color = vec4(0.3, 0.38, 1.0, 1.0);
uniform float rim_power = 2.4;
uniform float rim_strength = 1.0;
uniform vec4 glow : source_color = vec4(0.0);
uniform float glow_energy = 0.0;
void fragment() {
	ALBEDO = albedo.rgb;
	float f = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);
	EMISSION = rim_color.rgb * f * rim_strength + glow.rgb * glow_energy;
	ROUGHNESS = 0.8;
}
"""

var J := {}
var _sh: Shader
var M := {}

func mat(col: Color, rim := 1.0, glow := Color(0, 0, 0), ge := 0.0, rimc := Color(0.32, 0.4, 1.0)) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _sh
	m.set_shader_parameter("albedo", col)
	m.set_shader_parameter("rim_strength", rim)
	m.set_shader_parameter("rim_color", rimc)
	m.set_shader_parameter("glow", glow)
	m.set_shader_parameter("glow_energy", ge)
	return m

func _add(parent: Node3D, mesh: Mesh, m: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, sc := Vector3.ONE) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = m
	n.position = pos
	n.rotation_degrees = rot
	n.scale = sc
	parent.add_child(n)
	return n

func _joint(parent: Node3D, nm: String, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.name = nm
	j.position = pos
	parent.add_child(j)
	J[nm] = j
	return j

## rings: [[y, rx, rz, ox, oz], ...] — сечения вдоль оси Y.
func _loft(parent: Node3D, rings: Array, m: Material, sides := 16, pos := Vector3.ZERO, rot := Vector3.ZERO, sc := Vector3.ONE) -> MeshInstance3D:
	var rs := rings.duplicate()
	if float(rs[0][0]) < float(rs[rs.size() - 1][0]):
		rs.reverse()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := rs.size()
	for r in rs:
		for s in sides:
			var a := TAU * float(s) / float(sides)
			st.add_vertex(Vector3(float(r[3]) + float(r[1]) * cos(a), float(r[0]), float(r[4]) + float(r[2]) * sin(a)))
	for i in n - 1:
		for s in sides:
			var s2 := (s + 1) % sides
			var a0 := i * sides + s
			var b0 := i * sides + s2
			var a1 := (i + 1) * sides + s
			var b1 := (i + 1) * sides + s2
			st.add_index(a0); st.add_index(b0); st.add_index(a1)
			st.add_index(b0); st.add_index(b1); st.add_index(a1)
	# крышки
	var top: Array = rs[0]
	var bot: Array = rs[n - 1]
	var ct := sides * n
	st.add_vertex(Vector3(float(top[3]), float(top[0]), float(top[4])))
	st.add_vertex(Vector3(float(bot[3]), float(bot[0]), float(bot[4])))
	for s in sides:
		var s2 := (s + 1) % sides
		st.add_index(ct); st.add_index(s2); st.add_index(s)
		st.add_index(ct + 1); st.add_index((n - 1) * sides + s); st.add_index((n - 1) * sides + s2)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	mi.position = pos
	mi.rotation_degrees = rot
	mi.scale = sc
	parent.add_child(mi)
	return mi

func _ball(parent: Node3D, r: float, m: Material, pos := Vector3.ZERO, sc := Vector3.ONE) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 14
	s.rings = 8
	return _add(parent, s, m, pos, Vector3.ZERO, sc)

func _ribbon(parent: Node3D, pts: Array, w0: float, w1: float, m: Material, side := Vector3.RIGHT) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := pts.size()
	for i in n:
		var t := float(i) / float(n - 1)
		var w := lerpf(w0, w1, pow(t, 0.75)) * 0.5
		var p: Vector3 = pts[i]
		st.set_normal(Vector3(0, 0, -1))
		st.add_vertex(p - side * w)
		st.set_normal(Vector3(0, 0, -1))
		st.add_vertex(p + side * w)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	parent.add_child(mi)
	return mi

func _ready() -> void:
	_sh = Shader.new()
	_sh.code = SHADER
	build()

func build() -> void:
	var cloth := mat(Color(0.075, 0.062, 0.15), 1.3)
	var cloth2 := mat(Color(0.05, 0.04, 0.105), 1.1)
	var skin := mat(Color(0.8, 0.78, 0.94), 0.9, Color(0, 0, 0), 0.0, Color(0.55, 0.6, 1.0))
	var hair := mat(Color(0.03, 0.025, 0.06), 1.9, Color(0, 0, 0), 0.0, Color(0.5, 0.55, 1.0))
	var hairr := mat(Color(0.03, 0.025, 0.06), 0.12, Color(0, 0, 0), 0.0, Color(0.5, 0.55, 1.0))
	var boot := mat(Color(0.05, 0.04, 0.09), 1.4)
	var strap := mat(Color(0.2, 0.15, 0.42), 1.0)
	var purple := mat(Color(0.34, 0.16, 0.8), 1.0, Color(0.4, 0.2, 1.0), 0.7)
	var eye := mat(Color(0.2, 0.4, 1.0), 0.0, Color(0.25, 0.5, 1.0), 1.7)
	var dark := mat(Color(0.02, 0.015, 0.04), 0.3)
	var lips := mat(Color(0.5, 0.25, 0.36), 0.3)
	var bladem := mat(Color(0.92, 0.94, 1.0), 0.0, Color(0.7, 0.75, 1.0), 2.6)

	# --- таз и нижняя часть торса (куртка + пояс)
	var hips := _joint(self, "hips", Vector3(0, 0.95, 0))
	_loft(hips, [[-0.13, 0.12, 0.09, 0, 0.0], [-0.03, 0.17, 0.115, 0, 0.005], [0.04, 0.16, 0.11, 0, 0.0], [0.12, 0.118, 0.088, 0, -0.004], [0.22, 0.122, 0.09, 0, -0.006], [0.31, 0.128, 0.094, 0, -0.008]], cloth, 18)
	# длинные полы куртки (спереди и сзади)
	_loft(hips, [[0.02, 0.17, 0.12, 0, 0.01], [-0.18, 0.21, 0.15, 0, 0.02], [-0.42, 0.22, 0.14, 0, 0.04]], cloth2, 18)
	var belt := TorusMesh.new()
	belt.inner_radius = 0.118
	belt.outer_radius = 0.137
	_add(hips, belt, strap, Vector3(0, 0.1, 0), Vector3.ZERO, Vector3(1.04, 1.0, 0.8))
	_add(hips, BoxMesh.new(), purple, Vector3(0.02, 0.1, -0.1), Vector3.ZERO, Vector3(0.05, 0.05, 0.02))
	var spine := _joint(hips, "spine", Vector3(0, 0.1, 0))
	var chest := _joint(spine, "chest", Vector3(0, 0.2, 0))
	# --- грудная клетка, плечи, шея
	_loft(chest, [[0.0, 0.126, 0.092, 0, -0.005], [0.06, 0.145, 0.108, 0, -0.014], [0.12, 0.155, 0.108, 0, -0.012], [0.165, 0.172, 0.09, 0, 0.0], [0.205, 0.1, 0.07, 0, 0.0], [0.24, 0.052, 0.05, 0, 0.0]], cloth, 18)
	# воротник-капюшон
	_loft(chest, [[0.2, 0.085, 0.075, 0, 0.012], [0.25, 0.075, 0.07, 0, 0.01], [0.3, 0.07, 0.066, 0, 0.0]], cloth2, 14)
	# ремешок крест-накрест на груди
	var bs := _add(chest, BoxMesh.new(), strap, Vector3(0, 0.1, -0.1), Vector3(0, 0, -35), Vector3(0.03, 0.34, 0.02))
	var neck := _joint(chest, "neck", Vector3(0, 0.2, 0))
	_loft(neck, [[0.14, 0.04, 0.042, 0, 0], [0.04, 0.043, 0.045, 0, 0.0], [-0.02, 0.05, 0.05, 0, 0.0]], skin, 12)
	var head := _joint(neck, "head", Vector3(0, 0.15, 0))
	# голова: яйцо с подбородком, лицо слегка вперёд (−Z)
	_loft(head, [[0.125, 0.03, 0.04, 0, 0.0], [0.105, 0.07, 0.078, 0, 0.0], [0.06, 0.088, 0.095, 0, 0.0], [0.0, 0.09, 0.098, 0, -0.004], [-0.04, 0.083, 0.09, 0, -0.01], [-0.08, 0.06, 0.068, 0, -0.022], [-0.108, 0.03, 0.03, 0, -0.04], [-0.12, 0.012, 0.012, 0, -0.045]], skin, 18)
	# глаза (миндалевидные, светятся), брови, нос, губы
	for sx in [-1.0, 1.0]:
		_ball(head, 0.02, eye, Vector3(sx * 0.038, 0.012, -0.088), Vector3(1.25, 0.55, 0.3))
		_add(head, BoxMesh.new(), dark, Vector3(sx * 0.04, 0.036, -0.094), Vector3(0, 0, -sx * 12), Vector3(0.05, 0.006, 0.01))
		_add(head, BoxMesh.new(), dark, Vector3(sx * 0.04, 0.02, -0.094), Vector3(0, 0, 0), Vector3(0.046, 0.005, 0.008))
	_ball(head, 0.014, skin, Vector3(0, -0.018, -0.1), Vector3(0.8, 1.1, 1.0))
	_ball(head, 0.016, lips, Vector3(0, -0.062, -0.088), Vector3(1.6, 0.5, 0.6))
	# волосы: шапка, пробор-чёлка, боковые пряди, длинные сзади
	_ball(head, 0.103, hair, Vector3(0, 0.03, 0.028), Vector3(1.0, 1.02, 1.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	for i in 9:
		var f := float(i) / 8.0 - 0.5
		var pts := []
		for k in 4:
			var t := float(k) / 3.0
			pts.append(Vector3(f * 0.16 + f * 0.05 * t, 0.12 - t * 0.075, -0.07 - t * 0.04 + abs(f) * 0.04))
		_ribbon(head, pts, 0.04, 0.006, hairr)
	for sx in [-1.0, 1.0]:
		for q in 3:
			var pts := []
			for k in 6:
				var t := float(k) / 5.0
				pts.append(Vector3(sx * (0.095 + q * 0.008 + 0.015 * sin(t * 3.0)), 0.07 - t * 0.38, -0.045 - q * 0.015 - t * 0.02))
			_ribbon(head, pts, 0.032, 0.006, hairr, Vector3(0, 0, 1))
	var back := _joint(head, "hair", Vector3(0, 0.07, 0.07))
	_loft(back, [[0.0, 0.1, 0.05, 0, 0.0], [-0.2, 0.125, 0.06, 0, 0.03], [-0.5, 0.13, 0.05, 0, 0.06], [-0.8, 0.09, 0.03, 0, 0.1], [-0.95, 0.02, 0.01, 0, 0.12]], hair, 14)
	for i in 18:
		var f := float(i) / 17.0 - 0.5
		var L := 0.6 + 0.35 * rng.randf()
		var pts := []
		for k in 7:
			var t := float(k) / 6.0
			pts.append(Vector3(f * 0.3 * (1.0 + t * 0.9) + 0.03 * sin(t * 7.0 + i), -t * L, 0.06 + 0.12 * t * t + 0.05 * t))
		var rb := _ribbon(back, pts, 0.07, 0.006, hairr)
		rb.rotation_degrees = Vector3(0, f * 85.0, f * 14.0)
	# --- ноги
	for side in [-1, 1]:
		var s := "R" if side > 0 else "L"
		var th := _joint(hips, "thigh" + s, Vector3(side * 0.095, -0.03, 0))
		_loft(th, [[0.04, 0.095, 0.1, 0, 0], [-0.08, 0.112, 0.112, 0, 0], [-0.25, 0.1, 0.098, 0, -0.005], [-0.45, 0.082, 0.082, 0, -0.01]], cloth, 16)
		var kn := _joint(th, "shin" + s, Vector3(0, -0.45, 0))
		_loft(kn, [[0.03, 0.082, 0.082, 0, 0], [-0.1, 0.082, 0.088, 0, 0.012], [-0.25, 0.088, 0.09, 0, 0.005], [-0.4, 0.118, 0.12, 0, -0.01]], cloth, 16)
		var an := _joint(kn, "foot" + s, Vector3(0, -0.4, 0))
		_loft(an, [[0.06, 0.1, 0.1, 0, 0.0], [0.02, 0.112, 0.114, 0, 0.0], [-0.03, 0.07, 0.07, 0, 0.0]], strap, 14)
		# ботинок: лофт вдоль Z (поворот −90° по X: +Y -> -Z)
		_loft(an, [[0.0, 0.052, 0.07, 0, 0.0], [0.09, 0.058, 0.048, 0, 0.0], [0.17, 0.056, 0.04, 0, 0.0], [0.25, 0.04, 0.03, 0, 0.0], [0.285, 0.018, 0.014, 0, 0.0]], boot, 12, Vector3(0, -0.035, 0.07), Vector3(-90, 0, 0))
	# --- руки
	for side in [-1, 1]:
		var s := "R" if side > 0 else "L"
		var sh := _joint(chest, "shoulder" + s, Vector3(side * 0.172, 0.14, 0))
		_ball(sh, 0.066, cloth, Vector3.ZERO)
		_loft(sh, [[0.03, 0.062, 0.062, 0, 0], [-0.1, 0.07, 0.07, 0, 0], [-0.3, 0.056, 0.056, 0, 0]], cloth, 14)
		var el := _joint(sh, "elbow" + s, Vector3(0, -0.3, 0))
		_loft(el, [[0.03, 0.056, 0.056, 0, 0], [-0.1, 0.07, 0.07, 0, 0], [-0.26, 0.074, 0.076, 0, 0]], cloth, 14)
		_loft(el, [[-0.235, 0.076, 0.078, 0, 0], [-0.27, 0.078, 0.08, 0, 0]], cloth2, 14)
		var hd := _joint(el, "hand" + s, Vector3(0, -0.27, 0))
		_loft(hd, [[0.02, 0.034, 0.024, 0, 0], [-0.04, 0.04, 0.026, 0, 0], [-0.09, 0.034, 0.02, 0, 0], [-0.115, 0.012, 0.01, 0, 0]], skin, 10)
		_ball(hd, 0.014, skin, Vector3(side * -0.03, -0.045, -0.02), Vector3(0.8, 1.6, 0.8))
	# --- катана (правая рука)
	var kat := Node3D.new()
	kat.name = "katana"
	J["handR"].add_child(kat)
	J["katana"] = kat
	kat.position = Vector3(0, -0.05, 0)
	_loft(kat, [[0.12, 0.02, 0.02, 0, 0], [0.12, 0.022, 0.022, 0, 0], [-0.1, 0.02, 0.02, 0, 0]], purple, 8)
	_loft(kat, [[0.135, 0.021, 0.021, 0, 0], [0.12, 0.024, 0.024, 0, 0]], strap, 8)
	_loft(kat, [[-0.1, 0.05, 0.05, 0, 0], [-0.112, 0.05, 0.05, 0, 0]], strap, 14)
	var bp := []
	for k in 10:
		var t := float(k) / 9.0
		bp.append(Vector3(0, -0.112 - t * 0.9, -0.08 * t * t))
	_ribbon(kat, bp, 0.034, 0.014, bladem, Vector3(1, 0, 0))
	_ribbon(kat, bp, 0.034, 0.014, bladem, Vector3(0, 0, 1))
	var bl := OmniLight3D.new()
	bl.light_color = Color(0.6, 0.65, 1.0)
	bl.light_energy = 1.6
	bl.omni_range = 3.0
	kat.add_child(bl)
	bl.position = Vector3(0, -0.5, 0)
	# ножны на левом бедре
	var scb := _joint(hips, "scabbard", Vector3(-0.17, 0.02, -0.01))
	_loft(scb, [[0.1, 0.019, 0.019, 0, 0], [-0.6, 0.021, 0.021, 0, 0], [-0.72, 0.014, 0.014, 0, 0]], cloth2, 8, Vector3(0, 0, 0))
	_loft(scb, [[0.12, 0.03, 0.03, 0, 0], [0.09, 0.03, 0.03, 0, 0]], purple, 10)
	scb.rotation_degrees = Vector3(-72, 0, 10)
	pose_idle()

func pose_idle() -> void:
	var d := func(n: String, x := 0.0, y := 0.0, z := 0.0): (J[n] as Node3D).rotation_degrees = Vector3(x, y, z)
	d.call("hips", 0, 0, 0)
	d.call("spine", 3, 0, 0)
	d.call("chest", 3, 0, 0)
	d.call("head", -4, 0, 0)
	d.call("thighL", -8, 0, -3); d.call("shinL", 10, 0, 0)
	d.call("thighR", 14, 0, 3); d.call("shinR", -22, 0, 0)
	d.call("footL", -2, 0, 0); d.call("footR", 8, 0, 0)
	d.call("shoulderL", 12, 0, -8); d.call("elbowL", 25, 0, 0)
	d.call("shoulderR", 28, 0, 12); d.call("elbowR", 55, 0, 0)
	d.call("handR", 0, 0, 0)
	(J["katana"] as Node3D).rotation_degrees = Vector3(-70, 0, 0)
	(J["hair"] as Node3D).rotation_degrees = Vector3(8, 0, 0)
