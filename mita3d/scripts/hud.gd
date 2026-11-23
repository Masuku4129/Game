class_name Hud
extends Control
## Сенсорный интерфейс: стик слева, кнопки справа, полоски HP/ульты, перезарядки.

var player: MitaPlayer
var stick_id := -1
var stick_c := Vector2.ZERO
var stick_v := Vector2.ZERO
var btn := {}          # имя -> [центр, радиус, touch_id]
var names := ["atk", "jump", "dash", "block", "s1", "s2", "s3", "s4"]
var labels := {"atk": "АТАКА", "jump": "ПРЫЖОК", "dash": "РЫВОК", "block": "БЛОК", "s1": "СЛЕДЫ", "s2": "ЛУЧ", "s3": "СТИЛЬ", "s4": "УЛЬТА"}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for n in names:
		btn[n] = [Vector2.ZERO, 50.0, -1]
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_layout()

func _layout() -> void:
	var s := get_viewport_rect().size
	stick_c = Vector2(160, s.y - 160)
	btn["atk"][0] = Vector2(s.x - 140, s.y - 150); btn["atk"][1] = 84.0
	btn["jump"][0] = Vector2(s.x - 290, s.y - 90); btn["jump"][1] = 56.0
	btn["dash"][0] = Vector2(s.x - 110, s.y - 320); btn["dash"][1] = 54.0
	btn["block"][0] = Vector2(s.x - 300, s.y - 230); btn["block"][1] = 54.0
	for i in 4:
		btn["s%d" % (i + 1)][0] = Vector2(s.x - 90 - i * 96, 62)
		btn["s%d" % (i + 1)][1] = 40.0

func _input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		if ev.pressed:
			_down(ev.index, ev.position)
		else:
			_up(ev.index)
	elif ev is InputEventScreenDrag:
		if ev.index == stick_id:
			_move_stick(ev.position)

func _down(id: int, p: Vector2) -> void:
	if p.x < get_viewport_rect().size.x * 0.4 and stick_id == -1 and p.y > 140:
		stick_id = id
		stick_c = p
		stick_v = Vector2.ZERO
		return
	for n in names:
		var b: Array = btn[n]
		if p.distance_to(b[0]) <= b[1] * 1.25 and b[2] == -1:
			b[2] = id
			press(n, true)
			return

func _up(id: int) -> void:
	if id == stick_id:
		stick_id = -1
		stick_v = Vector2.ZERO
		player.move_in = Vector2.ZERO
		_layout()
		return
	for n in names:
		var b: Array = btn[n]
		if b[2] == id:
			b[2] = -1
			press(n, false)

func _move_stick(p: Vector2) -> void:
	var d := p - stick_c
	if d.length() > 90.0:
		d = d.normalized() * 90.0
	stick_v = d / 90.0
	player.move_in = stick_v if stick_v.length() > 0.12 else Vector2.ZERO

func press(n: String, down: bool) -> void:
	match n:
		"atk":
			if down: player.press_attack()
		"jump":
			if down: player.press_jump()
		"dash":
			if down: player.press_dash()
		"block":
			player.press_block(down)
		"s1":
			if down: player.skill1()
		"s2":
			if down: player.skill2()
		"s3":
			if down: player.skill3()
		"s4":
			if down: player.skill4()

func _process(_dt: float) -> void:
	queue_redraw()

func _draw() -> void:
	if player == null:
		return
	var f := ThemeDB.fallback_font
	var s := get_viewport_rect().size
	# стик
	draw_circle(stick_c, 90.0, Color(0.5, 0.55, 1.0, 0.14))
	draw_arc(stick_c, 90.0, 0, TAU, 48, Color(0.6, 0.65, 1.0, 0.5), 3.0)
	draw_circle(stick_c + stick_v * 90.0, 38.0, Color(0.7, 0.75, 1.0, 0.55))
	for n in names:
		var b: Array = btn[n]
		var c: Vector2 = b[0]
		var r: float = b[1]
		var pr: bool = b[2] != -1
		var col := Color(0.55, 0.6, 1.0, 0.75 if pr else 0.32)
		draw_circle(c, r, Color(0.08, 0.08, 0.25, 0.5))
		draw_arc(c, r, 0, TAU, 40, col, 4.0)
		var cdv := 0.0
		if n == "s1": cdv = player.cd1 / 5.0
		if n == "s2": cdv = player.cd2 / 7.0
		if n == "dash": cdv = player.cd_dash / 0.45
		if cdv > 0.0:
			draw_arc(c, r - 6, -PI / 2, -PI / 2 + TAU * cdv, 32, Color(1, 1, 1, 0.5), 8.0)
		if n == "s4":
			var rdy := player.ult >= 100.0
			draw_arc(c, r - 6, -PI / 2, -PI / 2 + TAU * player.ult / 100.0, 32, Color(1.0, 0.85, 0.3) if rdy else Color(0.5, 0.8, 1.0), 8.0)
		var lab: String = labels[n]
		if n == "s3":
			lab = player.STY[player.style]["n"]
		var fs := 15 if r < 60 else 20
		var w := f.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, c + Vector2(-w / 2, fs * 0.35), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.9, 0.92, 1.0))
	# HP
	draw_rect(Rect2(24, 22, 300, 20), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(24, 22, 300 * clampf(player.hp / 100.0, 0.0, 1.0), 20), Color(0.9, 0.3, 0.5))
	draw_rect(Rect2(24, 48, 300, 10), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(24, 48, 300 * player.ult / 100.0, 10), Color(0.5, 0.8, 1.0))
	draw_string(f, Vector2(24, 82), "Стиль: %s" % player.STY[player.style]["n"], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, player.STY[player.style]["c"])
