extends RefCounted

const ModifierService = preload("res://scripts/domain/services/modifier_service.gd")


static func resolve(attack: Dictionary, source: Dictionary, target: Dictionary, weapon: Dictionary, formula: Dictionary, random_source, forced_hit: bool = false) -> Dictionary:
	var estimate := estimate_attack(attack, source, target, weapon, formula)
	var category := str(estimate["damage_type"])
	var hit_rate := float(estimate["hit_rate"])
	var hit: bool = forced_hit or random_source.randf() <= hit_rate
	var hp_before := float(target["current_hp"])
	var result := {
		"attack_id": attack.get("attack_id", ""),
		"source_unit_id": source.get("entity_id", ""),
		"source_weapon_id": weapon.get("id", attack.get("source_weapon_id", "")),
		"target_unit_id": target.get("entity_id", ""),
		"damage_type": category,
		"hit": hit,
		"hit_rate": hit_rate,
		"hit_reason": "COLLISION" if forced_hit else ("ROLL_SUCCEEDED" if hit else "ROLL_FAILED"),
		"raw_damage": 0.0,
		"armor_modifier": 0.0,
		"armor_reduction": 0.0,
		"base_final_damage": 0.0,
		"buff_bonus_damage": 0.0,
		"buff_contribution_weights": {},
		"buff_contribution_details": [],
		"buff_source_skill_ids": [],
		"final_damage": 0.0,
		"target_hp_before": hp_before,
		"target_hp_after": hp_before,
		"caused_sinking": false,
	}
	if not hit:
		return result
	var raw_damage := float(estimate["raw_damage"])
	var armor_modifier := float(estimate["armor_modifier"])
	var armor_reduction := float(estimate["armor_reduction"])
	var base_final_damage := float(estimate["base_final_damage"])
	var final_damage := float(estimate["damage_on_hit"])
	var buff_attribution := _buff_attribution(source["status_effects"], category)
	result["raw_damage"] = raw_damage
	result["armor_modifier"] = armor_modifier
	result["armor_reduction"] = armor_reduction
	result["base_final_damage"] = base_final_damage
	result["buff_bonus_damage"] = maxf(0.0, final_damage - base_final_damage)
	result["buff_contribution_weights"] = buff_attribution["weights"]
	result["buff_contribution_details"] = buff_attribution["details"]
	result["buff_source_skill_ids"] = buff_attribution["skill_ids"]
	result["final_damage"] = final_damage
	result["target_hp_after"] = maxf(0.0, hp_before - final_damage)
	result["caused_sinking"] = hp_before > 0.0 and float(result["target_hp_after"]) <= 0.0
	return result


