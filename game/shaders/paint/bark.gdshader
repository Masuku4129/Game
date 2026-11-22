shader_type spatial;
render_mode cull_disabled;
#include "res://shaders/paint/paint.gdshaderinc"
// Кора: базовый цвет и мазки; у берёзы — тёмные чечевички (COLOR.g = 1).
uniform vec3 col = vec3(0.35, 0.25, 0.18);
uniform vec3 col2 = vec3(0.22, 0.16, 0.12);
uniform float birch = 0.0;
uniform float snow = 0.0;
varying vec3 wp;
varying vec3 wn;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float s = vnoise(vec2(UV.x * 6.0, UV.y * 1.2)) * 0.6 + vnoise(vec2(UV.x * 14.0, UV.y * 3.0)) * 0.4;
	vec3 c = mix(lin(col2), lin(col), s);
	if (birch > 0.5) {
		float d = step(0.78, vnoise(vec2(UV.x * 5.0, UV.y * 7.0))) * step(0.3, vnoise(vec2(UV.x * 20.0, UV.y * 2.0)));
		c = mix(c, vec3(0.012), d);
	}
	c = mix(c, vec3(0.9, 0.93, 0.97), smoothstep(0.6, 0.9, wn.y) * snow);
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
