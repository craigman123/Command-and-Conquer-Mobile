shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded;

uniform sampler2D albedo_tex : source_color;
uniform sampler2D mask_tex : hint_default_white;
uniform float mask_min = 0.3;
uniform float mask_max = 0.7;
uniform bool invert_mask = false;
uniform float strength = 0.7;

void fragment() {
    float m = texture(mask_tex, UV).r;
    if (invert_mask) m = 1.0 - m;
    ALBEDO = texture(albedo_tex, UV).rgb * 0.6;
    ALPHA = smoothstep(mask_min, mask_max, m) * strength;
}