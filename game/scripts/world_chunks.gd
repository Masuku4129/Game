extends Node
## Потоковый реестр мира. Хранит детерминированные чанки и изменения мира
## независимо от того, находятся ли их визуальные узлы сейчас в памяти.

const CHUNK_SIZE := 64.0
const ACTIVE_RADIUS := 2
const PRELOAD_RADIUS := 5
const LOAD_BUDGET := 3
const MAX_SAVED_CHUNKS := 4096
const TERRAIN_SEGMENTS := 64
const BASE_HALF_EXTENT := 256.0

var main: Node3D
var active: Dictionary = {}
var persistent: Dictionary = {}
var pending: Array[Vector2i] = []
var center := Vector2i(1 << 20, 1 << 20)
var _refresh := 1.0
var _explore_clock := 0.0
const MAP_SAMPLE_STEP := 16.0
const MAP_DISCOVERY_RADIUS := 25.0
var _sequence := 0
var terrain_nodes: Dictionary = {}
var terrain_materials: Dictionary = {}
var tree_mmis: Dictionary = {}
var prop_mmis: Dictionary = {}
var blocker_records: Dictionary = {}
var prop_blocker_records: Dictionary = {}
var prop_solid_records: Dictionary = {}
var _model_variant_cache: Dictionary = {}
var _far_mesh_cache: Dictionary = {}
var stream_water_material: ShaderMaterial
var _water_state_clock := 0.0
var _chunk_weather_clock := 0.0
const STREAM_TREE_KINDS := ["spruce", "pine", "birch", "larch", "aspen", "fir", "cedar", "alder", "willow", "rowan"]

func _process(delta: float) -> void:
	if main == null or main.hero == null or main.rig == null:
		return
	_update_stream_water(delta)
	_chunk_weather_clock -= delta
	if _chunk_weather_clock <= 0.0:
		_chunk_weather_clock = 0.25
		_sync_chunk_weather()
	_refresh -= delta
	var p: Vector3 = main.rig.position
	var next := Vector2i(floori(p.x / CHUNK_SIZE), floori(p.z / CHUNK_SIZE))
	if next != center or _refresh <= 0.0:
		center = next
		_refresh = 0.35
		_rebuild_queue()
		_unload_distant()
	# Drain chunk-generation work every frame, not only on refresh ticks.
	_process_queue()
	_explore_clock -= delta
	if _explore_clock <= 0.0:
		_explore_clock = 1.25
		_record_exploration(p)

func _record_exploration(player_pos: Vector3) -> void:
	if main == null:
		return
	var step := MAP_SAMPLE_STEP
	var gx := floori(player_pos.x / step)
	var gz := floori(player_pos.z / step)
	var radius_cells := ceili(MAP_DISCOVERY_RADIUS / step)
	var stamp := int(main.day_count) * 24 + int(main.t_hours)
	# Cache the existing cells once per chunk for this discovery pass. The previous
	# per-cell deep-copy read made the map update unnecessarily expensive.
	var staged: Dictionary = {}
	var known: Dictionary = {}
	for z in range(gz - radius_cells, gz + radius_cells + 1):
		for x in range(gx - radius_cells, gx + radius_cells + 1):
			var wx := (float(x) + 0.5) * step
			var wz := (float(z) + 0.5) * step
			if Vector2(wx - player_pos.x, wz - player_pos.z).length() > MAP_DISCOVERY_RADIUS:
				continue
			var key := "%d:%d" % [x, z]
			var coord := Vector2i(floori(wx / CHUNK_SIZE), floori(wz / CHUNK_SIZE))
			var chunk_key := _key(coord)
			if not known.has(chunk_key):
				known[chunk_key] = read_map_cells(coord)
			if known[chunk_key].has(key):
				continue
			var elevation := float(main.height(wx, wz))
			var water := float(main.water_level(wx, wz))
			var biome := int(main.zone(wx, wz)) if main.has_method("zone") else 0
			var wet := float(main.wet_k(wx, wz, elevation)) if main.has_method("wet_k") else 0.0
			var river := float(main.river_dist(wx, wz)) if main.has_method("river_dist") else 999.0
			var forest := float(main.forest_density(wx, wz)) if main.has_method("forest_density") else 0.0
			var terrain_type := "water" if elevation < water else "shore" if elevation < water + 1.5 else "land"
			var slope_dx := absf(float(main.height(wx + 4.0, wz) - main.height(wx - 4.0, wz))) / 8.0
			var slope_dz := absf(float(main.height(wx, wz + 4.0) - main.height(wx, wz - 4.0))) / 8.0
			var slope := sqrt(slope_dx * slope_dx + slope_dz * slope_dz)
			var zone_name := "forest"
			match biome:
				1:
					zone_name = "burned_forest"
				2:
					zone_name = "bog"
				4:
					zone_name = "windfall"
			var forest_name := "dense_taiga" if forest > 0.72 else "woodland" if forest > 0.38 else "sparse_trees" if forest > 0.12 else "clearing"
			var surface_name := "steep_slope" if slope > 0.42 else "rolling" if slope > 0.16 else "flat"
			var north_h := float(main.height(wx, wz - 12.0))
			var south_h := float(main.height(wx, wz + 12.0))
			var east_h := float(main.height(wx + 12.0, wz))
			var west_h := float(main.height(wx - 12.0, wz))
			var local_high := elevation - maxf(maxf(north_h, south_h), maxf(east_h, west_h))
			var local_low := minf(minf(north_h, south_h), minf(east_h, west_h)) - elevation
			var landmarks: Array[String] = []
			if river < 12.0:
				landmarks.append("river_corridor")
			if elevation < water + 1.0:
				landmarks.append("water_edge")
			if wet > 0.68:
				landmarks.append("wet_ground")
			if slope > 0.5:
				landmarks.append("steep_terrain")
			if local_high > 1.8:
				landmarks.append("local_ridge")
			if local_low > 1.8:
				landmarks.append("terrain_hollow")
			if elevation > main.WATER_Y + 12.0:
				landmarks.append("elevated_ground")
			if forest < 0.15:
				landmarks.append("open_area")
			var record := {
				"grid": [x, z], "position": [wx, wz], "discovered_at": stamp,
				"elevation": elevation, "water_level": water, "biome": biome,
				"zone_name": zone_name, "forest_class": forest_name, "surface_class": surface_name,
				"wetness": wet, "river_distance": river, "forest_density": forest,
				"terrain_type": terrain_type, "landmarks": landmarks,
				"season": int(main.weather.season_index()) if main.weather != null else 0
			}
			if not staged.has(chunk_key):
				staged[chunk_key] = {"coord": coord, "cells": {}}
			staged[chunk_key]["cells"][key] = record
	for batch in staged.values():
		if main.chunk_stream != null:
			main.chunk_stream.save_map_cells(batch["coord"], batch["cells"])

