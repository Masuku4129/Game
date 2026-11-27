extends Control
## Инвентарь — берестяной короб. Открывается кнопкой «Рюкзак» (или I / Tab): герой снимает
## короб, ставит перед собой и открывает; тогда появляется лист. Две вкладки: «Короб» (вещи,
## рука и пояс) и «Ремесло» (рецепты items.gd: craft, station "" — руками; видно, чего не хватает).
## «Закрыть» — герой закрывает короб и закидывает его на плечи. Пока короб открыт, идти нельзя.
## Данные — main.inv (вид → количество); то, что в руке и на поясе, в вес короба не входит.
##
## Для других команд: add_item(id, n) / remove_item(id, n) / count(id) / can_add(id);
## station_ok(station) спрашивает main.station_near(station), если такой метод есть.

const CAPACITY := 15.0
const COLS := 5
const ROWS := 4
const CELL := 104.0
const GAP := 8.0
const GRID := Vector2(36, 124)
const UI = preload("res://scripts/ui_palette.gd")
const IT = preload("res://scripts/items.gd")
const ITEMS = IT.DEF
const ICONS = preload("res://scripts/icons.gd")  # core: значки из моделей
# рецепты, которых нет в items.gd: расколоть два камня — получить кремнёвый скол
const EXTRA := {"flint": {"pebble": 2}, "meat_raw": {"carcass_small": 1}}
# сколько выходит и чем делается (разделать тушку — ножом)
const EXTRA_OUT := {"meat_raw": 2}
const EXTRA_TOOL := {"meat_raw": "knife"}
const ROW_H := 50.0

var main: Node3D
var sheet := Control.new()
var shown := 0.0        # 0..1 — видимость листа
var cam_k := 0.0        # 0..1 — камера наезжает на героя
var sel := ""
var tab := 0            # 0 — короб, 1 — ремесло, 2 — одежда, 3 — карта
var rsel := ""          # выбранный рецепт
var btn_use: Button
var btn_belt: Button
var btn_drop: Button
var btn_close: Button
var _base_dist := 12.0
var _base_pitch := 45.0
var _base_yaw := 0.0
var _view_yaw := 0.0
var _active := false
var craft_scroll := 0.0
var _craft_dragging := false
var _craft_drag_y := 0.0
var _craft_scroll_start := 0.0
var _craft_drag_mode := "list" # list | scrollbar
var _craft_bar_offset := 0.0
var _edge := PackedVector2Array()
var _blots: Array = []

func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.anchor_left = 1.0
	sheet.anchor_right = 1.0
	sheet.anchor_bottom = 1.0
	sheet.offset_left = -1010.0
	sheet.offset_right = -30.0
	sheet.offset_top = 66.0
	sheet.offset_bottom = -16.0
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	sheet.visible = false
	sheet.draw.connect(_draw_sheet)
	sheet.gui_input.connect(_sheet_input)
	add_child(sheet)
	btn_use = _button("Съесть", Rect2(36, 650, 214, 100))
	btn_use.pressed.connect(_use)
	btn_belt = _button("На пояс", Rect2(266, 650, 214, 100))
	btn_belt.pressed.connect(_belt)
	btn_drop = _button("Выбросить", Rect2(496, 650, 214, 100))
	btn_drop.pressed.connect(_drop)
	btn_close = _button("Закрыть", Rect2(730, 650, 214, 100))
	btn_close.pressed.connect(close)
	# неровный край листа и пятна краски — один раз
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var w := 980.0
	var h := 782.0
	var pts := []
	for i in 40:
		pts.append(Vector2(w * i / 40.0, rng.randf_range(-4, 5)))
	for i in 32:
		pts.append(Vector2(w + rng.randf_range(-5, 4), h * i / 32.0))
	for i in 40:
		pts.append(Vector2(w * (1.0 - i / 40.0), h + rng.randf_range(-5, 4)))
	for i in 32:
		pts.append(Vector2(rng.randf_range(-4, 5), h * (1.0 - i / 32.0)))
	_edge = PackedVector2Array(pts)
	for i in 70:
		_blots.append([Vector2(rng.randf_range(20, w - 20), rng.randf_range(20, h - 20)), rng.randf_range(18, 90), rng.randf_range(-0.07, 0.07)])
	if main != null and main.hud != null:
		main.hud.bag_btn.pressed.connect(toggle)

func _button(t: String, r: Rect2) -> Button:
	var b := Button.new()
	b.text = t
	b.position = r.position
	b.size = r.size
	b.focus_mode = Control.FOCUS_NONE
	style_button(b, 32)
	sheet.add_child(b)
	return b

