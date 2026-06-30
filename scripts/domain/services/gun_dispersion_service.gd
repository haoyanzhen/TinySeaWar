extends RefCounted


static func sigmas(distance: float, spread_degrees: float, sigma_scale: float, longitudinal_sigma_ratio: float) -> Vector2:
	var lateral_sigma := maxf(0.0, distance) * deg_to_rad(maxf(0.0, spread_degrees)) * maxf(0.0, sigma_scale)
	return Vector2(lateral_sigma, lateral_sigma * clampf(longitudinal_sigma_ratio, 0.0, 1.0))


static func sample(origin: Vector2, aim_position: Vector2, spread_degrees: float, sigma_scale: float, longitudinal_sigma_ratio: float, random_source) -> Dictionary:
	var firing_vector := aim_position - origin
	var firing_direction := firing_vector.normalized() if not firing_vector.is_zero_approx() else Vector2.RIGHT
	var cross_direction := firing_direction.rotated(PI * 0.5)
	var dispersion_sigmas := sigmas(firing_vector.length(), spread_degrees, sigma_scale, longitudinal_sigma_ratio)
	var lateral_error: float = random_source.randfn(0.0, dispersion_sigmas.x)
	var longitudinal_error: float = random_source.randfn(0.0, dispersion_sigmas.y)
	return {
		"position": aim_position + cross_direction * lateral_error + firing_direction * longitudinal_error,
		"lateral_sigma": dispersion_sigmas.x,
		"longitudinal_sigma": dispersion_sigmas.y,
		"lateral_error": lateral_error,
		"longitudinal_error": longitudinal_error,
	}