func _sync_chunk_weather() -> void:
	if main == null or main.weather == null:
		return
	var w = main.weather
	var freeze_now := clampf(-float(w.temp) * 0.5, 0.0, 1.0)
	var rain_now := float(w.precip) if float(w.temp) >= 0.5 else 0.0
	var snow_depth_now := float(w.snow) * 0.42
	var mud_depth_now := float(w.wet) * 0.24
	for material: ShaderMaterial in terrain_materials.values():
		material.set_shader_parameter("snow", w.snow)
		material.set_shader_parameter("wet", w.wet)
		material.set_shader_parameter("autumn", w.autumn)
		material.set_shader_parameter("leaf_drop", w.leaf_drop)
		material.set_shader_parameter("wind", w.wind)
		material.set_shader_parameter("blossom", w.blossom)
		material.set_shader_parameter("freeze", freeze_now)
		material.set_shader_parameter("rain", rain_now)
		material.set_shader_parameter("snow_m", snow_depth_now)
		material.set_shader_parameter("mud_m", mud_depth_now)

func _key(c: Vector2i) -> String:
	return "%d,%d" % [c.x, c.y]

func _seed(c: Vector2i) -> int:
	return int(main._chunk_seed(c.x, c.y))

func _rebuild_queue() -> void:
	pending.clear()
	var candidates: Array = []
	var view_forward := Vector2(-sin(main.rig.rotation.y), -cos(main.rig.rotation.y))
	var move_forward := Vector2(main.hero.vel.x, main.hero.vel.z)
	if move_forward.length_squared() > 0.25:
		move_forward = move_forward.normalized()
	else:
		move_forward = Vector2.ZERO
	# Queue two rings: near-player chunks first, then directional prefetch.
	# Priority smoothly favors view/movement direction while keeping the rear ring loaded.
	for z in range(-PRELOAD_RADIUS, PRELOAD_RADIUS + 1):
		for x in range(-PRELOAD_RADIUS, PRELOAD_RADIUS + 1):
			var c := center + Vector2i(x, z)
			var offset := Vector2(x, z)
			var d := offset.length_squared()
			if d > float(PRELOAD_RADIUS * PRELOAD_RADIUS) + 0.5:
				continue
			if active.has(_key(c)):
				continue
			var distance := sqrt(d)
			var direction := offset.normalized() if d > 0.0 else Vector2.ZERO
			var view_alignment := direction.dot(view_forward)
			var move_alignment := direction.dot(move_forward)
			var ring_bonus := 0.0
			if distance <= 1.5:
				ring_bonus = 100.0
			elif distance <= 2.5:
				ring_bonus = 25.0
			var forward_alignment := maxf(view_alignment, move_alignment)
			var forward_bonus := 0.0
			# Reserve a wider ahead-of-camera corridor: terrain and foliage begin
			# preparing before the player reaches the edge of the current preload ring.
			if distance > 2.0 and forward_alignment > 0.30:
				# Start preparing the visible/moving corridor earlier so dense
				# tree cover does not reveal itself at the camera's edge.
				forward_bonus = (forward_alignment - 0.30) * 92.0
			var priority := distance * 10.0 - view_alignment * 14.0 - move_alignment * 18.0 - ring_bonus - forward_bonus
			candidates.append({"coord": c, "priority": priority})
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
		var record: Dictionary
		if persistent.has(k):
			record = persistent[k]
		else:
			record = _create_record(c)
		record["last_seen"] = Time.get_unix_time_from_system()
		record["loaded"] = true
		active[k] = record
		persistent[k] = record
		# Центральный участок уже покрыт основной высокодетальной сеткой.
		# За его границей создаём продолжение теми же функциями рельефа и материалом.
		if not _inside_base_world(c):
			_build_terrain_chunk(c)
			_build_tree_cover(c)
			_build_understory(c)
			if main.animals != null:
				main.animals.populate_stream_chunk(c, _seed(c))
		budget -= 1

func _create_record(c: Vector2i) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed(c)
	var x := (float(c.x) + 0.5) * CHUNK_SIZE
	var z := (float(c.y) + 0.5) * CHUNK_SIZE
	var elevation := float(main.height(x, z))
	var wetness := float(main.wet_k(x, z, elevation))
	var forest_density := float(main.forest_density(x, z))
	var slope := 1.0 - float(main.normal_at(x, z).y)
	var river_distance := float(main.river_dist(x, z))
	var biome := int(main.zone(x, z))
	var ecology := {
		"wetness": wetness, "forest_density": forest_density, "slope": slope,
		"river_distance": river_distance,
		"forest_class": "dense" if forest_density > 0.72 else "woodland" if forest_density > 0.38 else "open",
		"terrain_class": "steep" if slope > 0.42 else "rolling" if slope > 0.16 else "flat",
		"habitat": "wetland" if biome == 2 or wetness > 0.68 else "burned" if biome == 1 else "windfall" if biome == 4 else "forest" if forest_density > 0.38 else "clearing",
		"water_edge": river_distance < 28.0 or float(main.lake_k(x, z)) > 0.2
	}
	return {
		"coord": [c.x, c.y], "seed": _seed(c), "biome": biome,
		"elevation": elevation, "water": float(main.water_level(x, z)),
		"vegetation_seed": rng.randi(), "ecology": ecology,
		"resource_state": {}, "terrain_delta": {}, "structures": [], "animals": [],
		"explored": false, "loaded": false, "revision": 0
	}

