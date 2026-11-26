extends SceneTree
## Экспорт моделей из того же генератора и текстур, которыми пользуется игровой лес.

const Vegetation = preload("res://scripts/veg.gd")

func _initialize() -> void:
	call_deferred("_export_models")

func _export_models() -> void:
	var generator = Vegetation.new()
	generator.lod = false
	var specs: Array = [
		{"file": "taiga_style_spruce.glb", "result": generator.spruce(9101, false)},
		{"file": "taiga_style_pine.glb", "result": generator.branchy(9201, "pine")},
		{"file": "taiga_style_birch.glb", "result": generator.branchy(9301, "birch")},
		{"file": "taiga_style_bush.glb", "result": generator.bush(9401)},
		{"file": "taiga_style_rock.glb", "result": generator.rock(9501, 2)}
	]
	var out_dir := ProjectSettings.globalize_path("res://models/game_style")
	var dir_error := DirAccess.make_dir_recursive_absolute(out_dir)
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		push_error("GAME_STYLE_EXPORT cannot create output directory: %s" % dir_error)
		quit(1)
		return

	var failures := 0
	for spec in specs:
		var result: Array = spec["result"]
		var source_mesh := result[0] as ArrayMesh
		if source_mesh == null:
			push_error("GAME_STYLE_EXPORT invalid mesh: " + String(spec["file"]))
			failures += 1
			continue
		var portable := _portable_mesh(source_mesh)
		var root := Node3D.new()
		root.name = String(spec["file"]).get_basename()
		var instance := MeshInstance3D.new()
		instance.name = "GameStyleMesh"
		instance.mesh = portable
		root.add_child(instance)
		instance.owner = root
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		var error := document.append_from_scene(root, state)
		if error == OK:
			error = document.write_to_filesystem(state, out_dir.path_join(String(spec["file"])))
		root.free()
		if error != OK:
			push_error("GAME_STYLE_EXPORT failed %s error=%s" % [String(spec["file"]), error])
			failures += 1
		else:
			print("GAME_STYLE_EXPORT ", spec["file"], " surfaces=", portable.get_surface_count(),
				" vertices=", _vertex_count(portable), " height=", snappedf(float(result[1]), 0.01))
	print("GAME_STYLE_EXPORT completed=", specs.size() - failures, " failed=", failures)
	quit(1 if failures > 0 else 0)

func _portable_mesh(source: ArrayMesh) -> ArrayMesh:
	var output := source.duplicate() as ArrayMesh
	for surface in output.get_surface_count():
		output.surface_set_material(surface, _portable_material(source.surface_get_material(surface)))
	return output

func _portable_material(source: Material) -> StandardMaterial3D:
	var output := StandardMaterial3D.new()
	output.vertex_color_use_as_albedo = true
	output.roughness = 0.92
	output.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if source is StandardMaterial3D:
		output = (source as StandardMaterial3D).duplicate() as StandardMaterial3D
		output.vertex_color_use_as_albedo = true
		return output
	if not (source is ShaderMaterial):
		return output
	var shader_material := source as ShaderMaterial
	var shader_path := shader_material.shader.resource_path if shader_material.shader != null else ""
	var texture: Variant = null
	var tint := Color.WHITE
	if shader_path.ends_with("card.gdshader") or shader_path.ends_with("bark.gdshader"):
		texture = shader_material.get_shader_parameter("tex")
		var tint_value: Variant = shader_material.get_shader_parameter("tint")
		if tint_value is Color:
			tint = tint_value
	elif shader_path.ends_with("rock.gdshader"):
		texture = shader_material.get_shader_parameter("rock")
	elif shader_path.ends_with("grass_blade.gdshader"):
		var grass_tint: Variant = shader_material.get_shader_parameter("tint")
		if grass_tint is Color:
			tint = grass_tint
	if texture is Texture2D:
		output.albedo_texture = texture
	output.albedo_color = tint
	if shader_path.ends_with("card.gdshader"):
		output.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		output.alpha_scissor_threshold = 0.45
		output.cull_mode = BaseMaterial3D.CULL_DISABLED
	return output

func _vertex_count(mesh: ArrayMesh) -> int:
	var total := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		total += vertices.size()
	return total
