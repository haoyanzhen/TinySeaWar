extends RefCounted

const SeededRandomSource = preload("res://scripts/infrastructure/random/seeded_random_source.gd")
const ModifierService = preload("res://scripts/domain/services/modifier_service.gd")
const DamageService = preload("res://scripts/domain/services/damage_service.gd")
const CollisionGeometryService = preload("res://scripts/domain/services/collision_geometry_service.gd")
const BattleRecorder = preload("res://scripts/infrastructure/analytics/battle_recorder.gd")
const TerrainQueryService = preload("res://scripts/domain/services/terrain_query_service.gd")
const TerrainContextService = preload("res://scripts/domain/services/terrain_context_service.gd")
const FacilityService = preload("res://scripts/domain/services/facility_service.gd")
const MinefieldService = preload("res://scripts/domain/services/minefield_service.gd")
const RoutePlanner = preload("res://scripts/application/navigation/route_planner.gd")

const PLAYER_FACTION := "player"
const ENEMY_FACTION := "enemy"
const CONTACT_GHOST_DURATION := 60.0

var registry
var random_source
var recorder := BattleRecorder.new()
var state := {}
var command_queue: Array = []
var delayed_attacks: Array = []
var terrain_query = TerrainQueryService.new()
var terrain_context_service = TerrainContextService.new()
var facility_service = FacilityService.new()
var minefield_service = MinefieldService.new()
var route_planner = RoutePlanner.new()
var navigation_definition: Dictionary = {}
var _event_buffer: Array = []
var _event_sequence := 0
var _entity_sequence := 0


func _init(definition_registry = null) -> void:
	registry = definition_registry


func create_battle(level_id: String, seed_value: int = 1) -> Dictionary:
	if registry == null:
		return {"ok": false, "errors": ["MISSING_REGISTRY"]}
	var level: Dictionary = registry.get_definition("levels", level_id)
	if level.is_empty():
		return {"ok": false, "errors": ["LEVEL_NOT_FOUND"]}
	var validation_errors := _validate_level_runtime(level)
	if not validation_errors.is_empty():
		return {"ok": false, "errors": validation_errors}
	random_source = SeededRandomSource.new(seed_value)
	_event_buffer.clear()
	command_queue.clear()
	delayed_attacks.clear()
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
		"visible_by_faction": {PLAYER_FACTION: {}, ENEMY_FACTION: {}},
		"contacts_by_faction": {PLAYER_FACTION: {}, ENEMY_FACTION: {}},
		"result": {},
	}
	_configure_scene_combat(level)
	_build_fleet("fleet.player", PLAYER_FACTION, level.get("player_fleet", []))
	_build_fleet("fleet.enemy", ENEMY_FACTION, level.get("enemy_fleet", []))
	state["phase"] = "Running"
	recorder.reset(state["battle_id"], seed_value)
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
	state["tick_index"] += 1
	state["elapsed_time"] += delta
	for environment_event in terrain_context_service.advance(delta):
		_emit(str(environment_event.get("event_type", "EnvironmentZoneChanged")), environment_event)
	state["environment_zones"] = terrain_context_service.snapshot()
	state["global_environment"] = terrain_context_service.global_snapshot()
	_update_support_effects(delta)
	_process_commands()
	_update_cooldowns_and_statuses(delta)
	_update_movement(delta)
	_resolve_unit_overlap()
	_update_projectiles(delta)
	_update_projectile_observation()
	_update_detection(delta)
	_update_ai_intents()
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
	_check_victory()
	_check_timeout()
	_assert_invariants()
	recorder.consume(_event_buffer, float(state["elapsed_time"]))
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
			"skill_cooldown": unit["skill_state"].get("cooldown_remaining", 0.0),
			"skill_cooldown_max": unit["skill_state"].get("cooldown_max", 0.0),
		}
	var contacts := {}
	var visible_minefields := {}
	var unit_terrain_contexts := {}
	for contact_id in state["contacts_by_faction"].get(viewer_faction, {}):
		var contact: Dictionary = state["contacts_by_faction"][viewer_faction][contact_id]
		if not bool(contact.get("visible", false)):
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
		"facilities": state.get("facilities_by_id", {}).duplicate(true),
		"minefields": visible_minefields,
		"support_effects": _visible_support_effects(viewer_faction, omniscient),
		"terrain_contexts": unit_terrain_contexts,
		"result": state.get("result", {}).duplicate(true),
	}


func get_statistics() -> Dictionary:
	return recorder.summary.duplicate(true)


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
	var group_launch_remaining := float(unit.get("weapon_group_launch_remaining", {}).get(primary_group_id, 0.0))
	for weapon_state in primary_states:
		var weapon: Dictionary = registry.get_definition("weapons", str(weapon_state["definition_id"]))
		if primary_name == "None": primary_name = str(weapon.get("display_name", weapon["id"]))
		if primary_mount_type.is_empty(): primary_mount_type = str(weapon.get("mount_type", ""))
		primary_reload = minf(primary_reload, float(weapon_state.get("reload_remaining", 0.0)))
		primary_reload_max = maxf(primary_reload_max, float(weapon.get("reload_time", 0.0)))
		primary_range = maxf(primary_range, float(weapon.get("range", 0.0)))
		if float(weapon_state.get("reload_remaining", 0.0)) <= 0.0:
			primary_mounts_ready += 1
			if group_launch_remaining <= 0.0: primary_ready = true
	if primary_states.is_empty():
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
	validation["selected_range"] = float(direction_weapon.get("range", validation["range"]))
	validation["spread_degrees"] = float(direction_weapon.get("spread", 0.0))
	return validation


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
		terrain_query.configure(terrain_definition)
		state["terrain_map"] = terrain_definition.duplicate(true)
	var navigation_id := str(map.get("navigation_definition_id", terrain_definition.get("navigation_definition_id", "")))
	if not navigation_id.is_empty():
		navigation_definition = registry.get_definition("navigation", navigation_id)
	var environment_id := str(map.get("environment_zone_set_id", terrain_definition.get("environment_zone_set_id", "")))
	var environment_set: Dictionary = registry.get_definition("environment_zones", environment_id) if not environment_id.is_empty() else {}
	terrain_context_service.configure(terrain_query, environment_set, registry.all("environment_zones"), str(map.get("ocean_palette", "day_clear")))
	state["environment_zones"] = terrain_context_service.snapshot()
	state["global_environment"] = terrain_context_service.global_snapshot()
	var facility_layout_id := str(map.get("facility_layout_id", terrain_definition.get("facility_layout_id", "")))
	var facility_layout: Dictionary = registry.get_definition("facilities", facility_layout_id) if not facility_layout_id.is_empty() else {}
	facility_service.configure(facility_layout, terrain_definition.get("facility_anchors", []), registry.all("facilities"))
	state["facilities_by_id"] = facility_service.snapshot()
	minefield_service.configure(registry.all("facilities"), terrain_id)
	state["minefields_by_id"] = minefield_service.snapshot()


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


