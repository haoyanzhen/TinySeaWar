class_name SimulationRunner
extends RefCounted

const BattleSession = preload("res://scripts/application/battle_session.gd")
const ExperimentLoader = preload("res://scripts/infrastructure/simulation/experiment_loader.gd")
const Aggregator = preload("res://scripts/infrastructure/simulation/simulation_aggregator.gd")


func run_experiment(registry, manifest: Dictionary) -> Dictionary:
	var loader = ExperimentLoader.new()
	var errors := loader.validate_manifest(manifest)
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "runs": [], "aggregate": {}}
	for scenario in manifest.get("scenarios", []):
		if registry.get_definition("levels", str(scenario.get("level_definition_id", ""))).is_empty():
			errors.append("Unknown level_definition_id: %s" % scenario.get("level_definition_id", ""))
	if registry.get_definition("ai_profiles", str(manifest.get("ai_profile_id", "ai.profile.standard"))).is_empty():
		errors.append("Unknown ai_profile_id: %s" % manifest.get("ai_profile_id", ""))
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "runs": [], "aggregate": {}}
	var started_usec := Time.get_ticks_usec()
	var runs: Array = []
	for scenario in manifest.get("scenarios", []):
		for seed_value in loader.seeds_for(manifest, scenario):
			runs.append(_run_battle(registry, manifest, scenario, seed_value, "original"))
			if bool(manifest.get("side_swap", false)):
				runs.append(_run_battle(registry, manifest, scenario, seed_value, "swapped"))
	var aggregate := Aggregator.new().aggregate(runs)
	if str(manifest.get("simulation_kind", "")) == "LevelWinRateEvaluation":
		aggregate["win_rate_evaluation"] = _win_rate_evaluation(manifest, aggregate, runs)
	var elapsed_seconds := float(Time.get_ticks_usec() - started_usec) / 1000000.0
	return {
		"ok": true,
		"errors": [],
		"metadata": {
			"schema_version": int(manifest.get("schema_version", 1)),
			"experiment_id": str(manifest.get("experiment_id", "")),
			"description": str(manifest.get("description", "")),
			"simulation_kind": str(manifest.get("simulation_kind", "FullBattleSimulation")),
			"player_policy_id": _policy_for_faction(manifest, "player"),
			"enemy_policy_id": _policy_for_faction(manifest, "enemy"),
			"tick_seconds": float(manifest.get("tick_seconds", 0.1)),
			"maximum_ticks": int(manifest.get("maximum_ticks", 1)),
			"side_swap": bool(manifest.get("side_swap", false)),
			"ai_mode_locks": manifest.get("ai_mode_locks", {}).duplicate(true),
			"ai_profile_id": str(manifest.get("ai_profile_id", "ai.profile.standard")),
			"godot_version": Engine.get_version_info().get("string", "unknown"),
			"executed_at": Time.get_datetime_string_from_system(false, true),
			"wall_time_seconds": elapsed_seconds,
			"manifest_hash": manifest.hash(),
		},
		"resolved_manifest": manifest.duplicate(true),
		"runs": runs,
		"aggregate": aggregate,
	}


