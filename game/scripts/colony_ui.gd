extends Control
## --- colony: лист острога (интерфейс под палец). ---
## Чисто и по делу: сверху слева задача, сверху справа день, сезон и погода,
## посередине полоса припасов. Внизу слева — трое: личины с именем, делом и
## полосками (здоровье, сытость, тепло, силы); тап по личине выбирает человека.
## Внизу справа — восемь кнопок: Приказ, Стройка, Работы, Зона, Метить, Рамка,
## Стоять, Сам. Старого снаряжения, пояса, прицела и кнопки руки тут нет.
##   «Работы» — таблица людей и родов работ с важностью 1–4 (как в RimWorld).
##   «Зона» — кисть разрешённой области и кому в ней сидеть.
##   «Метить» — помечать деревья в рубку, кусты в сбор, зверя в охоту.
##   «Рамка» — выбрать несколько человек протяжкой.

const INV = preload("res://scripts/inventory.gd")
const PLAN = preload("res://scripts/planner.gd")
const SHEET = preload("res://scripts/camp_ui.gd").Sheet
const INK := Color(0.24, 0.15, 0.08)
const PAPER := Color(0.88, 0.8, 0.62)
const BAR_COLS := [Color(0.7, 0.22, 0.18), Color(0.74, 0.6, 0.27), Color(0.8, 0.45, 0.25), Color(0.45, 0.62, 0.36)]

var colony
var main: Node3D
var portraits: Array = []
var build_btn: Button
var craft_btn: Button
var craft_sheet: Control
var craft_rows: Array = []
var auto_btn: Button
var stop_btn: Button
var order_btn: Button
var plan_btn: Button
var zone_btn: Button
var desig_btn: Button
var box_btn: Button
var main_btns: Array = []
var plan_sheet: Control
var zone_bar: Control
var cards: Array = []
var build_sheet: Control
var build_rows: Array = []
var rot_l: Button
var rot_r: Button
var place_btn: Button
var cancel_btn: Button
var radial: Control
var end_sheet: Control
var order_mark := Vector3.INF
var order_t := 0.0
var _t := 0.0

