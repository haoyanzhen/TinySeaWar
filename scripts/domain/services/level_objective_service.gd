extends RefCounted

var definition: Dictionary = {}
var runtime_state: Dictionary = {}


func setup(objective_definition: Dictionary) -> void:
	definition = objective_definition.duplicate(true)
	runtime_state = {
		"objective_set_id": str(definition.get("id", "")),
		"objective_kind": str(definition.get("objective_kind", "")),
		"title": str(definition.get("title", "")),
		"status": "Active",
		"current_step": 0,
		"engagement_unlocked": str(definition.get("objective_kind", "")) != "TutorialNavigation",
		"summary": _initial_summary(),
		"completed_at_tick": -1,
		"failed_at_tick": -1,
	}


func is_active() -> bool:
	return not definition.is_empty() and runtime_state.get("status", "") == "Active"


func snapshot() -> Dictionary:
	return runtime_state.duplicate(true)


func locked_player_commands() -> Array:
	return definition.get("locked_player_commands", []).duplicate()


func actions_locked_for(unit: Dictionary) -> bool:
	return is_active() and runtime_state.get("objective_kind", "") == "TutorialNavigation" and not bool(runtime_state.get("engagement_unlocked", false)) and unit.get("faction_id", "") in ["player", "enemy"]


func advance(battle_state: Dictionary) -> Dictionary:
	if not is_active():
		return {"events": [], "terminal": {}}
	var events: Array = []
	match str(definition.get("objective_kind", "")):
		"TutorialNavigation": _advance_tutorial_navigation(battle_state, events)
		"FlagshipMission": pass
	var terminal := _terminal_result(battle_state)
	if not terminal.is_empty():
		var completed: bool = str(terminal.get("winner_faction", "")) == "player"
		runtime_state["status"] = "Completed" if completed else "Failed"
		runtime_state["completed_at_tick" if completed else "failed_at_tick"] = int(battle_state.get("tick_index", 0))
		runtime_state["summary"] = str(definition.get("completion_text" if completed else "failure_text", ""))
		events.append({"event_type": "LevelObjectiveCompleted" if completed else "LevelObjectiveFailed", "objective_set_id": definition.get("id", ""), "summary": runtime_state["summary"]})
	return {"events": events, "terminal": terminal}


func _advance_tutorial_navigation(battle_state: Dictionary, events: Array) -> void:
	var unit: Dictionary = battle_state.get("units_by_id", {}).get(str(definition.get("player_unit_id", "")), {})
	if unit.is_empty() or unit.get("life_state", "") != "Alive": return
	var zones: Array = definition.get("waypoint_zones", [])
	var step := int(runtime_state.get("current_step", 0))
	if step >= zones.size(): return
	var zone: Dictionary = zones[step]
	var pair: Array = zone.get("position", [])
	if pair.size() != 2: return
	var center := Vector2(float(pair[0]), float(pair[1]))
	if (unit.get("position", Vector2.ZERO) as Vector2).distance_to(center) > float(zone.get("radius", 80.0)): return
	var movement: Dictionary = unit.get("movement_state", {})
	var corridor_points: Array = movement.get("corridor_points", [])
	var corridor_index := int(movement.get("corridor_index", 0))
	if corridor_index < corridor_points.size() and (corridor_points[corridor_index] as Vector2).distance_to(center) <= float(zone.get("radius", 80.0)):
		movement["corridor_index"] = corridor_index + 1
		unit.get("navigation_state", {})["trajectory_dirty"] = true
	step += 1
	runtime_state["current_step"] = step
	events.append({"event_type": "LevelObjectiveAdvanced", "objective_set_id": definition.get("id", ""), "step": step, "step_count": zones.size(), "label": zone.get("label", "")})
	if step >= zones.size():
		runtime_state["engagement_unlocked"] = true
		runtime_state["summary"] = "航行完成：自动副武器已开启，击沉沃德"
		events.append({"event_type": "TutorialStageChanged", "stage": "Engagement", "summary": runtime_state["summary"]})
	else:
		runtime_state["summary"] = "已到达航点 %d/%d，继续前往下一航点" % [step, zones.size()]


func _terminal_result(battle_state: Dictionary) -> Dictionary:
	var player_flagship := _flagship(battle_state, "fleet.player")
	var enemy_flagship := _flagship(battle_state, "fleet.enemy")
	if player_flagship.get("life_state", "") == "Sunk":
		return {"winner_faction": "enemy", "reason": "LEVEL_OBJECTIVE_CANCELLED"}
	if enemy_flagship.get("life_state", "") != "Sunk": return {}
	if runtime_state.get("objective_kind", "") == "TutorialNavigation" and not bool(runtime_state.get("engagement_unlocked", false)):
		return {"winner_faction": "enemy", "reason": "TUTORIAL_SEQUENCE_BROKEN"}
	return {"winner_faction": "player", "reason": "LEVEL_OBJECTIVE_COMPLETED"}


func _flagship(battle_state: Dictionary, fleet_id: String) -> Dictionary:
	var fleet: Dictionary = battle_state.get("fleets_by_id", {}).get(fleet_id, {})
	return battle_state.get("units_by_id", {}).get(str(fleet.get("flagship_unit_id", "")), {})


func _initial_summary() -> String:
	if definition.get("objective_kind", "") == "TutorialNavigation":
		return "选择天狼星，依次到达两个教学航点"
	return str(definition.get("completion_text", ""))
