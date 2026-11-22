// Параметры погоды, общие для растительности и камней (выставляет weather.gd).
uniform float snow = 0.0;
uniform float wet = 0.0;
uniform float autumn = 0.0;
uniform float leaf_drop = 0.0;
uniform float wind = 0.5;

float whash(vec3 p) { p = mod(p, 1024.0); p = fract(p * 0.1031); p += dot(p, p.zyx + 31.32); return fract((p.x + p.y) * p.z); }

// Доля снега на поверхности с нормалью ny (мировой), с пятнами.
float snow_cover(float ny, vec3 wp) {
	float n = whash(floor(wp * 1.7)) * 0.25 + whash(floor(wp * 0.5)) * 0.25;
	return clamp((snow * 1.5 - 0.15) - (1.0 - ny) * 2.2 + (n - 0.25), 0.0, 1.0);
}
