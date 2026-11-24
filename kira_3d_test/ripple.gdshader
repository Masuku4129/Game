shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

// Содрогание воздуха: расширяющееся кольцо, которое искажает картинку за собой
// (берёт экран и сдвигает его по радиусу), плюс бледная сиреневая кромка.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float strength = 0.035;
uniform vec3 tint = vec3(0.78, 0.66, 1.0);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ring_r = mix(0.12, 0.95, progress);
	float width = mix(0.10, 0.22, progress);
	float d = (r - ring_r) / width;
	float ring = exp(-d * d * 3.0);
	float fade = pow(1.0 - progress, 1.2);
	vec2 dir = r > 0.0001 ? p / r : vec2(0.0);
	vec2 off = dir * ring * strength * fade * sin(d * 3.14159);
	vec3 bg = textureLod(screen_tex, SCREEN_UV + off, 0.0).rgb;
	float rim = ring * fade;
	ALBEDO = bg + tint * rim * 0.35;
	ALPHA = clamp(ring * fade * 1.4, 0.0, 1.0) * step(r, 1.0);
}
