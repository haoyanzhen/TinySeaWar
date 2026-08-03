extends SceneTree

const BattleSession = preload("res://scripts/application/battle_session.gd")

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var menu_scene: PackedScene = load("res://scenes/menu/main_menu.tscn")
	var menu = menu_scene.instantiate()
	root.add_child(menu)
	await process_frame
	var flow = root.get_node_or_null("GameFlow")
	_check(not menu.has_node("btn_mode_1v1") and not menu.has_node("btn_mode_coastal"), "main menu removes direct prototype battle entry buttons")
	menu._show_tutorial()
	var tutorial_buttons := _descendants_of_type(menu.content, "Button")
	_check(tutorial_buttons.size() == 8, "tutorial entry exposes all eight designed training levels")
	var enabled_tutorial_buttons := tutorial_buttons.filter(func(button): return not button.disabled)
	_check(enabled_tutorial_buttons.size() == 8 and ["T-01", "T-02", "T-03", "T-04", "T-05", "T-06", "T-07", "T-08"].all(func(code): return enabled_tutorial_buttons.any(func(button): return button.text.contains(code))), "tutorial entry enables all eight implemented training levels")
	menu._show_challenge()
	var challenge_buttons := _descendants_of_type(menu.content, "Button")
	_check(challenge_buttons.size() == 15, "challenge entry exposes all fifteen designed challenge levels")
	_check(challenge_buttons.any(func(button): return not button.disabled and button.text.contains("S-01")), "challenge entry always enables the first implemented S challenge")
	menu._show_custom()
	_check(menu.custom_size_selector.item_count == 4 and menu.custom_map_selector.item_count == 11 and menu.custom_weather_selector.item_count == 20, "custom entry exposes four scales, open sea plus ten 16:9 coastal maps, and twenty weather palettes")
	var all_sizes_expose_expected_maps := true
	for size_index in range(menu.custom_size_selector.item_count):
		menu.custom_size_selector.select(size_index)
		menu._refresh_custom_maps()
		all_sizes_expose_expected_maps = all_sizes_expose_expected_maps and menu.custom_map_selector.item_count == 11
	menu.custom_size_selector.select(1)
	menu._refresh_custom_maps()
	_check(all_sizes_expose_expected_maps, "all scales expose the ten reviewed 16:9 coastal maps")
	_check(menu.ship_buttons.size() == 48, "custom fleet builder lists all configured characters")
	var custom_ship_ids: Array[String] = ["ship.ward", "ship.gnevny", "ship.argus"]
	var custom_result: Dictionary = flow.configure_custom_battle("level.prototype_3v3", "level.prototype_harbor_3v3", "clear_night", custom_ship_ids)
	var custom_level: Dictionary = flow.runtime_level_definition("level.custom_runtime")
	_check(custom_result.get("ok", false) and custom_level.get("player_fleet", []).size() == 3, "custom fleet selection builds a runtime level with the selected roster")
	_check(custom_level.get("map", {}).get("terrain_definition_id", "") == "terrain.map.harbor_mouth_16x9" and custom_level.get("map", {}).get("ocean_palette", "") == "clear_night", "custom runtime level applies the selected 16:9 map and weather")
	_check(custom_level.get("player_fleet", [])[0].get("position", []) == root.get_node("DataRegistry").registry.get_definition("levels", "level.prototype_harbor_3v3").get("player_fleet", [])[0].get("position", []) and custom_level.get("enemy_fleet", [])[0].get("position", []) == root.get_node("DataRegistry").registry.get_definition("levels", "level.prototype_harbor_3v3").get("enemy_fleet", [])[0].get("position", []), "custom runtime level uses the selected map's reviewed spawn slots for both fleets")
	_check(root.get_node("DataRegistry").registry.get_definition("levels", "level.custom_runtime").is_empty(), "custom runtime level does not modify the formal definition registry")
	var custom_session = BattleSession.new(root.get_node("DataRegistry").registry)
	_check(custom_session.create_battle_from_definition(custom_level, 901).get("ok", false), "custom runtime level creates a playable battle session")
	_test_custom_map_spawns(flow, root.get_node("DataRegistry").registry)
	_test_custom_open_sea_spawns(flow, root.get_node("DataRegistry").registry)
	flow.select_level("level.prototype_3v3")
	_check(flow != null and flow.logical_viewport_size() == Vector2i(1920, 1080), "window settings keep a fixed 1920x1080 logical canvas")
	_check(root.content_scale_size == Vector2i(1920, 1080), "root window applies the configured logical canvas size")
	_check(root.content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS and root.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_KEEP, "root window scales canvas items while preserving aspect ratio")
	_check(menu.size == Vector2(1920.0, 1080.0), "main menu retains its full logical layout instead of being cropped to the physical window")
	menu._show_settings()
	_check(_descendants_of_type(menu.content, "OptionButton").size() == 1, "main menu retains window settings after the entry redesign")
	menu._show_help()
	_check(_descendants_of_type(menu.content, "Label").size() >= 2, "main menu operation guide remains available")
	menu.queue_free()
	await process_frame

	var scene: PackedScene = load("res://scenes/battle/prototype_battle.tscn")
	var battle = scene.instantiate()
	root.add_child(battle)
	await process_frame
	_check(battle.has_node("TerrainView") and battle.has_node("TerrainDebugOverlay"), "battle scene includes terrain presentation and domain debug layers")
	await process_frame
	var viewport_size: Vector2 = battle.get_viewport_rect().size
	var map_data: Dictionary = battle.session.state["map"]
	_check(viewport_size == Vector2(1920.0, 1080.0), "logical viewport is 1920x1080")
	_check(float(map_data["width"]) > viewport_size.x * 2.0, "map width exceeds two visible screens")
	_check(float(map_data["height"]) > viewport_size.y * 2.0, "map height exceeds two visible screens")
	var warspite_snapshot: Dictionary = battle.session.snapshot("player", false)["units"]["unit.player.warspite"]
	_check(str(warspite_snapshot.get("display_name", "")) == "厌战号", "battle snapshot exposes the Chinese character name")
	_check(str(warspite_snapshot.get("asset_root", "")).contains("assets/characters/warspite/processed"), "unit snapshot exposes character art root")
	_check((warspite_snapshot.get("collision_half_extents", Vector2.ZERO) as Vector2).is_equal_approx(Vector2(75.0, 31.5)), "unit snapshot exposes the heading-aligned elliptical collision hull")
	var warspite_view = battle.effect_director.unit_views.get("unit.player.warspite", null)
	_check(warspite_view != null, "battle scene creates a runtime character view")
	_check(warspite_view.body_texture != null and warspite_view.rig_texture != null, "runtime character view loads body and rig art")
	_check(is_equal_approx(float(warspite_view.rig_texture.get_width()) * warspite_view.rig_art_scale, 150.0), "rendered rig width matches the collision ellipse longitudinal diameter")
	_check(warspite_view._texture(warspite_view.animation.current_frame_path()) != null, "runtime character view loads animation frames")
	var data_registry = root.get_node("DataRegistry")
	var warspite_main: Dictionary = data_registry.registry.get_definition("weapons", "weapon.warspite_381_ap")
	var warspite_main_visual: Dictionary = data_registry.assets.weapon_visual("warspite", "warspite_main")
	var warspite_secondary: Dictionary = data_registry.registry.get_definition("weapons", "weapon.warspite_152_he")
	var warspite_secondary_visual: Dictionary = data_registry.assets.weapon_visual("warspite", "warspite_secondary")
	_check(battle.effect_director._is_large_caliber_gun(warspite_main, warspite_main_visual), "381mm main guns qualify for miss water columns")
	_check(not battle.effect_director._is_large_caliber_gun(warspite_secondary, warspite_secondary_visual), "152mm secondary guns do not qualify for miss water columns")
	var small_shell_visual: Dictionary = battle.effect_director._caliber_shell_visual(127.0)
	var medium_shell_visual: Dictionary = battle.effect_director._caliber_shell_visual(203.0)
	var large_shell_visual: Dictionary = battle.effect_director._caliber_shell_visual(381.0)
	var superheavy_shell_visual: Dictionary = battle.effect_director._caliber_shell_visual(460.0)
	_check(
		str(small_shell_visual.get("id", "")).ends_with("small")
		and str(medium_shell_visual.get("id", "")).ends_with("medium")
		and str(large_shell_visual.get("id", "")).ends_with("large")
		and str(superheavy_shell_visual.get("id", "")).ends_with("superheavy"),
		"shell presentation selects small, medium, large, and superheavy visuals from authoritative caliber",
	)
	var small_trail: Dictionary = battle.effect_director._shell_trail_profile(127.0, {}, small_shell_visual)
	var large_trail: Dictionary = battle.effect_director._shell_trail_profile(381.0, {}, large_shell_visual)
	var superheavy_trail: Dictionary = battle.effect_director._shell_trail_profile(460.0, {}, superheavy_shell_visual)
	_check(
		float(large_trail.get("length", 0.0)) >= float(small_trail.get("length", 1.0)) * 3.5
		and float(large_trail.get("width", 0.0)) >= float(small_trail.get("width", 1.0)) * 3.0,
		"381mm trails are at least 3.5x longer and 3x wider than 127mm trails",
	)
	_check(
		float(superheavy_trail.get("afterimage_seconds", 0.0)) > float(large_trail.get("afterimage_seconds", 0.0))
		and int(superheavy_trail.get("afterimage_samples", 0)) > int(large_trail.get("afterimage_samples", 0)),
		"superheavy trails retain more and longer afterimages than large-caliber trails",
	)
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
	_check(torpedo_aim.get("weapon_type", "") == "Torpedo" and torpedo_aim.get("fire_arcs", []).size() == 2, "torpedo aim overlay receives merged sectors from all ready centerline mounts")
	_check(is_equal_approx(float(torpedo_aim.get("range", 0.0)), 765.0), "torpedo range circle renders the 1.5x effective range")
	_check(battle.has_method("_draw_directional_aim_overlay") and battle.has_method("_draw_gun_aim_overlay") and battle.has_method("_draw_area_target_overlay") and battle.has_method("_draw_skill_target_overlay"), "battle scene uses direction, gun-sector, area, and skill tactical overlays")
	battle.operation_mode = 0
	battle.selected_unit_id = "unit.player.warspite"
	var warspite_aim: Dictionary = battle.session.get_primary_aim_status("unit.player.warspite", warspite_snapshot["position"] + Vector2(0.0, 400.0))
	_check(warspite_aim.get("fire_arcs", []).size() == 1 and warspite_aim.get("full_salvo_fire_arcs", []).size() == 2, "main-gun overlay receives green available sectors and dark-green all-mount sectors")
	var dispersion_radii: Vector2 = battle._main_gun_dispersion_radii(1080.0, float(warspite_aim.get("spread_degrees", 0.0)))
	_check(is_equal_approx(dispersion_radii.x, 150.0) and is_equal_approx(dispersion_radii.y, 75.0), "main-gun scope shows the Warspite-calibrated lateral and longitudinal one-sigma ellipse")
	_check(battle.has_method("_draw_main_gun_scope") and battle.has_method("_draw_main_gun_dispersion"), "main-gun aiming uses a precise programmatic scope and dispersion overlay")
	battle._update_hud()
	_check(is_equal_approx(float(battle.session.get_operation_status("unit.player.warspite").get("primary_range", 0.0)), 1080.0), "HUD operation status displays the 1.5x main-gun range")
	_check(battle.battle_hud._skill_text().contains("老兵校射"), "battle HUD displays the Chinese skill name")
	var control_status: Dictionary = battle.session.get_operation_status("unit.player.warspite")
	_check(not bool(control_status.get("movement_assist_enabled", true)) and bool(control_status.get("secondary_auto_fire_enabled", false)) and not bool(control_status.get("primary_auto_fire_enabled", true)), "battle HUD receives stationary/secondary-on/primary-off player defaults")
	battle._toggle_route_placement()
	_check(battle.operation_mode == 3 and battle._operation_mode_name() == "PLACING_ROUTE", "Z route placement enters a dedicated operation mode")
	battle._append_route_waypoint(warspite_snapshot["position"] + Vector2(120.0, 30.0))
	battle.session.advance_tick(0.1)
	_check(battle.session.state["units_by_id"]["unit.player.warspite"]["movement_state"]["mode"] == "PlayerWaypointRoute", "route placement UI submits an append-waypoint command")
	var displayed_route: PackedVector2Array = battle._selected_route_points(battle.session.state["units_by_id"]["unit.player.warspite"])
	_check(displayed_route.size() >= 2 and displayed_route[-1].is_equal_approx(warspite_snapshot["position"] + Vector2(120.0, 30.0)), "manual route overlay reads the active corridor instead of retired legacy waypoints")
	battle._toggle_route_placement()
	battle._toggle_control_state("movement_assist_enabled", "自动航行", false)
	battle._toggle_control_state("primary_auto_fire_enabled", "主武器自动开火", false)
	battle.session.advance_tick(0.1)
	_check(bool(battle.session.state["units_by_id"]["unit.player.warspite"]["movement_assist_enabled"]) and bool(battle.session.state["units_by_id"]["unit.player.warspite"]["primary_auto_fire_enabled"]), "X/V UI helpers submit explicit player control states")
	var player_center: Vector2 = battle._player_fleet_center()
	_check(battle.battle_camera.position.distance_to(player_center) < 4.0, "initial camera centers on player fleet")
	_check(battle.camera_mode == "Manual", "initial camera remains in manual mode")
	battle._start_battle("level.prototype_harbor_3v3")
	await process_frame
	var harbor_snapshot: Dictionary = battle.session.snapshot("player", true)
	_check(not harbor_snapshot.get("terrain_map", {}).is_empty(), "harbor scene receives reviewed runtime terrain geometry")
	_check(battle.terrain_view.static_root.get_child_count() >= 9, "harbor scene renders water regions, six visual-only shore layers, and the land runtime asset")
	_check(battle.terrain_view.zone_root.get_child_count() >= 17, "soft-terrain presentation consumes fog detail and squall edge layers plus program boundaries")
	_check(harbor_snapshot.get("facilities", {}).size() == 8 and battle.terrain_view.facility_root.get_child_count() == 8, "harbor facilities share runtime state and presentation placement")
	var world_facility: Dictionary = harbor_snapshot["facilities"]["facility.harbor.observation_west"]
	_check(battle._facility_at(world_facility["position"], harbor_snapshot).get("facility_id", "") == world_facility["facility_id"], "world facility markers can select a known facility")
	var minimap_outer := Rect2(Vector2(28.0, viewport_size.y - 266.0), Vector2(330.0, 226.0))
	var minimap_rect := Rect2(minimap_outer.position + Vector2(14.0, 36.0), minimap_outer.size - Vector2(28.0, 52.0))
	var minimap_point: Vector2 = battle.battle_hud._minimap_position(world_facility["position"], minimap_rect, harbor_snapshot["map"])
	_check(battle._minimap_facility_at(minimap_point, harbor_snapshot).get("facility_id", "") == world_facility["facility_id"], "minimap facility markers can select a known facility")
	battle.selected_unit_id = "unit.player.shimakaze"
	battle.selected_facility_id = world_facility["facility_id"]
	battle._update_hud()
	var facility_status: Dictionary = battle.session.get_facility_action_status(battle.selected_unit_id, battle.selected_facility_id)
	_check(facility_status.has("control_progress_ratio") and facility_status.has("service_progress_ratio") and facility_status.has("berth_speed_ok") and facility_status.has("last_interruption_reason"), "facility HUD receives prerequisites, progress, berth state, and interruption feedback")
	_check(not battle.battle_hud._selected_facility().is_empty(), "facility selection opens the facility operation panel")
	battle.terrain_view.sync_dynamic(harbor_snapshot.get("environment_zones", []), harbor_snapshot.get("facilities", {}), battle.session.snapshot("player", true).get("minefields", {}))
	_check(battle.terrain_view.minefield_root.get_child_count() == 2, "omniscient terrain view renders the fixed minefield and its safe channel")
	_check(battle.battle_hud._texture("res://assets/ui/processed/battle/terrain/minimap_terrain_map_harbor_mouth.png") != null, "harbor minimap loads the generated geometry mask")
	battle._start_battle("level.prototype_broken_atoll_3v3")
	await process_frame
	var atoll_snapshot: Dictionary = battle.session.snapshot("player", true)
	_check(atoll_snapshot.get("terrain_map", {}).get("id", "") == "terrain.map.broken_atoll_16x9", "non-harbor coastal level receives its 16:9 runtime terrain geometry")
	_check(atoll_snapshot.get("facilities", {}).is_empty(), "non-harbor coastal level does not inherit harbor facilities")
	_check(battle.battle_hud._texture("res://assets/ui/processed/battle/terrain/minimap_terrain_map_broken_atoll_16x9.png") != null, "non-harbor coastal minimap loads its generated 16:9 geometry mask")
	_check(battle.battle_hud._environment_zone_icon("environment.effect.rain_squall") == "ui_marker_environment_rain_squall" and battle.battle_hud._texture("res://assets/ui/export/2x/ui_marker_environment_rain_squall.png") != null, "minimap maps local environment rules to the authored environment marker assets")
	_check(harbor_snapshot.get("global_environment", {}).get("canonical_ocean_palette", "") == "cloudy_dawn", "harbor scene and Domain share the same cloudy-dawn palette condition id")
	battle._start_battle("level.prototype_3v3")
	await process_frame
	warspite_view = battle.effect_director.unit_views.get("unit.player.warspite", null)
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
			"impact_positions": [warspite_snapshot["position"] + Vector2(380.0, 72.0), warspite_snapshot["position"] + Vector2(340.0, -58.0)],
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
		"impact_positions": [warspite_snapshot["position"] + Vector2(380.0, 72.0), warspite_snapshot["position"] + Vector2(340.0, -58.0)],
		"shot_count": 2,
	}, battle.session, battle.session.registry.get_definition("weapons", "weapon.warspite_381_ap"), battle.session.state["units_by_id"]["unit.player.warspite"], warspite_snapshot["position"])
	_check(shell_destinations == [warspite_snapshot["position"] + Vector2(380.0, 72.0), warspite_snapshot["position"] + Vector2(340.0, -58.0)], "shell flight visuals use the exact independently sampled combat impact positions")
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


