extends SceneTree

const Registry = preload("res://scripts/infrastructure/data/config_registry.gd")
const Session = preload("res://scripts/application/battle_session.gd")
const Planner = preload("res://scripts/application/navigation/route_planner.gd")
const Query = preload("res://scripts/domain/services/terrain_query_service.gd")
const Feedback = preload("res://scripts/presentation/battle/player_command_feedback.gd")
var failures: Array[String] = []
var checks := 0

class ClosedChannel extends RefCounted:
	func movement_segment_access(a: Vector2, b: Vector2) -> Dictionary:
		return {"allowed":not (minf(a.x,b.x)<500.0 and maxf(a.x,b.x)>500.0)}

func _init(): call_deferred("run")
func check(value: bool, message: String):
	checks += 1
	if not value: failures.append(message)

func run():
	var registry = Registry.new()
	check(registry.load_all(), "registry loads four navigation profiles")
	test_disconnected()
	test_real_channel(registry)
	test_pocket(registry)
	test_player_requests(registry)
	for failure in failures: push_error(failure)
	print("%s: %d navigation reachability checks" % ["PASS" if failures.is_empty() else "FAIL",checks])
	quit(0 if failures.is_empty() else 1)

func test_disconnected():
	var query = Query.new()
	var terrain := {"map_size":[1000,1000],"obstacles":[{"id":"wall","block_mask":["ShipMovement"],"polygon":[[450,0],[550,0],[550,1000],[450,1000]]}],"regions":[]}
	query.configure(terrain)
	var nodes := [{"id":"a","position":[100,500],"neighbors":["b"]},{"id":"b","position":[300,500],"neighbors":["a"]},{"id":"c","position":[700,500],"neighbors":["d"]},{"id":"d","position":[900,500],"neighbors":["c"]}]
	var graph := {"profiles":[{"radius":32,"movement_tags":["Surface"],"nodes":nodes}]}
	var planner = Planner.new()
	var result: Dictionary = planner.plan_path(query,graph,Vector2(100,500),Vector2(900,500),31,["Surface"])
	check(result.get("ok",false) and result.get("target_projected",false), "legal disconnected goal projects onto reachable component")
	check(result.get("resolved_target",Vector2.ZERO)==Vector2(300,500), "best reachable stage selected")
	check(planner.get_last_profile().get("astar_expansions",0)==2, "fallback reuses exhausted search without second flood")
	result = planner.plan_path(query,graph,Vector2(300,500),Vector2(900,500),31,["Surface"])
	check(not result.get("ok",true) and result.get("reason_code","")=="TARGET_UNREACHABLE", "no-progress retry cannot fabricate a new stage")
	# Same graph connected statically, but the current tide cuts its central edge.
	terrain["obstacles"] = []; query.configure(terrain)
	nodes[1]["neighbors"].append("c"); nodes[2]["neighbors"].append("b")
	planner.configure(graph)
	result = planner.plan_path(query,graph,Vector2(100,500),Vector2(900,500),31,["Surface"],ClosedChannel.new())
	check(result.get("target_projected",false) and result.get("resolved_target",Vector2.ZERO)==Vector2(300,500), "projection respects dynamic channel closure")
	result = planner.plan_path(query,graph,Vector2(100,500),Vector2(900,500),31,["Surface"])
	check(result.get("ok",false) and not result.get("target_projected",false), "reopened channel immediately permits exact goal")

func fixture(registry, level: String, position: Vector2) -> Dictionary:
	var session = Session.new(registry)
	session.create_battle("level.prototype_1v1",20260929)
	var unit: Dictionary = session.state["units_by_id"]["unit.player.warspite"]
	var definition: Dictionary = registry.get_definition("levels",level)
	session.state["map"] = definition["map"].duplicate(true)
	session._configure_scene_combat(definition)
	session.state["units_by_id"] = {unit["entity_id"]:unit}
	session._full_ai_factions.clear()
	unit["movement_assist_enabled"] = false
	unit["position"] = position; unit["current_speed"] = 0.0
	unit["movement_state"] = session._new_movement_state("HoldPosition",position,[])
	return {"session":session,"unit":unit}

func test_real_channel(registry):
	var f := fixture(registry,"level.prototype_double_island_long_channel_3v3",Vector2(3010.15,1921.26))
	var session = f["session"]
	var start := Vector2(3010.15,1921.26); var goal := Vector2(3110,2711.46)
	for radius in [30.0,31.0,46.0]:
		var result: Dictionary = session.route_planner.plan_path(session.terrain_query,session.navigation_definition,start,goal,radius,["Surface"])
		check(result.get("ok",false) and not result.get("target_projected",true), "channel resolves exact endpoint radius %s"%radius)
		var length := 0.0; var anchor := start
		for point: Vector2 in result.get("waypoints",[]):
			check(session.terrain_query.is_navigation_segment_clear(anchor,point,radius,["Surface"]),"corridor segment remains safe radius %s"%radius)
			length += anchor.distance_to(point); anchor=point
		if radius<=32: check(length<1400.0,"standard deep hull uses narrow passage rather than circling island")
	check(session.navigation_definition["profiles"].any(func(p):return p["id"]=="navigation.profile.standard_deep" and p["radius"]==32 and p["cell_size"]==128),"standard deep profile keeps original sampling density")
	var unit: Dictionary = f["unit"]
	session._submit_navigation_request(unit,start,goal,"Replace","AutoNavigate","original",10)
	session._update_navigation_requests()
	var gate: Vector2 = session._current_corridor_goal(unit)
	unit["navigation_state"]["recovery"] = {"stage":"Depart"}
	session._submit_navigation_request(unit,start,gate,"Recovery","AutoNavigate","recovery",10,goal)
	session._update_navigation_requests()
	check(not unit["navigation_state"].get("target_projected",true) and unit["movement_state"]["target_position"]==goal,"recovery of one leg does not mark an exact full route as projected")

