extends SceneTree
## Presentation fixtures only; never record player progression.
const OUT := "res://reports/portraits/20261001-unframed/ui"

func _init() -> void: call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
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
		battle._sync_visuals()
		battle._update_hud()
		await create_timer(0.3).timeout
		await process_frame
		RenderingServer.force_draw(false)
		assert(viewport.get_texture().get_image().save_png("%s/hud-%d.png" % [OUT, resolution.y]) == OK)
		var overlay = battle.skill_cutin
		overlay.set_process(false)
		overlay.set_mode("simple")
		battle._sync_skill_cutin()
		assert(overlay.running)
		for id in ["hai_shih", "akizuki", "belfast"]:
			overlay.present({"character_id":id, "character_name":id, "skill_name":"头像显示审查", "faction_id":"enemy" if id == "belfast" else "player"})
		assert(overlay.compact.size() == 3)
		await process_frame
		RenderingServer.force_draw(false)
		assert(viewport.get_texture().get_image().save_png("%s/skill-hints-%d.png" % [OUT, resolution.y]) == OK)
		print("PORTRAIT_UI_QA saved HUD and skill hints ", resolution)
		viewport.queue_free()
		await process_frame
	quit()
