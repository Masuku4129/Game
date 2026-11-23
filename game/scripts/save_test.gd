extends Node
## --- core: проверка сохранения без экрана.
## SAVE_TEST=1 — изменить мир (вещи, постройки с хранилищем, огонь, срубленное дерево, бревно,
##   воткнутое копьё, вещь на земле, тропа, убитый зверь, время, погода), сохранить, снять
##   слепок в user://snap_a.json и выйти.
## SAVE_TEST=2 SAVE_AUTO=load — загрузить при старте, через 2 кадра снять слепок в
##   user://snap_b.json и выйти. Сравнение слепков — скриптом снаружи.

var main: Node3D
var _f := 0
var mode := ""

func _process(_d: float) -> void:
	_f += 1
	if mode == "1":
		_run_a()
	elif _f == 3:
		_dump("user://snap_b.json")
		get_tree().quit()

func _dump(p: String) -> void:
	var d: Dictionary = main.saver.snapshot()
	d.erase("time")
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "", true))
	f.close()
	print("SAVETEST dump ", p, " разделов ", d.size())

func _run_a() -> void:
	var camp = main.camp
	match _f:
		30:
			main.inv.merge({"pebble": 30, "twig": 20, "branch": 20, "spruce_twigs": 30, "firewood": 10, "plank": 4, "clay": 5, "meat_raw": 4, "berry": 6, "jug": 1, "clay_pot": 1, "mug": 1}, true)
			main.t_hours = 21.5
			main.day_count = 7
			main.hunger = 0.42
			main.injuries["рана: рука"] = 30.0
			main.weather.temp = -7.5
			main.weather.kind = "Снег"
			main.weather.snow = 0.33
			# найти ровное место рядом с героем
			camp._tcenter = main.hero.position
			camp.build.start()
			for k: String in ["campfire", "cache", "chop_block", "leanto"]:
				print("SAVETEST place ", k, " -> ", camp._find_spot(k, 3.0))
			camp.build.stop()
			for s: Dictionary in camp.list:
				if s["type"] == "cache":
					camp.to_store(s, "meat_raw", 2)
					camp.to_store(s, "berry", 3)
				if s["type"] == "campfire":
					camp.add_fuel(s)
					camp.light(s)
		40:
			var tw = main.tools_world
			# срубить ближайшее дерево (спрятать экземпляр), бревно и копьё рядом
			var t: Array = tw.find_tree(main.hero.position, 25.0)
			if not t.is_empty():
				tw._hide_tree(t)
				print("SAVETEST tree hidden ", t[4])
			tw.drop_log(main.hero.position + Vector3(2, 0, 1), 0.7)
			tw.place_item("spear", Transform3D(Basis(Vector3.RIGHT, 0.3), main.hero.position + Vector3(-1.5, 0.6, 0)), false)
			main.hunt.drop_item("clay_pot", main.hero.position + Vector3(1, 0, -2))
			main.hunt.drop_item("meat_raw", main.hero.position + Vector3(1, 0, -2))
			main.feet.add_wear(main.hero.position.x + 3.0, main.hero.position.z, 2.0, 0.8)
			for a in main.animals.list:
				if a.kind == "roe" and not a.dead:
					a.kill()
					print("SAVETEST killed roe")
					break
			# combat: лук за спиной, стрела в земле, связка из трёх брёвен
			main.inv.merge({"bow": 1, "arrow": 4, "rope": 1}, true)
			main.hero.tools.back = "bow"
			tw.place_item("arrow", Transform3D(Basis(Vector3.RIGHT, 0.4), main.hero.position + Vector3(-2.5, 0.3, 1.0)), false)
			for k in 3:
				tw.drop_log(main.hero.position + Vector3(0.8, 0, -0.6 + k * 0.3), 1.2)
			main.hero.tools._tie_now()
			print("SAVETEST bundle ", main.hero.tools.bundle != null)
			main.hero.position += Vector3(0.7, 0, 0.4)
			main.hero.position.y = main.ground_at(main.hero.position.x, main.hero.position.z)
		45:
			main.saver.enabled = true
			print("SAVETEST save ", main.saver.save_game(), " ", main.saver.last_status)
			_dump("user://snap_a.json")
			get_tree().quit()
