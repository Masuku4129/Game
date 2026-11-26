shader_type spatial;
render_mode cull_disabled;
#include "res://shaders/paint/paint.gdshaderinc"
// Земля, написанная пятнами: луг, лесная подстилка, камень на склонах, галька у воды.
// Снег — настоящий слой: поверхность поднята на глубину снега (сугробы неравномерны,
// карта field_tex). Грязь — тёмная мокрая почва, в которую проваливаются.
// Рядом с героем лежит мелкая сетка-«заплатка» (COLOR.a = 0): она повторяет землю и снег
// точно так же, но ещё и продавлена следами из track_tex (вмятины, ямы, траншеи).
// Крупная земля под заплаткой опущена, чтобы не мешать.
uniform vec3 meadow = vec3(0.3, 0.4, 0.14);
uniform vec3 meadow2 = vec3(0.47, 0.5, 0.2);
uniform vec3 forest = vec3(0.16, 0.22, 0.11);
uniform vec3 litter = vec3(0.30, 0.23, 0.14);
uniform vec3 stone = vec3(0.36, 0.34, 0.29);
uniform vec3 bed = vec3(0.46, 0.42, 0.3);
uniform vec3 mud_col = vec3(0.24, 0.16, 0.1);
uniform float water_y = -2.0;
uniform float snow = 0.0;
uniform float wet = 0.0;
// поле: r — густота леса, g — множитель сугроба (×1.4), b — грязевитость
uniform sampler2D field_tex : filter_nearest;
uniform sampler2D hmap_tex : filter_nearest;
uniform sampler2D zone_tex : filter_nearest;
uniform float tsize = 512.0;
uniform float tseg = 384.0;
uniform float snow_m = 0.0;   // глубина снега (м) при множителе 1
uniform float mud_m = 0.0;    // глубина обычной грязи (м)
uniform float bog_m = 0.0;    // постоянная вязкость болотной почвы, сезонно промерзает
// следы: r — глубина (×1.25 м), g — отметка «часов засыпания» (0..255)
uniform sampler2D track_tex : filter_linear, repeat_enable;
uniform sampler2D track_near : filter_nearest, repeat_enable;
uniform float track_span = 40.0;
uniform float track_clock = 0.0;
uniform float track_life = 200.0;
uniform float track_res = 0.041666;  // метров на тексель следов
uniform vec2 track_eye = vec2(0.0);   // герой: следы плавно тают с расстоянием от него
uniform float track_r = 13.0;
uniform vec2 patch_c = vec2(0.0);
uniform float patch_h = -100.0;
varying vec3 wp;
varying vec4 zw;      // особые участки: гарь, болото, курумник, бурелом
varying vec3 wn;      // нормаль земли (без снега) — для камня и скал
varying vec3 sn;      // нормаль поверхности снега/земли без следов
varying float v_sd;
varying float v_md;
varying float v_fd;
varying float v_mf;
varying float v_patch;
varying float v_wear;  // build: тропа/расчистка (1 - field.a)

// Значение в точке по треугольникам той же разбивки, что у сетки земли.
vec4 tri4(sampler2D t, vec2 xz) {
	vec2 g = (xz + tsize * 0.5) / (tsize / tseg);
	g = clamp(g, vec2(0.0), vec2(tseg - 0.0001));
	ivec2 i = ivec2(floor(g));
	vec2 f = g - vec2(i);
	vec4 a = texelFetch(t, i, 0);
	vec4 b = texelFetch(t, i + ivec2(1, 0), 0);
	vec4 c = texelFetch(t, i + ivec2(0, 1), 0);
	vec4 d = texelFetch(t, i + ivec2(1, 1), 0);
	if (f.x + f.y <= 1.0) {
		return a + f.x * (b - a) + f.y * (c - a);
	}
	return d + (1.0 - f.x) * (c - d) + (1.0 - f.y) * (b - d);
}

float track_fade(vec2 uv) {
	float tb = floor(texture(track_near, uv).g * 255.0 + 0.5);
	float age = mod(track_clock - tb + 256.0, 256.0);
	return clamp(1.0 - age / track_life, 0.0, 1.0);
}

