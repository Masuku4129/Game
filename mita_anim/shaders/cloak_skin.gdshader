shader_type spatial;
render_mode cull_disabled;

// Character material + cloak cloth displacement.
// CUSTOM0 = indices of 4 simulation particles, CUSTOM1 = their blend weights (already multiplied by the vertex sim weight).
// The displacement is applied AFTER skeletal skinning (VERTEX is already skinned in Godot 4).

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 disp[192];
uniform mat3 w2l = mat3(1.0);
uniform float cloth_on = 1.0;
uniform float rough_mul = 1.0;

void vertex() {
	vec3 d = vec3(0.0);
	for (int k = 0; k < 4; k++) {
		int idx = int(CUSTOM0[k] + 0.5);
		d += CUSTOM1[k] * disp[idx];
	}
	VERTEX += w2l * d * cloth_on;
}

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	ALBEDO = c.rgb;
	vec4 o = texture(orm_tex, UV);
	ROUGHNESS = clamp(o.g * rough_mul, 0.05, 1.0);
	METALLIC = o.b;
}
