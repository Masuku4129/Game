shader_type spatial;
render_mode cull_back;
#include "res://shaders/fade.gdshaderinc"
#include "res://shaders/weather.gdshaderinc"
#include "res://shaders/paint/paint.gdshaderinc"
// Камни и валуны: мультяшная заливка — одна трипланарная выборка скалы в размытом виде,
// крупные цветовые пятна, мох сверху по цвету вершин. Свет — общий мультяшный.
uniform sampler2D rock : source_color, filter_linear_mipmap, repeat_enable;
uniform float tile = 0.4;
varying vec3 wp;
varying vec3 wn;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	if (fade_discard(wp, FRAGCOORD.xy)) {
		discard;
	}
	vec3 bw = pow(abs(wn), vec3(4.0));
	bw /= (bw.x + bw.y + bw.z);
	vec3 col = textureLod(rock, wp.zy * tile, 1.6).rgb * bw.x + textureLod(rock, wp.xz * tile, 1.6).rgb * bw.y + textureLod(rock, wp.xy * tile, 1.6).rgb * bw.z;
	vec3 alb = col * COLOR.rgb * (1.0 - wet * 0.3);
	alb = mix(alb, vec3(0.88, 0.9, 0.94), snow_cover(wn.y, wp));
	ALBEDO = cartoon(alb);
}