func _test_custom_map_spawns(flow, registry) -> void:
	var coastal_level_ids := [
		"level.prototype_harbor_3v3",
		"level.prototype_broken_atoll_3v3",
		"level.prototype_central_sandbar_3v3",
		"level.prototype_crescent_bay_3v3",
		"level.prototype_double_island_long_channel_3v3",
		"level.prototype_dual_channel_reef_line_3v3",
		"level.prototype_long_archipelago_3v3",
		"level.prototype_offset_large_island_3v3",
		"level.prototype_ring_lagoon_3v3",
		"level.prototype_scattered_islands_3v3",
	]
	var original_unlocks: Array[String] = flow.unlocked_ship_ids.duplicate()
	flow.unlocked_ship_ids.assign(registry.all("ships").map(func(ship): return str(ship.get("id", ""))))
	for base_level_id in ["level.prototype_1v1", "level.prototype_3v3", "level.prototype_5v5", "level.prototype_11v11"]:
		var base_level: Dictionary = registry.get_definition("levels", base_level_id)
		var selected_ship_ids: Array[String] = []
		for member in base_level.get("player_fleet", []): selected_ship_ids.append(str(member.get("ship_id", "")))
		for map_level_id in coastal_level_ids:
			var configured: Dictionary = flow.configure_custom_battle(base_level_id, map_level_id, "clear_day", selected_ship_ids)
			var custom_level: Dictionary = flow.runtime_level_definition("level.custom_runtime")
			var terrain: Dictionary = registry.get_definition("terrain", str(custom_level.get("map", {}).get("terrain_definition_id", "")))
			var slots_match := bool(configured.get("ok", false))
			for faction_id in ["player", "enemy"]:
				var fleet_name := "%s_fleet" % faction_id
				var expected: Array = terrain.get("spawn_points", []).filter(func(spawn): return str(spawn.get("faction_id", "")) == faction_id)
				expected.sort_custom(func(a, b): return int(str(a.get("id", "")).trim_prefix("%s_" % faction_id)) < int(str(b.get("id", "")).trim_prefix("%s_" % faction_id)))
				var actual: Array = custom_level.get(fleet_name, [])
				slots_match = slots_match and actual.size() == base_level.get(fleet_name, []).size()
				for index in range(actual.size()):
					slots_match = slots_match and actual[index].get("position", []) == expected[index].get("position", []) and is_equal_approx(float(actual[index].get("heading", 0.0)), float(expected[index].get("heading", 0.0)))
			_check(slots_match, "%s on %s maps both fleets onto its reviewed spawn slots" % [base_level_id, map_level_id])
			var session = BattleSession.new(registry)
			var created: Dictionary = session.create_battle_from_definition(custom_level, 902)
			var all_spawns_clear := bool(created.get("ok", false))
			var units: Array = session.state.get("units_by_id", {}).values()
			for unit in units:
				all_spawns_clear = all_spawns_clear and session.terrain_query.can_occupy_circle(unit.get("position", Vector2.ZERO), float(unit.get("stats", {}).get("collision_radius", 20.0)), session._movement_tags(unit))
			for first_index in range(units.size()):
				for second_index in range(first_index + 1, units.size()):
					if units[first_index].get("faction_id", "") != units[second_index].get("faction_id", ""): continue
					var required_distance := float(units[first_index].get("stats", {}).get("collision_radius", 20.0)) + float(units[second_index].get("stats", {}).get("collision_radius", 20.0))
					all_spawns_clear = all_spawns_clear and (units[first_index].get("position", Vector2.ZERO) as Vector2).distance_to(units[second_index].get("position", Vector2.ZERO)) > required_distance
			_check(all_spawns_clear, "%s on %s starts every unit in separated navigable water" % [base_level_id, map_level_id])
	flow.unlocked_ship_ids.assign(original_unlocks)


