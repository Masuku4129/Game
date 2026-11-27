shader_type spatial;
render_mode cull_disabled;
#include "res://shaders/paint/paint.gdshaderinc"
#include "res://shaders/fade.gdshaderinc"
#include "res://shaders/weather.gdshaderinc"
// Карточки хвои, листвы, травы: альфа-отсечение, качание на ветру, осень, листопад, снег.
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float sway = 0.05;
uniform float yellow_k = 0.0;
uniform float drop_k = 0.0;
uniform float fall_red = 0.0;
varying vec3 wpf;
varying float upn;
varying vec3 opos;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * (1.0 + wind * 0.6) + w.x * 0.21 + w.z * 0.17;
	float k = sway * (0.4 + wind * 1.2) * max(VERTEX.y, 0.0);
	VERTEX.x += sin(t) * k + wind * k * 0.6;
	VERTEX.z += cos(t * 0.83) * k;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * hero_push(w, clamp(VERTEX.y, 0.0, 1.5), TIME);
	wpf = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	upn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y;
	opos = MODEL_MATRIX[3].xyz;
}

void fragment() {
	if (fade_discard(wpf, FRAGCOORD.xy)) {
		discard;
	}
	// листопад: листья пропадают кучками, у каждого дерева чуть в свой срок
	float tree_r = whash(floor(opos));
	float leaf_r = whash(floor(wpf * 1.3));
	float dr = leaf_drop * drop_k * (1.15 + (tree_r - 0.5) * 0.5);
	if (dr > 0.001 && leaf_r < dr) {
		discard;
	}
	vec4 c = textureLod(tex, UV, 0.9);
	vec3 col = c.rgb * tint.rgb * COLOR.rgb;
	// осень: жёлтые и рыжие оттенки у лиственных, у травы бурые
	float a = clamp(autumn * yellow_k * (0.75 + tree_r * 0.6), 0.0, 1.0);
	float l = dot(col, vec3(0.3, 0.55, 0.15));
	vec3 fall = mix(mix(vec3(1.25, 0.95, 0.3), vec3(1.15, 0.55, 0.2), tree_r), vec3(1.25, 0.32, 0.2), fall_red * (0.5 + tree_r * 0.5)) * l * 1.35;
	col = mix(col, fall, a);
	// снег лежит на верхних сторонах
	float s = snow_cover(upn * 0.6 + 0.4, wpf) * 0.85;
	col = mix(col, vec3(0.88, 0.9, 0.94), s);
	col *= 1.0 - wet * 0.18;
	ALBEDO = cartoon(col);
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.45;
}