func _build_unit(member: Dictionary, ship: Dictionary, fleet_id: String, faction_id: String, operation_slot: int) -> Dictionary:
	var position_data: Array = member.get("position", [0.0, 0.0])
	var spawn_position := Vector2(float(position_data[0]), float(position_data[1]))
	var weapon_states: Array = []
	for weapon_id in ship.get("weapon_mounts", []):
		var weapon: Dictionary = registry.get_definition("weapons", str(weapon_id))
		var mount_fire_arcs: Array = weapon.get("mount_fire_arcs", [])
		if weapon.get("mount_type", "") == "Torpedo" and weapon.get("control_mode", "") == "ManualPrimary" and not mount_fire_arcs.is_empty():
			for mount_index in range(mount_fire_arcs.size()):
				weapon_states.append({
					"instance_id": "%s.%s.%s" % [member["entity_id"], weapon_id, mount_fire_arcs[mount_index].get("mount_id", "mount_%s" % [mount_index + 1])],
					"definition_id": weapon_id,
					"mount_index": mount_index,
					"mount_id": str(mount_fire_arcs[mount_index].get("mount_id", "mount_%s" % [mount_index + 1])),
					"reload_remaining": 0.0,
					"enabled": true,
				})
		else:
			weapon_states.append({"instance_id": "%s.%s" % [member["entity_id"], weapon_id], "definition_id": weapon_id, "mount_index": -1, "mount_id": "", "reload_remaining": 0.0, "enabled": true})
	var skill: Dictionary = registry.get_definition("skills", str(ship.get("skill_id", "")))
	return {
		"entity_id": str(member["entity_id"]),
		"definition_id": str(ship["id"]),
		"display_name": str(ship.get("display_name", ship["id"])),
		"fleet_id": fleet_id,
		"faction_id": faction_id,
		"operation_slot": operation_slot,
		"is_flagship": bool(member.get("is_flagship", false)),
		"life_state": "Alive",
		"current_hp": float(ship["max_hp"]),
		"max_hp": float(ship["max_hp"]),
		"stats": ship.duplicate(true),
		"position": spawn_position,
		"heading": deg_to_rad(float(member.get("heading", 0.0))),
		"current_speed": 0.0,
		"movement_state": {"mode": "AutoNavigate", "target_position": spawn_position},
		"targeting_state": {"mode": "Automatic", "focused_target_id": "", "current_target_id": ""},
		"weapon_states": weapon_states,
		"weapon_group_launch_remaining": {},
		"skill_state": {"definition_id": ship.get("skill_id", ""), "cooldown_remaining": float(skill.get("cooldown", 0.0)), "cooldown_max": float(skill.get("cooldown", 0.0))},
		"ammo_state": _build_ammo_state(ship),
		"status_effects": [],
		"firing_reveal_remaining": 0.0,
	}


func _build_ammo_state(ship: Dictionary) -> Dictionary:
	var ammo_group_id := str(ship.get("ammo_selection_group_id", ""))
	if ammo_group_id.is_empty():
		return {}
	var ammo_options := _ammo_options_for_ship(ship, ammo_group_id)
	var selected_ammo := str(ship.get("initial_ammo_type", ""))
	if selected_ammo.is_empty() or not selected_ammo in ammo_options:
		selected_ammo = ammo_options[0] if not ammo_options.is_empty() else ""
	return {ammo_group_id: selected_ammo}


func _process_commands() -> void:
	command_queue.sort_custom(func(a, b):
		var tick_a := int(a.get("issued_at_tick", 0))
		var tick_b := int(b.get("issued_at_tick", 0))
		return tick_a < tick_b if tick_a != tick_b else str(a.get("command_id", "")) < str(b.get("command_id", "")))
	var pending := command_queue
	command_queue = []
	for command in pending:
		var result := _apply_command(command)
		if not result.get("accepted", false):
			_emit("CommandRejected", {"command_id": command.get("command_id", ""), "reason_code": result.get("reason_code", "UNKNOWN")})


func _apply_command(command: Dictionary) -> Dictionary:
	if state["phase"] != "Running": return _rejection(command.get("command_id", ""), "BATTLE_NOT_RUNNING")
	var unit_id := str(command.get("unit_id", ""))
	var unit: Dictionary = state["units_by_id"].get(unit_id, {})
	if unit.is_empty(): return _rejection(command.get("command_id", ""), "UNIT_NOT_FOUND")
	if unit["life_state"] != "Alive": return _rejection(command.get("command_id", ""), "UNIT_SUNK")
	var issuer_faction := str(command.get("issuer_id", PLAYER_FACTION))
	if unit["faction_id"] != issuer_faction: return _rejection(command.get("command_id", ""), "UNIT_NOT_CONTROLLABLE")
	match command.get("command_type", ""):
		"MoveUnits":
			var target_position = command.get("target_position")
			if typeof(target_position) != TYPE_VECTOR2: return _rejection(command.get("command_id", ""), "INVALID_TARGET_TYPE")
			if not _inside_map(target_position): return _rejection(command.get("command_id", ""), "TARGET_POSITION_ON_LAND")
			var route := route_planner.plan_path(terrain_query, navigation_definition, unit["position"], target_position, float(unit["stats"].get("collision_radius", 20.0)), _movement_tags(unit), terrain_context_service)
			if not bool(route.get("ok", false)):
				return _rejection(command.get("command_id", ""), str(route.get("reason_code", "NO_NAVIGATION_PATH")))
			var environment_route := _validate_environment_route(unit["position"], route.get("waypoints", []))
			if not bool(environment_route.get("allowed", false)):
				return _rejection(command.get("command_id", ""), str(environment_route.get("reason_code", "TIDE_ACCESS_RESTRICTED")))
			var movement_mode := "AutoNavigate" if command.get("issuer_type", "Player") == "AI" else "PlayerMoveOrder"
			unit["movement_state"] = {"mode": movement_mode, "target_position": target_position, "waypoints": route.get("waypoints", [target_position]), "waypoint_index": 0}
			_emit("MoveOrderAccepted", {"unit_id": unit_id, "target_position": unit["movement_state"]["target_position"]})
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
			return _cast_skill(unit, command.get("target_ref", {}), command.get("command_id", ""))
		"SwitchAmmo":
			return _switch_ammo(unit, command.get("command_id", ""))
		"FirePrimaryWeapon":
			var target_position = command.get("target_position")
			if typeof(target_position) != TYPE_VECTOR2: return _rejection(command.get("command_id", ""), "INVALID_TARGET_TYPE")
			return _fire_primary_weapon(unit, target_position, command.get("command_id", ""))
		"StartFacilityInteraction":
			var facility_result := facility_service.start_interaction(str(command.get("facility_id", "")), unit, str(command.get("interaction_type", "Activate")))
			if bool(facility_result.get("accepted", false)) and facility_result.has("event"):
				var facility_event: Dictionary = facility_result["event"]
				_emit(str(facility_event.get("event_type", "FacilityInteractionStarted")), facility_event)
			return facility_result
		"CancelFacilityInteraction":
			var cancel_result := facility_service.cancel_interaction(str(command.get("facility_id", "")), unit_id)
			if bool(cancel_result.get("accepted", false)) and cancel_result.has("event"):
				var cancel_event: Dictionary = cancel_result["event"]
				_emit(str(cancel_event.get("event_type", "FacilityInteractionInterrupted")), cancel_event)
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
		_:
			return _rejection(command.get("command_id", ""), "UNKNOWN_COMMAND")