## Кнопка в стиле листа: тёмное дерево, светлые буквы (общая с HUD).
static func style_button(b: Button, fs: int) -> void:
	b.add_theme_font_size_override("font_size", fs)
	b.add_theme_color_override("font_color", UI.TEXT)
	b.add_theme_color_override("font_pressed_color", UI.TEXT)
	b.add_theme_color_override("font_hover_color", UI.ACCENT_HI)
	b.add_theme_color_override("font_disabled_color", UI.TEXT_MUTED)
	var cols := {"normal": UI.PANEL_SOFT, "hover": UI.PANEL_HOVER, "pressed": UI.PANEL_PRESSED, "disabled": UI.PANEL}
	for k: String in cols:
		var sb := StyleBoxFlat.new()
		sb.bg_color = cols[k]
		sb.set_corner_radius_all(14)
		sb.set_border_width_all(2)
		sb.border_color = UI.BORDER
		sb.shadow_color = Color(0, 0, 0, 0.24)
		sb.shadow_size = 3
		sb.shadow_offset = Vector2(1, 2)
		b.add_theme_stylebox_override(k, sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

# ---------- открытие и закрытие ----------

func toggle() -> void:
	if _active:
		close()
	else:
		open()

func open() -> void:
	if _active or main == null:
		return
	if not main.hero.pack_open():
		main._say("Сейчас короб не снять")
		return
	_active = true
	_base_dist = main.rig.distance
	_base_pitch = main.rig.pitch
	_base_yaw = main.rig.rotation.y
	# вид спереди-справа на три четверти: виден и герой, и короб перед ним (слева от листа)
	_view_yaw = float(main.hero.body.rotation.y) - 0.9
	sel = ""
	_pick_default()

func close() -> void:
	if not _active:
		return
	main.hero.pack_close()

## Сбросить без анимации (удар зверя, гибель).
func abort() -> void:
	if main != null and main.hero.pack_stage != "":
		main.hero.pack_abort()

func is_open() -> bool:
	return _active

func _process(delta: float) -> void:
	if main == null:
		return
	if OS.get_environment("INV_SHOTS") != "":
		_test_shots(delta)
	var hero: Node3D = main.hero
	var stage: String = hero.pack_stage
	if _active and stage == "":
		_active = false
	var want_sheet := 1.0 if (_active and stage == "open") else 0.0
	shown = move_toward(shown, want_sheet, delta * 4.0)
	sheet.visible = shown > 0.01
	sheet.modulate.a = shown
	sheet.offset_left = -1010.0 + (1.0 - _ease(shown)) * 120.0
	sheet.offset_right = -30.0 + (1.0 - _ease(shown)) * 120.0
	# камера мягко наезжает и сдвигает героя влево от листа
	var want_cam := 1.0 if _active else 0.0
	var was := cam_k
	cam_k = move_toward(cam_k, want_cam, delta / 1.6)
	if cam_k > 0.0 or was > 0.0:
		var k := _ease(cam_k)
		main.rig.distance = lerpf(_base_dist, 4.6, k)
		main.rig.pitch = lerpf(_base_pitch, 30.0, k)
		main.rig.rotation.y = lerp_angle(_base_yaw, _view_yaw, k)
		main.rig.cam.h_offset = k * 0.42 * main.rig.distance * _ease(shown * 0.6 + (0.4 if stage != "" else 0.0))
	var busy := _active or stage != ""
	main.hud.bag_btn.visible = not busy and hero.state == "walk"
	main.joy.visible = not busy
	if sheet.visible:
		_update_buttons()
		sheet.queue_redraw()

func _update_buttons() -> void:
	var tools: Node = main.hero.tools
	if tab == 1:
		btn_use.text = "Сделать"
		btn_use.disabled = rsel == "" or not missing(rsel).is_empty() or not station_ok(_station(rsel)) or not _tool_ok(rsel)
		btn_belt.visible = false
		btn_drop.visible = false
		return
	btn_belt.visible = true
	btn_drop.visible = true
	btn_drop.disabled = sel == ""
	var d: Dictionary = ITEMS.get(sel, {})
	if d.has("tool"):
		btn_use.text = "Убрать" if tools.held == sel else "В руку"
		btn_use.disabled = false
		btn_belt.text = "С пояса" if tools.belt.has(sel) else "На пояс"
		btn_belt.disabled = not d.get("belt", false)
		if d.get("back", false):  # --- combat: лук — за спину ---
			btn_belt.text = "Со спины" if tools.back == sel else "За спину"
			btn_belt.disabled = false
	else:
		btn_use.text = "Съесть"
		btn_use.disabled = sel == "" or not d.has("eat")
		btn_belt.text = "На пояс"
		btn_belt.disabled = true

func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		var kc: int = e.keycode
		if kc == KEY_I or kc == KEY_TAB or kc == KEY_B:
			toggle()
			get_viewport().set_input_as_handled()
		elif kc == KEY_ESCAPE and _active:
			close()
			get_viewport().set_input_as_handled()

# ---------- данные ----------

func _kinds() -> Array:
	var out := []
	for k in main.inv.keys():
		if int(main.inv[k]) > 0:
			out.append(k)
	# инструменты — первыми
	out.sort_custom(func(a: String, b: String) -> bool: return int(ITEMS.get(a, {}).has("tool")) > int(ITEMS.get(b, {}).has("tool")))
	return out

func count(id: String) -> int:
	return int(main.inv.get(id, 0))

func add_item(id: String, n: int = 1) -> bool:
	if n <= 0:
		return false
	if main == null:
		return false
	if not bool(main.get("creative_mode")) and not can_add(id, n):
		return false
	main.inv[id] = count(id) + n
	return int(main.inv[id]) >= n

func remove_item(id: String, n: int = 1) -> bool:
	var worn_count := 0
	for slot: String in main.worn:
		if String(main.worn[slot]) == id:
			worn_count += 1
	if count(id) - worn_count < n:
		return false
	main.inv[id] = count(id) - n
	if int(main.inv[id]) <= 0:
		main.inv.erase(id)
	if main.hero.tools != null:
		main.hero.tools.sync()
	return true

## Вес в коробе: то, что в руке и на поясе, не считается.
func weight() -> float:
	var w := 0.0
	var tools: Node = main.hero.tools if main.hero != null else null
	for k in main.inv.keys():
		var n := int(main.inv[k])
		if tools != null:
			n -= tools.equipped_count(k)
		for slot: String in main.worn:
			if String(main.worn[slot]) == String(k):
				n -= 1
		w += float(ITEMS.get(k, {}).get("w", 0.3)) * maxi(n, 0)
	return w

func can_add(kind: String, amount: int = 1) -> bool:
	if amount <= 0:
		return true
	if main != null and bool(main.get("creative_mode")):
		return true
	return weight() + float(ITEMS.get(kind, {}).get("w", 0.3)) * float(amount) <= CAPACITY + 0.001

func _name(kind: String) -> String:
	if ITEMS.has(kind):
		return ITEMS[kind]["name"]
	return String(main.PICK_NAME.get(kind, kind)).capitalize()

func _pick_default() -> void:
	var ks := _kinds()
	if not ks.has(sel):
		sel = ks[0] if not ks.is_empty() else ""

# ---------- ремесло ----------

func recipe(id: String) -> Dictionary:
	if EXTRA.has(id):
		return EXTRA[id]
	return ITEMS.get(id, {}).get("craft", {})

func _station(id: String) -> String:
	return String(ITEMS.get(id, {}).get("station", "")) if not EXTRA.has(id) else ""

func station_ok(st: String) -> bool:
	if main != null and bool(main.get("creative_mode")):
		return true
	if st == "":
		return true
	if main != null and main.has_method("station_near"):
		return bool(main.call("station_near", st))
	return false

## Рецепты: сначала руками, потом у огня/печи (если рядом).
func recipes() -> Array:
	var out: Array = []
	for id: String in EXTRA:
		out.append(id)
	for id: String in ITEMS:
		if ITEMS[id].has("craft"):
			out.append(id)
	var ok := func(id: String) -> int: return 1 if missing(id).is_empty() else 0
	out.sort_custom(func(a: String, b: String) -> bool: return ok.call(a) > ok.call(b))
	return out

## Чего не хватает: {id: сколько}.
func missing(id: String) -> Dictionary:
	if main != null and bool(main.get("creative_mode")):
		return {}
	var out := {}
	var rc := recipe(id)
	for k: String in rc:
		var worn_count := 0
		for slot: String in main.worn:
			if String(main.worn[slot]) == k:
				worn_count += 1
		var have: int = count(k) - (int(main.hero.tools.equipped_count(k)) if main.hero.tools != null else 0) - worn_count
		if have < int(rc[k]):
			out[k] = int(rc[k]) - have
	return out

func _tool_ok(id: String) -> bool:
	if main != null and bool(main.get("creative_mode")):
		return true
	# --- core: need [id] из items.gd — нужно иметь (нож, горшок, кружка), не тратится ---
	for t: String in ITEMS.get(id, {}).get("need", []):
		if count(t) <= 0:
			return false
	# --- /core ---
	return not EXTRA_TOOL.has(id) or main.hero.has_tool(String(EXTRA_TOOL[id]))

func craft(id: String) -> bool:
	if not missing(id).is_empty() or not station_ok(_station(id)) or not _tool_ok(id):
		return false
	var rc := recipe(id)
	var output_count := int(EXTRA_OUT.get(id, ITEMS.get(id, {}).get("out", 1)))
	var creative := main != null and bool(main.get("creative_mode"))
	if not creative:
		# Сначала считаем итоговый вес. Рецепт не должен списать материалы,
		# а затем потерять готовый предмет из-за переполненного короба.
		var consumed_weight := 0.0
		for k: String in rc:
			consumed_weight += float(ITEMS.get(k, {}).get("w", 0.3)) * float(rc[k])
		var output_weight := float(ITEMS.get(id, {}).get("w", 0.3)) * float(output_count)
		if weight() - consumed_weight + output_weight > CAPACITY + 0.001:
			if main != null:
				main._say("В коробе нет места для готового предмета")
			return false
		for k: String in rc:
			if not remove_item(k, int(rc[k])):
				return false
	add_item(id, output_count)  # core: out из items.gd
	main._say("Сделано: " + _name(id).to_lower())
	if main.sfx != null:
		main.sfx.play_at("chop" if id == "flint" else "cut", main.hero.position + Vector3(0, 0.6, 0), -2.0, 1.3)
	if ITEMS.get(id, {}).get("hands", false):
		main.hero.tools.give_long(id)
	return true

# ---------- кнопки ----------

func _use() -> void:
	if tab == 1:
		craft(rsel)
		return
	if sel == "":
		return
	if ITEMS.get(sel, {}).has("tool"):
		# --- combat: состояние рук и пояса — только через hero_tools ---
		var tools: Node = main.hero.tools
		if tools.held == sel:
			tools.to_pack(sel)
		else:
			tools.draw(sel)
		return
	if not ITEMS.get(sel, {}).has("eat"):
		return
	var e: Array = ITEMS[sel]["eat"]
	# --- core: миска и ложка (сытнее), горячее греет — main.core_eat() ---
	if main.has_method("core_eat"):
		e = main.core_eat(sel, e)
	# --- /core ---
	main.hunger = clampf(float(main.hunger) + float(e[0]), 0.0, 1.0)
	main.thirst = clampf(float(main.thirst) + float(e[1]), 0.0, 1.0)
	if float(e[2]) < 0.0:
		main.health = maxf(0.05, float(main.health) + float(e[2]))
		main.flash.color.a = 0.25
		main._say("Мухомор! Отравление")
	else:
		main._say("Съел: " + _name(sel).to_lower())
	main.hero.pack_eat()
	_take(sel)

func _belt() -> void:
	var tools: Node = main.hero.tools
	# --- combat: лук — за спину и обратно в короб ---
	if sel != "" and ITEMS.get(sel, {}).get("back", false):
		if tools.back == sel:
			tools.to_pack(sel)
		else:
			tools.to_back(sel)
		return
	# --- /combat ---
	if sel == "" or not ITEMS.get(sel, {}).get("belt", false):
		return
	if tools.belt.has(sel):
		tools.to_pack(sel)
	else:
		tools.to_belt(sel)

func _drop() -> void:
	if sel == "":
		return
	# охота (hunt.gd): шкура, мясо, тушка ложатся на землю моделью
	if main.get("hunt") != null:
		var yaw: float = main.hero.body.rotation.y
		main.hunt.drop_item(sel, main.hero.position + Vector3(sin(yaw), 0, cos(yaw)) * 0.8)
	main._say("Выбросил: " + _name(sel).to_lower())
	_take(sel)

func _take(kind: String) -> void:
	remove_item(kind, 1)
	_pick_default()

func _sheet_input(e: InputEvent) -> void:
	var rs := recipes() if tab == 1 else []
	var max_scroll := maxf(0.0, float(rs.size()) * ROW_H - (640.0 - GRID.y))
	if e is InputEventScreenTouch and e.pressed and e.position.y < 100.0 and e.position.x > 210.0 and e.position.x < 800.0:
		tab = clampi(int((e.position.x - 210.0) / 175.0), 0, 3)
		sheet.queue_redraw()
		return
	if tab == 2 and e is InputEventScreenTouch:
		var clothing_touch := e as InputEventScreenTouch
		if clothing_touch.pressed:
			if clothing_touch.position.x < 610.0 and clothing_touch.position.y >= GRID.y and clothing_touch.position.y <= 640.0:
				var clothing_list := _wearables()
				var clothing_index := int((clothing_touch.position.y - GRID.y) / ROW_H)
				if clothing_index >= 0 and clothing_index < clothing_list.size():
					sel = clothing_list[clothing_index]
			elif clothing_touch.position.x >= 640.0 and clothing_touch.position.y >= 500.0 and sel != "":
				_wear_toggle(sel)
			sheet.queue_redraw()
		return
	if tab == 1:
		if e is InputEventMouseButton:
			var mb := e as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
				craft_scroll = maxf(0.0, craft_scroll - ROW_H * 2.0)
				sheet.queue_redraw()
				return
			if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
				craft_scroll = minf(max_scroll, craft_scroll + ROW_H * 2.0)
				sheet.queue_redraw()
				return
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed and mb.position.x >= 604.0 and mb.position.x <= 642.0 and mb.position.y >= GRID.y and mb.position.y <= 640.0 and max_scroll > 0.0:
					_craft_dragging = true
					_craft_drag_mode = "scrollbar"
					var track_top := GRID.y
					var track_h_mouse := 516.0
					var thumb_h_mouse := maxf(42.0, track_h_mouse * track_h_mouse / (float(rs.size()) * ROW_H))
					var thumb_y_mouse := track_top + (track_h_mouse - thumb_h_mouse) * craft_scroll / max_scroll
					_craft_bar_offset = mb.position.y - thumb_y_mouse if mb.position.y >= thumb_y_mouse and mb.position.y <= thumb_y_mouse + thumb_h_mouse else thumb_h_mouse * 0.5
					var next_top_mouse := clampf(mb.position.y - _craft_bar_offset, track_top, track_top + track_h_mouse - thumb_h_mouse)
					craft_scroll = (next_top_mouse - track_top) / maxf(track_h_mouse - thumb_h_mouse, 1.0) * max_scroll
					sheet.queue_redraw()
					return
				if mb.pressed and mb.position.x < 604.0 and mb.position.y >= GRID.y and mb.position.y <= 640.0:
					_craft_dragging = true
					_craft_drag_mode = "list"
					_craft_drag_y = mb.position.y
					_craft_scroll_start = craft_scroll
					var row_i := int((mb.position.y - GRID.y + craft_scroll) / ROW_H)
					if row_i >= 0 and row_i < rs.size():
						rsel = rs[row_i]
					sheet.queue_redraw()
					return
				elif not mb.pressed:
					_craft_dragging = false
		if e is InputEventScreenTouch:
			var touch := e as InputEventScreenTouch
			if not touch.pressed:
				_craft_dragging = false
				return
			if touch.position.y >= GRID.y and touch.position.y <= 640.0:
				if touch.position.x >= 604.0 and touch.position.x <= 642.0 and max_scroll > 0.0:
					_craft_dragging = true
					_craft_drag_mode = "scrollbar"
					var track_h_touch := 516.0
					var thumb_h_touch := maxf(42.0, track_h_touch * track_h_touch / (float(rs.size()) * ROW_H))
					var thumb_y_touch := GRID.y + (track_h_touch - thumb_h_touch) * craft_scroll / max_scroll
					_craft_bar_offset = touch.position.y - thumb_y_touch if touch.position.y >= thumb_y_touch and touch.position.y <= thumb_y_touch + thumb_h_touch else thumb_h_touch * 0.5
					var next_top_touch := clampf(touch.position.y - _craft_bar_offset, GRID.y, GRID.y + track_h_touch - thumb_h_touch)
					craft_scroll = (next_top_touch - GRID.y) / maxf(track_h_touch - thumb_h_touch, 1.0) * max_scroll
				elif touch.position.x < 604.0:
					_craft_dragging = true
					_craft_drag_mode = "list"
					_craft_drag_y = touch.position.y
					_craft_scroll_start = craft_scroll
					var row_i := int((touch.position.y - GRID.y + craft_scroll) / ROW_H)
					if row_i >= 0 and row_i < rs.size():
						rsel = rs[row_i]
				sheet.queue_redraw()
				return
		if e is InputEventScreenDrag and _craft_dragging:
			var drag := e as InputEventScreenDrag
			if _craft_drag_mode == "scrollbar":
				var track_h_drag := 516.0
				var thumb_h_drag := maxf(42.0, track_h_drag * track_h_drag / (float(rs.size()) * ROW_H))
				var top_drag := clampf(drag.position.y - _craft_bar_offset, GRID.y, GRID.y + track_h_drag - thumb_h_drag)
				craft_scroll = (top_drag - GRID.y) / maxf(track_h_drag - thumb_h_drag, 1.0) * max_scroll
			else:
				craft_scroll = clampf(_craft_scroll_start - (drag.position.y - _craft_drag_y), 0.0, max_scroll)
			sheet.queue_redraw()
			return
		if e is InputEventMouseMotion and _craft_dragging:
			var motion := e as InputEventMouseMotion
			if _craft_drag_mode == "scrollbar":
				var track_h_motion := 516.0
				var thumb_h_motion := maxf(42.0, track_h_motion * track_h_motion / (float(rs.size()) * ROW_H))
				var top_motion := clampf(motion.position.y - _craft_bar_offset, GRID.y, GRID.y + track_h_motion - thumb_h_motion)
				craft_scroll = (top_motion - GRID.y) / maxf(track_h_motion - thumb_h_motion, 1.0) * max_scroll
			else:
				craft_scroll = clampf(_craft_scroll_start - (motion.position.y - _craft_drag_y), 0.0, max_scroll)
			sheet.queue_redraw()
			return
	if not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		return
	var pos: Vector2 = e.position
	if pos.y < 100.0 and pos.x > 210.0 and pos.x < 800.0:
		tab = clampi(int((pos.x - 210.0) / 175.0), 0, 3)
		sheet.queue_redraw()
		return
	if tab == 2:
		if pos.x < 610.0 and pos.y >= GRID.y and pos.y <= 640.0:
			var wearable := _wearables()
			var wi := int((pos.y - GRID.y) / ROW_H)
			if wi >= 0 and wi < wearable.size():
				sel = wearable[wi]
		elif pos.x >= 640.0 and pos.y >= 500.0 and sel != "":
			_wear_toggle(sel)
		sheet.queue_redraw()
		return
	if tab == 3:
		return
	if tab == 1:
		if pos.x < 610.0 and pos.y >= GRID.y and pos.y <= 640.0:
			var i := int((pos.y - GRID.y + craft_scroll) / ROW_H)
			if i >= 0 and i < rs.size():
				rsel = rs[i]
		sheet.queue_redraw()
		return
	var p: Vector2 = pos - GRID
	var cx := int(p.x / (CELL + GAP))
	var cy := int(p.y / (CELL + GAP))
	if p.x >= 0 and p.y >= 0 and cx < COLS and cy < ROWS:
		var i := cy * COLS + cx
		var ks := _kinds()
		if i < ks.size():
			sel = ks[i]
			sheet.queue_redraw()

# ---------- рисование листа ----------

const INK := UI.TEXT
const PAPER := UI.PANEL
const OK_C := Color(0.25, 0.42, 0.15)
const BAD_C := Color(0.62, 0.16, 0.1)

func _draw_sheet() -> void:
	var ci := sheet
	var f := ThemeDB.fallback_font
	var sz := Vector2(980, 782)
	# тень и лист с рваным краем, пятна краски
	var sh := PackedVector2Array()
	for p in _edge:
		sh.append(p + Vector2(8, 10))
	ci.draw_colored_polygon(sh, Color(0, 0, 0, 0.3))
	ci.draw_colored_polygon(_edge, UI.PANEL)
	for b: Array in _blots:
		var d: float = b[2]
		ci.draw_circle(b[0], b[1], Color(0.45 + d * 0.2, 0.62 + d * 0.2, 0.38 + d * 0.2, 0.045))
	var ring := _edge.duplicate()
	ring.append(_edge[0])
	ci.draw_polyline(ring, UI.BORDER, 3.0, true)
	# шапка — береста: светлая кора с тёмными чечевичками
	ci.draw_rect(Rect2(14, 14, sz.x - 28, 84), UI.PANEL_SOFT)
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	for i in 46:
		var x := rng.randf_range(20, sz.x - 60)
		var y := rng.randf_range(20, 90)
		ci.draw_line(Vector2(x, y), Vector2(x + rng.randf_range(14, 50), y + rng.randf_range(-1, 1)), Color(0.06, 0.09, 0.07, rng.randf_range(0.25, 0.55)), rng.randf_range(1.5, 3.5))
	ci.draw_rect(Rect2(14, 14, sz.x - 28, 84), UI.BORDER, false, 2.0)
	# вкладки
	for t in 4:
		var r := Rect2(210 + t * 175, 22, 165, 68)
		var on := tab == t
		ci.draw_rect(r, UI.PANEL_HOVER if on else UI.PANEL_SOFT)
		ci.draw_rect(r, UI.BORDER, false, 2.0)
		var lbl: String = ["Короб", "Ремесло", "Одежда", "Карта"][t]
		ci.draw_string(f, Vector2(r.position.x, r.position.y + 48), lbl, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 36, INK if on else Color(INK, 0.6))
	var w := weight()
	ci.draw_string_outline(f, Vector2(sz.x - 220, 66), "%.1f/%d кг" % [w, int(CAPACITY)], HORIZONTAL_ALIGNMENT_RIGHT, 190, 28, 6, Color(0.93, 0.9, 0.82))
	ci.draw_string(f, Vector2(sz.x - 220, 66), "%.1f/%d кг" % [w, int(CAPACITY)], HORIZONTAL_ALIGNMENT_RIGHT, 190, 28, INK)
	ci.draw_string(f, Vector2(36, 70), "Тайга", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color(INK, 0.85))
	if tab == 0:
		_draw_pack(ci, f, w)
	elif tab == 1:
		_draw_craft(ci, f)
	elif tab == 2:
		_draw_clothes(ci, f)
	else:
		_draw_map(ci, f)

func _cell_bg(ci: CanvasItem, r: Rect2) -> void:
	ci.draw_rect(r, UI.PANEL_SOFT)
	ci.draw_rect(Rect2(r.position + Vector2(4, 4), r.size - Vector2(8, 8)), UI.PANEL)
	ci.draw_line(r.position, Vector2(r.end.x, r.position.y), UI.BORDER, 2.0)
	ci.draw_line(r.position, Vector2(r.position.x, r.end.y), UI.BORDER, 2.0)

func _wearables() -> Array:
	var out: Array = []
	for id: String in _kinds():
		if ITEMS.get(id, {}).has("wear"):
			out.append(id)
	return out

func _wear_toggle(id: String) -> void:
	var slot := String(ITEMS.get(id, {}).get("wear", ""))
	if slot == "":
		return
	if String(main.worn.get(slot, "")) == id:
		main.worn.erase(slot)
		if main.hero != null:
			main.hero.refresh_clothing()
		main._say("Снято: " + _name(id).to_lower())
		return
	main.worn[slot] = id
	if main.hero != null:
		main.hero.refresh_clothing()
	main._say("Надето: " + _name(id).to_lower())

func _draw_clothes(ci: CanvasItem, f: Font) -> void:
	var wearable := _wearables()
	for i in wearable.size():
		var id := String(wearable[i])
		var y := GRID.y + i * ROW_H
		var slot := String(ITEMS[id].get("wear", ""))
		var equipped := String(main.worn.get(slot, "")) == id
		var r := Rect2(GRID.x, y, 574, ROW_H - 5)
		ci.draw_rect(r, UI.PANEL_HOVER if equipped else UI.PANEL_SOFT)
		ci.draw_rect(r, UI.BORDER, false, 1.5)
		icon(ci, id, r.position + Vector2(26, 21), 17.0)
		ci.draw_string(f, r.position + Vector2(56, 30), _name(id), HORIZONTAL_ALIGNMENT_LEFT, 300, 24, INK)
		ci.draw_string(f, r.position + Vector2(370, 30), "Надето" if equipped else "В коробе", HORIZONTAL_ALIGNMENT_RIGHT, 170, 22, OK_C if equipped else Color(INK, 0.65))
	var dr := Rect2(640, 124, 304, 500)
	ci.draw_rect(dr, Color(0.8, 0.7, 0.5, 0.55))
	ci.draw_rect(dr, Color(0.45, 0.33, 0.2), false, 3.0)
	ci.draw_string(f, Vector2(656, 166), "Экипировка", HORIZONTAL_ALIGNMENT_LEFT, 270, 28, INK)
	var y2 := 218.0
	var total_warm := 0.0
	for slot in ["head", "body", "feet"]:
		var id := String(main.worn.get(slot, ""))
		if id != "":
			total_warm += float(ITEMS.get(id, {}).get("warm", 0.0))
		var slot_name: String = {"head": "Голова", "body": "Туловище", "feet": "Ноги"}.get(slot, slot)
		ci.draw_string(f, Vector2(660, y2), "%s: %s" % [slot_name, _name(id) if id != "" else "пусто"], HORIZONTAL_ALIGNMENT_LEFT, 265, 22, INK)
		y2 += 48.0
	ci.draw_string(f, Vector2(660, 382), "Тепло одежды: +%d%%" % int(round(total_warm * 100.0)), HORIZONTAL_ALIGNMENT_LEFT, 265, 24, OK_C)
	ci.draw_rect(Rect2(660, 520, 250, 62), UI.PANEL_HOVER)
	ci.draw_rect(Rect2(660, 520, 250, 62), UI.BORDER, false, 2.0)
	var selected_slot := String(ITEMS.get(sel, {}).get("wear", ""))
	var is_worn := selected_slot != "" and String(main.worn.get(selected_slot, "")) == sel
	ci.draw_string(f, Vector2(660, 559), "Снять" if is_worn else "Надеть выбранное", HORIZONTAL_ALIGNMENT_CENTER, 250, 24, INK)
	ci.draw_multiline_string(f, Vector2(660, 600), "Одежда сохраняется и повышает сопротивление холоду.", HORIZONTAL_ALIGNMENT_LEFT, 250, 20, 2, Color(INK, 0.75))

func _draw_map(ci: CanvasItem, f: Font) -> void:
	var cells: Dictionary = main.explored_map if main != null else {}
	var center_x := floori(main.hero.position.x / 16.0)
	var center_z := floori(main.hero.position.z / 16.0)
	var cell_size := 18.0
	var origin := Vector2(76.0, 142.0)
	var cols := 29
	var rows := 25
	var map_rect := Rect2(origin, Vector2(cols * cell_size, rows * cell_size))
	ci.draw_rect(map_rect, Color(0.28, 0.31, 0.25, 0.22))
	for rz in rows:
		for rx in cols:
			var gx := center_x + rx - cols / 2
			var gz := center_z + rz - rows / 2
			var key := "%d,%d" % [gx, gz]
			var r := Rect2(origin + Vector2(rx, rz) * cell_size, Vector2(cell_size - 1.0, cell_size - 1.0))
			if not cells.has(key):
				continue
			var data: Dictionary = cells[key]
			var col := Color(0.28, 0.43, 0.24)
			match int(data.get("zone", 0)):
				1: col = Color(0.28, 0.25, 0.2)
				2: col = Color(0.38, 0.43, 0.29)
				4: col = Color(0.43, 0.39, 0.31)
			if bool(data.get("water", false)) or bool(data.get("lake", false)) or bool(data.get("river", false)):
				col = Color(0.25, 0.46, 0.55) if bool(data.get("water", false)) or bool(data.get("lake", false)) else Color(0.34, 0.56, 0.62)
			ci.draw_rect(r, col)
		ci.draw_rect(map_rect, Color(0.28, 0.2, 0.13), false, 3.0)
	var marker := origin + Vector2(cols / 2.0, rows / 2.0) * cell_size + Vector2(cell_size * 0.5, cell_size * 0.5)
	ci.draw_colored_polygon(PackedVector2Array([marker + Vector2(0, -8), marker + Vector2(6, 6), marker + Vector2(-6, 6)]), Color(0.82, 0.22, 0.12))
	var info := Rect2(620, 142, 324, 482)
	ci.draw_rect(info, Color(0.8, 0.7, 0.5, 0.55))
	ci.draw_rect(info, Color(0.45, 0.33, 0.2), false, 3.0)
	ci.draw_string(f, Vector2(640, 184), "Исследованная местность", HORIZONTAL_ALIGNMENT_LEFT, 285, 26, INK)
	ci.draw_string(f, Vector2(640, 222), "Открыто участков: %d" % cells.size(), HORIZONTAL_ALIGNMENT_LEFT, 285, 22, INK)
	var legends := [[Color(0.28, 0.43, 0.24), "Лес"], [Color(0.38, 0.43, 0.29), "Болото"], [Color(0.25, 0.46, 0.55), "Вода / озеро"], [Color(0.34, 0.56, 0.62), "Река"], [Color(0.28, 0.25, 0.2), "Гарь"]]
	for i in legends.size():
		var yy := 280.0 + i * 48.0
		ci.draw_rect(Rect2(644, yy - 18, 28, 24), legends[i][0])
		ci.draw_string(f, Vector2(688, yy), legends[i][1], HORIZONTAL_ALIGNMENT_LEFT, 230, 22, INK)
	ci.draw_multiline_string(f, Vector2(644, 550), "Карта открывается по мере исследования. Неизведанные участки не показываются.", HORIZONTAL_ALIGNMENT_LEFT, 275, 24, 3, Color(INK, 0.75))

func _draw_pack(ci: CanvasItem, f: Font, w: float) -> void:
	var tools: Node = main.hero.tools
	var ks := _kinds()
	for i in COLS * ROWS:
		var r := Rect2(GRID + Vector2((i % COLS) * (CELL + GAP), (i / COLS) * (CELL + GAP)), Vector2(CELL, CELL))
		_cell_bg(ci, r)
		if i < ks.size():
			var k: String = ks[i]
			icon(ci, k, r.get_center() + Vector2(0, -6), 34.0)
			var n := "%d" % int(main.inv[k])
			ci.draw_string_outline(f, r.end - Vector2(56, 10), n, HORIZONTAL_ALIGNMENT_RIGHT, 50, 26, 6, PAPER)
			ci.draw_string(f, r.end - Vector2(56, 10), n, HORIZONTAL_ALIGNMENT_RIGHT, 50, 26, INK)
			# метка: в руке / на поясе
			var tag := ""
			if tools != null and tools.held == k:
				tag = "рука"
			elif tools != null and tools.belt.has(k):
				tag = "пояс"
			if tag != "":
				ci.draw_rect(Rect2(r.position + Vector2(4, 4), Vector2(56, 24)), Color(0.46, 0.31, 0.18, 0.9))
				ci.draw_string(f, r.position + Vector2(4, 23), tag, HORIZONTAL_ALIGNMENT_CENTER, 56, 18, Color(0.98, 0.93, 0.8))
			if k == sel:
				ci.draw_rect(Rect2(r.position - Vector2(3, 3), r.size + Vector2(6, 6)), Color(0.72, 0.3, 0.12), false, 5.0)
	if ks.is_empty():
		ci.draw_string(f, GRID + Vector2(0, CELL * 1.5 + 10), "Пусто. Собирайте хворост, камни, ягоды и грибы.", HORIZONTAL_ALIGNMENT_LEFT, 560, 26, Color(INK, 0.7))
	# ноша
	var fr := clampf(w / CAPACITY, 0.0, 1.0)
	var br := Rect2(GRID.x, 584, COLS * CELL + (COLS - 1) * GAP, 40)
	ci.draw_rect(br, Color(0.6, 0.5, 0.34))
	var fc := Color(0.45, 0.6, 0.3).lerp(Color(0.8, 0.45, 0.15), smoothstep(0.5, 0.8, fr)).lerp(Color(0.75, 0.18, 0.12), smoothstep(0.85, 1.0, fr))
	ci.draw_rect(Rect2(br.position, Vector2(br.size.x * fr, br.size.y)), fc)
	ci.draw_rect(br, INK, false, 3.0)
	ci.draw_string_outline(f, br.position + Vector2(14, 30), "Ноша: %.1f / %d кг" % [w, int(CAPACITY)], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 6, Color(PAPER, 0.8))
	ci.draw_string(f, br.position + Vector2(14, 30), "Ноша: %.1f / %d кг" % [w, int(CAPACITY)], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, INK)
	# снаряжение: рука и пояс
	var er := Rect2(640, 124, 304, 128)
	ci.draw_rect(er, Color(0.8, 0.7, 0.5, 0.55))
	ci.draw_rect(er, Color(0.45, 0.33, 0.2), false, 3.0)
	var slots := [["Рука", tools.held if tools != null else ""], ["Пояс", tools.belt[0] if tools != null and tools.belt.size() > 0 else ""], ["Пояс", tools.belt[1] if tools != null and tools.belt.size() > 1 else ""]]
	for i in 3:
		var sr := Rect2(er.position + Vector2(12 + i * 98, 10), Vector2(86, 86))
		_cell_bg(ci, sr)
		var id: String = slots[i][1]
		if id != "":
			icon(ci, id, sr.get_center(), 30.0)
		ci.draw_string(f, Vector2(sr.position.x, er.end.y - 8), slots[i][0], HORIZONTAL_ALIGNMENT_CENTER, sr.size.x, 20, Color(INK, 0.8))
	# описание выбранного
	var dr := Rect2(640, 264, 304, 360)
	ci.draw_rect(dr, Color(0.8, 0.7, 0.5, 0.55))
	ci.draw_rect(dr, Color(0.45, 0.33, 0.2), false, 3.0)
	if sel != "" and main.inv.has(sel):
		ci.draw_circle(Vector2(dr.get_center().x, 330), 56, Color(0.74, 0.63, 0.44, 0.7))
		icon(ci, sel, Vector2(dr.get_center().x, 330), 46.0)
		ci.draw_string(f, Vector2(dr.position.x, 424), _name(sel), HORIZONTAL_ALIGNMENT_CENTER, dr.size.x, 34, INK)
		var iw := float(ITEMS.get(sel, {}).get("w", 0.3))
		ci.draw_string(f, Vector2(dr.position.x, 456), "%d шт. · %.2f кг" % [int(main.inv[sel]), iw * int(main.inv[sel])], HORIZONTAL_ALIGNMENT_CENTER, dr.size.x, 22, Color(INK, 0.75))
		var desc: String = ITEMS.get(sel, {}).get("desc", "")
		ci.draw_multiline_string(f, Vector2(dr.position.x + 16, 490), desc, HORIZONTAL_ALIGNMENT_LEFT, dr.size.x - 32, 23, 4, INK)
		if ITEMS.get(sel, {}).has("eat"):
			var e: Array = ITEMS[sel]["eat"]
			var eff := PackedStringArray()
			if float(e[0]) != 0.0:
				eff.append("сытость %+d%%" % int(round(float(e[0]) * 100.0)))
			if float(e[1]) != 0.0:
				eff.append("жажда %+d%%" % int(round(float(e[1]) * 100.0)))
			if float(e[2]) != 0.0:
				eff.append("здоровье %+d%%" % int(round(float(e[2]) * 100.0)))
			ci.draw_multiline_string(f, Vector2(dr.position.x + 16, 600), ", ".join(eff), HORIZONTAL_ALIGNMENT_LEFT, dr.size.x - 32, 21, 2, BAD_C if float(e[2]) < 0.0 else OK_C)
	else:
		ci.draw_string(f, Vector2(dr.position.x, 440), "Выберите вещь", HORIZONTAL_ALIGNMENT_CENTER, dr.size.x, 28, Color(INK, 0.6))

func _draw_craft(ci: CanvasItem, f: Font) -> void:
	var rs := recipes()
	if rsel == "" or not rs.has(rsel):
		rsel = rs[0] if not rs.is_empty() else ""
	var max_scroll := maxf(0.0, float(rs.size()) * ROW_H - (640.0 - GRID.y))
	craft_scroll = clampf(craft_scroll, 0.0, max_scroll)
	for i in rs.size():
		var id: String = rs[i]
		var y := GRID.y + i * ROW_H - craft_scroll
		if y < GRID.y or y + ROW_H > 640.0:
			continue
		var r := Rect2(GRID.x, y, 574, ROW_H - 6)
		var ok := missing(id).is_empty() and station_ok(_station(id)) and _tool_ok(id)
		ci.draw_rect(r, Color(0.8, 0.7, 0.5, 0.75 if ok else 0.35))
		if id == rsel:
			ci.draw_rect(Rect2(r.position - Vector2(2, 2), r.size + Vector2(4, 4)), Color(0.72, 0.3, 0.12), false, 4.0)
		icon(ci, id, r.position + Vector2(26, 22), 17.0)
		var nm := "Разделать тушку" if id == "meat_raw" else ("Расколоть камни" if id == "flint" else _name(id))
		ci.draw_string(f, r.position + Vector2(56, 32), nm, HORIZONTAL_ALIGNMENT_LEFT, 220, 25, INK if ok else Color(INK, 0.55))
		# состав: значки с количеством, недостающее — красным
		var x := r.position.x + 290
		var rc := recipe(id)
		var miss := missing(id)
		for k: String in rc:
			icon(ci, k, Vector2(x + 14, y + 22), 13.0)
			ci.draw_string(f, Vector2(x + 30, y + 32), "%d" % int(rc[k]), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, BAD_C if miss.has(k) else OK_C)
			x += 66
	var track := Rect2(610, GRID.y, 20, 516)
	ci.draw_rect(track, Color(0.22, 0.19, 0.14, 0.38))
	if max_scroll > 0.0:
		var thumb_h := maxf(42.0, track.size.y * track.size.y / (float(rs.size()) * ROW_H))
		var thumb_y := track.position.y + (track.size.y - thumb_h) * craft_scroll / max_scroll
		ci.draw_rect(Rect2(track.position.x + 3.0, thumb_y, 14.0, thumb_h), UI.ACCENT)
		ci.draw_rect(Rect2(track.position.x + 7.0, thumb_y + 5.0, 6.0, maxf(8.0, thumb_h - 10.0)), Color(1.0, 0.88, 0.7, 0.55))
	if rs.is_empty():
		ci.draw_string(f, GRID + Vector2(0, 40), "Нечего мастерить", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(INK, 0.6))
	var dr := Rect2(640, 124, 304, 500)
	ci.draw_rect(dr, Color(0.8, 0.7, 0.5, 0.55))
	ci.draw_rect(dr, Color(0.45, 0.33, 0.2), false, 3.0)
	if rsel == "":
		return
	ci.draw_circle(Vector2(dr.get_center().x, 200), 60, Color(0.74, 0.63, 0.44, 0.7))
	icon(ci, rsel, Vector2(dr.get_center().x, 200), 48.0)
	ci.draw_string(f, Vector2(dr.position.x, 300), _name(rsel), HORIZONTAL_ALIGNMENT_CENTER, dr.size.x, 32, INK)
	var desc: String = ITEMS.get(rsel, {}).get("desc", "")
	if rsel == "flint":
		desc = "Ударить камень о камень: отлетает острый скол."
	elif rsel == "meat_raw":
		desc = "Разделать тушку ножом: две порции мяса."
	ci.draw_multiline_string(f, Vector2(dr.position.x + 16, 336), desc, HORIZONTAL_ALIGNMENT_LEFT, dr.size.x - 32, 22, 3, INK)
	var y2 := 420.0
	ci.draw_string(f, Vector2(dr.position.x + 16, y2), "Нужно:", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, INK)
	var rc2 := recipe(rsel)
	var miss2 := missing(rsel)
	for k: String in rc2:
		y2 += 32
		var have := count(k)
		ci.draw_string(f, Vector2(dr.position.x + 24, y2), "%s  %d / %d" % [_name(k), mini(have, int(rc2[k])), int(rc2[k])], HORIZONTAL_ALIGNMENT_LEFT, dr.size.x - 40, 22, BAD_C if miss2.has(k) else OK_C)
	var st := _station(rsel)
	if st != "" and not station_ok(st):
		y2 += 34
		ci.draw_string(f, Vector2(dr.position.x + 24, y2), "Нужен " + {"fire": "костёр", "stove": "печь", "camp": "верстак, стол или колода"}.get(st, st), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, BAD_C)
	elif not _tool_ok(rsel):
		y2 += 34
		# --- core: перечислить, чего нет из нужного (нож, горшок, кружка…) ---
		var lack := PackedStringArray()
		for t: String in ITEMS.get(rsel, {}).get("need", []):
			if count(t) <= 0:
				lack.append(_name(t).to_lower())
		if EXTRA_TOOL.has(rsel):
			lack.append("нож")
		ci.draw_string(f, Vector2(dr.position.x + 24, y2), "Нужен: " + ", ".join(lack), HORIZONTAL_ALIGNMENT_LEFT, dr.size.x - 40, 22, BAD_C)
		# --- /core ---
	elif not miss2.is_empty():
		y2 += 34
		ci.draw_string(f, Vector2(dr.position.x + 24, y2), "Не хватает материала", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, BAD_C)

## Значок вещи: простой рисунок кистью (круги, эллипсы, штрихи).
static func icon(ci: CanvasItem, kind: String, c: Vector2, r: float) -> void:
	# --- core: значок, отрисованный из игровой модели (res://icons, студия STUDIO=icons) ---
	var png: Texture2D = ICONS.tex(kind)
	if png != null:
		ci.draw_texture_rect(png, Rect2(c - Vector2(r, r) * 1.25, Vector2(r, r) * 2.5), false)
		return
	# --- /core ---
	# --- combat: лук, стрела, верёвка, присед (combat_icons.gd) ---
	if preload("res://scripts/combat_icons.gd").icon(ci, kind, c, r):
		return
	# --- /combat ---
	match kind:
		"berry":
			ci.draw_colored_polygon(_ell(c + Vector2(-r * 0.35, -r * 0.55), r * 0.38, r * 0.16, -0.6), Color(0.3, 0.45, 0.2))
			ci.draw_colored_polygon(_ell(c + Vector2(r * 0.3, -r * 0.6), r * 0.34, r * 0.14, 0.5), Color(0.26, 0.4, 0.18))
			var bs := [Vector2(-0.3, 0.05), Vector2(0.28, 0.0), Vector2(0.0, -0.25), Vector2(-0.05, 0.35), Vector2(0.4, 0.4), Vector2(-0.42, 0.45)]
			for b: Vector2 in bs:
				var p := c + b * r
				ci.draw_circle(p + Vector2(2, 3), r * 0.26, Color(0, 0, 0, 0.2))
				ci.draw_circle(p, r * 0.26, Color(0.72, 0.1, 0.12))
				ci.draw_circle(p + Vector2(-r * 0.08, -r * 0.08), r * 0.08, Color(1, 0.75, 0.7, 0.85))
		"mushroom", "amanita":
			var red := kind == "amanita"
			ci.draw_colored_polygon(_ell(c + Vector2(0, r * 0.8), r * 0.6, r * 0.12, 0.0), Color(0, 0, 0, 0.18))
			var stem := PackedVector2Array([c + Vector2(-r * 0.2, -r * 0.05), c + Vector2(r * 0.2, -r * 0.05), c + Vector2(r * 0.27, r * 0.78), c + Vector2(-r * 0.27, r * 0.78)])
			ci.draw_colored_polygon(stem, Color(0.95, 0.92, 0.84))
			ci.draw_polyline(PackedVector2Array([stem[0], stem[3], stem[2], stem[1]]), Color(0.55, 0.45, 0.32), 2.0)
			var cap := PackedVector2Array()
			for i in 21:
				var a := PI + PI * i / 20.0
				cap.append(c + Vector2(cos(a) * r * 0.85, sin(a) * r * 0.75 + r * 0.05))
			ci.draw_colored_polygon(cap, Color(0.78, 0.12, 0.08) if red else Color(0.48, 0.3, 0.16))
			var cl := cap.duplicate()
			cl.append(cap[0])
			ci.draw_polyline(cl, Color(0.3, 0.12, 0.05), 2.5)
			ci.draw_colored_polygon(_ell(c + Vector2(-r * 0.3, -r * 0.4), r * 0.22, r * 0.1, -0.5), Color(1, 1, 1, 0.25))
			if red:
				for d: Vector2 in [Vector2(-0.4, -0.25), Vector2(0.0, -0.5), Vector2(0.38, -0.3), Vector2(-0.1, -0.15), Vector2(0.55, -0.05)]:
					ci.draw_circle(c + d * r, r * 0.08, Color(0.98, 0.96, 0.9))
		"twig":
			var sticks := [[Vector2(-0.9, 0.45), Vector2(0.85, -0.35), 0.11], [Vector2(-0.85, 0.15), Vector2(0.9, -0.05), 0.1], [Vector2(-0.8, -0.2), Vector2(0.8, 0.35), 0.09], [Vector2(-0.7, 0.55), Vector2(0.7, 0.1), 0.08]]
			for s: Array in sticks:
				var a: Vector2 = c + (s[0] as Vector2) * r
				var b: Vector2 = c + (s[1] as Vector2) * r
				ci.draw_line(a + Vector2(2, 3), b + Vector2(2, 3), Color(0, 0, 0, 0.2), r * float(s[2]) * 2.0)
				ci.draw_line(a, b, Color(0.42, 0.28, 0.16), r * float(s[2]) * 2.0)
				ci.draw_line(a, a.lerp(b, 0.6), Color(0.6, 0.45, 0.28), r * float(s[2]) * 0.6)
				var m := a.lerp(b, 0.7)
				ci.draw_line(m, m + Vector2(r * 0.15, -r * 0.3), Color(0.42, 0.28, 0.16), r * 0.06)
			ci.draw_line(c + Vector2(-r * 0.1, -r * 0.45), c + Vector2(r * 0.05, r * 0.6), Color(0.62, 0.52, 0.32), r * 0.12)
		"pebble":
			for s: Array in [[Vector2(-0.3, 0.2), 0.55, 0.38, 0.2, Color(0.55, 0.55, 0.52)], [Vector2(0.38, 0.3), 0.4, 0.3, -0.3, Color(0.46, 0.46, 0.44)], [Vector2(0.1, -0.3), 0.42, 0.32, 0.4, Color(0.62, 0.6, 0.56)]]:
				var p: Vector2 = c + (s[0] as Vector2) * r
				ci.draw_colored_polygon(_ell(p + Vector2(3, 4), r * float(s[1]), r * float(s[2]), float(s[3])), Color(0, 0, 0, 0.2))
				ci.draw_colored_polygon(_ell(p, r * float(s[1]), r * float(s[2]), float(s[3])), s[4])
				ci.draw_colored_polygon(_ell(p + Vector2(-r * 0.12, -r * 0.1), r * float(s[1]) * 0.45, r * float(s[2]) * 0.35, float(s[3])), Color(1, 1, 1, 0.22))
		"knife":
			_stroke(ci, c + Vector2(-r * 0.85, r * 0.6), c + Vector2(-r * 0.15, r * 0.05), r * 0.2, Color(0.5, 0.36, 0.22))
			for k in 4:
				var q := c + Vector2(-r * 0.6, r * 0.4).lerp(Vector2(-r * 0.25, r * 0.12), k / 3.0)
				ci.draw_line(q + Vector2(-r * 0.12, -r * 0.14), q + Vector2(r * 0.12, r * 0.14), Color(0.7, 0.6, 0.4), r * 0.07)
			_flint_icon(ci, PackedVector2Array([c + Vector2(-r * 0.2, r * 0.0), c + Vector2(r * 0.35, -r * 0.55), c + Vector2(r * 0.85, -r * 0.85), c + Vector2(r * 0.45, -r * 0.3), c + Vector2(-r * 0.05, r * 0.15)]))
		"axe":
			_stroke(ci, c + Vector2(-r * 0.7, r * 0.9), c + Vector2(r * 0.25, -r * 0.8), r * 0.17, Color(0.5, 0.36, 0.22))
			_flint_icon(ci, PackedVector2Array([c + Vector2(r * 0.0, -r * 0.55), c + Vector2(r * 0.9, -r * 0.2), c + Vector2(r * 0.95, -r * 0.65), c + Vector2(r * 0.65, -r * 0.95), c + Vector2(r * 0.05, -r * 0.75)]))
			for k in 3:
				var q := c + Vector2(r * 0.05, -r * 0.45 - k * r * 0.14)
				ci.draw_line(q + Vector2(-r * 0.18, r * 0.05), q + Vector2(r * 0.18, -r * 0.05), Color(0.7, 0.6, 0.4), r * 0.07)
		"spear":
			_stroke(ci, c + Vector2(-r * 1.0, r * 1.0), c + Vector2(r * 0.55, -r * 0.55), r * 0.1, Color(0.55, 0.42, 0.26))
			_stroke(ci, c + Vector2(r * 0.3, -r * 0.3), c + Vector2(r * 0.55, -r * 0.55), r * 0.11, Color(0.18, 0.12, 0.08))
			_flint_icon(ci, PackedVector2Array([c + Vector2(r * 0.45, -r * 0.6), c + Vector2(r * 0.7, -r * 0.55), c + Vector2(r * 1.0, -r * 1.0), c + Vector2(r * 0.55, -r * 0.7)]))
		"shovel":
			_stroke(ci, c + Vector2(-r * 0.8, -r * 0.8), c + Vector2(r * 0.25, r * 0.25), r * 0.12, Color(0.55, 0.42, 0.26))
			var bl := PackedVector2Array([c + Vector2(r * 0.1, r * 0.35), c + Vector2(r * 0.35, r * 0.1), c + Vector2(r * 0.95, r * 0.6), c + Vector2(r * 0.6, r * 0.95)])
			ci.draw_colored_polygon(bl, Color(0.66, 0.52, 0.34))
			ci.draw_polyline(bl + PackedVector2Array([bl[0]]), INK, 2.5)
		"flint":
			_flint_icon(ci, PackedVector2Array([c + Vector2(-r * 0.7, r * 0.3), c + Vector2(-r * 0.2, -r * 0.6), c + Vector2(r * 0.6, -r * 0.45), c + Vector2(r * 0.75, r * 0.2), c + Vector2(r * 0.1, r * 0.6)]))
		"bark":
			var rl := PackedVector2Array([c + Vector2(-r * 0.8, -r * 0.4), c + Vector2(r * 0.8, -r * 0.6), c + Vector2(r * 0.85, r * 0.35), c + Vector2(-r * 0.75, r * 0.55)])
			ci.draw_colored_polygon(rl, Color(0.92, 0.89, 0.8))
			for k in 6:
				var q := c + Vector2(-r * 0.6 + k * r * 0.24, -r * 0.3 + (k % 3) * r * 0.25)
				ci.draw_line(q, q + Vector2(r * 0.22, 0), Color(0.15, 0.12, 0.1), r * 0.07)
			ci.draw_polyline(rl + PackedVector2Array([rl[0]]), INK, 2.0)
		"fiber":
			for k in 7:
				var o := (k - 3) * r * 0.1
				ci.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.8, o), c + Vector2(-r * 0.2, o + r * 0.15), c + Vector2(r * 0.3, o - r * 0.1), c + Vector2(r * 0.85, o + r * 0.08)]), Color(0.66, 0.56, 0.36).darkened(k * 0.04), r * 0.08)
			ci.draw_line(c + Vector2(-r * 0.05, -r * 0.45), c + Vector2(-r * 0.05, r * 0.45), Color(0.42, 0.3, 0.18), r * 0.12)
		"branch":
			_stroke(ci, c + Vector2(-r * 1.0, r * 0.55), c + Vector2(r * 1.0, -r * 0.55), r * 0.13, Color(0.45, 0.34, 0.22))
			ci.draw_line(c + Vector2(r * 0.1, -r * 0.05), c + Vector2(r * 0.25, -r * 0.45), Color(0.45, 0.34, 0.22), r * 0.08)
		"spruce_twigs":
			for k in 3:
				var o := c + Vector2((k - 1) * r * 0.35, (k % 2) * r * 0.15)
				ci.draw_line(o + Vector2(0, r * 0.8), o + Vector2(0, -r * 0.8), Color(0.35, 0.25, 0.15), r * 0.07)
				for j in 6:
					var q := o + Vector2(0, -r * 0.6 + j * r * 0.25)
					ci.draw_line(q, q + Vector2(-r * 0.3, r * 0.18), Color(0.2, 0.34, 0.18), r * 0.1)
					ci.draw_line(q, q + Vector2(r * 0.3, r * 0.18), Color(0.24, 0.38, 0.2), r * 0.1)
		"log", "firewood", "plank":
			var n := 1 if kind == "log" else 3
			for k in n:
				var o := c + Vector2(0, (k - (n - 1) * 0.5) * r * 0.55)
				var th := r * (0.4 if kind == "log" else 0.22)
				ci.draw_rect(Rect2(o + Vector2(-r * 0.8, -th), Vector2(r * 1.5, th * 2.0)), Color(0.45, 0.33, 0.22) if kind != "plank" else Color(0.72, 0.58, 0.38))
				ci.draw_rect(Rect2(o + Vector2(-r * 0.8, -th), Vector2(r * 1.5, th * 2.0)), INK, false, 2.0)
				if kind != "plank":
					ci.draw_circle(o + Vector2(r * 0.7, 0), th, Color(0.88, 0.74, 0.5))
					ci.draw_arc(o + Vector2(r * 0.7, 0), th * 0.55, 0, TAU, 12, Color(0.6, 0.44, 0.26), 1.5)
					ci.draw_arc(o + Vector2(r * 0.7, 0), th, 0, TAU, 14, INK, 2.0)
		_:
			ci.draw_circle(c, r * 0.6, Color(0.5, 0.42, 0.3))


