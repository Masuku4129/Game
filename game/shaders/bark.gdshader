shader_type spatial;
render_mode cull_back;
#include "res://shaders/paint/paint.gdshaderinc"
#include "res://shaders/fade.gdshaderinc"
#include "res://shaders/weather.gdshaderinc"
uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
varying vec3 wpf;
varying float upn;

void vertex() {
	wpf = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	upn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y;
}

void fragment() {
	if (fade_discard(wpf, FRAGCOORD.xy)) {
		discard;
	}
	vec3 col = textureLod(tex, UV, 1.2).rgb * tint.rgb * COLOR.rgb * (1.0 - wet * 0.3);
	col = mix(col, vec3(0.88, 0.9, 0.94), snow_cover(upn, wpf) * 0.9);
	ALBEDO = cartoon(col);
}