func _validate_command_structure(command: Dictionary) -> Dictionary:
	for field in ["command_id", "command_type", "issuer_id"]:
		if not command.has(field): return _rejection(command.get("command_id", ""), "INVALID_COMMAND_STRUCTURE")
	return {}


func _update_cooldowns_and_statuses(delta: float) -> void:
	for unit_id in _sorted_unit_ids():
		var unit: Dictionary = state["units_by_id"][unit_id]
		if unit["life_state"] != "Alive": continue
		unit["firing_reveal_remaining"] = maxf(0.0, float(unit["firing_reveal_remaining"]) - delta)
		unit["skill_state"]["cooldown_remaining"] = maxf(0.0, float(unit["skill_state"]["cooldown_remaining"]) - delta)
		for weapon_state in unit["weapon_states"]:
			weapon_state["reload_remaining"] = maxf(0.0, float(weapon_state["reload_remaining"]) - delta)
		for group_id in unit.get("weapon_group_launch_remaining", {}).keys():
			unit["weapon_group_launch_remaining"][group_id] = maxf(0.0, float(unit["weapon_group_launch_remaining"][group_id]) - delta)
		for index in range(unit["status_effects"].size() - 1, -1, -1):
			var effect: Dictionary = unit["status_effects"][index]
			effect["remaining"] = float(effect.get("remaining", 0.0)) - delta
			if float(effect["remaining"]) <= 0.0:
				unit["status_effects"].remove_at(index)
				_emit("StatusExpired", {"target_unit_id": unit_id, "status_id": effect.get("status_id", "")})


func _update_movement(delta: float) -> void:
	for unit_id in _sorted_unit_ids():
		var unit: Dictionary = state["units_by_id"][unit_id]
		if unit["life_state"] != "Alive": continue
		var movement: Dictionary = unit["movement_state"]
		var target_position: Vector2 = _current_movement_target(movement, unit["position"])
		var distance := (unit["position"] as Vector2).distance_to(target_position)
		var context := terrain_context_service.context_at(unit["position"])
		var max_speed := ModifierService.calculate(float(unit["stats"]["speed"]), unit["status_effects"], "Speed") * float(context.get("movement_speed_multiplier", 1.0))
		var turn_speed := deg_to_rad(ModifierService.calculate(float(unit["stats"]["turn_speed"]), unit["status_effects"], "TurnSpeed"))
		if distance <= 8.0:
			_advance_movement_waypoint(movement)
			target_position = _current_movement_target(movement, unit["position"])
			distance = (unit["position"] as Vector2).distance_to(target_position)
			unit["current_speed"] = move_toward(float(unit["current_speed"]), 0.0, max_speed * delta * 2.0)
			if _movement_finished(movement) and movement["mode"] == "PlayerMoveOrder": movement["mode"] = "HoldPosition"
		else:
			var desired_heading := (target_position - (unit["position"] as Vector2)).angle()
			unit["heading"] = rotate_toward(float(unit["heading"]), desired_heading, turn_speed * delta)
			unit["current_speed"] = move_toward(float(unit["current_speed"]), max_speed, max_speed * delta)
		var movement_start: Vector2 = unit["position"]
		var desired_motion := Vector2.RIGHT.rotated(float(unit["heading"])) * float(unit["current_speed"]) * delta + (context.get("current_vector", Vector2.ZERO) as Vector2) * delta
		var environment_access := terrain_context_service.movement_segment_access(movement_start, movement_start + desired_motion)
		if not bool(environment_access.get("allowed", true)):
			desired_motion = Vector2.ZERO
			unit["current_speed"] = 0.0
			movement["mode"] = "HoldPosition"
			movement["target_position"] = movement_start
			_emit("UnitTideAccessRestricted", {"unit_id": unit_id, "zone_id": environment_access.get("zone_id", ""), "position": movement_start})
		if terrain_query.is_configured():
			var motion_result := terrain_query.resolve_circle_motion(unit["position"], desired_motion, float(unit["stats"].get("collision_radius", 20.0)), _movement_tags(unit))
			unit["position"] = motion_result["position"]
			if bool(motion_result.get("collided", false)):
				unit["current_speed"] = minf(float(unit["current_speed"]), max_speed * 0.25)
				var hit: Dictionary = motion_result.get("hit", {})
				_emit("UnitTerrainCollision", {"unit_id": unit_id, "obstacle_id": hit.get("obstacle_id", ""), "position": hit.get("position", unit["position"]), "normal": hit.get("normal", Vector2.ZERO)})
		else:
			unit["position"] = _clamp_to_map((unit["position"] as Vector2) + desired_motion)
		var mine_trigger := minefield_service.resolve_unit_motion(unit, movement_start, unit["position"])
		if bool(mine_trigger.get("triggered", false)):
			_apply_mine_trigger(unit, mine_trigger)


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
			var correction := delta_position.normalized() * (minimum_distance - delta_position.length()) * 0.5
			var first_position: Vector2 = _clamp_to_map(first["position"] - correction)
			var second_position: Vector2 = _clamp_to_map(second["position"] + correction)
			if not terrain_query.is_configured() or terrain_query.can_occupy_circle(first_position, float(first["stats"]["collision_radius"]), _movement_tags(first)):
				first["position"] = first_position
			if not terrain_query.is_configured() or terrain_query.can_occupy_circle(second_position, float(second["stats"]["collision_radius"]), _movement_tags(second)):
				second["position"] = second_position