func mark_explored(world_position: Vector3) -> void:
	var c := Vector2i(floori(world_position.x / CHUNK_SIZE), floori(world_position.z / CHUNK_SIZE))
	var k := _key(c)
	if not persistent.has(k):
		persistent[k] = _create_record(c)
	var rec: Dictionary = persistent[k]
	rec["explored"] = true
	persistent[k] = rec

func save_map_cell(world_x: float, world_z: float, cell_key: String, data: Dictionary) -> void:
	var chunk_coord := Vector2i(floori(world_x / CHUNK_SIZE), floori(world_z / CHUNK_SIZE))
	var k := _key(chunk_coord)
	if not persistent.has(k):
		persistent[k] = _create_record(chunk_coord)
	var rec: Dictionary = persistent[k]
	var cells: Dictionary = rec.get("map_cells", {})
	cells[cell_key] = data.duplicate(true)
	rec["map_cells"] = cells
	rec["explored"] = true
	rec["revision"] = int(rec.get("revision", 0)) + 1
	persistent[k] = rec

func read_map_cells(chunk_coord: Vector2i) -> Dictionary:
	var rec: Dictionary = persistent.get(_key(chunk_coord), {})
	var cells: Variant = rec.get("map_cells", {})
	return cells.duplicate(true) if cells is Dictionary else {}

func write_state(world_position: Vector3, section: String, state: Dictionary) -> void:
	if section not in ["resource_state", "tree_state", "fallen_state", "terrain_delta", "structures", "animals"]:
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

func is_resource_collected(world_position: Vector3, kind: String) -> bool:
	var state := read_state(world_position, "resource_state")
	var saved: Variant = state.get(_resource_key(world_position, kind), {})
	return saved is Dictionary and bool(saved.get("collected", false))

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


func _update_stream_water(delta: float) -> void:
	if stream_water_material == null:
		var shader := load("res://shaders/paint/stream_water.gdshader") as Shader
		if shader == null:
			return
		stream_water_material = ShaderMaterial.new()
		stream_water_material.shader = shader
	_water_state_clock -= delta
	if _water_state_clock > 0.0:
		return
	_water_state_clock = 0.5
	if main.weather == null:
		return
	var temperature: float = main.weather.temp
	var ice_now := clampf(main.weather.ice, 0.0, 1.0)
	var rain_now := clampf(main.weather.precip, 0.0, 1.0)
	var wind_now := clampf(main.weather.wind, 0.0, 1.0)
	stream_water_material.set_shader_parameter("ice", ice_now)
	stream_water_material.set_shader_parameter("rain", rain_now)
	stream_water_material.set_shader_parameter("wind", wind_now)
	# Все активные чанки получают те же сезонные параметры, что и центральный ландшафт.
	for chunk_key in terrain_materials:
		var terrain: ShaderMaterial = terrain_materials[chunk_key]
		terrain.set_shader_parameter("snow", main.weather.snow)
		terrain.set_shader_parameter("wet", main.weather.wet)
		terrain.set_shader_parameter("snow_m", main.weather.snow * 0.42)
		terrain.set_shader_parameter("mud_m", main.weather.wet * 0.24)
		terrain.set_shader_parameter("freeze", clampf(-temperature * 0.5, 0.0, 1.0))
		terrain.set_shader_parameter("rain", rain_now)

func _build_bog_cover(c: Vector2i, parent: Node3D) -> void:
	if main == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed(c) ^ 0x3D6E8A21
	var groups: Dictionary = {}
	var attempts := 1950
	for n in attempts:
		var wx := float(c.x) * CHUNK_SIZE + rng.randf_range(0.5, CHUNK_SIZE - 0.5)
		var wz := float(c.y) * CHUNK_SIZE + rng.randf_range(0.5, CHUNK_SIZE - 0.5)
		var wet: float = main.swamp_depth_at(wx, wz)
		var zone_id: int = main.zone(wx, wz)
		if zone_id != 2 and wet < 0.56:
			continue
		# Smooth world-coordinate patch signal produces plant communities rather
		# instead of a uniform dice mix: hummocks, reed beds and mossy pools.
		var patch_signal := sin(wx * 0.041 + wz * 0.023) * cos(wz * 0.037 - wx * 0.019)
		var roll := clampf(rng.randf() + patch_signal * 0.25 + wet * 0.16, 0.0, 1.0)
		var kind := "sedge"
		if wet > 0.78 and roll < 0.32:
			kind = "moss"
		elif patch_signal > 0.48 and roll < 0.42:
			kind = "reeds"
		elif patch_signal < -0.42 and roll < 0.28:
			kind = "bush"
		elif roll < 0.18:
			kind = "moss"
		elif roll < 0.36:
			kind = "fern"
		elif roll < 0.58:
			kind = "reeds"
		elif roll < 0.80:
			kind = "sedge"
		elif roll < 0.92:
			kind = "bush"
		else:
			kind = "rock"
		var variants: Array = _model_variants(kind)
		if variants.is_empty():
			continue
		var vi := rng.randi_range(0, variants.size() - 1)
		var key := "%s:%d" % [kind, vi]
		if not groups.has(key):
			groups[key] = {"kind": kind, "variant": vi, "xf": []}
		var h: float = main.height(wx, wz)
		var scale := rng.randf_range(0.56, 1.48)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf_range(-PI, PI)).scaled(Vector3.ONE * scale), Vector3(wx, h, wz))
		groups[key].xf.append({"transform": xf, "wet": wet})
	for key: String in groups:
		var g: Dictionary = groups[key]
		var variants: Array = _model_variants(String(g.kind))
		var entries: Array = g.xf
		if entries.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = variants[int(g.variant)][0]
		mm.instance_count = entries.size()
		for i in entries.size():
			var entry: Dictionary = entries[i]
			mm.set_instance_transform(i, entry.transform)
			mm.set_instance_custom_data(i, Color(70.0, float(entry.wet), 0.0, 0.0))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.name = "BogPlant_%s_%d" % [g.kind, g.variant]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)

