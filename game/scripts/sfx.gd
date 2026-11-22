extends Node
## Звуки из записей (Oculus Audio Pack 01, CC BY 4.0, см. sounds/CREDITS.txt):
## дневной лес, ночной лес, ветер, дождь, река (3D у ближайшей воды), плеск при плавании,
## шаги по траве, земле и снегу, птицы, шорох кустов. Волчий вой синтезируется,
## как и шорох листвы на ветру, стук дождя по листьям и капель с крон после дождя.

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
var _drip_t := 1.0
var drip_s: Array = []

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
	# дождь по листве и шорох крон — синтез, бесшовные петли
	loops["patter"] = _player(_patter())
	loops["rustle"] = _player(_rustle())
	for i in 3:
		drip_s.append(_drip(i))
	howl = _howl()
	synth = {"crack": _crack(), "thud": _thud(), "slap": _slap(), "gnaw": _gnaw(), "splash": _splash()}
	# --- tools: удар топора, нож по коре/прутьям, свист копья, копьё вонзилось
	synth["chop"] = _knock(0.22, 190.0, 0.5, 21)
	synth["thunk"] = _knock(0.3, 120.0, 0.25, 22)
	synth["cut"] = _scrape()
	synth["whoosh"] = _whoosh()
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

# --- tools ---
## Удар по дереву: щелчок, глухой тон и короткий отзвук волокон.
func _knock(len_s: float, tone: float, click: float, seed_v: int) -> AudioStreamWAV:
	var rate := 22050
	var n := int(len_s * rate)
	var b := PackedByteArray()
	b.resize(n * 2)
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var lp := 0.0
	for i in n:
		var t := float(i) / rate
		var nz := r.randf_range(-1.0, 1.0)
		lp += (nz - lp) * 0.25
		var v := nz * exp(-t * 90.0) * click + sin(TAU * tone * t) * exp(-t * 28.0) * 0.6 + sin(TAU * tone * 2.7 * t) * exp(-t * 45.0) * 0.25 + lp * exp(-t * 18.0) * 0.5
		b.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 28000.0))
	return _wav(b, rate)

## Нож по коре и прутьям: два-три сухих скребка.
func _scrape() -> AudioStreamWAV:
	var rate := 22050
	var n := int(0.5 * rate)
	var b := PackedByteArray()
	b.resize(n * 2)
	var r := RandomNumberGenerator.new()
	r.seed = 23
	var lp := 0.0
	for i in n:
		var t := float(i) / rate
		var nz := r.randf_range(-1.0, 1.0)
		lp += (nz - lp) * 0.5
		var env := maxf(0.0, sin(t * TAU * 5.0)) * exp(-t * 3.0)
		b.encode_s16(i * 2, int(clampf((nz - lp) * env * 0.7, -1.0, 1.0) * 26000.0))
	return _wav(b, rate)

## Свист летящего копья: полосовой шум с нарастанием и спадом.
func _whoosh() -> AudioStreamWAV:
	var rate := 22050
	var n := int(0.45 * rate)
	var b := PackedByteArray()
	b.resize(n * 2)
	var r := RandomNumberGenerator.new()
	r.seed = 24
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / n
		var nz := r.randf_range(-1.0, 1.0)
		lp += (nz - lp) * 0.3
		lp2 += (lp - lp2) * 0.3
		var env := sin(PI * t) * sin(PI * t)
		b.encode_s16(i * 2, int(clampf((lp - lp2) * env * 1.6, -1.0, 1.0) * 26000.0))
	return _wav(b, rate)

## Бесшовная петля: хвост плавно накладывается на начало.
func _loop_wav(v: PackedFloat32Array, rate: int, gain: float) -> AudioStreamWAV:
	var n := v.size()
	var xf := int(rate * 0.25)
	var m := n - xf
	var b := PackedByteArray()
	b.resize(m * 2)
	for i in m:
		var x := v[i]
		if i < xf:
			var t := float(i) / xf
			x = v[i] * t + v[m + i] * (1.0 - t)
		b.encode_s16(i * 2, int(clampf(x * gain, -1.0, 1.0) * 30000.0))
	var w := _wav(b, rate)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = m
	return w

