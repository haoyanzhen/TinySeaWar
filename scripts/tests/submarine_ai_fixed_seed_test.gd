extends SceneTree

const ConfigRegistry = preload("res://scripts/infrastructure/data/config_registry.gd")
const BattleSession = preload("res://scripts/application/battle_session.gd")

const CASES := [
	{"level_id":"level.challenge.s04", "unit_id":"unit.player.s04.hai_shih", "first_seed":8401},
	{"level_id":"level.challenge.s05", "unit_id":"unit.enemy.s05.u47", "first_seed":8501},
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	var seed_count := clampi(int(arguments[0]) if not arguments.is_empty() else 1, 1, 3)
	var first_seed_offset := clampi(int(arguments[1]) if arguments.size() > 1 else 0, 0, 2)
	seed_count = mini(seed_count, 3 - first_seed_offset)
	var registry = ConfigRegistry.new()
	if not registry.load_all():
		push_error("Configuration errors: %s" % registry.errors)
		quit(1)
		return
	var failures: Array[String] = []
	var summaries: Array = []
	var full_cycles_by_level := {}
	for case_definition in CASES:
		for seed_offset in range(first_seed_offset, first_seed_offset + seed_count):
			var result := _run_case(registry, case_definition, int(case_definition["first_seed"]) + seed_offset)
			summaries.append(result)
			var level_id := str(result.get("level_id", ""))
			var long_term: Dictionary = result.get("long_term_diagnostic", {})
			full_cycles_by_level[level_id] = int(full_cycles_by_level.get(level_id, 0)) + int(long_term.get("normal_full_cycles", 0)) + int(long_term.get("submerged_launch_cycles", 0))
			for failure in result.get("failures", []):
				failures.append(str(failure))
	for case_definition in CASES:
		var level_id := str(case_definition["level_id"])
		if int(full_cycles_by_level.get(level_id, 0)) <= 0:
			failures.append("%s fixed-seed batch produced no complete six-phase attack-cycle evidence" % level_id)
	print("SUBMARINE_AI_FIXED_SEED=%s" % JSON.stringify(summaries))
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _run_case(registry, case_definition: Dictionary, seed: int) -> Dictionary:
	var level_id := str(case_definition["level_id"])
	var submarine_id := str(case_definition["unit_id"])
	var session = BattleSession.new(registry)
	var creation: Dictionary = session.create_battle(level_id, seed)
	if not bool(creation.get("ok", false)):
		return {"level_id":level_id, "seed":seed, "failures":["%s seed %d failed to create: %s" % [level_id, seed, creation.get("errors", [])]]}
	session.configure_full_ai_factions(["player", "enemy"])
	var profile_result: Dictionary = session.configure_ai_profile("ai.profile.hard")
	if not bool(profile_result.get("accepted", false)):
		return {"level_id":level_id, "seed":seed, "failures":["%s seed %d failed to configure hard AI" % [level_id, seed]]}

	var counts := {
		"solutions":0, "commits":0, "fires":0, "break_contact":0,
		"recover_oxygen":0, "redive_requests":0, "stable_redives":0,
		"primary_rejections":0, "illegal_depth_fires":0,
		"friendly_commits":0, "launcher_mismatches":0, "navigation_failures":0,
	}
	var diagnostics := {"max_window_score":0.0, "max_window_values":{}, "phase_reasons":{}, "held_reasons":{}, "navigation_events":[], "visible_target_ticks":0, "visible_alive_ticks":0}
	var last_committed_instance_id := ""
	var ticks := 0
	while session.state.get("phase", "") == "Running" and ticks < 12000:
		var submarine: Dictionary = session.state.get("units_by_id", {}).get(submarine_id, {})
		if not submarine.is_empty():
			var observation = session._ai_observation_for(str(submarine.get("faction_id", "")))
			if not observation.visible_enemies.is_empty():
				diagnostics["visible_target_ticks"] = int(diagnostics["visible_target_ticks"]) + 1
				if submarine.get("life_state", "") == "Alive":
					diagnostics["visible_alive_ticks"] = int(diagnostics["visible_alive_ticks"]) + 1
		for event in session.advance_tick(0.1):
			var event_type := str(event.get("event_type", ""))
			var event_unit_id := str(event.get("unit_id", ""))
			if event_unit_id != submarine_id:
				continue
			if event_type in ["AIPathStuck", "AIRouteUnavailable", "NavigationRouteUnavailable", "NavigationTrajectoryFailed"]:
				counts["navigation_failures"] += 1
				if diagnostics["navigation_events"].size() < 4:
					diagnostics["navigation_events"].append(event.duplicate(true))
			match event_type:
				"AITorpedoSolutionSelected":
					counts["solutions"] += 1
					if float(event.get("window_score", 0.0)) > float(diagnostics["max_window_score"]):
						diagnostics["max_window_score"] = float(event.get("window_score", 0.0))
						diagnostics["max_window_values"] = event.get("window_values", {}).duplicate(true)
				"AIFireHeld":
					var held_reason := str(event.get("reason", "UNKNOWN"))
					diagnostics["held_reasons"][held_reason] = int(diagnostics["held_reasons"].get(held_reason, 0)) + 1
				"AIFireCommitted":
					counts["commits"] += 1
					last_committed_instance_id = str(event.get("weapon_state_instance_id", ""))
					var target: Dictionary = session.state.get("units_by_id", {}).get(str(event.get("target_unit_id", "")), {})
					var source: Dictionary = session.state.get("units_by_id", {}).get(submarine_id, {})
					if not target.is_empty() and target.get("faction_id", "") == source.get("faction_id", ""):
						counts["friendly_commits"] += 1
				"WeaponFired":
					var source: Dictionary = session.state.get("units_by_id", {}).get(submarine_id, {})
					var weapon = registry.get_definition("weapons", str(event.get("weapon_id", "")))
					if str(weapon.get("mount_type", "")) != "Torpedo":
						continue
					counts["fires"] += 1
					if str(event.get("weapon_state_instance_id", "")) != last_committed_instance_id:
						counts["launcher_mismatches"] += 1
					var stable_depth := not bool(source.get("depth_transition", {}).get("active", false))
					var depth_legal := str(source.get("depth_state", "")) == "Surface" or bool(source.get("stats", {}).get("can_launch_torpedoes_submerged", false))
					if not stable_depth or not depth_legal:
						counts["illegal_depth_fires"] += 1
				"AISubmarinePhaseChanged":
					var phase_reason := str(event.get("reason", "UNKNOWN"))
					diagnostics["phase_reasons"][phase_reason] = int(diagnostics["phase_reasons"].get(phase_reason, 0)) + 1
					match str(event.get("new_phase", "")):
						"BreakContact": counts["break_contact"] += 1
						"RecoverOxygen": counts["recover_oxygen"] += 1
				"AIDepthRequestCommitted":
					if str(event.get("target_depth_state", "")) == "Submerged":
						counts["redive_requests"] += 1
				"SubmarineDepthChanged":
					if str(event.get("target_depth_state", "")) == "Submerged":
						counts["stable_redives"] += 1
				"CommandRejected":
					if str(event.get("command_type", "")) == "FirePrimaryWeapon":
						counts["primary_rejections"] += 1
		ticks += 1

	var failures: Array[String] = []
	var prefix := "%s seed %d" % [level_id, seed]
	var long_term_diagnostic: Dictionary = session.get_statistics().get("submarine_ai", {}).get(submarine_id, {})
	for requirement in [
		["solutions", "%s produced no legal torpedo solution" % prefix],
		["commits", "%s produced no AI fire commit" % prefix],
		["fires", "%s produced no authoritative torpedo fire" % prefix],
		["recover_oxygen", "%s never entered RecoverOxygen" % prefix],
		["redive_requests", "%s never requested a recovery redive" % prefix],
		["stable_redives", "%s never completed a stable recovery redive" % prefix],
	]:
		if int(counts[requirement[0]]) <= 0:
			failures.append(str(requirement[1]))
	for zero_requirement in ["primary_rejections", "illegal_depth_fires", "friendly_commits", "launcher_mismatches", "navigation_failures"]:
		if int(counts[zero_requirement]) > 0:
			failures.append("%s has %d %s" % [prefix, int(counts[zero_requirement]), zero_requirement])
	if str(long_term_diagnostic.get("zero_fire_classification", "")) != "FIRED":
		failures.append("%s long-term diagnostic did not classify the submarine as FIRED" % prefix)
	if str(long_term_diagnostic.get("first_fire_weapon_state_instance_id", "")).is_empty():
		failures.append("%s long-term diagnostic lost the concrete first-fire launcher instance" % prefix)
	return {
		"level_id":level_id,
		"seed":seed,
		"phase":session.state.get("phase", ""),
		"duration":session.state.get("elapsed_time", 0.0),
		"result":session.state.get("result", {}).get("winner_faction", ""),
		"counts":counts,
		"diagnostics":diagnostics,
		"long_term_diagnostic":long_term_diagnostic,
		"failures":failures,
	}
