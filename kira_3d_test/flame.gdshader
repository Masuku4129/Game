shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

// Луч тёмно-фиолетового пламени: бегущий шум вдоль луча, языки по краям,
// тёмное тело и яркое ядро в центре (по углу к камере).
uniform float speed = 6.0;
uniform float fade = 1.0;
uniform vec3 col_dark = vec3(0.10, 0.01, 0.22);
uniform vec3 col_mid = vec3(0.42, 0.10, 0.85);
uniform vec3 col_core = vec3(0.92, 0.78, 1.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) { s += a * vnoise(p); p *= 2.03; a *= 0.5; }
	return s;
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	vec2 q = vec2(UV.x * 6.0, UV.y * 14.0 - TIME * speed);
	float n = fbm(q);
	float n2 = fbm(q * 1.7 + vec2(3.1, -TIME * speed * 0.6));
	float body = smoothstep(0.25, 0.75, facing + (n - 0.5) * 0.9);
	float core = smoothstep(0.82, 1.0, facing + (n2 - 0.5) * 0.35);
	vec3 col = mix(col_dark, col_mid, body * n);
	col = mix(col, col_core, core);
	ALBEDO = col * (1.0 + core * 2.5);
	ALPHA = clamp(body * (0.55 + 0.6 * n) + core, 0.0, 1.0) * fade;
}
