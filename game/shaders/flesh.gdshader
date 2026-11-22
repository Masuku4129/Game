shader_type spatial;
render_mode cull_back;
// Мясо, жир, изнанка шкуры, кости (модели hunt_models.gd). Цвет — из вершин (sRGB),
// COLOR.a — влажность (блеск). Волокна мышц — вытянутый шум по UV.
uniform float fibre = 1.0;      // 0 — гладко (кость, жир), 1 — волокна мяса
uniform float cooked = 0.0;     // жареное: темнее и коричневее
uniform float dry = 0.0;        // заветренное: темнее, без блеска
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
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 base = lin(COLOR.rgb);
	float f = vnoise(vec2(UV.x * 7.0, UV.y * 60.0)) * 0.6 + vnoise(vec2(UV.x * 19.0, UV.y * 140.0)) * 0.4;
	float big = vnoise(UV * 6.0);
	vec3 c = base * mix(1.0, mix(0.72, 1.15, f), fibre) * mix(0.9, 1.08, big);
	vec3 ck = lin(vec3(0.52, 0.32, 0.17)) * mix(0.75, 1.15, f);
	c = mix(c, ck, cooked * fibre);
	c *= 1.0 - dry * 0.35;
	ALBEDO = c;
	float wet = COLOR.a * (1.0 - dry) * (1.0 - cooked * 0.6);
	ROUGHNESS = mix(0.9, 0.4, wet);
	SPECULAR = 0.5;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float t = smoothstep(-0.05, 0.45, ndl) * mix(0.25, 1.0, ATTENUATION);
	vec3 c = mix(lin(vec3(0.55, 0.62, 0.85)) * 0.5, vec3(1.0, 0.95, 0.85), t);
	DIFFUSE_LIGHT += c * LIGHT_COLOR / PI;
	vec3 h = normalize(LIGHT + VIEW);
	float sh = pow(max(dot(NORMAL, h), 0.0), mix(8.0, 90.0, 1.0 - ROUGHNESS)) * (1.0 - ROUGHNESS);
	SPECULAR_LIGHT += sh * LIGHT_COLOR * ATTENUATION * 0.5;
}
