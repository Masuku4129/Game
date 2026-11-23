extends Node3D
## Связка брёвен на верёвке (до восьми), которую герой волочит за собой.
## Брёвна уложены пирамидкой (3 + 3 + 2), стянуты двумя витками верёвки. Перед связки
## (где завязан повод) идёт за плечом героя на длине повода и чуть приподнят, зад едет по земле:
## ось связки — от зада к переду, зад тянется за передом на длине связки (волок без отрыва).
## Звук — шорох по земле на каждые полметра пути.
## API: setup(брёвна, где герой, куда смотрит), step(dt, точка повода), count(), remove(n), untie(world).

const TM = preload("res://scripts/tool_models.gd")
const ROPE := 1.0             # повод от плеча до переда связки, м
const LIFT := 0.22            # перед связки над землёй, м

var main: Node3D
var logs: Array = []          # [{"r", "bark", "L"}]
var front := Vector3.ZERO     # точка повода на переднем торце (мир)
var rear := Vector3.ZERO      # середина заднего торца (мир)
var L := 1.25                 # длина связки
var hands: Array = []         # [кисти, плечо] — повод от рук через плечо (ставит hero_tools)
var body := Node3D.new()      # брёвна и витки в осях связки: +Y — к переду, центр в середине
var rope_a := MeshInstance3D.new()
var rope_b := MeshInstance3D.new()
var _slots: Array = []        # смещения брёвен в сечении [x, z, сдвиг вдоль]
var _hz := 0.0                # высота центра связки над нижним бревном
var _trav := 0.0

func _ready() -> void:
	add_child(body)
	for r in [rope_a, rope_b]:
		r.mesh = _rope_mesh()
		add_child(r)

static func _rope_mesh() -> ArrayMesh:
	var b = TM.B.new(81)
	var c := Color(0.6, 0.5, 0.33)
	b.tube([Vector3.ZERO, Vector3(0, 0.5, 0), Vector3(0, 1, 0)], [0.008, 0.008, 0.008], [c, c.darkened(0.08), c], 5, false)
	return b.commit(TM.mat())

func count() -> int:
	return logs.size()

func setup(list: Array, hero_p: Vector3, fwd: Vector3) -> void:
	logs = list.duplicate()
	var f := Vector3(fwd.x, 0, fwd.z).normalized()
	front = hero_p - f * (ROPE * 0.9)
	_rebuild()
	rear = front - f * L
	_place()

## Сечение: ряды по 3, 3, 2 бревна; длина — по самому длинному.
func _rebuild() -> void:
	for c in body.get_children():
		c.queue_free()
	_slots.clear()
	var r := 0.13
	L = 0.5
	for lg: Dictionary in logs:
		r = maxf(r, float(lg["r"]))
		L = maxf(L, float(lg["L"]))
	var rows := [3, 3, 2]
	var left := logs.size()
	var row := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	while left > 0 and row < rows.size():
		var n := mini(rows[row], left)
		for j in n:
			_slots.append([(float(j) - (n - 1) * 0.5) * r * 2.02, float(row) * r * 1.74, rng.randf_range(-0.07, 0.07)])
		left -= n
		row += 1
	_hz = r
	var top := 0.0
	var wx := 0.0
	for i in logs.size():
		var lg: Dictionary = logs[i]
		var sl: Array = _slots[i]
		var mi := MeshInstance3D.new()
		mi.mesh = TM.log_mesh(snappedf(float(lg["L"]), 0.05), snappedf(float(lg["r"]), 0.01), lg["bark"], 3 + i)
		body.add_child(mi)
		mi.position = Vector3(float(sl[0]), float(sl[2]), float(sl[1]))
		mi.rotation.y = rng.randf_range(0, TAU)
		top = maxf(top, float(sl[1]))
		wx = maxf(wx, absf(float(sl[0])))
	# два витка верёвки вокруг всей связки: обвод по сечению с запасом
	var b = TM.B.new(82)
	var c := Color(0.6, 0.5, 0.33)
	for yy in [-L * 0.3, L * 0.3]:
		var pts: Array = []
		var rs: Array = []
		var cs: Array = []
		for k in 25:
			var a := TAU * k / 24.0
			var ex := wx + r + 0.01
			var ez := (top + 2.0 * r) * 0.5 + 0.01
			pts.append(Vector3(cos(a) * ex, yy + sin(a * 3.0) * 0.006, top * 0.5 + sin(a) * ez))
			rs.append(0.009)
			cs.append(c.darkened(0.06 * sin(a * 5.0)))
		b.tube(pts, rs, cs, 5, false, 20.0)
	var band := MeshInstance3D.new()
	band.mesh = b.commit(TM.mat())
	body.add_child(band)

## Шаг волока: повод держит перед на своей длине, зад тянется следом по земле.
func step(delta: float, anchor: Vector3) -> void:
	var d := front - anchor
	d.y = 0.0
	var moved := 0.0
	if d.length() > ROPE:
		var nf := anchor + d.normalized() * ROPE
		moved = Vector2(nf.x - front.x, nf.z - front.z).length()
		front = nf
	var ax := front - rear
	ax.y = 0.0
	if ax.length() > 0.01:
		rear = front - ax.normalized() * L
	_place()
	_trav += moved
	if _trav > 0.5 and main != null and main.get("sfx") != null and main.sfx != null:
		_trav = 0.0
		main.sfx.play_at("cut", (front + rear) * 0.5, -12.0, randf_range(0.45, 0.6))
	if delta < 0.0:
		pass

func _gy(p: Vector3) -> float:
	if main == null:
		return 0.0
	return float(main.ground_at(p.x, p.z))

func _place() -> void:
	front.y = _gy(front) + LIFT + _hz
	rear.y = _gy(rear) + _hz
	var y := (front - rear).normalized()
	var x := y.cross(Vector3.UP).normalized()
	if x.length() < 0.5:
		x = Vector3.RIGHT
	var z := x.cross(y).normalized()
	global_transform = Transform3D.IDENTITY
	body.transform = Transform3D(Basis(x, y, z), (front + rear) * 0.5 - z * _hz * 0.0)
	# повод: от рук через плечо к переду связки
	var tie := body.transform * Vector3(0, L * 0.5, (_slots[0][1] if not _slots.is_empty() else 0.0))
	var sh: Vector3 = hands[1] if hands.size() > 1 else tie + Vector3(0, 1.2, 0)
	var hd: Vector3 = hands[0] if hands.size() > 0 else sh
	_seg(rope_a, tie, sh)
	_seg(rope_b, sh, hd)

func _seg(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var ln := maxf(d.length(), 0.001)
	var y := d / ln
	var x := y.cross(Vector3(0, 0, 1) if absf(y.z) < 0.9 else Vector3(1, 0, 0)).normalized()
	mi.transform = Transform3D(Basis(x, y * ln, x.cross(y).normalized()), a)

## Снять n брёвен (на стройку).
func remove(n: int) -> void:
	for i in mini(n, logs.size()):
		logs.pop_back()
	if not logs.is_empty():
		_rebuild()
		_place()

## Развязать: брёвна ложатся на землю там, где лежали в связке.
func untie(w: Node) -> void:
	var y := (front - rear)
	y.y = 0.0
	y = y.normalized()
	var x := y.cross(Vector3.UP).normalized()
	var c := (front + rear) * 0.5
	for i in logs.size():
		var lg: Dictionary = logs[i]
		var sl: Array = _slots[i]
		var p := c + x * float(sl[0]) * 1.4 + y * float(sl[2])
		if w != null:
			w._spawn_log(p, y, float(lg["L"]), float(lg["r"]), lg["bark"])
	queue_free()
