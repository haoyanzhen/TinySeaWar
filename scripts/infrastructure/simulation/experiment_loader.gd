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
