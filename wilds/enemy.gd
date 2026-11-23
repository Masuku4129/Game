extends CharacterBody2D
## Враг: ch (ближний), sh (стрелок), hd (босс-гончая), wr (призрак-маг)

const DATA = preload("res://art/valley/art_data.gd").DATA
const Y_SCALE    := 0.75
const STRIP_FRAMES := 8

var kind    := "ch"
var hp      := 60.0
var max_hp  := 60.0
var speed   := 105.0
var sc      := 0.82
var aggro   := 700.0
var dmg     := 10.0
var reach   := 120.0
var dead    := false
var player

var _state      := "idle"
var _t          := 0.0
var _cd         := 0.0        # кулдаун атаки
var _atk_cd     := 0.0        # доп. кд для босса
var _kb         := Vector2.ZERO
var _wt         := randf() * 6.0
var _face       := 1.0
var _view       := "side"
var _spr        : Sprite2D
var _sh         : Sprite2D    # тень
var _hp_bar     : Node2D      # HP-бар (для всех, кроме hd)
var _flash      := 0.0
var _hit_done   := false
var _tex        := {}

# boss-only
var _boss_phase := 0          # 0=нормальный, 1=бешеный (<50% hp)
var _leap_target := Vector2.ZERO


# ------------------------------------------------------------------ setup
func setup(k: String) -> void:
	kind = k
	match k:
		"ch": hp = 60.0;  speed = 115.0; sc = 0.82; dmg = 9.0;  reach = 115.0
		"sh": hp = 38.0;  speed = 95.0;  sc = 0.78; dmg = 8.0;  reach = 520.0
		"hd": hp = 900.0; speed = 190.0; sc = 1.35; dmg = 22.0; reach = 260.0; aggro = 1500.0
		"wr": hp = 50.0;  speed = 80.0;  sc = 0.80; dmg = 12.0; reach = 450.0; aggro = 600.0
	max_hp = hp


# ------------------------------------------------------------------ _ready
func _ready() -> void:
	collision_layer = 2
	collision_mask  = 1
	motion_mode     = CharacterBody2D.MOTION_MODE_FLOATING
	add_to_group("enemy")

	# коллизия
	var c := CollisionShape2D.new()
	var s := CircleShape2D.new()
	s.radius = 70.0 if kind == "hd" else (28.0 if kind == "wr" else 22.0)
	c.shape  = s
	add_child(c)

	# тень
	var g  := Gradient.new()
	g.set_color(0, Color(0.06, 0.04, 0.14, 0.5))
	g.set_color(1, Color(0.06, 0.04, 0.14, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g; gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5); gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128; gt.height = 128
	_sh = Sprite2D.new()
	_sh.texture = gt
	var sw := (420.0 if kind == "hd" else (110.0 if kind == "wr" else 90.0))
	_sh.scale = Vector2(sw / 64.0, sw * 0.3 / 64.0)
	add_child(_sh)

	# спрайт
	_spr = Sprite2D.new()
	_spr.centered = false
	_spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_spr)

	# HP-бар (не для hd — у него отдельный большой бар в HUD)
	if kind != "hd":
		_hp_bar = Node2D.new()
		_hp_bar.z_index = 10
		add_child(_hp_bar)

	# загрузка текстур
	for n in ["side","front","back","windup","strike","hit","crouch","death",
			"charge","shoot","recoil","run","run2","run3","leap","paw","howl","walk",
			"spin","claw","cast","throw"]:
		var p := "res://art/en/%s_%s.png" % [kind, n]
		if ResourceLoader.exists(p):
			_tex[n] = load(p)

	var sp := "walk" if _tex.has("walk") else ("run" if _tex.has("run") else "side")
	_pose(sp)


# ------------------------------------------------------------------ _pose
func _pose(n: String, frame: int = 0) -> void:
	var key := "en_%s_%s" % [kind, n]
	if not _tex.has(n) or not DATA.has(key):
		return
	var d: Array    = DATA[key]
	var t: Texture2D = _tex[n]
	if _spr.texture != t:
		_spr.texture = t
		_spr.hframes = STRIP_FRAMES if t.get_width() > t.get_height() * 2 else 1
		_spr.vframes = 1
	_spr.frame  = clampi(frame, 0, _spr.hframes - 1)
	_spr.offset = Vector2(-d[0], -d[1])


