extends Control

var value := Vector2.ZERO
var active_touch := -1
var base := Vector2(155, 565)
var radius := 78.0
var knob := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_process(true)

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and active_touch == -1 and event.position.x < 350 and event.position.y > get_viewport_rect().size.y * 0.55:
			active_touch = event.index
			base = event.position
			knob = base
			value = Vector2.ZERO
			queue_redraw()
		elif not event.pressed and event.index == active_touch:
			active_touch = -1
			value = Vector2.ZERO
			knob = base
			queue_redraw()
	elif event is InputEventScreenDrag and event.index == active_touch:
		knob = event.position
		var offset = knob - base
		if offset.length() > radius:
			offset = offset.normalized() * radius
		knob = base + offset
		value = Vector2(offset.x / radius, offset.y / radius)
		queue_redraw()

func _draw() -> void:
	if active_touch == -1:
		draw_circle(Vector2(155,565), 68, Color(0.15,0.2,0.17,0.20))
		draw_arc(Vector2(155,565), 68, 0, TAU, 64, Color(0.8,0.85,0.8,0.25), 3.0)
	else:
		draw_circle(base, radius, Color(0.16,0.22,0.17,0.28))
		draw_arc(base, radius, 0, TAU, 64, Color(0.8,0.85,0.8,0.5), 3.0)
		draw_circle(knob, 28, Color(0.84,0.87,0.78,0.65))
