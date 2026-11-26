extends MeshInstance3D
## Снег, грязь и следы.
## Снег лежит неравномерно: сугробы на открытом месте и с подветренной стороны склонов,
## под густым ельником тонко. Грязь — в низинах у воды и пятнами на ровных местах, после
## дождя глубже. Глубина в точке — snow_depth()/mud_depth(); земля в шейдере поднята на
## глубину снега. Следы рисуются в текстуру 960×960 (40×40 м вокруг героя, по кругу —
## края при сдвиге стираются), мелкая сетка-заплатка у героя продавливается по ней:
## мелкие отпечатки, ямы по колено, траншея по пояс. Следы засыпает снегом и замывает
## дождём (часы засыпания идут быстрее в осадки), пропадают, когда тает снег.

const TS := 960                 # текселей по стороне карты следов
const SPAN := 40.0              # метров по стороне карты следов и заплатки
const TEX := SPAN / TS          # ~4 см на тексель
const CELLS := 128              # клеток сетки заплатки по стороне
const SNAP := 5.0               # шаг сдвига заплатки, м
const LIFE := 200.0             # «часов засыпания» до полного исчезновения следа
const DEPTH_MAX := 1.25         # глубина, соответствующая байту 255
const BEHIND := 0.45            # след героя появляется позади него, а не под ногами
const FOOT_OFF := 0.12          # стопы — на столько в стороны от оси пути
const TRENCH := 0.5             # глубже — сплошная траншея вместо отдельных ям
const SHALLOW := 0.14           # мельче — отпечаток стопы, глубже — овальная яма
const VIS_R := 13.0             # дальше от героя следы плавно тают
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
var bog_m := 0.0
var bog_data := PackedByteArray()
var queue: Array = []           # отложенные следы героя: [время, x, z, dx, dz, сторона, y, x0, z0]
var _hp_last := Vector3(1e9, 0, 0)
var _dir := Vector2(0, 1)
var _step_acc := 0.0
var _side := 1.0
var _seg_last := Vector2(1e9, 0)  # последняя точка траншеи
var _animals := {}              # id зверя -> [последний след, сторона]
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
	m.set_shader_parameter("track_res", TEX)
	m.set_shader_parameter("track_r", VIS_R)
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
	bog_data.resize(fn * fn)
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
			# Отдельная маска настоящих болотных зон (zone 2), а не просто тёмной текстуры.
			bog_data[i] = 255 if main.zone(x, z) == 2 else 0
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
	# --- build: тропы и расчищенный лопатой снег (канал A карты поля — 255 минус износ) ---
	return snow_m * 1.4 * _field(x, z, 1) * (1.0 - 0.85 * wear_at(x, z))

func bog_factor(x: float, z: float) -> float:
	var gx := clampf((x + half) / fstep, 0.0, fn - 1.0001)
	var gz := clampf((z + half) / fstep, 0.0, fn - 1.0001)
	var ix := int(gx)
	var iz := int(gz)
	var fx := gx - ix
	var fz := gz - iz
	var a := float(bog_data[iz * fn + ix]) / 255.0
	var b := float(bog_data[iz * fn + ix + 1]) / 255.0
	var c := float(bog_data[(iz + 1) * fn + ix]) / 255.0
	var d := float(bog_data[(iz + 1) * fn + ix + 1]) / 255.0
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fz)

func mud_depth(x: float, z: float) -> float:
	# Обычная грязь появляется от дождя; болото остаётся насыщенным водой
	# даже в сухую погоду и промерзает только при устойчивом морозе.
	return mud_m * _field(x, z, 2) + bog_m * bog_factor(x, z)

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
	# --- build: по натоптанной тропе идти легче ---
	return (1.0 + path_k * 0.15) / (1.0 + 1.3 * s + 0.55 * s * s)

# ---------- build: тропы и расчистка снега ----------
# Износ хранится в канале A карты поля (255 — нетронуто, 0 — земля расчищена/утоптана до конца).
# Он постоянный: тропа, натоптанная за много проходов, остаётся; снег на ней лежит тонко,
# летом трава на ней вытерта (ground.gdshader). Лопата и постройки ставят износ сразу.
var path_k := 0.0     # герой на тропе (0..1): шаг чуть быстрее
var _wear_dirty := false
var _wear_t := 0.0

