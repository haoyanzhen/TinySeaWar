extends SceneTree

const ConfigRegistry = preload("res://scripts/infrastructure/data/config_registry.gd")
const BattleSession = preload("res://scripts/application/battle_session.gd")

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = ConfigRegistry.new()
	_check(registry.load_all(), "configuration registry loads")
	var facility_modes_valid := true
	for definition in registry.all("facilities"):
		if definition.get("definition_type", "") == "FacilityDefinition" and definition.get("operation_modes", []).is_empty(): facility_modes_valid = false
	_check(facility_modes_valid, "all facility definitions declare independent operation modes")
	var session = BattleSession.new(registry)
	_check(session.create_battle("level.prototype_harbor_3v3", 20260630).get("ok", false), "harbor AI fixture starts")
	session.state["visible_by_faction"]["enemy"] = {}
	session._ai_observations_by_faction.clear()
	var assigned: Array[String] = []
	var capture_plans := 0
	for unit_id in ["unit.enemy.gnevny", "unit.enemy.anshan", "unit.enemy.ning_hai"]:
		var unit: Dictionary = session.state["units_by_id"][unit_id]
		var plan: Dictionary = session._ai_facility_plan(unit, true)
		if not plan.is_empty():
			capture_plans += 1
			assigned.append(str(unit.get("ai_state", {}).get("task_target_ref", {}).get("facility_id", "")))
	_check(capture_plans == 1, "objective saturation assigns one capture runner while the group remains available")
	_check(assigned.size() == 1 and not assigned[0].is_empty(), "capture runner retains a concrete facility target")
	var runner: Dictionary = {}
	for unit_id in ["unit.enemy.gnevny", "unit.enemy.anshan", "unit.enemy.ning_hai"]:
		var candidate: Dictionary = session.state["units_by_id"][unit_id]
		if str(candidate.get("ai_state", {}).get("level_task", "")) == "CaptureFacility":
			runner = candidate
			break
	var runner_facility_id := str(runner.get("ai_state", {}).get("task_target_ref", {}).get("facility_id", ""))
	var runner_facility: Dictionary = session.state["facilities_by_id"].get(runner_facility_id, {})
	if not runner.is_empty() and not runner_facility.is_empty():
		runner["position"] = session.facility_service.interaction_center(runner_facility_id)
		runner["movement_state"] = {"mode": "AutoNavigate", "target_position": runner["position"] + Vector2(300.0, 0.0), "waypoints": [runner["position"] + Vector2(300.0, 0.0)], "waypoint_index": 0}
		runner["current_speed"] = 50.0
		var movement_before: Dictionary = runner["movement_state"].duplicate(true)
		var speed_before := float(runner["current_speed"])
		var position_before: Vector2 = runner["position"]
		var start_result: Dictionary = session._apply_command({"command_id": "test.facility.start", "command_type": "DeclareFacilityControl", "issuer_id": "enemy", "issuer_type": "AI", "unit_id": runner["entity_id"], "facility_id": runner_facility_id})
		_check(bool(start_result.get("accepted", false)), "capture runner can start its assigned facility interaction")
		_check(runner["movement_state"] == movement_before and is_equal_approx(float(runner["current_speed"]), speed_before), "ordinary facility work preserves navigation and speed")
		session._update_movement(0.5)
		_check((runner["position"] as Vector2).distance_to(position_before) > 1.0, "ordinary facility work does not hold station or cancel propulsion")
		session._ai_observations_by_faction.clear()
		session._ai_objective_plan_cache.clear()
		var active_plan: Dictionary = session._ai_facility_plan(runner, true)
		_check(bool(active_plan.get("hold_interaction", false)) and not active_plan.has("action_type"), "active facility action is held without duplicate declarations")
		for index in range(20):
			session._update_movement(0.5)
		var interaction_events: Array = session.facility_service.advance(0.5, 0.5, session.state["units_by_id"])
		_check(_has_event(interaction_events, "FacilityActionInterrupted") and session.facility_service.active_action_for_unit(str(runner["entity_id"])).is_empty(), "leaving the interaction water interrupts ordinary facility work")
	var defender: Dictionary = session.state["units_by_id"]["unit.enemy.gnevny"]
	var battery: Dictionary = session.state["facilities_by_id"]["facility.harbor.battery_west"]
	var intruder: Dictionary = session.state["units_by_id"]["unit.player.shimakaze"]
	intruder["position"] = battery["position"]
	session.state["visible_by_faction"]["enemy"] = {intruder["entity_id"]: true}
	for unit_id in ["unit.enemy.gnevny", "unit.enemy.anshan", "unit.enemy.ning_hai"]:
		session._clear_ai_facility_task(session.state["units_by_id"][unit_id])
	session._ai_observations_by_faction.clear()
	session._ai_local_power_cache.clear()
	var defense: Dictionary = session._ai_facility_plan(defender, false)
	_check(str(defense.get("task_type", "")) == "DefendFacility", "visible pressure creates a quantified defense task")
	_check(float(defense.get("score", 0.0)) >= 60.0, "facility defense meets the designed override threshold")
	_check(str(defender["ai_state"].get("objective_role", "")) == "ApproachIntercept", "fast destroyer receives approach-intercept duty")
	var fake_battleship := defender.duplicate(true)
	fake_battleship["stats"]["ship_class"] = "Battleship"
	_check(session._facility_defense_role(fake_battleship) == "FireSupport", "capital ship maps to facility fire-support duty")
	var fake_cruiser := defender.duplicate(true)
	fake_cruiser["stats"]["ship_class"] = "HeavyCruiser"
	_check(session._facility_defense_role(fake_cruiser) == "InnerGuard", "heavy cruiser maps to inner-guard duty")
	intruder["position"] = Vector2(99999.0, 99999.0)
	session._ai_observations_by_faction.clear()
	session._ai_local_power_cache.clear()
	var cleared: Dictionary = session._ai_facility_plan(defender, false)
	_check(cleared.is_empty() and str(defender["ai_state"].get("level_task", "")).is_empty(), "obsolete defense task is cleared when pressure disappears")

	var modes_session = BattleSession.new(registry)
	modes_session.create_battle("level.prototype_harbor_3v3", 20260704)
	var control_id := "facility.harbor.observation_west"
	var controller: Dictionary = modes_session.state["units_by_id"]["unit.player.shimakaze"]
	var friendly: Dictionary = modes_session.state["units_by_id"]["unit.player.aurora"]
	var contesting_enemy: Dictionary = modes_session.state["units_by_id"]["unit.enemy.gnevny"]
	controller["position"] = Vector2(200.0, 200.0)
	_check(modes_session.facility_service.declare_control(control_id, controller)["accepted"], "area control intent can be declared before entering its water")
	_check(not modes_session.facility_service.declare_control(control_id, friendly)["accepted"], "area control accepts only one executing ship")
	modes_session.facility_service.advance(2.0, 2.0, modes_session.state["units_by_id"])
	_check(is_zero_approx(float(modes_session.facility_service.facilities_by_id[control_id]["control_state"]["progress"])), "area control does not progress before the executor enters")
	var control_center: Vector2 = modes_session.facility_service.interaction_center(control_id)
	controller["position"] = control_center
	contesting_enemy["position"] = control_center
	modes_session.facility_service.advance(2.0, 4.0, modes_session.state["units_by_id"])
	_check(modes_session.facility_service.facilities_by_id[control_id]["interaction_state"] == "Contested" and is_zero_approx(float(modes_session.facility_service.facilities_by_id[control_id]["control_state"]["progress"])), "enemy presence pauses control in Contested")
	contesting_enemy["position"] = Vector2(4000.0, 1800.0)
	var control_events: Array = modes_session.facility_service.advance(5.1, 9.1, modes_session.state["units_by_id"])
	_check(_has_event(control_events, "FacilityControlCompleted") and modes_session.facility_service.facilities_by_id[control_id]["faction_id"] == "player", "uncontested executor completes ownership control alone")

	var supply_id := "facility.harbor.supply_west"
	var supply: Dictionary = modes_session.facility_service.facilities_by_id[supply_id]
	supply["faction_id"] = "player"
	supply["operation_state"] = "Active"
	supply["previous_operation_state"] = "Active"
	controller["position"] = modes_session.facility_service.interaction_center(supply_id)
	controller["current_speed"] = 30.0
	_check(modes_session.facility_service.request_service(supply_id, controller).get("reason_code", "") == "BERTH_SPEED_TOO_HIGH", "berthing service rejects excessive entry speed")
	controller["current_speed"] = 0.0
	controller["faction_id"] = "enemy"
	_check(modes_session.facility_service.request_service(supply_id, controller).get("reason_code", "") == "FACILITY_NOT_ACTIVE", "berthing service rejects the wrong faction")
	controller["faction_id"] = "player"
	_check(modes_session.facility_service.request_service(supply_id, controller)["accepted"], "berthing service accepts valid faction, position, speed, heading, and free berth")
	_check(modes_session._apply_command({"command_id":"legacy.facility","command_type":"StartFacilityInteraction","issuer_id":"player","issuer_type":"Player","unit_id":controller["entity_id"],"facility_id":supply_id}).get("reason_code", "") == "UNKNOWN_COMMAND", "legacy unified facility command is not a normal runtime entry")

	var player_assist_session = BattleSession.new(registry)
	player_assist_session.create_battle("level.prototype_harbor_3v3", 20260705)
	var assisted: Dictionary = player_assist_session.state["units_by_id"]["unit.player.shimakaze"]
	assisted["movement_assist_enabled"] = true
	var assisted_facility_id := "facility.harbor.observation_west"
	_check(player_assist_session._apply_command({"command_id":"player.approach", "command_type":"ApproachFacility", "issuer_id":"player", "issuer_type":"Player", "unit_id":assisted["entity_id"], "facility_id":assisted_facility_id})["accepted"], "player can explicitly assign a known facility approach")
	player_assist_session._update_player_assist_intent(assisted)
	var assist_command: Dictionary = player_assist_session.command_queue.back()
	_check((assist_command.get("target_position", Vector2.ZERO) as Vector2).distance_to(player_assist_session.facility_service.interaction_center(assisted_facility_id)) < 1.0 and assisted["player_facility_target_id"] == assisted_facility_id, "limited assist approaches only the player-assigned facility")
	player_assist_session.facility_service.facilities_by_id["facility.harbor.supply_west"]["faction_id"] = "enemy"
	player_assist_session._ai_observations_by_faction.clear()
	assisted["ai_state"]["decision_cooldown"] = 0.0
	player_assist_session._update_player_assist_intent(assisted)
	_check(assisted["player_facility_target_id"] == assisted_facility_id, "limited assist does not switch to a newly valuable facility")

	var player_rule_session = BattleSession.new(registry)
	var ai_rule_session = BattleSession.new(registry)
	player_rule_session.create_battle("level.prototype_harbor_3v3", 20260706)
	ai_rule_session.create_battle("level.prototype_harbor_3v3", 20260706)
	var player_executor: Dictionary = player_rule_session.state["units_by_id"]["unit.player.shimakaze"]
	var ai_executor: Dictionary = ai_rule_session.state["units_by_id"]["unit.enemy.gnevny"]
	var symmetry_id := "facility.harbor.observation_west"
	player_executor["position"] = player_rule_session.facility_service.interaction_center(symmetry_id)
	ai_executor["position"] = ai_rule_session.facility_service.interaction_center(symmetry_id)
	var player_control := player_rule_session._apply_command({"command_id":"symmetry.player", "command_type":"DeclareFacilityControl", "issuer_id":"player", "issuer_type":"Player", "unit_id":player_executor["entity_id"], "facility_id":symmetry_id})
	var ai_control := ai_rule_session._apply_command({"command_id":"symmetry.ai", "command_type":"DeclareFacilityControl", "issuer_id":"enemy", "issuer_type":"AI", "unit_id":ai_executor["entity_id"], "facility_id":symmetry_id})
	_check(player_control["accepted"] and ai_control["accepted"] and player_rule_session.facility_service.facilities_by_id[symmetry_id]["interaction_state"] == ai_rule_session.facility_service.facilities_by_id[symmetry_id]["interaction_state"], "player and AI control commands share the same domain transition")
	ai_rule_session._set_ai_facility_task(ai_executor, {"task_type":"CaptureFacility", "facility_id":symmetry_id, "score":80.0})
	ai_rule_session._handle_facility_event({"event_type":"FacilityActionInterrupted", "unit_id":ai_executor["entity_id"], "facility_id":symmetry_id, "reason_code":"UNIT_LEFT_INTERACTION_AREA"})
	_check(ai_executor["ai_state"]["level_task"].is_empty() and ai_executor["ai_state"]["task_blocked_facility_id"] == symmetry_id and float(ai_executor["ai_state"]["task_blocked_until"]) > 0.0, "interrupted full AI task is abandoned and temporarily blocked before rescoring")
	ai_rule_session._record_ai_facility_failure(ai_executor, symmetry_id)
	_check(is_inf(float(ai_executor["ai_state"]["task_blocked_until"])), "two failures make the unit abandon the same facility for the battle")
	ai_executor["ai_state"]["level_task"] = "ServiceFacility"; ai_executor["ai_state"]["task_started_at"] = -20.0
	var visible_target: Dictionary = ai_rule_session.state["units_by_id"]["unit.player.shimakaze"]
	ai_rule_session.state["visible_by_faction"]["enemy"] = {visible_target["entity_id"]: true}
	ai_rule_session._ai_observations_by_faction.clear()
	ai_rule_session._update_enemy_ai_intent(ai_executor)
	_check(ai_executor["ai_state"]["level_task"] != "ServiceFacility", "stale facility work cannot indefinitely block re-engagement")

	var mine_session = BattleSession.new(registry)
	mine_session.create_battle("level.prototype_harbor_3v3", 20260707)
	var mine_facility_id := "facility.harbor.mine_control_west"
	var mine_facility: Dictionary = mine_session.facility_service.facilities_by_id[mine_facility_id]
	mine_facility["faction_id"] = "player"; mine_facility["operation_state"] = "Active"; mine_facility["previous_operation_state"] = "Active"
	var mine_requester: Dictionary = mine_session.state["units_by_id"]["unit.player.shimakaze"]
	var mine_target: Vector2 = mine_facility["position"] + Vector2(450.0, 0.0)
	for enemy_id in ["unit.enemy.gnevny", "unit.enemy.anshan", "unit.enemy.ning_hai"]: mine_session.state["units_by_id"][enemy_id]["position"] = Vector2(3900.0, 2000.0)
	var mine_request := mine_session._apply_command({"command_id":"mine.player", "command_type":"RequestMineDeployment", "issuer_id":"player", "issuer_type":"Player", "unit_id":mine_requester["entity_id"], "facility_id":mine_facility_id, "target_position":mine_target})
	_check(mine_request["accepted"], "player mine action enters the shared remote-command rules")
	var mine_events: Array = mine_session.facility_service.advance(10.1, 10.1, mine_session.state["units_by_id"])
	for mine_event in mine_events: mine_session._handle_facility_event(mine_event)
	var deployed_count := 0
	for minefield in mine_session.minefield_service.minefields_by_id.values():
		if minefield.get("mine_type", "") == "DeployedMine": deployed_count += 1
	_check(deployed_count == 12, "completed mine task creates the authored random batch")

	var remote_ai_session = BattleSession.new(registry)
	remote_ai_session.create_battle("level.prototype_harbor_3v3", 20260708)
	var remote_target: Dictionary = remote_ai_session.state["units_by_id"]["unit.player.shimakaze"]
	remote_ai_session.state["visible_by_faction"]["enemy"] = {remote_target["entity_id"]: true}
	remote_ai_session._ai_observations_by_faction.clear()
	remote_ai_session._update_ai_support_intents("enemy")
	var airport_task_found := false
	for command in remote_ai_session.command_queue:
		if command.get("command_type", "") == "RequestSupportMission": airport_task_found = true
	_check(airport_task_found, "full AI creates an airport support task from known facilities")
	remote_ai_session.command_queue.clear()
	remote_ai_session.facility_service.facilities_by_id["facility.harbor.airfield_east"]["operation_state"] = "Suppressed"
	var ai_mine: Dictionary = remote_ai_session.facility_service.facilities_by_id["facility.harbor.mine_control_west"]
	ai_mine["faction_id"] = "enemy"; ai_mine["operation_state"] = "Active"; ai_mine["previous_operation_state"] = "Active"
	for remote_unit in remote_ai_session.state["units_by_id"].values():
		if remote_unit.get("faction_id", "") == "player": remote_unit["position"] = Vector2(3900.0, 2100.0)
	remote_ai_session.state["facilities_by_id"] = remote_ai_session.facility_service.snapshot()
	remote_ai_session._ai_observations_by_faction.clear()
	remote_ai_session._update_ai_support_intents("enemy")
	var mine_task_found := false
	for command in remote_ai_session.command_queue:
		if command.get("command_type", "") == "RequestMineDeployment": mine_task_found = true
	_check(mine_task_found, "full AI creates a remote mine deployment task")
	if failures.is_empty():
		print("PASS: %d AI facility task checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error("FAIL: %s" % failure)
		print("FAILED: %d of %d AI facility task checks; assigned=%s" % [failures.size(), checks, assigned])
		quit(1)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)


func _has_event(events: Array, event_type: String) -> bool:
	for event in events:
		if str(event.get("event_type", "")) == event_type:
			return true
	return false
