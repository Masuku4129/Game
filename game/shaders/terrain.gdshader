shader_type spatial;
render_mode diffuse_burley;
// Земля без текстур: лесная подстилка, трава, хвоя, грязь у воды и скала на крутых склонах.
uniform vec3 forest_col : source_color = vec3(0.27, 0.26, 0.17);
uniform vec3 grass_col : source_color = vec3(0.36, 0.42, 0.20);
uniform vec3 needle_col : source_color = vec3(0.33, 0.24, 0.15);
uniform vec3 mud_col : source_color = vec3(0.22, 0.19, 0.14);
uniform vec3 rock_col : source_color = vec3(0.47, 0.46, 0.42);
varying vec3 wpos;
varying vec3 wnor;

float hash(vec3 p) { return fract(sin(dot(p, vec3(17.13, 91.7, 47.2))) * 43758.5453); }
float noise(vec3 p) {
	vec3 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}

void vertex() {
	wpos = VERTEX;
	wnor = NORMAL;
}

void fragment() {
	float n1 = noise(wpos * 0.15), n2 = noise(wpos * 1.3), n3 = noise(wpos * 6.0);
	vec3 base = mix(forest_col, grass_col, COLOR.r);
	base = mix(base, needle_col, COLOR.b * smoothstep(0.35, 0.7, n1) * 0.7);
	base *= 0.78 + n2 * 0.3 + n3 * 0.14;
	base = mix(base, mud_col * (0.8 + n2 * 0.3), COLOR.g);
	float slope = 1.0 - wnor.y;
	float rk = smoothstep(0.22, 0.38, slope + (n2 - 0.5) * 0.1);
	float strata = noise(vec3(wpos.x * 0.3, wpos.y * 2.2, wpos.z * 0.3));
	vec3 rock = rock_col * (0.65 + strata * 0.35 + n3 * 0.15);
	rock = mix(rock, vec3(0.3, 0.36, 0.2), smoothstep(0.6, 0.9, n2) * (1.0 - slope) * 0.8);
	ALBEDO = mix(base, rock, rk);
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
