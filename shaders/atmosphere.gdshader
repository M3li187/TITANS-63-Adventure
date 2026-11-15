shader_type spatial;
// Additive fresnel rim used for the planet's atmosphere shell.
render_mode blend_add, unshaded, cull_back, depth_draw_never;

uniform vec4 atmo_color : source_color = vec4(0.35, 0.65, 1.0, 1.0);
uniform float power = 3.0;
uniform float strength = 1.8;

void fragment() {
	float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = atmo_color.rgb * pow(f, power) * strength;
}
