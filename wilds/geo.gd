extends RefCounted
## Общие размеры, типы ячеек и палитры уровня руин.

const W := 96.0          # ширина ячейки на экране
const H := 72.0          # высота ячейки на экране (перспектива 3/4)
const WALL_H := 120.0    # высота стены
const LIFT := 64.0       # высота верхней террасы
const GW := 96
const GH := 64

# типы ячеек
const VOID := 0
const FLOOR := 1
const WALL := 2
const CHASM := 3
const BRIDGE := 4
const STAIRS := 5
const RAISED := 6

# зоны (стиль пола и стен)
const Z_PLAZA := 0
const Z_HALL := 1
const Z_LIB := 2
const Z_CORR := 3
const Z_CELL := 4
const Z_OUT := 5
const Z_TERR := 6


static func hash2(x: int, y: int, s: int) -> float:
	var v := sin(float(x) * 12.9898 + float(y) * 78.233 + float(s) * 37.719) * 43758.5453
	return v - floorf(v)


static func walkable(k: int) -> bool:
	return k == FLOOR or k == BRIDGE or k == STAIRS or k == RAISED


static func floor_color(z: int) -> Color:
	match z:
		Z_PLAZA:
			return Color(0.105, 0.105, 0.215)
		Z_HALL:
			return Color(0.075, 0.075, 0.17)
		Z_LIB:
			return Color(0.115, 0.085, 0.17)
		Z_CORR:
			return Color(0.08, 0.08, 0.17)
		Z_CELL:
			return Color(0.06, 0.075, 0.14)
		Z_OUT:
			return Color(0.06, 0.065, 0.14)
		_:
			return Color(0.14, 0.13, 0.27)


# [лицевая грань, верхняя грань, светлая кромка]
static func wall_colors(z: int) -> Array:
	var rim := Color(0.42, 0.44, 1.0, 0.5)
	match z:
		Z_LIB:
			return [Color(0.09, 0.065, 0.13), Color(0.15, 0.11, 0.21), rim]
		Z_CELL:
			return [Color(0.055, 0.07, 0.12), Color(0.10, 0.12, 0.20), rim]
		Z_OUT:
			return [Color(0.045, 0.045, 0.10), Color(0.08, 0.08, 0.16), rim]
		Z_TERR:
			return [Color(0.10, 0.095, 0.20), Color(0.18, 0.17, 0.33), rim]
		_:
			return [Color(0.07, 0.07, 0.15), Color(0.13, 0.13, 0.26), rim]
