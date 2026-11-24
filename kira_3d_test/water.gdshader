shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;
// Тёмная вода ручья: бегущая рябь, фиолетовый блик, блеск у краёв.
varying vec3 wpos;
float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wpos.xz;
	float t = TIME;
	float r1 = vn(p * vec2(1.3, 2.8) + vec2(t * 0.9, 0.0));
	float r2 = vn(p * vec2(3.1, 5.0) + vec2(-t * 0.6, t * 0.2));
	float rip = smoothstep(0.62, 0.9, r1 * 0.6 + r2 * 0.5);
	vec3 deep = vec3(0.03, 0.07, 0.14);
	vec3 shallow = vec3(0.07, 0.17, 0.25);
	vec3 c = mix(deep, shallow, r1 * 0.7);
	ALBEDO = c;
	ALPHA = 0.88;
	ROUGHNESS = 0.08;
	SPECULAR = 0.9;
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	EMISSION = vec3(0.35, 0.28, 0.75) * (rip * 0.35 + fres * 0.5);
}
