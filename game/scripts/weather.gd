extends Node
## Календарь, сезоны и погода. Считает температуру, облачность, осадки, туман, ветер,
## снежный покров, мокрость, осеннюю листву, цветение, туман в низинах, лёд на реке;
## рисует дождь и снег вокруг камеры (остальные эффекты — atmo.gd).

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
var gust := 0.0
var gust_target := 0.0
var gust_timer := 0.0
var wind_angle := 0.0
var wind_angle_target := 0.0
var temp := 8.0
var snow := 0.0
var wet := 0.0
var autumn := 0.0
var leaf_drop := 0.0
var ice := 0.0
## туман в низинах и над рекой: на рассвете, после дождя, в туманную погоду
var mist := 0.0
## цветение черёмухи (поздняя весна)
var blossom := 0.0
var t_cloud := 0.1
var t_precip := 0.0
var t_fog := 0.0
var t_wind := 0.5
var _hours_acc := 0.0
var _gust_clock := 0.0

var rain: GPUParticles3D
var flakes: GPUParticles3D
var atmo

func _ready() -> void:
	rng.seed = int(main.map_seed) + 2026
	rain = _make_particles(true)
	flakes = _make_particles(false)
	atmo = preload("res://scripts/atmo.gd").new()
	atmo.main = main
	atmo.weather = self
	add_child(atmo)

