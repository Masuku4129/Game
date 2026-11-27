extends Node
## --- core: сохранение и загрузка (main.saver) ---
## Файлы: user://save.json — всё состояние (JSON), user://save.bin — двоичные блоки (текстуры).
## Автосохранение раз в AUTOSAVE секунд, при сворачивании (NOTIFICATION_APPLICATION_PAUSED)
## и при закрытии окна (NOTIFICATION_WM_CLOSE_REQUEST).
##
## РЕЕСТР — как подключить свою систему (для других команд: верёвки, связки, стрелы…):
##   main.saver.register("ropes", self, 70)
##       ключ — уникальное имя раздела в save.json; объект — любой Object с методами
##       to_save() -> Dictionary  и  from_save(d: Dictionary) -> void;
##       порядок (меньше — раньше) важен при загрузке: мир (60) → постройки (50) → звери (80).
##   Внутри to_save()/from_save() значения кодировать через SaveSys.enc(v) / SaveSys.dec(v):
##       Vector2/3, Vector2i, Color, Transform3D, Basis превращаются в словари с меткой "_t".
##       Числа из JSON приходят float — приводить int() там, где нужен int.
##   Двоичные данные: saver.put_bytes("ключ", PackedByteArray) в to_save(),
##       saver.get_bytes("ключ") в from_save().
##   Раздел, которого нет в файле (старое сохранение), просто не вызывает from_save().
## Встроенные разделы: main (время, герой, статы, короб, рука и пояс), weather, feet (тропы),
## camp (постройки, хранилища, огонь, изба, мебель, сушило), tools (поваленные деревья, стволы,
## брёвна, воткнутые копья, места сбора), animals (где звери, кто убит), hunt (вещи на земле, туши).

const PATH := "user://save.json"
const BIN := "user://save.bin"
const VERSION := 1
const AUTOSAVE := 120.0

var main: Node3D
var enabled := false        # до выбора в меню «Продолжить / Новая игра» не сохраняем
var _reg: Array = []        # [ключ, объект, порядок]
var _bytes := {}
var _t := 0.0
var last_status := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().set_auto_accept_quit(false)

func register(key: String, obj: Object, order: int = 100) -> void:
	for r: Array in _reg:
		if r[0] == key:
			r[1] = obj
			r[2] = order
			return
	_reg.append([key, obj, order])
	_reg.sort_custom(func(a: Array, b: Array) -> bool: return int(a[2]) < int(b[2]))

func put_bytes(key: String, b: PackedByteArray) -> void:
	_bytes[key] = b

func get_bytes(key: String) -> PackedByteArray:
	return _bytes.get(key, PackedByteArray())

func _active_path() -> String:
	return "user://creative_save.json" if main != null and bool(main.get("creative_mode")) else PATH

func _active_bin_path() -> String:
	return "user://creative_save.bin" if main != null and bool(main.get("creative_mode")) else BIN


static func has_save() -> bool:
	return FileAccess.file_exists(PATH)

static func delete_slot(creative: bool) -> void:
	var files: Array = ["user://creative_save.json", "user://creative_save.bin"] if creative else [PATH, BIN]
	for p: String in files:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

static func delete_save() -> void:
	delete_slot(false)
	delete_slot(true)

## Собрать всё состояние в словарь (без записи на диск).
func snapshot() -> Dictionary:
	_bytes = {}
	var d := {"version": VERSION, "time": Time.get_unix_time_from_system()}
	for r: Array in _reg:
		var o: Object = r[1]
		if o != null and is_instance_valid(o) and o.has_method("to_save"):
			d[r[0]] = o.call("to_save")
	return d

func save_game() -> bool:
	if not enabled or main == null or main.hero == null or main.hero.state == "dead":
		return false
	var t0 := Time.get_ticks_usec()
	var d := snapshot()
	var active_path := _active_path()
	var f := FileAccess.open(active_path + ".tmp", FileAccess.WRITE)
	if f == null:
		last_status = "не записать сохранение"
		return false
	f.store_string(JSON.stringify(d))
	f.close()
	var fb := FileAccess.open(_active_bin_path(), FileAccess.WRITE)
	if fb != null:
		fb.store_var(_bytes)
		fb.close()
	var rename_err := DirAccess.rename_absolute(ProjectSettings.globalize_path(active_path + ".tmp"), ProjectSettings.globalize_path(active_path))
	if rename_err != OK:
		last_status = "не удалось завершить запись сохранения"
		return false
	last_status = "сохранено за %.0f мс" % ((Time.get_ticks_usec() - t0) / 1000.0)
	print("SAVE ", last_status)
	return true

