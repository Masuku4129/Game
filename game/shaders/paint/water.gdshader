shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_schlick_ggx;
// Прозрачная река: у берега видно дно, глубже — бирюзово-зелёная толща, блики мазками.
// глубина из карты высот рельефа (на телефоне буфер глубины недоступен прозрачным)
uniform sampler2D hmap : filter_linear, repeat_disable;
uniform float hsize = 512.0;
uniform vec3 shallow = vec3(0.34, 0.48, 0.42);
uniform vec3 deep = vec3(0.07, 0.2, 0.22);
uniform float ice = 0.0;
uniform float rain = 0.0;
// круги и след от плывущего героя
uniform vec3 hero_pos = vec3(0.0, -1000.0, 0.0);
uniform float swim = 0.0;
uniform float swim_move = 0.0;
// бобровые плотины: dams — центр створа (x, z), подъём перед плотиной, спад после;
// dams_t — направление течения (x, z), 1 — плотина есть. Зона: вдоль течения -up_len..down_len,
// поперёк — half_w от оси реки. strip = 1 — полоса воды у плотины (уровень по зоне), 0 — общая гладь (в зоне её нет).
uniform vec4 dams[4];
uniform vec4 dams_t[4];
uniform float up_len = 55.0;
uniform float down_len = 35.0;
uniform float half_w = 30.0;
uniform float strip = 0.0;
vec3 lin(vec3 c) { return pow(c, vec3(2.2)); }
varying vec3 wp;

float river_d(vec2 p) { return abs(p.y - 70.0 * sin(p.x / 95.0) - 20.0); }
float dam_level(vec2 p) {
	float o = 0.0;
	float lat = 1.0 - smoothstep(half_w - 6.0, half_w, river_d(p));
	for (int i = 0; i < 4; i++) {
		if (dams_t[i].z > 0.5) {
			float u = dot(p - dams[i].xy, dams_t[i].xy);
			o += (u < 0.0 ? dams[i].z * smoothstep(-up_len, -up_len * 0.35, u) : -dams[i].w * (1.0 - smoothstep(2.0, down_len, u))) * step(-up_len, u) * step(u, down_len);
		}
	}
	return o * lat;
}
bool in_zone(vec2 p) {
	bool r = false;
	if (river_d(p) < half_w) {
		for (int i = 0; i < 4; i++) {
			float u = dot(p - dams[i].xy, dams_t[i].xy);
			if (dams_t[i].z > 0.5 && u > -up_len && u < down_len) { r = true; }
		}
	}
	return r;
}

float h21(vec2 p) {
	p = mod(p, 1024.0);
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

// Дождь по воде: расходящиеся круги от капель в трёх слоях ячеек, у каждой капли свой ритм.
// Возвращает (наклон x, наклон z, яркость кольца, всплеск в центре).
vec4 rain_rings(vec2 p, float t) {
	vec4 o = vec4(0.0);
	for (int l = 0; l < 3; l++) {
		float sc = 1.6 + float(l) * 0.9;
		vec2 q = p * sc + float(l) * 3.7;
		vec2 cell = floor(q);
		vec2 f = fract(q) - 0.5;
		float r1 = h21(cell + float(l) * 17.0);
		float r2 = h21(cell * 1.7 + 5.3 + float(l));
		// капля в ячейке бывает не всегда: чем сильнее дождь, тем чаще
		float on = step(r2, rain * 0.9 + 0.1);
		float ph = fract(t * (0.9 + r1 * 0.6) + r2);
		vec2 c = (vec2(r1, r2) - 0.5) * 0.5;
		vec2 dv = f - c;
		float d = length(dv);
		float rad = ph * 0.42;
		float w = 1.0 - smoothstep(0.0, 0.05 + ph * 0.04, abs(d - rad));
		float fade = (1.0 - ph) * (1.0 - ph) * on;
		o.xy += dv / max(d, 0.001) * w * fade;
		o.z += w * fade;
		o.w += (1.0 - smoothstep(0.0, 0.05, d)) * (1.0 - smoothstep(0.0, 0.12, ph)) * on;
	}
	return o;
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (strip > 0.5) {
		float o = dam_level(wp.xz);
		VERTEX.y += o;
		wp.y += o;
	}
}

void fragment() {
	if (in_zone(wp.xz) != (strip > 0.5)) {
		discard;
	}
	float gy = texture(hmap, wp.xz / hsize + 0.5).r;
	float depth = clamp(wp.y - gy, 0.0, 10.0);
	float k = smoothstep(0.0, 2.2, depth);
	vec2 flow = vec2(TIME * 0.35, 0.0);
	float r1 = vn(wp.xz * vec2(0.8, 2.2) - flow);
	float r2 = vn(wp.xz * vec2(1.6, 4.0) - flow * 1.7 + 3.0);
	float glint = smoothstep(0.82, 0.95, r1 * 0.6 + r2 * 0.5);
	vec2 hd = wp.xz - hero_pos.xz;
	float dh = length(hd);
	float ring = sin(dh * 9.0 - TIME * (4.0 + swim_move * 4.0)) * exp(-dh * 0.9) * swim * (1.0 - ice);
	float foam = smoothstep(0.55, 0.0, dh) * swim * (0.4 + swim_move * 0.6) * (0.6 + 0.4 * vn(wp.xz * 8.0 + TIME * 2.0));
	glint = max(glint, smoothstep(0.25, 0.7, ring));
	vec4 rr = vec4(0.0);
	if (rain > 0.02) {
		rr = rain_rings(wp.xz, TIME) * (1.0 - ice) * smoothstep(0.02, 0.25, rain);
	}
	vec3 c = mix(lin(shallow), lin(deep), k);
	// в дождь гладь темнеет и рябит, блики дробятся
	c *= 1.0 - rain * 0.12 * (1.0 - ice);
	c += vec3(0.85, 0.95, 0.9) * glint * 0.08 * (1.0 - rain * 0.5);
	c += vec3(0.75, 0.82, 0.85) * (rr.z * 0.09 + rr.w * 0.22);
	c = mix(c, vec3(0.8, 0.86, 0.84), foam * 0.6);
	c = mix(c, vec3(0.78, 0.86, 0.9), ice);
	ALBEDO = c;
	ALPHA = mix(clamp(0.3 + k * 0.62 + glint * 0.08 + rr.z * 0.1 + rr.w * 0.25, 0.0, 0.9), 0.97, ice);
	NORMAL = normalize(vec3((r1 - 0.5) * 0.25 + hd.x / max(dh, 0.01) * ring * 0.3 + rr.x * 0.5, 1.0, (r2 - 0.5) * 0.25 + hd.y / max(dh, 0.01) * ring * 0.3 + rr.y * 0.5) * mat3(INV_VIEW_MATRIX));
	ROUGHNESS = mix(0.55, 0.6, ice);
	SPECULAR = 0.2;
	METALLIC = 0.0;
}