func _run_battle(registry, manifest: Dictionary, scenario: Dictionary, seed_value: int, side_variant: String) -> Dictionary:
	var scenario_id := str(scenario.get("scenario_id", "scenario"))
	var level_id := str(scenario.get("level_definition_id", ""))
	var run_id := "%s.%s.%s.seed_%d" % [str(manifest.get("experiment_id", "experiment")), scenario_id, side_variant, seed_value]
	var run_registry = _registry_for_side_variant(registry, level_id, side_variant)
	var session = BattleSession.new(run_registry)
	var creation: Dictionary = session.create_battle(level_id, seed_value)
	if not bool(creation.get("ok", false)):
		return {
			"run_id": run_id,
			"scenario_id": scenario_id,
			"level_definition_id": level_id,
			"seed": seed_value,
			"side_variant": side_variant,
			"end_state": "CreationFailure",
			"errors": creation.get("errors", []),
		}
	var full_ai_factions: Array[String] = []
	if _policy_for_faction(manifest, "player") == "LatestRuntimeAI": full_ai_factions.append("player")
	if _policy_for_faction(manifest, "enemy") == "LatestRuntimeAI": full_ai_factions.append("enemy")
	if not full_ai_factions.is_empty():
		session.configure_full_ai_factions(full_ai_factions)
	var profile_result := session.configure_ai_profile(str(manifest.get("ai_profile_id", "ai.profile.standard")))
	if not bool(profile_result.get("accepted", false)):
		return {"run_id": run_id, "scenario_id": scenario_id, "seed": seed_value, "side_variant": side_variant, "end_state": "CreationFailure", "errors": [profile_result.get("reason_code", "AI_PROFILE_NOT_FOUND")]}
	var ai_mode_locks: Dictionary = manifest.get("ai_mode_locks", {})
	if not ai_mode_locks.is_empty():
		session.configure_ai_mode_locks(ai_mode_locks)
	var tick_seconds := float(manifest.get("tick_seconds", 0.1))
	var maximum_ticks := int(scenario.get("maximum_ticks", manifest.get("maximum_ticks", 1)))
	var ticks_executed := 0
	var enemy_damage_before_engagement := 0.0
	var policy_command_rejections := 0
	var policy_command_rejections_by_reason := {}
	var policy_command_rejection_details: Array = []
	while session.state.get("phase", "") == "Running" and ticks_executed < maximum_ticks:
		var engagement_before_tick := bool(session.state.get("level_objective", {}).get("engagement_unlocked", true))
		_queue_policy_commands(
			session,
			run_registry,
			_policy_for_faction(manifest, "player"),
			_policy_for_faction(manifest, "enemy")
		)
		var tick_events: Array = session.advance_tick(tick_seconds)
		for event in tick_events:
			if str(event.get("event_type", "")) == "CommandRejected" and str(event.get("issuer_type", "")) == "SimulationPolicy":
				policy_command_rejections += 1
				var rejection_reason := str(event.get("reason_code", "UNKNOWN"))
				policy_command_rejections_by_reason[rejection_reason] = int(policy_command_rejections_by_reason.get(rejection_reason, 0)) + 1
				policy_command_rejection_details.append({
					"tick_index":int(session.state.get("tick_index", 0)),
					"command_type":str(event.get("command_type", "")),
					"unit_id":str(event.get("unit_id", "")),
					"reason_code":rejection_reason,
				})
		if not engagement_before_tick:
			for event in tick_events:
				if str(event.get("event_type", "")) != "AttackResolved": continue
				var damage_result: Dictionary = event.get("damage_result", {})
				if str(damage_result.get("source_unit_id", "")).begins_with("unit.enemy.") and str(damage_result.get("target_unit_id", "")).begins_with("unit.player."):
					enemy_damage_before_engagement += float(damage_result.get("final_damage", 0.0))
		ticks_executed += 1
	var stats: Dictionary = session.get_statistics()
	var finished: bool = str(session.state.get("phase", "")) == "Finished"
	var result: Dictionary = stats.get("result", {})
	var fleet_health := _fleet_health(session.state)
	var unit_damage_statistics: Dictionary = session.get_all_unit_damage_statistics()
	var non_ship_damage_statistics: Dictionary = session.get_all_non_ship_damage_statistics()
	_annotate_lineups(unit_damage_statistics, side_variant)
	var winner_faction := str(result.get("winner_faction", ""))
	var finish_reason := str(result.get("reason_code", result.get("reason", "GUARD_LIMIT" if not finished else "UNKNOWN")))
	var finish_reason_summary := str(result.get("reason_summary", ""))
	var end_state := "Finished" if finished else "GuardLimit"
	if finish_reason == "LEVEL_TECHNICAL_LIMIT": end_state = "TechnicalLimit"
	return {
		"run_id": run_id,
		"scenario_id": scenario_id,
		"level_definition_id": level_id,
		"seed": seed_value,
		"side_variant": side_variant,
		"end_state": end_state,
		"ticks_executed": ticks_executed,
		"duration": float(stats.get("duration", session.state.get("elapsed_time", 0.0))),
		"winner_faction": winner_faction,
		"winner_lineup": _lineup_for_faction(winner_faction, side_variant),
		"finish_reason": finish_reason,
		"finish_reason_summary": finish_reason_summary,
		"finish_reason_context": result.get("reason_context", {}).duplicate(true),
		"first_detection_time": float(stats.get("first_detection_time", -1.0)),
		"first_fire_time": float(stats.get("first_fire_time", -1.0)),
		"first_hit_time": float(stats.get("first_hit_time", -1.0)),
		"first_sinking_time": float(stats.get("first_sinking_time", -1.0)),
		"commands": int(stats.get("commands", 0)),
		"skill_casts": int(stats.get("skill_casts", 0)),
		"enemy_damage_before_engagement": enemy_damage_before_engagement,
		"policy_command_rejections": policy_command_rejections,
		"policy_command_rejections_by_reason": policy_command_rejections_by_reason,
		"policy_command_rejection_details": policy_command_rejection_details,
		"ai_behavior": stats.get("ai_behavior", {}).duplicate(true),
		"fleet_health": fleet_health,
		"unit_end_states": _unit_end_states(session.state),
		"units": unit_damage_statistics,
		"non_ship_damage": non_ship_damage_statistics,
		"level_objective": session.state.get("level_objective", {}).duplicate(true),
	}