func load_game() -> bool:
	var active_path := _active_path()
	if not FileAccess.file_exists(active_path):
		return false
	var f := FileAccess.open(active_path, FileAccess.READ)
	if f == null:
		return false
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		push_warning("save.json повреждён")
		return false
	_bytes = {}
	var active_bin := _active_bin_path()
	if FileAccess.file_exists(active_bin):
		var fb := FileAccess.open(active_bin, FileAccess.READ)
		var v: Variant = fb.get_var()
		fb.close()
		if v is Dictionary:
			_bytes = v
	apply(parsed as Dictionary)
	return true

## Раздать разделы системам по порядку реестра.
func apply(d: Dictionary) -> void:
	for r: Array in _reg:
		var o: Object = r[1]
		if d.has(r[0]) and o != null and is_instance_valid(o) and o.has_method("from_save"):
			o.call("from_save", d[r[0]])

func _process(delta: float) -> void:
	if not enabled:
		return
	_t += delta
	if _t >= AUTOSAVE:
		_t = 0.0
		save_game()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			save_game()
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_WM_GO_BACK_REQUEST:
			save_game()
			get_tree().quit()

# ---------- кодирование значений для JSON ----------

static func enc(v: Variant) -> Variant:
	match typeof(v):
		TYPE_VECTOR2:
			return {"_t": "v2", "v": [v.x, v.y]}
		TYPE_VECTOR2I:
			return {"_t": "v2i", "v": [v.x, v.y]}
		TYPE_VECTOR3:
			var p: Vector3 = v
			if not p.is_finite():
				return {"_t": "v3inf"}
			return {"_t": "v3", "v": [p.x, p.y, p.z]}
		TYPE_COLOR:
			return {"_t": "c", "v": [v.r, v.g, v.b, v.a]}
		TYPE_BASIS:
			var b: Basis = v
			return {"_t": "b", "v": [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z]}
		TYPE_TRANSFORM3D:
			var t: Transform3D = v
			var bb: Dictionary = enc(t.basis)
			return {"_t": "t3", "b": bb["v"], "o": [t.origin.x, t.origin.y, t.origin.z]}
		TYPE_DICTIONARY:
			var out := {}
			for k: Variant in (v as Dictionary):
				out[str(k)] = enc(v[k])
			return out
		TYPE_ARRAY:
			var arr: Array = []
			for x: Variant in (v as Array):
				arr.append(enc(x))
			return arr
		TYPE_OBJECT:
			return null
	return v

static func dec(v: Variant) -> Variant:
	if v is Dictionary:
		var d: Dictionary = v
		if d.has("_t"):
			var a: Array = d.get("v", [])
			match String(d["_t"]):
				"v2":
					return Vector2(a[0], a[1])
				"v2i":
					return Vector2i(int(a[0]), int(a[1]))
				"v3":
					return Vector3(a[0], a[1], a[2])
				"v3inf":
					return Vector3.INF
				"c":
					return Color(a[0], a[1], a[2], a[3])
				"b":
					return Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8]))
				"t3":
					var b: Array = d["b"]
					var o: Array = d["o"]
					return Transform3D(Basis(Vector3(b[0], b[1], b[2]), Vector3(b[3], b[4], b[5]), Vector3(b[6], b[7], b[8])), Vector3(o[0], o[1], o[2]))
		var out := {}
		for k: Variant in d:
			out[k] = dec(d[k])
		return out
	if v is Array:
		var arr: Array = []
		for x: Variant in (v as Array):
			arr.append(dec(x))
		return arr
	return v

## Словарь {id: n} из JSON: значения — int.
static func int_dict(v: Variant) -> Dictionary:
	var out := {}
	if v is Dictionary:
		for k: Variant in (v as Dictionary):
			out[String(k)] = int(v[k])
	return out
