class_name SimulationAggregator
extends RefCounted


func aggregate(runs: Array) -> Dictionary:
	var result := _aggregate_core(runs)
	var scenario_runs := {}
	for run in runs:
		var scenario_id := str(run.get("scenario_id", "unknown"))
		if not scenario_runs.has(scenario_id):
			scenario_runs[scenario_id] = []
		scenario_runs[scenario_id].append(run)
	var by_scenario := {}
	var scenario_variant_runs := {}
	var scenario_ids: Array = scenario_runs.keys()
	scenario_ids.sort()
	for scenario_id in scenario_ids:
		by_scenario[scenario_id] = _aggregate_core(scenario_runs[scenario_id])
		for run in scenario_runs[scenario_id]:
			var variant_key := "%s.%s" % [scenario_id, str(run.get("side_variant", "original"))]
			if not scenario_variant_runs.has(variant_key): scenario_variant_runs[variant_key] = []
			scenario_variant_runs[variant_key].append(run)
	var by_scenario_variant := {}
	var variant_keys: Array = scenario_variant_runs.keys()
	variant_keys.sort()
	for variant_key in variant_keys:
		by_scenario_variant[variant_key] = _aggregate_core(scenario_variant_runs[variant_key])
	result["by_scenario"] = by_scenario
	result["by_scenario_variant"] = by_scenario_variant
	return result


func _aggregate_core(runs: Array) -> Dictionary:
	var durations: Array[float] = []
	var first_detection_times: Array[float] = []
	var first_fire_times: Array[float] = []
	var first_sinking_times: Array[float] = []
	var result_counts := {}
	var finish_reason_counts := {}
	var damage_totals := {}
	var damage_samples := {}
	var faction_combat := {
		"player": {"shots": 0, "hits": 0, "damage_dealt": 0.0},
		"enemy": {"shots": 0, "hits": 0, "damage_dealt": 0.0},
	}
	var finished_runs := 0
	var player_wins := 0
	var enemy_wins := 0
	var lineup_wins := {"original_player": 0, "original_enemy": 0}
	for run in runs:
		var end_state := str(run.get("end_state", "Unknown"))
		result_counts[end_state] = int(result_counts.get(end_state, 0)) + 1
		if end_state != "Finished":
			continue
		finished_runs += 1
		var winner := str(run.get("winner_faction", ""))
		if winner == "player": player_wins += 1
		elif winner == "enemy": enemy_wins += 1
		var winner_lineup := str(run.get("winner_lineup", ""))
		if lineup_wins.has(winner_lineup): lineup_wins[winner_lineup] += 1
		var reason := str(run.get("finish_reason", "UNKNOWN"))
		finish_reason_counts[reason] = int(finish_reason_counts.get(reason, 0)) + 1
		durations.append(float(run.get("duration", 0.0)))
		_append_non_negative(first_detection_times, float(run.get("first_detection_time", -1.0)))
		_append_non_negative(first_fire_times, float(run.get("first_fire_time", -1.0)))
		_append_non_negative(first_sinking_times, float(run.get("first_sinking_time", -1.0)))
		for unit_id in run.get("units", {}):
			var unit_stats: Dictionary = run["units"][unit_id]
			var damage := float(unit_stats.get("damage_dealt", 0.0))
			damage_totals[unit_id] = float(damage_totals.get(unit_id, 0.0)) + damage
			damage_samples[unit_id] = int(damage_samples.get(unit_id, 0)) + 1
			var faction_id := "player" if str(unit_id).begins_with("unit.player.") else ("enemy" if str(unit_id).begins_with("unit.enemy.") else "")
			if not faction_id.is_empty():
				faction_combat[faction_id]["shots"] += int(unit_stats.get("shots", 0))
				faction_combat[faction_id]["hits"] += int(unit_stats.get("hits", 0))
				faction_combat[faction_id]["damage_dealt"] += damage
	var average_damage_by_unit := {}
	for unit_id in damage_totals:
		average_damage_by_unit[unit_id] = float(damage_totals[unit_id]) / maxi(1, int(damage_samples[unit_id]))
	var win_rate := float(player_wins) / finished_runs if finished_runs > 0 else 0.0
	return {
		"planned_runs": runs.size(),
		"finished_runs": finished_runs,
		"completion_rate": float(finished_runs) / runs.size() if not runs.is_empty() else 0.0,
		"result_counts": result_counts,
		"finish_reason_counts": finish_reason_counts,
		"player_wins": player_wins,
		"enemy_wins": enemy_wins,
		"lineup_wins": lineup_wins,
		"original_player_lineup_win_rate": float(lineup_wins["original_player"]) / finished_runs if finished_runs > 0 else 0.0,
		"player_win_rate": win_rate,
		"player_win_rate_95": _wilson_interval(player_wins, finished_runs),
		"duration": _distribution(durations),
		"first_detection_time": _distribution(first_detection_times),
		"first_fire_time": _distribution(first_fire_times),
		"first_sinking_time": _distribution(first_sinking_times),
		"faction_combat": faction_combat,
		"average_damage_by_unit": average_damage_by_unit,
		"average_damage_by_ship": _average_damage_by_ship(runs),
	}


