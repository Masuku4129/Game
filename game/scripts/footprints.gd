extends MeshInstance3D
## Снег, грязь и следы.
## Снег лежит неравномерно: сугробы на открытом месте и с подветренной стороны склонов,
## под густым ельником тонко. Грязь — в низинах у воды и пятнами на ровных местах, после
## дождя глубже. Глубина в точке — snow_depth()/mud_depth(); земля в шейдере поднята на
## глубину снега. Следы рисуются в текстуру 640×640 (40×40 м вокруг героя, по кругу —
## края при сдвиге стираются), мелкая сетка-заплатка у героя продавливается по ней:
## мелкие отпечатки, ямы по колено, траншея по пояс. Следы засыпает снегом и замывает
## дождём (часы засыпания идут быстрее в осадки), пропадают, когда тает снег.

const TS := 640                 # текселей по стороне карты следов
const SPAN := 40.0              # метров по стороне карты следов и заплатки
const TEX := SPAN / TS          # 0.0625 м на тексель
const CELLS := 128              # клеток сетки заплатки по стороне
const SNAP := 5.0               # шаг сдвига заплатки, м
const LIFE := 200.0             # «часов засыпания» до полного исчезновения следа
const DEPTH_MAX := 1.25         # глубина, соответствующая байту 255
const HERO_DELAY := 0.35        # след героя появляется позади него, а не под ногами
const RING := 8192

var main: Node3D
var fn := 0                     # вершин сетки земли по стороне
var fstep := 1.0
var half := 256.0
var fdata := PackedByteArray()  # RGBA8 fn×fn: густота леса, сугроб, грязь
var hs := PackedFloat32Array()
var field_tex: ImageTexture
var tuft_mat: ShaderMaterial
var timg: Image
var ttex: ImageTexture
var dirty := false
var _up_t := 0.0
var clock := 0.0
var center := Vector2(1e9, 1e9)
var org := Vector2i(0, 0)       # мировой индекс текселя в углу окна
var snow_m := 0.0
var mud_m := 0.0
var queue: Array = []           # отложенные следы героя: [время, x, z, yaw, сторона]
var ring := PackedFloat32Array()  # для стирания: x, z, радиус, часы
var ring_head := 0
var ring_tail := 0
var _now := 0.0
var _test := ""
var _test_f := 0
var _spot := Vector3.ZERO

const ANIMAL_SINK := {"hare": 0.1, "squirrel": 0.05, "fox": 0.25, "wolf": 0.45, "roe": 0.65, "deer": 0.75, "boar": 0.8, "bear": 0.7, "tiger": 0.55, "beaver": 0.4}

func _ready() -> void:
	_build_field()
	timg = Image.create(TS, TS, false, Image.FORMAT_RG8)
	ttex = ImageTexture.create_from_image(timg)
	ring.resize(RING * 4)
	_build_patch()
	var m: ShaderMaterial = main.terrain_mat
	m.set_shader_parameter("hmap_tex", main.hmap_tex)
	m.set_shader_parameter("track_tex", ttex)
	m.set_shader_parameter("track_near", ttex)
	m.set_shader_parameter("track_span", SPAN)
	m.set_shader_parameter("track_life", LIFE)
	m.set_shader_parameter("tsize", main.SIZE)
	m.set_shader_parameter("tseg", float(main.SEG))
	_test = OS.get_environment("TRACKS_TEST")
	if main.pv.mats.has("tuft"):
		tuft_mat = main.pv.mats["tuft"]
		tuft_mat.set_shader_parameter("field_tex", field_tex)

