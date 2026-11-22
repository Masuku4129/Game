extends MultiMeshInstance3D
## Кровь на земле: капли, мазки и лужи — одна MultiMesh плоских пятен (кольцевой буфер).
## Форма пятна рисуется в шейдере (капля с брызгами, мазок, лужа с рваным краем), цвет —
## по возрасту (свежая алая, к суткам бурая) и по подложке: на снегу ярко-красная с розовым
## ореолом впитавшейся крови, на земле тёмная и почти незаметная. Пятна тают по своему сроку.
## Время — игровые часы (hunt.now_h()); позицию и наклон по земле считает вызывающий.

const CAP := 1600               # пятен всего; старые затираются новыми
const SHAPE_DROP := 0.0
const SHAPE_SMEAR := 0.5
const SHAPE_POOL := 1.0

var mm := MultiMesh.new()
var head := 0
var used := 0
var mat := ShaderMaterial.new()
# для обновления высоты и засыпания снегом: [x, z, глубина снега при появлении, размер, жив до (ч)]
var info: Array = []

func _init() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(1, 1)
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = pm
	mm.instance_count = CAP
	mm.visible_instance_count = 0
	multimesh = mm
	mat.shader = load("res://shaders/blood.gdshader")
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	info.resize(CAP)
	# пятна разбросаны по всей карте: не отсекать по рамке
	custom_aabb = AABB(Vector3(-400, -100, -400), Vector3(800, 300, 800))

## Пятно в точке p (уже на поверхности), n — нормаль земли, size — поперечник (м),
## shape — SHAPE_*, snow_k — 0 земля … 1 снег, life — сколько игровых часов видно,
## yaw — поворот пятна (мазок вытянут вдоль него), stretch — удлинение мазка.
func add(p: Vector3, n: Vector3, size: float, shape: float, snow_k: float, now_h: float, life: float, yaw: float = -1.0, stretch: float = 1.0, power: float = 1.0, sd0: float = 0.0) -> int:
	var i := head
	head = (head + 1) % CAP
	used = mini(used + 1, CAP)
	mm.visible_instance_count = used
	if yaw < 0.0:
		yaw = randf() * TAU
	var up := n.normalized()
	var fw := Vector3(sin(yaw), 0, cos(yaw))
	var rt := up.cross(fw).normalized()
	fw = rt.cross(up).normalized()
	var b := Basis(rt * size, up, fw * size * stretch)
	mm.set_instance_transform(i, Transform3D(b, p))
	mm.set_instance_color(i, Color(shape, clampf(power, 0.0, 1.0), snow_k, randf()))
	mm.set_instance_custom_data(i, Color(now_h, life, 0.0, 0.0))
	info[i] = [p.x, p.z, sd0, size, now_h + life]
	return i

## Снять пятно (занесло снегом): срок жизни — уже истёк.
func hide_one(i: int) -> void:
	var c := mm.get_instance_custom_data(i)
	c.g = 0.0
	mm.set_instance_custom_data(i, c)
	info[i] = null

func set_time(now_h: float) -> void:
	mat.set_shader_parameter("now_h", now_h)
