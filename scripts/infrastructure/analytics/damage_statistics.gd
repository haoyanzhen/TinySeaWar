extends RefCounted

const DIRECT_CATEGORIES := [
	"main_gun",
	"secondary_gun",
	"torpedo",
	"aviation",
	"anti_air",
	"anti_submarine",
	"skill",
	"buff",
	"mine",
	"other",
]
const CONTRIBUTION_CATEGORIES := ["buff"]


static func empty_unit_statistics(metadata: Dictionary = {}) -> Dictionary:
	return {
		"definition_id": str(metadata.get("definition_id", "")),
		"display_name": str(metadata.get("display_name", "")),
		"faction_id": str(metadata.get("faction_id", "")),
		"damage_dealt": 0.0,
		"overkill_damage": 0.0,
		"damage_taken": 0.0,
		"shots": 0,
		"hits": 0,
		"damage_by_category": _zero_map(DIRECT_CATEGORIES),
		"overkill_by_category": _zero_map(DIRECT_CATEGORIES),
		"damage_by_weapon": {},
		"contribution_damage": 0.0,
		"contribution_damage_by_category": _zero_map(CONTRIBUTION_CATEGORIES),
		"contribution_damage_by_skill": {},
	}


static func empty_non_ship_statistics(metadata: Dictionary = {}) -> Dictionary:
	var statistics := empty_unit_statistics(metadata)
	statistics["source_kind"] = str(metadata.get("source_kind", "NonShip"))
	statistics["source_id"] = str(metadata.get("source_id", ""))
	return statistics


static func ensure_unit(units: Dictionary, unit_id: String, metadata: Dictionary = {}) -> Dictionary:
	if unit_id.is_empty():
		return {}
	if not units.has(unit_id):
		units[unit_id] = empty_unit_statistics(metadata)
	else:
		for key in ["definition_id", "display_name", "faction_id"]:
			if str(units[unit_id].get(key, "")).is_empty() and metadata.has(key):
				units[unit_id][key] = str(metadata[key])
	return units[unit_id]


static func ensure_non_ship(non_ship_damage: Dictionary, source_id: String, metadata: Dictionary = {}) -> Dictionary:
	if source_id.is_empty():
		return {}
	if not non_ship_damage.has(source_id):
		non_ship_damage[source_id] = empty_non_ship_statistics(metadata.merged({"source_id": source_id}, true))
	else:
		for key in ["definition_id", "display_name", "faction_id", "source_kind"]:
			if str(non_ship_damage[source_id].get(key, "")).is_empty() and metadata.has(key):
				non_ship_damage[source_id][key] = str(metadata[key])
	return non_ship_damage[source_id]


static func enrich_result(result: Dictionary, weapon: Dictionary = {}, source_ship: Dictionary = {}, context: Dictionary = {}) -> Dictionary:
	var enriched := result.duplicate(true)
	enriched["damage_category"] = category_for(enriched, weapon, source_ship, context)
	if not weapon.is_empty():
		enriched["source_weapon_group_id"] = str(weapon.get("weapon_group_id", ""))
		enriched["source_weapon_control_mode"] = str(weapon.get("control_mode", ""))
	if context.has("source_skill_id"):
		enriched["source_skill_id"] = str(context["source_skill_id"])
	if context.has("source_buff_id"):
		enriched["source_buff_id"] = str(context["source_buff_id"])
	return enriched


