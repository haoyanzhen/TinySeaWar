extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var target_size := Vector2i(1920, 1080)
	var output_path := "/tmp/tinyseawar_scene_qa.png"
	var palette_id := "cloudy"
	var level_id := "level.prototype_3v3"
	var camera_position := Vector2(-1.0, -1.0)
	var camera_zoom := -1.0
	var terrain_debug := false
	var base_level_id := ""
	var map_level_id := ""
	var simulation_ticks := 0
	var full_ai := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--size="):
			var parts := argument.trim_prefix("--size=").split("x")
			if parts.size() == 2: target_size = Vector2i(int(parts[0]), int(parts[1]))
		elif argument.begins_with("--output="):
			output_path = argument.trim_prefix("--output=")
		elif argument.begins_with("--palette="):
			palette_id = argument.trim_prefix("--palette=")
		elif argument.begins_with("--level="):
			level_id = argument.trim_prefix("--level=")
		elif argument.begins_with("--camera="):
			var parts := argument.trim_prefix("--camera=").split(",")
			if parts.size() == 2: camera_position = Vector2(float(parts[0]), float(parts[1]))
		elif argument.begins_with("--zoom="):
			camera_zoom = float(argument.trim_prefix("--zoom="))
		elif argument == "--terrain-debug":
			terrain_debug = true
		elif argument.begins_with("--base-level="):
			base_level_id = argument.trim_prefix("--base-level=")
		elif argument.begins_with("--map-level="):
			map_level_id = argument.trim_prefix("--map-level=")
		elif argument.begins_with("--ticks="):
			simulation_ticks = int(argument.trim_prefix("--ticks="))
		elif argument == "--full-ai":
			full_ai = true

	var viewport := SubViewport.new()
	viewport.size = target_size
	viewport.size_2d_override = Vector2i(1920, 1080)
	viewport.size_2d_override_stretch = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var flow := root.get_node_or_null("GameFlow")
	var data_registry := root.get_node_or_null("DataRegistry")
	if flow != null:
		if not base_level_id.is_empty() and not map_level_id.is_empty():
			if data_registry == null:
				push_error("DataRegistry autoload is unavailable")
				quit(1)
				return
			var base_level: Dictionary = data_registry.registry.get_definition("levels", base_level_id)
			var player_ship_ids: Array[String] = []
			for member in base_level.get("player_fleet", []):
				var ship_id := str(member.get("ship_id", ""))
				player_ship_ids.append(ship_id)
				if ship_id not in flow.unlocked_ship_ids:
					flow.unlocked_ship_ids.append(ship_id)
			var custom_result: Dictionary = flow.configure_custom_battle(base_level_id, map_level_id, palette_id, player_ship_ids)
			if not bool(custom_result.get("ok", false)):
				push_error("Could not configure scene QA custom battle: %s" % custom_result)
				quit(1)
				return
			level_id = str(custom_result.get("level_id", level_id))
		flow.select_level(level_id)
	var scene: PackedScene = load("res://scenes/battle/prototype_battle.tscn")
	var battle = scene.instantiate()
	viewport.add_child(battle)
	await process_frame
	battle.set_process(false)
	if full_ai:
		battle.session.configure_full_ai_factions(["player", "enemy"])
	var executed_ticks := 0
	while executed_ticks < simulation_ticks and battle.session.state.get("phase", "") == "Running":
		battle._consume_events(battle.session.advance_tick(0.1))
		executed_ticks += 1
	battle._set_ocean_palette(palette_id)
	if camera_zoom > 0.0:
		battle.battle_camera.zoom = Vector2.ONE * camera_zoom
	if camera_position.x < 0.0 and camera_position.y < 0.0 and executed_ticks > 0:
		var selected_unit: Dictionary = battle.session.state.get("units_by_id", {}).get(battle.selected_unit_id, {})
		if not selected_unit.is_empty():
			camera_position = selected_unit.get("position", Vector2.ZERO)
	if camera_position.x >= 0.0 and camera_position.y >= 0.0:
		battle.battle_camera.position = camera_position
		battle._clamp_camera_to_map()
		battle.battle_camera.reset_smoothing()
	if terrain_debug:
		battle.terrain_debug_overlay.visible = true
		battle._sync_visuals()
		battle._update_hud()
	await process_frame
	await process_frame
	var image := viewport.get_texture().get_image()
	if image == null:
		push_error("Could not read scene QA image; use a real rendering driver")
		quit(1)
		return
	var error := image.save_png(output_path)
	if error != OK:
		push_error("Could not save scene QA image: %s" % error)
		quit(1)
		return
	print("SAVED: %s (%sx%s) level=%s ticks=%d phase=%s" % [output_path, image.get_width(), image.get_height(), level_id, executed_ticks, battle.session.state.get("phase", "")])
	battle.queue_free()
	viewport.queue_free()
	quit(0)
