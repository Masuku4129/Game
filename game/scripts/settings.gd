extends Control
## --- core: настройки (main.settings) — качество, предел кадров, громкость. ---
## Кнопка-шестерёнка справа вверху открывает лист-пергамент; игра на паузе, пока он открыт.
## Хранятся в user://settings.cfg. Пресеты:
##   Энергосбережение — 3D в 60 % разрешения, 30 кадров, тени 1024 на 22 м, без свечения;
##   Баланс           — 75 %, 60 кадров, тени 2048 на 32 м, свечение;
##   Качество         — 90 %, 60 кадров, тени 4096 на 40 м, свечение.
## Предел кадров (30/60) — отдельно; на экране 120 Гц без предела телефон греется вдвое.

const CFG := "user://settings.cfg"
const UI = preload("res://scripts/ui_palette.gd")
const SHEET = preload("res://scripts/camp_ui.gd").Sheet
const INV = preload("res://scripts/inventory.gd")
const PRESETS := [
	{"name": "Энергосбережение", "scale": 0.6, "fps": 30, "shadow": 1024, "sh_dist": 22.0, "glow": false, "info": "Меньше нагрев и расход батареи"},
	{"name": "Баланс", "scale": 0.75, "fps": 60, "shadow": 2048, "sh_dist": 32.0, "glow": true, "info": "Плавно и в меру прохладно"},
	{"name": "Качество", "scale": 0.9, "fps": 60, "shadow": 4096, "sh_dist": 40.0, "glow": true, "info": "Чётче картинка, телефон греется"},
]

var main: Node3D
var preset := 0
var fps := 30
var volume := 0.8
var gear: Button
var sheet: Control
var _q_btns: Array = []
var _f_btns: Array = []
var _vol: HSlider
var _vol_lbl: Label
var _info: Label
var _was_paused := false
var _hero_btn: Button      # colony: режим героя (отладка)
var hero_mode := false     # colony: читается при запуске (main._colony_pick_mode)

class GearBtn extends Button:
	var kind := "gear"   # gear | book
	func _ready() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 4.0
		draw_circle(c + Vector2(3, 4), r, Color(0, 0, 0, 0.3))
		draw_circle(c, r, UI.PANEL_SOFT if not is_pressed() else UI.PANEL_HOVER)
		draw_arc(c, r - 3.0, 0.0, TAU, 40, UI.ACCENT, 3.0, true)
		var lc := Color(0.95, 0.88, 0.7)
		if kind == "gear":
			for k in 8:
				var a := TAU * k / 8.0
				draw_line(c + Vector2(cos(a), sin(a)) * r * 0.3, c + Vector2(cos(a), sin(a)) * r * 0.62, lc, r * 0.2)
			draw_circle(c, r * 0.42, lc)
			draw_circle(c, r * 0.18, UI.PANEL)
		else:
			# раскрытая книга
			var w := r * 0.62
			var h := r * 0.42
			draw_colored_polygon(PackedVector2Array([c + Vector2(-w, -h * 0.8), c + Vector2(0, -h * 0.55), c + Vector2(0, h), c + Vector2(-w, h * 0.75)]), lc)
			draw_colored_polygon(PackedVector2Array([c + Vector2(w, -h * 0.8), c + Vector2(0, -h * 0.55), c + Vector2(0, h), c + Vector2(w, h * 0.75)]), lc.darkened(0.08))
			for k in 3:
				var y := -h * 0.35 + k * h * 0.38
				draw_line(c + Vector2(-w * 0.8, y), c + Vector2(-w * 0.15, y + h * 0.12), UI.TEXT_MUTED, 2.0)
				draw_line(c + Vector2(w * 0.15, y + h * 0.12), c + Vector2(w * 0.8, y), Color(0.4, 0.28, 0.16), 2.0)
			draw_line(c + Vector2(0, -h * 0.55), c + Vector2(0, h), Color(0.3, 0.2, 0.1), 2.5)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load()
	gear = GearBtn.new()
	_corner(gear, -126.0)
	gear.pressed.connect(toggle)
	add_child(gear)
	_build_sheet()
	apply()

