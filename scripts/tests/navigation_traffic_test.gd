extends SceneTree
const Registry = preload("res://scripts/infrastructure/data/config_registry.gd")
const Session = preload("res://scripts/application/battle_session.gd")
const Planner = preload("res://scripts/application/navigation/trajectory_planner.gd")
const Recorder = preload("res://scripts/infrastructure/analytics/battle_recorder.gd")
const Aggregator = preload("res://scripts/infrastructure/simulation/simulation_aggregator.gd")
var checks := 0
var failures: Array[String] = []

class DeniedWater extends "res://scripts/domain/services/terrain_context_service.gd":
	func movement_segment_access(_start: Vector2, _end: Vector2) -> Dictionary:
		return {"allowed":false, "zone_id":"fixture.closed", "reason_code":"WATER_ACCESS"}

func _init() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func run() -> void:
	var registry = Registry.new()
	check(registry.load_all(), "registry loads")
	var session = Session.new(registry)
	check(session.create_battle("level.prototype_3v3", 8412).get("ok", false), "traffic fixture starts")
	var units: Array = session.state.units_by_id.values()
	var first: Dictionary = units[0]
	var second: Dictionary = units[1]
	second.faction_id = first.faction_id
	first.position = Vector2(600, 600)
	second.position = Vector2(620, 600)
	var center := Vector2(1200, 600)
	var a: Vector2 = session._contact_search_station(first, center)
	var b: Vector2 = session._contact_search_station(second, center)
	var required: float = session._unit_collision_half_extents(first).x + session._unit_collision_half_extents(second).x + 24.0
	check(a.distance_to(b) >= required - 0.01, "shared ghost allocates disjoint hull envelopes")
	check(session._contact_search_station(first, center + Vector2(10, 0)) == a, "small ghost changes preserve station")
	session._queue_ai_move(first, center + Vector2(0, 500))
	check(not first.ai_state.has("contact_search_station"), "tactical takeover releases station")
	var hidden: Dictionary = units[-1]
	hidden.faction_id = "enemy" if first.faction_id == "player" else "player"
	hidden.position = first.position + Vector2(100, 0)
	session.state.visible_by_faction[first.faction_id] = {}
	check(not session._nearby_navigation_units(first).any(func(item): return item.id == hidden.entity_id), "hidden enemies are not dynamic obstacles")
	session.state.visible_by_faction[first.faction_id][hidden.entity_id] = true
	check(session._nearby_navigation_units(first).any(func(item): return item.id == hidden.entity_id), "visible enemies supply observed motion")
	_test_dynamic_geometry()
	_test_recorder()
	_test_water_rejection(registry)
	_test_head_on(registry)
	_test_occupied_endpoint(registry)
	if failures.is_empty():
		print("PASS: %d navigation traffic checks" % checks)
		quit()
	else:
		for failure in failures: push_error(failure)
		quit(1)

func _test_dynamic_geometry() -> void:
	var planner = Planner.new()
	var initial := {"position":Vector2.ZERO, "heading":0.0, "collision_half_extents":Vector2(70, 30)}
	var other := {"id":"other", "position":Vector2(100, 0), "heading":0.0, "half_extents":Vector2(50, 20), "radius":15.0}
	check(planner._dynamic_pose_collision({"position":Vector2(1,0), "heading":0.0}, initial, 30.0, [other], {}), "ellipse rejects deepening overlap missed by circles")
	check(not planner._dynamic_pose_collision({"position":Vector2(-1,0), "heading":0.0}, initial, 30.0, [other], {}), "existing overlap can monotonically escape")
	var penetration := {}
	planner._dynamic_pose_collision({"position":Vector2(-30,0), "heading":0.0}, initial, 30.0, [other], penetration)
	check(planner._dynamic_pose_collision({"position":Vector2.ZERO, "heading":0.0}, initial, 30.0, [other], penetration), "escaped overlap cannot re-enter")
	other.position = Vector2(180, 0)
	other.velocity = Vector2(100, 0)
	check(not planner._dynamic_pose_collision({"position":Vector2(150,0), "heading":0.0, "tick_offset":2.0}, initial, 30.0, [other], {}), "moving traffic vacates its old position")
	other.velocity = Vector2(-50, 0)
	check(planner._dynamic_pose_collision({"position":Vector2(30,0), "heading":0.0, "tick_offset":2.0}, initial, 30.0, [other], {}), "future crossing is rejected")
	var samples := [{"position":Vector2.ZERO, "tick_offset":0.0}, {"position":Vector2(30,0), "tick_offset":2.0}]
	check(planner._dynamic_candidate_units(samples, initial, 30.0, [other]).size() == 1, "swept broad phase retains a moving crossing")
	other.position = Vector2(500, 500)
	check(planner._dynamic_candidate_units(samples, initial, 30.0, [other]).is_empty(), "swept broad phase excludes disjoint motion envelopes")

