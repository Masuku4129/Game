extends SceneTree
## Every migrated environment category must resolve to an imported GLB mesh.

const Pveg = preload("res://scripts/pveg.gd")
const KINDS := [
	"spruce", "fir", "pine", "cedar", "larch", "birch", "aspen", "alder",
	"bush", "stump", "rock", "pebble", "slab", "split_rock", "outcrop",
	"scree", "fallen0", "fallen1", "windfall"
]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var builder = Pveg.new()
	var ok := true
	for kind in KINDS:
		var built: Array = builder.model_mesh(kind)
		if built.size() < 2 or not (built[0] is Mesh):
			push_error("GLB category did not produce a mesh: " + kind)
			ok = false
			continue
		var mesh: Mesh = built[0]
		if mesh.get_surface_count() == 0 or mesh.get_aabb().size.length() < 0.1:
			push_error("GLB category has empty/degenerate geometry: " + kind)
			ok = false
			continue
		for surface in mesh.get_surface_count():
			if mesh.surface_get_material(surface) == null:
				push_error("GLB category has no game material: " + kind + " surface=" + str(surface))
				ok = false
		print("ENVIRONMENT_GLB ", kind, " surfaces=", mesh.get_surface_count(), " bounds=", mesh.get_aabb().size)
	print("ENVIRONMENT_GLB_TEST categories=", KINDS.size(), " passed=", ok)
	quit(0 if ok else 1)
