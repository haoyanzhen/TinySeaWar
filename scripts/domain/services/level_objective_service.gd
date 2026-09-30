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
		"route_step": 0,
		"action_counts": {},
		"action_evidence": [],
		"engagement_unlocked": not tutorial,
		"summary": _initial_summary(),
		"instruction": _next_instruction({}),
		"ability_limit_text": str(definition.get("ability_limit_text", "")),
		"waypoint_zones": definition.get("waypoint_zones", []).duplicate(true),
		"route_waypoint_zones": definition.get("route_waypoint_zones", []).duplicate(true),
		"world_markers": definition.get("world_markers", []).duplicate(true),
		"enemy_staging_position": definition.get("enemy_staging_position", []).duplicate(true),
		"enemy_staging_positions": definition.get("enemy_staging_positions", {}).duplicate(true),
		"completed_at_tick": -1,
		"failed_at_tick": -1,
		"terminal_reason_code": "",
		"terminal_reason_summary": "",
		"terminal_reason_context": {},
		"mission_steps": [],
		"protection_lines": [],
		"reinforcement_hint": "",
		"optional_order_progress": 0,
		"optional_order_failed": false,
		"optional_mastery": "",
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
	return (_enemy_combat_locked(unit) and bool(definition.get("lock_enemy_primary_and_skill", false))) or _player_weapon_locked_until_action(unit)


func skill_locked_for(unit: Dictionary) -> bool:
	return (_enemy_combat_locked(unit) and bool(definition.get("lock_enemy_primary_and_skill", false))) or _player_weapon_locked_until_action(unit)


func automatic_weapons_locked_for(unit: Dictionary) -> bool:
	var player_tutorial_staging_lock: bool = is_active() and is_tutorial() and not bool(runtime_state.get("engagement_unlocked", false)) and unit.get("faction_id", "") == "player"
	return player_tutorial_staging_lock or (_enemy_combat_locked(unit) and bool(definition.get("lock_enemy_automatic_weapons", false))) or _player_weapon_locked_until_action(unit)


func _player_weapon_locked_until_action(unit: Dictionary) -> bool:
	if not is_active() or unit.get("faction_id", "") != "player": return false
	var action_id := str(definition.get("player_weapon_unlock_action_id", ""))
	if action_id.is_empty() or int(runtime_state.get("action_counts", {}).get(action_id, 0)) > 0: return false
	return str(unit.get("entity_id", "")) in definition.get("player_weapon_locked_unit_ids_until_action", [])


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
	if action_id == "GroupFocusTarget":
		var members: Array = facts.get("group_unit_ids", [])
		if str(facts.get("group_order_id", "")).is_empty() or members.size() < int(definition.get("minimum_group_focus_count", 2)):
			return {"accepted": false, "reason_code": "TUTORIAL_ACTION_MISMATCH", "events": []}
		for required_member in definition.get("command_player_unit_ids", []):
			if required_member not in members: return {"accepted": false, "reason_code": "TUTORIAL_ACTION_MISMATCH", "events": []}
	var required_unit_id := str(requirement.get("unit_id", ""))
	if required_unit_id.is_empty() and action_id in ["SelectTutorialUnit", "EnableCameraFollow"]:
		required_unit_id = str(definition.get("player_unit_id", ""))
	if not required_unit_id.is_empty() and unit_id != required_unit_id:
		return {"accepted": false, "reason_code": "TUTORIAL_WRONG_UNIT", "events": []}
	for fact_key in ["skill_id", "weapon_group_id", "ammo_group_id", "target_unit_id", "attack_category", "route_zone_id"]:
		if requirement.has(fact_key) and str(requirement.get(fact_key, "")) != str(facts.get(fact_key, "")):
			return {"accepted": false, "reason_code": "TUTORIAL_ACTION_MISMATCH", "events": []}
	var counts: Dictionary = runtime_state.get("action_counts", {})
	var prerequisite := str(requirement.get("prerequisite_action_id", ""))
	if not prerequisite.is_empty() and int(counts.get(prerequisite, 0)) < int(_requirement(prerequisite).get("required_count", 1)):
		return {"accepted": false, "reason_code": "TUTORIAL_PREREQUISITE_MISSING", "events": []}
	if requirement.has("required_active_skill_id") and str(requirement["required_active_skill_id"]) not in facts.get("active_skill_ids", []):
		return {"accepted": false, "reason_code": "TUTORIAL_ACTION_MISMATCH", "events": []}
	if requirement.has("ammo_type") and requirement["ammo_type"] != facts.get("ammo_type", ""):
		return {"accepted": false, "reason_code": "TUTORIAL_ACTION_MISMATCH", "events": []}
	var previous := int(counts.get(action_id, 0))
	var required := int(requirement.get("required_count", 1))
	counts[action_id] = mini(required, previous + 1)
	runtime_state["action_counts"] = counts
	runtime_state["summary"] = _action_progress_summary(counts)
	runtime_state["instruction"] = _next_instruction(counts)
	var events: Array = []
	if int(counts[action_id]) > previous:
		var evidence := {
			"event_type": "TutorialActionRecorded",
			"action_id": action_id,
			"unit_id": unit_id,
			"facts": facts.duplicate(true),
			"count": int(counts[action_id]),
			"required_count": required,
			"tick_index": tick_index,
		}
		runtime_state.get("action_evidence", []).append(evidence.duplicate(true))
		events.append(evidence)
	return {"accepted": true, "reason_code": "OK", "events": events}


