shader_type spatial;
render_mode cull_disabled;
// Боковая стена моста: кладка, арочные пролёты, опоры уходят вниз в дымку пропасти.
uniform sampler2D slab_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint = vec3(0.58, 0.60, 0.82);
uniform float zend = 35.0;
varying vec3 wpos;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 bricks(vec2 uv) {
	float rh = 0.45;
	float row = floor(uv.y / rh);
	float bl = 0.7 + h21(vec2(row, 9.1)) * 0.6;
	float x = (uv.x + h21(vec2(row, 3.7)) * 4.0) / bl;
	float col = floor(x);
	vec2 f = vec2(fract(x) * bl, fract(uv.y / rh) * rh);
	float e = min(min(f.x, bl - f.x), min(f.y, rh - f.y));
	float id = h21(vec2(col, row));
	float mortar = 1.0 - smoothstep(0.012, 0.05, e);
	float bevel = 0.72 + 0.28 * smoothstep(0.0, 0.13, e);
	vec3 g = texture(slab_tex, uv * 0.30 + vec2(id, 0.3)).rgb;
	vec3 c = tint * (0.55 + 0.9 * dot(g, vec3(0.33))) * (0.80 + 0.40 * id) * bevel;
	return mix(c, vec3(0.04, 0.04, 0.07), mortar * 0.85);
}

void fragment() {
	float u = wpos.z;
	float v = wpos.y;
	float endz = zend + 1.8 * vn(vec2(v * 0.4, 7.0));
	if (u > endz) {
		discard;
	}
	float d = abs(mod(u, 12.0) - 6.0);   // расстояние до центра пролёта (центры на u = 6 mod 12), опоры на u = 0 mod 12
	bool open = false;
	if (d < 4.2) {
		if (v < -7.0) {
			open = true;
		} else if (d * d + (v + 7.0) * (v + 7.0) < 17.64) {
			open = true;
		}
	}
	if (open) {
		discard;
	}
	vec3 c = bricks(vec2(u, v));
	c *= 0.8 + 0.3 * vn(vec2(u, v) * 0.5);
	// мох сверху и тень под балкой
	c = mix(c, vec3(0.10, 0.20, 0.09), smoothstep(0.55, 0.85, vn(vec2(u, v) * 0.9)) * 0.28 * smoothstep(-6.0, -0.5, v));
	float fade = clamp((v + 17.0) / 8.0, 0.0, 1.0);
	c = mix(vec3(0.06, 0.05, 0.14), c, fade);
	ALBEDO = c;
	ALPHA = clamp((v + 17.0) / 6.0, 0.0, 1.0);
	ROUGHNESS = 0.95;
	SPECULAR = 0.12;
}
