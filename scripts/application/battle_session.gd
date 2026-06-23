extends RefCounted

const SeededRandomSource = preload("res://scripts/infrastructure/random/seeded_random_source.gd")
const ModifierService = preload("res://scripts/domain/services/modifier_service.gd")
const DamageService = preload("res://scripts/domain/services/damage_service.gd")
const BattleRecorder = preload("res://scripts/infrastructure/analytics/battle_recorder.gd")

const PLAYER_FACTION := "player"
const ENEMY_FACTION := "enemy"
const CONTACT_GHOST_DURATION := 3.0

var registry
var random_source
var recorder := BattleRecorder.new()
var state := {}
var command_queue: Array = []
var delayed_attacks: Array = []
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
		"visible_by_faction": {PLAYER_FACTION: {}, ENEMY_FACTION: {}},
		"contacts_by_faction": {PLAYER_FACTION: {}, ENEMY_FACTION: {}},
		"result": {},
	}
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
	_process_commands()
	_update_cooldowns_and_statuses(delta)
	_update_movement(delta)
	_resolve_unit_overlap()
	_update_projectiles(delta)
	_update_detection(delta)
	_update_ai_intents()
	_update_auto_skills()
	_update_weapons()
	_resolve_delayed_attacks()
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
	for contact_id in state["contacts_by_faction"].get(viewer_faction, {}):
		var contact: Dictionary = state["contacts_by_faction"][viewer_faction][contact_id]
		if not bool(contact.get("visible", false)):
			contacts[contact_id] = contact.duplicate(true)
	return {
		"battle_id": state.get("battle_id", ""),
		"phase": state.get("phase", ""),
		"elapsed_time": state.get("elapsed_time", 0.0),
		"tick_index": state.get("tick_index", 0),
		"map": state.get("map", {}).duplicate(true),
		"units": units,
		"contacts": contacts,
		"projectiles": state.get("projectiles_by_id", {}).duplicate(true),
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
	for weapon_state in primary_states:
		var weapon: Dictionary = registry.get_definition("weapons", str(weapon_state["definition_id"]))
		if primary_name == "None": primary_name = str(weapon.get("display_name", weapon["id"]))
		if primary_mount_type.is_empty(): primary_mount_type = str(weapon.get("mount_type", ""))
		primary_reload = minf(primary_reload, float(weapon_state.get("reload_remaining", 0.0)))
		primary_reload_max = maxf(primary_reload_max, float(weapon.get("reload_time", 0.0)))
		primary_range = maxf(primary_range, float(weapon.get("range", 0.0)))
		if float(weapon_state.get("reload_remaining", 0.0)) <= 0.0: primary_ready = true
	if primary_states.is_empty():
		primary_reload = 0.0
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
		"primary_reload_remaining": primary_reload,
		"primary_reload_max": primary_reload_max,
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
	var direction_weapon := _direction_weapon_for_aim(unit, aim_weapons, target_position)
	validation["minimum_range"] = float(direction_weapon.get("minimum_range", 0.0))
	validation["selected_range"] = float(direction_weapon.get("range", validation["range"]))
	validation["spread_degrees"] = float(direction_weapon.get("spread", 0.0))
	return validation


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
		weapon_states.append({"instance_id": "%s.%s" % [member["entity_id"], weapon_id], "definition_id": weapon_id, "reload_remaining": 0.0, "enabled": true})
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
			var movement_mode := "AutoNavigate" if command.get("issuer_type", "Player") == "AI" else "PlayerMoveOrder"
			unit["movement_state"] = {"mode": movement_mode, "target_position": _clamp_to_map(target_position)}
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
			return _fire_primary_weapon(unit, _clamp_to_map(target_position), command.get("command_id", ""))
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
		var target_position: Vector2 = movement.get("target_position", unit["position"])
		var distance := (unit["position"] as Vector2).distance_to(target_position)
		var max_speed := ModifierService.calculate(float(unit["stats"]["speed"]), unit["status_effects"], "Speed")
		var turn_speed := deg_to_rad(ModifierService.calculate(float(unit["stats"]["turn_speed"]), unit["status_effects"], "TurnSpeed"))
		if distance <= 8.0:
			unit["current_speed"] = move_toward(float(unit["current_speed"]), 0.0, max_speed * delta * 2.0)
			if movement["mode"] == "PlayerMoveOrder": movement["mode"] = "HoldPosition"
		else:
			var desired_heading := (target_position - (unit["position"] as Vector2)).angle()
			unit["heading"] = rotate_toward(float(unit["heading"]), desired_heading, turn_speed * delta)
			unit["current_speed"] = move_toward(float(unit["current_speed"]), max_speed, max_speed * delta)
		unit["position"] = _clamp_to_map((unit["position"] as Vector2) + Vector2.RIGHT.rotated(float(unit["heading"])) * float(unit["current_speed"]) * delta)


func _resolve_unit_overlap() -> void:
	var unit_ids := _sorted_unit_ids()
	for first_index in range(unit_ids.size()):
		var first: Dictionary = state["units_by_id"][unit_ids[first_index]]
		if first["life_state"] != "Alive": continue
		for second_index in range(first_index + 1, unit_ids.size()):
			var second: Dictionary = state["units_by_id"][unit_ids[second_index]]
			if second["life_state"] != "Alive": continue
			var delta_position: Vector2 = second["position"] - first["position"]
			var minimum_distance := float(first["stats"]["collision_radius"]) + float(second["stats"]["collision_radius"])
			if delta_position.length_squared() <= 0.0001 or delta_position.length() >= minimum_distance: continue
			var correction := delta_position.normalized() * (minimum_distance - delta_position.length()) * 0.5
			first["position"] = _clamp_to_map(first["position"] - correction)
			second["position"] = _clamp_to_map(second["position"] + correction)


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


func _fleet_detects(observer_faction: String, target: Dictionary) -> bool:
	var concealment := ModifierService.calculate(float(target["stats"]["concealment_distance"]), target["status_effects"], "ConcealmentDistance")
	if float(target["firing_reveal_remaining"]) > 0.0: concealment *= float(target["stats"]["fire_concealment_multiplier"])
	for observer_id in _sorted_unit_ids():
		var observer: Dictionary = state["units_by_id"][observer_id]
		if observer["faction_id"] != observer_faction or observer["life_state"] != "Alive": continue
		var detection_range := ModifierService.calculate(float(observer["stats"]["detection_range"]), observer["status_effects"], "DetectionRange")
		var distance := (observer["position"] as Vector2).distance_to(target["position"] as Vector2)
		if distance <= detection_range and distance <= concealment: return true
	return false


func _update_ai_intents() -> void:
	var map_center := Vector2(float(state["map"].get("width", 1200.0)) * 0.5, float(state["map"].get("height", 700.0)) * 0.5)
	for unit_id in _sorted_unit_ids():
		var unit: Dictionary = state["units_by_id"][unit_id]
		if unit["life_state"] != "Alive" or unit["movement_state"]["mode"] == "PlayerMoveOrder": continue
		var target := _select_target(unit)
		if target.is_empty():
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
	for weapon_state in validation.get("legal_weapon_states", []):
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
			_fire_weapon(unit, target, weapon_state, weapon)
			if not group.is_empty():
				fired_groups[group] = true
				for sibling_state in weapon_states:
					var sibling: Dictionary = registry.get_definition("weapons", str(sibling_state["definition_id"]))
					if sibling.get("shared_cooldown_group", "") == group: sibling_state["reload_remaining"] = weapon_state["reload_remaining"]


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
	return {"legal": true, "reason_code": "OK"}


func _fire_weapon(unit: Dictionary, target: Dictionary, weapon_state: Dictionary, weapon: Dictionary) -> void:
	var category := str(weapon["mount_type"])
	var extra_shots := int(round(ModifierService.sum_modifier(unit["status_effects"], "ExtraShots", category)))
	var shot_count := int(weapon["mount_count"]) * int(weapon["shots_per_mount"]) + extra_shots
	_set_weapon_reload(unit, weapon_state, weapon)
	unit["firing_reveal_remaining"] = 3.0
	var base_heading := ((target["position"] as Vector2) - (unit["position"] as Vector2)).angle()
	for shot_index in range(shot_count):
		var spread_offset := 0.0
		if shot_count > 1: spread_offset = deg_to_rad(float(weapon.get("spread", 0.0))) * (float(shot_index) / float(shot_count - 1) - 0.5)
		var attack_id := _next_entity_id("attack")
		if category == "Torpedo":
			_spawn_projectile(unit, weapon, attack_id, base_heading + spread_offset)
		else:
			var travel_seconds := (unit["position"] as Vector2).distance_to(target["position"] as Vector2) / maxf(1.0, float(weapon.get("projectile_speed", 1.0)))
			delayed_attacks.append({"attack_id": attack_id, "source_unit_id": unit["entity_id"], "source_weapon_id": weapon["id"], "target_unit_id": target["entity_id"], "origin": unit["position"], "resolve_at_time": float(state["elapsed_time"]) + travel_seconds, "accuracy_modifier": 0.0})
	_emit("WeaponFired", {"unit_id": unit["entity_id"], "weapon_id": weapon["id"], "target_unit_id": target["entity_id"], "shot_count": shot_count})
	if extra_shots > 0: _consume_effect(unit, "ExtraShots", category)


func _fire_weapon_at_position(unit: Dictionary, target_position: Vector2, weapon_state: Dictionary, weapon: Dictionary, manual: bool) -> void:
	var category := str(weapon["mount_type"])
	var extra_shots := int(round(ModifierService.sum_modifier(unit["status_effects"], "ExtraShots", category)))
	var shot_count := int(weapon["mount_count"]) * int(weapon["shots_per_mount"]) + extra_shots
	_set_weapon_reload(unit, weapon_state, weapon)
	unit["firing_reveal_remaining"] = 3.0
	var base_heading := (target_position - (unit["position"] as Vector2)).angle()
	for shot_index in range(shot_count):
		var spread_offset := 0.0
		if shot_count > 1: spread_offset = deg_to_rad(float(weapon.get("spread", 0.0))) * (float(shot_index) / float(shot_count - 1) - 0.5)
		var attack_id := _next_entity_id("attack")
		if category == "Torpedo":
			_spawn_projectile(unit, weapon, attack_id, base_heading + spread_offset)
		else:
			var impact_offset := Vector2.RIGHT.rotated(base_heading + PI * 0.5) * spread_offset * float(weapon.get("impact_radius", 40.0))
			var impact_position := _clamp_to_map(target_position + impact_offset)
			var travel_seconds := (unit["position"] as Vector2).distance_to(impact_position) / maxf(1.0, float(weapon.get("projectile_speed", 1.0)))
			delayed_attacks.append({"attack_id": attack_id, "source_unit_id": unit["entity_id"], "source_weapon_id": weapon["id"], "target_unit_id": "", "target_position": impact_position, "impact_radius": float(weapon.get("impact_radius", 40.0)), "origin": unit["position"], "resolve_at_time": float(state["elapsed_time"]) + travel_seconds, "accuracy_modifier": 0.0})
	_emit("WeaponFired", {"unit_id": unit["entity_id"], "weapon_id": weapon["id"], "target_position": target_position, "shot_count": shot_count, "manual": manual})
	if extra_shots > 0: _consume_effect(unit, "ExtraShots", category)


func _set_weapon_reload(unit: Dictionary, weapon_state: Dictionary, weapon: Dictionary) -> void:
	var reload_time := ModifierService.reload_time(float(weapon["reload_time"]), unit["status_effects"], str(weapon["mount_type"]))
	weapon_state["reload_remaining"] = reload_time
	var shared_group := str(weapon.get("shared_cooldown_group", ""))
	if shared_group.is_empty(): return
	for sibling_state in unit["weapon_states"]:
		var sibling: Dictionary = registry.get_definition("weapons", str(sibling_state["definition_id"]))
		if str(sibling.get("shared_cooldown_group", "")) == shared_group:
			sibling_state["reload_remaining"] = reload_time


func _spawn_projectile(unit: Dictionary, weapon: Dictionary, attack_id: String, heading: float) -> void:
	var projectile_definition: Dictionary = registry.get_definition("projectiles", str(weapon["projectile_id"]))
	var projectile_id := _next_entity_id("projectile")
	var speed := ModifierService.calculate(float(projectile_definition.get("speed", weapon.get("projectile_speed", 0.0))), unit["status_effects"], "ProjectileSpeed", "Torpedo")
	var radius := ModifierService.calculate(float(projectile_definition.get("collision_radius", 8.0)), unit["status_effects"], "ProjectileRadius", "Torpedo")
	state["projectiles_by_id"][projectile_id] = {
		"entity_id": projectile_id,
		"definition_id": projectile_definition["id"],
		"attack_id": attack_id,
		"source_unit_id": unit["entity_id"],
		"source_weapon_id": weapon["id"],
		"faction_id": unit["faction_id"],
		"position": unit["position"] + Vector2.RIGHT.rotated(heading) * (float(unit["stats"]["collision_radius"]) + 3.0),
		"heading": heading,
		"speed": speed,
		"collision_radius": radius,
		"remaining_lifetime": float(projectile_definition.get("lifetime", 5.0)),
		"remaining_range": float(weapon.get("range", speed * float(projectile_definition.get("lifetime", 5.0)))),
		"target_types": projectile_definition.get("target_types", []).duplicate(),
	}
	_emit("ProjectileSpawned", {"projectile_id": projectile_id, "source_unit_id": unit["entity_id"], "position": state["projectiles_by_id"][projectile_id]["position"]})


func _update_projectiles(delta: float) -> void:
	for projectile_id in state["projectiles_by_id"].keys():
		var projectile: Dictionary = state["projectiles_by_id"][projectile_id]
		var movement := float(projectile["speed"]) * delta
		projectile["position"] += Vector2.RIGHT.rotated(float(projectile["heading"])) * movement
		projectile["remaining_lifetime"] = float(projectile["remaining_lifetime"]) - delta
		projectile["remaining_range"] = float(projectile["remaining_range"]) - movement
		if float(projectile["remaining_lifetime"]) <= 0.0 or float(projectile["remaining_range"]) <= 0.0:
			state["projectiles_by_id"].erase(projectile_id)
			continue
		for target_id in _sorted_unit_ids():
			var target: Dictionary = state["units_by_id"][target_id]
			if target["life_state"] != "Alive" or target["faction_id"] == projectile["faction_id"] or not _target_type(target) in projectile["target_types"]: continue
			var collision_distance := float(projectile["collision_radius"]) + float(target["stats"]["collision_radius"])
			if (projectile["position"] as Vector2).distance_to(target["position"] as Vector2) > collision_distance: continue
			_emit("ProjectileHit", {"projectile_id": projectile_id, "target_unit_id": target_id, "position": projectile["position"]})
			_resolve_attack({"attack_id": projectile["attack_id"], "source_unit_id": projectile["source_unit_id"], "source_weapon_id": projectile["source_weapon_id"], "target_unit_id": target_id, "origin": projectile["position"], "accuracy_modifier": 0.0}, true)
			state["projectiles_by_id"].erase(projectile_id)
			break


func _resolve_delayed_attacks() -> void:
	delayed_attacks.sort_custom(func(a, b): return float(a["resolve_at_time"]) < float(b["resolve_at_time"]) if not is_equal_approx(float(a["resolve_at_time"]), float(b["resolve_at_time"])) else str(a["attack_id"]) < str(b["attack_id"]))
	var remaining: Array = []
	for attack in delayed_attacks:
		if float(attack["resolve_at_time"]) <= float(state["elapsed_time"]): _resolve_attack(attack, false)
		else: remaining.append(attack)
	delayed_attacks = remaining


func _resolve_attack(attack: Dictionary, forced_hit: bool) -> void:
	var source: Dictionary = state["units_by_id"].get(str(attack["source_unit_id"]), {})
	if source.is_empty(): return
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
	target["current_hp"] = float(result["target_hp_after"])
	_emit("AttackResolved", {"damage_result": result})
	if bool(result["caused_sinking"]): _sink_unit(target, source["entity_id"])


func _resolve_area_attack(attack: Dictionary, source: Dictionary, forced_hit: bool) -> void:
	var weapon: Dictionary = registry.get_definition("weapons", str(attack["source_weapon_id"]))
	var impact_position: Vector2 = attack.get("target_position", source["position"])
	var impact_radius := float(attack.get("impact_radius", weapon.get("impact_radius", 40.0)))
	var candidates: Array = []
	for target_id in _sorted_unit_ids():
		var target: Dictionary = state["units_by_id"][target_id]
		if target["life_state"] != "Alive" or target["faction_id"] == source["faction_id"]: continue
		if not _target_type(target) in weapon.get("target_types", []): continue
		var distance := (target["position"] as Vector2).distance_to(impact_position)
		if distance <= impact_radius + float(target["stats"].get("collision_radius", 0.0)):
			candidates.append({"unit": target, "distance": distance})
	candidates.sort_custom(func(a, b): return float(a["distance"]) < float(b["distance"]) if not is_equal_approx(float(a["distance"]), float(b["distance"])) else str(a["unit"]["entity_id"]) < str(b["unit"]["entity_id"]))
	if candidates.is_empty():
		_emit("AttackResolved", {"damage_result": {"attack_id": attack.get("attack_id", ""), "source_unit_id": source.get("entity_id", ""), "target_unit_id": "", "damage_type": weapon.get("mount_type", ""), "hit": false, "hit_reason": "NO_TARGET_IN_AREA", "raw_damage": 0.0, "armor_modifier": 0.0, "armor_reduction": 0.0, "final_damage": 0.0, "target_hp_before": 0.0, "target_hp_after": 0.0, "caused_sinking": false}})
		return
	var target: Dictionary = candidates[0]["unit"]
	attack["target_unit_id"] = target["entity_id"]
	_resolve_attack(attack, forced_hit)


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
	var maximum := 250.0
	for weapon_state in unit["weapon_states"]:
		var weapon: Dictionary = registry.get_definition("weapons", str(weapon_state["definition_id"]))
		maximum = maxf(maximum, float(weapon.get("range", 0.0)))
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
	for weapon_state in primary_states:
		if float(weapon_state.get("reload_remaining", 0.0)) <= 0.0:
			return "OK"
	return "WEAPON_RELOADING"


func _validate_primary_fire(unit: Dictionary, weapon_states: Array, target_position: Vector2) -> Dictionary:
	if state.get("phase", "") != "Running": return {"legal": false, "reason_code": "BATTLE_NOT_RUNNING", "legal_weapon_states": []}
	if unit.get("life_state", "") != "Alive": return {"legal": false, "reason_code": "UNIT_SUNK", "legal_weapon_states": []}
	if weapon_states.is_empty(): return {"legal": false, "reason_code": "PRIMARY_WEAPON_UNAVAILABLE", "legal_weapon_states": []}
	var ready_states: Array = []
	for weapon_state in weapon_states:
		if float(weapon_state.get("reload_remaining", 0.0)) <= 0.0:
			ready_states.append(weapon_state)
	if ready_states.is_empty(): return {"legal": false, "reason_code": "WEAPON_RELOADING", "legal_weapon_states": []}
	var legal_states: Array = []
	var last_reason := "TARGET_OUT_OF_RANGE"
	for weapon_state in ready_states:
		var weapon: Dictionary = registry.get_definition("weapons", str(weapon_state["definition_id"]))
		var validation := _can_fire_at_position(unit, target_position, weapon)
		if bool(validation.get("legal", false)): legal_states.append(weapon_state)
		else: last_reason = str(validation.get("reason_code", last_reason))
	return {"legal": not legal_states.is_empty(), "reason_code": "OK" if not legal_states.is_empty() else last_reason, "legal_weapon_states": legal_states}


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
		var weapon: Dictionary = registry.get_definition("weapons", str(weapon_state.get("definition_id", "")))
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
	for weapon in weapons:
		for arc in _weapon_fire_arcs(weapon):
			result.append({
				"center": float(arc.get("center", 0.0)),
				"degrees": float(arc.get("degrees", 360.0)),
				"minimum_range": float(weapon.get("minimum_range", 0.0)),
				"range": float(weapon.get("range", 0.0)),
				"spread_degrees": float(weapon.get("spread", 0.0)),
				"weapon_id": str(weapon.get("id", "")),
			})
	return result


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


func _is_visible_to(faction_id: String, target_id: String) -> bool:
	return state.get("visible_by_faction", {}).get(faction_id, {}).has(target_id)


func _clamp_to_map(position: Vector2) -> Vector2:
	return Vector2(clampf(position.x, 0.0, float(state["map"].get("width", 1200.0))), clampf(position.y, 0.0, float(state["map"].get("height", 700.0))))


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