func advance(battle_state: Dictionary) -> Dictionary:
	if not is_active():
		return {"events": [], "terminal": {}}
	var events: Array = []
	_advance_route_waypoints(battle_state, events)
	_advance_retreat(battle_state, events)
	match str(definition.get("objective_kind", "")):
		"TutorialNavigation": _advance_tutorial_navigation(battle_state, events)
		"TutorialGunnery", "TutorialSkill": _advance_required_action_tutorial(events)
		"TutorialArmor": _advance_first_contact_tutorial(battle_state, events)
		"TutorialTorpedo":
			if str(definition.get("engagement_trigger", "")) == "RequiredActionsComplete":
				_advance_required_action_tutorial(events)
			else:
				_advance_first_contact_tutorial(battle_state, events)
		"TutorialCarrierHunt":
			if str(definition.get("engagement_trigger", "")) == "RequiredActionsComplete":
				_advance_required_action_tutorial(events)
			else:
				_advance_first_contact_tutorial(battle_state, events)
		"TutorialSharedContact": _advance_shared_contact_tutorial(battle_state, events)
		"TutorialCommand": _advance_command_tutorial(battle_state, events)
		"FlagshipMission", "ChallengeMission": _advance_challenge_progress(battle_state)
	var terminal := _terminal_result(battle_state)
	if is_tutorial() and _next_incomplete_action() != "":
		runtime_state["instruction"] = _next_instruction(runtime_state.get("action_counts", {}))
	if is_tutorial():
		runtime_state["next_action_id"] = _next_incomplete_action()
	if not terminal.is_empty():
		var completed: bool = str(terminal.get("winner_faction", "")) == "player"
		runtime_state["status"] = "Completed" if completed else "Failed"
		runtime_state["completed_at_tick" if completed else "failed_at_tick"] = int(battle_state.get("tick_index", 0))
		runtime_state["terminal_reason_code"] = str(terminal.get("reason_code", terminal.get("reason", "")))
		runtime_state["terminal_reason_summary"] = str(terminal.get("summary", definition.get("completion_text" if completed else "failure_text", "")))
		runtime_state["terminal_reason_context"] = terminal.get("context", {}).duplicate(true)
		runtime_state["summary"] = runtime_state["terminal_reason_summary"]
		events.append({
			"event_type": "LevelObjectiveCompleted" if completed else "LevelObjectiveFailed",
			"objective_set_id": definition.get("id", ""),
			"reason_code": runtime_state["terminal_reason_code"],
			"summary": runtime_state["summary"],
			"context": runtime_state["terminal_reason_context"].duplicate(true),
		})
	return {"events": events, "terminal": terminal}


func refresh_challenge_progress(battle_state: Dictionary) -> void:
	if str(definition.get("objective_kind", "")) in ["FlagshipMission", "ChallengeMission"]:
		_advance_challenge_progress(battle_state)