float track_edge(vec2 xz) {
	// от героя, а не от центра заплатки: при её сдвиге ничего не «прыгает»
	vec2 e = abs(xz - patch_c);
	float box = 1.0 - smoothstep(patch_h - 5.0, patch_h - 3.2, max(e.x, e.y));
	return box * (1.0 - smoothstep(track_r - 3.0, track_r, length(xz - track_eye)));
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_patch = COLOR.a < 0.5 ? 1.0 : 0.0;
	if (v_patch > 0.5) {
		float e = 0.3125;
		float h = tri4(hmap_tex, wp.xz).r;
		float hx = tri4(hmap_tex, wp.xz + vec2(e, 0.0)).r;
		float hz = tri4(hmap_tex, wp.xz + vec2(0.0, e)).r;
		vec4 f = tri4(field_tex, wp.xz);
		zw = tri4(zone_tex, wp.xz);
		float sx = tri4(field_tex, wp.xz + vec2(e, 0.0)).g;
		float sz = tri4(field_tex, wp.xz + vec2(0.0, e)).g;
		float k = snow_m * 1.4;
		v_wear = 1.0 - f.a;
		v_sd = k * f.g * (1.0 - 0.85 * v_wear);
		v_md = mud_m * f.b + bog_m * zw.y;
		v_fd = f.r;
		v_mf = max(f.b, zw.y);
		wn = normalize(vec3(h - hx, e, h - hz));
		sn = normalize(vec3(h + v_sd - hx - k * sx, e, h + v_sd - hz - k * sz));
		vec2 uv = wp.xz / track_span;
		// сетка реже карты следов: берём наибольшую глубину рядом, чтобы яма в сетке была
		// не меньше нарисованной, а форму и стенки рисует фрагментный шейдер
		float o = 0.5 * e / track_span;
		float tr = max(texture(track_tex, uv).r, max(max(texture(track_tex, uv + vec2(o, 0.0)).r, texture(track_tex, uv - vec2(o, 0.0)).r), max(texture(track_tex, uv + vec2(0.0, o)).r, texture(track_tex, uv - vec2(0.0, o)).r)));
		float t = tr * 1.25 * track_fade(uv) * track_edge(wp.xz);
		t = min(t, v_sd + v_md + 0.03 * wet);
		wp.y = h + v_sd - t + 0.015;
		VERTEX.y = wp.y - MODEL_MATRIX[3].y;
		NORMAL = sn;
	} else {
		wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
		// вершина крупной сетки стоит ровно в узле карты поля
		float step_m = tsize / tseg;
		ivec2 g0 = clamp(ivec2(round((wp.xz + tsize * 0.5) / step_m)), ivec2(0), ivec2(int(tseg)));
		ivec2 gi = clamp(g0, ivec2(1), ivec2(int(tseg) - 1));
		vec4 f = texelFetch(field_tex, g0, 0);
		zw = texelFetch(zone_tex, g0, 0);
		float sx = texelFetch(field_tex, gi + ivec2(1, 0), 0).g - texelFetch(field_tex, gi - ivec2(1, 0), 0).g;
		float sz = texelFetch(field_tex, gi + ivec2(0, 1), 0).g - texelFetch(field_tex, gi - ivec2(0, 1), 0).g;
		float k = snow_m * 1.4;
		v_wear = 1.0 - f.a;
		v_sd = k * f.g * (1.0 - 0.85 * v_wear);
		v_md = mud_m * f.b + bog_m * zw.y;
		v_fd = f.r;
		v_mf = max(f.b, zw.y);
		vec3 g = wn / max(wn.y, 0.05);
		sn = normalize(vec3(g.x - k * sx / (2.0 * step_m), 1.0, g.z - k * sz / (2.0 * step_m)));
		// под заплаткой у героя — опустить, по краю — чуть-чуть, чтобы не мерцало
		vec2 d = abs(wp.xz - patch_c);
		float m = max(d.x, d.y);
		float lift = v_sd;
		if (m < patch_h - 1.6) {
			lift = -0.8;
		} else if (m < patch_h + 1.5) {
			lift -= 0.02;
		}
		VERTEX.y += lift;
		wp.y += lift;
		NORMAL = sn;
	}
}

