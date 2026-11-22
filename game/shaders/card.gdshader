shader_type spatial;
render_mode cull_disabled, diffuse_burley;
// Карточки хвои, листвы, травы: альфа-отсечение, лёгкое качание на ветру.
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float sway = 0.05;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * 1.3 + w.x * 0.21 + w.z * 0.17;
	float k = sway * max(VERTEX.y, 0.0);
	VERTEX.x += sin(t) * k;
	VERTEX.z += cos(t * 0.83) * k;
}

void fragment() {
	vec4 c = texture(tex, UV);
	ALBEDO = c.rgb * tint.rgb * COLOR.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.45;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
}
