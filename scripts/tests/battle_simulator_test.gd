extends SceneTree

const ConfigRegistry = preload("res://scripts/infrastructure/data/config_registry.gd")
const ExperimentLoader = preload("res://scripts/infrastructure/simulation/experiment_loader.gd")
const SimulationRunner = preload("res://scripts/application/simulation/simulation_runner.gd")
const Aggregator = preload("res://scripts/infrastructure/simulation/simulation_aggregator.gd")
const ReportWriter = preload("res://scripts/infrastructure/simulation/simulation_report_writer.gd")

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var loader = ExperimentLoader.new()
	var invalid_errors := loader.validate_manifest({})
	_check(not invalid_errors.is_empty(), "invalid manifest is rejected")
	var manifest := {
		"schema_version": 1,
		"experiment_id": "sim.test.determinism",
		"description": "模拟器确定性集成测试",
		"simulation_kind": "RuleRegression",
		"player_policy_id": "BaselineAutopilot",
		"enemy_policy_id": "BaselineAutopilot",
		"tick_seconds": 0.1,
		"maximum_ticks": 2500,
		"seed_plan": {"type": "ExplicitList", "values": [731]},
		"scenarios": [{"scenario_id": "one_on_one", "level_definition_id": "level.prototype_1v1"}],
	}
	_check(loader.validate_manifest(manifest).is_empty(), "valid manifest passes validation")
	var registry = ConfigRegistry.new()
	_check(registry.load_all(), "configuration registry loads")
	var runner = SimulationRunner.new()
	var first := runner.run_experiment(registry, manifest)
	var second := runner.run_experiment(registry, manifest)
	_check(bool(first.get("ok", false)) and bool(second.get("ok", false)), "experiment runs twice")
	_check(int(first.get("aggregate", {}).get("planned_runs", 0)) == 1, "seed plan expands to one run")
	_check(int(first.get("aggregate", {}).get("finished_runs", 0)) == 1, "battle finishes before guard limit")
	_check(Aggregator.new().deterministic_signature(first) == Aggregator.new().deterministic_signature(second), "same manifest and seed reproduce the same result")
	var first_run: Dictionary = first.get("runs", [])[0]
	_check(not first_run.get("units", {}).has(""), "area misses do not create an empty analytics unit")
	var non_ship_aggregate := Aggregator.new().aggregate([{
		"end_state":"Finished", "winner_faction":"player", "winner_lineup":"original_player", "finish_reason":"FLAGSHIP_SUNK", "duration":1.0,
		"units":{"unit.player.test":{"lineup_id":"original_player", "definition_id":"ship.test", "display_name":"测试舰", "damage_dealt":10.0, "damage_taken":0.0, "contribution_damage":0.0, "damage_by_category":{}, "overkill_damage":0.0, "shots":1, "hits":1}},
		"non_ship_damage":{"facility.test":{"source_id":"facility.test", "source_kind":"Facility", "display_name":"测试炮台", "damage_dealt":20.0, "damage_taken":0.0, "overkill_damage":0.0, "shots":1, "hits":1, "damage_by_category":{"main_gun":20.0}}},
	}])
	_check(not non_ship_aggregate.get("average_damage_by_ship", {}).has("|") and non_ship_aggregate.get("average_damage_by_non_ship", {}).has("facility.test"), "non-ship damage aggregates separately without creating a blank ship grouping key")
	var player_health: Dictionary = first_run.get("fleet_health", {}).get("fleet.player", {})
	var player_damage_taken := 0.0
	for unit_id in first_run.get("units", {}):
		if str(unit_id).begins_with("unit.player."):
			player_damage_taken += float(first_run["units"][unit_id].get("damage_taken", 0.0))
	_check(player_damage_taken <= float(player_health.get("initial_hp", 0.0)) + 0.001, "effective damage excludes overkill from damage taken")
	var player_shots := 0
	var enemy_shots := 0
	for unit_id in first_run.get("units", {}):
		if str(unit_id).begins_with("unit.player."):
			player_shots += int(first_run["units"][unit_id].get("shots", 0))
		elif str(unit_id).begins_with("unit.enemy."):
			enemy_shots += int(first_run["units"][unit_id].get("shots", 0))
	_check(player_shots > 0, "player formation AI fires weapons")
	_check(enemy_shots > 0, "enemy formation AI fires weapons")
	var output_directory := "user://battle_simulator_test"
	var written := ReportWriter.new().write_all(output_directory, first)
	_check(bool(written.get("ok", false)), "report artifacts are written")
	_check(FileAccess.file_exists(output_directory.path_join("report.md")), "Markdown report exists")
	var report_text := FileAccess.get_file_as_string(output_directory.path_join("report.md"))
	_check(report_text.contains("累计消极时长") and report_text.contains("接敌压力触发次数") and report_text.contains("触发后平均接敌时间") and report_text.contains("长期原地不动次数"), "Markdown report exposes all passive-engagement metrics")
	_check(FileAccess.file_exists(output_directory.path_join("aggregate.json")), "aggregate JSON exists")
	_check(FileAccess.file_exists(output_directory.path_join("unit_damage.csv")), "per-battle unit damage CSV exists")
	var swapped_manifest: Dictionary = manifest.duplicate(true)
	swapped_manifest["experiment_id"] = "sim.test.side_swap"
	swapped_manifest["side_swap"] = true
	var swapped := runner.run_experiment(registry, swapped_manifest)
	_check(int(swapped.get("aggregate", {}).get("planned_runs", 0)) == 2, "side swap expands each seed into an original and swapped run")
	var swapped_runs: Array = swapped.get("runs", [])
	_check(swapped_runs[0].get("side_variant", "") == "original" and swapped_runs[1].get("side_variant", "") == "swapped", "paired runs retain stable side variant order")
	_check(swapped_runs[0].get("units", {}).get("unit.player.warspite", {}).get("definition_id", "") == "ship.warspite", "original run keeps the player lineup on the player side")
	_check(swapped_runs[1].get("units", {}).get("unit.player.bismarck", {}).get("definition_id", "") == "ship.bismarck", "swapped run places the original enemy lineup on player spawns")
	_check(swapped_runs[1].get("units", {}).get("unit.enemy.warspite", {}).get("definition_id", "") == "ship.warspite", "swapped run places the original player lineup on enemy spawns")
	var latest_ai_manifest: Dictionary = manifest.duplicate(true)
	latest_ai_manifest["experiment_id"] = "sim.test.latest_runtime_ai"
	latest_ai_manifest["player_policy_id"] = "LatestRuntimeAI"
	latest_ai_manifest["enemy_policy_id"] = "LatestRuntimeAI"
	latest_ai_manifest["side_swap"] = false
	var latest_ai := runner.run_experiment(registry, latest_ai_manifest)
	var latest_run: Dictionary = latest_ai.get("runs", [])[0]
	var latest_player_shots := int(latest_run.get("units", {}).get("unit.player.warspite", {}).get("shots", 0))
	var latest_enemy_shots := int(latest_run.get("units", {}).get("unit.enemy.bismarck", {}).get("shots", 0))
	_check(latest_player_shots > 0 and latest_enemy_shots > 0, "latest runtime AI drives primary and automatic fire for both factions")
	_check(latest_run.get("end_state", "") == "Finished", "latest runtime AI battle reaches a normal result")
	var behavior: Dictionary = latest_ai.get("aggregate", {}).get("ai_behavior", {})
	_check(float(behavior.get("fire_commitments", 0.0)) > 0.0, "AI behavior aggregate records fire commitments")
	_check(behavior.has("mode_switches_per_minute") and behavior.has("tactic_switches_per_minute"), "AI behavior aggregate reports normalized switch rates")
	_check(behavior.has("overkill_ratio") and float(behavior.get("overkill_ratio", -1.0)) >= 0.0, "AI behavior aggregate reports overkill ratio")
	_check(behavior.has("passive_duration_seconds") and behavior.has("engagement_pressure_triggers") and behavior.has("average_engagement_response_seconds") and behavior.has("long_idle_events"), "AI behavior aggregate reports passivity duration, triggers, response time, and long idle events")
	var aggregate: Dictionary = latest_ai.get("aggregate", {})
	_check(aggregate.has("original_player_lineup_win_rate") and aggregate.has("spawn_side_player_win_rate") and aggregate.has("facility_usage_rate") and aggregate.has("timeout_rate") and aggregate.has("behavior_anomalies_per_run"), "balance report aggregates lineup, spawn side, facility use, timeout, and behavior anomalies")
	_check(latest_run.get("ai_behavior", {}).has("mode_dwell_seconds"), "individual run retains mode dwell evidence")
	_check(latest_run.get("ai_behavior", {}).has("route_unavailable"), "individual run retains unavailable-route evidence")
	_check(not latest_run.get("unit_end_states", {}).is_empty(), "individual run retains final movement evidence")
	if failures.is_empty():
		print("PASS: %d battle simulator checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error("FAIL: %s" % failure)
		print("FAILED: %d of %d battle simulator checks" % [failures.size(), checks])
		quit(1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