## Дождь по листьям: частые мелкие щелчки капель разной высоты поверх мягкого шипения.
func _patter() -> AudioStreamWAV:
	var rate := 22050
	var n := int(2.75 * rate)
	var v := PackedFloat32Array()
	v.resize(n)
	var r := RandomNumberGenerator.new()
	r.seed = 11
	var lp := 0.0
	var hp := 0.0
	var prev := 0.0
	var drops: Array = []
	for i in n:
		if r.randf() < 0.01:
			# капля: короткий затухающий тон 1,5–5 кГц с шумовой атакой
			drops.append([r.randf_range(1500.0, 5000.0), r.randf_range(0.15, 0.6), 0.0])
		var x := 0.0
		var k := 0
		while k < drops.size():
			var d: Array = drops[k]
			var t: float = d[2]
			x += sin(TAU * float(d[0]) * t) * float(d[1]) * exp(-t * 180.0)
			d[2] = t + 1.0 / rate
			if t > 0.02:
				drops.remove_at(k)
			else:
				k += 1
		var nz := r.randf_range(-1.0, 1.0)
		lp += (nz - lp) * 0.5
		hp = lp - prev
		prev = lp
		v[i] = x * 0.5 + hp * 0.25
	return _loop_wav(v, rate, 0.9)

## Шорох листвы: полосовой шум с медленными порывами.
func _rustle() -> AudioStreamWAV:
	var rate := 22050
	var n := int(4.25 * rate)
	var v := PackedFloat32Array()
	v.resize(n)
	var r := RandomNumberGenerator.new()
	r.seed = 12
	var a := 0.0
	var b := 0.0
	var env := 0.5
	var target := 0.5
	for i in n:
		if i % 2205 == 0:
			target = r.randf_range(0.2, 1.0)
		env += (target - env) * 0.0006
		var nz := r.randf_range(-1.0, 1.0)
		a += (nz - a) * 0.45
		b += (a - b) * 0.12
		# мелкие «трески» листьев
		var crk := (r.randf_range(-1.0, 1.0) if r.randf() < 0.004 else 0.0) * env
		v[i] = (a - b) * env * 0.9 + crk * 0.5
	return _loop_wav(v, rate, 1.0)

## Капля с кроны: короткий «плик» с падающей высотой.
func _drip(seed_v: int) -> AudioStreamWAV:
	var rate := 22050
	var n := int(0.12 * rate)
	var b := PackedByteArray()
	b.resize(n * 2)
	var f0 := 1400.0 + seed_v * 380.0
	var ph := 0.0
	for i in n:
		var t := float(i) / rate
		ph += TAU * f0 * (1.0 + exp(-t * 60.0) * 0.8) / rate
		var x := sin(ph) * exp(-t * 45.0) * 0.6
		b.encode_s16(i * 2, int(clampf(x, -1.0, 1.0) * 30000.0))
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
	# листва: в дождь стучит по листьям, на ветру шумит; в лесу громче, без листвы тише
	var fk := smoothstep(0.25, 0.75, main.forest_density(hp.x, hp.z))
	var leafy := 1.0 - float(w.leaf_drop) * 0.7
	var warm_rain := precip if float(w.temp) >= 0.5 else 0.0
	_vol("patter", warm_rain * (0.25 + fk * 0.55) * leafy, delta)
	_vol("rustle", (smoothstep(0.35, 1.8, float(w.wind)) * 0.45 + warm_rain * 0.2) * (0.3 + fk * 0.7) * leafy * (1.0 - winter * 0.6), delta)
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
	# капель с крон после дождя
	_drip_t -= delta
	if _drip_t <= 0.0:
		_drip_t = rng.randf_range(0.3, 1.4)
		var wetk := float(w.wet) * fk * (1.0 - precip * 0.7)
		if wetk > 0.2 and rng.randf() < wetk and float(w.temp) >= 0.5:
			var a := rng.randf() * TAU
			_play3d(drip_s[rng.randi() % drip_s.size()], hp + Vector3(cos(a) * rng.randf_range(1.0, 6.0), 0.3, sin(a) * rng.randf_range(1.0, 6.0)), -16.0, rng.randf_range(0.85, 1.2))
	# волки воют по ночам
	_howl_t -= delta
	if _howl_t <= 0.0:
		_howl_t = rng.randf_range(60.0, 160.0)
		if day < 0.3:
			var a := rng.randf() * TAU
			_play3d(howl, hp + Vector3(cos(a) * 100.0, 5.0, sin(a) * 100.0), 4.0, rng.randf_range(0.9, 1.1))
