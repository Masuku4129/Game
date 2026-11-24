shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
// Лучи света сквозь кроны: цилиндрический билборд вдоль луча, мягкие края, медленное мерцание.
instance uniform float seed = 0.0;
uniform vec3 col : source_color = vec3(0.62, 0.72, 1.0);
uniform float strength = 0.16;
varying float vseed;
varying float cam_d;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 axis = normalize(MODEL_MATRIX[1].xyz);
	float len = length(MODEL_MATRIX[1].xyz);
	float wid = length(MODEL_MATRIX[0].xyz);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 right = normalize(cross(axis, cam - center));
	vec3 facing = normalize(cross(right, axis));
	mat4 mw = mat4(vec4(right * wid, 0.0), vec4(axis * len, 0.0), vec4(facing, 0.0), vec4(center, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * mw;
	vseed = seed;
	cam_d = length(cam - center);
}

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	across = pow(clamp(across, 0.0, 1.0), 1.6);
	float along = smoothstep(0.0, 0.22, UV.y) * smoothstep(1.0, 0.45, UV.y);
	float n = vn(vec2(UV.y * 3.0 + vseed, UV.x * 2.0 + TIME * 0.05));
	float flick = 0.6 + 0.4 * sin(TIME * 0.35 + vseed * 3.0);
	float near = smoothstep(1.5, 9.0, length(VERTEX));
	float a = across * along * (0.45 + 0.8 * n) * flick * near;
	ALBEDO = col * a * strength * 5.0;
	ALPHA = a;
}
