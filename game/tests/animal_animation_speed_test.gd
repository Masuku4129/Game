extends SceneTree
## Regression tests for gait speed scaling in imported animal animations.
const Animal = preload("res://scripts/animal.gd")

class MockWorld extends Node3D:
	func ground_at(_x: float, _z: float) -> float:
		return 0.0

func _initialize() -> void:
	var world := MockWorld.new()
	var animal := Animal.new()
	var ap := AnimationPlayer.new()
	var model := Node3D.new()
	animal.main = world
	animal.parts = {"ap": ap, "model": model, "L": 2.0, "cur": ""}
	animal.sp = {"walk": 1.5, "run": 8.0}
	animal.state = "walk"
	animal.swim_k = 0.0
	animal.add_child(ap)
	animal.add_child(model)
	var ok := true
	animal.speed = 8.0
	animal._animate_model(0.1)
	ok = ok and is_equal_approx(ap.speed_scale, 1.0)
	animal.speed = 6.0
	animal._animate_model(0.1)
	ok = ok and is_equal_approx(ap.speed_scale, 0.75)
	animal.speed = 1.5
	animal._animate_model(0.1)
	ok = ok and is_equal_approx(ap.speed_scale, 1.0)
	animal.speed = 0.75
	animal._animate_model(0.1)
	ok = ok and is_equal_approx(ap.speed_scale, 0.5)
	print("ANIMAL_ANIMATION_SPEED_TEST passed=", ok, " playback_scales=", [1.0, 0.75, 1.0, 0.5])
	animal.free()
	world.free()
	quit(0 if ok else 1)
