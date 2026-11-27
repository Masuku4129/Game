extends Control
## HUD: шкалы выживания на берестяной табличке, часы, строка сообщений; справа внизу —
## кнопки: «Действие» (main.act_btn), «Рюкзак», круглые кнопки инструмента по обстановке
## («Рубить», «Срезать», «Ударить»…), «Метнуть» и «Воткнуть» для копья, «Стрелять» для лука;
## внизу — пояс: нож, топор и лук за спиной (нажать — взять в руку, ещё раз — убрать на место),
## рядом — «рука» (что в руке; нажать — убрать). Слева у джойстика — «Присесть».
## Кнопки показывают только hero.tools.place_of(id): рука / пояс / спина / короб.
## Свои действия другие команды добавляют через hero.tools / world_tools (use_label/use).

const UI = preload("res://scripts/ui_palette.gd")
const INV = preload("res://scripts/inventory.gd")
const INK := UI.TEXT
const PAPER := UI.PANEL

var vals := [1.0, 0.85, 0.9, 0.8, 1.0]
var names := ["Здоровье", "Сытость", "Жажда", "Тепло", "Силы"]
var cols := [Color(0.7, 0.22, 0.18), Color(0.74, 0.6, 0.27), Color(0.33, 0.52, 0.72), Color(0.8, 0.45, 0.25), Color(0.45, 0.62, 0.36)]
var clock := ""
var info := ""
var bag_btn: BagButton
var main: Node3D
var use_btn: RoundBtn
var throw_btn: RoundBtn
var stick_btn: RoundBtn
var belt_btns := {}
# --- combat: рука, присед ---
var hand_btn: RoundBtn
var crouch_btn: RoundBtn
# --- /combat ---

## Кнопка короба: нарисованный берестяной короб с лямками и подписью.
class BagButton extends Button:
	const UI = preload("res://scripts/ui_palette.gd")
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
		# короб: корпус, крышка со скаткой, лямки
		var w := r * 0.82
		var h := r * 0.86
		var o := c + Vector2(0, -r * 0.08)
		var body := Rect2(o.x - w * 0.5, o.y - h * 0.35, w, h * 0.8)
		draw_rect(body, Color(0.82, 0.68, 0.45))
		for i in 4:
			var y := body.position.y + body.size.y * (0.2 + i * 0.2)
			draw_line(Vector2(body.position.x + 3, y), Vector2(body.end.x - 3, y), Color(0.6, 0.46, 0.28), 2.0)
		draw_rect(body, Color(0.35, 0.23, 0.13), false, 3.0)
		draw_rect(Rect2(o.x - w * 0.56, o.y - h * 0.5, w * 1.12, h * 0.17), Color(0.62, 0.47, 0.29))
		draw_rect(Rect2(o.x - w * 0.56, o.y - h * 0.5, w * 1.12, h * 0.17), Color(0.35, 0.23, 0.13), false, 2.5)
		var rr := Rect2(o.x - w * 0.6, o.y - h * 0.72, w * 1.2, h * 0.22)
		draw_rect(rr, Color(0.55, 0.2, 0.15))
		draw_circle(Vector2(rr.position.x, rr.get_center().y), rr.size.y * 0.5, Color(0.45, 0.16, 0.12))
		draw_circle(Vector2(rr.end.x, rr.get_center().y), rr.size.y * 0.5, Color(0.62, 0.25, 0.18))
		for sx in [-0.25, 0.25]:
			draw_line(Vector2(o.x + w * sx, body.position.y - 2), Vector2(o.x + w * sx, body.end.y + 2), Color(0.25, 0.15, 0.08), 4.0)
		var f := ThemeDB.fallback_font
		draw_string_outline(f, Vector2(c.x - 60, c.y + r * 0.8), "Рюкзак", HORIZONTAL_ALIGNMENT_CENTER, 120, 20, 5, Color(0.2, 0.12, 0.06))
		draw_string(f, Vector2(c.x - 60, c.y + r * 0.8), "Рюкзак", HORIZONTAL_ALIGNMENT_CENTER, 120, 20, Color(1, 0.95, 0.85))

