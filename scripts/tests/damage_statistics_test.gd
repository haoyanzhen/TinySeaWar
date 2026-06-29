extends SceneTree

const ConfigRegistry = preload("res://scripts/infrastructure/data/config_registry.gd")
const BattleSession = preload("res://scripts/application/battle_session.gd")
const BattleRecorder = preload("res://scripts/infrastructure/analytics/battle_recorder.gd")
const DamageStatistics = preload("res://scripts/infrastructure/analytics/damage_statistics.gd")

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_classification_and_aggregation()
	_test_battle_session_accessors()
	if failures.is_empty():
		print("PASS: %d damage statistics checks" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error("FAIL: %s" % failure)
		print("FAILED: %d of %d damage statistics checks" % [failures.size(), checks])
		quit(1)


func _test_classification_and_aggregation() -> void:
	var recorder = BattleRecorder.new()
	recorder.reset("battle.statistics.test", 1)
	recorder.register_units({
		"unit.attacker": {"definition_id":"ship.attacker", "display_name":"攻击舰", "faction_id":"player"},
		"unit.support": {"definition_id":"ship.support", "display_name":"支援舰", "faction_id":"player"},
		"unit.target": {"definition_id":"ship.target", "display_name":"目标舰", "faction_id":"enemy"},
	})
	var ship := {"primary_weapon_group_id":"attacker_main"}
	var main_weapon := {"id":"weapon.main", "mount_type":"Gun", "weapon_group_id":"attacker_main", "control_mode":"ManualPrimary"}
	var secondary_weapon := {"id":"weapon.secondary", "mount_type":"Gun", "weapon_group_id":"attacker_secondary", "control_mode":"Automatic"}
	var torpedo_weapon := {"id":"weapon.torpedo", "mount_type":"Torpedo", "weapon_group_id":"attacker_torpedo", "control_mode":"ManualPrimary"}
	var aviation_weapon := {"id":"weapon.airstrike", "mount_type":"Aviation", "weapon_group_id":"attacker_airstrike", "control_mode":"ManualPrimary"}
	var automatic_main_weapon := {"id":"weapon.destroyer_gun", "mount_type":"Gun", "weapon_group_id":"destroyer_gun", "control_mode":"Automatic"}
	_check(DamageStatistics.category_for({}, main_weapon, ship) == "main_gun", "primary gun group classifies as main gun")
	_check(DamageStatistics.category_for({}, secondary_weapon, ship) == "secondary_gun", "automatic non-primary gun classifies as secondary gun")
	_check(DamageStatistics.category_for({}, automatic_main_weapon, {"primary_weapon_group_id":"destroyer_torpedo"}) == "main_gun", "automatic destroyer battery remains main gun when torpedo is player-controlled")
	_check(DamageStatistics.category_for({}, torpedo_weapon, ship) == "torpedo", "torpedo weapon classifies as torpedo")
	_check(DamageStatistics.category_for({}, aviation_weapon, ship) == "aviation", "aviation weapon classifies as aviation")
	_check(DamageStatistics.category_for({}, {}, ship, {"source_skill_id":"skill.direct"}) == "skill", "explicit direct skill source overrides weapon fallback")
	var events: Array = []
	events.append(_event(DamageStatistics.enrich_result(_result("weapon.main", 150.0, 1000.0), main_weapon, ship)))
	events.append(_event(DamageStatistics.enrich_result(_result("weapon.secondary", 40.0, 850.0), secondary_weapon, ship)))
	events.append(_event(DamageStatistics.enrich_result(_result("weapon.torpedo", 200.0, 80.0), torpedo_weapon, ship)))
	var buffed := _result("weapon.main", 150.0, 600.0)
	buffed["base_final_damage"] = 100.0
	buffed["buff_bonus_damage"] = 50.0
	buffed["buff_contribution_weights"] = {"unit.support": 1.0}
	buffed["buff_contribution_details"] = [{"source_unit_id":"unit.support", "source_skill_id":"skill.support", "weight":1.0}]
	buffed["buff_source_skill_ids"] = ["skill.support"]
	events.append(_event(DamageStatistics.enrich_result(buffed, main_weapon, ship)))
	recorder.consume(events, 1.0)
	var attacker := recorder.unit_damage_statistics("unit.attacker")
	var support := recorder.unit_damage_statistics("unit.support")
	_check(is_equal_approx(float(attacker["damage_dealt"]), 420.0), "effective direct damage excludes torpedo overkill")
	_check(is_equal_approx(float(attacker["overkill_damage"]), 120.0), "overkill damage remains separately available")
	_check(is_equal_approx(float(attacker["damage_by_category"]["main_gun"]), 300.0), "main gun damage aggregates across attacks")
	_check(is_equal_approx(float(attacker["damage_by_category"]["secondary_gun"]), 40.0), "secondary gun damage has an independent bucket")
	_check(is_equal_approx(float(attacker["damage_by_category"]["torpedo"]), 80.0), "torpedo category stores effective damage")
	var category_sum := 0.0
	for value in attacker["damage_by_category"].values():
		category_sum += float(value)
	_check(is_equal_approx(category_sum, float(attacker["damage_dealt"])), "exclusive direct categories reconcile to total effective damage")
	_check(is_equal_approx(float(attacker["damage_by_weapon"]["weapon.main"]), 300.0), "weapon-level detail remains available below categories")
	_check(is_equal_approx(float(support["contribution_damage_by_category"]["buff"]), 50.0), "buff bonus is credited to the support ship without duplicating direct damage")
	_check(is_equal_approx(float(support["contribution_damage_by_skill"]["skill.support"]), 50.0), "buff contribution retains its source skill detail")
	_check(is_equal_approx(recorder.unit_damage_for_category("unit.support", "buff", true), 50.0), "category helper can include contribution damage")
	_check(recorder.all_unit_damage_statistics().size() == 3, "all registered ships remain present even with zero direct damage")
	_check(recorder.unit_damage_statistics("unit.unknown")["damage_dealt"] == 0.0, "unknown ship query returns a stable zero-filled structure")


func _test_battle_session_accessors() -> void:
	var registry = ConfigRegistry.new()
	_check(registry.load_all(), "configuration registry loads for battle integration")
	var session = BattleSession.new(registry)
	_check(bool(session.create_battle("level.prototype_1v1", 17).get("ok", false)), "battle session starts for damage statistics integration")
	var all_units := session.get_all_unit_damage_statistics()
	_check(all_units.has("unit.player.warspite") and all_units.has("unit.enemy.bismarck"), "battle registers every ship before damage occurs")
	_check(session.get_unit_damage_for_category("unit.player.warspite", "main_gun") == 0.0, "battle category accessor is immediately safe to consume")


func _result(weapon_id: String, damage: float, hp_before: float) -> Dictionary:
	return {
		"source_unit_id":"unit.attacker",
		"source_weapon_id":weapon_id,
		"target_unit_id":"unit.target",
		"damage_type":"Gun",
		"hit":true,
		"final_damage":damage,
		"target_hp_before":hp_before,
	}


func _event(result: Dictionary) -> Dictionary:
	return {"event_type":"AttackResolved", "damage_result":result}


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
