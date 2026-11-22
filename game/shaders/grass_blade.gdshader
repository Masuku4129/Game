shader_type spatial;
render_mode cull_disabled, diffuse_burley;
// Ковёр из отдельных травинок. Цвет берётся из вершин, нормаль смотрит вверх (мягкий свет).
uniform float sway = 0.06;
uniform vec3 tint : source_color = vec3(0.78, 0.82, 0.7);
uniform float snow = 0.0;
uniform float dry = 0.0;
uniform float wind = 0.5;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y *= max(0.0, 1.0 - snow * 1.6);
	float k = sway * (0.5 + wind) * smoothstep(0.0, 0.5, VERTEX.y);
	float t = TIME * 1.6 + w.x * 0.35 + w.z * 0.27;
	VERTEX.x += sin(t) * k + sin(t * 2.3 + 1.7) * k * 0.3;
	VERTEX.z += cos(t * 0.9) * k * 0.7;
}

void fragment() {
	vec3 c = COLOR.rgb * tint;
	float l = dot(c, vec3(0.3, 0.55, 0.15));
	c = mix(c, vec3(1.15, 0.9, 0.55) * l * 1.2, dry);
	ALBEDO = c;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	ROUGHNESS = 0.9;
	SPECULAR = 0.15;
}
