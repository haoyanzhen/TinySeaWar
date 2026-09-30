extends SceneTree
const Registry = preload("res://scripts/infrastructure/data/config_registry.gd")
const Session = preload("res://scripts/application/battle_session.gd")
const Column = preload("res://scripts/application/navigation/column_transit.gd")
const Planner = preload("res://scripts/application/navigation/trajectory_planner.gd")
var checks := 0
var failures: Array[String] = []

func _init() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func run() -> void:
	var registry = Registry.new()
	check(registry.load_all(), "registry loads")
	_test_prediction(registry)
	_test_trail()
	_test_lifecycle(registry)
	var results: Array = []
	for scenario in ["neck3", "bend3", "neck11"]:
		if "--neck11" in OS.get_cmdline_user_args() and scenario != "neck11": continue
		results.append(_transit(registry, scenario))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			FileAccess.open(argument.trim_prefix("--output="), FileAccess.WRITE).store_string(JSON.stringify(results, "\t"))
	for failure in failures: push_error(failure)
	print("%s: %d column transit and committed prediction checks" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)

func _test_prediction(registry) -> void:
	var planner = Planner.new()
	var other := {"friendly":true, "position":Vector2(100,100), "heading":0.0, "velocity":Vector2(100,0), "half_extents":Vector2(20,10), "committed_samples":[{"position":Vector2(100,100),"heading":0.0,"speed":100.0,"tick_offset":0.0}, {"position":Vector2(105,105),"heading":PI/2,"speed":0.0,"tick_offset":0.1}]}
	check(planner._neighbor_pose(other, 0.1).position == Vector2(105,105), "committed turn replaces straight extrapolation")
	check(planner._neighbor_pose(other, 0.1).heading == PI/2, "committed hull rotation is used")
	check(planner._neighbor_pose(other, 2.0).position == Vector2(105,105), "post-commit extrapolation starts at stopped tail")
	check(planner._neighbor_pose(other, 2.0).margin > 0, "post-commit uncertainty expands envelope")
	other.erase("_pose_cache")
	other.friendly = false
	check(planner._neighbor_pose(other, 0.1).position == Vector2(110,100), "enemy never supplies future plan")
	other.erase("_pose_cache")
	other.friendly = true
	other.committed_samples[1].position = Vector2(100,200)
	other.committed_samples[1].speed = 100.0
	var candidates: Array = planner._dynamic_candidate_units([{"position":Vector2(100,200)}, {"position":Vector2(100,200),"tick_offset":0.1}], {"collision_half_extents":Vector2(20,10)}, 20, [other])
	check(candidates.size() == 1, "broad phase retains curved committed path")
	var session = Session.new(registry)
	session.create_battle("level.prototype_3v3", 8412)
	session._full_ai_factions.clear()
	var unit: Dictionary = session.state.units_by_id["unit.player.shimakaze"]
	unit.position = Vector2(500,500)
	unit.heading = 0.0
	unit.current_speed = 0.0
	unit.movement_state = session._new_movement_state("PlayerMoveOrder", Vector2(1500,500), [Vector2(1500,500)])
	session._plan_normal_trajectory(unit)
	var samples: Array = session._friendly_committed_samples(unit)
	check(samples.size() == 11, "only one committed second is published")
	unit.navigation_state.trajectory_dirty = true
	check(session._friendly_committed_samples(unit).is_empty(), "dirty plan cannot be shared")
	unit.navigation_state.trajectory_dirty = false
	unit.position += Vector2(1,0)
	check(session._friendly_committed_samples(unit).is_empty(), "displaced ship invalidates shared prediction")
	unit.position -= Vector2(1,0)
	unit.navigation_state.trajectory_plan.environment_revision -= 1
	check(session._friendly_committed_samples(unit).is_empty(), "environment revision invalidates prediction")
	unit.navigation_state.trajectory_plan.environment_revision += 1
	session.state.tick_index = 10
	check(session._friendly_committed_samples(unit).is_empty(), "expired commitment is not a six-second promise")

func _test_trail() -> void:
	var trail: Array = []
	for position in [Vector2(100,100), Vector2(200,100), Vector2(200,200), Vector2(300,200)]: Column.record(trail, position, 0)
	var guidance := Column.follow(trail, Vector2(140,100), 50, 0, 40)
	check(guidance.goal == Vector2(200,100), "follower targets corner instead of cutting bend")
	check(Column.point_at(trail,150) == Vector2(200,150), "trail uses travelled distance through bend")
	for index in range(600): Column.record(trail,Vector2(310+index*10,200),0)
	check(trail.size() == Column.TRAIL_LIMIT, "trail memory is bounded")
	var waiting := Column.follow(trail, trail[-1].position, 120, float(trail[-1].distance), 40)
	check(waiting.waiting and waiting.goal == trail[-1].position, "headway wait never pulls follower backward")