func _unit_end_states(battle_state: Dictionary) -> Dictionary:
	var result := {}
	var unit_ids: Array = battle_state.get("units_by_id", {}).keys()
	unit_ids.sort()
	for unit_id in unit_ids:
		var unit: Dictionary = battle_state["units_by_id"][unit_id]
		result[str(unit_id)] = {
			"definition_id": unit.get("definition_id", ""),
			"faction_id": unit.get("faction_id", ""),
			"life_state": unit.get("life_state", ""),
			"position": unit.get("position", Vector2.ZERO),
			"heading": unit.get("heading", 0.0),
			"movement_mode": unit.get("movement_state", {}).get("mode", ""),
			"movement_target": unit.get("movement_state", {}).get("target_position", unit.get("position", Vector2.ZERO)),
			"corridor_index": unit.get("movement_state", {}).get("corridor_index", 0),
			"corridor_point_count": unit.get("movement_state", {}).get("corridor_points", []).size(),
			"corridor_current_point": _end_state_corridor_point(unit),
			"corridor_current_gate": _end_state_corridor_gate(unit),
			"pending_route_requests": unit.get("navigation_state", {}).get("pending_route_requests", 0),
			"route_waiting": unit.get("navigation_state", {}).get("route_waiting", false),
			"current_control": unit.get("navigation_state", {}).get("current_control", {}),
			"navigation_state": unit.get("navigation_state", {}).get("state", ""),
			"ai_mode": unit.get("ai_state", {}).get("mode_id", ""),
			"ai_tactic": unit.get("ai_state", {}).get("tactic_id", ""),
			"level_task": unit.get("ai_state", {}).get("level_task", ""),
			"active_interrupt": "TorpedoEvasion" if str(unit.get("navigation_state", {}).get("state", "NormalNavigation")) == "EmergencyEvasion" else "",
		}
	return result


func _end_state_corridor_point(unit: Dictionary) -> Vector2:
	var points: Array = unit.get("movement_state", {}).get("corridor_points", [])
	var index := int(unit.get("movement_state", {}).get("corridor_index", 0))
	return points[index] if index >= 0 and index < points.size() else unit.get("position", Vector2.ZERO)


func _end_state_corridor_gate(unit: Dictionary) -> Dictionary:
	var gates: Array = unit.get("movement_state", {}).get("corridor_gates", [])
	var index := int(unit.get("movement_state", {}).get("corridor_index", 0))
	return gates[index] if index >= 0 and index < gates.size() else {}


func _registry_for_side_variant(registry, level_id: String, side_variant: String):
	if side_variant != "swapped":
		return registry
	var cloned = registry.get_script().new()
	cloned.definitions = registry.definitions.duplicate(true)
	cloned.errors.clear()
	var level: Dictionary = registry.get_definition("levels", level_id)
	var swapped_level := level.duplicate(true)
	var player_fleet: Array = level.get("player_fleet", [])
	var enemy_fleet: Array = level.get("enemy_fleet", [])
	if player_fleet.size() != enemy_fleet.size():
		return registry
	swapped_level["player_fleet"] = _place_lineup_on_spawns(enemy_fleet, player_fleet, "player")
	swapped_level["enemy_fleet"] = _place_lineup_on_spawns(player_fleet, enemy_fleet, "enemy")
	cloned.definitions["levels"][level_id] = swapped_level
	return cloned


func _place_lineup_on_spawns(lineup: Array, spawn_template: Array, faction_id: String) -> Array:
	var placed: Array = []
	for index in range(lineup.size()):
		var member: Dictionary = lineup[index].duplicate(true)
		var spawn: Dictionary = spawn_template[index]
		member["position"] = spawn.get("position", []).duplicate(true)
		member["heading"] = spawn.get("heading", 0.0)
		var source_entity_id := str(member.get("entity_id", "unit.%s.%d" % [faction_id, index]))
		var suffix := source_entity_id.trim_prefix("unit.player.").trim_prefix("unit.enemy.")
		member["entity_id"] = "unit.%s.%s" % [faction_id, suffix]
		placed.append(member)
	return placed


func _annotate_lineups(units: Dictionary, side_variant: String) -> void:
	for unit_id in units:
		var faction_id := str(units[unit_id].get("faction_id", ""))
		units[unit_id]["lineup_id"] = _lineup_for_faction(faction_id, side_variant)


func _lineup_for_faction(faction_id: String, side_variant: String) -> String:
	if faction_id.is_empty(): return ""
	if side_variant == "swapped":
		return "original_enemy" if faction_id == "player" else "original_player"
	return "original_player" if faction_id == "player" else "original_enemy"


