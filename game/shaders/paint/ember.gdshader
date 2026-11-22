shader_type spatial;
render_mode unshaded, cull_disabled;
#include "res://shaders/paint/paint.gdshaderinc"
// Угли и зола: тёмные с тлеющими трещинами; glow — сила тления (0 — остывшая зола).
uniform float glow = 1.0;
varying vec3 wp;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float n = vnoise(wp.xz * 22.0 + wp.y * 9.0) * 0.6 + vnoise(wp.xz * 55.0) * 0.4;
	float pulse = 0.75 + 0.25 * sin(TIME * 2.0 + n * 9.0);
	float hot = smoothstep(0.62, 0.85, n) * glow * pulse * COLOR.r;
	vec3 ash = lin(vec3(0.16, 0.14, 0.13)) * (0.6 + n * 0.6);
	ash = mix(ash, lin(vec3(0.42, 0.4, 0.38)), (1.0 - COLOR.r) * smoothstep(0.4, 0.7, n) * 0.6);
	vec3 c = mix(ash * 0.35, lin(vec3(1.0, 0.36, 0.06)) * 2.0, hot);
	ALBEDO = c;
}
