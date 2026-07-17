extends RefCounted

var definition: Dictionary = {}
var runtime_state: Dictionary = {}


func setup(objective_definition: Dictionary) -> void:
	definition = objective_definition.duplicate(true)
	var kind := str(definition.get("objective_kind", ""))
	var tutorial := _is_tutorial_kind(kind)
	runtime_state = {
		"objective_set_id": str(definition.get("id", "")),
		"objective_kind": kind,
		"is_tutorial": tutorial,
		"title": str(definition.get("title", "")),
		"status": "Active",
		"stage": "Instruction" if tutorial else "Mission",
		"current_step": 0,
		"action_counts": {},
		"engagement_unlocked": not tutorial,
		"summary": _initial_summary(),
		"instruction": _next_instruction({}),
		"ability_limit_text": str(definition.get("ability_limit_text", "")),
		"waypoint_zones": definition.get("waypoint_zones", []).duplicate(true),
		"world_markers": definition.get("world_markers", []).duplicate(true),
		"enemy_staging_position": definition.get("enemy_staging_position", []).duplicate(true),
		"enemy_staging_positions": definition.get("enemy_staging_positions", {}).duplicate(true),
		"completed_at_tick": -1,
		"failed_at_tick": -1,
	}


func is_active() -> bool:
	return not definition.is_empty() and runtime_state.get("status", "") == "Active"


func is_tutorial() -> bool:
	return _is_tutorial_kind(str(definition.get("objective_kind", "")))


func snapshot() -> Dictionary:
	return runtime_state.duplicate(true)


func locked_player_commands() -> Array:
	if not is_active(): return []
	var result: Array = definition.get("locked_player_commands", []).duplicate()
	if not bool(runtime_state.get("engagement_unlocked", false)):
		for command_type in definition.get("locked_player_commands_until_engagement", []):
			if command_type not in result: result.append(command_type)
	return result


func initial_player_control_state() -> Dictionary:
	return definition.get("initial_player_control_state", {}).duplicate(true)


func engagement_player_control_state() -> Dictionary:
	return definition.get("engagement_player_control_state", {}).duplicate(true)


func engagement_enemy_mode_locks() -> Dictionary:
	return definition.get("engagement_enemy_mode_locks", {}).duplicate(true)


func primary_locked_for(unit: Dictionary) -> bool:
	return _enemy_combat_locked(unit) and bool(definition.get("lock_enemy_primary_and_skill", false))


func skill_locked_for(unit: Dictionary) -> bool:
	return _enemy_combat_locked(unit) and bool(definition.get("lock_enemy_primary_and_skill", false))


func automatic_weapons_locked_for(unit: Dictionary) -> bool:
	return _enemy_combat_locked(unit) and bool(definition.get("lock_enemy_automatic_weapons", false))


func uses_authored_staging_movement(unit: Dictionary) -> bool:
	return not staging_position_for(unit).is_equal_approx(Vector2.INF)


func staging_position_for(unit: Dictionary) -> Vector2:
	if not is_active() or not is_tutorial() or bool(runtime_state.get("engagement_unlocked", false)):
		return Vector2.INF
	if unit.get("faction_id", "") != "enemy": return Vector2.INF
	var unit_id := str(unit.get("entity_id", ""))
	var positions: Dictionary = definition.get("enemy_staging_positions", {})
	var pair: Array = positions.get(unit_id, [])
	if pair.size() != 2:
		pair = definition.get("enemy_staging_position", [])
	if pair.size() != 2: return Vector2.INF
	return Vector2(float(pair[0]), float(pair[1]))


