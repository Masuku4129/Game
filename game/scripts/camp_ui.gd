extends Control
## Интерфейс лагеря в стиле короба: берестяная шапка, лист-пергамент с рваным краем, кнопки
## под палец. Кнопка «Стройка» (открывает полосу построек сразу, без лагеря), столбик действий у ближайшей
## постройки, полоса построек с ценой, кнопки поворота и постановки, листы: хранилище,
## готовка, стройка избы, печь, обстановка, верстак, стол, сушило.

const UI = preload("res://scripts/ui_palette.gd")
const IT = preload("res://scripts/items.gd")
const INK := UI.TEXT
const PAPER := UI.PANEL
const OK_C := UI.GOOD
const BAD_C := UI.DANGER

var camp
var main: Node3D
var camp_btn: RoundButton
var ctx_box := VBoxContainer.new()
var ctx_btns: Array = []
var ctx_acts: Array = []
var bar: Sheet
var cards := HBoxContainer.new()
var ctl_box := VBoxContainer.new()
var btn_rot_l: Button
var btn_rot_r: Button
var btn_place: Button
var btn_cancel: Button
var panel: Sheet
var rows_box := VBoxContainer.new()
var left_box := VBoxContainer.new()
var right_box := VBoxContainer.new()
var cols := HBoxContainer.new()
var scroll := ScrollContainer.new()
var close_btn: Button
var mode_btn: Button
var night := ColorRect.new()
var _fn: Callable
var _sig := ""
var _t := 0.0
var _store: Dictionary = {}
var _move_all := false

## Лист-пергамент: рваный край, пятна краски, берестяная шапка с заголовком.
class Sheet extends Control:
	const UI = preload("res://scripts/ui_palette.gd")
	var title := ""
	var info := ""
	var info_col := UI.TEXT_MUTED
	var head := 70.0
	func _draw() -> void:
		var sz := size
		var rng := RandomNumberGenerator.new()
		rng.seed = 4242
		var pts := PackedVector2Array()
		for i in 30:
			pts.append(Vector2(sz.x * i / 30.0, rng.randf_range(-4, 5)))
		for i in 12:
			pts.append(Vector2(sz.x + rng.randf_range(-5, 4), sz.y * i / 12.0))
		for i in 30:
			pts.append(Vector2(sz.x * (1.0 - i / 30.0), sz.y + rng.randf_range(-5, 4)))
		for i in 12:
			pts.append(Vector2(rng.randf_range(-4, 5), sz.y * (1.0 - i / 12.0)))
		var sh := PackedVector2Array()
		for p in pts:
			sh.append(p + Vector2(8, 10))
		draw_colored_polygon(sh, Color(0, 0, 0, 0.3))
		draw_colored_polygon(pts, UI.PANEL)
		for i in int(sz.x * sz.y / 9000.0):
			var d := rng.randf_range(-0.07, 0.07)
			draw_circle(Vector2(rng.randf_range(20, sz.x - 20), rng.randf_range(20, sz.y - 20)), rng.randf_range(18, 70), Color(0.45 + d * 0.2, 0.62 + d * 0.2, 0.38 + d * 0.2, 0.045))
		var ring := pts.duplicate()
		ring.append(pts[0])
		draw_polyline(ring, UI.BORDER, 3.0, true)
		if head > 0.0:
			draw_rect(Rect2(12, 12, sz.x - 24, head), UI.PANEL_SOFT)
			for i in int(sz.x / 22.0):
				var x := rng.randf_range(20, sz.x - 60)
				var y := rng.randf_range(18, head + 6)
				draw_line(Vector2(x, y), Vector2(x + rng.randf_range(14, 50), y + rng.randf_range(-1, 1)), Color(0.06, 0.09, 0.07, rng.randf_range(0.25, 0.55)), rng.randf_range(1.5, 3.5))
			draw_rect(Rect2(12, 12, sz.x - 24, head), UI.BORDER, false, 2.0)
			var f := ThemeDB.fallback_font
			draw_string(f, Vector2(32, 12 + head * 0.72), title, HORIZONTAL_ALIGNMENT_LEFT, sz.x * 0.55, 40, UI.TEXT)
			if info != "":
				draw_string(f, Vector2(sz.x * 0.45, 12 + head * 0.68), info, HORIZONTAL_ALIGNMENT_RIGHT, sz.x * 0.55 - 40, 26, info_col)