## Личина землепроходца: круг с цветом куртки, имя, дело и полоски нужд.
class Portrait extends Button:
	var unit
	var ui
	func _ready() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
	func _draw() -> void:
		if unit == null:
			return
		var f := ThemeDB.fallback_font
		var sel: bool = unit.selected
		var dead: bool = unit.state == "dead"
		draw_rect(Rect2(Vector2(4, 6), size - Vector2(4, 8)), Color(0, 0, 0, 0.28))
		draw_rect(Rect2(Vector2.ZERO, size - Vector2(6, 12)), Color(0.86, 0.78, 0.6, 0.93) if not dead else Color(0.6, 0.56, 0.5, 0.8))
		draw_rect(Rect2(Vector2.ZERO, size - Vector2(6, 12)), Color(0.95, 0.72, 0.3) if sel else Color(0.42, 0.3, 0.18), false, 5.0 if sel else 3.0)
		var c := Vector2(44, 44)
		var jk: Color = unit.pal.get("jacket", Color(0.5, 0.41, 0.31))
		draw_circle(c, 30.0, jk)
		draw_circle(c - Vector2(0, 6), 17.0, Color(0.92, 0.78, 0.66))
		var hair: Color = unit.pal.get("hair", Color(0.4, 0.3, 0.2))
		draw_circle(c - Vector2(0, 14), 15.0, hair)
		draw_rect(Rect2(c + Vector2(-16, -2), Vector2(32, 10)), hair.darkened(0.1))
		if dead:
			draw_line(c + Vector2(-24, -24), c + Vector2(24, 24), Color(0.5, 0.1, 0.08), 5.0)
		draw_string(f, Vector2(84, 32), String(unit.unit_name), HORIZONTAL_ALIGNMENT_LEFT, 170, 26, INK)
		draw_string(f, Vector2(84, 58), unit.status(), HORIZONTAL_ALIGNMENT_LEFT, 180, 19, Color(0.36, 0.26, 0.16))
		var vals: Array = [unit.health, unit.hunger, unit.warmth, 1.0 - clampf(unit.fatigue, 0.0, 1.0)]
		for i in 4:
			var y := 72.0 + float(i) * 11.0
			draw_rect(Rect2(Vector2(84, y), Vector2(170, 8)), Color(0.42, 0.32, 0.2, 0.5))
			draw_rect(Rect2(Vector2(84, y), Vector2(170.0 * clampf(float(vals[i]), 0.0, 1.0), 8)), BAR_COLS[i])
	func _pressed_now() -> void:
		ui.pick_unit(unit)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var i := 0
	for u in colony.units:
		var p := Portrait.new()
		p.unit = u
		p.ui = self
		p.anchor_top = 1.0
		p.anchor_bottom = 1.0
		p.offset_left = 24.0 + float(i) * 280.0
		p.offset_right = p.offset_left + 270.0
		p.offset_top = -140.0
		p.offset_bottom = -16.0
		p.pressed.connect(p._pressed_now)
		add_child(p)
		portraits.append(p)
		i += 1
	# кнопки: два столбца по четыре (под большой палец)
	build_btn = _grid("Стройка", 0, 0)
	build_btn.pressed.connect(_open_build)
	plan_btn = _grid("Работы", 1, 0)
	plan_btn.pressed.connect(_open_plan)
	zone_btn = _grid("Зона", 0, 1)
	zone_btn.pressed.connect(_open_zone)
	desig_btn = _grid("Метить", 1, 1)
	desig_btn.pressed.connect(_toggle_desig)
	craft_btn = _grid("Заказы", 0, 2)
	craft_btn.pressed.connect(_open_craft)
	auto_btn = _grid("Сам: да", 1, 2)
	auto_btn.pressed.connect(_toggle_auto)
	main_btns = [build_btn, plan_btn, zone_btn, desig_btn, craft_btn, auto_btn]
	rot_l = _btn("⟲", -620.0, -150.0, 130.0, 100.0)
	rot_r = _btn("⟳", -470.0, -150.0, 130.0, 100.0)
	place_btn = _btn("Ставить", -300.0, -150.0, 270.0, 100.0)
	cancel_btn = _btn("Отмена", -300.0, -266.0, 270.0, 96.0)
	rot_l.pressed.connect(func() -> void: colony.build_rotate(-PI / 8.0))
	rot_r.pressed.connect(func() -> void: colony.build_rotate(PI / 8.0))
	place_btn.pressed.connect(_place)
	cancel_btn.pressed.connect(_close_build)
	for b: Button in [rot_l, rot_r, place_btn, cancel_btn]:
		b.visible = false

## Кнопка в сетке у правого нижнего угла: col 0 — левее, row 0 — ниже.
func _grid(t: String, col: int, row: int) -> Button:
	var w := 248.0
	var h := 92.0
	var l := -24.0 - w - float(1 - col) * (w + 10.0)
	var top := -16.0 - h - float(row) * (h + 10.0)
	return _btn(t, l, top, w, h)

func _btn(t: String, l: float, top: float, w: float, h: float) -> Button:
	var b := Button.new()
	b.text = t
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.anchor_top = 1.0
	b.anchor_bottom = 1.0
	b.offset_left = l
	b.offset_right = l + w
	b.offset_top = top
	b.offset_bottom = top + h
	b.focus_mode = Control.FOCUS_NONE
	INV.style_button(b, 32)
	add_child(b)
	return b

func pick_unit(u) -> void:
	colony.select(u)
	if colony.rig != null:
		colony.rig.look_at_point(u.position)

func refresh_units() -> void:
	for p: Portrait in portraits:
		p.queue_redraw()

func mark_order(p: Variant) -> void:
	order_mark = p
	order_t = 1.1

# ---------- стройка ----------

func _show_main(on: bool) -> void:
	for b: Button in main_btns:
		b.visible = on

