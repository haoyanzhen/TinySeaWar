extends SceneTree
const Registry = preload("res://scripts/infrastructure/data/config_registry.gd")
const Session = preload("res://scripts/application/battle_session.gd")
var failures: Array[String] = []
var checks := 0
func _init(): call_deferred("run")
func check(value: bool, label: String):
	checks += 1
	if not value: failures.append(label)
func run():
	var registry = Registry.new()
	check(registry.load_all(), "registry loads")
	for scenario in ["capture", "relay", "supply", "repair"]:
		var session = Session.new(registry)
		session.create_battle("level.prototype_harbor_3v3", 42023)
		var facility_id: String = {"relay":"facility.harbor.communication_east", "capture":"facility.harbor.observation_west", "supply":"facility.harbor.supply_west", "repair":"facility.harbor.repair_berth_east"}[scenario]
		var facility: Dictionary = session.facility_service.facilities_by_id[facility_id]
		var center: Vector2 = session.facility_service.interaction_center(facility_id)
		var level: Dictionary = registry.get_definition("levels", "level.prototype_harbor_3v3").duplicate(true)
		level.erase("require_equal_fleet_cost")
		level.player_fleet = [level.player_fleet[0]]
		level.enemy_fleet = [level.enemy_fleet[0]]
		var start := center + Vector2(350,0)
		for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
			var candidate: Vector2 = center + direction * 350.0
			if session.terrain_query.is_navigation_segment_clear(candidate, center, 20.0, ["Surface","ShallowDraft"]): start = candidate; break
		level.player_fleet[0].position = [start.x, start.y]
		level.player_fleet[0].heading = rad_to_deg((center-start).angle())
		level.player_fleet[0].initial_hp_ratio = 0.4 if scenario == "repair" else 1.0
		level.enemy_fleet[0].position = [5700,3000]
		check(session.create_battle_from_definition(level, 42023).get("ok", false), scenario + " fixture starts")
		# Controlled fixture: one published facility, an idle distant opposing flagship,
		# all motion and interactions run through normal fixed ticks after initialization.
		facility = session.facility_service.facilities_by_id[facility_id]
		if scenario in ["supply", "repair"]: facility.faction_id = "player"; facility.operation_state = "Active"; facility.desired_operation_state = "Active"
		var kept := {facility_id:facility}
		if scenario == "relay":
			for id in ["facility.harbor.radar_east", "facility.harbor.airfield_east", "facility.harbor.battery_west"]: kept[id] = session.facility_service.facilities_by_id[id]
		session.facility_service.facilities_by_id = kept
		session.facility_service.activation_events.clear()
		session.minefield_service.minefields_by_id.clear()
		session.state.minefields_by_id = {}
		session.state.facilities_by_id = session.facility_service.snapshot()
		session.configure_full_ai_factions(["player"])
		var unit: Dictionary = session.state.units_by_id[level.player_fleet[0].entity_id]
		var enemy: Dictionary = session.state.units_by_id[level.enemy_fleet[0].entity_id]
		enemy.movement_assist_enabled = false
		unit.skill_state.cooldown_remaining = 100.0
		var completed := false
		var rejections := 0
		var collisions := 0
		var benefit := 0.0
		for tick in range(1600):
			for event in session.advance_tick(0.1):
				var kind := str(event.get("event_type", ""))
				if kind == "CommandRejected": rejections += 1
				if kind in ["TerrainCollision", "NavigationCollisionContractViolated"]: collisions += 1
				if kind == ("FacilityControlCompleted" if scenario in ["capture", "relay"] else "UnitServiced"):
					completed = true
					benefit = float(event.get("hp_restored", event.get("skill_cooldown_recovered", 0)))
			if completed: break
		check(completed, scenario + " navigation and interaction complete")
		check(rejections == 0, scenario + " does not spam rejected commands")
		check(collisions == 0, scenario + " respects collision rules")
		if scenario in ["supply", "repair"]: check(benefit > 0.0, scenario + " grants actual benefit")
		if scenario == "relay":
			check(session.facility_service.facilities_by_id["facility.harbor.airfield_east"].faction_id == "player", "normal ticks hand captured airport to player")
			var airport: Dictionary = session.facility_service.facilities_by_id["facility.harbor.airfield_east"]
			var command := {"command_id":"test.captured_airport", "issued_at_tick":session.state.tick_index + 1, "issuer_type":"Player", "command_type":"RequestSupportMission", "issuer_id":"player", "unit_id":unit.entity_id, "facility_id":airport.facility_id, "mission_definition_id":"support_mission.air_recon", "target_position":airport.position}
			check(session.queue_command(command).get("accepted", false), "player can order captured airport")
			var resolved := false
			for tick in range(250):
				for event in session.advance_tick(0.1):
					if event.get("event_type") == "SupportMissionResolved": resolved = true
			check(resolved, "captured airport delivers actual reconnaissance")
		print("EXECUTION ", scenario, " completed=", completed, " seconds=", session.state.elapsed_time, " benefit=", benefit, " rejected=",rejections, " position=",unit.position," heading=",rad_to_deg(float(unit.heading))," task=",unit.ai_state.get("level_task"))
	for failure in failures: push_error(failure)
	print("FACILITY EXECUTION ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
