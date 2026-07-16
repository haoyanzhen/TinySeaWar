extends SceneTree

const BattleSession = preload("res://scripts/application/battle_session.gd")

var checks := 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = root.get_node("DataRegistry").registry
	var tutorial = BattleSession.new(registry)
	_check(tutorial.create_battle("level.tutorial.t01", 7301).get("ok", false), "T-01 creates from formal runtime data")
	var sirius: Dictionary = tutorial.state["units_by_id"]["unit.player.t01.sirius"]
	var ward: Dictionary = tutorial.state["units_by_id"]["unit.enemy.t01.ward"]
	_check(tutorial.state.get("level_objective", {}).get("objective_set_id", "") == "objective.t01_navigation", "T-01 loads its objective definition")
	_check(not bool(sirius.get("secondary_auto_fire_enabled", true)), "T-01 initially limits automatic secondary fire")
	var ward_start: Vector2 = ward["position"]
	var early_events: Array = []
	for _tick in range(20): early_events.append_array(tutorial.advance_tick(0.1))
	_check((ward["position"] as Vector2).distance_to(ward_start) > 0.1 and not early_events.any(func(event): return event.get("event_type", "") == "WeaponFired"), "T-01 stages the enemy through natural movement without opening fire")
	for action_id in ["SelectTutorialUnit", "EnableCameraFollow"]:
		tutorial.queue_command({"command_id":"test.t01.%s" % action_id,"command_type":"RecordTutorialAction","issued_at_tick":tutorial.state["tick_index"],"issuer_type":"Player","issuer_id":"player","unit_id":"unit.player.t01.sirius","action_id":action_id})
	var zones: Array = registry.get_definition("objectives", "objective.t01_navigation").get("waypoint_zones", [])
	tutorial.queue_command({"command_id":"test.t01.waypoint.1","command_type":"AppendMoveWaypoint","issued_at_tick":tutorial.state["tick_index"],"issuer_type":"Player","issuer_id":"player","unit_id":"unit.player.t01.sirius","target_position":_pair(zones[0]["position"])})
	tutorial.queue_command({"command_id":"test.t01.waypoint.2","command_type":"AppendMoveWaypoint","issued_at_tick":tutorial.state["tick_index"],"issuer_type":"Player","issuer_id":"player","unit_id":"unit.player.t01.sirius","target_position":_pair(zones[1]["position"])})
	var navigation_events: Array = []
	for _tick in range(500):
		navigation_events.append_array(tutorial.advance_tick(0.1))
		if bool(tutorial.state["level_objective"].get("engagement_unlocked", false)): break
	_check(tutorial.state["level_objective"].get("current_step", 0) >= 1 and navigation_events.any(func(event): return event.get("event_type", "") == "LevelObjectiveAdvanced"), "T-01 records the first waypoint through normal movement")
	var second_events := navigation_events
	_check(bool(tutorial.state["level_objective"].get("engagement_unlocked", false)) and bool(sirius.get("movement_assist_enabled", false)) and bool(sirius.get("secondary_auto_fire_enabled", false)) and bool(sirius.get("primary_auto_fire_enabled", false)), "T-01 unlocks the natural engagement and tutorial automatic abilities after both waypoints")
	_check(second_events.any(func(event): return event.get("event_type", "") == "TutorialStageChanged"), "T-01 emits a visible tutorial stage transition")
	_check(tutorial.state["level_objective"].get("action_counts", {}).get("AppendMoveWaypoint", 0) == 2 and tutorial.state["level_objective"].get("waypoint_zones", []).size() == 2, "T-01 records required actions and exposes waypoint markers")
	var finish_events: Array = []
	for _tick in range(5500):
		finish_events.append_array(tutorial.advance_tick(0.1))
		if tutorial.state.get("phase", "") == "Finished": break
	if tutorial.state.get("result", {}).get("winner_faction", "") != "player":
		print("T01_DIAGNOSTIC result=%s objective=%s sirius=%s ward=%s visible=%s" % [tutorial.state.get("result", {}), tutorial.state.get("level_objective", {}), {"position":sirius.get("position"),"heading":sirius.get("heading"),"hp":sirius.get("current_hp"),"weapons":sirius.get("weapon_states"),"secondary":sirius.get("secondary_auto_fire_enabled"),"target":sirius.get("targeting_state", {})}, {"position":ward.get("position"),"heading":ward.get("heading"),"hp":ward.get("current_hp"),"weapons":ward.get("weapon_states"),"secondary":ward.get("secondary_auto_fire_enabled"),"target":ward.get("targeting_state", {})}, tutorial.state.get("visible_by_faction", {})])
	_check(tutorial.state.get("result", {}).get("winner_faction", "") == "player" and tutorial.state.get("result", {}).get("reason", "") == "LEVEL_OBJECTIVE_COMPLETED", "T-01 completes only after navigation and Ward is sunk")
	_check(finish_events.any(func(event): return event.get("event_type", "") == "LevelObjectiveCompleted") and finish_events.any(func(event): return event.get("event_type", "") == "BattleFinished"), "T-01 emits objective and battle completion events")

	var challenge = BattleSession.new(registry)
	_check(challenge.create_battle("level.challenge.s01", 102).get("ok", false), "S-01 creates from formal runtime data")
	_check(challenge.state.get("terrain_map", {}).get("id", "") == "terrain.map.central_sandbar" and challenge.state.get("level_objective", {}).get("objective_set_id", "") == "objective.s01_flagship", "S-01 loads K-S01 central sandbar and its mission")
	var enemy_flagship: Dictionary = challenge.state["units_by_id"]["unit.enemy.s01.hindenburg"]
	enemy_flagship["life_state"] = "Sunk"
	enemy_flagship["current_hp"] = 0.0
	challenge.advance_tick(0.1)
	_check(challenge.state.get("result", {}).get("winner_faction", "") == "player" and challenge.state.get("result", {}).get("reason", "") == "LEVEL_OBJECTIVE_COMPLETED", "S-01 mission completion immediately wins the battle")

	var failed_challenge = BattleSession.new(registry)
	failed_challenge.create_battle("level.challenge.s01", 103)
	var player_flagship: Dictionary = failed_challenge.state["units_by_id"]["unit.player.s01.warspite"]
	player_flagship["life_state"] = "Sunk"
	player_flagship["current_hp"] = 0.0
	failed_challenge.advance_tick(0.1)
	_check(failed_challenge.state.get("result", {}).get("winner_faction", "") == "enemy" and failed_challenge.state.get("result", {}).get("reason", "") == "LEVEL_OBJECTIVE_CANCELLED", "S-01 cancels when the protected player flagship sinks")

	var technical_limit = BattleSession.new(registry)
	technical_limit.create_battle("level.challenge.s01", 104)
	technical_limit.state["elapsed_time"] = technical_limit.state["time_limit"]
	technical_limit.advance_tick(0.1)
	_check(technical_limit.state.get("result", {}).get("winner_faction", "") == "" and technical_limit.state.get("result", {}).get("reason", "") == "LEVEL_TECHNICAL_LIMIT", "formal objective technical limit produces an invalid sample instead of mission victory or defeat")

	if failures.is_empty():
		print("PASS: %d level objective runtime checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error("FAIL: %s" % failure)
		print("FAILED: %d of %d level objective runtime checks" % [failures.size(), checks])
		quit(1)


func _pair(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
