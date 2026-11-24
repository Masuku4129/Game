shader_type spatial;
// Камень руин: процедурная кладка блоками (триплanar по миру) + зерно с листа + мох сверху и у земли.
uniform sampler2D slab_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint = vec3(0.60, 0.62, 0.82);
uniform float row_h = 0.40;
uniform float moss_amt = 1.0;
uniform float fade_lo = -26.0;
uniform float fade_hi = -10.0;
varying vec3 wpos;
varying vec3 wnrm;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 bricks(vec2 uv, float seed) {
	float row = floor(uv.y / row_h);
	float bl = 0.65 + h21(vec2(row, 9.1 + seed)) * 0.55;
	float x = (uv.x + h21(vec2(row, 3.7 + seed)) * 4.0) / bl;
	float col = floor(x);
	vec2 f = vec2(fract(x) * bl, fract(uv.y / row_h) * row_h);
	float e = min(min(f.x, bl - f.x), min(f.y, row_h - f.y));
	float id = h21(vec2(col + seed, row));
	float mortar = 1.0 - smoothstep(0.012, 0.045, e);
	float bevel = 0.72 + 0.28 * smoothstep(0.0, 0.12, e);
	vec3 g = texture(slab_tex, uv * 0.30 + vec2(id, seed)).rgb;
	float lum = dot(g, vec3(0.33));
	vec3 c = tint * (0.55 + 0.9 * lum) * (0.80 + 0.40 * id) * bevel;
	return mix(c, vec3(0.04, 0.04, 0.07), mortar * 0.85);
}

void fragment() {
	vec3 n = normalize(wnrm);
	vec3 b = pow(abs(n), vec3(5.0));
	b /= (b.x + b.y + b.z);
	vec3 cx = bricks(wpos.zy, 1.0);
	vec3 cz = bricks(wpos.xy, 2.0);
	vec2 tp = wpos.xz * 0.55;
	vec3 gt = texture(slab_tex, tp).rgb;
	float gl = abs(fract(wpos.x * 0.7) - 0.5) < 0.012 || abs(fract(wpos.z * 0.7) - 0.5) < 0.012 ? 0.5 : 1.0;
	vec3 cy = tint * (0.55 + 0.9 * dot(gt, vec3(0.33))) * gl;
	vec3 c = cx * b.x + cy * b.y + cz * b.z;
	float m = smoothstep(0.50, 0.80, vn(wpos.xz * 1.4 + wpos.y * 0.8));
	float mossy = m * (0.30 + 0.70 * clamp(n.y, 0.0, 1.0)) * (1.0 - smoothstep(0.4, 3.2, wpos.y)) * moss_amt;
	mossy += clamp(n.y, 0.0, 1.0) * smoothstep(0.55, 0.85, vn(wpos.xz * 3.0)) * 0.35 * moss_amt;
	c = mix(c, vec3(0.10, 0.20, 0.08) * (0.7 + vn(wpos.xz * 6.0)), clamp(mossy, 0.0, 0.8));
	float ao = 0.55 + 0.45 * smoothstep(0.0, 1.2, wpos.y + 0.3);
	ALBEDO = c * ao * 1.1;
	ALPHA = clamp((wpos.y - fade_lo) / (fade_hi - fade_lo), 0.0, 1.0);
	ROUGHNESS = 0.95;
	SPECULAR = 0.15;
	float rim = pow(1.0 - clamp(dot(n, normalize(VIEW)), 0.0, 1.0), 3.0);
	EMISSION = vec3(0.10, 0.12, 0.30) * rim * 0.45;
}