# ------------------------------------------------------------------ hurt
func hurt(amount: float, from_dir: Vector2, knock := 260.0) -> void:
	if dead:
		return
	hp    -= amount
	_flash = 0.14
	_kb    = from_dir.normalized() * knock * (0.15 if kind == "hd" else 1.0)
	# звук попадания
	for snd in get_tree().get_nodes_in_group("sound"):
		if snd.has_method("play_sound"):
			snd.play_sound("hit")
			break

	# фаза бешенства bosss
	if kind == "hd" and _boss_phase == 0 and hp < max_hp * 0.5:
		_boss_phase = 1
		speed      *= 1.3
		dmg        *= 1.4
		_notify_rage()
		for snd in get_tree().get_nodes_in_group("sound"):
			if snd.has_method("play_sound"):
				snd.play_sound("boss_rage")
				break

	if hp <= 0.0:
		dead            = true
		_t              = 0.0
		collision_layer = 0
		_pose("death" if _tex.has("death") else "side", 0)
		var main = get_tree().current_scene
		if main.has_method("on_kill"):
			main.on_kill(kind)
	elif kind != "hd":
		_state    = "hit"
		_t        = 0.0
		_hit_done = true
		_pose("hit" if _tex.has("hit") else "side")


func _notify_rage() -> void:
	for n in get_tree().get_nodes_in_group("hud"):
		if n.has_method("show_message"):
			n.show_message("Гончая разъярена!")


# ------------------------------------------------------------------ главный цикл
func _physics_process(delta: float) -> void:
	_wt   += delta
	_flash = maxf(_flash - delta, 0.0)
	_spr.modulate = Color(1.7, 1.45, 1.9) if _flash > 0.0 else Color.WHITE

	# смерть
	if dead:
		_t += delta
		if _spr.hframes > 1:
			_spr.frame = clampi(int(_t / 0.8 * STRIP_FRAMES), 0, STRIP_FRAMES - 1)
		_spr.modulate.a = clampf(1.0 - (_t - 0.6) / 0.8, 0.0, 1.0)
		_spr.scale      = Vector2(_face * sc, sc)
		_sh.modulate.a  = _spr.modulate.a
		if _t > 1.5:
			queue_free()
		return

	if player == null:
		var ps := get_tree().get_nodes_in_group("player")
		if ps.size() > 0:
			player = ps[0]
		return

	_t  += delta
	_cd  = maxf(_cd - delta, 0.0)
	_atk_cd = maxf(_atk_cd - delta, 0.0)

	var to: Vector2  = player.global_position - global_position
	var dist := Vector2(to.x, to.y / Y_SCALE).length()
	var dir  := to.normalized()
	var move := Vector2.ZERO

	match _state:
		"idle":
			if dist < aggro:
				_state = "chase"

		"chase":
			move = _chase(dist, dir, to)

		# --- универсальный замах ---
		"windup":
			_face = 1.0 if to.x >= 0.0 else -1.0
			var wu := _windup_duration()
			var wf := int(_t / wu * STRIP_FRAMES) % STRIP_FRAMES
			if kind == "wr":
				_pose("cast", wf)
			elif kind == "hd":
				_pose("windup" if _tex.has("windup") else "walk", wf)
			if _t > wu:
				_do_attack(dir)

		# --- удар ch / sh ---
		"strike":
			if kind == "ch":
				move = dir * 330.0
				if not _hit_done and _t > 0.06 and dist < reach + 40.0:
					_hit_done = true
					player.hurt(dmg, global_position)
			elif kind == "wr":
				_pose("throw", int(_t / 0.4 * STRIP_FRAMES) % STRIP_FRAMES)
			if _t > _strike_duration():
				_state = "chase"
				_cd    = _attack_cd()
				_t     = 0.0

		# --- спин ch ---
		"spin":
			move = dir * 200.0
			var sf := int(_t * 12.0) % STRIP_FRAMES
			_pose("spin", sf)
			# хит всё вокруг
			if _t > 0.08 and not _hit_done:
				if dist < reach + 60.0:
					_hit_done = true
					player.hurt(dmg * 1.3, global_position)
			if _t > 0.55:
				_state = "chase"
				_cd    = 2.0
				_t     = 0.0

		# --- прыжок hd ---
		"leap":
			var ldist := (_leap_target - global_position)
			if ldist.length() > 60.0:
				var ldir := ldist.normalized()
				move = ldir * 900.0
				_pose("leap", int(_t * 10.0) % STRIP_FRAMES)
			else:
				# приземление
				_state    = "paw"
				_t        = 0.0
				_hit_done = false
				_pose("paw", 0)

		# --- удар лапой hd ---
		"paw":
			var pf := int(_t / 0.6 * STRIP_FRAMES) % STRIP_FRAMES
			_pose("paw", pf)
			if not _hit_done and _t > 0.15 and dist < reach + 80.0:
				_hit_done = true
				player.hurt(dmg * 1.5, global_position, 400.0)
			if _t > 0.6:
				_state = "chase"
				_cd    = (1.0 if _boss_phase == 1 else 1.8)
				_t     = 0.0

		# --- вой hd (шокволна) ---
		"howl":
			var hf := int(_t / 0.9 * STRIP_FRAMES) % STRIP_FRAMES
			_pose("howl" if _tex.has("howl") else "front", hf)
			# шокволна на пике воя
			if not _hit_done and _t > 0.45:
				_hit_done = true
				_do_shockwave()
			if _t > 0.9:
				_state  = "chase"
				_atk_cd = 6.0
				_t      = 0.0

		# --- отлёт от удара ---
		"hit":
			if _t > 0.28:
				_state = "chase"
				_t     = 0.0

	velocity = move + _kb
	_kb      = _kb.move_toward(Vector2.ZERO, 900.0 * delta)
	velocity.y *= Y_SCALE
	move_and_slide()
	_animate(move)
	_draw_hp_bar()


