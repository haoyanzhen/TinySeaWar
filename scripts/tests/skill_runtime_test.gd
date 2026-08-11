extends SceneTree

const ConfigRegistry = preload("res://scripts/infrastructure/data/config_registry.gd")
const BattleSession = preload("res://scripts/application/battle_session.gd")

var registry
var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	registry = ConfigRegistry.new()
	_check(registry.load_all(), "configuration registry loads")
	_test_all_skill_contracts_and_casts()
	_test_next_salvo_consumption()
	_test_effect_radius_is_not_cast_range()
	_test_torpedo_reload_and_oxygen_costs()
	if failures.is_empty():
		print("PASS: %d skill runtime checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error("FAIL: %s" % failure)
		print("FAILED: %d of %d skill runtime checks" % [failures.size(), checks])
		quit(1)


func _test_all_skill_contracts_and_casts() -> void:
	var skills: Array = registry.all("skills")
	_check(skills.size() == 48, "all 48 character skills are loaded")
	for skill in skills:
		var skill_id := str(skill.get("id", ""))
		_check(str(skill.get("implementation_status", "")) == "supported", "%s is fully supported" % skill_id)
		_check(skill.get("unsupported_effects", []).is_empty(), "%s has no placeholder effects" % skill_id)
		_check(not str(skill.get("description", "")).is_empty(), "%s exposes its battle description" % skill_id)
		_check(not skill.get("ai_tags", []).is_empty(), "%s declares AI semantics" % skill_id)
		if skill.get("target_type", "Self") == "Area":
			_check(float(skill.get("cast_range", 0.0)) > 0.0, "%s area cast has a legal range" % skill_id)
			_check(float(skill.get("effect_radius", 0.0)) > 0.0, "%s area cast has an independent effect radius" % skill_id)
		var session = BattleSession.new(registry)
		_check(session.create_battle("level.prototype_3v3", 7000 + checks).get("ok", false), "%s cast fixture starts" % skill_id)
		var source: Dictionary = session.state["units_by_id"]["unit.player.aurora"]
		var target: Dictionary = session.state["units_by_id"]["unit.enemy.bismarck"]
		source["position"] = Vector2(400.0, 400.0)
		target["position"] = Vector2(500.0, 400.0)
		source["skill_state"] = {"definition_id":skill_id, "cooldown_remaining":0.0, "cooldown_max":float(skill.get("cooldown", 0.0))}
		session.state["visible_by_faction"]["player"] = {target["entity_id"]:true}
		var status_before: int = source.get("status_effects", []).size()
		var attacks_before: int = session.delayed_attacks.size()
		var world_effects_before: int = session.state.get("skill_effects_by_id", {}).size()
		var target_ref := {"type":"Self"}
		match str(skill.get("target_type", "Self")):
			"Enemy": target_ref = {"type":"Entity", "entity_id":target["entity_id"]}
			"Area": target_ref = {"type":"Position", "position":target["position"]}
		var result: Dictionary = session._cast_skill(source, target_ref, "test.%s" % skill_id)
		_check(bool(result.get("accepted", false)), "%s can be cast through the shared command path" % skill_id)
		_check(is_equal_approx(float(source["skill_state"]["cooldown_remaining"]), float(skill.get("cooldown", 0.0))), "%s starts its declared cooldown" % skill_id)
		var produced_effect: bool = source.get("status_effects", []).size() > status_before or session.delayed_attacks.size() > attacks_before or session.state.get("skill_effects_by_id", {}).size() > world_effects_before
		_check(produced_effect, "%s produces a status, attack, or world effect" % skill_id)


func _test_next_salvo_consumption() -> void:
	var session = BattleSession.new(registry)
	session.create_battle("level.prototype_1v1", 8101)
	var source: Dictionary = session.state["units_by_id"]["unit.player.warspite"]
	var target: Dictionary = session.state["units_by_id"]["unit.enemy.bismarck"]
	source["position"] = Vector2(300.0, 350.0)
	target["position"] = Vector2(750.0, 350.0)
	source["heading"] = 0.0
	session.state["visible_by_faction"]["player"] = {target["entity_id"]:true}
	source["skill_state"]["cooldown_remaining"] = 0.0
	_check(session._cast_skill(source, {"type":"Entity", "entity_id":target["entity_id"]}, "warspite.skill").get("accepted", false), "Warspite prepares the selected-target salvo")
	_check(source["status_effects"].any(func(effect): return bool(effect.get("consume_on_fire", false))), "next-salvo effects persist until firing")
	_check(session._fire_primary_weapon(source, target["position"], "warspite.fire").get("accepted", false), "prepared Warspite salvo fires")
	_check(not source["status_effects"].any(func(effect): return bool(effect.get("consume_on_fire", false))), "next-salvo effects are consumed by that salvo")
	_check(session.delayed_attacks.any(func(attack): return attack.get("source_status_effects", []).any(func(effect): return effect.get("status_id", "") == "skill.warspite_veteran_aim")), "fired shells retain the launch-time skill snapshot")


func _test_effect_radius_is_not_cast_range() -> void:
	var session = BattleSession.new(registry)
	session.create_battle("level.prototype_3v3", 8102)
	var source: Dictionary = session.state["units_by_id"]["unit.player.aurora"]
	var skill: Dictionary = registry.get_definition("skills", "skill.aurora_searchlight_order")
	var center := Vector2(600.0, 400.0)
	for unit in session.state["units_by_id"].values(): unit["position"] = Vector2(2000.0, 2000.0)
	source["position"] = center - Vector2(100.0, 0.0)
	var near_ally: Dictionary = session.state["units_by_id"]["unit.player.shimakaze"]
	var far_ally: Dictionary = session.state["units_by_id"]["unit.player.warspite"]
	near_ally["position"] = center + Vector2(float(skill["effect_radius"]) - 1.0, 0.0)
	far_ally["position"] = center + Vector2(float(skill["effect_radius"]) + 1.0, 0.0)
	var recipients: Dictionary = session._skill_recipients(source, skill, center)
	_check(near_ally in recipients["AlliesInArea"] and far_ally not in recipients["AlliesInArea"], "area recipients use effect_radius instead of cast_range")


func _test_torpedo_reload_and_oxygen_costs() -> void:
	var torpedo_session = BattleSession.new(registry)
	torpedo_session.create_battle("level.prototype_3v3", 8103)
	var shimakaze: Dictionary = torpedo_session.state["units_by_id"]["unit.player.shimakaze"]
	shimakaze["position"] = Vector2(500.0, 500.0)
	shimakaze["heading"] = 0.0
	shimakaze["skill_state"]["cooldown_remaining"] = 0.0
	torpedo_session._cast_skill(shimakaze, {"type":"Self"}, "shimakaze.skill")
	var fire_position: Vector2 = shimakaze["position"] + Vector2(0.0, 300.0)
	_check(torpedo_session._fire_primary_weapon(shimakaze, fire_position, "shimakaze.fire").get("accepted", false), "Shimakaze skill-enhanced torpedo mount fires")
	var weapon: Dictionary = registry.get_definition("weapons", "weapon.shimakaze_610_torpedo")
	var used_state: Dictionary = shimakaze["weapon_states"].filter(func(state): return state.get("definition_id", "") == weapon["id"] and float(state.get("reload_remaining", 0.0)) > 0.0)[0]
	_check(is_equal_approx(float(used_state["reload_remaining"]), float(weapon["reload_time"]) + 4.0), "Shimakaze pays the declared four-second post-salvo reload cost")

	var oxygen_session = BattleSession.new(registry)
	oxygen_session.create_battle("level.prototype_3v3", 8104)
	var submarine: Dictionary = oxygen_session.state["units_by_id"]["unit.enemy.hai_shih"]
	submarine["skill_state"]["cooldown_remaining"] = 0.0
	var before := float(submarine["oxygen_state"]["current"])
	oxygen_session._cast_skill(submarine, {"type":"Self"}, "hai_shih.skill")
	oxygen_session._update_submarine_resources(1.0)
	var base_rate := float(submarine["stats"]["oxygen_consumption_rate"])
	_check(is_equal_approx(before - float(submarine["oxygen_state"]["current"]), base_rate * 1.2), "Hai Shih ambush applies its declared 20 percent oxygen cost")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
