shader_type spatial;
render_mode cull_disabled, unshaded, blend_mix, depth_draw_never, shadows_disabled;
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	ALBEDO = COLOR.rgb * vec3(1.1, 0.8, 1.6);
	ALPHA = clamp(COLOR.a, 0.0, 1.0) * 0.55 * (1.0 - dissolve);
}