## Износ в точке 0..1.
func wear_at(x: float, z: float) -> float:
	return 1.0 - _field(x, z, 3)

## Добавить износ в круге радиуса r (по узлам сетки поля), не выше cap.
func add_wear(x: float, z: float, r: float, amount: float, cap: float = 1.0) -> void:
	var i0 := maxi(0, int(floor((x - r + half) / fstep)))
	var i1 := mini(fn - 1, int(ceil((x + r + half) / fstep)))
	var j0 := maxi(0, int(floor((z - r + half) / fstep)))
	var j1 := mini(fn - 1, int(ceil((z + r + half) / fstep)))
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var px := i * fstep - half
			var pz := j * fstep - half
			var d := Vector2(px - x, pz - z).length()
			var rr := r + fstep * 0.5
			if d > rr:
				continue
			var k := (j * fn + i) * 4 + 3
			var w := 1.0 - float(fdata[k]) / 255.0
			if w >= cap:
				continue
			w = minf(cap, w + amount * clampf(1.2 - d / rr, 0.0, 1.0))
			fdata[k] = int(round((1.0 - w) * 255.0))
			_wear_dirty = true

# ---------- следы ----------

## Вызов из hero.gd на каждом шаге анимации: следы теперь ставятся по пройденному пути
## (ровная цепочка вдоль оси движения), поэтому здесь ничего не делаем.
func stamp(_p: Vector3, _yaw: float) -> void:
	pass

## Путь героя: каждые полшага — след левой или правой ноги, в траншее — отрезок оси.
func _track_hero() -> void:
	var hero = main.hero
	var hp: Vector3 = hero.position
	var ok: bool = hero.state == "walk" and float(hero.swimb) < 0.2 and float(hero.depth) < 0.6 and not hero.airborne
	var mv := Vector2(hp.x - _hp_last.x, hp.z - _hp_last.z)
	var dl := mv.length()
	if not ok or dl > 2.5:
		_hp_last = hp
		_step_acc = 0.0
		_seg_last = Vector2(1e9, 0)
		return
	if dl < 0.06:
		return
	# направление пути, сглаженное по пройденному расстоянию (не по повороту тела)
	_dir = _dir.lerp(mv / dl, clampf(dl / 0.6, 0.0, 1.0)).normalized()
	_hp_last = hp
	_step_acc += dl
	var sp: float = Vector2(hero.vel.x, hero.vel.z).length()
	var stride := clampf(0.55 + sp * 0.1, 0.6, 1.0)
	if _step_acc >= stride:
		_step_acc = fmod(_step_acc, stride)
		_side = -_side
		queue.append([_now, hp.x, hp.z, _dir.x, _dir.y, _side, hp.y, _seg_last.x, _seg_last.y])
		# --- build: каждый шаг понемногу натаптывает тропу ---
		add_wear(hp.x, hp.z, 0.7, 0.018, 0.75)
		_seg_last = Vector2(hp.x, hp.z)

## Глубина следа героя в точке (0 — следа нет).
func _print_depth(x: float, z: float, y: float) -> float:
	var h: float = main.height(x, z)
	if y > h + 0.15:
		return 0.0  # на камне, бревне, льду
	var sd := snow_depth(x, z)
	var md := mud_depth(x, z)
	var s := 0.0
	if sd > 0.01:
		s = sd
	if md > 0.01:
		s = maxf(s, sd + md * 0.9)
	var w: float = main.weather.wet
	if s < 0.01 and w > 0.15 and float(main.weather.temp) > 0.0:
		s = 0.02 * w
	return s if s >= 0.008 else 0.0

