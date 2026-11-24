shader_type spatial;
render_mode cull_disabled;
// Деревья, трава, камни: цвет из меша, оттенок экземпляра из INSTANCE_CUSTOM, лёгкое покачивание на ветру.
uniform float sway = 0.3;
uniform float height_ref = 1.0;
uniform float ao_height = 1.5;
uniform vec3 rim_col : source_color = vec3(0.30, 0.38, 0.85);
varying vec3 tint;
varying float ao_y;

void vertex() {
	tint = INSTANCE_CUSTOM.rgb;
	ao_y = VERTEX.y;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float k = clamp(VERTEX.y / height_ref, 0.0, 1.0);
	k = k * k;
	float t = TIME * 1.3;
	VERTEX.x += sin(t + w.x * 0.35 + w.z * 0.2) * sway * k;
	VERTEX.z += cos(t * 0.8 + w.z * 0.3 + w.x * 0.15) * sway * 0.6 * k;
}

void fragment() {
	float ao = mix(0.50, 1.0, smoothstep(0.0, ao_height, ao_y));
	ALBEDO = COLOR.rgb * tint * ao;
	ROUGHNESS = 0.9;
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	EMISSION = rim_col * rim * 0.55 * ao;
}
