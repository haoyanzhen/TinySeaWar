extends SceneTree

const ConfigRegistry = preload("res://scripts/infrastructure/data/config_registry.gd")
const BattleSession = preload("res://scripts/application/battle_session.gd")

const LEVEL_ID := "level.prototype_3v3"
const PROFILE_ID := "ai.profile.standard"
const TICK_SECONDS := 0.1
const MAXIMUM_TICKS := 4300
const DAMAGE_MULTIPLIER := 0.25
const OUTPUT_DIRECTORY := "res://artifacts/simulations/sim.balance.damage_ttk_20"
const SEEDS: Array[int] = [9201, 9202, 9203, 9204, 9205, 9206, 9207, 9208, 9209, 9210, 9211, 9212, 9213, 9214, 9215, 9216, 9217, 9218, 9219, 9220]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = ConfigRegistry.new()
	if not registry.load_all():
		_fail(registry.errors)
		return
	var output_path := ProjectSettings.globalize_path(OUTPUT_DIRECTORY)
	DirAccess.make_dir_recursive_absolute(output_path)
	var runs: Array[Dictionary] = []
	var jsonl := FileAccess.open(OUTPUT_DIRECTORY.path_join("runs.jsonl"), FileAccess.WRITE)
	if jsonl == null:
		_fail(["Unable to open balance output"])
		return
	for seed in SEEDS:
		var run := _run_battle(registry, seed)
		runs.append(run)
		jsonl.store_line(JSON.stringify(run))
	jsonl.flush()
	jsonl.close()
	var metadata := {
		"experiment_id": "sim.balance.damage_ttk_20",
		"description": "人工指定的大版本平衡验证：0.25 伤害倍率与舰炮散布的几何相交、命中、伤害和 TTK",
		"level_definition_id": LEVEL_ID,
		"ai_profile_id": PROFILE_ID,
		"tick_seconds": TICK_SECONDS,
		"maximum_ticks": MAXIMUM_TICKS,
		"damage_multiplier": DAMAGE_MULTIPLIER,
		"seed_count": SEEDS.size(),
		"seeds": SEEDS,
		"godot_version": Engine.get_version_info().get("string", "unknown"),
		"manual_designation": "2026-07-10 balance validation requested by user",
	}
	var metadata_file := FileAccess.open(OUTPUT_DIRECTORY.path_join("metadata.json"), FileAccess.WRITE)
	metadata_file.store_string(JSON.stringify(metadata, "  "))
	metadata_file.close()
	var summary_file := FileAccess.open(OUTPUT_DIRECTORY.path_join("summary.json"), FileAccess.WRITE)
	summary_file.store_string(JSON.stringify({"metadata": metadata, "runs": runs}, "  "))
	summary_file.close()
	print("BALANCE_RUNS=%d" % runs.size())
	quit(0 if runs.size() == SEEDS.size() else 2)


func _run_battle(registry, seed: int) -> Dictionary:
	var session = BattleSession.new(registry)
	var creation: Dictionary = session.create_battle(LEVEL_ID, seed)
	if not bool(creation.get("ok", false)):
		return {"seed": seed, "end_state": "CreationFailure", "errors": creation.get("errors", [])}
	session.configure_full_ai_factions(["player", "enemy"])
	session.configure_ai_profile(PROFILE_ID)
	var geometry_intersections := 0
	var geometry_misses := 0
	var hit_roll_successes := 0
	var hit_roll_failures := 0
	var unknown_geometry := 0
	var gun_resolutions := 0
	var effective_damage := 0.0
	var raw_damage := 0.0
	var final_damage := 0.0
	var damage_events := 0
	var main_gun_damage := 0.0
	var secondary_gun_damage := 0.0
	var first_flagship_sink := -1.0
	var ticks := 0
	while session.state.get("phase", "") == "Running" and ticks < MAXIMUM_TICKS:
		var events: Array = session.advance_tick(TICK_SECONDS)
		for event in events:
			var event_type := str(event.get("event_type", ""))
			if event_type == "AttackResolved":
				var result: Dictionary = event.get("damage_result", {})
				if str(result.get("damage_type", "")) != "Gun":
					continue
				gun_resolutions += 1
				if bool(result.get("geometry_intersection", false)): geometry_intersections += 1
				elif str(result.get("hit_reason", "")) == "NO_TARGET_IN_AREA": geometry_misses += 1
				else: unknown_geometry += 1
				var hit_reason := str(result.get("hit_reason", ""))
				if hit_reason == "ROLL_SUCCEEDED": hit_roll_successes += 1
				elif hit_reason == "ROLL_FAILED": hit_roll_failures += 1
				effective_damage += maxf(0.0, float(result.get("final_damage", 0.0)))
				raw_damage += maxf(0.0, float(result.get("raw_damage", 0.0)))
				final_damage += maxf(0.0, float(result.get("final_damage", 0.0)))
				if float(result.get("final_damage", 0.0)) > 0.0: damage_events += 1
				if str(result.get("damage_category", "")) == "main_gun": main_gun_damage += float(result.get("final_damage", 0.0))
				if str(result.get("damage_category", "")) == "secondary_gun": secondary_gun_damage += float(result.get("final_damage", 0.0))
			elif event_type == "FlagshipSunk" and first_flagship_sink < 0.0:
				first_flagship_sink = float(session.state.get("elapsed_time", 0.0))
		ticks += 1
	var stats: Dictionary = session.get_statistics()
	return {
		"seed": seed,
		"end_state": "Finished" if str(session.state.get("phase", "")) == "Finished" else "GuardLimit",
		"finish_reason": str(session.state.get("result", {}).get("reason", "GUARD_LIMIT")),
		"duration_seconds": float(stats.get("duration", session.state.get("elapsed_time", 0.0))),
		"ttk_seconds": float(stats.get("duration", session.state.get("elapsed_time", 0.0))),
		"first_flagship_sink_seconds": first_flagship_sink,
		"ticks_executed": ticks,
		"gun_resolutions": gun_resolutions,
		"geometry_intersections": geometry_intersections,
		"geometry_misses": geometry_misses,
		"unknown_geometry": unknown_geometry,
		"hit_roll_successes": hit_roll_successes,
		"hit_roll_failures": hit_roll_failures,
		"effective_damage": effective_damage,
		"raw_damage": raw_damage,
		"final_damage": final_damage,
		"damage_events": damage_events,
		"main_gun_damage": main_gun_damage,
		"secondary_gun_damage": secondary_gun_damage,
		"geometry_intersection_rate": float(geometry_intersections) / maxf(1.0, float(gun_resolutions - unknown_geometry)),
		"actual_hit_rate": float(geometry_intersections + hit_roll_successes) / maxf(1.0, float(gun_resolutions - unknown_geometry)),
	}


func _fail(errors: Array) -> void:
	for error in errors:
		push_error(str(error))
	quit(1)
