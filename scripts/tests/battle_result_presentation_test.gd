extends SceneTree

const ResultView = preload("res://scripts/presentation/battle/battle_result_presentation.gd")

func _init() -> void:
	assert(ResultView.describe({}).is_empty())
	assert(ResultView.describe({"winner_faction": "player", "reason": "LEVEL_OBJECTIVE_COMPLETED"})["kind"] == "Victory")
	assert(ResultView.describe({"winner_faction": "enemy", "reason": "LEVEL_OBJECTIVE_CANCELLED"})["kind"] == "Defeat")
	assert(ResultView.describe({"winner_faction": "", "reason": "FLAGSHIP_SUNK_SIMULTANEOUS"})["title"] == "平局")
	assert(ResultView.describe({"winner_faction": "", "reason": "LEVEL_TECHNICAL_LIMIT"})["kind"] == "Invalid")
	assert(ResultView.describe({"winner_faction": "", "reason": "UNKNOWN"})["kind"] == "Invalid")
	var mission := ResultView.describe({"winner_faction": "enemy", "reason": "LEVEL_OBJECTIVE_CANCELLED", "reason_summary": "保护目标沉没"})
	assert(mission["subtitle"] == "保护目标沉没")
	print("PASS: 7 authoritative battle result presentation cases")
	quit()
