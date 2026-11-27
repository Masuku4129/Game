shader_type spatial;
render_mode skip_vertex_transform, cull_disabled;
#include "res://shaders/paint/paint.gdshaderinc"
#include "res://shaders/fade.gdshaderinc"
// Мазки листвы: каждая вершина кроны — карточка-мазок, повёрнутая к камере.
// Нормаль берётся от центра облака, поэтому крона освещается как цельный объём, а край рваный.
uniform sampler2D brush : filter_linear_mipmap, repeat_disable;
uniform vec3 col_dark = vec3(0.18, 0.26, 0.16);
uniform vec3 col_mid = vec3(0.36, 0.52, 0.24);
uniform vec3 col_light = vec3(0.70, 0.78, 0.38);
uniform float wind = 0.5;
uniform float snow = 0.0;
uniform float autumn = 0.0;
uniform float autumn_k = 1.0;
uniform float leaf_drop = 0.0;
uniform vec3 col_autumn = vec3(0.85, 0.55, 0.15);
uniform float wet = 0.0;
uniform float bloom_k = 0.0;
uniform float blossom = 0.0;
uniform vec3 col_bloom = vec3(0.95, 0.94, 0.9);
varying float vis;
varying float tree_r;
varying vec3 wn;
varying vec3 wpc;
varying float drop_h;
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
	wpc = (INV_VIEW_MATRIX * vec4(vp.xyz, 1.0)).xyz;
	drop_h = fract(UV2.y * 7.31);
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	shade = COLOR.r;
	vis = dist_vis(INSTANCE_CUSTOM, MODEL_MATRIX[3].xyz);
	tree_r = whash3(floor(MODEL_MATRIX[3].xyz));
	if (abs(vis) < 0.001) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	if (vis_discard(vis, FRAGCOORD.xy) || fade_discard(wpc, FRAGCOORD.xy) || drop_h < leaf_drop * autumn_k) {
		discard;
	}
	vec4 b = texture(brush, UV);
	float up = wn.y * 0.5 + 0.5;
	float g = clamp(up * 1.0 + (b.g - 0.5) * 0.6 + shade * 0.25 - 0.2, 0.0, 1.0);
	vec3 c = g < 0.5 ? mix(lin(col_dark), lin(col_mid), g * 2.0) : mix(lin(col_mid), lin(col_light), g * 2.0 - 1.0);
	float color_noise = vnoise(wpc.xz * 4.7 + wpc.y * 1.9) * 0.65 + vnoise(wpc.xz * 11.0 - wpc.y * 2.3) * 0.35;
	float leaf_speckle = vnoise(wpc.xz * 21.0 + vec2(wpc.y * 7.0, -wpc.y * 3.0));
	c *= mix(0.82, 1.12, color_noise);
	c = mix(c, c * vec3(1.08, 1.02, 0.84), smoothstep(0.62, 0.9, leaf_speckle) * 0.12);
	c = mix(c, autumn_col(col_autumn, g, tree_r), clamp(autumn * autumn_k * (0.8 + tree_r * 0.45), 0.0, 1.0));
	c = mix(c, lin(col_bloom) * (0.8 + g * 0.25), bloom_k * blossom * step(0.45, fract(drop_h * 3.7)));
	c *= 1.0 - wet * 0.15;
	c = mix(c, vec3(0.9, 0.93, 0.97), smoothstep(0.6, 0.85, wn.y + b.g * 0.2) * snow);
	ALBEDO = cartoon(c);
	ALPHA = b.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	BACKLIGHT = c * 0.3;
}
