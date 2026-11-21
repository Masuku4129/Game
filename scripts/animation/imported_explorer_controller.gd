extends Node3D
## Imported rigged field explorer. Uses actual GLB Skeleton3D and AnimationPlayer clips.
const MODEL_PATH := "res://assets/character/field_explorer.glb"
var model_root: Node3D
var animation_player: AnimationPlayer
var current_clip := ""
var last_season := ""
var target_speed := 0.0

func _ready() -> void:
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		push_error("Missing rigged explorer model: " + MODEL_PATH)
		return
	model_root = packed.instantiate() as Node3D
	if model_root == null:
		push_error("Character GLB root is not Node3D")
		return
	add_child(model_root)
	animation_player = _find_animation_player(model_root)
	if animation_player == null:
		push_error("Character GLB has no AnimationPlayer")
	else:
		var clips := animation_player.get_animation_list()
		print("EXPLORER_CLIPS: ", clips)
		for clip in clips:
			var animation := animation_player.get_animation(clip)
			if String(clip).contains("Walk") or String(clip).contains("Run") or String(clip).contains("Idle"):
				animation.loop_mode = Animation.LOOP_LINEAR
		_play_matching(["Idle", "idle", "Breathing"])
	set_season("summer")

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null

func _play_matching(candidates: Array[String]) -> void:
	if animation_player == null:
		return
	for candidate in candidates:
		for clip in animation_player.get_animation_list():
			if String(clip).contains(candidate):
				if current_clip != clip:
					animation_player.play(clip, 0.15)
					current_clip = clip
				return

func set_motion(horizontal_speed: float, slope: float) -> void:
	target_speed = horizontal_speed
	if target_speed > 6.0:
		_play_matching(["Run", "run"])
	elif target_speed > 0.15:
		_play_matching(["Walk", "walk"])
	else:
		_play_matching(["Idle", "idle", "Breathing"])

func set_season(season: String) -> void:
	if model_root == null or season == last_season:
		return
	last_season = season
	var palette := {
		"spring": Color(0.34, 0.29, 0.21),
		"summer": Color(0.43, 0.37, 0.27),
		"autumn": Color(0.29, 0.23, 0.17),
		"winter": Color(0.22, 0.23, 0.22)
	}
	var coat_color: Color = palette.get(season, palette["summer"])
	_apply_seasonal_coat(model_root, coat_color)
	# Winter scarf is already part of the layered model; shift toward wool-like muted tones.
	if season == "winter":
		_apply_named_material_tint(model_root, "Scarf", Color(0.32, 0.34, 0.30))
	elif season == "autumn":
		_apply_named_material_tint(model_root, "Scarf", Color(0.38, 0.26, 0.16))
	else:
		_apply_named_material_tint(model_root, "Scarf", Color(0.24, 0.22, 0.14))

func _apply_seasonal_coat(node: Node, tint: Color) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		var mesh := mesh_node.mesh
		if mesh != null:
			for surface in range(mesh.get_surface_count()):
				var material := mesh.surface_get_material(surface) as StandardMaterial3D
				if material != null and String(material.resource_name).contains("Wool"):
					var copy := material.duplicate() as StandardMaterial3D
					copy.albedo_color = tint
					mesh_node.set_surface_override_material(surface, copy)
	for child in node.get_children():
		_apply_seasonal_coat(child, tint)

func _apply_named_material_tint(node: Node, label: String, tint: Color) -> void:
	if node is MeshInstance3D and String(node.name).contains(label):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null:
			for surface in range(mesh_node.mesh.get_surface_count()):
				var base := mesh_node.mesh.surface_get_material(surface) as StandardMaterial3D
				if base != null:
					var copy := base.duplicate() as StandardMaterial3D
					copy.albedo_color = tint
					mesh_node.set_surface_override_material(surface, copy)
	for child in node.get_children():
		_apply_named_material_tint(child, label, tint)
