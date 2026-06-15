extends RefCounted

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
	var target_id := str(result.get("target_unit_id", ""))
	if not summary["units"].has(source_id): summary["units"][source_id] = {"damage_dealt": 0.0, "damage_taken": 0.0, "shots": 0, "hits": 0}
	if not summary["units"].has(target_id): summary["units"][target_id] = {"damage_dealt": 0.0, "damage_taken": 0.0, "shots": 0, "hits": 0}
	summary["units"][source_id]["shots"] += 1
	if bool(result.get("hit", false)):
		summary["units"][source_id]["hits"] += 1
		if summary["first_hit_time"] < 0.0: summary["first_hit_time"] = elapsed_time
	var damage := float(result.get("final_damage", 0.0))
	summary["units"][source_id]["damage_dealt"] += damage
	summary["units"][target_id]["damage_taken"] += damage
