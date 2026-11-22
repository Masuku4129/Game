extends Node3D
## Рыба в реке: косячки хариуса под поверхностью (один MultiMesh на все), стоят против течения,
## покачиваясь, при опасности рассыпаются; изредка рыба выпрыгивает с плеском. Зимой подо льдом —
## меньше косяков, глубже, без прыжков. Медведь ловит рыбу на мелководье у берега (spot_near, catch_at).
## Рисуются только косяки рядом с камерой; хвост виляет в шейдере.

const AM = preload("res://scripts/animal_model.gd")
const SCHOOLS := 18
const PER := 7
const SHOW_R := 55.0
const JUMP_T := 0.75

var main: Node3D
var rng := RandomNumberGenerator.new()
var schools: Array = []
var mm: MultiMesh
var mesh: ArrayMesh
var mat: ShaderMaterial
var splash: CPUParticles3D
var jumper := {}
var _jump_t := 5.0
var _t := 0.0

const SHADER := """
shader_type spatial;
render_mode cull_disabled;
#include "res://shaders/paint/paint.gdshaderinc"
// хвост виляет волной от середины тела назад; у каждой рыбы своя фаза
void vertex() {
	float tail = smoothstep(0.05, -0.2, VERTEX.z);
	float ph = TIME * 8.0 + float(INSTANCE_ID) * 1.7;
	VERTEX.x += sin(ph - VERTEX.z * 12.0) * 0.032 * tail + sin(ph) * 0.004;
}
void fragment() {
	ALBEDO = lin(COLOR.rgb);
	ROUGHNESS = 0.45;
	SPECULAR = 0.45;
}
"""

func setup() -> void:
	rng.seed = 5150
	_make_mesh()
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = SCHOOLS * PER
	var zero := Transform3D(Basis().scaled(Vector3.ONE * 0.0001), Vector3(0, -500, 0))
	for i in mm.instance_count:
		mm.set_instance_transform(i, zero)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.material_override = mat
	# AABB на всю реку: экземпляры двигаются каждый кадр, пересчёт не нужен
	mmi.custom_aabb = AABB(Vector3(-260, -12, -120), Vector3(520, 16, 280))
	add_child(mmi)
	var half: float = main.SIZE * 0.5 - 25.0
	for si in SCHOOLS:
		var offs: Array = []
		for i in PER:
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf()) * 1.4
			offs.append([Vector3(cos(a) * r * 1.4, rng.randf_range(-0.12, 0.05), sin(a) * r * 0.8), rng.randf() * TAU, rng.randf_range(0.8, 1.2)])
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		schools.append({"x": rng.randf_range(-half, half), "l": side * rng.randf_range(10.5, 15.5), "ph": rng.randf() * TAU,
			"offs": offs, "hid": 0, "regen": 0.0, "scare": 0.0, "shown": false})
	splash = CPUParticles3D.new()
	splash.amount = 18
	splash.lifetime = 0.7
	splash.one_shot = true
	splash.explosiveness = 0.95
	splash.emitting = false
	var dm := SphereMesh.new()
	dm.radius = 0.025
	dm.height = 0.05
	dm.radial_segments = 4
	dm.rings = 2
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.9, 0.95, 0.97, 0.85)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.material = wm
	splash.mesh = dm
	splash.direction = Vector3(0, 1, 0)
	splash.spread = 35.0
	splash.initial_velocity_min = 1.2
	splash.initial_velocity_max = 2.6
	splash.gravity = Vector3(0, -9.8, 0)
	splash.scale_amount_min = 0.6
	splash.scale_amount_max = 1.4
	splash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(splash)

## Хариус ~35 см: тёмная спина, серебристые бока, большой спинной плавник, хвост.
func _make_mesh() -> void:
	var b := AM.MB.new()
	var back := Color(0.16, 0.2, 0.18)
	var belly := Color(0.72, 0.74, 0.7)
	b.loft([[-0.16, 0.004, 0.01, 0.0], [-0.12, 0.011, 0.026, 0.0], [-0.05, 0.021, 0.043, 0.003], [0.02, 0.024, 0.048, 0.004],
		[0.09, 0.02, 0.037, 0.0], [0.14, 0.012, 0.022, -0.004], [0.175, 0.003, 0.006, -0.006]], back, belly, 8)
	var fin := Color(0.14, 0.15, 0.17)
	b.tri(Vector3(0, 0, -0.15), Vector3(0, 0.05, -0.215), Vector3(0, -0.045, -0.215), fin)
	b.tri(Vector3(0, 0.04, -0.05), Vector3(0, 0.085, 0.0), Vector3(0, 0.045, 0.05), Color(0.25, 0.2, 0.26))
	b.tri(Vector3(0, -0.035, -0.07), Vector3(0, -0.055, -0.1), Vector3(0, -0.03, -0.11), fin)
	mesh = b.commit()
	var sh := Shader.new()
	sh.code = SHADER
	mat = ShaderMaterial.new()
	mat.shader = sh

