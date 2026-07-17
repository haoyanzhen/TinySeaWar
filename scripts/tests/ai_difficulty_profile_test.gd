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
	_check(registry.all("ai_profiles").size() == 3, "easy, standard and hard profiles load")
	var easy: Dictionary = registry.get_definition("ai_profiles", "ai.profile.easy")
	var standard: Dictionary = registry.get_definition("ai_profiles", "ai.profile.standard")
	var hard: Dictionary = registry.get_definition("ai_profiles", "ai.profile.hard")
	_check(float(easy["decision_interval"]) > float(standard["decision_interval"]) and float(standard["decision_interval"]) > float(hard["decision_interval"]), "difficulty changes decision cadence monotonically")
	_check(float(easy["skill_threshold"]) > float(standard["skill_threshold"]) and float(standard["skill_threshold"]) > float(hard["skill_threshold"]), "difficulty changes skill selectivity monotonically")
	_check(not easy.has("route_candidate_count") and not standard.has("route_candidate_count") and not hard.has("route_candidate_count"), "difficulty profiles do not override the shared navigation candidate budget")
	var session = BattleSession.new(registry)
	_check(session.create_battle("level.prototype_3v3", 20260630).get("ok", false), "difficulty fixture starts")
	var source: Dictionary = session.state["units_by_id"]["unit.enemy.bismarck"]
	var held: Dictionary = session.state["units_by_id"]["unit.player.aurora"]
	var better: Dictionary = session.state["units_by_id"]["unit.player.warspite"]
	var stats_before: Dictionary = source["stats"].duplicate(true)
	_check(session.configure_ai_profile("ai.profile.easy").get("accepted", false), "easy profile can be selected")
	_check(source["stats"] == stats_before, "difficulty profile does not alter combat attributes")
	better["current_hp"] = 1.0
	session.state["visible_by_faction"]["enemy"] = {held["entity_id"]:true, better["entity_id"]:true}
	session._ai_observations_by_faction.clear()
	source["targeting_state"]["current_target_id"] = held["entity_id"]
	source["ai_state"]["target_acquired_at"] = 0.0
	source["ai_state"]["target_switch_ready_at"] = 0.0
	session.state["elapsed_time"] = 5.0
	_check(session._select_target_with_hysteresis(source)["entity_id"] == held["entity_id"], "easy target selection waits after first confirmation")
	_check(session._select_target_with_hysteresis(source)["entity_id"] == held["entity_id"], "easy target selection waits after second confirmation")
	_check(session._select_target_with_hysteresis(source)["entity_id"] == better["entity_id"], "easy target selection switches on third confirmation")
	_check(not bool(easy["effect_reservations"]) and bool(standard["effect_reservations"]) and bool(hard["effect_reservations"]), "coordination depth follows profile without changing observation access")
	if failures.is_empty():
		print("PASS: %d AI difficulty profile checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error("FAIL: %s" % failure)
		print("FAILED: %d of %d AI difficulty profile checks" % [failures.size(), checks])
		quit(1)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
