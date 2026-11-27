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
	return {"version": 1, "chunk_size": CHUNK_SIZE, "records": persistent.duplicate(true)}

func from_save(data: Dictionary) -> void:
	persistent.clear()
	active.clear()
	pending.clear()
	if int(data.get("version", 0)) != 1:
		return
	var records: Variant = data.get("records", {})
	if not records is Dictionary:
		return
	for k: Variant in records:
		var rec: Variant = records[k]
		if rec is Dictionary and rec.has("coord") and rec.has("seed"):
			var copy: Dictionary = rec.duplicate(true)
			copy["loaded"] = false
			persistent[String(k)] = copy