func _update_detection(delta: float = 0.1) -> void:
	for observer_faction in [PLAYER_FACTION, ENEMY_FACTION]:
		var previous_visible: Dictionary = state["visible_by_faction"][observer_faction]
		var next_visible := {}
		var newly_lost := {}
		for target_id in _sorted_unit_ids():
			var target: Dictionary = state["units_by_id"][target_id]
			if target["life_state"] != "Alive" or target["faction_id"] == observer_faction: continue
			if _fleet_detects(observer_faction, target): next_visible[target_id] = true
		state["visible_by_faction"][observer_faction] = next_visible
		for target_id in next_visible:
			var target: Dictionary = state["units_by_id"][target_id]
			state["contacts_by_faction"][observer_faction][target_id] = {"unit_id": target_id, "visible": true, "last_known_position": target["position"], "ghost_remaining": 0.0}
			if not previous_visible.has(target_id): _emit("ContactAcquired", {"observer_faction": observer_faction, "target_unit_id": target_id, "position": target["position"]})
		for target_id in previous_visible:
			if next_visible.has(target_id): continue
			var target: Dictionary = state["units_by_id"].get(target_id, {})
			var last_position: Vector2 = target.get("position", Vector2.ZERO)
			state["contacts_by_faction"][observer_faction][target_id] = {"unit_id": target_id, "visible": false, "last_known_position": last_position, "ghost_remaining": CONTACT_GHOST_DURATION}
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
				var detection_distance := ModifierService.calculate(base_distance, observer.get("status_effects", []), "TorpedoDetectionDistance", "Torpedo")
				if (observer.get("position", Vector2.ZERO) as Vector2).distance_to(projectile.get("position", Vector2.ZERO)) > detection_distance:
					continue
				known[projectile_id] = true
				_emit("ProjectileDetected", {"observer_faction": observer_faction, "observer_unit_id": observer_id, "projectile_id": projectile_id, "position": projectile.get("position", Vector2.ZERO)})
				break


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
	var concealment := ModifierService.calculate(float(target["stats"]["concealment_distance"]), target["status_effects"], "ConcealmentDistance")
	if float(target["firing_reveal_remaining"]) > 0.0: concealment *= float(target["stats"]["fire_concealment_multiplier"])
	for observer_id in _sorted_unit_ids():
		var observer: Dictionary = state["units_by_id"][observer_id]
		if observer["faction_id"] != observer_faction or observer["life_state"] != "Alive": continue
		var detection_range := ModifierService.calculate(float(observer["stats"]["detection_range"]), observer["status_effects"], "DetectionRange")
		var observer_context := terrain_context_service.context_at(observer["position"])
		var target_context := terrain_context_service.context_at(target["position"])
		detection_range *= minf(float(observer_context.get("optical_visibility_multiplier", 1.0)), float(target_context.get("optical_visibility_multiplier", 1.0)))
		var distance := (observer["position"] as Vector2).distance_to(target["position"] as Vector2)
		if distance <= detection_range and distance <= concealment and terrain_query.has_surface_line_of_sight(observer["position"], target["position"]): return true
	for source in facility_service.observation_sources(observer_faction):
		var source_position: Vector2 = source.get("position", Vector2.ZERO)
		var source_context := terrain_context_service.context_at(source_position)
		var target_context := terrain_context_service.context_at(target["position"])
		var detection_range := float(source.get("detection_range", 0.0)) * minf(float(source_context.get("optical_visibility_multiplier", 1.0)), float(target_context.get("optical_visibility_multiplier", 1.0)))
		var distance := source_position.distance_to(target["position"])
		if distance <= detection_range and distance <= concealment and terrain_query.has_surface_line_of_sight(source_position, target["position"]): return true
	for effect in state.get("support_effects_by_id", {}).values():
		if str(effect.get("effect_type", "")) != "Reconnaissance" or str(effect.get("faction_id", "")) != observer_faction: continue
		if (effect.get("position", Vector2.ZERO) as Vector2).distance_to(target["position"]) <= float(effect.get("radius", 0.0)): return true
	return false


func _update_ai_intents() -> void:
	var map_center := Vector2(float(state["map"].get("width", 1200.0)) * 0.5, float(state["map"].get("height", 700.0)) * 0.5)
	if int(state.get("tick_index", 0)) % 10 == 0:
		_update_ai_support_intents()
	for unit_id in _sorted_unit_ids():
		var unit: Dictionary = state["units_by_id"][unit_id]
		if unit["life_state"] != "Alive" or unit["movement_state"]["mode"] == "PlayerMoveOrder": continue
		var target := _select_target(unit)
		if unit.get("faction_id", "") == ENEMY_FACTION:
			var facility_plan := _ai_facility_plan(unit, target.is_empty())
			if not facility_plan.is_empty():
				if facility_plan.has("interaction_type"):
					_queue_ai_facility_interaction(unit, str(facility_plan["facility_id"]), str(facility_plan["interaction_type"]))
				else:
					_queue_ai_move(unit, facility_plan["target_position"])
				continue
		if target.is_empty():
			var context := terrain_context_service.context_at(unit["position"])
			var lee_center := terrain_context_service.zone_center_for_effect("environment.effect.lee_water")
			if int(context.get("sea_state", 0)) >= 4 and lee_center != Vector2.ZERO:
				_queue_ai_move(unit, lee_center)
				continue
			var lane_offset := float(abs(unit_id.hash()) % 180) - 90.0
			_queue_ai_move(unit, map_center + Vector2(0.0, lane_offset))
			continue
		var preferred_range := _preferred_range(unit)
		var target_position: Vector2 = target["position"]
		var distance := (unit["position"] as Vector2).distance_to(target_position)
		if distance > preferred_range:
			_queue_ai_move(unit, target_position)
		elif distance < preferred_range * 0.55:
			_queue_ai_move(unit, _clamp_to_map(unit["position"] + (unit["position"] - target_position).normalized() * 140.0))
		else:
			_queue_ai_move(unit, unit["position"])


func _update_auto_skills() -> void:
	for unit_id in _sorted_unit_ids():
		var unit: Dictionary = state["units_by_id"][unit_id]
		if unit.get("faction_id", "") == PLAYER_FACTION: continue
		if unit["life_state"] != "Alive" or float(unit["skill_state"]["cooldown_remaining"]) > 0.0: continue
		var skill: Dictionary = registry.get_definition("skills", str(unit["skill_state"]["definition_id"]))
		if skill.is_empty(): continue
		var target_ref := {}
		match skill.get("target_type", "Self"):
			"Enemy":
				var target := _select_target(unit)
				if target.is_empty(): continue
				target_ref = {"type": "Entity", "entity_id": target["entity_id"]}
			"Area":
				var area_target := _select_target(unit)
				if area_target.is_empty(): continue
				target_ref = {"type": "Position", "position": area_target["position"]}
			_: target_ref = {"type": "Self"}
		command_queue.append({
			"command_id": "ai.skill.%s.%s" % [state["tick_index"] + 1, unit_id],
			"command_type": "CastSkill",
			"issued_at_tick": state["tick_index"] + 1,
			"issuer_type": "AI",
			"issuer_id": unit["faction_id"],
			"unit_id": unit_id,
			"target_ref": target_ref,
		})


func _queue_ai_move(unit: Dictionary, target_position: Vector2) -> void:
	target_position = minefield_service.avoidance_waypoint(str(unit.get("faction_id", "")), unit["position"], target_position)
	if (unit["movement_state"].get("target_position", unit["position"]) as Vector2).distance_to(target_position) < 8.0: return
	command_queue.append({
		"command_id": "ai.move.%s.%s" % [state["tick_index"] + 1, unit["entity_id"]],
		"command_type": "MoveUnits",
		"issued_at_tick": state["tick_index"] + 1,
		"issuer_type": "AI",
		"issuer_id": unit["faction_id"],
		"unit_id": unit["entity_id"],
		"target_position": _clamp_to_map(target_position),
	})