func record_action(action_id: String, unit_id: String, tick_index: int, facts: Dictionary = {}) -> Dictionary:
	if not is_active() or not is_tutorial():
		return {"accepted": false, "reason_code": "TUTORIAL_ACTION_NOT_REQUIRED", "events": []}
	var requirement := _requirement(action_id)
	if requirement.is_empty():
		return {"accepted": false, "reason_code": "TUTORIAL_ACTION_NOT_REQUIRED", "events": []}
	var required_unit_id := str(requirement.get("unit_id", ""))
	if required_unit_id.is_empty() and action_id in ["SelectTutorialUnit", "EnableCameraFollow"]:
		required_unit_id = str(definition.get("player_unit_id", ""))
	if not required_unit_id.is_empty() and unit_id != required_unit_id:
		return {"accepted": false, "reason_code": "TUTORIAL_WRONG_UNIT", "events": []}
	for fact_key in ["skill_id", "weapon_group_id", "ammo_group_id"]:
		if requirement.has(fact_key) and str(requirement.get(fact_key, "")) != str(facts.get(fact_key, "")):
			return {"accepted": false, "reason_code": "TUTORIAL_ACTION_MISMATCH", "events": []}
	var counts: Dictionary = runtime_state.get("action_counts", {})
	var previous := int(counts.get(action_id, 0))
	var required := int(requirement.get("required_count", 1))
	counts[action_id] = mini(required, previous + 1)
	runtime_state["action_counts"] = counts
	runtime_state["summary"] = _action_progress_summary(counts)
	runtime_state["instruction"] = _next_instruction(counts)
	var events: Array = []
	if int(counts[action_id]) > previous:
		events.append({
			"event_type": "TutorialActionRecorded",
			"action_id": action_id,
			"unit_id": unit_id,
			"facts": facts.duplicate(true),
			"count": int(counts[action_id]),
			"required_count": required,
			"tick_index": tick_index,
		})
	return {"accepted": true, "reason_code": "OK", "events": events}


func advance(battle_state: Dictionary) -> Dictionary:
	if not is_active():
		return {"events": [], "terminal": {}}
	var events: Array = []
	match str(definition.get("objective_kind", "")):
		"TutorialNavigation": _advance_tutorial_navigation(battle_state, events)
		"TutorialGunnery", "TutorialSkill": _advance_required_action_tutorial(events)
		"TutorialArmor": _advance_first_contact_tutorial(battle_state, events)
		"TutorialTorpedo", "TutorialCarrierHunt": _advance_first_contact_tutorial(battle_state, events)
		"TutorialSharedContact": _advance_shared_contact_tutorial(battle_state, events)
		"TutorialCommand": _advance_command_tutorial(battle_state, events)
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
	if step < zones.size():
		var zone: Dictionary = zones[step]
		var pair: Array = zone.get("position", [])
		if pair.size() == 2:
			var center := Vector2(float(pair[0]), float(pair[1]))
			if (unit.get("position", Vector2.ZERO) as Vector2).distance_to(center) <= float(zone.get("radius", 80.0)):
				var movement: Dictionary = unit.get("movement_state", {})
				var corridor_points: Array = movement.get("corridor_points", [])
				var corridor_index := int(movement.get("corridor_index", 0))
				if corridor_index < corridor_points.size() and (corridor_points[corridor_index] as Vector2).distance_to(center) <= float(zone.get("radius", 80.0)):
					movement["corridor_index"] = corridor_index + 1
					unit.get("navigation_state", {})["trajectory_dirty"] = true
				step += 1
				runtime_state["current_step"] = step
				events.append({"event_type": "LevelObjectiveAdvanced", "objective_set_id": definition.get("id", ""), "step": step, "step_count": zones.size(), "label": zone.get("label", "")})
	if step >= zones.size() and _required_actions_complete():
		_unlock_engagement("航行完成：教学已开启受限辅助航行与自动主炮，击沉沃德", events)
	elif step > 0:
		runtime_state["summary"] = "已到达航点 %d/%d，继续前往下一航点" % [step, zones.size()]
		runtime_state["instruction"] = _next_instruction(runtime_state.get("action_counts", {}))


func _advance_required_action_tutorial(events: Array) -> void:
	if _required_actions_complete():
		_unlock_engagement(str(definition.get("completion_text", "教学操作完成")), events)


