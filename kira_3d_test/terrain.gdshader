shader_type spatial;
// Двор древних руин: плиты из нарисованного листа (атлас 2x2), случайный выбор и отражение плит, затемнение к краю.
uniform sampler2D floor_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 tint = vec3(0.60, 0.62, 0.84);
uniform float tile = 3.0;
varying vec3 wpos;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz / tile;
	vec2 id = floor(p);
	vec2 f = fract(p);
	float h = h21(id);
	if (h21(id + 7.3) > 0.5) f.x = 1.0 - f.x;
	if (h21(id + 3.1) > 0.5) f.y = 1.0 - f.y;
	float q = floor(h * 4.0);
	vec2 off = vec2(mod(q, 2.0), floor(q / 2.0)) * 0.5;
	vec2 uv = off + 0.006 + f * 0.488;
	vec3 t = texture(floor_tex, uv).rgb;
	float r = length(wpos.xz);
	float n = 0.78 + 0.30 * vn(wpos.xz * 0.35) + 0.14 * vn(wpos.xz * 3.0);
	float edge = 1.0 - 0.62 * smoothstep(21.0, 32.0, r);
	vec3 c = t * tint * n * edge * 1.25;
	// мох и тёмные пятна ближе к краю
	c = mix(c, c * vec3(0.55, 0.85, 0.6), smoothstep(0.55, 0.85, vn(wpos.xz * 0.18 + 5.0)) * 0.55);
	ALBEDO = c;
	ROUGHNESS = 0.95;
	SPECULAR = 0.15;
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	EMISSION = vec3(0.10, 0.12, 0.30) * rim * 0.4;
}
