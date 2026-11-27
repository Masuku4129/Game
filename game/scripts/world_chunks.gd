extends Node
## Потоковый реестр мира. Хранит детерминированные чанки и изменения мира
## независимо от того, находятся ли их визуальные узлы сейчас в памяти.

const CHUNK_SIZE := 64.0
const ACTIVE_RADIUS := 2
const PRELOAD_RADIUS := 3
const LOAD_BUDGET := 2
const MAX_SAVED_CHUNKS := 4096

var main: Node3D
var active: Dictionary = {}
var persistent: Dictionary = {}
var pending: Array[Vector2i] = []
var center := Vector2i(1 << 20, 1 << 20)
var _refresh := 0.0
var _sequence := 0

func _process(delta: float) -> void:
	if main == null or main.hero == null or main.rig == null:
		return
	_refresh -= delta
	var p: Vector3 = main.rig.position
	var next := Vector2i(floori(p.x / CHUNK_SIZE), floori(p.z / CHUNK_SIZE))
	if next != center or _refresh <= 0.0:
		center = next
		_refresh = 0.35
		_rebuild_queue()
	_process_queue()
	_unload_distant()

func _key(c: Vector2i) -> String:
	return "%d,%d" % [c.x, c.y]

func _seed(c: Vector2i) -> int:
	return int(main._chunk_seed(c.x, c.y))

func _rebuild_queue() -> void:
	pending.clear()
	var candidates: Array = []
	for z in range(-PRELOAD_RADIUS, PRELOAD_RADIUS + 1):
		for x in range(-PRELOAD_RADIUS, PRELOAD_RADIUS + 1):
			var c := center + Vector2i(x, z)
			var d := Vector2(x, z).length_squared()
			if d > float(PRELOAD_RADIUS * PRELOAD_RADIUS) + 0.5:
				continue
			if active.has(_key(c)):
				continue
			candidates.append({"coord": c, "priority": d})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.priority) < float(b.priority))
	for item: Dictionary in candidates:
		pending.append(item.coord)

func _process_queue() -> void:
	var budget := LOAD_BUDGET
	while budget > 0 and not pending.is_empty():
		var c: Vector2i = pending.pop_front()
		var k := _key(c)
		if active.has(k):
			continue
		var record: Dictionary = persistent.get(k, _create_record(c))
		record["last_seen"] = Time.get_unix_time_from_system()
		record["loaded"] = true
		active[k] = record
		persistent[k] = record
		budget -= 1

func _create_record(c: Vector2i) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed(c)
	var x := (float(c.x) + 0.5) * CHUNK_SIZE
	var z := (float(c.y) + 0.5) * CHUNK_SIZE
	return {
		"coord": [c.x, c.y],
		"seed": _seed(c),
		"biome": int(main.zone(x, z)),
		"elevation": float(main.height(x, z)),
		"water": float(main.water_level(x, z)),
		"vegetation_seed": rng.randi(),
		"resource_state": {},
		"terrain_delta": {},
		"structures": [],
		"animals": [],
		"explored": false,
		"loaded": false,
		"revision": 0
	}

func mark_explored(world_position: Vector3) -> void:
	var c := Vector2i(floori(world_position.x / CHUNK_SIZE), floori(world_position.z / CHUNK_SIZE))
	var k := _key(c)
	if not persistent.has(k):
		persistent[k] = _create_record(c)
	var rec: Dictionary = persistent[k]
	rec["explored"] = true
	persistent[k] = rec

func write_state(world_position: Vector3, section: String, state: Dictionary) -> void:
	if section not in ["resource_state", "terrain_delta", "structures", "animals"]:
		return
	var c := Vector2i(floori(world_position.x / CHUNK_SIZE), floori(world_position.z / CHUNK_SIZE))
	var k := _key(c)
	if not persistent.has(k):
		persistent[k] = _create_record(c)
	var rec: Dictionary = persistent[k]
	rec[section] = state.duplicate(true)
	rec["revision"] = int(rec.get("revision", 0)) + 1
	persistent[k] = rec

func read_state(world_position: Vector3, section: String) -> Dictionary:
	var c := Vector2i(floori(world_position.x / CHUNK_SIZE), floori(world_position.z / CHUNK_SIZE))
	var rec: Dictionary = persistent.get(_key(c), {})
	var value: Variant = rec.get(section, {})
	return value.duplicate(true) if value is Dictionary else {}

