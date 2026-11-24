shader_type spatial;
// Только настил моста и площадка у замка: плиты рядами, светлая середина, тёмная кайма. Остальное отброшено - там пропасть.
uniform sampler2D floor_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 tint = vec3(0.62, 0.64, 0.88);
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
	vec2 w = wpos.xz;
	float zend = 35.0 + 1.8 * vn(vec2(w.x * 0.9, 3.0));
	bool in_bridge = abs(w.x) < 3.4 && w.y > -34.2 && w.y < zend;
	bool in_plat = abs(w.x) < 15.0 && w.y <= -34.2 && w.y > -44.6;
	if (!(in_bridge || in_plat)) {
		discard;
	}
	float din = in_bridge ? 3.4 - abs(w.x) : min(15.0 - abs(w.x), w.y + 44.6);
	vec2 sz = vec2(1.7, 1.7);
	vec2 p = w / sz;
	float row = floor(p.y);
	p.x += mod(row, 2.0) * 0.5;
	vec2 id = floor(p);
	vec2 f = fract(p);
	float ed = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)) * 1.7;
	float mortar = smoothstep(0.02, 0.10, ed);
	float tone = h21(id + 3.7);
	vec3 base = mix(vec3(0.27, 0.27, 0.39), vec3(0.38, 0.37, 0.51), tone);
	vec3 t = texture(floor_tex, vec2(0.01, 0.01) + f * 0.48).rgb;
	vec3 stone = base * (0.78 + 0.55 * dot(t, vec3(0.33))) * (0.86 + 0.28 * vn(w * 1.7));
	stone *= mix(0.30, 1.0, mortar);
	stone *= mix(0.60, 1.0, smoothstep(0.0, 0.7, din));
	// утоптанная середина и мох у краёв
	stone *= 1.0 + 0.18 * (1.0 - smoothstep(0.0, 1.6, abs(w.x))) * (in_bridge ? 1.0 : 0.0);
	stone = mix(stone, stone * vec3(0.60, 0.95, 0.64), smoothstep(0.60, 0.86, vn(w * 0.37 + 4.0)) * 0.45);
	ALBEDO = stone * tint * 1.3;
	ROUGHNESS = 0.95;
	SPECULAR = 0.12;
}
