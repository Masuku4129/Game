shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;
// Пятно крови на земле (экземпляр MultiMesh из blood.gd). Цвет экземпляра:
// r — форма (0 капля с брызгами, 0.5 мазок, 1 лужа), g — сила, b — снег под пятном, a — зерно.
// Своё: x — когда появилось (игровые часы), y — сколько живёт (ч).
uniform float now_h = 0.0;
varying vec4 v_c;
varying vec2 v_t;

vec3 lin(vec3 c) { return pow(c, vec3(2.2)); }
float h21(vec2 p) {
	p = mod(p, 1024.0);
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	v_c = COLOR;
	v_t = INSTANCE_CUSTOM.xy;
	// пятно чуть приподнято к камере: не тонет в земле на изломах сетки
	VERTEX.y += 0.004;
}

// Брызги вокруг: несколько мелких капель по зерну s.
float sats(vec2 q, float s, int n, float spread) {
	float d = 10.0;
	for (int i = 0; i < n; i++) {
		float fi = float(i);
		vec2 c = (vec2(h21(vec2(s * 91.0, fi * 7.3)), h21(vec2(fi * 3.1, s * 57.0))) - 0.5) * spread;
		float r = 0.025 + 0.06 * h21(vec2(s * 13.0 + fi, fi * 1.7));
		d = min(d, length(q - c) - r);
	}
	return d;
}

void fragment() {
	float life = v_t.y;
	float age = now_h - v_t.x;
	if (life <= 0.0 || age > life) {
		discard;
	}
	float shape = v_c.r;
	float s = v_c.a * 17.0;
	vec2 q = (UV - 0.5) * 2.0;
	float a = atan(q.y, q.x);
	vec2 dir = vec2(cos(a), sin(a));
	float d;
	float thick;
	if (shape < 0.25) {
		// капля: неровный край с зубцами (упала с высоты) и брызги вокруг
		float r = 0.36 * (0.82 + 0.3 * vnoise(dir * 2.2 + s)) + 0.1 * pow(vnoise(dir * 5.5 + s * 3.0), 3.0);
		d = length(q) - r;
		d = min(d, sats(q, v_c.a, 5, 1.5));
		thick = clamp(-d * 5.0, 0.0, 1.0);
	} else if (shape < 0.75) {
		// мазок: полоса вдоль оси, сужается к концам, с разрывами (зверь волочил рану)
		float along = q.y;
		float w = 0.38 * (1.0 - along * along) * (0.6 + 0.5 * vnoise(vec2(along * 3.0, s))) + 0.03 * (vnoise(vec2(along * 18.0, s * 3.0)) - 0.5);
		d = abs(q.x + 0.15 * (vnoise(vec2(along * 1.5, s + 3.0)) - 0.5)) - w;
		d = max(d, abs(along) - 0.92);
		d = min(d, sats(q, v_c.a + 0.3, 4, 1.6));
		thick = clamp(-d * 4.0, 0.0, 1.0);
	} else {
		// лужа: рваный край, к середине толще и темнее, вокруг брызги
		float r = 0.62 * (0.78 + 0.28 * vnoise(dir * 1.6 + s) + 0.1 * vnoise(dir * 4.5 + s * 2.0));
		d = length(q * vec2(1.0, 1.0 + 0.25 * (vnoise(vec2(s)) - 0.5))) - r;
		d = min(d, sats(q, v_c.a + 0.7, 6, 1.75));
		thick = clamp(-d * 2.5, 0.0, 1.0);
	}
	float snow = v_c.b;
	float m = 1.0 - smoothstep(-0.015, 0.015, d);
	// на снегу кровь расплывается розовым ореолом
	float halo = (1.0 - smoothstep(-0.02, 0.16 + 0.1 * vnoise(dir * 3.0 + s), d)) * snow;
	// свежая алая, за полсуток буреет; на снегу дольше остаётся красной
	float old = clamp(age / mix(10.0, 30.0, snow), 0.0, 1.0);
	vec3 fresh = mix(lin(vec3(0.34, 0.025, 0.03)), lin(vec3(0.6, 0.04, 0.05)), snow);
	vec3 dried = mix(lin(vec3(0.17, 0.06, 0.04)), lin(vec3(0.42, 0.09, 0.08)), snow);
	vec3 core = mix(fresh, dried, old) * mix(1.0, 0.55, thick * (1.0 - snow * 0.5));
	vec3 pink = lin(vec3(0.86, 0.5, 0.52));
	vec3 col = mix(pink, core, m);
	float fade = 1.0 - smoothstep(life * 0.55, life, age);
	float alpha = max(m * mix(0.72, 0.97, snow), halo * 0.5) * fade * mix(0.5, 1.0, v_c.g);
	ALBEDO = col;
	ALPHA = alpha;
	// свежая густая кровь блестит
	ROUGHNESS = mix(0.85, 0.22, (1.0 - old) * m * (0.4 + 0.6 * thick));
	SPECULAR = 0.5;
}

void light() {
	// мягкий живописный свет как у земли и блик на свежей крови
	float ndl = dot(NORMAL, LIGHT);
	float t = smoothstep(-0.05, 0.45, ndl) * mix(0.25, 1.0, ATTENUATION);
	vec3 c = mix(lin(vec3(0.55, 0.62, 0.85)) * 0.5, vec3(1.0, 0.95, 0.85), t);
	DIFFUSE_LIGHT += c * LIGHT_COLOR / PI;
	vec3 h = normalize(LIGHT + VIEW);
	float sh = pow(max(dot(NORMAL, h), 0.0), mix(8.0, 120.0, 1.0 - ROUGHNESS)) * (1.0 - ROUGHNESS);
	SPECULAR_LIGHT += sh * LIGHT_COLOR * ATTENUATION * 0.6;
}