# ------------------------------------------------------------------ вспомогательные
func _windup_duration() -> float:
	match kind:
		"wr": return 0.55
		"hd": return 0.35
		_:    return 0.42

func _strike_duration() -> float:
	match kind:
		"wr": return 0.4
		"ch": return 0.22
		_:    return 0.3

func _attack_cd() -> float:
	match kind:
		"wr": return 2.8
		"ch": return 1.4
		"sh": return 2.2
		_:    return 1.5


func _do_attack(dir: Vector2) -> void:
	_state    = "strike"
	_t        = 0.0
	_hit_done = false
	match kind:
		"sh":
			_pose("shoot")
			_fire(dir)
		"wr":
			_pose("throw", 0)
			_fire_orb(dir)
		_:
			_pose("strike" if _tex.has("strike") else "side")


func _do_shockwave() -> void:
	# рисуем волну через VFX и наносим урон если игрок рядом
	var pdist := (player.global_position - global_position).length()
	if pdist < 350.0:
		var knock_dir := (player.global_position - global_position).normalized()
		player.hurt(dmg * 0.8, global_position, 500.0)
	# визуальная волна
	var ring := Node2D.new()
	ring.script = preload("res://slash_fx.gd") if ResourceLoader.exists("res://slash_fx.gd") else null
	# простая расширяющаяся окружность через code
	var vfx := _make_ring_vfx()
	get_parent().add_child(vfx)
	vfx.global_position = global_position


func _make_ring_vfx() -> Node2D:
	var n := Node2D.new()
	var elapsed := [0.0]
	# используем скриптовый объект для анимации
	var sc_obj := GDScript.new()
	sc_obj.source_code = """
extends Node2D
var _t := 0.0
func _process(d):
	_t += d
	queue_redraw()
	if _t > 0.6: queue_free()
func _draw():
	var r = _t / 0.6 * 350.0
	var a = 1.0 - _t / 0.6
	draw_arc(Vector2.ZERO, r, 0, TAU, 48, Color(0.7,0.4,1.0,a), 4.0)
"""
	sc_obj.reload()
	n.set_script(sc_obj)
	return n


# ------------------------------------------------------------------ chase
func _chase(dist: float, dir: Vector2, to: Vector2) -> Vector2:
	match kind:
		"sh":
			if dist < reach and _cd <= 0.0:
				_state = "windup"; _t = 0.0
				_pose("charge" if _tex.has("charge") else "side")
				return Vector2.ZERO
			if dist < 330.0: return -dir * speed
			if dist > 480.0: return dir * speed
			return Vector2(-dir.y, dir.x) * speed * 0.5

		"wr":
			if dist < reach and _cd <= 0.0:
				_state = "windup"; _t = 0.0
				_face  = 1.0 if to.x >= 0.0 else -1.0
				_pose("cast", 0)
				return Vector2.ZERO
			if dist < 200.0:  return -dir * speed
			if dist > reach * 0.8: return dir * speed * 0.6
			return Vector2(-dir.y, dir.x) * speed * 0.4

		"hd":
			return _chase_hd(dist, dir, to)

		_:  # ch
			# иногда делает спин вместо обычного удара
			if dist < reach and _cd <= 0.0:
				if _tex.has("spin") and randf() < 0.3:
					_state    = "spin"; _t = 0.0
					_hit_done = false
					_pose("spin", 0)
					_cd = 2.5
					return Vector2.ZERO
				_state = "windup"; _t = 0.0
				_pose("windup" if _tex.has("windup") else "side")
				return Vector2.ZERO
			return dir * speed if dist > reach * 0.8 else Vector2.ZERO


