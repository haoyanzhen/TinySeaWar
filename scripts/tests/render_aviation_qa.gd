extends SceneTree
func _init(): call_deferred("run")
func run():
	var out := "res://reports/aviation/20260929-runtime"
	var size := Vector2i(1920,1080)
	var carrier := "enterprise_cv6"
	var palette := "day_clear"
	var zoom := 1.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--carrier="): carrier = arg.trim_prefix("--carrier=")
		if arg.begins_with("--palette="): palette = arg.trim_prefix("--palette=")
		if arg.begins_with("--zoom="): zoom = float(arg.trim_prefix("--zoom="))
		if arg == "--1440p": size = Vector2i(2560,1440)
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.size_2d_override = Vector2i(1920,1080)
	viewport.size_2d_override_stretch = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var battle = load("res://scenes/battle/prototype_battle.tscn").instantiate()
	viewport.add_child(battle)
	await process_frame
	battle.set_process(false)
	var registry = root.get_node("DataRegistry").registry
	var level: Dictionary = registry.get_definition("levels", "level.prototype_1v1").duplicate(true)
	level.map.ocean_palette = palette
	level.player_fleet[0].ship_id = "ship." + carrier
	level.player_fleet[0].position = [1700.0,1100.0]
	level.enemy_fleet[0].position = [2350.0,1100.0]
	level.aviation_rules_mode = "Physical" if "--physical" in OS.get_cmdline_user_args() else "Abstract"
	battle.session.create_battle_from_definition(level, 2910)
	battle.level_id = "level.prototype_1v1"
	battle.recent_messages.clear()
	battle.session._full_ai_factions.clear()
	for unit in battle.session.state.units_by_id.values():
		unit.secondary_auto_fire_enabled = false
		unit.primary_auto_fire_enabled = false
		unit.skill_auto_cast_enabled = false
	var source: Dictionary = battle.session.state.units_by_id["unit.player.warspite"]
	var target: Dictionary = battle.session.state.units_by_id["unit.enemy.bismarck"]
	battle.selected_unit_id = source.entity_id
	battle.selected_unit_ids.assign([str(source.entity_id)])
	battle.session.state.visible_by_faction.player = {target.entity_id:true}
	battle._set_ocean_palette(palette)
	battle.battle_camera.zoom = Vector2.ONE * zoom
	battle.battle_camera.position = Vector2(1950,1100)
	battle._clamp_camera_to_map()
	battle._sync_visuals()
	battle._update_hud()
	if "--torpedo" in OS.get_cmdline_user_args():
		battle.session._fire_weapon_at_position(source, target.position, source.weapon_states[0], registry.get_definition("weapons", "weapon.shokaku_torpedo_bomber"), true)
	var result: Dictionary = {"accepted":true} if "--torpedo" in OS.get_cmdline_user_args() else battle.session._fire_primary_weapon(source, target.position, "qa.aviation")
	var grounded_expected := "--expect-grounded" in OS.get_cmdline_user_args()
	if grounded_expected:
		assert(not result.get("accepted", false) and result.get("reason_code", "") == "AVIATION_WEATHER_BLOCKED")
		assert(battle.session.snapshot().aviation.is_empty())
	if not result.get("accepted", false) and not grounded_expected:
		push_error("QA fire rejected " + str(result))
		quit(1)
		return
	battle._consume_events(battle.session._event_buffer)
	var facts: Array = []
	for frame in range(100):
		var events: Array = battle.session.advance_tick(0.1)
		facts.append_array(events.filter(func(e): return str(e.event_type).begins_with("Aviation") or e.event_type in ["AttackResolved", "AircraftDestroyed", "AircraftDamaged"]))
		battle._consume_events(events)
		battle._sync_visuals()
		battle._update_hud()
		await process_frame
		await RenderingServer.frame_post_draw
		if frame in [1,30,60,85] or "--frames" in OS.get_cmdline_user_args():
			viewport.get_texture().get_image().save_png(out + "/%s-%s-%d-%03d.png" % [carrier,palette,size.y,frame])
	FileAccess.open(out + "/%s-%s-%d-facts.json" % [carrier,palette,size.y], FileAccess.WRITE).store_string(JSON.stringify(facts,"\t"))
	print("Aviation render complete: ",carrier," ",size," facts=",facts.size())
	quit()
