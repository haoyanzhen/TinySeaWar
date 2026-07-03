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
	while session.state.get("phase", "") == "Running" and ticks_executed < maximum_ticks:
		_queue_policy_commands(
			session,
			run_registry,
			_policy_for_faction(manifest, "player"),
			_policy_for_faction(manifest, "enemy")
		)
		session.advance_tick(tick_seconds)
		ticks_executed += 1
	var stats: Dictionary = session.get_statistics()
	var finished: bool = str(session.state.get("phase", "")) == "Finished"
	var result: Dictionary = stats.get("result", {})
	var fleet_health := _fleet_health(session.state)
	var unit_damage_statistics: Dictionary = session.get_all_unit_damage_statistics()
	_annotate_lineups(unit_damage_statistics, side_variant)
	var winner_faction := str(result.get("winner_faction", ""))
	return {
		"run_id": run_id,
		"scenario_id": scenario_id,
		"level_definition_id": level_id,
		"seed": seed_value,
		"side_variant": side_variant,
		"end_state": "Finished" if finished else "GuardLimit",
		"ticks_executed": ticks_executed,
		"duration": float(stats.get("duration", session.state.get("elapsed_time", 0.0))),
		"winner_faction": winner_faction,
		"winner_lineup": _lineup_for_faction(winner_faction, side_variant),
		"finish_reason": str(result.get("reason", "GUARD_LIMIT" if not finished else "UNKNOWN")),
		"first_detection_time": float(stats.get("first_detection_time", -1.0)),
		"first_fire_time": float(stats.get("first_fire_time", -1.0)),
		"first_hit_time": float(stats.get("first_hit_time", -1.0)),
		"first_sinking_time": float(stats.get("first_sinking_time", -1.0)),
		"commands": int(stats.get("commands", 0)),
		"skill_casts": int(stats.get("skill_casts", 0)),
		"ai_behavior": stats.get("ai_behavior", {}).duplicate(true),
		"fleet_health": fleet_health,
		"unit_end_states": _unit_end_states(session.state),
		"units": unit_damage_statistics,
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
			"movement_mode": unit.get("movement_state", {}).get("mode", ""),
			"movement_target": unit.get("movement_state", {}).get("target_position", unit.get("position", Vector2.ZERO)),
			"ai_mode": unit.get("ai_state", {}).get("mode_id", ""),
			"ai_tactic": unit.get("ai_state", {}).get("tactic_id", ""),
			"level_task": unit.get("ai_state", {}).get("level_task", ""),
			"active_interrupt": unit.get("ai_state", {}).get("active_interrupt", ""),
		}
	return result


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