func _queue_policy_commands(session, registry, player_policy_id: String, enemy_policy_id: String) -> void:
	match player_policy_id:
		"TutorialT01Deterministic": _queue_t01_tutorial_commands(session)
		"TutorialT02Deterministic": _queue_t02_tutorial_commands(session)
		"TutorialT03Deterministic": _queue_t03_tutorial_commands(session, registry)
		"TutorialT04Deterministic": pass
		"TutorialT05Deterministic": _queue_t05_tutorial_commands(session)
		"TutorialT06Deterministic": _queue_t06_tutorial_commands(session)
		"TutorialT07Deterministic": _queue_t07_tutorial_commands(session)
		"TutorialT08Deterministic": _queue_t08_tutorial_commands(session)
	var unit_ids: Array = session.state.get("units_by_id", {}).keys()
	unit_ids.sort()
	for unit_id in unit_ids:
		var unit: Dictionary = session.state["units_by_id"][unit_id]
		if unit.get("life_state", "") != "Alive":
			continue
		var policy_id := player_policy_id if unit.get("faction_id", "") == "player" else enemy_policy_id
		if policy_id != "BaselineAutopilot":
			continue
		var target := _first_visible_target(session, unit)
		if not target.is_empty():
			var aim_status: Dictionary = session.get_primary_aim_status(str(unit_id), target["position"])
			if bool(aim_status.get("legal", false)):
				session.queue_command({
					"command_id": "simulation.primary.%d.%s" % [int(session.state.get("tick_index", 0)), unit_id],
					"command_type": "FirePrimaryWeapon",
					"issued_at_tick": int(session.state.get("tick_index", 0)),
					"issuer_type": "SimulationPolicy",
					"issuer_id": str(unit.get("faction_id", "")),
					"unit_id": str(unit_id),
					"target_position": target["position"],
				})
		_queue_ready_skill(session, registry, unit, target)


func _queue_t01_tutorial_commands(session) -> void:
	var objective: Dictionary = session.state.get("level_objective", {})
	if objective.get("objective_set_id", "") != "objective.t01_navigation" or objective.get("status", "") != "Active": return
	var unit_id := "unit.player.t01.sirius"
	var counts: Dictionary = objective.get("action_counts", {})
	if bool(objective.get("engagement_unlocked", false)):
		return
	# Leave two seconds for the instructional text to be read before executing the
	# deterministic legal solution; this also mirrors the runtime objective test.
	if int(session.state.get("tick_index", 0)) < 20: return
	for action_id in ["SelectTutorialUnit", "EnableCameraFollow"]:
		if int(counts.get(action_id, 0)) > 0: continue
		session.queue_command({
			"command_id": "simulation.t01.%s.%d" % [action_id, int(session.state.get("tick_index", 0))],
			"command_type": "RecordTutorialAction", "issued_at_tick": int(session.state.get("tick_index", 0)),
			"issuer_type": "SimulationPolicy", "issuer_id": "player", "unit_id": unit_id, "action_id": action_id,
		})
	var queued_count := int(counts.get("AppendMoveWaypoint", 0))
	var zones: Array = objective.get("waypoint_zones", [])
	for index in range(queued_count, mini(2, zones.size())):
		var pair: Array = zones[index].get("position", [])
		if pair.size() != 2: continue
		session.queue_command({
			"command_id": "simulation.t01.waypoint.%d" % index,
			"command_type": "AppendMoveWaypoint", "issued_at_tick": int(session.state.get("tick_index", 0)),
			"issuer_type": "Player", "issuer_id": "player", "unit_id": unit_id,
			"target_position": Vector2(float(pair[0]), float(pair[1])),
		})


func _queue_t02_tutorial_commands(session) -> void:
	var objective: Dictionary = session.state.get("level_objective", {})
	if objective.get("objective_set_id", "") != "objective.t02_gunnery" or objective.get("status", "") != "Active" or bool(objective.get("engagement_unlocked", false)): return
	if int(session.state.get("tick_index", 0)) < 20: return
	var unit_id := "unit.player.t02.warspite"
	var counts: Dictionary = objective.get("action_counts", {})
	if int(counts.get("SwitchAmmo", 0)) <= 0:
		session.queue_command({
			"command_id": "simulation.t02.ammo", "command_type": "SwitchAmmo",
			"issued_at_tick": int(session.state.get("tick_index", 0)), "issuer_type": "SimulationPolicy",
			"issuer_id": "player", "unit_id": unit_id,
		})
		return
	if int(counts.get("ManualPrimaryFire", 0)) > 0: return
	var unit: Dictionary = session.state.get("units_by_id", {}).get(unit_id, {})
	var target := _first_visible_target(session, unit)
	if target.is_empty(): return
	var aim_status: Dictionary = session.get_primary_aim_status(unit_id, target.get("position", Vector2.ZERO))
	if not bool(aim_status.get("legal", false)): return
	session.queue_command({
		"command_id": "simulation.t02.primary.%d" % int(session.state.get("tick_index", 0)),
		"command_type": "FirePrimaryWeapon", "issued_at_tick": int(session.state.get("tick_index", 0)),
		"issuer_type": "SimulationPolicy", "issuer_id": "player", "unit_id": unit_id,
		"target_position": target.get("position", Vector2.ZERO),
	})


