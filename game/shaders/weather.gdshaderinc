// Параметры погоды, общие для растительности и камней (выставляет weather.gd).
uniform float snow = 0.0;
uniform float wet = 0.0;
uniform float autumn = 0.0;
uniform float leaf_drop = 0.0;
uniform float wind = 0.5;

float whash(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }

// Доля снега на поверхности с нормалью ny (мировой), с пятнами.
float snow_cover(float ny, vec3 wp) {
	float n = whash(floor(wp * 1.7)) * 0.25 + whash(floor(wp * 0.5)) * 0.25;
	return clamp((snow * 1.5 - 0.15) - (1.0 - ny) * 2.2 + (n - 0.25), 0.0, 1.0);
}
