extends SceneTree

const ConfigRegistry = preload("res://scripts/infrastructure/data/config_registry.gd")
const BattleSession = preload("res://scripts/application/battle_session.gd")
const MinefieldService = preload("res://scripts/domain/services/minefield_service.gd")

class MixedTerrain:
	extends RefCounted
	func is_configured() -> bool: return true
	func can_occupy_circle(position: Vector2, _radius: float, _tags: Array) -> bool: return position.x >= 0.0

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = ConfigRegistry.new()
	_check(registry.load_all(), "mine-control configuration and semantic references load")
	var session = BattleSession.new(registry)
	_check(session.create_battle("level.prototype_harbor_3v3", 42015).get("ok", false), "harbor mine-control fixture starts")
	var facility_id := "facility.harbor.mine_control_west"
	var facility: Dictionary = session.facility_service.facilities_by_id[facility_id]
	var definition: Dictionary = session.facility_service.definition_for(facility_id)
	var rules: Dictionary = definition["remote_command"]
	_check(facility.get("faction_id") == "neutral" and facility.get("operation_state") == "Dormant", "mine controller starts neutral and dormant")
	_check(definition.get("area_control", {}).get("capturable", false) and definition.get("combat_disposition", {}).get("suppressible", false) and definition.get("combat_disposition", {}).get("destroyable", false), "mine controller is capturable, suppressible, and destroyable")
	_check(is_equal_approx(float(rules.get("detection_distance", 0.0)), 75.0) and rules.get("detection_reference", {}).get("ship_id") == "ship.warspite", "mine detection resolves to half the classic battleship length")
	_check(rules.get("damage_reference", {}).get("ship_id") == "ship.shimakaze" and rules.get("damage_reference", {}).get("weapon_id") == "weapon.shimakaze_610_torpedo", "mine damage uses stable classic torpedo references")

	var controller: Dictionary = session.state["units_by_id"]["unit.player.shimakaze"]
	controller["position"] = session.facility_service.interaction_center(facility_id)
	_check(session.facility_service.declare_control(facility_id, controller).get("accepted", false), "player can declare control in the authored water area")
	session.facility_service.advance(6.1, 6.1, session.state["units_by_id"])
	_check(facility.get("faction_id") == "player" and facility.get("operation_state") == "Active", "capture activates the mine controller")
	var enemy: Dictionary = session.state["units_by_id"]["unit.enemy.kirov"]
	_check(session.facility_service.validate_mine_deployment(facility_id, controller, enemy["position"], session.state["units_by_id"]).get("reason_code") == "MINE_AREA_CONTAINS_ENEMY", "square selection rejects an area containing an enemy")
	_check(session.facility_service.validate_mine_deployment(facility_id, controller, facility["position"] + Vector2(1300.0, 0.0), session.state["units_by_id"]).get("reason_code") == "TARGET_OUT_OF_RANGE", "selection rejects targets outside the control radius")

	var target: Vector2 = facility["position"] + Vector2(400.0, -300.0)
	var request: Dictionary = session.facility_service.request_mine_deployment(facility_id, controller, target, 10.0, session.state["units_by_id"], 99)
	_check(request.get("accepted", false) and is_equal_approx(float(request.get("event", {}).get("duration", 0.0)), 10.0), "valid deployment starts a ten-second task")
	_check(not _has_event(session.facility_service.advance(9.9, 19.9, session.state["units_by_id"]), "MineDeploymentCompleted"), "mine batch does not resolve before ten seconds")
	var completed_events: Array = session.facility_service.advance(0.1, 20.0, session.state["units_by_id"])
	_check(_has_event(completed_events, "MineDeploymentCompleted"), "mine batch resolves together at ten seconds")

	var deployment: Dictionary = _event(completed_events, "MineDeploymentCompleted")
	deployment["target_position"] = Vector2.ZERO
	var isolated = MinefieldService.new()
	var batch_events: Array = isolated.deploy_random_batch(deployment, MixedTerrain.new())
	var batch_result := _event(batch_events, "MineDeploymentBatchResolved")
	_check(int(batch_result.get("active_count", 0)) + int(batch_result.get("invalid_count", 0)) == int(rules.get("mine_count", 0)) and int(batch_result.get("active_count", 0)) > 0 and int(batch_result.get("invalid_count", 0)) > 0, "landed mines invalidate individually without redraw or batch loss")

	var mine_id := "mine.test.shared"
	session.minefield_service.minefields_by_id[mine_id] = {"definition_id":"mine.dynamic", "mine_type":"DeployedMine", "position":controller["position"] + Vector2(90.0, 0.0), "owner_faction_id":"enemy", "operation_state":"Active", "known_by_faction":["enemy"], "trigger_radius":18.0, "detection_distance":75.0, "damage_reference":rules["damage_reference"].duplicate(true)}
	controller["status_effects"] = []
	session._update_mine_observation()
	_check("player" not in session.minefield_service.minefields_by_id[mine_id]["known_by_faction"], "mine remains hidden outside its base detection distance")
	controller["status_effects"] = [{"stat":"TorpedoDetectionDistance", "category":"Torpedo", "operation":"PercentAdd", "value":0.5}]
	session._event_buffer.clear()
	session._update_mine_observation()
	_check("player" in session.minefield_service.minefields_by_id[mine_id]["known_by_faction"] and _has_event(session._event_buffer, "MineDetected"), "torpedo detection bonus reveals a mine to the whole faction")

	var friendly_mine_id := "mine.test.friendly"
	session.minefield_service.minefields_by_id[friendly_mine_id] = {"definition_id":"mine.dynamic", "mine_type":"DeployedMine", "position":controller["position"], "owner_faction_id":"player", "operation_state":"Active", "known_by_faction":["player"], "trigger_radius":18.0, "detection_distance":75.0, "damage_reference":rules["damage_reference"].duplicate(true)}
	var trigger: Dictionary = session.minefield_service.resolve_unit_motion(controller, controller["position"], controller["position"])
	_check(trigger.get("triggered", false) and trigger.get("minefield_id") == friendly_mine_id, "deployed mines trigger friendly ships without faction exemption")
	session._event_buffer.clear()
	session._apply_mine_trigger(controller, trigger)
	var damage_result: Dictionary = _event(session._event_buffer, "AttackResolved").get("damage_result", {})
	var torpedo_formula: Dictionary = registry.get_definition("formulas", "formula.surface_torpedo")
	var shimakaze: Dictionary = registry.get_definition("ships", "ship.shimakaze")
	var expected_raw := float(torpedo_formula["base_damage"]) + float(shimakaze["torpedo_power"]) * float(torpedo_formula["power_coefficient"])
	_check(damage_result.get("source_weapon_id") == "weapon.shimakaze_610_torpedo" and damage_result.get("hit_reason") == "MINE_TRIGGER" and is_equal_approx(float(damage_result.get("raw_damage", 0.0)), expected_raw) and float(damage_result.get("armor_reduction", -1.0)) >= 0.0, "mine contact enters the referenced torpedo power, formula, and armor pipeline")

	facility["cooldown_remaining"] = 0.0
	facility["remote_charges_remaining"] = 1
	var cancel_request: Dictionary = session.facility_service.request_mine_deployment(facility_id, controller, target, 30.0, session.state["units_by_id"], 101)
	_check(cancel_request.get("accepted", false), "second deployment can start for interruption validation")
	session.facility_service.suppress(facility_id, 5.0, "test")
	_check(_has_event(session.facility_service.advance(0.1, 30.1, session.state["units_by_id"]), "MineDeploymentCancelled"), "suppression cancels an in-progress deployment")
	var independent_state := str(session.minefield_service.minefields_by_id[mine_id].get("operation_state", ""))
	session.facility_service.apply_damage(facility_id, 100000.0, "test")
	session.minefield_service.sync_controllers(session.facility_service.facilities_by_id)
	_check(str(session.minefield_service.minefields_by_id[mine_id].get("operation_state", "")) == independent_state, "controller loss does not clear independently deployed mines")

	if failures.is_empty():
		print("PASS: %d mine-control station checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error("FAIL: %s" % failure)
		print("FAILED: %d of %d mine-control station checks" % [failures.size(), checks])
		quit(1)


func _event(events: Array, event_type: String) -> Dictionary:
	for event in events:
		if event.get("event_type", "") == event_type: return event
	return {}


func _has_event(events: Array, event_type: String) -> bool:
	return not _event(events, event_type).is_empty()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
