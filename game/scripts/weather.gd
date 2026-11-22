extends Node
## Календарь, сезоны и погода. Считает температуру, облачность, осадки, туман, ветер,
## снежный покров, мокрость, осеннюю листву, лёд на реке; рисует дождь и снег вокруг камеры.

const DAYS_PER_SEASON := 12
const SEASONS := ["Осень", "Зима", "Весна", "Лето"]

var main: Node3D
var rng := RandomNumberGenerator.new()

# текущее состояние
var kind := "Ясно"
var next_change := 6.0  # игровых часов до смены
var cloud := 0.1
var precip := 0.0
var fogv := 0.0
var wind := 0.5
var temp := 8.0
var snow := 0.0
var wet := 0.0
var autumn := 0.0
var leaf_drop := 0.0
var ice := 0.0
var t_cloud := 0.1
var t_precip := 0.0
var t_fog := 0.0
var t_wind := 0.5
var _hours_acc := 0.0

var rain: GPUParticles3D
var flakes: GPUParticles3D

func _ready() -> void:
	rng.seed = 2026
	rain = _make_particles(true)
	flakes = _make_particles(false)

func _make_particles(is_rain: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(16, 1, 16)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 4.0 if is_rain else 25.0
	pm.initial_velocity_min = 16.0 if is_rain else 0.6
	pm.initial_velocity_max = 20.0 if is_rain else 1.4
	pm.gravity = Vector3(0.8, -12.0, 0.3) if is_rain else Vector3(0.4, -1.3, 0.2)
	p.process_material = pm
	var q: PrimitiveMesh
	if is_rain:
		var qm := QuadMesh.new()
		qm.size = Vector2(0.02, 0.5)
		q = qm
	else:
		var sm := SphereMesh.new()
		sm.radius = 0.018
		sm.height = 0.036
		sm.radial_segments = 4
		sm.rings = 2
		q = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.75, 0.8, 0.85, 0.35) if is_rain else Color(0.97, 0.98, 1.0, 0.9)
	if is_rain:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.vertex_color_use_as_albedo = false
	q.material = m
	p.draw_pass_1 = q
	p.amount = 2600 if is_rain else 3500
	p.lifetime = 1.4 if is_rain else 9.0
	p.preprocess = 2.0 if is_rain else 9.0
	p.visibility_aabb = AABB(Vector3(-30, -40, -30), Vector3(60, 60, 60))
	p.local_coords = false
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p

## Положение в году 0..1 (0 = начало осени).
func year_pos() -> float:
	var d: float = float(main.day_count - 1) + main.t_hours / 24.0
	return fposmod(d / (DAYS_PER_SEASON * 4.0), 1.0)

func season_index() -> int:
	return int(year_pos() * 4.0) % 4

func season_name() -> String:
	return SEASONS[season_index()]

## Средняя суточная температура по году (опорные точки каждые пол-сезона).
func base_temp(y: float) -> float:
	var pts := [8.0, 1.0, -8.0, -24.0, -14.0, 2.0, 15.0, 20.0, 8.0]
	var f := y * 8.0
	var i := int(f)
	return lerpf(pts[i], pts[i + 1], f - i)

func _pick_weather() -> void:
	var s := season_index()
	# вероятности: ясно, облачно, осадки, туман, буря
	var w: Array = [[0.25, 0.3, 0.3, 0.1, 0.05], [0.2, 0.25, 0.4, 0.05, 0.1], [0.3, 0.3, 0.25, 0.1, 0.05], [0.45, 0.25, 0.15, 0.05, 0.1]][s]
	var r := rng.randf()
	var k := 0
	while k < 4 and r > w[k]:
		r -= w[k]
		k += 1
	match k:
		0:
			t_cloud = rng.randf_range(0.0, 0.2); t_precip = 0.0; t_fog = 0.0; t_wind = rng.randf_range(0.3, 0.7)
		1:
			t_cloud = rng.randf_range(0.5, 0.8); t_precip = 0.0; t_fog = 0.0; t_wind = rng.randf_range(0.5, 1.0)
		2:
			t_cloud = 0.85; t_precip = rng.randf_range(0.4, 0.8); t_fog = 0.1; t_wind = rng.randf_range(0.6, 1.1)
		3:
			t_cloud = 0.6; t_precip = 0.0; t_fog = rng.randf_range(0.6, 1.0); t_wind = 0.15
		4:
			t_cloud = 1.0; t_precip = 1.0; t_fog = 0.25; t_wind = rng.randf_range(1.6, 2.2)
	next_change = rng.randf_range(3.0, 9.0)

func _kind_name() -> String:
	var cold := temp < 0.5
	if precip > 0.75 and wind > 1.4:
		return "Метель" if cold else "Гроза"
	if precip > 0.15:
		return "Снег" if cold else "Дождь"
	if fogv > 0.4:
		return "Туман"
	if cloud > 0.45:
		return "Облачно"
	return "Ясно"

