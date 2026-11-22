extends Node
## Звуки из записей (Oculus Audio Pack 01, CC BY 4.0, см. sounds/CREDITS.txt):
## дневной лес, ночной лес, ветер, дождь, река (3D у ближайшей воды), плеск при плавании,
## шаги по траве, земле и снегу, птицы, шорох кустов. Волчий вой синтезируется.

var main: Node3D
var rng := RandomNumberGenerator.new()
var loops := {}
var steps := {}
var birds: Array = []
var bushes: Array = []
var land_s: AudioStream
var howl: AudioStreamWAV
var river3d: AudioStreamPlayer3D
var _one: Array = []
## Синтезированные звуки бобров и падающих деревьев.
var synth := {}
var _bird_t := 4.0
var _howl_t := 60.0
var _bush_t := 0.0

func _ogg(n: String, loop: bool = false) -> AudioStream:
	var s: AudioStreamOggVorbis = load("res://sounds/%s.ogg" % n)
	s = s.duplicate()
	s.loop = loop
	return s

func _ready() -> void:
	rng.seed = 99
	for n in ["forest", "night", "wind", "rain", "swim"]:
		loops[n] = _player(_ogg(n, true))
	river3d = AudioStreamPlayer3D.new()
	river3d.stream = _ogg("river", true)
	river3d.unit_size = 10.0
	river3d.max_distance = 60.0
	river3d.volume_db = -60.0
	add_child(river3d)
	river3d.play()
	for k in ["grasswalk", "grassrun", "dirtwalk", "snowwalk", "snowrun"]:
		var arr: Array = []
		for i in 5:
			arr.append(_ogg("step_%s%d" % [k, i + 1]))
		steps[k] = arr
	for i in 3:
		birds.append(_ogg("bird%d" % (i + 1)))
	for i in 2:
		bushes.append(_ogg("bush%d" % (i + 1)))
	land_s = _ogg("land")
	howl = _howl()
	synth = {"crack": _crack(), "thud": _thud(), "slap": _slap(), "gnaw": _gnaw(), "splash": _splash()}
	for i in 6:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 10.0
		p.max_distance = 140.0
		add_child(p)
		_one.append(p)

func _player(s: AudioStream) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = -80.0
	add_child(p)
	p.play()
	return p

## Вой: синус с плавным подъёмом высоты, обертонами и вибрато.
func _howl() -> AudioStreamWAV:
	var rate := 22050
	var n := int(3.4 * rate)
	var b := PackedByteArray()
	b.resize(n * 2)
	var ph := 0.0
	for i in n:
		var t := float(i) / n
		var f := 330.0 + sin(PI * minf(t * 1.5, 1.0)) * 240.0 - t * 90.0 + sin(t * 75.0) * 7.0
		ph += TAU * f / rate
		var env := smoothstep(0.0, 0.18, t) * (1.0 - smoothstep(0.65, 1.0, t))
		var v := (sin(ph) * 0.65 + sin(ph * 2.0) * 0.22 + sin(ph * 3.0) * 0.08) * env * 0.45
		b.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = b
	return w

func _wav(b: PackedByteArray, rate: int) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = b
	return w

## Треск ломающегося ствола: редкие щелчки учащаются, скрип волокон, в конце — громкий излом.
func _crack() -> AudioStreamWAV:
	var rate := 22050
	var n := int(1.9 * rate)
	var b := PackedByteArray()
	b.resize(n * 2)
	var r := RandomNumberGenerator.new()
	r.seed = 5
	var click := 0.0
	var lp := 0.0
	var ph := 0.0
	for i in n:
		var t := float(i) / n
		# щелчки: вероятность растёт к концу
		if r.randf() < 0.0008 + t * t * 0.006:
			click = r.randf_range(0.4, 1.0)
		var snap := 0.0
		if t > 0.78 and t < 0.86:
			snap = (1.0 - (t - 0.78) / 0.08) * r.randf_range(-1.0, 1.0)
		var nz := r.randf_range(-1.0, 1.0)
		lp += (nz - lp) * 0.35
		var c := click * nz
		click *= 0.93
		# скрип: низкий пилообразный тон с дрожью
		ph += TAU * (70.0 + sin(t * 40.0) * 12.0 + r.randf() * 8.0) / rate
		var creak := (fmod(ph, TAU) / TAU - 0.5) * smoothstep(0.1, 0.5, t) * (1.0 - smoothstep(0.75, 0.8, t)) * 0.25
		var v := c * 0.8 + creak * (0.5 + 0.5 * absf(lp)) + snap * 0.9 + lp * 0.05 * (1.0 - t)
		b.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000.0))
	return _wav(b, rate)

