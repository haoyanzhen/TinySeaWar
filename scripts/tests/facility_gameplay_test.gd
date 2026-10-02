extends SceneTree
const Registry = preload("res://scripts/infrastructure/data/config_registry.gd")
const Session = preload("res://scripts/application/battle_session.gd")
var registry
var checks := 0
var failures: Array[String] = []
func _init(): call_deferred("run")
func check(value: bool, label: String):
	checks += 1
	if not value: failures.append(label)
func fresh():
	var session = Session.new(registry)
	check(session.create_battle("level.prototype_harbor_3v3", 42022).get("ok", false), "harbor creates")
	return session
func has(events: Array, kind: String) -> bool:
	return events.any(func(e): return e.get("event_type", "") == kind)
func run():
	registry = Registry.new()
	check(registry.load_all(), "definitions load")
	var session = fresh()
	var service = session.facility_service
	var radar_id := "facility.harbor.radar_east"
	check(not has(service.advance(29.9, 29.9, session.state.units_by_id), "FacilityActivated"), "radar does not start early")
	check(has(service.advance(0.1, 30.0, session.state.units_by_id), "FacilityActivated") and service.radar_sources("enemy").size() == 1, "radar starts at public 30 second boundary")
	check(not has(service.advance(1.0, 31.0, session.state.units_by_id), "FacilityActivated"), "radar activation emits once")
	var player: Dictionary = session.state.units_by_id["unit.player.shimakaze"]
	var relay_id := "facility.harbor.communication_east"
	player.position = service.interaction_center(relay_id)
	check(service.declare_control(relay_id, player).get("accepted", false), "relay capture starts")
	var events: Array = service.advance(6.1, 37.1, session.state.units_by_id)
	for event in events: session._handle_facility_event(event)
	check(has(events, "FacilitySystemHandedOver"), "authored capture triggers system handover")
	for fid in ["facility.harbor.battery_west", "facility.harbor.airfield_east", radar_id]:
		check(service.facilities_by_id[fid].faction_id == "player" and service.is_operational(fid), "capture grants operational " + fid)
	check(service.radar_sources("enemy").is_empty() and service.radar_sources("player").size() == 1, "radar intelligence changes recipient")
	var airfield_id := "facility.harbor.airfield_east"
	var target: Vector2 = service.facilities_by_id[airfield_id].position + Vector2(-300, 0)
	check(service.request_support(airfield_id, "support_mission.air_recon", "player", target, 37.1).get("accepted", false), "captured airport accepts player mission")
	var enemy: Dictionary = session.state.units_by_id["unit.enemy.kirov"]
	enemy.position = player.position
	player.position += Vector2(-700, 0)
	check(service.declare_control(relay_id, enemy).get("accepted", false), "enemy can recapture relay")
	events = service.advance(6.1, 43.2, session.state.units_by_id)
	check(has(events, "FacilitySystemHandedOver") and service.facilities_by_id[airfield_id].faction_id == "enemy", "recapture restores the defensive system")
	check(has(events, "SupportMissionCancelled"), "handover cancels old-owner preparing mission")
	# Generic layouts retain manual handover semantics and reject malformed schedules.
	var layout: Dictionary = registry.get_definition("facilities", "facility.layout.harbor_mouth_16x9").duplicate(true)
	for mode in ["negative", "missing", "event", "duplicate"]:
		var invalid := layout.duplicate(true)
		match mode:
			"negative": invalid.activation_events[0].at_seconds = -1
			"missing": invalid.activation_events[0].facility_id = "missing"
			"event": invalid.activation_events[0].event_id = "wrong"
			"duplicate": invalid.activation_events.append(invalid.activation_events[0].duplicate())
		var before: int = registry.errors.size()
		registry._validate_facility_definition(invalid)
		check(registry.errors.size() > before, "reject invalid activation " + mode)
	registry.errors.clear()
	# Basic AI keeps travel tasks, never selects a locked battery, and can use supply.
	session = fresh()
	player = session.state.units_by_id["unit.player.shimakaze"]
	session.configure_full_ai_factions(["player", "enemy"])
	session._ai_observations_by_faction.clear()
	var plan: Dictionary = session._ai_facility_plan(player, true)
	check(not plan.is_empty() and str(player.ai_state.task_target_ref.get("facility_id", "")) != "facility.harbor.battery_west", "AI chooses a legal facility")
	var chosen := str(player.ai_state.task_target_ref.get("facility_id", ""))
	check(float(player.ai_state.get("task_timeout", 0)) > 12.0, "travel budget includes navigation before interaction")
	check(not session._ai_facility_plan(player, false).is_empty() and str(player.ai_state.task_target_ref.get("facility_id", "")) == chosen, "new contact does not discard committed approach")
	session._clear_ai_facility_task(player)
	player.current_hp = player.max_hp * 0.2
	var replacement_found := false
	for ally in session.state.units_by_id.values():
		if ally.faction_id == "player" and ally.entity_id != player.entity_id and session._facility_capture_slot_available(ally): replacement_found = true
	check(replacement_found, "injured fastest runner does not block another healthy ship from capturing")
	player.current_hp = player.max_hp
	var supply_id := "facility.harbor.supply_west"
	var supply: Dictionary = session.facility_service.facilities_by_id[supply_id]
	supply.faction_id = "player"; supply.desired_operation_state = "Active"; supply.operation_state = "Active"
	player.position = session.facility_service.interaction_center(supply_id)
	player.current_speed = 0.0; player.heading = deg_to_rad(float(supply.heading)); player.skill_state.cooldown_remaining = 50.0
	session._clear_ai_facility_task(player)
	session.state.facilities_by_id = session.facility_service.snapshot()
	session._ai_observations_by_faction.clear()
	plan = session._ai_facility_plan(player, false)
	check(plan.get("action_type") == "Service" and plan.get("facility_id") == supply_id, "AI requests useful nearby supply")
	session._queue_ai_facility_action(player, supply_id, "Service")
	session._process_commands()
	events = session.facility_service.advance(7.1, 7.1, session.state.units_by_id)
	for event in events: session._handle_facility_event(event)
	check(has(events, "FacilityServiceCompleted") and is_equal_approx(float(player.skill_state.cooldown_remaining), 38.0), "AI supply creates cooldown benefit")
	# Repair cannot reduce a healthy unit's HP, and cancel releases the berth.
	var repair_id := "facility.harbor.repair_berth_east"
	var repair: Dictionary = session.facility_service.facilities_by_id[repair_id]
	repair.faction_id = "player"; repair.desired_operation_state = "Active"; repair.operation_state = "Active"
	player.position = session.facility_service.interaction_center(repair_id); player.heading = deg_to_rad(float(repair.heading)); player.current_speed = 0
	player.current_hp = player.max_hp
	session._apply_facility_service({"unit_id":player.entity_id, "facility_id":repair_id, "service_type":"Repair", "service_rules":session.facility_service.definition_for(repair_id).berthing_service})
	check(player.current_hp == player.max_hp, "repair cap does not damage a healthy ship")
	check(session._apply_command({"command_type":"RequestFacilityService", "issuer_id":"player", "unit_id":player.entity_id, "facility_id":repair_id}).get("accepted", false), "repair begins through shared command")
	check(session._apply_command({"command_type":"CancelFacilityAction", "issuer_id":"player", "unit_id":player.entity_id, "facility_id":repair_id}).get("accepted", false) and player.movement_state.mode != "Docked", "cancel command releases docked movement")
	for failure in failures: push_error(failure)
	print("FACILITY GAMEPLAY ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
