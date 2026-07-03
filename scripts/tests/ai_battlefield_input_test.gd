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
	_check(session.create_battle("level.prototype_1v1", 20260630).get("ok", false), "1v1 AI battlefield fixture starts")
	var player: Dictionary = session.state["units_by_id"]["unit.player.warspite"]
	var enemy: Dictionary = session.state["units_by_id"]["unit.enemy.bismarck"]
	player["position"] = Vector2(300.0, 350.0)
	enemy["position"] = Vector2(830.0, 350.0)
	player["heading"] = 0.0
	enemy["heading"] = PI
	session.state["visible_by_faction"]["enemy"] = {player["entity_id"]: true}
	session.state["visible_by_faction"]["player"] = {enemy["entity_id"]: true}
	var weapon_states: Array = session._weapon_states_for_group(enemy, str(enemy["stats"].get("primary_weapon_group_id", "")), true)
	var weapon: Dictionary = session._weapon_for_state(weapon_states[0])
	var aim: Dictionary = session._automatic_aim_solution(enemy, player, weapon)
	var expected_damage := session._expected_weapon_damage_ratio(enemy, player, weapon)
	var lane := session._battlefield_target_context(enemy, player)
	_check(expected_damage > 0.0, "authoritative damage formula produces a positive normalized attack value")
	_check(float(lane.get("firing_lane_quality", 0.0)) > 0.0, "visible in-range target produces a real firing lane")
	_check(session._friendly_fire_risk(enemy, player, weapon, aim.get("position", player["position"])) < 0.2, "isolated 1v1 lane has low friendly-fire risk")
	session._reserve_ai_damage(enemy, player, weapon)
	_check(session._reserved_damage_for_target(player["entity_id"]) > 0.0, "committed volley creates an expected-damage reservation")
	session._ai_damage_reservations[enemy["entity_id"]]["expires_at"] = -1.0
	session._expire_ai_damage_reservations()
	_check(is_zero_approx(session._reserved_damage_for_target(player["entity_id"])), "expired damage reservation is removed")
	var fire := session._automatic_weapon_allowed_by_ai_discipline(enemy, player, weapon)
	_check(fire, "GunlineSupport accepts the legal quantified primary window")
	var event_types: Array[String] = []
	for index in range(40):
		for event in session.advance_tick(0.1):
			event_types.append(str(event.get("event_type", "")))
	_check("WeaponFired" in event_types, "runtime AI submits and executes a weapon command from the quantified window")
	if failures.is_empty():
		print("PASS: %d AI battlefield input checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error("FAIL: %s" % failure)
		print("FAILED: %d of %d AI battlefield input checks; events=%s" % [failures.size(), checks, event_types])
		quit(1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
