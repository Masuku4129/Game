shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
// Клочья тумана: мягкие круги-билборды, плывут вокруг игрока.
uniform vec4 tint : source_color = vec4(0.55, 0.62, 0.88, 0.16);
uniform float near_fade = 6.0;

void vertex() {
	mat4 mat_world = mat4(normalize(INV_VIEW_MATRIX[0]) * length(MODEL_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]) * length(MODEL_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]) * length(MODEL_MATRIX[2]), MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat_world;
}

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float a = smoothstep(1.0, 0.0, d);
	a = a * a;
	float cam = smoothstep(1.0, near_fade, length(VERTEX));
	ALBEDO = tint.rgb;
	ALPHA = a * tint.a * COLOR.a * cam;
}
