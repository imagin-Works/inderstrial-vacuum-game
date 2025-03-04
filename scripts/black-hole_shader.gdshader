shader_type spatial;
render_mode unshaded;

uniform vec4 color = vec4(0.0, 0.0, 0.0, 0.0); // لون افتراضي اسود

void fragment() {
    ALBEDO = color.rgb;
}
