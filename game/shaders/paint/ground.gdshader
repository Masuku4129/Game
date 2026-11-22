shader_type spatial;
render_mode cull_disabled;
#include "res://shaders/paint/paint.gdshaderinc"
// Земля, написанная пятнами: луг, лесная подстилка, камень на склонах, галька у воды.
uniform vec3 meadow = vec3(0.3, 0.4, 0.14);
uniform vec3 meadow2 = vec3(0.47, 0.5, 0.2);
uniform vec3 forest = vec3(0.16, 0.22, 0.11);
uniform vec3 litter = vec3(0.30, 0.23, 0.14);
uniform vec3 stone = vec3(0.42, 0.41, 0.38);
uniform vec3 bed = vec3(0.46, 0.42, 0.3);
uniform float water_y = -2.0;
uniform float snow = 0.0;
uniform float wet = 0.0;
varying vec3 wp;
varying vec3 wn;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float big = vnoise(wp.xz * 0.05) * 0.6 + vnoise(wp.xz * 0.13) * 0.4;
	float s = vnoise(wp.xz * 0.35) * 0.5 + vnoise(wp.xz * 0.9 + 3.0) * 0.3 + vnoise(wp.xz * 2.1) * 0.2;
	float fine = vnoise(wp.xz * 4.0) * 0.6 + vnoise(wp.xz * 9.0) * 0.4;
	vec3 c = mix(lin(meadow), lin(meadow2), smoothstep(0.35, 0.75, big + (s - 0.5) * 0.5));
	float fd = COLOR.r;  // густота леса из вершинного цвета
	vec3 fl = mix(lin(forest), lin(litter), smoothstep(0.4, 0.7, s + big * 0.3 - 0.2));
	c = mix(c, fl, smoothstep(0.35, 0.65, fd + (s - 0.5) * 0.3));
	float slope = 1.0 - wn.y;
	c = mix(c, lin(stone) * (0.85 + fine * 0.3), smoothstep(0.28, 0.42, slope + (s - 0.5) * 0.12));
	// дно и берег: песок с округлыми камешками
	float sh = smoothstep(water_y + 0.5, water_y - 0.1, wp.y);
	vec2 pq = wp.xz * 1.6 + vec2(vnoise(wp.xz * 1.3), vnoise(wp.zx * 1.3 + 5.0)) * 0.9;
	vec2 cell = floor(pq);
	vec2 f = fract(pq) - 0.5;
	float pr = h21(cell);
	float peb = 0.5 * smoothstep(0.32, 0.22, length(f + (vec2(h21(cell + 3.1), h21(cell + 7.7)) - 0.5) * 0.3)) * step(0.6, pr);
	vec3 bc = mix(lin(bed), lin(mix(vec3(0.42, 0.42, 0.38), vec3(0.62, 0.58, 0.48), pr)), peb);
	c = mix(c, bc * (0.9 + fine * 0.2), sh);
	c *= 0.92 + fine * 0.16;
	c = mix(c, vec3(0.88, 0.91, 0.96) * (0.95 + fine * 0.05), smoothstep(0.2, 0.5, snow + wn.y * 0.2 - 0.2) * step(0.01, snow));
	c *= 1.0 - wet * 0.25;
	ALBEDO = c;
	ROUGHNESS = mix(1.0, 0.5, wet);
	SPECULAR = 0.0;
}
