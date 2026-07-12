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
	var session = BattleSession.new(registry)
	_check(session.create_battle("level.prototype_harbor_3v3", 20260630).get("ok", false), "harbor trajectory fixture starts")
	var unit: Dictionary = session.state["units_by_id"]["unit.enemy.kirov"]
	var target: Dictionary = session.state["units_by_id"]["unit.player.shimakaze"]
	var destination: Vector2 = unit["position"]
	var corridor := {}
	for offset in [Vector2(0.0, 240.0), Vector2(240.0, 0.0), Vector2(-240.0, 0.0), Vector2(0.0, -240.0), Vector2(160.0, 160.0), Vector2(-160.0, 160.0)]:
		destination = unit["position"] + offset
		corridor = session._build_navigation_corridor(unit, unit["position"], destination)
		if bool(corridor.get("ok", false)): break
	_check(bool(corridor.get("ok", false)), "strategic corridor resolves a reachable coastal target")
	_check(not corridor.get("points", []).is_empty(), "strategic corridor contains forward regions")
	unit["movement_state"] = session._new_movement_state("AutoNavigate", destination, corridor.get("points", []))
	session._mark_navigation_dirty(unit)
	for _index in range(10):
		session.state["tick_index"] = int(session.state.get("tick_index", 0)) + 1
		session._update_navigation_plans()
		if unit["navigation_state"].get("trajectory_plan", {}).get("ok", false): break
	_check(unit["navigation_state"].get("state", "") == "NormalNavigation", "coastal route uses normal navigation state")
	_check(unit["navigation_state"].get("trajectory_plan", {}).get("ok", false), "coastal corridor produces a dynamics trajectory")
	_check(unit["movement_state"].get("waypoints", []).is_empty(), "legacy AI waypoint trajectory remains unused")
	var cover: Dictionary = session._best_ai_cover_position(unit, target)
	_check(not cover.is_empty(), "nearshore AI still produces a tactical cover region")
	_check(session.terrain_query.can_occupy_circle(cover.get("position", Vector2.ZERO), float(unit["stats"].get("collision_radius", 20.0)), session._movement_tags(unit)), "cover region is legal water for the ship")
	var doomed: Dictionary = session.state["units_by_id"]["unit.enemy.anshan"]
	session.command_queue.append({"command_id":"test.stale", "command_type":"MoveUnits", "unit_id":doomed["entity_id"]})
	session._sink_unit(doomed, "test")
	_check(session.command_queue.all(func(command): return str(command.get("unit_id", "")) != str(doomed["entity_id"])), "sinking a unit removes its stale queued commands")
	if failures.is_empty():
		print("PASS: %d AI corridor and trajectory checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error("FAIL: %s" % failure)
		print("FAILED: %d of %d AI corridor and trajectory checks" % [failures.size(), checks])
		quit(1)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