func _test_recorder() -> void:
	var recorder = Recorder.new()
	recorder.reset("traffic", 1)
	recorder.consume([{"event_type":"NavigationSeparationApplied", "distance":2.5, "allowed":true}, {"event_type":"NavigationSeparationApplied", "distance":0.0, "allowed":false}, {"event_type":"UnitTideAccessRestricted"}, {"event_type":"NavigationStalled"}], 1.0)
	check(recorder.summary.navigation.separation_distance == 2.5, "recorder sums executed separation only")
	check(recorder.summary.navigation.separation_rejected == 1, "blocked separation is distinct")
	check(recorder.summary.navigation.event_counts.UnitTideAccessRestricted == 1, "water access failures counted")
	check(recorder.summary.ai_behavior.navigation_events.size() == 2, "water/stall facts kept without per-tick separation bloat")
	var aggregate: Dictionary = Aggregator.new().aggregate([{"end_state":"MaximumTicks", "navigation":recorder.summary.navigation}])
	check(aggregate.navigation_all_attempts.event_counts.UnitTideAccessRestricted == 1 and aggregate.navigation_invalid_attempts.separation_rejected == 1, "invalid battles retain navigation counters")

func _test_head_on(registry) -> void:
	var session = Session.new(registry)
	session.create_battle("level.prototype_3v3", 8412)
	session._full_ai_factions.clear()
	var units: Array = session.state.units_by_id.values()
	var moving: Array = [units[0], units[1]]
	for unit in units:
		unit.primary_auto_fire_enabled = false
		unit.secondary_auto_fire_enabled = false
		unit.skill_auto_cast_enabled = false
		unit.position = Vector2(2500, 1600)
	var targets: Array = [Vector2(1600, 600), Vector2(600, 600)]
	for index in range(2):
		var unit: Dictionary = moving[index]
		unit.position = Vector2(600 if index == 0 else 1600, 600)
		unit.heading = 0.0 if index == 0 else PI
		unit.current_speed = 0.0
		unit.faction_id = "player"
		unit.movement_state = session._new_movement_state("PlayerMoveOrder", targets[index], [targets[index]])
	var push_distance := 0.0
	for tick in range(1200):
		session.state.tick_index += 1
		session.state.elapsed_time += 0.1
		session._update_navigation_plans()
		session._update_movement(0.1)
		session._resolve_unit_overlap()
		for unit in moving: session._update_navigation_progress(unit, 0.1)
		if moving.all(func(unit): return unit.movement_state.mode == "HoldPosition"): break
	for index in range(2):
		var unit: Dictionary = moving[index]
		push_distance += float(unit.navigation_state.get("separation_distance", 0.0))
		check((unit.position as Vector2).distance_to(targets[index]) <= session.trajectory_planner.arrival_tolerance(float(unit.stats.collision_radius)), "head-on ship %d arrives" % index)
	print("HEAD_ON %.1fs, separation %.3f" % [session.state.elapsed_time, push_distance])
	check(push_distance < 0.001, "head-on ships pass without authoritative pushes")

