extends SceneTree

func _init() -> void: call_deferred("_run")

func _run() -> void:
	var output := "res://reports/multi_selection/20260930"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	for resolution in [Vector2i(1920, 1080), Vector2i(2560, 1440)]:
		var viewport := SubViewport.new()
		viewport.size = resolution
		viewport.size_2d_override = Vector2i(1920, 1080)
		viewport.size_2d_override_stretch = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var battle = load("res://scenes/battle/prototype_battle.tscn").instantiate()
		battle.progress_recording_enabled = false
		viewport.add_child(battle)
		battle.set_process(false)
		battle._select_in_rect(Rect2(-Vector2.ONE * 10000, Vector2.ONE * 30000), battle.session.snapshot("player", false))
		var center := Vector2.ZERO
		for id in battle._selected_live_ids(): center += battle.session.state.units_by_id[id].position
		center /= battle._selected_live_ids().size()
		battle.battle_camera.position = center
		battle.battle_camera.zoom = Vector2.ONE * 1.1
		battle.battle_camera.reset_smoothing()
		battle._clamp_camera_to_map()
		battle._sync_visuals()
		battle._update_hud()
		await create_timer(0.2).timeout
		await process_frame
		RenderingServer.force_draw(false)
		var path := "%s/selected-%d.png" % [output, resolution.y]
		assert(viewport.get_texture().get_image().save_png(path) == OK)
		print("SAVED ", path)
		viewport.queue_free()
		await process_frame
	quit()
