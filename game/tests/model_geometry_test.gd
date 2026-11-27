extends SceneTree
## Mesh regression gate: checks generated object meshes for empty geometry, non-finite
## vertices, and zero-size bounds. This is structural validation, not visual approval.
const PVegetation = preload("res://scripts/pveg.gd")
const Vegetation = preload("res://scripts/veg.gd")
const AnimalModel = preload("res://scripts/animal_model.gd")

func _initialize() -> void:
	call_deferred("_run")

func _check_mesh(mesh: Mesh, label: String) -> bool:
	if mesh == null or mesh.get_surface_count() == 0:
		push_error("%s has no surfaces" % label)
		return false
	var arrays := mesh.surface_get_arrays(0)
	if arrays.size() <= Mesh.ARRAY_VERTEX or arrays[Mesh.ARRAY_VERTEX].is_empty():
		push_error("%s has no vertices" % label)
		return false
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bounds := AABB()
	for i in verts.size():
		var p := verts[i]
		if not is_finite(p.x) or not is_finite(p.y) or not is_finite(p.z):
			push_error("%s vertex %d is non-finite" % [label, i])
			return false
		if i == 0:
			bounds = AABB(p, Vector3.ZERO)
		else:
			bounds = bounds.expand(p)
	if bounds.size.length() < 0.001:
		push_error("%s bounds are degenerate" % label)
		return false
	print("MODEL_MESH_OK ", label, " surfaces=", mesh.get_surface_count(), " vertices=", verts.size(), " bounds=", bounds.size.length())
	return true

func _run() -> void:
	var p := PVegetation.new()
	var v := Vegetation.new()
	var ok := true
	var samples := [
		["pveg_spruce", p.spruce(701, "spruce")],
		["pveg_pine", p.pine(702, "pine")],
		["pveg_birch", p.birch(703, "birch")],
		["pveg_bush", p.bush(704, "bush")],
		["pveg_shrub", p.shrub(705, "alder")],
		["pveg_berry", p.berry_bush(706)],
		["pveg_fern", p.fern(707)],
		["pveg_hummock", p.hummock(708)],
		["pveg_horsetail", p.horsetail(709)],
		["pveg_stlanik", p.stlanik(710)],
		["pveg_rock", p.rock(711)],
		["pveg_mushroom", p.mushroom(712, true)],
		["veg_fern", v.fern(713)],
		["veg_reeds", v.reeds(714)],
		["veg_grass_patch", v.grass_patch(715)],
		["veg_berry_bush", v.berry_bush(716)],
		["veg_rock", v.rock(717, 1)],
		["veg_mushroom", v.mushroom(718, false)]
	]
	for entry in samples:
		var model: Array = entry[1]
		ok = _check_mesh(model[0], entry[0]) and ok
	# Exercise the mesh skinning model path for representative wildlife species.
	for kind in ["hare", "fox", "boar", "lynx", "moose", "capercaillie"]:
		var holder := Node3D.new()
		root.add_child(holder)
		var data := AnimalModel.build_taiga(holder, kind, 1.0, false, false)
		ok = data.has("rig") and data["rig"] and data["mi"].mesh.get_surface_count() > 0 and ok
		print("ANIMAL_MODEL_OK ", kind, " vertices=", data["mi"].mesh.get_surface_count())
		holder.queue_free()
	p.queue_free()
	v.queue_free()
	print("MODEL_GEOMETRY_TEST overall=", ok)
	quit(0 if ok else 1)
