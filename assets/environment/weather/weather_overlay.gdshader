shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform vec2 map_size = vec2(4096.0, 2304.0);
uniform float animation_time = 0.0;
uniform float animation_speed = 1.0;
uniform sampler2D weather_cloud_texture : filter_linear;
uniform sampler2D foam_texture : filter_linear;
uniform sampler2D rain_line_texture : filter_linear;
uniform sampler2D rain_ripple_texture : filter_linear;
uniform sampler2D storm_shadow_texture : filter_linear;
uniform sampler2D lightning_mask_texture : filter_linear;
uniform sampler2D snow_flake_texture : filter_linear;
uniform sampler2D snow_haze_texture : filter_linear;
uniform vec4 highlight_color : source_color = vec4(0.72, 0.89, 0.90, 1.0);
uniform vec4 cloud_color : source_color = vec4(0.05, 0.17, 0.25, 1.0);
uniform float cloud_opacity : hint_range(0.0, 1.0) = 0.0;
uniform float foam_strength : hint_range(0.0, 1.0) = 0.0;
uniform float rain_strength : hint_range(0.0, 1.0) = 0.0;
uniform float mist_strength : hint_range(0.0, 1.0) = 0.0;
uniform float lightning_strength : hint_range(0.0, 1.0) = 0.0;
uniform float cloud_scale : hint_range(0.25, 2.0) = 1.0;
uniform float rain_angle : hint_range(-3.14159, 3.14159) = -0.55;
uniform float rain_density : hint_range(0.0, 2.0) = 1.0;
uniform float rain_line_strength : hint_range(0.0, 2.0) = 1.0;
uniform float rain_ripple_strength : hint_range(0.0, 2.0) = 1.0;
uniform float squall_strength : hint_range(0.0, 1.0) = 0.0;
uniform float snow_strength : hint_range(0.0, 1.0) = 0.0;
uniform float snow_haze_strength : hint_range(0.0, 1.0) = 0.0;

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
	mat2 texture_rotation = mat2(vec2(0.819, -0.574), vec2(0.574, 0.819));
	float cloud_texture_size = 2048.0 / max(0.25, cloud_scale);
	float cloud_mask = texture(weather_cloud_texture, fract(texture_rotation * world / cloud_texture_size + vec2(time * 0.0005, time * 0.0003))).r;
	float storm_mask = texture(storm_shadow_texture, fract(texture_rotation * world / 1536.0 + vec2(-time * 0.0007, time * 0.0005))).r;
	float cloud_alpha = cloud_mask * cloud_opacity * 0.22 + storm_mask * squall_strength * 0.20;
	vec3 color = cloud_color.rgb;
	float alpha = cloud_alpha;

	vec2 rain_axis = vec2(cos(rain_angle), sin(rain_angle));
	vec2 rain_uv = fract(world / 1024.0 + rain_axis * time * 0.006);
	float rain_mask = texture(rain_line_texture, rain_uv).r;
	float rain_breakup = smoothstep(0.20, 0.86, fbm(world * 0.005 + vec2(time * 0.32, -time * 0.21)));
	float rain_alpha = rain_mask * rain_strength * rain_line_strength * rain_breakup * (0.08 + rain_density * 0.05);
	color = mix(color, highlight_color.rgb, rain_alpha);
	alpha += rain_alpha;

	float ripple_mask = texture(rain_ripple_texture, fract(world / 1024.0 + vec2(time * 0.0004, -time * 0.0003))).r;
	float ripple_alpha = ripple_mask * rain_strength * rain_ripple_strength * 0.035;
	color = mix(color, highlight_color.rgb, ripple_alpha);
	alpha += ripple_alpha;

	float foam_mask = texture(foam_texture, fract(texture_rotation * world / 1024.0 + vec2(-time * 0.0014, time * 0.0007))).r;
	float foam_alpha = foam_mask * foam_strength * 0.055;
	color = mix(color, highlight_color.rgb, foam_alpha);
	alpha += foam_alpha;

	float snow_mask = texture(snow_flake_texture, fract(world / 1024.0 + vec2(-time * 0.0012, time * 0.0024))).r;
	float snow_alpha = smoothstep(0.66, 0.98, snow_mask) * snow_strength * 0.16;
	color = mix(color, vec3(0.88, 0.96, 1.0), snow_alpha);
	alpha += snow_alpha;

	float snow_haze_mask = texture(snow_haze_texture, fract(texture_rotation * world / 1536.0 + vec2(time * 0.0007, time * 0.0002))).r;
	float snow_haze_alpha = snow_haze_mask * snow_haze_strength * 0.14;
	color = mix(color, vec3(0.72, 0.86, 0.93), snow_haze_alpha);
	alpha += snow_haze_alpha;

	float lightning_pulse = pow(smoothstep(0.935, 1.0, sin(time * 0.73) * 0.5 + 0.5), 8.0) * lightning_strength;
	float lightning_mask = texture(lightning_mask_texture, fract(texture_rotation * world / 1536.0 + vec2(0.19, 0.41))).r;
	float lightning_alpha = lightning_pulse * (0.08 + lightning_mask * 0.18);
	color = mix(color, highlight_color.rgb, lightning_alpha);
	alpha += lightning_alpha;

	float screen_mist = mist_strength * (0.04 + rain_strength * 0.035 + snow_haze_strength * 0.04);
	color = mix(color, highlight_color.rgb, screen_mist);
	alpha += screen_mist;

	float map_edge_distance = min(min(world.x, map_size.x - world.x), min(world.y, map_size.y - world.y));
	float map_edge = 1.0 - smoothstep(0.0, 120.0, map_edge_distance);
	alpha *= 1.0 - map_edge * 0.35;
	COLOR = vec4(color, clamp(alpha, 0.0, 0.34));
}
