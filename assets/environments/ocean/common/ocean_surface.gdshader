shader_type canvas_item;
render_mode unshaded;

uniform vec2 map_size = vec2(4096.0, 2304.0);
uniform float animation_time = 0.0;
uniform float animation_speed = 1.0;
uniform sampler2D base_texture : filter_linear;
uniform sampler2D cloud_texture : filter_linear;
uniform sampler2D wave_texture : filter_linear;
uniform sampler2D clear_glint_texture : filter_linear;
uniform sampler2D weather_cloud_texture : filter_linear;
uniform sampler2D foam_texture : filter_linear;
uniform sampler2D rain_line_texture : filter_linear;
uniform sampler2D rain_ripple_texture : filter_linear;
uniform sampler2D storm_shadow_texture : filter_linear;
uniform sampler2D lightning_mask_texture : filter_linear;
uniform vec4 deep_color : source_color = vec4(0.071, 0.243, 0.349, 1.0);
uniform vec4 surface_color : source_color = vec4(0.118, 0.412, 0.510, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.302, 0.659, 0.710, 1.0);
uniform vec4 highlight_color : source_color = vec4(0.718, 0.894, 0.898, 1.0);
uniform vec4 cloud_color : source_color = vec4(0.051, 0.169, 0.251, 1.0);
uniform vec4 warm_reflection_color : source_color = vec4(0.576, 0.420, 0.408, 1.0);
uniform float wave_strength : hint_range(0.0, 1.0) = 0.22;
uniform float sparkle_strength : hint_range(0.0, 1.0) = 0.25;
uniform float cloud_opacity : hint_range(0.0, 1.0) = 0.1;
uniform float warm_reflection_strength : hint_range(0.0, 1.0) = 0.0;
uniform float ai_texture_strength : hint_range(0.0, 0.4) = 0.16;
uniform float foam_strength : hint_range(0.0, 1.0) = 0.02;
uniform float rain_strength : hint_range(0.0, 1.0) = 0.0;
uniform float mist_strength : hint_range(0.0, 1.0) = 0.0;
uniform float lightning_strength : hint_range(0.0, 1.0) = 0.0;
uniform float cloud_scale : hint_range(0.25, 2.0) = 1.0;
uniform float cloud_cutoff : hint_range(0.0, 1.0) = 0.42;
uniform float cloud_softness : hint_range(0.02, 0.6) = 0.27;
uniform float wave_scale : hint_range(0.4, 2.0) = 1.0;
uniform float foam_coverage : hint_range(0.0, 1.0) = 0.72;
uniform float rain_angle : hint_range(-3.14159, 3.14159) = -0.55;
uniform float rain_density : hint_range(0.0, 2.0) = 1.0;
uniform float rain_line_strength : hint_range(0.0, 2.0) = 1.0;
uniform float rain_ripple_strength : hint_range(0.0, 2.0) = 1.0;
uniform float squall_strength : hint_range(0.0, 1.0) = 0.0;

varying vec2 local_position;

float hash21(vec2 point) {
	point = fract(point * vec2(123.34, 456.21));
	point += dot(point, point + 45.32);
	return fract(point.x * point.y);
}

float value_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 local = fract(point);
	local = local * local * (3.0 - 2.0 * local);
	float a = hash21(cell);
	float b = hash21(cell + vec2(1.0, 0.0));
	float c = hash21(cell + vec2(0.0, 1.0));
	float d = hash21(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, local.x), mix(c, d, local.x), local.y);
}