func _test_custom_open_sea_spawns(flow, registry) -> void:
	for level_id in ["level.prototype_1v1", "level.prototype_3v3", "level.prototype_5v5", "level.prototype_11v11"]:
		var base_level: Dictionary = registry.get_definition("levels", level_id)
		var selected_ship_ids: Array[String] = []
		for _index in range(base_level.get("player_fleet", []).size()):
			selected_ship_ids.append("ship.ward")
		var configured: Dictionary = flow.configure_custom_battle(level_id, level_id, "clear_day", selected_ship_ids)
		var custom_level: Dictionary = flow.runtime_level_definition("level.custom_runtime")
		var slots_match := bool(configured.get("ok", false))
		for fleet_name in ["player_fleet", "enemy_fleet"]:
			var expected: Array = base_level.get(fleet_name, [])
			var actual: Array = custom_level.get(fleet_name, [])
			slots_match = slots_match and actual.size() == expected.size()
			for index in range(mini(actual.size(), expected.size())):
				slots_match = slots_match and actual[index].get("position", []) == expected[index].get("position", []) and is_equal_approx(float(actual[index].get("heading", 0.0)), float(expected[index].get("heading", 0.0)))
		_check(slots_match, "%s custom open-sea battle preserves both reviewed formations" % level_id)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)


func _descendants_of_type(node: Node, class_name_value: String) -> Array[Node]:
	var result: Array[Node] = []
	for child in node.get_children():
		if child.is_class(class_name_value):
			result.append(child)
		result.append_array(_descendants_of_type(child, class_name_value))
	return result