func _chase_hd(dist: float, dir: Vector2, to: Vector2) -> Vector2:
	# фаза бешенства: чаще атакует
	var leap_cd  := 2.5 if _boss_phase == 1 else 4.0
	var howl_cd  := 5.0 if _boss_phase == 1 else 8.0

	# вой (если давно не выл и игрок в радиусе)
	if _atk_cd <= 0.0 and dist < 500.0 and _tex.has("howl"):
		_state    = "howl"; _t = 0.0
		_hit_done = false
		_pose("howl" if _tex.has("howl") else "front", 0)
		_atk_cd   = howl_cd
		return Vector2.ZERO

	# прыжок-атака
	if _cd <= 0.0 and dist > 180.0 and dist < 700.0:
		_state       = "leap"; _t = 0.0
		_leap_target = player.global_position
		_pose("leap", 0)
		_cd = leap_cd
		return Vector2.ZERO

	# удар лапой вблизи
	if _cd <= 0.0 and dist < reach:
		_state    = "paw"; _t = 0.0
		_hit_done = false
		_pose("paw", 0)
		_cd = 1.5
		return Vector2.ZERO

	# бег к игроку
	_face = 1.0 if to.x >= 0.0 else -1.0
	return dir * speed


# ------------------------------------------------------------------ снаряды
func _fire(dir: Vector2) -> void:
	var p = preload("res://orb.gd").new()
	p.position = global_position + Vector2(_face * 28.0, -85.0)
	p.vel = (player.global_position + Vector2(0, -50.0) - p.position).normalized() * 300.0
	p.dmg = dmg
	get_parent().add_child(p)


func _fire_orb(dir: Vector2) -> void:
	for i in 2:
		var p = preload("res://orb.gd").new()
		p.position = global_position + Vector2(_face * (20.0 + i * 20.0), -110.0 + i * 20.0)
		var base_d := (player.global_position + Vector2(0, -50.0) - p.position).normalized()
		p.vel = base_d.rotated((-0.15 + i * 0.3)) * 260.0
		p.dmg = dmg
		get_parent().add_child(p)


# ------------------------------------------------------------------ анимация
func _animate(move: Vector2) -> void:
	var sp         := move.length() > 5.0
	var run_frame  := int(_wt * 8.0) % STRIP_FRAMES
	var walk_frame := int(_wt * 6.0) % STRIP_FRAMES

	# во время специальных состояний не перебиваем позу
	if _state in ["windup","strike","spin","leap","paw","howl"]:
		pass
	elif _state == "chase" or _state == "idle":
		if sp:
			if absf(move.x) > absf(move.y) * 1.2:
				_face = 1.0 if move.x > 0 else -1.0
				if kind == "wr":
					_view = "side" if _tex.has("side") else "walk"
					_pose(_view, walk_frame)
				elif _tex.has("run"):
					_view = "run"
					_pose("run", run_frame)
				else:
					_view = "side"
					_pose("side", run_frame)
			elif move.y > 0:
				_view = "front"; _pose("front", walk_frame)
			else:
				_view = "back"
				_pose("back" if _tex.has("back") else "side", walk_frame)
		else:
			if _view in ["run","run2","run3"]:
				_view = "side" if _tex.has("side") else "walk"
			_pose(_view, int(_wt * 4.0) % STRIP_FRAMES)

	var sx := _face if (_view in ["side","run","run2","run3","walk"]) else 1.0
	var tilt   := sin(_wt * 9.0) * 0.055 * sx if sp else 0.0
	var squash := 1.0 + (sin(_wt * 18.0) * 0.03 if sp else sin(_wt * 2.5) * 0.012)
	var bob    := absf(sin(_wt * 9.0)) * 4.0 if sp else sin(_wt * 2.0) * 1.5
	_spr.scale      = Vector2(sx * sc / squash, sc * squash)
	_spr.rotation   = tilt
	_spr.position.y = -bob


# ------------------------------------------------------------------ HP-бар
func _draw_hp_bar() -> void:
	if _hp_bar == null or dead:
		return
	_hp_bar.queue_redraw()
	# высота над спрайтом
	var bar_y := -(_spr.offset.y * sc + 18.0)
	_hp_bar.position = Vector2(0.0, bar_y)
	# рисуем через скрипт — создаём один раз
	if not _hp_bar.has_method("_draw"):
		var s := GDScript.new()
		s.source_code = """
extends Node2D
var hp_frac := 1.0
func _draw():
	var w := 36.0
	var h := 4.0
	draw_rect(Rect2(-w*0.5, -h*0.5, w, h), Color(0.1,0.1,0.1,0.7))
	var col = Color(0.2,0.9,0.3) if hp_frac > 0.5 else (Color(0.95,0.7,0.1) if hp_frac > 0.25 else Color(0.95,0.2,0.1))
	draw_rect(Rect2(-w*0.5, -h*0.5, w*hp_frac, h), col)
"""
		s.reload()
		_hp_bar.set_script(s)
	_hp_bar.set("hp_frac", clampf(hp / max_hp, 0.0, 1.0))
