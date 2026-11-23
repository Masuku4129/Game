extends Node2D
## Летящий шлейф от умения: белый серп мчится в сторону, режет врагов, останавливается об стену.

var vel := Vector2.RIGHT * 420.0   # направление и скорость
var dmg := 18.0
var _t := 0.0
var _life := 1.1
var _phase := 0.0            # фаза дуги
var _hit := {}               # словарь врагов чтобы не бить дважды
var _body: CharacterBody2D   # временное тело для движения


func _ready() -> void:
	z_index = 10
	# создаём движущееся тело и крепим к нему эту ноду
	_body = CharacterBody2D.new()
	_body.collision_layer = 0
	_body.collision_mask = 1          # реагирует только на StaticBody (стены)
	_body.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var sh := CollisionShape2D.new()
	var cs := CircleShape2D.new()
	cs.radius = 18.0
	sh.shape = cs
	_body.add_child(sh)
	# помещаем тело туда же где нода
	_body.global_position = global_position
	# добавляем тело как сиблинг
	get_parent().call_deferred("add_child", _body)


func _physics_process(delta: float) -> void:
	_t += delta
	_phase += delta * 14.0
	if _t >= _life:
		queue_free()
		if is_instance_valid(_body):
			_body.queue_free()
		return

	# движение через тело
	if is_instance_valid(_body) and _body.is_inside_tree():
		_body.velocity = vel
		_body.move_and_slide()
		global_position = _body.global_position
		# если ударились об стену — зависаем
		if _body.get_slide_collision_count() > 0:
			vel = Vector2.ZERO
			_life = minf(_life, _t + 0.25)   # быстро исчезаем после столкновения

	# урон по врагам
	for e in get_tree().get_nodes_in_group("enemy"):
		if e.dead or _hit.has(e):
			continue
		var d: float = global_position.distance_to(e.global_position)
		if d < 70.0:
			_hit[e] = true
			e.hurt(dmg, global_position - e.global_position, 180.0)

	queue_redraw()


func _draw() -> void:
	var fade := clampf(1.0 - (_t / _life), 0.0, 1.0)
	var grow := clampf(_t * 6.0, 0.0, 1.0)
	var r := 55.0 * grow
	var col := Color(1.0, 1.0, 1.0, fade * 0.9)
	var col2 := Color(0.8, 0.9, 1.0, fade * 0.5)
	# серп: дуга + усы
	var pts := PackedVector2Array()
	var arc := TAU * 0.6
	var n := 20
	for i in n + 1:
		var a := _phase + (float(i) / n - 0.5) * arc
		pts.append(Vector2(cos(a), sin(a)) * r)
	draw_polyline(pts, col, 5.0, true)
	# хвост свечение
	draw_circle(Vector2.ZERO, r * 0.28, col2)