func test_pocket(registry):
	var f := fixture(registry,"level.prototype_ring_lagoon_3v3",Vector2(4054.42,935.47))
	var session = f["session"]; var unit: Dictionary = f["unit"]
	var goal := Vector2(4502.92,1779.54)
	check(session.terrain_query.can_occupy_circle(goal,30,["Surface"]),"pocket is occupiable, not necessarily reachable")
	session._submit_navigation_request(unit,unit["position"],goal,"Replace","AutoNavigate","test.ai",10)
	session._update_navigation_requests()
	var stage: Vector2 = unit["movement_state"]["target_position"]
	check(unit["navigation_state"].get("target_projected",false) and stage!=goal,"AI receives reachable stage for isolated goal")
	check(unit["navigation_state"]["strategic_intent_target"]==goal,"AI semantic target preserved")
	var arrived := false; var collisions := 0
	for tick in range(5000):
		session.state["tick_index"] = tick+1; session.state["elapsed_time"] = (tick+1)*0.1
		session._event_buffer=[]
		session._update_navigation_plans(); session._update_movement(0.1)
		for event in session._event_buffer:
			if event["event_type"] in ["UnitTerrainCollision","NavigationCollisionContractViolated"]: collisions+=1
		if (unit["position"] as Vector2).distance_to(stage)<=15.0: arrived=true; break
	check(arrived and collisions==0,"AI physically reaches projected pocket stage without touching shore")
	session._advance_corridor_progress(unit)
	session._queue_ai_move(unit,goal)
	check(session.command_queue.size()==1,"completed stage permits same-semantic-target reassessment")
	session._process_commands(); session._update_navigation_requests()
	check(unit["navigation_state"].get("route_failure_count",0)>0,"no further progress produces classified failure")
	session.command_queue.clear(); session._queue_ai_move(unit,goal)
	check(session.command_queue.is_empty(),"unreachable same target observes retry backoff")
	session.state["elapsed_time"] += 13.0
	session._queue_ai_move(unit,goal)
	check(session.command_queue.size()==1,"same target may retry after backoff expires")

func command(unit: Dictionary, kind: String, target: Vector2, id: String) -> Dictionary:
	return {"command_type":kind,"command_id":id,"unit_id":unit["entity_id"],"target_position":target,"issuer_id":"player","issuer_type":"Player","issued_at_tick":1}

func test_player_requests(registry):
	var f := fixture(registry,"level.prototype_ring_lagoon_3v3",Vector2(2828,441.79))
	var session = f["session"]; var unit: Dictionary = f["unit"]
	var good := Vector2(4054.42,935.47); var bad := Vector2(4502.92,1779.54)
	for c in [command(unit,"AppendMoveWaypoint",good,"a"),command(unit,"AppendMoveWaypoint",bad,"b"),command(unit,"AppendMoveWaypoint",Vector2(2828,2707.89),"c")]: session.queue_command(c)
	session._process_commands(); session._update_navigation_requests()
	var prefix: Array = unit["movement_state"]["corridor_points"].duplicate()
	session._event_buffer=[]; session._update_navigation_requests()
	check(unit["movement_state"]["corridor_points"]==prefix,"failed waypoint preserves already accepted prefix")
	check(unit["player_route_waypoints"]==[good] and session.navigation_request_broker.pending_count()==0,"unreachable waypoint cancels dependent suffix")
	var rejected: Array = session._event_buffer.filter(func(e):return e["event_type"]=="CommandRejected")
	check(rejected.size()==1 and rejected[0].get("command_id","")=="b","async player failure emits one correctly attributed rejection")
	var feedback = Feedback.new()
	if not rejected.is_empty():
		check(feedback.reject(rejected[0],rejected[0]["reason_code"],0),"async rejection reaches player feedback")
		check(feedback.current(0).get("text","").contains("可通行水域"),"rejection gives actionable human wording")
	# A replacement that cannot be executed must not remove a valid old corridor.
	session._event_buffer=[]
	session.queue_command(command(unit,"MoveUnits",bad,"replace")); session._process_commands(); session._update_navigation_requests()
	check(unit["movement_state"]["corridor_points"]==prefix,"unreachable replacement leaves previous accepted route intact")
	# Stale player requests are cancelled before they can reject or override a new order.
	session.queue_command(command(unit,"MoveUnits",bad,"stale")); session._process_commands()
	session.queue_command(command(unit,"MoveUnits",good,"new")); session._process_commands()
	session._event_buffer=[]; session._update_navigation_requests()
	check(not session._event_buffer.any(func(e):return e["event_type"]=="CommandRejected"),"replaced stale request emits no late rejection")
