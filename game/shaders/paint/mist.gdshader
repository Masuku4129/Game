shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled;
// Стелющийся туман: несколько полупрозрачных слоёв у земли. Лежит только в низинах и над рекой —
// толщина под слоем берётся из карты высот (на телефоне прозрачным буфер глубины недоступен).
// Клочья плывут по ветру, у края области слой растворяется в общей дымке.
uniform sampler2D hmap : filter_linear, repeat_disable;
uniform float hsize = 512.0;
uniform float water_y = -2.0;
uniform float mist = 0.0;
uniform vec3 col : source_color = vec3(0.8, 0.82, 0.84);
uniform vec2 drift = vec2(0.0);
uniform vec3 center = vec3(0.0);
uniform float radius = 70.0;
uniform float layer = 0.0;
varying vec3 wp;

float h21(vec2 p) {
	p = mod(p, 1024.0);
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float gy = max(texture(hmap, wp.xz / hsize + 0.5).r, water_y);
	float above = wp.y - gy;
	// слой виден там, где земля под ним: мягко у самой земли, гуще в глубоких низинах
	float a = smoothstep(0.0, 1.4, above) * (1.0 - smoothstep(5.0, 9.0, above));
	vec2 p = wp.xz + drift * (1.0 + layer * 0.35);
	float n = vn(p * 0.045) * 0.6 + vn(p * 0.11 + 13.0) * 0.3 + vn(p * 0.31 - 7.0) * 0.1;
	float patches = smoothstep(0.62 - mist * 0.5, 0.95 - mist * 0.2, n);
	float edge = 1.0 - smoothstep(radius * 0.6, radius, distance(wp.xz, center.xz));
	// вблизи камеры слой тоньше, чтобы туман не закрывал героя молочной плёнкой
	float near = smoothstep(3.0, 14.0, distance(wp, CAMERA_POSITION_WORLD));
	ALBEDO = col * (0.92 + n * 0.12);
	ALPHA = clamp(a * patches * edge * near * mist * 0.42, 0.0, 0.6);
}
