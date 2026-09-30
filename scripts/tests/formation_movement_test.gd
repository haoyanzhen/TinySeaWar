extends SceneTree

const Registry = preload("res://scripts/infrastructure/data/config_registry.gd")
const Session = preload("res://scripts/application/battle_session.gd")
const Formation = preload("res://scripts/application/navigation/formation_movement.gd")
const Planner = preload("res://scripts/application/navigation/trajectory_planner.gd")
var checks := 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)

func run() -> void:
	var registry = Registry.new()
	check(registry.load_all(), "registry loads")
	var members: Array = [{"id":"c", "position":Vector2(0, 200), "extent":50.0}, {"id":"a", "position":Vector2(0, 0), "extent":30.0}, {"id":"b", "position":Vector2(0, 100), "extent":40.0}]
	var slots := Formation.allocate(members, Vector2(1000, 100), func(_id, _point): return true)
	check(slots.size() == 3, "three distinct arrival slots")
	check(slots.a.y < slots.b.y and slots.b.y < slots.c.y, "spatial order wins over selection order")
	members.reverse()
	check(Formation.allocate(members, Vector2(1000, 100), func(_id, _point): return true) == slots, "selection order does not change destinations")
	var shore := Formation.allocate(members, Vector2(1000, 100), func(_id, point): return point.x <= 800)
	check(shore.size() == 3, "shore slots fall back behind destination")
	for id in shore:
		check(shore[id].x <= 800, "fallback obeys occupancy")
		for other in shore:
			if str(id) < str(other): check(shore[id].distance_to(shore[other]) >= 128.0, "fallback slots retain hull clearance")
	check(Formation.allocate(members, Vector2.ZERO, func(_id, _point): return false).is_empty(), "blocked allocation terminates without unsafe fallback")
	for formation in ["Screen", "Column", "Wedge", "LineAbreast", "Dispersed"]:
		var unique := {}
		for index in range(4): unique[Formation.slot_offset(formation, index, 4, 150.0)] = true
		check(unique.size() == 4, "%s has four unique slots" % formation)
	_test_orders(registry)
	_test_following()
	_test_group_frame(registry)
	if failures.is_empty(): print("PASS: %d formation movement checks" % checks)
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _test_orders(registry) -> void:
	var session = Session.new(registry)
	session.create_battle("level.prototype_3v3", 8412)
	var ids: Array = []
	for id in session._sorted_unit_ids():
		if session.state.units_by_id[id].faction_id == "player": ids.append(id)
	var target := Vector2(1400, 900)
	var result: Dictionary = session._apply_command({"command_type":"MoveUnits", "issuer_id":"player", "unit_ids":ids, "target_position":target})
	check(result.accepted, "group command accepted")
	var endpoints := {}
	for id in ids:
		var unit: Dictionary = session.state.units_by_id[id]
		endpoints[unit.player_route_waypoints[0]] = true
		check(unit.navigation_state.formation_move.center == target, "clicked center is preserved separately")
	check(endpoints.size() == ids.size(), "group endpoints never collapse")
	check(session.navigation_request_broker.pending_count() == 3, "each member keeps an independent Broker request")
	session._update_navigation_requests()
	check(session.navigation_request_broker.pending_count() == 2, "one strategic request per tick")
	var single_target := Vector2(1300, 1000)
	session._apply_command({"command_type":"MoveUnits", "issuer_id":"player", "unit_id":ids[0], "target_position":single_target})
	check(session.state.units_by_id[ids[0]].player_route_waypoints == [single_target], "single command retains exact endpoint")
	check(not session.state.units_by_id[ids[0]].navigation_state.has("formation_move"), "new single order releases formation state")
	var enemy: Dictionary = session.state.units_by_id["unit.enemy.bismarck"]
	var before: Dictionary = enemy.movement_state.duplicate(true)
	result = session._apply_command({"command_type":"MoveUnits", "issuer_id":"player", "unit_ids":[ids[0], enemy.entity_id, ids[0]], "target_position":single_target})
	check(enemy.movement_state == before and result.rejected_unit_ids == [enemy.entity_id], "group allocation cannot control enemies")
	check(result.successful_unit_ids == [ids[0]], "duplicate member receives only one command")
	# An occupied endpoint must not be allocated through hidden enemy facts.
	var unit: Dictionary = session.state.units_by_id[ids[0]]
	enemy.position = target
	for id in ids: session.state.units_by_id[id].position = Vector2(500, 500)
	check(session._formation_endpoint_clear(str(unit.entity_id), target, {ids[0]:true, ids[1]:true, ids[2]:true}), "hidden enemy cannot influence destination allocation")
	check(not session._formation_endpoint_clear(str(unit.entity_id), Vector2(1, 1), {}), "map-edge endpoint includes hull radius")
	var ally: Dictionary = session.state.units_by_id[ids[1]]
	ally.player_route_waypoints = [target]
	check(not session._formation_endpoint_clear(str(unit.entity_id), target, {ids[0]:true, ids[2]:true}), "other friendly order reserves its arrival point")