func _open_build() -> void:
	_close_tools()
	_show_main(false)
	_free_build_sheet()
	var sh: Control = SHEET.new()
	sh.set("title", "Стройка")
	sh.set("info", "")
	sh.anchor_left = 0.0
	sh.anchor_right = 0.0
	sh.anchor_top = 0.0
	sh.anchor_bottom = 1.0
	sh.offset_left = 24.0
	sh.offset_right = 824.0
	sh.offset_top = 150.0
	sh.offset_bottom = -170.0
	sh.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(sh)
	build_sheet = sh
	var sc := ScrollContainer.new()
	sc.anchor_right = 1.0
	sc.anchor_bottom = 1.0
	sc.offset_left = 24.0
	sc.offset_top = 100.0
	sc.offset_right = -24.0
	sc.offset_bottom = -24.0
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	sc.scroll_deadzone = 12
	sh.add_child(sc)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.custom_minimum_size = Vector2(720, 0)
	vb.add_theme_constant_override("separation", 12)
	sc.add_child(vb)
	build_rows = []
	var entries: Array = []
	for type: String in main.camp.ORDER_COLONY:
		var vl: Array = main.camp.VARIANTS.get(type, [])
		if vl.is_empty():
			entries.append([type, 0])
		else:
			for vi in vl.size():
				entries.append([type, vi])
	for en: Array in entries:
		var type: String = en[0]
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 150)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		INV.style_button(b, 26)
		b.pressed.connect(_pick_type.bind(type, int(en[1])))
		vb.add_child(b)
		build_rows.append([type, b, int(en[1])])
	_refresh_build_rows()
	var x := _btn("Закрыть", 0.0, 0.0, 200.0, 70.0)
	remove_child(x)
	x.anchor_left = 1.0
	x.anchor_right = 1.0
	x.anchor_top = 0.0
	x.anchor_bottom = 0.0
	x.offset_left = -214.0
	x.offset_right = -22.0
	x.offset_top = 14.0
	x.offset_bottom = 78.0
	INV.style_button(x, 26)
	x.pressed.connect(_close_build)
	sh.add_child(x)

func _refresh_build_rows() -> void:
	for r: Array in build_rows:
		var d: Dictionary = main.camp.DEFS[String(r[0])]
		var vl: Array = main.camp.VARIANTS.get(String(r[0]), [])
		var ttl := String(d["name"])
		var dd: Dictionary = d
		if not vl.is_empty():
			var v: Dictionary = vl[int(r[2])]
			ttl += " — " + String(v["name"])
			dd = {"need": v["need"]}
		(r[1] as Button).text = "%s\n%s\n%s" % [ttl, String(d.get("desc", "")), _cost_text(dd)]

func _free_build_sheet() -> void:
	if build_sheet != null:
		build_sheet.queue_free()
		build_sheet = null
	build_rows = []

func _cost_text(d: Dictionary) -> String:
	var parts: Array = []
	var src: Dictionary = d.get("need", {})
	if src.is_empty():
		src = d.get("cost", {})
	for k: String in src:
		var have: int = colony.count(k)
		parts.append("%s %d/%d%s" % [preload("res://scripts/items.gd").name_of(k).to_lower(), have, int(src[k]), " ✓" if have >= int(src[k]) else ""])
	if parts.is_empty():
		return "даром"
	return " · ".join(PackedStringArray(parts))

func _pick_type(type: String, vi: int = 0) -> void:
	colony.build_begin(type, vi)
	_free_build_sheet()
	for b: Button in [rot_l, rot_r, place_btn, cancel_btn]:
		b.visible = true

func _place() -> void:
	if colony.build_confirm():
		_close_build()

func _close_build() -> void:
	colony.build_cancel()
	_free_build_sheet()
	for b: Button in [rot_l, rot_r, place_btn, cancel_btn]:
		b.visible = false
	_show_main(true)

func _toggle_auto() -> void:
	colony.auto_work = not colony.auto_work
	auto_btn.text = "Сам: да" if colony.auto_work else "Сам: нет"

