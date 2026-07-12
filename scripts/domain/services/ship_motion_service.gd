extends RefCounted


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
	var maximum_speed: float = modifier_service.calculate(float(unit.get("stats", {}).get("speed", 0.0)), active_effects, "Speed") * float(context.get("movement_speed_multiplier", 1.0))
	var turn_rate: float = deg_to_rad(modifier_service.calculate(float(unit.get("stats", {}).get("turn_speed", 0.0)), active_effects, "TurnSpeed"))
	return {
		"position": unit.get("position", Vector2.ZERO),
		"heading": float(unit.get("heading", 0.0)),
		"speed": float(unit.get("current_speed", 0.0)),
		"maximum_speed": maximum_speed,
		"reverse_speed": maximum_speed * float(unit.get("stats", {}).get("reverse_speed_ratio", 0.25)),
		"acceleration": maximum_speed * float(unit.get("stats", {}).get("acceleration_ratio", 1.0)),
		"braking": maximum_speed * float(unit.get("stats", {}).get("braking_ratio", 2.0)),
		"turn_rate_limit": turn_rate,
		"current_vector": context.get("current_vector", Vector2.ZERO),
	}