void fragment() {
	float big = vnoise(wp.xz * 0.05) * 0.6 + vnoise(wp.xz * 0.13) * 0.4;
	float s = vnoise(wp.xz * 0.35) * 0.5 + vnoise(wp.xz * 0.9 + 3.0) * 0.3 + vnoise(wp.xz * 2.1) * 0.2;
	float fine = vnoise(wp.xz * 4.0) * 0.6 + vnoise(wp.xz * 9.0) * 0.4;
	vec3 c = mix(lin(meadow), lin(meadow2), smoothstep(0.35, 0.75, big + (s - 0.5) * 0.5));
	float fd = v_fd;  // густота леса
	vec3 fl = mix(lin(forest), lin(litter), smoothstep(0.4, 0.7, s + big * 0.3 - 0.2));
	c = mix(c, fl, smoothstep(0.35, 0.65, fd + (s - 0.5) * 0.3));
	float slope = 1.0 - wn.y;
	c = mix(c, lin(stone) * (0.85 + fine * 0.3), smoothstep(0.28, 0.42, slope + (s - 0.5) * 0.12));
	// отвесная скала: серый камень, пятна лишайника, вертикальные потёки и тёмные расщелины
	vec2 cuv = vec2(wp.x + wp.z, wp.y);
	float blocks = vnoise(cuv * vec2(0.9, 0.35)) * 0.6 + vnoise(cuv * vec2(2.3, 0.8)) * 0.4;
	float streak = vnoise(vec2(cuv.x * 3.0, cuv.y * 0.15));
	float crev = smoothstep(0.72, 0.82, vnoise(cuv * vec2(1.6, 0.25)));
	vec3 cliff = lin(vec3(0.43, 0.42, 0.39)) * (0.72 + blocks * 0.35) * (0.9 + streak * 0.15);
	cliff = mix(cliff, lin(vec3(0.5, 0.54, 0.4)), smoothstep(0.62, 0.8, vnoise(cuv * 0.5 + 7.0)) * 0.45);
	cliff *= 1.0 - crev * 0.5;
	c = mix(c, cliff, smoothstep(0.5, 0.7, slope));
	// особые участки: гарь, болото, курумник, бурелом (края рваные от шума)
	float ze = (s - 0.5) * 0.5 + (big - 0.5) * 0.3;
	float kb = smoothstep(0.35, 0.65, zw.x + ze);
	float kg = smoothstep(0.35, 0.65, zw.y + ze);
	float kr = smoothstep(0.35, 0.65, zw.z + ze);
	float kw = smoothstep(0.35, 0.65, zw.w + ze);
	vec3 ash = mix(lin(vec3(0.13, 0.11, 0.1)), lin(vec3(0.42, 0.4, 0.36)), smoothstep(0.4, 0.8, fine + s * 0.4 - 0.2));
	ash = mix(ash, lin(vec3(0.36, 0.42, 0.16)), smoothstep(0.55, 0.8, big) * 0.6);
	c = mix(c, ash, kb);
	vec3 bog = mix(lin(vec3(0.5, 0.5, 0.18)), lin(vec3(0.3, 0.36, 0.12)), smoothstep(0.3, 0.7, s));
	bog = mix(bog, lin(vec3(0.62, 0.36, 0.22)), smoothstep(0.7, 0.85, fine) * 0.5);
	bog = mix(bog, lin(vec3(0.08, 0.1, 0.07)), smoothstep(0.62, 0.7, big + s * 0.3) * 0.8);
	c = mix(c, bog, kg);
	vec3 kur = lin(vec3(0.45, 0.44, 0.4)) * (0.7 + fine * 0.4);
	kur = mix(kur, lin(vec3(0.68, 0.7, 0.56)), smoothstep(0.6, 0.85, s) * 0.6);
	c = mix(c, kur, kr * 0.85);
	c = mix(c, lin(litter) * (0.8 + fine * 0.3), kw * 0.6);
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
	// build: натоптанная тропа и расчищенная площадка — вытертая трава, утоптанная земля
	float worn = smoothstep(0.25, 0.65, v_wear + (s - 0.5) * 0.25);
	c = mix(c, lin(vec3(0.36, 0.29, 0.2)) * (0.85 + fine * 0.3), worn * 0.8);
	// грязь: тёмная, мокрая, блестит; лужицы в низинах
	float mudv = clamp(v_md / 0.12, 0.0, 1.0) * smoothstep(0.1, 0.4, v_mf + (s - 0.5) * 0.35);
	float puddle = mudv * smoothstep(0.62, 0.72, s + big * 0.2) * clamp(wet * 1.5 + 0.2, 0.0, 1.0);
	c = mix(c, lin(mud_col) * (0.8 + fine * 0.3), mudv);
	c = mix(c, lin(vec3(0.12, 0.11, 0.1)), puddle * 0.6);
	// следы
	float t = 0.0;
	float wall = 0.0;
	vec3 nw = sn;
	if (v_patch > 0.5) {
		vec2 uv = wp.xz / track_span;
		float fade = track_fade(uv) * track_edge(wp.xz) * 1.25;
		float cap = v_sd + v_md + 0.03 * wet;
		float e = track_res;
		t = min(texture(track_tex, uv).r * fade, cap);
		float tx = min(texture(track_tex, uv + vec2(e / track_span, 0.0)).r * fade, cap) - min(texture(track_tex, uv - vec2(e / track_span, 0.0)).r * fade, cap);
		float tz = min(texture(track_tex, uv + vec2(0.0, e / track_span)).r * fade, cap) - min(texture(track_tex, uv - vec2(0.0, e / track_span)).r * fade, cap);
		vec3 g = sn / max(sn.y, 0.05);
		nw = normalize(vec3(g.x + tx / (2.0 * e), 1.0, g.z + tz / (2.0 * e)));
		// стенка следа: чёткий тонкий контур
		wall = smoothstep(0.3, 1.5, length(vec2(tx, tz)) / (2.0 * e));
	}
	// снег: слой по глубине сугроба, на кручах не держится
	float cover = smoothstep(0.012, 0.07, v_sd + (fine - 0.5) * 0.02) * smoothstep(0.35, 0.6, wn.y + (s - 0.5) * 0.1);
	cover = max(cover, smoothstep(0.2, 0.5, snow + wn.y * 0.2 - 0.2) * step(0.01, snow) * 0.5 * smoothstep(0.5, 0.7, wn.y));
	float drift = clamp(v_sd / 0.8, 0.0, 1.0);
	float packed = smoothstep(0.2, 0.6, v_wear);
	vec3 sc = vec3(0.7, 0.73, 0.8) * (0.94 + fine * 0.05 + drift * 0.04);
	sc = mix(sc, vec3(0.6, 0.63, 0.7) * (0.9 + fine * 0.15), packed * 0.7);
	// в яме снег голубеет и темнеет, на дне грязного следа стоит вода
	// в яме — лёгкая прохладная тень, глубже чуть темнее; стенки рисует нормаль
	float hole = smoothstep(0.0, 0.03, t) * 0.5 + smoothstep(0.05, 0.6, t) * 0.5;
	sc = mix(sc, sc * vec3(0.8, 0.85, 0.94), hole);
	sc *= 1.0 - wall * vec3(0.3, 0.26, 0.18);
	sc = mix(sc, c * 0.6 + sc * 0.4, smoothstep(0.9, 1.0, t / max(v_sd, 0.001)) * step(0.05, t) * 0.6);
	vec3 mudt = c * (1.0 - smoothstep(0.0, 0.15, t) * 0.6) * (1.0 - wall * 0.3);
	c = mix(mudt, sc, cover);
	c *= 1.0 - wet * 0.25 * (1.0 - cover);
	ALBEDO = c;
	float gloss = max(wet, mudv * 0.8) * (1.0 - cover);
	ROUGHNESS = mix(mix(1.0, 0.6, wet), 0.85, cover) - gloss * 0.2 * mudv - puddle * 0.2;
	SPECULAR = (mudv * 0.2 + puddle * 0.15) * (1.0 - cover);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
}