func _queue_t03_tutorial_commands(session, registry) -> void:
	var objective: Dictionary = session.state.get("level_objective", {})
	if objective.get("objective_set_id", "") != "objective.t03_skill" or objective.get("status", "") != "Active" or bool(objective.get("engagement_unlocked", false)): return
	if int(session.state.get("tick_index", 0)) < 20 or int(objective.get("action_counts", {}).get("CastSkill", 0)) > 0: return
	var unit: Dictionary = session.state.get("units_by_id", {}).get("unit.player.t03.iowa", {})
	var target := _first_visible_target(session, unit)
	if target.is_empty(): return
	var skill: Dictionary = registry.get_definition("skills", "skill.iowa_radar_salvo")
	if (unit.get("position", Vector2.ZERO) as Vector2).distance_to(target.get("position", Vector2.ZERO)) > float(skill.get("cast_range", 0.0)): return
	session.queue_command({
		"command_id": "simulation.t03.skill.%d" % int(session.state.get("tick_index", 0)),
		"command_type": "CastSkill", "issued_at_tick": int(session.state.get("tick_index", 0)),
		"issuer_type": "SimulationPolicy", "issuer_id": "player", "unit_id": "unit.player.t03.iowa",
		"target_ref": {"type": "Entity", "entity_id": str(target.get("entity_id", ""))},
	})


func _queue_t05_tutorial_commands(session) -> void:
	var objective: Dictionary = session.state.get("level_objective", {})
	if objective.get("objective_set_id", "") != "objective.t05_torpedo" or objective.get("status", "") != "Active": return
	_queue_tutorial_manual_control(session, ["unit.player.t05.yukikaze", "unit.player.t05.anshan"])
	if _queue_tutorial_route_move(session, objective): return
	var target: Dictionary = session.state.get("units_by_id", {}).get("unit.enemy.t05.warspite", {})
	if target.is_empty(): return
	if not session.state.get("visible_by_faction", {}).get("player", {}).has("unit.enemy.t05.warspite"):
		var contact: Dictionary = session.state.get("contacts_by_faction", {}).get("player", {}).get("unit.enemy.t05.warspite", {})
		var search_position: Vector2 = contact.get("last_known_position", Vector2(2200.0, 700.0))
		_queue_tutorial_move(session, "unit.player.t05.yukikaze", search_position, "simulation.t05.search")
		var escort_search := search_position + Vector2(0.0, 220.0)
		escort_search.y = clampf(escort_search.y, 80.0, float(session.state.get("map", {}).get("height", 2304.0)) - 80.0)
		_queue_tutorial_move(session, "unit.player.t05.anshan", escort_search, "simulation.t05.escort_search")
		return
	var attack_plans: Array = [
		{"unit_id":"unit.player.t05.yukikaze", "weapon_id":"weapon.yukikaze_torpedo", "cover":Vector2(1472.0, 1728.0)},
	]
	if int(objective.get("action_counts", {}).get("TorpedoHit", 0)) > 0:
		attack_plans.append({"unit_id":"unit.player.t05.anshan", "weapon_id":"weapon.anshan_torpedo", "cover":Vector2(1320.0, 1950.0)})
	for attack_plan in attack_plans:
		var unit_id := str(attack_plan["unit_id"])
		var unit: Dictionary = session.state.get("units_by_id", {}).get(unit_id, {})
		if unit.is_empty() or unit.get("life_state", "") != "Alive": continue
		var torpedo_states: Array = unit.get("weapon_states", []).filter(func(weapon_state):
			return str(weapon_state.get("definition_id", "")) == str(attack_plan["weapon_id"])
		)
		var all_mounts_reloading := not torpedo_states.is_empty() and torpedo_states.all(func(weapon_state):
			return float(weapon_state.get("reload_remaining", 0.0)) > 1.0
		)
		if all_mounts_reloading:
			_queue_tutorial_move(session, unit_id, attack_plan["cover"], "simulation.t05.disengage")
			continue
		_queue_ready_skill(session, session.registry, unit, target)
		_queue_manual_torpedo_solution(session, unit_id, str(attack_plan["weapon_id"]), target)


func _queue_manual_torpedo_solution(session, unit_id: String, weapon_id: String, target: Dictionary) -> void:
	var unit: Dictionary = session.state.get("units_by_id", {}).get(unit_id, {})
	if unit.is_empty() or unit.get("life_state", "") != "Alive": return
	var weapon: Dictionary = session.registry.get_definition("weapons", weapon_id)
	var aim_solution: Dictionary = session._automatic_aim_solution(unit, target, weapon)
	var aim_position: Vector2 = aim_solution.get("position", target.get("position", Vector2.ZERO))
	var aim_status: Dictionary = session.get_primary_aim_status(unit_id, aim_position)
	if not bool(aim_status.get("legal", false)):
		var direct_position: Vector2 = target.get("position", Vector2.ZERO)
		var direct_status: Dictionary = session.get_primary_aim_status(unit_id, direct_position)
		if bool(direct_status.get("legal", false)):
			aim_position = direct_position
			aim_status = direct_status
	if not bool(aim_status.get("legal", false)):
		var tick := int(session.state.get("tick_index", 0))
		if tick % 50 != 0:
			return
		var aim_direction := (target.get("position", aim_position) as Vector2) - (unit.get("position", Vector2.ZERO) as Vector2)
		var broadside_destination := (unit.get("position", Vector2.ZERO) as Vector2) + Vector2.RIGHT.rotated(aim_direction.angle() + PI * 0.5) * 600.0
		broadside_destination.x = clampf(broadside_destination.x, 80.0, float(session.state.get("map", {}).get("width", 4096.0)) - 80.0)
		broadside_destination.y = clampf(broadside_destination.y, 80.0, float(session.state.get("map", {}).get("height", 2304.0)) - 80.0)
		_queue_tutorial_move(session, unit_id, broadside_destination, "simulation.t05.broadside")
		return
	session.queue_command({"command_id": "simulation.t05.torpedo.%s.%d" % [unit_id, int(session.state.get("tick_index", 0))], "command_type": "FirePrimaryWeapon", "issued_at_tick": int(session.state.get("tick_index", 0)), "issuer_type": "SimulationPolicy", "issuer_id": "player", "unit_id": unit_id, "target_position": aim_position})


