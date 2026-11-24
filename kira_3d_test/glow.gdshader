shader_type spatial;
// Светящиеся кристаллы и грибы (цвет экземпляра в INSTANCE_CUSTOM). Свечение даёт bloom.
varying vec3 tint;

void vertex() {
	tint = INSTANCE_CUSTOM.rgb;
}

void fragment() {
	vec3 base = COLOR.rgb * tint;
	ALBEDO = base * 0.25;
	EMISSION = base * 3.0;
	ROUGHNESS = 0.35;
}