static func _zc(x: float) -> float:
	return 70.0 * sin(x / 95.0) + 20.0

## Отдельная рыбина (в пасти медведя, на берегу).
func make_fish() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.scale = Vector3.ONE * 1.2
	return mi

func splash_at(p: Vector3) -> void:
	splash.global_position = Vector3(p.x, main.water_level(p.x, p.z) + 0.02, p.z)
	splash.restart()
	splash.emitting = true

func _ice() -> float:
	return float(main.weather.ice) if main.weather != null else 0.0

func _active(si: int) -> bool:
	# подо льдом остаётся каждый третий косяк
	return _ice() < 0.3 or si % 3 == 0

## Мелководье у берега напротив ближнего косяка (≈0,3 м глубины) — место медвежьей рыбалки.
func spot_near(p: Vector3, r: float) -> Vector3:
	if _ice() > 0.2:
		return Vector3.INF
	var best := Vector3.INF
	var bd := r
	for si in schools.size():
		if not _active(si):
			continue
		var s: Dictionary = schools[si]
		var x: float = s["x"]
		var side := signf(float(s["l"]))
		var zc := _zc(x)
		var d := 22.0
		while d > 8.0:
			var z := zc + side * d
			var dep: float = main.water_level(x, z) - main.height(x, z)
			if dep >= 0.28:
				var q := Vector3(x, main.height(x, z), z)
				var dd := Vector2(q.x - p.x, q.z - p.z).length()
				if dd < bd and not main.blocked(x, z, 0.6):
					bd = dd
					best = q
				break
			d -= 0.4
	return best

## Удар лапой по воде в точке p: base — удача без косяка рядом. Рыба рассыпается.
func catch_at(p: Vector3, base: float) -> bool:
	splash_at(p)
	var best: Dictionary = {}
	var bd := 9.0
	for si in schools.size():
		if not _active(si):
			continue
		var s: Dictionary = schools[si]
		var c := Vector3(float(s["x"]), 0.0, _zc(float(s["x"])) + float(s["l"]))
		var d := Vector2(c.x - p.x, c.z - p.z).length()
		if d < bd:
			bd = d
			best = s
	var chance := base + (0.3 if not best.is_empty() else 0.0) - _ice()
	if not best.is_empty():
		best["scare"] = 2.5
		# косяк тянется к перекату у медведя: в следующий раз — ближе
		best["l"] = lerpf(float(best["l"]), signf(float(best["l"])) * 15.5, 0.3)
	if rng.randf() < chance:
		if not best.is_empty():
			best["hid"] = mini(int(best["hid"]) + 1, PER - 2)
		return true
	return false

