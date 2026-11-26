shader_type spatial;
render_mode cull_disabled, diffuse_burley;
uniform sampler2D base_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 base_tint : source_color = vec4(1.0);
uniform float has_texture = 0.0;
uniform float foliage = 0.0;
uniform float deciduous = 0.0;
uniform float snow = 0.0;
uniform float wet = 0.0;
uniform float autumn = 0.0;
uniform float wind = 0.5;
uniform float sway_strength = 0.045;
varying vec3 world_normal;
varying float local_height;
void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	local_height = clamp(VERTEX.y / 12.0, 0.0, 1.0);
	float phase = TIME * (0.65 + wind) + VERTEX.x * 0.7 + VERTEX.z * 0.43;
	float sway = sin(phase) * sway_strength * wind * local_height * foliage;
	VERTEX.x += sway;
	VERTEX.z += cos(phase * 0.83) * sway * 0.62;
}
void fragment() {
	vec4 texel = has_texture > 0.5 ? texture(base_texture, UV) : vec4(1.0);
	if (foliage > 0.5 && texel.a < 0.45) discard;
	vec3 color = texel.rgb * base_tint.rgb * COLOR.rgb;
	float autumn_mix = clamp(autumn * deciduous * foliage, 0.0, 1.0);
	vec3 autumn_tint = mix(vec3(0.55, 0.25, 0.075), vec3(0.82, 0.56, 0.16), clamp(color.g, 0.0, 1.0));
	color = mix(color, autumn_tint, autumn_mix);
	float snow_cover = smoothstep(0.38, 0.84, world_normal.y) * snow;
	color = mix(color, vec3(0.89, 0.93, 0.98), snow_cover);
	color *= 1.0 - wet * 0.13;
	ALBEDO = color;
	ROUGHNESS = 0.94;
	SPECULAR = 0.08;
}
