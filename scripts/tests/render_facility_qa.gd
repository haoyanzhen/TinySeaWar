extends SceneTree
const OUT := "res://reports/facilities/20261002-runtime"
func _init(): call_deferred("run")
func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
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
		battle.level_id = "level.prototype_harbor_3v3"
		battle.session.create_battle(battle.level_id, 42021)
		battle.selected_unit_id = "unit.player.shimakaze"
		battle.selected_unit_ids.assign([battle.selected_unit_id])
		for facility_id in ["facility.harbor.communication_east", "facility.harbor.radar_east", "facility.harbor.repair_berth_east"]:
			battle.selected_facility_id = facility_id
			battle._sync_visuals()
			battle._update_hud()
			await create_timer(0.15).timeout
			await process_frame
			var path := "%s/%s-%d.png" % [OUT, facility_id.get_slice(".",2), resolution.y]
			assert(viewport.get_texture().get_image().save_png(path) == OK)
			print("SAVED ",path)
		battle.queue_free()
		viewport.queue_free()
		await process_frame
	quit()