## Круглая кнопка лагеря: костерок в шалашике и подпись.
class RoundButton extends Button:
	const UI = preload("res://scripts/ui_palette.gd")
	var label := ""
	func _ready() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 4.0
		var dn := is_pressed() and is_hovered()
		draw_circle(c + Vector2(3, 4), r, Color(0, 0, 0, 0.3))
		draw_circle(c, r, UI.PANEL_SOFT if not dn else UI.PANEL_HOVER)
		draw_arc(c, r - 3.0, 0.0, TAU, 48, UI.ACCENT, 4.0, true)
		# шалашик из жердей и огонёк
		var o := c + Vector2(0, -r * 0.12)
		var w := r * 0.55
		var top := o + Vector2(0, -r * 0.48)
		for k in 5:
			var x := -w + w * 2.0 * k / 4.0
			draw_line(top, o + Vector2(x, r * 0.22), Color(0.82, 0.68, 0.45), 4.0)
		draw_colored_polygon(PackedVector2Array([o + Vector2(-r * 0.14, r * 0.22), o + Vector2(0, -r * 0.18), o + Vector2(r * 0.14, r * 0.22)]), Color(1.0, 0.55, 0.15))
		draw_colored_polygon(PackedVector2Array([o + Vector2(-r * 0.07, r * 0.22), o + Vector2(0, -r * 0.02), o + Vector2(r * 0.07, r * 0.22)]), Color(1.0, 0.9, 0.5))
		var f := ThemeDB.fallback_font
		var fs := 19 if label.length() < 10 else 16
		draw_string(f, Vector2(c.x - 75, c.y + r * 0.72), label, HORIZONTAL_ALIGNMENT_CENTER, 150, fs, Color(1, 0.95, 0.85))

## Карточка постройки или мебели: название и цена (зелёным — что есть, красным — чего нет).
class Card extends Button:
	const UI = preload("res://scripts/ui_palette.gd")
	var title := ""
	var lines: Array = []   # [текст, хватает]
	var picked := false
	func _ready() -> void:
		focus_mode = Control.FOCUS_NONE
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
	func _draw() -> void:
		var r := Rect2(Vector2(4, 4), size - Vector2(8, 8))
		draw_rect(r, UI.PANEL_SOFT)
		draw_rect(Rect2(r.position + Vector2(4, 4), r.size - Vector2(8, 8)), UI.PANEL)
		draw_rect(r, UI.BORDER, false, 2.0)
		if picked:
			draw_rect(Rect2(r.position - Vector2(2, 2), r.size + Vector2(4, 4)), Color(0.72, 0.3, 0.12), false, 6.0)
		var f := ThemeDB.fallback_font
		draw_string(f, Vector2(14, 40), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 24, 22, UI.TEXT)
		var y := 78.0
		for l: Array in lines:
			draw_string(f, Vector2(16, y), String(l[0]), HORIZONTAL_ALIGNMENT_LEFT, size.x - 26, 21, UI.GOOD if bool(l[1]) else UI.DANGER)
			y += 26.0

## Кнопка поворота: дуга со стрелкой.
class RotButton extends Button:
	var dir := 1.0
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.28
		var a0 := -PI * 0.85
		var a1 := PI * 0.35
		draw_arc(c, r, a0, a1, 24, Color(0.98, 0.93, 0.8), 6.0, true)
		var ae := a1 if dir > 0.0 else a0
		var tip := c + Vector2(cos(ae), sin(ae)) * r
		var tg := Vector2(-sin(ae), cos(ae)) * dir
		var nn := Vector2(cos(ae), sin(ae))
		draw_colored_polygon(PackedVector2Array([tip + tg * 16.0, tip + nn * 12.0 - tg * 4.0, tip - nn * 12.0 - tg * 4.0]), Color(0.98, 0.93, 0.8))

