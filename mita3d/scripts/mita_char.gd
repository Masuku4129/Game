class_name MitaChar
extends MitaModel
## Мита на анатомической сетке (MakeHuman, CC0) со скелетом из 163 костей. Лицо смотрит в +Z модели,
## корень повёрнут на 180°, так что в мире персонаж смотрит в -Z.

const BODY_SHADER := """
shader_type spatial;
uniform vec4 rim_color : source_color = vec4(0.32, 0.4, 1.0, 1.0);
uniform float rim_power = 2.4;
uniform float rim_strength = 0.6;
void fragment() {
	ALBEDO = COLOR.rgb;
	float f = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);
	EMISSION = rim_color.rgb * f * rim_strength;
	float sk = step(0.6, COLOR.r);
	EMISSION += vec3(0.30, 0.17, 0.12) * sk;
	ALBEDO = mix(ALBEDO, vec3(1.0, 0.8, 0.68), sk * 0.5);
	ROUGHNESS = 0.75;
}
"""

var skel: Skeleton3D
var rootn: Node3D
var att := {}
var blade_mat: ShaderMaterial
var body_mat: ShaderMaterial
var blade_light: OmniLight3D
var blade_local := Vector3(0.25, -0.35, -0.9)

func _ready() -> void:
	_sh = Shader.new()
	_sh.code = SHADER
	build()

func _attach(bone: String) -> BoneAttachment3D:
	if att.has(bone):
		return att[bone]
	var a := BoneAttachment3D.new()
	a.bone_name = bone
	skel.add_child(a)
	att[bone] = a
	return a

func _find(n: Node, cls: String) -> Node:
	if n.get_class() == cls:
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r != null:
			return r
	return null

func build() -> void:
	rootn = (load("res://models/MhBody.glb") as PackedScene).instantiate()
	rootn.rotation_degrees.y = 180.0
	add_child(rootn)
	skel = _find(rootn, "Skeleton3D")
	var mi: MeshInstance3D = _find(rootn, "MeshInstance3D")
	var bs := Shader.new()
	bs.code = BODY_SHADER
	var bm := ShaderMaterial.new()
	bm.shader = bs
	body_mat = bm
	mi.material_override = bm
	var cloth := mat(Color(0.075, 0.062, 0.15), 1.3)
	var cloth2 := mat(Color(0.05, 0.04, 0.105), 1.1)
	var hair := mat(Color(0.03, 0.025, 0.06), 1.9, Color(0, 0, 0), 0.0, Color(0.5, 0.55, 1.0))
	var hairr := mat(Color(0.03, 0.025, 0.06), 0.12, Color(0, 0, 0), 0.0, Color(0.5, 0.55, 1.0))
	var strap := mat(Color(0.2, 0.15, 0.42), 1.0)
	var purple := mat(Color(0.34, 0.16, 0.8), 1.0, Color(0.4, 0.2, 1.0), 0.7)
	var eye := mat(Color(0.2, 0.4, 1.0), 0.0, Color(0.25, 0.5, 1.0), 1.9)
	var dark := mat(Color(0.02, 0.015, 0.04), 0.3)
	var bladem := mat(Color(0.92, 0.94, 1.0), 0.0, Color(0.7, 0.75, 1.0), 2.6)
	# --- голова: глаза, брови, причёска (в координатах модели: лицо смотрит в +Z)
	var h := _attach("head")
	for sx in [-1.0, 1.0]:
		_ball(h, 0.0135, eye, Vector3(sx * 0.031, 0.031, 0.1), Vector3(1.4, 0.75, 0.5))
		_add(h, BoxMesh.new(), dark, Vector3(sx * 0.033, 0.052, 0.108), Vector3(0, 0, sx * 10), Vector3(0.045, 0.006, 0.008))
	_ball(h, 0.1, hair, Vector3(0, 0.07, -0.022), Vector3(1.0, 1.04, 1.1))
	for sx in [-1.0, 1.0]:
		for q in 3:
			var pts := []
			for k in 6:
				var t := float(k) / 5.0
				pts.append(Vector3(sx * (0.088 + q * 0.007 + 0.012 * sin(t * 3.0)), 0.1 - t * 0.34, 0.05 - q * 0.015 - t * 0.02))
			_ribbon(h, pts, 0.03, 0.006, hairr, Vector3(0, 0, 1))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var back := Node3D.new()
	h.add_child(back)
	back.position = Vector3(0, 0.1, -0.075)
	_loft(back, [[0.0, 0.095, 0.045, 0, 0.0], [-0.25, 0.12, 0.06, 0, -0.04], [-0.55, 0.125, 0.05, 0, -0.07], [-0.8, 0.09, 0.03, 0, -0.1], [-0.95, 0.02, 0.01, 0, -0.12]], hair, 14)
	for i in 18:
		var f := float(i) / 17.0 - 0.5
		var L := 0.7 + 0.3 * rng.randf()
		var pts := []
		for k in 7:
			var t := float(k) / 6.0
			pts.append(Vector3(f * 0.28 * (1.0 + t * 0.8) + 0.03 * sin(t * 7.0 + i), -t * L, -0.05 - 0.1 * t * t - 0.04 * t))
		var rb := _ribbon(back, pts, 0.07, 0.006, hairr)
		rb.rotation_degrees = Vector3(0, f * 70.0, f * 12.0)
	# --- полы куртки на тазу
	var pv := _attach("root")
	_loft(pv, [[0.06, 0.17, 0.12, 0, -0.01], [-0.2, 0.22, 0.16, 0, -0.02], [-0.5, 0.23, 0.16, 0, -0.03]], cloth2, 18)
	var belt := TorusMesh.new()
	belt.inner_radius = 0.15
	belt.outer_radius = 0.168
	_add(pv, belt, strap, Vector3(0, 0.1, -0.01), Vector3.ZERO, Vector3(1.0, 1.0, 0.75))
	# --- катана в правой руке (wrist.R), ножны на левом бедре
	var wr := _attach("wrist.R")
	var kat := Node3D.new()
	kat.name = "katana"
	wr.add_child(kat)
	J["katana"] = kat
	_loft(kat, [[0.1, 0.02, 0.02, 0, 0], [-0.12, 0.02, 0.02, 0, 0]], purple, 8, Vector3(0, -0.0, 0))
	_loft(kat, [[-0.12, 0.05, 0.05, 0, 0], [-0.132, 0.05, 0.05, 0, 0]], strap, 14)
	var bp := []
	for k in 10:
		var t := float(k) / 9.0
		bp.append(Vector3(0, -0.132 - t * 0.9, 0.08 * t * t))
	_ribbon(kat, bp, 0.034, 0.014, bladem, Vector3(1, 0, 0))
	_ribbon(kat, bp, 0.034, 0.014, bladem, Vector3(0, 0, 1))
	blade_mat = bladem
	var bl := OmniLight3D.new()
	blade_light = bl
	bl.light_color = Color(0.6, 0.65, 1.0)
	bl.light_energy = 1.6
	bl.omni_range = 3.0
	kat.add_child(bl)
	bl.position = Vector3(0, -0.5, 0)
	var sc := _attach("root")
	var scb := Node3D.new()
	sc.add_child(scb)
	_loft(scb, [[0.1, 0.019, 0.019, 0, 0], [-0.6, 0.021, 0.021, 0, 0], [-0.72, 0.014, 0.014, 0, 0]], cloth2, 8)
	_loft(scb, [[0.04, 0.026, 0.026, 0, 0], [0.0, 0.026, 0.026, 0, 0]], purple, 10)
	scb.position = Vector3(0.2, 0.02, -0.03)
	scb.rotation_degrees = Vector3(72, 0, -10)
	pose_idle()

