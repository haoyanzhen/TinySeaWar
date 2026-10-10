extends SceneTree
const Fixtures = preload("res://tools/art_review/far_view/fixtures.gd")
const OUT = "res://reports/art/20261009-far-view"
var records: Array = []
func _init() -> void: call_deferred("run")
func make_battle(size: Vector2i, sample: bool) -> Dictionary:
	var viewport = SubViewport.new()
	viewport.size = size
	viewport.size_2d_override = Vector2i(1920,1080)
	viewport.size_2d_override_stretch = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var flow = root.get_node("GameFlow")
	flow.selected_level_id = "level.custom_runtime" if sample else "level.challenge.l01"
	if sample: flow._custom_level_definition = Fixtures.sample_definition(root.get_node("DataRegistry").registry)
	var battle = load("res://scenes/battle/prototype_battle.tscn").instantiate()
	battle.set_script(load("res://tools/art_review/far_view/pilot_battle.gd"))
	viewport.add_child(battle)
	battle.set_process(false)
	var stamp = Label.new()
	stamp.name = "ReviewStamp"
	stamp.position = Vector2(38,150)
	stamp.add_theme_font_size_override("font_size",16)
	stamp.add_theme_color_override("font_color",Color("ffdf86"))
	stamp.add_theme_color_override("font_shadow_color",Color("142d3b"))
	stamp.add_theme_constant_override("shadow_offset_x",1)
	stamp.add_theme_constant_override("shadow_offset_y",1)
	battle.battle_hud.add_child(stamp)
	return {"viewport":viewport,"battle":battle}
func capture(pair: Dictionary, name: String, kind: String) -> void:
	pair.battle.battle_hud.get_node("ReviewStamp").text = ("受控22单位压力布局 · 三角色重复 · 非真实战斗/侦查证据" if name.begins_with("density") else ("L-01真实开局 · 仅厌战/雪风替换 · 其余保持原版" if name.begins_with("fleet") else "实际3v3公开快照 · 三角色试验 · 人工美术待审")) + (" | 候选 %dpx" % pair.battle.candidate_height if pair.battle.candidate_enabled else " | 原版")
	await process_frame
	await process_frame
	RenderingServer.force_draw(false)
	var path := OUT+"/"+name+".png"
	assert(pair.viewport.get_texture().get_image().save_png(path)==OK)
	records.append({"file":name+".png","kind":kind,"resolution":[pair.viewport.size.x,pair.viewport.size.y],"zoom":pair.battle.battle_camera.zoom.x,"candidate":pair.battle.candidate_enabled,"height":pair.battle.candidate_height})
	print("SAVED ",name)
func freeze_views(battle) -> void:
	for view in battle.effect_director.unit_views.values():
		view.set_process(false)
		if view.get("clock_seconds") != null: view.clock_seconds=0.0
func set_camera(battle, center: Vector2, near: bool=false) -> void:
	battle.battle_camera.zoom=Vector2.ONE*(battle.camera_zoom_max if near else battle.camera_zoom_min)
	battle.battle_camera.position=center
	battle.battle_camera.reset_smoothing()
	battle._clamp_camera_to_map()
func run() -> void:
	var registry=root.get_node("DataRegistry").registry
	# Real formal 11-ship opening: only supported character IDs change.
	var pair=make_battle(Vector2i(1920,1080),false)
	var battle=pair.battle
	set_camera(battle,battle._player_fleet_center())
	for h in [0,48,56,64]:
		battle.candidate_enabled=h!=0
		battle.candidate_height=float(max(h,48))
		battle._sync_visuals(); battle._update_hud(); freeze_views(battle)
		await capture(pair,"fleet11_1080_"+str(h),"formal L-01 opening; public snapshot; partial 3-character pilot coverage")
	pair.viewport.queue_free(); await process_frame
	# Controlled 22-unit crossing, explicitly separate from real visibility/navigation.
	for size in [Vector2i(1920,1080),Vector2i(2560,1440),Vector2i(3840,2160)]:
		pair=make_battle(size,true); battle=pair.battle
		set_camera(battle,Vector2(3072,1728))
		var snap: Dictionary=Fixtures.density_snapshot(registry)
		for h in ([0,48,56,64] if size.y==1080 else [56]):
			battle.candidate_enabled=h!=0
			battle.candidate_height=float(max(h,48))
			battle.effect_director.sync_snapshot(snap,"fixture.0.00","fixture.1.00",["fixture.0.00"])
			battle.apply_review_views(); freeze_views(battle)
			await capture(pair,"density22_%d_%d" % [size.y,h],"controlled 22-unit visual fixture; repeated three pilot identities; NOT actual battle or visibility evidence")
		pair.viewport.queue_free(); await process_frame
	# Actual equal 3v3, deterministic real events and public visibility.
	pair=make_battle(Vector2i(1920,1080),true); battle=pair.battle
	set_camera(battle,Vector2(3072,1728))
	battle.session.configure_full_ai_factions(["player","enemy"])
	for tick in range(160):
		battle._process(0.1)
		if tick%10==0: await process_frame
	var state_before:=var_to_bytes(battle.session.state)
	for h in [0,48,56,64]:
		battle.candidate_enabled=h!=0; battle.candidate_height=float(max(h,48))
		battle._sync_visuals(); battle._update_hud(); freeze_views(battle)
		await capture(pair,"combat3_1080_"+str(h),"actual 3v3 16-second public snapshot; identical Domain state across A/B")
	assert(var_to_bytes(battle.session.state)==state_before)
	battle.candidate_enabled=true; battle.candidate_height=56.0
	set_camera(battle,battle._player_fleet_center(),true)
	battle._sync_visuals(); battle._update_hud(); freeze_views(battle)
	await capture(pair,"near3_1080_56","near zoom compatibility check, same 16-second state")
	pair.viewport.queue_free(); await process_frame
	# Actual combat replay video at maximum distance, 12 seconds from start.
	pair=make_battle(Vector2i(1920,1080),true); battle=pair.battle
	set_camera(battle,Vector2(3072,1728))
	battle.session.configure_full_ai_factions(["player","enemy"])
	battle.battle_hud.get_node("ReviewStamp").text="实际3v3 · 最远视角56px · 前12秒公开画面 · 美术候选待审"
	for frame in range(120):
		battle._process(0.1)
		for view in battle.effect_director.unit_views.values():
			view.set_process(false)
			view._process(0.1)
		await process_frame
		RenderingServer.force_draw(false)
		assert(pair.viewport.get_texture().get_image().save_png(OUT+"/frames/combat_%04d.png"%frame)==OK)
	print("VIDEO_FRAMES 120; simulation_time=",battle.session.state.elapsed_time)
	pair.viewport.queue_free(); await process_frame
	var file=FileAccess.open(OUT+"/captures.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(records,"\t"));file.close()
	quit()
