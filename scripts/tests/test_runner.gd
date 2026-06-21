extends SceneTree

const ConfigRegistry = preload("res://scripts/infrastructure/data/config_registry.gd")
const AssetCatalog = preload("res://scripts/infrastructure/assets/asset_catalog.gd")
const BattleSession = preload("res://scripts/application/battle_session.gd")
const ModifierService = preload("res://scripts/domain/services/modifier_service.gd")
const DamageService = preload("res://scripts/domain/services/damage_service.gd")
const SeededRandomSource = preload("res://scripts/infrastructure/random/seeded_random_source.gd")
const UiText = preload("res://scripts/presentation/ui_text.gd")

var failures: Array[String] = []
var checks := 0
var registry
var assets


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	registry = ConfigRegistry.new()
	_check(registry.load_all(), "configuration registry loads: %s" % str(registry.errors))
	_check(registry.all("ships").size() == 6, "six prototype ship definitions load")
	_check(registry.all("levels").size() == 4, "1v1, 3v3, 5v5, and 11v11 levels load")
	var presentation_settings: Dictionary = registry.get_definition("settings", "settings.presentation")
	_check(presentation_settings.get("window", {}).get("logical_size", []) == [1920.0, 1080.0], "presentation settings expose the fixed logical canvas size")
	_check(presentation_settings.get("window", {}).get("size_options", []).size() == 5, "presentation settings expose five window sizes")
	_check(presentation_settings.get("camera", {}).get("min_visible_size", []) == [500.0, 500.0], "camera minimum visible size loads from configuration")
	_check(is_equal_approx(float(presentation_settings.get("camera", {}).get("max_map_visible_fraction", 0.0)), 0.6666667), "camera maximum map fraction loads from configuration")
	_test_chinese_display_text()
	assets = AssetCatalog.new()
	_check(assets.load_all(), "asset catalog loads: %s" % str(assets.errors))
	_test_asset_catalog()
	_test_modifier_order()
	_test_command_and_skill_rules()
	_test_operation_design_rules()
	_test_detection_and_contact_ghost()
	_test_damage_zero_floor()
	_test_simultaneous_flagship_victory()
	_test_determinism()
	_test_battle_smoke("level.prototype_1v1", 3200)
	_test_battle_smoke("level.prototype_3v3", 4200)
	_test_battle_smoke("level.prototype_5v5", 5200)
	_test_battle_smoke("level.prototype_11v11", 7200)
	if failures.is_empty():
		print("PASS: %d checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error("FAIL: %s" % failure)
		print("FAILED: %d of %d checks" % [failures.size(), checks])
		quit(1)


func _test_chinese_display_text() -> void:
	for category in ["ships", "weapons", "skills", "levels"]:
		for definition in registry.all(category):
			_check(_contains_chinese(str(definition.get("display_name", ""))), "%s display name is Chinese: %s" % [category, definition.get("id", "?")])
	_check(UiText.mode_name("level.prototype_11v11") == "11v11 大规模会战", "battle mode has a Chinese display label")
	_check(UiText.ship_class_name("Battleship") == "战列舰", "ship class has a Chinese display label")
	_check(UiText.reason_name("WEAPON_RELOADING") == "武器装填中", "operation reason has a Chinese display label")
	_check(UiText.character_name("warspite") == "厌战号", "character id has a Chinese display label")


func _contains_chinese(value: String) -> bool:
	for index in range(value.length()):
		var code := value.unicode_at(index)
		if code >= 0x4E00 and code <= 0x9FFF:
			return true
	return false


func _test_modifier_order() -> void:
	var effects := [
		{"stat":"Armor","operation":"FlatAdd","value":10.0,"category":"All"},
		{"stat":"Armor","operation":"PercentAdd","value":0.20,"category":"All"},
		{"stat":"Armor","operation":"StateMultiply","value":0.50,"category":"All"},
		{"stat":"Armor","operation":"IndependentMultiply","value":1.10,"category":"All"},
	]
	_check(is_equal_approx(ModifierService.calculate(100.0, effects, "Armor"), 72.6), "modifier order follows flat, percent, state, independent")
	var reload_effects := [{"stat":"ReloadSpeed","operation":"PercentAdd","value":0.50,"category":"Gun"}]
	_check(is_equal_approx(ModifierService.reload_time(10.0, reload_effects, "Gun"), 10.0 / 1.5), "reload speed uses divisor formula")


func _test_asset_catalog() -> void:
	_check(assets.has_character("bismarck"), "asset catalog discovers processed character packages")
	var idle: Dictionary = assets.animation_state("bismarck", "idle")
	_check(idle.get("frames", []).size() == 4 and str(idle["frames"][0]).begins_with("res://"), "character animation state resolves normalized frame paths")
	var wake: Dictionary = assets.vfx_role("bismarck", "wake")
	_check(str(wake.get("file", "")).ends_with("bismarck_vfx_wake.png"), "character VFX role resolves by semantic role")
	var bind: Dictionary = assets.bind_points("bismarck", "bismarck_battle_rig_base.png")
	_check(bind.has("turret_mount_01"), "character bind points resolve per battle asset")
	_check(assets.battle_asset_path("bismarck", "rig_base").ends_with("bismarck_battle_rig_base.png"), "battle asset resolves by semantic suffix")
	_check(assets.ui_asset_path("ui.icon.torpedo", "2x").ends_with("/2x/ui_icon_torpedo.png"), "UI asset resolves by semantic key and export scale")
	_check(not assets.projectile_visual("projectile.surface_torpedo").is_empty(), "projectile visual resolves by projectile id")
	_check(assets.weapon_visual("shimakaze", "shimakaze_torpedo").get("fire_animation_state", "") == "firepower", "weapon visual resolves by character and weapon group")
	_check(float(assets.vfx_playback_profile("vfx.profile.shell_impact").get("duration", 0.0)) > 0.0, "VFX playback profile resolves by semantic id")


func _test_command_and_skill_rules() -> void:
	var session = BattleSession.new(registry)
	_check(session.create_battle("level.prototype_3v3", 9).get("ok", false), "3v3 battle can be created")
	var move_result: Dictionary = session.queue_command({"command_id":"move.1","command_type":"MoveUnits","issued_at_tick":0,"issuer_id":"player","unit_id":"unit.player.aurora","target_position":Vector2(400.0, 300.0)})
	_check(move_result.get("accepted", false), "valid move command enters shared command queue")
	session.advance_tick(0.1)
	_check(session.state["units_by_id"]["unit.player.aurora"]["movement_state"]["mode"] == "PlayerMoveOrder", "move command changes domain movement state")
	var hindenburg: Dictionary = session.state["units_by_id"]["unit.enemy.hindenburg"]
	hindenburg["skill_state"]["cooldown_remaining"] = 0.0
	var cast_result: Dictionary = session._cast_skill(hindenburg, {"type":"Self"}, "skill.1")
	_check(cast_result.get("accepted", false), "ready skill casts successfully")
	_check(float(hindenburg["skill_state"]["cooldown_remaining"]) == 40.0, "successful skill starts cooldown")
	_check(not hindenburg["status_effects"].is_empty(), "skill applies reusable status effects")
	var second_cast: Dictionary = session._cast_skill(hindenburg, {"type":"Self"}, "skill.2")
	_check(second_cast.get("reason_code", "") == "SKILL_ON_COOLDOWN", "skill on cooldown is rejected atomically")
	var aurora: Dictionary = session.state["units_by_id"]["unit.player.aurora"]
	session._sink_unit(aurora, "test")
	session.queue_command({"command_id":"move.sunk","command_type":"MoveUnits","issued_at_tick":1,"issuer_id":"player","unit_id":"unit.player.aurora","target_position":Vector2(500.0, 300.0)})
	var events: Array = session.advance_tick(0.1)
	_check(_has_event_reason(events, "CommandRejected", "UNIT_SUNK"), "sunk unit cannot accept tactical commands")


func _test_operation_design_rules() -> void:
	var session = BattleSession.new(registry)
	session.create_battle("level.prototype_1v1", 21)
	var player: Dictionary = session.state["units_by_id"]["unit.player.warspite"]
	var enemy: Dictionary = session.state["units_by_id"]["unit.enemy.bismarck"]
	player["position"] = Vector2(300.0, 350.0)
	enemy["position"] = Vector2(830.0, 350.0)
	player["heading"] = 0.0
	enemy["heading"] = PI
	player["movement_state"]["mode"] = "HoldPosition"
	enemy["movement_state"]["mode"] = "HoldPosition"
	for index in range(30): session.advance_tick(0.1)
	var auto_events := session.drain_events()
	_check(not _has_event(auto_events, "WeaponFired"), "ManualPrimary weapon does not participate in automatic fire")
	_check(session.get_player_slots()[0]["unit_id"] == "unit.player.warspite", "slot 1 selects the first fleet member")
	session.queue_command({"command_id":"primary.1","command_type":"FirePrimaryWeapon","issued_at_tick":session.state["tick_index"],"issuer_id":"player","unit_id":"unit.player.warspite","target_position":enemy["position"]})
	var fire_events: Array = session.advance_tick(0.1)
	_check(_has_event(fire_events, "WeaponFired"), "E-style primary confirmation creates a weapon fire fact")
	var ap_state := _weapon_state(player, "weapon.warspite_381_ap")
	var he_state := _weapon_state(player, "weapon.warspite_381_he")
	_check(float(ap_state["reload_remaining"]) > 0.0 and is_equal_approx(float(ap_state["reload_remaining"]), float(he_state["reload_remaining"])), "HE/AP modes share cooldown after primary fire")
	var reload_after_fire := float(ap_state["reload_remaining"])
	_check(not session.delayed_attacks.is_empty() and session.delayed_attacks[0]["source_weapon_id"] == "weapon.warspite_381_ap", "already-fired shell keeps launch-time ammo definition")
	session.queue_command({"command_id":"ammo.1","command_type":"SwitchAmmo","issued_at_tick":session.state["tick_index"],"issuer_id":"player","unit_id":"unit.player.warspite"})
	session.advance_tick(0.1)
	_check(player["ammo_state"]["warspite_main"] == "HE", "Q switches HE/AP ammo state")
	_check(float(ap_state["reload_remaining"]) < reload_after_fire and float(ap_state["reload_remaining"]) > 0.0, "Q does not reset shared reload progress")
	session._sink_unit(player, "test")
	_check(session.get_player_slots()[0]["unit_id"] == "unit.player.warspite", "slot remains stable after sinking")


func _test_detection_and_contact_ghost() -> void:
	var session = BattleSession.new(registry)
	session.create_battle("level.prototype_1v1", 11)
	var player: Dictionary = session.state["units_by_id"]["unit.player.warspite"]
	var enemy: Dictionary = session.state["units_by_id"]["unit.enemy.bismarck"]
	player["position"] = Vector2(400.0, 350.0)
	enemy["position"] = Vector2(740.0, 350.0)
	player["movement_state"]["mode"] = "HoldPosition"
	enemy["movement_state"]["mode"] = "HoldPosition"
	session._update_detection(0.1)
	_check(session.state["visible_by_faction"]["player"].has(enemy["entity_id"]), "dual detection boundary acquires target")
	enemy["position"] = Vector2(1000.0, 350.0)
	session._update_detection(0.1)
	var contact: Dictionary = session.state["contacts_by_faction"]["player"].get(enemy["entity_id"], {})
	_check(not contact.is_empty() and not contact.get("visible", true), "lost target creates a last-known-position contact")
	for index in range(30): session._update_detection(0.1)
	_check(not session.state["contacts_by_faction"]["player"].has(enemy["entity_id"]), "contact ghost expires after three seconds")


func _test_damage_zero_floor() -> void:
	var source := {"entity_id":"source","position":Vector2.ZERO,"stats":{"gunnery_power":1.0},"status_effects":[]}
	var target := {"entity_id":"target","position":Vector2(10.0,0.0),"current_hp":100.0,"stats":{"armor":999.0,"armor_thickness":"Heavy","evasion":0.0},"status_effects":[]}
	var weapon := {"mount_type":"Gun","range":100.0,"accuracy_modifier":0.0,"armor_damage_modifiers":{"Heavy":0.1}}
	var formula := {"base_damage":1.0,"base_hit_rate":1.0,"power_coefficient":1.0,"armor_coefficient":1.0,"evasion_coefficient":0.0,"distance_penalty_coefficient":0.0,"hit_rate_min":1.0,"hit_rate_max":1.0}
	var result: Dictionary = DamageService.resolve({"attack_id":"zero"}, source, target, weapon, formula, SeededRandomSource.new(1), true)
	_check(float(result["final_damage"]) == 0.0 and float(result["target_hp_after"]) == 100.0, "armor can reduce damage to zero and later bonuses do not revive it")


func _test_simultaneous_flagship_victory() -> void:
	var session = BattleSession.new(registry)
	session.create_battle("level.prototype_1v1", 17)
	session.state["units_by_id"]["unit.player.warspite"]["life_state"] = "Sunk"
	session.state["units_by_id"]["unit.player.warspite"]["current_hp"] = 0.0
	session.state["units_by_id"]["unit.enemy.bismarck"]["life_state"] = "Sunk"
	session.state["units_by_id"]["unit.enemy.bismarck"]["current_hp"] = 0.0
	session._check_victory()
	_check(session.state["result"].get("winner_faction", "") == "player", "simultaneous flagship sinking awards player victory")


func _test_determinism() -> void:
	var first := _simulate("level.prototype_1v1", 2468, 3200)
	var second := _simulate("level.prototype_1v1", 2468, 3200)
	_check(first["result"] == second["result"], "same seed produces same battle result")
	_check(first["events"] == second["events"], "same seed produces identical event type sequence")
	_check(first["stats"] == second["stats"], "same seed produces identical analytics")


func _test_battle_smoke(level_id: String, maximum_ticks: int) -> void:
	var simulation := _simulate(level_id, 20260614, maximum_ticks)
	_check(simulation["phase"] == "Finished", "%s headless battle reaches Finished" % level_id)
	_check(not simulation["result"].is_empty(), "%s records a battle result" % level_id)
	_check(simulation["events"].has("WeaponFired") and simulation["events"].has("AttackResolved") and simulation["events"].has("BattleFinished"), "%s emits complete combat event chain" % level_id)


func _simulate(level_id: String, seed_value: int, maximum_ticks: int) -> Dictionary:
	var session = BattleSession.new(registry)
	var creation: Dictionary = session.create_battle(level_id, seed_value)
	var event_types: Array[String] = []
	for event in session.drain_events(): event_types.append(str(event["event_type"]))
	if not creation.get("ok", false): return {"phase":"Failed","result":{},"events":event_types,"stats":{}}
	for index in range(maximum_ticks):
		var events: Array = session.advance_tick(0.1)
		for event in events: event_types.append(str(event["event_type"]))
		if session.state["phase"] == "Finished": break
	return {"phase":session.state["phase"],"result":session.state["result"].duplicate(true),"events":event_types,"stats":session.get_statistics()}


func _has_event_reason(events: Array, event_type: String, reason_code: String) -> bool:
	for event in events:
		if event.get("event_type", "") == event_type and event.get("reason_code", "") == reason_code: return true
	return false


func _has_event(events: Array, event_type: String) -> bool:
	for event in events:
		if event.get("event_type", "") == event_type: return true
	return false


func _weapon_state(unit: Dictionary, weapon_id: String) -> Dictionary:
	for weapon_state in unit.get("weapon_states", []):
		if weapon_state.get("definition_id", "") == weapon_id: return weapon_state
	return {}


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
