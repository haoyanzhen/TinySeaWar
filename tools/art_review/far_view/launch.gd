extends SceneTree
func _init() -> void: call_deferred("run")
func run() -> void:
	root.get_node("GameFlow").selected_level_id = "level.challenge.l01"
	if "--sample" in OS.get_cmdline_user_args():
		var fixtures = load("res://tools/art_review/far_view/fixtures.gd")
		root.get_node("GameFlow").selected_level_id = "level.custom_runtime"
		root.get_node("GameFlow")._custom_level_definition = fixtures.sample_definition(root.get_node("DataRegistry").registry)
	var battle = load("res://scenes/battle/prototype_battle.tscn").instantiate()
	battle.set_script(load("res://tools/art_review/far_view/pilot_battle.gd"))
	root.add_child(battle)
	print("Far-view pilot: F6 original/candidate; F7 48/56/64; normal battle controls. No progress recording.")
