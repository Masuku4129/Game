shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_schlick_ggx;
// Прозрачная река: у берега видно дно, глубже — бирюзово-зелёная толща, блики мазками.
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 shallow : source_color = vec3(0.45, 0.62, 0.5);
uniform vec3 deep : source_color = vec3(0.12, 0.3, 0.32);
uniform float ice = 0.0;
uniform float rain = 0.0;
varying vec3 wp;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float dz = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, dz, 1.0);
	vec4 v = INV_PROJECTION_MATRIX * ndc;
	v.xyz /= v.w;
	float depth = clamp(VERTEX.z - v.z, 0.0, 10.0);
	float k = smoothstep(0.0, 1.6, depth);
	vec2 flow = vec2(TIME * 0.35, 0.0);
	float r1 = vn(wp.xz * vec2(0.8, 2.2) - flow);
	float r2 = vn(wp.xz * vec2(1.6, 4.0) - flow * 1.7 + 3.0);
	float glint = smoothstep(0.72, 0.9, r1 * 0.6 + r2 * 0.5);
	vec3 c = mix(shallow, deep, k);
	c += vec3(0.85, 0.95, 0.9) * glint * 0.35;
	c = mix(c, vec3(0.78, 0.86, 0.9), ice);
	ALBEDO = c;
	ALPHA = mix(clamp(0.15 + k * 0.8 + glint * 0.3, 0.0, 0.92), 0.97, ice);
	NORMAL = normalize(vec3((r1 - 0.5) * 0.25, 1.0, (r2 - 0.5) * 0.25) * mat3(INV_VIEW_MATRIX));
	ROUGHNESS = mix(0.12, 0.6, ice);
	METALLIC = 0.0;
}
