extends RefCounted


static func calculate(base_value: float, status_effects: Array, stat: String, category: String = "All") -> float:
	var flat_add := 0.0
	var percent_add := 0.0
	var state_multiply := 1.0
	var independent_multiply := 1.0
	var limit_min := -INF
	var limit_max := INF
	for effect in status_effects:
		if effect.get("stat", "") != stat or not _matches_category(effect.get("category", "All"), category):
			continue
		match effect.get("operation", ""):
			"FlatAdd":
				flat_add += float(effect.get("value", 0.0))
			"PercentAdd":
				percent_add += float(effect.get("value", 0.0))
			"StateMultiply":
				state_multiply *= float(effect.get("value", 1.0))
			"IndependentMultiply":
				independent_multiply *= float(effect.get("value", 1.0))
		if effect.has("limit_min"):
			limit_min = maxf(limit_min, float(effect["limit_min"]))
		if effect.has("limit_max"):
			limit_max = minf(limit_max, float(effect["limit_max"]))
	return clampf((base_value + flat_add) * (1.0 + percent_add) * state_multiply * independent_multiply, limit_min, limit_max)


static func reload_time(base_reload: float, status_effects: Array, category: String) -> float:
	var fixed_time := calculate(base_reload, status_effects, "ReloadTime", category) - base_reload
	var speed_bonus := calculate(1.0, status_effects, "ReloadSpeed", category) - 1.0
	var speed_factor := maxf(0.25, 1.0 + speed_bonus)
	return maxf(maxf(base_reload * 0.35, 0.2), (base_reload + fixed_time) / speed_factor)


static func sum_modifier(status_effects: Array, stat: String, category: String = "All") -> float:
	return calculate(0.0, status_effects, stat, category)


static func _matches_category(effect_category: String, requested_category: String) -> bool:
	return effect_category == "All" or requested_category == "All" or effect_category == requested_category