func _hero_print(q: Array) -> void:
	var x: float = q[1]
	var z: float = q[2]
	var dir := Vector2(q[3], q[4])
	var side: float = q[5]
	var s := _print_depth(x, z, q[6])
	if s <= 0.0:
		return
	var yaw := atan2(dir.x, dir.y)
	if s >= TRENCH:
		# по пояс: сплошная траншея с отвесными стенками по оси пути
		var x0: float = q[7]
		var z0: float = q[8]
		if x0 > 1e8 or Vector2(x - x0, z - z0).length() > 1.6:
			x0 = x - dir.x * 0.3
			z0 = z - dir.y * 0.3
		_paint_seg(x0, z0, x, z, lerpf(0.26, 0.32, smoothstep(TRENCH, 1.0, s)), s)
		return
	# стопа в стороне от оси пути, носком по ходу
	var px := x + dir.y * side * FOOT_OFF
	var pz := z - dir.x * side * FOOT_OFF
	if s < SHALLOW:
		_paint_foot(px, pz, yaw, s, side)
	else:
		# по колено: ровная овальная яма, глубже — шире и длиннее
		var k := smoothstep(SHALLOW, TRENCH, s)
		_paint_oval(px, pz, yaw, lerpf(0.09, 0.14, k), lerpf(0.2, 0.32, k), s, 5.0)

## Отпечаток стопы: носок и каблук.
func _paint_foot(x: float, z: float, yaw: float, depth: float, side: float) -> void:
	var fx := sin(yaw)
	var fz := cos(yaw)
	var r := 0.17
	if not _in_window(x, z, r):
		return
	var cb := _cb()
	for kz in range(floori((z - r) / TEX), floori((z + r) / TEX) + 1):
		var wz := (kz + 0.5) * TEX - z
		for kx in range(floori((x - r) / TEX), floori((x + r) / TEX) + 1):
			var wx := (kx + 0.5) * TEX - x
			var u := (wx * fz - wz * fx) * side  # поперёк, наружу от оси
			var v := wx * fx + wz * fz            # вдоль, вперёд
			var et := pow((u - 0.008) / 0.052, 2.0) + pow((v - 0.05) / 0.085, 2.0)
			var eh := pow(u / 0.042, 2.0) + pow((v + 0.085) / 0.05, 2.0)
			var e := minf(et, eh)
			if e < 1.0:
				_put(kx, kz, depth * clampf((1.0 - e) * 4.0, 0.0, 1.0), cb)
	_note(x, z, r)

## Овал (яма или след зверя); sharp — крутизна стенок.
func _paint_oval(x: float, z: float, yaw: float, hw: float, hl: float, depth: float, sharp: float) -> void:
	var fx := sin(yaw)
	var fz := cos(yaw)
	var r := maxf(hw, hl)
	if not _in_window(x, z, r):
		return
	var cb := _cb()
	for kz in range(floori((z - r) / TEX), floori((z + r) / TEX) + 1):
		var wz := (kz + 0.5) * TEX - z
		for kx in range(floori((x - r) / TEX), floori((x + r) / TEX) + 1):
			var wx := (kx + 0.5) * TEX - x
			var u := (wx * fz - wz * fx) / hw
			var v := (wx * fx + wz * fz) / hl
			var e := u * u + v * v
			if e < 1.0:
				_put(kx, kz, depth * clampf((1.0 - sqrt(e)) * sharp, 0.0, 1.0), cb)
	_note(x, z, r)

## Отрезок траншеи шириной 2·hw с плоским дном и почти отвесными стенками.
func _paint_seg(x0: float, z0: float, x1: float, z1: float, hw: float, depth: float) -> void:
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	var ax := x1 - x0
	var az := z1 - z0
	var l2 := maxf(ax * ax + az * az, 1e-6)
	var r := sqrt(l2) * 0.5 + hw
	if not _in_window(cx, cz, r):
		return
	var cb := _cb()
	for kz in range(floori((minf(z0, z1) - hw) / TEX), floori((maxf(z0, z1) + hw) / TEX) + 1):
		var wz := (kz + 0.5) * TEX
		for kx in range(floori((minf(x0, x1) - hw) / TEX), floori((maxf(x0, x1) + hw) / TEX) + 1):
			var wx := (kx + 0.5) * TEX
			var t := clampf(((wx - x0) * ax + (wz - z0) * az) / l2, 0.0, 1.0)
			var dx := wx - (x0 + ax * t)
			var dz := wz - (z0 + az * t)
			var dd := sqrt(dx * dx + dz * dz)
			if dd < hw:
				_put(kx, kz, depth * clampf((1.0 - dd / hw) * 7.0, 0.0, 1.0), cb)
	_note(cx, cz, r)

