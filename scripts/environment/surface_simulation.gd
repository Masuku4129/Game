extends RefCounted
class_name SurfaceSimulation

# CPU-side, deterministic local surface state. The RGBA texture is consumed by
# the terrain shader: R=snow depth, G=soil moisture, B=compaction, A=runoff.
const RESOLUTION := 96
const CELL_COUNT := RESOLUTION * RESOLUTION
const UPDATE_INTERVAL := 0.16

var world_extent := 90.0
var snow := PackedFloat32Array()
var moisture := PackedFloat32Array()
var compaction := PackedFloat32Array()
var runoff := PackedFloat32Array()
var elevation := PackedFloat32Array()
var next_moisture := PackedFloat32Array()
var state_image: Image
var state_texture: ImageTexture
var update_clock := 0.0
var simulation_time := 0.0


func initialize(extent: float, height_sampler: Callable) -> void:
	world_extent = extent
	snow.resize(CELL_COUNT)
	moisture.resize(CELL_COUNT)
	compaction.resize(CELL_COUNT)
	runoff.resize(CELL_COUNT)
	elevation.resize(CELL_COUNT)
	next_moisture.resize(CELL_COUNT)
	for z in range(RESOLUTION):
		for x in range(RESOLUTION):
			var index := _index(x, z)
			elevation[index] = float(height_sampler.call(_world_x(x), _world_z(z)))
	state_image = Image.create(RESOLUTION, RESOLUTION, false, Image.FORMAT_RGBA8)
	_write_texture()
	state_texture = ImageTexture.create_from_image(state_image)


func get_texture() -> Texture2D:
	return state_texture


func step(delta: float, weather: String, player_position: Vector3, player_speed: float) -> void:
	update_clock += delta
	simulation_time += delta
	if update_clock < UPDATE_INTERVAL:
		return
	var dt := minf(update_clock, 0.5)
	update_clock = 0.0
	_apply_precipitation(dt, weather)
	_route_surface_water(dt, weather)
	_relax_surface_state(dt, weather)
	if player_speed > 0.7:
		_compact_under_actor(player_position, player_speed, weather)
	_write_texture()
	if state_texture == null:
		state_texture = ImageTexture.create_from_image(state_image)
	else:
		state_texture.update(state_image)


func stamp_footstep(position: Vector3, weather: String) -> void:
	var center := _cell_at(position.x, position.z)
	var radius := 2
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var x := center.x + dx
			var z := center.y + dz
			if not _inside(x, z):
				continue
			var distance := Vector2(float(dx), float(dz)).length()
			if distance > 2.2:
				continue
			var index := _index(x, z)
			var influence := 1.0 - distance / 2.4
			compaction[index] = clampf(compaction[index] + 0.38 * influence, 0.0, 1.0)
			if weather == "snow":
				snow[index] = maxf(0.0, snow[index] - 0.035 * influence)
			elif weather == "rain":
				moisture[index] = minf(1.0, moisture[index] + 0.12 * influence)


func sample_surface(position: Vector3) -> Dictionary:
	var cell := _cell_at(position.x, position.z)
	if not _inside(cell.x, cell.y):
		return {"snow": 0.0, "moisture": 0.0, "compaction": 0.0, "runoff": 0.0}
	var index := _index(cell.x, cell.y)
	return {
		"snow": snow[index],
		"moisture": moisture[index],
		"compaction": compaction[index],
		"runoff": runoff[index]
	}


func _apply_precipitation(dt: float, weather: String) -> void:
	for index in range(CELL_COUNT):
		match weather:
			"rain":
				moisture[index] = minf(1.0, moisture[index] + dt * 0.075)
			"snow":
				snow[index] = minf(1.0, snow[index] + dt * 0.032)
				moisture[index] = maxf(0.0, moisture[index] - dt * 0.006)
			_:
				moisture[index] = maxf(0.0, moisture[index] - dt * 0.009)
				snow[index] = maxf(0.0, snow[index] - dt * 0.0018)


func _route_surface_water(dt: float, weather: String) -> void:
	for index in range(CELL_COUNT):
		next_moisture[index] = moisture[index]
		runoff[index] = maxf(0.0, runoff[index] - dt * 0.035)
	for z in range(1, RESOLUTION - 1):
		for x in range(1, RESOLUTION - 1):
			var index := _index(x, z)
			if moisture[index] < 0.16:
				continue
			var lowest := index
			var lowest_height := elevation[index] + moisture[index] * 0.025
			for offset in [-RESOLUTION, 1, RESOLUTION, -1]:
				var candidate := index + offset
				var candidate_height := elevation[candidate] + moisture[candidate] * 0.025
				if candidate_height < lowest_height:
					lowest_height = candidate_height
					lowest = candidate
			if lowest == index:
				continue
			var gradient := maxf(0.0, elevation[index] - elevation[lowest])
			var transfer := minf(next_moisture[index] * 0.035, dt * (0.003 + gradient * 0.018))
			if transfer <= 0.0:
				continue
			next_moisture[index] -= transfer
			next_moisture[lowest] = minf(1.0, next_moisture[lowest] + transfer * 0.92)
			runoff[lowest] = minf(1.0, runoff[lowest] + transfer * 2.8)
			# Erosion is deliberately slow and only occurs where water is moving.
			elevation[index] -= transfer * 0.0012
	for index in range(CELL_COUNT):
		moisture[index] = clampf(next_moisture[index], 0.0, 1.0)


func _relax_surface_state(dt: float, weather: String) -> void:
	var compaction_decay := 0.0007 if weather == "rain" else 0.00018
	for index in range(CELL_COUNT):
		compaction[index] = maxf(0.0, compaction[index] - dt * compaction_decay)
		if weather == "rain":
			# Saturated soil loses bearing strength and softens around old tracks.
			compaction[index] = maxf(0.0, compaction[index] - dt * moisture[index] * 0.002)


func _compact_under_actor(position: Vector3, speed: float, weather: String) -> void:
	var center := _cell_at(position.x, position.z)
	if not _inside(center.x, center.y):
		return
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var x := center.x + dx
			var z := center.y + dz
			if not _inside(x, z):
				continue
			var distance := Vector2(float(dx), float(dz)).length()
			if distance > 2.1:
				continue
			var index := _index(x, z)
			var influence := 1.0 - distance / 2.2
			var amount := minf(0.0025, speed * 0.00012) * influence
			compaction[index] = minf(1.0, compaction[index] + amount)
			if weather == "snow":
				snow[index] = maxf(0.0, snow[index] - amount * 0.24)


func _write_texture() -> void:
	for z in range(RESOLUTION):
		for x in range(RESOLUTION):
			var index := _index(x, z)
			state_image.set_pixel(x, z, Color(snow[index], moisture[index], compaction[index], runoff[index]))


func _world_x(x: int) -> float:
	return -world_extent + (float(x) + 0.5) * world_extent * 2.0 / RESOLUTION


func _world_z(z: int) -> float:
	return -world_extent + (float(z) + 0.5) * world_extent * 2.0 / RESOLUTION


func _cell_at(x: float, z: float) -> Vector2i:
	return Vector2i(
		clampi(int(floor((x + world_extent) / (world_extent * 2.0) * RESOLUTION)), 0, RESOLUTION - 1),
		clampi(int(floor((z + world_extent) / (world_extent * 2.0) * RESOLUTION)), 0, RESOLUTION - 1)
	)


func _inside(x: int, z: int) -> bool:
	return x >= 0 and x < RESOLUTION and z >= 0 and z < RESOLUTION


func _index(x: int, z: int) -> int:
	return z * RESOLUTION + x