## Круглая кнопка с нарисованным значком вещи и подписью под ней.
class RoundBtn extends Button:
	const UI = preload("res://scripts/ui_palette.gd")
	var icon_id := ""
	var caption := ""
	var hot := false        # выделена (вещь в руке)
	var dim := false        # вещь в коробе (не на поясе и не за спиной)
	func _ready() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
	func _draw() -> void:
		var c := Vector2(size.x * 0.5, size.x * 0.5)
		var r := size.x * 0.5 - 4.0
		var dn := is_pressed() and is_hovered()
		draw_circle(c + Vector2(3, 4), r, Color(0, 0, 0, 0.3))
		draw_circle(c, r, UI.PANEL_SOFT if not dn else UI.PANEL_HOVER)
		draw_circle(c, r - 7.0, UI.ACCENT_HI if hot else UI.PANEL_SOFT if dim else UI.PANEL)
		draw_arc(c, r - 3.0, 0.0, TAU, 48, UI.ACCENT if not hot else UI.ACCENT_HI, 4.0 if not hot else 6.0, true)
		if icon_id != "":
			INV.icon(self, icon_id, c, r * 0.55)
		if caption != "":
			var f := ThemeDB.fallback_font
			var fs := 22 if caption.length() < 12 else 19
			draw_string_outline(f, Vector2(c.x - 110, size.y - 4), caption, HORIZONTAL_ALIGNMENT_CENTER, 220, fs, 6, Color(0.18, 0.11, 0.06, 0.9))
			draw_string(f, Vector2(c.x - 110, size.y - 4), caption, HORIZONTAL_ALIGNMENT_CENTER, 220, fs, Color(1, 0.95, 0.85))

func _anchor_br(c: Control, l: float, t: float, w: float, h: float) -> void:
	c.anchor_left = 1.0
	c.anchor_right = 1.0
	c.anchor_top = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = l
	c.offset_right = l + w
	c.offset_top = t
	c.offset_bottom = t + h

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	bag_btn = BagButton.new()
	_anchor_br(bag_btn, -236.0, -400.0, 150.0, 150.0)
	add_child(bag_btn)

func _round(id: String, cap: String, l: float, t: float, sz: float) -> RoundBtn:
	var b := RoundBtn.new()
	b.icon_id = id
	b.caption = cap
	_anchor_br(b, l, t, sz, sz + 30.0)
	b.visible = false
	add_child(b)
	return b

## Подключить кнопки к миру (из main после создания героя и кнопки «Действие»).
func setup(m: Node3D) -> void:
	main = m
	# основная кнопка «Действие» в стиле листа
	if main.act_btn != null:
		INV.style_button(main.act_btn, 34)
	use_btn = _round("", "", -440.0, -270.0, 150.0)
	use_btn.pressed.connect(func() -> void: main.hero.tools.use())
	throw_btn = _round("spear", "Метнуть", -400.0, -470.0, 120.0)
	# --- combat: «Метнуть» / «Стрелять» — прицел (combat.gd) ---
	throw_btn.pressed.connect(_aim_pressed)
	stick_btn = _round("spear", "Воткнуть", -560.0, -470.0, 120.0)
	stick_btn.pressed.connect(func() -> void: main.hero.tools.stick())
	var x := -898.0
	# --- combat: «рука» и пояс: нож, топор, лук ---
	hand_btn = _round("", "Убрать", x, -150.0, 104.0)
	hand_btn.hot = true
	hand_btn.pressed.connect(func() -> void: main.hero.tools.holster())
	x += 118.0
	for id in ["knife", "axe", "bow"]:
		var b := _round(id, IT_name(id), x, -150.0, 104.0)
		b.pressed.connect(_belt_pressed.bind(id))
		belt_btns[id] = b
		x += 118.0
	crouch_btn = _round("crouch", "Присесть", 0.0, 0.0, 104.0)
	crouch_btn.anchor_left = 0.0
	crouch_btn.anchor_right = 0.0
	crouch_btn.offset_left = 420.0
	crouch_btn.offset_right = 524.0
	crouch_btn.offset_top = -150.0
	crouch_btn.offset_bottom = -16.0
	crouch_btn.pressed.connect(func() -> void: main.hero.toggle_crouch())
	# --- /combat ---

func IT_name(id: String) -> String:
	return String(INV.ITEMS.get(id, {}).get("name", id))

func _belt_pressed(id: String) -> void:
	main.hero.tools.toggle(id)
	_ui_t = 0.0

# --- combat: прицел копья или лука ---
func _aim_pressed() -> void:
	if main.get("combat") != null and main.combat != null:
		main.combat.begin_aim("bow" if main.hero.tools.held == "bow" else "spear")
	else:
		main.hero.tools.throw()
# --- /combat ---