## Перемотка: прожить hours игровых часов шагами по полчаса.
func fast_forward(hours: float) -> void:
	var left := hours
	while left > 0.0:
		var dh := minf(0.5, left)
		main.t_hours += dh
		if main.t_hours >= 24.0:
			main.t_hours -= 24.0
			main.day_count += 1
		step(dh)
		left -= dh

## dh — прошедшие игровые часы.
func step(dh: float) -> void:
	next_change -= dh
	if next_change <= 0.0:
		_pick_weather()
	var k := 1.0 - exp(-dh * 1.2)  # плавный переход за ~1 игровой час
	cloud = lerpf(cloud, t_cloud, k)
	precip = lerpf(precip, t_precip, k)
	fogv = lerpf(fogv, t_fog, k)
	wind = lerpf(wind, t_wind, k)
	var y := year_pos()
	var daily: float = (main.day_factor - 0.5) * 9.0 * (1.0 - cloud * 0.5)
	temp = base_temp(y) + daily - precip * 2.0
	var cold := temp < 0.5
	# снег копится в снегопад, тает в тепло
	if cold and precip > 0.1:
		snow = minf(1.0, snow + precip * dh * 0.09)
	elif temp > 1.0:
		snow = maxf(0.0, snow - (temp * 0.004 + precip * 0.02) * dh)
	# в зимний мороз покров держится и понемногу растёт (позёмка, иней)
	if season_index() == 1 and temp < -2.0:
		snow = minf(maxf(snow, 0.35), snow + dh * 0.015) if snow < 0.95 else snow
	# мокрость: дождь мочит, солнце и ветер сушат
	if not cold and precip > 0.1:
		wet = minf(1.0, wet + precip * dh * 0.8)
	else:
		wet = maxf(0.0, wet - dh * (0.08 + main.day_factor * 0.12) * clampf(temp / 10.0, 0.1, 1.0))
	# река замерзает после нескольких дней мороза
	if temp < -6.0:
		ice = minf(1.0, ice + dh * 0.012)
	elif temp > 0.0:
		ice = maxf(0.0, ice - dh * 0.01 * (1.0 + temp * 0.2))
	# листва: желтеет в первой половине осени, опадает во второй, распускается в конце весны
	var s := y * 4.0
	if s < 1.0:
		autumn = smoothstep(0.05, 0.55, s)
		leaf_drop = smoothstep(0.5, 0.95, s)
	elif s < 2.0:
		autumn = 1.0
		leaf_drop = 1.0
	elif s < 3.0:
		autumn = 0.0
		leaf_drop = 1.0 - smoothstep(2.45, 2.9, s)
	else:
		autumn = smoothstep(3.85, 4.0, s) * 0.2
		leaf_drop = 0.0
	kind = _kind_name()

func update_visual(cam_target: Vector3) -> void:
	var pos := cam_target + Vector3(0, 16.0, 0)
	rain.global_position = pos
	flakes.global_position = pos
	var cold := temp < 0.5
	var amt := clampf(precip * 1.15, 0.0, 1.0)
	rain.emitting = amt > 0.05 and not cold
	flakes.emitting = amt > 0.05 and cold
	rain.amount_ratio = amt
	flakes.amount_ratio = amt
	var pm: ParticleProcessMaterial = flakes.process_material
	pm.gravity = Vector3(wind * 1.2, -1.3, wind * 0.5)
	var pr: ParticleProcessMaterial = rain.process_material
	pr.gravity = Vector3(wind * 2.5, -12.0, wind * 1.0)

## Раздать параметры шейдерам.
func apply(mats: Array, terrain: ShaderMaterial, blade: ShaderMaterial, water: ShaderMaterial) -> void:
	for m in mats:
		m.set_shader_parameter("snow", snow)
		m.set_shader_parameter("wet", wet)
		m.set_shader_parameter("autumn", autumn)
		m.set_shader_parameter("leaf_drop", leaf_drop)
		m.set_shader_parameter("wind", wind)
	terrain.set_shader_parameter("snow", snow)
	terrain.set_shader_parameter("wet", wet)
	terrain.set_shader_parameter("freeze", clampf(-temp * 0.5, 0.0, 1.0))
	terrain.set_shader_parameter("rain", precip if temp >= 0.5 else 0.0)
	blade.set_shader_parameter("snow", snow)
	blade.set_shader_parameter("dry", clampf(autumn * 0.8 + (1.0 - smoothstep(0.0, 0.4, temp)) * 0.3, 0.0, 1.0))
	blade.set_shader_parameter("wind", wind)
	water.set_shader_parameter("ice", ice)
	water.set_shader_parameter("rain", precip if temp >= 0.5 else 0.0)
