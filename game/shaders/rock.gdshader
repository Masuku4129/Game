shader_type spatial;
render_mode diffuse_burley;
// Камни и валуны: трипланарная текстура скалы в двух масштабах с рельефом из карты высот.
uniform sampler2D rock : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile = 0.55;
uniform float bump = 1.4;
varying vec3 wp;
varying vec3 wn;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec4 tri(vec3 p, vec3 bw, float sc) {
	return texture(rock, p.zy * sc) * bw.x + texture(rock, p.xz * sc) * bw.y + texture(rock, p.xy * sc) * bw.z;
}

void fragment() {
	vec3 bw = pow(abs(wn), vec3(4.0));
	bw /= (bw.x + bw.y + bw.z);
	vec4 a = tri(wp, bw, tile);
	vec4 b = tri(wp, bw, tile * 0.27);
	vec3 col = mix(a.rgb, b.rgb, 0.4);
	// рельеф по доминирующей плоскости
	float e = 0.005;
	vec3 g;
	if (bw.y > bw.x && bw.y > bw.z) {
		vec2 uv = wp.xz * tile;
		vec2 d = vec2(texture(rock, uv + vec2(e, 0)).a - texture(rock, uv - vec2(e, 0)).a, texture(rock, uv + vec2(0, e)).a - texture(rock, uv - vec2(0, e)).a);
		g = vec3(d.x, 0.0, d.y);
	} else if (bw.x > bw.z) {
		vec2 uv = wp.zy * tile;
		vec2 d = vec2(texture(rock, uv + vec2(e, 0)).a - texture(rock, uv - vec2(e, 0)).a, texture(rock, uv + vec2(0, e)).a - texture(rock, uv - vec2(0, e)).a);
		g = vec3(0.0, d.y, d.x);
	} else {
		vec2 uv = wp.xy * tile;
		vec2 d = vec2(texture(rock, uv + vec2(e, 0)).a - texture(rock, uv - vec2(e, 0)).a, texture(rock, uv + vec2(0, e)).a - texture(rock, uv - vec2(0, e)).a);
		g = vec3(d.x, d.y, 0.0);
	}
	vec3 nw = normalize(wn - g * bump * 9.0);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	// мох сверху по цвету вершин
	ALBEDO = col * COLOR.rgb * (0.65 + a.a * 0.6);
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