func _ai_facility_plan(unit: Dictionary, allow_capture: bool) -> Dictionary:
	var facilities: Dictionary = facility_service.snapshot()
	var candidates: Array = []
	var hp_ratio := float(unit.get("current_hp", 0.0)) / maxf(1.0, float(unit.get("max_hp", 1.0)))
	for facility_id in facilities:
		var facility: Dictionary = facilities[facility_id]
		if str(facility.get("life_state", "")) != "Alive": continue
		var definition := facility_service.definition_for(str(facility_id))
		var interaction_type := ""
		var priority := 0.0
		if hp_ratio < 0.55 and facility_service.is_operational(str(facility_id)) and facility.get("faction_id") == unit.get("faction_id") and str(definition.get("service_profile", {}).get("service_type", "")) == "Repair":
			interaction_type = "Service"
			priority = 3000.0
		elif allow_capture and "Ownable" in definition.get("capabilities", []) and "Seize" in definition.get("interaction_types", []) and facility.get("faction_id") != unit.get("faction_id"):
			interaction_type = "Seize"
			priority = 1600.0 if "ObservationSource" in definition.get("capabilities", []) or "HazardController" in definition.get("capabilities", []) else 1200.0
		elif allow_capture and "Activate" in definition.get("interaction_types", []) and facility.get("faction_id") in ["neutral", unit.get("faction_id")] and facility.get("operation_state") == "Dormant":
			interaction_type = "Activate"
			priority = 1000.0
		if interaction_type.is_empty(): continue
		var interaction: Dictionary = facility.get("interaction", {})
		if not interaction.is_empty() and str(interaction.get("unit_id", "")) != str(unit.get("entity_id", "")): continue
		var center := facility_service.interaction_center(str(facility_id))
		var distance := (unit["position"] as Vector2).distance_to(center)
		candidates.append({"facility_id": str(facility_id), "interaction_type": interaction_type, "target_position": center, "score": priority - distance})
	if candidates.is_empty(): return {}
	candidates.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]) if not is_equal_approx(float(a["score"]), float(b["score"])) else str(a["facility_id"]) < str(b["facility_id"]))
	var selected: Dictionary = candidates[0]
	var selected_facility: Dictionary = facilities[selected["facility_id"]]
	if not selected_facility.get("interaction", {}).is_empty(): return {"target_position": unit["position"]}
	if Geometry2D.is_point_in_polygon(unit["position"], _polygon(selected_facility.get("interaction_water_polygon", []))):
		return {"facility_id": selected["facility_id"], "interaction_type": selected["interaction_type"]}
	return {"target_position": selected["target_position"]}


func _queue_ai_facility_interaction(unit: Dictionary, facility_id: String, interaction_type: String) -> void:
	command_queue.append({
		"command_id": "ai.facility.%s.%s" % [state["tick_index"] + 1, unit["entity_id"]],
		"command_type": "StartFacilityInteraction",
		"issued_at_tick": state["tick_index"] + 1,
		"issuer_type": "AI",
		"issuer_id": unit["faction_id"],
		"unit_id": unit["entity_id"],
		"facility_id": facility_id,
		"interaction_type": interaction_type,
	})


func _update_ai_support_intents() -> void:
	var target: Dictionary = {}
	var visible_target_ids: Array = state.get("visible_by_faction", {}).get(ENEMY_FACTION, {}).keys()
	visible_target_ids.sort()
	for target_id in visible_target_ids:
		var candidate: Dictionary = state["units_by_id"].get(target_id, {})
		if candidate.get("life_state", "") == "Alive":
			target = candidate
			break
	if target.is_empty(): return
	var requester: Dictionary = {}
	for unit_id in _sorted_unit_ids():
		var unit: Dictionary = state["units_by_id"][unit_id]
		if unit.get("faction_id", "") == ENEMY_FACTION and unit.get("life_state", "") == "Alive": requester = unit; break
	if requester.is_empty(): return
	var facilities := facility_service.snapshot()
	var facility_ids: Array = facilities.keys()
	facility_ids.sort()
	for facility_id_key in facility_ids:
		var facility: Dictionary = facilities[facility_id_key]
		var facility_id := str(facility.get("facility_id", ""))
		if facility.get("faction_id", "") != ENEMY_FACTION or not facility_service.is_operational(facility_id): continue
		var definition := facility_service.definition_for(facility_id)
		if "SupportMissionProvider" not in definition.get("capabilities", []): continue
		for mission_id in ["support_mission.airstrike", "support_mission.fighter_patrol", "support_mission.air_recon"]:
			if mission_id not in definition.get("support_mission_ids", []) or int(facility.get("mission_charges_remaining", {}).get(mission_id, 0)) <= 0: continue
			command_queue.append({"command_id":"ai.support.%s.%s" % [state["tick_index"] + 1, mission_id], "command_type":"RequestSupportMission", "issued_at_tick":state["tick_index"] + 1, "issuer_type":"AI", "issuer_id":ENEMY_FACTION, "unit_id":requester["entity_id"], "facility_id":facility_id, "mission_definition_id":mission_id, "target_position":target["position"]})
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
	var recipients := _skill_recipients(unit, skill, target_position)
	for effect in skill.get("effects", []):
		for recipient in recipients.get(effect.get("scope", "Self"), []): _apply_status(recipient, effect, float(skill.get("duration", 0.0)), skill["id"], unit["entity_id"])
	unit["skill_state"]["cooldown_remaining"] = float(skill["cooldown"])
	_emit("SkillCast", {"unit_id": unit["entity_id"], "skill_id": skill["id"], "target_ref": target_ref.duplicate(true)})
	return {"accepted": true}


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
	var radius := float(skill.get("cast_range", 0.0))
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


func _update_weapons() -> void:
	for unit_id in _sorted_unit_ids():
		var unit: Dictionary = state["units_by_id"][unit_id]
		if unit["life_state"] != "Alive": continue
		var target := _select_target(unit)
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
			_fire_facility_weapon(facility, target, weapon)


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
	var shot_count := int(weapon.get("mount_count", 1)) * int(weapon.get("shots_per_mount", 1))
	var impact_positions: Array = []
	for shot_index in range(shot_count):
		var spread_offset := deg_to_rad(float(weapon.get("spread", 0.0))) * (float(shot_index) / float(maxi(1, shot_count - 1)) - 0.5) if shot_count > 1 else 0.0
		var intended_impact := _salvo_impact_position(origin, target_position, spread_offset, weapon)
		var terrain_hit := _terrain_hit_for_attack(origin, intended_impact, str(facility.get("faction_id", "")))
		var resolved_impact: Vector2 = terrain_hit.get("position", intended_impact) if bool(terrain_hit.get("hit", false)) else intended_impact
		impact_positions.append(resolved_impact)
		var travel_seconds := origin.distance_to(resolved_impact) / maxf(1.0, float(weapon.get("projectile_speed", 1.0)))
		delayed_attacks.append({"attack_id":_next_entity_id("facility_attack"), "source_unit_id":"", "source_facility_id":facility["facility_id"], "source_weapon_id":weapon["id"], "target_unit_id":"", "aimed_target_unit_id":target["entity_id"], "target_position":resolved_impact, "intended_impact_position":intended_impact, "resolved_impact_position":resolved_impact, "terrain_obstacle_id":terrain_hit.get("obstacle_id", ""), "blocked_by_terrain":bool(terrain_hit.get("hit", false)), "impact_radius":float(weapon.get("impact_radius", 40.0)), "origin":origin, "resolve_at_time":float(state["elapsed_time"]) + travel_seconds, "accuracy_modifier":_environment_accuracy_modifier(str(facility.get("faction_id", "")), origin, intended_impact, "Gun")})
	facility_service.mark_weapon_fired(str(facility["facility_id"]), str(weapon["id"]), float(weapon.get("reload_time", 1.0)))
	_emit("FacilityWeaponFired", {"facility_id":facility["facility_id"], "weapon_id":weapon["id"], "target_unit_id":target["entity_id"], "target_position":target_position, "impact_positions":impact_positions, "shot_count":shot_count})