## Карта сугробов и грязи по вершинам сетки земли (та же разбивка, что у меша).
func _build_field() -> void:
	fn = main.SEG + 1
	fstep = main.SIZE / main.SEG
	half = main.SIZE * 0.5
	hs = main.terrain_hs
	var cols: PackedColorArray = main.terrain_cols
	var nz := FastNoiseLite.new()
	nz.seed = 7311
	nz.frequency = 0.045 * fstep
	nz.fractal_octaves = 3
	nz.offset = Vector3(0, 0, 0)
	var dunes := nz.get_image(fn, fn).get_data()
	var nm := FastNoiseLite.new()
	nm.seed = 913
	nm.frequency = 0.035 * fstep
	nm.fractal_octaves = 2
	var mudn := nm.get_image(fn, fn).get_data()
	# преобладающий ветер с запада: сугробы копятся на восточных (подветренных) склонах
	var wdir := Vector2(1.0, 0.3).normalized()
	var wy: float = main.WATER_Y
	fdata.resize(fn * fn * 4)
	for iz in fn:
		var zl := maxi(iz - 1, 0) * fn
		var zh := mini(iz + 1, fn - 1) * fn
		var zl3 := maxi(iz - 3, 0) * fn
		var zh3 := mini(iz + 3, fn - 1) * fn
		for ix in fn:
			var i := iz * fn + ix
			var y := hs[i]
			var gx := (hs[iz * fn + mini(ix + 1, fn - 1)] - hs[iz * fn + maxi(ix - 1, 0)]) / (2.0 * fstep)
			var gz := (hs[zh + ix] - hs[zl + ix]) / (2.0 * fstep)
			var ny := 1.0 / sqrt(1.0 + gx * gx + gz * gz)
			var fd: float = cols[i].r
			# лощины засыпает: средняя высота вокруг выше точки
			var avg := (hs[iz * fn + mini(ix + 3, fn - 1)] + hs[iz * fn + maxi(ix - 3, 0)] + hs[zh3 + ix] + hs[zl3 + ix]) * 0.25
			var hollow := clampf((avg - y) * 0.35, -0.3, 0.4)
			# склон, обращённый по ветру (вниз по ветру), — подветренный
			var lee := clampf(-(gx * wdir.x + gz * wdir.y) * 3.0, -0.5, 0.8)
			var dn := float(dunes[i]) / 255.0
			var drift := lerpf(1.0, 0.28, fd) * (0.45 + dn * 0.75) * (1.0 + lee * 0.6) + hollow
			drift *= smoothstep(0.62, 0.9, ny)
			drift *= smoothstep(wy + 0.3, wy + 1.3, y)
			drift = clampf(drift, 0.0, 1.4)
			# грязь: низины у воды и пятна на ровных открытых местах
			var low := smoothstep(wy + 2.2, wy + 0.5, y)
			var mn := float(mudn[i]) / 255.0
			var patch := smoothstep(0.62, 0.78, mn + hollow * 0.4) * (1.0 - fd * 0.6)
			var mf := clampf(maxf(low * 0.95, patch), 0.0, 1.0) * smoothstep(0.85, 0.96, ny)
			fdata[i * 4] = int(clampf(fd, 0.0, 1.0) * 255.0)
			fdata[i * 4 + 1] = int(drift / 1.4 * 255.0)
			fdata[i * 4 + 2] = int(mf * 255.0)
			fdata[i * 4 + 3] = 255
	var img := Image.create_from_data(fn, fn, false, Image.FORMAT_RGBA8, fdata)
	field_tex = ImageTexture.create_from_image(img)
	main.terrain_mat.set_shader_parameter("field_tex", field_tex)

func _build_patch() -> void:
	var m := CELLS + 1
	var e := SPAN / CELLS
	var v := PackedVector3Array(); v.resize(m * m)
	var nr := PackedVector3Array(); nr.resize(m * m)
	var c := PackedColorArray(); c.resize(m * m)
	for iz in m:
		for ix in m:
			v[iz * m + ix] = Vector3(ix * e - SPAN * 0.5, 0, iz * e - SPAN * 0.5)
			nr[iz * m + ix] = Vector3.UP
			c[iz * m + ix] = Color(0, 0, 0, 0)
	var idx := PackedInt32Array()
	idx.resize(CELLS * CELLS * 6)
	var k := 0
	for iz in CELLS:
		for ix in CELLS:
			var a := iz * m + ix
			idx[k] = a; idx[k + 1] = a + 1; idx[k + 2] = a + m
			idx[k + 3] = a + 1; idx[k + 4] = a + m + 1; idx[k + 5] = a + m
			k += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nr
	arr[Mesh.ARRAY_COLOR] = c
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	am.surface_set_material(0, main.terrain_mat)
	am.custom_aabb = AABB(Vector3(-SPAN * 0.5, -200, -SPAN * 0.5), Vector3(SPAN, 400, SPAN))
	mesh = am
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

# ---------- запросы ----------

## Значение канала ch карты поля в точке (по тем же треугольникам, что и меш).
func _field(x: float, z: float, ch: int) -> float:
	var gx := clampf((x + half) / fstep, 0.0, fn - 1.0001)
	var gz := clampf((z + half) / fstep, 0.0, fn - 1.0001)
	var ix := int(gx)
	var iz := int(gz)
	var fx := gx - ix
	var fz := gz - iz
	var i := (iz * fn + ix) * 4 + ch
	var a := float(fdata[i])
	var b := float(fdata[i + 4])
	var c := float(fdata[i + fn * 4])
	var d := float(fdata[i + fn * 4 + 4])
	if fx + fz <= 1.0:
		return (a + fx * (b - a) + fz * (c - a)) / 255.0
	return (d + (1.0 - fx) * (c - d) + (1.0 - fz) * (b - d)) / 255.0

