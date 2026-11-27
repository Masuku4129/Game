extends Control
## --- core: «Справочник» — книжка (кнопка с книгой справа вверху). Лист-пергамент, вкладки:
## Ресурсы (где взять, чем, зачем), Ремесло (рецепт и место), Постройки (цена и польза),
## Звери (опасность, добыча), Как… (валка, разделка, изба, готовка, тепло).
## Картинки — значки, отрисованные из игровых моделей (res://icons, icons.gd).
## Пока справочник открыт — пауза.

const UI = preload("res://scripts/ui_palette.gd")
const SHEET = preload("res://scripts/camp_ui.gd").Sheet
const INV = preload("res://scripts/inventory.gd")
const IT = preload("res://scripts/items.gd")
const GD = preload("res://scripts/guide_data.gd")
const ICONS = preload("res://scripts/icons.gd")
const ST = preload("res://scripts/structures.gd")
const CAB = preload("res://scripts/cabin.gd")
const GEAR = preload("res://scripts/settings.gd").GearBtn
const INK := UI.TEXT
const TABS := ["Ресурсы", "Ремесло", "Постройки", "Звери", "Как…"]

var main: Node3D
var book: Button
var sheet: Control
var tab := 0
var sel := ""
var list_box := VBoxContainer.new()
var scroll := ScrollContainer.new()
var pic := TextureRect.new()
var title_l := Label.new()
var sub_l := Label.new()
var body := RichTextLabel.new()
var _tab_btns: Array = []
var _was_paused := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	book = GEAR.new()
	book.kind = "book"
	book.anchor_left = 1.0
	book.anchor_right = 1.0
	book.offset_left = -246.0
	book.offset_right = -142.0
	book.offset_top = 96.0
	book.offset_bottom = 200.0
	book.pressed.connect(toggle)
	add_child(book)
	sheet = SHEET.new()
	sheet.title = "Справочник"
	sheet.anchor_right = 1.0
	sheet.anchor_bottom = 1.0
	sheet.offset_left = 50.0
	sheet.offset_right = -50.0
	sheet.offset_top = 24.0
	sheet.offset_bottom = -20.0
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	sheet.visible = false
	add_child(sheet)
	for i in TABS.size():
		var b := _btn(TABS[i], Rect2(470 + i * 205, 18, 195, 62), 26)
		b.pressed.connect(_set_tab.bind(i))
		_tab_btns.append(b)
	var cl := _btn("Закрыть", Rect2(1520, 18, 270, 62), 26)
	cl.anchor_left = 0.0
	cl.pressed.connect(close)
	scroll.position = Vector2(28, 100)
	scroll.size = Vector2(520, 690)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sheet.add_child(scroll)
	list_box.custom_minimum_size = Vector2(500, 0)
	list_box.add_theme_constant_override("separation", 6)
	scroll.add_child(list_box)
	pic.position = Vector2(580, 110)
	pic.size = Vector2(300, 300)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sheet.add_child(pic)
	title_l.position = Vector2(900, 110)
	title_l.add_theme_font_size_override("font_size", 44)
	title_l.add_theme_color_override("font_color", INK)
	sheet.add_child(title_l)
	sub_l.position = Vector2(902, 170)
	sub_l.size = Vector2(880, 40)
	sub_l.add_theme_font_size_override("font_size", 24)
	sub_l.add_theme_color_override("font_color", UI.TEXT_MUTED)
	sheet.add_child(sub_l)
	body.position = Vector2(900, 220)
	body.size = Vector2(900, 570)
	body.bbcode_enabled = true
	body.scroll_active = true
	body.add_theme_font_size_override("normal_font_size", 25)
	body.add_theme_font_size_override("bold_font_size", 26)
	body.add_theme_color_override("default_color", INK)
	sheet.add_child(body)

func _btn(t: String, r: Rect2, fs: int) -> Button:
	var b := Button.new()
	b.text = t
	b.position = r.position
	b.size = r.size
	b.focus_mode = Control.FOCUS_NONE
	INV.style_button(b, fs)
	sheet.add_child(b)
	return b

