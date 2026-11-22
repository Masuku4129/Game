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
	vec3 c = mix(lin(shallow), lin(deep), k);
	c += vec3(0.85, 0.95, 0.9) * glint * 0.08;
	c = mix(c, vec3(0.8, 0.86, 0.84), foam * 0.6);
	c = mix(c, vec3(0.78, 0.86, 0.9), ice);
	ALBEDO = c;
	ALPHA = mix(clamp(0.3 + k * 0.62 + glint * 0.08, 0.0, 0.85), 0.97, ice);
	NORMAL = normalize(vec3((r1 - 0.5) * 0.25 + hd.x / max(dh, 0.01) * ring * 0.3, 1.0, (r2 - 0.5) * 0.25 + hd.y / max(dh, 0.01) * ring * 0.3) * mat3(INV_VIEW_MATRIX));
	ROUGHNESS = mix(0.55, 0.6, ice);
	SPECULAR = 0.2;
	METALLIC = 0.0;
}
