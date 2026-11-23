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

class EndProbe extends Node:
	var probe: Node
	func _process(_d: float) -> void:
		probe.call("_end", Time.get_ticks_usec())

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
		print("PERF %-18s скрипты за кадр: среднее %.3f мс, медиана %.3f, 95%% %.3f" % [_stages[_stage][0], s / _us.size(), _us[_us.size() / 2], _us[int(_us.size() * 0.95)]])
		_toggle(String(_stages[_stage][1]), true)
		if _stage + 1 >= _stages.size():
			get_tree().quit()
			return
		_begin(_stage + 1)

func _end(t: int) -> void:
	if _stage >= 0:
		_us.append(float(t - _t0) / 1000.0)

func _begin(i: int) -> void:
	_stage = i
	_n = 0
	_us.clear()
	_toggle(String(_stages[i][1]), false)

func _toggle(key: String, on: bool) -> void:
	if key == "@self":
		main.set_process(on)
	elif key != "" and main.get(key) != null:
		(main.get(key) as Node).process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
