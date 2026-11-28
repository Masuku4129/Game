shader_type spatial;
render_mode cull_disabled;
#include "res://shaders/paint/paint.gdshaderinc"
#include "res://shaders/fade.gdshaderinc
uniform sampler2D strokes_tex : filter_linear_mipmap, repeat_disable;
uniform vec3 col_root = vec3(0.36, 0.44, 0.20);
uniform vec3 col_tip = vec3(0.58, 0.64, 0.30);
uniform float wind = 0.5;
uniform float snow = 0.0;
uniform float dry = 0.0;
uniform float grass_r = 38.0;
uniform sampler2D field_tex : filter_linear;
uniform float mud_m = 0.0;
varying float hgt;
varying float vis;
uniform float grass_now = 0.0;
void vertex() {
 vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
 hgt = 1.0 - UV.y;
 float t = TIME * 0.65 + w.x * 0.12 + w.z * 0.10;
 float k = 0.018 * clamp(wind, 0.0, 2.0) * hgt;
 VERTEX.x += sin(t) * k;
 VERTEX.z += cos(t * 0.82) * k * 0.45;
 vec2 dv = w.xz - hero_pos.xz;
 float d = length(dv);
 float near = (1.0 - smoothstep(0.2, 0.8, d)) * step(abs(w.y - hero_pos.y + 1.0), 1.5);
 VERTEX += inverse(mat3(MODEL_MATRIX)) * vec3(dv.x / max(d, 0.001), -0.5, dv.y / max(d, 0.001)) * near * hgt * 0.22;
 VERTEX *= max(0.0, 1.0 - snow * 1.8);
 VERTEX *= 1.0 - smoothstep(grass_r - 14.0, grass_r - 2.0, d);
 vec4 fld = texture(field_tex, ((w.xz + 256.0) / (512.0 / 384.0) + 0.5) / 385.0);
 float mf = fld.b;
 VERTEX *= 1.0 - smoothstep(0.3, 0.6, 1.0 - fld.a);
 VERTEX *= 1.0 - smoothstep(0.3, 0.7, mf) * clamp(mud_m / 0.15, 0.0, 1.0) * 0.85;
 if (INSTANCE_CUSTOM.z > 0.0) VERTEX *= clamp((grass_now - INSTANCE_CUSTOM.z) / 0.7, 0.0, 1.0);
 NORMAL = vec3(0.0, 1.0, 0.0);
 vis = dist_vis(INSTANCE_CUSTOM, MODEL_MATRIX[3].xyz);
 if (abs(vis) < 0.001) VERTEX = vec3(0.0);
}
void fragment() {
 if (vis_discard(vis, FRAGCOORD.xy)) discard;
 vec4 s = texture(strokes_tex, UV);
 vec3 c = mix(lin(col_root), lin(col_tip), smoothstep(0.0, 1.0, hgt) * (0.65 + s.g * 0.35)) * (0.95 + COLOR.r * 0.15);
 c = mix(c, lin(vec3(0.72, 0.58, 0.32)) * (0.7 + hgt * 0.3), dry);
 ALBEDO = cartoon(c); ALPHA = s.a; ALPHA_SCISSOR_THRESHOLD = 0.5;
 ROUGHNESS = 1.0; SPECULAR = 0.0; BACKLIGHT = c * 0.15;
}