static func _stroke(ci: CanvasItem, a: Vector2, b: Vector2, w: float, col: Color) -> void:
	ci.draw_line(a + Vector2(2, 3), b + Vector2(2, 3), Color(0, 0, 0, 0.2), w * 2.0)
	ci.draw_line(a, b, col, w * 2.0)
	ci.draw_line(a, a.lerp(b, 0.7), col.lightened(0.18), w * 0.6)

## Кремень: гранёный многоугольник со сколами.
static func _flint_icon(ci: CanvasItem, pts: PackedVector2Array) -> void:
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= pts.size()
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		ci.draw_colored_polygon(PackedVector2Array([c, a, b]), Color(0.36, 0.33, 0.31).lerp(Color(0.6, 0.56, 0.48), float(i % 3) / 3.0))
	ci.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.15, 0.13, 0.12), 2.0)

static func _ell(c: Vector2, rx: float, ry: float, rot: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 18:
		var a := TAU * i / 18.0
		out.append(c + Vector2(cos(a) * rx, sin(a) * ry).rotated(rot))
	return out

# ---------- проверка: INV_SHOTS=папка — открыть, снять кадры, закрыть ----------
var _tt := 0.0
var _tn := 0
func _test_shots(delta: float) -> void:
	_tt += delta
	var dir := OS.get_environment("INV_SHOTS")
	var plan := [[4.0, "open"], [4.7, "s"], [5.4, "s"], [6.1, "s"], [6.8, "s"], [6.9, "craft"], [7.6, "s"], [7.7, "pack"], [8.6, "s"], [8.7, "sel"], [9.4, "s"], [9.5, "eat"], [10.1, "s"], [10.6, "close"], [11.3, "s"], [12.0, "s"], [12.6, "s"], [13.4, "s"], [15.0, "s"], [15.2, "quit"]]
	if _tn >= plan.size() or _tt < float(plan[_tn][0]):
		return
	var a: String = plan[_tn][1]
	_tn += 1
	match a:
		"open":
			main.inv.merge({"twig": 6, "pebble": 3, "berry": 4, "mushroom": 2, "amanita": 1, "flint": 3, "fiber": 3, "branch": 1, "bark": 2})
			open()
		"sel":
			sel = "berry"
		"craft":
			tab = 1
		"pack":
			tab = 0
		"eat":
			_use()
		"close":
			close()
		"quit":
			get_tree().quit()
		_:
			get_viewport().get_texture().get_image().save_png(dir + "/inv_%02d.png" % _tn)
			print("inv shot ", _tn, " stage ", main.hero.pack_stage)
