extends Node
## Звуки, синтезированные при запуске (без файлов): ветер, река, дождь, шаги, всплески,
## птицы днём, сверчки вечером, вой волков ночью.

const RATE := 22050
var main: Node3D
var rng := RandomNumberGenerator.new()
var loops := {}
var steps: Array = []
var splashes: Array = []
var chirps: Array = []
var howl: AudioStreamWAV
var river3d: AudioStreamPlayer3D
var _one: Array = []
var _bird_t := 3.0
var _howl_t := 60.0
var _last_step := 0

func _ready() -> void:
	rng.seed = 99
	loops["wind"] = _player(_loop_noise(6.0, 0.035, 0.25, 0.4))
	loops["rain"] = _player(_loop_noise(3.0, 0.75, 0.0, 0.0, true))
	loops["crickets"] = _player(_crickets(4.0))
	river3d = AudioStreamPlayer3D.new()
	river3d.stream = _loop_noise(4.0, 0.25, 0.15, 0.1)
	river3d.unit_size = 6.0
	river3d.max_distance = 45.0
	river3d.volume_db = 2.0
	add_child(river3d)
	river3d.play()
	for i in 4:
		steps.append(_step(i, false))
	for i in 3:
		splashes.append(_step(10 + i, true))
	for i in 4:
		chirps.append(_chirp(i))
	howl = _howl()
	for i in 6:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 8.0
		p.max_distance = 120.0
		add_child(p)
		_one.append(p)

func _player(s: AudioStream) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = -80.0
	add_child(p)
	p.play()
	return p

