extends SceneTree
## Regression coverage for animal obstacle clearance and swept-step checks.
const Animal = preload("res://scripts/animal.gd")

class MockWorld extends Node3D:
	const SIZE := 512.0
	const WATER_Y := -2.0
	func blocked(x: float, z: float, radius: float) -> bool:
		return Vector2(x, z).length() < 0.4 + radius
	func grid_height(_x: float, _z: float) -> float:
		return 0.0
	func solid_top(_x: float, _z: float) -> float:
		return -1000000000.0
	func water_level(_x: float, _z: float) -> float:
		return -2.0

func _initialize() -> void:
	var world := MockWorld.new()
	var animal := Animal.new()
	animal.main = world
	animal.parts = {"L": 2.0}
	animal.scale_k = 1.0
	var through_obstacle := animal._can_move_segment(Vector3(-1, 0, 0), Vector3(1, 0, 0))
	var clear_path := animal._can_move_segment(Vector3(-1, 0, 1.5), Vector3(1, 0, 1.5))
	var footprint := animal._obstacle_radius()
	animal.position = Vector3(0.65, 0.0, 0.0)
	animal._push_out()
	var recovered_clearance := Vector2(animal.position.x, animal.position.z).length()
	var recovered := recovered_clearance >= 0.4 + footprint
	print("ANIMAL_COLLISION_TEST blocked_segment=", not through_obstacle,
		" clear_segment=", clear_path, " footprint_radius=", footprint,
		" recovery_clearance=", recovered_clearance, " recovered=", recovered)
	animal.free()
	world.free()
	if through_obstacle or not clear_path or footprint <= 0.18 or not recovered:
		quit(1)
	else:
		quit(0)
