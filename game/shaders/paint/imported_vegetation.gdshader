shader_type spatial;
render_mode cull_disabled;

// Vertex colors come from the original merged GLB meshes. Green-dominant regions
// are foliage; brown/grey regions remain bark, wood and stone.
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
varying float foliage_mask;
varying float local_height;
varying float vertex_color_valid;

void vertex() {
    float color_distance = length(COLOR.rgb - vec3(1.0));
    vertex_color_valid = step(0.10, color_distance);
    float green_dominance = COLOR.g - max(COLOR.r, COLOR.b) * 1.12;
    local_height = clamp(VERTEX.y / 8.0, 0.0, 1.0);
    // Fallback foliage mask for models without meaningful vertex colors:
    // height separates crown from trunk, while authored green colors take precedence.
    float authored_mask = smoothstep(0.015, 0.12, green_dominance);
    float fallback_mask = smoothstep(0.22, 0.55, local_height);
    foliage_mask = mix(fallback_mask, authored_mask, vertex_color_valid);
    vec3 fallback_color = is_rock > 0.5 ? fallback_rock_color : mix(fallback_bark_color, fallback_leaf_color, foliage_mask);
    base_color = mix(fallback_color, COLOR.rgb, vertex_color_valid);

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
    vec3 autumn_tint = mix(vec3(0.55, 0.25, 0.075), vec3(0.82, 0.56, 0.16), clamp(base_color.g, 0.0, 1.0));
    color = mix(color, autumn_tint, clamp(autumn * leaf, 0.0, 1.0));

    float snow_cover = smoothstep(0.38, 0.84, world_normal.y) * snow;
    color = mix(color, vec3(0.89, 0.93, 0.98), snow_cover);
    color *= 1.0 - wet * 0.13;

    ALBEDO = color;
    ROUGHNESS = 0.94;
    SPECULAR = 0.08;
}
