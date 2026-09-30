extends "res://scripts/tests/challenge_mission_feedback_test.gd"

const Session = preload("res://scripts/application/battle_session.gd")
const Loader = preload("res://scripts/infrastructure/simulation/experiment_loader.gd")
const Aggregator = preload("res://scripts/infrastructure/simulation/simulation_aggregator.gd")

func _run() -> void:
	var registry = root.get_node("DataRegistry").registry
	var route_evidence: Array = []
	_check(registry.errors.is_empty(), "registry has no loading errors: %s" % [registry.errors])
	for chapter in ["m", "l"]:
		for index in range(1, 6):
			var code := "%s%02d" % [chapter, index]
			var level: Dictionary = registry.get_definition("levels", "level.challenge." + code)
			var scenario := _scenario(registry, code)
			var required: Array = scenario.service.definition["required_enemy_unit_ids"]
			for id in required: _sink(scenario.state, id)
			if code in ["m05", "l05"]:
				_check(scenario.service.advance(scenario.state).terminal.is_empty(), code + " flagship alone insufficient")
				var minimum := int(scenario.service.definition.minimum_enemy_sunk)
				for member in level.enemy_fleet.slice(0, minimum): _sink(scenario.state, member.entity_id)
			_check(scenario.service.advance(scenario.state).terminal.get("winner_faction") == "player", code + " mission completes")
			_check(scenario.service.advance(scenario.state).events.is_empty(), code + " unique terminal")
			var failed := _scenario(registry, code)
			for member in level.enemy_fleet: _sink(failed.state, member.entity_id)
			_sink(failed.state, level.player_fleet[0].entity_id)
			_check(failed.service.advance(failed.state).terminal.get("winner_faction") == "enemy", code + " same Tick flagship loss wins precedence")
			for protected in scenario.service.definition.protected_player_unit_ids:
				var loss := _scenario(registry, code)
				_sink(loss.state, protected)
				_check(loss.service.advance(loss.state).terminal.get("winner_faction") == "enemy", code + " protected unit loss")
			var session = Session.new(registry)
			_check(session.create_battle(level.id, 1).get("ok", false), code + " creates")
			_check(session.state.units_by_id.size() == (10 if chapter == "m" else 22), code + " correct initial cap")
			_check(session.state.get("facilities_by_id", {}).is_empty(), code + " facilities disabled")
			_check(not root.get_node("DataRegistry").assets.minimap_asset_path(level.map.terrain_definition_id).is_empty(), code + " minimap bound")
			for unit in session.state.units_by_id.values():
				_check(session.terrain_query.can_occupy_circle(unit.position, unit.stats.collision_radius, session._movement_tags(unit)), code + " actual hull legal " + unit.entity_id)
			var enemy_flag: Dictionary = session.state.units_by_id[session.state.fleets_by_id["fleet.enemy"].flagship_unit_id]
			for member in level.player_fleet:
				var unit: Dictionary = session.state.units_by_id[member.entity_id]
				var path: Dictionary = session.route_planner.plan_path(session.terrain_query, session.navigation_definition, unit.position, enemy_flag.position, unit.stats.collision_radius, session._movement_tags(unit), session.terrain_context_service)
				route_evidence.append({"level":code, "unit":member.entity_id, "radius":unit.stats.collision_radius, "origin":unit.position, "destination":enemy_flag.position, "route":path})
				_check(path.get("ok", false) and not path.get("target_projected", false), code + " connected complete route " + member.entity_id)
			if code == "m01":
				for phase in range(4):
					if phase > 0: session.terrain_context_service.advance(45.0)
					var unit: Dictionary = session.state.units_by_id[level.player_fleet[0].entity_id]
					var path: Dictionary = session.route_planner.plan_path(session.terrain_query, session.navigation_definition, unit.position, enemy_flag.position, unit.stats.collision_radius, session._movement_tags(unit), session.terrain_context_service)
					_check(path.get("ok", false) and not path.get("target_projected", false), "M01 exact route in tide phase %d" % phase)
			_check(Loader.new().load_manifest("res://data/simulations/experiments/level_%s_win_rate_20.json" % code).ok, code + " valid 20-seed manifest")
			if index >= 4:
				_check(session.terrain_context_service.global_context().aviation_condition == "Severe", code + " starts grounded")
				session.terrain_context_service.advance(60.0)
				_check(session.terrain_context_service.global_context().aviation_condition == "Restricted", code + " rain opens aviation")
	for code in ["m03", "l02", "l03"]:
		for reverse_order in [false, true]:
			var case := _scenario(registry, code)
			var stages: Array = case.service.definition.optional_enemy_sunk_stages
			var first: Array = stages[0].duplicate()
			if reverse_order: first.reverse()
			for id in first:
				_sink(case.state, id)
				case.service.advance(case.state)
			_sink(case.state, stages[1][0])
			case.service.advance(case.state)
			_check(not case.service.snapshot().optional_order_failed and case.service.snapshot().optional_order_progress == 2, code + " unordered stage accepts either order")
		var simultaneous := _scenario(registry, code)
		for stage in simultaneous.service.definition.optional_enemy_sunk_stages:
			for id in stage: _sink(simultaneous.state, id)
		simultaneous.service.advance(simultaneous.state)
		_check(not simultaneous.service.snapshot().optional_order_failed, code + " grouped same Tick")
		var early := _scenario(registry, code)
		_sink(early.state, early.service.definition.optional_enemy_sunk_stages[1][0])
		_check(early.service.advance(early.state).terminal.get("winner_faction") == "player" and early.service.snapshot().optional_order_failed, code + " missed mastery still wins")
	for code in ["m05", "l05"]:
		var count_first := _scenario(registry, code)
		var level: Dictionary = registry.get_definition("levels", "level.challenge." + code)
		for member in level.enemy_fleet.slice(1, int(count_first.service.definition.minimum_enemy_sunk) + 1): _sink(count_first.state, member.entity_id)
		_check(count_first.service.advance(count_first.state).terminal.is_empty(), code + " count alone cannot win")
		_sink(count_first.state, level.enemy_fleet[0].entity_id)
		_check(count_first.service.advance(count_first.state).terminal.get("winner_faction") == "player", code + " count then flagship succeeds")
		var active = Session.new(registry)
		active.create_battle(level.id, 1)
		active.configure_full_ai_factions(["player", "enemy"])
		_sink(active.state, level.enemy_fleet[0].entity_id)
		active.advance_tick(0.1)
		_check(active.state.phase == "Running", code + " flagship-first does not stop runtime")
		_check(active.state.units_by_id[level.enemy_fleet[1].entity_id].ai_state.get("mode_id", "") != "", code + " surviving enemy continues AI intent")
	var limited := _scenario(registry, "m04")
	var ids: Array = limited.service.definition.required_any_player_unit_ids
	for id in ids.slice(1, 3): _sink(limited.state, id)
	_check(limited.service.advance(limited.state).terminal.is_empty(), "M04 permits two nonflagship losses")
	_sink(limited.state, ids[3])
	_check(limited.service.advance(limited.state).terminal.get("winner_faction") == "enemy", "M04 third loss cancels")
	var objective: Dictionary = registry.get_definition("objectives", "objective.m03_flanks")
	for bad in [[], "invalid", [[]], [["unit.enemy.m03.gnevny"], ["unit.enemy.m03.gnevny"]], [["unit.player.m03.hood"], ["unit.enemy.m03.iowa"]], [["missing"], ["unit.enemy.m03.iowa"]]]:
		var validator := ConfigRegistry.new()
		validator.definitions = registry.definitions
		var definition := objective.duplicate(true)
		definition.optional_enemy_sunk_stages = bad
		validator._validate_objective(definition)
		_check(not validator.errors.is_empty(), "reject malformed grouped mastery")
	var reinforcement = Session.new(registry)
	reinforcement.create_battle("level.challenge.l05", 1)
	reinforcement.state.elapsed_time = 301.0
	reinforcement._update_reinforcements()
	_check(reinforcement.state.reinforcement_waves[0].status == "Pending", "full fleet waits")
	var enemy_ids: Array = reinforcement.state.fleets_by_id["fleet.enemy"].unit_ids
	_sink(reinforcement.state, enemy_ids[1])
	var wave: Dictionary = reinforcement.state.reinforcement_waves[0].definition
	var blocker: Dictionary = reinforcement.state.units_by_id[enemy_ids[2]]
	var previous: Vector2 = blocker.position
	blocker.position = Vector2(wave.members[0].position[0], wave.members[0].position[1])
	reinforcement._update_reinforcements()
	_check(reinforcement.state.reinforcement_waves[0].status == "Pending", "occupied spawn waits")
	blocker.position = Vector2(wave.members[0].position[0] + 80, wave.members[0].position[1])
	blocker.heading = 0.0
	wave.members[0].heading = 0.0
	_check(not reinforcement._reinforcement_positions_safe(wave, "fleet.enemy"), "ellipse overlap rejects an entrance beyond legacy circle radii")
	# A later wave may use the free slot while the first entrance is blocked.
	for unit in reinforcement.state.units_by_id.values():
		if str(unit.entity_id).ends_with("_reserve"): _sink(reinforcement.state, unit.entity_id)
	blocker.position = previous
	reinforcement._update_reinforcements()
	_check(reinforcement.state.reinforcement_waves[0].status == "Spawned", "safe free slot spawns")
	var whole = Session.new(registry)
	whole.create_battle("level.challenge.l05", 1)
	whole.state.elapsed_time = 301.0
	var fleet: Array = whole.state.fleets_by_id["fleet.enemy"].unit_ids
	var members: Array = whole.state.reinforcement_waves[0].definition.members
	var extra: Dictionary = members[0].duplicate(true)
	extra.entity_id = "unit.enemy.test.second_reserve"
	var vacant: Vector2 = whole.state.units_by_id[fleet[1]].position
	extra.position = [vacant.x, vacant.y]
	members.append(extra)
	_sink(whole.state, fleet[1])
	whole.state.reinforcement_waves[1].definition.earliest_time = 2000.0
	whole._update_reinforcements()
	_check(whole.state.reinforcement_waves[0].status == "Pending", "two-member wave waits for two slots atomically")
	_sink(whole.state, fleet[2])
	whole._update_reinforcements()
	_check(whole.state.reinforcement_waves[0].status == "Spawned" and whole.state.units_by_id.has(extra.entity_id), "entire safe wave enters together")
	var reversed: Dictionary = registry.get_definition("levels", "level.challenge.l05").duplicate(true)
	reversed.reinforcement_waves.reverse()
	whole._initialize_reinforcements(reversed)
	_check(whole.state.reinforcement_waves[0].wave_id == "wave.l05.01", "waves sort independently of file order")
	var ending = Session.new(registry)
	ending.create_battle("level.challenge.l05", 1)
	ending._finish_battle("player", "TEST_COMPLETED")
	_check(ending.state.reinforcement_waves.all(func(w): return w.status == "Cancelled"), "terminal cancels pending reinforcements")
	ending.state.elapsed_time = 1000
	ending._update_reinforcements()
	_check(ending.state.units_by_id.size() == 22, "finished battle cannot spawn reserves")
	var mixed := Aggregator.new().aggregate([
		{"end_state":"Finished", "winner_faction":"player", "duration":1.0, "ai_behavior":{"path_stuck_events":2}},
		{"end_state":"TechnicalLimit", "duration":1200.0, "ai_behavior":{"path_stuck_events":7}}
	])
	_check(mixed.finished_runs == 1 and mixed.ai_behavior.path_stuck_events == 2 and mixed.ai_behavior_all_attempts.path_stuck_events == 9 and mixed.ai_behavior_invalid_attempts.path_stuck_events == 7, "invalid behavior preserved separately from win denominator")
	DirAccess.make_dir_recursive_absolute("res://reports/challenges/20260930-ml")
	var evidence := FileAccess.open("res://reports/challenges/20260930-ml/static-routes.json", FileAccess.WRITE)
	evidence.store_string(JSON.stringify(route_evidence, "\t"))
	for failure in failures: push_error(failure)
	print("M/L challenge runtime: %d/%d passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
