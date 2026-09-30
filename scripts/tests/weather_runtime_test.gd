extends SceneTree
const Registry = preload("res://scripts/infrastructure/data/config_registry.gd")
const Context = preload("res://scripts/domain/services/terrain_context_service.gd")
const Session = preload("res://scripts/application/battle_session.gd")
var registry
var checks := 0
var failures: Array[String] = []

func _init(): call_deferred("run")

func check(value: bool, message: String):
	checks += 1
	if not value: failures.append(message)

func context(id := "environment.timeline.storm_passage", harbor := false):
	var service = Context.new()
	var timeline: Dictionary = registry.get_definition("environment_zones", id)
	service.configure(null, registry.get_definition("environment_zones", "environment.zone_set.harbor_mouth_16x9") if harbor else {}, registry.all("environment_zones"), str(timeline.stages[0].ocean_palette), timeline)
	return service

func run():
	registry = Registry.new()
	check(registry.load_all(), "registry loads")
	configuration()
	timelines()
	runtime()
	complete_session_timelines()
	aviation_weather()
	await presentation()
	for failure in failures: push_error(failure)
	print("%s: %d weather runtime checks" % ["PASS" if failures.is_empty() else "FAILED", checks])
	quit(0 if failures.is_empty() else 1)

func configuration():
	var original: Dictionary = registry.get_definition("environment_zones", "environment.timeline.storm_passage")
	for field in ["duplicate", "negative", "precision", "palette", "first", "loop", "forecast", "type"]:
		var definition := original.duplicate(true)
		match field:
			"duplicate": definition.stages[1].start_seconds = 0
			"negative": definition.stages[1].start_seconds = -1
			"precision": definition.stages[1].start_seconds = 60.01
			"palette": definition.stages[1].ocean_palette = "snow_day"
			"first": definition.stages[0].start_seconds = 1
			"loop": definition.loop_seconds = 240
			"forecast": definition.forecast_seconds = -10
			"type": definition.stages = "bad"
		check(not registry.validate_environment_timeline(definition).is_empty(), "reject malformed " + field)
	check(not registry.validate_environment_map({"ocean_palette":"clear_day", "environment_timeline_id":"missing"}).is_empty(), "reject unknown timeline")
	check(not registry.validate_environment_map({"ocean_palette":"rain_day", "environment_timeline_id":original.id}).is_empty(), "reject initial mismatch")
	check(registry.validate_environment_map({"ocean_palette":"day_clear"}).is_empty(), "legacy fixed palette alias accepted")

