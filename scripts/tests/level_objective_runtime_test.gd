extends SceneTree

const BattleSession = preload("res://scripts/application/battle_session.gd")
const ConfigRegistry = preload("res://scripts/infrastructure/data/config_registry.gd")

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

	_test_t02_gunnery(registry)
	_test_t03_skill(registry)
	_test_t04_armor(registry)
	_test_tutorial_definition_validation(registry)

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

	_test_s_challenges(registry)

	if failures.is_empty():
		print("PASS: %d level objective runtime checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error("FAIL: %s" % failure)
		print("FAILED: %d of %d level objective runtime checks" % [failures.size(), checks])
		quit(1)


func _test_s_challenges(registry) -> void:
	var s02 = BattleSession.new(registry)
	_check(s02.create_battle("level.challenge.s02", 8201).get("ok", false), "S-02 creates with its reviewed large-island deployment")
	for unit_id in ["unit.player.s02.chongqing", "unit.player.s02.yukikaze"]:
		var unit: Dictionary = s02.state["units_by_id"][unit_id]
		unit["life_state"] = "Sunk"; unit["current_hp"] = 0.0
	s02.advance_tick(0.1)
	_check(s02.state.get("result", {}).get("winner_faction", "") == "enemy", "S-02 cancels when both named flank ships sink")
	var s03 = BattleSession.new(registry)
	s03.create_battle("level.challenge.s03", 8301)
	var early_flagship: Dictionary = s03.state["units_by_id"]["unit.enemy.s03.bismarck"]
	early_flagship["life_state"] = "Sunk"; early_flagship["current_hp"] = 0.0
	s03.advance_tick(0.1)
	_check(s03.state.get("result", {}).get("winner_faction", "") == "enemy", "S-03 rejects a flagship kill before the carrier")
	var s04 = BattleSession.new(registry)
	s04.create_battle("level.challenge.s04", 8401)
	var hood: Dictionary = s04.state["units_by_id"]["unit.player.s04.hood"]
	hood["current_hp"] = hood["max_hp"] * 0.3
	s04.advance_tick(0.1)
	_check(s04.state.get("result", {}).get("winner_faction", "") == "enemy", "S-04 cancels at Hood's 30 percent protection threshold")
	var s04_wave = BattleSession.new(registry)
	s04_wave.create_battle("level.challenge.s04", 8402)
	var replaced_unit: Dictionary = s04_wave.state["units_by_id"]["unit.enemy.s04.san_diego"]
	replaced_unit["life_state"] = "Sunk"; replaced_unit["current_hp"] = 0.0
	s04_wave.state["elapsed_time"] = 120.0
	s04_wave.advance_tick(0.1)
	_check(s04_wave.state.get("reinforcement_waves", [])[0].get("status", "") == "Spawned" and s04_wave.state["units_by_id"].has("unit.enemy.s04.ward"), "S-04 deterministically spawns Ward after the authored replacement time")
	var s05 = BattleSession.new(registry)
	s05.create_battle("level.challenge.s05", 8501)
	for unit_id in ["unit.enemy.s05.bismarck", "unit.enemy.s05.hindenburg", "unit.enemy.s05.u47"]:
		var unit: Dictionary = s05.state["units_by_id"][unit_id]
		unit["life_state"] = "Sunk"; unit["current_hp"] = 0.0
	s05.advance_tick(0.1)
	_check(s05.state.get("result", {}).get("winner_faction", "") == "player", "S-05 requires its flagship and three enemy losses before immediate success")


func _test_t02_gunnery(registry) -> void:
	var session = BattleSession.new(registry)
	_check(session.create_battle("level.tutorial.t02", 7401).get("ok", false), "T-02 creates from formal runtime data")
	var warspite: Dictionary = session.state["units_by_id"]["unit.player.t02.warspite"]
	var aurora: Dictionary = session.state["units_by_id"]["unit.enemy.t02.aurora"]
	var aurora_start: Vector2 = aurora["position"]
	var aurora_hp := float(aurora["current_hp"])
	var early_events: Array = []
	for _tick in range(40): early_events.append_array(session.advance_tick(0.1))
	_check((aurora["position"] as Vector2).distance_to(aurora_start) > 0.1 and not early_events.any(func(event): return event.get("event_type", "") in ["WeaponFired", "SkillCast"]), "T-02 moves Aurora naturally without attacking before the required actions")
	_check(is_equal_approx(float(aurora["current_hp"]), aurora_hp) and not bool(warspite.get("movement_assist_enabled", true)) and not bool(warspite.get("secondary_auto_fire_enabled", true)), "T-02 preserves public HP while exposing its initial player restrictions")
	session.queue_command({"command_id":"test.t02.ammo","command_type":"SwitchAmmo","issued_at_tick":session.state["tick_index"],"issuer_type":"Player","issuer_id":"player","unit_id":"unit.player.t02.warspite"})
	session.advance_tick(0.1)
	_check(session.state["level_objective"].get("action_counts", {}).get("SwitchAmmo", 0) == 1 and warspite.get("ammo_state", {}).get("warspite_main", "") == "HE", "T-02 records only a successful real ammo switch")
	var target_visible := false
	for _tick in range(700):
		if session.state.get("visible_by_faction", {}).get("player", {}).has("unit.enemy.t02.aurora") and bool(session.get_primary_aim_status("unit.player.t02.warspite", aurora["position"]).get("legal", false)):
			target_visible = true
			break
		session.advance_tick(0.1)
	_check(target_visible, "T-02 natural staging reaches a visible legal manual-gunnery window")
	if target_visible:
		session.queue_command({"command_id":"test.t02.primary","command_type":"FirePrimaryWeapon","issued_at_tick":session.state["tick_index"],"issuer_type":"Player","issuer_id":"player","unit_id":"unit.player.t02.warspite","target_position":aurora["position"]})
		var unlock_events := session.advance_tick(0.1)
		_check(session.state["level_objective"].get("action_counts", {}).get("ManualPrimaryFire", 0) == 1 and bool(session.state["level_objective"].get("engagement_unlocked", false)), "T-02 records a legal manual primary shot and unlocks engagement")
		_check(unlock_events.any(func(event): return event.get("event_type", "") == "TutorialStageChanged") and bool(warspite.get("movement_assist_enabled", false)) and bool(warspite.get("primary_auto_fire_enabled", false)), "T-02 visibly restores authored assist and automatic capabilities")
	aurora["life_state"] = "Sunk"; aurora["current_hp"] = 0.0
	session.advance_tick(0.1)
	_check(session.state.get("result", {}).get("winner_faction", "") == "player" and session.state.get("result", {}).get("reason", "") == "LEVEL_OBJECTIVE_COMPLETED", "T-02 requires its real actions before the target sinking completes the level")


func _test_t03_skill(registry) -> void:
	var session = BattleSession.new(registry)
	_check(session.create_battle("level.tutorial.t03", 7501).get("ok", false), "T-03 creates from formal runtime data")
	var iowa: Dictionary = session.state["units_by_id"]["unit.player.t03.iowa"]
	var kirov: Dictionary = session.state["units_by_id"]["unit.enemy.t03.kirov"]
	var early_events: Array = []
	var target_visible := false
	for _tick in range(700):
		if session.state.get("visible_by_faction", {}).get("player", {}).has("unit.enemy.t03.kirov"):
			target_visible = true
			break
		early_events.append_array(session.advance_tick(0.1))
	_check(target_visible and not early_events.any(func(event): return event.get("event_type", "") in ["WeaponFired", "SkillCast"]), "T-03 reaches a public skill window without either side attacking early")
	if target_visible:
		session.queue_command({"command_id":"test.t03.skill","command_type":"CastSkill","issued_at_tick":session.state["tick_index"],"issuer_type":"Player","issuer_id":"player","unit_id":"unit.player.t03.iowa","target_ref":{"type":"Entity","entity_id":"unit.enemy.t03.kirov"}})
		var unlock_events := session.advance_tick(0.1)
		if session.state["level_objective"].get("action_counts", {}).get("CastSkill", 0) != 1:
			print("T03_DIAGNOSTIC events=%s objective=%s iowa_pos=%s kirov_pos=%s distance=%.2f" % [unlock_events, session.state["level_objective"], iowa["position"], kirov["position"], (iowa["position"] as Vector2).distance_to(kirov["position"])])
		_check(session.state["level_objective"].get("action_counts", {}).get("CastSkill", 0) == 1 and bool(session.state["level_objective"].get("engagement_unlocked", false)), "T-03 records the specified successful SkillCast fact and unlocks engagement")
		_check(unlock_events.any(func(event): return event.get("event_type", "") == "SkillCast" and event.get("skill_id", "") == "skill.iowa_radar_salvo") and bool(iowa.get("primary_auto_fire_enabled", false)), "T-03 uses the public skill command and restores main-gun automation afterward")
	kirov["life_state"] = "Sunk"; kirov["current_hp"] = 0.0
	session.advance_tick(0.1)
	_check(session.state.get("result", {}).get("winner_faction", "") == "player", "T-03 completes after the specified skill and Kirov sinking")


func _test_t04_armor(registry) -> void:
	var session = BattleSession.new(registry)
	_check(session.create_battle("level.tutorial.t04", 7601).get("ok", false), "T-04 creates from formal runtime data")
	var warspite: Dictionary = session.state["units_by_id"]["unit.player.t04.warspite"]
	var ward: Dictionary = session.state["units_by_id"]["unit.player.t04.ward"]
	_check(session.state.get("environment_zones", []).any(func(zone): return zone.get("zone_id", zone.get("id", "")) == "zone.t04.moonlit_lane") and bool(ward.get("secondary_auto_fire_enabled", false)), "T-04 loads the public moonlit lane and visibly keeps Ward secondary automation enabled")
	var staging_events: Array = []
	for _tick in range(1000):
		if bool(session.state["level_objective"].get("engagement_unlocked", false)): break
		staging_events.append_array(session.advance_tick(0.1))
	if not bool(session.state["level_objective"].get("engagement_unlocked", false)):
		print("T04_DIAGNOSTIC objective=%s player_visible=%s warspite_pos=%s ward_pos=%s hindenburg_pos=%s aurora_pos=%s contexts=%s" % [session.state["level_objective"], session.state.get("visible_by_faction", {}).get("player", {}), warspite["position"], ward["position"], session.state["units_by_id"]["unit.enemy.t04.hindenburg"]["position"], session.state["units_by_id"]["unit.enemy.t04.aurora"]["position"], {"ward":session.terrain_context_service.context_at(ward["position"]),"aurora":session.terrain_context_service.context_at(session.state["units_by_id"]["unit.enemy.t04.aurora"]["position"])}])
	_check(bool(session.state["level_objective"].get("engagement_unlocked", false)) and session.state["level_objective"].get("current_step", 0) == 1, "T-04 unlocks only after a real player-faction contact")
	_check(not staging_events.any(func(event): return event.get("event_type", "") in ["WeaponFired", "SkillCast", "AttackResolved"]), "T-04 deals no damage before the authored first-contact stage")
	_check(bool(warspite.get("movement_assist_enabled", false)) and bool(warspite.get("primary_auto_fire_enabled", false)), "T-04 restores the authored player assist and main-gun automation on contact")
	for enemy_id in ["unit.enemy.t04.hindenburg", "unit.enemy.t04.aurora"]:
		var enemy: Dictionary = session.state["units_by_id"][enemy_id]
		enemy["life_state"] = "Sunk"; enemy["current_hp"] = 0.0
	session.advance_tick(0.1)
	_check(session.state.get("result", {}).get("winner_faction", "") == "player" and warspite.get("life_state", "") == "Alive", "T-04 requires both cruisers sunk while Warspite remains alive")


func _test_tutorial_definition_validation(registry) -> void:
	var invalid_trigger: Dictionary = registry.get_definition("objectives", "objective.t04_armor").duplicate(true)
	invalid_trigger["engagement_trigger"] = "Timer"
	_check(_validation_errors(registry, invalid_trigger).any(func(error): return str(error).contains("engagement trigger")), "tutorial validation rejects an unsupported stage trigger")
	var invalid_skill: Dictionary = registry.get_definition("objectives", "objective.t03_skill").duplicate(true)
	invalid_skill["required_actions"][0]["skill_id"] = "skill.missing"
	_check(_validation_errors(registry, invalid_skill).any(func(error): return str(error).contains("mounted skill")), "tutorial validation rejects an unknown or unmounted required skill")
	var invalid_staging: Dictionary = registry.get_definition("objectives", "objective.t02_gunnery").duplicate(true)
	invalid_staging["enemy_staging_positions"] = {"unit.enemy.missing":[100.0, 100.0]}
	_check(_validation_errors(registry, invalid_staging).any(func(error): return str(error).contains("staging unit")), "tutorial validation rejects an unknown authored staging unit")
	var invalid_marker: Dictionary = registry.get_definition("objectives", "objective.t04_armor").duplicate(true)
	invalid_marker["world_markers"][0]["marker_type"] = "HiddenTarget"
	_check(_validation_errors(registry, invalid_marker).any(func(error): return str(error).contains("world marker")), "tutorial validation rejects an unsupported world marker")
	var invalid_control: Dictionary = registry.get_definition("objectives", "objective.t02_gunnery").duplicate(true)
	invalid_control["initial_player_control_state"]["damage_multiplier"] = 2.0
	_check(_validation_errors(registry, invalid_control).any(func(error): return str(error).contains("control state field")), "tutorial validation rejects hidden stat changes in stage control data")


func _validation_errors(registry, objective: Dictionary) -> Array[String]:
	var validator = ConfigRegistry.new()
	validator.definitions = registry.definitions.duplicate(true)
	validator._validate_objective(objective)
	return validator.errors


func _pair(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
