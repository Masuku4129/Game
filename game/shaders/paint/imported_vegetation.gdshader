shader_type spatial;
render_mode cull_disabled;

// Species palettes and climate modifiers. Procedural surface detail is layered on top
// of vertex colors or fallback palette, so meshes without image textures no longer
// read as flat clay. Uses UVs plus world-space noise to avoid obvious tiling.
uniform float snow = 0.0;
uniform float wet = 0.0;
uniform float autumn = 0.0;
uniform float leaf_drop = 0.0;
uniform float wind = 0.5;
uniform float deciduous = 0.0;
uniform float sway_strength = 0.045;
uniform vec3 fallback_leaf_color = vec3(0.16, 0.30, 0.10);
uniform vec3 fallback_bark_color = vec3(0.24, 0.15, 0.09);
uniform vec3 fallback_rock_color = vec3(0.34, 0.35, 0.34);
uniform float is_rock = 0.0;

varying vec3 base_color;
varying vec3 world_normal;
varying vec3 world_position;
varying float foliage_mask;
varying float local_height;
varying float vertex_color_valid;
varying vec2 mesh_uv;

float hash3(vec3 p) {
    p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float noise3(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash3(i), hash3(i + vec3(1,0,0)), f.x),
                  mix(hash3(i + vec3(0,1,0)), hash3(i + vec3(1,1,0)), f.x), f.y),
                mix(mix(hash3(i + vec3(0,0,1)), hash3(i + vec3(1,0,1)), f.x),
                  mix(hash3(i + vec3(0,1,1)), hash3(i + vec3(1,1,1)), f.x), f.y), f.z);
}

void vertex() {
    float color_distance = length(COLOR.rgb - vec3(1.0));
    vertex_color_valid = step(0.10, color_distance);
    float green_dominance = COLOR.g - max(COLOR.r, COLOR.b) * 1.12;
    local_height = clamp(VERTEX.y / 8.0, 0.0, 1.0);
    float authored_mask = smoothstep(0.015, 0.12, green_dominance);
    float fallback_mask = smoothstep(0.22, 0.55, local_height);
    foliage_mask = mix(fallback_mask, authored_mask, vertex_color_valid);
    vec3 fallback_color = is_rock > 0.5 ? fallback_rock_color : mix(fallback_bark_color, fallback_leaf_color, foliage_mask);
    base_color = mix(fallback_color, COLOR.rgb, vertex_color_valid);
    mesh_uv = UV;
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

    float phase = TIME * (0.65 + wind) + VERTEX.x * 0.7 + VERTEX.z * 0.43;
    float sway = sin(phase) * sway_strength * wind * local_height * foliage_mask;
    VERTEX.x += sway;
    VERTEX.z += cos(phase * 0.83) * sway * 0.62;
    world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
    float leaf = foliage_mask * deciduous;
    if (leaf_drop * leaf > 0.62) {
        discard;
    }

    vec3 color = base_color;
    // Small-scale mottling and larger clumps produce non-uniform, natural-looking foliage.
    float foliage_noise = noise3(world_position * 3.8) * 0.55 + noise3(world_position * 12.0) * 0.25 + noise3(vec3(mesh_uv * 38.0, local_height * 8.0)) * 0.20;
    float leaf_variation = mix(0.76, 1.18, foliage_noise);
    color *= mix(1.0, leaf_variation, foliage_mask);

    // Bark grain: vertical bands plus irregular cracks, masked away from foliage.
    vec3 bark_coord = vec3(world_position.x * 3.0, world_position.y * 0.65, world_position.z * 3.0);
    float grain = noise3(bark_coord * vec3(2.4, 0.65, 2.4));
    float grooves = abs(sin((world_position.y * 7.0 + world_position.x * 0.8 + world_position.z * 0.6) + grain * 2.3));
    float bark_detail = mix(0.70, 1.12, grooves * 0.48 + grain * 0.52);
    color *= mix(1.0, bark_detail, (1.0 - foliage_mask) * (1.0 - is_rock));

    // Rock grain is finer and desaturated; avoid foliage treatment.
    float stone_noise = noise3(world_position * 5.2) * 0.65 + noise3(world_position * 18.0) * 0.35;
    color *= mix(0.82, 1.12, stone_noise * is_rock);

    vec3 autumn_tint = mix(vec3(0.55, 0.25, 0.075), vec3(0.82, 0.56, 0.16), clamp(base_color.g, 0.0, 1.0));
    color = mix(color, autumn_tint, clamp(autumn * leaf, 0.0, 1.0));
    float snow_cover = smoothstep(0.38, 0.84, world_normal.y) * snow;
    color = mix(color, vec3(0.89, 0.93, 0.98), snow_cover);
    color *= 1.0 - wet * 0.13;

    ALBEDO = color;
    ROUGHNESS = mix(0.96, 0.82, wet);
    SPECULAR = 0.07;
}