func _advance_first_contact_tutorial(battle_state: Dictionary, events: Array) -> void:
	if bool(runtime_state.get("engagement_unlocked", false)): return
	var visible: Dictionary = battle_state.get("visible_by_faction", {}).get("player", {})
	for target_unit_id in definition.get("contact_target_unit_ids", []):
		if visible.has(str(target_unit_id)):
			runtime_state["current_step"] = 1
			events.append({"event_type": "LevelObjectiveAdvanced", "objective_set_id": definition.get("id", ""), "step": 1, "step_count": 1, "label": "首次接触"})
			_unlock_engagement("首次接触建立：观察重甲与大口径压制", events)
			return


func _advance_shared_contact_tutorial(battle_state: Dictionary, events: Array) -> void:
	if bool(runtime_state.get("engagement_unlocked", false)): return
	var scout_id := str(definition.get("scout_player_unit_id", ""))
	var target_id := str(definition.get("shared_contact_target_unit_id", ""))
	var scout: Dictionary = battle_state.get("units_by_id", {}).get(scout_id, {})
	var target: Dictionary = battle_state.get("units_by_id", {}).get(target_id, {})
	if scout.is_empty() or target.is_empty() or scout.get("life_state", "") != "Alive": return
	if battle_state.get("visible_by_faction", {}).get("player", {}).has(target_id):
		record_action("EstablishSharedContact", scout_id, int(battle_state.get("tick_index", 0)), {"target_unit_id": target_id})
		runtime_state["current_step"] = 1
		_unlock_engagement(str(definition.get("engagement_instruction", "共享接触建立")), events)


func _advance_command_tutorial(battle_state: Dictionary, events: Array) -> void:
	if bool(runtime_state.get("engagement_unlocked", false)): return
	var target_id := str(definition.get("command_target_unit_id", ""))
	var focused := 0
	for unit_id in definition.get("command_player_unit_ids", []):
		var unit: Dictionary = battle_state.get("units_by_id", {}).get(str(unit_id), {})
		if unit.get("life_state", "") == "Alive" and str(unit.get("targeting_state", {}).get("focused_target_id", "")) == target_id:
			focused += 1
	if focused >= int(definition.get("minimum_group_focus_count", 2)):
		record_action("GroupFocusTarget", "", int(battle_state.get("tick_index", 0)), {"target_unit_id": target_id})
		runtime_state["current_step"] = 1
		if _required_actions_complete(): _unlock_engagement(str(definition.get("engagement_instruction", "集火指令已确认")), events)


func _unlock_engagement(summary: String, events: Array) -> void:
	if bool(runtime_state.get("engagement_unlocked", false)): return
	runtime_state["engagement_unlocked"] = true
	runtime_state["stage"] = "Engagement"
	runtime_state["summary"] = summary
	runtime_state["instruction"] = str(definition.get("engagement_instruction", "保持己方旗舰存活并完成任务"))
	runtime_state["ability_limit_text"] = str(definition.get("engagement_ability_text", runtime_state.get("ability_limit_text", "")))
	events.append({"event_type": "TutorialStageChanged", "stage": "Engagement", "summary": runtime_state["summary"]})