func _build_bog_water(c: Vector2i, parent: Node3D) -> void:
	if main == null:
		return
	var cells := 18
	var step := CHUNK_SIZE / float(cells)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for z in range(cells):
		for x in range(cells):
			var wx := float(c.x) * CHUNK_SIZE + (float(x) + 0.5) * step
			var wz := float(c.y) * CHUNK_SIZE + (float(z) + 0.5) * step
			var wet: float = main.swamp_depth_at(wx, wz)
			if wet < 0.66:
				continue
			var base := verts.size()
			var x0 := float(x) * step
			var z0 := float(z) * step
			var y: float = main.water_level(wx, wz) - 0.035
			verts.append_array([Vector3(x0, y, z0), Vector3(x0 + step, y, z0), Vector3(x0, y, z0 + step), Vector3(x0 + step, y, z0 + step)])
			uvs.append_array([Vector2(wx, wz), Vector2(wx + step, wz), Vector2(wx, wz + step), Vector2(wx + step, wz + step)])
			normals.append_array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
			indices.append_array(PackedInt32Array([base, base + 2, base + 1, base + 1, base + 2, base + 3]))
	if verts.is_empty():
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, stream_water_material)
	var water := MeshInstance3D.new()
	water.name = "BogPools"
	water.mesh = mesh
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(water)

func _build_water_surface(c: Vector2i, parent: Node3D) -> void:
	if stream_water_material == null:
		_update_stream_water(0.0)
	if stream_water_material == null:
		return
	var seg := TERRAIN_SEGMENTS
	var step := CHUNK_SIZE / float(seg)
	var ox := float(c.x) * CHUNK_SIZE
	var oz := float(c.y) * CHUNK_SIZE
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for z in range(seg):
		for x in range(seg):
			var wx := ox + (float(x) + 0.5) * step
			var wz := oz + (float(z) + 0.5) * step
			var ground: float = main.height(wx, wz)
			var level: float = main.water_level(wx, wz)
			if ground >= level - 0.035:
				continue
			var in_river: bool = main.river_dist(wx, wz) < 9.5
			var in_lake: bool = main.lake_k(wx, wz) > 0.28
			var in_bog: bool = main.zone(wx, wz) == 2 and main.swamp_depth_at(wx, wz) > 0.72
			if not (in_river or in_lake or in_bog):
				continue
			var base := vertices.size()
			var x0 := float(x) * step
			var z0 := float(z) * step
			var y := level + 0.025
			vertices.append(Vector3(x0, y, z0))
			vertices.append(Vector3(x0 + step, y, z0))
			vertices.append(Vector3(x0, y, z0 + step))
			vertices.append(Vector3(x0 + step, y, z0 + step))
			for uv in [Vector2(wx - step * 0.5, wz - step * 0.5), Vector2(wx + step * 0.5, wz - step * 0.5), Vector2(wx - step * 0.5, wz + step * 0.5), Vector2(wx + step * 0.5, wz + step * 0.5)]:
				uvs.append(uv * 0.08)
			for n in 4:
				normals.append(Vector3.UP)
			indices.append_array(PackedInt32Array([base, base + 2, base + 1, base + 1, base + 2, base + 3]))
	if vertices.is_empty():
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, stream_water_material)
	var water := MeshInstance3D.new()
	water.name = "StreamWater"
	water.mesh = mesh
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.position.y = 0.0
	parent.add_child(water)

func _inside_base_world(c: Vector2i) -> bool:
	var x0 := float(c.x) * CHUNK_SIZE
	var z0 := float(c.y) * CHUNK_SIZE
	return x0 >= -BASE_HALF_EXTENT and x0 + CHUNK_SIZE <= BASE_HALF_EXTENT and z0 >= -BASE_HALF_EXTENT and z0 + CHUNK_SIZE <= BASE_HALF_EXTENT

