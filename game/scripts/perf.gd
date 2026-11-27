extends Node
## Замер нагрузки на процессор без экрана: PERF=1 godot --headless.
## Время всех _process за кадр меряется между двумя узлами: этот обрабатывается первым
## (process_priority -1e6), его дочерний «конец» — последним (+1e6). Герой идёт по кругу.
## Блоки по FRAMES кадров: сначала всё включено, затем по очереди выключается одна система,
## чтобы увидеть её долю. Печатает «PERF …» и выходит.

const WARM := 240
const FRAMES := 300

var main: Node3D
var _n := 0
var _stage := -1
var _stages: Array = []
var _t0 := 0
var _us: Array = []
var _draws: Array[float] = []
var _tris: Array[float] = []
var _physics_active: Array[float] = []
var _physics_pairs: Array[float] = []
var _nodes: Array[float] = []
var _frame_ms: Array[float] = []

class EndProbe extends Node:
	var probe: Node
	func _process(d: float) -> void:
		probe.call("_end", Time.get_ticks_usec(), d)

func _ready() -> void:
	process_priority = -1000000
	var e := EndProbe.new()
	e.probe = self
	e.process_priority = 1000000
	add_child(e)
	_stages = [["всё", ""], ["без зверей", "animals"], ["без бобров", "beavers"], ["без следов", "feet"], ["без звука", "sfx"], ["без охоты", "hunt"], ["без инструм.", "tools_world"], ["без погоды", "weather"], ["без героя", "hero"], ["без лагеря", "camp"], ["без main._process", "@self"], ["всё (повтор)", ""]]

func _process(_d: float) -> void:
	_t0 = Time.get_ticks_usec()
	_n += 1
	# герой идёт по большому кругу: работают следы, трава, звуки шагов
	if main.joy != null:
		var a := Time.get_ticks_msec() * 0.0002
		main.joy.value = Vector2(cos(a), sin(a)) * 0.8
	if _stage < 0:
		if _n >= WARM:
			_begin(0)
		return
	if _n >= FRAMES:
		_us.sort()
		var s := 0.0
		for u: float in _us:
			s += u
		print("PERF %-18s CPU scripts avg %.3f ms | median %.3f | p95 %.3f" % [_stages[_stage][0], s / _us.size(), _us[_us.size() / 2], _us[int(_us.size() * 0.95)]])
		_print_metric("frame", _frame_ms, "ms")
		_print_metric("draw_calls", _draws, "")
		_print_metric("triangles", _tris, "")
		_print_metric("physics_active", _physics_active, "")
		_print_metric("physics_pairs", _physics_pairs, "")
		_print_metric("nodes", _nodes, "")
		_toggle(String(_stages[_stage][1]), true)
		if _stage + 1 >= _stages.size():
			get_tree().quit()
			return
		_begin(_stage + 1)

func _end(t: int, delta: float) -> void:
	if _stage < 0:
		return
	_us.append(float(t - _t0) / 1000.0)
	_frame_ms.append(delta * 1000.0)
	_draws.append(float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	_tris.append(float(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	_physics_active.append(float(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)))
	_physics_pairs.append(float(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)))
	_nodes.append(float(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))

func _print_metric(label: String, values: Array[float], unit: String) -> void:
	if values.is_empty():
		return
	values.sort()
	var total := 0.0
	for value in values:
		total += value
	var suffix := " " + unit if unit != "" else ""
	print("PERF   %-16s avg %.2f%s | median %.2f%s | p95 %.2f%s" % [label, total / values.size(), suffix, values[values.size() / 2], suffix, values[mini(values.size() - 1, int(values.size() * 0.95))], suffix])

func _begin(i: int) -> void:
	_stage = i
	_n = 0
	_us.clear()
	_draws.clear()
	_tris.clear()
	_physics_active.clear()
	_physics_pairs.clear()
	_nodes.clear()
	_frame_ms.clear()
	_toggle(String(_stages[i][1]), false)

func _toggle(key: String, on: bool) -> void:
	if key == "@self":
		main.set_process(on)
	elif key != "" and main.get(key) != null:
		(main.get(key) as Node).process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