func timelines():
	var service = context()
	var facts: Array = []
	for tick in range(1, 3001):
		facts.append_array(service.advance(0.1))
		var snapshot: Dictionary = service.global_snapshot()
		if tick == 499: check(snapshot.forecast.is_empty() and snapshot.canonical_ocean_palette == "clear_day", "49.9 no forecast")
		if tick == 500: check(snapshot.forecast.remaining_seconds == 10.0 and snapshot.forecast.ocean_palette == "overcast_day", "50 forecast starts")
		if tick == 599: check(is_equal_approx(snapshot.forecast.remaining_seconds, 0.1) and snapshot.canonical_ocean_palette == "clear_day", "59.9 original weather")
		if tick in [600, 1200, 1800, 2400, 3000]:
			var expected := {600:"overcast_day", 1200:"thunderstorm_day", 1800:"rain_day", 2400:"clear_day", 3000:"clear_day"}
			check(snapshot.canonical_ocean_palette == expected[tick] and snapshot.forecast.is_empty(), "stage at tick %d" % tick)
	check(facts.filter(func(e): return e.event_type == "GlobalEnvironmentForecast").size() == 4, "one forecast per change")
	check(facts.filter(func(e): return e.event_type == "GlobalEnvironmentChanged").size() == 4, "finite timeline holds final stage")
	var replay = context()
	var replay_facts: Array = []
	for tick in range(3000): replay_facts.append_array(replay.advance(0.1))
	check(facts == replay_facts, "deterministic replay")
	var cycle = context("environment.timeline.day_cycle")
	cycle.advance(230.0)
	check(cycle.global_snapshot().canonical_ocean_palette == "clear_night" and cycle.global_snapshot().forecast.ocean_palette == "clear_dawn", "cycle preannounces wrap")
	cycle.advance(10.0)
	check(cycle.global_snapshot().canonical_ocean_palette == "clear_dawn" and cycle.global_snapshot().cycle == 1, "240 cycle wraps")
	cycle.advance(240.0)
	check(cycle.global_snapshot().cycle == 2, "second cycle")
	var harbor = context("environment.timeline.storm_passage", true)
	harbor.advance(59.9)
	var elapsed: float = harbor.global_elapsed
	var zones: Array = harbor.snapshot()
	var tide: int = harbor.tide_phase_index
	var baseline: Dictionary = harbor.global_context()
	for index in range(3):
		harbor.override_environment("thunderstorm_night", "Validation")
		check(is_equal_approx(float(harbor.global_context().torpedo_sigma_multiplier), 3.0), "storm sigma cap")
		harbor.override_environment("clear_day", "Validation")
	check(harbor.global_context() == baseline, "repeated switches restore authored baseline without accumulation")
	check(harbor.snapshot() == zones and harbor.global_elapsed == elapsed and harbor.tide_phase_index == tide, "override preserves zones and tide")
	harbor.advance(0.1)
	check(harbor.global_snapshot().timeline_id == "" and harbor.global_snapshot().canonical_ocean_palette == "clear_day", "override cancels scheduled boundary")
	harbor.advance(160.0)
	check(harbor.snapshot().filter(func(z): return z.id.ends_with("fog_bank") and not z.active).size() == 1, "local fog still dissipates")

func runtime():
	var level: Dictionary = registry.get_definition("levels", "level.prototype_3v3").duplicate(true)
	level.map.ocean_palette = "clear_day"
	level.map.environment_timeline_id = "environment.timeline.storm_passage"
	var session = Session.new(registry)
	check(session.create_battle_from_definition(level, 9330).ok, "dynamic session creates")
	check(not session.queue_environment_override("snow_day").accepted, "unknown override rejected")
	check(not session.queue_environment_override("rain_day", "Player").accepted, "player source rejected")
	check(not session.queue_command({"command_type":"SetEnvironment"}).accepted, "unit queue cannot change environment")
	var initial: Dictionary = session.state.global_environment.duplicate(true)
	session.pause()
	check(session.queue_environment_override("thunderstorm_night", "Validation").accepted, "paused override queues")
	check(session.advance_tick(0.1).is_empty() and session.state.global_environment == initial, "pause freezes authoritative environment")
	session.resume()
	var facts: Array = session.advance_tick(0.1)
	check(facts.filter(func(e): return e.event_type == "GlobalEnvironmentChanged").size() == 1, "override emits one fact")
	check(session.presentation_events(facts).any(func(e): return e.event_type == "GlobalEnvironmentChanged"), "global change survives presentation filtering")
	var env: Dictionary = session.state.global_environment
	check(env.canonical_ocean_palette == "thunderstorm_night" and env.timeline_id == "", "runtime override authoritative and disables timeline")
	check(is_equal_approx(env.global_effects.optical_visibility_multiplier, 0.45) and is_equal_approx(env.global_effects.movement_speed_multiplier, 0.8), "global HUD effects use Domain final rules")
	var unit: Dictionary = session.state.units_by_id["unit.player.warspite"]
	check(is_equal_approx(float(session._detection_unit_fact(unit).optical_visibility_multiplier), 0.45), "observation facts read new weather")
	check(is_equal_approx(float(session.terrain_context_service.motion_context_at(unit.position).movement_speed_multiplier), 0.8), "motion reads new weather")
	check(is_equal_approx(float(session._environment_accuracy_modifier("player", unit.position, unit.position, "Gun")), -0.29), "weapon accuracy reads new weather")
	check(is_equal_approx(float(session._aviation_delay_multiplier(unit.position, unit.position)), 2.944), "aviation delay reads new weather")
	check(is_equal_approx(float(session.terrain_context_service.context_at(unit.position).torpedo_sigma_multiplier), 3), "torpedo source reads new weather")
	var due_ticks := {}
	for ship in session.state.units_by_id.values(): due_ticks[ship.navigation_state.next_normal_plan_tick] = true
	check(due_ticks.size() > 1, "environment rebuild returns to staggered navigation schedule")
	check(session.snapshot("enemy").global_environment == env, "both factions share global conditions")
	session.state.phase = "Finished"
	check(not session.queue_environment_override("clear_day").accepted and session.advance_tick().is_empty(), "finished session freezes environment")
	check(session.create_battle_from_definition(level, 9330).ok and session.state.global_environment.canonical_ocean_palette == "clear_day" and session.state.global_environment.stage_index == 0, "restart restores initial stage")
	# Cross a real timeline boundary with both movement intentions and an in-flight attack.
	session.terrain_context_service.advance(59.9)
	unit = session.state.units_by_id["unit.player.warspite"]
	var movement: Dictionary = unit.movement_state.duplicate(true)
	var attack := {"attack_id":"weather.inflight", "resolve_at_time":99999.0, "accuracy_modifier":0.123, "source_unit_id":unit.entity_id}
	session.delayed_attacks.append(attack.duplicate(true))
	facts = session.advance_tick(0.1)
	check(session.state.global_environment.canonical_ocean_palette == "overcast_day", "automatic boundary applies within session tick")
	check(session.delayed_attacks.any(func(a): return a == attack), "in-flight launch parameters unchanged")
	check(unit.movement_state == movement, "weather replan preserves held movement intention")
	check(facts.any(func(e): return e.event_type == "GlobalEnvironmentChanged"), "scheduled boundary recorded")