func _can_fire(unit: Dictionary, target: Dictionary, weapon: Dictionary) -> bool:
	if target["life_state"] != "Alive" or not _is_visible_to(unit["faction_id"], target["entity_id"]): return false
	if not _target_type(target) in weapon.get("target_types", []): return false
	var distance := (unit["position"] as Vector2).distance_to(target["position"] as Vector2)
	if distance < float(weapon.get("minimum_range", 0.0)) or distance > float(weapon.get("range", 0.0)): return false
	var target_angle := ((target["position"] as Vector2) - (unit["position"] as Vector2)).angle()
	return _angle_in_weapon_fire_arcs(float(unit["heading"]), target_angle, weapon)


func _can_fire_at_position(unit: Dictionary, target_position: Vector2, weapon: Dictionary) -> Dictionary:
	var distance := (unit["position"] as Vector2).distance_to(target_position)
	if distance < float(weapon.get("minimum_range", 0.0)):
		return {"legal": false, "reason_code": "TARGET_TOO_CLOSE"}
	if distance > float(weapon.get("range", 0.0)):
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
		return maxf(1.0, ModifierService.calculate(float(projectile.get("speed", weapon.get("projectile_speed", 1.0))), unit.get("status_effects", []), "ProjectileSpeed", "Torpedo"))
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
	var extra_shots := int(round(ModifierService.sum_modifier(unit["status_effects"], "ExtraShots", category)))
	var shot_count := (int(weapon["shots_per_mount"]) if category == "Torpedo" else int(weapon["mount_count"]) * int(weapon["shots_per_mount"])) + extra_shots
	_set_weapon_reload(unit, weapon_state, weapon)
	_start_mount_launch_interval(unit, weapon)
	_mark_unit_fired(unit)
	var aim_position: Vector2 = aim_solution.get("position", target["position"])
	var base_heading := (aim_position - (unit["position"] as Vector2)).angle()
	var torpedo_error_profile := _torpedo_error_profile(unit, weapon, shot_count)
	var impact_positions: Array = []
	for shot_index in range(shot_count):
		var spread_offset := 0.0
		if shot_count > 1: spread_offset = deg_to_rad(float(weapon.get("spread", 0.0))) * (float(shot_index) / float(shot_count - 1) - 0.5)
		var attack_id := _next_entity_id("attack")
		if category == "Torpedo":
			var angular_error: float = random_source.randfn(0.0, float(torpedo_error_profile["sigma_radians"]))
			_spawn_projectile(unit, weapon, attack_id, base_heading + spread_offset + angular_error, str(weapon_state.get("mount_id", "")), angular_error, float(torpedo_error_profile["sigma_radians"]), float(torpedo_error_profile["environment_multiplier"]))
		else:
			var intended_impact := _salvo_impact_position(unit["position"], aim_position, spread_offset, weapon)
			var terrain_hit := _terrain_hit_for_attack(unit["position"], intended_impact, unit["faction_id"]) if category == "Gun" else {"hit": false}
			var resolved_impact: Vector2 = terrain_hit.get("position", intended_impact) if bool(terrain_hit.get("hit", false)) else intended_impact
			impact_positions.append(resolved_impact)
			var travel_seconds := (unit["position"] as Vector2).distance_to(resolved_impact) / maxf(1.0, float(weapon.get("projectile_speed", 1.0)))
			if category == "Aviation": travel_seconds *= _aviation_delay_multiplier(unit["position"], intended_impact)
			delayed_attacks.append({"attack_id": attack_id, "source_unit_id": unit["entity_id"], "source_weapon_id": weapon["id"], "target_unit_id": "", "aimed_target_unit_id": target["entity_id"], "target_position": resolved_impact, "intended_impact_position": intended_impact, "resolved_impact_position": resolved_impact, "terrain_obstacle_id": terrain_hit.get("obstacle_id", ""), "blocked_by_terrain": bool(terrain_hit.get("hit", false)), "impact_radius": float(weapon.get("impact_radius", 40.0)), "origin": unit["position"], "resolve_at_time": float(state["elapsed_time"]) + travel_seconds, "accuracy_modifier": _environment_accuracy_modifier(unit["faction_id"], unit["position"], intended_impact, category)})
	_emit("WeaponFired", {"unit_id": unit["entity_id"], "weapon_id": weapon["id"], "mount_id": weapon_state.get("mount_id", ""), "target_unit_id": target["entity_id"], "target_position": aim_position, "impact_positions": impact_positions, "shot_count": shot_count})
	if extra_shots > 0: _consume_effect(unit, "ExtraShots", category)


func _fire_weapon_at_position(unit: Dictionary, target_position: Vector2, weapon_state: Dictionary, weapon: Dictionary, manual: bool) -> void:
	var category := str(weapon["mount_type"])
	var extra_shots := int(round(ModifierService.sum_modifier(unit["status_effects"], "ExtraShots", category)))
	var shot_count := (int(weapon["shots_per_mount"]) if category == "Torpedo" else int(weapon["mount_count"]) * int(weapon["shots_per_mount"])) + extra_shots
	_set_weapon_reload(unit, weapon_state, weapon)
	_start_mount_launch_interval(unit, weapon)
	_mark_unit_fired(unit)
	var base_heading := (target_position - (unit["position"] as Vector2)).angle()
	var torpedo_error_profile := _torpedo_error_profile(unit, weapon, shot_count)
	var impact_positions: Array = []
	for shot_index in range(shot_count):
		var spread_offset := 0.0
		if shot_count > 1: spread_offset = deg_to_rad(float(weapon.get("spread", 0.0))) * (float(shot_index) / float(shot_count - 1) - 0.5)
		var attack_id := _next_entity_id("attack")
		if category == "Torpedo":
			var angular_error: float = random_source.randfn(0.0, float(torpedo_error_profile["sigma_radians"]))
			_spawn_projectile(unit, weapon, attack_id, base_heading + spread_offset + angular_error, str(weapon_state.get("mount_id", "")), angular_error, float(torpedo_error_profile["sigma_radians"]), float(torpedo_error_profile["environment_multiplier"]))
		else:
			var intended_impact := _salvo_impact_position(unit["position"], target_position, spread_offset, weapon)
			var terrain_hit := _terrain_hit_for_attack(unit["position"], intended_impact, unit["faction_id"]) if category == "Gun" else {"hit": false}
			var resolved_impact: Vector2 = terrain_hit.get("position", intended_impact) if bool(terrain_hit.get("hit", false)) else intended_impact
			impact_positions.append(resolved_impact)
			var travel_seconds := (unit["position"] as Vector2).distance_to(resolved_impact) / maxf(1.0, float(weapon.get("projectile_speed", 1.0)))
			if category == "Aviation": travel_seconds *= _aviation_delay_multiplier(unit["position"], intended_impact)
			delayed_attacks.append({"attack_id": attack_id, "source_unit_id": unit["entity_id"], "source_weapon_id": weapon["id"], "target_unit_id": "", "target_position": resolved_impact, "intended_impact_position": intended_impact, "resolved_impact_position": resolved_impact, "terrain_obstacle_id": terrain_hit.get("obstacle_id", ""), "blocked_by_terrain": bool(terrain_hit.get("hit", false)), "impact_radius": float(weapon.get("impact_radius", 40.0)), "origin": unit["position"], "resolve_at_time": float(state["elapsed_time"]) + travel_seconds, "accuracy_modifier": _environment_accuracy_modifier(unit["faction_id"], unit["position"], intended_impact, category)})
	_emit("WeaponFired", {"unit_id": unit["entity_id"], "weapon_id": weapon["id"], "mount_id": weapon_state.get("mount_id", ""), "target_position": target_position, "impact_positions": impact_positions, "shot_count": shot_count, "manual": manual})
	if extra_shots > 0: _consume_effect(unit, "ExtraShots", category)


