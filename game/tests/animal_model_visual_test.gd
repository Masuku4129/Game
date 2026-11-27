extends SceneTree
## Regression coverage for every wildlife model in warm/cold palettes.
const AnimalModel = preload("res://scripts/animal_model.gd")
const SPECIES := ["hare", "squirrel", "fox", "roe", "deer", "boar", "wolf", "bear", "beaver", "tiger", "moose", "lynx", "wolverine", "muskdeer", "capercaillie"]

func _initialize() -> void:
	call_deferred("_run")

func _check_mesh(mesh: Mesh, label: String) -> bool:
	if mesh == null or mesh.get_surface_count() == 0:
		push_error(label + " missing mesh surfaces")
		return false
	var ok := true
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if verts.size() < 3:
			push_error(label + " surface too small")
			ok = false
			continue
		var bounds := AABB(verts[0], Vector3.ZERO)
		for v in verts:
			if not is_finite(v.x) or not is_finite(v.y) or not is_finite(v.z):
				push_error(label + " non-finite vertex")
				ok = false
				break
			bounds = bounds.expand(v)
		if bounds.size.length() < 0.001:
			push_error(label + " degenerate mesh bounds")
			ok = false
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for ix in indices:
			if ix < 0 or ix >= verts.size():
				push_error(label + " invalid mesh index")
				ok = false
				break
		print("ANIMAL_MESH ", label, " surface=", s, " verts=", verts.size(), " bounds=", bounds.size)
	return ok

func _run() -> void:
	var builder := AnimalModel.new()
	var ok := true
	var count := 0
	for species in SPECIES:
		for winter in [false, true]:
			var holder := Node3D.new()
			var result: Dictionary = builder.build(holder, species, 1.0, true, winter)
			if result.is_empty():
				push_error("Build failed for " + species + " winter=" + str(winter))
				ok = false
			else:
				var root: Node = holder
				var mesh_nodes := root.find_children("*", "MeshInstance3D", true, false)
				if mesh_nodes.is_empty():
					push_error("No MeshInstance for " + species)
				ok = false
				for node in mesh_nodes:
					ok = _check_mesh(node.mesh, species + "_winter_" + str(winter)) and ok
				var skel := root.find_child("*", "Skeleton3D", true, false)
				if skel != null and skel.get_bone_count() == 0:
					push_error("Empty skeleton for " + species)
					ok = false
			count += 1
			holder.free()
	print("ANIMAL_MODEL_VISUAL_TEST count=", count, " passed=", ok)
	quit(0 if ok and count == SPECIES.size() * 2 else 1)