func _advance_challenge_progress(battle_state: Dictionary) -> void:
	var units: Dictionary = battle_state.get("units_by_id", {})
	var targets: Array = definition.get("required_enemy_unit_ids", []).duplicate()
	if targets.is_empty(): targets = definition.get("ordered_enemy_unit_ids", []).duplicate()
	if targets.is_empty(): targets = [str(_flagship(battle_state, "fleet.enemy").get("entity_id", ""))]
	var steps: Array = []
	for target_id in targets:
		var target: Dictionary = units.get(str(target_id), {})
		steps.append({"label": "击沉%s" % _unit_label(target, str(target_id)), "completed": target.get("life_state", "") == "Sunk"})
	var minimum := int(definition.get("minimum_enemy_sunk", 0))
	if minimum > 0:
		var sunk := 0
		for unit in units.values():
			if unit.get("faction_id", "") == "enemy" and unit.get("life_state", "") == "Sunk": sunk += 1
		steps.append({"label": "击沉敌舰 %d/%d" % [sunk, minimum], "completed": sunk >= minimum})
	runtime_state["mission_steps"] = steps
	var protection: Array = []
	var flagship := _flagship(battle_state, "fleet.player")
	for unit_id in definition.get("protected_player_unit_ids", []):
		if str(unit_id) == str(flagship.get("entity_id", "")): continue
		protection.append("保护%s" % _unit_label(units.get(str(unit_id), {}), str(unit_id)))
	if not flagship.is_empty(): protection.append("旗舰%s须存活" % _unit_label(flagship))
	var any_ids: Array = definition.get("required_any_player_unit_ids", [])
	if not any_ids.is_empty():
		var labels: Array[String] = []
		for unit_id in any_ids: labels.append(_unit_label(units.get(str(unit_id), {}), str(unit_id)))
		protection.append("%s至少存活%d艘" % ["/".join(labels), int(definition.get("minimum_required_any_player_alive", 1))])
	var hp_id := str(definition.get("minimum_player_hp_ratio_unit_id", ""))
	if not hp_id.is_empty(): protection.append("%s耐久须高于%.0f%%" % [_unit_label(units.get(hp_id, {}), hp_id), float(definition.get("minimum_player_hp_ratio", 0.0)) * 100.0])
	if int(definition.get("minimum_player_alive", 0)) > 0: protection.append("己方至少存活%d艘" % int(definition["minimum_player_alive"]))
	runtime_state["protection_lines"] = protection
	var hints: Array[String] = []
	for wave in battle_state.get("reinforcement_waves", []):
		if wave.get("status", "") != "Pending": continue
		var wave_def: Dictionary = wave.get("definition", {})
		var remaining := maxf(0.0, float(wave_def.get("earliest_time", 0.0)) - float(battle_state.get("elapsed_time", 0.0)))
		var spawn_id := str(wave_def.get("spawn_point_id", ""))
		var entrance := str(wave_def.get("spawn_display_name", {"RN": "北侧入口", "RS": "南侧入口"}.get(spawn_id, "")))
		hints.append("%s接替增援%s：%s" % ["己方" if wave_def.get("faction_id", "") == "player" else "敌方", "（%s）" % entrance if not entrance.is_empty() else "", "最早%d秒后，需有空位" % ceili(remaining) if remaining > 0.0 else "等待出战空位"])
	runtime_state["reinforcement_hint"] = "；".join(hints)
	var stages: Array = definition.get("optional_enemy_sunk_stages", []).duplicate(true)
	if stages.is_empty():
		for unit_id in definition.get("optional_ordered_enemy_unit_ids", []): stages.append([unit_id])
	if stages.is_empty(): return
	var progress := int(runtime_state.get("optional_order_progress", 0))
	while progress < stages.size() and stages[progress].all(func(id): return units.get(str(id), {}).get("life_state", "") == "Sunk"):
		progress += 1
	for index in range(progress + 1, stages.size()):
		if stages[index].any(func(id): return units.get(str(id), {}).get("life_state", "") == "Sunk"):
			runtime_state["optional_order_failed"] = true
	runtime_state["optional_order_progress"] = progress
	var labels: Array[String] = []
	for stage in stages:
		var members: Array[String] = []
		for unit_id in stage:
			var unit: Dictionary = units.get(str(unit_id), {})
			members.append("%s%s" % [_unit_label(unit, str(unit_id)), "✓" if unit.get("life_state", "") == "Sunk" else ""])
		labels.append(" + ".join(members))
	var status := "未达成" if bool(runtime_state["optional_order_failed"]) else ("已完成" if progress == stages.size() else "%d/%d" % [progress, stages.size()])
	runtime_state["optional_mastery"] = "可选精通：%s（%s，不影响通关奖励）" % [" → ".join(labels), status]


