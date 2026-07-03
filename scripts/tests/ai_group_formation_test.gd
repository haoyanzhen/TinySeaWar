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
	_check(session.create_battle("level.prototype_3v3", 20260630).get("ok", false), "3v3 group fixture starts")
	var groups: Dictionary = session.state["ai_groups_by_faction"]["enemy"]
	_check(groups.size() == 1 and groups.values()[0]["member_ids"].size() == 3, "small fleet forms one elastic group")
	var group: Dictionary = groups.values()[0]
	_check(group["leader_unit_id"] == "unit.enemy.bismarck", "flagship becomes deterministic group leader")
	_check(group["formation_id"] == "LineAbreast", "searching fleet uses line-abreast formation")
	session.configure_full_ai_factions(["player", "enemy"])
	_check(not session.state["ai_groups_by_faction"]["player"].is_empty(), "full-AI simulation builds groups for the player-side faction too")
	var role_set: Array = []
	for unit_id in group["member_ids"]: role_set.append(session.state["units_by_id"][unit_id]["ai_state"]["group_role"])
	_check("Fixer" in role_set and "Screen" in role_set and "Flanker" in role_set, "ship classes receive complementary group roles")
	session.state["projectiles_by_id"]["projectile.threat"] = {"entity_id":"projectile.threat", "faction_id":"player", "position":Vector2.ZERO}
	session.state["known_projectiles_by_faction"]["enemy"] = {"projectile.threat":true}
	session._ai_observations_by_faction.clear()
	session._rebuild_ai_groups("enemy")
	_check(session.state["ai_groups_by_faction"]["enemy"].values()[0]["formation_id"] == "Dispersed", "known hostile projectile switches group to dispersed formation")
	var old_leader: Dictionary = session.state["units_by_id"]["unit.enemy.bismarck"]
	old_leader["life_state"] = "Sunk"
	session._ai_observations_by_faction.clear()
	session._rebuild_ai_groups("enemy")
	var successor_group: Dictionary = session.state["ai_groups_by_faction"]["enemy"].values()[0]
	_check(successor_group["leader_unit_id"] != old_leader["entity_id"] and successor_group["member_ids"].size() == 2, "living member replaces a sunk leader")
	var large = BattleSession.new(registry)
	_check(large.create_battle("level.prototype_11v11", 20260630).get("ok", false), "11v11 group fixture starts")
	var large_groups: Dictionary = large.state["ai_groups_by_faction"]["enemy"]
	var bounded := large_groups.size() == 3
	for candidate in large_groups.values(): bounded = bounded and candidate["member_ids"].size() >= 1 and candidate["member_ids"].size() <= 4
	_check(bounded, "11v11 fleet splits into bounded 1-4 ship groups")
	var harbor = BattleSession.new(registry)
	_check(harbor.create_battle("level.prototype_harbor_3v3", 20260630).get("ok", false), "harbor group fixture starts")
	_check(harbor.state["ai_groups_by_faction"]["enemy"].values()[0]["formation_id"] == "Column", "nearshore group selects column formation")
	if failures.is_empty():
		print("PASS: %d AI group and formation checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error("FAIL: %s" % failure)
		print("FAILED: %d of %d AI group and formation checks" % [failures.size(), checks])
		quit(1)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
