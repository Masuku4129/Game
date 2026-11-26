shader_type spatial;
render_mode cull_disabled;
#include "res://shaders/paint/paint.gdshaderinc"
#include "res://shaders/fade.gdshaderinc"
// Текстурированные GLB-модели леса (models/environment): тот же живописный свет, растворение
// перед камерой/по дальности, ветер, снег, влага, осень и листопад, что и у процедурных крон.
uniform sampler2D base_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform float foliage = 0.0;      // 1 — карточки хвои/листвы с альфа-маской
uniform float autumn_k = 0.0;     // 1 — лиственная порода: желтеет и сбрасывает листву
uniform vec3 col_autumn = vec3(0.85, 0.55, 0.15);
uniform float alpha_cut = 0.5;
uniform float sway = 0.03;
uniform bool no_fade = false;
uniform float snow = 0.0;
uniform float wet = 0.0;
uniform float autumn = 0.0;
uniform float leaf_drop = 0.0;
uniform float wind = 0.5;
varying vec3 wp;
varying vec3 wn;
varying float vis;
varying float tree_r;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * (0.8 + wind) + w.x * 0.15 + w.z * 0.12;
	float k = sway * (0.4 + wind) * max(VERTEX.y, 0.0) * 0.15 * mix(0.35, 1.0, foliage);
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
	if (vis_discard(vis, FRAGCOORD.xy) || (!no_fade && fade_discard(wp, FRAGCOORD.xy))) {
		discard;
	}
	vec4 tx = texture(base_texture, UV);
	if (foliage > 0.5) {
		if (tx.a < alpha_cut) {
			discard;
		}
		// листопад: часть карточек исчезает по хешу ячейки в мире
		if (whash3(floor(wp * 2.3)) < leaf_drop * autumn_k) {
			discard;
		}
	}
	vec3 c = tx.rgb * COLOR.rgb;
	c *= mix(0.86, 1.12, vnoise(wp.xz * 4.0 + wp.y * 1.5));
	if (foliage > 0.5) {
		float g = clamp(dot(c, vec3(0.3, 0.5, 0.2)) * 3.0, 0.0, 1.0);
		float a = clamp(autumn * autumn_k * (0.8 + tree_r * 0.45), 0.0, 1.0);
		c = mix(c, autumn_col(col_autumn, g, tree_r), a);
	}
	c *= 1.0 - wet * 0.15;
	float up = smoothstep(0.5, 0.8, wn.y + (vnoise(wp.xz * 3.0 + wp.y) - 0.5) * 0.3);
	c = mix(c, vec3(0.9, 0.93, 0.97), up * snow);
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	if (foliage > 0.5) {
		BACKLIGHT = c * 0.3;
	}
}