func _build_terrain_chunk(c: Vector2i) -> void:
	var k := _key(c)
	if terrain_nodes.has(k) or main == null or main.terrain_mat == null:
		return
	var seg := TERRAIN_SEGMENTS
	var side := seg + 1
	var origin_x := float(c.x) * CHUNK_SIZE
	var origin_z := float(c.y) * CHUNK_SIZE
	var step := CHUNK_SIZE / float(seg)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	vertices.resize(side * side)
	normals.resize(side * side)
	colors.resize(side * side)
	uvs.resize(side * side)
	for z in range(side):
		for x in range(side):
			var wx := origin_x + float(x) * step
			var wz := origin_z + float(z) * step
			var index := z * side + x
			var h: float = main.height(wx, wz)
			vertices[index] = Vector3(float(x) * step, h, float(z) * step)
			# Нормаль считается с тем же шагом, что у исходной сетки 512×512,
			# поэтому освещение не выдаёт стык между центральной картой и чанком.
			var e := step
			normals[index] = Vector3(
				main.height(wx - e, wz) - main.height(wx + e, wz),
				2.0 * e,
				main.height(wx, wz - e) - main.height(wx, wz + e)
			).normalized()
			var density: float = main.forest_density(wx, wz)
			var mud := clampf((main.WATER_Y + 1.2 - h) / 1.5, 0.0, 1.0)
			var leaves := clampf(main.n_detail.get_noise_2d(wx * 2.0, wz * 2.0) * 0.8 + density * 0.5, 0.0, 1.0)
			colors[index] = Color(density, mud, leaves)
			uvs[index] = Vector2(wx, wz) * 0.08
	var indices := PackedInt32Array()
	indices.resize(seg * seg * 6)
	var cursor := 0
	for z in range(seg):
		for x in range(seg):
			var a := z * side + x
			indices[cursor] = a
			indices[cursor + 1] = a + 1
			indices[cursor + 2] = a + side
			indices[cursor + 3] = a + 1
			indices[cursor + 4] = a + side + 1
			indices[cursor + 5] = a + side
			cursor += 6
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var field_bytes := PackedByteArray()
	var zone_bytes := PackedByteArray()
	var field_values := PackedFloat32Array()
	field_bytes.resize(side * side * 4)
	zone_bytes.resize(side * side * 4)
	field_values.resize(side * side)
	for z in range(side):
		for x in range(side):
			var index := z * side + x
			var wx := origin_x + float(x) * step
			var wz := origin_z + float(z) * step
			var h: float = main.height(wx, wz)
			var density: float = main.forest_density(wx, wz)
			var mud: float = clampf(main.wet_k(wx, wz, h), 0.0, 1.0)
			field_bytes[index * 4] = int(density * 255.0)
			field_bytes[index * 4 + 1] = 255
			field_bytes[index * 4 + 2] = int(mud * 255.0)
			field_bytes[index * 4 + 3] = 255
			var zone_id: int = main.zone(wx, wz)
			zone_bytes[index * 4] = 255 if zone_id == 1 else 0
			zone_bytes[index * 4 + 1] = 255 if zone_id == 2 else 0
			zone_bytes[index * 4 + 2] = 255 if zone_id == 3 else 0
			zone_bytes[index * 4 + 3] = 255 if zone_id == 4 else 0
			field_values[index] = h
	var field_tex := ImageTexture.create_from_image(Image.create_from_data(side, side, false, Image.FORMAT_RGBA8, field_bytes))
	var zone_tex := ImageTexture.create_from_image(Image.create_from_data(side, side, false, Image.FORMAT_RGBA8, zone_bytes))
	var hmap_tex := ImageTexture.create_from_image(Image.create_from_data(side, side, false, Image.FORMAT_RF, field_values.to_byte_array()))
	var chunk_material := main.terrain_mat.duplicate() as ShaderMaterial
	chunk_material.set_shader_parameter("field_tex", field_tex)
	chunk_material.set_shader_parameter("hmap_tex", hmap_tex)
	chunk_material.set_shader_parameter("zone_tex", zone_tex)
	chunk_material.set_shader_parameter("tsize", CHUNK_SIZE)
	chunk_material.set_shader_parameter("tseg", float(seg))
	chunk_material.set_shader_parameter("field_origin", Vector2(origin_x, origin_z))
	chunk_material.set_shader_parameter("snow_m", 0.0)
	chunk_material.set_shader_parameter("mud_m", 0.0)
	mesh.surface_set_material(0, chunk_material)
	terrain_materials[_key(c)] = chunk_material
	var root := Node3D.new()
	root.name = "TerrainChunk_%d_%d" % [c.x, c.y]
	root.position = Vector3(origin_x, 0.0, origin_z)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.extra_cull_margin = 8.0
	root.add_child(visual)
	var body := StaticBody3D.new()
	body.name = "TerrainCollision"
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(mesh.get_faces())
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	root.add_child(body)
	_build_water_surface(c, root)
	_build_bog_cover(c, root)
	_build_bog_water(c, root)
	add_child(root)
	terrain_nodes[k] = root

func _far_tree_mesh(source: Mesh) -> Mesh:
	var cache_key := source.get_instance_id()
	if _far_mesh_cache.has(cache_key):
		return _far_mesh_cache[cache_key]
	var out := ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			indices.resize(vertices.size())
			for i in vertices.size():
				indices[i] = i
		var reduced := PackedInt32Array()
		var triangle_count := int(indices.size() / 3)
		# Дальняя версия сохраняет общий силуэт GLB, сокращая плотность
		# мелких кроновых полигонов. Ближний меш остаётся исходным.
		for triangle in range(0, triangle_count, 2):
			var base := triangle * 3
			reduced.append(indices[base])
			reduced.append(indices[base + 1])
			reduced.append(indices[base + 2])
		arrays[Mesh.ARRAY_INDEX] = reduced
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(surface, source.surface_get_material(surface))
	_far_mesh_cache[cache_key] = out
	return out

func _tree_state_key(p: Vector3) -> String:
	return "%d:%d" % [roundi(p.x * 10.0), roundi(p.z * 10.0)]

func _model_variants(kind: String) -> Array:
	if not _model_variant_cache.has(kind):
		_model_variant_cache[kind] = main._variants(kind)
	return _model_variant_cache[kind]

