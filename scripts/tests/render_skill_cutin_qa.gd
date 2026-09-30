extends SceneTree
## Deterministic visual fixtures, not human acceptance or balance evidence.
const OUT := "res://reports/skill_cutin/20260930-transparent"
func _init(): call_deferred("run")
func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for resolution in [Vector2i(1920,1080), Vector2i(2560,1440), Vector2i(3840,2160)]:
		var viewport := SubViewport.new()
		viewport.size = resolution
		viewport.size_2d_override = Vector2i(1920,1080)
		viewport.size_2d_override_stretch = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var battle = load("res://scenes/battle/prototype_battle.tscn").instantiate()
		viewport.add_child(battle)
		battle.set_process(false)
		var overlay = battle.skill_cutin
		overlay.set_process(false)
		for palette in ["clear_day", "thunderstorm_night"]:
			battle.palette_override = palette
			battle._start_battle("level.prototype_3v3")
			battle._sync_visuals()
			battle._update_hud()
			for side in ["player", "enemy"]:
				overlay.set_mode("full")
				battle._sync_skill_cutin()
				overlay.present({"character_id":"hood" if side == "player" else "bismarck", "character_name":"胡德" if side == "player" else "俾斯麦", "skill_name":"皇家海军的荣耀" if side == "player" else "超长技能名称：集中火力齐射与舰队协同作战", "faction_id":side})
				for i in range(4):
					overlay.present({"character_id":"warspite" if i < 3 else "missing_fixture", "character_name":"厌战" if i < 3 else "缺图文字回退", "skill_name":"精确齐射 · %d" % i, "faction_id":side})
				overlay.advance(0.2)
				await create_timer(0.15).timeout
				await process_frame
				RenderingServer.force_draw(false)
				var path := "%s/%s-%s-%d.png" % [OUT, palette, side, resolution.y]
				assert(viewport.get_texture().get_image().save_png(path) == OK)
				print("SAVED ", path)
				if resolution.y == 1080 and palette == "clear_day" and side == "player":
					overlay.compact.clear()
					for frame in range(21):
						if frame == 20: overlay.full.clear()
						else: overlay.full.age = frame * 0.05
						overlay.queue_redraw()
						await process_frame
						RenderingServer.force_draw(false)
						assert(viewport.get_texture().get_image().save_png("%s/motion-%02d.png" % [OUT, frame]) == OK)

		battle.session.pause()
		battle._sync_skill_cutin()
		battle._update_hud()
		battle.battle_hud.pause_panel.modulate = Color.WHITE
		await create_timer(0.15).timeout
		assert(battle.battle_hud.pause_panel.get_rect().end.y < battle.battle_hud.minimap_rect().position.y)
		RenderingServer.force_draw(false)
		assert(viewport.get_texture().get_image().save_png("%s/settings-%d.png" % [OUT,resolution.y]) == OK)
		viewport.queue_free()
		await process_frame
	quit()