func _stop_unit() -> void:
	if colony.sel != null:
		colony.jobs.cancel(colony.sel)
		colony.sel.stop()

# ---------- лист работ ----------

func _open_plan() -> void:
	_close_tools()
	if plan_sheet != null:
		_close_plan()
		return
	var sh: Control = SHEET.new()
	sh.set("title", "Работы")
	sh.set("info", "важность 1–4 · тап по клетке")
	sh.anchor_left = 0.5
	sh.anchor_right = 0.5
	sh.anchor_top = 0.5
	sh.anchor_bottom = 0.5
	sh.offset_left = -620.0
	sh.offset_right = 620.0
	sh.offset_top = -250.0
	sh.offset_bottom = 250.0
	sh.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(sh)
	plan_sheet = sh
	var x0 := 270.0
	var i := 0
	for c: Dictionary in PLAN.COLS:
		var l := Label.new()
		l.text = String(c["name"])
		l.position = Vector2(x0 + float(i) * 98.0, 96.0)
		l.size = Vector2(100, 30)
		l.add_theme_font_size_override("font_size", 21)
		l.add_theme_color_override("font_color", INK)
		sh.add_child(l)
		i += 1
	var y := 136.0
	for uu in colony.units:
		var nm := Label.new()
		nm.text = String(uu.unit_name)
		nm.position = Vector2(50, y + 14.0)
		nm.size = Vector2(230, 36)
		nm.add_theme_font_size_override("font_size", 27)
		nm.add_theme_color_override("font_color", INK)
		sh.add_child(nm)
		var k := 0
		for c2: Dictionary in PLAN.COLS:
			var col := String(c2["id"])
			var b := Button.new()
			b.position = Vector2(x0 + float(k) * 98.0, y)
			b.size = Vector2(90, 64)
			b.focus_mode = Control.FOCUS_NONE
			INV.style_button(b, 30)
			b.text = _pri_text(uu, col)
			b.pressed.connect(func() -> void:
				colony.planner.cycle(uu, col)
				b.text = _pri_text(uu, col)
				colony.jobs.cancel(uu))
			sh.add_child(b)
			k += 1
		y += 76.0
	var cb := Button.new()
	cb.text = "Закрыть"
	cb.position = Vector2(x0 + 520.0, 384.0)
	cb.size = Vector2(300, 84)
	cb.focus_mode = Control.FOCUS_NONE
	INV.style_button(cb, 32)
	cb.pressed.connect(_close_plan)
	sh.add_child(cb)
	var hint := Label.new()
	hint.text = "Помеченное («Метить») разбирают по этому листу: 1 — первым делом."
	hint.position = Vector2(50, 392.0)
	hint.size = Vector2(760, 40)
	hint.add_theme_font_size_override("font_size", 22)
	hint.add_theme_color_override("font_color", Color(0.36, 0.26, 0.16))
	sh.add_child(hint)

func _pri_text(u, col: String) -> String:
	var v: int = colony.planner.pri_of(u, col)
	return "—" if v <= 0 else str(v)

func _close_plan() -> void:
	if plan_sheet != null:
		plan_sheet.queue_free()
		plan_sheet = null

# ---------- разрешённая область ----------

