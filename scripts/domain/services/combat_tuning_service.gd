extends RefCounted
## Shared battle multipliers act on existing runtime baselines exactly once.
## Ship motion, torpedo water speed and gun firing arcs are separate parameters.

static func multiplier(settings: Dictionary, key: String) -> float:
	return float(settings.get("battle_multipliers", {}).get(key, 1.0))


static func is_shell(weapon: Dictionary) -> bool:
	return str(weapon.get("mount_type", "")) in ["Gun", "AntiAir"]


static func weapon_flight_speed(weapon: Dictionary, settings: Dictionary) -> float:
	var factor := 1.0
	if str(weapon.get("mount_type", "")) == "Aviation":
		factor = multiplier(settings, "aircraft_speed")
	elif is_shell(weapon):
		factor = multiplier(settings, "shell_speed")
	return float(weapon.get("projectile_speed", 1.0)) * factor


static func weapon_spread(weapon: Dictionary, settings: Dictionary) -> float:
	var factor := multiplier(settings, "shell_spread") if is_shell(weapon) else 1.0
	return float(weapon.get("spread", 0.0)) * factor
