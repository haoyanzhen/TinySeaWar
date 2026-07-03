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
	_check(session.create_battle("level.prototype_3v3", 20260630).get("ok", false), "coordination fixture starts")
	var aurora: Dictionary = session.state["units_by_id"]["unit.player.aurora"]
	var ally: Dictionary = session.state["units_by_id"]["unit.player.warspite"]
	var recon_skill: Dictionary = registry.get_definition("skills", "skill.aurora_searchlight_order")
	var center := Vector2(600.0, 500.0)
	_check(session._skill_reservation_groups(recon_skill) == ["AreaSupport", "Control", "Recon"], "skill semantics map to stable reservation groups")
	session._reserve_ai_skill_effect(aurora, recon_skill, center)
	_check(session._skill_effect_reservation_conflict(ally, recon_skill, center + Vector2(100.0, 0.0)), "overlapping same-purpose skill is reserved")
	_check(not session._skill_effect_reservation_conflict(ally, recon_skill, center + Vector2(1000.0, 0.0)), "non-overlapping area remains available")
	session._ai_effect_reservations[aurora["entity_id"]]["expires_at"] = -1.0
	session._expire_ai_effect_reservations()
	_check(not session._skill_effect_reservation_conflict(ally, recon_skill, center), "expired effect reservation is released")
	var source: Dictionary = session.state["units_by_id"]["unit.enemy.bismarck"]
	var wingman: Dictionary = session.state["units_by_id"]["unit.enemy.hindenburg"]
	var target: Dictionary = session.state["units_by_id"]["unit.player.warspite"]
	source["position"] = Vector2(500.0, 350.0)
	wingman["position"] = Vector2(500.0, 470.0)
	target["position"] = Vector2(950.0, 350.0)
	session.state["visible_by_faction"]["enemy"] = {target["entity_id"]: true}
	session._ai_observations_by_faction.clear()
	session._ai_battlefield_context_cache.clear()
	var attack_skill: Dictionary = registry.get_definition("skills", "skill.bismarck_decisive_lock")
	var open_score := session._skill_coordination_score(source, attack_skill, target)
	session._ai_damage_reservations[wingman["entity_id"]] = {"source_unit_id": wingman["entity_id"], "target_unit_id": target["entity_id"], "expected_damage": target["current_hp"], "expires_at": 20.0}
	var reserved_score := session._skill_coordination_score(source, attack_skill, target)
	_check(session._skill_requires_attack_coordination(attack_skill), "offensive burst skill requires explicit coordination")
	_check(open_score >= 70.0, "ready offensive skill reaches the coordination threshold in a clean window")
	_check(reserved_score < open_score, "overkill reservation lowers offensive coordination score")
	if failures.is_empty():
		print("PASS: %d AI coordination checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error("FAIL: %s" % failure)
		print("FAILED: %d of %d AI coordination checks; open=%.2f reserved=%.2f" % [failures.size(), checks, open_score, reserved_score])
		quit(1)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
