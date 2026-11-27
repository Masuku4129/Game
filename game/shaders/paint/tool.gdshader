shader_type spatial;
render_mode cull_disabled;
#include "res://shaders/paint/paint.gdshaderinc"
// Вещи в руках и на поясе: цвет вершин (sRGB), мазки вдоль волокон (UV.y — вдоль длины).
// COLOR.a < 1 — камень (кремень): чуть глянцевее, без волокон.
uniform float wet = 0.0;
varying vec3 wn;

void vertex() {
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float stone = 1.0 - COLOR.a;
	float grain = vnoise(vec2(UV.x * 7.0, UV.y * 1.3)) * 0.55 + vnoise(vec2(UV.x * 19.0, UV.y * 3.5)) * 0.45;
	float blot = vnoise(UV * 11.0) * 0.6 + vnoise(UV * 27.0) * 0.4;
	float s = mix(grain, blot, stone);
	vec3 c = lin(COLOR.rgb) * mix(0.8, 1.12, s);
	ALBEDO = cartoon(c * (1.0 - wet * 0.25));
	ROUGHNESS = mix(0.92, 0.5, stone);
	SPECULAR = mix(0.12, 0.35, stone);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = c * rim * 0.12;
}
