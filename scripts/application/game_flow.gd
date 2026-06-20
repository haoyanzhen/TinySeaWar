extends Node

const DEFAULT_LEVEL_ID := "level.prototype_3v3"

var selected_level_id := DEFAULT_LEVEL_ID


func select_level(level_id: String) -> void:
	selected_level_id = level_id if not level_id.is_empty() else DEFAULT_LEVEL_ID


func selected_mode_label() -> String:
	match selected_level_id:
		"level.prototype_1v1": return "1v1 Duel"
		"level.prototype_3v3": return "3v3 Fleet Test"
		"level.prototype_5v5": return "5v5 Fleet Battle"
		"level.prototype_11v11": return "11v11 Stress Battle"
		_: return selected_level_id.trim_prefix("level.")