## Удар ствола о землю: глухой низкий удар и шорох кроны.
func _thud() -> AudioStreamWAV:
	var rate := 22050
	var n := int(1.4 * rate)
	var b := PackedByteArray()
	b.resize(n * 2)
	var r := RandomNumberGenerator.new()
	r.seed = 6
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / rate
		var nz := r.randf_range(-1.0, 1.0)
		lp += (nz - lp) * 0.04
		lp2 += (nz - lp2) * 0.5
		var boom := (sin(TAU * 48.0 * t) * 0.6 + lp * 3.0) * exp(-t * 6.0)
		var rustle := (nz - lp2) * 0.25 * exp(-t * 2.5) * smoothstep(0.0, 0.05, t)
		b.encode_s16(i * 2, int(clampf(boom + rustle, -1.0, 1.0) * 30000.0))
	return _wav(b, rate)

## Шлепок хвостом по воде.
func _slap() -> AudioStreamWAV:
	var rate := 22050
	var n := int(0.6 * rate)
	var b := PackedByteArray()
	b.resize(n * 2)
	var r := RandomNumberGenerator.new()
	r.seed = 7
	var lp := 0.0
	for i in n:
		var t := float(i) / rate
		var nz := r.randf_range(-1.0, 1.0)
		lp += (nz - lp) * 0.2
		var v := nz * exp(-t * 60.0) * 0.9 + lp * exp(-t * 7.0) * 0.8 + sin(TAU * 110.0 * t) * exp(-t * 30.0) * 0.4
		b.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000.0))
	return _wav(b, rate)

## Всплеск: рыба выпрыгнула или медведь ударил лапой по воде — шипящий шлепок с капелью.
func _splash() -> AudioStreamWAV:
	var rate := 22050
	var n := int(0.5 * rate)
	var b := PackedByteArray()
	b.resize(n * 2)
	var r := RandomNumberGenerator.new()
	r.seed = 11
	var lp := 0.0
	var hp := 0.0
	for i in n:
		var t := float(i) / rate
		var nz := r.randf_range(-1.0, 1.0)
		lp += (nz - lp) * 0.35
		hp = nz - lp
		var drip := sin(TAU * (900.0 + 600.0 * exp(-t * 20.0)) * t) * exp(-t * 25.0) * 0.25
		var v := lp * exp(-t * 14.0) * 0.9 + hp * exp(-t * 9.0) * 0.35 + drip
		b.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 26000.0))
	return _wav(b, rate)

## Грызёт: короткие сухие поскрёбывания.
func _gnaw() -> AudioStreamWAV:
	var rate := 22050
	var n := int(0.7 * rate)
	var b := PackedByteArray()
	b.resize(n * 2)
	var r := RandomNumberGenerator.new()
	r.seed = 8
	var lp := 0.0
	for i in n:
		var t := float(i) / rate
		var nz := r.randf_range(-1.0, 1.0)
		lp += (nz - lp) * 0.6
		var burst := maxf(0.0, sin(t * TAU * 9.0)) * (0.6 + 0.4 * sin(t * 170.0))
		var v := (nz - lp) * burst * 0.5
		b.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000.0))
	return _wav(b, rate)

## Звук в точке мира (бобры, деревья).
func play_at(name_s: String, p: Vector3, db: float, pitch: float = 1.0) -> void:
	if synth.has(name_s):
		_play3d(synth[name_s], p, db, pitch)

func _play3d(s: AudioStream, p: Vector3, db: float, pitch: float = 1.0) -> void:
	for pl in _one:
		if not pl.playing:
			pl.stream = s
			pl.global_position = p
			pl.volume_db = db
			pl.pitch_scale = pitch
			pl.play()
			return

func _play(s: AudioStream, db: float, pitch: float) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = db
	p.pitch_scale = pitch
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