func _open_zone() -> void:
	var was: bool = zone_bar != null
	_close_tools()
	if was:
		return
	var bar := Control.new()
	bar.offset_left = 24.0
	bar.offset_top = 150.0
	bar.offset_right = 24.0 + 1010.0
	bar.offset_bottom = 150.0 + 196.0
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	var bg := ColorRect.new()
	bg.color = Color(0.88, 0.8, 0.62, 0.93)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(bg)
	add_child(bar)
	zone_bar = bar
	var ttl := Label.new()
	ttl.text = "Разрешённая область: красьте пальцем по земле"
	ttl.position = Vector2(16, 8)
	ttl.size = Vector2(900, 32)
	ttl.add_theme_font_size_override("font_size", 24)
	ttl.add_theme_color_override("font_color", INK)
	bar.add_child(ttl)
	var names := [["Красить", "paint"], ["Стирать", "erase"], ["Очистить", "clear"], ["Готово", "done"]]
	var x := 16.0
	for e: Array in names:
		var b := Button.new()
		b.text = String(e[0])
		b.position = Vector2(x, 44)
		b.size = Vector2(230, 70)
		b.focus_mode = Control.FOCUS_NONE
		INV.style_button(b, 28)
		var act := String(e[1])
		b.pressed.connect(func() -> void: _zone_act(act))
		bar.add_child(b)
		x += 242.0
	# кому сидеть в области
	x = 16.0
	for uu in colony.units:
		var b2 := Button.new()
		b2.position = Vector2(x, 120)
		b2.size = Vector2(320, 66)
		b2.focus_mode = Control.FOCUS_NONE
		INV.style_button(b2, 26)
		b2.text = _lock_text(uu)
		b2.pressed.connect(func() -> void:
			uu.area_lock = not uu.area_lock
			b2.text = _lock_text(uu)
			colony.jobs.cancel(uu))
		bar.add_child(b2)
		x += 330.0
	colony.set_tool("paint")

func _lock_text(u) -> String:
	return "%s: область" % String(u.unit_name) if u.area_lock else "%s: вся карта" % String(u.unit_name)

func _zone_act(act: String) -> void:
	match act:
		"paint":
			colony.set_tool("paint")
		"erase":
			colony.set_tool("erase")
		"clear":
			colony.zones.clear()
			colony.note("Область снята: ходят везде")
		"done":
			_close_tools()

func _close_zone() -> void:
	if zone_bar != null:
		zone_bar.queue_free()
		zone_bar = null

# ---------- метки и рамка ----------

func _toggle_desig() -> void:
	if String(colony.tool_mode) == "desig":
		colony.set_tool("")
		return
	_close_tools()
	colony.set_tool("desig")
	colony.note("Метьте цели: дерево, куст, зверя")

func _toggle_box() -> void:
	if String(colony.tool_mode) == "box":
		colony.set_tool("")
		return
	_close_tools()
	colony.set_tool("box")

func _close_tools() -> void:
	_close_craft()
	_close_plan()
	_close_zone()
	if colony != null and String(colony.tool_mode) != "":
		colony.set_tool("")

## Строй кнопок подсказывает, какой палец сейчас в руке.
func tool_changed() -> void:
	var m := String(colony.tool_mode)
	if desig_btn != null:
		desig_btn.text = "Метить: да" if m == "desig" else "Метить"
	if box_btn != null:
		box_btn.text = "Рамка: да" if m == "box" else "Рамка"
	if zone_btn != null:
		zone_btn.text = "Зона: кисть" if m == "paint" else ("Зона: стирка" if m == "erase" else "Зона")
	queue_redraw()

# ---------- кольцо приказов ----------

func open_radial(at: Vector2, cmds: Array, hit: Dictionary) -> void:
	close_radial()
	radial = Control.new()
	radial.anchor_right = 1.0
	radial.anchor_bottom = 1.0
	radial.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(radial)
	var n := mini(cmds.size(), 6)
	for i in n:
		var e: Array = cmds[i]
		var a := -PI * 0.5 + TAU * float(i) / float(n)
		var b := Button.new()
		b.text = String(e[0])
		b.size = Vector2(210, 86)
		b.position = at + Vector2(cos(a), sin(a)) * 150.0 - Vector2(105, 43)
		b.position.x = clampf(b.position.x, 10.0, size.x - 220.0)
		b.position.y = clampf(b.position.y, 10.0, size.y - 96.0)
		b.focus_mode = Control.FOCUS_NONE
		INV.style_button(b, 26)
		var kind := String(e[1])
		b.pressed.connect(func() -> void:
			colony.order(kind, hit)
			close_radial())
		radial.add_child(b)
	radial.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			close_radial()
		elif ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed:
			close_radial())