func _salvo_impact_position(origin: Vector2, target_position: Vector2, spread_offset: float, weapon: Dictionary) -> Vector2:
	var base_heading := (target_position - origin).angle()
	var impact_offset := Vector2.RIGHT.rotated(base_heading + PI * 0.5) * spread_offset * float(weapon.get("impact_radius", 40.0))
	return _clamp_to_map(target_position + impact_offset)


func _mark_unit_fired(unit: Dictionary) -> void:
	unit["firing_reveal_remaining"] = maxf(float(unit["firing_reveal_remaining"]), _firing_reveal_duration(unit))


func _firing_reveal_duration(unit: Dictionary) -> float:
	var concealment := ModifierService.calculate(float(unit["stats"]["concealment_distance"]), unit["status_effects"], "ConcealmentDistance")
	var speed := ModifierService.calculate(float(unit["stats"]["speed"]), unit["status_effects"], "Speed")
	return maxf(0.1, concealment / maxf(1.0, speed))


func _set_weapon_reload(unit: Dictionary, weapon_state: Dictionary, weapon: Dictionary) -> void:
	var reload_time := ModifierService.reload_time(float(weapon["reload_time"]), unit["status_effects"], str(weapon["mount_type"]))
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


func _torpedo_error_profile(unit: Dictionary, weapon: Dictionary, shot_count: int) -> Dictionary:
	if weapon.get("mount_type", "") != "Torpedo" or shot_count <= 1:
		return {"sigma_radians": 0.0, "environment_multiplier": 1.0}
	var adjacent_angle := deg_to_rad(float(weapon.get("spread", 0.0))) / float(shot_count - 1)
	var environment_context := terrain_context_service.context_at(unit.get("position", Vector2.ZERO))
	var environment_multiplier := float(environment_context.get("torpedo_sigma_multiplier", 1.0))
	var sigma_ratio := float(weapon.get("torpedo_angular_sigma_ratio", 0.2))
	return {
		"sigma_radians": adjacent_angle * sigma_ratio * environment_multiplier,
		"environment_multiplier": environment_multiplier,
		"sea_state": int(environment_context.get("sea_state", 0)),
		"wind_speed": float(environment_context.get("wind_speed", 0.0)),
	}