func _make_particles(is_rain: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(16, 1, 16)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 3.0 if is_rain else 25.0
	pm.initial_velocity_min = 16.0 if is_rain else 0.6
	pm.initial_velocity_max = 20.0 if is_rain else 1.4
	pm.gravity = Vector3(0.8, -12.0, 0.3) if is_rain else Vector3(0.4, -1.3, 0.2)
	p.process_material = pm
	var q: PrimitiveMesh
	if is_rain:
		# струйка: вытянута по скорости (с ветром косит), к концам прозрачнее
		var qm := QuadMesh.new()
		qm.size = Vector2(0.03, 0.8)
		q = qm
		pm.scale_min = 0.7
		pm.scale_max = 1.2
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
	m.albedo_color = Color(0.78, 0.83, 0.88, 0.32) if is_rain else Color(0.97, 0.98, 1.0, 0.9)
	if is_rain:
		var gt := GradientTexture2D.new()
		var gr := Gradient.new()
		gr.set_color(0, Color(1, 1, 1, 0))
		gr.set_color(1, Color(1, 1, 1, 0))
		gr.add_point(0.35, Color(1, 1, 1, 1))
		gr.add_point(0.8, Color(1, 1, 1, 0.8))
		gt.gradient = gr
		gt.fill_from = Vector2(0, 0)
		gt.fill_to = Vector2(0, 1)
		gt.width = 4
		gt.height = 64
		m.albedo_texture = gt
		p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	m.vertex_color_use_as_albedo = false
	q.material = m
	p.draw_pass_1 = q
	p.amount = 3000 if is_rain else 3500
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
	# Ветер меняется порывами, а не только постоянной величиной.
	gust_timer -= dh
	if gust_timer <= 0.0:
		gust_timer = rng.randf_range(0.18, 0.9) if t_wind > 1.4 else rng.randf_range(0.6, 2.4)
		gust_target = rng.randf_range(0.0, 0.45) if t_wind < 1.4 else rng.randf_range(0.25, 1.0)
		wind_angle_target = rng.randf_range(-PI, PI)
	wind_angle = lerp_angle(wind_angle, wind_angle_target, clampf(dh * (0.25 + gust * 0.25), 0.0, 1.0))
	gust = lerpf(gust, gust_target, clampf(dh * (1.2 if gust_target > gust else 0.45), 0.0, 1.0))
	wind = clampf(wind + gust * (0.25 if t_wind < 1.4 else 0.5), 0.0, 2.8)
	var y := year_pos()
	var daily: float = (main.day_factor - 0.5) * 9.0 * (1.0 - cloud * 0.5)
	temp = base_temp(y) + daily - precip * 2.0
	var cold := temp < 0.5
	# снег копится в снегопад, тает в тепло
	if cold and precip > 0.1:
		snow = minf(1.0, snow + precip * dh * (0.09 + wind * 0.012))
	elif temp > 1.0:
		snow = maxf(0.0, snow - (temp * 0.004 + precip * 0.02 + wind * 0.003) * dh)
	# в зимний мороз покров держится и понемногу растёт (позёмка, иней)
	if season_index() == 1 and temp < -2.0:
		snow = minf(maxf(snow, 0.35), snow + dh * 0.015) if snow < 0.95 else snow
	# Поверхностная влага: дождь насыщает почву, солнце и ветер испаряют воду,
	# а влажная земля при отрицательной температуре постепенно покрывается коркой.
	var liquid_precip := precip if temp >= 0.5 else precip * 0.18
	var evaporation := (0.025 + main.day_factor * 0.045 + wind * 0.035) * clampf((temp + 5.0) / 18.0, 0.05, 1.0)
	wet = clampf(wet + liquid_precip * dh * (0.72 + (1.0 - wet) * 0.28) - evaporation * dh, 0.0, 1.0)
	if temp < -1.5:
		ice = minf(1.0, ice + dh * (0.004 + wet * 0.012) * clampf(-temp / 4.0, 0.35, 3.5))
	elif temp > 0.0:
		ice = maxf(0.0, ice - dh * (0.008 + temp * 0.006) * (1.0 + wind * 0.15))
	if temp > 0.5 and precip > 0.15:
		snow = maxf(0.0, snow - precip * dh * 0.025)

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
	# цветение черёмухи: когда листва уже распустилась, к концу весны
	blossom = smoothstep(2.55, 2.7, s) * (1.0 - smoothstep(2.88, 3.02, s)) if s < 3.2 else 0.0
	# туман в низинах: на рассвете в безветрие, после дождя (мокро, но уже не льёт), в туманную погоду
	var h: float = main.t_hours
	var dawn := smoothstep(3.0, 5.5, h) * (1.0 - smoothstep(7.5, 10.5, h)) + (smoothstep(19.5, 22.0, h) + 1.0 - smoothstep(1.0, 4.0, h)) * 0.35
	var calm := clampf(1.3 - wind * 0.8, 0.0, 1.0)
	var t_mist := clampf(fogv * 0.9 + dawn * (0.45 + wet * 0.4) * calm + wet * (1.0 - precip) * 0.35 * calm + precip * 0.15, 0.0, 1.0)
	if temp < -6.0:
		t_mist *= 0.4
	mist = lerpf(mist, t_mist, k)
	kind = _kind_name()

func update_visual(cam_target: Vector3) -> void:
	var pos := cam_target + Vector3(0, 16.0, 0)
	rain.global_position = pos
	flakes.global_position = pos
	var cold := temp < 0.5
	var amt := clampf(precip * 1.15, 0.0, 1.0)
	# ночью струи едва видны, днём — серебристые
	var rm: StandardMaterial3D = (rain.draw_pass_1 as QuadMesh).material
	var lv: float = 0.25 + float(main.day_factor) * 0.75
	rm.albedo_color = Color(0.8 * lv, 0.85 * lv, 0.9 * lv, 0.3 + amt * 0.2)
	rain.emitting = amt > 0.05 and not cold
	flakes.emitting = amt > 0.05 and cold
	rain.amount_ratio = amt
	flakes.amount_ratio = amt
	var drift := Vector3(cos(wind_angle), 0.0, sin(wind_angle))
	var pm: ParticleProcessMaterial = flakes.process_material
	pm.gravity = drift * wind * (1.2 + gust * 0.8) + Vector3(0, -1.3, 0)
	var pr: ParticleProcessMaterial = rain.process_material
	pr.gravity = drift * wind * (2.5 + gust * 1.5) + Vector3(0, -12.0, 0)
	atmo.update(cam_target)

## Раздать параметры шейдерам.
var _last_shader_weather := PackedFloat32Array()

func apply(mats_a: Array, mats_b: Array, terrain: ShaderMaterial, blade: ShaderMaterial, water: ShaderMaterial) -> void:
	# Погодные значения интерполируются каждый тик, но микроскопические изменения
	# не требуют повторной отправки параметров сотням материалов.
	var freeze_now := clampf(-temp * 0.5, 0.0, 1.0)
	var rain_now := precip if temp >= 0.5 else 0.0
	var dry_now := clampf(autumn * 0.8 + (1.0 - smoothstep(0.0, 0.4, temp)) * 0.3, 0.0, 1.0)
	var values := PackedFloat32Array([snow, wet, autumn, leaf_drop, wind, blossom, freeze_now, rain_now, dry_now, ice, gust])
	var changed := _last_shader_weather.size() != values.size()
	if not changed:
		for i in values.size():
			if absf(values[i] - _last_shader_weather[i]) >= 0.003:
				changed = true
				break
	if not changed:
		return
	_last_shader_weather = values
	for m in mats_a:
		m.set_shader_parameter("snow", snow)
		m.set_shader_parameter("wet", wet)
		m.set_shader_parameter("autumn", autumn)
		m.set_shader_parameter("leaf_drop", leaf_drop)
		m.set_shader_parameter("wind", wind)
		m.set_shader_parameter("blossom", blossom)
	for m in mats_b:
		m.set_shader_parameter("snow", snow)
		m.set_shader_parameter("wet", wet)
		m.set_shader_parameter("autumn", autumn)
		m.set_shader_parameter("leaf_drop", leaf_drop)
		m.set_shader_parameter("wind", wind)
		m.set_shader_parameter("blossom", blossom)
	terrain.set_shader_parameter("snow", snow)
	terrain.set_shader_parameter("wet", wet)
	terrain.set_shader_parameter("snow_m", snow * 0.42)
	terrain.set_shader_parameter("mud_m", wet * 0.24)
	terrain.set_shader_parameter("freeze", freeze_now)
	terrain.set_shader_parameter("rain", rain_now)
	blade.set_shader_parameter("snow", snow)
	blade.set_shader_parameter("dry", dry_now)
	blade.set_shader_parameter("wind", wind)
	water.set_shader_parameter("ice", ice)
	water.set_shader_parameter("rain", rain_now)

# --- core: сохранение (save.gd, раздел «weather») ---
const _SAVE_KEYS := ["next_change", "cloud", "precip", "fogv", "wind", "gust", "gust_target", "gust_timer", "wind_angle", "wind_angle_target", "temp", "snow", "wet", "autumn", "leaf_drop", "ice", "mist", "blossom", "t_cloud", "t_precip", "t_fog", "t_wind", "_hours_acc"]

func to_save() -> Dictionary:
	var d := {"kind": kind, "rng_state": rng.state}
	for k: String in _SAVE_KEYS:
		d[k] = float(get(k))
	return d

func from_save(d: Dictionary) -> void:
	kind = String(d.get("kind", kind))
	if d.has("rng_state"):
		rng.state = int(d["rng_state"])
	for k: String in _SAVE_KEYS:
		if d.has(k):
			set(k, float(d[k]))
# --- /core ---