func _advance_route_waypoints(battle_state: Dictionary, events: Array) -> void:
	var zones: Array = definition.get("route_waypoint_zones", [])
	if zones.is_empty(): return
	var step := int(runtime_state.get("route_step", 0))
	if step >= zones.size(): return
	var unit_id := str(definition.get("route_player_unit_id", ""))
	var unit: Dictionary = battle_state.get("units_by_id", {}).get(unit_id, {})
	if unit.is_empty() or unit.get("life_state", "") != "Alive": return
	var zone: Dictionary = zones[step]
	var pair: Array = zone.get("position", [])
	if pair.size() != 2: return
	var center := Vector2(float(pair[0]), float(pair[1]))
	if (unit.get("position", Vector2.ZERO) as Vector2).distance_to(center) > float(zone.get("radius", 80.0)):
		return
	var action_result := record_action(
		"ReachTutorialRouteZone",
		unit_id,
		int(battle_state.get("tick_index", 0)),
		{"route_zone_id": str(zone.get("id", ""))}
	)
	if not bool(action_result.get("accepted", false)): return
	step += 1
	runtime_state["route_step"] = step
	events.append_array(action_result.get("events", []))
	events.append({
		"event_type": "LevelObjectiveAdvanced",
		"objective_set_id": definition.get("id", ""),
		"step": step,
		"step_count": zones.size(),
		"label": zone.get("label", ""),
		"route_zone_id": zone.get("id", ""),
	})


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
	var scout: Dictionary = battle_state.get("units_by_id", {}).get(scout_id, {})
	if scout.is_empty() or scout.get("life_state", "") != "Alive": return
	var action_counts: Dictionary = runtime_state.get("action_counts", {})
	var route_requirement := _requirement("ReachTutorialRouteZone")
	var route_complete := route_requirement.is_empty() or int(action_counts.get("ReachTutorialRouteZone", 0)) >= int(route_requirement.get("required_count", 1))
	if route_complete and int(action_counts.get("EstablishSharedContact", 0)) > 0:
		runtime_state["current_step"] = 1
		_unlock_engagement(str(definition.get("engagement_instruction", "共享接触建立")), events)


func _advance_command_tutorial(_battle_state: Dictionary, events: Array) -> void:
	if bool(runtime_state.get("engagement_unlocked", false)): return
	if _required_actions_complete():
		runtime_state["current_step"] = 1
		_unlock_engagement(str(definition.get("engagement_instruction", "集火指令已确认")), events)


