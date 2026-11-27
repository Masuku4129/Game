shader_type spatial;
render_mode cull_disabled;
#include "res://shaders/paint/paint.gdshaderinc"
#include "res://shaders/fade.gdshaderinc"
// Кора: базовый цвет и мазки; у берёзы — тёмные чечевички (COLOR.g = 1).
uniform vec3 col = vec3(0.35, 0.25, 0.18);
uniform vec3 col2 = vec3(0.22, 0.16, 0.12);
uniform float birch = 0.0;
uniform bool no_fade = false;
uniform float snow = 0.0;
uniform float wet = 0.0;
// подгрызенное дерево: ниже clip_y (по модели) коры нет
uniform float clip_y = -10000.0;
varying vec3 wp;
varying float ly;
varying vec3 wn;
varying float vis;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	ly = VERTEX.y;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vis = dist_vis(INSTANCE_CUSTOM, MODEL_MATRIX[3].xyz);
	if (abs(vis) < 0.001) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	if (ly < clip_y || vis_discard(vis, FRAGCOORD.xy) || (!no_fade && fade_discard(wp, FRAGCOORD.xy))) {
		discard;
	}
	float s = vnoise(vec2(UV.x * 6.0, UV.y * 1.2)) * 0.6 + vnoise(vec2(UV.x * 14.0, UV.y * 3.0)) * 0.4;
	vec3 c = mix(lin(col2), lin(col), s);
	float vertical_grain = vnoise(vec2(UV.x * 13.0, UV.y * 1.7));
	float fine_grain = vnoise(vec2(UV.x * 34.0, UV.y * 4.0));
	float fissure = smoothstep(0.72, 0.88, vnoise(vec2(UV.x * 19.0, UV.y * 1.3))) * (1.0 - smoothstep(0.88, 0.97, fine_grain));
	float bark_ridge = sin(UV.x * 58.0 + vertical_grain * 4.0) * 0.5 + 0.5;
	c *= mix(0.76, 1.13, vertical_grain);
	c *= mix(0.88, 1.08, bark_ridge);
	c = mix(c, c * 0.48, fissure * 0.35);
	if (birch > 0.5) {
		float d = step(0.78, vnoise(vec2(UV.x * 5.0, UV.y * 7.0))) * step(0.3, vnoise(vec2(UV.x * 20.0, UV.y * 2.0)));
		c = mix(c, vec3(0.012), d);
		float birch_noise = vnoise(vec2(UV.x * 13.0, UV.y * 6.0));
		float stripe = smoothstep(0.58, 0.78, vnoise(vec2(UV.x * 3.8, UV.y * 10.0))) * smoothstep(0.35, 0.7, birch_noise);
		c = mix(c, vec3(0.32, 0.30, 0.26), stripe * 0.28);
	}
	c = mix(c, vec3(0.9, 0.93, 0.97), smoothstep(0.6, 0.9, wn.y) * snow);
	c *= 1.0 - wet * 0.18;
	ALBEDO = cartoon(c);
	ROUGHNESS = mix(1.0, 0.68, wet);
	SPECULAR = wet * 0.08;
}
