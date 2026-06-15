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
	var runs := 20
	var player_wins := 0
	var durations: Array[float] = []
	var damage_by_unit := {}
	for run_index in range(runs):
		var session = BattleSession.new(registry)
		session.create_battle("level.prototype_3v3", 1000 + run_index)
		for tick in range(4200):
			session.advance_tick(0.1)
			if session.state["phase"] == "Finished": break
		var stats: Dictionary = session.get_statistics()
		if stats.get("result", {}).get("winner_faction", "") == "player": player_wins += 1
		durations.append(float(stats.get("duration", 0.0)))
		for unit_id in stats.get("units", {}): damage_by_unit[unit_id] = float(damage_by_unit.get(unit_id, 0.0)) + float(stats["units"][unit_id].get("damage_dealt", 0.0))
	var duration_total := 0.0
	for duration in durations: duration_total += duration
	for unit_id in damage_by_unit: damage_by_unit[unit_id] = float(damage_by_unit[unit_id]) / runs
	print(JSON.stringify({"runs":runs,"player_win_rate":float(player_wins)/runs,"average_duration":duration_total/runs,"average_damage_by_unit":damage_by_unit}, "  "))
	quit(0)
