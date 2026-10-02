extends SceneTree
func _init() -> void: call_deferred("_run")
func _run() -> void:
	var size := Vector2i(1920,1080)
	var scale := 3
	var difficulty := "Standard"
	var output := "/tmp/custom_matching.png"
	for arg in OS.get_cmdline_user_args():
		if arg == "--1440": size = Vector2i(2560,1440)
		elif arg.begins_with("--scale="): scale = int(arg.trim_prefix("--scale="))
		elif arg.begins_with("--difficulty="): difficulty = arg.trim_prefix("--difficulty=")
		elif arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	var flow = root.get_node("GameFlow")
	var registry = root.get_node("DataRegistry").registry
	flow.unlocked_ship_ids.assign(registry.all("ships").map(func(ship): return str(ship.id)))
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.size_2d_override = Vector2i(1920,1080)
	viewport.size_2d_override_stretch = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var menu = load("res://scenes/menu/main_menu.tscn").instantiate()
	viewport.add_child(menu)
	menu.custom_size_index = [1,3,5,11].find(scale)
	menu.custom_difficulty = difficulty
	var suffix: String = {3:".08", 5:".14", 11:".15"}.get(scale, "")
	var roster: Dictionary = registry.all("custom_rosters").filter(func(r): return int(r.unit_count) == scale and str(r.id).ends_with(suffix))[0]
	menu.selected_ship_ids.assign(roster.ship_ids)
	menu._show_custom()
	await create_timer(0.5).timeout
	await process_frame
	if "--enemy" in OS.get_cmdline_user_args(): menu.custom_fleet_tabs.current_tab = 1
	await process_frame
	var overflow := false
	for selector in [menu.custom_size_selector,menu.custom_map_selector,menu.custom_weather_selector,menu.custom_environment_selector,menu.custom_difficulty_selector]:
		if selector.get_global_rect().end.x > 1856: overflow = true
	print("CUSTOM_RENDER scale=%d difficulty=%s preview=%s overflow=%s" % [scale,difficulty,menu.custom_preview.get("ok",false),overflow])
	var result := viewport.get_texture().get_image().save_png(output)
	var passed: bool = result == OK and not overflow and menu.custom_preview.get("ok", false)
	menu.queue_free()
	viewport.queue_free()
	await process_frame
	quit(0 if passed else 1)
