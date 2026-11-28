extends Control
## --- core: меню при запуске: «Продолжить» (если есть сохранение) и «Новая игра». ---
## Пока меню открыто, игра на паузе; после выбора включается автосохранение.

const UI = preload("res://scripts/ui_palette.gd")
const SHEET = preload("res://scripts/camp_ui.gd").Sheet
const INV = preload("res://scripts/inventory.gd")
const SV = preload("res://scripts/save.gd")

var main: Node3D
var _confirm := false
var _new_btn: Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.04, 0.03, 0.55)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var sh := SHEET.new()
	sh.title = "Тайга"
	sh.info = "землепроходец"
	sh.anchor_left = 0.5
	sh.anchor_right = 0.5
	sh.anchor_top = 0.5
	sh.anchor_bottom = 0.5
	sh.offset_left = -360.0
	sh.offset_right = 360.0
	sh.offset_top = -270.0
	sh.offset_bottom = 270.0
	add_child(sh)
	var y := 120.0
	var creative_active := main != null and bool(main.creative_mode)
	var active_save := FileAccess.file_exists("user://creative_save.json") if creative_active else SV.has_save()
	if active_save:
		var c := _btn(sh, "Продолжить творческую игру" if creative_active else "Продолжить", y)
		c.pressed.connect(_continue)
		y += 130.0
		var l := Label.new()
		l.text = _save_info()
		l.position = Vector2(60, y - 30)
		l.add_theme_font_size_override("font_size", 22)
		l.add_theme_color_override("font_color", UI.TEXT_MUTED)
		sh.add_child(l)
		y += 30.0
	_new_btn = _btn(sh, "Новая игра", y)
	_new_btn.pressed.connect(_new)
	get_tree().paused = true

func _btn(sh: Control, t: String, y: float) -> Button:
	var b := Button.new()
	b.text = t
	b.position = Vector2(60, y)
	b.size = Vector2(600, 110)
	b.focus_mode = Control.FOCUS_NONE
	INV.style_button(b, 40)
	sh.add_child(b)
	return b

func _save_info() -> String:
	var path := "user://creative_save.json" if main != null and bool(main.creative_mode) else SV.PATH
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary) or not (d as Dictionary).has("main"):
		return ""
	var m: Dictionary = d["main"]
	var t := Time.get_datetime_string_from_unix_time(int(d.get("time", 0)), true)
	return "День %d, %02d:00 · сохранено %s" % [int(m.get("day", 1)), int(m.get("t_hours", 0)), t.substr(0, 16)]

func _continue() -> void:
	get_tree().paused = false
	main.saver.load_game()
	main.saver.enabled = true
	main._say("Игра загружена")
	queue_free()

func _new() -> void:
	# Подтверждение проверяет именно активный слот: обычная и творческая
	# кампании независимы и не должны случайно перезаписывать друг друга.
	var active_save_path := "user://creative_save.json" if main != null and bool(main.creative_mode) else SV.PATH
	if FileAccess.file_exists(active_save_path) and not _confirm:
		_confirm = true
		_new_btn.text = "Точно? Сохранение этого режима сотрётся"
		return
	SV.delete_slot(main != null and bool(main.creative_mode))
	# Новая игра должна получить другой seed ещё до генерации рельефа и растительности.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var previous_seed := int(main.map_seed) if main != null else 0
	var seed_value := rng.randi_range(1, 2147483646)
	# Даже при повторном нажатии «Новая игра» ядро мира гарантированно меняется.
	while seed_value == previous_seed:
		seed_value = rng.randi_range(1, 2147483646)
	var seed_file := FileAccess.open("user://pending_world_seed.txt", FileAccess.WRITE)
	if seed_file != null:
		seed_file.store_string(str(seed_value))
		seed_file.close()
	# Явно передаём сцене признак запуска новой игры. Без него _core_setup()
	# после reload_current_scene() снова открывал стартовое меню и ставил игру на паузу.
	var start_file := FileAccess.open("user://pending_new_game.flag", FileAccess.WRITE)
	if start_file != null:
		start_file.store_string("1")
		start_file.close()
	get_tree().paused = false
	get_tree().reload_current_scene()
