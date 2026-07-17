class_name SimulationExperimentLoader
extends RefCounted


func load_manifest(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "errors": ["Cannot read simulation manifest: %s" % path]}
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "errors": ["Simulation manifest must be a JSON object: %s" % path]}
	var manifest: Dictionary = parsed
	var errors := validate_manifest(manifest)
	return {"ok": errors.is_empty(), "errors": errors, "manifest": manifest.duplicate(true)}


func validate_manifest(manifest: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if int(manifest.get("schema_version", 0)) != 1:
		errors.append("Unsupported simulation schema_version")
	if str(manifest.get("experiment_id", "")).is_empty():
		errors.append("Missing experiment_id")
	if float(manifest.get("tick_seconds", 0.0)) <= 0.0:
		errors.append("tick_seconds must be positive")
	if int(manifest.get("maximum_ticks", 0)) <= 0:
		errors.append("maximum_ticks must be positive")
	var allowed_policies := ["SessionAutonomy", "BaselineAutopilot", "LatestRuntimeAI", "TutorialT01Deterministic", "TutorialT02Deterministic", "TutorialT03Deterministic", "TutorialT04Deterministic", "TutorialT05Deterministic", "TutorialT06Deterministic", "TutorialT07Deterministic", "TutorialT08Deterministic"]
	for faction_id in ["player", "enemy"]:
		var policy_id := str(manifest.get("%s_policy_id" % faction_id, manifest.get("policy_id", "SessionAutonomy")))
		if policy_id not in allowed_policies:
			errors.append("Unsupported %s policy_id: %s" % [faction_id, policy_id])
	var scenarios = manifest.get("scenarios", [])
	if not scenarios is Array or scenarios.is_empty():
		errors.append("At least one simulation scenario is required")
		return errors
	var scenario_ids := {}
	for index in range(scenarios.size()):
		var scenario = scenarios[index]
		if not scenario is Dictionary:
			errors.append("Scenario %d must be an object" % index)
			continue
		var scenario_id := str(scenario.get("scenario_id", ""))
		if scenario_id.is_empty():
			errors.append("Scenario %d is missing scenario_id" % index)
		elif scenario_ids.has(scenario_id):
			errors.append("Duplicate scenario_id: %s" % scenario_id)
		else:
			scenario_ids[scenario_id] = true
		if str(scenario.get("level_definition_id", "")).is_empty():
			errors.append("Scenario %s is missing level_definition_id" % scenario_id)
		var seeds := seeds_for(manifest, scenario)
		if seeds.is_empty():
			errors.append("Scenario %s has no seeds" % scenario_id)
		var unique_seeds := {}
		for seed_value in seeds:
			if unique_seeds.has(seed_value): errors.append("Scenario %s contains duplicate seed %s" % [scenario_id, seed_value])
			unique_seeds[seed_value] = true
	if str(manifest.get("simulation_kind", "")) == "LevelWinRateEvaluation":
		if bool(manifest.get("side_swap", false)):
			errors.append("LevelWinRateEvaluation requires side_swap=false so every battle uses a distinct seed")
		var planned_runs := 0
		var evaluation_seeds := {}
		for scenario in scenarios:
			var scenario_seeds := seeds_for(manifest, scenario)
			planned_runs += scenario_seeds.size()
			for seed_value in scenario_seeds:
				if evaluation_seeds.has(seed_value):
					errors.append("LevelWinRateEvaluation reuses seed %s across planned battles" % seed_value)
				evaluation_seeds[seed_value] = true
		if planned_runs != 20:
			errors.append("LevelWinRateEvaluation must contain exactly 20 planned battles, got %d" % planned_runs)
		var evaluation: Dictionary = manifest.get("win_rate_evaluation", {})
		if float(evaluation.get("target_player_win_rate", -1.0)) < 0.0 or float(evaluation.get("target_player_win_rate", 2.0)) > 1.0:
			errors.append("LevelWinRateEvaluation requires target_player_win_rate in [0, 1]")
		if float(evaluation.get("tolerance", -1.0)) < 0.0:
			errors.append("LevelWinRateEvaluation requires non-negative tolerance")
		if str(evaluation.get("settlement_source", "")) != "BattleStatisticsReport":
			errors.append("LevelWinRateEvaluation settlement_source must be BattleStatisticsReport")
		if float(evaluation.get("minimum_p10_duration", 0.0)) < 0.0:
			errors.append("LevelWinRateEvaluation minimum_p10_duration must be non-negative")
		if float(evaluation.get("maximum_enemy_damage_before_engagement", 0.0)) < 0.0:
			errors.append("LevelWinRateEvaluation maximum enemy pre-engagement damage must be non-negative")
		if int(evaluation.get("maximum_policy_command_rejections", 0)) < 0:
			errors.append("LevelWinRateEvaluation maximum_policy_command_rejections must be non-negative")
		var action_ids := {}
		for action_id_value in evaluation.get("required_objective_action_ids", []):
			var action_id := str(action_id_value)
			if action_id.is_empty() or action_ids.has(action_id):
				errors.append("LevelWinRateEvaluation required objective action ids must be unique and non-empty")
			action_ids[action_id] = true
	return errors


func seeds_for(manifest: Dictionary, scenario: Dictionary) -> Array[int]:
	var source = scenario.get("seeds", [])
	if source is Array and not source.is_empty():
		return _integer_seeds(source)
	var seed_plan: Dictionary = manifest.get("seed_plan", {})
	var plan_type := str(seed_plan.get("type", "ExplicitList"))
	if plan_type == "SequentialRange":
		var start := int(seed_plan.get("start", 1))
		var count := maxi(0, int(seed_plan.get("count", 0)))
		var seeds: Array[int] = []
		for offset in range(count):
			seeds.append(start + offset)
		return seeds
	return _integer_seeds(seed_plan.get("values", []))


func _integer_seeds(values: Variant) -> Array[int]:
	var seeds: Array[int] = []
	if not values is Array:
		return seeds
	for value in values:
		seeds.append(int(value))
	return seeds
