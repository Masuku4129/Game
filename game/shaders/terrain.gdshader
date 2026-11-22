shader_type spatial;
render_mode diffuse_burley;
// Земля: лесная подстилка и плотная трава (текстуры в двух масштабах), грязь у воды,
// скала на крутых склонах. Рельеф мелочей берётся из альфа-канала текстур (высота).
uniform sampler2D forest : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_forest = 0.28;
uniform float tile_grass = 0.45;
uniform float tile_rock = 0.5;
uniform float bump = 1.1;
varying vec3 wpos;
varying vec3 wnor;

float hash(vec3 p) { return fract(sin(dot(p, vec3(17.13, 91.7, 47.2))) * 43758.5453); }
float noise(vec3 p) {
	vec3 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}

vec4 tri(sampler2D t, vec3 p, vec3 bw, float sc) {
	return texture(t, p.zy * sc) * bw.x + texture(t, p.xz * sc) * bw.y + texture(t, p.xy * sc) * bw.z;
}

void vertex() {
	wpos = VERTEX;
	wnor = NORMAL;
}

vec4 two_scale(sampler2D t, vec2 uv) {
	return mix(texture(t, uv), texture(t, uv * 0.21 + vec2(0.37, 0.11)), 0.42);
}

void fragment() {
	vec2 xz = wpos.xz;
	float macro = noise(wpos * 0.05) * 0.5 + noise(wpos * 0.17) * 0.35 + noise(wpos * 0.6) * 0.15;
	// --- слой подстилки и слой травы
	vec4 f = two_scale(forest, xz * tile_forest);
	vec4 g = two_scale(grass, xz * tile_grass);
	float gw = smoothstep(0.38, 0.62, COLOR.r + (macro - 0.5) * 0.7);
	vec3 col = mix(f.rgb, g.rgb, gw);
	float hgt = mix(f.a, g.a, gw);
	// крупные пятна: суше / влажнее / мох
	col *= 0.78 + macro * 0.5;
	col = mix(col, col * vec3(0.8, 1.05, 0.7), smoothstep(0.55, 0.8, noise(wpos * 0.11)) * (1.0 - gw) * 0.6);
	// у воды: мокрая тёмная грязь и камешки
	float mud = COLOR.g;
	col = mix(col, col * vec3(0.45, 0.42, 0.38), mud);
	// --- скала по крутизне, трипланарно
	float slope = 1.0 - wnor.y;
	float rk = smoothstep(0.2, 0.36, slope + (macro - 0.5) * 0.12);
	vec3 bw = pow(abs(wnor), vec3(4.0));
	bw /= (bw.x + bw.y + bw.z);
	vec4 r = mix(tri(rock, wpos, bw, tile_rock), tri(rock, wpos, bw, tile_rock * 0.23), 0.4);
	float rd = noise(wpos * 2.7) * 0.5 + noise(wpos * 8.0) * 0.5;
	col = mix(col, r.rgb * (0.8 + macro * 0.3) * (0.75 + rd * 0.5), rk);
	hgt = mix(hgt, r.a, rk);
	// --- мнимый рельеф: градиент высоты текстуры, без карт нормалей
	float e = 0.004;
	vec2 uvf = xz * tile_forest;
	vec2 uvg = xz * tile_grass;
	vec2 uv = mix(uvf, uvg, gw);
	vec2 d = vec2(texture(forest, uvf + vec2(e, 0.0)).a - texture(forest, uvf - vec2(e, 0.0)).a, texture(forest, uvf + vec2(0.0, e)).a - texture(forest, uvf - vec2(0.0, e)).a);
	vec2 dg = vec2(texture(grass, uvg + vec2(e, 0.0)).a - texture(grass, uvg - vec2(e, 0.0)).a, texture(grass, uvg + vec2(0.0, e)).a - texture(grass, uvg - vec2(0.0, e)).a);
	d = mix(d, dg, gw) * (1.0 - rk);
	// рельеф скалы по доминирующей плоскости
	float re = 0.005;
	vec3 rg;
	if (bw.y > bw.x && bw.y > bw.z) {
		vec2 u = wpos.xz * tile_rock;
		rg = vec3(texture(rock, u + vec2(re, 0)).a - texture(rock, u - vec2(re, 0)).a, 0.0, texture(rock, u + vec2(0, re)).a - texture(rock, u - vec2(0, re)).a);
	} else if (bw.x > bw.z) {
		vec2 u = wpos.zy * tile_rock;
		rg = vec3(0.0, texture(rock, u + vec2(0, re)).a - texture(rock, u - vec2(0, re)).a, texture(rock, u + vec2(re, 0)).a - texture(rock, u - vec2(re, 0)).a);
	} else {
		vec2 u = wpos.xy * tile_rock;
		rg = vec3(texture(rock, u + vec2(re, 0)).a - texture(rock, u - vec2(re, 0)).a, texture(rock, u + vec2(0, re)).a - texture(rock, u - vec2(0, re)).a, 0.0);
	}
	vec3 nw = normalize(wnor + vec3(-d.x, 0.0, -d.y) * bump * 6.0 - rg * rk * 11.0);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	// каверны темнее
	col *= 0.7 + hgt * 0.5;
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.55, mud);
	SPECULAR = 0.25;
}
