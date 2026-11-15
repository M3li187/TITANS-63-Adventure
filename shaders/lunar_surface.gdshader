shader_type spatial;
render_mode cull_disabled;
uniform sampler2D survey : source_color, filter_linear_mipmap;
uniform sampler2D grain : source_color, filter_linear_mipmap, repeat_enable;
void fragment() {
 vec3 mapped = texture(survey, UV).rgb;
 vec3 detail = texture(grain, UV * 80.0).rgb;
 ALBEDO = clamp(mapped * 0.28 + vec3(0.025), vec3(0.035), vec3(0.35)) * (vec3(0.88) + detail * 0.25);
 ROUGHNESS = 0.97;
}