func _average_damage_by_ship(runs: Array) -> Dictionary:
	var totals := {}
	for run in runs:
		if run.get("end_state", "") != "Finished": continue
		for unit_id in run.get("units", {}):
			var unit: Dictionary = run["units"][unit_id]
			var key := "%s|%s" % [unit.get("lineup_id", ""), unit.get("definition_id", unit_id)]
			if not totals.has(key):
				totals[key] = {
					"lineup_id": unit.get("lineup_id", ""),
					"definition_id": unit.get("definition_id", ""),
					"display_name": unit.get("display_name", ""),
					"battles": 0,
					"damage_dealt": 0.0,
					"damage_taken": 0.0,
					"contribution_damage": 0.0,
					"damage_by_category": {},
				}
			var entry: Dictionary = totals[key]
			entry["battles"] += 1
			entry["damage_dealt"] += float(unit.get("damage_dealt", 0.0))
			entry["damage_taken"] += float(unit.get("damage_taken", 0.0))
			entry["contribution_damage"] += float(unit.get("contribution_damage", 0.0))
			for category in unit.get("damage_by_category", {}):
				entry["damage_by_category"][category] = float(entry["damage_by_category"].get(category, 0.0)) + float(unit["damage_by_category"][category])
	for key in totals:
		var count := maxi(1, int(totals[key]["battles"]))
		totals[key]["average_damage_dealt"] = float(totals[key]["damage_dealt"]) / count
		totals[key]["average_damage_taken"] = float(totals[key]["damage_taken"]) / count
		totals[key]["average_contribution_damage"] = float(totals[key]["contribution_damage"]) / count
	return totals


func deterministic_signature(result: Dictionary) -> String:
	var signatures: Array[String] = []
	for run in result.get("runs", []):
		signatures.append("%s|%s|%s|%.3f|%s" % [
			str(run.get("run_id", "")),
			str(run.get("end_state", "")),
			str(run.get("winner_faction", "")),
			float(run.get("duration", 0.0)),
			JSON.stringify(run.get("units", {})),
		])
	return "\n".join(signatures)


func _append_non_negative(values: Array[float], value: float) -> void:
	if value >= 0.0:
		values.append(value)


func _distribution(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {"count": 0, "mean": 0.0, "median": 0.0, "p10": 0.0, "p90": 0.0, "min": 0.0, "max": 0.0}
	values.sort()
	var total := 0.0
	for value in values: total += value
	return {
		"count": values.size(),
		"mean": total / values.size(),
		"median": _percentile(values, 0.5),
		"p10": _percentile(values, 0.1),
		"p90": _percentile(values, 0.9),
		"min": values.front(),
		"max": values.back(),
	}


func _percentile(values: Array[float], ratio: float) -> float:
	if values.size() == 1: return values[0]
	var position := clampf(ratio, 0.0, 1.0) * float(values.size() - 1)
	var lower := int(floor(position))
	var upper := int(ceil(position))
	if lower == upper: return values[lower]
	return lerpf(values[lower], values[upper], position - lower)


func _wilson_interval(successes: int, count: int) -> Array[float]:
	if count <= 0: return [0.0, 0.0]
	var z := 1.959963984540054
	var proportion := float(successes) / count
	var denominator := 1.0 + z * z / count
	var center := (proportion + z * z / (2.0 * count)) / denominator
	var margin := z * sqrt((proportion * (1.0 - proportion) + z * z / (4.0 * count)) / count) / denominator
	return [maxf(0.0, center - margin), minf(1.0, center + margin)]
