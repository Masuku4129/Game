// Живописный свет: мягкая «ступень» света вместо физически точного затухания,
// тени уходят в холодный цвет, освещённые стороны — в тёплый.
uniform vec3 shade_cool : source_color = vec3(0.55, 0.62, 0.85);
uniform float ramp_lo = -0.05;
uniform float ramp_hi = 0.45;

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float t = smoothstep(ramp_lo, ramp_hi, ndl) * mix(0.25, 1.0, ATTENUATION);
	vec3 c = mix(shade_cool * 0.3, vec3(1.0, 0.95, 0.85), t);
	DIFFUSE_LIGHT += c * LIGHT_COLOR / PI;
}

// Мазки: вытянутый шум для живописной неровности цвета.
float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}
float strokes(vec2 p) {
	// мазки вдоль одного направления: сжатие по оси и два слоя
	vec2 q = vec2(p.x * 0.35 + p.y * 0.2, p.y * 1.6 - p.x * 0.3);
	return vnoise(q) * 0.6 + vnoise(q * 2.3 + 7.1) * 0.4;
}