func _spawn_projectile(unit: Dictionary, weapon: Dictionary, attack_id: String, heading: float, source_mount_id: String = "", angular_error: float = 0.0, angular_sigma: float = 0.0, environmental_sigma_multiplier: float = 1.0) -> void:
	var projectile_definition: Dictionary = registry.get_definition("projectiles", str(weapon["projectile_id"]))
	var projectile_id := _next_entity_id("projectile")
	var speed := ModifierService.calculate(float(projectile_definition.get("speed", weapon.get("projectile_speed", 0.0))), unit["status_effects"], "ProjectileSpeed", "Torpedo")
	var radius := ModifierService.calculate(float(projectile_definition.get("collision_radius", 8.0)), unit["status_effects"], "ProjectileRadius", "Torpedo")
	var launch_direction := Vector2.RIGHT.rotated(heading)
	var launch_clearance := CollisionGeometryService.radial_extent(_unit_collision_half_extents(unit), float(unit["heading"]), launch_direction)
	state["projectiles_by_id"][projectile_id] = {
		"entity_id": projectile_id,
		"definition_id": projectile_definition["id"],
		"attack_id": attack_id,
		"source_unit_id": unit["entity_id"],
		"source_weapon_id": weapon["id"],
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
			_resolve_attack({"attack_id": projectile["attack_id"], "source_unit_id": projectile["source_unit_id"], "source_weapon_id": projectile["source_weapon_id"], "target_unit_id": unit_hit["target_unit_id"], "origin": impact_position, "accuracy_modifier": 0.0}, true)
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
	var result := DamageService.resolve(attack, source_snapshot, target, weapon, formula, random_source, forced_hit)
	result["impact_position"] = attack.get("target_position", target.get("position", Vector2.ZERO))
	result["aimed_target_unit_id"] = attack.get("aimed_target_unit_id", attack.get("target_unit_id", ""))
	target["current_hp"] = float(result["target_hp_after"])
	_emit("AttackResolved", {"damage_result": result})
	if bool(result["caused_sinking"]): _sink_unit(target, source["entity_id"])


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
		_emit("AttackResolved", {"damage_result": {"attack_id": attack.get("attack_id", ""), "source_unit_id": source.get("entity_id", ""), "source_weapon_id": weapon.get("id", ""), "aimed_target_unit_id": attack.get("aimed_target_unit_id", ""), "target_unit_id": "", "impact_position": impact_position, "damage_type": weapon.get("mount_type", ""), "hit": false, "hit_reason": "NO_TARGET_IN_AREA", "raw_damage": 0.0, "armor_modifier": 0.0, "armor_reduction": 0.0, "final_damage": 0.0, "target_hp_before": 0.0, "target_hp_after": 0.0, "caused_sinking": false}})
		return
	var selected: Dictionary = candidates[0]
	if selected["target_type"] == "Facility":
		attack["target_facility_id"] = selected["target_id"]
	else:
		attack["target_unit_id"] = selected["target_id"]
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
	result["impact_position"] = attack.get("target_position", target.get("position", Vector2.ZERO))
	result["source_facility_id"] = attack.get("source_facility_id", "")
	result["target_facility_id"] = facility_id
	result["target_unit_id"] = ""
	_emit("AttackResolved", {"damage_result": result})
	if not bool(result.get("hit", false)): return
	for event in facility_service.apply_damage(facility_id, float(result.get("final_damage", 0.0)), str(source.get("entity_id", ""))):
		_handle_facility_event(event)
	state["facilities_by_id"] = facility_service.snapshot()


func _handle_facility_event(event: Dictionary) -> void:
	var event_type := str(event.get("event_type", "FacilityChanged"))
	match event_type:
		"FacilityServiceCompleted": _apply_facility_service(event)
		"SupportMissionCompleted": _resolve_support_mission(event)
	_emit(event_type, event)


func _apply_facility_service(event: Dictionary) -> void:
	var unit: Dictionary = state["units_by_id"].get(str(event.get("unit_id", "")), {})
	if unit.is_empty() or unit.get("life_state", "") != "Alive": return
	var profile: Dictionary = event.get("service_profile", {})
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


func _visible_support_effects(viewer_faction: String, omniscient: bool) -> Dictionary:
	var result := {}
	for effect_id in state.get("support_effects_by_id", {}):
		var effect: Dictionary = state["support_effects_by_id"][effect_id]
		if omniscient or str(effect.get("faction_id", "")) == viewer_faction: result[effect_id] = effect.duplicate(true)
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
	var hp_before := float(unit.get("current_hp", 0.0))
	var damage := minf(hp_before, maxf(0.0, float(trigger.get("damage", 0.0))))
	unit["current_hp"] = maxf(0.0, hp_before - damage)
	state["minefields_by_id"] = minefield_service.snapshot()
	_emit("MineTriggered", {"minefield_id":trigger.get("minefield_id", ""), "unit_id":unit["entity_id"], "position":trigger.get("position", unit["position"]), "damage":damage})
	_emit("AttackResolved", {"damage_result":{"attack_id":_next_entity_id("mine_attack"), "source_unit_id":str(trigger.get("minefield_id", "")), "source_weapon_id":"hazard.minefield", "target_unit_id":unit["entity_id"], "impact_position":trigger.get("position", unit["position"]), "damage_type":"Mine", "hit":true, "hit_rate":1.0, "hit_reason":"MINE_TRIGGER", "raw_damage":damage, "armor_modifier":1.0, "armor_reduction":0.0, "final_damage":damage, "target_hp_before":hp_before, "target_hp_after":unit["current_hp"], "caused_sinking":is_zero_approx(float(unit["current_hp"]))}})
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


func _attack_source_faction(attack: Dictionary, source: Dictionary) -> String:
	if not str(attack.get("source_facility_id", "")).is_empty():
		return str(state.get("facilities_by_id", {}).get(str(attack["source_facility_id"]), {}).get("faction_id", "neutral"))
	return str(source.get("faction_id", "neutral"))


func _sink_unit(unit: Dictionary, source_unit_id: String) -> void:
	if unit["life_state"] == "Sunk": return
	unit["life_state"] = "Sunk"
	unit["current_hp"] = 0.0
	unit["current_speed"] = 0.0
	unit["status_effects"].clear()
	_emit("UnitSunk", {"unit_id": unit["entity_id"], "source_unit_id": source_unit_id})
	if unit["is_flagship"]: _emit("FlagshipSunk", {"fleet_id": unit["fleet_id"], "unit_id": unit["entity_id"]})


func _check_victory() -> void:
	if state["phase"] != "Running": return
	var player_flagship: Dictionary = state["units_by_id"][state["fleets_by_id"]["fleet.player"]["flagship_unit_id"]]
	var enemy_flagship: Dictionary = state["units_by_id"][state["fleets_by_id"]["fleet.enemy"]["flagship_unit_id"]]
	var player_sunk: bool = player_flagship["life_state"] == "Sunk"
	var enemy_sunk: bool = enemy_flagship["life_state"] == "Sunk"
	if not player_sunk and not enemy_sunk: return
	var winner := PLAYER_FACTION if enemy_sunk else ENEMY_FACTION
	_finish_battle(winner, "FLAGSHIP_SUNK_SIMULTANEOUS" if player_sunk and enemy_sunk else "FLAGSHIP_SUNK")


func _check_timeout() -> void:
	if state["phase"] != "Running" or float(state["elapsed_time"]) < float(state["time_limit"]): return
	var player_ratio := _remaining_hp_ratio("fleet.player")
	var enemy_ratio := _remaining_hp_ratio("fleet.enemy")
	_finish_battle(PLAYER_FACTION if player_ratio >= enemy_ratio else ENEMY_FACTION, "TIME_LIMIT")


func _finish_battle(winner: String, reason: String) -> void:
	state["phase"] = "Finished"
	state["result"] = {"winner_faction": winner, "reason": reason, "elapsed_time": state["elapsed_time"]}
	_emit("BattleFinished", {"result": state["result"].duplicate(true)})


func _remaining_hp_ratio(fleet_id: String) -> float:
	var fleet: Dictionary = state["fleets_by_id"][fleet_id]
	var hp := 0.0
	for unit_id in fleet["unit_ids"]: hp += float(state["units_by_id"][unit_id]["current_hp"])
	return hp / maxf(1.0, float(fleet["initial_max_hp_total"]))


func _select_target(unit: Dictionary) -> Dictionary:
	var focused_id := str(unit["targeting_state"].get("focused_target_id", ""))
	if not focused_id.is_empty() and _is_visible_to(unit["faction_id"], focused_id):
		var focused: Dictionary = state["units_by_id"].get(focused_id, {})
		if not focused.is_empty() and focused["life_state"] == "Alive": return focused
	var candidates: Array = []
	for target_id in state["visible_by_faction"].get(unit["faction_id"], {}):
		var target: Dictionary = state["units_by_id"][target_id]
		if target["life_state"] == "Alive": candidates.append(target)
	candidates.sort_custom(func(a, b):
		var score_a := _target_score(unit, a)
		var score_b := _target_score(unit, b)
		return score_a > score_b if not is_equal_approx(score_a, score_b) else str(a["entity_id"]) < str(b["entity_id"]))
	return {} if candidates.is_empty() else candidates[0]


func _target_score(source: Dictionary, target: Dictionary) -> float:
	var priorities := {"Submarine": 600.0, "Carrier": 600.0, "Destroyer": 500.0, "Battleship": 400.0, "HeavyCruiser": 300.0, "LightCruiser": 200.0}
	var score := float(priorities.get(target["stats"].get("ship_class", ""), 0.0))
	if target["is_flagship"]: score += 75.0
	score -= (source["position"] as Vector2).distance_to(target["position"] as Vector2) * 0.1
	score += (1.0 - float(target["current_hp"]) / maxf(1.0, float(target["max_hp"]))) * 50.0
	return score


func _preferred_range(unit: Dictionary) -> float:
	var automatic_maximum := 0.0
	var fallback_maximum := 250.0
	for weapon_state in unit["weapon_states"]:
		var weapon: Dictionary = registry.get_definition("weapons", str(weapon_state["definition_id"]))
		var range := float(weapon.get("range", 0.0))
		fallback_maximum = maxf(fallback_maximum, range)
		if weapon.get("control_mode", "Automatic") == "Automatic":
			automatic_maximum = maxf(automatic_maximum, range)
	var maximum := automatic_maximum if automatic_maximum > 0.0 else fallback_maximum
	return maximum * 0.72


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
		if float(weapon_state.get("reload_remaining", 0.0)) <= 0.0:
			ready_states.append(weapon_state)
	if ready_states.is_empty(): return {"legal": false, "reason_code": "WEAPON_RELOADING", "legal_weapon_states": []}
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
	return "Submerged" if unit["stats"].get("ship_class", "") == "Submarine" else "Surface"


func _unit_collision_half_extents(unit: Dictionary) -> Vector2:
	return CollisionGeometryService.half_extents(unit.get("stats", unit))


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


func _current_movement_target(movement: Dictionary, fallback: Vector2) -> Vector2:
	var waypoints: Array = movement.get("waypoints", [])
	var index := int(movement.get("waypoint_index", 0))
	if index >= 0 and index < waypoints.size():
		return waypoints[index]
	return movement.get("target_position", fallback)


func _advance_movement_waypoint(movement: Dictionary) -> void:
	var waypoints: Array = movement.get("waypoints", [])
	if waypoints.is_empty():
		return
	var index := int(movement.get("waypoint_index", 0))
	if index < waypoints.size():
		movement["waypoint_index"] = index + 1


func _movement_finished(movement: Dictionary) -> bool:
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
