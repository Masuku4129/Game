extends Node
## --- colony: проверка острога и съёмка кадров. ---
## COLONY_TEST=1 — без экрана: отряд рубит дерево, кряжует, несёт бревно в амбар,
## строит амбар, затем проверяем победу и проигрыш. Печатает «CL …» и PASS/FAIL.
## COLONY_SHOTS=папка — кадры с новой камеры на трёх приближениях, лист стройки
## и лист сценария; печатает треугольники, вызовы отрисовки и время скриптов.

var main: Node3D
var colony
var _n := 0
var _stage := 0
var _t := 0.0
var _fails: Array = []
var _dbg := false
var _shots := ""
var _plank_seen := false

func _ready() -> void:
	colony = main.colony
	_shots = OS.get_environment("COLONY_SHOTS")
	Engine.time_scale = 3.0 if _shots != "" else 6.0
	# «сам найдёт работу» — как в игре: по нему и идёт цепочка рубить → кряжевать → нести
	colony.auto_work = true
	_dbg = OS.get_environment("COLONY_DEBUG") != ""

func _ok(cond: bool, what: String) -> void:
	if cond:
		print("CL ok  ", what)
	else:
		_fails.append(what)
		print("CL FAIL ", what)

func _process(delta: float) -> void:
	_n += 1
	_t += delta
	if _dbg and _n % 120 == 0:
		for u in colony.units:
			if u.state == "walk" and not u.path.is_empty():
				var dd: Vector3 = (u.path[0] - u.position).normalized() * 0.5
				print("CL blk ", u.unit_name, " here ", colony.nav.cost_at(u.position.x, u.position.z), main.blocked(u.position.x, u.position.z, 0.22), " ahead ", colony.nav.cost_at(u.position.x + dd.x, u.position.z + dd.z), main.blocked(u.position.x + dd.x, u.position.z + dd.z, 0.22), " vel ", u.vel)
		for u in colony.units:
			print("CL dbg %s %s pos=%s path=%s goal=%s job=%s stage=%s path=%d carry=%s" % [u.unit_name, u.state, u.position, u.path, u._goal,
				String(u.job.get("kind", "-")), String(u.job.get("stage", "-")), u.path.size(), u.carry])
	if _shots != "":
		_shot_step()
		return
	_test_step()

# ---------- проверка без экрана ----------