func presentation():
	var menu = load("res://scenes/menu/main_menu.tscn").instantiate()
	root.add_child(menu)
	menu._show_custom()
	check(menu.custom_environment_selector.item_count == 3 and not menu.custom_weather_selector.disabled, "custom menu fixed default and three modes")
	for id in ["environment.timeline.storm_passage", "environment.timeline.day_cycle"]:
		menu.custom_environment_id = id
		menu._refresh_environment_schedule()
		check(menu.custom_weather_selector.disabled and menu.custom_environment_schedule.text.contains("60秒"), "dynamic menu disables fixed selector and shows schedule")
	menu.custom_environment_id = ""
	menu.custom_weather_id = "rain_night"
	menu._refresh_environment_schedule()
	check(not menu.custom_weather_selector.disabled and menu.custom_weather_selector.get_item_metadata(menu.custom_weather_selector.selected) == "rain_night", "fixed selection restored")
	var flow = root.get_node("GameFlow")
	var fleet: Array[String] = ["ship.warspite", "ship.shimakaze", "ship.argus"]
	for id in fleet:
		if id not in flow.unlocked_ship_ids: flow.unlocked_ship_ids.append(id)
	check(flow.configure_custom_battle("level.prototype_3v3", "level.prototype_3v3", "rain_night", fleet, "environment.timeline.day_cycle").ok, "custom timeline accepted")
	var level: Dictionary = flow.runtime_level_definition("level.custom_runtime")
	check(level.map.ocean_palette == "clear_dawn" and level.map.environment_timeline_id == "environment.timeline.day_cycle", "custom timeline controls initial palette")
	var battle = load("res://scenes/battle/prototype_battle.tscn").instantiate()
	root.add_child(battle)
	battle.set_process(false)
	check(battle.current_palette_id == "clear_dawn", "scene initializes from authority")
	check(battle._set_ocean_palette("thunderstorm_night").accepted and battle.current_palette_id == "clear_dawn", "visual waits for accepted fixed tick")
	battle._consume_events(battle.session.advance_tick(0.1))
	battle._sync_visuals()
	battle._update_hud()
	check(battle.current_palette_id == "thunderstorm_night" and battle.session.state.global_environment.canonical_ocean_palette == battle.current_palette_id, "debug visual and rule stay synchronized")
	check(battle.recent_messages.any(func(m): return m.contains("环境变化")), "weather change logged")
	check(battle.battle_hud.weather_button.text.contains("海况5") and battle.battle_hud.weather_button.tooltip_text.contains("0.45"), "HUD displays weather and rule details")
	battle.battle_hud.weather_button.pressed.emit()
	await process_frame
	await process_frame
	check(battle.battle_hud.weather_details.visible, "weather details opens")
	check(battle.battle_hud.battle_rect().encloses(battle.battle_hud.weather_details.get_rect()), "weather details stays inside sea frame after layout")
	battle.battle_hud.weather_details.get_node("Column/Close").pressed.emit()
	check(not battle.battle_hud.weather_details.visible, "weather details closes")
	# Initial overrides must be correct before the first simulation Tick.
	battle.palette_override = "rain_night"
	battle._start_battle("level.custom_runtime")
	check(battle.session.state.tick_index == 0 and battle.session.state.global_environment.canonical_ocean_palette == "rain_night" and battle.session.state.global_environment.timeline_id == "", "initial debug override precedes first tick")
	battle.queue_free()
	menu.queue_free()
	await process_frame


