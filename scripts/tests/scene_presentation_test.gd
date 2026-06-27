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
	var data_registry = root.get_node("DataRegistry")
	var warspite_main: Dictionary = data_registry.registry.get_definition("weapons", "weapon.warspite_381_ap")
	var warspite_main_visual: Dictionary = data_registry.assets.weapon_visual("warspite", "warspite_main")
	var warspite_secondary: Dictionary = data_registry.registry.get_definition("weapons", "weapon.warspite_152_he")
	var warspite_secondary_visual: Dictionary = data_registry.assets.weapon_visual("warspite", "warspite_secondary")
	_check(battle.effect_director._is_large_caliber_gun(warspite_main, warspite_main_visual), "381mm main guns qualify for miss water columns")
	_check(not battle.effect_director._is_large_caliber_gun(warspite_secondary, warspite_secondary_visual), "152mm secondary guns do not qualify for miss water columns")
	var vfx_count_before_miss: int = battle.vfx_layer.get_child_count()
	battle.effect_director._handle_attack_resolved({"damage_result":{"source_unit_id":"unit.player.warspite","source_weapon_id":"weapon.warspite_381_ap","target_unit_id":"","hit":false,"impact_position":Vector2(900.0, 700.0)}}, battle.session)
	var vfx_count_after_large_miss: int = battle.vfx_layer.get_child_count()
	battle.effect_director._handle_attack_resolved({"damage_result":{"source_unit_id":"unit.player.warspite","source_weapon_id":"weapon.warspite_152_he","target_unit_id":"","hit":false,"impact_position":Vector2(920.0, 700.0)}}, battle.session)
	_check(vfx_count_after_large_miss == vfx_count_before_miss + 1 and battle.vfx_layer.get_child_count() == vfx_count_after_large_miss, "only large-caliber gun misses create a water-column VFX")
	_check(battle.battle_hud._texture("res://assets/ui/export/2x/ui_marker_selected.png") != null, "battle HUD loads exported UI marker art")
	_check(battle.battle_hud._portrait_texture(warspite_snapshot) != null, "battle HUD loads character portrait art")
	_check(battle.session.get_player_slots()[0].has("current_hp") and battle.session.get_player_slots()[0].has("ship_class"), "player slot data includes HUD presentation fields")
	var shimakaze: Dictionary = battle.session.state["units_by_id"]["unit.player.shimakaze"]
	shimakaze["heading"] = 0.0
	var torpedo_aim: Dictionary = battle.session.get_primary_aim_status(shimakaze["entity_id"], shimakaze["position"] + Vector2(0.0, 300.0))
	battle.selected_unit_id = shimakaze["entity_id"]
	battle.operation_mode = 1
	await process_frame
	_check(torpedo_aim.get("weapon_type", "") == "Torpedo" and torpedo_aim.get("fire_arcs", []).size() == 2, "torpedo aim overlay receives broadside sectors from the battle session")
	_check(is_equal_approx(float(torpedo_aim.get("range", 0.0)), 765.0), "torpedo range circle renders the 1.5x effective range")
	_check(battle.has_method("_draw_directional_aim_overlay") and battle.has_method("_draw_gun_aim_overlay") and battle.has_method("_draw_area_target_overlay") and battle.has_method("_draw_skill_target_overlay"), "battle scene uses direction, gun-sector, area, and skill tactical overlays")
	battle.operation_mode = 0
	battle.selected_unit_id = "unit.player.warspite"
	var warspite_aim: Dictionary = battle.session.get_primary_aim_status("unit.player.warspite", warspite_snapshot["position"] + Vector2(0.0, 400.0))
	_check(warspite_aim.get("fire_arcs", []).size() == 1 and warspite_aim.get("full_salvo_fire_arcs", []).size() == 2, "main-gun overlay receives green available sectors and dark-green all-mount sectors")
	battle._update_hud()
	_check(is_equal_approx(float(battle.session.get_operation_status("unit.player.warspite").get("primary_range", 0.0)), 1080.0), "HUD operation status displays the 1.5x main-gun range")
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
	var weather_material := battle.weather_overlay.material as ShaderMaterial
	_check(weather_material != null, "battle scene includes an independent weather overlay material")
	_check(float(ocean_material.get_shader_parameter("ai_texture_strength")) > 0.0, "runtime ocean palette enables authored ocean texture weight")
	_check(ocean_material.get_shader_parameter("base_texture") != null, "runtime ocean palette binds the authored base ocean texture")
	var ocean_palette_file := FileAccess.open("res://data/environments/ocean_palettes.json", FileAccess.READ)
	var ocean_palette_data: Dictionary = JSON.parse_string(ocean_palette_file.get_as_text())
	var ocean_palettes: Dictionary = ocean_palette_data.get("palettes", {})
	var ocean_times := ["day", "dawn", "dusk", "night"]
	var ocean_weathers := ["clear", "cloudy", "overcast", "rain", "thunderstorm"]
	for weather in ocean_weathers:
		for time_of_day in ocean_times:
			var palette_id := "%s_%s" % [weather, time_of_day]
			_check(ocean_palettes.has(palette_id), "ocean palette exists: %s" % palette_id)
			battle._set_ocean_palette(palette_id)
			_check(ocean_material.get_shader_parameter("base_texture") != null, "ocean palette binds texture: %s" % palette_id)
	battle._set_ocean_palette("rain_night")
	_check(float(ocean_material.get_shader_parameter("rain_strength")) > 0.0 and float(ocean_material.get_shader_parameter("mist_strength")) > 0.0, "rain ocean palette drives rain and mist shader layers")
	_check(float(ocean_material.get_shader_parameter("rain_density")) > 1.0 and float(ocean_material.get_shader_parameter("rain_line_strength")) > 1.0, "rain ocean palette drives visible rain-line profile parameters")
	_check(ocean_material.get_shader_parameter("rain_line_texture") != null and ocean_material.get_shader_parameter("rain_ripple_texture") != null, "rain ocean palette binds authored rain texture masters")
	_check(float(weather_material.get_shader_parameter("rain_strength")) > 0.0 and weather_material.get_shader_parameter("rain_line_texture") != null, "rain weather overlay binds authored rain layer")
	_check(weather_material.get_shader_parameter("snow_flake_texture") != null and weather_material.get_shader_parameter("snow_haze_texture") != null, "weather overlay binds authored snow master textures")
	battle._set_ocean_palette("thunderstorm_night")
	_check(float(ocean_material.get_shader_parameter("lightning_strength")) > 0.0 and float(ocean_material.get_shader_parameter("foam_strength")) > 0.0, "thunderstorm ocean palette drives lightning and foam shader layers")
	_check(float(ocean_material.get_shader_parameter("squall_strength")) > 0.0 and float(ocean_material.get_shader_parameter("wave_scale")) > 1.0, "thunderstorm ocean palette drives squall and rough-wave profile parameters")
	_check(ocean_material.get_shader_parameter("storm_shadow_texture") != null and ocean_material.get_shader_parameter("lightning_mask_texture") != null, "thunderstorm ocean palette binds authored storm texture masters")
	_check(float(weather_material.get_shader_parameter("lightning_strength")) > 0.0 and weather_material.get_shader_parameter("storm_shadow_texture") != null, "thunderstorm weather overlay drives storm and lightning layers")
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
	var shell_count_before: int = battle.projectile_layer.get_child_count()
	battle.effect_director.consume_events([
		{
			"event_type": "WeaponFired",
			"unit_id": "unit.player.warspite",
			"weapon_id": "weapon.warspite_381_ap",
			"target_position": warspite_snapshot["position"] + Vector2(360.0, 0.0),
			"shot_count": 2,
		}
	], battle.session)
	await process_frame
	var shell_flight_found := false
	for child in battle.projectile_layer.get_children():
		var script: Script = child.get_script() as Script
		if script != null and str(script.resource_path).ends_with("shell_flight_view.gd"):
			shell_flight_found = true
			break
	_check(battle.projectile_layer.get_child_count() > shell_count_before and shell_flight_found, "gun fire spawns visible shell flight nodes with trailing effects")
	var shell_destinations: Array = battle.effect_director._shell_flight_destinations({
		"event_type": "WeaponFired",
		"unit_id": "unit.player.warspite",
		"weapon_id": "weapon.warspite_381_ap",
		"target_position": warspite_snapshot["position"] + Vector2(360.0, 0.0),
		"shot_count": 8,
	}, battle.session, battle.session.registry.get_definition("weapons", "weapon.warspite_381_ap"), battle.session.state["units_by_id"]["unit.player.warspite"], warspite_snapshot["position"])
	var clustered_shells := true
	for destination in shell_destinations:
		if (destination as Vector2).distance_to(warspite_snapshot["position"] + Vector2(360.0, 0.0)) > 24.0:
			clustered_shells = false
			break
	_check(clustered_shells, "shell flight visuals cluster around the target area instead of forming a wide fan")
	battle.session.state["visible_by_faction"]["player"]["unit.enemy.bismarck"] = true
	var damage_result := {"target_unit_id":"unit.enemy.bismarck","source_unit_id":"unit.player.warspite","source_weapon_id":"weapon.warspite_381_ap","damage_type":"Gun","hit":true,"final_damage":321.0}
	var damage_numbers_before: int = battle.vfx_layer.get_child_count()
	battle.effect_director._spawn_damage_number(damage_result, battle.session)
	_check(battle.vfx_layer.get_child_count() > damage_numbers_before, "visible confirmed hits spawn runtime-font damage numbers")
	var damage_view = battle.effect_director.damage_number_views_by_target["unit.enemy.bismarck"][0]
	battle.effect_director._spawn_damage_number(damage_result, battle.session)
	_check(int(damage_view.hit_count) == 2 and int(damage_view.amount) == 642, "damage numbers merge rapid multi-hit damage on the same target")
	battle.session.state["visible_by_faction"]["player"].erase("unit.enemy.hindenburg")
	var hidden_result := {"target_unit_id":"unit.enemy.hindenburg","source_unit_id":"unit.player.warspite","source_weapon_id":"weapon.warspite_381_ap","damage_type":"Gun","hit":true,"final_damage":100.0}
	var hidden_count_before: int = battle.vfx_layer.get_child_count()
	battle.effect_director._spawn_damage_number(hidden_result, battle.session)
	_check(battle.vfx_layer.get_child_count() == hidden_count_before, "damage numbers do not reveal hidden enemy positions")
	battle.session.state["phase"] = "Finished"
	battle.session.state["result"] = {"winner_faction": "player", "reason": "FLAGSHIP_SUNK", "elapsed_time": 93.0}
	battle.result_character_id = "warspite"
	battle._update_hud()
	_check(battle.battle_hud.return_button.visible and battle.battle_hud.restart_button.visible, "result screen exposes return and replay buttons")
	_check(battle.battle_hud._texture("res://assets/characters/warspite/processed/ui/warspite_illust_full_alpha.png") != null, "result screen loads vertical friendly character illustration")
	battle._start_battle("level.prototype_11v11")
	await process_frame
	await process_frame
	battle.effect_director.sync_snapshot(battle.session.snapshot("player", true), "", "")
	_check(battle.effect_director.unit_views.size() == 22, "11v11 scene instantiates 22 unique runtime character views")
	var full_roster_views_ready := true
	for view in battle.effect_director.unit_views.values():
		if view.body_texture == null or view.rig_texture == null:
			full_roster_views_ready = false
			break
	_check(full_roster_views_ready, "all 11v11 roster members load battle body and rig artwork")

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
