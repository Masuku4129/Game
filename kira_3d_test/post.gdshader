shader_type canvas_item;
// Постобработка: виньетка, лёгкая хроматическая аберрация по краям, тонировка теней/светов, зерно, красная вспышка при уроне.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float hurt = 0.0;
uniform float low_hp = 0.0;
uniform float flash = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float r2 = dot(c, c);
	vec2 off = vec2(0.0);
	vec3 col;
	col.r = textureLod(screen_tex, uv + off, 0.0).r;
	col.g = textureLod(screen_tex, uv, 0.0).g;
	col.b = textureLod(screen_tex, uv - off, 0.0).b;
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	// тонировка: тени холодные сине-фиолетовые, света тёплые
	col = mix(col, col * vec3(0.86, 0.92, 1.18), (1.0 - smoothstep(0.0, 0.45, lum)) * 0.45);
	col = mix(col, col * vec3(1.14, 1.02, 0.86), smoothstep(0.45, 1.0, lum) * 0.35);
	col += vec3(0.30, 0.20, 0.55) * flash * 0.25;
	float vig = smoothstep(0.80, 0.18, sqrt(r2) * 1.25);
	col *= mix(0.62, 1.0, vig);
	col += (hash(uv * vec2(1920.0, 1080.0) + TIME) - 0.5) * 0.028;
	float pulse = 0.5 + 0.5 * sin(TIME * 5.0);
	col = mix(col, col * vec3(1.5, 0.45, 0.55), clamp(hurt + low_hp * 0.25 * pulse, 0.0, 1.0) * smoothstep(0.05, 0.7, sqrt(r2) * 1.4));
	COLOR = vec4(col, 1.0);
}
