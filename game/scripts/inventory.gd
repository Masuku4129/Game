extends Control
## Инвентарь — берестяной короб. Открывается кнопкой «Рюкзак» (или I / Tab): герой снимает
## короб, ставит перед собой и открывает; тогда появляется лист с вещами. «Закрыть» — герой
## закрывает короб и закидывает его на плечи. Пока короб открыт, идти нельзя.
## Данные — main.inv (вид → количество); вес и вместимость считаются здесь.

const CAPACITY := 15.0
const COLS := 4
const ROWS := 3
const CELL := 136.0
const GAP := 10.0
const GRID := Vector2(36, 120)
const IT = preload("res://scripts/items.gd")
const ITEMS = IT.DEF

var main: Node3D
var sheet := Control.new()
var shown := 0.0        # 0..1 — видимость листа
var cam_k := 0.0        # 0..1 — камера наезжает на героя
var sel := ""
var btn_use: Button
var btn_drop: Button
var btn_close: Button
var _base_dist := 12.0
var _base_pitch := 45.0
var _base_yaw := 0.0
var _view_yaw := 0.0
var _active := false
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
	btn_use = _button("Съесть", Rect2(36, 640, 264, 106))
	btn_use.pressed.connect(_use)
	btn_drop = _button("Выбросить", Rect2(320, 640, 264, 106))
	btn_drop.pressed.connect(_drop)
	btn_close = _button("Закрыть", Rect2(670, 640, 274, 106))
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
	b.add_theme_font_size_override("font_size", 34)
	b.add_theme_color_override("font_color", Color(0.98, 0.93, 0.8))
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 0.9))
	b.add_theme_color_override("font_hover_color", Color(1, 0.97, 0.88))
	b.add_theme_color_override("font_disabled_color", Color(0.75, 0.68, 0.56, 0.7))
	var cols := {"normal": Color(0.46, 0.31, 0.18), "hover": Color(0.52, 0.35, 0.2), "pressed": Color(0.34, 0.22, 0.12), "disabled": Color(0.55, 0.47, 0.36)}
	for k: String in cols:
		var sb := StyleBoxFlat.new()
		sb.bg_color = cols[k]
		sb.set_corner_radius_all(18)
		sb.set_border_width_all(3)
		sb.border_color = Color(0.25, 0.15, 0.08)
		sb.shadow_color = Color(0, 0, 0, 0.25)
		sb.shadow_size = 4
		sb.shadow_offset = Vector2(2, 3)
		b.add_theme_stylebox_override(k, sb)
	sheet.add_child(b)
	return b

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
		btn_use.disabled = sel == "" or not ITEMS.get(sel, {}).has("eat")
		btn_drop.disabled = sel == ""
		sheet.queue_redraw()

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
	return out

func weight() -> float:
	var w := 0.0
	for k in main.inv.keys():
		w += float(ITEMS.get(k, {}).get("w", 0.3)) * int(main.inv[k])
	return w

func can_add(kind: String) -> bool:
	return weight() + float(ITEMS.get(kind, {}).get("w", 0.3)) <= CAPACITY + 0.001

func _name(kind: String) -> String:
	if ITEMS.has(kind):
		return ITEMS[kind]["name"]
	return String(main.PICK_NAME.get(kind, kind)).capitalize()

func _pick_default() -> void:
	var ks := _kinds()
	if not ks.has(sel):
		sel = ks[0] if not ks.is_empty() else ""

func _use() -> void:
	if sel == "" or not ITEMS.get(sel, {}).has("eat"):
		return
	var e: Array = ITEMS[sel]["eat"]
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

func _drop() -> void:
	if sel == "":
		return
	main._say("Выбросил: " + _name(sel).to_lower())
	_take(sel)

func _take(kind: String) -> void:
	main.inv[kind] = int(main.inv.get(kind, 0)) - 1
	if int(main.inv[kind]) <= 0:
		main.inv.erase(kind)
	_pick_default()

func _sheet_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = e.position - GRID
		var cx := int(p.x / (CELL + GAP))
		var cy := int(p.y / (CELL + GAP))
		if p.x >= 0 and p.y >= 0 and cx < COLS and cy < ROWS:
			var i := cy * COLS + cx
			var ks := _kinds()
			if i < ks.size():
				sel = ks[i]
				sheet.queue_redraw()

# ---------- рисование листа ----------

