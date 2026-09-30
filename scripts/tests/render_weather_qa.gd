extends SceneTree
## Clock-positioned visual fixtures, not played battle or balance evidence.
const OUT := "res://reports/weather/20260930-runtime"
func _init(): call_deferred("run")
func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var registry = root.get_node("DataRegistry").registry
	for resolution in [Vector2i(1920,1080), Vector2i(2560,1440)]:
		var viewport := SubViewport.new()
		viewport.size = resolution
		viewport.size_2d_override = Vector2i(1920,1080)
		viewport.size_2d_override_stretch = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var battle = load("res://scenes/battle/prototype_battle.tscn").instantiate()
		viewport.add_child(battle)
		battle.set_process(false)
		battle.level_id = "level.prototype_3v3"
		for scenario in ["fixed", "forecast", "storm", "paused", "details"]:
			var level: Dictionary = registry.get_definition("levels", "level.prototype_3v3").duplicate(true)
			level.map.ocean_palette = "clear_day"
			if scenario != "fixed": level.map.environment_timeline_id = "environment.timeline.storm_passage"
			battle.session.create_battle_from_definition(level, 9330)
			battle.environment_visual_revision = -1
			var ticks := 0 if scenario == "fixed" else (500 if scenario in ["forecast", "paused"] else 1200)
			for tick in range(ticks): battle.session.terrain_context_service.advance(0.1)
			battle.session.state.elapsed_time = ticks / 10.0
			battle.session.state.tick_index = ticks
			battle.session.state.global_environment = battle.session.terrain_context_service.global_snapshot()
			battle.session.state.environment_zones = battle.session.terrain_context_service.snapshot()
			if scenario == "paused": battle.session.pause()
			battle._sync_visuals()
			battle._update_hud()
			battle.ocean_surface.set_animation_paused(scenario == "paused")
			battle.weather_overlay.set_animation_paused(scenario == "paused")
			if scenario == "details": battle.battle_hud.weather_button.pressed.emit()
			await create_timer(0.15).timeout
			await process_frame
			var path := "%s/%s-%d.png" % [OUT, scenario, resolution.y]
			assert(viewport.get_texture().get_image().save_png(path) == OK)
			print("SAVED ", path)
			battle.battle_hud.weather_details.hide()
		battle.queue_free()
		await process_frame
		var menu = load("res://scenes/menu/main_menu.tscn").instantiate()
		viewport.add_child(menu)
		menu._show_custom()
		menu.custom_environment_selector.select(1)
		menu.custom_environment_selector.item_selected.emit(1)
		await create_timer(0.15).timeout
		await process_frame
		assert(viewport.get_texture().get_image().save_png("%s/menu-%d.png" % [OUT, resolution.y]) == OK)
		menu.queue_free()
		viewport.queue_free()
		await process_frame
	quit()