static func estimate_attack(attack: Dictionary, source: Dictionary, target: Dictionary, weapon: Dictionary, formula: Dictionary) -> Dictionary:
	var category := str(weapon.get("mount_type", "Gun"))
	var source_effects := _applicable_effects(source.get("status_effects", []), source, target, category)
	var target_effects := _applicable_effects(target.get("status_effects", []), target, source, category)
	var distance := (source.get("position", Vector2.ZERO) as Vector2).distance_to(target.get("position", Vector2.ZERO) as Vector2)
	var hit_rate := float(formula.get("base_hit_rate", 1.0))
	hit_rate += float(weapon.get("accuracy_modifier", 0.0))
	hit_rate += float(attack.get("accuracy_modifier", 0.0))
	hit_rate += ModifierService.sum_modifier(source_effects, "AccuracyPoint", category)
	hit_rate -= ModifierService.calculate(float(target.get("stats", {}).get("evasion", 0.0)), target_effects, "Evasion") * float(formula.get("evasion_coefficient", 0.0))
	hit_rate -= distance / maxf(1.0, float(weapon.get("range", 1.0))) * float(formula.get("distance_penalty_coefficient", 0.0))
	hit_rate = clampf(hit_rate, float(formula.get("hit_rate_min", 0.0)), float(formula.get("hit_rate_max", 1.0)))
	var power_stat := _power_stat_for(category)
	var power := float(source.get("stats", {}).get(power_stat, 0.0))
	var raw_damage := float(formula.get("base_damage", 0.0)) + power * float(formula.get("power_coefficient", 0.0))
	var thickness := str(target.get("stats", {}).get("armor_thickness", "Unarmored"))
	var armor_modifier := float(weapon.get("armor_damage_modifiers", {}).get(thickness, 0.0))
	armor_modifier *= maxf(0.0, 1.0 + ModifierService.sum_modifier(source_effects, "ArmorDamageModifier", category))
	var armor := ModifierService.calculate(float(target.get("stats", {}).get("armor", 0.0)), target_effects, "Armor")
	var armor_reduction := armor * float(formula.get("armor_coefficient", 0.0))
	var penetrated_damage := maxf(0.0, raw_damage * armor_modifier - armor_reduction)
	var type_damage := 1.0 + ModifierService.sum_modifier(source_effects, "Damage", category)
	var all_damage := 1.0 + ModifierService.sum_modifier(source_effects, "AllDamage", "All")
	var reduction := clampf(ModifierService.sum_modifier(target_effects, "DamageReduction", category), 0.0, 0.70)
	var base_final_damage := maxf(0.0, penetrated_damage * maxf(0.30, 1.0 - reduction))
	var damage_on_hit := maxf(0.0, base_final_damage * type_damage * all_damage * float(attack.get("damage_multiplier", 1.0)))
	return {
		"damage_type": category,
		"hit_rate": hit_rate,
		"raw_damage": raw_damage,
		"armor_modifier": armor_modifier,
		"armor_reduction": armor_reduction,
		"base_final_damage": base_final_damage,
		"damage_on_hit": damage_on_hit,
		"expected_damage": damage_on_hit * hit_rate,
	}


static func _applicable_effects(effects: Array, owner: Dictionary, counterpart: Dictionary, category: String) -> Array:
	var result: Array = []
	for effect in effects:
		if bool(effect.get("requires_submerged", false)) and str(owner.get("depth_state", "Surface")) != "Submerged":
			continue
		var bound_target_id := str(effect.get("bound_target_id", ""))
		if not bound_target_id.is_empty() and bound_target_id != str(counterpart.get("entity_id", "")):
			continue
		var armor_classes: Array = effect.get("target_armor_classes", [])
		if not armor_classes.is_empty() and str(counterpart.get("stats", {}).get("armor_thickness", "Unarmored")) not in armor_classes:
			continue
		var required_categories: Array = effect.get("weapon_categories", [])
		if not required_categories.is_empty() and category not in required_categories:
			continue
		result.append(effect)
	return result


static func _power_stat_for(category: String) -> String:
	match category:
		"Torpedo": return "torpedo_power"
		"AntiAir": return "anti_air_power"
		"Aviation": return "aviation_power"
		_: return "gunnery_power"


static func _buff_attribution(status_effects: Array, category: String) -> Dictionary:
	var weights := {}
	var details: Array[Dictionary] = []
	var skill_ids: Array[String] = []
	for effect in status_effects:
		var stat := str(effect.get("stat", ""))
		if stat not in ["Damage", "AllDamage"]:
			continue
		var effect_category := str(effect.get("category", "All"))
		if stat == "Damage" and effect_category not in ["All", category]:
			continue
		var value := float(effect.get("value", 0.0))
		if value <= 0.0:
			continue
		var source_unit_id := str(effect.get("source_unit_id", ""))
		if not source_unit_id.is_empty():
			weights[source_unit_id] = float(weights.get(source_unit_id, 0.0)) + value
		var status_id := str(effect.get("status_id", ""))
		if not source_unit_id.is_empty():
			details.append({"source_unit_id": source_unit_id, "source_skill_id": status_id, "weight": value})
		if not status_id.is_empty() and status_id not in skill_ids:
			skill_ids.append(status_id)
	skill_ids.sort()
	return {"weights": weights, "details": details, "skill_ids": skill_ids}
