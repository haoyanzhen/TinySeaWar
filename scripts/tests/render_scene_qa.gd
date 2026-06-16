extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var target_size := Vector2i(1920, 1080)
	var output_path := "/tmp/tinyseawar_scene_qa.png"
	var palette_id := "cloudy"
	var camera_position := Vector2(-1.0, -1.0)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--size="):
			var parts := argument.trim_prefix("--size=").split("x")
			if parts.size() == 2: target_size = Vector2i(int(parts[0]), int(parts[1]))
		elif argument.begins_with("--output="): output_path = argument.trim_prefix("--output=")
		elif argument.begins_with("--palette="): palette_id = argument.trim_prefix("--palette=")
		elif argument.begins_with("--camera="):
			var parts := argument.trim_prefix("--camera=").split(",")
			if parts.size() == 2: camera_position = Vector2(float(parts[0]), float(parts[1]))

	var viewport := SubViewport.new()
	viewport.size = target_size
	viewport.size_2d_override = Vector2i(1920, 1080)
	viewport.size_2d_override_stretch = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var scene: PackedScene = load("res://scenes/battle/prototype_battle.tscn")
	var battle = scene.instantiate()
	viewport.add_child(battle)
	await process_frame
	battle._set_ocean_palette(palette_id)
	if camera_position.x >= 0.0 and camera_position.y >= 0.0:
		battle.battle_camera.position = camera_position
		battle._clamp_camera_to_map()
		battle.battle_camera.reset_smoothing()
	await process_frame
	await process_frame
	var image := viewport.get_texture().get_image()
	var error := image.save_png(output_path)
	if error != OK:
		push_error("Could not save scene QA image: %s" % error)
		quit(1)
		return
	print("SAVED: %s (%sx%s)" % [output_path, image.get_width(), image.get_height()])
	battle.queue_free()
	viewport.queue_free()
	quit(0)
