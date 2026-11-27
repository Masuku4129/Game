extends SceneTree
## Mesh regression gate: checks every surface for valid vertices, indices and finite bounds.
const PVegetation = preload("res://scripts/pveg.gd")
const Vegetation = preload("res://scripts/veg.gd")
const AnimalModel = preload("res://scripts/animal_model.gd")

func _initialize() -> void:
	call_deferred("_run")

func _check_mesh(mesh: Mesh, label: String) -> bool:
	if mesh == null or mesh.get_surface_count() == 0:
		push_error("%s has no surfaces" % label)
		return false
	var ok := true
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		if arrays.size() <= Mesh.ARRAY_VERTEX or arrays[Mesh.ARRAY_VERTEX].is_empty():
			push_error("%s surface %d has no vertices" % [label, surface])
			ok = false
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bounds := AABB()
		for i in verts.size():
			var p := verts[i]
			if not is_finite(p.x) or not is_finite(p.y) or not is_finite(p.z):
				push_error("%s surface %d vertex %d is non-finite" % [label, surface, i])
				ok = false
				break
			if i == 0:
				bounds = AABB(p, Vector3.ZERO)
			else:
				bounds = bounds.expand(p)
		if bounds.size.length() < 0.001:
			push_error("%s surface %d has degenerate bounds" % [label, surface])
			ok = false
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if not indices.is_empty():
			for idx in indices:
				if idx < 0 or idx >= verts.size():
					push_error("%s surface %d index out of range: %d" % [label, surface, idx])
					ok = false
					break
		print("MODEL_SURFACE ", label, " surface=", surface, " vertices=", verts.size(), " indices=", indices.size(), " bounds=", bounds.size.length())
	return ok

func _run() -> void:
	var p := PVegetation.new()
	var v := Vegetation.new()
	var ok := true
	var samples := [
		["pveg_spruce", p.spruce(701, "spruce")], ["pveg_pine", p.pine(702, "pine")],
		["pveg_birch", p.birch(703, "birch")], ["pveg_bush", p.bush(704, "bush")],
		["pveg_shrub", p.shrub(705, "alder")], ["pveg_berry", p.berry_bush(706)],
		["pveg_fern", p.fern(707)], ["pveg_hummock", p.hummock(708)],
		["pveg_horsetail", p.horsetail(709)], ["pveg_stlanik", p.stlanik(710)],
		["pveg_rock", p.rock(711)], ["pveg_mushroom", p.mushroom(712, true)],
		["veg_fern", v.fern(713)], ["veg_reeds", v.reeds(714)],
		["veg_grass_patch", v.grass_patch(715)], ["veg_berry_bush", v.berry_bush(716)],
		["veg_rock", v.rock(717, 1)], ["veg_mushroom", v.mushroom(718, false)]
	]
	for entry in samples:
		var model: Array = entry[1]
		ok = _check_mesh(model[0], entry[0]) and ok
	# Repeat procedural samples across additional seeds to catch fragile geometry.
	for seed_v in [91, 307, 919]:
		ok = _check_mesh(p.rock(seed_v), "pveg_rock_seed_%d" % seed_v) and ok
		ok = _check_mesh(p.berry_bush(seed_v), "pveg_berry_seed_%d" % seed_v) and ok
		ok = _check_mesh(v.rock(seed_v, 1), "veg_rock_seed_%d" % seed_v) and ok
	# Instantiate every supported wildlife model and inspect its mesh surfaces.
	for kind in ["hare", "squirrel", "fox", "roe", "deer", "boar", "wolf", "bear", "tiger", "lynx", "moose", "wolverine", "muskdeer", "capercaillie", "beaver"]:
		var holder := Node3D.new()
		root.add_child(holder)
		var data := AnimalModel.build_taiga(holder, kind, 1.0, false, false)
		ok = data.has("rig") and data["rig"] and _check_mesh(data["mi"].mesh, "animal_%s" % kind) and ok
		holder.queue_free()
	p.queue_free()
	v.queue_free()
	print("MODEL_GEOMETRY_TEST overall=", ok)
	quit(0 if ok else 1)
