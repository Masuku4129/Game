shader_type spatial;
render_mode cull_back;
#include "res://shaders/paint/paint.gdshaderinc"
// Шерсть мазками: цвет из вершин (спина темнее, брюхо светлее), штрихи вдоль тела,
// мягкий живописный свет и тёплый контровой край. Полосы для тигра.
uniform float stripes = 0.0;
// узор по маске COLOR.a: 1 — пятна (рысь, кабарга), 2 — поперечная рябь (глухарка)
uniform float spots = 0.0;
uniform vec3 tint = vec3(1.0);
uniform bool use_vc = true;
uniform float snow = 0.0;
uniform float wet = 0.0;
varying vec3 wn;

void vertex() {
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 base = use_vc ? COLOR.rgb : tint;
	base = lin(base);
	float s = vnoise(vec2(UV.x * 7.0, UV.y * 2.0));
	vec3 c = base * mix(0.78, 1.12, s);
	if (stripes > 0.5) {
		float st = sin(UV.y * 26.0 + vnoise(UV * vec2(4.0, 9.0)) * 5.0 + UV.x * 3.0);
		float m = smoothstep(0.55, 0.7, st) * smoothstep(0.15, 0.45, COLOR.g);
		c = mix(c, lin(vec3(0.08, 0.06, 0.05)), m);
	}
	if (spots > 0.5) {
		float pm = COLOR.a;
		if (spots < 1.5) {
			float sp = vnoise(UV * vec2(34.0, 15.0)) * 0.75 + vnoise(UV * vec2(70.0, 30.0)) * 0.25;
			c *= 1.0 - smoothstep(0.6, 0.7, sp) * 0.45 * pm;
		} else {
			float br = sin(UV.y * 140.0 + vnoise(UV * vec2(14.0, 40.0)) * 4.0) * 0.6 + vnoise(UV * vec2(40.0, 60.0)) * 0.8;
			c *= 1.0 - smoothstep(0.45, 0.9, br) * 0.35 * pm;
		}
	}
	c = mix(c, vec3(0.85, 0.88, 0.92), smoothstep(0.55, 0.9, wn.y) * snow * 0.6);
	c *= 1.0 - wet * 0.25;
	ALBEDO = cartoon(c);
	ROUGHNESS = mix(0.95, 0.55, wet);
	SPECULAR = 0.15;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = base * rim * 0.12;
}