func _in_window(x: float, z: float, r: float) -> bool:
	return absf(x - center.x) + r < SPAN * 0.5 - 3.0 and absf(z - center.y) + r < SPAN * 0.5 - 3.0

func _cb() -> float:
	return float(int(clock) % 256) / 255.0

## Записать глубину в тексель, если новая глубже видимой старой.
func _put(kx: int, kz: int, d: float, cb: float) -> void:
	var px := posmod(kx, TS)
	var pz := posmod(kz, TS)
	var old := timg.get_pixel(px, pz)
	if d > old.r * DEPTH_MAX * _fade(old.g) + 0.004:
		timg.set_pixel(px, pz, Color(minf(d / DEPTH_MAX, 1.0), cb, 0))

## Запомнить след, чтобы стереть его, когда засыплет.
func _note(x: float, z: float, r: float) -> void:
	dirty = true
	var j := ring_head * 4
	ring[j] = x
	ring[j + 1] = z
	ring[j + 2] = r
	ring[j + 3] = clock
	ring_head = (ring_head + 1) % RING
	if ring_head == ring_tail:
		ring_tail = (ring_tail + 1) % RING

## Зверь: высота над землёй (стоит на снегу, лёгкие почти не проваливаются) и следы
## ровной цепочкой вдоль его пути.
func animal_step(a: Node3D, _dist: float) -> float:
	var x := a.position.x
	var z := a.position.z
	var sd := snow_depth(x, z)
	var md := mud_depth(x, z)
	if sd + md < 0.005:
		return 0.0
	var k: float = ANIMAL_SINK.get(a.kind, 0.5)
	var sink := sd * k + md * k * 0.8
	if not a.far:
		var id := a.get_instance_id()
		var st: Array = _animals.get(id, [])
		var here := Vector2(x, z)
		if st.is_empty():
			_animals[id] = [here, 1.0]
		else:
			var last: Vector2 = st[0]
			var dv := here - last
			var dl := dv.length()
			var L: float = float(a.parts.get("L", 1.0))
			var stride := clampf(L * 0.4, 0.22, 0.9)
			if dl > 3.0:
				st[0] = here
			elif dl >= stride:
				var dir := dv / dl
				var side: float = -float(st[1])
				st[0] = here
				st[1] = side
				var off := clampf(L * 0.09, 0.04, 0.15) * side
				var w := clampf(L * 0.045, 0.03, 0.11) + sink * 0.2
				_paint_oval(x + dir.y * off, z - dir.x * off, atan2(dir.x, dir.y), w, w * 1.3, maxf(sink, 0.02), 4.0)
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
	_up_t = 0.0  # сразу: иначе пару кадров видна стёртая полоса со старым содержимым
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
	var bog_thaw := clampf((temp + 3.0) / 6.0, 0.0, 1.0)
	var bog_saturation := clampf(0.55 + wet * 0.25 + pr * 0.2, 0.35, 1.0)
	var bog_target := bog_thaw * lerpf(0.28, 0.72, bog_saturation)
	bog_m = lerpf(bog_m, bog_target, minf(1.0, delta * 0.4))
	# часы засыпания: снегопад, дождь и оттепель заметают следы быстрее
	var rate := 0.33 * (1.0 + pr * 10.0 + maxf(temp - 1.0, 0.0) * 0.15 * cover)
	clock += rate * delta
	var hp: Vector3 = main.hero.position
	# заплатку сдвигаем с запасом, чтобы она не металась туда-сюда на границе
	if absf(hp.x - center.x) > SNAP * 0.7 or absf(hp.z - center.y) > SNAP * 0.7:
		_recenter(Vector2(snappedf(hp.x, SNAP), snappedf(hp.z, SNAP)))
	_track_hero()
	while not queue.is_empty():
		var q: Array = queue[0]
		var behind := Vector2(hp.x - float(q[1]), hp.z - float(q[2])).length()
		if behind < BEHIND and _now - float(q[0]) < 1.0:
			break
		queue.pop_front()
		_hero_print(q)
	_expire()
	if _animals.size() > 400:
		_animals.clear()
	var m: ShaderMaterial = main.terrain_mat
	m.set_shader_parameter("snow_m", snow_m)
	m.set_shader_parameter("mud_m", mud_m)
	m.set_shader_parameter("bog_m", bog_m)
	if tuft_mat != null:
		tuft_mat.set_shader_parameter("mud_m", mud_m)
	m.set_shader_parameter("track_clock", fposmod(clock, 256.0))
	m.set_shader_parameter("track_eye", Vector2(hp.x, hp.z))
	# --- build: износ (тропы, расчистка) — в текстуру поля не чаще раза в 0,4 с ---
	_wear_t -= delta
	if _wear_dirty and _wear_t <= 0.0:
		_wear_t = 1.0  # perf: реже (было 0,4 с)
		_wear_dirty = false
		field_tex.update(Image.create_from_data(fn, fn, false, Image.FORMAT_RGBA8, fdata))
	path_k = smoothstep(0.25, 0.6, wear_at(hp.x, hp.z))
	_up_t -= delta
	if dirty and _up_t <= 0.0:
		_up_t = 0.2  # perf: было 0,12 с
		dirty = false
		ttex.update(timg)