func _test_lifecycle(registry) -> void:
	var session = Session.new(registry)
	session.create_battle("level.prototype_3v3",8412)
	session._full_ai_factions.clear()
	var ids: Array = []
	for id in session._sorted_unit_ids():
		if session.state.units_by_id[id].faction_id == "player": ids.append(id)
	session._register_formation_transit(ids, Vector2(1600,800))
	var unit: Dictionary = session.state.units_by_id[ids[0]]
	unit.navigation_state.column_guidance = {"goal":Vector2(900,500)}
	unit.navigation_state.sailed_trail = [{"position":unit.position,"distance":0.0}]
	session._begin_navigation_intent(unit)
	check(not unit.navigation_state.has("column_guidance") and not unit.navigation_state.has("transit_group_id"), "replacement order immediately detaches column")
	check(not unit.navigation_state.has("sailed_trail"), "old intent trail cannot survive replacement")
	session._register_formation_transit(ids, Vector2(1600,800))
	session._append_player_waypoint(unit,Vector2(1400,800),"test.append")
	check(not unit.navigation_state.has("transit_group_id"), "explicit appended waypoint retains its own route authority")
	var filter = preload("res://scripts/application/battle_presentation_filter.gd")
	check(filter.events([{"event_type":"FormationTransitChanged","group_id":"enemy","member_ids":["hidden"]}],session.state,registry,"player").is_empty(), "internal coordination never publishes hidden enemy membership")
	var terrain := {"id":"open.fixture","map_size":[3200,1800],"obstacles":[],"regions":[]}
	session.terrain_query.configure(terrain)
	session.terrain_context_service.configure(session.terrain_query,{},[],"")
	for id in ids:
		var member: Dictionary = session.state.units_by_id[id]
		member.movement_state = session._new_movement_state("HoldPosition",member.position,[])
		member.navigation_state.route_waiting = false
	session._update_formation_transits()
	check(session.state.formation_transits.is_empty(), "finished or invalid groups release coordination state")