func _resource_key(world_position: Vector3, kind: String) -> String:
	return "%d:%d:%s" % [roundi(world_position.x * 10.0), roundi(world_position.z * 10.0), kind]

func mark_resource_collected(world_position: Vector3, kind: String) -> void:
	if kind.is_empty():
		return
	var state := read_state(world_position, "resource_state")
	state[_resource_key(world_position, kind)] = {
		"kind": kind,
		"collected": true,
		"x": world_position.x,
		"z": world_position.z
	}
	write_state(world_position, "resource_state", state)

func _apply_resource_state() -> void:
	# The deterministic scatter pass has already populated main.pickables before
	# the save manager calls from_save(). Remove collected instances from both
	# the spatial index and their MultiMesh slot, so a reload cannot respawn them.
	if main == null:
		return
	var pickables: Dictionary = main.pickables
	if pickables.is_empty():
		return
	for cell_key in pickables.keys():
		var entries: Array = pickables[cell_key]
		for entry in entries.duplicate():
			if entry.size() < 4:
				continue
			var p: Vector3 = entry[0]
			var kind := String(entry[1])
			var state := read_state(p, "resource_state")
			var saved: Variant = state.get(_resource_key(p, kind), {})
			if not saved is Dictionary or not bool(saved.get("collected", false)):
				continue
			entries.erase(entry)
			var mm: MultiMesh = entry[2]
			var instance_index := int(entry[3])
			if mm != null and instance_index >= 0 and instance_index < mm.instance_count:
				mm.set_instance_transform(instance_index, Transform3D(
					Basis().scaled(Vector3(0.001, 0.001, 0.001)),
					p - Vector3(0, 5, 0)
				))
		if entries.is_empty():
			pickables.erase(cell_key)
	main.pickables = pickables


func _unload_distant() -> void:
	for k: String in active.keys():
		var rec: Dictionary = active[k]
		var a: Array = rec.get("coord", [0, 0])
		var c := Vector2i(int(a[0]), int(a[1]))
		if maxi(absi(c.x - center.x), absi(c.y - center.y)) <= PRELOAD_RADIUS:
			continue
		rec["loaded"] = false
		persistent[k] = rec
		active.erase(k)
	_prune()

func _prune() -> void:
	if persistent.size() <= MAX_SAVED_CHUNKS:
		return
	var removable: Array = []
	for k: String in persistent:
		if active.has(k) or bool(persistent[k].get("explored", false)):
			continue
		removable.append(k)
	if removable.size() <= 0:
		return
	removable.sort_custom(func(a: String, b: String) -> bool:
		return float(persistent[a].get("last_seen", 0.0)) < float(persistent[b].get("last_seen", 0.0)))
	while persistent.size() > MAX_SAVED_CHUNKS and not removable.is_empty():
		persistent.erase(removable.pop_front())

func to_save() -> Dictionary:
	return {
		"version": 2,
		"chunk_size": CHUNK_SIZE,
		"world_seed": int(main.map_seed) if main != null else 0,
		"records": persistent.duplicate(true)
	}

func from_save(data: Dictionary) -> void:
	persistent.clear()
	active.clear()
	pending.clear()
	var version := int(data.get("version", 0))
	if version < 1 or version > 2:
		return
	var saved_seed := int(data.get("world_seed", main.map_seed if main != null else 0))
	if main != null and saved_seed != 0 and saved_seed != int(main.map_seed):
		push_warning("World chunk data ignored because the world seed differs from the save")
		return
	var records: Variant = data.get("records", {})
	if not records is Dictionary:
		return
	for k: Variant in records:
		var rec: Variant = records[k]
		if rec is Dictionary and rec.has("coord") and rec.has("seed"):
			var copy: Dictionary = rec.duplicate(true)
			var coords: Array = copy.get("coord", [])
			if coords.size() != 2:
				continue
			var coord := Vector2i(int(coords[0]), int(coords[1]))
			# Ignore corrupt records or records generated by another world seed.
			if int(copy["seed"]) != _seed(coord):
				continue
			copy["loaded"] = false
			persistent[String(k)] = copy
	_apply_resource_state()