func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# кнопка лагеря над «Рюкзаком»
	camp_btn = RoundButton.new()
	_anchor(camp_btn, 1, 1, Rect2(-236, -560, 150, 150))
	camp_btn.pressed.connect(_camp_pressed)
	add_child(camp_btn)
	# столбик действий над кнопками инструментов (Метнуть/Воткнуть/пояс), чтобы не перекрывать их
	_anchor(ctx_box, 1, 1, Rect2(-760, -860, 370, 370))
	ctx_box.alignment = BoxContainer.ALIGNMENT_END
	ctx_box.add_theme_constant_override("separation", 12)
	ctx_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ctx_box)
	for i in 5:
		var b := _button("", Vector2(370, 76), 28)
		b.visible = false
		b.pressed.connect(_ctx.bind(i))
		ctx_box.add_child(b)
		ctx_btns.append(b)
	# полоса построек внизу
	bar = Sheet.new()
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.anchor_right = 1.0
	bar.offset_left = 420.0
	bar.offset_right = -380.0
	bar.offset_top = -330.0
	bar.offset_bottom = -14.0
	bar.head = 58.0
	bar.title = "Стройка"
	bar.visible = false
	add_child(bar)
	cards.position = Vector2(18, 84)
	cards.add_theme_constant_override("separation", 8)
	bar.add_child(cards)
	# поворот, постановка, отмена — справа сверху
	_anchor(ctl_box, 1, 0, Rect2(-700, 110, 300, 420))
	ctl_box.add_theme_constant_override("separation", 12)
	ctl_box.visible = false
	add_child(ctl_box)
	var rot_row := HBoxContainer.new()
	rot_row.add_theme_constant_override("separation", 12)
	ctl_box.add_child(rot_row)
	btn_rot_l = _rot_button(-1.0)
	btn_rot_r = _rot_button(1.0)
	rot_row.add_child(btn_rot_l)
	rot_row.add_child(btn_rot_r)
	btn_rot_l.pressed.connect(func(): _rotate(-1.0))
	btn_rot_r.pressed.connect(func(): _rotate(1.0))
	btn_place = _button("Поставить", Vector2(300, 100), 34)
	btn_place.pressed.connect(_place)
	ctl_box.add_child(btn_place)
	btn_cancel = _button("Готово", Vector2(300, 90), 32)
	btn_cancel.pressed.connect(_cancel)
	ctl_box.add_child(btn_cancel)
	# лист для хранилища, готовки и прочего
	panel = Sheet.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.offset_left = -560.0
	panel.offset_right = 560.0
	panel.offset_top = 60.0
	panel.offset_bottom = 820.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.visible = false
	add_child(panel)
	scroll.position = Vector2(30, 110)
	scroll.size = Vector2(1060, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	rows_box.custom_minimum_size = Vector2(1040, 0)
	rows_box.add_theme_constant_override("separation", 10)
	scroll.add_child(rows_box)
	cols.position = Vector2(30, 110)
	cols.size = Vector2(1060, 520)
	cols.add_theme_constant_override("separation", 20)
	panel.add_child(cols)
	for bx: VBoxContainer in [left_box, right_box]:
		var sc := ScrollContainer.new()
		sc.custom_minimum_size = Vector2(520, 520)
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		bx.custom_minimum_size = Vector2(500, 0)
		bx.add_theme_constant_override("separation", 8)
		sc.add_child(bx)
		cols.add_child(sc)
	close_btn = _button("Закрыть", Vector2(280, 96), 34)
	close_btn.position = Vector2(810, 648)
	close_btn.pressed.connect(close_panel)
	panel.add_child(close_btn)
	mode_btn = _button("По одному", Vector2(300, 96), 30)
	mode_btn.position = Vector2(30, 648)
	mode_btn.pressed.connect(func():
		_move_all = not _move_all
		mode_btn.text = "Всё сразу" if _move_all else "По одному")
	panel.add_child(mode_btn)
	# затемнение «ночь прошла»
	night.anchor_right = 1.0
	night.anchor_bottom = 1.0
	night.color = Color(0.02, 0.02, 0.05, 0.0)
	night.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(night)

func _anchor(c: Control, ax: int, ay: int, r: Rect2) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = r.position.x
	c.offset_top = r.position.y
	c.offset_right = r.position.x + r.size.x
	c.offset_bottom = r.position.y + r.size.y

## Кнопка в стиле короба (как в inventory.gd).
func _button(t: String, sz: Vector2, fs: int) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = sz
	b.size = sz
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	b.add_theme_font_size_override("font_size", fs)
	b.add_theme_color_override("font_color", UI.TEXT)
	b.add_theme_color_override("font_pressed_color", UI.TEXT)
	b.add_theme_color_override("font_hover_color", UI.ACCENT_HI)
	b.add_theme_color_override("font_disabled_color", UI.TEXT_MUTED)
	var cs := {"normal": UI.PANEL_SOFT, "hover": UI.PANEL_HOVER, "pressed": UI.PANEL_PRESSED, "disabled": UI.PANEL}
	for k: String in cs:
		var sb := StyleBoxFlat.new()
		sb.bg_color = cs[k]
		sb.set_corner_radius_all(14)
		sb.set_border_width_all(2)
		sb.border_color = UI.BORDER
		sb.shadow_color = Color(0, 0, 0, 0.25)
		sb.shadow_size = 3
		sb.shadow_offset = Vector2(1, 2)
		b.add_theme_stylebox_override(k, sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b

## Строка списка на листе: светлая плашка, чернила.
func _row(t: String, enabled: bool, fs: int = 28) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(0, 76)
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.disabled = not enabled
	b.clip_text = true
	b.add_theme_font_size_override("font_size", fs)
	for k: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(k, UI.TEXT)
	b.add_theme_color_override("font_disabled_color", UI.TEXT_MUTED)
	var cs := {"normal": UI.PANEL_SOFT, "hover": UI.PANEL_HOVER, "pressed": UI.PANEL_PRESSED, "disabled": UI.PANEL}
	for k: String in cs:
		var sb := StyleBoxFlat.new()
		sb.bg_color = cs[k]
		sb.set_corner_radius_all(10)
		sb.set_border_width_all(2)
		sb.border_color = UI.BORDER
		sb.content_margin_left = 22
		b.add_theme_stylebox_override(k, sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b

func _rot_button(d: float) -> RotButton:
	var b := RotButton.new()
	var src := _button("", Vector2(144, 100), 30)
	for k: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(k, src.get_theme_stylebox(k))
	src.free()
	b.custom_minimum_size = Vector2(144, 100)
	b.focus_mode = Control.FOCUS_NONE
	b.dir = d
	return b

# ---------- кнопка лагеря и режим стройки ----------

func _camp_pressed() -> void:
	var b = camp.build
	if b.active:
		_end_build()
		return
	# лагеря больше нет: стройка открывается сразу, ставить можно где угодно (проверки места — в build_mode)
	b.start()
	_fill_build_cards()

func _end_build() -> void:
	camp.build.stop()

func _fill_build_cards() -> void:
	for c in cards.get_children():
		c.queue_free()
	for k: String in camp.ORDER:
		var d: Dictionary = camp.DEFS[k]
		var cd := Card.new()
		cd.custom_minimum_size = Vector2(212, 220)
		cd.title = d["name"]
		cd.pressed.connect(func(): camp.build.select(k))
		cd.set_meta("kind", k)
		cards.add_child(cd)
	_update_cards()

func _update_cards() -> void:
	for cd in cards.get_children():
		var card := cd as Card
		if card == null or not card.has_meta("kind"):
			continue
		var k: String = card.get_meta("kind")
		var lines: Array = []
		if camp.cabin_ctl.inside:
			var fd: Dictionary = camp.cabin_ctl.FURN[k]
			for id: String in fd["cost"]:
				lines.append(["%s %d/%d" % [IT.name_of(id), camp.count(id), int(fd["cost"][id])], camp.count(id) >= int(fd["cost"][id])])
			card.picked = camp.cabin_ctl.placing and camp.cabin_ctl.p_kind == k
		else:
			var d: Dictionary = camp.DEFS[k]
			var cost: Dictionary = d["cost"] if k != "cabin" else d["need"]
			for id: String in cost:
				var have: int = camp.count(id)
				lines.append(["%s %d/%d" % [IT.name_of(id), have, int(cost[id])], have >= int(cost[id]) or k == "cabin"])
			if k == "snow_shelter":
				lines.append(["лопата", camp.has_shovel()])
			if k == "cabin":
				lines.append(["вносится на стройку", true])
			card.picked = camp.build.kind == k
		card.lines = lines
		card.queue_redraw()

func _rotate(d: float) -> void:
	if camp.cabin_ctl.placing:
		camp.cabin_ctl.rotate_piece()
	else:
		camp.build.rotate_by(d * PI / 8.0)

func _place() -> void:
	if camp.cabin_ctl.placing:
		camp.cabin_ctl.confirm_place()
	else:
		camp.build.confirm()
	_update_cards()

func _cancel() -> void:
	if camp.cabin_ctl.placing:
		camp.cabin_ctl.cancel_place()
	elif camp.build.kind != "":
		camp.build.select("")
	else:
		_end_build()

# ---------- кадр ----------

func _process(delta: float) -> void:
	if camp == null or main == null:
		return
	night.color.a = maxf(0.0, night.color.a - delta * 0.5)
	var hero: Node3D = main.hero
	var inv_open: bool = main.inventory != null and (main.inventory.is_open() or hero.pack_stage != "")
	var b = camp.build
	var cc = camp.cabin_ctl
	var placing: bool = (b.active and b.kind != "") or cc.placing
	# кнопка лагеря
	camp_btn.visible = not inv_open and not panel.visible and not cc.inside and hero.state == "walk"
	camp_btn.label = "Готово" if b.active else "Стройка"
	camp_btn.queue_redraw()
	# полоса построек / мебели
	bar.visible = (b.active or (cc.inside and cc.placing)) and not panel.visible
	ctl_box.visible = bar.visible
	btn_place.visible = placing
	btn_rot_l.visible = placing
	btn_rot_r.visible = placing
	btn_cancel.text = "Отмена" if placing else "Готово"
	if bar.visible:
		if cc.inside:
			bar.title = "Обстановка"
			bar.info = "" if cc.p_valid else "Здесь не встанет"
		else:
			bar.title = "Стройка"
			bar.info = b.reason if b.kind != "" and not b.valid else ("Тяните призрак пальцем" if b.kind != "" else "Выберите постройку")
		bar.info_col = BAD_C if (b.kind != "" and not b.valid) or (cc.placing and not cc.p_valid) else INK
		btn_place.disabled = not ((cc.placing and cc.p_valid) or (not cc.placing and b.valid))
		bar.queue_redraw()
	_t -= delta
	if _t <= 0.0:
		_t = 0.25
		if bar.visible:
			_update_cards()
		# действия у построек
		ctx_acts = [] if (inv_open or panel.visible or placing or b.active) else camp.actions()
		for i in ctx_btns.size():
			var btn: Button = ctx_btns[i]
			btn.visible = i < ctx_acts.size()
			if btn.visible:
				btn.text = String(ctx_acts[i][0])
		if panel.visible and _fn.is_valid():
			_refresh_panel()
	if panel.visible:
		main.joy.visible = false   # иначе видимостью джойстика управляет inventory.gd

func _ctx(i: int) -> void:
	if i < ctx_acts.size():
		var c: Callable = ctx_acts[i][1]
		c.call()
		_t = 0.0

func fade_night() -> void:
	night.color.a = 1.0

# ---------- листы ----------

## Открыть лист со строками. fn() -> {title, info, rows: [[текст, можно, Callable]]}.
func _open(fn: Callable, two_cols: bool = false) -> void:
	_fn = fn
	_sig = ""
	_transition_panel(true)
	scroll.visible = not two_cols
	cols.visible = two_cols
	mode_btn.visible = two_cols
	_refresh_panel()

func close_panel() -> void:
	_transition_panel(false)
	_fn = Callable()
	_store = {}

func _transition_panel(opening: bool) -> void:
	if _panel_tween != null and _panel_tween.is_running():
		_panel_tween.kill()
	if opening:
		panel.visible = true
		panel.pivot_offset = panel.size * 0.5
		panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
		panel.scale = Vector2(0.98, 0.98)
		_panel_tween = panel.create_tween()
		_panel_tween.set_parallel(true)
		_panel_tween.tween_property(panel, "modulate", Color.WHITE, 0.18)
		_panel_tween.tween_property(panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		if not panel.visible:
			return
		_panel_tween = panel.create_tween()
		_panel_tween.set_parallel(true)
		_panel_tween.tween_property(panel, "modulate", Color(1.0, 1.0, 1.0, 0.0), 0.12)
		_panel_tween.tween_property(panel, "scale", Vector2(0.98, 0.98), 0.12)
		_panel_tween.chain().tween_callback(func() -> void:
			panel.visible = false
			panel.modulate = Color.WHITE
			panel.scale = Vector2.ONE
		)

func _refresh_panel() -> void:
	var d: Dictionary = _fn.call()
	panel.title = d.get("title", "")
	panel.info = d.get("info", "")
	panel.queue_redraw()
	if d.has("left"):
		var sig := str(d["left"]) + str(d["right"])
		if sig == _sig:
			return
		_sig = sig
		for bx: VBoxContainer in [left_box, right_box]:
			for c in bx.get_children():
				c.queue_free()
		_fill(left_box, d["left"])
		_fill(right_box, d["right"])
		return
	var rows: Array = d.get("rows", [])
	var sig2 := ""
	for r: Array in rows:
		sig2 += String(r[0]) + str(r[1]) + ";"
	if sig2 == _sig:
		return
	_sig = sig2
	for c in rows_box.get_children():
		c.queue_free()
	_fill(rows_box, rows)

func _fill(box: VBoxContainer, rows: Array) -> void:
	for r: Array in rows:
		if r.size() < 3:
			var l := Label.new()
			l.text = String(r[0])
			l.add_theme_font_size_override("font_size", 26)
			l.add_theme_color_override("font_color", Color(INK, 0.8))
			box.add_child(l)
			continue
		var b := _row(String(r[0]), bool(r[1]))
		var cb: Callable = r[2]
		b.pressed.connect(func():
			cb.call()
			_sig = ""
			_refresh_panel())
		box.add_child(b)

## Хранилище постройки: слева короб, справа хранилище; тап переносит.
func open_store(s: Dictionary) -> void:
	_store = s
	var fn := func() -> Dictionary:
		var l: Array = [["Короб: %.1f / %d кг" % [main.inventory.weight() if main.inventory != null else 0.0, 15]]]
		for id: String in _sorted(main.inv):
			l.append(["%s  ×%d   →" % [IT.name_of(id), int(main.inv[id])], true, func(): camp.to_store(s, id, 999 if _move_all else 1)])
		var r: Array = [["Хранилище: %.1f / %d кг" % [camp.store_weight(s), int(camp.store_cap(s))]]]
		for id2: String in _sorted(s["store"]):
			r.append(["←   %s  ×%d" % [IT.name_of(id2), int(s["store"][id2])], true, func(): camp.from_store(s, id2, 999 if _move_all else 1)])
		var dur: String = "" if s["type"] == "cabin" else camp.dur_text(s)
		return {"title": "Хранилище · " + String(camp.DEFS[s["type"]]["name"]), "info": dur, "left": l, "right": r}
	_open(fn, true)

func _sorted(d: Dictionary) -> Array:
	var ks: Array = []
	for k: String in d:
		if int(d[k]) > 0:
			ks.append(k)
	ks.sort()
	return ks

## Готовка на костре (и на печи — из листа печи).
func open_cook(s: Dictionary) -> void:
	_open(func() -> Dictionary:
		var rows: Array = []
		var ck: Dictionary = s["cook"]
		if not ck.is_empty():
			var k: float = camp.cook_k(s)
			rows.append(["На огне: %s — %d%%" % [IT.name_of(String(ck["in"])), int(k * 100.0)]])
			rows.append([("Снять: " + IT.name_of(String(ck["out"]))) if bool(ck["done"]) else "Снять недожаренное", true, func(): camp.take_cooked(s)])
		for r: Array in camp.fire_recipes():
			var n: int = camp.count(String(r[1]))
			rows.append(["%s → %s   (есть %d)" % [IT.name_of(String(r[1])), IT.name_of(String(r[0])), n], n > 0 and ck.is_empty(), func(): camp.start_cook(s, r[0], r[1])])
		rows.append(["Подбросить дров (дрова %d, хворост %d)" % [camp.count("firewood"), camp.count("twig")], true, func(): camp.add_fuel(s)])
		var fuel_key := "fuel" if s["type"] == "campfire" else "stove_fuel"
		return {"title": "Готовка" if s["type"] == "campfire" else "Печь", "info": "огонь ещё на %.1f ч" % float(s[fuel_key]), "rows": rows})

func open_stove(s: Dictionary) -> void:
	_open(func() -> Dictionary:
		var rows: Array = []
		var lit: bool = s["stove_lit"]
		if lit:
			rows.append(["Подбросить дров (дрова %d, хворост %d)" % [camp.count("firewood"), camp.count("twig")], true, func(): camp.add_fuel(s)])
			rows.append(["Закрыть заслонку (погасить)", true, func(): camp.put_out(s)])
		else:
			rows.append(["Затопить печь", true, func(): camp.light(s)])
			rows.append(["Положить дрова", true, func(): camp.add_fuel(s)])
		var ck: Dictionary = s["cook"]
		if not ck.is_empty():
			rows.append([("Достать: " + IT.name_of(String(ck["out"]))) if bool(ck["done"]) else "В печи: %s — %d%%" % [IT.name_of(String(ck["in"])), int(camp.cook_k(s) * 100.0)], bool(ck["done"]), func(): camp.take_cooked(s)])
		for r: Array in camp.fire_recipes():
			var n: int = camp.count(String(r[1]))
			rows.append(["В печь: %s → %s   (есть %d)" % [IT.name_of(String(r[1])), IT.name_of(String(r[0])), n], n > 0 and ck.is_empty() and lit, func(): camp.start_cook(s, r[0], r[1])])
		return {"title": "Печь", "info": ("топится, дров на %.1f ч" % float(s["stove_fuel"])) if lit else "холодная", "rows": rows})

## Стройка избы: внести припасы, начать стройку.
func open_site(s: Dictionary) -> void:
	_open(func() -> Dictionary:
		var rows: Array = []
		var need: Dictionary = camp.need_of(s)
		var have: Dictionary = s["have"]
		for id: String in need:
			rows.append(["%s: на стройке %d из %d   (в коробе %d)" % [IT.name_of(id), int(have.get(id, 0)), int(need[id]), camp.count(id)]])
		rows.append(["Внести всё, что есть", true, func(): camp.deposit(s)])
		var ready: bool = camp.site_ready(s)
		rows.append(["Строить" if ready else "Строить — не хватает припасов", ready, func():
			camp.start_building(s)
			close_panel()])
		var tot := 0
		var got := 0
		for id2: String in need:
			tot += int(need[id2])
			got += mini(int(have.get(id2, 0)), int(need[id2]))
		return {"title": "Стройка избы", "info": "припасы %d%%" % int(100.0 * got / maxf(tot, 1.0)), "rows": rows})

## Обстановка: новая мебель (полоса карточек) и уже стоящая.
func open_furn(s: Dictionary) -> void:
	_open(func() -> Dictionary:
		var rows: Array = []
		var cc = camp.cabin_ctl
		for k: String in cc.FURN_ORDER:
			var fd: Dictionary = cc.FURN[k]
			var cost := PackedStringArray()
			for id: String in fd["cost"]:
				cost.append("%s %d" % [IT.name_of(id).to_lower(), int(fd["cost"][id])])
			rows.append(["Поставить: %s (%s) — %s" % [fd["name"], ", ".join(cost), fd["desc"]], camp.can_pay(fd["cost"]), func():
				close_panel()
				_start_furn(k)])
		for f: Dictionary in s["furn"]:
			var nm: String = cc.FURN[String(f["kind"])]["name"]
			rows.append(["Передвинуть: " + nm, true, func():
				close_panel()
				_start_furn(String(f["kind"]), f)])
			rows.append(["Убрать: %s (вернётся половина)" % nm, true, func(): cc.remove_piece(f)])
		return {"title": "Обстановка избы", "info": "хранилище %d кг" % int(camp.store_cap(s)), "rows": rows})

func _start_furn(k: String, move: Dictionary = {}) -> void:
	camp.cabin_ctl.begin_place(k, move)
	for c in cards.get_children():
		c.queue_free()
	var cd := Card.new()
	cd.custom_minimum_size = Vector2(420, 220)
	cd.title = camp.cabin_ctl.FURN[k]["name"]
	cd.set_meta("kind", k)
	cards.add_child(cd)
	var hint := Card.new()
	hint.custom_minimum_size = Vector2(620, 220)
	hint.title = "Тап по полу — переставить"
	hint.lines = [["стрелки — повернуть, «Поставить» — готово", true]]
	cards.add_child(hint)

func open_bench() -> void:
	_open(func() -> Dictionary:
		var rows: Array = []
		for r: Array in camp.cabin_ctl.BENCH:
			var cost := PackedStringArray()
			var cd: Dictionary = r[2]
			for id: String in cd:
				cost.append("%s %d/%d" % [IT.name_of(id).to_lower(), camp.count(id), int(cd[id])])
			rows.append(["%s ×%d  ←  %s" % [IT.name_of(String(r[0])), int(r[1]), ", ".join(cost)], camp.can_pay(cd), func(): camp.cabin_ctl.bench_make(r)])
		return {"title": "Верстак", "info": "станция «camp»", "rows": rows})

func open_table() -> void:
	_open(func() -> Dictionary:
		var rows: Array = []
		for id: String in _sorted(main.inv):
			if IT.DEF.get(id, {}).has("eat") and id != "amanita":
				rows.append(["Съесть: %s  ×%d" % [IT.name_of(id), int(main.inv[id])], true, func(): camp.cabin_ctl.eat_at_table(id)])
		if rows.is_empty():
			rows.append(["Нечего есть: принесите еду в коробе"])
		return {"title": "За столом", "info": "сытость +33%", "rows": rows})

func open_rack(s: Dictionary) -> void:
	_open(func() -> Dictionary:
		var rows: Array = []
		var rk: Dictionary = s.get("rack", {})
		if not rk.is_empty():
			var k := clampf(float(rk["t"]) / float(rk["need"]), 0.0, 1.0)
			rows.append([("Снять: " + IT.name_of(String(rk["out"]))) if bool(rk["done"]) else "Сохнет: %s — %d%%" % [IT.name_of(String(rk["in"])), int(k * 100.0)], true, func(): camp.cabin_ctl.rack_take(s)])
		for r: Array in camp.cabin_ctl.rack_recipes():
			var n: int = camp.count(String(r[1]))
			rows.append(["%s → %s   (есть %d)" % [IT.name_of(String(r[1])), IT.name_of(String(r[0])), n], n > 0 and rk.is_empty(), func(): camp.cabin_ctl.rack_put(s, r[0], r[1])])
		return {"title": "Сушило", "info": "4 ч, у топленой печи быстрее", "rows": rows})
