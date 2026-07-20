shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

const int MAX_WAVE_COUNT = 4;
const int MAX_IMPACT_RIPPLES = 16;

uniform vec4 shallow_color : source_color = vec4(0.17, 0.62, 0.76, 1.0);
uniform vec4 deep_color : source_color = vec4(0.015, 0.13, 0.25, 1.0);
uniform vec4 crest_color : source_color = vec4(0.82, 0.96, 1.0, 1.0);

uniform float ocean_time = 0.0;
uniform int active_wave_count = 3;
uniform float wave_height_scale : hint_range(0.0, 4.0, 0.01) = 1.0;
uniform float maximum_displacement : hint_range(0.0, 20.0, 0.01) = 3.0;

uniform vec4 wave_direction_amplitude_0 = vec4(1.0, 0.16, 0.55, 0.0);
uniform vec4 wave_frequency_speed_phase_0 = vec4(0.055, 0.9, 0.0, 0.0);
uniform vec4 wave_direction_amplitude_1 = vec4(-0.38, 0.92, 0.32, 0.0);
uniform vec4 wave_frequency_speed_phase_1 = vec4(0.085, 1.35, 1.2, 0.0);
uniform vec4 wave_direction_amplitude_2 = vec4(0.74, -0.67, 0.2, 0.0);
uniform vec4 wave_frequency_speed_phase_2 = vec4(0.13, 0.55, 2.1, 0.0);
uniform vec4 wave_direction_amplitude_3 = vec4(-0.88, -0.46, 0.0, 0.0);
uniform vec4 wave_frequency_speed_phase_3 = vec4(0.0, 0.0, 0.0, 0.0);

uniform sampler2D normal_map_a : hint_normal;
uniform sampler2D normal_map_b : hint_normal;
uniform vec2 normal_speed_a = vec2(0.025, 0.012);
uniform vec2 normal_speed_b = vec2(-0.018, 0.02);
uniform float normal_scale_a : hint_range(0.001, 1.0, 0.001) = 0.08;
uniform float normal_scale_b : hint_range(0.001, 1.0, 0.001) = 0.035;
uniform float normal_strength : hint_range(0.0, 1.0, 0.01) = 0.0;

uniform float fresnel_power : hint_range(0.1, 12.0, 0.1) = 4.0;
uniform float fresnel_strength : hint_range(0.0, 2.0, 0.01) = 0.45;
uniform float roughness : hint_range(0.0, 1.0, 0.01) = 0.28;
uniform float specular_strength : hint_range(0.0, 1.0, 0.01) = 0.62;
uniform float crest_foam_threshold : hint_range(0.0, 1.0, 0.01) = 0.68;
uniform float crest_foam_strength : hint_range(0.0, 2.0, 0.01) = 0.45;

uniform int active_impact_count = 0;
uniform vec4 impact_ripples[MAX_IMPACT_RIPPLES];
uniform float ripple_speed : hint_range(0.1, 40.0, 0.1) = 8.5;
uniform float ripple_width : hint_range(0.05, 8.0, 0.01) = 1.15;
uniform float ripple_frequency : hint_range(0.1, 30.0, 0.1) = 7.0;
uniform float ripple_decay : hint_range(0.0, 8.0, 0.01) = 1.25;
uniform float ripple_height_scale : hint_range(0.0, 4.0, 0.01) = 0.35;
uniform float impact_depression_strength : hint_range(0.0, 4.0, 0.01) = 0.22;
uniform float impact_depression_duration : hint_range(0.01, 2.0, 0.01) = 0.28;
uniform float maximum_impact_displacement : hint_range(0.0, 8.0, 0.01) = 1.4;

varying float wave_height_varying;
varying float normalized_wave_height_varying;
varying vec3 world_normal_varying;
varying vec3 world_position_varying;

vec4 get_wave_direction_amplitude(int index) {
	if (index == 0) {
		return wave_direction_amplitude_0;
	}
	if (index == 1) {
		return wave_direction_amplitude_1;
	}
	if (index == 2) {
		return wave_direction_amplitude_2;
	}
	return wave_direction_amplitude_3;
}

vec4 get_wave_frequency_speed_phase(int index) {
	if (index == 0) {
		return wave_frequency_speed_phase_0;
	}
	if (index == 1) {
		return wave_frequency_speed_phase_1;
	}
	if (index == 2) {
		return wave_frequency_speed_phase_2;
	}
	return wave_frequency_speed_phase_3;
}