func _test_water_rejection(registry) -> void:
	var session = Session.new(registry)
	session.create_battle("level.prototype_1v1", 1)
	session.terrain_context_service = DeniedWater.new()
	var unit: Dictionary = session.state.units_by_id.values()[0]
	var start: Vector2 = unit.position
	unit.current_speed = 20.0
	unit.navigation_state.trajectory_plan = {"ok":true, "environment_revision":session.terrain_context_service.environment_revision, "tide_phase_index":session.terrain_context_service.tide_phase_index, "planned_at_tick":0, "valid_until_tick":10}
	unit.navigation_state.current_control = {"thrust_ratio":1.0, "turn_ratio":0.0}
	session._event_buffer.clear()
	session._update_movement(0.1)
	check(unit.position == start and unit.current_speed == 0.0, "unconfigured terrain still respects water denial")
	check(unit.navigation_state.trajectory_plan.is_empty() and unit.navigation_state.current_control.thrust_ratio == 0.0, "water denial invalidates plan and control")
	check(unit.navigation_state.next_normal_plan_tick == session.state.tick_index + 1, "water denial schedules next-tick replan")
	check(session._event_buffer.any(func(event): return event.event_type == "NavigationCollisionContractViolated" and event.get("reason_code", "") == "WATER_ACCESS"), "same revision water inconsistency is recorded")
	check(not session._navigation_plan_is_committed({"ok":true, "planned_at_tick":-20, "valid_until_tick":-10}), "expired plan is not a same-plan collision violation")
	unit.navigation_state.trajectory_plan = {"ok":true, "environment_revision":session.terrain_context_service.environment_revision, "tide_phase_index":session.terrain_context_service.tide_phase_index + 1, "planned_at_tick":0, "valid_until_tick":10}
	session._event_buffer.clear()
	session._update_movement(0.1)
	check(not session._event_buffer.any(func(event): return event.event_type == "NavigationCollisionContractViolated"), "a changed tide phase is not a same-state prediction violation")

func _test_occupied_endpoint(registry) -> void:
	var session = Session.new(registry)
	session.create_battle("level.prototype_3v3", 8412)
	session._full_ai_factions.clear()
	var units: Array = session.state.units_by_id.values()
	var unit: Dictionary = units[0]
	var blocker: Dictionary = units[1]
	for other in units:
		if other != unit and other != blocker: other.life_state = "Sunk"
	unit.position = Vector2(700, 600)
	unit.heading = 0.0
	unit.current_speed = 0.0
	blocker.position = Vector2(1000, 600)
	blocker.heading = PI * 0.5
	blocker.current_speed = 0.0
	blocker.faction_id = unit.faction_id
	blocker.movement_state = session._new_movement_state("HoldPosition", blocker.position, [])
	var target: Vector2 = blocker.position
	unit.movement_state = session._new_movement_state("PlayerMoveOrder", target, [target])
	for tick in range(1200):
		if tick == 200:
			check(unit.movement_state.mode == "PlayerMoveOrder" and unit.movement_state.target_position == target, "occupied explicit endpoint remains pending, not falsely completed or moved")
			var departure: Vector2 = blocker.position + Vector2(0, 500)
			blocker.movement_state = session._new_movement_state("PlayerMoveOrder", departure, [departure])
			session._mark_navigation_dirty(blocker)
		session.state.tick_index += 1
		session.state.elapsed_time += 0.1
		session._update_navigation_plans()
		session._update_movement(0.1)
		session._resolve_unit_overlap()
		for other in [unit, blocker]: session._update_navigation_progress(other, 0.1)
		if tick > 200 and unit.movement_state.mode == "HoldPosition": break
	check((unit.position as Vector2).distance_to(target) <= session.trajectory_planner.arrival_tolerance(float(unit.stats.collision_radius)), "explicit endpoint arrives after blocker leaves")
	print("OCCUPIED_ENDPOINT %.1fs, separation %.3f" % [session.state.elapsed_time, float(unit.navigation_state.get("separation_distance", 0.0))])
