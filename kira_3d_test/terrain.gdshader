shader_type spatial;
// Двор замка: ровная кладка плит (ряды со смещением), центральная дорожка, тёмная кайма и мшистая земля снаружи.
// Камера с yaw 0: оси мира совпадают с осями экрана, плиты на экране - ровные прямоугольники.
uniform sampler2D floor_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 tint = vec3(0.62, 0.64, 0.88);
uniform float x_half = 19.0;
uniform float z_back = -14.5;
uniform float z_front = 10.5;
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
	float din = min(min(x_half - abs(w.x), w.y - z_back), z_front - w.y);   // расстояние до края двора (внутри > 0)
	bool path_x = abs(w.x) < 2.3;
	// ---- плиты
	vec2 sz = vec2(2.4, 1.6);
	vec2 p = w / sz;
	float row = floor(p.y);
	p.x += mod(row, 2.0) * 0.5;
	vec2 id = floor(p);
	vec2 f = fract(p);
	float ed = min(min(f.x * sz.x, (1.0 - f.x) * sz.x), min(f.y * sz.y, (1.0 - f.y) * sz.y));
	float mortar = smoothstep(0.02, 0.10, ed);
	float tone = h21(id + 3.7);
	vec3 base = mix(vec3(0.27, 0.27, 0.39), vec3(0.37, 0.36, 0.50), tone);
	if (path_x) {
		base = mix(vec3(0.34, 0.33, 0.46), vec3(0.45, 0.43, 0.56), tone);
	}
	// детали камня из нарисованного атласа: одна плита, без отражений, лёгкий контраст
	vec3 t = texture(floor_tex, vec2(0.01, 0.01) + f * 0.48).rgb;
	float lum = dot(t, vec3(0.33));
	vec3 stone = base * (0.78 + 0.55 * lum) * (0.86 + 0.28 * vn(w * 1.7));
	stone *= mix(0.30, 1.0, mortar);
	// кайма у края двора темнее, трещины и мох пятнами
	stone *= mix(0.55, 1.0, smoothstep(0.0, 1.2, din));
	stone = mix(stone, stone * vec3(0.62, 0.95, 0.66), smoothstep(0.62, 0.86, vn(w * 0.31 + 4.0)) * 0.5);
	// ---- земля снаружи
	float n2 = vn(w * 0.4) * 0.6 + vn(w * 1.9) * 0.4;
	vec3 grass = mix(vec3(0.045, 0.085, 0.075), vec3(0.085, 0.13, 0.10), n2);
	grass = mix(grass, vec3(0.11, 0.075, 0.16), smoothstep(0.55, 0.85, vn(w * 0.22 + 9.0)) * 0.5);
	vec3 dirt = mix(vec3(0.15, 0.12, 0.11), vec3(0.20, 0.16, 0.14), n2);
	float outside = 1.0 - smoothstep(-0.25, 0.15, din);
	// дорожка из ворот двора наружу к югу
	float road = (1.0 - smoothstep(1.8, 2.8, abs(w.x))) * step(z_front - 0.5, w.y) * (1.0 - smoothstep(0.0, 1.0, abs(w.y - z_front) - 0.5)) ;
	float road2 = (1.0 - smoothstep(1.6, 2.6, abs(w.x + 0.8 * sin(w.y * 0.25)))) * smoothstep(z_front - 0.3, z_front + 0.4, w.y);
	vec3 ground = mix(grass, dirt, clamp(road2, 0.0, 1.0));
	vec3 c = mix(stone, ground, outside) * tint * 1.25;
	c *= 1.0 - 0.45 * smoothstep(22.0, 40.0, length(w));
	ALBEDO = c;
	ROUGHNESS = 0.95;
	SPECULAR = 0.12;
}
