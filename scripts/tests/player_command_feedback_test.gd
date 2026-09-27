extends SceneTree

const Feedback = preload("res://scripts/presentation/battle/player_command_feedback.gd")

func _init() -> void:
	var feedback = Feedback.new()
	var player := {"command_type": "MoveUnits", "issuer_type": "Player", "issuer_id": "player"}
	assert(feedback.reject(player, "TARGET_POSITION_ON_LAND", 0.0))
	assert(feedback.current(0.0)["text"].contains("陆地"))
	assert(feedback.reject(player, "TARGET_POSITION_ON_LAND", 0.5))
	assert(feedback.current(0.6)["count"] == 2)
	assert(feedback.entries.size() == 1)
	assert(feedback.current(3.6).is_empty())
	assert(not feedback.reject({"issuer_type": "AI", "issuer_id": "enemy"}, "TARGET_NOT_VISIBLE", 4.0))
	assert(not feedback.reject({"issuer_type": "PlayerAssistAI", "issuer_id": "player"}, "TARGET_NOT_VISIBLE", 4.0))
	assert(not feedback.reject({"command_type": "RecordTutorialAction"}, "TUTORIAL_ACTION_NOT_REQUIRED", 4.0))
	assert(not feedback.reject({"command_type": "SetUnitControlState", "primary_auto_fire_suspended": true}, "TUTORIAL_ACTION_LOCKED", 4.0))
	assert(feedback.reject(player, "UNKNOWN_NEW_REASON", 5.0))
	assert(not feedback.current(5.0)["text"].contains("UNKNOWN_NEW_REASON"))
	for index in range(20): feedback.reject(player, "reason_%d" % index, 6.0 + index)
	assert(feedback.entries.size() == Feedback.HISTORY_LIMIT)
	feedback.clear()
	assert(feedback.current(26.0).is_empty())
	print("PASS: player rejection feedback filtering, merging, expiry, bounded history and reset")
	quit()
