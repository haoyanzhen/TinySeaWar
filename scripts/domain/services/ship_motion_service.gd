extends RefCounted


static func simulate_control_sequence(initial_state: Dictionary, controls: Array, fixed_tick_delta: float, horizon: float, context_sampler: Callable = Callable()) -> Array:
	var samples: Array = []
	if fixed_tick_delta <= 0.0 or horizon < 0.0:
		return samples
	var simulated := initial_state.duplicate(true)
	samples.append(_sample(simulated, 0.0))
	if controls.is_empty() or is_zero_approx(horizon):
		return samples
	var control_index := 0
	var control_elapsed := 0.0
	var elapsed := 0.0
	while elapsed < horizon - 0.000001:
		var control: Dictionary = controls[mini(control_index, controls.size() - 1)]
		var control_duration := maxf(fixed_tick_delta, float(control.get("duration", horizon)))
		var remaining_control := control_duration - control_elapsed if control_index < controls.size() - 1 else horizon - elapsed
		var step_delta := minf(fixed_tick_delta, minf(horizon - elapsed, remaining_control))
		if step_delta <= 0.000001:
			control_index = mini(control_index + 1, controls.size() - 1)
			control_elapsed = 0.0
			continue
		if context_sampler.is_valid():
			var context: Dictionary = context_sampler.call(simulated.get("position", Vector2.ZERO))
			simulated["current_vector"] = context.get("current_vector", simulated.get("current_vector", Vector2.ZERO))
			if simulated.has("base_maximum_speed"):
				simulated["maximum_speed"] = float(simulated.get("base_maximum_speed", 0.0)) * float(context.get("movement_speed_multiplier", 1.0))
		simulated = step(simulated, control, step_delta)
		elapsed += step_delta
		control_elapsed += step_delta
		samples.append(_sample(simulated, elapsed))
		if control_index < controls.size() - 1 and control_elapsed >= control_duration - 0.000001:
			control_index += 1
			control_elapsed = 0.0
	return samples


static func _sample(state: Dictionary, elapsed: float) -> Dictionary:
	return {
		"tick_offset":elapsed,
		"position":state.get("position", Vector2.ZERO),
		"heading":float(state.get("heading", 0.0)),
		"speed":float(state.get("speed", 0.0)),
		"current_vector":state.get("current_vector", Vector2.ZERO),
	}


static func step(state: Dictionary, control: Dictionary, delta: float) -> Dictionary:
	var result := state.duplicate(true)
	var maximum_speed := maxf(0.0, float(state.get("maximum_speed", 0.0)))
	var reverse_speed := maxf(0.0, float(state.get("reverse_speed", maximum_speed * 0.25)))
	var acceleration := maxf(0.0, float(state.get("acceleration", maximum_speed)))
	var braking := maxf(acceleration, float(state.get("braking", maximum_speed * 2.0)))
	var turn_rate_limit := maxf(0.0, float(state.get("turn_rate_limit", 0.0)))
	var thrust_ratio := clampf(float(control.get("thrust_ratio", 0.0)), -1.0, 1.0)
	var turn_ratio := clampf(float(control.get("turn_ratio", 0.0)), -1.0, 1.0)
	var speed := float(state.get("speed", 0.0))
	var desired_speed := maximum_speed * thrust_ratio if thrust_ratio >= 0.0 else reverse_speed * thrust_ratio
	var crossing_zero := (speed > 0.0 and desired_speed < 0.0) or (speed < 0.0 and desired_speed > 0.0)
	if crossing_zero:
		speed = move_toward(speed, 0.0, braking * delta)
	else:
		var rate := acceleration if absf(desired_speed) > absf(speed) else braking
		speed = move_toward(speed, desired_speed, rate * delta)
	var heading := float(state.get("heading", 0.0)) + turn_rate_limit * turn_ratio * delta
	var current_vector: Vector2 = state.get("current_vector", Vector2.ZERO)
	var position: Vector2 = state.get("position", Vector2.ZERO)
	position += Vector2.RIGHT.rotated(heading) * speed * delta + current_vector * delta
	result["position"] = position
	result["heading"] = heading
	result["speed"] = speed
	return result


static func state_for_unit(unit: Dictionary, context: Dictionary, active_effects: Array, modifier_service) -> Dictionary:
	var base_maximum_speed: float = modifier_service.calculate(float(unit.get("stats", {}).get("speed", 0.0)), active_effects, "Speed")
	var maximum_speed: float = base_maximum_speed * float(context.get("movement_speed_multiplier", 1.0))
	var turn_rate: float = deg_to_rad(modifier_service.calculate(float(unit.get("stats", {}).get("turn_speed", 0.0)), active_effects, "TurnSpeed"))
	return {
		"position": unit.get("position", Vector2.ZERO),
		"heading": float(unit.get("heading", 0.0)),
		"speed": float(unit.get("current_speed", 0.0)),
		"base_maximum_speed": base_maximum_speed,
		"maximum_speed": maximum_speed,
		"reverse_speed": maximum_speed * float(unit.get("stats", {}).get("reverse_speed_ratio", 0.25)),
		"acceleration": maximum_speed * float(unit.get("stats", {}).get("acceleration_ratio", 1.0)),
		"braking": maximum_speed * float(unit.get("stats", {}).get("braking_ratio", 2.0)),
		"turn_rate_limit": turn_rate,
		"current_vector": context.get("current_vector", Vector2.ZERO),
	}
