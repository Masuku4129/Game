extends Node3D
## Loads the rigged GLB, drives the skeleton with the procedural animator and the cloak with the cloth simulation.

const RS = preload("res://scripts/rig_solver.gd")
const Anim = preload("res://scripts/animator.gd")
const Cloak = preload("res://scripts/cloak_sim.gd")
const MODEL_PATH := "res://assets/mita_rig.glb"

var model: Node3D
var skel: Skeleton3D
var mesh_inst: MeshInstance3D
var solver
var anim
var cloak
var cloth_mat: ShaderMaterial
var ready_ok := false
var input_dir := Vector2.ZERO        # world-space xz movement direction (unit or zero)
var input_speed := 0.0               # m/s
var cloak_enabled := true
var last_pose
var cloak_ms := 0.0
var anim_ms := 0.0
var fist_ok := false
var hand_idx := [0, 0]

func _ready() -> void:
	var scene = load(MODEL_PATH)
	if scene == null:
		push_error("cannot load " + MODEL_PATH)
		return
	model = scene.instantiate()
	add_child(model)
	for ap in model.find_children("*", "AnimationPlayer", true, false):
		ap.queue_free()
	var sk := model.find_children("*", "Skeleton3D", true, false)
	if sk.is_empty():
		push_error("no Skeleton3D in model")
		return
	skel = sk[0]
	var mis := model.find_children("*", "MeshInstance3D", true, false)
	if mis.is_empty():
		push_error("no MeshInstance3D in model")
		return
	mesh_inst = mis[0]
	solver = RS.new()
	if not solver.setup(skel, self):
		push_error("[char] solver.setup failed")
		return
	anim = Anim.new()
	anim.setup(solver)
	cloak = Cloak.new()
	if not cloak.setup(solver):
		return
	_build_cloth_mesh()
	# keep rest pose until the first update
	ready_ok = true

func _build_cloth_mesh() -> void:
	var src: ArrayMesh = mesh_inst.mesh as ArrayMesh
	if src == null:
		push_warning("mesh is not an ArrayMesh, cloak disabled")
		return
	var arrays := src.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if verts.size() != cloak.vertex_count:
		push_warning("vertex count differs (%d vs %d): cloak disabled" % [verts.size(), cloak.vertex_count])
		return
	arrays[Mesh.ARRAY_CUSTOM0] = cloak.vtx_idx
	arrays[Mesh.ARRAY_CUSTOM1] = cloak.vtx_w
	var flags: int = (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	# смещения вершин кисти для кулака (у модели нет костей пальцев)
	var ff := FileAccess.open("res://assets/fist_vtx.bin", FileAccess.READ)
	if ff != null:
		var fraw := ff.get_buffer(ff.get_length()).to_float32_array()
		if fraw.size() == verts.size() * 4:
			arrays[Mesh.ARRAY_CUSTOM2] = fraw
			flags |= Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT
			fist_ok = true
		else:
			push_warning("fist_vtx.bin size mismatch")
	var bones = arrays[Mesh.ARRAY_BONES]
	if bones != null and bones.size() == verts.size() * 8:
		flags |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	var old_mat := src.surface_get_material(0)
	var nm := ArrayMesh.new()
	nm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	cloth_mat = ShaderMaterial.new()
	cloth_mat.shader = load("res://shaders/cloak_skin.gdshader")
	if old_mat is BaseMaterial3D:
		var bm: BaseMaterial3D = old_mat
		cloth_mat.set_shader_parameter("albedo_tex", bm.albedo_texture)
		var orm: Texture2D = bm.roughness_texture if bm.roughness_texture != null else bm.metallic_texture
		if orm != null:
			cloth_mat.set_shader_parameter("orm_tex", orm)
	nm.surface_set_material(0, cloth_mat)
	mesh_inst.mesh = nm
	mesh_inst.custom_aabb = AABB(Vector3(-500, -5, -500), Vector3(1000, 60, 1000))

func do_action(name: String) -> bool:
	if not ready_ok:
		return false
	return anim.start(name)

func busy() -> bool:
	return ready_ok and anim.busy()

func get_state() -> String:
	return anim.state_name if ready_ok else "loading"

func _process(delta: float) -> void:
	if not ready_ok:
		return
	var dt := minf(delta, 1.0 / 30.0)
	var t0 := Time.get_ticks_usec()
	var pose = anim.update(dt, input_dir, input_speed)
	solver.solve(pose)
	solver.apply()
	last_pose = pose
	var t1 := Time.get_ticks_usec()
	if cloth_mat != null:
		cloak.step(dt, solver)
		var d: PackedVector3Array = cloak.disp
		cloth_mat.set_shader_parameter("disp", d)
		cloth_mat.set_shader_parameter("w2l", mesh_inst.global_transform.affine_inverse().basis)
		cloth_mat.set_shader_parameter("cloth_on", 1.0 if cloak_enabled else 0.0)
		if fist_ok:
			cloth_mat.set_shader_parameter("hand_l", Basis(solver.D[solver.idx["LeftHand"]]))
			cloth_mat.set_shader_parameter("hand_r", Basis(solver.D[solver.idx["RightHand"]]))
			cloth_mat.set_shader_parameter("fist_amt", anim.fist)
	var t2 := Time.get_ticks_usec()
	anim_ms = lerpf(anim_ms, (t1 - t0) / 1000.0, 0.05)
	cloak_ms = lerpf(cloak_ms, (t2 - t1) / 1000.0, 0.05)

func world_pos() -> Vector3:
	return anim.pos if ready_ok else Vector3.ZERO

func set_wind(w: Vector3) -> void:
	if ready_ok:
		cloak.wind = w