static func category_for(result: Dictionary, weapon: Dictionary = {}, source_ship: Dictionary = {}, context: Dictionary = {}) -> String:
	var explicit_category := str(context.get("damage_category", result.get("damage_category", ""))).to_snake_case()
	if explicit_category in DIRECT_CATEGORIES:
		return explicit_category
	var weapon_category := str(weapon.get("damage_category", "")).to_snake_case()
	if weapon_category in DIRECT_CATEGORIES:
		return weapon_category
	if not str(context.get("source_skill_id", result.get("source_skill_id", ""))).is_empty():
		return "skill"
	if not str(context.get("source_buff_id", result.get("source_buff_id", ""))).is_empty():
		return "buff"
	var mount_type := str(weapon.get("mount_type", result.get("damage_type", "")))
	match mount_type:
		"Gun":
			var weapon_group_id := str(weapon.get("weapon_group_id", result.get("source_weapon_group_id", "")))
			var battery_role := str(weapon.get("battery_role", weapon.get("weapon_role", ""))).to_lower()
			var display_name := str(weapon.get("display_name", ""))
			if battery_role == "secondary" or "secondary" in weapon_group_id.to_lower() or "副炮" in display_name:
				return "secondary_gun"
			return "main_gun"
		"Torpedo": return "torpedo"
		"Aviation": return "aviation"
		"AntiAir": return "anti_air"
		"AntiSubmarine": return "anti_submarine"
		"Skill": return "skill"
		"Buff": return "buff"
		"Mine": return "mine"
		_: return "other"


static func record_result(units: Dictionary, non_ship_damage: Dictionary, result: Dictionary) -> Dictionary:
	var source_descriptor := _source_descriptor(result)
	var target_descriptor := _target_descriptor(result)
	var source_id := str(source_descriptor.get("entity_id", ""))
	var target_id := str(target_descriptor.get("entity_id", ""))
	var source_stats := ensure_unit(units, source_id) if source_descriptor.get("is_ship", false) else ensure_non_ship(non_ship_damage, source_id, source_descriptor)
	var target_stats := ensure_unit(units, target_id) if target_descriptor.get("is_ship", false) else ensure_non_ship(non_ship_damage, target_id, target_descriptor)
	var category := category_for(result)
	var damage := maxf(0.0, float(result.get("final_damage", 0.0)))
	var hp_before := maxf(0.0, float(result.get("target_hp_before", damage)))
	var effective_damage := minf(damage, hp_before) if not target_id.is_empty() else 0.0
	var overkill_damage := maxf(0.0, damage - effective_damage)
	if not source_stats.is_empty():
		source_stats["shots"] = int(source_stats.get("shots", 0)) + 1
		if bool(result.get("hit", false)):
			source_stats["hits"] = int(source_stats.get("hits", 0)) + 1
		source_stats["damage_dealt"] = float(source_stats.get("damage_dealt", 0.0)) + effective_damage
		source_stats["overkill_damage"] = float(source_stats.get("overkill_damage", 0.0)) + overkill_damage
		_add(source_stats["damage_by_category"], category, effective_damage)
		_add(source_stats["overkill_by_category"], category, overkill_damage)
		var weapon_id := str(result.get("source_weapon_id", ""))
		if not weapon_id.is_empty():
			_add(source_stats["damage_by_weapon"], weapon_id, effective_damage)
	if not target_stats.is_empty():
		target_stats["damage_taken"] = float(target_stats.get("damage_taken", 0.0)) + effective_damage
	_record_buff_contribution(units, result, source_id, effective_damage, damage)
	return {
		"category": category,
		"effective_damage": effective_damage,
		"overkill_damage": overkill_damage,
	}


static func non_ship_statistics(non_ship_damage: Dictionary, source_id: String) -> Dictionary:
	if not non_ship_damage.has(source_id):
		return empty_non_ship_statistics()
	return non_ship_damage[source_id].duplicate(true)


static func all_non_ship_statistics(non_ship_damage: Dictionary) -> Dictionary:
	return non_ship_damage.duplicate(true)


static func unit_statistics(units: Dictionary, unit_id: String) -> Dictionary:
	if not units.has(unit_id):
		return empty_unit_statistics()
	return units[unit_id].duplicate(true)


static func all_unit_statistics(units: Dictionary) -> Dictionary:
	return units.duplicate(true)


static func damage_for_category(units: Dictionary, unit_id: String, category: String, include_contribution: bool = false) -> float:
	var statistics := unit_statistics(units, unit_id)
	var total := float(statistics.get("damage_by_category", {}).get(category, 0.0))
	if include_contribution:
		total += float(statistics.get("contribution_damage_by_category", {}).get(category, 0.0))
	return total