# ---------- проверка: TRACKS_TEST=папка — пройти по снегу и по грязи, снять кадры ----------

func _run_test() -> void:
	_test_f += 1
	var w = main.weather
	var ph := _test_f / 500
	var f := _test_f % 500
	var names := ["shallow", "knee", "waist", "mud"]
	var winter := ph < 3
	main.day_count = 20 if winter else 30
	w.snow = [0.15, 0.55, 1.0, 0.0][mini(ph, 3)]
	w.wet = 0.0 if winter else 1.0
	w.t_precip = 0.0
	w.precip = 0.0
	w.next_change = 100.0
	main.t_hours = 12.0
	if f == 1:
		_test_spot(1 if winter else 2, 0.75 if winter else 0.5)
	var gone: float = Vector2(main.hero.position.x - _spot.x, main.hero.position.z - _spot.z).length()
	main.joy.value = Vector2(0.35 * sin(f * 0.03), -0.8) if f > 30 and gone < 9.0 else Vector2.ZERO
	if f == 2:
		main.rig.rotation.y = 0.0
	if f == 410 or f == 480:
		main.rig.rotation.y = 0.15 if f == 410 else PI * 0.5
		main.rig.distance = 8.0
	if f == 430 or f == 499:
		var tag := "%d%s_%d" % [ph, names[mini(ph, 3)], f]
		get_viewport().get_texture().get_image().save_png(_test + "/tracks_%s.png" % tag)
		print("tracks shot ", tag, " sink ", sink_at(main.hero.position), " sd ", snow_depth(main.hero.position.x, main.hero.position.z), " md ", mud_depth(main.hero.position.x, main.hero.position.z), " fps ", Engine.get_frames_per_second(), " tris ", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	if _test_f >= 1999:
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

# --- core: сохранение (save.gd, раздел «feet»): износ — тропы и расчищенный снег —
# канал A карты поля, двоичным блоком "feet_wear" (fn×fn байт) ---
func to_save() -> Dictionary:
	var w := PackedByteArray()
	w.resize(fn * fn)
	for i in fn * fn:
		w[i] = fdata[i * 4 + 3]
	if main.get("saver") != null:
		main.saver.put_bytes("feet_wear", w)
	return {"fn": fn}

func from_save(d: Dictionary) -> void:
	if int(d.get("fn", 0)) != fn or main.get("saver") == null:
		return
	var w: PackedByteArray = main.saver.get_bytes("feet_wear")
	if w.size() != fn * fn:
		return
	for i in fn * fn:
		fdata[i * 4 + 3] = w[i]
	_wear_dirty = true
	_wear_t = 0.0
# --- /core ---
