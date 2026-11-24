shader_type spatial;
render_mode unshaded, cull_disabled;
// Дно пропасти: тёмная фиолетовая дымка, медленные облака и далёкие огоньки.
varying vec3 wpos;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	return vn(p) * 0.55 + vn(p * 2.1 + 3.0) * 0.30 + vn(p * 4.3 + 9.0) * 0.15;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float c = fbm(p * 0.03 + vec2(TIME * 0.012, 0.0));
	float c2 = fbm(p * 0.08 - vec2(0.0, TIME * 0.02));
	vec3 deep = vec3(0.025, 0.022, 0.075);
	vec3 mid = vec3(0.095, 0.075, 0.21);
	vec3 hi = vec3(0.28, 0.21, 0.52);
	vec3 col = mix(deep, mid, smoothstep(0.30, 0.75, c));
	col = mix(col, hi, smoothstep(0.55, 0.92, c2) * 0.38);
	vec2 g = p * 0.16;
	vec2 id = floor(g);
	vec2 f = fract(g) - 0.5;
	vec2 o = (vec2(h21(id + 3.1), h21(id + 7.7)) - 0.5) * 0.7;
	float star = step(0.90, h21(id)) * smoothstep(0.10, 0.0, length(f - o));
	col += vec3(1.0, 0.70, 0.35) * star * 0.8;
	ALBEDO = col;
}