func _build_tree_cover(c: Vector2i) -> void:
	var k := _key(c)
	if tree_mmis.has(k) or main == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed(c) ^ 0x4A17B39
	var groups: Dictionary = {}
	var canopy_spacing: Dictionary = {}
	var spacing_cell := 4.0
	var count := 2850
	for attempt in range(count):
		var wx := float(c.x) * CHUNK_SIZE + rng.randf_range(2.0, CHUNK_SIZE - 2.0)
		var wz := float(c.y) * CHUNK_SIZE + rng.randf_range(2.0, CHUNK_SIZE - 2.0)
		var density: float = main.forest_density(wx, wz)
		if rng.randf() > clampf(density * 1.28, 0.08, 0.995):
			continue
		var h: float = main.height(wx, wz)
		if h < main.WATER_Y + 1.0 or main.river_dist(wx, wz) < 6.5 or main.lake_k(wx, wz) > 0.45:
			continue
		var slope: float = main.normal_at(wx, wz).y
		if slope < 0.76:
			continue
		var zone_id: int = main.zone(wx, wz)
		var moisture: float = main.wet_k(wx, wz, h)
		# Spatial bins prevent same-chunk canopy trees from overlapping into
		# unreadable clumps; spacing is relaxed in dense forest and wider in open stands.
		var spacing := lerpf(4.45, 2.55, clampf(density, 0.0, 1.0))
		var bx := floori(wx / spacing_cell)
		var bz := floori(wz / spacing_cell)
		var crowded := false
		for nz in range(bz - 1, bz + 2):
			for nx in range(bx - 1, bx + 2):
				var bin_key := Vector2i(nx, nz)
				if not canopy_spacing.has(bin_key):
					continue
				for existing: Vector2 in canopy_spacing[bin_key]:
					if Vector2(wx - existing.x, wz - existing.y).length() < spacing:
						crowded = true
						break
				if crowded:
					break
		if crowded:
			continue
		var bin_key := Vector2i(bx, bz)
		if not canopy_spacing.has(bin_key):
			canopy_spacing[bin_key] = []
		canopy_spacing[bin_key].append(Vector2(wx, wz))
		var kind := "spruce"
		if zone_id == 2:
			kind = ["alder", "willow", "birch"][rng.randi_range(0, 2)]
		elif zone_id == 4 or main.biome(wx, wz) > 0.55:
			kind = ["cedar", "fir", "larch"][rng.randi_range(0, 2)]
		else:
			var pick := rng.randf()
			if moisture > 0.62 and pick < 0.24:
				kind = "alder"
			elif moisture > 0.5 and pick < 0.38:
				kind = "willow"
			elif pick < 0.22:
				kind = "pine"
			elif pick < 0.40:
				kind = "birch"
			elif pick < 0.55:
				kind = "larch"
			elif pick < 0.66:
				kind = "aspen"
			elif pick < 0.76:
				kind = "cedar"
			elif pick < 0.88:
				kind = "fir"
		var variants: Array = _model_variants(kind)
		if variants.is_empty():
			continue
		var variant_index := rng.randi_range(0, variants.size() - 1)
		var bucket_key := "%s:%d" % [kind, variant_index]
		if not groups.has(bucket_key):
			groups[bucket_key] = {"kind": kind, "variant": variant_index, "transforms": []}
		# Age structure responds to stand density and moisture. Crowded stands
		# contain more slender young trees; wet, established patches can carry
		# broader mature crowns, with rare emergent trees breaking the canopy.
		var juvenile_bias := clampf(0.28 + (1.0 - density) * 0.34 - moisture * 0.12, 0.08, 0.62)
		var scale := rng.randf_range(0.54, 1.66)
		if rng.randf() < juvenile_bias:
			scale = rng.randf_range(0.48, 0.92)
		elif moisture > 0.58 and rng.randf() < 0.22:
			scale = rng.randf_range(1.32, 1.78)
		if rng.randf() < 0.035:
			scale = rng.randf_range(1.68, 1.92)
		var yaw := rng.randf_range(-PI, PI)
		var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), Vector3(wx, h, wz))
		groups[bucket_key].transforms.append(xf)
	var created: Array = []
	var blockers_for_chunk: Array = []
	for bucket_key: String in groups:
		var group: Dictionary = groups[bucket_key]
		var kind := String(group.kind)
		var vi := int(group.variant)
		var variants: Array = _model_variants(kind)
		var mesh: Mesh = variants[vi][0]
		var transforms: Array = group.transforms
		if transforms.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = _far_tree_mesh(mesh)
		mm.instance_count = transforms.size()
		for i in transforms.size():
			mm.set_instance_transform(i, transforms[i])
			mm.set_instance_custom_data(i, Color(115.0, -1.0, 0.0, 0.0))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "StreamTrees_%s_%d" % [kind, vi]
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mmi.visibility_range_end = 145.0
		mmi.extra_cull_margin = 8.0
		add_child(mmi)
		created.append(mm)
		# Подключаем деревья к общей системе рубки/поиска ближайшего дерева.
		main._place_cell_records(mm, transforms, [kind], vi, variants, true, "")
		# Срубленные деревья имеют стабильный ID от координат, а не от порядка
		# загрузки чанков. Состояние переживает выгрузку и повторную генерацию.
		for i in transforms.size():
			var tree_pos: Vector3 = transforms[i].origin
			var tree_state := read_state(tree_pos, "tree_state")
			var tree_id := _tree_state_key(tree_pos)
			var saved_tree: Variant = tree_state.get(tree_id, {})
			var stable_id := 1000000000 + posmod(_seed(c) + kind.hash() + vi * 73856093 + i * 19349663, 1000000000)
			var found_record: Array = []
			for cell_key in main.tree_grid:
				for tree_rec: Array in main.tree_grid[cell_key]:
					if tree_rec[0] == mm and int(tree_rec[1]) == i:
						found_record = tree_rec
					break
				if not found_record.is_empty():
					break
			if not found_record.is_empty():
				found_record[4] = stable_id
			if saved_tree is Dictionary and bool(saved_tree.get("hidden", false)):
				var hidden_xf := Transform3D(Basis().scaled(Vector3(0.0001, 0.0001, 0.0001)), Vector3(tree_pos.x, -500.0, tree_pos.z))
				mm.set_instance_transform(i, hidden_xf)
				if not found_record.is_empty():
					found_record[2] = hidden_xf
		for xf: Transform3D in transforms:
			var p := xf.origin
			var radius := float(main.BLOCK_R.get(kind, 0.38)) * xf.basis.x.length()
			main._add_blocker(p.x, p.z, radius)
			blockers_for_chunk.append([Vector2i(floori(p.x / 8.0), floori(p.z / 8.0)), Vector3(p.x, p.z, radius)])
	tree_mmis[k] = created
	blocker_records[k] = blockers_for_chunk
	if main.tools_world != null:
		main.tools_world.restore_pending_tree_fells()