func _test_step() -> void:
	match _stage:
		0:
			if _n < 10:
				return
			_ok(colony.units.size() == 3, "трое в отряде")
			_ok(colony.alive_count() == 3, "все живы")
			var u = colony.units[0]
			var p: Vector3 = colony.center() + Vector3(8, 0, 6)
			var pts: Array = colony.nav.find_path(u.position, colony.nav.nearest_free(p, 8.0))
			_ok(not pts.is_empty(), "путь по сетке найден")
			_ok(colony.count("axe") >= 1, "топор в запасе")
			# разрешённая область: кисть, запрет выхода, снятие
			var zc: Vector3 = colony.center()
			colony.zones.paint(zc, 24.0, true)
			_ok(bool(colony.zones.active()), "область закрашена")
			_ok(bool(colony.zones.allowed(zc.x, zc.z)), "в области ходить можно")
			_ok(not bool(colony.zones.allowed(zc.x + 90.0, zc.z)), "вне области нельзя")
			u.area_lock = true
			var far_p: Vector3 = colony.nav.nearest_free(zc + Vector3(90, 0, 0), 14.0)
			_ok((colony.nav.find_path(u.position, far_p, true) as Array).is_empty(), "за край области пути нет")
			_ok(not bool(colony.can_work_at(u, far_p)), "работа вне области запрещена")
			u.area_lock = false
			colony.zones.clear()
			_ok(not bool(colony.zones.active()), "область снята")
			# лист работ: важность и переключение клетки
			colony.planner.set_pri(u, "chop", 1)
			colony.planner.cycle(u, "chop")
			_ok(colony.planner.pri_of(u, "chop") == 2, "клетка листа работ переключается")
			colony.planner.set_pri(u, "chop", 1)
			# метка: помеченное дерево берут в работу по листу
			var rec0: Array = colony.find_tree_near(colony.center(), 60.0)
			if not rec0.is_empty():
				_ok(bool(colony.planner.designate({"what": "tree", "rec": rec0, "pos": (rec0[2] as Transform3D).origin})), "метка рубки поставлена")
				var u2 = colony.units[2]
				colony.jobs.cancel(u2)
				colony.planner.set_pri(u2, "chop", 1)
				_ok(bool(colony.planner.pick(u2)), "работа взята по листу")
				_ok(String(u2.job.get("kind", "")) in ["chop", "cut"], "взято помеченное дерево (%s)" % String(u2.job.get("kind", "-")))
			# выбор нескольких
			colony.select_all()
			_ok(colony.sel_all.size() == 3, "выбраны все трое")
			colony.select(u)
			# валка: ближнее дерево
			var rec: Array = colony.find_tree_near(colony.center(), 60.0)
			_ok(not rec.is_empty(), "дерево рядом нашлось")
			if rec.is_empty():
				_finish()
				return
			colony.select(u)
			var started: bool = colony.jobs.start(u, "chop", {"rec": rec, "pos": (rec[2] as Transform3D).origin})
			_ok(started, "дело «рубить» начато")
			_stage = 1
			_t = 0.0
		1:
			# ждём, пока дерево свалят и появится лежачий ствол
			if int(colony.stats.get("trees", 0)) > 0:
				_ok(true, "дерево срублено")
				_stage = 2
				_t = 0.0
			elif _t > 90.0:
				_ok(false, "дерево срублено")
				_stage = 2
				_t = 0.0
		2:
			# кряжевание и перенос: ждём бревно в запасе
			if colony.count("log") > 0:
				_ok(true, "бревно принесено в амбар")
				_stage = 3
				_t = 0.0
			elif _t > 150.0:
				_ok(false, "бревно принесено в амбар (цепочка рубить → нести → сложить)")
				_stage = 3
				_t = 0.0
		3:
			# стройка: ставим амбар и даём припасы
			colony.give("log", 10)
			colony.give("plank", 6)
			var c: Vector3 = colony.nav.nearest_free(colony.center() + Vector3(6, 0, -6), 10.0)
			colony.build_begin("storehouse")
			colony.build_move(c)
			var tries := 0
			while not colony.ghost_ok and tries < 24:
				var a := TAU * float(tries) / 12.0
				colony.build_move(colony.nav.nearest_free(colony.center() + Vector3(cos(a), 0, sin(a)) * (7.0 + float(tries) * 0.7), 10.0))
				tries += 1
			_ok(colony.ghost_ok, "место под амбар выбрано (%s)" % colony.ghost_why)
			_ok(colony.build_confirm(), "амбар поставлен на стройку")
			_stage = 4
			_t = 0.0
		4:
			# стройка берёт не только брёвна: доски приносят отдельными рейсами
			for st2: Dictionary in main.camp.list:
				if String(st2["type"]) == "storehouse" and int((st2.get("have", {}) as Dictionary).get("plank", 0)) > 0:
					_plank_seen = true
			if colony.count_built("storehouse") > 0:
				_ok(_plank_seen, "доски принесены на стройку отдельным рейсом")
				_ok(true, "амбар достроен работой строителя")
				_stage = 5
				_t = 0.0
			elif _t > 420.0:
				var st: Dictionary = {}
				for s5: Dictionary in main.camp.list:
					if String(s5["type"]) == "storehouse":
						st = s5
				print("CL dbg site ", st.get("stage"), " have ", st.get("have"), " stock log ", colony.count("log"), " plank ", colony.count("plank"))
				_ok(false, "амбар достроен (ход %.2f, этап %s)" % [float(st.get("prog", 0.0)), String(st.get("stage", "?"))])
				_stage = 5
				_t = 0.0
		5:
			# сохранение и загрузка: люди, ноша и дела
			var snap: Dictionary = main.saver.snapshot()
			_ok(snap.has("colony"), "раздел «colony» в сохранении")
			var u0 = colony.units[0]
			var was_name: String = u0.unit_name
			var was_h: float = u0.health
			u0.health = 0.42
			colony.from_save(snap.get("colony", {}))
			_ok(colony.units[0].unit_name == was_name, "имя после загрузки")
			_ok(absf(float(colony.units[0].health) - was_h) < 0.01, "здоровье после загрузки (%.2f)" % float(colony.units[0].health))
			_stage = 51
			_t = 0.0
		51:
			# сценарий: победа по мехам к весне
			colony.give("fur", 8)
			main.day_count = 26
			colony.scenario._day = 25
			_stage = 6
			_t = 0.0
		6:
			if _t < 2.0:
				return
			_ok(colony.scenario.over and colony.scenario.won, "победа: меха сданы воеводе")
			# проигрыш: отряд погиб
			colony.scenario.over = false
			colony.scenario.won = false
			for u in colony.units:
				u.health = 0.0
				u.die()
			_stage = 7
			_t = 0.0
		7:
			if _t < 2.0:
				return
			_ok(colony.alive_count() == 0, "весь отряд погиб")
			_ok(colony.scenario.over and not colony.scenario.won, "проигрыш отмечен")
			_finish()