func snow_depth(x: float, z: float) -> float:
	return snow_m * 1.4 * _field(x, z, 1)

func mud_depth(x: float, z: float) -> float:
	return mud_m * _field(x, z, 2)

## Видимая глубина уже продавленного следа в точке.
func track_depth(x: float, z: float) -> float:
	var kx := floori(x / TEX)
	var kz := floori(z / TEX)
	if kx < org.x or kz < org.y or kx >= org.x + TS or kz >= org.y + TS:
		return 0.0
	var px := timg.get_pixel(posmod(kx, TS), posmod(kz, TS))
	return px.r * DEPTH_MAX * _fade(px.g)

func _fade(g: float) -> float:
	var age := fposmod(fposmod(clock, 256.0) - roundf(g * 255.0), 256.0)
	return clampf(1.0 - age / LIFE, 0.0, 1.0)

## Насколько герой (ноги в точке p) погружён: x — в снег, y — в грязь.
func sink_at(p: Vector3) -> Vector2:
	var h: float = main.height(p.x, p.z)
	var sd := snow_depth(p.x, p.z)
	var md := mud_depth(p.x, p.z)
	var t := track_depth(p.x, p.z)
	var s := clampf(h + sd - minf(t, sd) - p.y, 0.0, sd)
	var mm := 0.0
	if absf(p.y - h) < 0.12:
		mm = maxf(0.0, md * 0.9 - maxf(t - sd, 0.0) * 0.3)
	return Vector2(s, mm)

## Множитель скорости: по щиколотку почти не мешает, по колено ~0.6, по пояс ~0.35.
func slow(sk: Vector2) -> float:
	var s := sk.x + sk.y * 1.5
	return 1.0 / (1.0 + 1.3 * s + 0.55 * s * s)

# ---------- следы ----------

## Шаг героя в точке p (стопа), направление yaw. След рисуется с задержкой — позади.
func stamp(p: Vector3, yaw: float) -> void:
	queue.append([_now, p.x, p.z, yaw, p.y])

func _hero_print(x: float, z: float, yaw: float, y: float) -> void:
	var sd := snow_depth(x, z)
	var md := mud_depth(x, z)
	var w: float = main.weather.wet
	var s := 0.0
	var h: float = main.height(x, z)
	if y > h + 0.15:
		return  # на камне, бревне, льду
	if sd > 0.01:
		s = sd
	if md > 0.01:
		s = maxf(s, sd + md * 0.9)
	if s < 0.01 and w > 0.15 and float(main.weather.temp) > 0.0:
		s = 0.02 * w
	if s < 0.008:
		return
	# по щиколотку — отпечаток стопы, по колено — яма, по пояс — сплошная траншея
	var k := smoothstep(0.08, 0.85, s)
	var wid := lerpf(0.06, 0.3, k)
	var ln := lerpf(0.15, 0.78, k)
	_paint(x, z, yaw, wid, ln, s)

func _paint(x: float, z: float, yaw: float, hw: float, hl: float, depth: float) -> void:
	if absf(x - center.x) > SPAN * 0.5 - 3.5 or absf(z - center.y) > SPAN * 0.5 - 3.5:
		return
	var fx := sin(yaw)
	var fz := cos(yaw)
	var r := maxf(hw, hl)
	var k0x := floori((x - r) / TEX)
	var k1x := floori((x + r) / TEX)
	var k0z := floori((z - r) / TEX)
	var k1z := floori((z + r) / TEX)
	var cb := float(int(clock) % 256) / 255.0
	for kz in range(k0z, k1z + 1):
		var wz := (kz + 0.5) * TEX - z
		var pz := posmod(kz, TS)
		for kx in range(k0x, k1x + 1):
			var wx := (kx + 0.5) * TEX - x
			var u := (wx * fz - wz * fx) / hw
			var v := (wx * fx + wz * fz) / hl
			var e := u * u + v * v
			if e >= 1.0:
				continue
			# плоское дно и пологие стенки
			var d := depth * clampf((1.0 - e) * 2.5, 0.0, 1.0)
			var px := posmod(kx, TS)
			var old := timg.get_pixel(px, pz)
			var od := old.r * DEPTH_MAX * _fade(old.g)
			if d > od + 0.004:
				timg.set_pixel(px, pz, Color(minf(d / DEPTH_MAX, 1.0), cb, 0))
	dirty = true
	var j := ring_head * 4
	ring[j] = x
	ring[j + 1] = z
	ring[j + 2] = r
	ring[j + 3] = clock
	ring_head = (ring_head + 1) % RING
	if ring_head == ring_tail:
		ring_tail = (ring_tail + 1) % RING