## Строка списка: значок и имя, в стиле ячейки короба.
func _row(id: String, icon_id: String, name_s: String) -> Button:
	var b := Button.new()
	b.text = "  " + name_s
	b.icon = ICONS.tex(icon_id)
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", 64)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(500, 78)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 27)
	for k: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(k, INK)
	var cs := {"normal": Color(0.8, 0.7, 0.5, 0.6), "hover": Color(0.84, 0.74, 0.54, 0.8), "pressed": Color(0.7, 0.58, 0.38, 0.9)}
	for k: String in cs:
		var sb := StyleBoxFlat.new()
		sb.bg_color = cs[k]
		sb.set_corner_radius_all(8)
		sb.set_border_width_all(2 if id != sel else 4)
		sb.border_color = Color(0.45, 0.33, 0.2, 0.8) if id != sel else Color(0.72, 0.3, 0.12)
		sb.content_margin_left = 10
		b.add_theme_stylebox_override(k, sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(_select.bind(id))
	return b

# ---------- открытие ----------

func toggle() -> void:
	if sheet.visible:
		close()
	else:
		open()

func open() -> void:
	sheet.visible = true
	_was_paused = get_tree().paused
	get_tree().paused = true
	_set_tab(tab)

func close() -> void:
	sheet.visible = false
	get_tree().paused = _was_paused

func is_open() -> bool:
	return sheet.visible

func _process(_d: float) -> void:
	if main == null or main.hero == null:
		return
	var inv_open: bool = main.inventory != null and (main.inventory.is_open() or main.hero.pack_stage != "")
	book.visible = not inv_open and main.hero.state != "dead"

# ---------- данные вкладок ----------

## Список вкладки: [[id, имя], ...].
func entries(t: int) -> Array:
	var out: Array = []
	match t:
		0:
			for id: String in IT.DEF:
				if not IT.DEF[id].has("craft") or GD.SRC.has(id):
					out.append([id, IT.name_of(id)])
		1:
			for id: String in INV.EXTRA:
				out.append(["x_" + id, "Расколоть камни" if id == "flint" else "Разделать тушку"])
			for id: String in IT.DEF:
				if IT.DEF[id].has("craft"):
					out.append([id, IT.name_of(id)])
			for r: Array in CAB.BENCH:
				out.append(["w_" + String(r[0]), "Верстак: " + IT.name_of(String(r[0])).to_lower()])
		2:
			for k: String in ST.ORDER:
				out.append(["b_" + k, String(ST.DEFS[k]["name"])])
			for k: String in CAB.FURN_ORDER:
				out.append(["f_" + k, String(CAB.FURN[k]["name"]) + " (в избе)"])
		3:
			for k: String in GD.ANIMALS:
				out.append(["a_" + k, String(GD.ANIMALS[k][0])])
		4:
			for k: String in GD.HOWTO:
				out.append([k, String(GD.HOWTO[k][0])])
	return out

func _set_tab(t: int) -> void:
	tab = t
	for i in _tab_btns.size():
		(_tab_btns[i] as Button).modulate = Color(1, 1, 1) if i == t else Color(1, 1, 1, 0.6)
	var es := entries(t)
	sel = String(es[0][0]) if not es.is_empty() else ""
	_fill()
	_show(sel)

func _fill() -> void:
	for c in list_box.get_children():
		c.queue_free()
	for e: Array in entries(tab):
		list_box.add_child(_row(String(e[0]), _icon_id(String(e[0])), String(e[1])))

func _select(id: String) -> void:
	sel = id
	_fill()
	_show(id)
	# прокрутить список к выбранному
	var es := entries(tab)
	for i in es.size():
		if String(es[i][0]) == id:
			scroll.set_deferred("scroll_vertical", maxi(0, i * 84 - 250))

## Значок записи: у рецептов «x_»/«w_» — значок вещи.
func _icon_id(id: String) -> String:
	if id.begins_with("x_") or id.begins_with("w_"):
		return id.substr(2)
	return id

func _show(id: String) -> void:
	pic.texture = ICONS.tex(_icon_id(id))
	body.text = page(id)
	body.scroll_to_line(0)
	title_l.text = ""
	sub_l.text = ""
	for e: Array in entries(tab):
		if String(e[0]) == id:
			title_l.text = String(e[1])

# ---------- текст страницы ----------

func _h(t: String) -> String:
	return "[color=#7a3a14][b]%s[/b][/color]\n" % t

func _cost(c: Dictionary) -> String:
	var parts := PackedStringArray()
	for k: String in c:
		parts.append("%s ×%d" % [IT.name_of(k).to_lower(), int(c[k])])
	return ", ".join(parts)

## Где вещь идёт в дело: рецепты и постройки, где она нужна.
func _used_in(id: String) -> String:
	var parts := PackedStringArray()
	for k: String in IT.DEF:
		var d: Dictionary = IT.DEF[k]
		if (d.get("craft", {}) as Dictionary).has(id) or (d.get("need", []) as Array).has(id):
			parts.append(IT.name_of(k).to_lower())
	for k2: String in ST.DEFS:
		var sd: Dictionary = ST.DEFS[k2]
		if (sd.get("cost", {}) as Dictionary).has(id) or (sd.get("need", {}) as Dictionary).has(id):
			parts.append(String(sd["name"]).to_lower())
	for k3: String in CAB.FURN:
		if (CAB.FURN[k3]["cost"] as Dictionary).has(id):
			parts.append(String(CAB.FURN[k3]["name"]).to_lower())
	for r: Array in CAB.BENCH:
		if (r[2] as Dictionary).has(id):
			parts.append(IT.name_of(String(r[0])).to_lower() + " (верстак)")
	return ", ".join(parts)

func page(id: String) -> String:
	var t := ""
	if id.begins_with("b_"):
		var k := id.substr(2)
		var d: Dictionary = ST.DEFS[k]
		sub_l.text = "Постройка · кнопка «Стройка»"
		t += _h("Польза") + String(d["desc"]) + "\n\n"
		if k == "cabin":
			t += _h("Внести на стройку") + _cost(d["need"]) + "\n\n"
		else:
			t += _h("Цена") + _cost(d["cost"]) + "\n\n"
		if d.has("cap"):
			t += _h("Хранилище") + "%d кг\n\n" % int(d["cap"])
		if d.has("warm"):
			t += _h("Тепло и ветер") + "тепло +%d %%, ветер ×%.2f\n\n" % [int(float(d["warm"]) * 100.0), float(d["wind"])]
		if d.has("decay"):
			t += _h("Прочность") + "ветшает со временем (в дождь быстрее); чинится лапником.\n\n"
		t += _h("Где ставить") + "Где угодно на ровном сухом месте, не дальше 30 м от себя: без деревьев, камней, валежин и других построек."
		return t
	if id.begins_with("f_"):
		var k2 := id.substr(2)
		var fd: Dictionary = CAB.FURN[k2]
		sub_l.text = "Обстановка избы · внутри «Обстановка»"
		return _h("Польза") + String(fd["desc"]) + "\n\n" + _h("Цена") + _cost(fd["cost"])
	if id.begins_with("a_"):
		var a: Array = GD.ANIMALS[id.substr(2)]
		sub_l.text = "Зверь"
		return _h("Опасность") + String(a[1]) + "\n\n" + _h("Добыча") + String(a[2]) + "\n\n" + _h("Повадки") + String(a[3])
	if id.begins_with("h_"):
		sub_l.text = "Как…"
		return String(GD.HOWTO[id][1])
	if id.begins_with("x_"):
		var e := id.substr(2)
		sub_l.text = "Ремесло · руками"
		return _h("Рецепт") + _cost(INV.EXTRA[e]) + "\n\n" + _h("Выход") + "%s ×%d" % [IT.name_of(e).to_lower(), int(INV.EXTRA_OUT.get(e, 1))] + ("\n\n" + _h("Нужно") + "нож" if INV.EXTRA_TOOL.has(e) else "")
	if id.begins_with("w_"):
		for r: Array in CAB.BENCH:
			if "w_" + String(r[0]) == id:
				sub_l.text = "Верстак в избе"
				return _h("Рецепт") + _cost(r[2]) + "\n\n" + _h("Выход") + "%s ×%d" % [IT.name_of(String(r[0])).to_lower(), int(r[1])]
		return ""
	# вещь
	var d2: Dictionary = IT.DEF.get(id, {})
	sub_l.text = "%.2f кг" % float(d2.get("w", 0.3)) + (" · инструмент" if d2.has("tool") else "") + (" · только в руках" if d2.get("hands", false) else "") + (" · на пояс" if d2.get("belt", false) else "")
	t += String(d2.get("desc", "")) + "\n\n"
	if GD.SRC.has(id):
		t += _h("Где взять") + String(GD.SRC[id][0]) + "\n\n"
		if String(GD.SRC[id][1]) != "":
			t += _h("Чем") + String(GD.SRC[id][1]) + "\n\n"
	if d2.has("craft"):
		t += _h("Рецепт") + _cost(d2["craft"]) + ("  →  ×%d" % int(d2["out"]) if d2.has("out") else "") + "\n"
		if d2.has("need"):
			var ns := PackedStringArray()
			for n: String in d2["need"]:
				ns.append(IT.name_of(n).to_lower())
			t += "Нужно иметь (не тратится): " + ", ".join(ns) + "\n"
		t += "Где: " + String(GD.STATION.get(String(d2.get("station", "")), "")) + "\n\n"
	if d2.has("eat"):
		var e2: Array = d2["eat"]
		t += _h("Еда") + "сытость %+d %%, жажда %+d %%, здоровье %+d %%" % [int(float(e2[0]) * 100.0), int(float(e2[1]) * 100.0), int(float(e2[2]) * 100.0)] + (", тепло +%d %%" % int(float(d2["warm"]) * 100.0) if d2.has("warm") else "") + "\n\n"
	var use := String(GD.USE.get(id, ""))
	var ui := _used_in(id)
	if use != "" or ui != "":
		t += _h("Зачем") + use + ("\n" if use != "" and ui != "" else "") + ("Идёт на: " + ui if ui != "" else "")
	return t
