shader_type spatial;
// Крона дерева: комковатая форма (шум по нормали), переливы цвета, лёгкое покачивание.
uniform vec3 base_col : source_color = vec3(0.07, 0.20, 0.10);
uniform vec3 hi_col : source_color = vec3(0.30, 0.42, 0.12);
uniform float lump = 0.35;
varying vec3 wpos;
float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float n = vn(w.xz * 1.6 + w.y * 1.1);
	VERTEX += NORMAL * (n - 0.5) * 2.0 * lump;
	VERTEX.x += sin(TIME * 1.2 + w.x * 0.4 + w.z * 0.2) * 0.06;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float n = vn(wpos.xz * 2.2 + wpos.y * 1.7);
	float up = clamp(NORMAL.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 c = mix(base_col, hi_col, clamp(n * 0.6 + up * 0.5, 0.0, 1.0));
	c *= 0.65 + 0.5 * smoothstep(0.0, 6.0, wpos.y);
	ALBEDO = c;
	ROUGHNESS = 0.9;
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	EMISSION = hi_col * rim * 0.25;
}
