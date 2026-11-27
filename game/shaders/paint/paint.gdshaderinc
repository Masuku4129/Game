vec3 lin(vec3 c) { return pow(c, vec3(2.2)); }
// Живописный свет: мягкая «ступень» света вместо физически точного затухания,
// тени уходят в холодный цвет, освещённые стороны — в тёплый.
uniform vec3 shade_cool = vec3(0.55, 0.62, 0.85);
uniform float ramp_lo = -0.05;
uniform float ramp_hi = 0.45;
uniform float shadow_fill = 0.5;

void light() {
	float ndl = dot(NORMAL, LIGHT);
	// мультяшный свет: три ступени (тень / полутень / свет) с узким переходом — дёшево и читаемо
	float band = smoothstep(ramp_lo - 0.02, ramp_lo + 0.05, ndl) * 0.55 + smoothstep(ramp_hi - 0.04, ramp_hi + 0.04, ndl) * 0.45;
	float t = band * mix(0.3, 1.0, smoothstep(0.3, 0.65, ATTENUATION));
	// тень не проваливается в черноту: холодная подсветка от неба (shadow_fill)
	vec3 c = mix(lin(shade_cool) * shadow_fill, vec3(1.0, 0.95, 0.85), t);
	DIFFUSE_LIGHT += c * LIGHT_COLOR / PI;
}

// Мазки: вытянутый шум для живописной неровности цвета.
// хеш без sin(): на мобильных GPU sin больших чисел неточен и даёт квадраты
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
float strokes(vec2 p) {
	// одно пятно шума вместо двух слоёв: мультяшная заливка дешевле и чище
	return vnoise(vec2(p.x * 0.35 + p.y * 0.2, p.y * 1.6 - p.x * 0.3));
}

float whash3(vec3 p) { p = mod(p, 1024.0); p = fract(p * 0.1031); p += dot(p, p.zyx + 31.32); return fract((p.x + p.y) * p.z); }
// Осенний цвет кроны: у каждого дерева свой оттенок (r — хеш дерева) — от лимонного до багряного.
uniform float autumn_red = 0.55;
vec3 autumn_col(vec3 base, float g, float r) {
	vec3 a = lin(base);
	a = mix(a, lin(vec3(0.86, 0.72, 0.26)), (1.0 - smoothstep(0.0, 0.35, r)) * 0.5);
	a = mix(a, lin(vec3(0.72, 0.3, 0.14)), smoothstep(0.6, 1.0, r) * autumn_red);
	return a * mix(0.62, 1.05, g);
}