float fbm(vec2 point) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int index = 0; index < 4; index++) {
		value += value_noise(point) * amplitude;
		point = point * 2.03 + vec2(17.1, 9.2);
		amplitude *= 0.5;
	}
	return value;
}

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	vec2 world = local_position;
	float time = animation_time * animation_speed;
	float broad_a = fbm(world * 0.00115 + vec2(time * 0.012, -time * 0.007));
	float broad_b = fbm(world * 0.00185 + vec2(-time * 0.008, time * 0.011) + 31.7);
	float depth = 0.5;
	depth += sin(world.x * 0.00072 + world.y * 0.00021 + time * 0.018) * 0.17;
	depth += sin(world.x * -0.00031 + world.y * 0.00091 - time * 0.013) * 0.13;
	depth += (broad_a - 0.5) * 0.0;
	depth = clamp(depth, 0.0, 1.0);
	vec3 water = mix(deep_color.rgb, surface_color.rgb, smoothstep(0.2, 0.82, depth));
	water = mix(water, shallow_color.rgb, smoothstep(0.66, 0.96, depth) * 0.3);
	vec2 texture_uv = fract(world / 1024.0);
	mat2 texture_rotation = mat2(vec2(0.819, -0.574), vec2(0.574, 0.819));
	vec3 ai_base_a = texture(base_texture, texture_uv).rgb;
	vec3 ai_base_b = texture(base_texture, fract(texture_rotation * world / 1536.0 + vec2(0.37, 0.19))).rgb;
	vec3 ai_base = mix(ai_base_a, ai_base_b, 0.42);
	water = mix(water, ai_base, ai_texture_strength);

	float wave_scale_safe = max(0.4, wave_scale);
	float wave_a = sin((world.x * 0.028 + world.y * 0.014) * wave_scale_safe + time * 1.15 + broad_a * 5.5);
	float wave_b = sin((world.x * -0.019 + world.y * 0.031) * wave_scale_safe - time * 0.86 + broad_b * 4.2);
	float wave_c = sin((world.x * 0.043 + world.y * -0.011) * wave_scale_safe + time * 0.57);
	float crest_a = smoothstep(0.985, 1.0, abs(wave_a));
	float crest_b = smoothstep(0.988, 1.0, abs(wave_b));
	float crest_c = smoothstep(0.993, 1.0, abs(wave_c));
	float wave_breakup = smoothstep(0.24, 0.82, broad_a);
	float wave_line = (crest_a * 0.64 + crest_b * 0.28 + crest_c * 0.08) * wave_strength * wave_breakup;
	float authored_wave_a = texture(wave_texture, fract(texture_uv + vec2(time * 0.002, -time * 0.0015))).r;
	float authored_wave_b = texture(wave_texture, fract(texture_rotation * world / 1380.0 - vec2(time * 0.0011, time * 0.0016) + 0.23)).r;
	float authored_wave = authored_wave_a * 0.58 + authored_wave_b * 0.42;
	float clear_glint = texture(clear_glint_texture, fract(texture_rotation * world / 1024.0 + vec2(time * 0.0008, -time * 0.0004))).r;
	float sparkle_mask = crest_a * crest_b * (0.45 + crest_c * 0.55) + authored_wave * 0.24 + clear_glint * 0.42;
	water = mix(water, highlight_color.rgb, wave_line * 0.62 + sparkle_mask * sparkle_strength);
	float foam_noise = fbm(world * 0.0048 * wave_scale_safe + vec2(-time * 0.045, time * 0.026));
	float foam_authored = texture(foam_texture, fract(texture_rotation * world / 1024.0 + vec2(-time * 0.0014, time * 0.0007))).r;
	float foam = smoothstep(foam_coverage, 0.99, foam_noise + authored_wave * 0.2 + foam_authored * 0.58 + wave_line * 0.18) * foam_strength;
	water = mix(water, highlight_color.rgb, foam * 0.56);

	float cloud_texture_size = 2048.0 / max(0.25, cloud_scale);
	float cloud_authored = texture(weather_cloud_texture, fract(texture_rotation * world / cloud_texture_size + vec2(time * 0.0005, time * 0.0003))).r;
	float cloud_field = 0.5;
	cloud_field += sin((world.x * 0.00115 + world.y * 0.00048) * cloud_scale + time * 0.045) * 0.22;
	cloud_field += sin((world.x * -0.00062 + world.y * 0.00134) * cloud_scale - time * 0.031) * 0.18;
	cloud_field += (broad_b - 0.5) * 0.12 + (cloud_authored - 0.5) * 0.58;
	float cloud = smoothstep(cloud_cutoff, cloud_cutoff + cloud_softness, cloud_field) * cloud_opacity;
	vec3 cloud_tint = mix(water * 0.68, cloud_color.rgb, 0.12);
	water = mix(water, cloud_tint, cloud);
	float storm_authored = texture(storm_shadow_texture, fract(texture_rotation * world / 1536.0 + vec2(-time * 0.0007, time * 0.0005))).r;
	float squall = smoothstep(0.46, 0.84, fbm(world * 0.00135 * max(0.55, cloud_scale) + vec2(-time * 0.035, time * 0.019) + 93.0) * 0.45 + storm_authored * 0.55) * squall_strength;
	water = mix(water, cloud_color.rgb * 0.82, squall * 0.36);

	float warm_pattern = smoothstep(0.69, 0.94, broad_b + wave_line * 0.25);
	water = mix(water, warm_reflection_color.rgb, warm_pattern * warm_reflection_strength);
	float rain_breakup = smoothstep(0.28, 0.86, fbm(world * 0.006 + vec2(time * 0.42, -time * 0.31)));
	vec2 rain_axis = vec2(cos(rain_angle), sin(rain_angle));
	vec2 rain_cross = vec2(-rain_axis.y, rain_axis.x);
	float rain_phase_a = dot(world, rain_cross) * 0.105 * max(0.2, rain_density) + dot(world, rain_axis) * 0.018 - time * 8.6;
	float rain_phase_b = dot(world, rain_cross) * 0.153 * max(0.2, rain_density) + dot(world, rain_axis) * 0.024 - time * 7.2 + 1.7;
	float rain_line_a = smoothstep(0.986 - rain_density * 0.004, 1.0, sin(rain_phase_a) * 0.5 + 0.5);
	float rain_line_b = smoothstep(0.991 - rain_density * 0.003, 1.0, sin(rain_phase_b) * 0.5 + 0.5);
	float rain_line_authored_a = texture(rain_line_texture, fract(texture_uv + rain_axis * time * 0.006)).r;
	float rain_line_authored_b = texture(rain_line_texture, fract(texture_rotation * world / 1320.0 + rain_axis * time * 0.004 + 0.37)).r;
	float rain_lines = ((rain_line_a * 0.22 + rain_line_b * 0.18) + rain_line_authored_a * 0.36 + rain_line_authored_b * 0.24) * rain_breakup * rain_strength;
	float rain_ripple_authored = texture(rain_ripple_texture, fract(world / 1024.0 + vec2(time * 0.0004, -time * 0.0003))).r;
	float rain_ripple = (smoothstep(0.965, 1.0, fbm(world * 0.021 + vec2(time * 1.4, time * 0.9))) * 0.35 + rain_ripple_authored * 0.65) * rain_strength;
	vec3 rain_tint = mix(water, highlight_color.rgb, 0.36);
	water = mix(water, rain_tint, rain_lines * rain_line_strength * 0.36 + rain_ripple * rain_ripple_strength * 0.14);
	float lightning_pulse = pow(smoothstep(0.935, 1.0, sin(time * 0.73) * 0.5 + 0.5), 8.0);
	lightning_pulse = max(lightning_pulse, squall * 0.08);
	lightning_pulse *= lightning_strength;
	lightning_pulse *= smoothstep(0.38, 0.86, cloud_field);
	float lightning_authored = texture(lightning_mask_texture, fract(texture_rotation * world / 1536.0 + vec2(0.19, 0.41))).r;
	water = mix(water, highlight_color.rgb, lightning_pulse * (0.18 + lightning_authored * 0.32));
	float map_edge_distance = min(min(world.x, map_size.x - world.x), min(world.y, map_size.y - world.y));
	float map_edge = 1.0 - smoothstep(0.0, 150.0, map_edge_distance);
	water = mix(water, deep_color.rgb * 0.58, map_edge * 0.72);

	vec2 centered = SCREEN_UV * 2.0 - 1.0;
	float vignette = smoothstep(0.28, 1.25, length(centered * vec2(0.78, 1.0)));
	vec3 mist_tint = mix(surface_color.rgb, highlight_color.rgb, 0.28);
	water = mix(water, mist_tint, mist_strength * (0.22 + vignette * 0.16 + rain_strength * 0.08));
	water *= 1.025 - vignette * 0.115;
	COLOR = vec4(water, 1.0);
}
