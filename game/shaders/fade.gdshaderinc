uniform vec3 hero_pos = vec3(0.0, -1000.0, 0.0);
uniform vec3 cam_pos = vec3(0.0, -999.0, 0.0);

// Растворяет (дизерингом) всё, что стоит на луче камера -> герой.
bool fade_discard(vec3 wp, vec2 fc) {
	vec3 ab = hero_pos - cam_pos;
	float t = dot(wp - cam_pos, ab) / dot(ab, ab);
	if (t < 0.0 || t > 0.985) {
		return false;
	}
	float d = distance(wp, cam_pos + ab * t);
	float k = mix(0.08, 1.0, smoothstep(0.8, 2.6, d));
	float n = fract(52.9829189 * fract(dot(fc, vec2(0.06711056, 0.00583715))));
	return k < n;
}