func _queue_t06_tutorial_commands(session) -> void:
	var objective: Dictionary = session.state.get("level_objective", {})
	if objective.get("objective_set_id", "") != "objective.t06_carrier_hunt" or objective.get("status", "") != "Active": return
	if _queue_tutorial_route_move(session, objective): return
	if not bool(objective.get("engagement_unlocked", false)): return
	_queue_tutorial_focus(session, ["unit.player.t06.shimakaze", "unit.player.t06.gnevny", "unit.player.t06.ward"], "unit.enemy.t06.argus")


func _queue_t07_tutorial_commands(session) -> void:
	var objective: Dictionary = session.state.get("level_objective", {})
	if objective.get("objective_set_id", "") != "objective.t07_shared_contact" or objective.get("status", "") != "Active": return
	if _queue_tutorial_route_move(session, objective): return
	if not bool(objective.get("engagement_unlocked", false)): return
	_queue_tutorial_focus(session, ["unit.player.t07.iowa"], "unit.enemy.t07.hindenburg")
	var iowa: Dictionary = session.state.get("units_by_id", {}).get("unit.player.t07.iowa", {})
	var hindenburg: Dictionary = session.state.get("units_by_id", {}).get("unit.enemy.t07.hindenburg", {})
	if iowa.is_empty() or hindenburg.is_empty() or hindenburg.get("life_state", "") != "Alive": return
	var aim_position: Vector2 = hindenburg.get("position", Vector2.ZERO)
	var aim_status: Dictionary = session.get_primary_aim_status("unit.player.t07.iowa", aim_position)
	if not bool(aim_status.get("legal", false)): return
	session.queue_command({
		"command_id":"simulation.t07.manual_primary.%d" % int(session.state.get("tick_index", 0)),
		"command_type":"FirePrimaryWeapon",
		"issued_at_tick":int(session.state.get("tick_index", 0)),
		"issuer_type":"SimulationPolicy",
		"issuer_id":"player",
		"unit_id":"unit.player.t07.iowa",
		"target_position":aim_position,
	})


func _queue_t08_tutorial_commands(session) -> void:
	var objective: Dictionary = session.state.get("level_objective", {})
	if objective.get("objective_set_id", "") != "objective.t08_command" or bool(objective.get("engagement_unlocked", false)): return
	if _queue_tutorial_route_move(session, objective): return
	_queue_tutorial_focus(session, ["unit.player.t08.warspite", "unit.player.t08.san_diego"], "unit.enemy.t08.hindenburg")


func _queue_tutorial_route_move(session, objective: Dictionary) -> bool:
	var zones: Array = objective.get("route_waypoint_zones", [])
	var step := int(objective.get("route_step", 0))
	if step >= zones.size():
		var route_unit_id := str(session.registry.get_definition("objectives", str(objective.get("objective_set_id", ""))).get("route_player_unit_id", ""))
		var route_unit: Dictionary = session.state.get("units_by_id", {}).get(route_unit_id, {})
		if str(route_unit.get("movement_state", {}).get("mode", "")) in ["PlayerMoveOrder", "PlayerWaypointRoute"]:
			var clear_tick := int(session.state.get("tick_index", 0))
			if clear_tick % 20 == 0:
				session.queue_command({
					"command_id":"simulation.route.clear.%s.%d" % [route_unit_id, clear_tick],
					"command_type":"ClearMoveRoute",
					"issued_at_tick":clear_tick,
					"issuer_type":"SimulationPolicy",
					"issuer_id":"player",
					"unit_id":route_unit_id,
				})
			return true
		return false
	var tick := int(session.state.get("tick_index", 0))
	if tick < 20: return true
	var pair: Array = zones[step].get("position", [])
	if pair.size() != 2: return true
	var unit_id := str(session.registry.get_definition("objectives", str(objective.get("objective_set_id", ""))).get("route_player_unit_id", ""))
	if unit_id.is_empty(): return true
	_queue_tutorial_move(session, unit_id, Vector2(float(pair[0]), float(pair[1])), "simulation.route.%d" % step)
	return true


