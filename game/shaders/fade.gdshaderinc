uniform vec3 hero_pos = vec3(0.0, -1000.0, 0.0);
uniform vec3 cam_pos = vec3(0.0, -999.0, 0.0);

// Растворяет (дизерингом) всё, что стоит на луче камера -> герой.
bool fade_discard(vec3 wp, vec2 fc) {
	vec3 ab = hero_pos - cam_pos;
	float t = dot(wp - cam_pos, ab) / dot(ab, ab);
	if (t < 0.0 || t > 0.97) {
		return false;
	}
	// чистый коридор 1,3 м вокруг луча и узкая полоса дизеринга, у героя коридор сужается
	float d = distance(wp, cam_pos + ab * t);
	float r = mix(1.3, 0.6, smoothstep(0.85, 0.97, t));
	float k = smoothstep(r, r + 0.45, d);
	float n = fract(52.9829189 * fract(dot(fc, vec2(0.06711056, 0.00583715))));
	return k < n;
}

// Растения расступаются вокруг героя: смещение в мировых координатах.
vec3 hero_push(vec3 w, float h, float tm) {
	vec2 dv = w.xz - hero_pos.xz;
	float d = length(dv);
	float near = 1.0 - smoothstep(0.25, 1.1, d);
	near *= step(w.y, hero_pos.y + 0.9);
	vec2 dir = dv / max(d, 0.001);
	float wob = sin(tm * 9.0 + w.x * 3.0) * 0.15;
	return vec3(dir.x, -0.35 - wob, dir.y) * near * h * 0.55;
}

// Плавное появление по дальности вместо щелчка целой клетки MultiMesh.
// INSTANCE_CUSTOM.x — дальность, на которой экземпляр полностью растворился (0 — не растворять);
// INSTANCE_CUSTOM.y = 1 — детальная ближняя модель дерева, -1 — лёгкая дальняя: на краю
// круга near_r вокруг near_c они перетекают друг в друга дизерингом.
uniform vec3 near_c = vec3(0.0, -100000.0, 0.0);
uniform float near_r = 44.0;
float dist_vis(vec4 ic, vec3 org) {
	float v = 1.0;
	if (ic.x > 0.0) {
		v = 1.0 - smoothstep(ic.x - 12.0, ic.x, distance(org, cam_pos));
	}
	if (ic.y > 0.5) {
		v *= 1.0 - smoothstep(near_r - 10.0, near_r, distance(org.xz, near_c.xz));
	} else if (ic.y < -0.5) {
		// дальняя версия берёт дополнение того же дизеринга: со стороны -v
		v = -v * smoothstep(near_r - 6.0, near_r, distance(org.xz, near_c.xz));
	}
	return v;
}
// v из dist_vis: >0 — обычная доля видимости, <0 — дополняющий дизеринг.
bool vis_discard(float v, vec2 fc) {
	float n = fract(52.9829189 * fract(dot(fc, vec2(0.06711056, 0.00583715))));
	if (v < 0.0) {
		return -v < 0.999 && 1.0 - n > -v;
	}
	return v < 0.999 && n > v;
}
