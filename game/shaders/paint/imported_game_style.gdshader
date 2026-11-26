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
uniform float leaf_drop = 0.0;
uniform float wind = 0.5;
uniform float sway_strength = 0.045;
varying vec3 world_normal;
varying vec3 world_position;
varying float local_height;
float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}
float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec3(1,0,0));
	float c = hash(i + vec3(0,1,0));
	float d = hash(i + vec3(1,1,0));
	float e = hash(i + vec3(0,0,1));
	float g = hash(i + vec3(1,0,1));
	float h = hash(i + vec3(0,1,1));
	float j = hash(i + vec3(1,1,1));
	return mix(mix(mix(a,b,f.x),mix(c,d,f.x),f.y),mix(mix(e,g,f.x),mix(h,j,f.x),f.y),f.z);
}
void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local_height = clamp(VERTEX.y / 12.0, 0.0, 1.0);
	float phase = TIME * (0.65 + wind) + VERTEX.x * 0.7 + VERTEX.z * 0.43;
	float sway = sin(phase) * sway_strength * wind * local_height * foliage;
	VERTEX.x += sway;
	VERTEX.z += cos(phase * 0.83) * sway * 0.62;
}
void fragment() {
	vec4 texel = has_texture > 0.5 ? texture(base_texture, UV) : vec4(1.0);
	float leaf_hash = fract(sin(dot(floor(world_position.xz * 1.3), vec2(12.9898, 78.233))) * 43758.5453);
	if (leaf_drop * deciduous * foliage > leaf_hash) discard;
	if (foliage > 0.5 && texel.a < 0.45) discard;
	vec3 color = texel.rgb * base_tint.rgb * COLOR.rgb;
	// Procedural texture breakup supplements the authored texture and also supplies
	// visible grain when GLB has no image map. Bark has longitudinal streaks;
	// foliage receives mottled leaf clusters at multiple scales.
	float broad = noise(world_position * 2.1);
	float fine = noise(world_position * 11.0 + vec3(UV * 19.0, 0.0));
	float detail = mix(broad * 0.65 + fine * 0.35, noise(vec3(UV * 46.0, local_height * 8.0)), 0.30);
	float leaf_mod = mix(0.78, 1.16, detail);
	float bark_grain = abs(sin(world_position.y * 8.0 + world_position.x * 1.4 + broad * 4.0));
	float bark_mod = mix(0.72, 1.12, bark_grain * 0.52 + fine * 0.48);
	color *= mix(bark_mod, leaf_mod, foliage);
	float autumn_mix = clamp(autumn * deciduous * foliage, 0.0, 1.0);
	vec3 autumn_tint = mix(vec3(0.55, 0.25, 0.075), vec3(0.82, 0.56, 0.16), clamp(color.g, 0.0, 1.0));
	color = mix(color, autumn_tint, autumn_mix);
	float snow_cover = smoothstep(0.38, 0.84, world_normal.y) * snow;
	color = mix(color, vec3(0.89, 0.93, 0.98), snow_cover);
	color *= 1.0 - wet * 0.13;
	ALBEDO = color;
	ROUGHNESS = mix(0.96, 0.82, wet);
	SPECULAR = 0.07;
}
