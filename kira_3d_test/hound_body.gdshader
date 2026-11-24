shader_type spatial;
render_mode cull_disabled;
// Дымная гончая бездны: тёмно-фиолетовое тело, холодная кайма по краю, растворение при появлении и смерти.
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
varying vec3 wpos;
float hsh(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float n = hsh(floor(wpos.xz * 9.0) + floor(wpos.y * 9.0) * 3.7);
	if (n < dissolve) { discard; }
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.5);
	ALBEDO = COLOR.rgb * 1.2;
	ROUGHNESS = 0.9;
	EMISSION = vec3(0.30, 0.10, 0.60) * rim * 0.9 + vec3(1.0, 0.8, 0.9) * flash * 1.2
		+ vec3(0.6, 0.25, 1.0) * smoothstep(dissolve, dissolve + 0.12, n) * (1.0 - smoothstep(0.0, 0.12, n - dissolve)) * step(0.001, dissolve) * 2.0;
}
