extends RefCounted
## Значки и миниатюры, заранее отрисованные из игровых моделей (студия: STUDIO=icons,
## scripts/studio_icons.gd) и сохранённые в res://icons/<id>.png. Предметы — по id из items.gd,
## постройки — "b_<тип>", мебель — "f_<вид>", звери — "a_<вид>", страницы «Как…» — "h_<тема>".
## Нет файла — null (тогда рисуется старый значок кистью).

static var _cache := {}

static func tex(id: String) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	var path := "res://icons/%s.png" % id
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path) as Texture2D
	_cache[id] = t
	return t