func _queue_tutorial_manual_control(session, unit_ids: Array) -> void:
	if not bool(session.state.get("level_objective", {}).get("engagement_unlocked", false)): return
	var tick := int(session.state.get("tick_index", 0))
	if tick % 20 != 0: return
	session.queue_command({
		"command_id":"simulation.manual_control.%d" % tick,
		"command_type":"SetUnitControlState",
		"issued_at_tick":tick,
		"issuer_type":"SimulationPolicy",
		"issuer_id":"player",
		"unit_ids":unit_ids,
		"movement_assist_enabled":false,
		"secondary_auto_fire_enabled":false,
		"primary_auto_fire_enabled":false,
	})


func _queue_tutorial_move(session, unit_id: String, target_position: Vector2, command_prefix: String) -> void:
	var tick := int(session.state.get("tick_index", 0))
	if tick % 20 != 0: return
	var unit: Dictionary = session.state.get("units_by_id", {}).get(unit_id, {})
	if unit.is_empty() or unit.get("life_state", "") != "Alive": return
	var movement: Dictionary = unit.get("movement_state", {})
	if str(movement.get("mode", "")) in ["PlayerMoveOrder", "PlayerWaypointRoute"] and (movement.get("target_position", unit.get("position", Vector2.ZERO)) as Vector2).distance_to(target_position) <= 1.0:
		return
	session.queue_command({
		"command_id":"%s.%s.%d" % [command_prefix, unit_id, tick],
		"command_type":"MoveUnits",
		"issued_at_tick":tick,
		"issuer_type":"SimulationPolicy",
		"issuer_id":"player",
		"unit_id":unit_id,
		"movement_mode":"PlayerMoveOrder",
		"target_position":target_position,
	})


func _queue_tutorial_focus(session, unit_ids: Array, target_id: String) -> void:
	if not session.state.get("visible_by_faction", {}).get("player", {}).has(target_id): return
	for unit_id in unit_ids:
		var unit: Dictionary = session.state.get("units_by_id", {}).get(str(unit_id), {})
		if unit.is_empty() or unit.get("life_state", "") != "Alive" or str(unit.get("targeting_state", {}).get("focused_target_id", "")) == target_id: continue
		session.queue_command({
			"command_id": "simulation.focus.%s.%d" % [unit_id, int(session.state.get("tick_index", 0))],
			"command_type": "FocusTarget",
			"issued_at_tick": int(session.state.get("tick_index", 0)),
			"issuer_type": "SimulationPolicy",
			"issuer_id": "player",
			"unit_id": str(unit_id),
			"target_unit_id": target_id,
		})


func _first_visible_target(session, unit: Dictionary) -> Dictionary:
	var faction_id := str(unit.get("faction_id", ""))
	var target_ids: Array = session.state.get("visible_by_faction", {}).get(faction_id, {}).keys()
	target_ids.sort()
	for target_id in target_ids:
		var target: Dictionary = session.state.get("units_by_id", {}).get(target_id, {})
		if target.get("life_state", "") == "Alive" and target.get("faction_id", "") != faction_id:
			return target
	return {}


func _queue_ready_skill(session, registry, unit: Dictionary, target: Dictionary) -> void:
	if float(unit.get("skill_state", {}).get("cooldown_remaining", 0.0)) > 0.0:
		return
	var skill_id := str(unit.get("skill_state", {}).get("definition_id", ""))
	var skill: Dictionary = registry.get_definition("skills", skill_id)
	if skill.is_empty():
		return
	var target_ref := {"type": "Self"}
	var target_type := str(skill.get("target_type", "Self"))
	if target_type in ["Enemy", "Area"]:
		if target.is_empty():
			return
		var cast_range := float(skill.get("cast_range", 0.0))
		if cast_range > 0.0 and (unit.get("position", Vector2.ZERO) as Vector2).distance_to(target["position"]) > cast_range:
			return
		target_ref = {"type": "Entity", "entity_id": target["entity_id"]} if target_type == "Enemy" else {"type": "Position", "position": target["position"]}
	session.queue_command({
		"command_id": "simulation.skill.%d.%s" % [int(session.state.get("tick_index", 0)), unit.get("entity_id", "")],
		"command_type": "CastSkill",
		"issued_at_tick": int(session.state.get("tick_index", 0)),
		"issuer_type": "SimulationPolicy",
		"issuer_id": str(unit.get("faction_id", "")),
		"unit_id": str(unit.get("entity_id", "")),
		"target_ref": target_ref,
	})


func _policy_for_faction(manifest: Dictionary, faction_id: String) -> String:
	var field_name := "%s_policy_id" % faction_id
	return str(manifest.get(field_name, manifest.get("policy_id", "SessionAutonomy")))


