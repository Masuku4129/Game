shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 water_deep : source_color = vec4(0.055, 0.22, 0.28, 0.94);
uniform vec4 water_shallow : source_color = vec4(0.20, 0.43, 0.48, 0.88);
uniform vec4 ice_tint : source_color = vec4(0.70, 0.82, 0.83, 0.98);
uniform float ice : hint_range(0.0, 1.0) = 0.0;
uniform float rain : hint_range(0.0, 1.0) = 0.0;
uniform float wind : hint_range(0.0, 1.0) = 0.2;
uniform float time_scale : hint_range(0.0, 3.0) = 1.0;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float motion = (1.0 - ice) * (0.018 + rain * 0.012) * (0.25 + wind);
	VERTEX.y += sin(world_position.x * 0.19 + TIME * time_scale) * cos(world_position.z * 0.16 - TIME * time_scale * 0.73) * motion;
}

void fragment() {
	vec2 p = world_position.xz;
	float t = TIME * time_scale;
	vec2 flow_a = p * vec2(0.075, 0.11) + vec2(t * 0.10, -t * 0.07);
	vec2 flow_b = p * vec2(-0.13, 0.055) + vec2(-t * 0.06, t * 0.09);
	float wave_a = sin(flow_a.x * 6.2831 + sin(flow_a.y * 3.0));
	float wave_b = cos(flow_b.y * 6.2831 + sin(flow_b.x * 2.5));
	float ripple = (wave_a * 0.5 + wave_b * 0.5) * (1.0 - ice);
	float shallow_k = clamp(0.5 + ripple * 0.16, 0.0, 1.0);
	vec3 water_col = mix(water_deep.rgb, water_shallow.rgb, shallow_k);
	water_col = mix(water_col, ice_tint.rgb, ice * 0.94);
	float glint = pow(max(0.0, ripple * 0.5 + 0.5), 10.0) * (1.0 - ice) * (0.12 + rain * 0.08);
	ALBEDO = water_col + vec3(glint);
	ROUGHNESS = mix(0.19, 0.68, ice);
	METALLIC = mix(0.12, 0.02, ice);
	SPECULAR = mix(0.72, 0.3, ice);
	ALPHA = mix(0.91, 0.98, ice);
}