const INK := Color(0.24, 0.15, 0.08)
const PAPER := Color(0.88, 0.8, 0.62)

func _draw_sheet() -> void:
	var ci := sheet
	var f := ThemeDB.fallback_font
	var sz := Vector2(980, 782)
	# тень и лист с рваным краем, пятна краски
	var sh := PackedVector2Array()
	for p in _edge:
		sh.append(p + Vector2(8, 10))
	ci.draw_colored_polygon(sh, Color(0, 0, 0, 0.3))
	ci.draw_colored_polygon(_edge, PAPER)
	for b: Array in _blots:
		var d: float = b[2]
		ci.draw_circle(b[0], b[1], Color(0.5 + d, 0.36 + d, 0.18, 0.06))
	var ring := _edge.duplicate()
	ring.append(_edge[0])
	ci.draw_polyline(ring, Color(0.45, 0.32, 0.18), 5.0, true)
	# шапка — береста: светлая кора с тёмными чечевичками
	ci.draw_rect(Rect2(14, 14, sz.x - 28, 84), Color(0.93, 0.9, 0.82))
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	for i in 46:
		var x := rng.randf_range(20, sz.x - 60)
		var y := rng.randf_range(20, 90)
		ci.draw_line(Vector2(x, y), Vector2(x + rng.randf_range(14, 50), y + rng.randf_range(-1, 1)), Color(0.15, 0.12, 0.1, rng.randf_range(0.35, 0.8)), rng.randf_range(1.5, 3.5))
	ci.draw_rect(Rect2(14, 14, sz.x - 28, 84), Color(0.4, 0.3, 0.2), false, 3.0)
	ci.draw_string(f, Vector2(38, 72), "Короб", HORIZONTAL_ALIGNMENT_LEFT, -1, 48, Color(0, 0, 0, 0.25))
	ci.draw_string(f, Vector2(36, 70), "Короб", HORIZONTAL_ALIGNMENT_LEFT, -1, 48, INK)
	var ks := _kinds()
	ci.draw_string(f, Vector2(sz.x - 440, 68), "вещей: %d" % ks.size(), HORIZONTAL_ALIGNMENT_RIGHT, 400, 28, INK)
	# ячейки
	for i in COLS * ROWS:
		var r := Rect2(GRID + Vector2((i % COLS) * (CELL + GAP), (i / COLS) * (CELL + GAP)), Vector2(CELL, CELL))
		ci.draw_rect(r, Color(0.74, 0.63, 0.44, 0.75))
		ci.draw_rect(Rect2(r.position + Vector2(4, 4), r.size - Vector2(8, 8)), Color(0.8, 0.7, 0.5, 0.8))
		ci.draw_line(r.position, Vector2(r.end.x, r.position.y), Color(0.45, 0.33, 0.2, 0.8), 3.0)
		ci.draw_line(r.position, Vector2(r.position.x, r.end.y), Color(0.45, 0.33, 0.2, 0.8), 3.0)
		if i < ks.size():
			var k: String = ks[i]
			icon(ci, k, r.get_center() + Vector2(0, -8), 44.0)
			var n := "%d" % int(main.inv[k])
			ci.draw_string_outline(f, r.end - Vector2(64, 14), n, HORIZONTAL_ALIGNMENT_RIGHT, 56, 30, 6, PAPER)
			ci.draw_string(f, r.end - Vector2(64, 14), n, HORIZONTAL_ALIGNMENT_RIGHT, 56, 30, INK)
			if k == sel:
				ci.draw_rect(Rect2(r.position - Vector2(3, 3), r.size + Vector2(6, 6)), Color(0.72, 0.3, 0.12), false, 5.0)
	if ks.is_empty():
		ci.draw_string(f, GRID + Vector2(0, CELL * 1.5 + 10), "Пусто. Собирайте хворост, камни, ягоды и грибы.", HORIZONTAL_ALIGNMENT_LEFT, 580, 26, Color(INK, 0.7))
	# ноша
	var w := weight()
	var fr := clampf(w / CAPACITY, 0.0, 1.0)
	var br := Rect2(GRID.x, 572, COLS * CELL + (COLS - 1) * GAP, 40)
	ci.draw_rect(br, Color(0.6, 0.5, 0.34))
	var fc := Color(0.45, 0.6, 0.3).lerp(Color(0.8, 0.45, 0.15), smoothstep(0.5, 0.8, fr)).lerp(Color(0.75, 0.18, 0.12), smoothstep(0.85, 1.0, fr))
	ci.draw_rect(Rect2(br.position, Vector2(br.size.x * fr, br.size.y)), fc)
	ci.draw_rect(br, INK, false, 3.0)
	ci.draw_string_outline(f, br.position + Vector2(14, 30), "Ноша: %.1f / %d кг" % [w, int(CAPACITY)], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 6, Color(PAPER, 0.8))
	ci.draw_string(f, br.position + Vector2(14, 30), "Ноша: %.1f / %d кг" % [w, int(CAPACITY)], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, INK)
	# описание выбранного
	var dr := Rect2(640, 120, 304, 492)
	ci.draw_rect(dr, Color(0.8, 0.7, 0.5, 0.55))
	ci.draw_rect(dr, Color(0.45, 0.33, 0.2), false, 3.0)
	if sel != "" and main.inv.has(sel):
		ci.draw_circle(Vector2(dr.get_center().x, 210), 76, Color(0.74, 0.63, 0.44, 0.7))
		icon(ci, sel, Vector2(dr.get_center().x, 210), 62.0)
		ci.draw_string(f, Vector2(dr.position.x, 330), _name(sel), HORIZONTAL_ALIGNMENT_CENTER, dr.size.x, 38, INK)
		var iw := float(ITEMS.get(sel, {}).get("w", 0.3))
		ci.draw_string(f, Vector2(dr.position.x, 370), "%d шт. · %.2f кг" % [int(main.inv[sel]), iw * int(main.inv[sel])], HORIZONTAL_ALIGNMENT_CENTER, dr.size.x, 24, Color(INK, 0.75))
		var desc: String = ITEMS.get(sel, {}).get("desc", "")
		ci.draw_multiline_string(f, Vector2(dr.position.x + 18, 412), desc, HORIZONTAL_ALIGNMENT_LEFT, dr.size.x - 36, 25, 6, INK)
		if ITEMS.get(sel, {}).has("eat"):
			var e: Array = ITEMS[sel]["eat"]
			var eff := PackedStringArray()
			if float(e[0]) != 0.0:
				eff.append("сытость %+d%%" % int(round(float(e[0]) * 100.0)))
			if float(e[1]) != 0.0:
				eff.append("жажда %+d%%" % int(round(float(e[1]) * 100.0)))
			if float(e[2]) != 0.0:
				eff.append("здоровье %+d%%" % int(round(float(e[2]) * 100.0)))
			ci.draw_multiline_string(f, Vector2(dr.position.x + 18, 575), ", ".join(eff), HORIZONTAL_ALIGNMENT_LEFT, dr.size.x - 36, 22, 2, Color(0.5, 0.18, 0.1) if float(e[2]) < 0.0 else Color(0.25, 0.4, 0.15))
	else:
		ci.draw_string(f, Vector2(dr.position.x, 330), "Выберите вещь", HORIZONTAL_ALIGNMENT_CENTER, dr.size.x, 28, Color(INK, 0.6))

