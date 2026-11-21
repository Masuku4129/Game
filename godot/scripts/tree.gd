extends Node3D
@export var seed_value:int=0

func _ready()->void:
	var rng:=RandomNumberGenerator.new()
	rng.seed=seed_value
	var trunkmat:=StandardMaterial3D.new()
	trunkmat.albedo_color=Color(0.27,0.18,0.11)
	trunkmat.roughness=1.0
	var leafmat:=StandardMaterial3D.new()
	leafmat.albedo_color=[Color(0.12,0.28,0.10),Color(0.17,0.35,0.13),Color(0.22,0.40,0.16),Color(0.26,0.43,0.20)][rng.randi_range(0,3)]
	leafmat.roughness=0.92
	var trunk:=MeshInstance3D.new()
	var tm:=CylinderMesh.new()
	tm.top_radius=0.13
	tm.bottom_radius=0.28
	tm.height=2.9
	trunk.mesh=tm
	trunk.position.y=1.45
	trunk.material_override=trunkmat
	add_child(trunk)
	# Branches create a fuller silhouette beneath the layered canopy.
	for branch_i in range(16):
		var branch := MeshInstance3D.new()
		var branch_mesh := CylinderMesh.new()
		branch_mesh.top_radius = 0.035
		branch_mesh.bottom_radius = 0.075
		branch_mesh.height = rng.randf_range(0.65, 1.15)
		branch.mesh = branch_mesh
		branch.position = Vector3(rng.randf_range(-0.45,0.45),rng.randf_range(1.3,2.6),rng.randf_range(-0.45,0.45))
		branch.rotation_degrees = Vector3(rng.randf_range(-55,55),rng.randf_range(0,360),rng.randf_range(-55,55))
		branch.material_override = trunkmat
		add_child(branch)
	# Layered overlapping canopy blobs blend into a single organic mass.
	for i in range(12):
		var crown:=MeshInstance3D.new()
		var sm:=SphereMesh.new()
		sm.radius=rng.randf_range(0.72,1.15)
		sm.height=sm.radius*2
		crown.mesh=sm
		crown.position=Vector3(rng.randf_range(-0.45,0.45),rng.randf_range(2.6,4.2),rng.randf_range(-0.45,0.45))
		crown.scale=Vector3(rng.randf_range(0.9,1.25),rng.randf_range(0.85,1.3),rng.randf_range(0.9,1.25))
		crown.material_override=leafmat
		add_child(crown)
