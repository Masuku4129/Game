extends Sprite2D
## Облако тумана: медленно дрейфует и заворачивается по границам карты.

var vel := Vector2(8.0, 0.0)
var area := Rect2()


func _process(delta: float) -> void:
	position += vel * delta
	if position.x > area.end.x + 400.0:
		position.x = area.position.x - 400.0
	elif position.x < area.position.x - 400.0:
		position.x = area.end.x + 400.0