func _terminal_result(battle_state: Dictionary) -> Dictionary:
	var player_flagship := _flagship(battle_state, "fleet.player")
	if player_flagship.get("life_state", "") == "Sunk":
		return {"winner_faction": "enemy", "reason": "LEVEL_OBJECTIVE_CANCELLED"}
	for protected_id in definition.get("protected_player_unit_ids", []):
		var protected: Dictionary = battle_state.get("units_by_id", {}).get(str(protected_id), {})
		if protected.is_empty() or protected.get("life_state", "") == "Sunk":
			return {"winner_faction": "enemy", "reason": "LEVEL_OBJECTIVE_CANCELLED"}
	var minimum_alive := int(definition.get("minimum_player_alive", 0))
	if minimum_alive > 0:
		var alive_count := 0
		for unit_id in battle_state.get("fleets_by_id", {}).get("fleet.player", {}).get("unit_ids", []):
			if battle_state.get("units_by_id", {}).get(str(unit_id), {}).get("life_state", "") == "Alive": alive_count += 1
		if alive_count < minimum_alive:
			return {"winner_faction": "enemy", "reason": "LEVEL_OBJECTIVE_CANCELLED"}
	if str(definition.get("objective_kind", "")) == "FlagshipMission":
		var enemy_flagship := _flagship(battle_state, "fleet.enemy")
		if enemy_flagship.get("life_state", "") == "Sunk":
			return {"winner_faction": "player", "reason": "LEVEL_OBJECTIVE_COMPLETED"}
		return {}
	if not is_tutorial(): return {}
	var required_enemy_ids: Array = definition.get("required_enemy_unit_ids", [])
	if required_enemy_ids.is_empty():
		required_enemy_ids = [str(battle_state.get("fleets_by_id", {}).get("fleet.enemy", {}).get("flagship_unit_id", ""))]
	var all_required_enemies_sunk := true
	for enemy_id in required_enemy_ids:
		var enemy: Dictionary = battle_state.get("units_by_id", {}).get(str(enemy_id), {})
		if enemy.is_empty() or enemy.get("life_state", "") != "Sunk":
			all_required_enemies_sunk = false
			break
	if not all_required_enemies_sunk: return {}
	if not bool(runtime_state.get("engagement_unlocked", false)) or not _required_actions_complete():
		return {"winner_faction": "enemy", "reason": "TUTORIAL_SEQUENCE_BROKEN"}
	return {"winner_faction": "player", "reason": "LEVEL_OBJECTIVE_COMPLETED"}


func _flagship(battle_state: Dictionary, fleet_id: String) -> Dictionary:
	var fleet: Dictionary = battle_state.get("fleets_by_id", {}).get(fleet_id, {})
	return battle_state.get("units_by_id", {}).get(str(fleet.get("flagship_unit_id", "")), {})


func _initial_summary() -> String:
	if not str(definition.get("intro_text", "")).is_empty():
		return str(definition.get("intro_text", ""))
	if definition.get("objective_kind", "") == "TutorialNavigation":
		return "学习选择、镜头跟随与连续航点；随后观察自动交战"
	return str(definition.get("completion_text", ""))


func _action_progress_summary(counts: Dictionary) -> String:
	var completed := 0
	var required_actions: Array = definition.get("required_actions", [])
	for requirement in required_actions:
		if int(counts.get(str(requirement.get("action_id", "")), 0)) >= int(requirement.get("required_count", 1)):
			completed += 1
	return "教学操作 %d/%d 已完成" % [completed, required_actions.size()]


func _requirement(action_id: String) -> Dictionary:
	for requirement in definition.get("required_actions", []):
		if str(requirement.get("action_id", "")) == action_id:
			return requirement
	return {}


func _required_actions_complete() -> bool:
	var counts: Dictionary = runtime_state.get("action_counts", {})
	for requirement in definition.get("required_actions", []):
		if int(counts.get(str(requirement.get("action_id", "")), 0)) < int(requirement.get("required_count", 1)):
			return false
	return true


func _next_instruction(counts: Dictionary) -> String:
	for requirement in definition.get("required_actions", []):
		var action_id := str(requirement.get("action_id", ""))
		if int(counts.get(action_id, 0)) < int(requirement.get("required_count", 1)):
			return str(requirement.get("instruction", ""))
	if str(definition.get("engagement_trigger", "")) == "FirstContact":
		return str(definition.get("pre_engagement_instruction", "等待首次接触"))
	return "驶入依次标记的教学航点" if definition.get("objective_kind", "") == "TutorialNavigation" else str(definition.get("engagement_instruction", "等待交战阶段开启"))


func _enemy_combat_locked(unit: Dictionary) -> bool:
	return is_active() and is_tutorial() and not bool(runtime_state.get("engagement_unlocked", false)) and unit.get("faction_id", "") == "enemy"


func _is_tutorial_kind(kind: String) -> bool:
	return kind.begins_with("Tutorial")
