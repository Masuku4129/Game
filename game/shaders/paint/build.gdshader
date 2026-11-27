shader_type spatial;
render_mode cull_disabled;
#include "res://shaders/paint/paint.gdshaderinc"
#include "res://shaders/fade.gdshaderinc"
// Постройки: тёсаное дерево, торцы брёвен, побелка и глина, снег, ткань, мех.
// Цвет — вершинный (COLOR.rgb в sRGB), COLOR.a — 1 снаружи (ложится снег), 0 внутри.
// mode 0 — мазки краски, 1 — волокна дерева вдоль UV.y, 2 — годичные кольца торца (UV вокруг 0.5),
// 3 — гранёная поверхность (вырезанный лопатой снег, глина под рукой).
uniform int mode = 0;
uniform bool no_fade = true;
uniform float snow = 0.0;
uniform float wet = 0.0;
uniform float stroke_k = 0.22;
varying vec3 wp;
varying vec3 wn;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	if (!no_fade && fade_discard(wp, FRAGCOORD.xy)) {
		discard;
	}
	vec3 n = normalize(wn);
	if (mode == 3) {
		n = normalize(cross(dFdx(wp), dFdy(wp)));
		if (dot(n, CAMERA_POSITION_WORLD - wp) < 0.0) { n = -n; }
		n = normalize(mix(n, normalize(wn), 0.35));
	}
	if (!FRONT_FACING && mode != 3) { n = -n; }
	vec3 base = lin(COLOR.rgb);
	float s;
	if (mode == 1) {
		// волокна: вытянутый вдоль доски шум, тёмные прожилки, сучки
		float f = vnoise(vec2(UV.x * 26.0, UV.y * 1.3)) * 0.55 + vnoise(vec2(UV.x * 70.0, UV.y * 4.0)) * 0.45;
		float vein = smoothstep(0.62, 0.8, vnoise(vec2(UV.x * 40.0 + UV.y * 0.6, UV.y * 0.8)));
		float knot = smoothstep(0.93, 0.98, vnoise(UV * vec2(30.0, 7.0)));
		s = f;
		base *= mix(1.0 - stroke_k, 1.0 + stroke_k, f) * (1.0 - vein * 0.12) * (1.0 - knot * 0.35);
	} else if (mode == 2) {
		// торец: светлый срез с годичными кольцами и трещинами от сердцевины, тёмная кромка коры
		vec2 q = UV - 0.5;
		float r = length(q) * 2.0;
		float ring = sin(r * 38.0 + vnoise(q * 9.0) * 4.0) * 0.5 + 0.5;
		float crack = smoothstep(0.03, 0.0, abs(fract(atan(q.y, q.x) / 6.2831 * 3.0 + vnoise(q * 3.0) * 0.2) - 0.5) - 0.47) * step(0.25, r);
		s = ring;
		base *= (0.9 + ring * 0.14) * (1.0 - smoothstep(0.86, 0.98, r) * 0.45) * (1.0 - crack * 0.35);
	} else {
		s = strokes(wp.xz * 3.1 + wp.y * 2.3 + UV * 4.0);
		float fine = vnoise(wp.xz * 11.0 + wp.y * 7.0);
		base *= mix(1.0 - stroke_k, 1.0 + stroke_k, s * 0.7 + fine * 0.3);
	}
	// снег на верхних гранях снаружи
	base = mix(base, vec3(0.86, 0.9, 0.96), smoothstep(0.55, 0.85, n.y + (s - 0.5) * 0.3) * snow * COLOR.a);
	base *= 1.0 - wet * 0.25 * COLOR.a;
	ALBEDO = cartoon(base);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ROUGHNESS = mix(0.95, 0.6, wet * COLOR.a);
	SPECULAR = 0.05;
}
