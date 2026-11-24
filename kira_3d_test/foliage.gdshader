shader_type spatial;
render_mode cull_disabled;
// Деревья, трава, камни: цвет из меша, оттенок экземпляра из INSTANCE_CUSTOM, лёгкое покачивание на ветру.
uniform float sway = 0.3;
uniform float height_ref = 1.0;
varying vec3 tint;

void vertex() {
	tint = INSTANCE_CUSTOM.rgb;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float k = clamp(VERTEX.y / height_ref, 0.0, 1.0);
	k = k * k;
	float t = TIME * 1.3;
	VERTEX.x += sin(t + w.x * 0.35 + w.z * 0.2) * sway * k;
	VERTEX.z += cos(t * 0.8 + w.z * 0.3 + w.x * 0.15) * sway * 0.6 * k;
}

void fragment() {
	ALBEDO = COLOR.rgb * tint;
	ROUGHNESS = 0.95;
}
