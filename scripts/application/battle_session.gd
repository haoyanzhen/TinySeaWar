extends RefCounted

const SeededRandomSource = preload("res://scripts/infrastructure/random/seeded_random_source.gd")
const ModifierService = preload("res://scripts/domain/services/modifier_service.gd")
const DamageService = preload("res://scripts/domain/services/damage_service.gd")
const CollisionGeometryService = preload("res://scripts/domain/services/collision_geometry_service.gd")
const GunDispersionService = preload("res://scripts/domain/services/gun_dispersion_service.gd")
const BattleRecorder = preload("res://scripts/infrastructure/analytics/battle_recorder.gd")
const DamageStatistics = preload("res://scripts/infrastructure/analytics/damage_statistics.gd")
const TerrainQueryService = preload("res://scripts/domain/services/terrain_query_service.gd")
const TerrainCollisionFieldLoader = preload("res://scripts/infrastructure/data/terrain_collision_field_loader.gd")
const TerrainContextService = preload("res://scripts/domain/services/terrain_context_service.gd")
const FacilityService = preload("res://scripts/domain/services/facility_service.gd")
const MinefieldService = preload("res://scripts/domain/services/minefield_service.gd")
const RoutePlanner = preload("res://scripts/application/navigation/route_planner.gd")
const LevelObjectiveService = preload("res://scripts/domain/services/level_objective_service.gd")
const NavigationRequestBroker = preload("res://scripts/application/navigation/navigation_request_broker.gd")
const TrajectoryPlanner = preload("res://scripts/application/navigation/trajectory_planner.gd")
const ShipMotionService = preload("res://scripts/domain/services/ship_motion_service.gd")
const AIQuantitativeModel = preload("res://scripts/application/ai/ai_quantitative_model.gd")
const AIObservation = preload("res://scripts/application/ai/ai_observation.gd")

const PLAYER_FACTION := "player"
const ENEMY_FACTION := "enemy"
const CONTACT_GHOST_DURATION := 60.0
const AI_DECISION_INTERVAL := 0.5
const AI_IMMEDIATE_THRESHOLD := 65.0
const AI_TACTIC_MINIMUM_HOLD := 1.5
const AI_TACTIC_SWITCH_MARGIN := 12.0
const AI_TARGET_MINIMUM_HOLD := 2.0
const AI_TARGET_SWITCH_MARGIN := 12.0
const AI_TARGET_SWITCH_COOLDOWN := 1.5
const AI_ENGAGEMENT_PRESSURE_TRIGGER := 0.25
const AI_LONG_IDLE_SECONDS := 20.0
const AI_PATH_RECOVERY_SECONDS := 4.0
const AI_PATH_STUCK_SECONDS := 20.0
const NAVIGATION_NORMAL_INTERVAL_TICKS := 10
const NAVIGATION_EMERGENCY_EXIT_TICKS := 4
const NAVIGATION_STRATEGIC_INTERVAL := 3.0
const NAVIGATION_FAILURE_RETRY_MAX := 12.0

var registry
var random_source
var recorder := BattleRecorder.new()
var state := {}
var command_queue: Array = []
var delayed_attacks: Array = []
var terrain_query = TerrainQueryService.new()
var terrain_collision_field_loader = TerrainCollisionFieldLoader.new()
var terrain_context_service = TerrainContextService.new()
var facility_service = FacilityService.new()
var minefield_service = MinefieldService.new()
var route_planner = RoutePlanner.new()
var level_objective_service = LevelObjectiveService.new()
var navigation_request_broker = NavigationRequestBroker.new()
var trajectory_planner = TrajectoryPlanner.new()
var navigation_definition: Dictionary = {}
var _event_buffer: Array = []
var _event_sequence := 0
var _entity_sequence := 0
var _full_ai_factions := {ENEMY_FACTION: true}
var _ai_mode_locks_by_definition := {}
var _ai_battlefield_context_cache := {}
var _ai_local_power_cache := {}
var _ai_observations_by_faction := {}
var _ai_damage_reservations := {}
var _ai_facility_route_cache := {}
var _ai_effect_reservations := {}
var _ai_profile := {}
var _ai_cover_cache := {}
var _ai_route_quality_cache := {}
var _ai_objective_plan_cache := {}
var _performance_profile_enabled := false
var _performance_profile := {}
var _performance_tick_counts := {}


func _init(definition_registry = null) -> void:
	registry = definition_registry


func configure_performance_profiling(enabled: bool = true) -> void:
	_performance_profile_enabled = enabled
	_performance_profile = {
		"tick_total_usec": [],
		"navigation_usec": [],
		"movement_usec": [],
		"ai_decision_usec": [],
		"normal_plans_per_tick": [],
		"emergency_scans_per_tick": [],
		"emergency_plans_per_tick": [],
		"strategic_corridors_per_tick": [],
		"trajectory_candidates_per_tick": [],
		"trajectory_failures_per_tick": [],
		"trajectory_segments_simulated_per_tick": [],
		"trajectory_candidates_rejected_by_terrain_per_tick": [],
		"collision_field_usec": [],
		"collision_field_queries_per_tick": [],
		"collision_field_cells_visited_per_tick": [],
		"collision_field_definitely_clear_per_tick": [],
		"collision_field_exact_fallbacks_per_tick": [],
		"collision_field_unavailable_fallbacks_per_tick": [],
	}
	_performance_tick_counts = {}


func get_performance_profile() -> Dictionary:
	return _performance_profile.duplicate(true)


func _profile_increment(key: String, amount: int = 1) -> void:
	if not _performance_profile_enabled: return
	_performance_tick_counts[key] = int(_performance_tick_counts.get(key, 0)) + amount


func _profile_stage(key: String, elapsed_usec: int) -> void:
	if _performance_profile_enabled:
		_performance_profile[key].append(elapsed_usec)


func create_battle(level_id: String, seed_value: int = 1) -> Dictionary:
	if registry == null:
		return {"ok": false, "errors": ["MISSING_REGISTRY"]}
	var level: Dictionary = registry.get_definition("levels", level_id)
	if level.is_empty():
		return {"ok": false, "errors": ["LEVEL_NOT_FOUND"]}
	return create_battle_from_definition(level, seed_value)


func create_battle_from_definition(level_definition: Dictionary, seed_value: int = 1) -> Dictionary:
	if registry == null:
		return {"ok": false, "errors": ["MISSING_REGISTRY"]}
	if level_definition.is_empty():
		return {"ok": false, "errors": ["LEVEL_NOT_FOUND"]}
	var level: Dictionary = level_definition.duplicate(true)
	var level_id := str(level.get("id", ""))
	if level_id.is_empty():
		return {"ok": false, "errors": ["MISSING_LEVEL_ID"]}
	_ai_profile = registry.get_definition("ai_profiles", str(level.get("enemy_ai_profile_id", "ai.profile.standard"))).duplicate(true)
	level_objective_service = LevelObjectiveService.new()
	var objective_definition: Dictionary = registry.get_definition("objectives", str(level.get("objective_set_id", "")))
	if not objective_definition.is_empty():
		level_objective_service.setup(objective_definition)
	var validation_errors := _validate_level_runtime(level)
	if not validation_errors.is_empty():
		return {"ok": false, "errors": validation_errors}
	random_source = SeededRandomSource.new(seed_value)
	_event_buffer.clear()
	command_queue.clear()
	delayed_attacks.clear()
	navigation_request_broker.clear()
	navigation_request_broker.configure(1, 2000)
	_ai_battlefield_context_cache.clear()
	_ai_local_power_cache.clear()
	_ai_observations_by_faction.clear()
	_ai_damage_reservations.clear()
	_ai_facility_route_cache.clear()
	_ai_effect_reservations.clear()
	_ai_cover_cache.clear()
	_ai_route_quality_cache.clear()
	_ai_objective_plan_cache.clear()
	_event_sequence = 0
	_entity_sequence = 0
	state = {
		"battle_id": "battle.%s.%s" % [level_id.trim_prefix("level."), seed_value],
		"phase": "Preparing",
		"elapsed_time": 0.0,
		"tick_index": 0,
		"level_definition_id": level_id,
		"battle_seed": seed_value,
		"map": level.get("map", {}).duplicate(true),
		"time_limit": float(level.get("time_limit", 1200.0)),
		"fleets_by_id": {},
		"units_by_id": {},
		"projectiles_by_id": {},
		"known_projectiles_by_faction": {PLAYER_FACTION: {}, ENEMY_FACTION: {}},
		"terrain_map": {},
		"environment_zones": [],
		"global_environment": {},
		"facilities_by_id": {},
		"minefields_by_id": {},
		"support_effects_by_id": {},
		"skill_effects_by_id": {},
		"visible_by_faction": {PLAYER_FACTION: {}, ENEMY_FACTION: {}},
		"contact_types_by_faction": {PLAYER_FACTION: {}, ENEMY_FACTION: {}},
		"contacts_by_faction": {PLAYER_FACTION: {}, ENEMY_FACTION: {}},
		"ai_groups_by_faction": {PLAYER_FACTION: {}, ENEMY_FACTION: {}},
		"result": {},
		"level_objective": level_objective_service.snapshot(),
		"reinforcement_waves": [],
	}
	_configure_scene_combat(level)
	_build_fleet("fleet.player", PLAYER_FACTION, level.get("player_fleet", []))
	_build_fleet("fleet.enemy", ENEMY_FACTION, level.get("enemy_fleet", []))
	_initialize_reinforcements(level)
	if level_objective_service.is_tutorial():
		var initial_control_state := level_objective_service.initial_player_control_state()
		for unit_id in state["fleets_by_id"]["fleet.player"]["unit_ids"]:
			_apply_tutorial_control_state(state["units_by_id"][unit_id], initial_control_state)
		for unit_id in state["fleets_by_id"]["fleet.enemy"]["unit_ids"]:
			var staging_unit: Dictionary = state["units_by_id"][unit_id]
			var staging_position := level_objective_service.staging_position_for(staging_unit)
			if staging_position.is_equal_approx(Vector2.INF): continue
			staging_unit["movement_state"] = _new_movement_state("AutoNavigate", staging_position, [])
			_mark_navigation_dirty(staging_unit)
	_rebuild_ai_groups(ENEMY_FACTION)
	state["phase"] = "Running"
	recorder.reset(state["battle_id"], seed_value)
	recorder.register_units(state["units_by_id"])
	_emit("BattleStarted", {"level_definition_id": level_id, "fleets": state["fleets_by_id"].keys()})
	for unit_id in _sorted_unit_ids():
		var unit: Dictionary = state["units_by_id"][unit_id]
		_emit("UnitSpawned", {"unit_id": unit_id, "faction_id": unit["faction_id"], "position": unit["position"], "is_flagship": unit["is_flagship"]})
	return {"ok": true, "battle_id": state["battle_id"]}


func queue_command(command: Dictionary) -> Dictionary:
	var rejection := _validate_command_structure(command)
	if not rejection.is_empty():
		return rejection
	command_queue.append(command.duplicate(true))
	return {"accepted": true}


func pause() -> Dictionary:
	if state.get("phase", "") != "Running":
		return _rejection("", "BATTLE_NOT_RUNNING")
	state["phase"] = "Paused"
	return {"accepted": true}


func resume() -> Dictionary:
	if state.get("phase", "") != "Paused":
		return _rejection("", "BATTLE_NOT_PAUSED")
	state["phase"] = "Running"
	return {"accepted": true}


func advance_tick(delta: float = 0.1) -> Array:
	_event_buffer = []
	if state.get("phase", "") != "Running":
		return _event_buffer
	if delta <= 0.0:
		return _event_buffer
	var tick_started_usec := Time.get_ticks_usec() if _performance_profile_enabled else 0
	_performance_tick_counts = {}
	terrain_query.reset_collision_field_diagnostics()
	state["tick_index"] += 1
	state["elapsed_time"] += delta
	_update_reinforcements()
	_ai_observations_by_faction.clear()
	_expire_ai_damage_reservations()
	_expire_ai_effect_reservations()
	if int(state["tick_index"]) % 5 == 0:
		_ai_battlefield_context_cache.clear()
		_ai_local_power_cache.clear()
	for environment_event in terrain_context_service.advance(delta):
		_emit(str(environment_event.get("event_type", "EnvironmentZoneChanged")), environment_event)
	state["environment_zones"] = terrain_context_service.snapshot()
	state["global_environment"] = terrain_context_service.global_snapshot()
	_update_support_effects(delta)
	_process_commands()
	_update_navigation_requests()
	_update_cooldowns_and_statuses(delta)
	_update_submarine_resources(delta)
	var stage_started_usec := Time.get_ticks_usec() if _performance_profile_enabled else 0
	_update_navigation_plans()
	if _performance_profile_enabled: _profile_stage("navigation_usec", Time.get_ticks_usec() - stage_started_usec)
	stage_started_usec = Time.get_ticks_usec() if _performance_profile_enabled else 0
	_update_movement(delta)
	if _performance_profile_enabled: _profile_stage("movement_usec", Time.get_ticks_usec() - stage_started_usec)
	_resolve_unit_overlap()
	_update_projectiles(delta)
	_update_projectile_observation()
	_update_mine_observation()
	_update_detection(delta)
	_update_ai_engagement_memory(delta)
	stage_started_usec = Time.get_ticks_usec() if _performance_profile_enabled else 0
	_update_ai_intents()
	if _performance_profile_enabled: _profile_stage("ai_decision_usec", Time.get_ticks_usec() - stage_started_usec)
	_update_auto_skills()
	_update_weapons()
	_update_facility_weapons()
	_resolve_delayed_attacks()
	for facility_event in facility_service.advance(delta, float(state["elapsed_time"]), state["units_by_id"]):
		_handle_facility_event(facility_event)
	state["facilities_by_id"] = facility_service.snapshot()
	for minefield_event in minefield_service.sync_controllers(state["facilities_by_id"]):
		_emit(str(minefield_event.get("event_type", "MineFieldStateChanged")), minefield_event)
	state["minefields_by_id"] = minefield_service.snapshot()
	_clear_invalid_targets()
	_update_level_objective()
	_check_victory()
	_check_timeout()
	_assert_invariants()
	recorder.consume(_event_buffer, float(state["elapsed_time"]))
	if _performance_profile_enabled:
		_performance_profile["tick_total_usec"].append(Time.get_ticks_usec() - tick_started_usec)
		for key in ["normal_plans_per_tick", "emergency_scans_per_tick", "emergency_plans_per_tick", "strategic_corridors_per_tick", "trajectory_candidates_per_tick", "trajectory_failures_per_tick", "trajectory_segments_simulated_per_tick", "trajectory_candidates_rejected_by_terrain_per_tick"]:
			_performance_profile[key].append(int(_performance_tick_counts.get(key, 0)))
		var field_profile := terrain_query.collision_field_diagnostics()
		_performance_profile["collision_field_usec"].append(int(field_profile.get("collision_field_usec", 0)))
		for field_key in ["collision_field_queries", "collision_field_cells_visited", "collision_field_definitely_clear", "collision_field_exact_fallbacks", "collision_field_unavailable_fallbacks"]:
			_performance_profile["%s_per_tick" % field_key].append(int(field_profile.get(field_key, 0)))
	return _event_buffer.duplicate(true)


func drain_events() -> Array:
	var events := _event_buffer.duplicate(true)
	_event_buffer.clear()
	return events


func snapshot(viewer_faction: String = PLAYER_FACTION, omniscient: bool = false) -> Dictionary:
	var units := {}
	for unit_id in _sorted_unit_ids():
		var unit: Dictionary = state["units_by_id"][unit_id]
		var visible: bool = omniscient or unit["faction_id"] == viewer_faction or state["visible_by_faction"].get(viewer_faction, {}).has(unit_id)
		if not visible:
			continue
		units[unit_id] = {
			"entity_id": unit_id,
			"definition_id": unit["definition_id"],
			"display_name": unit["display_name"],
			"faction_id": unit["faction_id"],
			"operation_slot": unit.get("operation_slot", 0),
			"ship_class": unit.get("stats", {}).get("ship_class", ""),
			"asset_root": unit.get("stats", {}).get("asset_root", ""),
			"collision_radius": unit.get("stats", {}).get("collision_radius", 20.0),
			"collision_half_extents": _unit_collision_half_extents(unit),
			"position": unit["position"],
			"heading": unit["heading"],
			"current_hp": unit["current_hp"],
			"max_hp": unit["max_hp"],
			"life_state": unit["life_state"],
			"is_flagship": unit["is_flagship"],
			"depth_state": unit.get("depth_state", "Surface"),
			"oxygen_state": unit.get("oxygen_state", {}).duplicate(true),
			"skill_cooldown": unit["skill_state"].get("cooldown_remaining", 0.0),
			"skill_cooldown_max": unit["skill_state"].get("cooldown_max", 0.0),
			"movement_state": unit.get("movement_state", {}).duplicate(true),
			"movement_assist_enabled": bool(unit.get("movement_assist_enabled", false)),
			"secondary_auto_fire_enabled": bool(unit.get("secondary_auto_fire_enabled", true)),
			"primary_auto_fire_enabled": bool(unit.get("primary_auto_fire_enabled", false)),
			"skill_auto_cast_enabled": false if unit["faction_id"] == PLAYER_FACTION else bool(unit.get("skill_auto_cast_enabled", true)),
			"player_route_waypoints": unit.get("player_route_waypoints", []).duplicate(true),
			"ai_mode_id": str(unit.get("ai_state", {}).get("mode_id", "")),
			"ai_tactic_id": str(unit.get("ai_state", {}).get("tactic_id", "")),
			"ai_interrupt": "TorpedoEvasion" if str(unit.get("navigation_state", {}).get("state", "NormalNavigation")) == "EmergencyEvasion" else "",
			"radar_stealth_state": str(unit.get("radar_stealth_state", "Exposed")),
			"contact_types": state.get("contact_types_by_faction", {}).get(viewer_faction, {}).get(unit_id, []).duplicate(),
			"primary_contact_type": _primary_contact_type(state.get("contact_types_by_faction", {}).get(viewer_faction, {}).get(unit_id, [])),
		}
	var contacts := {}
	var visible_minefields := {}
	var visible_facilities: Dictionary = state.get("facilities_by_id", {}).duplicate(true) if omniscient else _ai_observation_for(viewer_faction).known_facilities.duplicate(true)
	var unit_terrain_contexts := {}
	for contact_id in state["contacts_by_faction"].get(viewer_faction, {}):
		var contact: Dictionary = state["contacts_by_faction"][viewer_faction][contact_id]
		if not bool(contact.get("visible", false)) or str(contact.get("primary_contact_type", "")) == "Radar":
			contacts[contact_id] = contact.duplicate(true)
	for unit_id in units:
		var terrain_context := terrain_context_service.context_at(units[unit_id]["position"])
		var facility_sources: Array = facility_service.sources_at(units[unit_id]["position"])
		terrain_context["facility_sources"] = facility_sources
		terrain_context["effect_sources"].append_array(facility_sources)
		terrain_context["position"] = units[unit_id]["position"]
		unit_terrain_contexts[unit_id] = terrain_context
	for minefield_id in state.get("minefields_by_id", {}):
		var minefield: Dictionary = state["minefields_by_id"][minefield_id]
		if omniscient or viewer_faction == str(minefield.get("owner_faction_id", "")) or viewer_faction in minefield.get("known_by_faction", []):
			visible_minefields[minefield_id] = minefield.duplicate(true)
	return {
		"battle_id": state.get("battle_id", ""),
		"phase": state.get("phase", ""),
		"elapsed_time": state.get("elapsed_time", 0.0),
		"tick_index": state.get("tick_index", 0),
		"map": state.get("map", {}).duplicate(true),
		"units": units,
		"contacts": contacts,
		"projectiles": _visible_projectiles(viewer_faction, omniscient),
		"terrain_map": state.get("terrain_map", {}).duplicate(true),
		"environment_zones": state.get("environment_zones", []).duplicate(true),
		"global_environment": state.get("global_environment", {}).duplicate(true),
		"facilities": visible_facilities,
		"minefields": visible_minefields,
		"support_effects": _visible_support_effects(viewer_faction, omniscient),
		"skill_effects": _visible_skill_effects(viewer_faction, omniscient),
		"terrain_contexts": unit_terrain_contexts,
		"result": state.get("result", {}).duplicate(true),
		"level_objective": state.get("level_objective", {}).duplicate(true),
	}


func get_statistics() -> Dictionary:
	return recorder.summary.duplicate(true)


func configure_full_ai_factions(faction_ids: Array) -> void:
	_full_ai_factions.clear()
	for faction_id in faction_ids:
		_full_ai_factions[str(faction_id)] = true
	for unit_id in state.get("units_by_id", {}):
		var unit: Dictionary = state["units_by_id"][unit_id]
		if not _uses_full_ai(unit): continue
		unit["control_authority"] = "SimulationAI"
		unit["movement_assist_enabled"] = true
		unit["secondary_auto_fire_enabled"] = true
		unit["primary_auto_fire_enabled"] = true
		unit["primary_auto_fire_suspended"] = false
		unit["skill_auto_cast_enabled"] = true
		var tutorial_staging_position := level_objective_service.staging_position_for(unit)
		unit["movement_state"] = _new_movement_state("AutoNavigate", tutorial_staging_position if not tutorial_staging_position.is_equal_approx(Vector2.INF) else unit["position"], [])
		_mark_navigation_dirty(unit)
		unit["ai_state"]["mode_id"] = _default_ai_mode(unit.get("stats", {}))
		unit["ai_state"]["mode_entered_at"] = float(state.get("elapsed_time", 0.0))
	for faction_id in faction_ids:
		_rebuild_ai_groups(str(faction_id))


func configure_ai_profile(profile_id: String) -> Dictionary:
	var profile: Dictionary = registry.get_definition("ai_profiles", profile_id)
	if profile.is_empty(): return {"accepted": false, "reason_code": "AI_PROFILE_NOT_FOUND"}
	_ai_profile = profile.duplicate(true)
	return {"accepted": true, "profile_id": profile_id}


func configure_ai_mode_locks(mode_locks_by_definition: Dictionary) -> void:
	_ai_mode_locks_by_definition = mode_locks_by_definition.duplicate(true)
	for unit_id in state.get("units_by_id", {}):
		var unit: Dictionary = state["units_by_id"][unit_id]
		var locked_mode := str(_ai_mode_locks_by_definition.get(str(unit.get("definition_id", "")), ""))
		if locked_mode.is_empty(): continue
		unit["ai_state"]["mode_id"] = locked_mode
		unit["ai_state"]["mode_candidate_id"] = ""
		unit["ai_state"]["mode_candidate_confirmations"] = 0


func activate_facility_from_scenario(facility_id: String, event_id: String) -> Dictionary:
	var facility: Dictionary = facility_service.facilities_by_id.get(facility_id, {})
	var result := facility_service.activate_from_scenario(facility_id, str(facility.get("faction_id", "")), event_id)
	if not bool(result.get("accepted", false)): return result
	var state_change: Dictionary = result.get("state_change", {})
	if not state_change.is_empty(): _emit(str(state_change.get("event_type", "FacilityOperationStateChanged")), state_change)
	var activation_event: Dictionary = result.get("event", {})
	_emit(str(activation_event.get("event_type", "FacilityActivated")), activation_event)
	state["facilities_by_id"] = facility_service.snapshot()
	return result


func handover_facility_system_from_scenario(event_id: String, faction_id: String) -> Dictionary:
	var result := facility_service.apply_system_handover(event_id, faction_id)
	if not bool(result.get("accepted", false)): return result
	for event in result.get("events", []): _emit(str(event.get("event_type", "FacilityChanged")), event)
	state["facilities_by_id"] = facility_service.snapshot()
	return result


func get_unit_damage_statistics(unit_id: String) -> Dictionary:
	return recorder.unit_damage_statistics(unit_id)


func get_all_unit_damage_statistics() -> Dictionary:
	return recorder.all_unit_damage_statistics()


func get_non_ship_damage_statistics(source_id: String) -> Dictionary:
	return recorder.non_ship_damage_statistics(source_id)


func get_all_non_ship_damage_statistics() -> Dictionary:
	return recorder.all_non_ship_damage_statistics()


func get_unit_damage_for_category(unit_id: String, category: String, include_contribution: bool = false) -> float:
	return recorder.unit_damage_for_category(unit_id, category, include_contribution)


func get_player_slots() -> Array:
	var slots: Array = []
	for unit_id in state.get("fleets_by_id", {}).get("fleet.player", {}).get("unit_ids", []):
		var unit: Dictionary = state["units_by_id"].get(unit_id, {})
		if unit.is_empty(): continue
		var stats: Dictionary = unit.get("stats", {})
		slots.append({
			"slot": int(unit.get("operation_slot", 0)),
			"unit_id": unit_id,
			"definition_id": unit.get("definition_id", ""),
			"display_name": unit.get("display_name", unit_id),
			"life_state": unit.get("life_state", ""),
			"current_hp": unit.get("current_hp", 0.0),
			"max_hp": unit.get("max_hp", 1.0),
			"is_flagship": unit.get("is_flagship", false),
			"ship_class": stats.get("ship_class", ""),
			"asset_root": stats.get("asset_root", ""),
		})
	slots.sort_custom(func(a, b): return int(a["slot"]) < int(b["slot"]))
	return slots


func get_operation_status(unit_id: String) -> Dictionary:
	var unit: Dictionary = state.get("units_by_id", {}).get(unit_id, {})
	if unit.is_empty():
		return {"available": false, "reason_code": "UNIT_NOT_FOUND"}
	var ship: Dictionary = unit.get("stats", {})
	var primary_group_id := str(ship.get("primary_weapon_group_id", ""))
	var selected_ammo := _selected_ammo_for_group(unit, primary_group_id)
	var primary_states := _weapon_states_for_group(unit, primary_group_id, true)
	var primary_ready := false
	var primary_reload := INF
	var primary_reload_max := 0.0
	var primary_range := 0.0
	var primary_name := "None"
	var primary_mount_type := ""
	var primary_mounts_ready := 0
	var primary_enabled := false
	var group_launch_remaining := float(unit.get("weapon_group_launch_remaining", {}).get(primary_group_id, 0.0))
	for weapon_state in primary_states:
		var weapon: Dictionary = registry.get_definition("weapons", str(weapon_state["definition_id"]))
		if primary_name == "None": primary_name = str(weapon.get("display_name", weapon["id"]))
		if primary_mount_type.is_empty(): primary_mount_type = str(weapon.get("mount_type", ""))
		if not bool(weapon_state.get("enabled", true)): continue
		primary_enabled = true
		primary_reload = minf(primary_reload, float(weapon_state.get("reload_remaining", 0.0)))
		primary_reload_max = maxf(primary_reload_max, float(weapon.get("reload_time", 0.0)))
		primary_range = maxf(primary_range, _effective_weapon_range(unit, weapon))
		if float(weapon_state.get("reload_remaining", 0.0)) <= 0.0:
			primary_mounts_ready += 1
			if group_launch_remaining <= 0.0: primary_ready = true
	if primary_states.is_empty() or not primary_enabled:
		primary_reload = 0.0
	else:
		primary_reload = maxf(primary_reload, group_launch_remaining)
	var ammo_group_id := str(ship.get("ammo_selection_group_id", ""))
	var ammo_options := _ammo_options_for_ship(ship, ammo_group_id)
	var skill_cooldown := float(unit["skill_state"].get("cooldown_remaining", 0.0))
	return {
		"available": true,
		"slot": int(unit.get("operation_slot", 0)),
		"life_state": unit.get("life_state", ""),
		"display_name": unit.get("display_name", unit_id),
		"primary_group_id": primary_group_id,
		"primary_control_type": ship.get("primary_weapon_control_type", ""),
		"primary_name": primary_name,
		"primary_mount_type": primary_mount_type,
		"primary_mounts_ready": primary_mounts_ready,
		"primary_mounts_total": primary_states.size(),
		"primary_reload_remaining": primary_reload,
		"primary_reload_max": primary_reload_max,
		"primary_mount_launch_remaining": group_launch_remaining,
		"primary_range": primary_range,
		"primary_ready": primary_ready and unit.get("life_state", "") == "Alive" and state.get("phase", "") == "Running",
		"primary_reason": _primary_unavailable_reason(unit, primary_states),
		"ammo_group_id": ammo_group_id,
		"ammo_options": ammo_options,
		"selected_ammo": selected_ammo,
		"q_enabled": ammo_options.size() > 1,
		"skill_id": unit["skill_state"].get("definition_id", ""),
		"skill_cooldown": skill_cooldown,
		"skill_ready": skill_cooldown <= 0.0 and unit.get("life_state", "") == "Alive" and state.get("phase", "") == "Running",
		"movement_assist_enabled": bool(unit.get("movement_assist_enabled", false)),
		"secondary_auto_fire_enabled": bool(unit.get("secondary_auto_fire_enabled", true)),
		"primary_auto_fire_enabled": bool(unit.get("primary_auto_fire_enabled", false)),
		"skill_auto_cast_enabled": false,
		"player_route_waypoints": unit.get("player_route_waypoints", []).duplicate(true),
		"player_route_remaining": _remaining_player_route(unit),
		"movement_mode": str(unit.get("movement_state", {}).get("mode", "HoldPosition")),
	}


func get_primary_aim_status(unit_id: String, target_position: Vector2) -> Dictionary:
	var unit: Dictionary = state.get("units_by_id", {}).get(unit_id, {})
	if unit.is_empty():
		return {"legal": false, "reason_code": "UNIT_NOT_FOUND"}
	var primary_group_id := str(unit.get("stats", {}).get("primary_weapon_group_id", ""))
	var weapon_states := _weapon_states_for_group(unit, primary_group_id, true)
	var validation := _validate_primary_fire(unit, weapon_states, target_position)
	var operation_status := get_operation_status(unit_id)
	validation["control_type"] = operation_status.get("primary_control_type", "")
	validation["range"] = operation_status.get("primary_range", 0.0)
	var aim_weapons := _primary_aim_weapons(weapon_states)
	validation["weapon_type"] = _common_weapon_type(aim_weapons)
	validation["fire_arcs"] = _aim_fire_arcs(aim_weapons)
	validation["full_salvo_fire_arcs"] = _aim_full_salvo_fire_arcs(aim_weapons)
	validation["impact_radius"] = _aim_impact_radius(aim_weapons)
	var direction_weapon := _direction_weapon_for_aim(unit, aim_weapons, target_position)
	validation["minimum_range"] = float(direction_weapon.get("minimum_range", 0.0))
	validation["selected_range"] = _effective_weapon_range(unit, direction_weapon) if not direction_weapon.is_empty() else float(validation["range"])
	var spread_degrees := float(direction_weapon.get("spread", 0.0))
	if direction_weapon.get("mount_type", "") == "Gun":
		spread_degrees = ModifierService.calculate(spread_degrees, unit.get("status_effects", []), "WeaponSpread", "Gun")
	validation["spread_degrees"] = spread_degrees
	return validation


func get_facility_action_status(unit_id: String, facility_id: String) -> Dictionary:
	var unit: Dictionary = state.get("units_by_id", {}).get(unit_id, {})
	var facility: Dictionary = _ai_observation_for(PLAYER_FACTION).known_facilities.get(facility_id, {})
	if unit.is_empty() or facility.is_empty(): return {"available": false, "reason_code": "FACILITY_NOT_KNOWN"}
	var definition := facility_service.definition_for(facility_id)
	var modes: Array = definition.get("operation_modes", [])
	var control: Dictionary = facility.get("control_state", {})
	var service: Dictionary = facility.get("service_state", {})
	var control_duration := maxf(0.001, float(control.get("duration", definition.get("area_control", {}).get("duration", 1.0))))
	var service_duration := maxf(0.001, float(service.get("duration", definition.get("berthing_service", {}).get("duration", 1.0))))
	var inside: bool = Geometry2D.is_point_in_polygon(unit.get("position", Vector2.ZERO), _polygon(facility.get("interaction_water_polygon", [])))
	var berth: Dictionary = definition.get("berthing_service", {})
	var disposition: Dictionary = definition.get("combat_disposition", {})
	var suppression_threshold := maxf(0.001, float(definition.get("suppression_damage_threshold", 1.0)))
	var remote: Dictionary = definition.get("remote_command", {})
	var mine_status := facility_service.mine_deployment_status(facility_id, float(state.get("elapsed_time", 0.0)))
	var heading_ok: bool = absf(wrapf(float(unit.get("heading", 0.0)) - deg_to_rad(float(facility.get("heading", 0.0))), -PI, PI)) <= deg_to_rad(float(berth.get("heading_tolerance_degrees", 180.0)))
	var speed_ok: bool = absf(float(unit.get("current_speed", 0.0))) <= float(berth.get("max_entry_speed", 0.0))
	return {
		"available": true, "facility_id": facility_id, "display_name": facility.get("display_name", facility_id),
		"faction_id": facility.get("faction_id", "neutral"), "life_state": facility.get("life_state", "Alive"), "operation_state": facility.get("operation_state", "Dormant"),
		"interaction_state": facility.get("interaction_state", "Idle"), "last_interruption_reason": facility.get("last_interruption_reason", ""),
		"operation_modes": modes.duplicate(), "service_type": berth.get("service_type", ""),
		"control_progress_ratio": clampf(float(control.get("progress", 0.0)) / control_duration, 0.0, 1.0),
		"service_progress_ratio": clampf(float(service.get("progress", 0.0)) / service_duration, 0.0, 1.0),
		"control_executor_unit_id": control.get("executor_unit_id", ""), "berth_unit_id": service.get("unit_id", ""),
		"dependencies_active": facility.get("dependencies_active", true),
		"suppression_remaining": facility.get("suppression_remaining", 0.0),
		"suppression_progress_ratio": clampf(float(facility.get("suppression_damage_accumulated", 0.0)) / suppression_threshold, 0.0, 1.0),
		"destroyable": disposition.get("destroyable", true), "damage_floor_ratio": disposition.get("damage_floor_ratio", 0.0),
		"inside_interaction_water": inside, "berth_speed_ok": speed_ok, "berth_heading_ok": heading_ok,
		"control_ready": "AreaControl" in modes and bool(definition.get("area_control", {}).get("capturable", false)) and facility.get("life_state", "") == "Alive" and facility.get("operation_state", "") != "Suppressed" and control.is_empty(),
		"service_ready": "BerthingService" in modes and facility_service.is_operational(facility_id) and facility.get("faction_id", "") == unit.get("faction_id", "") and inside and speed_ok and heading_ok and service.is_empty(),
		"support_ready": "RemoteCommand" in modes and str(definition.get("remote_command", {}).get("command_type", "")) == "SupportMission" and facility_service.is_operational(facility_id) and facility.get("faction_id", "") == unit.get("faction_id", ""),
		"mine_ready": "RemoteCommand" in modes and str(remote.get("command_type", "")) == "MineDeployment" and facility_service.is_operational(facility_id) and facility.get("faction_id", "") == unit.get("faction_id", "") and mine_status.is_empty() and float(facility.get("cooldown_remaining", 0.0)) <= 0.0 and int(facility.get("remote_charges_remaining", 0)) > 0,
		"mine_control_radius": float(remote.get("control_radius", 0.0)), "mine_area_side_length": float(remote.get("area_side_length", 0.0)),
		"mine_duration": float(remote.get("duration", 0.0)), "mine_progress_ratio": float(mine_status.get("progress_ratio", 0.0)),
		"mine_charges_remaining": int(facility.get("remote_charges_remaining", 0)), "mine_cooldown_remaining": float(facility.get("cooldown_remaining", 0.0)),
		"last_mine_deployment_result": facility.get("last_mine_deployment_result", {}).duplicate(true),
		"can_cancel": str(control.get("executor_unit_id", "")) == unit_id or str(service.get("unit_id", "")) == unit_id,
	}


func get_mine_deployment_preview(unit_id: String, facility_id: String, target_position: Vector2) -> Dictionary:
	var unit: Dictionary = state.get("units_by_id", {}).get(unit_id, {})
	if unit.is_empty(): return {"accepted":false, "reason_code":"UNIT_UNAVAILABLE"}
	return facility_service.validate_mine_deployment(facility_id, unit, target_position, state.get("units_by_id", {}))


func _configure_scene_combat(level: Dictionary) -> void:
	terrain_query = TerrainQueryService.new()
	terrain_context_service = TerrainContextService.new()
	facility_service = FacilityService.new()
	minefield_service = MinefieldService.new()
	route_planner = RoutePlanner.new()
	navigation_definition = {}
	var map: Dictionary = level.get("map", {})
	var terrain_id := str(map.get("terrain_definition_id", ""))
	var terrain_definition: Dictionary = registry.get_definition("terrain", terrain_id) if not terrain_id.is_empty() else {}
	if not terrain_definition.is_empty():
		var collision_field = null
		var collision_field_id := str(terrain_definition.get("collision_field_id", ""))
		var collision_field_definition: Dictionary = registry.get_definition("collision_fields", collision_field_id) if not collision_field_id.is_empty() else {}
		var collision_field_result := terrain_collision_field_loader.load_field(collision_field_definition, terrain_definition)
		if bool(collision_field_result.get("ok", false)):
			collision_field = collision_field_result.get("field")
		else:
			_emit("TerrainCollisionFieldUnavailable", {"terrain_definition_id":terrain_id, "collision_field_id":collision_field_id, "reason_code":collision_field_result.get("reason_code", "COLLISION_FIELD_UNAVAILABLE")})
		terrain_query.configure(terrain_definition, collision_field)
		state["terrain_map"] = terrain_definition.duplicate(true)
	var navigation_id := str(map.get("navigation_definition_id", terrain_definition.get("navigation_definition_id", "")))
	if not navigation_id.is_empty():
		navigation_definition = registry.get_definition("navigation", navigation_id)
		route_planner.configure(navigation_definition)
	var environment_id := str(map.get("environment_zone_set_id", terrain_definition.get("environment_zone_set_id", "")))
	var environment_set: Dictionary = registry.get_definition("environment_zones", environment_id) if not environment_id.is_empty() else {}
	terrain_context_service.configure(terrain_query, environment_set, registry.all("environment_zones"), str(map.get("ocean_palette", "day_clear")))
	state["environment_zones"] = terrain_context_service.snapshot()
	state["global_environment"] = terrain_context_service.global_snapshot()
	var facility_layout_id := str(map.get("facility_layout_id", terrain_definition.get("facility_layout_id", "")))
	var facility_layout: Dictionary = registry.get_definition("facilities", facility_layout_id) if not facility_layout_id.is_empty() else {}
	facility_service.configure(facility_layout, terrain_definition.get("facility_anchors", []), _resolved_facility_definitions())
	state["facilities_by_id"] = facility_service.snapshot()
	minefield_service.configure(_resolved_facility_definitions(), terrain_id)
	state["minefields_by_id"] = minefield_service.snapshot()


func _resolved_facility_definitions() -> Array:
	var result: Array = []
	for raw_definition in registry.all("facilities"):
		var definition: Dictionary = raw_definition.duplicate(true)
		var durability_reference_id := str(definition.get("durability_reference_id", ""))
		if not durability_reference_id.is_empty():
			var ship: Dictionary = registry.get_definition("ships", durability_reference_id)
			for field in ["max_hp", "armor", "armor_thickness", "gunnery_power", "aviation_power"]:
				if ship.has(field): definition[field] = ship[field]
		var detection_reference: Dictionary = definition.get("detection_reference", {})
		if detection_reference.is_empty(): detection_reference = definition.get("remote_command", {}).get("detection_reference", {})
		if not detection_reference.is_empty():
			var reference_ship: Dictionary = registry.get_definition("ships", str(detection_reference.get("ship_id", "")))
			var half_extents: Array = reference_ship.get("collision_half_extents", [])
			if not half_extents.is_empty():
				var resolved_distance := float(half_extents[0]) * 2.0 * float(detection_reference.get("full_length_multiplier", 0.5))
				if definition.has("remote_command"): definition["remote_command"]["detection_distance"] = resolved_distance
				else: definition["detection_distance"] = resolved_distance
		result.append(definition)
	return result


func _validate_level_runtime(level: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var all_entity_ids := {}
	for fleet_name in ["player_fleet", "enemy_fleet"]:
		var flagship_count := 0
		for member in level.get(fleet_name, []):
			var entity_id := str(member.get("entity_id", ""))
			if all_entity_ids.has(entity_id): errors.append("DUPLICATE_ENTITY_ID")
			all_entity_ids[entity_id] = true
			if bool(member.get("is_flagship", false)): flagship_count += 1
		if flagship_count != 1: errors.append("INVALID_FLAGSHIP_COUNT")
	for wave in level.get("reinforcement_waves", []):
		for member in wave.get("members", []):
			var entity_id := str(member.get("entity_id", ""))
			if all_entity_ids.has(entity_id): errors.append("DUPLICATE_ENTITY_ID")
			all_entity_ids[entity_id] = true
	return errors


func _build_fleet(fleet_id: String, faction_id: String, members: Array) -> void:
	var fleet := {"fleet_id": fleet_id, "faction_id": faction_id, "unit_ids": [], "flagship_unit_id": "", "initial_max_hp_total": 0.0}
	for member_index in range(members.size()):
		var member: Dictionary = members[member_index]
		var ship: Dictionary = registry.get_definition("ships", str(member["ship_id"]))
		var unit := _build_unit(member, ship, fleet_id, faction_id, member_index + 1)
		state["units_by_id"][unit["entity_id"]] = unit
		fleet["unit_ids"].append(unit["entity_id"])
		fleet["initial_max_hp_total"] += unit["max_hp"]
		if unit["is_flagship"]: fleet["flagship_unit_id"] = unit["entity_id"]
	state["fleets_by_id"][fleet_id] = fleet


func _initialize_reinforcements(level: Dictionary) -> void:
	var waves: Array = []
	for wave_definition_value in level.get("reinforcement_waves", []):
		var wave_definition: Dictionary = wave_definition_value.duplicate(true)
		waves.append({"wave_id": str(wave_definition.get("wave_id", "")), "definition": wave_definition, "status": "Pending", "spawned_at_tick": -1})
	state["reinforcement_waves"] = waves


func _update_reinforcements() -> void:
	var waves: Array = state.get("reinforcement_waves", [])
	for wave in waves:
		if str(wave.get("status", "")) != "Pending": continue
		var definition: Dictionary = wave.get("definition", {})
		if float(state.get("elapsed_time", 0.0)) < float(definition.get("earliest_time", 0.0)): continue
		var faction_id := str(definition.get("faction_id", ""))
		var fleet_id := "fleet.%s" % faction_id
		var fleet: Dictionary = state.get("fleets_by_id", {}).get(fleet_id, {})
		var alive_count := 0
		for unit_id in fleet.get("unit_ids", []):
			if state["units_by_id"].get(str(unit_id), {}).get("life_state", "") == "Alive": alive_count += 1
		if alive_count >= int(definition.get("concurrent_unit_cap", 3)): continue
		for member_value in definition.get("members", []):
			var member: Dictionary = member_value
			var ship: Dictionary = registry.get_definition("ships", str(member.get("ship_id", "")))
			var unit := _build_unit(member, ship, fleet_id, faction_id, fleet["unit_ids"].size() + 1)
			state["units_by_id"][unit["entity_id"]] = unit
			fleet["unit_ids"].append(unit["entity_id"])
			_emit("UnitSpawned", {"unit_id": unit["entity_id"], "faction_id": faction_id, "position": unit["position"], "is_flagship": false, "reinforcement_wave_id": wave.get("wave_id", "")})
		wave["status"] = "Spawned"
		wave["spawned_at_tick"] = int(state.get("tick_index", 0))
		_emit("ReinforcementWaveSpawned", {"wave_id": wave.get("wave_id", ""), "faction_id": faction_id})
		_rebuild_ai_groups(faction_id)
		break


func _build_unit(member: Dictionary, ship: Dictionary, fleet_id: String, faction_id: String, operation_slot: int) -> Dictionary:
	var position_data: Array = member.get("position", [0.0, 0.0])
	var spawn_position := Vector2(float(position_data[0]), float(position_data[1]))
	var configured_group_states = member.get("weapon_group_states", {})
	var initial_group_states: Dictionary = configured_group_states if typeof(configured_group_states) == TYPE_DICTIONARY else {}
	var weapon_states: Array = []
	for weapon_id in ship.get("weapon_mounts", []):
		var weapon: Dictionary = registry.get_definition("weapons", str(weapon_id))
		var weapon_group_id := str(weapon.get("weapon_group_id", ""))
		var availability_state := str(initial_group_states.get(weapon_group_id, "Enabled"))
		var mount_fire_arcs: Array = weapon.get("mount_fire_arcs", [])
		if weapon.get("mount_type", "") == "Torpedo" and weapon.get("control_mode", "") == "ManualPrimary" and not mount_fire_arcs.is_empty():
			for mount_index in range(mount_fire_arcs.size()):
				weapon_states.append({
					"instance_id": "%s.%s.%s" % [member["entity_id"], weapon_id, mount_fire_arcs[mount_index].get("mount_id", "mount_%s" % [mount_index + 1])],
					"definition_id": weapon_id,
					"mount_index": mount_index,
					"mount_id": str(mount_fire_arcs[mount_index].get("mount_id", "mount_%s" % [mount_index + 1])),
					"reload_remaining": 0.0,
					"weapon_group_id": weapon_group_id,
					"availability_state": availability_state,
					"enabled": availability_state == "Enabled",
				})
		else:
			weapon_states.append({"instance_id": "%s.%s" % [member["entity_id"], weapon_id], "definition_id": weapon_id, "mount_index": -1, "mount_id": "", "reload_remaining": 0.0, "weapon_group_id": weapon_group_id, "availability_state": availability_state, "enabled": availability_state == "Enabled"})
	var skill: Dictionary = registry.get_definition("skills", str(ship.get("skill_id", "")))
	var player_controlled := faction_id == PLAYER_FACTION
	var initial_movement_mode := "HoldPosition" if player_controlled else "AutoNavigate"
	# Spread the two fleets across opposite halves of the one-second planning
	# wheel. This gives 11v11 a 2-3 unit baseline per fixed Tick; immediate
	# invalidations may add replans instead of waiting for a later slot.
	var normal_plan_slot := posmod(operation_slot + (0 if player_controlled else int(NAVIGATION_NORMAL_INTERVAL_TICKS / 2)), NAVIGATION_NORMAL_INTERVAL_TICKS)
	return {
		"entity_id": str(member["entity_id"]),
		"definition_id": str(ship["id"]),
		"display_name": str(ship.get("display_name", ship["id"])),
		"fleet_id": fleet_id,
		"faction_id": faction_id,
		"operation_slot": operation_slot,
		"is_flagship": bool(member.get("is_flagship", false)),
		"life_state": "Alive",
		"current_hp": float(ship["max_hp"]) * clampf(float(member.get("initial_hp_ratio", 1.0)), 0.0, 1.0),
		"max_hp": float(ship["max_hp"]),
		"stats": ship.duplicate(true),
		"position": spawn_position,
		"heading": deg_to_rad(float(member.get("heading", 0.0))),
		"current_speed": 0.0,
		"movement_state": _new_movement_state(initial_movement_mode, spawn_position, []),
		"navigation_state": {
			"state": "NormalNavigation",
			"trajectory_plan": {},
			"current_control": {"thrust_ratio": 0.0, "turn_ratio": 0.0},
			"normal_plan_slot": normal_plan_slot,
			"next_normal_plan_tick": normal_plan_slot,
			"emergency_clear_ticks": 0,
			"tracked_threat_ids": [],
			"trajectory_dirty": true,
			"strategic_update_due": false,
			"intent_revision": 0,
			"pending_route_requests": 0,
			"route_waiting": false,
			"strategic_intent_target": spawn_position,
			"pending_intent_target": spawn_position,
			"failed_intent_target": spawn_position,
			"failed_intent_origin": spawn_position,
			"route_failure_count": 0,
			"route_retry_at": 0.0,
		},
		"targeting_state": {"mode": "Automatic", "focused_target_id": "", "current_target_id": ""},
		"weapon_states": weapon_states,
		"weapon_group_launch_remaining": {},
		"skill_state": {"definition_id": ship.get("skill_id", ""), "cooldown_remaining": float(member.get("initial_skill_cooldown", skill.get("cooldown", 0.0))), "cooldown_max": float(skill.get("cooldown", 0.0))},
		"ammo_state": _build_ammo_state(ship, str(member.get("initial_ammo_type", ""))),
		"status_effects": [],
		"depth_state": "Submerged" if ship.get("ship_class", "") == "Submarine" else "Surface",
		"radar_stealth_state": "Stealthed" if bool(ship.get("radar_stealth", false)) else "Exposed",
		"oxygen_state": {"current": float(ship.get("max_oxygen", 0.0)), "maximum": float(ship.get("max_oxygen", 0.0))},
		"firing_reveal_remaining": 0.0,
		"control_authority": "Player" if player_controlled else "EnemyAI",
		"movement_assist_enabled": false if player_controlled else true,
		"secondary_auto_fire_enabled": true,
		"primary_auto_fire_enabled": false if player_controlled else true,
		"primary_auto_fire_suspended": false,
		"skill_auto_cast_enabled": false if player_controlled else true,
		"player_route_waypoints": [],
		"player_facility_target_id": "",
		"ai_state": {
			"mode_id": _default_ai_mode(ship) if not player_controlled else "",
			"mode_entered_at": 0.0,
			"tactic_id": "Defend",
			"tactic_entered_at": 0.0,
			"tactic_candidate_id": "",
			"tactic_candidate_confirmations": 0,
			"decision_cooldown": float(absi(str(member["entity_id"]).hash()) % maxi(1, int(round(AI_DECISION_INTERVAL / 0.1)))) * 0.1,
			"fire_decision_cooldown": 0.0,
			"skill_decision_cooldown": 0.0,
			"last_primary_command_tick": -1,
			"last_skill_command_tick": -1,
			"mode_candidate_id": "",
			"mode_candidate_confirmations": 0,
			"target_acquired_at": 0.0,
			"target_candidate_id": "",
			"target_candidate_confirmations": 0,
			"target_switch_ready_at": 0.0,
			"level_task": "",
			"task_target_ref": {},
			"task_score": 0.0,
			"task_started_at": 0.0,
			"task_failures": 0,
			"facility_failure_counts": {},
			"task_blocked_facility_id": "",
			"task_blocked_until": 0.0,
			"group_id": "",
			"group_role": "",
			"formation_id": "",
			"formation_slot_index": -1,
			"last_progress_position": spawn_position,
			"last_progress_heading": deg_to_rad(float(member.get("heading", 0.0))),
			"last_progress_at": 0.0,
			"path_stuck": false,
			"path_recovery_count": 0,
			"objective_role": "",
			"last_route_command_at": -1000.0,
			"passive_sample_position": spawn_position,
			"passive_sample_elapsed": 0.0,
			"continuous_evasion_seconds": 0.0,
			"no_effective_movement_seconds": 0.0,
			"no_engagement_seconds": 0.0,
			"no_effective_attack_seconds": 0.0,
			"last_effective_attack_at": 0.0,
			"engagement_pressure": 0.0,
			"engagement_pressure_started_at": -1.0,
			"engagement_pressure_triggered": false,
			"passive_report_accumulator": 0.0,
			"long_idle_reported": false,
		},
	}


func _new_movement_state(mode: String, target_position: Vector2, corridor_points: Array) -> Dictionary:
	return {
		"mode": mode,
		"target_position": target_position,
		"corridor_points": corridor_points.duplicate(),
		"corridor_index": 0,
		"corridor_gates": corridor_points.map(func(point): return {"center":point, "radius":0.0}),
		# Compatibility-only authored inputs. Runtime motion never follows this list directly.
		"waypoints": [],
		"waypoint_index": 0,
	}


func _build_ammo_state(ship: Dictionary, initial_ammo_override: String = "") -> Dictionary:
	var ammo_group_id := str(ship.get("ammo_selection_group_id", ""))
	if ammo_group_id.is_empty():
		return {}
	var ammo_options := _ammo_options_for_ship(ship, ammo_group_id)
	var selected_ammo := initial_ammo_override if not initial_ammo_override.is_empty() else str(ship.get("initial_ammo_type", ""))
	if selected_ammo.is_empty() or not selected_ammo in ammo_options:
		selected_ammo = ammo_options[0] if not ammo_options.is_empty() else ""
	return {ammo_group_id: selected_ammo}


func _process_commands() -> void:
	command_queue.sort_custom(func(a, b):
		var tick_a := int(a.get("issued_at_tick", 0))
		var tick_b := int(b.get("issued_at_tick", 0))
		if tick_a != tick_b: return tick_a < tick_b
		var priority_a := 0 if str(a.get("command_type", "")) == "SetUnitControlState" else 1
		var priority_b := 0 if str(b.get("command_type", "")) == "SetUnitControlState" else 1
		return priority_a < priority_b if priority_a != priority_b else str(a.get("command_id", "")) < str(b.get("command_id", "")))
	var pending := command_queue
	command_queue = []
	for command in pending:
		var result := _apply_command(command)
		if not result.get("accepted", false):
			_emit("CommandRejected", {"command_id": command.get("command_id", ""), "command_type": command.get("command_type", ""), "reason_code": result.get("reason_code", "UNKNOWN"), "issuer_type": command.get("issuer_type", ""), "unit_id": command.get("unit_id", "")})


func _apply_command(command: Dictionary) -> Dictionary:
	if state["phase"] != "Running": return _rejection(command.get("command_id", ""), "BATTLE_NOT_RUNNING")
	if command.get("command_type", "") == "RecordTutorialAction":
		return _record_tutorial_action(str(command.get("action_id", "")), str(command.get("unit_id", "")))
	if str(command.get("issuer_id", PLAYER_FACTION)) == PLAYER_FACTION and str(command.get("issuer_type", "Player")) in ["Player", "SimulationPolicy"] and str(command.get("command_type", "")) in level_objective_service.locked_player_commands():
		return _rejection(command.get("command_id", ""), "TUTORIAL_ACTION_LOCKED")
	if command.get("command_type", "") == "SetUnitControlState":
		return _set_unit_control_state(command)
	var unit_id := str(command.get("unit_id", ""))
	var unit: Dictionary = state["units_by_id"].get(unit_id, {})
	if unit.is_empty(): return _rejection(command.get("command_id", ""), "UNIT_NOT_FOUND")
	if unit["life_state"] != "Alive": return _rejection(command.get("command_id", ""), "UNIT_SUNK")
	var issuer_faction := str(command.get("issuer_id", PLAYER_FACTION))
	if unit["faction_id"] != issuer_faction: return _rejection(command.get("command_id", ""), "UNIT_NOT_CONTROLLABLE")
	match command.get("command_type", ""):
		"MoveUnits":
			var issuer_type := str(command.get("issuer_type", "Player"))
			var requested_mode := str(command.get("movement_mode", "AssistNavigate" if issuer_type == "PlayerAssistAI" else "AutoNavigate"))
			if issuer_type in ["AI", "PlayerAssistAI"] and requested_mode != "ImmediateAvoidance" and str(unit.get("movement_state", {}).get("mode", "")) in ["PlayerMoveOrder", "PlayerWaypointRoute"]:
				return _rejection(command.get("command_id", ""), "PLAYER_NAVIGATION_ACTIVE")
			if str(command.get("issuer_type", "")) == "PlayerAssistAI" and str(unit.get("faction_id", "")) == PLAYER_FACTION and str(command.get("movement_mode", "AssistNavigate")) != "ImmediateAvoidance" and not bool(unit.get("movement_assist_enabled", false)):
				return _rejection(command.get("command_id", ""), "MOVEMENT_ASSIST_DISABLED")
			var target_position = command.get("target_position")
			if typeof(target_position) != TYPE_VECTOR2: return _rejection(command.get("command_id", ""), "INVALID_TARGET_TYPE")
			if not _inside_map(target_position): return _rejection(command.get("command_id", ""), "TARGET_POSITION_ON_LAND")
			_undock_for_move_order(unit)
			# SimulationPolicy represents the authored player's actions in headless
			# tutorial experiments, so its move orders must have the same navigation
			# authority as interactive player orders. Otherwise the assist AI can
			# overwrite the route being validated.
			var player_order: bool = str(command.get("issuer_type", "Player")) in ["Player", "SimulationPolicy"] and str(unit["faction_id"]) == PLAYER_FACTION
			var movement_mode := "PlayerMoveOrder" if player_order else str(command.get("movement_mode", "AssistNavigate" if command.get("issuer_type", "") == "PlayerAssistAI" else "AutoNavigate"))
			if player_order:
				_begin_navigation_intent(unit)
				unit["player_route_waypoints"] = [target_position]
			var strategic_target_position: Vector2 = command.get("strategic_target_position", target_position)
			_submit_navigation_request(unit, unit["position"], target_position, "Replace", movement_mode, str(command.get("command_id", "")), 0 if player_order else 10, strategic_target_position)
			_emit("MoveOrderQueued", {"unit_id": unit_id, "target_position": target_position})
			return {"accepted": true}
		"AppendMoveWaypoint":
			if unit["faction_id"] != PLAYER_FACTION: return _rejection(command.get("command_id", ""), "UNIT_NOT_CONTROLLABLE")
			var append_position = command.get("target_position")
			if typeof(append_position) != TYPE_VECTOR2: return _rejection(command.get("command_id", ""), "INVALID_TARGET_TYPE")
			return _append_player_waypoint(unit, append_position, command.get("command_id", ""))
		"ClearMoveRoute":
			if unit["faction_id"] != PLAYER_FACTION: return _rejection(command.get("command_id", ""), "UNIT_NOT_CONTROLLABLE")
			_begin_navigation_intent(unit)
			unit["player_route_waypoints"] = []
			unit["movement_state"] = _new_movement_state("AssistNavigate" if bool(unit.get("movement_assist_enabled", false)) else "HoldPosition", unit["position"], [])
			_mark_navigation_dirty(unit)
			_emit("MoveRouteCleared", {"unit_id": unit_id})
			return {"accepted": true}
		"FocusTarget":
			var target_id := str(command.get("target_unit_id", ""))
			if not _is_visible_to(unit["faction_id"], target_id): return _rejection(command.get("command_id", ""), "TARGET_NOT_VISIBLE")
			var target: Dictionary = state["units_by_id"].get(target_id, {})
			if target.is_empty() or target["life_state"] != "Alive" or target["faction_id"] == unit["faction_id"]: return _rejection(command.get("command_id", ""), "INVALID_TARGET_TYPE")
			var old_target: String = str(unit["targeting_state"].get("focused_target_id", ""))
			unit["targeting_state"]["mode"] = "Focused"
			unit["targeting_state"]["focused_target_id"] = target_id
			_emit("FocusTargetChanged", {"unit_id": unit_id, "old_target_id": old_target, "new_target_id": target_id})
			return {"accepted": true}
		"ClearFocusTarget":
			unit["targeting_state"]["mode"] = "Automatic"
			unit["targeting_state"]["focused_target_id"] = ""
			return {"accepted": true}
		"CastSkill":
			var cast_result := _cast_skill(unit, command.get("target_ref", {}), command.get("command_id", ""))
			if bool(cast_result.get("accepted", false)) and _is_player_tutorial_command(command):
				_record_tutorial_action("CastSkill", unit_id, {"skill_id": str(unit.get("skill_state", {}).get("definition_id", ""))})
			return cast_result
		"SwitchAmmo":
			var switch_result := _switch_ammo(unit, command.get("command_id", ""))
			if bool(switch_result.get("accepted", false)) and _is_player_tutorial_command(command):
				_record_tutorial_action("SwitchAmmo", unit_id, {"ammo_group_id": str(unit.get("stats", {}).get("ammo_selection_group_id", ""))})
			return switch_result
		"FirePrimaryWeapon":
			if str(command.get("issuer_type", "")) == "PlayerAssistAI" and (not bool(unit.get("primary_auto_fire_enabled", false)) or bool(unit.get("primary_auto_fire_suspended", false))):
				return _rejection(command.get("command_id", ""), "AUTO_FIRE_DISABLED")
			var target_position = command.get("target_position")
			if typeof(target_position) != TYPE_VECTOR2: return _rejection(command.get("command_id", ""), "INVALID_TARGET_TYPE")
			var fire_result := _fire_primary_weapon(unit, target_position, command.get("command_id", ""))
			if bool(fire_result.get("accepted", false)) and _is_player_tutorial_command(command):
				_record_tutorial_action("ManualPrimaryFire", unit_id, {"weapon_group_id": str(unit.get("stats", {}).get("primary_weapon_group_id", ""))})
			return fire_result
		"DeclareFacilityControl":
			var facility_result := facility_service.declare_control(str(command.get("facility_id", "")), unit)
			if bool(facility_result.get("accepted", false)) and facility_result.has("event"):
				if unit["faction_id"] == PLAYER_FACTION: unit["player_facility_target_id"] = str(command.get("facility_id", ""))
				_ai_objective_plan_cache.erase(unit_id)
				state["facilities_by_id"] = facility_service.snapshot()
				_ai_observations_by_faction.clear()
				var facility_event: Dictionary = facility_result["event"]
				_emit(str(facility_event.get("event_type", "FacilityControlDeclared")), facility_event)
			elif str(command.get("issuer_type", "")) == "AI": _record_ai_facility_failure(unit, str(command.get("facility_id", "")))
			return facility_result
		"RequestFacilityService":
			var service_result := facility_service.request_service(str(command.get("facility_id", "")), unit)
			if bool(service_result.get("accepted", false)) and service_result.has("event"):
				state["facilities_by_id"] = facility_service.snapshot()
				var service_event: Dictionary = service_result["event"]
				if service_event.get("berth_state", "") == "Docked": _dock_unit_for_service(unit, service_event)
				_emit(str(service_event.get("event_type", "FacilityServiceStarted")), service_event)
			elif str(command.get("issuer_type", "")) == "AI": _record_ai_facility_failure(unit, str(command.get("facility_id", "")))
			return service_result
		"ApproachFacility":
			var approach_facility_id := str(command.get("facility_id", ""))
			if unit["faction_id"] != PLAYER_FACTION or not _ai_observation_for(PLAYER_FACTION).known_facilities.has(approach_facility_id):
				return _rejection(command.get("command_id", ""), "FACILITY_NOT_KNOWN")
			unit["player_facility_target_id"] = approach_facility_id
			_emit("FacilityApproachAssigned", {"unit_id": unit_id, "facility_id": approach_facility_id})
			return {"accepted": true}
		"CancelFacilityAction":
			var cancel_result := facility_service.cancel_action(str(command.get("facility_id", "")), unit_id)
			if bool(cancel_result.get("accepted", false)) and cancel_result.has("event"):
				if unit["faction_id"] == PLAYER_FACTION: unit["player_facility_target_id"] = ""
				var cancel_event: Dictionary = cancel_result["event"]
				_emit(str(cancel_event.get("event_type", "FacilityActionInterrupted")), cancel_event)
			return cancel_result
		"RequestSupportMission":
			var support_target = command.get("target_position")
			if typeof(support_target) != TYPE_VECTOR2: return _rejection(command.get("command_id", ""), "INVALID_TARGET_TYPE")
			var support_context := terrain_context_service.context_at(support_target)
			var support_result := facility_service.request_support(str(command.get("facility_id", "")), str(command.get("mission_definition_id", "")), unit["faction_id"], support_target, float(state["elapsed_time"]), support_context)
			if bool(support_result.get("accepted", false)) and support_result.has("event"):
				var support_event: Dictionary = support_result["event"]
				_emit(str(support_event.get("event_type", "SupportMissionStarted")), support_event)
			return support_result
		"RequestMineDeployment":
			var mine_target = command.get("target_position")
			if typeof(mine_target) != TYPE_VECTOR2: return _rejection(command.get("command_id", ""), "INVALID_TARGET_TYPE")
			var mine_seed := int(state.get("battle_seed", 1)) ^ int(state.get("tick_index", 0) * 7919) ^ int(str(command.get("facility_id", "")).hash())
			var mine_result := facility_service.request_mine_deployment(str(command.get("facility_id", "")), unit, mine_target, float(state.get("elapsed_time", 0.0)), state["units_by_id"], mine_seed)
			if bool(mine_result.get("accepted", false)) and mine_result.has("event"):
				var mine_event: Dictionary = mine_result["event"]
				_emit(str(mine_event.get("event_type", "MineDeploymentStarted")), mine_event)
			elif str(command.get("issuer_type", "")) == "AI": _record_ai_facility_failure(unit, str(command.get("facility_id", "")))
			return mine_result
		_:
			return _rejection(command.get("command_id", ""), "UNKNOWN_COMMAND")


func _validate_command_structure(command: Dictionary) -> Dictionary:
	for field in ["command_id", "command_type", "issuer_id"]:
		if not command.has(field): return _rejection(command.get("command_id", ""), "INVALID_COMMAND_STRUCTURE")
	return {}


func _set_unit_control_state(command: Dictionary) -> Dictionary:
	if str(command.get("issuer_id", "")) != PLAYER_FACTION:
		return _rejection(command.get("command_id", ""), "UNIT_NOT_CONTROLLABLE")
	var unit_ids: Array = command.get("unit_ids", [])
	if unit_ids.is_empty() and command.has("unit_id"):
		unit_ids = [str(command.get("unit_id", ""))]
	if unit_ids.is_empty():
		return _rejection(command.get("command_id", ""), "INVALID_COMMAND_STRUCTURE")
	unit_ids = unit_ids.duplicate()
	unit_ids.sort()
	var changed: Array = []
	for unit_id_value in unit_ids:
		var unit_id := str(unit_id_value)
		var unit: Dictionary = state.get("units_by_id", {}).get(unit_id, {})
		if unit.is_empty() or unit.get("faction_id", "") != PLAYER_FACTION or unit.get("life_state", "") != "Alive":
			continue
		if command.has("movement_assist_enabled"):
			unit["movement_assist_enabled"] = bool(command["movement_assist_enabled"])
			if unit.get("player_route_waypoints", []).is_empty() and str(unit.get("movement_state", {}).get("mode", "")) not in ["ImmediateAvoidance", "PlayerMoveOrder", "PlayerWaypointRoute"]:
				unit["movement_state"] = _new_movement_state("AssistNavigate" if bool(unit["movement_assist_enabled"]) else "HoldPosition", unit["position"], [])
				_mark_navigation_dirty(unit)
		if command.has("secondary_auto_fire_enabled"):
			unit["secondary_auto_fire_enabled"] = bool(command["secondary_auto_fire_enabled"])
		if command.has("primary_auto_fire_enabled") and not str(unit.get("stats", {}).get("primary_weapon_group_id", "")).is_empty():
			unit["primary_auto_fire_enabled"] = bool(command["primary_auto_fire_enabled"])
		if command.has("primary_auto_fire_suspended"):
			unit["primary_auto_fire_suspended"] = bool(command["primary_auto_fire_suspended"])
		unit["skill_auto_cast_enabled"] = false
		changed.append(unit_id)
		_emit("UnitControlStateChanged", {
			"unit_id": unit_id,
			"movement_assist_enabled": bool(unit.get("movement_assist_enabled", false)),
			"secondary_auto_fire_enabled": bool(unit.get("secondary_auto_fire_enabled", true)),
			"primary_auto_fire_enabled": bool(unit.get("primary_auto_fire_enabled", false)),
		})
	return {"accepted": not changed.is_empty(), "changed_unit_ids": changed, "reason_code": "OK" if not changed.is_empty() else "UNIT_NOT_CONTROLLABLE"}


func _append_player_waypoint(unit: Dictionary, target_position: Vector2, command_id: String) -> Dictionary:
	if not _inside_map(target_position): return _rejection(command_id, "TARGET_POSITION_ON_LAND")
	var authored_points: Array = unit.get("player_route_waypoints", [])
	if authored_points.is_empty():
		_begin_navigation_intent(unit)
	var anchor: Vector2 = authored_points[-1] if not authored_points.is_empty() else unit["position"]
	authored_points = authored_points.duplicate()
	authored_points.append(target_position)
	unit["player_route_waypoints"] = authored_points
	_submit_navigation_request(unit, anchor, target_position, "Append", "PlayerWaypointRoute", command_id, 0)
	_emit("MoveWaypointQueued", {"unit_id": unit["entity_id"], "target_position": target_position, "route_size": authored_points.size()})
	_record_tutorial_action("AppendMoveWaypoint", str(unit.get("entity_id", "")))
	return {"accepted": true}


func _begin_navigation_intent(unit: Dictionary) -> int:
	var navigation: Dictionary = unit.get("navigation_state", {})
	var cancelled := navigation_request_broker.cancel_for_unit(str(unit.get("entity_id", "")))
	navigation["intent_revision"] = int(navigation.get("intent_revision", 0)) + 1
	navigation["pending_route_requests"] = maxi(0, int(navigation.get("pending_route_requests", 0)) - cancelled)
	navigation["route_waiting"] = int(navigation["pending_route_requests"]) > 0
	return int(navigation["intent_revision"])


func _record_tutorial_action(action_id: String, unit_id: String, facts: Dictionary = {}) -> Dictionary:
	var result: Dictionary = level_objective_service.record_action(action_id, unit_id, int(state.get("tick_index", 0)), facts)
	state["level_objective"] = level_objective_service.snapshot()
	for action_event in result.get("events", []):
		var event: Dictionary = action_event
		_emit(str(event.get("event_type", "TutorialActionRecorded")), event)
	return {"accepted": bool(result.get("accepted", false)), "reason_code": str(result.get("reason_code", "TUTORIAL_ACTION_NOT_REQUIRED"))}


func _is_player_tutorial_command(command: Dictionary) -> bool:
	if str(command.get("issuer_id", PLAYER_FACTION)) != PLAYER_FACTION: return false
	return str(command.get("issuer_type", "Player")) in ["Player", "SimulationPolicy"]


func _submit_navigation_request(unit: Dictionary, start: Vector2, target: Vector2, apply_mode: String, movement_mode: String, command_id: String, priority: int, intent_target = null) -> void:
	var navigation: Dictionary = unit.get("navigation_state", {})
	var semantic_target: Vector2 = target if intent_target == null or typeof(intent_target) != TYPE_VECTOR2 else intent_target
	navigation["pending_route_requests"] = int(navigation.get("pending_route_requests", 0)) + 1
	navigation["route_waiting"] = true
	navigation["pending_intent_target"] = semantic_target
	if unit.get("movement_state", {}).get("corridor_points", []).is_empty():
		navigation["state"] = "StrategicRouteWaiting"
		navigation["current_control"] = {"thrust_ratio":0.0, "turn_ratio":0.0}
	navigation_request_broker.submit({
		"unit_id":unit["entity_id"], "start":start, "target":target,
		"intent_target":semantic_target, "target_preprojected":not semantic_target.is_equal_approx(target),
		"radius":float(unit.get("stats", {}).get("collision_radius", 20.0)),
		"movement_tags":_movement_tags(unit), "apply_mode":apply_mode,
		"movement_mode":movement_mode, "command_id":command_id, "priority":priority,
		"intent_revision":int(navigation.get("intent_revision", 0)),
	})


func _update_navigation_requests() -> void:
	for completed in navigation_request_broker.advance(route_planner, terrain_query, navigation_definition, terrain_context_service):
		_profile_increment("strategic_corridors_per_tick")
		var request: Dictionary = completed.get("request", {})
		var unit: Dictionary = state.get("units_by_id", {}).get(str(request.get("unit_id", "")), {})
		if unit.is_empty() or unit.get("life_state", "") != "Alive": continue
		var navigation: Dictionary = unit.get("navigation_state", {})
		navigation["pending_route_requests"] = maxi(0, int(navigation.get("pending_route_requests", 1)) - 1)
		navigation["route_waiting"] = int(navigation["pending_route_requests"]) > 0
		if int(request.get("intent_revision", -1)) != int(navigation.get("intent_revision", 0)):
			_emit("NavigationRequestDiscarded", {"unit_id":unit["entity_id"], "command_id":request.get("command_id", ""), "reason_code":"STALE_INTENT_REVISION"})
			continue
		var result: Dictionary = completed.get("result", {})
		var intent_target: Vector2 = request.get("intent_target", request.get("target", unit.get("position", Vector2.ZERO)))
		var route_profile: Dictionary = completed.get("route_profile", {}).duplicate(true)
		var target_preprojected := bool(request.get("target_preprojected", false))
		if target_preprojected:
			route_profile["target_projected"] = true
			route_profile["projection_progress"] = (request.get("start", unit.get("position", Vector2.ZERO)) as Vector2).distance_to(intent_target) - (request.get("target", intent_target) as Vector2).distance_to(intent_target)
		if not bool(result.get("ok", false)):
			var failed_target: Vector2 = intent_target
			var previous_failed_target: Vector2 = navigation.get("failed_intent_target", failed_target)
			var repeated_failure := previous_failed_target.distance_to(failed_target) < 8.0
			navigation["route_failure_count"] = int(navigation.get("route_failure_count", 0)) + 1 if repeated_failure else 1
			navigation["failed_intent_target"] = failed_target
			navigation["failed_intent_origin"] = unit.get("position", Vector2.ZERO)
			var retry_delay := minf(NAVIGATION_FAILURE_RETRY_MAX, NAVIGATION_STRATEGIC_INTERVAL * pow(2.0, float(maxi(0, int(navigation["route_failure_count"]) - 1))))
			navigation["route_retry_at"] = float(state.get("elapsed_time", 0.0)) + retry_delay
			_emit("NavigationRequestFailed", {"unit_id":unit["entity_id"], "command_id":request.get("command_id", ""), "start":request.get("start", Vector2.ZERO), "target":intent_target, "route_target":request.get("target", intent_target), "reason_code":result.get("reason_code", "NO_NAVIGATION_PATH"), "elapsed_usec":completed.get("elapsed_usec", 0), "route_profile":route_profile})
			if not bool(navigation["route_waiting"]): navigation["state"] = "SafetyHold"
			continue
		var points: Array = result.get("waypoints", [request.get("target", unit["position"])]).duplicate()
		var gates: Array = result.get("gates", points.map(func(point): return {"center":point, "radius":0.0})).duplicate(true)
		var resolved_target: Vector2 = result.get("resolved_target", request.get("target", unit["position"]))
		if str(request.get("apply_mode", "Replace")) == "Append":
			var movement: Dictionary = unit.get("movement_state", {})
			var remaining: Array = []
			var remaining_gates: Array = []
			for index in range(int(movement.get("corridor_index", 0)), movement.get("corridor_points", []).size()): remaining.append(movement["corridor_points"][index])
			for index in range(int(movement.get("corridor_index", 0)), movement.get("corridor_gates", []).size()): remaining_gates.append(movement["corridor_gates"][index])
			remaining.append_array(points)
			remaining_gates.append_array(gates)
			unit["movement_state"] = _new_movement_state(str(request.get("movement_mode", "PlayerWaypointRoute")), resolved_target, remaining)
			unit["movement_state"]["corridor_gates"] = remaining_gates
		else:
			unit["movement_state"] = _new_movement_state(str(request.get("movement_mode", "AutoNavigate")), resolved_target, points)
			unit["movement_state"]["corridor_gates"] = gates
		navigation["strategic_intent_target"] = intent_target
		navigation["pending_intent_target"] = intent_target
		navigation["route_failure_count"] = 0
		navigation["route_retry_at"] = 0.0
		navigation["state"] = "NormalNavigation"
		_mark_navigation_dirty(unit)
		_emit("NavigationRequestCompleted", {"unit_id":unit["entity_id"], "command_id":request.get("command_id", ""), "start":request.get("start", Vector2.ZERO), "target":intent_target, "route_target":request.get("target", intent_target), "resolved_target":resolved_target, "target_projected":target_preprojected or bool(result.get("target_projected", false)), "waypoint_count":points.size(), "elapsed_usec":completed.get("elapsed_usec", 0), "route_profile":route_profile})
		if str(request.get("apply_mode", "Replace")) == "Replace":
			_emit("MoveOrderAccepted", {"unit_id":unit["entity_id"], "target_position":intent_target})


func _build_navigation_corridor(unit: Dictionary, start: Vector2, target: Vector2) -> Dictionary:
	_profile_increment("strategic_corridors_per_tick")
	var radius := float(unit.get("stats", {}).get("collision_radius", 20.0))
	var direct_clear := not terrain_query.is_configured() or terrain_query.is_movement_segment_clear(start, target, radius, _movement_tags(unit))
	var result := {"ok": true, "reason_code": "OK", "waypoints": [target]} if direct_clear else route_planner.plan_path(terrain_query, navigation_definition, start, target, radius, _movement_tags(unit), terrain_context_service)
	if not bool(result.get("ok", false)):
		return {"ok": false, "reason_code": result.get("reason_code", "NO_NAVIGATION_PATH")}
	var points: Array = result.get("waypoints", [target]).duplicate()
	var environment_route := _validate_environment_route(start, points)
	if not bool(environment_route.get("allowed", false)):
		return {"ok": false, "reason_code": environment_route.get("reason_code", "TIDE_ACCESS_RESTRICTED")}
	return {"ok": true, "reason_code": "OK", "points": points}


func _mark_navigation_dirty(unit: Dictionary) -> void:
	var navigation: Dictionary = unit.get("navigation_state", {})
	navigation["trajectory_dirty"] = true
	var tick := int(state.get("tick_index", 0))
	var slot := int(navigation.get("normal_plan_slot", absi(str(unit.get("entity_id", "")).hash()) % NAVIGATION_NORMAL_INTERVAL_TICKS))
	var delay := posmod(slot - posmod(tick, NAVIGATION_NORMAL_INTERVAL_TICKS), NAVIGATION_NORMAL_INTERVAL_TICKS)
	navigation["next_normal_plan_tick"] = tick + delay


func _mark_navigation_dirty_immediate(unit: Dictionary) -> void:
	var navigation: Dictionary = unit.get("navigation_state", {})
	navigation["trajectory_dirty"] = true
	navigation["next_normal_plan_tick"] = int(state.get("tick_index", 0)) + 1


func _update_cooldowns_and_statuses(delta: float) -> void:
	for unit_id in _sorted_unit_ids():
		var unit: Dictionary = state["units_by_id"][unit_id]
		if unit["life_state"] != "Alive": continue
		unit["firing_reveal_remaining"] = maxf(0.0, float(unit["firing_reveal_remaining"]) - delta)
		unit["skill_state"]["cooldown_remaining"] = maxf(0.0, float(unit["skill_state"]["cooldown_remaining"]) - delta)
		unit["ai_state"]["decision_cooldown"] = maxf(0.0, float(unit.get("ai_state", {}).get("decision_cooldown", 0.0)) - delta)
		unit["ai_state"]["fire_decision_cooldown"] = maxf(0.0, float(unit.get("ai_state", {}).get("fire_decision_cooldown", 0.0)) - delta)
		unit["ai_state"]["skill_decision_cooldown"] = maxf(0.0, float(unit.get("ai_state", {}).get("skill_decision_cooldown", 0.0)) - delta)
		for weapon_state in unit["weapon_states"]:
			weapon_state["reload_remaining"] = maxf(0.0, float(weapon_state["reload_remaining"]) - delta)
		for group_id in unit.get("weapon_group_launch_remaining", {}).keys():
			unit["weapon_group_launch_remaining"][group_id] = maxf(0.0, float(unit["weapon_group_launch_remaining"][group_id]) - delta)
		for index in range(unit["status_effects"].size() - 1, -1, -1):
			var effect: Dictionary = unit["status_effects"][index]
			if bool(effect.get("persistent_until_consumed", false)):
				continue
			effect["remaining"] = float(effect.get("remaining", 0.0)) - delta
			if float(effect["remaining"]) <= 0.0:
				unit["status_effects"].remove_at(index)
				_emit("StatusExpired", {"target_unit_id": unit_id, "status_id": effect.get("status_id", "")})


func _active_status_effects(unit: Dictionary) -> Array:
	var result: Array = []
	for effect in unit.get("status_effects", []):
		if bool(effect.get("requires_submerged", false)) and str(unit.get("depth_state", "Surface")) != "Submerged":
			continue
		result.append(effect)
	return result


func _update_submarine_resources(delta: float) -> void:
	for unit_id in _sorted_unit_ids():
		var unit: Dictionary = state["units_by_id"][unit_id]
		if unit.get("life_state", "") != "Alive" or str(unit.get("stats", {}).get("ship_class", "")) != "Submarine":
			continue
		var oxygen: Dictionary = unit.get("oxygen_state", {})
		var maximum := maxf(0.0, float(oxygen.get("maximum", unit.get("stats", {}).get("max_oxygen", 0.0))))
		if maximum <= 0.0: continue
		var current := clampf(float(oxygen.get("current", maximum)), 0.0, maximum)
		if str(unit.get("depth_state", "Submerged")) == "Submerged":
			var consumption_rate := float(unit.get("stats", {}).get("oxygen_consumption_rate", maximum / 90.0))
			consumption_rate = ModifierService.calculate(consumption_rate, _active_status_effects(unit), "OxygenConsumptionRate")
			current = maxf(0.0, current - consumption_rate * delta)
			if is_zero_approx(current):
				unit["depth_state"] = "Surface"
				_emit("SubmarineForcedSurface", {"unit_id": unit_id, "reason": "OXYGEN_DEPLETED"})
		else:
			var recovery_rate := float(unit.get("stats", {}).get("oxygen_recovery_rate", maximum / 45.0))
			recovery_rate = ModifierService.calculate(recovery_rate, _active_status_effects(unit), "OxygenRecoveryRate")
			current = minf(maximum, current + recovery_rate * delta)
		oxygen["current"] = current
		oxygen["maximum"] = maximum
		unit["oxygen_state"] = oxygen


func _update_navigation_plans() -> void:
	for unit_id in _sorted_unit_ids():
		var unit: Dictionary = state["units_by_id"][unit_id]
		if unit.get("life_state", "") != "Alive": continue
		if not _docked_action_for_unit(unit_id).is_empty(): continue
		var navigation: Dictionary = unit.get("navigation_state", {})
		var threats := _navigation_high_threats(unit)
		var navigation_mode := str(navigation.get("state", "NormalNavigation"))
		if not threats.is_empty():
			if navigation_mode != "EmergencyEvasion":
				navigation["state"] = "EmergencyEvasion"
				navigation["emergency_clear_ticks"] = 0
				_emit("NavigationStateChanged", {"unit_id": unit_id, "from": navigation_mode, "to": "EmergencyEvasion", "reason": threats[0].get("kind", "HighThreat")})
			_plan_emergency_trajectory(unit, threats)
			continue
		if navigation_mode == "EmergencyEvasion":
			navigation["emergency_clear_ticks"] = int(navigation.get("emergency_clear_ticks", 0)) + 1
			if int(navigation["emergency_clear_ticks"]) < NAVIGATION_EMERGENCY_EXIT_TICKS:
				continue
			navigation["state"] = "NormalNavigation"
			navigation["trajectory_dirty"] = true
			navigation["next_normal_plan_tick"] = int(state.get("tick_index", 0))
			_emit("NavigationStateChanged", {"unit_id": unit_id, "from": "EmergencyEvasion", "to": "NormalNavigation", "reason": "THREATS_CLEAR"})
		var tick := int(state.get("tick_index", 0))
		if tick >= int(navigation.get("next_normal_plan_tick", 0)):
			_plan_normal_trajectory(unit)


func _plan_normal_trajectory(unit: Dictionary) -> void:
	_profile_increment("normal_plans_per_tick")
	var navigation: Dictionary = unit["navigation_state"]
	var movement: Dictionary = unit["movement_state"]
	var goal: Vector2 = _current_corridor_goal(unit)
	var hold: bool = str(movement.get("mode", "HoldPosition")) in ["HoldPosition", "Docked"] or goal == unit.get("position", Vector2.ZERO)
	if hold:
		navigation["current_control"] = {"thrust_ratio": 0.0, "turn_ratio": 0.0}
		navigation["trajectory_plan"] = {}
		navigation["trajectory_dirty"] = false
		navigation["next_normal_plan_tick"] = int(state.get("tick_index", 0)) + NAVIGATION_NORMAL_INTERVAL_TICKS
		return
	var motion_state := ShipMotionService.state_for_unit(unit, terrain_context_service.context_at(unit["position"]), _active_status_effects(unit), ModifierService)
	motion_state["map_width"] = float(state.get("map", {}).get("width", 0.0))
	motion_state["map_height"] = float(state.get("map", {}).get("height", 0.0))
	motion_state["previous_control"] = navigation.get("current_control", {"thrust_ratio":0.0, "turn_ratio":0.0})
	if navigation.has("last_collision"):
		motion_state["collision_recovery"] = navigation.get("last_collision", {}).duplicate(true)
	var movement_mode := str(movement.get("mode", ""))
	var prioritize_direct_player_motion := movement_mode in ["PlayerMoveOrder", "PlayerWaypointRoute"]
	var result := trajectory_planner.plan_normal(motion_state, goal, float(unit["stats"].get("collision_radius", 20.0)), _movement_tags(unit), terrain_query, terrain_context_service, _nearby_navigation_units(unit), _current_corridor_goal_is_final(unit), _current_corridor_lookahead(unit, 2), prioritize_direct_player_motion)
	_profile_increment("trajectory_segments_simulated_per_tick", int(result.get("segments_simulated", 0)))
	_profile_increment("trajectory_candidates_rejected_by_terrain_per_tick", int(result.get("candidates_rejected_by_terrain", 0)))
	if not bool(result.get("ok", false)):
		_profile_increment("trajectory_failures_per_tick")
		navigation["state"] = "SafetyHold"
		navigation["current_control"] = {"thrust_ratio": -0.25 if absf(float(unit.get("current_speed", 0.0))) < 1.0 else 0.0, "turn_ratio": 0.0}
		_emit("TrajectoryPlanFailed", {"unit_id": unit["entity_id"], "mode": "NormalNavigation", "reason_code": result.get("reason_code", "NO_SAFE_TRAJECTORY")})
	else:
		_profile_increment("trajectory_candidates_per_tick", int(result.get("candidate_count", 0)))
		navigation["state"] = "NormalNavigation"
		result["planned_at_tick"] = int(state.get("tick_index", 0))
		result["valid_until_tick"] = int(state.get("tick_index", 0)) + NAVIGATION_NORMAL_INTERVAL_TICKS
		result["terrain_revision"] = int(state.get("terrain_map", {}).get("navigation_revision", 0))
		navigation["trajectory_plan"] = result
		navigation["current_control"] = result.get("controls", [{"thrust_ratio": 0.0, "turn_ratio": 0.0}])[0]
		if navigation.has("last_collision") and float(result.get("minimum_clearance", 0.0)) > float(unit["stats"].get("collision_radius", 20.0)) + 40.0:
			navigation.erase("last_collision")
		_emit("TrajectoryPlanned", {"unit_id": unit["entity_id"], "mode": "NormalNavigation", "candidate_count": result.get("candidate_count", 0), "candidate_id":result.get("candidate_id", ""), "goal": goal, "minimum_clearance":result.get("minimum_clearance", 0.0)})
	navigation["trajectory_dirty"] = false
	navigation["next_normal_plan_tick"] = int(state.get("tick_index", 0)) + NAVIGATION_NORMAL_INTERVAL_TICKS


func _plan_emergency_trajectory(unit: Dictionary, threats: Array) -> void:
	_profile_increment("emergency_plans_per_tick")
	var navigation: Dictionary = unit["navigation_state"]
	var motion_state := ShipMotionService.state_for_unit(unit, terrain_context_service.context_at(unit["position"]), _active_status_effects(unit), ModifierService)
	motion_state["map_width"] = float(state.get("map", {}).get("width", 0.0))
	motion_state["map_height"] = float(state.get("map", {}).get("height", 0.0))
	var result := trajectory_planner.plan_emergency(motion_state, threats, float(unit["stats"].get("collision_radius", 20.0)), _movement_tags(unit), terrain_query, terrain_context_service, _nearby_navigation_units(unit), false)
	if not bool(result.get("ok", false)) or float(result.get("threat_safety", 0.0)) < 0.75:
		result = trajectory_planner.plan_emergency(motion_state, threats, float(unit["stats"].get("collision_radius", 20.0)), _movement_tags(unit), terrain_query, terrain_context_service, _nearby_navigation_units(unit), true)
	if not bool(result.get("ok", false)):
		_profile_increment("trajectory_failures_per_tick")
		navigation["state"] = "SafetyHold"
		navigation["current_control"] = {"thrust_ratio": 0.0, "turn_ratio": 0.0}
		_emit("TrajectoryPlanFailed", {"unit_id": unit["entity_id"], "mode": "EmergencyEvasion", "reason_code": result.get("reason_code", "NO_SAFE_TRAJECTORY")})
		return
	_profile_increment("trajectory_candidates_per_tick", int(result.get("candidate_count", 0)))
	_profile_increment("trajectory_segments_simulated_per_tick", int(result.get("segments_simulated", 0)))
	_profile_increment("trajectory_candidates_rejected_by_terrain_per_tick", int(result.get("candidates_rejected_by_terrain", 0)))
	result["planned_at_tick"] = int(state.get("tick_index", 0))
	result["valid_until_tick"] = int(state.get("tick_index", 0)) + 1
	result["terrain_revision"] = int(state.get("terrain_map", {}).get("navigation_revision", 0))
	navigation["trajectory_plan"] = result
	navigation["current_control"] = result.get("controls", [{"thrust_ratio": 0.0, "turn_ratio": 0.0}])[0]
	navigation["tracked_threat_ids"] = threats.map(func(threat): return str(threat.get("id", "")))
	_emit("TrajectoryPlanned", {"unit_id": unit["entity_id"], "mode": "EmergencyEvasion", "candidate_count": result.get("candidate_count", 0), "threat_ids": navigation["tracked_threat_ids"], "controlled_contact": result.get("controlled_contact", false)})


func _update_movement(delta: float) -> void:
	for unit_id in _sorted_unit_ids():
		var unit: Dictionary = state["units_by_id"][unit_id]
		if unit["life_state"] != "Alive": continue
		var docked_action := _docked_action_for_unit(unit_id)
		if not docked_action.is_empty():
			unit["position"] = docked_action.get("dock_position", unit.get("position", Vector2.ZERO))
			unit["current_speed"] = 0.0
			continue
		_advance_corridor_progress(unit)
		var navigation: Dictionary = unit.get("navigation_state", {})
		var control: Dictionary = _active_trajectory_control(navigation)
		navigation["current_control"] = control
		var context := terrain_context_service.context_at(unit["position"])
		var motion_state := ShipMotionService.state_for_unit(unit, context, _active_status_effects(unit), ModifierService)
		var next_state := ShipMotionService.step(motion_state, control, delta)
		var movement_start: Vector2 = unit["position"]
		var desired_position: Vector2 = next_state.get("position", movement_start)
		var desired_motion := desired_position - movement_start
		unit["heading"] = float(next_state.get("heading", unit["heading"]))
		unit["current_speed"] = float(next_state.get("speed", unit["current_speed"]))
		var environment_access := terrain_context_service.movement_segment_access(movement_start, desired_position)
		if not bool(environment_access.get("allowed", true)):
			desired_motion = Vector2.ZERO
			unit["current_speed"] = 0.0
			navigation["trajectory_dirty"] = true
			_emit("UnitTideAccessRestricted", {"unit_id": unit_id, "zone_id": environment_access.get("zone_id", ""), "position": movement_start})
		if terrain_query.is_configured():
			var motion_result := terrain_query.resolve_circle_motion(unit["position"], desired_motion, float(unit["stats"].get("collision_radius", 20.0)), _movement_tags(unit))
			unit["position"] = motion_result["position"]
			if bool(motion_result.get("collided", false)):
				var collision_entry_speed := float(unit.get("current_speed", 0.0))
				unit["current_speed"] = 0.0
				var hit: Dictionary = motion_result.get("hit", {})
				var active_plan: Dictionary = navigation.get("trajectory_plan", {})
				if bool(active_plan.get("ok", false)) and int(active_plan.get("terrain_revision", -1)) == int(state.get("terrain_map", {}).get("navigation_revision", 0)):
					_emit("NavigationCollisionContractViolated", {"unit_id":unit_id, "plan_tick":active_plan.get("planned_at_tick", -1), "collision_tick":state.get("tick_index", 0), "field_revision":active_plan.get("terrain_revision", -1), "terrain_revision":state.get("terrain_map", {}).get("navigation_revision", 0), "candidate_id":active_plan.get("candidate_id", ""), "obstacle_id":hit.get("obstacle_id", "")})
				navigation["trajectory_plan"] = {}
				navigation["current_control"] = {"thrust_ratio":0.0, "turn_ratio":0.0}
				navigation["last_collision"] = {"normal":hit.get("normal", Vector2.ZERO), "obstacle_id":hit.get("obstacle_id", ""), "position":hit.get("position", unit["position"]), "entry_speed":collision_entry_speed, "tick":state.get("tick_index", 0)}
				_mark_navigation_dirty_immediate(unit)
				_emit("UnitTerrainCollision", {"unit_id": unit_id, "obstacle_id": hit.get("obstacle_id", ""), "position": hit.get("position", unit["position"]), "normal": hit.get("normal", Vector2.ZERO)})
		else:
			unit["position"] = _clamp_to_map(desired_position)
		var mine_trigger := minefield_service.resolve_unit_motion(unit, movement_start, unit["position"])
		if bool(mine_trigger.get("triggered", false)): _apply_mine_trigger(unit, mine_trigger)
		_update_ai_path_progress(unit, unit["movement_state"])


func _current_corridor_goal(unit: Dictionary) -> Vector2:
	var movement: Dictionary = unit.get("movement_state", {})
	var points: Array = movement.get("corridor_points", [])
	var index := int(movement.get("corridor_index", 0))
	if index >= 0 and index < points.size(): return points[index]
	return movement.get("target_position", unit.get("position", Vector2.ZERO))


func _current_corridor_goal_is_final(unit: Dictionary) -> bool:
	var movement: Dictionary = unit.get("movement_state", {})
	var points: Array = movement.get("corridor_points", [])
	var index := int(movement.get("corridor_index", 0))
	return points.is_empty() or index >= points.size() - 1


func _current_corridor_lookahead(unit: Dictionary, count: int) -> Array:
	var movement: Dictionary = unit.get("movement_state", {})
	var points: Array = movement.get("corridor_points", [])
	var index := int(movement.get("corridor_index", 0))
	var result: Array = []
	for point_index in range(index + 1, mini(points.size(), index + 1 + maxi(0, count))):
		result.append(points[point_index])
	return result


func _active_trajectory_control(navigation: Dictionary) -> Dictionary:
	var plan: Dictionary = navigation.get("trajectory_plan", {})
	var controls: Array = plan.get("controls", [])
	if controls.is_empty():
		return navigation.get("current_control", {"thrust_ratio":0.0, "turn_ratio":0.0})
	var elapsed := maxf(0.0, float(int(state.get("tick_index", 0)) - int(plan.get("planned_at_tick", state.get("tick_index", 0)))) * 0.1)
	for raw_control in controls:
		var control: Dictionary = raw_control
		var duration := maxf(0.0, float(control.get("duration", 0.0)))
		if elapsed < duration - 0.0001:
			return control
		elapsed -= duration
	return controls[-1]


func _advance_corridor_progress(unit: Dictionary) -> void:
	var movement: Dictionary = unit.get("movement_state", {})
	var points: Array = movement.get("corridor_points", [])
	var index := int(movement.get("corridor_index", 0))
	var arrival_distance := trajectory_planner.arrival_tolerance(float(unit.get("stats", {}).get("collision_radius", 20.0)))
	var transit_reach_distance := maxf(arrival_distance, absf(float(unit.get("current_speed", 0.0))) * 0.8)
	var gates: Array = movement.get("corridor_gates", [])
	while index < points.size():
		var gate_radius := float(gates[index].get("radius", 0.0)) if index < gates.size() else 0.0
		var is_final_point := index == points.size() - 1
		# Corridor gates are not precision waypoints. Allow a modest margin for
		# inertial hulls so a ship that safely enters the authored gate does not
		# stop just outside the mathematical radius.
		var point_reach_distance := arrival_distance if is_final_point else maxf(transit_reach_distance, gate_radius * 1.5)
		var current_position: Vector2 = unit.get("position", Vector2.ZERO)
		var reached_gate := current_position.distance_to(points[index]) <= point_reach_distance
		if not reached_gate and not is_final_point:
			var next_direction: Vector2 = points[index + 1] - points[index]
			if next_direction.length_squared() > 0.001:
				var offset: Vector2 = current_position - points[index]
				var passed_gate_plane := offset.dot(next_direction) > 0.0
				var lateral_distance := absf(offset.cross(next_direction.normalized()))
				reached_gate = passed_gate_plane and lateral_distance <= maxf(point_reach_distance * 1.5, arrival_distance * 2.0)
		if not reached_gate: break
		index += 1
		movement["corridor_index"] = index
		unit.get("navigation_state", {})["trajectory_dirty"] = true
	if index < points.size(): return
	var final_target: Vector2 = movement.get("target_position", unit.get("position", Vector2.ZERO))
	if (unit.get("position", Vector2.ZERO) as Vector2).distance_to(final_target) > arrival_distance: return
	if str(movement.get("mode", "")) in ["PlayerMoveOrder", "PlayerWaypointRoute"]:
		unit["player_route_waypoints"] = []
	movement["mode"] = "AssistNavigate" if bool(unit.get("movement_assist_enabled", false)) else "HoldPosition"
	movement["target_position"] = unit["position"]
	movement["corridor_points"] = []
	movement["corridor_index"] = 0
	unit.get("navigation_state", {})["current_control"] = {"thrust_ratio": 0.0, "turn_ratio": 0.0}


func _nearby_navigation_units(unit: Dictionary) -> Array:
	var result: Array = []
	var origin: Vector2 = unit.get("position", Vector2.ZERO)
	for other_id in _sorted_unit_ids():
		if other_id == unit.get("entity_id", ""): continue
		var other: Dictionary = state["units_by_id"][other_id]
		if other.get("life_state", "") != "Alive": continue
		if origin.distance_to(other.get("position", Vector2.ZERO)) > 500.0: continue
		result.append({"id": other_id, "position": other.get("position", Vector2.ZERO), "radius": float(other.get("stats", {}).get("collision_radius", 20.0))})
	return result


func _navigation_high_threats(unit: Dictionary) -> Array:
	_profile_increment("emergency_scans_per_tick")
	var threats: Array = []
	var projectile_threat := _highest_projectile_threat(unit)
	if float(projectile_threat.get("score", 0.0)) >= AI_IMMEDIATE_THRESHOLD:
		var projectile: Dictionary = projectile_threat.get("projectile", {})
		if not projectile.is_empty():
			threats.append({
				"id": projectile.get("entity_id", projectile.get("projectile_id", "")),
				"kind": "Torpedo",
				"position": projectile.get("position", Vector2.ZERO),
				"velocity": Vector2.RIGHT.rotated(float(projectile.get("heading", 0.0))) * float(projectile.get("speed", 0.0)),
				"danger_radius": _unit_collision_half_extents(unit).y + float(projectile.get("collision_radius", 8.0)) + 24.0,
				"horizon": 8.0,
			})
	for attack in delayed_attacks:
		if threats.size() >= 8: break
		if not _is_committed_high_threat_attack(unit, attack): continue
		threats.append({"id": attack.get("attack_id", ""), "kind": "Area", "position": attack.get("target_position", Vector2.ZERO), "radius": float(attack.get("impact_radius", 40.0)) + _unit_collision_half_extents(unit).y})
	return threats


func _is_committed_high_threat_attack(unit: Dictionary, attack: Dictionary) -> bool:
	var source: Dictionary = state.get("units_by_id", {}).get(str(attack.get("source_unit_id", "")), {})
	if not source.is_empty() and source.get("faction_id", "") == unit.get("faction_id", ""): return false
	if not source.is_empty() and not _is_visible_to(str(unit.get("faction_id", "")), str(source.get("entity_id", ""))): return false
	var weapon: Dictionary = registry.get_definition("weapons", str(attack.get("source_weapon_id", "")))
	if weapon.is_empty(): return false
	var resolve_in := float(attack.get("resolve_at_time", 0.0)) - float(state.get("elapsed_time", 0.0))
	if resolve_in < 0.0 or resolve_in > 8.0: return false
	var impact: Vector2 = attack.get("target_position", Vector2.ZERO)
	var radius := float(attack.get("impact_radius", weapon.get("impact_radius", 40.0))) + _unit_collision_half_extents(unit).y
	if (unit.get("position", Vector2.ZERO) as Vector2).distance_to(impact) > radius + absf(float(unit.get("current_speed", 0.0))) * resolve_in: return false
	var mount_type := str(weapon.get("mount_type", ""))
	var group_id := str(weapon.get("weapon_group_id", "")).to_lower()
	var attack_id := str(attack.get("attack_id", ""))
	var high_threat_kind := (mount_type == "Gun" and "main" in group_id) or mount_type == "Aviation" or attack_id.begins_with("skill_attack")
	if not high_threat_kind: return false
	var formula: Dictionary = registry.get_definition("formulas", str(weapon.get("formula_id", "")))
	var raw_damage := float(formula.get("base_damage", 0.0)) + float(source.get("stats", {}).get(_power_stat_for_weapon(weapon), 0.0)) * float(formula.get("power_coefficient", 0.0))
	return raw_damage / maxf(1.0, float(unit.get("current_hp", 1.0))) >= 0.20


func _update_ai_path_progress(unit: Dictionary, movement: Dictionary) -> void:
	if not _uses_full_ai(unit): return
	# Player-authored routes have their own tutorial route and command evidence.
	# Reporting them as AIPathStuck both misclassifies the owner and makes a
	# route-conformance experiment fail for an AI subsystem that did not issue
	# the order.
	if str(movement.get("mode", "")) in ["PlayerMoveOrder", "PlayerWaypointRoute"]:
		var player_route_ai_state: Dictionary = unit.get("ai_state", {})
		player_route_ai_state["path_stuck"] = false
		return
	var ai_state: Dictionary = unit.get("ai_state", {})
	if not terrain_query.is_configured():
		ai_state["path_stuck"] = false
		return
	var position: Vector2 = unit.get("position", Vector2.ZERO)
	var last_position: Vector2 = ai_state.get("last_progress_position", position)
	var heading := float(unit.get("heading", 0.0))
	var last_heading := float(ai_state.get("last_progress_heading", heading))
	var moving := str(movement.get("mode", "HoldPosition")) not in ["HoldPosition", ""] and not _movement_finished(movement)
	var target_position: Vector2 = movement.get("target_position", position)
	var near_target := position.distance_to(target_position) <= maxf(36.0, float(unit.get("stats", {}).get("collision_radius", 20.0)))
	# A large ship that is turning toward a new corridor is making real
	# navigational progress even before its center moves 18 units.
	if not moving or near_target or position.distance_to(last_position) >= 18.0 or absf(angle_difference(heading, last_heading)) >= deg_to_rad(8.0):
		ai_state["last_progress_position"] = position
		ai_state["last_progress_heading"] = heading
		ai_state["last_progress_at"] = float(state.get("elapsed_time", 0.0))
		ai_state["path_recovery_count"] = 0
		if not moving: ai_state["path_stuck"] = false
		return
	var stalled_seconds := float(state.get("elapsed_time", 0.0)) - float(ai_state.get("last_progress_at", 0.0))
	if stalled_seconds >= AI_PATH_RECOVERY_SECONDS and int(ai_state.get("path_recovery_count", 0)) == 0:
		var navigation: Dictionary = unit.get("navigation_state", {})
		var recovery_turn := -1.0 if absi(str(unit.get("entity_id", "")).hash()) % 2 == 0 else 1.0
		navigation["state"] = "PathRecovery"
		navigation["current_control"] = {"thrust_ratio":-0.25, "turn_ratio":recovery_turn}
		navigation["trajectory_dirty"] = true
		navigation["next_normal_plan_tick"] = int(state.get("tick_index", 0)) + NAVIGATION_NORMAL_INTERVAL_TICKS * 2
		ai_state["path_recovery_count"] = 1
		_emit("AIPathRecoveryStarted", {"unit_id":unit.get("entity_id", ""), "position":position, "target_position":target_position})
		return
	if not bool(ai_state.get("path_stuck", false)) and stalled_seconds >= AI_PATH_STUCK_SECONDS:
		ai_state["path_stuck"] = true
		_emit("AIPathStuck", {"unit_id": unit.get("entity_id", ""), "position": position, "target_position": movement.get("target_position", position)})


func _update_ai_engagement_memory(delta: float) -> void:
	for unit_id in _sorted_unit_ids():
		var unit: Dictionary = state["units_by_id"][unit_id]
		if unit.get("life_state", "") != "Alive" or not _uses_full_ai(unit): continue
		var ai_state: Dictionary = unit["ai_state"]
		var observation = _ai_observation_for(str(unit.get("faction_id", "")))
		var has_contact: bool = not observation.visible_enemies.is_empty()
		var emergency_evasion := str(unit.get("navigation_state", {}).get("state", "NormalNavigation")) == "EmergencyEvasion"
		var defensive_evasion := emergency_evasion or str(ai_state.get("tactic_id", "")) == "Kite" or str(ai_state.get("mode_id", "")) == "DisengageRegroup"
		ai_state["continuous_evasion_seconds"] = float(ai_state.get("continuous_evasion_seconds", 0.0)) + delta if defensive_evasion else maxf(0.0, float(ai_state.get("continuous_evasion_seconds", 0.0)) - delta * 2.0)
		ai_state["no_engagement_seconds"] = 0.0 if has_contact else float(ai_state.get("no_engagement_seconds", 0.0)) + delta
		ai_state["no_effective_attack_seconds"] = maxf(0.0, float(state.get("elapsed_time", 0.0)) - float(ai_state.get("last_effective_attack_at", 0.0)))

		ai_state["passive_sample_elapsed"] = float(ai_state.get("passive_sample_elapsed", 0.0)) + delta
		if float(ai_state["passive_sample_elapsed"]) >= 1.0:
			var sample_seconds := float(ai_state["passive_sample_elapsed"])
			var sample_position: Vector2 = ai_state.get("passive_sample_position", unit.get("position", Vector2.ZERO))
			var moved_distance := sample_position.distance_to(unit.get("position", Vector2.ZERO))
			var significant_distance := maxf(18.0, float(unit.get("stats", {}).get("speed", 0.0)) * 0.18)
			if moved_distance >= significant_distance:
				ai_state["no_effective_movement_seconds"] = maxf(0.0, float(ai_state.get("no_effective_movement_seconds", 0.0)) - sample_seconds * 2.0)
				ai_state["long_idle_reported"] = false
			else:
				ai_state["no_effective_movement_seconds"] = float(ai_state.get("no_effective_movement_seconds", 0.0)) + sample_seconds
			ai_state["passive_sample_position"] = unit.get("position", Vector2.ZERO)
			ai_state["passive_sample_elapsed"] = 0.0
			if float(ai_state.get("no_effective_movement_seconds", 0.0)) >= AI_LONG_IDLE_SECONDS and not bool(ai_state.get("long_idle_reported", false)):
				ai_state["long_idle_reported"] = true
				_emit("AILongIdleDetected", {"unit_id": unit_id, "duration": ai_state["no_effective_movement_seconds"], "position": unit.get("position", Vector2.ZERO)})

		var components := {
			"continuous_evasion": clampf((float(ai_state.get("continuous_evasion_seconds", 0.0)) - 6.0) / 18.0, 0.0, 1.0),
			"no_effective_movement": clampf((float(ai_state.get("no_effective_movement_seconds", 0.0)) - 8.0) / 22.0, 0.0, 1.0),
			"no_engagement": clampf((float(ai_state.get("no_engagement_seconds", 0.0)) - 12.0) / 30.0, 0.0, 1.0),
			"no_effective_attack": clampf((float(ai_state.get("no_effective_attack_seconds", 0.0)) - 15.0) / 30.0, 0.0, 1.0),
		}
		var raw_pressure := 0.25 * (float(components["continuous_evasion"]) + float(components["no_effective_movement"]) + float(components["no_engagement"]) + float(components["no_effective_attack"]))
		var exemption := _ai_engagement_pressure_exemption(unit)
		var pressure := clampf(raw_pressure * float(exemption.get("multiplier", 1.0)), 0.0, 1.0)
		ai_state["engagement_pressure"] = pressure
		var triggered := bool(ai_state.get("engagement_pressure_triggered", false))
		if pressure >= AI_ENGAGEMENT_PRESSURE_TRIGGER and not triggered:
			ai_state["engagement_pressure_triggered"] = true
			ai_state["engagement_pressure_started_at"] = float(state.get("elapsed_time", 0.0))
			_emit("AIEngagementPressureTriggered", {"unit_id": unit_id, "pressure": pressure, "components": components, "exemption_multiplier": exemption.get("multiplier", 1.0), "exemption_reasons": exemption.get("reasons", []), "score_adjustments": _ai_engagement_score_adjustments(pressure)})
		elif pressure < 0.10 and triggered:
			ai_state["engagement_pressure_triggered"] = false
			ai_state["engagement_pressure_started_at"] = -1.0
			ai_state["passive_report_accumulator"] = 0.0
		if pressure >= AI_ENGAGEMENT_PRESSURE_TRIGGER:
			ai_state["passive_report_accumulator"] = float(ai_state.get("passive_report_accumulator", 0.0)) + delta
			if float(ai_state["passive_report_accumulator"]) >= 1.0:
				_emit("AIEngagementPressureSample", {"unit_id": unit_id, "duration": ai_state["passive_report_accumulator"], "pressure": pressure})
				ai_state["passive_report_accumulator"] = 0.0
		if bool(ai_state.get("engagement_pressure_triggered", false)) and _ai_has_engagement_window(unit, observation):
			var response_time := maxf(0.0, float(state.get("elapsed_time", 0.0)) - float(ai_state.get("engagement_pressure_started_at", state.get("elapsed_time", 0.0))))
			_emit("AIEngagementPressureResolved", {"unit_id": unit_id, "response_time": response_time, "reason": "ENGAGEMENT_WINDOW"})
			_reset_ai_passive_memory(unit)


func _ai_engagement_pressure_exemption(unit: Dictionary) -> Dictionary:
	var multiplier := 1.0
	var reasons: Array[String] = []
	var hp_ratio := float(unit.get("current_hp", 0.0)) / maxf(1.0, float(unit.get("max_hp", 1.0)))
	var local_pressure := float(_local_power_context(unit).get("pressure", 0.0))
	if local_pressure >= 0.75 or str(unit.get("navigation_state", {}).get("state", "NormalNavigation")) == "EmergencyEvasion":
		multiplier = 0.0
		reasons.append("IMMEDIATE_THREAT")
	elif hp_ratio <= 0.35:
		multiplier = 0.0
		reasons.append("LOW_HP")
	if _primary_ready_ratio(unit) <= 0.15:
		multiplier = minf(multiplier, 0.35)
		reasons.append("PRIMARY_RELOADING")
	var level_task := str(unit.get("ai_state", {}).get("level_task", ""))
	if not level_task.is_empty():
		multiplier = minf(multiplier, 0.35)
		reasons.append("LEVEL_TASK")
	if str(unit.get("ai_state", {}).get("mode_id", "")) == "EscortScreen":
		multiplier = minf(multiplier, 0.35)
		reasons.append("ESCORT")
	return {"multiplier": multiplier, "reasons": reasons}


func _ai_has_engagement_window(unit: Dictionary, observation) -> bool:
	var preferred := maxf(1.0, _preferred_range(unit))
	for target in observation.visible_enemies.values():
		if target.get("life_state", "") != "Alive": continue
		if (unit.get("position", Vector2.ZERO) as Vector2).distance_to(target.get("position", Vector2.ZERO)) > preferred * 1.25: continue
		for weapon_state in unit.get("weapon_states", []):
			var weapon := _weapon_for_state(weapon_state)
			if not weapon.is_empty() and _can_fire(unit, target, weapon): return true
	return false


func _ai_engagement_score_adjustments(pressure: float) -> Dictionary:
	return {"attack": 30.0 * pressure, "defend": -25.0 * pressure, "kite": -20.0 * pressure, "vanguard": 22.0 * pressure, "flank": 18.0 * pressure, "facility_capture": 18.0 * pressure, "fire_window": 12.0 * pressure}


func _reset_ai_passive_memory(unit: Dictionary, reset_movement: bool = true) -> void:
	var ai_state: Dictionary = unit.get("ai_state", {})
	ai_state["continuous_evasion_seconds"] = 0.0
	ai_state["no_engagement_seconds"] = 0.0
	ai_state["no_effective_attack_seconds"] = 0.0
	if reset_movement: ai_state["no_effective_movement_seconds"] = 0.0
	ai_state["engagement_pressure"] = 0.0
	ai_state["engagement_pressure_triggered"] = false
	ai_state["engagement_pressure_started_at"] = -1.0
	ai_state["passive_report_accumulator"] = 0.0


func _mark_ai_effective_attack(unit: Dictionary) -> void:
	if not _uses_full_ai(unit): return
	var ai_state: Dictionary = unit.get("ai_state", {})
	if bool(ai_state.get("engagement_pressure_triggered", false)):
		var response_time := maxf(0.0, float(state.get("elapsed_time", 0.0)) - float(ai_state.get("engagement_pressure_started_at", state.get("elapsed_time", 0.0))))
		_emit("AIEngagementPressureResolved", {"unit_id": unit.get("entity_id", ""), "response_time": response_time, "reason": "WEAPON_FIRED"})
	ai_state["last_effective_attack_at"] = float(state.get("elapsed_time", 0.0))
	_reset_ai_passive_memory(unit)


func _resolve_unit_overlap() -> void:
	var unit_ids := _sorted_unit_ids()
	for first_index in range(unit_ids.size()):
		var first: Dictionary = state["units_by_id"][unit_ids[first_index]]
		if first["life_state"] != "Alive": continue
		for second_index in range(first_index + 1, unit_ids.size()):
			var second: Dictionary = state["units_by_id"][unit_ids[second_index]]
			if second["life_state"] != "Alive": continue
			var delta_position: Vector2 = second["position"] - first["position"]
			var center_direction := delta_position.normalized() if delta_position.length_squared() > 0.0001 else Vector2.RIGHT
			var minimum_distance := CollisionGeometryService.separation_distance(
				_unit_collision_half_extents(first), float(first["heading"]),
				_unit_collision_half_extents(second), float(second["heading"]),
				center_direction,
			)
			if delta_position.length_squared() <= 0.0001 or delta_position.length() >= minimum_distance: continue
			var first_docked := not _docked_action_for_unit(str(first.get("entity_id", ""))).is_empty()
			var second_docked := not _docked_action_for_unit(str(second.get("entity_id", ""))).is_empty()
			if first_docked and second_docked: continue
			var correction_scale := 1.0 if first_docked or second_docked else 0.5
			var correction := delta_position.normalized() * (minimum_distance - delta_position.length()) * correction_scale
			var first_position: Vector2 = _clamp_to_map(first["position"] - correction)
			var second_position: Vector2 = _clamp_to_map(second["position"] + correction)
			if not first_docked and (not terrain_query.is_configured() or terrain_query.can_occupy_circle(first_position, float(first["stats"]["collision_radius"]), _movement_tags(first))):
				first["position"] = first_position
			if not second_docked and (not terrain_query.is_configured() or terrain_query.can_occupy_circle(second_position, float(second["stats"]["collision_radius"]), _movement_tags(second))):
				second["position"] = second_position


func _update_detection(delta: float = 0.1) -> void:
	for observer_faction in [PLAYER_FACTION, ENEMY_FACTION]:
		var previous_visible: Dictionary = state["visible_by_faction"][observer_faction]
		var next_visible := {}
		var next_contact_types := {}
		var newly_lost := {}
		for target_id in _sorted_unit_ids():
			var target: Dictionary = state["units_by_id"][target_id]
			if target["life_state"] != "Alive" or target["faction_id"] == observer_faction: continue
			var contact_types := _fleet_detection_types(observer_faction, target)
			if not contact_types.is_empty():
				next_visible[target_id] = true
				next_contact_types[target_id] = contact_types
		state["visible_by_faction"][observer_faction] = next_visible
		state["contact_types_by_faction"][observer_faction] = next_contact_types
		for target_id in next_visible:
			var target: Dictionary = state["units_by_id"][target_id]
			var contact_types: Array = next_contact_types.get(target_id, [])
			var primary_type := _primary_contact_type(contact_types)
			var previous_contact: Dictionary = state["contacts_by_faction"][observer_faction].get(target_id, {})
			state["contacts_by_faction"][observer_faction][target_id] = {"unit_id": target_id, "visible": true, "last_known_position": target["position"], "ghost_remaining": 0.0, "contact_types":contact_types.duplicate(), "primary_contact_type":primary_type, "contact_accuracy":"ExactPosition"}
			if not previous_visible.has(target_id):
				_emit("ContactAcquired", {"observer_faction": observer_faction, "target_unit_id": target_id, "position": target["position"], "contact_types":contact_types.duplicate(), "primary_contact_type":primary_type, "contact_accuracy":"ExactPosition"})
				if observer_faction == PLAYER_FACTION:
					for observer_id in _optical_detector_unit_ids(observer_faction, target):
						_record_tutorial_action("EstablishSharedContact", observer_id, {"target_unit_id": target_id})
			elif previous_contact.get("contact_types", []) != contact_types: _emit("ContactTypeChanged", {"observer_faction":observer_faction, "target_unit_id":target_id, "position":target["position"], "old_contact_types":previous_contact.get("contact_types", []).duplicate(), "contact_types":contact_types.duplicate(), "primary_contact_type":primary_type})
		for target_id in previous_visible:
			if next_visible.has(target_id): continue
			var target: Dictionary = state["units_by_id"].get(target_id, {})
			var last_position: Vector2 = target.get("position", Vector2.ZERO)
			var old_contact: Dictionary = state["contacts_by_faction"][observer_faction].get(target_id, {})
			state["contacts_by_faction"][observer_faction][target_id] = {"unit_id": target_id, "visible": false, "last_known_position": last_position, "ghost_remaining": CONTACT_GHOST_DURATION, "contact_types":old_contact.get("contact_types", []).duplicate(), "primary_contact_type":old_contact.get("primary_contact_type", "Optical"), "contact_accuracy":old_contact.get("contact_accuracy", "ExactPosition")}
			newly_lost[target_id] = true
			_emit("ContactLost", {"observer_faction": observer_faction, "target_unit_id": target_id, "last_known_position": last_position, "ghost_duration": CONTACT_GHOST_DURATION})
		for target_id in state["contacts_by_faction"][observer_faction].keys():
			var contact: Dictionary = state["contacts_by_faction"][observer_faction][target_id]
			if bool(contact.get("visible", false)) or newly_lost.has(target_id): continue
			contact["ghost_remaining"] = float(contact.get("ghost_remaining", 0.0)) - delta
			if float(contact["ghost_remaining"]) <= 0.0: state["contacts_by_faction"][observer_faction].erase(target_id)


func _update_projectile_observation() -> void:
	for observer_faction in [PLAYER_FACTION, ENEMY_FACTION]:
		var known: Dictionary = state["known_projectiles_by_faction"][observer_faction]
		for known_id in known.keys():
			if not state["projectiles_by_id"].has(known_id):
				known.erase(known_id)
		for projectile_id in state["projectiles_by_id"]:
			if known.has(projectile_id):
				continue
			var projectile: Dictionary = state["projectiles_by_id"][projectile_id]
			if str(projectile.get("faction_id", "")) == observer_faction:
				known[projectile_id] = true
				continue
			var base_distance := float(projectile.get("minimum_detection_distance", 0.0))
			if base_distance <= 0.0:
				continue
			for observer_id in _sorted_unit_ids():
				var observer: Dictionary = state["units_by_id"][observer_id]
				if observer.get("faction_id", "") != observer_faction or observer.get("life_state", "") != "Alive":
					continue
				var detection_distance := ModifierService.calculate(base_distance, _active_status_effects(observer), "TorpedoDetectionDistance", "Torpedo")
				if (observer.get("position", Vector2.ZERO) as Vector2).distance_to(projectile.get("position", Vector2.ZERO)) > detection_distance:
					continue
				known[projectile_id] = true
				_emit("ProjectileDetected", {"observer_faction": observer_faction, "observer_unit_id": observer_id, "projectile_id": projectile_id, "position": projectile.get("position", Vector2.ZERO)})
				break


func _update_mine_observation() -> void:
	var minefields: Dictionary = minefield_service.snapshot()
	for observer_faction in [PLAYER_FACTION, ENEMY_FACTION]:
		for mine_id in minefields:
			var mine: Dictionary = minefields[mine_id]
			if str(mine.get("mine_type", "")) != "DeployedMine" or str(mine.get("operation_state", "")) != "Active" or observer_faction in mine.get("known_by_faction", []): continue
			var base_distance := float(mine.get("detection_distance", 0.0))
			for observer_id in _sorted_unit_ids():
				var observer: Dictionary = state["units_by_id"][observer_id]
				if observer.get("faction_id", "") != observer_faction or observer.get("life_state", "") != "Alive": continue
				var detection_distance := ModifierService.calculate(base_distance, _active_status_effects(observer), "TorpedoDetectionDistance", "Torpedo")
				if (observer.get("position", Vector2.ZERO) as Vector2).distance_to(mine.get("position", Vector2.ZERO)) > detection_distance: continue
				if minefield_service.discover_deployed_mine(mine_id, observer_faction):
					_emit("MineDetected", {"observer_faction":observer_faction, "observer_unit_id":observer_id, "mine_id":mine_id, "position":mine.get("position", Vector2.ZERO), "detection_distance":detection_distance})
				break
	state["minefields_by_id"] = minefield_service.snapshot()


func _visible_projectiles(viewer_faction: String, omniscient: bool) -> Dictionary:
	if omniscient:
		return state.get("projectiles_by_id", {}).duplicate(true)
	var result := {}
	var known: Dictionary = state.get("known_projectiles_by_faction", {}).get(viewer_faction, {})
	for projectile_id in state.get("projectiles_by_id", {}):
		var projectile: Dictionary = state["projectiles_by_id"][projectile_id]
		if str(projectile.get("faction_id", "")) == viewer_faction or known.has(projectile_id):
			result[projectile_id] = projectile.duplicate(true)
	return result


func _fleet_detects(observer_faction: String, target: Dictionary) -> bool:
	return not _fleet_detection_types(observer_faction, target).is_empty()


func _fleet_detection_types(observer_faction: String, target: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var concealment := ModifierService.calculate(float(target["stats"]["concealment_distance"]), _active_status_effects(target), "ConcealmentDistance")
	if float(target["firing_reveal_remaining"]) > 0.0: concealment *= float(target["stats"]["fire_concealment_multiplier"])
	for observer_id in _sorted_unit_ids():
		var observer: Dictionary = state["units_by_id"][observer_id]
		if observer["faction_id"] != observer_faction or observer["life_state"] != "Alive": continue
		var detection_range := ModifierService.calculate(float(observer["stats"]["detection_range"]), _active_status_effects(observer), "DetectionRange")
		var observer_context := terrain_context_service.context_at(observer["position"])
		var target_context := terrain_context_service.context_at(target["position"])
		detection_range *= minf(float(observer_context.get("optical_visibility_multiplier", 1.0)), float(target_context.get("optical_visibility_multiplier", 1.0)))
		var distance := (observer["position"] as Vector2).distance_to(target["position"] as Vector2)
		if distance <= detection_range and distance <= concealment and terrain_query.has_surface_line_of_sight(observer["position"], target["position"]):
			result.append("Optical")
			break
	for source in facility_service.observation_sources(observer_faction):
		var source_position: Vector2 = source.get("position", Vector2.ZERO)
		var source_context := terrain_context_service.context_at(source_position)
		var target_context := terrain_context_service.context_at(target["position"])
		var detection_range := float(source.get("detection_range", 0.0))
		if bool(source.get("weather_affected", true)) or bool(source.get("time_affected", true)) or bool(source.get("local_visibility_affected", true)):
			detection_range *= minf(float(source_context.get("optical_visibility_multiplier", 1.0)), float(target_context.get("optical_visibility_multiplier", 1.0)))
		var distance := source_position.distance_to(target["position"])
		var line_of_sight_ok := not bool(source.get("line_of_sight_required", true)) or terrain_query.has_surface_line_of_sight(source_position, target["position"])
		if distance <= detection_range and distance <= concealment and line_of_sight_ok:
			if "Optical" not in result: result.append("Optical")
			break
	if str(target.get("radar_stealth_state", "Exposed")) != "Stealthed":
		for source in facility_service.radar_sources(observer_faction):
			var source_position: Vector2 = source.get("position", Vector2.ZERO)
			var distance := source_position.distance_to(target["position"])
			var line_of_sight_ok := not bool(source.get("line_of_sight_required", false)) or terrain_query.has_surface_line_of_sight(source_position, target["position"])
			if distance <= float(source.get("detection_range", 0.0)) and line_of_sight_ok:
				result.append("Radar")
				break
	for effect in state.get("support_effects_by_id", {}).values():
		if str(effect.get("effect_type", "")) != "Reconnaissance" or str(effect.get("faction_id", "")) != observer_faction: continue
		if (effect.get("position", Vector2.ZERO) as Vector2).distance_to(target["position"]) <= float(effect.get("radius", 0.0)):
			if "Optical" not in result: result.append("Optical")
			break
	for effect in state.get("skill_effects_by_id", {}).values():
		if str(effect.get("effect_type", "")) != "Reconnaissance" or str(effect.get("faction_id", "")) != observer_faction: continue
		if (effect.get("position", Vector2.ZERO) as Vector2).distance_to(target["position"]) <= float(effect.get("radius", 0.0)):
			if "Optical" not in result: result.append("Optical")
			break
	result.sort()
	return result


func _optical_detector_unit_ids(observer_faction: String, target: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var concealment := ModifierService.calculate(float(target["stats"]["concealment_distance"]), _active_status_effects(target), "ConcealmentDistance")
	if float(target["firing_reveal_remaining"]) > 0.0:
		concealment *= float(target["stats"]["fire_concealment_multiplier"])
	for observer_id in _sorted_unit_ids():
		var observer: Dictionary = state["units_by_id"][observer_id]
		if observer["faction_id"] != observer_faction or observer["life_state"] != "Alive": continue
		var detection_range := ModifierService.calculate(float(observer["stats"]["detection_range"]), _active_status_effects(observer), "DetectionRange")
		var observer_context := terrain_context_service.context_at(observer["position"])
		var target_context := terrain_context_service.context_at(target["position"])
		detection_range *= minf(float(observer_context.get("optical_visibility_multiplier", 1.0)), float(target_context.get("optical_visibility_multiplier", 1.0)))
		var distance := (observer["position"] as Vector2).distance_to(target["position"] as Vector2)
		if distance <= detection_range and distance <= concealment and terrain_query.has_surface_line_of_sight(observer["position"], target["position"]):
			result.append(observer_id)
	return result


func _primary_contact_type(contact_types: Array) -> String:
	return "Optical" if "Optical" in contact_types else ("Radar" if "Radar" in contact_types else "")


func _update_ai_intents() -> void:
	# Formation work runs on a deterministic 1 s time wheel.
	if int(state.get("tick_index", 0)) % 10 == 1:
		var group_factions: Array = _full_ai_factions.keys()
		group_factions.sort()
		for faction_id in group_factions:
			if bool(_full_ai_factions.get(faction_id, false)): _rebuild_ai_groups(str(faction_id))
	if int(state.get("tick_index", 0)) % 10 == 0:
		var support_factions: Array = _full_ai_factions.keys()
		support_factions.sort()
		for faction_id in support_factions:
			if bool(_full_ai_factions.get(faction_id, false)): _update_ai_support_intents(str(faction_id))
	for unit_id in _sorted_unit_ids():
		var unit: Dictionary = state["units_by_id"][unit_id]
		if unit["life_state"] != "Alive": continue
		if level_objective_service.uses_authored_staging_movement(unit): continue
		if str(unit.get("faction_id", "")) == PLAYER_FACTION and str(unit.get("movement_state", {}).get("mode", "")) in ["PlayerMoveOrder", "PlayerWaypointRoute"]:
			continue
		if _uses_full_ai(unit):
			_update_enemy_ai_intent(unit)
		else:
			_update_player_assist_intent(unit)
	_update_ai_primary_weapons()


func _update_auto_skills() -> void:
	for unit_id in _sorted_unit_ids():
		var unit: Dictionary = state["units_by_id"][unit_id]
		if level_objective_service.skill_locked_for(unit): continue
		if not _uses_full_ai(unit) or not bool(unit.get("skill_auto_cast_enabled", true)): continue
		if unit["life_state"] != "Alive" or float(unit["skill_state"]["cooldown_remaining"]) > 0.0: continue
		if float(unit["ai_state"].get("skill_decision_cooldown", 0.0)) > 0.0: continue
		unit["ai_state"]["skill_decision_cooldown"] = 1.0
		if int(unit.get("ai_state", {}).get("last_skill_command_tick", -1)) == int(state.get("tick_index", 0)): continue
		var skill: Dictionary = registry.get_definition("skills", str(unit["skill_state"]["definition_id"]))
		if skill.is_empty(): continue
		var target_ref := {}
		var target := _current_or_select_target(unit)
		match skill.get("target_type", "Self"):
			"Enemy":
				if target.is_empty(): continue
				target_ref = {"type": "Entity", "entity_id": target["entity_id"]}
			"Area":
				var area_position := _skill_ai_area_position(unit, skill, target)
				if area_position == Vector2.INF: continue
				target_ref = {"type": "Position", "position": area_position}
			_: target_ref = {"type": "Self"}
		var action_position: Vector2 = target_ref.get("position", target.get("position", unit.get("position", Vector2.ZERO)))
		if not _skill_action_rejection(unit, skill, action_position).is_empty(): continue
		if bool(_ai_profile.get("effect_reservations", true)) and _skill_effect_reservation_conflict(unit, skill, action_position):
			_emit("AISkillHeld", {"unit_id": unit_id, "skill_id": skill.get("id", ""), "reason": "EFFECT_RESERVED"})
			continue
		var skill_score := _skill_ai_score(unit, skill, target, target_ref)
		if skill_score < float(_ai_profile.get("skill_threshold", 60.0)):
			_emit("AISkillHeld", {"unit_id": unit_id, "skill_id": skill.get("id", ""), "reason": "VALUE_BELOW_THRESHOLD", "score": skill_score})
			continue
		var coordination_score := _skill_coordination_score(unit, skill, target)
		if _skill_requires_attack_coordination(skill) and coordination_score < float(_ai_profile.get("coordination_threshold", 70.0)):
			_emit("AISkillHeld", {"unit_id": unit_id, "skill_id": skill.get("id", ""), "reason": "COORDINATION_BELOW_THRESHOLD", "score": skill_score, "coordination_score": coordination_score})
			continue
		command_queue.push_front({
			"command_id": "ai.skill.%s.%s" % [state["tick_index"] + 1, unit_id],
			"command_type": "CastSkill",
			"issued_at_tick": state["tick_index"] + 1,
			"issuer_type": "AI",
			"issuer_id": unit["faction_id"],
			"unit_id": unit_id,
			"target_ref": target_ref,
		})
		unit["ai_state"]["last_skill_command_tick"] = int(state.get("tick_index", 0))
		if bool(_ai_profile.get("effect_reservations", true)): _reserve_ai_skill_effect(unit, skill, action_position)
		_emit("AISkillCommitted", {"unit_id": unit_id, "skill_id": skill.get("id", ""), "score": skill_score, "coordination_score": coordination_score})


func _skill_ai_area_position(unit: Dictionary, skill: Dictionary, target: Dictionary) -> Vector2:
	var tags: Array = skill.get("ai_tags", [])
	if "Recon" in tags:
		var contacts: Dictionary = _ai_observation_for(str(unit.get("faction_id", ""))).contact_ghosts
		for contact_id in contacts:
			var contact: Dictionary = contacts[contact_id]
			var position: Vector2 = contact.get("last_known_position", Vector2.INF)
			if (unit.get("position", Vector2.ZERO) as Vector2).distance_to(position) <= float(skill.get("cast_range", 0.0)):
				return position
	if not target.is_empty(): return target.get("position", Vector2.INF)
	return Vector2.INF


func _skill_ai_score(unit: Dictionary, skill: Dictionary, target: Dictionary, target_ref: Dictionary) -> float:
	var tags: Array = skill.get("ai_tags", [])
	var hp_safety := float(unit.get("current_hp", 0.0)) / maxf(1.0, float(unit.get("max_hp", 1.0)))
	var primary_ready := _primary_ready_ratio(unit)
	var target_value := 0.0 if target.is_empty() else _normalized_target_value(unit, target, false)
	var center: Vector2 = target_ref.get("position", unit.get("position", Vector2.ZERO))
	var radius := float(skill.get("effect_radius", 0.0))
	var ally_coverage := clampf(float(_allied_unit_count_in_radius(unit, center, radius)) / 3.0, 0.0, 1.0) if radius > 0.0 else 0.0
	var threat_match := 0.0
	if "AntiAir" in tags and (_visible_enemy_class_count(unit, ["Carrier"]) > 0 or _has_incoming_aviation(unit)): threat_match = 1.0
	if "AntiSubmarine" in tags and _visible_enemy_class_count(unit, ["Submarine"]) > 0: threat_match = 1.0
	if "TorpedoWarning" in tags and _known_hostile_torpedo_count(unit) > 0: threat_match = 1.0
	if "Recon" in tags: threat_match = maxf(threat_match, 1.0 if _has_hidden_contact(unit) else (0.65 if not target.is_empty() else 0.0))
	if "Defense" in tags: threat_match = maxf(threat_match, 1.0 - hp_safety)
	if "Burst" in tags or "AreaAttack" in tags: threat_match = maxf(threat_match, maxf(primary_ready, target_value))
	if tags.is_empty(): threat_match = maxf(target_value, 1.0 - hp_safety)
	var waste_risk := 0.0
	if ("Burst" in tags or "AreaAttack" in tags or skill.get("target_type", "Self") == "Enemy") and target.is_empty(): waste_risk = 1.0
	if ("AntiAir" in tags or "AntiSubmarine" in tags or "TorpedoWarning" in tags) and threat_match <= 0.0: waste_risk = 1.0
	return AIQuantitativeModel.skill_expected_value({
		"direct_value": maxf(target_value, threat_match),
		"coverage_value": maxf(ally_coverage, threat_match),
		"attack_synergy": primary_ready if ("Burst" in tags or "AreaAttack" in tags) else threat_match,
		"defense_urgency": (1.0 - hp_safety) if "Defense" in tags else threat_match * 0.5,
		"objective_value": 0.5 if not _ai_observation_for(str(unit.get("faction_id", ""))).known_facilities.is_empty() and ("Recon" in tags or "AreaSupport" in tags) else 0.0,
		"group_followup": maxf(_ally_weapon_readiness(unit), ally_coverage) if "AreaSupport" in tags else _ally_weapon_readiness(unit),
		"waste_risk": waste_risk,
		"exposure_cost": 0.2 if "Concealment" in tags and str(unit.get("depth_state", "Surface")) != "Submerged" else 0.0,
	})


func _skill_reservation_groups(skill: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for tag in skill.get("ai_tags", []):
		var semantic := str(tag)
		if semantic in ["Recon", "AntiAir", "AntiSubmarine", "TorpedoWarning", "AreaSupport", "Control"] and semantic not in result:
			result.append(semantic)
	result.sort()
	return result


func _skill_effect_reservation_conflict(unit: Dictionary, skill: Dictionary, center: Vector2) -> bool:
	var groups := _skill_reservation_groups(skill)
	if groups.is_empty(): return false
	var radius := maxf(120.0, float(skill.get("effect_radius", 0.0)))
	for reservation in _ai_effect_reservations.values():
		if reservation.get("faction_id", "") != unit.get("faction_id", ""): continue
		var shares_group := false
		for group in groups:
			if group in reservation.get("groups", []): shares_group = true; break
		if not shares_group: continue
		var other_center: Vector2 = reservation.get("center", Vector2.ZERO)
		var other_radius := float(reservation.get("radius", 120.0))
		if center.distance_to(other_center) <= radius + other_radius:
			return true
	return false


func _reserve_ai_skill_effect(unit: Dictionary, skill: Dictionary, center: Vector2) -> void:
	var groups := _skill_reservation_groups(skill)
	if groups.is_empty(): return
	var duration := float(skill.get("duration", 0.0))
	for zone in skill.get("recon_zones", []): duration = maxf(duration, float(zone.get("duration", 0.0)))
	_ai_effect_reservations[str(unit.get("entity_id", ""))] = {
		"source_unit_id": str(unit.get("entity_id", "")), "skill_id": str(skill.get("id", "")),
		"faction_id": str(unit.get("faction_id", "")), "groups": groups,
		"center": center, "radius": maxf(120.0, float(skill.get("effect_radius", 0.0))),
		"expires_at": float(state.get("elapsed_time", 0.0)) + maxf(1.5, duration),
	}
	_emit("AIEffectReserved", {"unit_id": unit.get("entity_id", ""), "skill_id": skill.get("id", ""), "groups": groups, "center": center, "radius": maxf(120.0, float(skill.get("effect_radius", 0.0))), "expires_at": _ai_effect_reservations[str(unit.get("entity_id", ""))]["expires_at"]})


func _expire_ai_effect_reservations() -> void:
	var now := float(state.get("elapsed_time", 0.0))
	for source_id in _ai_effect_reservations.keys():
		var reservation: Dictionary = _ai_effect_reservations[source_id]
		var source: Dictionary = state.get("units_by_id", {}).get(source_id, {})
		if float(reservation.get("expires_at", 0.0)) <= now or source.get("life_state", "") != "Alive":
			_ai_effect_reservations.erase(source_id)


func _skill_requires_attack_coordination(skill: Dictionary) -> bool:
	var tags: Array = skill.get("ai_tags", [])
	return "TargetAttack" in tags or "AreaAttack" in tags or "Burst" in tags


func _skill_coordination_score(unit: Dictionary, skill: Dictionary, target: Dictionary) -> float:
	if target.is_empty(): return 0.0
	var target_window := _normalized_target_value(unit, target, false)
	var battlefield := _battlefield_target_context(unit, target)
	var reserved_ratio := _reserved_damage_for_target(str(target.get("entity_id", "")), str(unit.get("entity_id", ""))) / maxf(1.0, float(target.get("current_hp", 1.0)))
	var task_timing := 1.0 if not str(unit.get("ai_state", {}).get("level_task", "")).is_empty() else 0.5
	return AIQuantitativeModel.coordination_score({
		"readiness_alignment": _primary_ready_ratio(unit),
		"target_window": target_window,
		"skill_synergy": 1.0,
		"crossfire_quality": float(battlefield.get("flank_quality", 0.0)),
		"reservation_fit": 1.0 - clampf(reserved_ratio, 0.0, 1.0),
		"objective_timing": task_timing,
		"overkill": clampf(reserved_ratio, 0.0, 1.0),
	})


func _allied_unit_count_in_radius(source: Dictionary, center: Vector2, radius: float) -> int:
	var count := 0
	for unit_id in _sorted_unit_ids():
		var unit: Dictionary = state["units_by_id"][unit_id]
		if unit.get("life_state", "") == "Alive" and unit.get("faction_id", "") == source.get("faction_id", "") and (unit.get("position", Vector2.ZERO) as Vector2).distance_to(center) <= radius: count += 1
	return count


func _visible_enemy_class_count(source: Dictionary, classes: Array) -> int:
	var count := 0
	var observation = _ai_observation_for(str(source.get("faction_id", "")))
	for target_id in observation.visible_enemies:
		var target: Dictionary = observation.visible_enemies.get(target_id, {})
		if str(target.get("stats", {}).get("ship_class", "")) in classes: count += 1
	return count


func _has_hidden_contact(source: Dictionary) -> bool:
	return not _ai_observation_for(str(source.get("faction_id", ""))).contact_ghosts.is_empty()


func _has_incoming_aviation(source: Dictionary) -> bool:
	for attack in delayed_attacks:
		var weapon: Dictionary = registry.get_definition("weapons", str(attack.get("source_weapon_id", "")))
		if str(weapon.get("mount_type", "")) != "Aviation": continue
		var attacker: Dictionary = state.get("units_by_id", {}).get(str(attack.get("source_unit_id", "")), {})
		if attacker.get("faction_id", "") == source.get("faction_id", ""): continue
		if (attack.get("target_position", Vector2.ZERO) as Vector2).distance_to(source.get("position", Vector2.ZERO)) <= 600.0: return true
	return false


func _known_hostile_torpedo_count(source: Dictionary) -> int:
	var count := 0
	var observation = _ai_observation_for(str(source.get("faction_id", "")))
	for projectile_id in observation.known_projectiles:
		var projectile: Dictionary = observation.known_projectiles.get(projectile_id, {})
		if not projectile.is_empty() and projectile.get("faction_id", "") != source.get("faction_id", ""): count += 1
	return count


func _queue_ai_move(unit: Dictionary, target_position: Vector2, issuer_type: String = "AI", movement_mode: String = "AutoNavigate") -> void:
	if str(unit.get("faction_id", "")) == PLAYER_FACTION and movement_mode != "ImmediateAvoidance" and str(unit.get("movement_state", {}).get("mode", "")) in ["PlayerMoveOrder", "PlayerWaypointRoute"]:
		return
	target_position = minefield_service.avoidance_waypoint(str(unit.get("faction_id", "")), unit["position"], target_position)
	var navigation: Dictionary = unit.get("navigation_state", {})
	var current_target: Vector2 = navigation.get("strategic_intent_target", unit.get("movement_state", {}).get("target_position", unit.get("position", Vector2.ZERO)))
	if issuer_type == "AI" and movement_mode != "ImmediateAvoidance":
		if int(navigation.get("pending_route_requests", 0)) > 0:
			var pending_target: Vector2 = navigation.get("pending_intent_target", current_target)
			if pending_target.distance_to(target_position) < 120.0: return
		var failed_target: Vector2 = navigation.get("failed_intent_target", current_target)
		var failed_origin: Vector2 = navigation.get("failed_intent_origin", unit.get("position", Vector2.ZERO))
		if failed_target.distance_to(target_position) < 120.0 and failed_origin.distance_to(unit.get("position", Vector2.ZERO)) <= 80.0 and float(state.get("elapsed_time", 0.0)) < float(navigation.get("route_retry_at", 0.0)):
			return
		var target_shift := current_target.distance_to(target_position)
		var since_route := float(state.get("elapsed_time", 0.0)) - float(unit.get("ai_state", {}).get("last_route_command_at", -1000.0))
		if since_route < NAVIGATION_STRATEGIC_INTERVAL or target_shift < 120.0: return
	if (unit["movement_state"].get("target_position", unit["position"]) as Vector2).distance_to(target_position) < 8.0: return
	command_queue.append({
		"command_id": "ai.move.%s.%s" % [state["tick_index"] + 1, unit["entity_id"]],
		"command_type": "MoveUnits",
		"issued_at_tick": state["tick_index"] + 1,
		"issuer_type": issuer_type,
		"issuer_id": unit["faction_id"],
		"unit_id": unit["entity_id"],
		"target_position": _clamp_to_map(target_position),
		"movement_mode": movement_mode,
	})
	if issuer_type == "AI": unit["ai_state"]["last_route_command_at"] = float(state.get("elapsed_time", 0.0))


func _cheap_ai_segment_clear(unit: Dictionary, start: Vector2, finish: Vector2) -> bool:
	var radius := float(unit.get("stats", {}).get("collision_radius", 20.0))
	if not terrain_query.can_occupy_circle(finish, radius, _movement_tags(unit)): return false
	return not bool(terrain_query.first_segment_hit(start, finish, "ShipMovement", radius).get("hit", false))


func _update_player_assist_intent(unit: Dictionary) -> void:
	var movement_mode := str(unit.get("movement_state", {}).get("mode", "HoldPosition"))
	if float(unit["ai_state"].get("decision_cooldown", 0.0)) > 0.0:
		return
	unit["ai_state"]["decision_cooldown"] = AI_DECISION_INTERVAL
	var target := _select_target_with_hysteresis(unit, true)
	if movement_mode in ["PlayerMoveOrder", "PlayerWaypointRoute"]:
		return
	if not bool(unit.get("movement_assist_enabled", false)):
		unit["movement_state"] = _new_movement_state("HoldPosition", unit["position"], [])
		_mark_navigation_dirty(unit)
		return
	var facility_id := str(unit.get("player_facility_target_id", ""))
	if not facility_id.is_empty():
		var known_facility: Dictionary = _ai_observation_for(PLAYER_FACTION).known_facilities.get(facility_id, {})
		if known_facility.is_empty() or known_facility.get("life_state", "") != "Alive":
			unit["player_facility_target_id"] = ""
		else:
			_queue_ai_move(unit, facility_service.interaction_center(facility_id), "PlayerAssistAI", "AssistNavigate")
			return
	if target.is_empty():
		unit["movement_state"] = _new_movement_state("HoldPosition", unit["position"], [])
		_mark_navigation_dirty(unit)
		return
	var tactic_scores := AIQuantitativeModel.player_assist_detected_tactic_scores(_detected_tactic_values(unit, target, true))
	var tactic_id := _update_ai_tactic(unit, tactic_scores)
	var destination := _tactical_destination(unit, target, tactic_id, "PlayerAssist")
	_queue_ai_move(unit, destination, "PlayerAssistAI", "AssistNavigate")


func _update_enemy_ai_intent(unit: Dictionary) -> void:
	if float(unit["ai_state"].get("decision_cooldown", 0.0)) > 0.0:
		return
	unit["ai_state"]["decision_cooldown"] = float(_ai_profile.get("decision_interval", AI_DECISION_INTERVAL))
	var target := _select_target_with_hysteresis(unit)
	var ai_state: Dictionary = unit["ai_state"]
	if not str(ai_state.get("level_task", "")).is_empty() and float(state.get("elapsed_time", 0.0)) - float(ai_state.get("task_started_at", 0.0)) >= 12.0:
		var active_action := facility_service.active_action_for_unit(str(unit.get("entity_id", "")))
		if not active_action.is_empty(): facility_service.cancel_action(str(active_action.get("facility_id", "")), str(unit.get("entity_id", "")))
		_record_ai_facility_failure(unit, str(ai_state.get("task_target_ref", {}).get("facility_id", "")))
	var facility_plan := _scheduled_ai_facility_plan(unit, target.is_empty())
	if not facility_plan.is_empty():
		if bool(facility_plan.get("hold_interaction", false)):
			return
		elif facility_plan.has("action_type"):
			_queue_ai_facility_action(unit, str(facility_plan["facility_id"]), str(facility_plan["action_type"]))
		else:
			_queue_ai_move(unit, facility_plan["target_position"])
		return
	_update_enemy_mode(unit, target)
	if target.is_empty():
		var context := terrain_context_service.context_at(unit["position"])
		var lee_center := terrain_context_service.zone_center_for_effect("environment.effect.lee_water")
		if int(context.get("sea_state", 0)) >= 4 and lee_center != Vector2.ZERO:
			_queue_ai_move(unit, lee_center)
			return
		var map_center := _map_center()
		var search_x := float(state["map"].get("width", 1200.0)) * (0.25 if float(unit["position"].x) >= map_center.x else 0.75)
		var faction_units: Array = _sorted_unit_ids().filter(func(unit_id):
			var candidate: Dictionary = state["units_by_id"].get(unit_id, {})
			return candidate.get("life_state", "") == "Alive" and candidate.get("faction_id", "") == unit.get("faction_id", "")
		)
		var lane_index := maxi(0, faction_units.find(str(unit.get("entity_id", ""))))
		var lane_spacing := minf(96.0, float(state["map"].get("height", 800.0)) * 0.5 / maxf(1.0, float(faction_units.size() - 1)))
		var lane_offset := (float(lane_index) - float(faction_units.size() - 1) * 0.5) * lane_spacing
		_queue_ai_move(unit, Vector2(search_x, map_center.y + lane_offset))
		return
	var tactic_scores := AIQuantitativeModel.detected_tactic_scores(_detected_tactic_values(unit, target, false))
	var tactic_id := _update_ai_tactic(unit, tactic_scores)
	var destination := _tactical_destination(unit, target, tactic_id, str(unit["ai_state"].get("mode_id", "VanguardLine")))
	_queue_ai_move(unit, destination)


func _scheduled_ai_facility_plan(unit: Dictionary, allow_capture: bool) -> Dictionary:
	var unit_id := str(unit.get("entity_id", ""))
	var now := float(state.get("elapsed_time", 0.0))
	var cached: Dictionary = _ai_objective_plan_cache.get(unit_id, {})
	if not cached.is_empty() and float(cached.get("expires_at", 0.0)) > now and bool(cached.get("allow_capture", false)) == allow_capture:
		return cached.get("plan", {}).duplicate(true)
	var plan := _ai_facility_plan(unit, allow_capture)
	_ai_objective_plan_cache[unit_id] = {"plan": plan.duplicate(true), "allow_capture": allow_capture, "expires_at": now + 2.0}
	return plan


func _update_enemy_mode(unit: Dictionary, target: Dictionary) -> void:
	var locked_mode := str(_ai_mode_locks_by_definition.get(str(unit.get("definition_id", "")), ""))
	if not locked_mode.is_empty():
		unit["ai_state"]["mode_id"] = locked_mode
		unit["ai_state"]["mode_candidate_id"] = ""
		unit["ai_state"]["mode_candidate_confirmations"] = 0
		return
	var scores := AIQuantitativeModel.mode_scores(_enemy_mode_values(unit, target))
	var allowed := _allowed_ai_modes(unit)
	var filtered := {}
	for mode_id in allowed:
		filtered[mode_id] = float(scores.get(mode_id, 0.0))
	var choice := AIQuantitativeModel.choose_highest(filtered)
	var ai_state: Dictionary = unit["ai_state"]
	var current_id := str(ai_state.get("mode_id", _default_ai_mode(unit.get("stats", {}))))
	var result := AIQuantitativeModel.switch_with_hysteresis({
		"current_id": current_id,
		"candidate_id": str(choice.get("id", current_id)),
		"previous_candidate_id": str(ai_state.get("mode_candidate_id", "")),
		"current_score": float(filtered.get(current_id, 0.0)),
		"candidate_score": float(choice.get("score", 0.0)),
		"elapsed_in_current": float(state.get("elapsed_time", 0.0)) - float(ai_state.get("mode_entered_at", 0.0)),
		"confirmations": int(ai_state.get("mode_candidate_confirmations", 0)),
		"current_legal": current_id in allowed,
	})
	ai_state["mode_candidate_id"] = str(choice.get("id", ""))
	ai_state["mode_candidate_confirmations"] = int(result.get("confirmations", 0))
	if bool(result.get("switch", false)):
		var new_mode := str(result.get("selected_id", current_id))
		ai_state["mode_id"] = new_mode
		ai_state["mode_entered_at"] = float(state.get("elapsed_time", 0.0))
		_emit("AIModeChanged", {"unit_id": unit["entity_id"], "old_mode_id": current_id, "new_mode_id": new_mode, "score": choice.get("score", 0.0), "reason": result.get("reason", "")})


func _set_ai_tactic(unit: Dictionary, tactic_id: String, score: float) -> void:
	var old_id := str(unit["ai_state"].get("tactic_id", ""))
	if old_id == tactic_id:
		return
	unit["ai_state"]["tactic_id"] = tactic_id
	unit["ai_state"]["tactic_entered_at"] = float(state.get("elapsed_time", 0.0))
	unit["ai_state"]["tactic_candidate_id"] = ""
	unit["ai_state"]["tactic_candidate_confirmations"] = 0
	_emit("AITacticChanged", {"unit_id": unit["entity_id"], "old_tactic_id": old_id, "new_tactic_id": tactic_id, "score": score})


func _update_ai_tactic(unit: Dictionary, scores: Dictionary) -> String:
	var choice := AIQuantitativeModel.choose_highest(scores)
	var ai_state: Dictionary = unit["ai_state"]
	var current_id := str(ai_state.get("tactic_id", "Defend"))
	var candidate_id := str(choice.get("id", current_id))
	var result := AIQuantitativeModel.switch_with_hysteresis({
		"current_id": current_id,
		"candidate_id": candidate_id,
		"previous_candidate_id": str(ai_state.get("tactic_candidate_id", "")),
		"current_score": float(scores.get(current_id, 0.0)),
		"candidate_score": float(choice.get("score", 0.0)),
		"elapsed_in_current": float(state.get("elapsed_time", 0.0)) - float(ai_state.get("tactic_entered_at", 0.0)),
		"confirmations": int(ai_state.get("tactic_candidate_confirmations", 0)),
		"minimum_hold": AI_TACTIC_MINIMUM_HOLD,
		"enter_threshold": 0.0,
		"switch_margin": AI_TACTIC_SWITCH_MARGIN,
	})
	ai_state["tactic_candidate_id"] = candidate_id
	ai_state["tactic_candidate_confirmations"] = int(result.get("confirmations", 0))
	if bool(result.get("switch", false)):
		_set_ai_tactic(unit, str(result.get("selected_id", current_id)), float(choice.get("score", 0.0)))
	return str(ai_state.get("tactic_id", current_id))


func _detected_tactic_values(unit: Dictionary, target: Dictionary, player_assist: bool) -> Dictionary:
	var local := _local_power_context(unit)
	var battlefield := _battlefield_target_context(unit, target)
	var hp_safety := float(unit.get("current_hp", 0.0)) / maxf(1.0, float(unit.get("max_hp", 1.0)))
	var preferred := _preferred_range(unit)
	var distance := (unit["position"] as Vector2).distance_to(target["position"])
	var range_advantage := clampf((distance - preferred * 0.6) / maxf(1.0, preferred * 0.8), 0.0, 1.0)
	var speed_advantage := clampf((float(unit["stats"].get("speed", 0.0)) - float(target["stats"].get("speed", 0.0))) / maxf(1.0, float(unit["stats"].get("speed", 1.0))), 0.0, 1.0)
	var values := {
		"local_advantage": float(local.get("advantage", 0.5)),
		"hp_safety": hp_safety,
		"weapon_ready": _primary_ready_ratio(unit),
		"target_opportunity": _normalized_target_value(unit, target, player_assist),
		"movement_safety": float(battlefield.get("position_safety", 0.0)),
		"position_safety": float(battlefield.get("position_safety", 0.0)),
		"attack_route_quality": float(battlefield.get("attack_route_quality", 0.0)),
		"exposure_risk": float(local.get("pressure", 0.0)),
		"range_advantage": range_advantage,
		"speed_advantage": speed_advantage,
		"exit_quality": float(battlefield.get("exit_quality", 0.0)),
		"weapon_cycle_value": 1.0 - _primary_ready_ratio(unit),
		"cooldown_need": 1.0 - _primary_ready_ratio(unit),
		"engagement_pressure": float(unit.get("ai_state", {}).get("engagement_pressure", 0.0)) if not player_assist else 0.0,
	}
	if not player_assist:
		values["skill_attack_value"] = 1.0 if float(unit["skill_state"].get("cooldown_remaining", 0.0)) <= 0.0 else 0.0
		values["group_followup"] = _ally_weapon_readiness(unit)
		values["group_support"] = float(local.get("friendly_ratio", 0.5))
		values["objective_defense"] = _protectee_threat(unit, target)
		values["cover_quality"] = 0.0
	return values


func _rebuild_ai_groups(faction_id: String) -> void:
	var members: Array = []
	for unit_id in _sorted_unit_ids():
		var unit: Dictionary = state["units_by_id"][unit_id]
		if unit.get("life_state", "") == "Alive" and unit.get("faction_id", "") == faction_id:
			members.append(unit)
	var groups := {}
	for start in range(0, members.size(), 4):
		var group_members: Array = members.slice(start, mini(start + 4, members.size()))
		var group_id := "group.%s.%02d" % [faction_id, start / 4 + 1]
		var leader: Dictionary = _choose_group_leader(group_members)
		var formation := _choose_group_formation(group_members)
		var member_ids: Array[String] = []
		for index in range(group_members.size()):
			var member: Dictionary = group_members[index]
			var role := _default_group_role(member, leader, index)
			member["ai_state"]["group_id"] = group_id
			member["ai_state"]["group_role"] = role
			member["ai_state"]["formation_id"] = formation
			member["ai_state"]["formation_slot_index"] = index
			member_ids.append(str(member["entity_id"]))
		groups[group_id] = {"group_id": group_id, "leader_unit_id": leader.get("entity_id", ""), "member_ids": member_ids, "formation_id": formation}
	state["ai_groups_by_faction"][faction_id] = groups


func _choose_group_leader(members: Array) -> Dictionary:
	var candidates := members.duplicate()
	candidates.sort_custom(func(a, b):
		if bool(a.get("is_flagship", false)) != bool(b.get("is_flagship", false)): return bool(a.get("is_flagship", false))
		var cost_a := float(a.get("stats", {}).get("cost", 0.0))
		var cost_b := float(b.get("stats", {}).get("cost", 0.0))
		return cost_a > cost_b if not is_equal_approx(cost_a, cost_b) else str(a.get("entity_id", "")) < str(b.get("entity_id", "")))
	return {} if candidates.is_empty() else candidates[0]


func _choose_group_formation(members: Array) -> String:
	if members.is_empty(): return "Wedge"
	var faction_id := str(members[0].get("faction_id", ""))
	var observation = _ai_observation_for(faction_id)
	for projectile in observation.known_projectiles.values():
		if projectile.get("faction_id", "") != faction_id: return "Dispersed"
	for member in members:
		if str(member.get("stats", {}).get("ship_class", "")) == "Carrier": return "Screen"
	if terrain_query.is_configured(): return "Column"
	if not observation.visible_enemies.is_empty(): return "Wedge"
	return "LineAbreast"


func _default_group_role(unit: Dictionary, leader: Dictionary, slot_index: int) -> String:
	if unit.get("entity_id", "") == leader.get("entity_id", ""):
		return "Fixer" if str(unit.get("stats", {}).get("ship_class", "")) != "Carrier" else "FireSupport"
	match str(unit.get("stats", {}).get("ship_class", "")):
		"Carrier", "Battleship": return "FireSupport"
		"Submarine": return "Flanker"
		"Destroyer": return "Scout" if slot_index == 1 else "Flanker"
		"LightCruiser": return "Screen"
		_: return "Screen" if bool(leader.get("is_flagship", false)) else "Fixer"


func _tactical_destination(unit: Dictionary, target: Dictionary, tactic_id: String, mode_id: String) -> Vector2:
	var base := _tactical_destination_without_formation(unit, target, tactic_id, mode_id)
	if terrain_query.is_configured() and (tactic_id in ["Defend", "Kite"] or mode_id in ["ReconAvoid", "DisengageRegroup"]):
		var cover := _best_ai_cover_position(unit, target)
		if float(cover.get("score", 0.0)) >= 60.0:
			base = cover.get("position", base)
	return _apply_group_formation(unit, target, base)


func _tactical_destination_without_formation(unit: Dictionary, target: Dictionary, tactic_id: String, mode_id: String) -> Vector2:
	var unit_position: Vector2 = unit["position"]
	var target_position: Vector2 = target["position"]
	var away := (unit_position - target_position).normalized()
	if away == Vector2.ZERO: away = Vector2.RIGHT.rotated(float(unit["heading"]) + PI)
	var preferred := _preferred_range(unit)
	var distance := unit_position.distance_to(target_position)
	if tactic_id == "Kite" or mode_id in ["DisengageRegroup", "CarrierStandoff"]:
		return _clamp_to_map(unit_position + away * maxf(160.0, preferred * 0.35))
	if tactic_id == "Defend" or mode_id == "EscortScreen":
		if mode_id == "EscortScreen":
			var flagship := _faction_flagship(unit["faction_id"])
			if not flagship.is_empty():
				return _clamp_to_map((flagship["position"] as Vector2).lerp(target_position, 0.25))
		return unit_position if distance >= preferred * 0.55 else _clamp_to_map(unit_position + away * 120.0)
	if mode_id == "TorpedoFlank":
		var toward := (target_position - unit_position).normalized()
		var side_sign := -1.0 if abs(str(unit["entity_id"]).hash()) % 2 == 0 else 1.0
		return _clamp_to_map(target_position - toward * preferred * 0.75 + toward.orthogonal() * preferred * 0.45 * side_sign)
	if distance > preferred * 0.9:
		return target_position
	if distance < preferred * 0.5:
		return _clamp_to_map(unit_position + away * 140.0)
	return unit_position


func _apply_group_formation(unit: Dictionary, target: Dictionary, base: Vector2) -> Vector2:
	var ai_state: Dictionary = unit.get("ai_state", {})
	if str(ai_state.get("level_task", "")) in ["CaptureFacility", "ServiceFacility"]: return base
	var group: Dictionary = state.get("ai_groups_by_faction", {}).get(unit.get("faction_id", ""), {}).get(str(ai_state.get("group_id", "")), {})
	if group.is_empty() or group.get("member_ids", []).size() <= 1: return base
	var leader: Dictionary = state.get("units_by_id", {}).get(str(group.get("leader_unit_id", "")), {})
	if leader.is_empty() or leader.get("life_state", "") != "Alive": return base
	var heading := float(leader.get("heading", 0.0))
	if not target.is_empty(): heading = (target.get("position", leader["position"]) - leader["position"]).angle()
	var forward := Vector2.RIGHT.rotated(heading)
	var side := forward.orthogonal()
	var index := int(ai_state.get("formation_slot_index", 0))
	var spacing := 150.0
	var offset := Vector2.ZERO
	match str(ai_state.get("formation_id", "Wedge")):
		"Column": offset = -forward * spacing * float(index)
		"LineAbreast": offset = side * spacing * (float(index) - float(group.get("member_ids", []).size() - 1) * 0.5)
		"Screen":
			var ring_index := maxi(0, index - 1)
			offset = Vector2.RIGHT.rotated(heading + PI + (-0.65 + 1.3 * float(ring_index % 2))) * spacing
		"Dispersed": offset = Vector2.RIGHT.rotated(float(index) * TAU / float(group.get("member_ids", []).size())) * spacing * 1.5
		_: offset = -forward * spacing * float((index + 1) / 2) + side * spacing * (-1.0 if index % 2 == 1 else 1.0) * float((index + 1) / 2)
	var slot: Vector2 = leader.get("position", Vector2.ZERO) + offset
	if unit.get("entity_id", "") == leader.get("entity_id", ""): return base
	var distance := (unit.get("position", Vector2.ZERO) as Vector2).distance_to(slot)
	if distance <= 70.0: return base
	var correction_weight := 0.65 if distance > 300.0 else 0.35
	return _clamp_to_map(base.lerp(slot, correction_weight))


func _best_ai_cover_position(unit: Dictionary, target: Dictionary) -> Dictionary:
	if target.is_empty(): return {}
	var cache_key := "%s|%s" % [unit.get("entity_id", ""), target.get("entity_id", "")]
	var cached: Dictionary = _ai_cover_cache.get(cache_key, {})
	var now := float(state.get("elapsed_time", 0.0))
	var origin: Vector2 = unit.get("position", Vector2.ZERO)
	if not cached.is_empty() and float(cached.get("expires_at", 0.0)) > now and (cached.get("origin", origin) as Vector2).distance_to(origin) <= 300.0:
		return cached.get("result", {}).duplicate(true)
	var obstacle_candidates: Array = []
	for obstacle in terrain_query.obstacles:
		if "ShellTravel" not in obstacle.get("block_mask", []) and "SurfaceOpticalLineOfSight" not in obstacle.get("block_mask", []): continue
		var polygon := _polygon(obstacle.get("polygon", []))
		if polygon.is_empty(): continue
		var center := Vector2.ZERO
		for point in polygon: center += point
		center /= float(polygon.size())
		obstacle_candidates.append({"obstacle": obstacle, "polygon": polygon, "center": center, "distance": (unit.get("position", Vector2.ZERO) as Vector2).distance_to(center)})
	obstacle_candidates.sort_custom(func(a, b): return float(a["distance"]) < float(b["distance"]) if not is_equal_approx(float(a["distance"]), float(b["distance"])) else str(a["obstacle"].get("id", "")) < str(b["obstacle"].get("id", "")))
	var limit := mini(obstacle_candidates.size(), 3)
	var best := {}
	for index in range(limit):
		var item: Dictionary = obstacle_candidates[index]
		var center: Vector2 = item["center"]
		var away_from_target := (center - (target.get("position", Vector2.ZERO) as Vector2)).normalized()
		if away_from_target == Vector2.ZERO: continue
		var obstacle_radius := 0.0
		for point in item["polygon"]: obstacle_radius = maxf(obstacle_radius, center.distance_to(point))
		var candidate := _clamp_to_map(center + away_from_target * (obstacle_radius + float(unit.get("stats", {}).get("collision_radius", 20.0)) + 35.0))
		if not terrain_query.can_occupy_circle(candidate, float(unit.get("stats", {}).get("collision_radius", 20.0)), _movement_tags(unit)): continue
		var route_quality := 1.0 if _cheap_ai_segment_clear(unit, unit.get("position", Vector2.ZERO), candidate) else 0.0
		if route_quality <= 0.0: continue
		var exit_count := 0
		for exit_index in range(8):
			var exit_point := candidate + Vector2.RIGHT.rotated(float(exit_index) * TAU / 8.0) * 140.0
			if terrain_query.is_movement_segment_clear(candidate, exit_point, float(unit.get("stats", {}).get("collision_radius", 20.0)), _movement_tags(unit)): exit_count += 1
		var shell_block := 0.0 if terrain_query.is_segment_clear(candidate, target.get("position", Vector2.ZERO), "ShellTravel") else 1.0
		var los_break := 0.0 if terrain_query.has_surface_line_of_sight(candidate, target.get("position", Vector2.ZERO)) else 1.0
		var distance_fit := _range_fit({"position": candidate, "weapon_states": unit.get("weapon_states", []), "stats": unit.get("stats", {})}, target)
		var score := AIQuantitativeModel.cover_score({
			"reachable": true, "exit_count": exit_count,
			"shell_block": shell_block, "line_of_sight_break": los_break,
			"exit_quality": clampf(float(exit_count) / 4.0, 0.0, 1.0),
			"weapon_access": maxf(0.35, distance_fit), "turn_room": clampf(float(exit_count) / 6.0, 0.0, 1.0),
			"distance_fit": distance_fit, "group_support": _formation_fit_at(unit, candidate),
			"dead_end_risk": 1.0 - clampf(float(exit_count) / 2.0, 0.0, 1.0), "depth_risk": 0.0,
		})
		if best.is_empty() or score > float(best.get("score", 0.0)):
			best = {"position": candidate, "score": score, "obstacle_id": item["obstacle"].get("id", ""), "exit_count": exit_count}
	_ai_cover_cache[cache_key] = {"result": best.duplicate(true), "origin": origin, "expires_at": now + 10.0}
	if not best.is_empty(): _emit("AICoverSelected", {"unit_id": unit.get("entity_id", ""), "position": best["position"], "score": best["score"], "obstacle_id": best["obstacle_id"], "exit_count": best["exit_count"]})
	return best


func _update_ai_primary_weapons() -> void:
	for unit_id in _sorted_unit_ids():
		var unit: Dictionary = state["units_by_id"][unit_id]
		if unit.get("life_state", "") != "Alive": continue
		if level_objective_service.primary_locked_for(unit): continue
		if float(unit["ai_state"].get("fire_decision_cooldown", 0.0)) > 0.0: continue
		unit["ai_state"]["fire_decision_cooldown"] = 0.5
		var player_assist := not _uses_full_ai(unit)
		if player_assist and (not bool(unit.get("primary_auto_fire_enabled", false)) or bool(unit.get("primary_auto_fire_suspended", false))): continue
		if int(unit["ai_state"].get("last_primary_command_tick", -1)) == int(state.get("tick_index", 0)): continue
		if _primary_ready_ratio(unit) <= 0.0: continue
		var target := _current_or_select_target(unit, player_assist)
		if target.is_empty(): continue
		unit["targeting_state"]["current_target_id"] = str(target["entity_id"])
		var primary_states := _weapon_states_for_group(unit, str(unit["stats"].get("primary_weapon_group_id", "")), true)
		if primary_states.is_empty(): continue
		var enabled_primary_states := primary_states.filter(func(weapon_state): return bool(weapon_state.get("enabled", true)))
		if enabled_primary_states.is_empty(): continue
		var aim_weapon := _weapon_for_state(enabled_primary_states[0])
		var aim_solution := _automatic_aim_solution(unit, target, aim_weapon)
		if aim_solution.is_empty(): continue
		var aim_position: Vector2 = aim_solution.get("position", target["position"])
		var validation := _validate_primary_fire(unit, primary_states, aim_position)
		if not bool(validation.get("legal", false)): continue
		var window_values := {
			"target_value": _normalized_target_value(unit, target, player_assist),
			"hit_quality": _weapon_hit_quality(unit, target, aim_weapon),
			"weapon_ready": _primary_ready_ratio(unit),
			"expected_damage": _expected_weapon_damage_ratio(unit, target, aim_weapon),
			"kill_opportunity": 1.0 - float(target.get("current_hp", 0.0)) / maxf(1.0, float(target.get("max_hp", 1.0))),
			"position_safety": 1.0 - _boundary_risk(unit),
			"exposure_risk": float(_local_power_context(unit).get("pressure", 0.0)),
			"friendly_risk": _friendly_fire_risk(unit, target, aim_weapon, aim_position),
			"skill_synergy": 1.0 if float(unit["skill_state"].get("cooldown_remaining", 0.0)) <= 0.0 else 0.0,
			"group_sync": _attack_window_group_sync(unit),
			"objective_relevance": _protectee_threat(unit, target),
			"overkill": clampf(_reserved_damage_for_target(str(target.get("entity_id", "")), str(unit.get("entity_id", ""))) / maxf(1.0, float(target.get("current_hp", 1.0))), 0.0, 1.0),
			"engagement_pressure": 0.0 if player_assist else float(unit.get("ai_state", {}).get("engagement_pressure", 0.0)),
			"visible": true,
			"weapon_legal": true,
			"path_clear": true,
		}
		var fire := AIQuantitativeModel.player_assist_execution(unit, window_values) if player_assist else AIQuantitativeModel.should_fire(window_values, _fire_discipline_for_mode(str(unit["ai_state"].get("mode_id", "VanguardLine"))), _is_unit_under_threat(unit, target), _is_unit_in_fire_emergency(unit, target))
		if not bool(fire.get("primary_auto_fire", fire.get("fire", false))): continue
		command_queue.append({
			"command_id": "ai.primary.%s.%s" % [state["tick_index"] + 1, unit_id],
			"command_type": "FirePrimaryWeapon",
			"issued_at_tick": state["tick_index"] + 1,
			"issuer_type": "PlayerAssistAI" if player_assist else "AI",
			"issuer_id": unit["faction_id"],
			"unit_id": unit_id,
			"target_position": aim_position,
		})
		unit["ai_state"]["last_primary_command_tick"] = int(state.get("tick_index", 0))
		_reserve_ai_damage(unit, target, aim_weapon)
		_emit("AIFireCommitted", {"unit_id": unit_id, "target_unit_id": target["entity_id"], "score": fire.get("primary_score", fire.get("score", 0.0))})


func _uses_full_ai(unit: Dictionary) -> bool:
	if str(unit.get("faction_id", "")) == PLAYER_FACTION and not str(state.get("level_objective", {}).get("objective_set_id", "")).is_empty():
		return bool(unit.get("movement_assist_enabled", false))
	return bool(_full_ai_factions.get(str(unit.get("faction_id", "")), false))


func _highest_projectile_threat(unit: Dictionary) -> Dictionary:
	var best := {"score": 0.0, "projectile": {}}
	var observation = _ai_observation_for(str(unit.get("faction_id", "")))
	var projectile_ids: Array = observation.known_projectiles.keys()
	projectile_ids.sort()
	for projectile_id in projectile_ids:
		var projectile: Dictionary = observation.known_projectiles.get(projectile_id, {})
		if projectile.is_empty() or projectile.get("faction_id", "") == unit.get("faction_id", ""): continue
		var projectile_velocity := Vector2.RIGHT.rotated(float(projectile.get("heading", 0.0))) * float(projectile.get("speed", 0.0))
		var unit_velocity := Vector2.RIGHT.rotated(float(unit.get("heading", 0.0))) * float(unit.get("current_speed", 0.0))
		var relative_position: Vector2 = projectile["position"] - unit["position"]
		var relative_velocity := projectile_velocity - unit_velocity
		var speed_squared := relative_velocity.length_squared()
		if speed_squared <= 0.001: continue
		var time_to_cpa := clampf(-relative_position.dot(relative_velocity) / speed_squared, 0.0, 12.0)
		var cpa_distance := (relative_position + relative_velocity * time_to_cpa).length()
		var danger_radius := _unit_collision_half_extents(unit).y + float(projectile.get("collision_radius", 8.0)) + 24.0
		var ship_class := str(unit["stats"].get("ship_class", ""))
		var reaction_horizon := 8.0 if ship_class in ["Battleship", "Carrier"] else (7.0 if ship_class in ["LightCruiser", "HeavyCruiser"] else 6.0)
		var left_turn := absf(wrapf(float(projectile.get("heading", 0.0)) + PI * 0.5 - float(unit.get("heading", 0.0)), -PI, PI))
		var right_turn := absf(wrapf(float(projectile.get("heading", 0.0)) - PI * 0.5 - float(unit.get("heading", 0.0)), -PI, PI))
		var turn_angle := minf(left_turn, right_turn)
		var turn_speed := deg_to_rad(maxf(1.0, ModifierService.calculate(float(unit.get("stats", {}).get("turn_speed", 1.0)), unit.get("status_effects", []), "TurnSpeed")))
		var turn_time := turn_angle / turn_speed
		var score := AIQuantitativeModel.torpedo_threat_score({
			"visible": true, "approaching": relative_position.dot(relative_velocity) < 0.0,
			"reaction_horizon": reaction_horizon, "time_to_cpa": time_to_cpa,
			"danger_radius": danger_radius, "cpa_distance": cpa_distance,
			"expected_damage_ratio": _projectile_expected_damage_ratio(projectile, unit),
			"maneuver_margin": clampf((time_to_cpa - turn_time) / maxf(0.1, time_to_cpa), 0.0, 1.0),
		})
		if score > float(best["score"]):
			best = {"score": score, "projectile": projectile}
	return best


func _projectile_expected_damage_ratio(projectile: Dictionary, target: Dictionary) -> float:
	var weapon: Dictionary = registry.get_definition("weapons", str(projectile.get("source_weapon_id", "")))
	var formula: Dictionary = registry.get_definition("formulas", str(weapon.get("formula_id", "")))
	if weapon.is_empty() or formula.is_empty():
		return 0.5
	var coefficient := float(formula.get("power_coefficient", 0.0))
	var inferred_power := 0.0
	if coefficient > 0.0:
		inferred_power = maxf(0.0, (float(projectile.get("observed_raw_damage", formula.get("base_damage", 0.0))) - float(formula.get("base_damage", 0.0))) / coefficient)
	var source := {"position": projectile.get("position", Vector2.ZERO), "stats": {_power_stat_for_weapon(weapon): inferred_power}, "status_effects": []}
	var estimate := DamageService.estimate_attack({"accuracy_modifier": 0.0}, source, target, weapon, formula)
	return clampf(float(estimate.get("damage_on_hit", 0.0)) / maxf(1.0, float(target.get("current_hp", 1.0))), 0.0, 1.0)


func _power_stat_for_weapon(weapon: Dictionary) -> String:
	match str(weapon.get("mount_type", "Gun")):
		"Torpedo": return "torpedo_power"
		"Aviation": return "aviation_power"
		"AntiAir": return "anti_air_power"
		"AntiSubmarine": return "anti_submarine_power"
		_: return "gunnery_power"


func _ai_facility_plan(unit: Dictionary, allow_capture: bool) -> Dictionary:
	var observation = _ai_observation_for(str(unit.get("faction_id", "")))
	var facilities: Dictionary = observation.known_facilities
	var candidates: Array = []
	var hp_ratio := float(unit.get("current_hp", 0.0)) / maxf(1.0, float(unit.get("max_hp", 1.0)))
	var capture_slot_available := _facility_capture_slot_available(unit)
	for facility_id in facilities:
		var facility: Dictionary = facilities[facility_id]
		if str(unit.get("ai_state", {}).get("task_blocked_facility_id", "")) == str(facility_id) and float(unit.get("ai_state", {}).get("task_blocked_until", 0.0)) > float(state.get("elapsed_time", 0.0)): continue
		if str(facility.get("life_state", "")) != "Alive": continue
		var definition := facility_service.definition_for(str(facility_id))
		var action_type := ""
		var task_type := ""
		var objective_role := ""
		var score := 0.0
		var center := facility_service.interaction_center(str(facility_id))
		var contest_pressure := _facility_contest_pressure(unit, center)
		var is_repair: bool = hp_ratio < 0.55 and facility_service.is_operational(str(facility_id)) and facility.get("faction_id") == unit.get("faction_id") and str(definition.get("berthing_service", {}).get("service_type", "")) == "Repair"
		var is_control: bool = allow_capture and capture_slot_available and "AreaControl" in definition.get("operation_modes", []) and bool(definition.get("area_control", {}).get("enabled", false)) and bool(definition.get("area_control", {}).get("capturable", false)) and (facility.get("faction_id") != unit.get("faction_id") or facility.get("operation_state") == "Dormant")
		var is_defense: bool = facility.get("faction_id") == unit.get("faction_id") and facility_service.is_operational(str(facility_id)) and contest_pressure > 0.0
		if not is_repair and not is_control and not is_defense: continue
		var distance := (unit["position"] as Vector2).distance_to(center)
		var path_quality := _facility_route_quality(unit, str(facility_id), center)
		var saturation := _facility_assignment_saturation(unit, str(facility_id), 1)
		var facility_value := _facility_value(definition)
		var role_fit := _facility_role_fit(unit, definition)
		if is_repair:
			action_type = "Service"
			task_type = "ServiceFacility"
			score = 100.0 * (0.55 * (1.0 - hp_ratio) + 0.25 * path_quality + 0.20 * (1.0 - saturation))
		elif is_control:
			action_type = "Control"
			task_type = "CaptureFacility"
			score = AIQuantitativeModel.facility_capture_score({
				"known": true, "seizable": true, "path_valid": path_quality > 0.0,
				"facility_value": facility_value, "survival": hp_ratio,
				"path_quality": path_quality, "role_fit": role_fit,
				"ownership_need": 1.0, "followup_value": facility_value,
				"time_margin": _facility_time_margin(unit, definition, distance),
				"contest_pressure": contest_pressure, "assignment_saturation": saturation,
				"engagement_pressure": float(unit.get("ai_state", {}).get("engagement_pressure", 0.0)),
			})
		elif is_defense:
			task_type = "DefendFacility"
			objective_role = _facility_defense_role(unit)
			saturation = _facility_assignment_saturation(unit, str(facility_id), 3)
			score = AIQuantitativeModel.facility_defense_score({
				"known": true, "owned": true, "path_valid": path_quality > 0.0,
				"facility_value": facility_value, "capture_threat": contest_pressure,
				"reach_quality": path_quality, "role_fit": role_fit,
				"ally_need": 1.0 - saturation, "defensive_position": _position_safety(unit, center),
				"local_disadvantage": float(_local_power_context(unit).get("pressure", 0.0)),
				"assignment_saturation": saturation,
			})
			center = _facility_defense_position(unit, center, objective_role)
		if task_type.is_empty(): continue
		var active_action := facility_service.active_action_for_unit(str(unit.get("entity_id", "")))
		if not action_type.is_empty() and active_action.is_empty() and (not facility.get("control_state", {}).is_empty() or not facility.get("service_state", {}).is_empty()): continue
		var threshold := 60.0 if task_type == "DefendFacility" else (35.0 if task_type == "ServiceFacility" else 42.0)
		if score < threshold: continue
		candidates.append({"facility_id": str(facility_id), "action_type": action_type, "task_type": task_type, "objective_role": objective_role, "target_position": center, "score": score})
	if candidates.is_empty():
		_clear_ai_facility_task(unit)
		return {}
	candidates.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]) if not is_equal_approx(float(a["score"]), float(b["score"])) else str(a["facility_id"]) < str(b["facility_id"]))
	var selected: Dictionary = candidates[0]
	_set_ai_facility_task(unit, selected)
	var selected_facility: Dictionary = facilities[selected["facility_id"]]
	if str(selected.get("task_type", "")) == "DefendFacility":
		return {"target_position": selected["target_position"], "task_type": selected["task_type"], "score": selected["score"]}
	var selected_action := facility_service.active_action_for_unit(str(unit.get("entity_id", "")))
	if not selected_action.is_empty() and str(selected_action.get("facility_id", "")) == str(selected["facility_id"]):
		if Geometry2D.is_point_in_polygon(unit["position"], _polygon(selected_facility.get("interaction_water_polygon", []))):
			return {"hold_interaction": true, "facility_id": selected["facility_id"], "task_type": selected["task_type"], "score": selected["score"]}
		return {"target_position": selected["target_position"], "task_type": selected["task_type"], "score": selected["score"]}
	if str(selected.get("action_type", "")) == "Control":
		return {"facility_id": selected["facility_id"], "action_type": "Control", "task_type": selected["task_type"], "score": selected["score"]}
	if Geometry2D.is_point_in_polygon(unit["position"], _polygon(selected_facility.get("interaction_water_polygon", []))):
		return {"facility_id": selected["facility_id"], "action_type": selected["action_type"], "task_type": selected["task_type"], "score": selected["score"]}
	return {"target_position": selected["target_position"], "task_type": selected["task_type"], "score": selected["score"]}


func _facility_value(definition: Dictionary) -> float:
	var weights := {
		"ObservationSource": 0.90, "SensorSource": 0.85, "WeaponPlatform": 0.90,
		"SupportMissionProvider": 1.0, "CommandRelay": 0.75, "HazardController": 0.90,
		"ServiceProvider": 0.72,
	}
	var best := 0.35
	for capability in definition.get("capabilities", []):
		best = maxf(best, float(weights.get(str(capability), 0.35)))
	return best


func _facility_capture_slot_available(unit: Dictionary) -> bool:
	if str(unit.get("ai_state", {}).get("level_task", "")) == "CaptureFacility": return true
	for ally_id in _sorted_unit_ids():
		var ally: Dictionary = state["units_by_id"][ally_id]
		if ally.get("entity_id", "") == unit.get("entity_id", "") or ally.get("life_state", "") != "Alive" or ally.get("faction_id", "") != unit.get("faction_id", ""): continue
		if str(ally.get("ai_state", {}).get("level_task", "")) == "CaptureFacility": return false
	return true


func _facility_defense_role(unit: Dictionary) -> String:
	match str(unit.get("stats", {}).get("ship_class", "")):
		"Destroyer", "LightCruiser": return "ApproachIntercept"
		"Battleship", "Carrier": return "FireSupport"
		_: return "InnerGuard"


func _facility_defense_position(unit: Dictionary, center: Vector2, role: String) -> Vector2:
	var observation = _ai_observation_for(str(unit.get("faction_id", "")))
	var threat_position := center
	var nearest := INF
	for enemy in observation.visible_enemies.values():
		var distance := center.distance_to(enemy.get("position", Vector2.ZERO))
		if distance < nearest: nearest = distance; threat_position = enemy.get("position", center)
	var toward := (threat_position - center).normalized()
	if toward == Vector2.ZERO: toward = Vector2.RIGHT.rotated(float(unit.get("heading", 0.0)))
	match role:
		"ApproachIntercept": return _clamp_to_map(center + toward * 260.0)
		"FireSupport": return _clamp_to_map(center - toward * minf(480.0, _preferred_range(unit) * 0.45))
		_: return center


func _facility_route_quality(unit: Dictionary, facility_id: String, center: Vector2) -> float:
	var key := "%s|%s" % [unit.get("entity_id", ""), facility_id]
	var cached: Dictionary = _ai_facility_route_cache.get(key, {})
	var now := float(state.get("elapsed_time", 0.0))
	var origin: Vector2 = unit.get("position", Vector2.ZERO)
	if not cached.is_empty() and float(cached.get("expires_at", 0.0)) > now and (cached.get("origin", origin) as Vector2).distance_to(origin) <= 80.0:
		return float(cached.get("quality", 0.0))
	var direct_clear := not terrain_query.is_configured() or _cheap_ai_segment_clear(unit, origin, center)
	var distance_fit := clampf(1.0 - origin.distance_to(center) / maxf(1200.0, _preferred_range(unit) * 2.0), 0.0, 1.0)
	# Objective scoring only needs a stable reach estimate. The selected command performs
	# authoritative path planning; blocked direct lines receive a conservative detour score.
	var quality := (0.75 + 0.25 * distance_fit) if direct_clear else (0.45 + 0.20 * distance_fit)
	_ai_facility_route_cache[key] = {"quality": quality, "origin": origin, "expires_at": now + 2.0}
	return quality


func _facility_role_fit(unit: Dictionary, definition: Dictionary) -> float:
	var ship_class := str(unit.get("stats", {}).get("ship_class", ""))
	var fit := 0.72
	if ship_class in ["Destroyer", "LightCruiser"]: fit = 1.0
	elif ship_class in ["HeavyCruiser", "Submarine"]: fit = 0.78
	elif ship_class == "Battleship": fit = 0.55
	elif ship_class == "Carrier": fit = 0.35
	if "BerthingService" in definition.get("operation_modes", []) and str(definition.get("berthing_service", {}).get("service_type", "")) == "Repair":
		fit = maxf(fit, 0.85 if ship_class in ["Battleship", "Carrier"] else 0.75)
	return fit


func _facility_assignment_saturation(unit: Dictionary, facility_id: String, required_count: int) -> float:
	var assigned := 0
	for ally_id in _sorted_unit_ids():
		var ally: Dictionary = state["units_by_id"][ally_id]
		if ally.get("entity_id", "") == unit.get("entity_id", "") or ally.get("life_state", "") != "Alive" or ally.get("faction_id", "") != unit.get("faction_id", ""): continue
		if str(ally.get("ai_state", {}).get("task_target_ref", {}).get("facility_id", "")) == facility_id:
			assigned += 1
	return clampf(float(assigned) / float(maxi(1, required_count)), 0.0, 1.0)


func _facility_contest_pressure(unit: Dictionary, center: Vector2) -> float:
	var observation = _ai_observation_for(str(unit.get("faction_id", "")))
	var pressure := 0.0
	for enemy in observation.visible_enemies.values():
		if enemy.get("life_state", "") != "Alive": continue
		var distance := center.distance_to(enemy.get("position", Vector2.ZERO))
		pressure = maxf(pressure, clampf(1.0 - distance / 750.0, 0.0, 1.0))
	return pressure


func _facility_time_margin(unit: Dictionary, definition: Dictionary, distance: float) -> float:
	var speed := maxf(1.0, float(unit.get("stats", {}).get("speed", 1.0)))
	var required_time := distance / speed + maxf(float(definition.get("area_control", {}).get("duration", 0.0)), float(definition.get("berthing_service", {}).get("duration", 0.0)))
	var remaining := maxf(0.0, float(state.get("time_limit", 0.0)) - float(state.get("elapsed_time", 0.0)))
	return clampf((remaining - required_time) / maxf(30.0, required_time), 0.0, 1.0)


func _set_ai_facility_task(unit: Dictionary, plan: Dictionary) -> void:
	var ai_state: Dictionary = unit["ai_state"]
	var old_task := str(ai_state.get("level_task", ""))
	var old_facility := str(ai_state.get("task_target_ref", {}).get("facility_id", ""))
	ai_state["level_task"] = str(plan.get("task_type", ""))
	ai_state["task_target_ref"] = {"facility_id": str(plan.get("facility_id", ""))}
	ai_state["task_score"] = float(plan.get("score", 0.0))
	ai_state["objective_role"] = str(plan.get("objective_role", ""))
	ai_state["group_role"] = "ObjectiveRunner" if ai_state["level_task"] in ["CaptureFacility", "ServiceFacility"] else ("Screen" if ai_state["level_task"] == "DefendFacility" else ai_state.get("group_role", ""))
	if old_task != ai_state["level_task"] or old_facility != str(plan.get("facility_id", "")):
		ai_state["task_started_at"] = float(state.get("elapsed_time", 0.0))
		_emit("AILevelTaskChanged", {"unit_id": unit["entity_id"], "old_task": old_task, "level_task": ai_state["level_task"], "facility_id": plan.get("facility_id", ""), "score": plan.get("score", 0.0)})


func _clear_ai_facility_task(unit: Dictionary) -> void:
	var ai_state: Dictionary = unit["ai_state"]
	if str(ai_state.get("level_task", "")).is_empty(): return
	var old_task := str(ai_state.get("level_task", ""))
	ai_state["level_task"] = ""
	ai_state["task_target_ref"] = {}
	ai_state["task_score"] = 0.0
	ai_state["objective_role"] = ""
	ai_state["task_started_at"] = 0.0
	var group: Dictionary = state.get("ai_groups_by_faction", {}).get(unit.get("faction_id", ""), {}).get(str(ai_state.get("group_id", "")), {})
	var leader: Dictionary = state.get("units_by_id", {}).get(str(group.get("leader_unit_id", "")), {})
	ai_state["group_role"] = _default_group_role(unit, leader, int(ai_state.get("formation_slot_index", 0)))
	_emit("AILevelTaskChanged", {"unit_id": unit["entity_id"], "old_task": old_task, "level_task": "", "facility_id": "", "score": 0.0})


func _record_ai_facility_failure(unit: Dictionary, facility_id: String) -> void:
	var ai_state: Dictionary = unit["ai_state"]
	ai_state["task_failures"] = int(ai_state.get("task_failures", 0)) + 1
	var counts: Dictionary = ai_state.get("facility_failure_counts", {})
	counts[facility_id] = int(counts.get(facility_id, 0)) + 1
	ai_state["facility_failure_counts"] = counts
	ai_state["task_blocked_facility_id"] = facility_id
	ai_state["task_blocked_until"] = INF if int(counts[facility_id]) >= 2 else float(state.get("elapsed_time", 0.0)) + minf(15.0, 4.0 * float(ai_state["task_failures"]))
	_clear_ai_facility_task(unit)


func _queue_ai_facility_action(unit: Dictionary, facility_id: String, action_type: String) -> void:
	command_queue.append({
		"command_id": "ai.facility.%s.%s" % [state["tick_index"] + 1, unit["entity_id"]],
		"command_type": "DeclareFacilityControl" if action_type == "Control" else "RequestFacilityService",
		"issued_at_tick": state["tick_index"] + 1,
		"issuer_type": "AI",
		"issuer_id": unit["faction_id"],
		"unit_id": unit["entity_id"],
		"facility_id": facility_id,
	})


func _update_ai_support_intents(faction_id: String = ENEMY_FACTION) -> void:
	var target: Dictionary = {}
	var observation = _ai_observation_for(faction_id)
	var visible_target_ids: Array = observation.visible_enemies.keys()
	visible_target_ids.sort()
	for target_id in visible_target_ids:
		var candidate: Dictionary = observation.visible_enemies.get(target_id, {})
		if candidate.get("life_state", "") == "Alive":
			target = candidate
			break
	if target.is_empty(): return
	var requester: Dictionary = {}
	for unit_id in _sorted_unit_ids():
		var unit: Dictionary = state["units_by_id"][unit_id]
		if unit.get("faction_id", "") == faction_id and unit.get("life_state", "") == "Alive": requester = unit; break
	if requester.is_empty(): return
	var facilities: Dictionary = observation.known_facilities
	var live_facilities := facility_service.snapshot()
	var facility_ids: Array = facilities.keys()
	facility_ids.sort()
	for facility_id_key in facility_ids:
		var facility: Dictionary = live_facilities.get(facility_id_key, facilities[facility_id_key])
		var facility_id := str(facility.get("facility_id", ""))
		if facility.get("faction_id", "") != faction_id or not facility_service.is_operational(facility_id): continue
		if float(facility.get("cooldown_remaining", 0.0)) > 0.0: continue
		var definition := facility_service.definition_for(facility_id)
		if "SupportMissionProvider" not in definition.get("capabilities", []): continue
		for mission_id in ["support_mission.airstrike", "support_mission.fighter_patrol", "support_mission.air_recon"]:
			if mission_id not in definition.get("support_mission_ids", []) or int(facility.get("mission_charges_remaining", {}).get(mission_id, 0)) <= 0: continue
			var mission_definition: Dictionary = registry.get_definition("facilities", mission_id)
			var maximum_range := float(mission_definition.get("max_range", INF))
			var range_margin := maxf(20.0, float(target.get("stats", {}).get("speed", 0.0)) * 0.5)
			if (facility.get("position", Vector2.ZERO) as Vector2).distance_to(target["position"]) > maximum_range - range_margin: continue
			command_queue.append({"command_id":"ai.support.%s.%s.%s" % [state["tick_index"] + 1, faction_id, mission_id], "command_type":"RequestSupportMission", "issued_at_tick":state["tick_index"] + 1, "issuer_type":"AI", "issuer_id":faction_id, "unit_id":requester["entity_id"], "facility_id":facility_id, "mission_definition_id":mission_id, "target_position":target["position"]})
			_set_ai_facility_task(requester, {"task_type":"AirportSupport", "facility_id":facility_id, "score":70.0, "objective_role":"RemoteSupport"})
			return
	for facility_id_key in facility_ids:
		var facility: Dictionary = live_facilities.get(facility_id_key, facilities[facility_id_key])
		var facility_id := str(facility.get("facility_id", ""))
		var definition := facility_service.definition_for(facility_id)
		if facility.get("faction_id", "") != faction_id or not facility_service.is_operational(facility_id) or str(definition.get("remote_command", {}).get("command_type", "")) != "MineDeployment": continue
		if float(facility.get("cooldown_remaining", 0.0)) > 0.0 or int(facility.get("remote_charges_remaining", 0)) <= 0: continue
		var rules: Dictionary = definition.get("remote_command", {})
		var direction := (target.get("position", Vector2.ZERO) as Vector2) - (facility.get("position", Vector2.ZERO) as Vector2)
		var mine_target := (facility.get("position", Vector2.ZERO) as Vector2) + direction.normalized() * minf(float(rules.get("control_radius", 0.0)) * 0.65, direction.length() * 0.5)
		command_queue.append({"command_id":"ai.mine.%s.%s" % [state["tick_index"] + 1, faction_id], "command_type":"RequestMineDeployment", "issued_at_tick":state["tick_index"] + 1, "issuer_type":"AI", "issuer_id":faction_id, "unit_id":requester["entity_id"], "facility_id":facility_id, "target_position":mine_target})
		_set_ai_facility_task(requester, {"task_type":"MineDeployment", "facility_id":facility_id, "score":68.0, "objective_role":"RemoteSupport"})
		return


func _cast_skill(unit: Dictionary, target_ref: Dictionary, command_id: String) -> Dictionary:
	if float(unit["skill_state"]["cooldown_remaining"]) > 0.0: return _rejection(command_id, "SKILL_ON_COOLDOWN")
	var skill: Dictionary = registry.get_definition("skills", str(unit["skill_state"]["definition_id"]))
	if skill.is_empty(): return _rejection(command_id, "SKILL_NOT_FOUND")
	var target_position: Vector2 = unit["position"]
	if skill.get("target_type", "Self") == "Enemy":
		var target_id := str(target_ref.get("entity_id", ""))
		if not _is_visible_to(unit["faction_id"], target_id): return _rejection(command_id, "TARGET_NOT_VISIBLE")
		var target: Dictionary = state["units_by_id"].get(target_id, {})
		if target.is_empty() or target["life_state"] != "Alive": return _rejection(command_id, "INVALID_TARGET_TYPE")
		target_position = target["position"]
	elif skill.get("target_type", "Self") == "Area":
		if typeof(target_ref.get("position")) != TYPE_VECTOR2: return _rejection(command_id, "INVALID_TARGET_TYPE")
		target_position = target_ref["position"]
	if float(skill.get("cast_range", 0.0)) > 0.0 and (unit["position"] as Vector2).distance_to(target_position) > float(skill["cast_range"]): return _rejection(command_id, "TARGET_OUT_OF_RANGE")
	var action_rejection := _skill_action_rejection(unit, skill, target_position)
	if not action_rejection.is_empty(): return _rejection(command_id, action_rejection)
	var recipients := _skill_recipients(unit, skill, target_position)
	for effect in skill.get("effects", []):
		for recipient in recipients.get(effect.get("scope", "Self"), []):
			var recipient_classes: Array = effect.get("recipient_ship_classes", [])
			if not recipient_classes.is_empty() and str(recipient.get("stats", {}).get("ship_class", "")) not in recipient_classes:
				continue
			var applied_effect: Dictionary = effect.duplicate(true)
			if bool(applied_effect.get("bind_selected_target", false)) and skill.get("target_type", "Self") == "Enemy":
				applied_effect["bound_target_id"] = str(target_ref.get("entity_id", ""))
			_apply_status(recipient, applied_effect, float(applied_effect.get("duration", skill.get("duration", 0.0))), skill["id"], unit["entity_id"])
	_execute_skill_actions(unit, skill, target_position, target_ref)
	unit["skill_state"]["cooldown_remaining"] = float(skill["cooldown"])
	_emit("SkillCast", {"unit_id": unit["entity_id"], "skill_id": skill["id"], "target_ref": target_ref.duplicate(true)})
	return {"accepted": true}


func _skill_action_rejection(source: Dictionary, skill: Dictionary, target_position: Vector2) -> String:
	for attack_spec in skill.get("triggered_attacks", []):
		var weapon: Dictionary = registry.get_definition("weapons", str(attack_spec.get("weapon_id", "")))
		if weapon.is_empty(): return "SKILL_ATTACK_WEAPON_NOT_FOUND"
		if str(weapon.get("mount_type", "")) == "Aviation":
			var source_condition := str(terrain_context_service.context_at(source["position"]).get("aviation_condition", "Normal"))
			var target_condition := str(terrain_context_service.context_at(target_position).get("aviation_condition", "Normal"))
			if source_condition in ["Severe", "Grounded"] or target_condition in ["Severe", "Grounded"]: return "AVIATION_WEATHER_BLOCKED"
	return ""


func _switch_ammo(unit: Dictionary, command_id: String) -> Dictionary:
	var ship: Dictionary = unit.get("stats", {})
	var ammo_group_id := str(ship.get("ammo_selection_group_id", ""))
	if ammo_group_id.is_empty(): return _rejection(command_id, "AMMO_SWITCH_DISABLED")
	var options := _ammo_options_for_ship(ship, ammo_group_id)
	if options.size() <= 1: return _rejection(command_id, "AMMO_SWITCH_DISABLED")
	var current := _selected_ammo_for_group(unit, ammo_group_id)
	var next_index := (options.find(current) + 1) % options.size()
	unit["ammo_state"][ammo_group_id] = options[next_index]
	_emit("AmmoSwitched", {"unit_id": unit["entity_id"], "ammo_group_id": ammo_group_id, "ammo_type": options[next_index]})
	return {"accepted": true}


func _fire_primary_weapon(unit: Dictionary, target_position: Vector2, command_id: String) -> Dictionary:
	var primary_group_id := str(unit.get("stats", {}).get("primary_weapon_group_id", ""))
	var weapon_states := _weapon_states_for_group(unit, primary_group_id, true)
	var validation := _validate_primary_fire(unit, weapon_states, target_position)
	if not bool(validation.get("legal", false)):
		return _rejection(command_id, str(validation.get("reason_code", "PRIMARY_WEAPON_UNAVAILABLE")))
	var legal_states: Array = validation.get("legal_weapon_states", [])
	var weapon_state: Dictionary = legal_states[0]
	var weapon: Dictionary = registry.get_definition("weapons", str(weapon_state["definition_id"]))
	_fire_weapon_at_position(unit, target_position, weapon_state, weapon, true)
	return {"accepted": true}


func _skill_recipients(source: Dictionary, skill: Dictionary, target_position: Vector2) -> Dictionary:
	var result := {"Self": [source], "AlliesInArea": [], "EnemiesInArea": []}
	var radius := float(skill.get("effect_radius", 0.0))
	for unit_id in _sorted_unit_ids():
		var unit: Dictionary = state["units_by_id"][unit_id]
		if unit["life_state"] != "Alive" or (unit["position"] as Vector2).distance_to(target_position) > radius: continue
		if unit["faction_id"] == source["faction_id"]: result["AlliesInArea"].append(unit)
		else: result["EnemiesInArea"].append(unit)
	return result


func _apply_status(target: Dictionary, effect: Dictionary, duration: float, status_id: String, source_unit_id: String) -> void:
	var new_effect: Dictionary = effect.duplicate(true)
	new_effect["status_id"] = status_id
	new_effect["source_unit_id"] = source_unit_id
	new_effect["remaining"] = maxf(duration, 0.1)
	var group := str(effect.get("stack_group", status_id))
	var rule := str(effect.get("stack_rule", "Add"))
	for index in range(target["status_effects"].size() - 1, -1, -1):
		var existing: Dictionary = target["status_effects"][index]
		if existing.get("stack_group", existing.get("status_id", "")) != group or existing.get("stat", "") != effect.get("stat", ""): continue
		if rule == "Highest" and absf(float(existing.get("value", 0.0))) >= absf(float(effect.get("value", 0.0))):
			existing["remaining"] = maxf(float(existing["remaining"]), duration)
			return
		if rule in ["Refresh", "Replace", "Highest"]: target["status_effects"].remove_at(index)
	target["status_effects"].append(new_effect)
	_emit("StatusApplied", {"source_unit_id": source_unit_id, "target_unit_id": target["entity_id"], "status_id": status_id, "duration": duration})


func _execute_skill_actions(source: Dictionary, skill: Dictionary, target_position: Vector2, target_ref: Dictionary) -> void:
	for recon in skill.get("recon_zones", []):
		var effect_id := _next_entity_id("skill_recon")
		state["skill_effects_by_id"][effect_id] = {
			"effect_id": effect_id,
			"effect_type": "Reconnaissance",
			"source_unit_id": source["entity_id"],
			"source_skill_id": skill["id"],
			"faction_id": source["faction_id"],
			"position": target_position,
			"radius": float(recon.get("radius", 0.0)),
			"remaining": float(recon.get("duration", skill.get("duration", 0.0))),
			"current_hp": float(recon.get("aircraft_hp", 350.0)),
			"max_hp": float(recon.get("aircraft_hp", 350.0)),
			"destroyed_cooldown_penalty": float(recon.get("destroyed_cooldown_penalty", 0.0)),
		}
		_emit("SkillReconDeployed", state["skill_effects_by_id"][effect_id].duplicate(true))
	for attack_spec in skill.get("triggered_attacks", []):
		_queue_skill_attack(source, skill, attack_spec, target_position, target_ref)


func _queue_skill_attack(source: Dictionary, skill: Dictionary, attack_spec: Dictionary, target_position: Vector2, target_ref: Dictionary) -> void:
	var weapon: Dictionary = registry.get_definition("weapons", str(attack_spec.get("weapon_id", "")))
	if weapon.is_empty(): return
	_mark_unit_fired(source)
	if attack_spec.has("firing_reveal_multiplier"):
		source["firing_reveal_remaining"] = maxf(float(source.get("firing_reveal_remaining", 0.0)), _firing_reveal_duration(source) * float(attack_spec.get("firing_reveal_multiplier", 1.0)))
	var waves := maxi(1, int(attack_spec.get("waves", 1)))
	var default_shots := int(weapon.get("mount_count", 1)) * int(weapon.get("shots_per_mount", 1))
	var shot_count := maxi(1, int(attack_spec.get("shots_per_wave", default_shots)))
	var wave_interval := float(attack_spec.get("wave_interval", 0.0))
	var charge_time := float(attack_spec.get("charge_time", 0.0))
	var temporary_effects: Array = []
	for modifier in attack_spec.get("modifiers", []):
		var effect: Dictionary = modifier.duplicate(true)
		effect["status_id"] = skill["id"]
		effect["source_unit_id"] = source["entity_id"]
		temporary_effects.append(effect)
	var launch_effects := _active_status_effects(source).duplicate(true)
	launch_effects.append_array(temporary_effects)
	for wave_index in range(waves):
		var launch_at_time := float(state["elapsed_time"]) + charge_time + wave_index * wave_interval
		for shot_index in range(shot_count):
			var impact_position := target_position
			var dispersion_sample := {}
			var terrain_hit := {"hit":false}
			if str(weapon.get("mount_type", "")) == "Gun":
				dispersion_sample = _sample_gun_impact(source["position"], target_position, weapon, launch_effects)
				impact_position = dispersion_sample.get("position", target_position)
				terrain_hit = _terrain_hit_for_attack(source["position"], impact_position, str(source.get("faction_id", "")))
				if bool(terrain_hit.get("hit", false)): impact_position = terrain_hit.get("position", impact_position)
			var travel_seconds := (source["position"] as Vector2).distance_to(impact_position) / maxf(1.0, float(weapon.get("projectile_speed", 1.0)))
			if str(weapon.get("mount_type", "")) == "Aviation": travel_seconds *= _aviation_delay_multiplier(source["position"], impact_position)
			var attack := {
				"attack_id": _next_entity_id("skill_attack"),
				"source_unit_id": source["entity_id"],
				"source_weapon_id": weapon["id"],
				"source_skill_id": skill["id"],
				"target_unit_id": "",
				"aimed_target_unit_id": str(target_ref.get("entity_id", "")),
				"target_position": impact_position,
				"origin": source["position"],
				"impact_radius": float(attack_spec.get("impact_radius", weapon.get("impact_radius", 40.0))),
				"terrain_obstacle_id": terrain_hit.get("obstacle_id", ""),
				"blocked_by_terrain": bool(terrain_hit.get("hit", false)),
				"launch_at_time": launch_at_time,
				"resolve_at_time": launch_at_time + travel_seconds,
				"accuracy_modifier": _environment_accuracy_modifier(source["faction_id"], source["position"], impact_position, str(weapon.get("mount_type", ""))),
				"source_status_effects": launch_effects.duplicate(true),
				"on_hit_effects": attack_spec.get("on_hit_effects", []).duplicate(true),
			}
			_apply_dispersion_metadata(attack, dispersion_sample)
			delayed_attacks.append(attack)
	_emit("SkillAttackScheduled", {"unit_id":source["entity_id"], "skill_id":skill["id"], "weapon_id":weapon["id"], "waves":waves, "shots_per_wave":shot_count, "target_position":target_position})


func _update_weapons() -> void:
	for unit_id in _sorted_unit_ids():
		var unit: Dictionary = state["units_by_id"][unit_id]
		if unit["life_state"] != "Alive": continue
		if level_objective_service.automatic_weapons_locked_for(unit): continue
		if unit.get("faction_id", "") == PLAYER_FACTION and not bool(unit.get("secondary_auto_fire_enabled", true)): continue
		var target := _current_or_select_target(unit, unit.get("faction_id", "") == PLAYER_FACTION)
		if target.is_empty(): continue
		unit["targeting_state"]["current_target_id"] = target["entity_id"]
		var fired_groups := {}
		var weapon_states: Array = unit["weapon_states"]
		weapon_states.sort_custom(func(a, b): return str(a["definition_id"]) < str(b["definition_id"]))
		for weapon_state in weapon_states:
			if not bool(weapon_state["enabled"]) or float(weapon_state["reload_remaining"]) > 0.0: continue
			var weapon: Dictionary = registry.get_definition("weapons", str(weapon_state["definition_id"]))
			if weapon.get("control_mode", "Automatic") == "ManualPrimary": continue
			if not _weapon_matches_selected_ammo(unit, weapon): continue
			if _uses_full_ai(unit) and not _automatic_weapon_allowed_by_ai_discipline(unit, target, weapon): continue
			var group := str(weapon.get("shared_cooldown_group", ""))
			if not group.is_empty() and fired_groups.has(group): continue
			if not _can_fire(unit, target, weapon): continue
			var aim_solution := _automatic_aim_solution(unit, target, weapon)
			if aim_solution.is_empty() or not bool(_can_fire_at_position(unit, aim_solution["position"], weapon).get("legal", false)):
				continue
			_fire_weapon(unit, target, weapon_state, weapon, aim_solution)
			if not group.is_empty():
				fired_groups[group] = true
				for sibling_state in weapon_states:
					var sibling: Dictionary = registry.get_definition("weapons", str(sibling_state["definition_id"]))
					if sibling.get("shared_cooldown_group", "") == group: sibling_state["reload_remaining"] = weapon_state["reload_remaining"]


func _update_facility_weapons() -> void:
	for facility in facility_service.weapon_platforms():
		var faction_id := str(facility.get("faction_id", "neutral"))
		if faction_id == "neutral": continue
		for weapon_state in facility.get("weapon_states", []):
			if not bool(weapon_state.get("enabled", true)) or float(weapon_state.get("reload_remaining", 0.0)) > 0.0: continue
			var weapon: Dictionary = registry.get_definition("weapons", str(weapon_state.get("definition_id", "")))
			if weapon.is_empty(): continue
			var target := _select_facility_weapon_target(facility, weapon)
			if target.is_empty(): continue
			var selected_ammo := "AP" if str(target.get("stats", {}).get("armor_thickness", "Unarmored")) in ["Medium", "Heavy"] else "HE"
			facility["selected_ammo_type"] = selected_ammo
			if not str(weapon.get("ammo_type", "")).is_empty() and str(weapon.get("ammo_type", "")) != selected_ammo: continue
			_fire_facility_weapon(facility, target, weapon)
			break


func _select_facility_weapon_target(facility: Dictionary, weapon: Dictionary) -> Dictionary:
	var candidates: Array = []
	var origin: Vector2 = facility.get("muzzle_position", facility.get("position", Vector2.ZERO))
	for target_id in state.get("visible_by_faction", {}).get(str(facility.get("faction_id", "")), {}):
		var target: Dictionary = state["units_by_id"].get(target_id, {})
		if target.get("life_state", "") != "Alive" or target.get("faction_id", "") == facility.get("faction_id", ""): continue
		if _target_type(target) not in weapon.get("target_types", []): continue
		var distance := origin.distance_to(target["position"])
		if distance < float(weapon.get("minimum_range", 0.0)) or distance > float(weapon.get("range", 0.0)): continue
		var heading := deg_to_rad(float(facility.get("heading", 0.0)))
		if not _angle_in_weapon_fire_arcs(heading, (target["position"] - origin).angle(), weapon): continue
		if terrain_query.is_configured() and not terrain_query.is_segment_clear(origin, target["position"], "ShellTravel"): continue
		candidates.append({"target": target, "distance": distance})
	candidates.sort_custom(func(a, b): return float(a["distance"]) < float(b["distance"]) if not is_equal_approx(float(a["distance"]), float(b["distance"])) else str(a["target"]["entity_id"]) < str(b["target"]["entity_id"]))
	return {} if candidates.is_empty() else candidates[0]["target"]


func _fire_facility_weapon(facility: Dictionary, target: Dictionary, weapon: Dictionary) -> void:
	var origin: Vector2 = facility.get("muzzle_position", facility.get("position", Vector2.ZERO))
	var target_position: Vector2 = target["position"]
	var mount_reference: Dictionary = facility_service.definition_for(str(facility.get("facility_id", ""))).get("weapon_mount_reference", {})
	var shot_count := int(mount_reference.get("mount_count", weapon.get("mount_count", 1))) * int(mount_reference.get("shots_per_mount", weapon.get("shots_per_mount", 1)))
	var impact_positions: Array = []
	var dispersion_samples: Array = []
	for shot_index in range(shot_count):
		var dispersion_sample := _sample_gun_impact(origin, target_position, weapon)
		var intended_impact: Vector2 = dispersion_sample["position"]
		var terrain_hit := _terrain_hit_for_attack(origin, intended_impact, str(facility.get("faction_id", "")))
		var resolved_impact: Vector2 = terrain_hit.get("position", intended_impact) if bool(terrain_hit.get("hit", false)) else intended_impact
		impact_positions.append(resolved_impact)
		dispersion_samples.append(dispersion_sample)
		var travel_seconds := origin.distance_to(resolved_impact) / maxf(1.0, float(weapon.get("projectile_speed", 1.0)))
		delayed_attacks.append({"attack_id":_next_entity_id("facility_attack"), "source_unit_id":"", "source_facility_id":facility["facility_id"], "source_weapon_id":weapon["id"], "target_unit_id":"", "aimed_target_unit_id":target["entity_id"], "target_position":resolved_impact, "intended_impact_position":intended_impact, "resolved_impact_position":resolved_impact, "terrain_obstacle_id":terrain_hit.get("obstacle_id", ""), "blocked_by_terrain":bool(terrain_hit.get("hit", false)), "impact_radius":float(weapon.get("impact_radius", 40.0)), "origin":origin, "resolve_at_time":float(state["elapsed_time"]) + travel_seconds, "accuracy_modifier":_environment_accuracy_modifier(str(facility.get("faction_id", "")), origin, intended_impact, "Gun"), "dispersion_lateral_sigma":dispersion_sample["lateral_sigma"], "dispersion_longitudinal_sigma":dispersion_sample["longitudinal_sigma"], "dispersion_lateral_error":dispersion_sample["lateral_error"], "dispersion_longitudinal_error":dispersion_sample["longitudinal_error"]})
	facility_service.mark_weapon_fired(str(facility["facility_id"]), str(weapon["id"]), float(weapon.get("reload_time", 1.0)))
	_emit("FacilityWeaponFired", {"facility_id":facility["facility_id"], "weapon_id":weapon["id"], "target_unit_id":target["entity_id"], "target_position":target_position, "impact_positions":impact_positions, "dispersion_samples":dispersion_samples, "shot_count":shot_count})


func _can_fire(unit: Dictionary, target: Dictionary, weapon: Dictionary) -> bool:
	if target["life_state"] != "Alive" or not _is_visible_to(unit["faction_id"], target["entity_id"]): return false
	if not _target_type(target) in weapon.get("target_types", []): return false
	var distance := (unit["position"] as Vector2).distance_to(target["position"] as Vector2)
	if distance < float(weapon.get("minimum_range", 0.0)) or distance > _effective_weapon_range(unit, weapon): return false
	var target_angle := ((target["position"] as Vector2) - (unit["position"] as Vector2)).angle()
	return _angle_in_weapon_fire_arcs(float(unit["heading"]), target_angle, weapon)


func _can_fire_at_position(unit: Dictionary, target_position: Vector2, weapon: Dictionary) -> Dictionary:
	var distance := (unit["position"] as Vector2).distance_to(target_position)
	if distance < float(weapon.get("minimum_range", 0.0)):
		return {"legal": false, "reason_code": "TARGET_TOO_CLOSE"}
	if distance > _effective_weapon_range(unit, weapon):
		return {"legal": false, "reason_code": "TARGET_OUT_OF_RANGE"}
	var target_angle := (target_position - (unit["position"] as Vector2)).angle()
	if not _angle_in_weapon_fire_arcs(float(unit["heading"]), target_angle, weapon):
		return {"legal": false, "reason_code": "FIRE_ARC_INVALID"}
	if weapon.get("mount_type", "") == "Aviation":
		var source_condition := str(terrain_context_service.context_at(unit["position"]).get("aviation_condition", "Normal"))
		var target_condition := str(terrain_context_service.context_at(target_position).get("aviation_condition", "Normal"))
		if source_condition in ["Severe", "Grounded"] or target_condition in ["Severe", "Grounded"]:
			return {"legal": false, "reason_code": "AVIATION_WEATHER_BLOCKED"}
	if weapon.get("mount_type", "") == "Gun" and terrain_query.is_configured():
		var terrain_hit := terrain_query.first_segment_hit(unit["position"], target_position, "ShellTravel")
		var facility_path_hit := _first_facility_path_hit(unit["position"], target_position, unit["faction_id"])
		if bool(terrain_hit.get("hit", false)) and (facility_path_hit.is_empty() or float(terrain_hit.get("fraction", 1.0)) + 0.001 < float(facility_path_hit.get("fraction", 1.0))):
			return {"legal": false, "reason_code": "TERRAIN_BLOCKS_SHELL_PATH", "terrain_hit": terrain_hit}
	return {"legal": true, "reason_code": "OK"}


func _can_fire_in_direction(unit: Dictionary, direction_point: Vector2, weapon: Dictionary) -> Dictionary:
	var direction: Vector2 = direction_point - (unit["position"] as Vector2)
	if direction.length_squared() <= 0.0001:
		return {"legal": false, "reason_code": "INVALID_TARGET_TYPE"}
	if not _angle_in_weapon_fire_arcs(float(unit["heading"]), direction.angle(), weapon):
		return {"legal": false, "reason_code": "FIRE_ARC_INVALID"}
	return {"legal": true, "reason_code": "OK"}


func _automatic_aim_solution(unit: Dictionary, target: Dictionary, weapon: Dictionary) -> Dictionary:
	var origin: Vector2 = unit["position"]
	var target_position: Vector2 = target["position"]
	var projectile_speed := _automatic_attack_speed(unit, weapon)
	var target_velocity := Vector2.RIGHT.rotated(float(target.get("heading", 0.0))) * float(target.get("current_speed", 0.0))
	var relative_position := target_position - origin
	var intercept_time := _positive_intercept_time(relative_position, target_velocity, projectile_speed)
	if intercept_time <= 0.0:
		intercept_time = relative_position.length() / projectile_speed
	var predicted_position := _clamp_to_map(target_position + target_velocity * intercept_time)
	return {
		"position": predicted_position,
		"travel_seconds": origin.distance_to(predicted_position) / projectile_speed,
		"target_velocity": target_velocity,
	}


func _automatic_attack_speed(unit: Dictionary, weapon: Dictionary) -> float:
	if weapon.get("mount_type", "") == "Torpedo":
		var projectile: Dictionary = registry.get_definition("projectiles", str(weapon.get("projectile_id", "")))
		return maxf(1.0, ModifierService.calculate(float(projectile.get("speed", weapon.get("projectile_speed", 1.0))), _active_status_effects(unit), "ProjectileSpeed", "Torpedo"))
	return maxf(1.0, float(weapon.get("projectile_speed", 1.0)))


func _positive_intercept_time(relative_position: Vector2, target_velocity: Vector2, projectile_speed: float) -> float:
	var a := target_velocity.length_squared() - projectile_speed * projectile_speed
	var b := 2.0 * relative_position.dot(target_velocity)
	var c := relative_position.length_squared()
	if absf(a) <= 0.0001:
		return -c / b if b < -0.0001 else -1.0
	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0.0:
		return -1.0
	var root := sqrt(discriminant)
	var first := (-b - root) / (2.0 * a)
	var second := (-b + root) / (2.0 * a)
	var result := INF
	if first > 0.0: result = first
	if second > 0.0: result = minf(result, second)
	return -1.0 if is_inf(result) else result


func _fire_weapon(unit: Dictionary, target: Dictionary, weapon_state: Dictionary, weapon: Dictionary, aim_solution: Dictionary = {}) -> void:
	var category := str(weapon["mount_type"])
	var launch_effects := _active_status_effects(unit)
	var extra_shots := int(round(ModifierService.sum_modifier(launch_effects, "ExtraShots", category)))
	var shot_count := (int(weapon["shots_per_mount"]) if category == "Torpedo" else int(weapon["mount_count"]) * int(weapon["shots_per_mount"])) + extra_shots
	_set_weapon_reload(unit, weapon_state, weapon)
	_start_mount_launch_interval(unit, weapon)
	_mark_unit_fired(unit)
	var aim_position: Vector2 = aim_solution.get("position", target["position"])
	var base_heading := (aim_position - (unit["position"] as Vector2)).angle()
	var torpedo_error_profile := _torpedo_error_profile(unit, weapon, shot_count, launch_effects)
	var impact_positions: Array = []
	var dispersion_samples: Array = []
	for shot_index in range(shot_count):
		var spread_offset := 0.0
		if shot_count > 1: spread_offset = deg_to_rad(float(weapon.get("spread", 0.0))) * (float(shot_index) / float(shot_count - 1) - 0.5)
		var attack_id := _next_entity_id("attack")
		if category == "Torpedo":
			var angular_error: float = random_source.randfn(0.0, float(torpedo_error_profile["sigma_radians"]))
			_spawn_projectile(unit, weapon, attack_id, base_heading + spread_offset + angular_error, str(weapon_state.get("mount_id", "")), angular_error, float(torpedo_error_profile["sigma_radians"]), float(torpedo_error_profile["environment_multiplier"]), launch_effects)
		else:
			var dispersion_sample := _sample_gun_impact(unit["position"], aim_position, weapon, launch_effects) if category == "Gun" else {}
			var intended_impact: Vector2 = dispersion_sample["position"] if not dispersion_sample.is_empty() else _salvo_impact_position(unit["position"], aim_position, spread_offset, weapon)
			var terrain_hit := _terrain_hit_for_attack(unit["position"], intended_impact, unit["faction_id"]) if category == "Gun" else {"hit": false}
			var resolved_impact: Vector2 = terrain_hit.get("position", intended_impact) if bool(terrain_hit.get("hit", false)) else intended_impact
			impact_positions.append(resolved_impact)
			if not dispersion_sample.is_empty(): dispersion_samples.append(dispersion_sample)
			var travel_seconds := (unit["position"] as Vector2).distance_to(resolved_impact) / maxf(1.0, float(weapon.get("projectile_speed", 1.0)))
			if category == "Aviation": travel_seconds *= _aviation_delay_multiplier(unit["position"], intended_impact)
			var delayed_attack := {"attack_id": attack_id, "source_unit_id": unit["entity_id"], "source_weapon_id": weapon["id"], "target_unit_id": "", "aimed_target_unit_id": target["entity_id"], "target_position": resolved_impact, "intended_impact_position": intended_impact, "resolved_impact_position": resolved_impact, "terrain_obstacle_id": terrain_hit.get("obstacle_id", ""), "blocked_by_terrain": bool(terrain_hit.get("hit", false)), "impact_radius": float(weapon.get("impact_radius", 40.0)), "origin": unit["position"], "resolve_at_time": float(state["elapsed_time"]) + travel_seconds, "accuracy_modifier": _environment_accuracy_modifier(unit["faction_id"], unit["position"], intended_impact, category), "source_status_effects":launch_effects.duplicate(true)}
			_apply_dispersion_metadata(delayed_attack, dispersion_sample)
			delayed_attacks.append(delayed_attack)
	_mark_ai_effective_attack(unit)
	_emit("WeaponFired", {"unit_id": unit["entity_id"], "weapon_id": weapon["id"], "mount_id": weapon_state.get("mount_id", ""), "target_unit_id": target["entity_id"], "target_position": aim_position, "impact_positions": impact_positions, "dispersion_samples": dispersion_samples, "shot_count": shot_count})
	_consume_on_fire_effects(unit, weapon)


func _fire_weapon_at_position(unit: Dictionary, target_position: Vector2, weapon_state: Dictionary, weapon: Dictionary, manual: bool) -> void:
	var category := str(weapon["mount_type"])
	var launch_effects := _active_status_effects(unit)
	var extra_shots := int(round(ModifierService.sum_modifier(launch_effects, "ExtraShots", category)))
	var shot_count := (int(weapon["shots_per_mount"]) if category == "Torpedo" else int(weapon["mount_count"]) * int(weapon["shots_per_mount"])) + extra_shots
	_set_weapon_reload(unit, weapon_state, weapon)
	_start_mount_launch_interval(unit, weapon)
	_mark_unit_fired(unit)
	var base_heading := (target_position - (unit["position"] as Vector2)).angle()
	var torpedo_error_profile := _torpedo_error_profile(unit, weapon, shot_count, launch_effects)
	var impact_positions: Array = []
	var dispersion_samples: Array = []
	for shot_index in range(shot_count):
		var spread_offset := 0.0
		if shot_count > 1: spread_offset = deg_to_rad(float(weapon.get("spread", 0.0))) * (float(shot_index) / float(shot_count - 1) - 0.5)
		var attack_id := _next_entity_id("attack")
		if category == "Torpedo":
			var angular_error: float = random_source.randfn(0.0, float(torpedo_error_profile["sigma_radians"]))
			_spawn_projectile(unit, weapon, attack_id, base_heading + spread_offset + angular_error, str(weapon_state.get("mount_id", "")), angular_error, float(torpedo_error_profile["sigma_radians"]), float(torpedo_error_profile["environment_multiplier"]), launch_effects)
		else:
			var dispersion_sample := _sample_gun_impact(unit["position"], target_position, weapon, launch_effects) if category == "Gun" else {}
			var intended_impact: Vector2 = dispersion_sample["position"] if not dispersion_sample.is_empty() else _salvo_impact_position(unit["position"], target_position, spread_offset, weapon)
			var terrain_hit := _terrain_hit_for_attack(unit["position"], intended_impact, unit["faction_id"]) if category == "Gun" else {"hit": false}
			var resolved_impact: Vector2 = terrain_hit.get("position", intended_impact) if bool(terrain_hit.get("hit", false)) else intended_impact
			impact_positions.append(resolved_impact)
			if not dispersion_sample.is_empty(): dispersion_samples.append(dispersion_sample)
			var travel_seconds := (unit["position"] as Vector2).distance_to(resolved_impact) / maxf(1.0, float(weapon.get("projectile_speed", 1.0)))
			if category == "Aviation": travel_seconds *= _aviation_delay_multiplier(unit["position"], intended_impact)
			var delayed_attack := {"attack_id": attack_id, "source_unit_id": unit["entity_id"], "source_weapon_id": weapon["id"], "target_unit_id": "", "target_position": resolved_impact, "intended_impact_position": intended_impact, "resolved_impact_position": resolved_impact, "terrain_obstacle_id": terrain_hit.get("obstacle_id", ""), "blocked_by_terrain": bool(terrain_hit.get("hit", false)), "impact_radius": float(weapon.get("impact_radius", 40.0)), "origin": unit["position"], "resolve_at_time": float(state["elapsed_time"]) + travel_seconds, "accuracy_modifier": _environment_accuracy_modifier(unit["faction_id"], unit["position"], intended_impact, category), "source_status_effects":launch_effects.duplicate(true)}
			_apply_dispersion_metadata(delayed_attack, dispersion_sample)
			delayed_attacks.append(delayed_attack)
	_mark_ai_effective_attack(unit)
	_emit("WeaponFired", {"unit_id": unit["entity_id"], "weapon_id": weapon["id"], "mount_id": weapon_state.get("mount_id", ""), "target_position": target_position, "impact_positions": impact_positions, "dispersion_samples": dispersion_samples, "shot_count": shot_count, "manual": manual})
	_consume_on_fire_effects(unit, weapon)


func _salvo_impact_position(origin: Vector2, target_position: Vector2, spread_offset: float, weapon: Dictionary) -> Vector2:
	var base_heading := (target_position - origin).angle()
	var impact_offset := Vector2.RIGHT.rotated(base_heading + PI * 0.5) * spread_offset * float(weapon.get("impact_radius", 40.0))
	return _clamp_to_map(target_position + impact_offset)


func _sample_gun_impact(origin: Vector2, aim_position: Vector2, weapon: Dictionary, status_effects: Array = []) -> Dictionary:
	var settings := _gun_dispersion_settings()
	var effective_spread := ModifierService.calculate(float(weapon.get("spread", 0.0)), status_effects, "WeaponSpread", "Gun")
	var sample := GunDispersionService.sample(origin, aim_position, effective_spread, float(settings["sigma_scale"]), float(settings["longitudinal_sigma_ratio"]), random_source)
	sample["spread_degrees"] = effective_spread
	return sample


func _gun_dispersion_settings() -> Dictionary:
	return registry.get_definition("settings", "settings.combat").get("gun_dispersion", {
		"sigma_scale": 0.5684105110424833,
		"longitudinal_sigma_ratio": 0.5,
	})


func _apply_dispersion_metadata(attack: Dictionary, sample: Dictionary) -> void:
	if sample.is_empty(): return
	attack["dispersion_lateral_sigma"] = float(sample["lateral_sigma"])
	attack["dispersion_longitudinal_sigma"] = float(sample["longitudinal_sigma"])
	attack["dispersion_lateral_error"] = float(sample["lateral_error"])
	attack["dispersion_longitudinal_error"] = float(sample["longitudinal_error"])


func _mark_unit_fired(unit: Dictionary) -> void:
	unit["firing_reveal_remaining"] = maxf(float(unit["firing_reveal_remaining"]), _firing_reveal_duration(unit))


func _firing_reveal_duration(unit: Dictionary) -> float:
	var effects := _active_status_effects(unit)
	var concealment := ModifierService.calculate(float(unit["stats"]["concealment_distance"]), effects, "ConcealmentDistance")
	var speed := ModifierService.calculate(float(unit["stats"]["speed"]), effects, "Speed")
	var multiplier := ModifierService.calculate(1.0, effects, "FiringRevealMultiplier")
	return maxf(0.1, concealment / maxf(1.0, speed) * multiplier)


func _set_weapon_reload(unit: Dictionary, weapon_state: Dictionary, weapon: Dictionary) -> void:
	var reload_time := ModifierService.reload_time(float(weapon["reload_time"]), _active_status_effects(unit), str(weapon["mount_type"]))
	weapon_state["reload_remaining"] = reload_time
	var shared_group := str(weapon.get("shared_cooldown_group", ""))
	if shared_group.is_empty(): return
	for sibling_state in unit["weapon_states"]:
		var sibling: Dictionary = registry.get_definition("weapons", str(sibling_state["definition_id"]))
		if str(sibling.get("shared_cooldown_group", "")) == shared_group:
			sibling_state["reload_remaining"] = reload_time


func _start_mount_launch_interval(unit: Dictionary, weapon: Dictionary) -> void:
	if weapon.get("mount_type", "") != "Torpedo":
		return
	var group_id := str(weapon.get("weapon_group_id", ""))
	if group_id.is_empty():
		return
	unit["weapon_group_launch_remaining"][group_id] = maxf(1.0, float(weapon.get("mount_launch_interval", 1.0)))


func _torpedo_error_profile(unit: Dictionary, weapon: Dictionary, shot_count: int, status_effects: Array = []) -> Dictionary:
	if weapon.get("mount_type", "") != "Torpedo" or shot_count <= 1:
		return {"sigma_radians": 0.0, "environment_multiplier": 1.0}
	var effective_spread := ModifierService.calculate(float(weapon.get("spread", 0.0)), status_effects, "WeaponSpread", "Torpedo")
	var adjacent_angle := deg_to_rad(effective_spread) / float(shot_count - 1)
	var environment_context := terrain_context_service.context_at(unit.get("position", Vector2.ZERO))
	var environment_multiplier := float(environment_context.get("torpedo_sigma_multiplier", 1.0))
	var sigma_ratio := float(weapon.get("torpedo_angular_sigma_ratio", 0.2))
	return {
		"sigma_radians": adjacent_angle * sigma_ratio * environment_multiplier,
		"environment_multiplier": environment_multiplier,
		"sea_state": int(environment_context.get("sea_state", 0)),
		"wind_speed": float(environment_context.get("wind_speed", 0.0)),
	}


func _spawn_projectile(unit: Dictionary, weapon: Dictionary, attack_id: String, heading: float, source_mount_id: String = "", angular_error: float = 0.0, angular_sigma: float = 0.0, environmental_sigma_multiplier: float = 1.0, launch_effects: Array = []) -> void:
	var projectile_definition: Dictionary = registry.get_definition("projectiles", str(weapon["projectile_id"]))
	var projectile_id := _next_entity_id("projectile")
	var effects := launch_effects if not launch_effects.is_empty() else _active_status_effects(unit)
	var speed := ModifierService.calculate(float(projectile_definition.get("speed", weapon.get("projectile_speed", 0.0))), effects, "ProjectileSpeed", "Torpedo")
	var radius := ModifierService.calculate(float(projectile_definition.get("collision_radius", 8.0)), effects, "ProjectileRadius", "Torpedo")
	var launch_direction := Vector2.RIGHT.rotated(heading)
	var formula: Dictionary = registry.get_definition("formulas", str(weapon.get("formula_id", "")))
	var observed_raw_damage := float(formula.get("base_damage", 0.0)) + float(unit.get("stats", {}).get(_power_stat_for_weapon(weapon), 0.0)) * float(formula.get("power_coefficient", 0.0))
	var launch_clearance := CollisionGeometryService.radial_extent(_unit_collision_half_extents(unit), float(unit["heading"]), launch_direction)
	state["projectiles_by_id"][projectile_id] = {
		"entity_id": projectile_id,
		"definition_id": projectile_definition["id"],
		"attack_id": attack_id,
		"source_unit_id": unit["entity_id"],
		"source_weapon_id": weapon["id"],
		"observed_raw_damage": observed_raw_damage,
		"source_mount_id": source_mount_id,
		"faction_id": unit["faction_id"],
		"position": unit["position"] + launch_direction * (launch_clearance + 3.0),
		"heading": heading,
		"ideal_heading": heading - angular_error,
		"angular_error": angular_error,
		"angular_sigma": angular_sigma,
		"environmental_sigma_multiplier": environmental_sigma_multiplier,
		"speed": speed,
		"collision_radius": radius,
		"minimum_detection_distance": float(projectile_definition.get("minimum_detection_distance", 0.0)),
		"max_range": float(weapon.get("range", 0.0)),
		"travelled_distance": 0.0,
		"remaining_range": float(weapon.get("range", 0.0)),
		"source_status_effects": effects.duplicate(true),
		"target_types": projectile_definition.get("target_types", []).duplicate(),
	}
	state["known_projectiles_by_faction"][unit["faction_id"]][projectile_id] = true
	_emit("ProjectileSpawned", {"projectile_id": projectile_id, "source_unit_id": unit["entity_id"], "source_mount_id": source_mount_id, "position": state["projectiles_by_id"][projectile_id]["position"], "heading": heading, "ideal_heading": heading - angular_error, "angular_error": angular_error, "angular_sigma": angular_sigma, "environmental_sigma_multiplier": environmental_sigma_multiplier})


func _update_projectiles(delta: float) -> void:
	for projectile_id in state["projectiles_by_id"].keys():
		var projectile: Dictionary = state["projectiles_by_id"][projectile_id]
		var movement := minf(float(projectile["speed"]) * delta, float(projectile["remaining_range"]))
		var start: Vector2 = projectile["position"]
		var current_vector: Vector2 = terrain_context_service.context_at(start).get("current_vector", Vector2.ZERO)
		var end := start + Vector2.RIGHT.rotated(float(projectile["heading"])) * movement + current_vector * delta
		var terrain_hit := terrain_query.first_segment_hit(start, end, "TorpedoTravel", float(projectile["collision_radius"])) if terrain_query.is_configured() else {"hit": false, "fraction": 1.0}
		var unit_hit := {"hit": false, "fraction": 1.0, "target_unit_id": ""}
		for target_id in _sorted_unit_ids():
			var target: Dictionary = state["units_by_id"][target_id]
			if target["life_state"] != "Alive" or target["faction_id"] == projectile["faction_id"] or not _target_type(target) in projectile["target_types"]: continue
			var fraction := CollisionGeometryService.segment_expanded_ellipse_fraction(
				start, end, target["position"], float(target["heading"]),
				_unit_collision_half_extents(target), float(projectile["collision_radius"]),
			)
			if fraction < 0.0 or fraction > float(unit_hit["fraction"]) + 0.001:
				continue
			if is_equal_approx(fraction, float(unit_hit["fraction"])) and target_id > str(unit_hit["target_unit_id"]):
				continue
			unit_hit = {"hit": true, "fraction": fraction, "target_unit_id": target_id}
		if bool(terrain_hit.get("hit", false)) and (not bool(unit_hit.get("hit", false)) or float(terrain_hit["fraction"]) <= float(unit_hit["fraction"]) + 0.001):
			projectile["position"] = terrain_hit["position"]
			_emit("ProjectileBlockedByTerrain", {"projectile_id": projectile_id, "source_unit_id": projectile["source_unit_id"], "source_weapon_id": projectile["source_weapon_id"], "obstacle_id": terrain_hit.get("obstacle_id", ""), "position": terrain_hit["position"], "normal": terrain_hit.get("normal", Vector2.ZERO)})
			state["projectiles_by_id"].erase(projectile_id)
			continue
		if bool(unit_hit.get("hit", false)):
			var impact_position := start.lerp(end, float(unit_hit["fraction"]))
			projectile["position"] = impact_position
			_emit("ProjectileHit", {"projectile_id": projectile_id, "target_unit_id": unit_hit["target_unit_id"], "position": impact_position})
			_resolve_attack({"attack_id": projectile["attack_id"], "source_unit_id": projectile["source_unit_id"], "source_weapon_id": projectile["source_weapon_id"], "target_unit_id": unit_hit["target_unit_id"], "origin": impact_position, "accuracy_modifier": 0.0, "source_status_effects":projectile.get("source_status_effects", []).duplicate(true)}, true)
			state["projectiles_by_id"].erase(projectile_id)
			continue
		projectile["position"] = end
		var actual_distance := start.distance_to(end)
		projectile["travelled_distance"] = float(projectile["travelled_distance"]) + actual_distance
		projectile["remaining_range"] = float(projectile["remaining_range"]) - actual_distance
		if float(projectile["remaining_range"]) <= 0.0001:
			_emit("ProjectileExpired", {"projectile_id": projectile_id, "position": projectile["position"], "reason_code": "MAX_RANGE"})
			state["projectiles_by_id"].erase(projectile_id)


func _resolve_delayed_attacks() -> void:
	delayed_attacks.sort_custom(func(a, b): return float(a["resolve_at_time"]) < float(b["resolve_at_time"]) if not is_equal_approx(float(a["resolve_at_time"]), float(b["resolve_at_time"])) else str(a["attack_id"]) < str(b["attack_id"]))
	var remaining: Array = []
	for attack in delayed_attacks:
		if float(attack["resolve_at_time"]) <= float(state["elapsed_time"]):
			if bool(attack.get("blocked_by_terrain", false)):
				_emit("ShellBlockedByTerrain", {"attack_id": attack.get("attack_id", ""), "source_unit_id": attack.get("source_unit_id", ""), "source_weapon_id": attack.get("source_weapon_id", ""), "obstacle_id": attack.get("terrain_obstacle_id", ""), "position": attack.get("resolved_impact_position", attack.get("target_position", Vector2.ZERO)), "intended_impact_position": attack.get("intended_impact_position", Vector2.ZERO)})
			else:
				_resolve_attack(attack, false)
		else: remaining.append(attack)
	delayed_attacks = remaining


func _resolve_attack(attack: Dictionary, forced_hit: bool) -> void:
	var source: Dictionary = state["units_by_id"].get(str(attack["source_unit_id"]), {})
	if source.is_empty() and not str(attack.get("source_facility_id", "")).is_empty():
		source = facility_service.combat_source(str(attack.get("source_facility_id", "")))
	if source.is_empty(): return
	if not str(attack.get("target_facility_id", "")).is_empty():
		_resolve_facility_attack(attack, source, forced_hit)
		return
	if str(attack.get("target_unit_id", "")).is_empty():
		_resolve_area_attack(attack, source, forced_hit)
		return
	var target: Dictionary = state["units_by_id"].get(str(attack["target_unit_id"]), {})
	if target.is_empty() or target["life_state"] != "Alive": return
	var weapon: Dictionary = registry.get_definition("weapons", str(attack["source_weapon_id"]))
	var formula: Dictionary = registry.get_definition("formulas", str(weapon["formula_id"]))
	var source_snapshot := source.duplicate(true)
	source_snapshot["position"] = attack.get("origin", source["position"])
	if attack.has("source_status_effects"):
		source_snapshot["status_effects"] = _resolved_attack_effects(source, target, attack.get("source_status_effects", []))
	if str(weapon.get("mount_type", "")) == "Aviation":
		attack["damage_multiplier"] = float(attack.get("damage_multiplier", 1.0)) * _aviation_survival_ratio(attack, source_snapshot)
	var result := DamageService.resolve(attack, source_snapshot, target, weapon, formula, random_source, forced_hit)
	result = DamageStatistics.enrich_result(result, weapon, source.get("stats", source), attack)
	_annotate_non_ship_damage_result(result, attack)
	result["geometry_intersection"] = bool(attack.get("geometry_intersection", false))
	result["impact_position"] = attack.get("target_position", target.get("position", Vector2.ZERO))
	result["aimed_target_unit_id"] = attack.get("aimed_target_unit_id", attack.get("target_unit_id", ""))
	target["current_hp"] = float(result["target_hp_after"])
	if not bool(result.get("caused_sinking", false)):
		var repair_interruption := facility_service.interrupt_service_on_unit_damage(str(target.get("entity_id", "")), float(result.get("final_damage", 0.0)), float(target.get("max_hp", 1.0)))
		if not repair_interruption.is_empty(): _handle_facility_event(repair_interruption)
	if bool(result.get("hit", false)):
		for effect in attack.get("on_hit_effects", []):
			_apply_status(target, effect, float(effect.get("duration", 0.1)), str(attack.get("source_skill_id", "")), str(source.get("entity_id", "")))
	if is_zero_approx(float(result.get("final_damage", 0.0))):
		_apply_zero_damage_reactions(target)
	_emit("AttackResolved", {"damage_result": result})
	if bool(result.get("hit", false)) and str(source.get("faction_id", "")) == PLAYER_FACTION:
		var mount_type := str(weapon.get("mount_type", ""))
		if mount_type == "Torpedo":
			_record_tutorial_action("TorpedoHit", str(source.get("entity_id", "")), {"target_unit_id": str(target.get("entity_id", "")), "attack_category": mount_type, "weapon_group_id": str(weapon.get("weapon_group_id", ""))})
		elif mount_type == "Gun":
			_record_tutorial_action("SharedTargetGunHit", str(source.get("entity_id", "")), {"target_unit_id": str(target.get("entity_id", "")), "attack_category": mount_type, "weapon_group_id": str(weapon.get("weapon_group_id", ""))})
	if bool(result["caused_sinking"]): _sink_unit(target, source["entity_id"])


func _resolved_attack_effects(source: Dictionary, target: Dictionary, effects: Array) -> Array:
	var result: Array = []
	for effect in effects:
		if bool(effect.get("requires_scouted_target", false)) and not _is_visible_to(str(source.get("faction_id", "")), str(target.get("entity_id", ""))):
			continue
		result.append(effect)
	return result


func _aviation_survival_ratio(attack: Dictionary, aviation_source: Dictionary) -> float:
	var target_position: Vector2 = attack.get("target_position", aviation_source.get("position", Vector2.ZERO))
	var source_effects: Array = aviation_source.get("status_effects", [])
	var aircraft_hp := 350.0 * maxf(0.1, ModifierService.calculate(1.0, source_effects, "AircraftHP", "Aviation"))
	var anti_air_damage := 0.0
	for unit_id in _sorted_unit_ids():
		var defender: Dictionary = state["units_by_id"][unit_id]
		if defender.get("life_state", "") != "Alive" or defender.get("faction_id", "") == aviation_source.get("faction_id", ""): continue
		for weapon_state in defender.get("weapon_states", []):
			var aa_weapon: Dictionary = registry.get_definition("weapons", str(weapon_state.get("definition_id", "")))
			if str(aa_weapon.get("mount_type", "")) != "AntiAir" or (defender.get("position", Vector2.ZERO) as Vector2).distance_to(target_position) > _effective_weapon_range(defender, aa_weapon): continue
			var formula: Dictionary = registry.get_definition("formulas", str(aa_weapon.get("formula_id", "")))
			var raw := float(formula.get("base_damage", 0.0)) + float(defender.get("stats", {}).get("anti_air_power", 0.0)) * float(formula.get("power_coefficient", 0.0))
			var damage_bonus := 1.0 + ModifierService.sum_modifier(_active_status_effects(defender), "Damage", "AntiAir")
			var reload := ModifierService.reload_time(float(aa_weapon.get("reload_time", 1.0)), _active_status_effects(defender), "AntiAir")
			anti_air_damage += raw * damage_bonus * float(aa_weapon.get("mount_count", 1)) * float(aa_weapon.get("shots_per_mount", 1)) / maxf(0.2, reload) * 0.12
	var floor_ratio := clampf(ModifierService.sum_modifier(source_effects, "AviationDamageFloor", "Aviation"), 0.0, 1.0)
	return maxf(floor_ratio, clampf((aircraft_hp - anti_air_damage) / aircraft_hp, 0.0, 1.0))


func _resolve_area_attack(attack: Dictionary, source: Dictionary, forced_hit: bool) -> void:
	var weapon: Dictionary = registry.get_definition("weapons", str(attack["source_weapon_id"]))
	var impact_position: Vector2 = attack.get("target_position", source["position"])
	var impact_radius := float(attack.get("impact_radius", weapon.get("impact_radius", 40.0)))
	var candidates: Array = []
	var source_faction := _attack_source_faction(attack, source)
	for target_id in _sorted_unit_ids():
		var target: Dictionary = state["units_by_id"][target_id]
		if target["life_state"] != "Alive" or target["faction_id"] == source_faction: continue
		if not _target_type(target) in weapon.get("target_types", []): continue
		var distance := (target["position"] as Vector2).distance_to(impact_position)
		if CollisionGeometryService.point_in_expanded_ellipse(
			impact_position, target["position"], float(target["heading"]),
			_unit_collision_half_extents(target), impact_radius,
		):
			candidates.append({"target_type":"Unit", "target":target, "target_id":str(target["entity_id"]), "distance":distance})
	for facility_id in state.get("facilities_by_id", {}):
		var facility: Dictionary = state["facilities_by_id"][facility_id]
		if str(facility.get("life_state", "")) != "Alive" or str(facility.get("faction_id", "neutral")) in [source_faction, "neutral"]: continue
		var radius := float(facility.get("target_shape", {}).get("radius", facility_service.definition_for(str(facility_id)).get("target_radius", 24.0)))
		var distance := (facility.get("position", Vector2.ZERO) as Vector2).distance_to(impact_position)
		if distance <= impact_radius + radius:
			candidates.append({"target_type":"Facility", "target":facility, "target_id":str(facility_id), "distance":distance})
	candidates.sort_custom(func(a, b): return float(a["distance"]) < float(b["distance"]) if not is_equal_approx(float(a["distance"]), float(b["distance"])) else str(a["target_id"]) < str(b["target_id"]))
	if candidates.is_empty():
		var miss_result := {"attack_id": attack.get("attack_id", ""), "source_unit_id": source.get("entity_id", ""), "source_weapon_id": weapon.get("id", ""), "aimed_target_unit_id": attack.get("aimed_target_unit_id", ""), "target_unit_id": "", "impact_position": impact_position, "damage_type": weapon.get("mount_type", ""), "hit": false, "hit_reason": "NO_TARGET_IN_AREA", "raw_damage": 0.0, "armor_modifier": 0.0, "armor_reduction": 0.0, "base_final_damage": 0.0, "buff_bonus_damage": 0.0, "buff_contribution_weights": {}, "buff_contribution_details": [], "buff_source_skill_ids": [], "final_damage": 0.0, "target_hp_before": 0.0, "target_hp_after": 0.0, "caused_sinking": false}
		miss_result["geometry_intersection"] = false
		miss_result = DamageStatistics.enrich_result(miss_result, weapon, source.get("stats", source), attack)
		_emit("AttackResolved", {"damage_result": miss_result})
		return
	var selected: Dictionary = candidates[0]
	if selected["target_type"] == "Facility":
		attack["target_facility_id"] = selected["target_id"]
	else:
		attack["target_unit_id"] = selected["target_id"]
	attack["geometry_intersection"] = true
	_resolve_attack(attack, forced_hit)


func _resolve_facility_attack(attack: Dictionary, source: Dictionary, forced_hit: bool) -> void:
	var facility_id := str(attack.get("target_facility_id", ""))
	var target := facility_service.target_for_damage(facility_id)
	if target.is_empty(): return
	var weapon: Dictionary = registry.get_definition("weapons", str(attack["source_weapon_id"]))
	var formula: Dictionary = registry.get_definition("formulas", str(weapon.get("formula_id", "")))
	if weapon.is_empty() or formula.is_empty(): return
	var source_snapshot := source.duplicate(true)
	source_snapshot["position"] = attack.get("origin", source.get("position", Vector2.ZERO))
	var result := DamageService.resolve(attack, source_snapshot, target, weapon, formula, random_source, forced_hit)
	result = DamageStatistics.enrich_result(result, weapon, source.get("stats", source), attack)
	_annotate_non_ship_damage_result(result, attack)
	result["impact_position"] = attack.get("target_position", target.get("position", Vector2.ZERO))
	result["source_facility_id"] = attack.get("source_facility_id", "")
	result["target_facility_id"] = facility_id
	result["target_unit_id"] = ""
	if not bool(result.get("hit", false)):
		_emit("AttackResolved", {"damage_result": result})
		return
	var facility_events := facility_service.apply_damage(facility_id, float(result.get("final_damage", 0.0)), str(source.get("entity_id", "")))
	var resolved_facility: Dictionary = facility_service.facilities_by_id.get(facility_id, {})
	var actual_damage := 0.0
	for facility_event in facility_events:
		if facility_event.get("event_type", "") == "FacilityDamaged": actual_damage = float(facility_event.get("damage", 0.0))
	result["final_damage"] = actual_damage
	result["target_hp_after"] = resolved_facility.get("current_hp", result.get("target_hp_after", 0.0))
	result["caused_sinking"] = resolved_facility.get("life_state", "") == "Destroyed"
	result["facility_damage_limited"] = facility_events.any(func(event): return event.get("event_type", "") == "FacilityDamageLimited")
	_emit("AttackResolved", {"damage_result": result})
	for event in facility_events:
		_handle_facility_event(event)
	state["facilities_by_id"] = facility_service.snapshot()


func _handle_facility_event(event: Dictionary) -> void:
	var event_type := str(event.get("event_type", "FacilityChanged"))
	if event_type in ["FacilityControlCompleted", "FacilityServiceCompleted"]:
		var task_unit: Dictionary = state.get("units_by_id", {}).get(str(event.get("unit_id", "")), {})
		if not task_unit.is_empty(): _reset_ai_passive_memory(task_unit)
	match event_type:
		"FacilityServiceCompleted":
			_apply_facility_service(event)
			_release_docked_unit(event)
		"SupportMissionCompleted": _resolve_support_mission(event)
		"MineDeploymentCompleted":
			for mine_event in minefield_service.deploy_random_batch(event, terrain_query):
				if mine_event.get("event_type", "") == "MineDeploymentBatchResolved":
					facility_service.record_mine_deployment_result(str(mine_event.get("facility_id", "")), {"result":"Completed", "mission_id":mine_event.get("deployment_id", ""), "active_count":mine_event.get("active_count", 0), "invalid_count":mine_event.get("invalid_count", 0)})
				_emit(str(mine_event.get("event_type", "MineDeployed")), mine_event)
		"FacilityActionInterrupted":
			_release_docked_unit(event)
			var unit: Dictionary = state.get("units_by_id", {}).get(str(event.get("unit_id", "")), {})
			if not unit.is_empty() and _uses_full_ai(unit):
				_record_ai_facility_failure(unit, str(event.get("facility_id", "")))
	_emit(event_type, event)


func _dock_unit_for_service(unit: Dictionary, event: Dictionary) -> void:
	var dock_position: Vector2 = event.get("dock_position", unit.get("position", Vector2.ZERO))
	unit["position"] = dock_position
	unit["current_speed"] = 0.0
	unit["movement_state"] = _new_movement_state("Docked", dock_position, [])
	_mark_navigation_dirty(unit)
	unit["player_route_waypoints"] = []


func _release_docked_unit(event: Dictionary) -> void:
	if str(event.get("service_type", "")) != "Repair": return
	var unit: Dictionary = state.get("units_by_id", {}).get(str(event.get("unit_id", "")), {})
	if unit.is_empty() or str(unit.get("movement_state", {}).get("mode", "")) != "Docked": return
	unit["current_speed"] = 0.0
	unit["movement_state"] = _new_movement_state("HoldPosition", unit.get("position", Vector2.ZERO), [])
	unit["navigation_state"]["state"] = "SafetyHold"
	unit["navigation_state"]["current_control"] = {"thrust_ratio": 0.0, "turn_ratio": 0.0}


func _docked_action_for_unit(unit_id: String) -> Dictionary:
	var action := facility_service.active_action_for_unit(unit_id)
	if action.get("action_type", "") != "Service" or action.get("service_type", "") != "Repair" or str(action.get("phase", "")) not in ["Docked", "Servicing"]: return {}
	return action


func _undock_for_move_order(unit: Dictionary) -> void:
	var action := _docked_action_for_unit(str(unit.get("entity_id", "")))
	if action.is_empty(): return
	var cancellation := facility_service.cancel_action(str(action.get("facility_id", "")), str(unit.get("entity_id", "")))
	if bool(cancellation.get("accepted", false)) and cancellation.has("event"): _handle_facility_event(cancellation["event"])


func _apply_facility_service(event: Dictionary) -> void:
	var unit: Dictionary = state["units_by_id"].get(str(event.get("unit_id", "")), {})
	if unit.is_empty() or unit.get("life_state", "") != "Alive": return
	var profile: Dictionary = event.get("service_rules", {})
	var result := {"unit_id":unit["entity_id"], "facility_id":event.get("facility_id", ""), "service_type":event.get("service_type", "")}
	match str(event.get("service_type", "")):
		"Supply":
			var reload_ratio := clampf(float(profile.get("weapon_reload_recovery_ratio", 0.0)), 0.0, 1.0)
			for weapon_state in unit.get("weapon_states", []):
				weapon_state["reload_remaining"] = float(weapon_state.get("reload_remaining", 0.0)) * (1.0 - reload_ratio)
			var cooldown_before := float(unit.get("skill_state", {}).get("cooldown_remaining", 0.0))
			unit["skill_state"]["cooldown_remaining"] = maxf(0.0, cooldown_before - float(profile.get("skill_cooldown_recovery", 0.0)))
			result["weapon_reload_recovery_ratio"] = reload_ratio
			result["skill_cooldown_recovered"] = cooldown_before - float(unit["skill_state"]["cooldown_remaining"])
		"Repair":
			var hp_before := float(unit.get("current_hp", 0.0))
			var repair_cap := float(unit.get("max_hp", 1.0)) * clampf(float(profile.get("repair_cap_ratio", 1.0)), 0.0, 1.0)
			unit["current_hp"] = minf(repair_cap, hp_before + float(unit.get("max_hp", 1.0)) * maxf(0.0, float(profile.get("hp_restore_ratio", 0.0))))
			result["hp_restored"] = float(unit["current_hp"]) - hp_before
	_emit("UnitServiced", result)


func _resolve_support_mission(event: Dictionary) -> void:
	var mission := facility_service.mission_definition(str(event.get("definition_id", "")))
	if mission.is_empty(): return
	var target_position: Vector2 = event.get("target_position", Vector2.ZERO)
	var context := terrain_context_service.context_at(target_position)
	if str(context.get("aviation_condition", "Normal")) in mission.get("blocked_aviation_conditions", []):
		_emit("SupportMissionCancelled", {"mission_id":event.get("mission_id", ""), "definition_id":event.get("definition_id", ""), "facility_id":event.get("facility_id", ""), "reason_code":"AVIATION_WEATHER_BLOCKED"})
		return
	var mission_type := str(mission.get("mission_type", ""))
	if mission_type in ["Reconnaissance", "FighterPatrol"]:
		state["support_effects_by_id"][str(event["mission_id"])] = {
			"effect_id": str(event["mission_id"]),
			"definition_id": str(event["definition_id"]),
			"effect_type": mission_type,
			"faction_id": str(event.get("faction_id", "")),
			"position": target_position,
			"radius": float(mission.get("effect_radius", 0.0)),
			"remaining": float(mission.get("effect_duration", 0.0)),
			"enemy_aviation_accuracy_modifier": float(mission.get("enemy_aviation_accuracy_modifier", 0.0)),
		}
		_emit("SupportMissionResolved", {"mission_id":event["mission_id"], "definition_id":event["definition_id"], "effect_type":mission_type, "target_position":target_position})
		return
	if mission_type != "Airstrike": return
	var facility_id := str(event.get("facility_id", ""))
	var source := facility_service.combat_source(facility_id)
	var weapon: Dictionary = registry.get_definition("weapons", str(mission.get("weapon_id", "")))
	if source.is_empty() or weapon.is_empty(): return
	for salvo_index in range(int(mission.get("salvo_count", 1))):
		var attack := {
			"attack_id": _next_entity_id("support_attack"),
			"source_unit_id": "",
			"source_facility_id": facility_id,
			"source_weapon_id": weapon["id"],
			"target_unit_id": "",
			"target_position": target_position,
			"impact_radius": float(mission.get("effect_radius", weapon.get("impact_radius", 40.0))),
			"origin": source["position"],
			"accuracy_modifier": _environment_accuracy_modifier(str(event.get("faction_id", "")), source["position"], target_position, "Aviation"),
		}
		_resolve_area_attack(attack, source, false)
	_emit("SupportMissionResolved", {"mission_id":event["mission_id"], "definition_id":event["definition_id"], "effect_type":"Airstrike", "target_position":target_position})


func _update_support_effects(delta: float) -> void:
	for effect_id in state.get("support_effects_by_id", {}).keys():
		var effect: Dictionary = state["support_effects_by_id"][effect_id]
		effect["remaining"] = maxf(0.0, float(effect.get("remaining", 0.0)) - delta)
		if is_zero_approx(float(effect["remaining"])):
			state["support_effects_by_id"].erase(effect_id)
			_emit("SupportMissionEffectExpired", {"effect_id":effect_id, "definition_id":effect.get("definition_id", "")})
	for effect_id in state.get("skill_effects_by_id", {}).keys():
		var effect: Dictionary = state["skill_effects_by_id"][effect_id]
		effect["remaining"] = maxf(0.0, float(effect.get("remaining", 0.0)) - delta)
		if str(effect.get("effect_type", "")) == "Reconnaissance" and float(effect.get("current_hp", 0.0)) > 0.0:
			effect["current_hp"] = maxf(0.0, float(effect["current_hp"]) - _anti_air_dps_at_position(str(effect.get("faction_id", "")), effect.get("position", Vector2.ZERO)) * delta)
			if is_zero_approx(float(effect["current_hp"])):
				var source: Dictionary = state.get("units_by_id", {}).get(str(effect.get("source_unit_id", "")), {})
				if not source.is_empty(): source["skill_state"]["cooldown_remaining"] += float(effect.get("destroyed_cooldown_penalty", 0.0))
				state["skill_effects_by_id"].erase(effect_id)
				_emit("SkillReconDestroyed", {"effect_id":effect_id, "skill_id":effect.get("source_skill_id", ""), "cooldown_penalty":effect.get("destroyed_cooldown_penalty", 0.0)})
				continue
		if is_zero_approx(float(effect["remaining"])):
			state["skill_effects_by_id"].erase(effect_id)
			_emit("SkillWorldEffectExpired", {"effect_id":effect_id, "skill_id":effect.get("source_skill_id", "")})


func _anti_air_dps_at_position(friendly_faction: String, position: Vector2) -> float:
	var result := 0.0
	for unit_id in _sorted_unit_ids():
		var defender: Dictionary = state["units_by_id"][unit_id]
		if defender.get("life_state", "") != "Alive" or defender.get("faction_id", "") == friendly_faction: continue
		for weapon_state in defender.get("weapon_states", []):
			var weapon: Dictionary = registry.get_definition("weapons", str(weapon_state.get("definition_id", "")))
			if str(weapon.get("mount_type", "")) != "AntiAir" or (defender.get("position", Vector2.ZERO) as Vector2).distance_to(position) > _effective_weapon_range(defender, weapon): continue
			var formula: Dictionary = registry.get_definition("formulas", str(weapon.get("formula_id", "")))
			var raw := float(formula.get("base_damage", 0.0)) + float(defender.get("stats", {}).get("anti_air_power", 0.0)) * float(formula.get("power_coefficient", 0.0))
			var effects := _active_status_effects(defender)
			var damage_bonus := 1.0 + ModifierService.sum_modifier(effects, "Damage", "AntiAir")
			var reload := ModifierService.reload_time(float(weapon.get("reload_time", 1.0)), effects, "AntiAir")
			result += raw * damage_bonus * float(weapon.get("mount_count", 1)) * float(weapon.get("shots_per_mount", 1)) / maxf(0.2, reload) * 0.25
	return result


func _visible_support_effects(viewer_faction: String, omniscient: bool) -> Dictionary:
	var result := {}
	for effect_id in state.get("support_effects_by_id", {}):
		var effect: Dictionary = state["support_effects_by_id"][effect_id]
		if omniscient or str(effect.get("faction_id", "")) == viewer_faction: result[effect_id] = effect.duplicate(true)
	return result


func _visible_skill_effects(viewer_faction: String, omniscient: bool) -> Dictionary:
	var result := {}
	for effect_id in state.get("skill_effects_by_id", {}):
		var effect: Dictionary = state["skill_effects_by_id"][effect_id]
		if omniscient or str(effect.get("faction_id", "")) == viewer_faction:
			result[effect_id] = effect.duplicate(true)
	return result


func _environment_accuracy_modifier(faction_id: String, source_position: Vector2, target_position: Vector2, category: String) -> float:
	var source_modifier := float(terrain_context_service.context_at(source_position).get("weapon_accuracy_modifier", 0.0))
	var target_modifier := float(terrain_context_service.context_at(target_position).get("weapon_accuracy_modifier", 0.0))
	var result := minf(source_modifier, target_modifier)
	if category == "Aviation":
		for effect in state.get("support_effects_by_id", {}).values():
			if str(effect.get("effect_type", "")) != "FighterPatrol" or str(effect.get("faction_id", "")) == faction_id: continue
			var center: Vector2 = effect.get("position", Vector2.ZERO)
			var radius := float(effect.get("radius", 0.0))
			if center.distance_to(source_position) <= radius or center.distance_to(target_position) <= radius:
				result += float(effect.get("enemy_aviation_accuracy_modifier", 0.0))
	return result


func _aviation_delay_multiplier(source_position: Vector2, target_position: Vector2) -> float:
	return maxf(float(terrain_context_service.context_at(source_position).get("aviation_delay_multiplier", 1.0)), float(terrain_context_service.context_at(target_position).get("aviation_delay_multiplier", 1.0)))


func _apply_mine_trigger(unit: Dictionary, trigger: Dictionary) -> void:
	var reference: Dictionary = trigger.get("damage_reference", {})
	var source_ship: Dictionary = registry.get_definition("ships", str(reference.get("ship_id", ""))).duplicate(true)
	var weapon: Dictionary = registry.get_definition("weapons", str(reference.get("weapon_id", "")))
	var formula: Dictionary = registry.get_definition("formulas", str(weapon.get("formula_id", "")))
	var result: Dictionary
	if not source_ship.is_empty() and not weapon.is_empty() and not formula.is_empty():
		var mine_source := {"entity_id":str(trigger.get("minefield_id", "")), "position":trigger.get("position", unit.get("position", Vector2.ZERO)), "status_effects":[], "stats":source_ship}
		var attack := {"attack_id":_next_entity_id("mine_attack"), "source_weapon_id":weapon.get("id", ""), "target_unit_id":unit.get("entity_id", ""), "impact_position":trigger.get("position", unit.get("position", Vector2.ZERO))}
		result = DamageService.resolve(attack, mine_source, unit, weapon, formula, random_source, true)
		result["source_hazard_id"] = str(trigger.get("minefield_id", ""))
		result["damage_category"] = "mine"
		result["hit_reason"] = "MINE_TRIGGER"
		unit["current_hp"] = result["target_hp_after"]
	else:
		var hp_before := float(unit.get("current_hp", 0.0))
		var damage := minf(hp_before, maxf(0.0, float(trigger.get("damage", 0.0))))
		unit["current_hp"] = maxf(0.0, hp_before - damage)
		result = {"attack_id":_next_entity_id("mine_attack"), "source_unit_id":str(trigger.get("minefield_id", "")), "source_hazard_id":str(trigger.get("minefield_id", "")), "source_weapon_id":"hazard.minefield", "target_unit_id":unit["entity_id"], "impact_position":trigger.get("position", unit["position"]), "damage_type":"Mine", "hit":true, "hit_rate":1.0, "hit_reason":"MINE_TRIGGER", "raw_damage":damage, "armor_modifier":1.0, "armor_reduction":0.0, "final_damage":damage, "target_hp_before":hp_before, "target_hp_after":unit["current_hp"], "caused_sinking":is_zero_approx(float(unit["current_hp"]))}
	state["minefields_by_id"] = minefield_service.snapshot()
	_emit("MineTriggered", {"minefield_id":trigger.get("minefield_id", ""), "unit_id":unit["entity_id"], "position":trigger.get("position", unit["position"]), "damage":result.get("final_damage", 0.0)})
	_emit("AttackResolved", {"damage_result":result})
	if not bool(result.get("caused_sinking", false)):
		var repair_interruption := facility_service.interrupt_service_on_unit_damage(str(unit.get("entity_id", "")), float(result.get("final_damage", 0.0)), float(unit.get("max_hp", 1.0)))
		if not repair_interruption.is_empty(): _handle_facility_event(repair_interruption)
	if is_zero_approx(float(unit["current_hp"])): _sink_unit(unit, str(trigger.get("minefield_id", "")))


func _validate_environment_route(start: Vector2, waypoints: Array) -> Dictionary:
	var anchor := start
	for waypoint in waypoints:
		var result := terrain_context_service.movement_segment_access(anchor, waypoint)
		if not bool(result.get("allowed", true)): return result
		anchor = waypoint
	return {"allowed":true, "reason_code":"OK"}


func _terrain_hit_for_attack(origin: Vector2, target_position: Vector2, source_faction: String) -> Dictionary:
	if not terrain_query.is_configured(): return {"hit":false}
	var terrain_hit := terrain_query.first_segment_hit(origin, target_position, "ShellTravel")
	if not bool(terrain_hit.get("hit", false)): return terrain_hit
	var facility_hit := _first_facility_path_hit(origin, target_position, source_faction)
	return {"hit":false} if not facility_hit.is_empty() and float(facility_hit.get("fraction", 1.0)) <= float(terrain_hit.get("fraction", 1.0)) + 0.001 else terrain_hit


func _first_facility_path_hit(origin: Vector2, target_position: Vector2, source_faction: String) -> Dictionary:
	var best: Dictionary = {}
	for facility_id in state.get("facilities_by_id", {}):
		var facility: Dictionary = state["facilities_by_id"][facility_id]
		if str(facility.get("life_state", "")) != "Alive" or str(facility.get("faction_id", "neutral")) in [source_faction, "neutral"]: continue
		var radius := float(facility.get("target_shape", {}).get("radius", 0.0))
		var fraction := CollisionGeometryService.segment_expanded_ellipse_fraction(origin, target_position, facility.get("position", Vector2.ZERO), 0.0, Vector2(radius, radius))
		if fraction < 0.0: continue
		if best.is_empty() or fraction < float(best.get("fraction", 1.0)) - 0.001 or (is_equal_approx(fraction, float(best.get("fraction", 1.0))) and str(facility_id) < str(best.get("facility_id", ""))):
			best = {"facility_id":str(facility_id), "fraction":fraction}
	return best


func _annotate_non_ship_damage_result(result: Dictionary, attack: Dictionary) -> void:
	var source_facility_id := str(attack.get("source_facility_id", ""))
	if not source_facility_id.is_empty():
		var source_facility: Dictionary = state.get("facilities_by_id", {}).get(source_facility_id, {})
		result["source_facility_id"] = source_facility_id
		result["source_definition_id"] = str(source_facility.get("definition_id", ""))
		result["source_display_name"] = str(source_facility.get("display_name", source_facility_id))
		result["source_faction_id"] = str(source_facility.get("faction_id", ""))
	var target_facility_id := str(attack.get("target_facility_id", ""))
	if not target_facility_id.is_empty():
		var target_facility: Dictionary = state.get("facilities_by_id", {}).get(target_facility_id, {})
		result["target_facility_id"] = target_facility_id
		result["target_definition_id"] = str(target_facility.get("definition_id", ""))
		result["target_display_name"] = str(target_facility.get("display_name", target_facility_id))
		result["target_faction_id"] = str(target_facility.get("faction_id", ""))


func _attack_source_faction(attack: Dictionary, source: Dictionary) -> String:
	if not str(attack.get("source_facility_id", "")).is_empty():
		return str(state.get("facilities_by_id", {}).get(str(attack["source_facility_id"]), {}).get("faction_id", "neutral"))
	return str(source.get("faction_id", "neutral"))


func _sink_unit(unit: Dictionary, source_unit_id: String) -> void:
	navigation_request_broker.cancel_for_unit(str(unit.get("entity_id", "")))
	if unit["life_state"] == "Sunk": return
	unit["life_state"] = "Sunk"
	unit["current_hp"] = 0.0
	unit["current_speed"] = 0.0
	unit["status_effects"].clear()
	var sunk_unit_id := str(unit.get("entity_id", ""))
	command_queue = command_queue.filter(func(command): return str(command.get("unit_id", "")) != sunk_unit_id)
	delayed_attacks = delayed_attacks.filter(func(attack): return str(attack.get("source_unit_id", "")) != sunk_unit_id or float(attack.get("launch_at_time", -INF)) <= float(state.get("elapsed_time", 0.0)))
	var active_facility_action := facility_service.active_action_for_unit(sunk_unit_id)
	if not active_facility_action.is_empty():
		var cancellation := facility_service.interrupt_action_for_unit(sunk_unit_id, "UNIT_SUNK")
		if not cancellation.is_empty(): _handle_facility_event(cancellation)
	unit["movement_state"] = _new_movement_state("HoldPosition", unit.get("position", Vector2.ZERO), [])
	unit["player_route_waypoints"] = []
	unit["player_facility_target_id"] = ""
	unit["targeting_state"] = {"mode":"Automatic", "focused_target_id":"", "current_target_id":""}
	unit["weapon_group_launch_remaining"] = {}
	unit["ai_state"]["level_task"] = ""
	unit["ai_state"]["task_target_ref"] = {}
	_ai_damage_reservations.erase(sunk_unit_id)
	_ai_effect_reservations.erase(sunk_unit_id)
	for other in state.get("units_by_id", {}).values():
		other["status_effects"] = other.get("status_effects", []).filter(func(effect): return not (str(effect.get("source_unit_id", "")) == sunk_unit_id and bool(effect.get("end_on_source_sunk", false))))
	for effect_id in state.get("skill_effects_by_id", {}).keys():
		var world_effect: Dictionary = state["skill_effects_by_id"][effect_id]
		if str(world_effect.get("source_unit_id", "")) == sunk_unit_id and bool(world_effect.get("end_on_source_sunk", false)):
			state["skill_effects_by_id"].erase(effect_id)
	_emit("UnitPendingActionsCancelled", {"unit_id":sunk_unit_id})
	_emit("UnitSunk", {"unit_id": unit["entity_id"], "source_unit_id": source_unit_id})
	if unit["is_flagship"]: _emit("FlagshipSunk", {"fleet_id": unit["fleet_id"], "unit_id": unit["entity_id"]})


func _check_victory() -> void:
	if state["phase"] != "Running": return
	if not str(state.get("level_objective", {}).get("objective_set_id", "")).is_empty(): return
	var player_flagship: Dictionary = state["units_by_id"][state["fleets_by_id"]["fleet.player"]["flagship_unit_id"]]
	var enemy_flagship: Dictionary = state["units_by_id"][state["fleets_by_id"]["fleet.enemy"]["flagship_unit_id"]]
	var player_sunk: bool = player_flagship["life_state"] == "Sunk"
	var enemy_sunk: bool = enemy_flagship["life_state"] == "Sunk"
	if not player_sunk and not enemy_sunk: return
	if player_sunk and enemy_sunk:
		_finish_battle("", "FLAGSHIP_SUNK_SIMULTANEOUS")
		return
	var winner := PLAYER_FACTION if enemy_sunk else ENEMY_FACTION
	_finish_battle(winner, "FLAGSHIP_SUNK")


func _check_timeout() -> void:
	if state["phase"] != "Running" or float(state["elapsed_time"]) < float(state["time_limit"]): return
	if not str(state.get("level_objective", {}).get("objective_set_id", "")).is_empty():
		_finish_battle("", "LEVEL_TECHNICAL_LIMIT")
		return
	var player_ratio := _remaining_hp_ratio("fleet.player")
	var enemy_ratio := _remaining_hp_ratio("fleet.enemy")
	_finish_battle(PLAYER_FACTION if player_ratio >= enemy_ratio else ENEMY_FACTION, "TIME_LIMIT")


func _update_level_objective() -> void:
	if str(state.get("level_objective", {}).get("objective_set_id", "")).is_empty(): return
	var previous_engagement := bool(state.get("level_objective", {}).get("engagement_unlocked", false))
	var update: Dictionary = level_objective_service.advance(state)
	state["level_objective"] = level_objective_service.snapshot()
	for objective_event in update.get("events", []):
		var event: Dictionary = objective_event
		_emit(str(event.get("event_type", "LevelObjectiveAdvanced")), event)
	if not previous_engagement and bool(state["level_objective"].get("engagement_unlocked", false)):
		_full_ai_factions[PLAYER_FACTION] = true
		var engagement_control_state := level_objective_service.engagement_player_control_state()
		for unit_id in state["fleets_by_id"]["fleet.player"]["unit_ids"]:
			var tutorial_unit: Dictionary = state["units_by_id"][unit_id]
			tutorial_unit["control_authority"] = "TutorialAssistAI"
			_apply_tutorial_control_state(tutorial_unit, engagement_control_state)
			tutorial_unit["player_route_waypoints"] = []
			tutorial_unit["movement_state"] = _new_movement_state("AutoNavigate" if bool(tutorial_unit.get("movement_assist_enabled", false)) else "HoldPosition", tutorial_unit["position"], [])
			_mark_navigation_dirty(tutorial_unit)
		var enemy_mode_locks := level_objective_service.engagement_enemy_mode_locks()
		for ship_id in enemy_mode_locks:
			_ai_mode_locks_by_definition[str(ship_id)] = str(enemy_mode_locks[ship_id])
		for unit_id in state["fleets_by_id"]["fleet.enemy"]["unit_ids"]:
			var enemy_unit: Dictionary = state["units_by_id"][unit_id]
			var locked_mode := str(enemy_mode_locks.get(str(enemy_unit.get("definition_id", "")), ""))
			if locked_mode.is_empty(): continue
			enemy_unit["ai_state"]["mode_id"] = locked_mode
			enemy_unit["ai_state"]["mode_candidate_id"] = ""
			enemy_unit["ai_state"]["mode_candidate_confirmations"] = 0
	var terminal: Dictionary = update.get("terminal", {})
	if not terminal.is_empty() and state.get("phase", "") == "Running":
		_finish_battle(str(terminal.get("winner_faction", "")), str(terminal.get("reason", "LEVEL_OBJECTIVE_COMPLETED")))


func _apply_tutorial_control_state(unit: Dictionary, control_state: Dictionary) -> void:
	for field_name in ["movement_assist_enabled", "secondary_auto_fire_enabled", "primary_auto_fire_enabled"]:
		if control_state.has(field_name): unit[field_name] = bool(control_state[field_name])
	unit["skill_auto_cast_enabled"] = false


func _finish_battle(winner: String, reason: String) -> void:
	state["phase"] = "Finished"
	state["result"] = {"winner_faction": winner, "reason": reason, "elapsed_time": state["elapsed_time"], "level_objective": state.get("level_objective", {}).duplicate(true)}
	_emit("BattleFinished", {"result": state["result"].duplicate(true)})


func _remaining_hp_ratio(fleet_id: String) -> float:
	var fleet: Dictionary = state["fleets_by_id"][fleet_id]
	var hp := 0.0
	for unit_id in fleet["unit_ids"]: hp += float(state["units_by_id"][unit_id]["current_hp"])
	return hp / maxf(1.0, float(fleet["initial_max_hp_total"]))


func _current_or_select_target(unit: Dictionary, player_assist: bool = false) -> Dictionary:
	var observation = _ai_observation_for(str(unit.get("faction_id", "")))
	var focused_id := str(unit.get("targeting_state", {}).get("focused_target_id", ""))
	if not focused_id.is_empty():
		var focused: Dictionary = observation.visible_enemies.get(focused_id, {})
		if focused.get("life_state", "") == "Alive":
			_commit_ai_target(unit, focused, "FOCUSED_TARGET")
			return focused
	var current_id := str(unit.get("targeting_state", {}).get("current_target_id", ""))
	if not current_id.is_empty():
		var current: Dictionary = observation.visible_enemies.get(current_id, {})
		if current.get("life_state", "") == "Alive": return current
	var selected := _select_target(unit, player_assist)
	_commit_ai_target(unit, selected, "TARGET_INVALID_OR_EMPTY")
	return selected


func _select_target_with_hysteresis(unit: Dictionary, player_assist: bool = false) -> Dictionary:
	var observation = _ai_observation_for(str(unit.get("faction_id", "")))
	var best := _select_target(unit, player_assist)
	var focused_id := str(unit.get("targeting_state", {}).get("focused_target_id", ""))
	if not focused_id.is_empty() and str(best.get("entity_id", "")) == focused_id:
		_commit_ai_target(unit, best, "FOCUSED_TARGET")
		return best
	var current_id := str(unit.get("targeting_state", {}).get("current_target_id", ""))
	var current: Dictionary = observation.visible_enemies.get(current_id, {})
	if current.is_empty() or current.get("life_state", "") != "Alive":
		_commit_ai_target(unit, best, "TARGET_INVALID_OR_EMPTY")
		return best
	if best.is_empty() or str(best.get("entity_id", "")) == current_id:
		unit["ai_state"]["target_candidate_id"] = ""
		unit["ai_state"]["target_candidate_confirmations"] = 0
		return current
	var ai_state: Dictionary = unit["ai_state"]
	var now := float(state.get("elapsed_time", 0.0))
	if now - float(ai_state.get("target_acquired_at", 0.0)) < AI_TARGET_MINIMUM_HOLD or now < float(ai_state.get("target_switch_ready_at", 0.0)):
		ai_state["target_candidate_id"] = ""
		ai_state["target_candidate_confirmations"] = 0
		return current
	var current_score := _target_score(unit, current, player_assist)
	var best_score := _target_score(unit, best, player_assist)
	if best_score < current_score + AI_TARGET_SWITCH_MARGIN:
		ai_state["target_candidate_id"] = ""
		ai_state["target_candidate_confirmations"] = 0
		return current
	var best_id := str(best["entity_id"])
	if str(ai_state.get("target_candidate_id", "")) != best_id:
		ai_state["target_candidate_id"] = best_id
		ai_state["target_candidate_confirmations"] = 0
	ai_state["target_candidate_confirmations"] = int(ai_state.get("target_candidate_confirmations", 0)) + 1
	var required_confirmations := 2 if player_assist else int(_ai_profile.get("target_confirmations", 2))
	if int(ai_state["target_candidate_confirmations"]) < required_confirmations:
		return current
	_commit_ai_target(unit, best, "BETTER_TARGET_CONFIRMED")
	return best


func _commit_ai_target(unit: Dictionary, target: Dictionary, reason: String) -> void:
	var old_id := str(unit.get("targeting_state", {}).get("current_target_id", ""))
	var new_id := str(target.get("entity_id", ""))
	unit["targeting_state"]["current_target_id"] = new_id
	var ai_state: Dictionary = unit["ai_state"]
	ai_state["target_candidate_id"] = ""
	ai_state["target_candidate_confirmations"] = 0
	if old_id == new_id:
		return
	var now := float(state.get("elapsed_time", 0.0))
	ai_state["target_acquired_at"] = now
	ai_state["target_switch_ready_at"] = now + AI_TARGET_SWITCH_COOLDOWN
	_emit("AITargetChanged", {"unit_id": unit["entity_id"], "old_target_id": old_id, "new_target_id": new_id, "reason": reason})


func _select_target(unit: Dictionary, player_assist: bool = false) -> Dictionary:
	var observation = _ai_observation_for(str(unit.get("faction_id", "")))
	var focused_id := str(unit["targeting_state"].get("focused_target_id", ""))
	if not focused_id.is_empty():
		var focused: Dictionary = observation.visible_enemies.get(focused_id, {})
		if not focused.is_empty() and focused["life_state"] == "Alive": return focused
	var candidates: Array = []
	for target_id in observation.visible_enemies:
		var target: Dictionary = observation.visible_enemies[target_id]
		if target["life_state"] == "Alive": candidates.append(target)
	candidates.sort_custom(func(a, b):
		var score_a := _target_score(unit, a, player_assist)
		var score_b := _target_score(unit, b, player_assist)
		return score_a > score_b if not is_equal_approx(score_a, score_b) else str(a["entity_id"]) < str(b["entity_id"]))
	return {} if candidates.is_empty() else candidates[0]


func _target_score(source: Dictionary, target: Dictionary, player_assist: bool = false) -> float:
	var distance := (source["position"] as Vector2).distance_to(target["position"] as Vector2)
	var preferred := maxf(1.0, _preferred_range(source))
	var kill_opportunity := 1.0 - float(target.get("current_hp", 0.0)) / maxf(1.0, float(target.get("max_hp", 1.0)))
	var turn_cost := absf(wrapf((target["position"] - source["position"]).angle() - float(source.get("heading", 0.0)), -PI, PI)) / PI
	if player_assist:
		return AIQuantitativeModel.player_assist_target_score({
			"visible": true,
			"legal": true,
			"immediate_threat": clampf(1.0 - distance / maxf(preferred * 1.4, 1.0), 0.0, 1.0),
			"weapon_fit": _weapon_fit(source, target),
			"range_fit": _range_fit(source, target),
			"kill_opportunity": kill_opportunity,
			"turn_cost": turn_cost,
		})
	var mission_priorities := {"Carrier": 1.0, "Submarine": 0.9, "Destroyer": 0.78, "Battleship": 0.72, "HeavyCruiser": 0.62, "LightCruiser": 0.55}
	var mission_value := float(mission_priorities.get(target["stats"].get("ship_class", ""), 0.5))
	if bool(target.get("is_flagship", false)): mission_value = minf(1.0, mission_value + 0.25)
	var focus_count := 0
	for ally_id in _sorted_unit_ids():
		var ally: Dictionary = state["units_by_id"][ally_id]
		if ally.get("life_state", "") == "Alive" and ally.get("faction_id", "") == source.get("faction_id", "") and str(ally.get("targeting_state", {}).get("current_target_id", "")) == str(target.get("entity_id", "")):
			focus_count += 1
	var reserved_ratio := _reserved_damage_for_target(str(target.get("entity_id", "")), str(source.get("entity_id", ""))) / maxf(1.0, float(target.get("current_hp", 1.0)))
	return AIQuantitativeModel.target_score({
		"visible": true,
		"legal": true,
		"mission_value": mission_value,
		"threat": clampf(0.65 * _target_threat_value(source, target) + 0.35 * _protectee_threat(source, target), 0.0, 1.0),
		"weapon_fit": _weapon_fit(source, target),
		"range_fit": _range_fit(source, target),
		"kill_opportunity": kill_opportunity,
		"focus_fire": clampf(float(focus_count) / 2.0, 0.0, 1.0),
		"objective_relevance": _protectee_threat(source, target),
		"pursuit_cost": clampf(distance / maxf(preferred * 2.2, 1.0), 0.0, 1.0),
		"overkill": maxf(0.35 if kill_opportunity > 0.9 and focus_count >= 2 else 0.0, clampf(reserved_ratio, 0.0, 1.0)),
	})


func _target_threat_value(source: Dictionary, target: Dictionary) -> float:
	var distance := (source.get("position", Vector2.ZERO) as Vector2).distance_to(target.get("position", Vector2.ZERO))
	var best := 0.0
	for weapon_state in target.get("weapon_states", []):
		if not bool(weapon_state.get("enabled", true)): continue
		var weapon := _weapon_for_state(weapon_state)
		if weapon.is_empty() or _target_type(source) not in weapon.get("target_types", []): continue
		var weapon_range := maxf(1.0, float(weapon.get("range", 1.0)))
		var range_pressure := clampf(1.0 - maxf(0.0, distance - weapon_range) / weapon_range, 0.0, 1.0)
		var damage_pressure := _expected_weapon_damage_ratio(target, source, weapon)
		best = maxf(best, 0.55 * damage_pressure + 0.45 * range_pressure)
	return best


func _default_ai_mode(ship: Dictionary) -> String:
	match str(ship.get("ship_class", "")):
		"Carrier": return "CarrierStandoff"
		"Battleship": return "GunlineSupport"
		"Submarine": return "TorpedoFlank"
		_: return "VanguardLine"


func _allowed_ai_modes(unit: Dictionary) -> Array:
	match str(unit.get("stats", {}).get("ship_class", "")):
		"Destroyer": return ["ReconAvoid", "VanguardLine", "TorpedoFlank", "EscortScreen", "DisengageRegroup"]
		"LightCruiser", "HeavyCruiser": return ["VanguardLine", "GunlineSupport", "EscortScreen", "DisengageRegroup"]
		"Battleship": return ["GunlineSupport", "VanguardLine", "DisengageRegroup"]
		"Carrier": return ["CarrierStandoff", "DisengageRegroup"]
		"Submarine": return ["TorpedoFlank", "ReconAvoid", "DisengageRegroup"]
		_: return ["VanguardLine", "DisengageRegroup"]


func _enemy_mode_values(unit: Dictionary, target: Dictionary) -> Dictionary:
	var local := _local_power_context(unit)
	var battlefield := _battlefield_target_context(unit, target)
	var hp_safety := float(unit.get("current_hp", 0.0)) / maxf(1.0, float(unit.get("max_hp", 1.0)))
	var fleet_center := Vector2.ZERO
	var ally_count := 0
	for unit_id in _sorted_unit_ids():
		var ally: Dictionary = state["units_by_id"][unit_id]
		if ally.get("life_state", "") != "Alive" or ally.get("faction_id", "") != unit.get("faction_id", ""): continue
		fleet_center += ally["position"]
		ally_count += 1
	if ally_count > 0: fleet_center /= float(ally_count)
	var cohesion := clampf(1.0 - (unit["position"] as Vector2).distance_to(fleet_center) / 700.0, 0.0, 1.0)
	var target_valid := 0.0 if target.is_empty() else 1.0
	var target_high_value := 0.0 if target.is_empty() else (1.0 if target.get("is_flagship", false) or target.get("stats", {}).get("ship_class", "") == "Carrier" else 0.35)
	return {
		"hp_safety": hp_safety,
		"local_pressure": float(local.get("pressure", 0.0)),
		"boundary_risk": _boundary_risk(unit),
		"exit_quality": 1.0 - _boundary_risk(unit),
		"vision_need": 1.0 - clampf(float(_ai_observation_for(str(unit.get("faction_id", ""))).visible_enemies.size()) / 3.0, 0.0, 1.0),
		"cohesion": cohesion,
		"recon_route_quality": float(battlefield.get("search_route_quality", 0.0)),
		"valid_target": target_valid,
		"weapon_ready": _primary_ready_ratio(unit),
		"flank_quality": target_valid * float(battlefield.get("flank_quality", 0.0)),
		"high_value_exposed": target_high_value,
		"group_fixing_target": _ally_weapon_readiness(unit),
		"firing_lane_quality": float(battlefield.get("firing_lane_quality", 0.0)),
		"escort_coverage": float(local.get("friendly_ratio", 0.5)),
		"protectee_threat": 0.0 if target.is_empty() else _protectee_threat(unit, target),
		"intercept_quality": target_valid * (1.0 - _boundary_risk(unit)),
		"defensive_skill_ready": 1.0 if float(unit.get("skill_state", {}).get("cooldown_remaining", 1.0)) <= 0.0 else 0.0,
		"engagement_pressure": float(unit.get("ai_state", {}).get("engagement_pressure", 0.0)),
	}


func _primary_ready_ratio(unit: Dictionary) -> float:
	var group_id := str(unit.get("stats", {}).get("primary_weapon_group_id", ""))
	var weapon_states := _weapon_states_for_group(unit, group_id, true)
	var best := 0.0
	for weapon_state in weapon_states:
		if not bool(weapon_state.get("enabled", true)): continue
		var weapon := _weapon_for_state(weapon_state)
		var reload_max := maxf(0.1, float(weapon.get("reload_time", 0.1)))
		best = maxf(best, 1.0 - clampf(float(weapon_state.get("reload_remaining", 0.0)) / reload_max, 0.0, 1.0))
	return best


func _normalized_target_value(source: Dictionary, target: Dictionary, player_assist: bool) -> float:
	return clampf(_target_score(source, target, player_assist) / 100.0, 0.0, 1.0)


func _visible_enemy_count_in_radius(unit: Dictionary, radius: float) -> int:
	var count := 0
	var effective_radius := maxf(radius, _preferred_range(unit))
	var observation = _ai_observation_for(str(unit.get("faction_id", "")))
	for target_id in observation.visible_enemies:
		var target: Dictionary = observation.visible_enemies.get(target_id, {})
		if target.get("life_state", "") == "Alive" and (unit["position"] as Vector2).distance_to(target["position"]) <= effective_radius:
			count += 1
	return count


func _ally_weapon_readiness(unit: Dictionary) -> float:
	var total := 0.0
	var count := 0
	var radius := maxf(450.0, _preferred_range(unit) * 1.3)
	for ally_id in _sorted_unit_ids():
		var ally: Dictionary = state["units_by_id"][ally_id]
		if ally.get("entity_id", "") == unit.get("entity_id", "") or ally.get("life_state", "") != "Alive" or ally.get("faction_id", "") != unit.get("faction_id", ""): continue
		if (unit["position"] as Vector2).distance_to(ally["position"]) > radius: continue
		total += _primary_ready_ratio(ally)
		count += 1
	return total / float(count) if count > 0 else 0.0


func _attack_window_group_sync(unit: Dictionary) -> float:
	var radius := maxf(450.0, _preferred_range(unit) * 1.3)
	for ally_id in _sorted_unit_ids():
		var ally: Dictionary = state["units_by_id"][ally_id]
		if ally.get("entity_id", "") == unit.get("entity_id", "") or ally.get("life_state", "") != "Alive" or ally.get("faction_id", "") != unit.get("faction_id", ""): continue
		if (unit.get("position", Vector2.ZERO) as Vector2).distance_to(ally.get("position", Vector2.ZERO)) <= radius:
			return _ally_weapon_readiness(unit)
	return 1.0


func _local_power_context(unit: Dictionary) -> Dictionary:
	var cache_key := str(unit.get("entity_id", ""))
	if _ai_local_power_cache.has(cache_key):
		return _ai_local_power_cache[cache_key]
	var friendly_power := 0.0
	var enemy_power := 0.0
	var friendly_count := 0
	var radius := maxf(600.0, _preferred_range(unit) * 1.25)
	var observation = _ai_observation_for(str(unit.get("faction_id", "")))
	var observed_units: Array = observation.friendly_units.values() + observation.visible_enemies.values()
	for other in observed_units:
		if other.get("life_state", "") != "Alive" or (unit["position"] as Vector2).distance_to(other["position"]) > radius: continue
		var hp_ratio := float(other.get("current_hp", 0.0)) / maxf(1.0, float(other.get("max_hp", 1.0)))
		var power := maxf(1.0, float(other.get("stats", {}).get("cost", 1.0))) * hp_ratio
		if other.get("faction_id", "") == unit.get("faction_id", ""):
			friendly_power += power
			friendly_count += 1
		else:
			enemy_power += power
	var total := friendly_power + enemy_power
	var power_ratio := enemy_power / maxf(friendly_power, 1.0)
	var context := {
		"advantage": friendly_power / total if total > 0.0 else 0.5,
		"pressure": clampf((power_ratio - 0.8) / 1.2, 0.0, 1.0),
		"friendly_ratio": clampf(float(friendly_count) / 3.0, 0.0, 1.0),
	}
	_ai_local_power_cache[cache_key] = context
	return context


func _range_fit(source: Dictionary, target: Dictionary) -> float:
	var distance := (source["position"] as Vector2).distance_to(target["position"])
	var preferred := maxf(1.0, _preferred_range(source))
	var ratio := distance / preferred
	return clampf(1.0 - absf(ratio - 0.8) / 0.8, 0.0, 1.0)


func _weapon_fit(source: Dictionary, target: Dictionary) -> float:
	var armor_class := str(target.get("stats", {}).get("armor_thickness", "Unarmored"))
	var target_type := _target_type(target)
	var best := 0.0
	for weapon_state in source.get("weapon_states", []):
		var weapon := _weapon_for_state(weapon_state)
		if target_type not in weapon.get("target_types", []): continue
		var modifier := float(weapon.get("armor_damage_modifiers", {}).get(armor_class, 0.0))
		best = maxf(best, clampf(modifier / 1.25, 0.0, 1.0))
	return best


func _protectee_threat(source: Dictionary, target: Dictionary) -> float:
	var flagship := _faction_flagship(str(source.get("faction_id", "")))
	if flagship.is_empty(): return 0.0
	var distance := (flagship["position"] as Vector2).distance_to(target["position"])
	return clampf(1.0 - distance / maxf(500.0, _preferred_range(target)), 0.0, 1.0)


func _boundary_risk(unit: Dictionary) -> float:
	var width := float(state.get("map", {}).get("width", 1200.0))
	var height := float(state.get("map", {}).get("height", 700.0))
	var future := (unit["position"] as Vector2) + Vector2.RIGHT.rotated(float(unit.get("heading", 0.0))) * float(unit.get("current_speed", 0.0)) * 2.0
	var clearance := minf(minf(future.x, width - future.x), minf(future.y, height - future.y))
	return clampf(1.0 - clearance / 140.0, 0.0, 1.0)


func _faction_flagship(faction_id: String) -> Dictionary:
	for fleet_id in state.get("fleets_by_id", {}):
		var fleet: Dictionary = state["fleets_by_id"][fleet_id]
		if str(fleet.get("faction_id", "")) != faction_id: continue
		return state.get("units_by_id", {}).get(str(fleet.get("flagship_unit_id", "")), {})
	return {}


func _fire_discipline_for_mode(mode_id: String) -> String:
	match mode_id:
		"ReconAvoid": return "Silent"
		"TorpedoFlank": return "HoldUntilWindow"
		"EscortScreen", "CarrierStandoff", "DisengageRegroup": return "SelfDefense"
		_: return "FreeFire"


func _is_unit_under_threat(unit: Dictionary, target: Dictionary = {}) -> bool:
	if float(_local_power_context(unit).get("pressure", 0.0)) > 0.0:
		return true
	if not target.is_empty() and (unit.get("position", Vector2.ZERO) as Vector2).distance_to(target.get("position", Vector2.ZERO)) <= maxf(350.0, _preferred_range(unit) * 0.8):
		return true
	if not target.is_empty() and _protectee_threat(unit, target) >= 0.35:
		return true
	return float(unit.get("current_hp", 0.0)) / maxf(1.0, float(unit.get("max_hp", 1.0))) <= 0.5


func _is_unit_in_fire_emergency(unit: Dictionary, target: Dictionary = {}) -> bool:
	var hp_ratio := float(unit.get("current_hp", 0.0)) / maxf(1.0, float(unit.get("max_hp", 1.0)))
	if hp_ratio <= 0.35 or float(_local_power_context(unit).get("pressure", 0.0)) >= 0.75:
		return true
	return not target.is_empty() and (unit.get("position", Vector2.ZERO) as Vector2).distance_to(target.get("position", Vector2.ZERO)) <= 250.0


func _automatic_weapon_allowed_by_ai_discipline(unit: Dictionary, target: Dictionary, weapon: Dictionary) -> bool:
	var mode_id := str(unit.get("ai_state", {}).get("mode_id", "VanguardLine"))
	var discipline := _fire_discipline_for_mode(mode_id)
	var aim_solution := _automatic_aim_solution(unit, target, weapon)
	var aim_position: Vector2 = aim_solution.get("position", target.get("position", Vector2.ZERO))
	var fire_validation := _can_fire_at_position(unit, aim_position, weapon)
	var window_values := {
		"target_value": _normalized_target_value(unit, target, false),
		"hit_quality": _weapon_hit_quality(unit, target, weapon),
		"weapon_ready": 1.0,
		"expected_damage": _expected_weapon_damage_ratio(unit, target, weapon),
		"skill_synergy": 1.0 if float(unit.get("skill_state", {}).get("cooldown_remaining", 0.0)) <= 0.0 else 0.0,
		"group_sync": _attack_window_group_sync(unit),
		"kill_opportunity": 1.0 - float(target.get("current_hp", 0.0)) / maxf(1.0, float(target.get("max_hp", 1.0))),
		"objective_relevance": _protectee_threat(unit, target),
		"exposure_risk": float(_local_power_context(unit).get("pressure", 0.0)),
		"overkill": 0.0,
		"friendly_risk": _friendly_fire_risk(unit, target, weapon, aim_position),
		"engagement_pressure": float(unit.get("ai_state", {}).get("engagement_pressure", 0.0)),
		"visible": _is_visible_to(str(unit.get("faction_id", "")), str(target.get("entity_id", ""))),
		"weapon_legal": _can_fire(unit, target, weapon),
		"path_clear": bool(fire_validation.get("legal", false)),
	}
	return bool(AIQuantitativeModel.should_fire(window_values, discipline, _is_unit_under_threat(unit, target), _is_unit_in_fire_emergency(unit, target)).get("fire", false))


func _battlefield_target_context(unit: Dictionary, target: Dictionary) -> Dictionary:
	var cache_key := "%s|%s" % [str(unit.get("entity_id", "")), str(target.get("entity_id", "none"))]
	if _ai_battlefield_context_cache.has(cache_key):
		return _ai_battlefield_context_cache[cache_key]
	var position_safety := _position_safety(unit, unit.get("position", Vector2.ZERO))
	var search_destination := _map_center()
	if target.is_empty():
		var empty_context := {
			"position_safety": position_safety,
			"attack_route_quality": 0.0,
			"exit_quality": _route_quality_between(unit, search_destination),
			"search_route_quality": _route_quality_between(unit, search_destination),
			"flank_quality": 0.0,
			"firing_lane_quality": 0.0,
		}
		_ai_battlefield_context_cache[cache_key] = empty_context
		return empty_context
	var unit_position: Vector2 = unit.get("position", Vector2.ZERO)
	var target_position: Vector2 = target.get("position", Vector2.ZERO)
	var away := (unit_position - target_position).normalized()
	if away == Vector2.ZERO:
		away = Vector2.RIGHT.rotated(float(unit.get("heading", 0.0)) + PI)
	var exit_destination := _clamp_to_map(unit_position + away * maxf(180.0, _preferred_range(unit) * 0.4))
	var attack_destination := _tactical_destination(unit, target, "Attack", str(unit.get("ai_state", {}).get("mode_id", "VanguardLine")))
	var exit_quality := _route_quality_between(unit, exit_destination)
	var attack_route_quality := _route_quality_between(unit, attack_destination)
	var source_bearing := (unit_position - target_position).angle()
	var crossfire_angle := 0.0
	for ally_id in _sorted_unit_ids():
		var ally: Dictionary = state["units_by_id"][ally_id]
		if ally.get("entity_id", "") == unit.get("entity_id", "") or ally.get("life_state", "") != "Alive" or ally.get("faction_id", "") != unit.get("faction_id", ""):
			continue
		var ally_bearing := ((ally.get("position", Vector2.ZERO) as Vector2) - target_position).angle()
		crossfire_angle = maxf(crossfire_angle, absf(wrapf(ally_bearing - source_bearing, -PI, PI)))
	var flank_quality := AIQuantitativeModel.flank_quality({
		"reachable": attack_route_quality > 0.0,
		"bearing_from_target": source_bearing,
		"target_heading": float(target.get("heading", 0.0)),
		"crossfire_angle": crossfire_angle,
		"distance_fit": _range_fit(unit, target),
		"exit_quality": exit_quality,
	}) / 100.0
	var firing_lane_quality := 0.0
	var primary_states := _weapon_states_for_group(unit, str(unit.get("stats", {}).get("primary_weapon_group_id", "")), true)
	if not primary_states.is_empty():
		var weapon := _weapon_for_state(primary_states[0])
		var aim_solution := _automatic_aim_solution(unit, target, weapon)
		var aim_position: Vector2 = aim_solution.get("position", target_position)
		var validation := _can_fire_at_position(unit, aim_position, weapon)
		firing_lane_quality = AIQuantitativeModel.firing_lane_quality({
			"weapon_legal": _can_fire(unit, target, weapon),
			"path_clear": bool(validation.get("legal", false)),
			"arc_quality": _fire_arc_quality(unit, aim_position, weapon),
			"range_fit": _range_fit(unit, target),
			"friendly_risk": _friendly_fire_risk(unit, target, weapon, aim_position),
			"sustain_quality": position_safety,
		}) / 100.0
	var context := {
		"position_safety": position_safety,
		"attack_route_quality": attack_route_quality,
		"exit_quality": exit_quality,
		"search_route_quality": attack_route_quality,
		"flank_quality": flank_quality,
		"firing_lane_quality": firing_lane_quality,
	}
	_ai_battlefield_context_cache[cache_key] = context
	return context


func _route_quality_between(unit: Dictionary, destination: Vector2) -> float:
	var origin: Vector2 = unit.get("position", Vector2.ZERO)
	var direct_distance := origin.distance_to(destination)
	if direct_distance <= 8.0:
		return _position_safety(unit, destination)
	var origin_cell := Vector2i(roundi(origin.x / 80.0), roundi(origin.y / 80.0))
	var destination_cell := Vector2i(roundi(destination.x / 80.0), roundi(destination.y / 80.0))
	var cache_key := "%s|%s|%s" % [unit.get("entity_id", ""), origin_cell, destination_cell]
	var now := float(state.get("elapsed_time", 0.0))
	var cached: Dictionary = _ai_route_quality_cache.get(cache_key, {})
	if not cached.is_empty() and float(cached.get("expires_at", 0.0)) > now:
		return float(cached.get("quality", 0.0))
	var radius := float(unit.get("stats", {}).get("collision_radius", 20.0))
	if not terrain_query.can_occupy_circle(destination, radius, _movement_tags(unit)):
		_ai_route_quality_cache[cache_key] = {"quality": 0.0, "expires_at": now + 1.0}
		return 0.0
	# Tactical scoring needs a stable reach estimate, not an authoritative route.
	# Full A* remains in the accepted movement command path.
	var direct_clear := _cheap_ai_segment_clear(unit, origin, destination)
	var threat_safety := 1.0
	var boundary_safety := 1.0 - _boundary_risk_at_position(destination)
	var congestion_safety := 1.0
	var observation = _ai_observation_for(str(unit.get("faction_id", "")))
	for enemy_id in observation.visible_enemies:
		var enemy: Dictionary = observation.visible_enemies.get(enemy_id, {})
		if enemy.get("life_state", "") != "Alive": continue
		var danger_range := maxf(350.0, _preferred_range(enemy))
		threat_safety = minf(threat_safety, clampf(destination.distance_to(enemy.get("position", Vector2.ZERO)) / danger_range, 0.0, 1.0))
	for ally_id in _sorted_unit_ids():
		var ally: Dictionary = state["units_by_id"][ally_id]
		if ally.get("entity_id", "") == unit.get("entity_id", "") or ally.get("life_state", "") != "Alive" or ally.get("faction_id", "") != unit.get("faction_id", ""): continue
		congestion_safety = minf(congestion_safety, clampf(destination.distance_to(ally.get("position", Vector2.ZERO)) / 140.0, 0.0, 1.0))
	var time_efficiency := 1.0 if direct_clear else 0.55
	var quality := AIQuantitativeModel.route_utility({
		"legal": true,
		"time_efficiency": time_efficiency,
		"depth_safety": 1.0 if direct_clear else 0.7,
		"threat_safety": threat_safety,
		"exposure_safety": threat_safety,
		"turn_room": boundary_safety,
		"congestion_safety": congestion_safety,
		"formation_fit": _formation_fit_at(unit, destination),
		"objective_fit": 1.0,
	}) / 100.0
	_ai_route_quality_cache[cache_key] = {"quality": quality, "expires_at": now + 2.0}
	return quality


func _formation_fit_at(unit: Dictionary, position: Vector2) -> float:
	var center := Vector2.ZERO
	var count := 0
	for ally_id in _sorted_unit_ids():
		var ally: Dictionary = state["units_by_id"][ally_id]
		if ally.get("life_state", "") != "Alive" or ally.get("faction_id", "") != unit.get("faction_id", ""): continue
		center += ally.get("position", Vector2.ZERO)
		count += 1
	if count <= 1:
		return 1.0
	center /= float(count)
	return clampf(1.0 - position.distance_to(center) / 900.0, 0.0, 1.0)


func _position_safety(unit: Dictionary, position: Vector2) -> float:
	var boundary_safety := 1.0 - _boundary_risk_at_position(position)
	if terrain_query.is_configured() and not terrain_query.can_occupy_circle(position, float(unit.get("stats", {}).get("collision_radius", 20.0)), _movement_tags(unit)):
		return 0.0
	return boundary_safety


func _boundary_risk_at_position(position: Vector2) -> float:
	var width := float(state.get("map", {}).get("width", 1200.0))
	var height := float(state.get("map", {}).get("height", 700.0))
	var clearance := minf(minf(position.x, width - position.x), minf(position.y, height - position.y))
	return clampf(1.0 - clearance / 140.0, 0.0, 1.0)


func _fire_arc_quality(unit: Dictionary, target_position: Vector2, weapon: Dictionary) -> float:
	var direction := target_position - (unit.get("position", Vector2.ZERO) as Vector2)
	if direction.length_squared() <= 0.0001:
		return 0.0
	var quality := 0.0
	for arc in _weapon_fire_arcs(weapon):
		var half_arc := deg_to_rad(float(arc.get("degrees", 360.0)) * 0.5)
		if half_arc >= PI - 0.0001:
			return 1.0
		var center := float(unit.get("heading", 0.0)) + deg_to_rad(float(arc.get("center", 0.0)))
		var delta := absf(wrapf(direction.angle() - center, -PI, PI))
		if delta <= half_arc:
			quality = maxf(quality, 1.0 - delta / maxf(0.0001, half_arc))
	return quality


func _weapon_hit_quality(unit: Dictionary, target: Dictionary, weapon: Dictionary) -> float:
	if weapon.is_empty():
		return 0.0
	if str(weapon.get("mount_type", "")) == "Torpedo":
		var source_bearing := ((unit.get("position", Vector2.ZERO) as Vector2) - (target.get("position", Vector2.ZERO) as Vector2)).angle()
		var aspect := AIQuantitativeModel.flank_quality({
			"bearing_from_target": source_bearing,
			"target_heading": float(target.get("heading", 0.0)),
			"distance_fit": _range_fit(unit, target),
			"exit_quality": 0.5,
		}) / 100.0
		return clampf(0.55 * _range_fit(unit, target) + 0.45 * aspect, 0.0, 1.0)
	var formula: Dictionary = registry.get_definition("formulas", str(weapon.get("formula_id", "")))
	if formula.is_empty():
		return _range_fit(unit, target)
	var estimate := DamageService.estimate_attack({"accuracy_modifier": _environment_accuracy_modifier(str(unit.get("faction_id", "")), unit.get("position", Vector2.ZERO), target.get("position", Vector2.ZERO), str(weapon.get("mount_type", "Gun")))}, unit, target, weapon, formula)
	return clampf(float(estimate.get("hit_rate", 0.0)), 0.0, 1.0)


func _expected_weapon_damage_ratio(unit: Dictionary, target: Dictionary, weapon: Dictionary) -> float:
	var expected_volley := _estimated_weapon_volley_damage(unit, target, weapon)
	var tactical_hp_window := minf(float(target.get("current_hp", 1.0)), float(target.get("max_hp", target.get("current_hp", 1.0))) * 0.25)
	return clampf(expected_volley / maxf(1.0, tactical_hp_window), 0.0, 1.0)


func _estimated_weapon_volley_damage(unit: Dictionary, target: Dictionary, weapon: Dictionary) -> float:
	if weapon.is_empty():
		return 0.0
	var formula: Dictionary = registry.get_definition("formulas", str(weapon.get("formula_id", "")))
	if formula.is_empty():
		return 0.0
	var estimate := DamageService.estimate_attack({"accuracy_modifier": _environment_accuracy_modifier(str(unit.get("faction_id", "")), unit.get("position", Vector2.ZERO), target.get("position", Vector2.ZERO), str(weapon.get("mount_type", "Gun")))}, unit, target, weapon, formula)
	var shot_count := int(weapon.get("shots_per_mount", 1))
	if str(weapon.get("mount_type", "")) != "Torpedo":
		shot_count *= int(weapon.get("mount_count", 1))
	return float(estimate.get("expected_damage", 0.0)) * float(maxi(1, shot_count))


func _friendly_fire_risk(unit: Dictionary, target: Dictionary, weapon: Dictionary, aim_position: Vector2) -> float:
	var risk := 0.0
	var mount_type := str(weapon.get("mount_type", "Gun"))
	var origin: Vector2 = unit.get("position", Vector2.ZERO)
	for ally_id in _sorted_unit_ids():
		var ally: Dictionary = state["units_by_id"][ally_id]
		if ally.get("entity_id", "") == unit.get("entity_id", "") or ally.get("life_state", "") != "Alive" or ally.get("faction_id", "") != unit.get("faction_id", ""):
			continue
		var ally_position: Vector2 = ally.get("position", Vector2.ZERO)
		var ally_velocity := Vector2.RIGHT.rotated(float(ally.get("heading", 0.0))) * float(ally.get("current_speed", 0.0))
		var projected_position := ally_position + ally_velocity * 2.0
		if mount_type == "Torpedo":
			var direction := (aim_position - origin).normalized()
			if direction == Vector2.ZERO: continue
			var end := origin + direction * float(weapon.get("range", origin.distance_to(aim_position)))
			var half_extents := _unit_collision_half_extents(ally) + Vector2.ONE * 12.0
			for candidate_position in [ally_position, projected_position]:
				var fraction := CollisionGeometryService.segment_expanded_ellipse_fraction(origin, end, candidate_position, float(ally.get("heading", 0.0)), half_extents)
				if fraction >= 0.0:
					risk = maxf(risk, 1.0 - 0.5 * fraction)
		else:
			var danger_radius := float(weapon.get("impact_radius", 40.0)) + _unit_collision_half_extents(ally).x
			for candidate_position in [ally_position, projected_position]:
				risk = maxf(risk, clampf(1.0 - candidate_position.distance_to(aim_position) / maxf(1.0, danger_radius * 2.0), 0.0, 1.0))
	return risk


func _map_center() -> Vector2:
	return Vector2(float(state.get("map", {}).get("width", 1200.0)) * 0.5, float(state.get("map", {}).get("height", 700.0)) * 0.5)


func _remaining_player_route(unit: Dictionary) -> int:
	if str(unit.get("movement_state", {}).get("mode", "")) not in ["PlayerMoveOrder", "PlayerWaypointRoute"]:
		return 0
	var movement: Dictionary = unit.get("movement_state", {})
	var corridor: Array = movement.get("corridor_points", [])
	if not corridor.is_empty(): return maxi(0, corridor.size() - int(movement.get("corridor_index", 0)))
	return maxi(0, movement.get("waypoints", []).size() - int(movement.get("waypoint_index", 0)))


func _preferred_range(unit: Dictionary) -> float:
	var maximum := 250.0
	for weapon_state in unit["weapon_states"]:
		var weapon: Dictionary = registry.get_definition("weapons", str(weapon_state["definition_id"]))
		maximum = maxf(maximum, _effective_weapon_range(unit, weapon))
	return maximum * 0.72


func _effective_weapon_range(unit: Dictionary, weapon: Dictionary) -> float:
	return maxf(0.0, ModifierService.calculate(float(weapon.get("range", 0.0)), _active_status_effects(unit), "WeaponRange", str(weapon.get("mount_type", "All"))))


func _clear_invalid_targets() -> void:
	for unit_id in _sorted_unit_ids():
		var unit: Dictionary = state["units_by_id"][unit_id]
		var focused_id := str(unit["targeting_state"].get("focused_target_id", ""))
		if focused_id.is_empty(): continue
		var target: Dictionary = state["units_by_id"].get(focused_id, {})
		if target.is_empty() or target["life_state"] != "Alive" or not _is_visible_to(unit["faction_id"], focused_id):
			unit["targeting_state"]["focused_target_id"] = ""
			unit["targeting_state"]["mode"] = "Automatic"
			_emit("FocusTargetChanged", {"unit_id": unit_id, "old_target_id": focused_id, "new_target_id": ""})


func _consume_effect(unit: Dictionary, stat: String, category: String) -> void:
	for index in range(unit["status_effects"].size() - 1, -1, -1):
		var effect: Dictionary = unit["status_effects"][index]
		if effect.get("stat", "") == stat and effect.get("category", "All") in ["All", category]: unit["status_effects"].remove_at(index)


func _consume_on_fire_effects(unit: Dictionary, weapon: Dictionary) -> void:
	var category := str(weapon.get("mount_type", "All"))
	var weapon_group_id := str(weapon.get("weapon_group_id", ""))
	for index in range(unit.get("status_effects", []).size() - 1, -1, -1):
		var effect: Dictionary = unit["status_effects"][index]
		if not bool(effect.get("consume_on_fire", false)) or str(effect.get("category", "All")) not in ["All", category]:
			continue
		var required_group := str(effect.get("consume_weapon_group_id", ""))
		if not required_group.is_empty() and required_group != weapon_group_id: continue
		unit["status_effects"].remove_at(index)
		_emit("StatusConsumed", {"target_unit_id":unit["entity_id"], "status_id":effect.get("status_id", ""), "reason":"WeaponFired"})


func _apply_zero_damage_reactions(target: Dictionary) -> void:
	for effect in _active_status_effects(target):
		if str(effect.get("stat", "")) != "ZeroDamageReloadProc": continue
		var proc_effect := {
			"stat":"ReloadSpeed", "operation":"PercentAdd", "value":float(effect.get("value", 0.0)),
			"category":str(effect.get("proc_category", "All")), "stack_group":str(effect.get("stack_group", "zero_damage_reload_proc")) + ".proc",
			"stack_rule":"Refresh",
		}
		_apply_status(target, proc_effect, float(effect.get("proc_duration", 3.0)), str(effect.get("status_id", "")), str(effect.get("source_unit_id", "")))


func _weapon_states_for_group(unit: Dictionary, group_id: String, match_selected_ammo: bool) -> Array:
	var result: Array = []
	if group_id.is_empty(): return result
	for weapon_state in unit.get("weapon_states", []):
		var weapon: Dictionary = registry.get_definition("weapons", str(weapon_state["definition_id"]))
		if str(weapon.get("weapon_group_id", "")) != group_id: continue
		if match_selected_ammo and not _weapon_matches_selected_ammo(unit, weapon): continue
		result.append(weapon_state)
	return result


func _weapon_matches_selected_ammo(unit: Dictionary, weapon: Dictionary) -> bool:
	var ammo_type := str(weapon.get("ammo_type", ""))
	if ammo_type.is_empty(): return true
	var group_id := str(weapon.get("weapon_group_id", ""))
	var selected_ammo := _selected_ammo_for_group(unit, group_id)
	return selected_ammo.is_empty() or ammo_type == selected_ammo


func _selected_ammo_for_group(unit: Dictionary, group_id: String) -> String:
	if group_id.is_empty(): return ""
	return str(unit.get("ammo_state", {}).get(group_id, ""))


func _ammo_options_for_ship(ship: Dictionary, ammo_group_id: String) -> Array[String]:
	var options: Array[String] = []
	if ammo_group_id.is_empty(): return options
	for weapon_id in ship.get("weapon_mounts", []):
		var weapon: Dictionary = registry.get_definition("weapons", str(weapon_id))
		if str(weapon.get("weapon_group_id", "")) != ammo_group_id: continue
		var ammo_type := str(weapon.get("ammo_type", ""))
		if ammo_type in ["HE", "AP"] and not ammo_type in options: options.append(ammo_type)
	options.sort()
	return options


func _primary_unavailable_reason(unit: Dictionary, primary_states: Array) -> String:
	if state.get("phase", "") != "Running": return "BATTLE_NOT_RUNNING"
	if unit.get("life_state", "") != "Alive": return "UNIT_SUNK"
	if primary_states.is_empty(): return "PRIMARY_WEAPON_UNAVAILABLE"
	if primary_states.all(func(weapon_state): return not bool(weapon_state.get("enabled", true))): return "WEAPON_GROUP_DISABLED"
	var primary_group_id := str(unit.get("stats", {}).get("primary_weapon_group_id", ""))
	if float(unit.get("weapon_group_launch_remaining", {}).get(primary_group_id, 0.0)) > 0.0:
		return "TORPEDO_MOUNT_INTERVAL"
	for weapon_state in primary_states:
		if float(weapon_state.get("reload_remaining", 0.0)) <= 0.0:
			return "OK"
	return "WEAPON_RELOADING"


func _validate_primary_fire(unit: Dictionary, weapon_states: Array, target_position: Vector2) -> Dictionary:
	if state.get("phase", "") != "Running": return {"legal": false, "reason_code": "BATTLE_NOT_RUNNING", "legal_weapon_states": []}
	if unit.get("life_state", "") != "Alive": return {"legal": false, "reason_code": "UNIT_SUNK", "legal_weapon_states": []}
	if weapon_states.is_empty(): return {"legal": false, "reason_code": "PRIMARY_WEAPON_UNAVAILABLE", "legal_weapon_states": []}
	var primary_group_id := str(unit.get("stats", {}).get("primary_weapon_group_id", ""))
	if float(unit.get("weapon_group_launch_remaining", {}).get(primary_group_id, 0.0)) > 0.0:
		return {"legal": false, "reason_code": "TORPEDO_MOUNT_INTERVAL", "legal_weapon_states": []}
	var ready_states: Array = []
	for weapon_state in weapon_states:
		if bool(weapon_state.get("enabled", true)) and float(weapon_state.get("reload_remaining", 0.0)) <= 0.0:
			ready_states.append(weapon_state)
	if ready_states.is_empty():
		var reason_code := "WEAPON_GROUP_DISABLED" if weapon_states.all(func(weapon_state): return not bool(weapon_state.get("enabled", true))) else "WEAPON_RELOADING"
		return {"legal": false, "reason_code": reason_code, "legal_weapon_states": []}
	var legal_states: Array = []
	var last_reason := "TARGET_OUT_OF_RANGE"
	for weapon_state in ready_states:
		var weapon := _weapon_for_state(weapon_state)
		var validation := _can_fire_in_direction(unit, target_position, weapon) if weapon.get("mount_type", "") == "Torpedo" else _can_fire_at_position(unit, target_position, weapon)
		if bool(validation.get("legal", false)): legal_states.append(weapon_state)
		else: last_reason = str(validation.get("reason_code", last_reason))
	legal_states.sort_custom(func(a, b): return int(a.get("mount_index", -1)) < int(b.get("mount_index", -1)))
	return {"legal": not legal_states.is_empty(), "reason_code": "OK" if not legal_states.is_empty() else last_reason, "legal_weapon_states": legal_states}


func _weapon_for_state(weapon_state: Dictionary) -> Dictionary:
	var weapon: Dictionary = registry.get_definition("weapons", str(weapon_state.get("definition_id", "")))
	if weapon.is_empty() or weapon.get("mount_type", "") != "Torpedo":
		return weapon
	var mount_index := int(weapon_state.get("mount_index", -1))
	var mount_fire_arcs: Array = weapon.get("mount_fire_arcs", [])
	if mount_index < 0 or mount_index >= mount_fire_arcs.size():
		return weapon
	var mounted_weapon := weapon.duplicate(true)
	mounted_weapon["fire_arcs"] = mount_fire_arcs[mount_index].get("fire_arcs", []).duplicate(true)
	mounted_weapon["active_mount_id"] = str(mount_fire_arcs[mount_index].get("mount_id", ""))
	return mounted_weapon


func _weapon_fire_arcs(weapon: Dictionary) -> Array:
	var configured_arcs: Array = weapon.get("fire_arcs", [])
	if not configured_arcs.is_empty():
		return configured_arcs
	return [{
		"center": float(weapon.get("fire_arc_center", 0.0)),
		"degrees": float(weapon.get("fire_arc_degrees", 360.0)),
	}]


func _angle_in_weapon_fire_arcs(unit_heading: float, target_angle: float, weapon: Dictionary) -> bool:
	for arc in _weapon_fire_arcs(weapon):
		var arc_center := unit_heading + deg_to_rad(float(arc.get("center", 0.0)))
		var angle_delta := absf(wrapf(target_angle - arc_center, -PI, PI))
		if angle_delta <= deg_to_rad(float(arc.get("degrees", 360.0)) * 0.5):
			return true
	return false


func _primary_aim_weapons(weapon_states: Array) -> Array:
	var weapons: Array = []
	for weapon_state in weapon_states:
		if not bool(weapon_state.get("enabled", true)): continue
		if float(weapon_state.get("reload_remaining", 0.0)) > 0.0: continue
		var weapon := _weapon_for_state(weapon_state)
		if not weapon.is_empty():
			weapons.append(weapon)
	return weapons


func _common_weapon_type(weapons: Array) -> String:
	if weapons.is_empty(): return ""
	var weapon_type := str(weapons[0].get("mount_type", ""))
	for weapon in weapons:
		if str(weapon.get("mount_type", "")) != weapon_type: return "Mixed"
	return weapon_type


func _aim_fire_arcs(weapons: Array) -> Array:
	var result: Array = []
	var seen := {}
	for weapon in weapons:
		for arc in _weapon_fire_arcs(weapon):
			var entry := {
				"center": float(arc.get("center", 0.0)),
				"degrees": float(arc.get("degrees", 360.0)),
				"minimum_range": float(weapon.get("minimum_range", 0.0)),
				"range": float(weapon.get("range", 0.0)),
				"spread_degrees": float(weapon.get("spread", 0.0)),
				"weapon_id": str(weapon.get("id", "")),
			}
			var key := "%s|%s|%s|%s|%s" % [entry["center"], entry["degrees"], entry["minimum_range"], entry["range"], entry["spread_degrees"]]
			if seen.has(key):
				continue
			seen[key] = true
			result.append(entry)
	return result


func _aim_full_salvo_fire_arcs(weapons: Array) -> Array:
	var result: Array = []
	for weapon in weapons:
		for arc in weapon.get("full_salvo_fire_arcs", []):
			result.append({
				"center": float(arc.get("center", 0.0)),
				"degrees": float(arc.get("degrees", 360.0)),
				"minimum_range": float(weapon.get("minimum_range", 0.0)),
				"range": float(weapon.get("range", 0.0)),
				"weapon_id": str(weapon.get("id", "")),
			})
	return result


func _aim_impact_radius(weapons: Array) -> float:
	var radius := 42.0
	for weapon in weapons:
		radius = maxf(radius, float(weapon.get("impact_radius", radius)))
	return radius


func _direction_weapon_for_aim(unit: Dictionary, weapons: Array, target_position: Vector2) -> Dictionary:
	if weapons.is_empty(): return {}
	var target_angle := (target_position - (unit["position"] as Vector2)).angle()
	for weapon in weapons:
		if _angle_in_weapon_fire_arcs(float(unit["heading"]), target_angle, weapon):
			return weapon
	var nearest_weapon: Dictionary = weapons[0]
	var nearest_delta := INF
	for weapon in weapons:
		for arc in _weapon_fire_arcs(weapon):
			var arc_center := float(unit["heading"]) + deg_to_rad(float(arc.get("center", 0.0)))
			var angle_delta := absf(wrapf(target_angle - arc_center, -PI, PI))
			if angle_delta < nearest_delta:
				nearest_delta = angle_delta
				nearest_weapon = weapon
	return nearest_weapon


func _target_type(unit: Dictionary) -> String:
	return "Submerged" if str(unit.get("depth_state", "Surface")) == "Submerged" else "Surface"


func _unit_collision_half_extents(unit: Dictionary) -> Vector2:
	return CollisionGeometryService.half_extents(unit.get("stats", unit))


func _ai_observation_for(faction_id: String):
	if not _ai_observations_by_faction.has(faction_id):
		_ai_observations_by_faction[faction_id] = AIObservation.from_battle_state(state, faction_id)
	return _ai_observations_by_faction[faction_id]


func _reserve_ai_damage(source: Dictionary, target: Dictionary, weapon: Dictionary) -> void:
	var source_id := str(source.get("entity_id", ""))
	var target_id := str(target.get("entity_id", ""))
	if source_id.is_empty() or target_id.is_empty(): return
	var travel_time := (source.get("position", Vector2.ZERO) as Vector2).distance_to(target.get("position", Vector2.ZERO)) / maxf(1.0, _automatic_attack_speed(source, weapon))
	_ai_damage_reservations[source_id] = {
		"source_unit_id": source_id,
		"target_unit_id": target_id,
		"expected_damage": _estimated_weapon_volley_damage(source, target, weapon),
		"expires_at": float(state.get("elapsed_time", 0.0)) + clampf(travel_time + 1.0, 1.5, 12.0),
	}
	_emit("AIDamageReserved", _ai_damage_reservations[source_id].duplicate(true))


func _reserved_damage_for_target(target_id: String, excluding_source_id: String = "") -> float:
	var total := 0.0
	for reservation in _ai_damage_reservations.values():
		if str(reservation.get("source_unit_id", "")) == excluding_source_id: continue
		if str(reservation.get("target_unit_id", "")) == target_id:
			total += float(reservation.get("expected_damage", 0.0))
	return total


func _expire_ai_damage_reservations() -> void:
	var now := float(state.get("elapsed_time", 0.0))
	for source_id in _ai_damage_reservations.keys():
		var reservation: Dictionary = _ai_damage_reservations[source_id]
		var target: Dictionary = state.get("units_by_id", {}).get(str(reservation.get("target_unit_id", "")), {})
		if float(reservation.get("expires_at", 0.0)) <= now or target.get("life_state", "") != "Alive":
			_ai_damage_reservations.erase(source_id)


func _is_visible_to(faction_id: String, target_id: String) -> bool:
	return state.get("visible_by_faction", {}).get(faction_id, {}).has(target_id)


func _clamp_to_map(position: Vector2) -> Vector2:
	return Vector2(clampf(position.x, 0.0, float(state["map"].get("width", 1200.0))), clampf(position.y, 0.0, float(state["map"].get("height", 700.0))))


func _inside_map(position: Vector2) -> bool:
	return position.x >= 0.0 and position.y >= 0.0 and position.x <= float(state["map"].get("width", 1200.0)) and position.y <= float(state["map"].get("height", 700.0))


func _movement_tags(unit: Dictionary) -> Array:
	var tags: Array = ["Surface"]
	if str(unit.get("stats", {}).get("ship_class", "")) in ["Destroyer", "LightCruiser"]:
		tags.append("ShallowDraft")
	return tags


func _polygon(raw: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in raw:
		result.append(point if point is Vector2 else Vector2(float(point[0]), float(point[1])))
	return result


func _movement_finished(movement: Dictionary) -> bool:
	var corridor: Array = movement.get("corridor_points", [])
	if not corridor.is_empty(): return int(movement.get("corridor_index", 0)) >= corridor.size()
	var waypoints: Array = movement.get("waypoints", [])
	return waypoints.is_empty() or int(movement.get("waypoint_index", 0)) >= waypoints.size()


func _sorted_unit_ids() -> Array:
	var ids: Array = state.get("units_by_id", {}).keys()
	ids.sort()
	return ids


func _next_entity_id(prefix: String) -> String:
	_entity_sequence += 1
	return "%s.%06d" % [prefix, _entity_sequence]


func _emit(event_type: String, payload: Dictionary = {}) -> void:
	_event_sequence += 1
	var event := {"event_id": "event.%06d" % _event_sequence, "battle_id": state.get("battle_id", ""), "tick_index": state.get("tick_index", 0), "event_type": event_type}
	for key in payload: event[key] = payload[key]
	_event_buffer.append(event)


func _rejection(command_id: String, reason_code: String) -> Dictionary:
	return {"accepted": false, "command_id": command_id, "reason_code": reason_code}


func _assert_invariants() -> void:
	if not OS.is_debug_build(): return
	for unit_id in _sorted_unit_ids():
		var unit: Dictionary = state["units_by_id"][unit_id]
		assert(float(unit["current_hp"]) >= 0.0 and float(unit["current_hp"]) <= float(unit["max_hp"]))
		for weapon_state in unit["weapon_states"]:
			assert(float(weapon_state["reload_remaining"]) >= 0.0)
