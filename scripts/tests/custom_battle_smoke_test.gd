extends SceneTree
const Session = preload("res://scripts/application/battle_session.gd")
func _init() -> void: call_deferred("_run")
func _run() -> void:
	var flow = root.get_node("GameFlow")
	var registry = root.get_node("DataRegistry").registry
	var original: Array[String] = flow.unlocked_ship_ids.duplicate()
	flow.unlocked_ship_ids.assign(registry.all("ships").map(func(ship): return str(ship.id)))
	var player: Array[String] = ["ship.shimakaze", "ship.yukikaze", "ship.aurora"]
	var runs: Array = []
	var passed := true
	for map_id in ["level.prototype_3v3", "level.prototype_harbor_3v3"]:
		for difficulty in ["Easy", "Standard", "Hard"]:
			var configured: Dictionary = flow.configure_custom_battle("level.prototype_3v3", map_id, "clear_day", player, "", difficulty, 42, 91214)
			if not configured.get("ok", false): passed = false; continue
			var session = Session.new(registry)
			var started: Dictionary = session.create_battle_from_definition(configured.level, int(configured.battle_seed))
			if not started.ok: passed = false; continue
			session.configure_full_ai_factions(["player", "enemy"])
			for tick in range(12010):
				if session.state.phase == "Finished": break
				session.advance_tick(0.1)
			var run := {"map_id":map_id, "difficulty":difficulty, "roster_id":configured.roster.id, "enemy_cost":configured.enemy_cost, "lower":configured.lower, "upper":configured.upper, "phase":session.state.phase, "duration":session.state.elapsed_time, "result":session.state.result}
			runs.append(run)
			print("CUSTOM_SMOKE " + JSON.stringify(run))
			passed = passed and session.state.phase == "Finished"
	flow.unlocked_ship_ids.assign(original)
	var file := FileAccess.open("res://reports/custom_battle/20261002-runtime/smoke.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"scope":"TechnicalSmokeNotBalance", "runs":runs, "passed":passed}, "\t") + "\n")
	quit(0 if passed else 1)