func _process(delta: float) -> void:
	if main == null or main.hero == null or main.rig == null:
		return
	_t += delta
	var hp: Vector3 = main.rig.position
	var ice := _ice()
	var winter: bool = main.weather != null and main.weather.season_index() == 1
	var half: float = main.SIZE * 0.5 - 25.0
	var zero := Transform3D(Basis().scaled(Vector3.ONE * 0.0001), Vector3(0, -500, 0))
	for si in schools.size():
		var s: Dictionary = schools[si]
		# косяк медленно ходит вдоль русла и поперёк, держась глубины 0,5–2 м
		var ph: float = s["ph"]
		var x: float = clampf(float(s["x"]) + sin(_t * 0.05 + ph) * 0.25 * delta, -half, half)
		s["x"] = x
		s["scare"] = maxf(0.0, float(s["scare"]) - delta)
		s["regen"] = float(s["regen"]) + delta
		if float(s["regen"]) > 60.0:
			s["regen"] = 0.0
			s["hid"] = maxi(0, int(s["hid"]) - 1)
		var zc := _zc(x)
		var c := Vector3(x, 0.0, zc + float(s["l"]))
		var show := _active(si) and Vector2(c.x - hp.x, c.z - hp.z).length() < SHOW_R
		if not show:
			if s["shown"]:
				s["shown"] = false
				for i in PER:
					mm.set_instance_transform(si * PER + i, zero)
			continue
		s["shown"] = true
		var wl: float = main.water_level(c.x, c.z)
		var dep: float = wl - main.height(c.x, c.z)
		if dep < 0.55:
			s["l"] = float(s["l"]) * (1.0 - delta * 0.3)
		elif dep > 2.0:
			s["l"] = float(s["l"]) * (1.0 + delta * 0.1)
		var fy := wl - (0.55 if ice > 0.3 else 0.2)
		var sc_k := 1.0 + float(s["scare"]) * 0.5
		var hid: int = s["hid"]
		var offs: Array = s["offs"]
		for i in PER:
			var idx := si * PER + i
			if i < hid:
				mm.set_instance_transform(idx, zero)
				continue
			if not jumper.is_empty() and int(jumper["s"]) == si and int(jumper["i"]) == i:
				continue
			var o: Array = offs[i]
			var op: Vector3 = o[0]
			var fph: float = o[1]
			var fs: float = o[2]
			var wob := Vector3(sin(_t * 0.7 + fph) * 0.35, 0.0, sin(_t * 0.53 + fph * 1.3) * 0.25)
			var pos := c + op * sc_k + wob
			pos.y = fy + op.y
			# против течения (течение — к +x), чуть рыщут; испуганные — врассыпную
			var yaw := -PI * 0.5 + sin(_t * 0.9 + fph) * 0.35 + cos(_t * 0.7 + fph) * 0.35 * float(s["scare"])
			mm.set_instance_transform(idx, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * fs), pos))
	_jumps(delta, ice, winter, hp)

## Прыжок: рыба выходит из воды дугой и падает с плеском.
func _jumps(delta: float, ice: float, winter: bool, hp: Vector3) -> void:
	if jumper.is_empty():
		_jump_t -= delta
		if _jump_t > 0.0 or ice > 0.05 or winter:
			return
		_jump_t = rng.randf_range(4.0, 12.0)
		var cand: Array = []
		for si in schools.size():
			if schools[si]["shown"]:
				cand.append(si)
		if cand.is_empty():
			return
		var si2: int = cand[rng.randi() % cand.size()]
		var s: Dictionary = schools[si2]
		var x: float = s["x"]
		var a := Vector3(x + rng.randf_range(-1.0, 1.0), 0.0, _zc(x) + float(s["l"]) + rng.randf_range(-1.0, 1.0))
		a.y = main.water_level(a.x, a.z) - 0.1
		var yaw := rng.randf() * TAU
		var b := a + Vector3(sin(yaw), 0.0, cos(yaw)) * rng.randf_range(0.8, 1.5)
		jumper = {"s": si2, "i": PER - 1, "t": 0.0, "a": a, "b": b, "yaw": yaw, "h": rng.randf_range(0.4, 0.8)}
		splash_at(a)
		if main.sfx != null and Vector2(a.x - hp.x, a.z - hp.z).length() < 40.0:
			main.sfx.play_at("splash", a, -4.0, rng.randf_range(1.2, 1.5))
		return
	var t: float = float(jumper["t"]) + delta
	jumper["t"] = t
	var k := t / JUMP_T
	var idx: int = int(jumper["s"]) * PER + int(jumper["i"])
	if k >= 1.0:
		var bp: Vector3 = jumper["b"]
		splash_at(bp)
		if main.sfx != null:
			main.sfx.play_at("splash", bp, -2.0, rng.randf_range(1.1, 1.4))
		jumper = {}
		return
	var pa: Vector3 = jumper["a"]
	var pb: Vector3 = jumper["b"]
	var p := pa.lerp(pb, k) + Vector3(0, sin(k * PI) * float(jumper["h"]), 0)
	var bs := Basis(Vector3.UP, float(jumper["yaw"])) * Basis(Vector3.RIGHT, -cos(k * PI) * 0.9)
	mm.set_instance_transform(idx, Transform3D(bs, p))