func close_radial() -> void:
	if radial != null:
		radial.queue_free()
		radial = null

# ---------- конец сценария ----------

func show_end(win: bool) -> void:
	if end_sheet != null:
		return
	var sc = colony.scenario
	var sh: Control = SHEET.new()
	sh.set("title", "Острог поставлен" if win else "Зима взяла своё")
	sh.set("info", "Первая зима")
	sh.anchor_left = 0.5
	sh.anchor_right = 0.5
	sh.anchor_top = 0.5
	sh.anchor_bottom = 0.5
	sh.offset_left = -420.0
	sh.offset_right = 420.0
	sh.offset_top = -280.0
	sh.offset_bottom = 280.0
	sh.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(sh)
	end_sheet = sh
	var st: Dictionary = colony.stats
	var lines: Array = [
		String(sc.end_text),
		"Дней прожито: %d" % int(st.get("days", 1)),
		"Срублено деревьев: %d, брёвен: %d" % [int(st.get("trees", 0)), int(st.get("logs", 0))],
		"Мяса добыто: %d, мехов: %d" % [int(st.get("meat", 0)), colony.furs()],
		"Построено: %d, волков побито: %d" % [int(st.get("built", 0)), int(st.get("wolves", 0))],
		"Людей осталось: %d из %d" % [colony.alive_count(), colony.units.size()],
	]
	var y := 110.0
	for t: String in lines:
		var l := Label.new()
		l.text = t
		l.position = Vector2(50, y)
		l.size = Vector2(740, 36)
		l.add_theme_font_size_override("font_size", 28)
		l.add_theme_color_override("font_color", INK)
		sh.add_child(l)
		y += 44.0
	var b := Button.new()
	b.text = "Заново"
	b.position = Vector2(50, 440)
	b.size = Vector2(340, 90)
	b.focus_mode = Control.FOCUS_NONE
	INV.style_button(b, 34)
	b.pressed.connect(func() -> void: colony.scenario.restart())
	sh.add_child(b)
	var b2 := Button.new()
	b2.text = "Смотреть дальше"
	b2.position = Vector2(430, 440)
	b2.size = Vector2(380, 90)
	b2.focus_mode = Control.FOCUS_NONE
	INV.style_button(b2, 34)
	b2.pressed.connect(func() -> void:
		end_sheet.queue_free()
		end_sheet = null)
	sh.add_child(b2)

# ---------- рисование ----------

func _process(delta: float) -> void:
	order_t = maxf(0.0, order_t - delta)
	_t -= delta
	if _t <= 0.0:
		_t = 0.2
		if build_sheet != null:
			_refresh_build_rows()
		if craft_sheet != null:
			_refresh_craft()
		queue_redraw()
	if order_t > 0.0 or String(colony.tool_mode) != "":
		queue_redraw()

func _panel(r: Rect2, title: String, lines: Array) -> void:
	var f := ThemeDB.fallback_font
	draw_rect(Rect2(r.position + Vector2(5, 6), r.size), Color(0, 0, 0, 0.25))
	draw_rect(r, Color(0.88, 0.8, 0.62, 0.9))
	draw_rect(r, Color(0.45, 0.32, 0.18), false, 3.0)
	var y := r.position.y + 34.0
	if title != "":
		draw_string(f, Vector2(r.position.x + 16, y), title, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 24, 26, INK)
		y += 32.0
	for t: String in lines:
		draw_string(f, Vector2(r.position.x + 16, y), t, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 24, 22, Color(0.33, 0.23, 0.13))
		y += 28.0