## Зверь: высота над землёй (стоит на снегу, лёгкие почти не проваливаются) и следы.
func animal_step(a: Node3D, dist: float) -> float:
	var x := a.position.x
	var z := a.position.z
	var sd := snow_depth(x, z)
	var md := mud_depth(x, z)
	if sd + md < 0.005:
		return 0.0
	var k: float = ANIMAL_SINK.get(a.kind, 0.5)
	var sink := sd * k + md * k * 0.8
	var L: float = float(a.parts.get("L", 1.0))
	if not a.far:
		a.trk += dist
		var stride := clampf(L * 0.4, 0.22, 0.9)
		if a.trk > stride:
			a.trk = 0.0
			a.trk_side = -a.trk_side
			var yaw: float = a.rotation.y
			var side: float = a.trk_side
			var off := clampf(L * 0.1, 0.04, 0.16) * side
			var w := clampf(L * 0.045, 0.03, 0.11) + sink * 0.25
			_paint(x + cos(yaw) * off, z - sin(yaw) * off, yaw, w, w * 1.3, maxf(sink, 0.02))
	return sd - sink

# ---------- обновление ----------

func _recenter(c: Vector2) -> void:
	var norg := Vector2i(roundi((c.x - SPAN * 0.5) / TEX), roundi((c.y - SPAN * 0.5) / TEX))
	var dx := norg.x - org.x
	var dz := norg.y - org.y
	if absi(dx) >= TS or absi(dz) >= TS or center.x > 1e8:
		timg.fill(Color(0, 0, 0, 0))
	else:
		# вошедшие в окно полосы ещё хранят старое с другого края — стереть
		if dx > 0:
			_clear_cols(org.x + TS, dx)
		elif dx < 0:
			_clear_cols(norg.x, -dx)
		if dz > 0:
			_clear_rows(org.y + TS, dz)
		elif dz < 0:
			_clear_rows(norg.y, -dz)
	org = norg
	center = c
	dirty = true
	position = Vector3(c.x, 0, c.y)
	main.terrain_mat.set_shader_parameter("patch_c", c)
	main.terrain_mat.set_shader_parameter("patch_h", SPAN * 0.5)

func _clear_cols(k0: int, n: int) -> void:
	var s := posmod(k0, TS)
	var a := mini(n, TS - s)
	timg.fill_rect(Rect2i(s, 0, a, TS), Color(0, 0, 0, 0))
	if n > a:
		timg.fill_rect(Rect2i(0, 0, n - a, TS), Color(0, 0, 0, 0))

func _clear_rows(k0: int, n: int) -> void:
	var s := posmod(k0, TS)
	var a := mini(n, TS - s)
	timg.fill_rect(Rect2i(0, s, TS, a), Color(0, 0, 0, 0))
	if n > a:
		timg.fill_rect(Rect2i(0, 0, TS, n - a), Color(0, 0, 0, 0))

## Стереть отжившие следы, пока байт часов не пошёл на новый круг.
func _expire() -> void:
	var n := 0
	while ring_tail != ring_head and n < 4:
		var j := ring_tail * 4
		if clock - ring[j + 3] < LIFE + 2.0:
			break
		var x := ring[j]
		var z := ring[j + 1]
		var r := ring[j + 2]
		for kz in range(floori((z - r) / TEX), floori((z + r) / TEX) + 1):
			for kx in range(floori((x - r) / TEX), floori((x + r) / TEX) + 1):
				if kx < org.x or kz < org.y or kx >= org.x + TS or kz >= org.y + TS:
					continue
				var px := posmod(kx, TS)
				var pz := posmod(kz, TS)
				var o := timg.get_pixel(px, pz)
				if o.r > 0.0 and _fade(o.g) <= 0.0:
					timg.set_pixel(px, pz, Color(0, 0, 0, 0))
		ring_tail = (ring_tail + 1) % RING
		n += 1
		dirty = true

