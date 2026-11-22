shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, depth_draw_always;
// Вода: две волны, преломление дна, цвет по глубине, пена у берега и вокруг камней, блики.
uniform sampler2D wave : filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform vec3 shallow_col : source_color = vec3(0.30, 0.42, 0.34);
uniform vec3 deep_col : source_color = vec3(0.05, 0.13, 0.15);
uniform vec3 foam_col : source_color = vec3(0.86, 0.90, 0.88);
uniform vec2 flow = vec2(0.05, 0.03);
uniform float ice = 0.0;
uniform float rain = 0.0;
varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv1 = wp.xz * 0.07 + flow * TIME;
	vec2 uv2 = wp.xz * 0.19 + vec2(-flow.y, flow.x) * TIME * 1.6;
	vec4 w1 = texture(wave, uv1);
	vec4 w2 = texture(wave, uv2);
	vec3 n1 = w1.xyz * 2.0 - 1.0;
	vec3 n2 = w2.xyz * 2.0 - 1.0;
	vec3 nm = normalize(vec3(n1.xy + n2.xy * 0.7, n1.z * n2.z));
	NORMAL_MAP = nm * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.4;

	float depth = texture(depth_tex, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	vec4 v = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	v.xyz /= v.w;
	float thick = max(0.0, VERTEX.z - v.z);

	vec2 refr = SCREEN_UV + nm.xy * 0.035 * clamp(thick, 0.0, 1.0);
	vec3 under = textureLod(screen_tex, refr, 0.0).rgb;
	float t = clamp(thick / 3.5, 0.0, 1.0);
	vec3 body = mix(shallow_col, deep_col, smoothstep(0.0, 1.0, t));
	vec3 col = mix(under * mix(vec3(1.0), shallow_col * 1.8, t), body, smoothstep(0.05, 0.9, t));

	// пена: у берега и вокруг камней, с бегущим шумом
	float fn = w1.a * 0.6 + w2.a * 0.7;
	float shore = 1.0 - smoothstep(0.0, 0.55, thick + (fn - 0.5) * 0.35);
	float streak = smoothstep(0.62, 0.9, w1.a + w2.a * 0.4) * (1.0 - smoothstep(0.0, 1.6, thick)) * 0.5;
	float foam = clamp(shore + streak, 0.0, 1.0);
	col = mix(col, foam_col, foam * 0.85);

	// капли дождя: мелкие кольца-блики
	vec2 cell = floor(wp.xz * 3.0);
	float ph = fract(TIME * 1.3 + fract(sin(dot(cell, vec2(12.9, 78.2))) * 437.5));
	float ring = 1.0 - smoothstep(0.0, 0.08, abs(length(fract(wp.xz * 3.0) - 0.5) - ph * 0.45));
	col += vec3(0.18) * ring * (1.0 - ph) * rain;
	// лёд: сначала у берега, потом вся река; матовый, с трещинами из текстуры волн
	float ic = clamp(ice * 1.6 - t * 0.6 + (w1.a - 0.5) * 0.3, 0.0, 1.0);
	vec3 ice_col = mix(vec3(0.62, 0.72, 0.78), vec3(0.85, 0.9, 0.93), w2.a);
	col = mix(col, ice_col, ic);
	ALBEDO = col;
	ROUGHNESS = mix(mix(0.04, 0.5, foam), 0.3, ic);
	SPECULAR = 0.7;
	METALLIC = 0.0;
	ALPHA = 1.0;
}