## Шаг героя (зовётся из походки). Вплавь шагов нет — только плеск гребка.
func step(swimming: bool, strength: float) -> void:
	if swimming:
		return
	var w = main.weather
	var hp: Vector3 = main.hero.position
	var run := strength > 1.2
	var kind := "grass"
	if float(w.snow) > 0.4:
		kind = "snow"
	elif main.forest_density(hp.x, hp.z) > 0.55 or main.height(hp.x, hp.z) < main.WATER_Y + 0.8:
		kind = "dirt"
	var key := kind + ("run" if run and kind != "dirt" else "walk")
	var arr: Array = steps[key]
	_play(arr[rng.randi() % arr.size()], -8.0 + (3.0 if run else 0.0), rng.randf_range(0.92, 1.08))

func landed(impact: float) -> void:
	_play(land_s, linear_to_db(clampf(impact / 6.0, 0.2, 1.0)) - 4.0, rng.randf_range(0.9, 1.05))

func _vol(name_s: String, lin_v: float, delta: float) -> void:
	var p: AudioStreamPlayer = loops[name_s]
	var target := linear_to_db(maxf(lin_v, 0.0001))
	p.volume_db = lerpf(p.volume_db, target, minf(1.0, delta * 1.2))

func _process(delta: float) -> void:
	if main == null or main.hero == null:
		return
	var w = main.weather
	var h: float = main.t_hours
	var day := smoothstep(4.5, 6.5, h) * (1.0 - smoothstep(20.5, 22.0, h))
	var hero = main.hero
	var hp: Vector3 = hero.position
	var precip := float(w.precip) * (1.0 - float(w.snow))
	var winter := clampf(float(w.snow) * 1.5, 0.0, 1.0)
	# зимой лес почти молчит: остаётся ветер
	_vol("forest", day * (1.0 - precip * 0.7) * (1.0 - winter * 0.8) * 0.55, delta)
	var warm := clampf((float(w.temp) - 4.0) / 8.0, 0.0, 1.0)
	_vol("night", (1.0 - day) * warm * (1.0 - precip * 0.6) * 0.6, delta)
	_vol("wind", 0.08 + float(w.wind) * 0.45 + winter * 0.15, delta)
	_vol("rain", precip * 0.85, delta)
	var swim: float = hero.swimb
	var moving: bool = hero.run_mag > 0.15
	_vol("swim", swim * (0.75 if moving else 0.3), delta)
	# река: источник звука — ближайшая точка воды
	var best := Vector3.INF
	var bd := 1e9
	for k in 12:
		var a := TAU * k / 12.0
		for rr: float in [5.0, 14.0, 28.0]:
			var x: float = hp.x + cos(a) * rr
			var z: float = hp.z + sin(a) * rr
			if main.height(x, z) < main.WATER_Y - 0.1 and rr < bd:
				bd = rr
				best = Vector3(x, main.WATER_Y, z)
	var frozen := float(w.ice) > 0.85
	if best != Vector3.INF and not frozen:
		river3d.global_position = river3d.global_position.lerp(best, minf(1.0, delta * 2.0)) if river3d.volume_db > -40.0 else best
		river3d.volume_db = lerpf(river3d.volume_db, 0.0, minf(1.0, delta))
	else:
		river3d.volume_db = lerpf(river3d.volume_db, -60.0, minf(1.0, delta))
	# отдельные птичьи трели днём, не в дождь и не зимой
	_bird_t -= delta
	if _bird_t <= 0.0:
		_bird_t = rng.randf_range(4.0, 11.0)
		if day > 0.5 and precip < 0.3 and winter < 0.5:
			var a := rng.randf() * TAU
			var p := hp + Vector3(cos(a) * rng.randf_range(10.0, 30.0), rng.randf_range(5.0, 10.0), sin(a) * rng.randf_range(10.0, 30.0))
			_play3d(birds[rng.randi() % birds.size()], p, -2.0, rng.randf_range(0.95, 1.05))
	# шорох, когда идёшь сквозь кусты и подлесок
	_bush_t -= delta
	if _bush_t <= 0.0 and moving and swim < 0.3 and main.forest_density(hp.x, hp.z) > 0.6 and rng.randf() < 0.3:
		_bush_t = rng.randf_range(2.5, 5.0)
		_play(bushes[rng.randi() % bushes.size()], -14.0, rng.randf_range(0.9, 1.1))
	# волки воют по ночам
	_howl_t -= delta
	if _howl_t <= 0.0:
		_howl_t = rng.randf_range(60.0, 160.0)
		if day < 0.3:
			var a := rng.randf() * TAU
			_play3d(howl, hp + Vector3(cos(a) * 100.0, 5.0, sin(a) * 100.0), 4.0, rng.randf_range(0.9, 1.1))
