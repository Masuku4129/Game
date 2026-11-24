shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

// Волна-полумесяц, рассекающая плоскость удара.
// Три вложенных полумесяца разной яркости, яркая кромка, радиальные "волокна" и растворение по краю.
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec3 col_rim = vec3(1.0, 1.0, 1.0);
uniform vec3 col_body = vec3(0.62, 0.38, 1.0);
uniform vec3 col_deep = vec3(0.25, 0.08, 0.65);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.y = -p.y;                       // +y = направление полёта волны
	vec3 acc = vec3(0.0);
	float alpha = 0.0;
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float k = 1.0 - 0.16 * fi;                 // вложенные слои
		vec2 ca = vec2(0.0, -0.18 * k);
		vec2 cb = vec2(0.0, -0.18 * k - 0.52 * k);
		float ra = 0.92 * k;
		float rb = 0.86 * k;
		float da = length(p - ca) - ra;            // <0 внутри внешнего круга
		float db = length(p - cb) - rb;            // <0 внутри вычитаемого круга
		float inside = smoothstep(0.012, -0.012, da) * smoothstep(-0.012, 0.012, db);
		float thick = clamp(-db / 0.55, 0.0, 1.0);        // 0 у внутренней кромки .. 1 у внешней
		vec2 q = p - ca;
		float ang = atan(q.y, q.x);
		float streak = vnoise(vec2(ang * 22.0 + fi * 7.0, length(q) * 4.0 - progress * 8.0));
		float fib = 0.55 + 0.9 * streak;
		float rim = exp(-abs(da) * 38.0);                  // яркая внешняя кромка
		float edge2 = exp(-abs(db) * 60.0) * 0.5;          // тонкая подсветка внутренней кромки
		vec3 body = mix(col_deep, col_body, thick) * fib;
		vec3 layer = body * 0.9 + col_rim * (rim * 1.6 + edge2);
		float w = (i == 0) ? 1.0 : 0.55;
		acc += layer * inside * w;
		alpha = max(alpha, inside * w);
	}
	// растворение к концу: края рассыпаются шумом
	float n = vnoise(p * 7.0 + vec2(0.0, progress * 3.0));
	float dissolve = smoothstep(progress * 1.05 - 0.15, progress * 1.05, n);
	float fade = pow(1.0 - progress, 1.3);
	float head = smoothstep(0.0, 0.12, progress);        // быстрый вход
	ALBEDO = acc * 1.6 * fade * dissolve * head;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
