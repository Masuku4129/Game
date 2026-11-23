extends Sprite2D
## Одноразовый эффект из листа: проигрывает ряд кадров и удаляется.

var row := 0
var fps := 30.0
var _t := 0.0


func _process(delta: float) -> void:
	_t += delta * fps
	var c := int(_t)
	if c >= hframes:
		queue_free()
		return
	frame = row * hframes + c
