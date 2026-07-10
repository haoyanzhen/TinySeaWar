extends SceneTree

const ConfigRegistry = preload("res://scripts/infrastructure/data/config_registry.gd")
const BattleSession = preload("res://scripts/application/battle_session.gd")
const LEVEL_ID := "level.prototype_harbor_3v3"
const SEED := 6401

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var registry = ConfigRegistry.new()
	if not registry.load_all():
		push_error("Configuration errors: %s" % registry.errors)
		quit(1)
		return
	var results := [_trace(registry, "original"), _trace(_swapped_registry(registry), "swapped")]
	var totals := {}
	for result in results:
		for guard in result.get("rejections_by_guard", {}): totals[guard] = int(totals.get(guard, 0)) + int(result["rejections_by_guard"][guard])
	print("FACILITY_CONTROL_TICK_TRACE=" + JSON.stringify({"seed": SEED, "runs": results, "totals": totals}))
	quit(0)

func _trace(registry, variant: String) -> Dictionary:
	var session = BattleSession.new(registry)
	var creation: Dictionary = session.create_battle(LEVEL_ID, SEED)
	if not bool(creation.get("ok", false)): return {"side_variant": variant, "errors": creation.get("errors", [])}
	session.configure_full_ai_factions(["player", "enemy"])
	session.configure_ai_profile("ai.profile.standard")
	var counts := {}
	var accepted := 0
	var samples: Array = []
	while session.state.get("phase", "") == "Running" and int(session.state.get("tick_index", 0)) < 4300:
		var commands := _pending_controls(session)
		var events: Array = session.advance_tick(0.1)
		var rejected := {}
		for event in events:
			if str(event.get("event_type", "")) == "CommandRejected": rejected[str(event.get("command_id", ""))] = true
		for pending in commands:
			if rejected.has(str(pending.command.get("command_id", ""))):
				var guard := _guard(pending.facility, pending.definition, pending.unit)
				counts[guard] = int(counts.get(guard, 0)) + 1
				if samples.size() < 6: samples.append({"tick": pending.tick, "facility_id": pending.command.get("facility_id", ""), "unit_id": pending.command.get("unit_id", ""), "guard": guard, "executor": pending.facility.get("control_state", {}).get("executor_unit_id", "")})
			else: accepted += 1
	return {"side_variant": variant, "accepted_controls": accepted, "rejections_by_guard": counts, "samples": samples}

func _pending_controls(session) -> Array:
	var pending: Array = []
	for value in session.command_queue:
		var command: Dictionary = value
		if str(command.get("command_type", "")) != "DeclareFacilityControl" or str(command.get("issuer_type", "")) != "AI": continue
		var facility_id := str(command.get("facility_id", ""))
		pending.append({"tick": int(session.state.get("tick_index", 0)) + 1, "command": command.duplicate(true), "facility": session.facility_service.facilities_by_id.get(facility_id, {}).duplicate(true), "definition": session.facility_service.definition_for(facility_id).duplicate(true), "unit": session.state["units_by_id"].get(str(command.get("unit_id", "")), {}).duplicate(true)})
	return pending

func _guard(facility: Dictionary, definition: Dictionary, unit: Dictionary) -> String:
	if facility.is_empty() or str(facility.get("life_state", "")) != "Alive": return "NOT_ALIVE_OR_MISSING"
	if "AreaControl" not in definition.get("operation_modes", []) or not bool(definition.get("area_control", {}).get("enabled", false)) or not bool(definition.get("area_control", {}).get("capturable", false)): return "NOT_AREA_CONTROLLABLE"
	if not facility.get("control_state", {}).is_empty(): return "ALREADY_CONTROLLED_BY_OTHER_COMMAND"
	if str(facility.get("operation_state", "")) == "Suppressed": return "SUPPRESSED_SEPARATE_REASON"
	if str(unit.get("life_state", "")) != "Alive": return "UNIT_UNAVAILABLE_SEPARATE_REASON"
	var faction_id := str(unit.get("faction_id", ""))
	var policy := str(facility.get("control_policy", "SeizeOrActivate"))
	if policy == "LockedWhileActive" and str(facility.get("desired_operation_state", "")) == "Active": return "LOCKED_WHILE_ACTIVE"
	if policy == "ActivateOwnerOnly" and str(facility.get("faction_id", "")) != faction_id: return "OWNER_ONLY"
	if "Ownable" not in definition.get("capabilities", []): return "NOT_OWNABLE"
	if str(facility.get("faction_id", "neutral")) == faction_id and str(facility.get("operation_state", "")) == "Active": return "ALREADY_OWNED_AND_ACTIVE"
	return "UNCLASSIFIED"

func _swapped_registry(registry):
	var clone = registry.get_script().new()
	clone.definitions = registry.definitions.duplicate(true)
	clone.errors.clear()
	var level: Dictionary = registry.get_definition("levels", LEVEL_ID)
	var swapped := level.duplicate(true)
	swapped["player_fleet"] = _place(level.get("enemy_fleet", []), level.get("player_fleet", []), "player")
	swapped["enemy_fleet"] = _place(level.get("player_fleet", []), level.get("enemy_fleet", []), "enemy")
	clone.definitions["levels"][LEVEL_ID] = swapped
	return clone

func _place(lineup: Array, spawns: Array, faction_id: String) -> Array:
	var placed: Array = []
	for index in range(lineup.size()):
		var unit: Dictionary = lineup[index].duplicate(true)
		unit["position"] = spawns[index].get("position", []).duplicate(true)
		unit["heading"] = spawns[index].get("heading", 0.0)
		var suffix := str(unit.get("entity_id", "")).trim_prefix("unit.player.").trim_prefix("unit.enemy.")
		unit["entity_id"] = "unit.%s.%s" % [faction_id, suffix]
		placed.append(unit)
	return placed
