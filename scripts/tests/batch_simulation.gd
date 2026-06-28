extends SceneTree

const ConfigRegistry = preload("res://scripts/infrastructure/data/config_registry.gd")
const BattleSession = preload("res://scripts/application/battle_session.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = ConfigRegistry.new()
	if not registry.load_all():
		push_error("Configuration errors: %s" % registry.errors)
		quit(1)
		return
	var level_ticks := {
		"level.prototype_1v1": 3200,
		"level.prototype_3v3": 4200,
		"level.prototype_5v5": 5200,
		"level.prototype_11v11": 7200,
		"level.prototype_harbor_3v3": 4200,
	}
	var summaries := {}
	for level_id in level_ticks:
		summaries[level_id] = _simulate_level(registry, level_id, int(level_ticks[level_id]))
	print(JSON.stringify(summaries, "  "))
	quit(0)


func _simulate_level(registry, level_id: String, maximum_ticks: int) -> Dictionary:
	var runs := 6
	var player_wins := 0
	var finished_runs := 0
	var durations: Array[float] = []
	var damage_by_unit := {}
	for run_index in range(runs):
		var session = BattleSession.new(registry)
		session.create_battle(level_id, 1000 + run_index)
		for tick in range(maximum_ticks):
			session.advance_tick(0.1)
			if session.state["phase"] == "Finished":
				break
		if session.state["phase"] == "Finished":
			finished_runs += 1
		var stats: Dictionary = session.get_statistics()
		if stats.get("result", {}).get("winner_faction", "") == "player":
			player_wins += 1
		durations.append(float(stats.get("duration", 0.0)))
		for unit_id in stats.get("units", {}):
			damage_by_unit[unit_id] = float(damage_by_unit.get(unit_id, 0.0)) + float(stats["units"][unit_id].get("damage_dealt", 0.0))
	var duration_total := 0.0
	for duration in durations:
		duration_total += duration
	for unit_id in damage_by_unit:
		damage_by_unit[unit_id] = float(damage_by_unit[unit_id]) / runs
	return {
		"runs": runs,
		"finished_runs": finished_runs,
		"player_win_rate": float(player_wins) / runs,
		"average_duration": duration_total / runs,
		"average_damage_by_unit": damage_by_unit,
	}