func rot(b: String, x := 0.0, y := 0.0, z := 0.0) -> void:
	var i := skel.find_bone(b)
	if i >= 0:
		skel.set_bone_pose_rotation(i, Quaternion.from_euler(Vector3(deg_to_rad(x), deg_to_rad(y), deg_to_rad(z))))

func pose_idle() -> void:
	# боевая стойка: правая нога сзади, катана в правой руке вперёд-вниз
	rot("spine03", -6, 0, 0); rot("head", 8, 0, 0)
	rot("upperleg01.L", -18, 0, 0); rot("lowerleg01.L", 22, 0, 0); rot("foot.L", -4, 0, 0)
	rot("upperleg01.R", 12, 0, 6); rot("lowerleg01.R", 24, 0, 0); rot("foot.R", 4, 0, 0)
	rot("upperarm01.R", 0, 35, 10); rot("lowerarm01.R", 0, 70, 0)
	rot("upperarm01.L", 0, -25, -10); rot("lowerarm01.L", 0, -60, 0)

func _process(_d: float) -> void:
	# клинок катаны направлен вперёд-вниз в мировых координатах, независимо от позы руки
	var k: Node3D = J.get("katana")
	if k == null or not k.is_inside_tree():
		return
	var d: Vector3 = (global_transform.basis * blade_local).normalized()
	var y := -d
	var x := Vector3.UP.cross(y).normalized()
	var z := x.cross(y).normalized()
	k.global_basis = Basis(x, y, z)

func set_style_color(c: Color) -> void:
	blade_mat.set_shader_parameter("glow", c)
	blade_light.light_color = c
	body_mat.set_shader_parameter("rim_color", c.lerp(Color(0.32, 0.4, 1.0), 0.35))