float sample_impact_ripples(vec2 world_xz) {
	float displacement = 0.0;
	int ripple_count = min(active_impact_count, MAX_IMPACT_RIPPLES);

	for (int index = 0; index < MAX_IMPACT_RIPPLES; index++) {
		if (index >= ripple_count) {
			break;
		}

		vec4 impact = impact_ripples[index];
		float age = ocean_time - impact.z;
		if (age < 0.0) {
			continue;
		}

		float strength = max(impact.w, 0.0);
		vec2 center = impact.xy;
		float distance_to_center = distance(world_xz, center);
		float radius = age * ripple_speed;
		float ring_distance = distance_to_center - radius;
		float width = max(ripple_width * (1.0 + strength * 0.08), 0.001);
		float ring_envelope = exp(-(ring_distance * ring_distance) / (2.0 * width * width));
		float time_decay = exp(-age * ripple_decay);
		float ring_wave = sin(ring_distance * ripple_frequency - age * 5.0);
		displacement += ring_wave * ring_envelope * time_decay * strength * ripple_height_scale;

		float depression_life = 1.0 - smoothstep(0.0, impact_depression_duration, age);
		float depression_radius = max(0.8 + strength * 0.28 + radius * 0.12, 0.001);
		float depression_mask = 1.0 - smoothstep(0.0, depression_radius, distance_to_center);
		displacement -= depression_mask * depression_life * impact_depression_strength * strength;
	}

	return clamp(displacement, -maximum_impact_displacement, maximum_impact_displacement);
}

void vertex() {
	vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 world_xz = world_position.xz;
	float height = 0.0;
	float slope_x = 0.0;
	float slope_z = 0.0;
	float possible_height = 0.0;
	int wave_count = min(active_wave_count, MAX_WAVE_COUNT);

	for (int index = 0; index < MAX_WAVE_COUNT; index++) {
		if (index >= wave_count) {
			break;
		}

		vec4 direction_amplitude = get_wave_direction_amplitude(index);
		vec4 frequency_speed_phase = get_wave_frequency_speed_phase(index);
		vec2 direction = direction_amplitude.xy;
		float direction_length = length(direction);
		if (direction_length < 0.0001) {
			direction = vec2(1.0, 0.0);
		} else {
			direction /= direction_length;
		}

		float amplitude = direction_amplitude.z * wave_height_scale;
		float frequency = frequency_speed_phase.x;
		float speed = frequency_speed_phase.y;
		float phase_offset = frequency_speed_phase.z;
		float phase = dot(world_xz, direction) * frequency + ocean_time * speed + phase_offset;
		float wave_sin = sin(phase);
		float wave_cos = cos(phase);

		height += wave_sin * amplitude;
		slope_x += wave_cos * amplitude * frequency * direction.x;
		slope_z += wave_cos * amplitude * frequency * direction.y;
		possible_height += abs(amplitude);
	}

	float impact_height = sample_impact_ripples(world_xz);
	float clamped_height = clamp(height + impact_height, -maximum_displacement - maximum_impact_displacement, maximum_displacement + maximum_impact_displacement);
	VERTEX.y += clamped_height;
	wave_height_varying = clamped_height;
	normalized_wave_height_varying = possible_height > 0.0001 ? clamp((height / possible_height + 1.0) * 0.5, 0.0, 1.0) : 0.5;

	vec3 world_normal = normalize(vec3(-slope_x, 1.0, -slope_z));
	world_normal_varying = world_normal;
	world_position_varying = world_position + vec3(0.0, clamped_height, 0.0);
	NORMAL = normalize((inverse(MODEL_MATRIX) * vec4(world_normal, 0.0)).xyz);
}

void fragment() {
	float height_blend = clamp(normalized_wave_height_varying, 0.0, 1.0);
	vec3 base_color = mix(deep_color.rgb, shallow_color.rgb, height_blend * 0.55 + 0.18);

	vec2 uv_a = world_position_varying.xz * normal_scale_a + ocean_time * normal_speed_a;
	vec2 uv_b = world_position_varying.xz * normal_scale_b + ocean_time * normal_speed_b;
	vec3 normal_a = texture(normal_map_a, uv_a).xyz * 2.0 - 1.0;
	vec3 normal_b = texture(normal_map_b, uv_b).xyz * 2.0 - 1.0;
	vec3 blended_normal = normalize(vec3(normal_a.xy + normal_b.xy, normal_a.z + normal_b.z));
	vec3 encoded_normal = blended_normal * 0.5 + 0.5;
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), encoded_normal, normal_strength);
	NORMAL_MAP_DEPTH = normal_strength;

	float view_alignment = clamp(dot(normalize(world_normal_varying), normalize(CAMERA_POSITION_WORLD - world_position_varying)), 0.0, 1.0);
	float fresnel = pow(1.0 - view_alignment, fresnel_power) * fresnel_strength;
	float crest = smoothstep(crest_foam_threshold, 1.0, height_blend) * crest_foam_strength;
	vec3 final_color = base_color + vec3(fresnel) + crest_color.rgb * crest;

	ALBEDO = final_color;
	ROUGHNESS = roughness;
	SPECULAR = specular_strength;
}
