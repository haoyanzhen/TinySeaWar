extends RefCounted

const ModifierService = preload("res://scripts/domain/services/modifier_service.gd")


static func resolve(attack: Dictionary, source: Dictionary, target: Dictionary, weapon: Dictionary, formula: Dictionary, random_source, forced_hit: bool = false) -> Dictionary:
	var category := str(weapon.get("mount_type", "Gun"))
	var distance := (source["position"] as Vector2).distance_to(target["position"] as Vector2)
	var hit_rate := float(formula.get("base_hit_rate", 1.0))
	hit_rate += float(weapon.get("accuracy_modifier", 0.0))
	hit_rate += float(attack.get("accuracy_modifier", 0.0))
	hit_rate += ModifierService.sum_modifier(source["status_effects"], "AccuracyPoint", category)
	hit_rate -= ModifierService.calculate(float(target["stats"].get("evasion", 0.0)), target["status_effects"], "Evasion") * float(formula.get("evasion_coefficient", 0.0))
	hit_rate -= distance / maxf(1.0, float(weapon.get("range", 1.0))) * float(formula.get("distance_penalty_coefficient", 0.0))
	hit_rate = clampf(hit_rate, float(formula.get("hit_rate_min", 0.0)), float(formula.get("hit_rate_max", 1.0)))
	var hit: bool = forced_hit or random_source.randf() <= hit_rate
	var hp_before := float(target["current_hp"])
	var result := {
		"attack_id": attack.get("attack_id", ""),
		"source_unit_id": source.get("entity_id", ""),
		"target_unit_id": target.get("entity_id", ""),
		"damage_type": category,
		"hit": hit,
		"hit_rate": hit_rate,
		"hit_reason": "COLLISION" if forced_hit else ("ROLL_SUCCEEDED" if hit else "ROLL_FAILED"),
		"raw_damage": 0.0,
		"armor_modifier": 0.0,
		"armor_reduction": 0.0,
		"final_damage": 0.0,
		"target_hp_before": hp_before,
		"target_hp_after": hp_before,
		"caused_sinking": false,
	}
	if not hit:
		return result
	var power_stat := _power_stat_for(category)
	var power := float(source["stats"].get(power_stat, 0.0))
	var raw_damage := float(formula.get("base_damage", 0.0)) + power * float(formula.get("power_coefficient", 0.0))
	var thickness := str(target["stats"].get("armor_thickness", "Unarmored"))
	var armor_modifier := float(weapon.get("armor_damage_modifiers", {}).get(thickness, 0.0))
	armor_modifier *= maxf(0.0, 1.0 + ModifierService.sum_modifier(source["status_effects"], "ArmorDamageModifier", category))
	var armor := ModifierService.calculate(float(target["stats"].get("armor", 0.0)), target["status_effects"], "Armor")
	var armor_reduction := armor * float(formula.get("armor_coefficient", 0.0))
	var penetrated_damage := maxf(0.0, raw_damage * armor_modifier - armor_reduction)
	var type_damage := 1.0 + ModifierService.sum_modifier(source["status_effects"], "Damage", category)
	var all_damage := 1.0 + ModifierService.sum_modifier(source["status_effects"], "AllDamage", "All")
	var reduction := clampf(ModifierService.sum_modifier(target["status_effects"], "DamageReduction", category), 0.0, 0.70)
	var final_damage := maxf(0.0, penetrated_damage * type_damage * all_damage * maxf(0.30, 1.0 - reduction))
	result["raw_damage"] = raw_damage
	result["armor_modifier"] = armor_modifier
	result["armor_reduction"] = armor_reduction
	result["final_damage"] = final_damage
	result["target_hp_after"] = maxf(0.0, hp_before - final_damage)
	result["caused_sinking"] = hp_before > 0.0 and float(result["target_hp_after"]) <= 0.0
	return result


static func _power_stat_for(category: String) -> String:
	match category:
		"Torpedo": return "torpedo_power"
		"AntiAir": return "anti_air_power"
		"Aviation": return "aviation_power"
		_: return "gunnery_power"
