extends RefCounted

const DamageStatistics = preload("res://scripts/infrastructure/analytics/damage_statistics.gd")

var summary := {}


func reset(battle_id: String, seed_value: int) -> void:
	summary = {
		"battle_id": battle_id,
		"seed": seed_value,
		"duration": 0.0,
		"first_detection_time": -1.0,
		"first_fire_time": -1.0,
		"first_hit_time": -1.0,
		"first_sinking_time": -1.0,
		"commands": 0,
		"skill_casts": 0,
		"units": {},
		"result": {},
	}


func register_units(units_by_id: Dictionary) -> void:
	for unit_id in units_by_id:
		var unit: Dictionary = units_by_id[unit_id]
		DamageStatistics.ensure_unit(summary["units"], str(unit_id), {
			"definition_id": unit.get("definition_id", ""),
			"display_name": unit.get("display_name", ""),
			"faction_id": unit.get("faction_id", ""),
		})


func consume(events: Array, elapsed_time: float) -> void:
	summary["duration"] = elapsed_time
	for event in events:
		match event.get("event_type", ""):
			"MoveOrderAccepted", "FocusTargetChanged": summary["commands"] += 1
			"ContactAcquired":
				if summary["first_detection_time"] < 0.0: summary["first_detection_time"] = elapsed_time
			"WeaponFired":
				if summary["first_fire_time"] < 0.0: summary["first_fire_time"] = elapsed_time
			"SkillCast": summary["skill_casts"] += 1
			"AttackResolved": _record_damage(event.get("damage_result", {}), elapsed_time)
			"UnitSunk":
				if summary["first_sinking_time"] < 0.0: summary["first_sinking_time"] = elapsed_time
			"BattleFinished": summary["result"] = event.get("result", {}).duplicate(true)


func _record_damage(result: Dictionary, elapsed_time: float) -> void:
	var source_id := str(result.get("source_unit_id", ""))
	if bool(result.get("hit", false)) and not source_id.is_empty():
		if summary["first_hit_time"] < 0.0: summary["first_hit_time"] = elapsed_time
	DamageStatistics.record_result(summary["units"], result)


func unit_damage_statistics(unit_id: String) -> Dictionary:
	return DamageStatistics.unit_statistics(summary.get("units", {}), unit_id)


func all_unit_damage_statistics() -> Dictionary:
	return DamageStatistics.all_unit_statistics(summary.get("units", {}))


func unit_damage_for_category(unit_id: String, category: String, include_contribution: bool = false) -> float:
	return DamageStatistics.damage_for_category(summary.get("units", {}), unit_id, category, include_contribution)