func complete_session_timelines():
	for id in ["environment.timeline.storm_passage", "environment.timeline.day_cycle"]:
		var signatures: Array = []
		for replay in range(2):
			var level: Dictionary = registry.get_definition("levels", "level.prototype_1v1").duplicate(true)
			level.map.environment_timeline_id = id
			level.map.ocean_palette = registry.get_definition("environment_zones", id).stages[0].ocean_palette
			level.time_limit = 600
			var session = Session.new(registry)
			check(session.create_battle_from_definition(level, 9330).ok, "full timeline session creates")
			session._full_ai_factions.clear()
			for unit in session.state.units_by_id.values():
				unit.secondary_auto_fire_enabled = false
				unit.primary_auto_fire_enabled = false
				unit.skill_auto_cast_enabled = false
			var signature: Array = []
			for tick in range(3000):
				for event in session.advance_tick(0.1):
					if event.event_type in ["GlobalEnvironmentChanged", "GlobalEnvironmentForecast"]: signature.append(event)
			check(session.state.phase == "Running" and session.state.tick_index == 3000, "300 seconds through actual fixed-tick session")
			check(signature.size() == (8 if id.ends_with("storm_passage") else 10), "all scheduled forecasts and changes recorded")
			check(session.state.global_environment.canonical_ocean_palette == "clear_day", "final session palette")
			signatures.append(signature)
		check(signatures[0] == signatures[1], "same-seed full session environment replay")


func aviation_weather():
	for mode in ["Abstract", "Physical"]:
		var level: Dictionary = registry.get_definition("levels", "level.prototype_1v1").duplicate(true)
		level.map.ocean_palette = "clear_day"
		level.player_fleet[0].ship_id = "ship.enterprise_cv6"
		level.aviation_rules_mode = mode
		var session = Session.new(registry)
		check(session.create_battle_from_definition(level, 9330).ok, "carrier session creates " + mode)
		session._full_ai_factions.clear()
		var source: Dictionary = session.state.units_by_id["unit.player.warspite"]
		var target: Dictionary = session.state.units_by_id["unit.enemy.bismarck"]
		source.position = Vector2(400,400)
		target.position = Vector2(900,400)
		for unit in session.state.units_by_id.values():
			unit.secondary_auto_fire_enabled = false
			unit.primary_auto_fire_enabled = false
			session.state.visible_by_faction.player = {target.entity_id:true}
		session.queue_environment_override("thunderstorm_day", "Validation")
		session.advance_tick(0.1)
		var blocked: Dictionary = session._fire_primary_weapon(source, target.position, "weather.air.blocked")
		check(blocked.get("reason_code", "") == "AVIATION_WEATHER_BLOCKED", "new severe weather blocks launch " + mode)
		session.queue_environment_override("clear_day", "Validation")
		session.advance_tick(0.1)
		check(session._fire_primary_weapon(source, target.position, "weather.air.clear").get("accepted", false), "clearing weather restores launch " + mode)
