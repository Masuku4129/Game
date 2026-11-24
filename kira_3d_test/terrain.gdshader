shader_type spatial;
// Рельеф: цвет граней из меша + мелкий шум, слои породы и трещины на скалах (чтобы не было "пластилина").
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

void fragment() {
	float n1 = vn(wpos.xz * 0.4);
	float n2 = vn(wpos.xz * 1.9);
	float n3 = vn(wpos.xz * 7.0);
	float d = 0.70 + 0.25 * n1 + 0.20 * n2 + 0.14 * n3;
	vec3 c = COLOR.rgb * d;
	float rock = COLOR.a;
	float s = sin(wpos.y * 2.6 + vn(wpos.xz * 0.5) * 4.0) * 0.5 + 0.5;
	float band = smoothstep(0.55, 0.62, s);
	vec3 rc = COLOR.rgb * (0.78 + 0.32 * s);
	rc *= 1.0 - 0.35 * smoothstep(0.7, 0.95, vn(vec2(wpos.x + wpos.z, wpos.y * 3.0) * 2.3));
	rc = mix(rc, rc * vec3(1.25, 1.05, 0.95), band * 0.5);
	c = mix(c, rc * (0.9 + 0.2 * n2), rock);
	ALBEDO = c;
	ROUGHNESS = 0.96;
	SPECULAR = 0.15;
}