func _transit(registry, scenario: String) -> Dictionary:
	var baseline := "--baseline" in OS.get_cmdline_user_args()
	var session_type = load("res://artifacts/formation_transit_20260930/battle_session.before.gd") if baseline else Session
	var session = session_type.new(registry)
	session.create_battle("level.prototype_11v11" if scenario == "neck11" else "level.prototype_3v3", 8412)
	session._full_ai_factions.clear()
	var moving: Array = []
	var ids: Array = []
	for id in session._sorted_unit_ids():
		var unit: Dictionary = session.state.units_by_id[id]
		if unit.faction_id != "player": unit.life_state = "Sunk"; continue
		unit.position = Vector2(1000 - (moving.size()/3)*220, 700 + (moving.size()%3-1)*220) if scenario == "neck11" else Vector2(400, 500 + moving.size() * 200)
		unit.heading = 0.0
		unit.current_speed = 0.0
		unit.movement_assist_enabled = false
		unit.movement_state = session._new_movement_state("HoldPosition", unit.position, [])
		moving.append(unit)
		ids.append(id)
	var polygons: Array = [[[900,0],[1550,0],[1550,620],[900,620]], [[900,780],[1550,780],[1550,1600],[900,1600]]]
	var points: Array = [Vector2(700,700), Vector2(950,700), Vector2(1200,700), Vector2(1500,700), Vector2(1750,700)]
	var target := Vector2(2100,700)
	if scenario == "bend3":
		polygons = [[[900,0],[1600,0],[1600,1000],[1400,1000],[1400,600],[900,600]], [[900,800],[1200,800],[1200,1200],[1600,1200],[1600,1600],[900,1600]]]
		points = [Vector2(700,700),Vector2(1000,700),Vector2(1150,700),Vector2(1300,850),Vector2(1300,950),Vector2(1450,1100),Vector2(1800,1100)]
		target = Vector2(2100,1100)
	if scenario == "neck11":
		for polygon in polygons:
			for point in polygon: point[0] += 400
		for index in range(points.size()): points[index] += Vector2(400,0)
		target += Vector2(400,0)
		points.append_array([Vector2(2350,700),Vector2(2600,700),Vector2(2850,700),Vector2(3100,700)])
	var obstacles: Array = []
	for index in range(polygons.size()): obstacles.append({"id":"bank.%d" % index, "block_mask":["ShipMovement"], "polygon":polygons[index]})
	var terrain := {"id":"terrain.column.test", "map_size":[3600,1600], "obstacles":obstacles, "regions":[]}
	session.terrain_query.configure(terrain)
	session.terrain_context_service.configure(session.terrain_query, {}, [], "")
	session.state.terrain_map = terrain
	session.state.map = {"width":3600.0,"height":1600.0}
	var nodes: Array = []
	for index in range(points.size()):
		var neighbors: Array = []
		if index > 0: neighbors.append(str(index - 1))
		if index + 1 < points.size(): neighbors.append(str(index + 1))
		nodes.append({"id":str(index), "position":[points[index].x,points[index].y], "neighbors":neighbors})
	session.navigation_definition = {"profiles":[{"radius":32.0,"movement_tags":["Surface"],"nodes":nodes}, {"radius":32.0,"movement_tags":["Surface","ShallowDraft"],"nodes":nodes}]}

	for tags in [["Surface"],["Surface","ShallowDraft"]]: session.navigation_definition.profiles.append({"radius":46.0,"movement_tags":tags,"nodes":nodes})
	session.route_planner.configure(session.navigation_definition)
	check(session._apply_command({"command_type":"MoveUnits", "issuer_id":"player", "unit_ids":ids, "target_position":target}).accepted, scenario + " group order accepted")
	var endpoints := {}
	var paths := {}
	for unit in moving:
		endpoints[unit.entity_id] = unit.player_route_waypoints[-1]
		paths[unit.entity_id] = []
	var events := {}
	var diagnostics: Array = []
	var arrived := 0
	var settle := 0
	var cpu := 0
	var cpu_first_400 := 0
	for tick in range(3600):
		var started := Time.get_ticks_usec()
		session.state.tick_index += 1
		session.state.elapsed_time += 0.1
		session._update_navigation_requests()
		session._update_navigation_plans()
		session._update_movement(0.1)
		session._resolve_unit_overlap()
		for unit in moving: session._update_navigation_progress(unit,0.1)
		var cost := Time.get_ticks_usec() - started
		cpu += cost
		if tick < 400: cpu_first_400 += cost
		for event in session._event_buffer:
			if str(event.event_type) in ["NavigationRecoveryStarted", "NavigationRequestFailed"]:
				var affected: Dictionary = session.state.units_by_id.get(str(event.get("unit_id", "")), {})
				diagnostics.append({"time":session.state.elapsed_time, "event":event, "position":affected.get("position"), "movement":affected.get("movement_state"), "guidance":affected.get("navigation_state",{}).get("column_guidance",{}).duplicate(true)})
			var name := str(event.event_type)
			if name == "FormationTransitChanged": name += "." + str(event.mode)
			if name in ["FormationTransitChanged.Column","FormationTransitChanged.Expanded","UnitTerrainCollision","NavigationCollisionContractViolated","NavigationRequestFailed","NavigationRecoveryStarted","TrajectoryPlanFailed","NavigationSeparationApplied","UnitTideAccessRestricted"]: events[name] = int(events.get(name,0)) + 1
		session._event_buffer.clear()
		arrived = 0
		for unit in moving:
			if tick % 10 == 0: paths[unit.entity_id].append([unit.position.x,unit.position.y])
			if unit.position.distance_to(endpoints[unit.entity_id]) <= session.trajectory_planner.arrival_tolerance(float(unit.stats.collision_radius)) + 0.1 and unit.movement_state.mode == "HoldPosition": arrived += 1
		settle = settle + 1 if arrived == moving.size() else 0
		if settle >= 20: break
	var result := {"scenario":scenario,"arrived":arrived,"seconds":snappedf(session.state.elapsed_time,0.1),"events":events,"cpu_mean_usec":float(cpu)/session.state.tick_index,"cpu_first_400_mean_usec":float(cpu_first_400)/mini(400,session.state.tick_index),"paths":paths,"polygons":polygons,"diagnostics":diagnostics,"end_states":moving.map(func(unit): return {"id":unit.entity_id,"position":unit.position,"mode":unit.movement_state.mode,"radius":unit.stats.collision_radius,"goal":endpoints[unit.entity_id]})}
	var summary := result.duplicate()
	summary.erase("paths"); summary.erase("polygons"); summary.erase("diagnostics"); summary.erase("end_states")
	print(JSON.stringify(summary))
	if not baseline:
		check(arrived == moving.size(), scenario + " all ships arrive and settle")
		check(int(events.get("FormationTransitChanged.Column",0)) > 0, scenario + " narrows into column")
		check(int(events.get("UnitTerrainCollision",0)) + int(events.get("NavigationCollisionContractViolated",0)) + int(events.get("NavigationSeparationApplied",0)) + int(events.get("UnitTideAccessRestricted",0)) + int(events.get("NavigationRequestFailed",0)) == 0, scenario + " no terrain contact, water rejection, request failure or hull separation")
	return result
