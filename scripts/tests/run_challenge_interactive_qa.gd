extends SceneTree
# Uses only an in-memory save so real keyboard QA cannot alter the user's profile.
class MemoryStore extends RefCounted:
	var data := {}
	func save(_path: String, value: Dictionary) -> bool:
		data = value.duplicate(true)
		return true
	func load_best(_path: String) -> Dictionary: return data.duplicate(true)

func _init() -> void: call_deferred("_run")
func _run() -> void:
	var flow = root.get_node("GameFlow")
	flow._progress_store = MemoryStore.new()
	flow._apply_loaded_progress({"schema_version":1, "unlocked_ship_ids":[], "completed_challenge_level_ids":[]})
	root.size = Vector2i(1280, 720)
	change_scene_to_file("res://scenes/menu/main_menu.tscn")
