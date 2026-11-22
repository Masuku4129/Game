shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;
// Кровь на руках и куртке героя (слой поверх модели, hunt.gd). COLOR.r — шум пятен по вершине,
// COLOR.g — насколько это место пачкается; amount — сколько крови (0..1).
uniform float amount = 0.0;

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

void fragment() {
	float n = COLOR.r * 0.7 + vnoise(UV * 90.0) * 0.3;
	float k = amount * COLOR.g;
	float m = smoothstep(1.0 - k * 1.1, 1.0 - k * 1.1 + 0.06, n);
	if (m < 0.01) {
		discard;
	}
	ALBEDO = mix(lin(vec3(0.32, 0.03, 0.03)), lin(vec3(0.2, 0.04, 0.03)), vnoise(UV * 40.0));
	ALPHA = m * 0.92;
	ROUGHNESS = 0.35;
	SPECULAR = 0.4;
}