func _draw() -> void:
	if colony == null or main == null:
		return
	var f := ThemeDB.fallback_font
	var sc = colony.scenario
	# задача
	if sc != null:
		var c: Dictionary = sc.cur()
		_panel(Rect2(24, 20, 520, 120), "Задача", [String(c["text"]), String(c["prog"])])
		if sc.event_tt > 0.0:
			draw_string_outline(f, Vector2(size.x * 0.5 - 420, 190), String(sc.event_text), HORIZONTAL_ALIGNMENT_CENTER, 840, 30, 6, Color(0.1, 0.07, 0.04))
			draw_string(f, Vector2(size.x * 0.5 - 420, 190), String(sc.event_text), HORIZONTAL_ALIGNMENT_CENTER, 840, 30, Color(1, 0.92, 0.78))
	# день и погода
	var w = main.weather
	var hh := int(main.t_hours)
	var mm := int((main.t_hours - float(hh)) * 60.0)
	_panel(Rect2(size.x - 450, 20, 426, 92), "", ["%s, день %d · %02d:%02d" % [w.season_name(), int(main.day_count), hh, mm],
		"%d°C · %s" % [int(round(float(w.temp))), String(w.kind)]])
	# припасы
	var res: Array = [["meat_cooked", colony.food_count()], ["firewood", colony.count("firewood")], ["fur", colony.furs()], ["log", colony.count("log")]]
	var x := 580.0
	draw_rect(Rect2(x - 12, 24, 420, 80), Color(0.88, 0.8, 0.62, 0.86))
	draw_rect(Rect2(x - 12, 24, 420, 80), Color(0.45, 0.32, 0.18), false, 3.0)
	for e: Array in res:
		var cc := Vector2(x + 26, 64)
		INV.icon(self, String(e[0]), cc, 24.0)
		draw_string_outline(f, Vector2(x + 44, 78), str(int(e[1])), HORIZONTAL_ALIGNMENT_LEFT, 70, 26, 5, Color(0.9, 0.84, 0.7))
		draw_string(f, Vector2(x + 44, 78), str(int(e[1])), HORIZONTAL_ALIGNMENT_LEFT, 70, 26, INK)
		x += 105.0
	# сообщение
	if colony.msg_t > 0.0:
		draw_string_outline(f, Vector2(size.x * 0.5 - 500, size.y - 200), String(colony.msg), HORIZONTAL_ALIGNMENT_CENTER, 1000, 26, 6, Color(0.1, 0.07, 0.04))
		draw_string(f, Vector2(size.x * 0.5 - 500, size.y - 200), String(colony.msg), HORIZONTAL_ALIGNMENT_CENTER, 1000, 26, Color(1, 0.95, 0.85))
	# подсказка постановки
	if colony.place_type != "":
		var nm := String(main.camp.DEFS[colony.place_type]["name"])
		var why := String(colony.ghost_why)
		var txt := "%s: ткните в землю, где ставить" % nm
		if why != "":
			txt = "%s — %s" % [nm, why]
		draw_string_outline(f, Vector2(size.x * 0.5 - 500, 250), txt, HORIZONTAL_ALIGNMENT_CENTER, 1000, 28, 6, Color(0.1, 0.07, 0.04))
		draw_string(f, Vector2(size.x * 0.5 - 500, 250), txt, HORIZONTAL_ALIGNMENT_CENTER, 1000, 28,
			Color(0.75, 1.0, 0.75) if colony.ghost_ok else Color(1.0, 0.72, 0.6))
	# рамка выбора и подсказка пальца
	var tm := String(colony.tool_mode)
	if tm == "box" and colony.box_from != Vector2.INF and colony.box_to != Vector2.INF:
		var br := Rect2(colony.box_from, colony.box_to - colony.box_from).abs()
		draw_rect(br, Color(0.55, 0.86, 1.0, 0.12))
		draw_rect(br, Color(0.72, 0.95, 1.0, 0.85), false, 3.0)
	if tm != "":
		var hint := ""
		match tm:
			"paint":
				hint = "Кисть области: ведите пальцем, где ходить можно"
			"erase":
				hint = "Стирка: ведите, где ходить нельзя"
			"desig":
				hint = "Метьте цели: дерево — рубить, куст — собрать, зверь — охота"
			"box":
				hint = "Протяните рамку по людям"
		if hint != "":
			draw_string_outline(f, Vector2(size.x * 0.5 - 500, 400), hint, HORIZONTAL_ALIGNMENT_CENTER, 1000, 28, 6, Color(0.1, 0.07, 0.04))
			draw_string(f, Vector2(size.x * 0.5 - 500, 400), hint, HORIZONTAL_ALIGNMENT_CENTER, 1000, 28, Color(0.86, 0.96, 1.0))
	# метка приказа и обводка выбранного
	if order_t > 0.0 and order_mark != Vector3.INF and colony.rig != null:
		var sp: Vector2 = (colony.rig.cam as Camera3D).unproject_position(order_mark + Vector3(0, 0.3, 0))
		var k := order_t / 1.1
		draw_arc(sp, 26.0 * (1.4 - k), 0.0, TAU, 24, Color(1.0, 0.88, 0.5, k), 4.0, true)