func _win_rate_evaluation(manifest: Dictionary, aggregate: Dictionary, runs: Array = []) -> Dictionary:
	var contract: Dictionary = manifest.get("win_rate_evaluation", {})
	var target := float(contract.get("target_player_win_rate", 0.0))
	var tolerance := float(contract.get("tolerance", 0.0))
	var finished := int(aggregate.get("finished_runs", 0))
	var planned := int(aggregate.get("planned_runs", 0))
	var observed := float(aggregate.get("player_win_rate", 0.0))
	var sample_complete := planned == 20 and finished == 20
	var within_target := observed >= target - tolerance - 0.000001 and observed <= target + tolerance + 0.000001
	var minimum_p10_duration := float(contract.get("minimum_p10_duration", 0.0))
	var observed_p10_duration := float(aggregate.get("duration", {}).get("p10", 0.0))
	var duration_passed := observed_p10_duration + 0.000001 >= minimum_p10_duration
	var required_action_ids: Array = contract.get("required_objective_action_ids", [])
	var required_action_sequence: Array = contract.get("required_objective_action_sequence", [])
	var objective_evidence_passed := true
	if (bool(contract.get("require_engagement_unlocked", false)) or not required_action_ids.is_empty() or not required_action_sequence.is_empty()) and runs.size() != planned:
		objective_evidence_passed = false
	for run in runs:
		var objective: Dictionary = run.get("level_objective", {})
		if bool(contract.get("require_engagement_unlocked", false)) and not bool(objective.get("engagement_unlocked", false)):
			objective_evidence_passed = false
		for action_id in required_action_ids:
			if int(objective.get("action_counts", {}).get(str(action_id), 0)) <= 0:
				objective_evidence_passed = false
		var evidence_index := 0
		for evidence in objective.get("action_evidence", []):
			if evidence_index < required_action_sequence.size() and str(evidence.get("action_id", "")) == str(required_action_sequence[evidence_index]):
				evidence_index += 1
		if evidence_index != required_action_sequence.size():
			objective_evidence_passed = false
	var maximum_early_damage := float(contract.get("maximum_enemy_damage_before_engagement", INF))
	var observed_early_damage := float(aggregate.get("enemy_damage_before_engagement", 0.0))
	var early_damage_passed := observed_early_damage <= maximum_early_damage + 0.000001
	var maximum_policy_rejections := int(contract.get("maximum_policy_command_rejections", 0))
	var observed_policy_rejections := int(aggregate.get("policy_command_rejections", 0))
	var policy_rejections_passed := observed_policy_rejections <= maximum_policy_rejections
	var maximum_behavior_anomalies := int(contract.get("maximum_behavior_anomalies", 0))
	var observed_behavior_anomalies := int(aggregate.get("behavior_anomaly_count", 0))
	var behavior_anomalies_passed := observed_behavior_anomalies <= maximum_behavior_anomalies
	return {
		"settlement_source": "BattleStatisticsReport",
		"required_battles": 20,
		"valid_battles": finished,
		"target_player_win_rate": target,
		"tolerance": tolerance,
		"observed_player_win_rate": observed,
		"sample_complete": sample_complete,
		"within_target": within_target,
		"minimum_p10_duration": minimum_p10_duration,
		"observed_p10_duration": observed_p10_duration,
		"duration_passed": duration_passed,
		"required_objective_action_ids": required_action_ids.duplicate(),
		"required_objective_action_sequence": required_action_sequence.duplicate(),
		"objective_evidence_passed": objective_evidence_passed,
		"maximum_enemy_damage_before_engagement": maximum_early_damage,
		"observed_enemy_damage_before_engagement": observed_early_damage,
		"early_damage_passed": early_damage_passed,
		"maximum_policy_command_rejections": maximum_policy_rejections,
		"observed_policy_command_rejections": observed_policy_rejections,
		"policy_rejections_passed": policy_rejections_passed,
		"maximum_behavior_anomalies": maximum_behavior_anomalies,
		"observed_behavior_anomalies": observed_behavior_anomalies,
		"behavior_anomalies_passed": behavior_anomalies_passed,
		"passed": sample_complete and within_target and duration_passed and objective_evidence_passed and early_damage_passed and policy_rejections_passed and behavior_anomalies_passed,
	}


func _fleet_health(state: Dictionary) -> Dictionary:
	var result := {}
	for fleet_id in state.get("fleets_by_id", {}):
		var fleet: Dictionary = state["fleets_by_id"][fleet_id]
		var current_hp := 0.0
		var alive_units := 0
		for unit_id in fleet.get("unit_ids", []):
			var unit: Dictionary = state.get("units_by_id", {}).get(unit_id, {})
			current_hp += float(unit.get("current_hp", 0.0))
			if unit.get("life_state", "") == "Alive": alive_units += 1
		var initial_hp := maxf(1.0, float(fleet.get("initial_max_hp_total", 1.0)))
		result[fleet_id] = {
			"current_hp": current_hp,
			"initial_hp": initial_hp,
			"remaining_hp_ratio": current_hp / initial_hp,
			"alive_units": alive_units,
		}
	return result