func _finish() -> void:
	print("CL stock log=%d firewood=%d еда=%d меха=%d" % [colony.count("log"), colony.count("firewood"), colony.food_count(), colony.furs()])
	print("CL stats ", colony.stats)
	if _fails.is_empty():
		print("CL PASS")
	else:
		print("CL FAIL ", _fails.size(), ": ", ", ".join(PackedStringArray(_fails)))
	get_tree().quit()

# ---------- кадры ----------

func _shot(nm: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(_shots + "/" + nm + ".png")
	print("CL shot %s tris %.1f тыс. draws %d script %.2f мс colony %.2f мс" % [nm,
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		colony.script_us() / 1000.0])

func _shot_step() -> void:
	var rig = colony.rig
	match _n:
		10:
			# работа: двое рубят и носят, третий собирает
			colony.give("log", 6)
			colony.give("plank", 4)
			var rec: Array = colony.find_tree_near(colony.center(), 50.0)
			if not rec.is_empty():
				colony.jobs.start(colony.units[0], "chop", {"rec": rec, "pos": (rec[2] as Transform3D).origin})
			var r2: Dictionary = colony.find_res_near(colony.center(), 40.0)
			if not r2.is_empty():
				colony.jobs.start(colony.units[2], "gather", {"res": r2, "pos": r2["pos"]})
		20:
			rig.snap_to(colony.units[0].position, 12.0, 0.7)
		30:
			_shot("1_vblizi")
		34:
			rig.snap_to(colony.center(), 42.0, 0.7)
		44:
			_shot("2_lager")
		48:
			rig.snap_to(colony.center(), 140.0, 0.9)
		58:
			_shot("3_daleko")
		62:
			rig.snap_to(colony.center(), 36.0, 0.4)
			colony.ui._open_build()
		72:
			_shot("4_stroika")
		76:
			colony.ui._pick_type("storehouse")
			colony.build_move(colony.nav.nearest_free(colony.center() + Vector3(5, 0, -4), 8.0))
		84:
			_shot("5_prizrak")
		88:
			colony.ui._close_build()
			var hit: Dictionary = {}
			var rec2: Array = colony.find_tree_near(colony.center(), 40.0)
			if not rec2.is_empty():
				hit = {"what": "tree", "rec": rec2, "pos": (rec2[2] as Transform3D).origin}
				colony.ui.open_radial(Vector2(900, 420), colony.jobs.commands(hit) + [["Нести в амбар", "move"], ["Погреться", "move"]], hit)
			colony.scenario.say("Волки! Стая идёт к лагерю")
		98:
			_shot("6_prikazy")
		102:
			colony.ui.close_radial()
			# зима: снег, метель, вечер
			main.weather.fast_forward(24.0 * 13.0)
			main.weather.snow = 0.8
			main.t_hours = 17.0
			main._update_sky()
			rig.snap_to(colony.center(), 30.0, 1.2)
		118:
			_shot("7_zima")
		124:
			print("CL shots done")
			get_tree().quit()
