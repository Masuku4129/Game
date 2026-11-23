extends Node3D
## --- core: студия значков (STUDIO=icons, scenes/studio.tscn). Каждая вещь, постройка, мебель,
## зверь и картинка «Как…» строится из игровых моделей, кадрируется по своей рамке и
## снимается на прозрачном фоне; квадрат SIZE×SIZE сохраняется в ICON_DIR/<id>.png
## (затем файлы кладутся в res://icons и попадают в репозиторий).

const IT = preload("res://scripts/items.gd")
const IM = preload("res://scripts/item_models.gd")
const GEO = preload("res://scripts/build_geo.gd")
const ST = preload("res://scripts/structures.gd")
const CAB = preload("res://scripts/cabin.gd")
const AM = preload("res://scripts/animal_model.gd")
const GD = preload("res://scripts/guide_data.gd")
const SIZE := 192

var pv
var geo
var im
var cam := Camera3D.new()
var jobs: Array = []    # [id, Callable -> Node3D, yaw, pitch]
var ji := 0
var wait := 0
var cur: Node3D
var dir := ""

func _ready() -> void:
	dir = OS.get_environment("ICON_DIR")
	if dir == "":
		dir = OS.get_environment("SHOTS")
	pv = load("res://scripts/pveg.gd").new()
	geo = GEO.new(pv)
	im = IM.new(pv)
	get_viewport().transparent_bg = true
	for c in get_parent().get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).visible = false
		if c is WorldEnvironment:
			var env: Environment = (c as WorldEnvironment).environment
			env.background_mode = Environment.BG_CLEAR_COLOR
			env.ambient_light_energy = 0.8
	cam.fov = 30.0
	add_child(cam)
	cam.current = true
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.35
	fill.rotation_degrees = Vector3(-20, 150, 0)
	add_child(fill)
	for id: String in IT.DEF:
		jobs.append([id, im.make.bind(id), 35.0, 38.0])
	for k: String in ST.ORDER:
		jobs.append(["b_" + k, _building.bind(k), 35.0, 28.0])
	for k: String in CAB.FURN_ORDER:
		jobs.append(["f_" + k, geo.furniture.bind(k), 35.0, 28.0])
	for k: String in GD.ANIMALS:
		jobs.append(["a_" + k, _animal.bind(k), 65.0, 14.0])
	for k: String in GD.HOWTO:
		jobs.append([k, _howto.bind(k), 35.0, 30.0])
	var only := OS.get_environment("ICON_ONLY")
	if only != "":
		jobs = jobs.filter(func(j: Array) -> bool: return String(j[0]) in only.split(","))

func _building(k: String) -> Node3D:
	match k:
		"campfire":
			return geo.campfire()
		"leanto":
			return geo.lean_to()
		"tree_shelter":
			var n: Node3D = geo.tree_shelter()
			var t := MeshInstance3D.new()
			t.mesh = pv.spruce(101)[0]
			n.add_child(t)
			return n
		"snow_shelter":
			return geo.snow_shelter()
		"cache":
			return geo.cache()
		"chop_block":
			return geo.chop_block()
		"cabin":
			var c := Node3D.new()
			c.add_child(geo.cabin(GEO.NC, 1.0, []))
			c.add_child(geo.stove())
			return c
	return Node3D.new()

func _animal(k: String) -> Node3D:
	var n := Node3D.new()
	AM.build(n, k, 1.0, true, false)
	return n

func _howto(k: String) -> Node3D:
	var n := Node3D.new()
	match k:
		"h_fell":
			var lg: Node3D = im.make("log")
			n.add_child(lg)
			var ax: Node3D = im.make("axe")
			ax.position = Vector3(0.1, 0.27, 0.0)
			ax.rotation.y = 0.6
			n.add_child(ax)
			var fw: Node3D = im.make("firewood")
			fw.position = Vector3(0.3, 0.0, 0.45)
			n.add_child(fw)
		"h_butcher":
			var c: Node3D = im.make("carcass_small")
			n.add_child(c)
			var kn: Node3D = im.make("knife")
			kn.position = Vector3(0.25, 0.0, 0.25)
			n.add_child(kn)
			var m: Node3D = im.make("meat_raw")
			m.position = Vector3(-0.25, 0.0, 0.3)
			n.add_child(m)
		"h_cabin":
			n.add_child(_building("cabin"))
		"h_cook":
			n.add_child(geo.campfire())
			var p: Node3D = im.make("clay_pot")
			p.position = Vector3(0.9, 0, 0.6)
			p.scale = Vector3.ONE * 2.0
			n.add_child(p)
		"h_warm":
			n.add_child(geo.lean_to())
			var f: Node3D = geo.campfire()
			f.position = Vector3(0, 0, 2.2)
			n.add_child(f)
	return n

## Рамка всех мешей узла (в мировых координатах).
func _aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for c in n.find_children("*", "GeometryInstance3D", true, false):
		var g := c as GeometryInstance3D
		if c is GPUParticles3D or c is CPUParticles3D:
			continue
		var bb: AABB = g.global_transform * g.get_aabb()
		if first:
			out = bb
			first = false
		else:
			out = out.merge(bb)
	return out

func _process(_d: float) -> void:
	if ji >= jobs.size():
		print("icons done ", jobs.size())
		get_tree().quit()
		return
	var j: Array = jobs[ji]
	if wait == 0:
		if cur != null:
			cur.queue_free()
		cur = (j[1] as Callable).call()
		add_child(cur)
		for p in cur.find_children("*", "GPUParticles3D", true, false):
			(p as GPUParticles3D).visible = false
		for l in cur.find_children("*", "OmniLight3D", true, false):
			(l as OmniLight3D).visible = false
	if wait == 1:
		var bb := _aabb(cur)
		var c := bb.get_center()
		var r := maxf(bb.size.length() * 0.5, 0.05)
		var yaw := deg_to_rad(float(j[2]))
		var pitch := deg_to_rad(float(j[3]))
		var d := r / sin(deg_to_rad(cam.fov * 0.5)) * 0.92
		cam.position = c + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * d
		cam.near = maxf(0.01, d - r * 2.0)
		cam.far = d + r * 3.0
		cam.look_at(c, Vector3.UP)
	wait += 1
	if wait < 5:
		return
	wait = 0
	var img := get_viewport().get_texture().get_image()
	var h := img.get_height()
	var w := img.get_width()
	var sq := img.get_region(Rect2i((w - h) / 2, 0, h, h))
	sq.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	sq.save_png(dir + "/" + String(j[0]) + ".png")
	ji += 1
