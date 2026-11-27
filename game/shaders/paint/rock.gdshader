shader_type spatial;
render_mode cull_disabled;
#include "res://shaders/paint/paint.gdshaderinc"
#include "res://shaders/fade.gdshaderinc"
// Камень гранями: плоские грани, тёплый серый, мох сверху, мазки.
uniform vec3 col = vec3(0.48, 0.45, 0.38);
uniform vec3 col_dark = vec3(0.27, 0.27, 0.25);
uniform vec3 moss = vec3(0.42, 0.54, 0.27);
uniform float moss_k = 0.4;
uniform float snow = 0.0;
uniform float wet = 0.0;
varying vec3 wp;
varying float vis;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vis = dist_vis(INSTANCE_CUSTOM, MODEL_MATRIX[3].xyz);
	if (abs(vis) < 0.001) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	if (vis_discard(vis, FRAGCOORD.xy) || fade_discard(wp, FRAGCOORD.xy)) {
		discard;
	}
	vec3 wn = normalize(cross(dFdx(wp), dFdy(wp)));
	if (dot(wn, CAMERA_POSITION_WORLD - wp) < 0.0) { wn = -wn; }
	vec3 n = (VIEW_MATRIX * vec4(wn, 0.0)).xyz;
	float s = strokes(wp.xz * 2.0 + wp.y * 1.3);
	vec3 c = mix(lin(col_dark), lin(col), clamp(s * 0.7 + COLOR.r * 0.5, 0.0, 1.0));
	float m = smoothstep(0.6, 0.9, wn.y + (s - 0.5) * 0.4) * moss_k;
	c = mix(c, lin(moss), m);
	c = mix(c, vec3(0.9, 0.93, 0.97), smoothstep(0.5, 0.75, wn.y + s * 0.2) * snow);
	c *= 1.0 - wet * 0.3;
	ALBEDO = c;
	NORMAL = n;
	ROUGHNESS = mix(0.95, 0.4, wet);
	SPECULAR = 0.1;
}
