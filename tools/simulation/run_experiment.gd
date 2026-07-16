extends SceneTree

const ConfigRegistry = preload("res://scripts/infrastructure/data/config_registry.gd")
const ExperimentLoader = preload("res://scripts/infrastructure/simulation/experiment_loader.gd")
const SimulationRunner = preload("res://scripts/application/simulation/simulation_runner.gd")
const ReportWriter = preload("res://scripts/infrastructure/simulation/simulation_report_writer.gd")

const DEFAULT_MANIFEST := "res://data/simulations/experiments/smoke_single_battle.json"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	var manifest_path := arguments[0] if not arguments.is_empty() else DEFAULT_MANIFEST
	var loaded := ExperimentLoader.new().load_manifest(manifest_path)
	if not bool(loaded.get("ok", false)):
		_fail(loaded.get("errors", []))
		return
	var manifest: Dictionary = loaded["manifest"]
	var registry = ConfigRegistry.new()
	if not registry.load_all():
		_fail(registry.errors)
		return
	var result := SimulationRunner.new().run_experiment(registry, manifest)
	if not bool(result.get("ok", false)):
		_fail(result.get("errors", []))
		return
	var output_directory := str(manifest.get("output_directory", "res://artifacts/simulations/%s" % manifest.get("experiment_id", "experiment")))
	var written := ReportWriter.new().write_all(output_directory, result)
	if not bool(written.get("ok", false)):
		_fail(written.get("errors", []))
		return
	print("SIMULATION_REPORT=%s" % output_directory.path_join("report.md"))
	print(JSON.stringify(result.get("aggregate", {}), "  "))
	var aggregate: Dictionary = result.get("aggregate", {})
	var complete := int(aggregate.get("finished_runs", 0)) == int(aggregate.get("planned_runs", -1))
	var evaluation: Dictionary = aggregate.get("win_rate_evaluation", {})
	var accepted := evaluation.is_empty() or bool(evaluation.get("passed", false))
	quit(0 if complete and accepted else (3 if complete else 2))


func _fail(errors: Array) -> void:
	for error in errors:
		push_error(str(error))
	quit(1)