func _advance_retreat(battle_state: Dictionary, events: Array) -> void:
	var zone: Dictionary = definition.get("retreat_zone", {})
	if zone.is_empty(): return
	var unit_id := str(zone.get("unit_id", ""))
	var unit: Dictionary = battle_state.get("units_by_id", {}).get(unit_id, {})
	var pair: Array = zone.get("position", [])
	if pair.size() != 2 or unit.get("life_state", "") != "Alive": return
	if (unit.get("position", Vector2.ZERO) as Vector2).distance_to(Vector2(float(pair[0]), float(pair[1]))) <= float(zone.get("radius", 0.0)):
		events.append_array(record_action("ReachRetreatZone", unit_id, int(battle_state.get("tick_index", 0)), {"route_zone_id":zone.get("id", "")}).get("events", []))


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
		return _cancelled_result(
			"PLAYER_FLAGSHIP_SUNK",
			"己方旗舰%s沉没，任务取消" % _unit_label(player_flagship),
			{"unit_id": str(player_flagship.get("entity_id", ""))}
		)
	for protected_id in definition.get("protected_player_unit_ids", []):
		var protected: Dictionary = battle_state.get("units_by_id", {}).get(str(protected_id), {})
		if protected.is_empty() or protected.get("life_state", "") == "Sunk":
			return _cancelled_result(
				"PROTECTED_PLAYER_UNIT_SUNK",
				"保护目标%s沉没，任务取消" % _unit_label(protected, str(protected_id)),
				{"unit_id": str(protected_id)}
			)
	var required_any: Array = definition.get("required_any_player_unit_ids", [])
	if not required_any.is_empty():
		var survivors := 0
		for unit_id in required_any:
			if battle_state.get("units_by_id", {}).get(str(unit_id), {}).get("life_state", "") == "Alive": survivors += 1
		var required_survivors := int(definition.get("minimum_required_any_player_alive", 1))
		if survivors < required_survivors:
			var labels: Array[String] = []
			for unit_id in required_any:
				labels.append(_unit_label(battle_state.get("units_by_id", {}).get(str(unit_id), {}), str(unit_id)))
			return _cancelled_result(
				"REQUIRED_ANY_PLAYER_SURVIVORS_LOST",
				"%s的存活数量为%d，低于任务要求%d，任务取消" % ["、".join(labels), survivors, required_survivors],
				{"unit_ids": required_any.duplicate(), "survivors": survivors, "minimum_survivors": required_survivors}
			)
	var hp_unit_id := str(definition.get("minimum_player_hp_ratio_unit_id", ""))
	if not hp_unit_id.is_empty():
		var hp_unit: Dictionary = battle_state.get("units_by_id", {}).get(hp_unit_id, {})
		var hp_ratio := float(hp_unit.get("current_hp", 0.0)) / maxf(1.0, float(hp_unit.get("max_hp", 1.0)))
		var minimum_ratio := float(definition.get("minimum_player_hp_ratio", 0.0))
		if hp_unit.is_empty() or hp_ratio <= minimum_ratio:
			return _cancelled_result(
				"PLAYER_UNIT_HP_RATIO_BREACHED",
				"%s耐久降至%.1f%%，不高于任务要求的%.1f%%，任务取消" % [_unit_label(hp_unit, hp_unit_id), hp_ratio * 100.0, minimum_ratio * 100.0],
				{"unit_id": hp_unit_id, "hp_ratio": hp_ratio, "minimum_hp_ratio": minimum_ratio}
			)
	var minimum_alive := int(definition.get("minimum_player_alive", 0))
	if minimum_alive > 0:
		var alive_count := 0
		for unit_id in battle_state.get("fleets_by_id", {}).get("fleet.player", {}).get("unit_ids", []):
			if battle_state.get("units_by_id", {}).get(str(unit_id), {}).get("life_state", "") == "Alive": alive_count += 1
		if alive_count < minimum_alive:
			return _cancelled_result(
				"MINIMUM_PLAYER_SURVIVORS_LOST",
				"己方存活舰艇仅%d艘，低于任务要求%d艘，任务取消" % [alive_count, minimum_alive],
				{"survivors": alive_count, "minimum_survivors": minimum_alive}
			)
	if str(definition.get("objective_kind", "")) == "FlagshipMission":
		var enemy_flagship := _flagship(battle_state, "fleet.enemy")
		if enemy_flagship.get("life_state", "") == "Sunk":
			return _completed_result()
		return {}
	if str(definition.get("objective_kind", "")) == "ChallengeMission":
		var ordered_targets: Array = definition.get("ordered_enemy_unit_ids", [])
		if not ordered_targets.is_empty():
			for index in range(ordered_targets.size()):
				var target: Dictionary = battle_state.get("units_by_id", {}).get(str(ordered_targets[index]), {})
				if target.get("life_state", "") != "Sunk": continue
				for prior_index in range(index):
					if battle_state.get("units_by_id", {}).get(str(ordered_targets[prior_index]), {}).get("life_state", "") != "Sunk":
						var prior_id := str(ordered_targets[prior_index])
						var target_id := str(ordered_targets[index])
						return _cancelled_result(
							"ORDERED_TARGET_SUNK_EARLY",
							"%s在%s之前沉没，任务顺序被破坏" % [
								_unit_label(target, target_id),
								_unit_label(battle_state.get("units_by_id", {}).get(prior_id, {}), prior_id),
							],
							{"sunk_unit_id": target_id, "required_prior_unit_id": prior_id, "ordered_index": index}
						)
			if ordered_targets.all(func(unit_id): return battle_state.get("units_by_id", {}).get(str(unit_id), {}).get("life_state", "") == "Sunk"):
				return _completed_result()
			return {}
		var required_enemy_ids: Array = definition.get("required_enemy_unit_ids", [])
		for enemy_id in required_enemy_ids:
			if battle_state.get("units_by_id", {}).get(str(enemy_id), {}).get("life_state", "") != "Sunk": return {}
		var minimum_enemy_sunk := int(definition.get("minimum_enemy_sunk", 0))
		if minimum_enemy_sunk > 0:
			var sunk_count := 0
			for unit_id in battle_state.get("fleets_by_id", {}).get("fleet.enemy", {}).get("unit_ids", []):
				if battle_state.get("units_by_id", {}).get(str(unit_id), {}).get("life_state", "") == "Sunk": sunk_count += 1
			if sunk_count < minimum_enemy_sunk: return {}
		return _completed_result()
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
		if bool(definition.get("allow_post_sink_actions", false)) and int(runtime_state.get("action_counts", {}).get("TorpedoHit", 0)) > 0: return {}
		return {
			"winner_faction": "enemy",
			"reason": "TUTORIAL_SEQUENCE_BROKEN",
			"reason_code": "TUTORIAL_SEQUENCE_BROKEN",
			"summary": str(definition.get("failure_text", "教学必做操作或顺序未完成")),
			"context": {},
		}
	return _completed_result()


