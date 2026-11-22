shader_type spatial;
render_mode cull_disabled;
#include "res://shaders/paint/paint.gdshaderinc"
// Пучок травы мазками: перекрещенные карточки с текстурой штрихов, без одиночных волосков.
uniform sampler2D strokes_tex : filter_linear_mipmap, repeat_disable;
uniform vec3 col_root = vec3(0.28, 0.38, 0.13);
uniform vec3 col_tip = vec3(0.5, 0.56, 0.22);
uniform float wind = 0.5;
uniform float snow = 0.0;
uniform float dry = 0.0;
uniform vec3 hero_pos = vec3(0.0, -1000.0, 0.0);
varying float hgt;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	hgt = 1.0 - UV.y;
	float t = TIME * 1.4 + w.x * 0.3 + w.z * 0.25;
	float k = 0.07 * (0.5 + wind) * hgt;
	VERTEX.x += sin(t) * k;
	VERTEX.z += cos(t * 0.9) * k * 0.7;
	vec2 dv = w.xz - hero_pos.xz;
	float d = length(dv);
	float near = (1.0 - smoothstep(0.2, 0.8, d)) * step(abs(w.y - hero_pos.y + 1.0), 1.5);
	VERTEX += inverse(mat3(MODEL_MATRIX)) * vec3(dv.x / max(d, 0.001), -0.5, dv.y / max(d, 0.001)) * near * hgt * 0.35;
	VERTEX.y *= max(0.0, 1.0 - snow * 1.5);
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	vec4 s = texture(strokes_tex, UV);
	vec3 c = mix(lin(col_root), lin(col_tip), smoothstep(0.0, 1.0, hgt) * (0.7 + s.g * 0.5)) * (0.85 + COLOR.r * 0.3);
	c = mix(c, lin(vec3(0.78, 0.66, 0.38)) * (0.6 + hgt * 0.5), dry);
	ALBEDO = c;
	ALPHA = s.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	BACKLIGHT = c * 0.4;
}
