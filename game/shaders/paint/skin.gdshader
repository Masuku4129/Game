shader_type spatial;
render_mode cull_back;
#include "res://shaders/paint/paint.gdshaderinc"
// Текстурированная модель (кожа, волосы) с живописным светом мира. Вершинный цвет — оттенок.
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform bool use_tex = true;
uniform vec3 tint = vec3(1.0);
uniform bool use_vc = false;
uniform float alpha_cut = 0.0;
uniform float wet = 0.0;
varying vec3 wn;

void vertex() {
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec4 t = use_tex ? texture(tex, UV) : vec4(1.0);
	vec3 c = t.rgb * lin(tint);
	if (use_vc) {
		c *= lin(COLOR.rgb);
	}
	if (!use_tex) {
		float s = vnoise(vec2(UV.x * 9.0, UV.y * 2.2)) * 0.55 + vnoise(vec2(UV.x * 23.0, UV.y * 5.0)) * 0.45;
		c *= mix(0.85, 1.1, s);
	}
	ALBEDO = c * (1.0 - wet * 0.25);
	if (alpha_cut > 0.0) {
		ALPHA = t.a;
		ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	}
	ROUGHNESS = mix(0.9, 0.5, wet);
	SPECULAR = 0.2;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = c * rim * 0.15;
}
