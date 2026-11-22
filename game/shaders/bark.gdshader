shader_type spatial;
render_mode diffuse_burley;
#include "res://shaders/fade.gdshaderinc"
uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
varying vec3 wpf;

void vertex() {
	wpf = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (fade_discard(wpf, FRAGCOORD.xy)) {
		discard;
	}
	ALBEDO = texture(tex, UV).rgb * tint.rgb * COLOR.rgb;
	ROUGHNESS = 1.0;
}