func _process(delta: float) -> void:
	_now += delta
	var w = main.weather
	var temp: float = w.temp
	var pr: float = w.precip
	var wet: float = w.wet
	if _test != "":
		_run_test()
		temp = w.temp
		pr = w.precip
		wet = w.wet
	# глубины: снег из покрова погоды; грязь — от мокрости, мёрзлая земля не вязнет
	snow_m = float(w.snow) * 0.85
	var unfrozen := clampf((temp + 1.0) / 3.0, 0.0, 1.0)
	var cover := clampf(snow_m / 0.1, 0.0, 1.0)
	var mt := 0.5 * clampf(0.15 + wet * 0.85 + (pr if temp > 0.5 else 0.0) * 0.2, 0.0, 1.0) * unfrozen * (1.0 - cover)
	mud_m = lerpf(mud_m, mt, minf(1.0, delta * 0.5))
	# часы засыпания: снегопад, дождь и оттепель заметают следы быстрее
	var rate := 0.33 * (1.0 + pr * 10.0 + maxf(temp - 1.0, 0.0) * 0.15 * cover)
	clock += rate * delta
	var hp: Vector3 = main.hero.position
	var c := Vector2(snappedf(hp.x, SNAP), snappedf(hp.z, SNAP))
	if c != center:
		_recenter(c)
	while not queue.is_empty() and _now - float(queue[0][0]) >= HERO_DELAY:
		var q: Array = queue.pop_front()
		_hero_print(q[1], q[2], q[3], q[4])
	_expire()
	var m: ShaderMaterial = main.terrain_mat
	m.set_shader_parameter("snow_m", snow_m)
	m.set_shader_parameter("mud_m", mud_m)
	if tuft_mat != null:
		tuft_mat.set_shader_parameter("mud_m", mud_m)
	m.set_shader_parameter("track_clock", fposmod(clock, 256.0))
	_up_t -= delta
	if dirty and _up_t <= 0.0:
		_up_t = 0.12
		dirty = false
		ttex.update(timg)

# ---------- проверка: TRACKS_TEST=папка — пройти по снегу и по грязи, снять кадры ----------

func _run_test() -> void:
	_test_f += 1
	var w = main.weather
	var winter := _test_f < 700
	main.day_count = 20 if winter else 30
	w.snow = 1.0 if winter else 0.0
	w.wet = 0.0 if winter else 1.0
	w.t_precip = 0.0
	w.precip = 0.0
	w.next_change = 100.0
	main.t_hours = 12.0
	var f := _test_f % 700
	if f == 1:
		_test_spot(1 if winter else 2, 0.75 if winter else 0.5)
	var gone: float = Vector2(main.hero.position.x - _spot.x, main.hero.position.z - _spot.z).length()
	main.joy.value = Vector2(0.0, -0.8) if f > 30 and gone < 9.0 else Vector2.ZERO
	if f == 2:
		main.rig.rotation.y = 0.0
	if f == 600 or f == 680:
		main.rig.rotation.y = 0.15 if f == 600 else PI * 0.5
		main.rig.distance = 9.0
	if f == 620 or f == 699:
		var tag := "%s_%d" % ["snow" if winter else "mud", f]
		get_viewport().get_texture().get_image().save_png(_test + "/tracks_%s.png" % tag)
		print("tracks shot ", tag, " sink ", sink_at(main.hero.position), " sd ", snow_depth(main.hero.position.x, main.hero.position.z), " md ", mud_depth(main.hero.position.x, main.hero.position.z), " fps ", Engine.get_frames_per_second(), " tris ", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	if f % 100 == 50:
		print("f ", f, " gone ", gone, " sink ", main.hero.sink, " mud ", main.hero.mud_sink, " slow ", slow(Vector2(main.hero.sink, main.hero.mud_sink)), " mud_m ", mud_m, " mf ", _field(main.hero.position.x, main.hero.position.z, 2))
	if _test_f >= 1399:
		get_tree().quit()

## Найти ровное место с сильным значением канала ch (сугроб или грязь) и поставить туда героя.
func _test_spot(ch: int, want: float) -> void:
	for r in range(0, 200, 3):
		for kk in 32:
			var ang := kk * TAU / 32.0
			var x: float = main.hero.position.x + cos(ang) * r
			var z: float = main.hero.position.z + sin(ang) * r
			var y: float = main.height(x, z)
			var ok := true
			for j in 5:
				var zz := z - j * 2.0
				if _field(x, zz, ch) < want * 0.7 or (ch == 1 and _field(x, zz, 0) > 0.35) or main.height(x, zz) < main.WATER_Y + 0.3 or main.blocked(x, zz, 0.5):
					ok = false
			if ok and _field(x, z, ch) > want:
				main.hero.position = Vector3(x, y, z)
				_spot = main.hero.position
				main.rig.position = main.hero.position
				return