func _build_understory(c: Vector2i) -> void:
	var k := _key(c)
	if prop_mmis.has(k) or main == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed(c) ^ 0x6C8E9CF5
	var groups: Dictionary = {}
	var meadow_groups: Dictionary = {}
	var wet_groups: Dictionary = {}
	# Низкорослые GLB-модели заполняют просветы между деревьями.
	# Плотность привязана к лесу и болотному микрорельефу, а не к квадратному биому.
	for attempt in range(2900):
		var wx := float(c.x) * CHUNK_SIZE + rng.randf_range(1.0, CHUNK_SIZE - 1.0)
		var wz := float(c.y) * CHUNK_SIZE + rng.randf_range(1.0, CHUNK_SIZE - 1.0)
		var density: float = main.forest_density(wx, wz)
		var h: float = main.height(wx, wz)
		var zone_id: int = main.zone(wx, wz)
		var slope: float = main.normal_at(wx, wz).y
		var moisture: float = main.wet_k(wx, wz, h)
		if h < main.WATER_Y + 0.45 or main.river_dist(wx, wz) < 3.2 or main.lake_k(wx, wz) > 0.65:
			continue
		var kind := "fern"
		if zone_id == 2:
			var wet_pick := rng.randf()
			if wet_pick < 0.24:
				kind = "sedge"
			elif wet_pick < 0.42:
				kind = "reeds"
			elif wet_pick < 0.62:
				kind = "moss"
			elif wet_pick < 0.78:
				kind = "fern"
			elif wet_pick < 0.9:
				kind = "bush"
			else:
				kind = "mushroom"
		else:
			var understory_density := clampf(0.14 + density * 0.9 + moisture * 0.22, 0.0, 0.98)
			if rng.randf() > understory_density:
				continue
			var pick := rng.randf()
			if slope < 0.72:
				kind = "rock"
			elif moisture > 0.62 and pick < 0.18:
				kind = "moss"
			elif moisture > 0.45 and pick < 0.32:
				kind = "fern"
			elif pick < 0.22:
				kind = "fern"
			elif pick < 0.38:
				kind = "bush"
			elif pick < 0.49:
				kind = "hazel"
			elif pick < 0.60:
				kind = "dogrose"
			elif pick < 0.73:
				kind = "moss"
			elif pick < 0.82:
				kind = "mushroom"
			elif pick < 0.90:
				kind = "rock"
			elif pick < 0.96:
				kind = "stump"
			else:
				kind = "fallen0"
		var variants: Array = _model_variants(kind)
		if variants.is_empty():
			continue
		var vi := rng.randi_range(0, variants.size() - 1)
		var bucket := "%s:%d" % [kind, vi]
		var patch_kind := "forest"
		if zone_id == 2 or moisture > 0.68:
			patch_kind = "wet"
		elif density < 0.18:
			patch_kind = "meadow"
		var target_groups: Dictionary = wet_groups if patch_kind == "wet" else meadow_groups if patch_kind == "meadow" else groups
		if not target_groups.has(bucket):
			target_groups[bucket] = {"kind": kind, "variant": vi, "transforms": []}
		var scale := rng.randf_range(0.48, 1.62)
		if kind in ["rock", "stump"]:
			scale = rng.randf_range(0.58, 1.58)
		elif kind in ["fern", "sedge", "reeds"] and patch_kind == "wet":
			scale = rng.randf_range(0.72, 1.82)
		var yaw := rng.randf_range(-PI, PI)
		var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), Vector3(wx, h, wz))
		target_groups[bucket].transforms.append(xf)
	var created: Array = []
	var chunk_blockers: Array = []
	var chunk_solids: Array = []
	for patch_groups in [groups, meadow_groups, wet_groups]:
		for bucket: String in patch_groups:
			var group: Dictionary = patch_groups[bucket]
			var kind := String(group.kind)
			var vi := int(group.variant)
			var variants: Array = _model_variants(kind)
			var transforms: Array = group.transforms
			if transforms.is_empty():
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = variants[vi][0]
			mm.instance_count = transforms.size()
			for i in transforms.size():
				mm.set_instance_transform(i, transforms[i])
				mm.set_instance_custom_data(i, Color(90.0, 0.0, 0.0, 0.0))
			var mmi := MultiMeshInstance3D.new()
			var patch_label := "Forest"
			if patch_groups == meadow_groups:
				patch_label = "Meadow"
			elif patch_groups == wet_groups:
				patch_label = "Wet"
			mmi.name = "StreamUnderstory%s_%s_%d" % [patch_label, kind, vi]
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)
			created.append(mm)
		# Подключаем ягоды/грибы/валежник к штатным системам сбора и инструментов.
			main._place_cell_records(mm, transforms, [kind], vi, variants, false, "mushroom" if kind == "mushroom" else "")
			if kind in ["fallen0", "fallen1"]:
				var fallen_state := read_state(Vector3(float(c.x) * CHUNK_SIZE, 0.0, float(c.y) * CHUNK_SIZE), "fallen_state")
				for i in transforms.size():
					var origin: Vector3 = transforms[i].origin
					var fallen_id := "%d_%d" % [int(round(origin.x * 4.0)), int(round(origin.z * 4.0))]
					var saved_fallen: Variant = fallen_state.get(fallen_id, {})
					if saved_fallen is Dictionary and bool(saved_fallen.get("done", false)):
						mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(0.0001, 0.0001, 0.0001)), origin - Vector3(0, 500, 0)))
						for cell_key in main.fallen_spots:
							for fallen_rec: Dictionary in main.fallen_spots[cell_key]:
								if fallen_rec.get("mm") == mm and int(fallen_rec.get("i", -1)) == i:
									fallen_rec["done"] = true
									break
			if kind == "rock":
				var bounds: AABB = (variants[vi][0] as Mesh).get_aabb()
				for xf: Transform3D in transforms:
					var p := xf.origin
					var radius := maxf(0.35, (bounds.size.x + bounds.size.z) * 0.25 * xf.basis.x.length())
					var obstacle := Vector3(p.x, p.z, radius)
					main._add_blocker(p.x, p.z, radius)
					chunk_blockers.append([Vector2i(floori(p.x / 8.0), floori(p.z / 8.0)), obstacle])
					var solid := [0, p, Vector3.ZERO, radius, maxf(0.25, bounds.size.y * xf.basis.y.length() * 0.72)]
					main._add_solid(solid)
					chunk_solids.append(solid)
			elif kind in ["fallen0", "fallen1"]:
				var spec: Array = variants[vi]
				for xf: Transform3D in transforms:
					var radius := maxf(0.12, float(spec[2]) * xf.basis.x.length())
					var a: Vector3 = xf * Vector3(float(spec[4]), float(spec[3]), 0.0)
					var b: Vector3 = xf * Vector3(float(spec[4]) + float(spec[1]) * 0.85, 0.12, 0.0)
					var solid := [1, a, b, radius, 0.0]
					main._add_solid(solid)
					chunk_solids.append(solid)
					var steps := maxi(1, ceili(a.distance_to(b) / 1.4))
					for s in range(steps + 1):
						var p := a.lerp(b, float(s) / float(steps))
						var obstacle := Vector3(p.x, p.z, radius + 0.08)
						main._add_blocker(p.x, p.z, radius + 0.08)
						chunk_blockers.append([Vector2i(floori(p.x / 8.0), floori(p.z / 8.0)), obstacle])
	prop_mmis[k] = created
	prop_blocker_records[k] = chunk_blockers
	prop_solid_records[k] = chunk_solids