static func _source_descriptor(result: Dictionary) -> Dictionary:
	var facility_id := str(result.get("source_facility_id", ""))
	if not facility_id.is_empty():
		return _non_ship_descriptor(facility_id, "Facility", result, "source")
	var hazard_id := str(result.get("source_hazard_id", ""))
	if not hazard_id.is_empty():
		return _non_ship_descriptor(hazard_id, "Hazard", result, "source")
	var unit_id := str(result.get("source_unit_id", ""))
	if unit_id.begins_with("unit."):
		return {"entity_id": unit_id, "is_ship": true}
	if unit_id.is_empty():
		return {}
	return _non_ship_descriptor(unit_id, "NonShip", result, "source")


static func _target_descriptor(result: Dictionary) -> Dictionary:
	var facility_id := str(result.get("target_facility_id", ""))
	if not facility_id.is_empty():
		return _non_ship_descriptor(facility_id, "Facility", result, "target")
	var unit_id := str(result.get("target_unit_id", ""))
	if unit_id.begins_with("unit."):
		return {"entity_id": unit_id, "is_ship": true}
	return {}


static func _non_ship_descriptor(entity_id: String, source_kind: String, result: Dictionary, role: String) -> Dictionary:
	return {
		"entity_id": entity_id,
		"source_id": entity_id,
		"source_kind": source_kind,
		"definition_id": str(result.get("%s_definition_id" % role, "")),
		"display_name": str(result.get("%s_display_name" % role, entity_id)),
		"faction_id": str(result.get("%s_faction_id" % role, "")),
		"is_ship": false,
	}


static func _record_buff_contribution(units: Dictionary, result: Dictionary, fallback_source_id: String, effective_damage: float, final_damage: float) -> void:
	if effective_damage <= 0.0 or final_damage <= 0.0:
		return
	var raw_bonus := maxf(0.0, float(result.get("buff_bonus_damage", 0.0)))
	if raw_bonus <= 0.0:
		return
	var effective_bonus := raw_bonus * effective_damage / final_damage
	var details: Array = result.get("buff_contribution_details", [])
	if not details.is_empty():
		var detail_weight := 0.0
		for detail in details:
			detail_weight += maxf(0.0, float(detail.get("weight", 0.0)))
		if detail_weight > 0.0:
			for detail in details:
				var share := effective_bonus * maxf(0.0, float(detail.get("weight", 0.0))) / detail_weight
				var contributor := ensure_unit(units, str(detail.get("source_unit_id", "")))
				if contributor.is_empty():
					continue
				contributor["contribution_damage"] = float(contributor.get("contribution_damage", 0.0)) + share
				_add(contributor["contribution_damage_by_category"], "buff", share)
				_add(contributor["contribution_damage_by_skill"], str(detail.get("source_skill_id", "")), share)
			return
	var weights: Dictionary = result.get("buff_contribution_weights", {}).duplicate(true)
	if weights.is_empty() and not fallback_source_id.is_empty():
		weights[fallback_source_id] = 1.0
	var total_weight := 0.0
	for value in weights.values():
		total_weight += maxf(0.0, float(value))
	if total_weight <= 0.0:
		return
	var skill_ids: Array = result.get("buff_source_skill_ids", [])
	for contributor_id in weights:
		var share := effective_bonus * maxf(0.0, float(weights[contributor_id])) / total_weight
		var contributor := ensure_unit(units, str(contributor_id))
		contributor["contribution_damage"] = float(contributor.get("contribution_damage", 0.0)) + share
		_add(contributor["contribution_damage_by_category"], "buff", share)
		if not skill_ids.is_empty():
			var skill_share := share / float(skill_ids.size())
			for skill_id in skill_ids:
				_add(contributor["contribution_damage_by_skill"], str(skill_id), skill_share)


static func _zero_map(keys: Array) -> Dictionary:
	var result := {}
	for key in keys:
		result[key] = 0.0
	return result


static func _add(values: Dictionary, key: String, amount: float) -> void:
	if key.is_empty():
		return
	values[key] = float(values.get(key, 0.0)) + amount