## Значок вещи: простой рисунок кистью (круги, эллипсы, штрихи).
static func icon(ci: CanvasItem, kind: String, c: Vector2, r: float) -> void:
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
		_:
			ci.draw_circle(c, r * 0.6, Color(0.5, 0.42, 0.3))

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
	var plan := [[4.0, "open"], [4.7, "s"], [5.4, "s"], [6.1, "s"], [6.8, "s"], [8.6, "s"], [8.7, "sel"], [9.4, "s"], [9.5, "eat"], [10.1, "s"], [10.6, "close"], [11.3, "s"], [12.0, "s"], [12.6, "s"], [13.4, "s"], [15.0, "s"], [15.2, "quit"]]
	if _tn >= plan.size() or _tt < float(plan[_tn][0]):
		return
	var a: String = plan[_tn][1]
	_tn += 1
	match a:
		"open":
			main.inv.merge({"twig": 6, "pebble": 3, "berry": 4, "mushroom": 2, "amanita": 1})
			open()
		"sel":
			sel = "berry"
		"eat":
			_use()
		"close":
			close()
		"quit":
			get_tree().quit()
		_:
			get_viewport().get_texture().get_image().save_png(dir + "/inv_%02d.png" % _tn)
			print("inv shot ", _tn, " stage ", main.hero.pack_stage)
