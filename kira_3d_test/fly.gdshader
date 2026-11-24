shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
// Светлячки: маленькие яркие точки, bloom делает ореол.
uniform vec3 glow : source_color = vec3(0.65, 0.5, 1.0);

void vertex() {
	mat4 mat_world = mat4(normalize(INV_VIEW_MATRIX[0]) * length(MODEL_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]) * length(MODEL_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]) * length(MODEL_MATRIX[2]), MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat_world;
}

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float a = smoothstep(1.0, 0.0, d);
	ALBEDO = glow * 4.0 * a * COLOR.a;
	ALPHA = a * COLOR.a;
}