# ---------- заказы мастерской ----------

func _close_craft() -> void:
	if craft_sheet != null:
		craft_sheet.queue_free()
		craft_sheet = null
	craft_rows = []

func _open_craft() -> void:
	if craft_sheet != null:
		_close_craft()
		return
	_close_tools()
	var sh: Control = SHEET.new()
	sh.set("title", "Заказы")
	sh.set("info", "")
	sh.anchor_left = 0.0
	sh.anchor_right = 0.0
	sh.anchor_top = 0.0
	sh.anchor_bottom = 1.0
	sh.offset_left = 24.0
	sh.offset_right = 824.0
	sh.offset_top = 150.0
	sh.offset_bottom = -170.0
	sh.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(sh)
	craft_sheet = sh
	var sc := ScrollContainer.new()
	sc.anchor_right = 1.0
	sc.anchor_bottom = 1.0
	sc.offset_left = 24.0
	sc.offset_top = 100.0
	sc.offset_right = -24.0
	sc.offset_bottom = -24.0
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.scroll_deadzone = 12
	sh.add_child(sc)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.custom_minimum_size = Vector2(720, 0)
	vb.add_theme_constant_override("separation", 10)
	sc.add_child(vb)
	craft_rows = []
	for id: String in colony.RECIPE_ORDER:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		vb.add_child(hb)
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 120)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		INV.style_button(b, 26)
		b.pressed.connect(func() -> void: colony.order_add(id, 1))
		hb.add_child(b)
		var m := Button.new()
		m.text = "−"
		m.custom_minimum_size = Vector2(110, 120)
		m.focus_mode = Control.FOCUS_NONE
		m.mouse_filter = Control.MOUSE_FILTER_PASS
		INV.style_button(m, 40)
		m.pressed.connect(func() -> void: colony.order_add(id, -1))
		hb.add_child(m)
		craft_rows.append([id, b])
	var x := _btn("Закрыть", 0.0, 0.0, 200.0, 70.0)
	remove_child(x)
	x.anchor_left = 1.0
	x.anchor_right = 1.0
	x.anchor_top = 0.0
	x.anchor_bottom = 0.0
	x.offset_left = -214.0
	x.offset_right = -22.0
	x.offset_top = 14.0
	x.offset_bottom = 78.0
	INV.style_button(x, 26)
	x.pressed.connect(_close_craft)
	sh.add_child(x)
	_refresh_craft()

func _refresh_craft() -> void:
	for r: Array in craft_rows:
		var id := String(r[0])
		var rc: Dictionary = colony.RECIPES[id]
		var parts: Array = []
		for k: String in rc["in"]:
			var have: int = colony.count(k)
			parts.append("%s %d/%d" % [INV.IT.name_of(k).to_lower(), have, int(rc["in"][k])])
		var q: int = int(colony.orders.get(id, 0))
		var warn := ""
		if colony.count(String(rc["tool"])) < 1:
			warn = " · нужен " + INV.IT.name_of(String(rc["tool"])).to_lower()
		(r[1] as Button).text = "%s ×%d    в очереди: %d\n%s%s\nтап — заказать ещё" % [INV.IT.name_of(id), int(rc["out"]), q, " · ".join(PackedStringArray(parts)), warn]
