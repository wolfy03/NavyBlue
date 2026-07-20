shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled, unshaded;

uniform vec4 foam_color : source_color = vec4(0.86, 0.97, 1.0, 1.0);
uniform float alpha : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform vec2 noise_offset = vec2(0.0, 0.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

void fragment() {
	vec2 centered_uv = UV * 2.0 - 1.0;
	float distance_from_center = length(centered_uv);
	float circle = 1.0 - smoothstep(0.68, 1.0, distance_from_center);
	float ring = smoothstep(0.18, 0.35, distance_from_center) * (1.0 - smoothstep(0.75, 1.0, distance_from_center));
	float foam_noise = noise(UV * 9.0 + noise_offset);
	float mask = circle * ring * smoothstep(0.28, 0.92, foam_noise);
	ALBEDO = foam_color.rgb;
	ALPHA = mask * alpha;
}
