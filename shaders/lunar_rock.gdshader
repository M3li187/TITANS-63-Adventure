shader_type spatial;
void vertex() {
 float n = fract(sin(dot(VERTEX, vec3(13.3, 71.7, 21.9))) * 4358.53);
 VERTEX *= 0.86 + n * 0.22;
}
void fragment() {
 ALBEDO = vec3(0.17, 0.16, 0.145);
 ROUGHNESS = 1.0;
}
