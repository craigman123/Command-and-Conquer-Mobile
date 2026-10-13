shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
    vec2 px = SCREEN_PIXEL_SIZE * strength * 25.0;
    vec3 sum = vec3(0.0);
    for (int i = 0; i < 16; i++) {
        float a = float(i) * 2.399963;          // golden angle
        float r = sqrt(float(i) + 0.5) / 4.0;   // spreads taps over a disc
        sum += texture(screen_tex, SCREEN_UV + vec2(cos(a), sin(a)) * r * px).rgb;
    }
    vec3 col = sum / 16.0;
    col *= mix(1.0, 0.6, strength);             // slight darkening
    COLOR = vec4(col, 1.0);
}