func _remove_prop_cover(k: String) -> void:
	var meshes: Array = prop_mmis.get(k, [])
	if meshes.is_empty():
		return
	for mm: MultiMesh in meshes:
		for node in get_children():
			if node is MultiMeshInstance3D and node.multimesh == mm:
				node.queue_free()
		for cell_key in main.pickables.keys():
			var picks: Array = main.pickables[cell_key]
			for i in range(picks.size() - 1, -1, -1):
				if picks[i].size() > 2 and picks[i][2] == mm:
					picks.remove_at(i)
			if picks.is_empty():
				main.pickables.erase(cell_key)
		for cell_key in main.res_spots.keys():
			var spots: Array = main.res_spots[cell_key]
			for i in range(spots.size() - 1, -1, -1):
				var p: Vector3 = spots[i][0]
				if floori(p.x / CHUNK_SIZE) == int(k.split(",")[0]) and floori(p.z / CHUNK_SIZE) == int(k.split(",")[1]):
					spots.remove_at(i)
			if spots.is_empty():
				main.res_spots.erase(cell_key)
		for cell_key in main.fallen_spots.keys():
			var fallen: Array = main.fallen_spots[cell_key]
			for i in range(fallen.size() - 1, -1, -1):
				if fallen[i].get("mm") == mm:
					fallen.remove_at(i)
			if fallen.is_empty():
				main.fallen_spots.erase(cell_key)
	# Убираем препятствия и опорные поверхности, созданные моделями этого чанка.
	for item: Array in prop_blocker_records.get(k, []):
		var grid_key: Vector2i = item[0]
		var obstacle: Vector3 = item[1]
		if main.blockers.has(grid_key):
			var entries: Array = main.blockers[grid_key]
			for i in range(entries.size() - 1, -1, -1):
				if entries[i] == obstacle:
					entries.remove_at(i)
			if entries.is_empty():
				main.blockers.erase(grid_key)
	for solid: Array in prop_solid_records.get(k, []):
		for grid_key in main.solids.keys():
			var entries: Array = main.solids[grid_key]
			for i in range(entries.size() - 1, -1, -1):
				if entries[i] == solid:
					entries.remove_at(i)
			if entries.is_empty():
				main.solids.erase(grid_key)
	prop_mmis.erase(k)
	prop_blocker_records.erase(k)
	prop_solid_records.erase(k)

func _remove_tree_cover(k: String) -> void:
	var meshes: Array = tree_mmis.get(k, [])
	if meshes.is_empty():
		return
	for mm: MultiMesh in meshes:
		for grid_key in main.tree_grid.keys():
			var entries: Array = main.tree_grid[grid_key]
			for i in range(entries.size() - 1, -1, -1):
				if entries[i][0] == mm:
					entries.remove_at(i)
			if entries.is_empty():
				main.tree_grid.erase(grid_key)
		for node in get_children():
			if node is MultiMeshInstance3D and node.multimesh == mm:
				node.queue_free()
	# Удаляем только блокираторы, поставленные этим чанком.
	for item: Array in blocker_records.get(k, []):
		var grid_key: Vector2i = item[0]
		var obstacle: Vector3 = item[1]
		if not main.blockers.has(grid_key):
			continue
		var entries: Array = main.blockers[grid_key]
		for i in range(entries.size() - 1, -1, -1):
			if entries[i] == obstacle:
				entries.remove_at(i)
		if entries.is_empty():
			main.blockers.erase(grid_key)
	tree_mmis.erase(k)
	blocker_records.erase(k)
	if main != null:
		main._update_near(true)
	# Кэш near_mesh оставляем: другие чанки могут использовать те же варианты GLB.

func _remove_terrain_chunk(k: String) -> void:
	if not terrain_nodes.has(k):
		return
	var node: Node = terrain_nodes[k]
	terrain_nodes.erase(k)
	terrain_materials.erase(k)
	if is_instance_valid(node):
		node.queue_free()

func _unload_distant() -> void:
	for k: String in active.keys():
		var rec: Dictionary = active[k]
		var a: Array = rec.get("coord", [0, 0])
		var c := Vector2i(int(a[0]), int(a[1]))
		if maxi(absi(c.x - center.x), absi(c.y - center.y)) <= PRELOAD_RADIUS:
			continue
		rec["loaded"] = false
		persistent[k] = rec
		_remove_tree_cover(k)
		_remove_prop_cover(k)
		_remove_terrain_chunk(k)
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
			# Preserve saved mutations across generator revisions. Geometry uses the
			# new deterministic seed; position-keyed resources and structures survive.
			copy["seed"] = _seed(coord)
			copy["loaded"] = false
			persistent[String(k)] = copy
	_apply_resource_state()
