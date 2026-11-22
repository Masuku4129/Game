shader_type spatial;
render_mode skip_vertex_transform, cull_disabled;
#include "res://shaders/paint/paint.gdshaderinc"
// Мазки листвы: каждая вершина кроны — карточка-мазок, повёрнутая к камере.
// Нормаль берётся от центра облака, поэтому крона освещается как цельный объём, а край рваный.
uniform sampler2D brush : filter_linear_mipmap, repeat_disable;
uniform vec3 col_dark = vec3(0.12, 0.22, 0.14);
uniform vec3 col_mid = vec3(0.30, 0.46, 0.22);
uniform vec3 col_light = vec3(0.62, 0.70, 0.32);
uniform float wind = 0.5;
uniform float snow = 0.0;
uniform float autumn = 0.0;
uniform vec3 col_autumn = vec3(0.85, 0.55, 0.15);
varying vec3 wn;
varying float shade;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * (0.8 + wind) + w.x * 0.3 + w.z * 0.25;
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float sz = UV2.x * length(MODEL_MATRIX[0].xyz);
	float rot = UV2.y + sin(t) * 0.08 * (0.5 + wind);
	vec2 c = UV * 2.0 - 1.0;
	c = mat2(vec2(cos(rot), sin(rot)), vec2(-sin(rot), cos(rot))) * c;
	vp.xy += c * sz;
	VERTEX = vp.xyz;
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	shade = COLOR.r;
}

void fragment() {
	vec4 b = texture(brush, UV);
	float up = wn.y * 0.5 + 0.5;
	float g = clamp(up * 1.0 + (b.g - 0.5) * 0.6 + shade * 0.25 - 0.2, 0.0, 1.0);
	vec3 c = g < 0.5 ? mix(lin(col_dark), lin(col_mid), g * 2.0) : mix(lin(col_mid), lin(col_light), g * 2.0 - 1.0);
	c = mix(c, mix(lin(col_autumn) * 0.7, lin(col_autumn), g), autumn);
	c = mix(c, vec3(0.9, 0.93, 0.97), smoothstep(0.6, 0.85, wn.y + b.g * 0.2) * snow);
	ALBEDO = c;
	ALPHA = b.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	BACKLIGHT = c * 0.3;
}
