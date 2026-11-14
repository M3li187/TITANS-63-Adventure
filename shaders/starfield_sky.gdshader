shader_type sky;
// Procedural deep-space backdrop: three star layers, a faint galactic band,
// coloured nebula clouds and a sun disc driven by the first DirectionalLight3D.

uniform vec3 nebula_a : source_color = vec3(0.16, 0.06, 0.30);
uniform vec3 nebula_b : source_color = vec3(0.03, 0.14, 0.32);
uniform float star_brightness = 2.2;
uniform float nebula_strength = 0.55;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
			   mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise3(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return v;
}

float star_layer(vec3 dir, float scale, float threshold, float radius) {
	vec3 p = dir * scale;
	vec3 c = floor(p);
	vec3 f = fract(p);
	float h = hash13(c);
	vec3 o = hash33(c) * 0.6 + 0.2;
	float d = length(f - o);
	float s = smoothstep(radius, 0.0, d);
	return s * step(threshold, h) * (0.4 + 0.6 * (h - threshold) / (1.0 - threshold));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 band_axis = normalize(vec3(0.35, 1.0, 0.25));
	float band = exp(-pow(dot(d, band_axis) * 3.2, 2.0));

	float s = star_layer(d, 70.0, 0.93, 0.10) * 1.6
			+ star_layer(d, 160.0, 0.90, 0.16) * 0.9
			+ star_layer(d, 340.0, 0.86 - band * 0.12, 0.22) * 0.55;
	float tint = hash13(floor(d * 160.0));
	vec3 star_col = mix(vec3(0.65, 0.78, 1.0), vec3(1.0, 0.88, 0.7), tint);

	float n1 = fbm(d * 2.6);
	float n2 = fbm(d * 5.0 + vec3(4.0, 1.0, 7.0));
	vec3 neb = nebula_a * smoothstep(0.45, 0.85, n1) + nebula_b * smoothstep(0.5, 0.9, n2);
	neb += vec3(0.55, 0.6, 0.8) * band * 0.05 * (0.6 + fbm(d * 9.0));

	vec3 col = star_col * s * star_brightness + neb * nebula_strength;

	if (LIGHT0_ENABLED) {
		float sd = max(dot(d, LIGHT0_DIRECTION), 0.0);
		col += LIGHT0_COLOR * (smoothstep(0.9993, 0.9998, sd) * 25.0 + pow(sd, 350.0) * 1.2 + pow(sd, 18.0) * 0.06);
	}
	COLOR = col;
}
