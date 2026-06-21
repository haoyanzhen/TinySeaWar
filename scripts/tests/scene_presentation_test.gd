extends SceneTree

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var menu_scene: PackedScene = load("res://scenes/menu/main_menu.tscn")
	var menu = menu_scene.instantiate()
	root.add_child(menu)
	await process_frame
	_check(menu.has_node("btn_mode_1v1") and menu.has_node("btn_mode_3v3") and menu.has_node("btn_mode_5v5") and menu.has_node("btn_mode_11v11"), "main menu exposes 1v1, 3v3, 5v5, and 11v11 buttons")
	_check(menu.has_node("btn_settings") and menu.has_node("SettingsOverlay"), "main menu exposes window settings")
	menu._show_settings()
	_check(menu.settings_overlay.visible and menu.resolution_selector.item_count == 5, "window settings list configured resolutions")
	var flow = root.get_node_or_null("GameFlow")
	_check(flow != null and flow.logical_viewport_size() == Vector2i(1920, 1080), "window settings keep a fixed 1920x1080 logical canvas")
	_check(root.content_scale_size == Vector2i(1920, 1080), "root window applies the configured logical canvas size")
	_check(root.content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS and root.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_KEEP, "root window scales canvas items while preserving aspect ratio")
	_check(menu.size == Vector2(1920.0, 1080.0), "main menu retains its full logical layout instead of being cropped to the physical window")
	menu.settings_overlay.hide()
	_check(menu._character_texture(menu.cover_character_id, "illust_skill_cutin_alpha") != null, "main menu loads a random horizontal character cover")
	menu._show_operation_guide()
	_check(menu.info_title == "操作说明" and menu.info_body.contains("E"), "main menu operation guide is available")
	menu._show_game_intro()
	_check(menu.info_title == "游戏介绍" and menu.info_body.contains("胜利条件"), "main menu game introduction is available")
	menu.queue_free()
	await process_frame

	var scene: PackedScene = load("res://scenes/battle/prototype_battle.tscn")
	var battle = scene.instantiate()
	root.add_child(battle)
	await process_frame
	await process_frame
	var viewport_size: Vector2 = battle.get_viewport_rect().size
	var map_data: Dictionary = battle.session.state["map"]
	_check(viewport_size == Vector2(1920.0, 1080.0), "logical viewport is 1920x1080")
	_check(float(map_data["width"]) > viewport_size.x * 2.0, "map width exceeds two visible screens")
	_check(float(map_data["height"]) > viewport_size.y * 2.0, "map height exceeds two visible screens")
	var warspite_snapshot: Dictionary = battle.session.snapshot("player", false)["units"]["unit.player.warspite"]
	_check(str(warspite_snapshot.get("display_name", "")) == "厌战号", "battle snapshot exposes the Chinese character name")
	_check(str(warspite_snapshot.get("asset_root", "")).contains("assets/characters/warspite/processed"), "unit snapshot exposes character art root")
	_check(float(warspite_snapshot.get("collision_radius", 0.0)) > 0.0, "unit snapshot exposes presentation collision radius")
	var warspite_view = battle.effect_director.unit_views.get("unit.player.warspite", null)
	_check(warspite_view != null, "battle scene creates a runtime character view")
	_check(warspite_view.body_texture != null and warspite_view.rig_texture != null, "runtime character view loads body and rig art")
	_check(warspite_view._texture(warspite_view.animation.current_frame_path()) != null, "runtime character view loads animation frames")
	_check(battle.battle_hud._texture("res://assets/ui/export/2x/ui_marker_selected.png") != null, "battle HUD loads exported UI marker art")
	_check(battle.battle_hud._portrait_texture(warspite_snapshot) != null, "battle HUD loads character portrait art")
	_check(battle.session.get_player_slots()[0].has("current_hp") and battle.session.get_player_slots()[0].has("ship_class"), "player slot data includes HUD presentation fields")
	battle.selected_unit_id = "unit.player.warspite"
	battle._update_hud()
	_check(battle.battle_hud._skill_text().contains("老兵校射"), "battle HUD displays the Chinese skill name")
	var player_center: Vector2 = battle._player_fleet_center()
	_check(battle.battle_camera.position.distance_to(player_center) < 4.0, "initial camera centers on player fleet")
	_check(battle.camera_mode == "Manual", "initial camera remains in manual mode")
	var camera_center := viewport_size * 0.5
	for index in range(32):
		battle._adjust_camera_zoom(0.8, camera_center)
	var far_visible_size: Vector2 = battle._camera_visible_size()
	_check(is_equal_approx(battle.battle_camera.zoom.x, battle.camera_zoom_min), "mouse wheel zoom-out stops at the configured map fraction")
	_check(far_visible_size.x <= float(map_data["width"]) * 0.6666667 + 0.1 and far_visible_size.y <= float(map_data["height"]) * 0.6666667 + 0.1, "zoom-out never reveals more than two thirds of the battlefield")
	for index in range(32):
		battle._adjust_camera_zoom(1.25, camera_center)
	var near_visible_size: Vector2 = battle._camera_visible_size()
	_check(is_equal_approx(battle.battle_camera.zoom.x, battle.camera_zoom_max), "mouse wheel zoom-in stops at the configured minimum view")
	_check(near_visible_size.x >= 500.0 - 0.1 and near_visible_size.y >= 500.0 - 0.1, "zoom-in preserves at least a 500x500 world-space view")
	battle.battle_camera.position = Vector2(float(map_data["width"]) * 0.5, float(map_data["height"]) * 0.5)
	var anchor_screen := Vector2(1260.0, 620.0)
	var anchor_before: Vector2 = battle.battle_camera.position + (anchor_screen - camera_center) / battle.battle_camera.zoom.x
	battle._adjust_camera_zoom(0.8, anchor_screen)
	var anchor_after: Vector2 = battle.battle_camera.position + (anchor_screen - camera_center) / battle.battle_camera.zoom.x
	_check(anchor_before.distance_to(anchor_after) < 0.1, "camera zoom keeps the world point under the mouse stable")
	battle._configure_camera_zoom(map_data)
	battle.battle_camera.position = player_center

	battle.selected_unit_id = "unit.player.warspite"
	battle._toggle_follow_selected()
	_check(battle.camera_mode == "Follow", "follow mode activates for selected friendly unit")
	var followed: Dictionary = battle.session.state["units_by_id"]["unit.player.warspite"]
	followed["position"] = Vector2(2200.0, 1300.0)
	var distance_before_follow: float = battle.battle_camera.position.distance_to(followed["position"])
	battle._update_camera(0.1)
	_check(battle.camera_mode == "Follow" and battle.battle_camera.position.distance_to(followed["position"]) < distance_before_follow, "follow camera smoothly approaches the selected friendly unit")

	battle._set_ocean_palette("dusk")
	_check(battle.current_palette_id == "dusk", "ocean palette can switch at runtime")
	var ocean_material := battle.ocean_surface.material as ShaderMaterial
	_check(float(ocean_material.get_shader_parameter("ai_texture_strength")) > 0.0, "runtime ocean palette enables authored ocean texture weight")
	_check(ocean_material.get_shader_parameter("base_texture") != null, "runtime ocean palette binds the authored base ocean texture")
	var camera_before_input: Vector2 = battle.battle_camera.position
	Input.action_press("camera_right")
	await process_frame
	Input.action_release("camera_right")
	_check(battle.camera_mode == "Manual" and battle.battle_camera.position.x > camera_before_input.x, "WASD input exits follow mode and moves the camera")
	battle.battle_camera.position = Vector2(-1000.0, -1000.0)
	battle._clamp_camera_to_map()
	_check(battle.battle_camera.position.x > 0.0 and battle.battle_camera.position.y > 0.0, "camera clamp prevents exposing outside the map")
	warspite_view.play_fire_state("firepower")
	await process_frame
	_check(warspite_view.current_animation_state() == "firepower", "weapon fire can drive the character animation state")
	var vfx_count_before: int = battle.vfx_layer.get_child_count()
	battle.effect_director._spawn_role_vfx("warspite", "heavy_muzzle", warspite_snapshot["position"], 0.0, "vfx.profile.muzzle_flash")
	await process_frame
	_check(battle.vfx_layer.get_child_count() > vfx_count_before, "VFX director can spawn role-bound combat effects")
	battle.session.state["phase"] = "Finished"
	battle.session.state["result"] = {"winner_faction": "player", "reason": "FLAGSHIP_SUNK", "elapsed_time": 93.0}
	battle.result_character_id = "warspite"
	battle._update_hud()
	_check(battle.battle_hud.return_button.visible and battle.battle_hud.restart_button.visible, "result screen exposes return and replay buttons")
	_check(battle.battle_hud._texture("res://assets/characters/warspite/processed/ui/warspite_illust_full_alpha.png") != null, "result screen loads vertical friendly character illustration")

	battle.queue_free()
	if failures.is_empty():
		print("PASS: %d scene presentation checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error("FAIL: %s" % failure)
		print("FAILED: %d of %d scene presentation checks" % [failures.size(), checks])
		quit(1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
