extends SceneTree
const Animals = preload("res://scripts/animals.gd")

class MockWorld extends Node3D:
	var hero := Node3D.new()
	var rig := Node3D.new()

class MockAP:
	var active := false

class MockAnimal extends Node3D:
	var kind := "roe"
	var far := false
	var _acc := 0.0
	var dead := false
	var meat := 1.0
	var state := "wander"
	var parts := {"ap": MockAP.new()}
	var ticks := 0
	func tick(_delta: float) -> void:
		ticks += 1

func _initialize() -> void:
	call_deferred("run_test")

func run_test() -> void:
	var world := MockWorld.new()
	root.add_child(world)
	var manager := Animals.new()
	root.add_child(manager)
	manager.main = world
	var near_a := MockAnimal.new()
	var mid_a := MockAnimal.new()
	var far_a := MockAnimal.new()
	near_a.position = Vector3(10.0, 0.0, 0.0)
	mid_a.position = Vector3(45.0, 0.0, 0.0)
	far_a.position = Vector3(80.0, 0.0, 0.0)
	manager.list.append(near_a)
	manager.list.append(mid_a)
	manager.list.append(far_a)
	for i in 57:
		var distant := MockAnimal.new()
		distant.position = Vector3(120.0 + i, 0.0, 120.0)
		manager.list.append(distant)
	for i in 20:
		manager._process(0.05)
	var near_ok := near_a.ticks >= 18
	var mid_ok := mid_a.ticks >= 8 and mid_a.ticks <= near_a.ticks / 2 + 1
	var far_ok := far_a.ticks <= 2 and not far_a.parts["ap"].active
	print("WILDLIFE_SCHEDULER near=", near_a.ticks, " mid=", mid_a.ticks, " far=", far_a.ticks, " far_anim=", far_a.parts["ap"].active)
	manager.queue_free()
	world.queue_free()
	quit(0 if near_ok and mid_ok and far_ok else 1)
