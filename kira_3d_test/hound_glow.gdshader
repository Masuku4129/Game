shader_type spatial;
render_mode cull_disabled, shadows_disabled;
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform float energy = 3.2;
void fragment() {
	if (dissolve > 0.55) { discard; }
	ALBEDO = vec3(0.1);
	EMISSION = COLOR.rgb * energy * (1.0 - dissolve);
}