func _test_following() -> void:
	var planner = Planner.new()
	var motion := {"position":Vector2(500, 500), "heading":0.0, "speed":50.0, "maximum_speed":80.0, "braking":160.0, "collision_half_extents":Vector2(40, 20), "current_vector":Vector2.ZERO}
	var front := {"position":Vector2(680, 500), "heading":0.0, "velocity":Vector2(20, 0), "half_extents":Vector2(40, 20), "friendly":true, "navigating":true}
	var limit: float = planner._following_thrust_limit(motion, Vector2(1500, 500), 30, [front])
	check(limit > 0.0 and limit < 0.5, "fast follower slows before catching slower front ship")
	motion.acceleration = 80.0
	motion.turn_rate_limit = 0.5
	var plan: Dictionary = planner.plan_normal(motion, Vector2(1500, 500), 30, [], null, null, [front], false, [], true)
	check(bool(plan.get("ok", false)), "following produces a validated trajectory")
	check(plan.get("predicted_samples", []).size() == 61, "following preserves full six-second horizon")
	var bounded := true
	for control in plan.get("prediction_controls", []): bounded = bounded and float(control.thrust_ratio) <= limit + 0.0001
	check(bounded and int(plan.get("candidate_count", 0)) <= 6, "following cap enters simulation without adding candidates")
	front.position = Vector2(680, 800)
	check(planner._following_thrust_limit(motion, Vector2(1500, 500), 30, [front]) == 1.0, "parallel lane does not limit speed")
	front.position = Vector2(450, 500)
	check(planner._following_thrust_limit(motion, Vector2(1500, 500), 30, [front]) == 1.0, "ship behind does not limit speed")
	front.position = Vector2(680, 500)
	front.heading = PI
	check(planner._following_thrust_limit(motion, Vector2(1500, 500), 30, [front]) == 1.0, "head-on uses ordinary avoidance")
	front.heading = 0.0
	front.navigating = false
	check(planner._following_thrust_limit(motion, Vector2(1500, 500), 30, [front]) == 1.0, "stopped destination occupant permits passing")
	front.navigating = true
	front.friendly = false
	check(planner._following_thrust_limit(motion, Vector2(1500, 500), 30, [front]) == 1.0, "enemy cannot impose friendly following")

func _test_group_frame(registry) -> void:
	var session = Session.new(registry)
	session.create_battle("level.prototype_3v3", 8412)
	var group: Dictionary = session.state.ai_groups_by_faction.enemy.values()[0]
	check(session.state.units_by_id[group.leader_unit_id].ai_state.formation_slot_index == 0, "leader owns center slot")
	var unit: Dictionary = session.state.units_by_id[group.member_ids[1]]
	var base := Vector2(1500, 900)
	var first: Vector2 = session._apply_group_formation(unit, {"position":Vector2(100, 100)}, base)
	var second: Vector2 = session._apply_group_formation(unit, {"position":Vector2(2000, 2000)}, base)
	check(first == second, "member target changes cannot rotate shared formation")
	check(first.distance_to(base) <= 60.01, "elastic correction is bounded")
	var previous_heading := float(group.heading)
	var leader: Dictionary = session.state.units_by_id[group.leader_unit_id]
	leader.movement_state = session._new_movement_state("AutoNavigate", leader.position + Vector2.LEFT * 1000.0, [leader.position + Vector2.LEFT * 1000.0])
	session.state.elapsed_time += 1.0
	session._rebuild_ai_groups("enemy")
	group = session.state.ai_groups_by_faction.enemy.values()[0]
	check(absf(angle_difference(previous_heading, float(group.heading))) <= PI / 12.0 + 0.001, "shared travel frame turns gradually")