## Кнопка справа вверху под часами (x — отступ от правого края).
func _corner(b: Control, x: float) -> void:
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.offset_left = x
	b.offset_right = x + 104.0
	b.offset_top = 96.0
	b.offset_bottom = 200.0

func _load() -> void:
	var c := ConfigFile.new()
	if c.load(CFG) == OK:
		preset = clampi(int(c.get_value("video", "preset", 0)), 0, 2)
		fps = int(c.get_value("video", "fps", PRESETS[preset]["fps"]))
		volume = clampf(float(c.get_value("audio", "volume", 0.8)), 0.0, 1.0)
		hero_mode = bool(c.get_value("game", "hero_mode", false))  # colony
	else:
		fps = int(PRESETS[preset]["fps"])

func _store() -> void:
	var c := ConfigFile.new()
	c.set_value("video", "preset", preset)
	c.set_value("video", "fps", fps)
	c.set_value("audio", "volume", volume)
	c.set_value("game", "hero_mode", hero_mode)  # colony
	c.save(CFG)

## Применить всё к движку.
func apply() -> void:
	var p: Dictionary = PRESETS[preset]
	if OS.get_environment("PERF") == "":
		Engine.max_fps = fps
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	var vp := get_viewport()
	# FSR в Godot 4.3 есть только в Forward+; у мобильного рендера — билинейное масштабирование
	var method := String(ProjectSettings.get_setting("rendering/renderer/rendering_method", "mobile"))
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if method == "forward_plus" else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = float(p["scale"])
	vp.msaa_3d = Viewport.MSAA_DISABLED
	RenderingServer.directional_shadow_atlas_set_size(int(p["shadow"]), true)
	if main != null:
		if main.sun != null:
			main.sun.directional_shadow_max_distance = float(p["sh_dist"])
		if main.env != null:
			main.env.glow_enabled = bool(p["glow"])
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	_refresh()

# ---------- лист ----------

func _build_sheet() -> void:
	sheet = SHEET.new()
	sheet.title = "Настройки"
	sheet.anchor_left = 0.5
	sheet.anchor_right = 0.5
	sheet.anchor_top = 0.5
	sheet.anchor_bottom = 0.5
	sheet.offset_left = -470.0
	sheet.offset_right = 470.0
	sheet.offset_top = -330.0
	sheet.offset_bottom = 330.0
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	sheet.visible = false
	add_child(sheet)
	_label("Качество", Vector2(40, 110), 30)
	for i in 3:
		var b := _btn(String(PRESETS[i]["name"]), Rect2(40 + i * 290, 150, 275, 84), 26)
		b.pressed.connect(_set_preset.bind(i))
		_q_btns.append(b)
	_info = _label("", Vector2(40, 244), 22)
	_label("Предел кадров", Vector2(40, 300), 30)
	for i in 2:
		var b2 := _btn(["30 кадров", "60 кадров"][i], Rect2(40 + i * 290, 340, 275, 80), 26)
		b2.pressed.connect(_set_fps.bind([30, 60][i]))
		_f_btns.append(b2)
	_label("Громкость", Vector2(40, 450), 30)
	_vol = HSlider.new()
	_vol.min_value = 0
	_vol.max_value = 100
	_vol.step = 5
	_vol.position = Vector2(260, 450)
	_vol.size = Vector2(480, 50)
	_vol.focus_mode = Control.FOCUS_NONE
	var gr := StyleBoxFlat.new()
	gr.bg_color = Color(0.46, 0.31, 0.18)
	gr.content_margin_top = 8
	gr.content_margin_bottom = 8
	_vol.add_theme_stylebox_override("slider", gr)
	var ga := StyleBoxFlat.new()
	ga.bg_color = Color(0.72, 0.3, 0.12)
	_vol.add_theme_stylebox_override("grabber_area", ga)
	_vol.add_theme_stylebox_override("grabber_area_highlight", ga)
	_vol.value_changed.connect(_set_vol)
	sheet.add_child(_vol)
	_vol_lbl = _label("", Vector2(770, 450), 28)
	var sv := _btn("Сохранить игру", Rect2(40, 540, 420, 84), 28)
	sv.pressed.connect(_save_now)
	var cl := _btn("Закрыть", Rect2(480, 540, 420, 84), 28)
	cl.pressed.connect(close)
	# --- colony: отладочный переключатель старого режима героя (джойстик, от первого лица) ---
	_hero_btn = _btn(_hero_text(), Rect2(40, 636, 860, 76), 24)
	_hero_btn.pressed.connect(_toggle_hero_mode)
	sheet.offset_top = -380.0
	sheet.offset_bottom = 380.0

