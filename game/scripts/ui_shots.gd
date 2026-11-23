extends Node
## --- core: кадры интерфейса (UI_SHOTS=папка): справочник (все вкладки и несколько страниц),
## настройки, меню запуска, ремесло в коробе. Работает и на паузе.

var main: Node3D
var dir := ""
var _f := 0
var _plan: Array = []
var _i := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	dir = OS.get_environment("UI_SHOTS")
	_plan = [
		[60, "give"],
		[90, "guide", 0, "clay"], [96, "shot", "guide_res_clay"],
		[100, "guide", 0, "moss"], [106, "shot", "guide_res_moss"],
		[110, "guide", 0, "fish_raw"], [116, "shot", "guide_res_fish"],
		[120, "guide", 1, "stew"], [126, "shot", "guide_craft_stew"],
		[130, "guide", 1, "mug"], [136, "shot", "guide_craft_mug"],
		[140, "guide", 1, "jug"], [146, "shot", "guide_craft_jug"],
		[150, "guide", 2, "b_cache"], [156, "shot", "guide_build_cache"],
		[160, "guide", 2, "b_cabin"], [166, "shot", "guide_build_cabin"],
		[170, "guide", 3, "a_wolf"], [176, "shot", "guide_animal_wolf"],
		[180, "guide", 4, "h_fell"], [186, "shot", "guide_howto_fell"],
		[190, "guide", 4, "h_warm"], [196, "shot", "guide_howto_warm"],
		[200, "close_guide"],
		[204, "settings"], [212, "shot", "settings"],
		[216, "close_settings"],
		[220, "menu"], [228, "shot", "start_menu"],
		[232, "close_menu"],
		[236, "inv"], [330, "shot", "inventory_craft"],
		[334, "close_inv"], [420, "build"], [440, "shot", "build_cards"],
		[444, "quit"],
	]

var _menu: Control

func _process(_d: float) -> void:
	_f += 1
	while _i < _plan.size() and _f >= int(_plan[_i][0]):
		_do(_plan[_i])
		_i += 1

func _do(p: Array) -> void:
	match String(p[1]):
		"give":
			main.inv.merge({"clay": 4, "firewood": 6, "meat_raw": 2, "mushroom": 2, "clay_pot": 1, "mug": 1, "spruce_twigs": 3, "branch": 2}, true)
		"guide":
			if not main.guide.is_open():
				main.guide.open()
			main.guide._set_tab(int(p[2]))
			main.guide._select(String(p[3]))
		"close_guide":
			main.guide.close()
		"settings":
			main.settings.open()
		"close_settings":
			main.settings.close()
		"menu":
			_menu = preload("res://scripts/start_menu.gd").new()
			_menu.set("main", main)
			main.core_ui.add_child(_menu)
		"close_menu":
			_menu.queue_free()
			get_tree().paused = false
		"inv":
			main.inventory.tab = 1
			main.inventory.rsel = "stew"
			main.inventory.open()
		"close_inv":
			main.inventory.close()
		"build":
			main.inv.merge({"pebble": 8, "twig": 4, "branch": 6, "spruce_twigs": 8, "plank": 2}, true)
			main.camp.ui._camp_pressed()
			main.camp.build.select("cache")
		"shot":
			get_viewport().get_texture().get_image().save_png(dir + "/" + String(p[2]) + ".png")
			print("ui shot ", p[2])
		"quit":
			get_tree().quit()
