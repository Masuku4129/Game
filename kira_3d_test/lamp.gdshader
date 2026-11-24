shader_type spatial;
render_mode cull_disabled, shadows_disabled;
// Тёплые окна и фонари.
void fragment() {
	ALBEDO = COLOR.rgb * 0.2;
	EMISSION = COLOR.rgb * 2.6;
}
