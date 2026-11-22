shader_type spatial;
render_mode cull_back;
// Освежёванная туша на модели самого зверя: шкура снята с туловища и верха ног, на голове
// и нижних частях ног мех остаётся (как при настоящей разделке). На боках — рёбра под плёнкой,
// по хребту — белые сухожилия и жир, на окороках и лопатках — волокна мышц.
// Зоны — по положению вершины в рамке сетки (box_pos/box_size), вперёд — +Z модели.
uniform vec3 box_pos = vec3(-0.5, 0.0, -0.5);
uniform vec3 box_size = vec3(1.0);
uniform float head_cut = 0.8;   // доля длины: дальше вперёд — голова в шкуре
uniform float leg_cut = 0.28;   // доля высоты: ниже — ноги в шкуре
uniform float fwd = 1.0;        // 1 — голова к +Z, -1 — к −Z
uniform bool use_vc = true;     // мех: цвет из вершин (модели-скелеты) или tint (готовые модели)
uniform vec3 tint = vec3(0.5, 0.4, 0.3);
uniform float dry = 0.0;        // 0 — свежая, 1 — обветренные, объеденные остатки
uniform float skinned = 1.0;    // 0 — ещё в шкуре (плавный переход при свежевании)
varying vec3 vp;
varying vec3 wn;

vec3 lin(vec3 c) { return pow(c, vec3(2.2)); }
float h21(vec2 p) {
	p = mod(p, 1024.0);
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	vp = VERTEX;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = (vp - box_pos) / box_size;
	if (fwd < 0.0) {
		n.z = 1.0 - n.z;
	}
	// мех, как у живого (тот же мазок, что в fur.gdshader)
	vec3 fb = lin(use_vc ? COLOR.rgb : tint);
	float s = vnoise(vec2(UV.x * 9.0, UV.y * 2.2)) * 0.55 + vnoise(vec2(UV.x * 23.0, UV.y * 5.0)) * 0.45;
	vec3 fur = fb * mix(0.78, 1.12, s);
	// граница шкуры: рваный надрез ножом
	float jag = (vnoise(vec2(n.x * 40.0, n.y * 40.0)) - 0.5) * 0.03 + (vnoise(vec2(n.y * 9.0, n.x * 9.0)) - 0.5) * 0.04;
	float hz = n.z - (head_cut + jag);
	float ly = (leg_cut + jag) - n.y;
	float keep = max(step(0.0, hz), step(0.0, ly));
	// рога и макушка над шеей (рога загнуты назад — дальше линии отреза)
	keep = max(keep, step(0.9, n.y) * step(0.5, n.z));
	// снятие шкуры идёт от брюха к хребту: skinned 0..1
	float edge_d = min(abs(hz), abs(ly));
	if (skinned < 0.999) {
		keep = max(keep, step(skinned * 1.15, n.y + jag));
	}
	// мясо
	float fib = vnoise(vec2(n.z * 90.0, (n.y + n.x) * 14.0)) * 0.6 + vnoise(vec2(n.z * 210.0, (n.y - n.x) * 30.0)) * 0.4;
	float grp = vnoise(vec2(n.z * 7.0, n.y * 5.0 + n.x * 3.0));
	vec3 muscle = mix(lin(vec3(0.22, 0.03, 0.025)), lin(vec3(0.5, 0.1, 0.06)), fib * 0.65 + grp * 0.35);
	// плёнка-фасция поверх мышц: перламутровые пятна
	float fas = smoothstep(0.55, 0.8, vnoise(vec2(n.z * 11.0 + n.x * 5.0, n.y * 13.0)));
	vec3 c = mix(muscle, lin(vec3(0.72, 0.58, 0.5)), fas * 0.22);
	// рёбра на боках: светлые дуги под плёнкой, между ними тёмные межрёберные мышцы
	float ribz = smoothstep(0.36, 0.42, n.z) * (1.0 - smoothstep(0.6, 0.66, n.z));
	float riby = smoothstep(0.42, 0.52, n.y) * (1.0 - smoothstep(0.78, 0.86, n.y));
	float side = smoothstep(0.08, 0.22, abs(n.x - 0.5));
	float rw = sin((n.z + 0.01 * sin(n.y * 9.0)) * 6.2832 * 30.0);
	float rib = smoothstep(0.55, 0.9, rw) * ribz * riby * side * (0.6 + 0.4 * vnoise(vec2(n.y * 20.0, n.z * 5.0)));
	float gap = smoothstep(-0.2, -0.75, rw) * ribz * riby * side;
	c = mix(c, lin(vec3(0.76, 0.6, 0.54)), rib * 0.55);
	c = mix(c, lin(vec3(0.17, 0.02, 0.02)), gap * 0.35);
	// хребет: белые сухожилия и жир полосой
	float back = smoothstep(0.84, 0.94, n.y + jag) * (1.0 - step(0.0, hz));
	float sin_ = smoothstep(0.35, 0.75, vnoise(vec2(n.z * 40.0, n.x * 6.0)));
	c = mix(c, mix(lin(vec3(0.8, 0.7, 0.6)), lin(vec3(0.9, 0.84, 0.74)), sin_), back * 0.5);
	// у надреза — тонкая полоса подкожного жира
	c = mix(c, lin(vec3(0.9, 0.84, 0.7)), (1.0 - smoothstep(0.0, 0.025, edge_d)) * (1.0 - keep) * 0.7);
	// остатки: обветренное тёмное мясо, местами кости
	float bone = smoothstep(0.62, 0.7, vnoise(vec2(n.z * 18.0, n.y * 18.0 + n.x * 4.0))) * dry;
	c = mix(c, c * vec3(0.55, 0.42, 0.4), dry * 0.8);
	c = mix(c, lin(vec3(0.82, 0.76, 0.66)), max(bone, rib * dry * 0.8));
	vec3 col = mix(c, fur, keep);
	ALBEDO = col;
	ROUGHNESS = mix(mix(0.5, 0.9, dry), 0.95, keep);
	SPECULAR = 0.5;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float t = smoothstep(-0.05, 0.45, ndl) * mix(0.25, 1.0, ATTENUATION);
	vec3 c = mix(lin(vec3(0.55, 0.62, 0.85)) * 0.5, vec3(1.0, 0.95, 0.85), t);
	DIFFUSE_LIGHT += c * LIGHT_COLOR / PI;
	vec3 h = normalize(LIGHT + VIEW);
	float sh = pow(max(dot(NORMAL, h), 0.0), mix(8.0, 90.0, 1.0 - ROUGHNESS)) * (1.0 - ROUGHNESS);
	SPECULAR_LIGHT += sh * LIGHT_COLOR * ATTENUATION * 0.2;
}