func _completed_result() -> Dictionary:
	return {
		"winner_faction": "player",
		"reason": "LEVEL_OBJECTIVE_COMPLETED",
		"reason_code": "LEVEL_OBJECTIVE_COMPLETED",
		"summary": str(definition.get("completion_text", "关卡任务完成")),
		"context": {},
	}


func _cancelled_result(condition_code: String, summary: String, context: Dictionary) -> Dictionary:
	return {
		"winner_faction": "enemy",
		"reason": "LEVEL_OBJECTIVE_CANCELLED",
		"reason_code": "LEVEL_OBJECTIVE_CANCELLED_%s" % condition_code,
		"summary": summary,
		"context": context.duplicate(true),
	}


func _unit_label(unit: Dictionary, fallback: String = "指定单位") -> String:
	var label := str(unit.get("display_name", ""))
	if not label.is_empty(): return label
	var unit_id := str(unit.get("entity_id", fallback))
	return unit_id if not unit_id.is_empty() else fallback


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
	if str(definition.get("engagement_trigger", "")) == "FirstContact" and not bool(runtime_state.get("engagement_unlocked", false)):
		return str(definition.get("pre_engagement_instruction", "等待首次接触"))
	for requirement in definition.get("required_actions", []):
		var action_id := str(requirement.get("action_id", ""))
		if int(counts.get(action_id, 0)) < int(requirement.get("required_count", 1)):
			return str(requirement.get("instruction", ""))
	return "驶入依次标记的教学航点" if definition.get("objective_kind", "") == "TutorialNavigation" else str(definition.get("engagement_instruction", "等待交战阶段开启"))


func _next_incomplete_action() -> String:
	var counts: Dictionary = runtime_state.get("action_counts", {})
	for requirement in definition.get("required_actions", []):
		var action_id := str(requirement.get("action_id", ""))
		if int(counts.get(action_id, 0)) < int(requirement.get("required_count", 1)): return action_id
	return ""


func _enemy_combat_locked(unit: Dictionary) -> bool:
	if not is_active() or not is_tutorial() or unit.get("faction_id", "") != "enemy":
		return false
	if not bool(runtime_state.get("engagement_unlocked", false)):
		return true
	var unlock_action_id := str(definition.get("enemy_weapon_unlock_action_id", ""))
	return not unlock_action_id.is_empty() and int(runtime_state.get("action_counts", {}).get(unlock_action_id, 0)) <= 0


func _is_tutorial_kind(kind: String) -> bool:
	return kind.begins_with("Tutorial")
