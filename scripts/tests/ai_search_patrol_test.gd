extends SceneTree
const Registry = preload("res://scripts/infrastructure/data/config_registry.gd")
const Session = preload("res://scripts/application/battle_session.gd")
var checks := 0
var failures: Array[String] = []
func _init() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func run() -> void:
	var registry = Registry.new()
	check(registry.load_all(), "registry loads")
	for faction in ["player", "enemy"]:
		var session = Session.new(registry)
		check(session.create_battle("level.challenge.s03", 2108932566).get("ok", false), "fixture starts")
		session.configure_full_ai_factions(["player", "enemy"])
		var id := "unit.player.s03.warspite" if faction == "player" else "unit.enemy.s03.bismarck"
		var unit: Dictionary = session.state["units_by_id"][id]
		var ai: Dictionary = unit["ai_state"]
		var nav: Dictionary = unit["navigation_state"]
		unit["position"] = Vector2(2040 if faction == "player" else 2056, 400)
		session._queue_enemy_search_intent(unit)
		var destination: Vector2 = ai["search_patrol"]["destination"]
		check(destination.x == (3072.0 if faction == "player" else 1024.0), "initial search chooses opposite side")
		unit["position"].x = 2056 if faction == "player" else 2040
		session._queue_enemy_search_intent(unit)
		check(ai["search_patrol"]["destination"] == destination, "crossing centre keeps destination")
		nav["target_projected"] = true
		unit["movement_state"]["corridor_points"] = []
		session._queue_enemy_search_intent(unit)
		check(ai["search_patrol"]["destination"] == destination, "intermediate projected arrival is not patrol arrival")
		nav["route_failure_count"] = 1
		nav["failed_intent_target"] = destination
		nav["failed_intent_origin"] = unit["position"]
		nav["route_retry_at"] = 10.0
		session.command_queue.clear()
		session._queue_enemy_search_intent(unit)
		check(session.command_queue.is_empty(), "unreachable search respects retry backoff")
		check(ai["search_patrol"]["destination"] == destination, "route failure does not flip patrol")
		session.state["elapsed_time"] = 11.0
		session._queue_enemy_search_intent(unit)
		check(not session.command_queue.is_empty(), "same search retries after backoff")
		unit["position"] = destination + Vector2(50, 0)
		session._queue_enemy_search_intent(unit)
		check(ai["search_patrol"]["destination"].x != destination.x, "arrival advances patrol")
		session.state["contacts_by_faction"][faction] = {"ghost": {"unit_id":"ghost", "visible":false, "last_known_position":Vector2(1400, 700), "ghost_remaining":5.0}}
		session._ai_observations_by_faction.clear()
		session._queue_enemy_search_intent(unit)
		check(ai["search_patrol"].is_empty(), "legal ghost supersedes patrol")
		session.state["contacts_by_faction"][faction] = {}
		session._ai_observations_by_faction.clear()
		session._queue_enemy_search_intent(unit)
		check(not ai["search_patrol"].is_empty(), "expired ghost starts fresh patrol")
		session._queue_ai_move(unit, Vector2(1800, 800))
		check(ai["search_patrol"].is_empty(), "tactical movement supersedes patrol")
	if failures.is_empty():
		print("PASS: %d AI search patrol checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)