var _ui_t := 0.0
func _process(delta: float) -> void:
	if main == null or main.hero == null or main.hero.tools == null:
		return
	_ui_t -= delta
	if _ui_t > 0.0:
		return
	_ui_t = 0.15
	var hero: Node3D = main.hero
	var t: Node = hero.tools
	var free: bool = hero.state == "walk" and not main.inventory.is_open() and hero.pack_stage == ""
	var ul: String = t.use_label() if free else ""
	use_btn.visible = ul != ""
	if ul != "":
		use_btn.caption = ul
		use_btn.icon_id = t.held if t.held != "" else "fiber"
		use_btn.queue_redraw()
	# --- combat: «Метнуть» для копья, «Стрелять» для лука ---
	var bow: bool = t.held == "bow"
	throw_btn.visible = free and (t.can_shoot() if bow else t.can_throw())
	if throw_btn.visible and throw_btn.icon_id != t.held:
		throw_btn.icon_id = t.held
		throw_btn.caption = "Стрелять" if bow else "Метнуть"
		throw_btn.queue_redraw()
	stick_btn.visible = free and t.can_stick()
	if stick_btn.visible and stick_btn.icon_id != t.held:
		stick_btn.icon_id = t.held
		stick_btn.queue_redraw()
	# --- combat: кнопки — по месту вещи (рука / пояс / спина / короб) ---
	for id: String in belt_btns:
		var b: RoundBtn = belt_btns[id]
		var pl: String = t.place_of(id)
		b.visible = free and pl != ""
		var h: bool = pl == "hand"
		var dm: bool = pl == "pack"
		if b.hot != h or b.dim != dm:
			b.hot = h
			b.dim = dm
			b.caption = ("Убрать" if h else IT_name(id))
			b.queue_redraw()
	var hid: String = t.held
	hand_btn.visible = free and hid != "" and hid != "log" and not t.is_long(hid)
	if hand_btn.visible and hand_btn.icon_id != hid:
		hand_btn.icon_id = hid
		hand_btn.queue_redraw()
	crouch_btn.visible = free and (hero.crouch or t.can_crouch())
	var cc := "Встать" if hero.crouch else "Присесть"
	if crouch_btn.caption != cc or crouch_btn.hot != hero.crouch:
		crouch_btn.caption = cc
		crouch_btn.hot = hero.crouch
		crouch_btn.queue_redraw()
	# --- /combat ---

func set_state(v: Array, text: String, inf: String) -> void:
	vals = v
	clock = text
	info = inf
	queue_redraw()

## Берестяная табличка: светлая подложка, неровная тёмная рамка.
func _plate(r: Rect2) -> void:
	draw_rect(Rect2(r.position + Vector2(4, 5), r.size), Color(0, 0, 0, 0.25))
	draw_rect(r, UI.PANEL_SOFT)
	draw_rect(Rect2(r.position + Vector2(5, 5), r.size - Vector2(10, 10)), UI.PANEL)
	draw_rect(r, UI.BORDER, false, 2.0)

func _draw() -> void:
	var f := ThemeDB.fallback_font
	var pr := Rect2(18, 16, 330, 30.0 + vals.size() * 34.0)
	_plate(pr)
	for i in vals.size():
		var y := pr.position.y + 22.0 + i * 34.0
		draw_string(f, Vector2(32, y + 7), names[i], HORIZONTAL_ALIGNMENT_LEFT, 120, 20, INK)
		var br := Rect2(150, y - 6, 180, 14)
		draw_rect(br, UI.BAR_BG)
		var v := clampf(vals[i], 0.0, 1.0)
		var c: Color = cols[i]
		if v < 0.25:
			c = c.lerp(UI.DANGER, 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008))
		draw_rect(Rect2(br.position, Vector2(br.size.x * v, br.size.y)), c)
		draw_rect(br, UI.BORDER, false, 1.5)
	if info != "":
		var w := minf(f.get_string_size(info, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 36.0, 900.0)
		var ir := Rect2(18, pr.end.y + 10, w, 40)
		_plate(ir)
		draw_string(f, Vector2(36, ir.position.y + 28), info, HORIZONTAL_ALIGNMENT_LEFT, 860, 22, INK)
	if clock != "":
		var cw := f.get_string_size(clock, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x + 40.0
		var cr := Rect2(size.x - cw - 20.0, 16, cw, 44)
		_plate(cr)
		draw_string(f, Vector2(cr.position.x + 20, cr.position.y + 31), clock, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, INK)
