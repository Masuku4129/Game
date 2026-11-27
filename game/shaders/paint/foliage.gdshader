shader_type spatial;
render_mode cull_disabled;
#include "res://shaders/paint/paint.gdshaderinc"
#include "res://shaders/fade.gdshaderinc"
// Крона пятнами: цвет от тени к свету по высоте и нормали, мазки, лёгкое покачивание.
uniform vec3 col_dark = vec3(0.18, 0.26, 0.16);
uniform vec3 col_mid = vec3(0.36, 0.52, 0.24);
uniform vec3 col_light = vec3(0.70, 0.78, 0.38);
uniform float sway = 0.04;
uniform float wind = 0.5;
uniform float snow = 0.0;
uniform float autumn = 0.0;
uniform float autumn_k = 1.0;
uniform float leaf_drop = 0.0;
uniform vec3 col_autumn = vec3(0.85, 0.55, 0.15);
uniform float wet = 0.0;
// цветение (черёмуха): bloom_k — доля цветков в кроне, blossom — сезон (поздняя весна)
uniform float bloom_k = 0.0;
uniform float blossom = 0.0;
uniform vec3 col_bloom = vec3(0.95, 0.94, 0.9);
varying vec3 wp;
varying vec3 wn;
varying float vis;
varying float tree_r;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * (0.8 + wind) + w.x * 0.15 + w.z * 0.12;
	float k = sway * (0.4 + wind) * max(VERTEX.y, 0.0) * 0.15;
	VERTEX.x += sin(t) * k;
	VERTEX.z += cos(t * 0.8) * k;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vis = dist_vis(INSTANCE_CUSTOM, MODEL_MATRIX[3].xyz);
	tree_r = whash3(floor(MODEL_MATRIX[3].xyz));
	if (abs(vis) < 0.001) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	if (vis_discard(vis, FRAGCOORD.xy) || fade_discard(wp, FRAGCOORD.xy) || leaf_drop * autumn_k > 0.6) {
		discard;
	}
	float s = strokes(wp.xz * 0.9 + wp.y * 0.55);
	float up = wn.y * 0.5 + 0.5;
	float g_raw = clamp(up * 0.82 + (s - 0.5) * 0.32 + COLOR.r * 0.22 - 0.12, 0.0, 1.0);
	// Stylized foliage: five broad color bands keep silhouettes readable on mobile.
	float g = floor(g_raw * 4.0 + 0.5) / 4.0;
	vec3 c = g < 0.5 ? mix(lin(col_dark), lin(col_mid), g * 2.0) : mix(lin(col_mid), lin(col_light), g * 2.0 - 1.0);
	float canopy_noise = vnoise(wp.xz * 1.15 + wp.y * 0.55) * 0.88 + vnoise(wp.xz * 3.1) * 0.12;
	// Large painted patches instead of noisy, muddy surface breakup.
	c *= mix(0.88, 1.10, canopy_noise);
	c = mix(c, autumn_col(col_autumn, g, tree_r), clamp(autumn * autumn_k * (0.8 + tree_r * 0.45), 0.0, 1.0) * COLOR.g);
	c = mix(c, lin(col_bloom) * (0.75 + g * 0.3), bloom_k * blossom * smoothstep(0.35, 0.6, s + tree_r * 0.3));
	c *= 1.0 - wet * 0.15;
	c = mix(c, vec3(0.9, 0.93, 0.97), smoothstep(0.42, 0.74, wn.y + s * 0.2) * snow);
	ALBEDO = cartoon(c);
	ROUGHNESS = 0.92;
	SPECULAR = 0.0;
	BACKLIGHT = c * 0.35;
}
