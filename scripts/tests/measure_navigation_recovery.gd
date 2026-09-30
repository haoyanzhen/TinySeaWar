extends SceneTree
## Fixed-seed, bounded diagnostic. Writes all episodes, including censored ones,
## and CPU percentiles; does not interpret a cancelled episode as success.
const Registry = preload("res://scripts/infrastructure/data/config_registry.gd")
const Session = preload("res://scripts/application/battle_session.gd")

class MeasuredSession extends Session:
	var correction_ticks := 0
	var correction_distance := 0.0
	func _resolve_unit_overlap() -> void:
		var before := {}
		for id in state.units_by_id:
			before[id] = state.units_by_id[id].position
		super._resolve_unit_overlap()
		for id in before:
			var distance: float = before[id].distance_to(state.units_by_id[id].position)
			if distance > 0.00001:
				correction_ticks += 1
				correction_distance += distance

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() >= 3, "level suffix, seed, absolute output JSON required")
	var registry = Registry.new()
	assert(registry.load_all())
	var session = MeasuredSession.new(registry)
	assert(session.create_battle("level.challenge." + args[0], int(args[1])).get("ok", false))
	session.configure_full_ai_factions(["player", "enemy"])
	session.configure_ai_profile("ai.profile.hard" if args[0] == "s04" else "ai.profile.standard")
	session.configure_performance_profiling(true)
	var counts := {}
	var failures: Array = []
	var active := {}
	var episodes: Array = []
	for tick in range(4000):
		for event in session.advance_tick(0.1):
			var kind := str(event.get("event_type", ""))
			counts[kind] = int(counts.get(kind, 0)) + 1
			if kind in ["TrajectoryPlanFailed", "NavigationRequestFailed", "NavigationCollisionContractViolated", "UnitTideAccessRestricted"]:
				failures.append({"time":session.state.elapsed_time, "event":event})
			var id := str(event.get("unit_id", ""))
			var now := float(session.state.elapsed_time)
			if kind == "NavigationRecoveryStarted":
				active[id] = {"unit":id, "start":now, "attempts":1, "reason":event.get("reason_code", "")}
			if kind == "NavigationRecoveryRetried" and active.has(id): active[id].attempts += 1
			if kind in ["NavigationRecoveryCompleted", "NavigationRecoveryCancelled"] and active.has(id):
				var episode: Dictionary = active[id]
				episode.merge({"end":now, "duration":now-float(episode.start), "outcome":kind, "reason_end":event.get("reason_code", "")})
				episodes.append(episode)
				active.erase(id)
		for id in active.keys():
			if session.state.units_by_id[id].life_state == "Alive": continue
			var episode: Dictionary = active[id]
			episode.merge({"end":session.state.elapsed_time, "duration":float(session.state.elapsed_time)-float(episode.start), "outcome":"CensoredAtSinking"})
			episodes.append(episode)
			active.erase(id)
		if session.state.phase != "Running": break
	for episode in active.values():
		episode.merge({"end":session.state.elapsed_time, "duration":float(session.state.elapsed_time)-float(episode.start), "outcome":"CensoredAtBattleEnd"})
		episodes.append(episode)
	var profile := {}
	var common_profile := {}
	var raw_profile := session.get_performance_profile()
	for key in raw_profile:
		var values = raw_profile[key]
		if values is Array and not values.is_empty():
			profile[key] = summarize(values)
			common_profile[key] = summarize(values.slice(0, mini(1000, values.size())))
	var result := {"level":args[0], "seed":int(args[1]), "phase":session.state.phase, "duration":session.state.elapsed_time, "counts":counts, "episodes":episodes, "failures":failures, "correction_unit_ticks":session.correction_ticks, "correction_distance":session.correction_distance, "profile":profile}
	result["first_1000_tick_profile"] = common_profile
	result["submarine_ai"] = session.recorder.summary.get("submarine_ai", {})
	var output := FileAccess.open(args[2], FileAccess.WRITE)
	assert(output != null)
	output.store_string(JSON.stringify(result, "  "))
	print("MEASURED %s %s %.1fs, %d episodes, %d correction unit ticks" % [args[0], args[1], result.duration, episodes.size(), result.correction_unit_ticks])
	quit()

func summarize(values: Array) -> Dictionary:
	var ordered := values.duplicate()
	ordered.sort()
	var total := 0.0
	for value in ordered: total += float(value)
	return {"n":ordered.size(), "mean":total/ordered.size(), "p95":ordered[mini(ordered.size()-1, int(ceil(ordered.size()*0.95))-1)], "p99":ordered[mini(ordered.size()-1, int(ceil(ordered.size()*0.99))-1)], "max":ordered[-1]}
