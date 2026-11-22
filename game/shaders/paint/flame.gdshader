shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
#include "res://shaders/paint/paint.gdshaderinc"
// Языки пламени на скрещенных карточках: форма — сужающийся вверх язык, шум бежит вверх.
// UV.x поперёк (0..1), UV.y снизу вверх (0..1). COLOR.r — сдвиг фазы карточки.
uniform float power = 1.0;   // 0 — угли, 1 — ровный огонь
uniform vec3 c_core = vec3(1.0, 0.86, 0.45);
uniform vec3 c_mid = vec3(1.0, 0.5, 0.12);
uniform vec3 c_edge = vec3(0.75, 0.16, 0.04);

void fragment() {
	float ph = COLOR.r * 17.0;
	float y = UV.y;
	float x = (UV.x - 0.5) * 2.0;
	float t = TIME * 2.3;
	float n1 = vnoise(vec2(UV.x * 5.0 + ph, y * 3.0 - t * 1.6));
	float n2 = vnoise(vec2(UV.x * 11.0 - ph, y * 6.0 - t * 2.7));
	float n = n1 * 0.65 + n2 * 0.35;
	// ширина языка падает к верху, края рвёт шум
	float h = clamp(power, 0.0, 1.0) * 0.85 + 0.15;
	float w = (1.0 - smoothstep(0.0, h, y)) * (0.75 + 0.25 * sin(y * 7.0 - t * 3.0 + ph));
	x += (n - 0.5) * 0.7 * y;
	float body = smoothstep(w, w * 0.35, abs(x)) * smoothstep(0.0, 0.08, y);
	body *= smoothstep(0.25, 0.6, n + (1.0 - y / max(h, 0.01)) * 0.7);
	float core = smoothstep(w * 0.55, 0.0, abs(x)) * (1.0 - smoothstep(0.0, h * 0.6, y));
	vec3 c = mix(lin(c_edge), lin(c_mid), smoothstep(0.1, 0.6, body));
	c = mix(c, lin(c_core), core);
	ALBEDO = c * body * 2.2;
}