func _wav(data: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var b := PackedByteArray()
	b.resize(data.size() * 2)
	for i in data.size():
		b.encode_s16(i * 2, int(clampf(data[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = b
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = data.size()
	return w

## Шум с однополюсным фильтром: lp — доля новой выборки (меньше — глуше),
## am — глубина медленных порывов, crackle — капли дождя. Шов петли сведён наплывом.
func _loop_noise(sec: float, lp: float, am: float, am_f: float, crackle: bool = false) -> AudioStreamWAV:
	var n := int(sec * RATE)
	var fade := int(0.5 * RATE)
	var d := PackedFloat32Array()
	d.resize(n + fade)
	var y := 0.0
	var y2 := 0.0
	for i in n + fade:
		var w := rng.randf_range(-1.0, 1.0)
		y += (w - y) * lp
		y2 += (y - y2) * lp
		var v := y2 * (1.6 / sqrt(lp + 0.02))
		if crackle and rng.randf() < 0.004:
			v += rng.randf_range(-0.6, 0.6)
		var t := float(i) / RATE
		v *= 1.0 - am + am * (0.5 + 0.5 * sin(TAU * am_f * t + sin(t * 1.3) * 1.5))
		d[i] = v * 0.5
	for i in fade:
		var k := float(i) / fade
		d[i] = d[i] * k + d[n + i] * (1.0 - k)
	d.resize(n)
	return _wav(d, true)

## Шаг: короткий хруст (трава, хвоя) или всплеск.
func _step(seed_v: int, wet: bool) -> AudioStreamWAV:
	rng.seed = 500 + seed_v
	var n := int((0.35 if wet else 0.16) * RATE)
	var d := PackedFloat32Array()
	d.resize(n)
	var y := 0.0
	var lp := 0.12 if wet else rng.randf_range(0.25, 0.4)
	for i in n:
		var t := float(i) / n
		var env := pow(1.0 - t, 3.0 if not wet else 1.6) * minf(1.0, t * 40.0)
		var w := rng.randf_range(-1.0, 1.0)
		if not wet and rng.randf() < 0.05:
			w *= 3.0
		y += (w - y) * lp
		var v := y * env
		if wet:
			v += sin(TAU * (380.0 - t * 200.0) * i / RATE) * env * 0.15 * (1.0 - t)
		d[i] = v * (0.9 if wet else 0.7)
	return _wav(d, false)

## Птица: серия трелей с частотной модуляцией.
func _chirp(seed_v: int) -> AudioStreamWAV:
	rng.seed = 900 + seed_v
	var notes := rng.randi_range(2, 6)
	var f0 := rng.randf_range(2600.0, 4200.0)
	var nl := rng.randf_range(0.06, 0.14)
	var gap := rng.randf_range(0.03, 0.09)
	var n := int((nl + gap) * notes * RATE) + 10
	var d := PackedFloat32Array()
	d.resize(n)
	var ph := 0.0
	for k in notes:
		var fa := f0 * rng.randf_range(0.85, 1.15)
		var fb := fa * rng.randf_range(0.7, 1.4)
		var s0 := int((nl + gap) * k * RATE)
		var m := int(nl * RATE)
		for i in m:
			var t := float(i) / m
			var f := lerpf(fa, fb, t) + sin(t * 60.0) * 120.0
			ph += TAU * f / RATE
			d[s0 + i] = sin(ph) * sin(PI * t) * 0.35
	return _wav(d, false)

func _crickets(sec: float) -> AudioStreamWAV:
	var n := int(sec * RATE)
	var d := PackedFloat32Array()
	d.resize(n)
	for i in n:
		var t := float(i) / RATE
		var pulse := maxf(0.0, sin(TAU * 28.0 * t)) * maxf(0.0, sin(TAU * 1.0 * t))
		var pulse2 := maxf(0.0, sin(TAU * 23.0 * t + 1.0)) * maxf(0.0, sin(TAU * 0.75 * t + 2.0))
		d[i] = sin(TAU * 4400.0 * t) * pulse * 0.12 + sin(TAU * 3900.0 * t) * pulse2 * 0.08
	return _wav(d, true)

func _howl() -> AudioStreamWAV:
	var n := int(3.2 * RATE)
	var d := PackedFloat32Array()
	d.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / n
		var f := 300.0 + sin(PI * minf(t * 1.6, 1.0)) * 260.0 - t * 80.0 + sin(t * 70.0) * 6.0
		ph += TAU * f / RATE
		var env := smoothstep(0.0, 0.15, t) * (1.0 - smoothstep(0.7, 1.0, t))
		d[i] = (sin(ph) * 0.7 + sin(ph * 2.0) * 0.2 + sin(ph * 3.0) * 0.08) * env * 0.4
	return _wav(d, false)

func _play3d(s: AudioStream, p: Vector3, db: float, pitch: float = 1.0) -> void:
	for pl in _one:
		if not pl.playing:
			pl.stream = s
			pl.global_position = p
			pl.volume_db = db
			pl.pitch_scale = pitch
			pl.play()
			return

## Шаг героя: зовётся из походки.
func step(wet: bool, strength: float) -> void:
	var arr: Array = splashes if wet else steps
	var p := AudioStreamPlayer.new()
	p.stream = arr[rng.randi() % arr.size()]
	p.volume_db = linear_to_db(clampf(strength, 0.15, 1.0)) - (6.0 if not wet else 2.0)
	p.pitch_scale = rng.randf_range(0.85, 1.15)
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

func _vol(name_s: String, lin_v: float, delta: float) -> void:
	var p: AudioStreamPlayer = loops[name_s]
	var target := linear_to_db(maxf(lin_v, 0.0001))
	p.volume_db = lerpf(p.volume_db, target, minf(1.0, delta * 1.5))

func _process(delta: float) -> void:
	if main == null or main.hero == null:
		return
	var w = main.weather
	var h: float = main.t_hours
	var day := smoothstep(5.0, 7.0, h) * (1.0 - smoothstep(20.0, 22.0, h))
	var hp: Vector3 = main.hero.position
	_vol("wind", 0.12 + float(w.wind) * 0.35, delta)
	_vol("rain", float(w.precip) * (1.0 - float(w.snow)) * 0.7, delta)
	var warm := clampf((float(w.temp) - 6.0) / 10.0, 0.0, 1.0)
	_vol("crickets", (1.0 - day) * warm * (1.0 - float(w.precip)) * 0.35 + 0.0001, delta)
	# река: источник звука — ближайшая точка воды рядом с героем
	var best := Vector3.INF
	for k in 12:
		var a := TAU * k / 12.0
		for rr in [6.0, 14.0, 26.0]:
			var x := hp.x + cos(a) * rr
			var z := hp.z + sin(a) * rr
			if main.height(x, z) < main.WATER_Y - 0.1 and (best == Vector3.INF or Vector2(x - hp.x, z - hp.z).length() < Vector2(best.x - hp.x, best.z - hp.z).length()):
				best = Vector3(x, main.WATER_Y, z)
	if best != Vector3.INF:
		river3d.global_position = river3d.global_position.lerp(best, minf(1.0, delta * 2.0)) if river3d.volume_db > -40.0 else best
		river3d.volume_db = lerpf(river3d.volume_db, 2.0, minf(1.0, delta))
	else:
		river3d.volume_db = lerpf(river3d.volume_db, -60.0, minf(1.0, delta))
	# птицы днём, реже в дождь и зимой
	_bird_t -= delta
	if _bird_t <= 0.0:
		_bird_t = rng.randf_range(2.0, 7.0)
		if day > 0.5 and float(w.precip) < 0.4 and rng.randf() < 0.85 - float(w.snow) * 0.6:
			var a := rng.randf() * TAU
			var p := hp + Vector3(cos(a) * rng.randf_range(8.0, 30.0), rng.randf_range(4.0, 10.0), sin(a) * rng.randf_range(8.0, 30.0))
			var c: AudioStream = chirps[rng.randi() % chirps.size()]
			for r in rng.randi_range(1, 3):
				_play3d(c, p, -4.0, rng.randf_range(0.9, 1.1))
	# волки воют по ночам
	_howl_t -= delta
	if _howl_t <= 0.0:
		_howl_t = rng.randf_range(50.0, 140.0)
		if day < 0.3:
			var a := rng.randf() * TAU
			_play3d(howl, hp + Vector3(cos(a) * 90.0, 5.0, sin(a) * 90.0), 6.0, rng.randf_range(0.9, 1.1))
