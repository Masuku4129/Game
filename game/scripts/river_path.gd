extends RefCounted
## Ось реки: единый детерминированный меандр, зависящий от seed мира.
## Все подсистемы передают один map_seed, чтобы русло, рыба и плотины совпадали.

static func _phase(seed: int) -> float:
	return float(posmod(seed, 1000003)) / 1000003.0 * TAU

static func zc(x: float, seed: int = 20261127) -> float:
	var p := _phase(seed)
	return 70.0 * sin(x / 95.0 + 0.271 + p) + 20.0 + 18.0 * sin(x / 41.0 + 1.571 + p * 1.7) + 7.0 * sin(x / 17.0 + 0.672 + p * 2.3)

static func dzc(x: float, seed: int = 20261127) -> float:
	var p := _phase(seed)
	return 70.0 / 95.0 * cos(x / 95.0 + 0.271 + p) + 18.0 / 41.0 * cos(x / 41.0 + 1.571 + p * 1.7) + 7.0 / 17.0 * cos(x / 17.0 + 0.672 + p * 2.3)