func _label(t: String, p: Vector2, fs: int) -> Label:
	var l := Label.new()
	l.text = t
	l.position = p
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", Color(0.24, 0.15, 0.08))
	sheet.add_child(l)
	return l

func _btn(t: String, r: Rect2, fs: int) -> Button:
	var b := Button.new()
	b.text = t
	b.position = r.position
	b.size = r.size
	b.focus_mode = Control.FOCUS_NONE
	INV.style_button(b, fs)
	sheet.add_child(b)
	return b

func _refresh() -> void:
	if sheet == null:
		return
	for i in _q_btns.size():
		(_q_btns[i] as Button).modulate = Color(1, 1, 1) if i == preset else Color(1, 1, 1, 0.55)
	for i in _f_btns.size():
		(_f_btns[i] as Button).modulate = Color(1, 1, 1) if [30, 60][i] == fps else Color(1, 1, 1, 0.55)
	_info.text = "%s · 3D %d%% разрешения · тени %d" % [PRESETS[preset]["info"], int(float(PRESETS[preset]["scale"]) * 100.0), int(PRESETS[preset]["shadow"])]
	_vol.set_value_no_signal(round(volume * 100.0))
	_vol_lbl.text = "%d%%" % int(round(volume * 100.0))

func _set_preset(i: int) -> void:
	preset = i
	fps = int(PRESETS[i]["fps"])
	_store()
	apply()

func _set_fps(v: int) -> void:
	fps = v
	_store()
	apply()

func _set_vol(v: float) -> void:
	volume = v / 100.0
	_store()
	apply()

# --- colony: старый режим героя — для отладки; меняется при следующем запуске ---
func _hero_text() -> String:
	return "Режим героя (отладка): %s · нужен перезапуск" % ("да" if hero_mode else "нет")

func _toggle_hero_mode() -> void:
	hero_mode = not hero_mode
	_store()
	if _hero_btn != null:
		_hero_btn.text = _hero_text()
	if main != null:
		main._say("Режим героя включён — перезапустите игру" if hero_mode else "Режим острога — перезапустите игру")
# --- /colony ---

func _save_now() -> void:
	if main != null and main.saver != null:
		main.saver.enabled = true
		var ok: bool = main.saver.save_game()
		main._say("Игра сохранена" if ok else "Сейчас не сохранить")

func is_open() -> bool:
	return sheet.visible

func toggle() -> void:
	if sheet.visible:
		close()
	else:
		open()

func open() -> void:
	_refresh()
	sheet.visible = true
	_was_paused = get_tree().paused
	get_tree().paused = true

func close() -> void:
	sheet.visible = false
	get_tree().paused = _was_paused

func _process(_d: float) -> void:
	if main == null or main.hero == null:
		return
	var inv_open: bool = main.inventory != null and (main.inventory.is_open() or main.hero.pack_stage != "")
	# colony: в режиме острога шестерёнка всегда на месте
	gear.visible = main.colony != null or (not inv_open and main.hero.state != "dead")
