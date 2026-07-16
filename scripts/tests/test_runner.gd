extends SceneTree

const ConfigRegistry = preload("res://scripts/infrastructure/data/config_registry.gd")
const AssetCatalog = preload("res://scripts/infrastructure/assets/asset_catalog.gd")
const BattleSession = preload("res://scripts/application/battle_session.gd")
const ModifierService = preload("res://scripts/domain/services/modifier_service.gd")
const DamageService = preload("res://scripts/domain/services/damage_service.gd")
const SeededRandomSource = preload("res://scripts/infrastructure/random/seeded_random_source.gd")
const UiText = preload("res://scripts/presentation/ui_text.gd")
const TerrainQueryService = preload("res://scripts/domain/services/terrain_query_service.gd")
const TerrainContextService = preload("res://scripts/domain/services/terrain_context_service.gd")
const RoutePlanner = preload("res://scripts/application/navigation/route_planner.gd")
const CollisionGeometryService = preload("res://scripts/domain/services/collision_geometry_service.gd")
const GunDispersionService = preload("res://scripts/domain/services/gun_dispersion_service.gd")
const MinefieldService = preload("res://scripts/domain/services/minefield_service.gd")

var failures: Array[String] = []
var checks := 0
var registry
var assets


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	registry = ConfigRegistry.new()
	_check(registry.load_all(), "configuration registry loads: %s" % str(registry.errors))
	_check(registry.all("ships").size() == 48, "all 48 phase-one and phase-two character ship definitions load")
	_check(registry.all("levels").size() == 19, "four open-sea, ten coastal, and five formal levels load")
	_check(registry.all("objectives").size() == 5, "T-01 through T-04 and S-01 objective definitions load")
	_test_terrain_configuration_and_rules()
	_test_coastal_runtime_levels()
	_test_scene_combat_tactical_effects()
	_test_runtime_baseline_scales()
	_test_gun_dispersion_rules()
	_test_elliptical_collision_geometry()
	_test_hit_rate_floor()
	var presentation_settings: Dictionary = registry.get_definition("settings", "settings.presentation")
	_check(presentation_settings.get("window", {}).get("logical_size", []) == [1920.0, 1080.0], "presentation settings expose the fixed logical canvas size")
	_check(presentation_settings.get("window", {}).get("size_options", []).size() == 5, "presentation settings expose five window sizes")
	_check(presentation_settings.get("camera", {}).get("min_visible_size", []) == [500.0, 500.0], "camera minimum visible size loads from configuration")
	_check(is_equal_approx(float(presentation_settings.get("camera", {}).get("max_map_visible_fraction", 0.0)), 0.6666667), "camera maximum map fraction loads from configuration")
	_test_chinese_display_text()
	assets = AssetCatalog.new()
	_check(assets.load_all(), "asset catalog loads: %s" % str(assets.errors))
	_test_asset_catalog()
	_test_full_roster_runtime_data()
	_test_modifier_order()
	_test_command_and_skill_rules()
	_test_runtime_ai_control_rules()
	_test_operation_design_rules()
	_test_automatic_lead_and_fixed_impacts()
	_test_torpedo_fire_arc_rules()
	_test_detection_and_contact_ghost()
	_test_torpedo_observation_rules()
	_test_damage_zero_floor()
	_test_simultaneous_flagship_victory()
	_test_sinking_action_boundary()
	_test_determinism()
	if "skip_smoke" not in OS.get_cmdline_user_args():
		_test_battle_smoke("level.prototype_1v1", 3200)
		_test_battle_smoke("level.prototype_3v3", 4200)
		_test_battle_smoke("level.prototype_5v5", 5200)
		_test_battle_smoke("level.prototype_11v11", 7200)
		_test_battle_smoke("level.prototype_harbor_3v3", 4400)
	if failures.is_empty():
		print("PASS: %d checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error("FAIL: %s" % failure)
		print("FAILED: %d of %d checks" % [failures.size(), checks])
		quit(1)


func _test_chinese_display_text() -> void:
	for category in ["ships", "weapons", "skills", "levels"]:
		for definition in registry.all(category):
			var display_name := str(definition.get("display_name", ""))
			var language_neutral_name := str(definition.get("id", "")) == "ship.u_47"
			_check(_contains_chinese(display_name) or language_neutral_name, "%s display name is localized: %s" % [category, definition.get("id", "?")])
	_check(UiText.mode_name("level.prototype_11v11") == "11v11 大规模会战", "battle mode has a Chinese display label")
	_check(UiText.ship_class_name("Battleship") == "战列舰", "ship class has a Chinese display label")
	_check(UiText.reason_name("WEAPON_RELOADING") == "武器装填中", "operation reason has a Chinese display label")
	_check(UiText.reason_name("TORPEDO_MOUNT_INTERVAL") == "鱼雷管组切换中", "torpedo mount interval has a Chinese operation reason")
	_check(UiText.character_name("warspite") == "厌战号", "character id has a Chinese display label")


func _test_terrain_configuration_and_rules() -> void:
	_check(registry.all("terrain").size() == 20, "ten island terrain templates and ten runtime maps load")
	_check(registry.all("navigation").size() == 10, "all ten coastal navigation graphs load")
	_check(registry.all("environment_zones").size() == 20, "seven local effects, two authored zone sets, and eleven ocean condition definitions load")
	_check(registry.all("facilities").size() == 13, "facility, support mission, minefield, and harbor layout definitions load")
	var harbor_level: Dictionary = registry.get_definition("levels", "level.prototype_harbor_3v3")
	var harbor_costs := {"player":0, "enemy":0}
	for member in harbor_level.get("player_fleet", []): harbor_costs["player"] += int(registry.get_definition("ships", str(member.get("ship_id", ""))).get("cost", 0))
	for member in harbor_level.get("enemy_fleet", []): harbor_costs["enemy"] += int(registry.get_definition("ships", str(member.get("ship_id", ""))).get("cost", 0))
	_check(bool(harbor_level.get("require_equal_fleet_cost", false)) and harbor_costs["player"] == 12 and harbor_costs["enemy"] == 12, "harbor balance verification requires equal 12 Cost fleets")
	var invalid_cost_registry = ConfigRegistry.new()
	invalid_cost_registry.load_all()
	invalid_cost_registry.errors.clear()
	var invalid_harbor := harbor_level.duplicate(true)
	invalid_harbor["enemy_fleet"].pop_back()
	invalid_cost_registry._validate_level(invalid_harbor)
	_check(not invalid_cost_registry.errors.filter(func(error): return str(error).contains("Equal-cost level")).is_empty(), "equal-cost level validation rejects mismatched fleets")
	var invalid_weapon_state_registry = ConfigRegistry.new()
	invalid_weapon_state_registry.load_all()
	invalid_weapon_state_registry.errors.clear()
	var invalid_weapon_state_level: Dictionary = registry.get_definition("levels", "level.prototype_1v1").duplicate(true)
	invalid_weapon_state_level["player_fleet"][0]["weapon_group_states"] = {"unknown_group":"Enabled", "warspite_main":"Broken"}
	invalid_weapon_state_registry._validate_level(invalid_weapon_state_level)
	_check(not invalid_weapon_state_registry.errors.filter(func(error): return str(error).contains("Unknown weapon group")).is_empty(), "level validation rejects weapon groups not mounted by the configured ship")
	_check(not invalid_weapon_state_registry.errors.filter(func(error): return str(error).contains("Invalid weapon group state")).is_empty(), "level validation rejects unsupported initial weapon group states")
	var terrain_definition: Dictionary = registry.get_definition("terrain", "terrain.map.harbor_mouth")
	var query = TerrainQueryService.new()
	query.configure(terrain_definition)
	_check(terrain_definition.get("visual_regions", []).size() == 6 and query.obstacles.size() == 2, "harbor sediment, breaker, and wet-rock regions remain visual-only outside Domain obstacles")
	_check(not query.debug_spatial_cells().is_empty(), "terrain query builds the same spatial index exposed by F9 debug")
	var fast_sweep: Dictionary = query.first_segment_hit(Vector2(0.0, 1160.0), Vector2(4096.0, 1160.0), "TorpedoTravel", 8.0)
	_check(bool(fast_sweep.get("hit", false)) and float(fast_sweep.get("fraction", 1.0)) < 1.0, "continuous torpedo sweep cannot tunnel through harbor land")
	var shell_hit: Dictionary = query.first_segment_hit(Vector2(700.0, 1100.0), Vector2(2050.0, 1100.0), "ShellTravel")
	_check(bool(shell_hit.get("hit", false)), "shell path reports the first blocking shore")
	_check(not query.has_surface_line_of_sight(Vector2(700.0, 1100.0), Vector2(2050.0, 1100.0)), "surface optical line of sight is blocked by the same shore geometry")
	var first_obstacle: Dictionary = terrain_definition.get("obstacles", [])[0]
	var first_polygon: Array = first_obstacle.get("polygon", [])
	var land_center := Vector2.ZERO
	for point in first_polygon:
		land_center += Vector2(float(point[0]), float(point[1]))
	land_center /= float(first_polygon.size())
	_check(not query.can_occupy_circle(land_center, 20.0, ["Surface", "ShallowDraft"]), "ship occupancy rejects reviewed hard land")
	_check(query.can_occupy_circle(Vector2(2048.0, 1160.0), 20.0, ["Surface", "ShallowDraft"]), "reviewed harbor navigation channel remains passable")
	_check(not query.can_occupy_circle(Vector2(1850.0, 900.0), 20.0, ["Surface"]) and query.can_occupy_circle(Vector2(1850.0, 900.0), 20.0, ["Surface", "ShallowDraft"]), "shallow-water access honors unit draft tags")
	var shallow_crossing_query = TerrainQueryService.new()
	shallow_crossing_query.configure({"id":"terrain.test.shallow_crossing", "map_size":[100,100], "obstacles":[], "regions":[{"id":"region.shallow_strip", "region_type":"ShallowWater", "priority":50, "polygon":[[40,0],[40,100],[60,100],[60,0]]}]})
	_check(not shallow_crossing_query.is_movement_segment_clear(Vector2(10,50), Vector2(90,50), 2.0, ["Surface"]), "deep-draft movement cannot cross shallow water between legal endpoints")
	var shallow_motion: Dictionary = shallow_crossing_query.resolve_circle_motion(Vector2(10,50), Vector2(80,0), 2.0, ["Surface"])
	_check(bool(shallow_motion.get("collided", false)) and (shallow_motion["position"] as Vector2).x < 40.0, "authoritative movement stops at the first illegal water-depth boundary")
	var shallow_route: Dictionary = RoutePlanner.new().plan_path(shallow_crossing_query, {}, Vector2(10,50), Vector2(90,50), 2.0, ["Surface"])
	_check(not bool(shallow_route.get("ok", true)) and shallow_route.get("reason_code") == "NO_NAVIGATION_PATH", "route planning cannot smooth through an illegal shallow strip")
	var path_context = TerrainContextService.new()
	path_context.configure(query, {"zones": [{"id":"zone.path_test", "polygon":[[0,0],[0,20],[20,20],[20,0]], "position":[0,0], "drift_speed":10.0, "drift_path":[[0,0],[10,0],[10,10]], "duration":0.0}]}, [])
	path_context.advance(1.5)
	_check((path_context.snapshot()[0]["position"] as Vector2).is_equal_approx(Vector2(10.0, 5.0)), "soft-terrain drift follows authored polyline corners at fixed speed")
	path_context.advance(1.0)
	_check((path_context.snapshot()[0]["position"] as Vector2).is_equal_approx(Vector2(10.0, 10.0)), "soft-terrain drift clamps at the authored path endpoint")
	var overlap_context = TerrainContextService.new()
	var overlap_polygon := [[0,0],[0,100],[100,100],[100,0]]
	overlap_context.configure(query, {"global_environment":{"base_sea_state":4}, "zones":[
		{"id":"zone.overlap.low", "effect_id":"effect.overlap", "polygon":overlap_polygon, "position":[0,0], "intensity":0.5},
		{"id":"zone.overlap.high", "effect_id":"effect.overlap", "polygon":overlap_polygon, "position":[0,0], "intensity":1.0},
	]}, [{"id":"effect.overlap", "definition_type":"EnvironmentEffect", "priority":80, "stack_rule":"Override", "context":{"sea_state_delta":-2}}])
	var overlap_result: Dictionary = overlap_context.context_at(Vector2(50.0, 50.0))
	_check(int(overlap_result["sea_state"]) == 2 and overlap_result["effect_sources"].size() == 1, "overlapping non-vector zones apply only the highest-intensity source once")
	var light_context = TerrainContextService.new()
	light_context.configure(query, {"zones":[
		{"id":"zone.light", "effect_id":"effect.light", "polygon":overlap_polygon, "position":[0,0], "intensity":1.0},
		{"id":"zone.tide", "effect_id":"effect.tide", "polygon":overlap_polygon, "position":[0,0], "intensity":1.0},
	]}, [
		{"id":"effect.light", "definition_type":"EnvironmentEffect", "priority":55, "stack_rule":"Highest", "context":{"optical_visibility_multiplier":1.18}},
		{"id":"effect.tide", "definition_type":"EnvironmentEffect", "priority":65, "stack_rule":"Override", "context":{"tide_controls_access":true}},
	])
	var light_result: Dictionary = light_context.context_at(Vector2(50.0, 50.0))
	_check(is_equal_approx(float(light_result["optical_visibility_multiplier"]), 1.18) and bool(light_result["tide_controls_access"]), "moonlit visibility gain and tidal access fact survive TerrainContext composition")
	var planner = RoutePlanner.new()
	var route: Dictionary = planner.plan_path(query, registry.get_definition("navigation", "navigation.harbor_mouth"), Vector2(2048.0, 1870.0), Vector2(2048.0, 250.0), 20.0, ["Surface", "ShallowDraft"])
	_check(bool(route.get("ok", false)) and not route.get("waypoints", []).is_empty(), "player and AI shared route graph finds a harbor path")
	var open_session = BattleSession.new(registry)
	open_session.create_battle("level.prototype_1v1", 31)
	_check(open_session.state.get("terrain_map", {}).is_empty(), "open-sea levels retain the no-terrain regression path")
	var harbor_session = BattleSession.new(registry)
	var creation: Dictionary = harbor_session.create_battle("level.prototype_harbor_3v3", 31)
	_check(bool(creation.get("ok", false)) and harbor_session.state.get("facilities_by_id", {}).size() == 8, "harbor battle creates all eight shore facility states")
	_check(harbor_session.state.get("environment_zones", []).size() == 7, "harbor battle creates all seven soft-terrain zone types")
	_check(harbor_session.state.get("minefields_by_id", {}).size() == 1, "harbor battle loads the fixed minefield and faction visibility contract")
	_check(harbor_session.snapshot("player", false).get("minefields", {}).is_empty(), "enemy minefield remains hidden from a faction without discovery knowledge")
	_check(harbor_session.snapshot("enemy", false).get("minefields", {}).size() == 1 and harbor_session.snapshot("player", true).get("minefields", {}).size() == 1, "minefield visibility reveals owner knowledge and omniscient debug state")
	var support_request: Dictionary = harbor_session.facility_service.request_support("facility.harbor.airfield_east", "support_mission.air_recon", "enemy", Vector2(2048.0, 900.0), 0.0)
	_check(bool(support_request.get("accepted", false)), "active airfield with live dependencies accepts an authored support mission")
	var airfield_snapshot: Dictionary = harbor_session.facility_service.snapshot()["facility.harbor.airfield_east"]
	_check(airfield_snapshot.get("service_queue", []).size() == 1 and int(airfield_snapshot.get("mission_charges_remaining", {}).get("support_mission.air_recon", -1)) == 2, "facility debug snapshot exposes the active service queue and remaining mission charges")
	var interaction_polygon: Array = terrain_definition.get("facility_anchors", [])[0].get("interaction_water_polygon", [])
	var interaction_center := Vector2.ZERO
	for point in interaction_polygon: interaction_center += Vector2(float(point[0]), float(point[1]))
	interaction_center /= float(interaction_polygon.size())
	_check(not harbor_session.facility_service.sources_at(interaction_center).is_empty(), "TerrainContext inspector can attribute facility interaction-water sources")
	var direct_route: Dictionary = harbor_session.queue_command({"command_id":"terrain.move.1","command_type":"MoveUnits","issued_at_tick":0,"issuer_id":"player","unit_id":"unit.player.shimakaze","target_position":Vector2(2048.0, 300.0)})
	_check(bool(direct_route.get("accepted", false)), "terrain move command enters the shared command pipeline")
	var move_events: Array = harbor_session.advance_tick(0.1)
	_check(_has_event(move_events, "MoveOrderAccepted"), "terrain move command receives an authored route")
	harbor_session._event_buffer = []
	harbor_session.state["projectiles_by_id"]["projectile.fast_test"] = {"entity_id":"projectile.fast_test","definition_id":"projectile.torpedo","attack_id":"attack.fast_test","source_unit_id":"unit.player.shimakaze","source_weapon_id":"weapon.shimakaze_torpedo","faction_id":"player","position":Vector2(700.0,1160.0),"heading":0.0,"speed":1900.0,"collision_radius":8.0,"remaining_range":2200.0,"travelled_distance":0.0,"target_types":["Surface"]}
	harbor_session._update_projectiles(1.0)
	_check(not harbor_session.state["projectiles_by_id"].has("projectile.fast_test") and _has_event(harbor_session._event_buffer, "ProjectileBlockedByTerrain"), "high-speed runtime torpedo resolves terrain before targets behind shore")
	var first_replay := _terrain_replay_signature(907)
	var second_replay := _terrain_replay_signature(907)
	_check(first_replay == second_replay, "fixed seed reproduces harbor environment, facility, route, and terrain events")


func _test_coastal_runtime_levels() -> void:
	var coastal_ids := [
		"harbor_mouth", "broken_atoll", "central_sandbar", "crescent_bay",
		"double_island_long_channel", "dual_channel_reef_line", "long_archipelago",
		"offset_large_island", "ring_lagoon", "scattered_islands",
	]
	for coastal_id in coastal_ids:
		var level_id := "level.prototype_harbor_3v3" if coastal_id == "harbor_mouth" else "level.prototype_%s_3v3" % coastal_id
		var session = BattleSession.new(registry)
		var creation: Dictionary = session.create_battle(level_id, 20260710)
		_check(creation.get("ok", false), "%s creates a battle session" % level_id)
		_check(session.state.get("terrain_map", {}).get("id", "") == "terrain.map.%s" % coastal_id, "%s loads its authored terrain map" % level_id)
		_check(not session.navigation_definition.is_empty(), "%s loads its shared navigation graph" % level_id)
		var level: Dictionary = registry.get_definition("levels", level_id)
		var terrain_spawns: Array = session.state.get("terrain_map", {}).get("spawn_points", [])
		for faction_id in ["player", "enemy"]:
			var fleet: Array = level.get("%s_fleet" % faction_id, [])
			var authored: Array = terrain_spawns.filter(func(spawn): return spawn.get("faction_id", "") == faction_id)
			authored.sort_custom(func(a, b): return int(str(a.get("id", "")).trim_prefix("%s_" % faction_id)) < int(str(b.get("id", "")).trim_prefix("%s_" % faction_id)))
			var all_match := authored.size() == 11
			for member in fleet:
				var member_index := fleet.find(member)
				all_match = all_match and member_index < authored.size() and _as_vector2(authored[member_index].get("position", Vector2.ZERO)).distance_to(_as_vector2(member.get("position", Vector2.ZERO))) < 0.1
			_check(all_match, "%s %s fleet uses the reviewed terrain spawn points" % [level_id, faction_id])


func _as_vector2(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


func _terrain_replay_signature(seed_value: int) -> Dictionary:
	var session = BattleSession.new(registry)
	session.create_battle("level.prototype_harbor_3v3", seed_value)
	var event_types: Array[String] = []
	for event in session.drain_events():
		event_types.append(str(event.get("event_type", "")))
	for index in range(400):
		for event in session.advance_tick(0.1):
			event_types.append(str(event.get("event_type", "")))
	var snapshot: Dictionary = session.snapshot("player", true)
	return {"events": event_types, "environment_zones": snapshot.get("environment_zones", []), "facilities": snapshot.get("facilities", {}), "units": snapshot.get("units", {})}


func _test_scene_combat_tactical_effects() -> void:
	var terrain_definition: Dictionary = registry.get_definition("terrain", "terrain.map.harbor_mouth")
	var query = TerrainQueryService.new()
	query.configure(terrain_definition)
	for weather in ["clear", "cloudy", "overcast", "rain", "thunderstorm"]:
		for time_of_day in ["day", "dawn", "dusk", "night"]:
			var palette_id := "%s_%s" % [weather, time_of_day]
			var palette_context = TerrainContextService.new()
			palette_context.configure(query, {}, registry.all("environment_zones"), palette_id)
			var palette_global := palette_context.global_snapshot()
			_check(palette_global.get("canonical_ocean_palette", "") == palette_id and palette_global.get("weather", "") == weather and palette_global.get("time_of_day", "") == time_of_day, "ocean palette drives the matching global battle condition: %s" % palette_id)
	var storm_context = TerrainContextService.new()
	storm_context.configure(query, {}, registry.all("environment_zones"), "thunderstorm_night")
	var storm := storm_context.context_at(Vector2(50, 50))
	_check(int(storm["sea_state"]) == 5 and is_equal_approx(float(storm["optical_visibility_multiplier"]), 0.45) and is_equal_approx(float(storm["movement_speed_multiplier"]), 0.80), "thunderstorm night combines weather sea state, visibility floor, and movement penalty")
	_check(is_equal_approx(float(storm["weapon_accuracy_modifier"]), -0.29) and storm["aviation_condition"] == "Severe" and is_equal_approx(float(storm["aviation_delay_multiplier"]), 2.944), "thunderstorm night combines weather, time, and final sea-state weapon and aviation modifiers")
	_check(is_equal_approx(float(storm["wind_speed"]), 15.0) and is_equal_approx(float(storm["torpedo_sigma_multiplier"]), 3.0), "thunderstorm wind and sea state cap torpedo angular sigma at three times the calm baseline")
	var clear_context = TerrainContextService.new()
	clear_context.configure(query, {}, registry.all("environment_zones"), "clear_day")
	var clear := clear_context.context_at(Vector2(50, 50))
	_check(is_equal_approx(float(clear["wind_speed"]), 2.0) and is_equal_approx(float(clear["torpedo_sigma_multiplier"]), 1.0), "clear low-wind water preserves the base torpedo angular sigma")
	var dawn_context = TerrainContextService.new()
	dawn_context.configure(query, {}, registry.all("environment_zones"), "clear_dawn")
	_check(is_equal_approx(float(dawn_context.context_at(Vector2(50, 50))["optical_visibility_multiplier"]), 1.03), "bright dawn condition provides the authored slight optical visibility benefit")
	var legacy_weather_session = BattleSession.new(registry)
	legacy_weather_session.create_battle("level.prototype_11v11", 1199)
	_check(legacy_weather_session.state["global_environment"].get("canonical_ocean_palette", "") == "cloudy_dusk", "legacy dusk palette resolves to the same cloudy-dusk art and battle condition")
	var area := [[0,0],[0,100],[100,100],[100,0]]
	var rough_context = TerrainContextService.new()
	rough_context.configure(query, {"global_environment":{"base_sea_state":2,"sea_state_rules":[{"minimum_sea_state":4,"movement_speed_multiplier":0.88,"weapon_accuracy_modifier":-0.10,"aviation_delay_multiplier":1.30,"aviation_condition":"Restricted"}]},"zones":[{"id":"zone.rough","effect_id":"effect.rough","polygon":area,"position":[0,0],"intensity":1.0}]}, [{"id":"effect.rough","definition_type":"EnvironmentEffect","priority":50,"stack_rule":"Highest","context":{"sea_state":4}}])
	var rough := rough_context.context_at(Vector2(50,50))
	_check(int(rough["sea_state"]) == 4 and is_equal_approx(float(rough["movement_speed_multiplier"]), 0.88) and is_equal_approx(float(rough["weapon_accuracy_modifier"]), -0.10) and rough["aviation_condition"] == "Restricted", "high sea state changes movement, weapon accuracy, and aviation conditions through TerrainContext")
	var lee_context = TerrainContextService.new()
	lee_context.configure(query, {"global_environment":{"base_sea_state":2,"sea_state_rules":[{"minimum_sea_state":4,"movement_speed_multiplier":0.88,"weapon_accuracy_modifier":-0.10,"aviation_delay_multiplier":1.30}]},"zones":[{"id":"zone.rough","effect_id":"effect.rough","polygon":area,"position":[0,0],"intensity":1.0},{"id":"zone.lee","effect_id":"effect.lee","polygon":area,"position":[0,0],"intensity":1.0}]}, [{"id":"effect.rough","definition_type":"EnvironmentEffect","priority":50,"stack_rule":"Highest","context":{"sea_state":4}},{"id":"effect.lee","definition_type":"EnvironmentEffect","priority":80,"stack_rule":"Override","context":{"sea_state_delta":-2}}])
	var sheltered := lee_context.context_at(Vector2(50,50))
	_check(int(sheltered["sea_state"]) == 2 and is_equal_approx(float(sheltered["movement_speed_multiplier"]), 1.0), "lee water removes the high-sea movement penalty after final context composition")
	var tide_context = TerrainContextService.new()
	tide_context.configure(query, {"global_environment":{"tide":{"initial_phase":"Flood","phases":["Flood","High","Ebb","Low"],"phase_duration":45.0,"open_phases":["Flood","High"]}},"zones":[{"id":"zone.tide","effect_id":"effect.tide","polygon":area,"position":[0,0],"intensity":1.0}]}, [{"id":"effect.tide","definition_type":"EnvironmentEffect","priority":60,"stack_rule":"Override","context":{"tide_controls_access":true}}])
	_check(tide_context.movement_segment_access(Vector2(-20,50), Vector2(50,50))["allowed"], "flood tide opens the authored tidal passage")
	var tide_events := tide_context.advance(90.0)
	var denied_tide := tide_context.movement_segment_access(Vector2(-20,50), Vector2(50,50))
	var evacuation_tide := tide_context.movement_segment_access(Vector2(50,50), Vector2(-20,50))
	_check(not denied_tide["allowed"] and denied_tide["reason_code"] == "TIDE_ACCESS_RESTRICTED" and evacuation_tide["allowed"] and _has_event(tide_events, "EnvironmentForecastChanged"), "ebb tide blocks new entry while allowing units already inside to evacuate")

	var observation_session = BattleSession.new(registry)
	observation_session.create_battle("level.prototype_harbor_3v3", 1201)
	var observation_id := "facility.harbor.observation_west"
	var observation: Dictionary = observation_session.facility_service.facilities_by_id[observation_id]
	observation["faction_id"] = "enemy"
	observation["operation_state"] = "Active"
	observation["previous_operation_state"] = "Active"
	for unit_id in observation_session._sorted_unit_ids():
		if observation_session.state["units_by_id"][unit_id]["faction_id"] == "enemy": observation_session.state["units_by_id"][unit_id]["life_state"] = "Sunk"
	var observed: Dictionary = observation_session.state["units_by_id"]["unit.player.shimakaze"]
	var observer_position: Vector2 = observation_session.facility_service.observation_sources("enemy")[0]["position"]
	observed["position"] = _find_clear_observation_point(observation_session, observer_position, 260.0)
	_check(observation_session._fleet_detects("enemy", observed), "active coastal observation post contributes a real faction detection source")
	observation_session.facility_service.suppress(observation_id, 10.0, "test")
	_check(not observation_session._fleet_detects("enemy", observed), "suppressed observation post is removed from faction detection")

	var battery_session = BattleSession.new(registry)
	battery_session.create_battle("level.prototype_harbor_3v3", 1202)
	var battery: Dictionary = battery_session.facility_service.facilities_by_id["facility.harbor.battery_west"]
	var battery_target: Dictionary = battery_session.state["units_by_id"]["unit.player.shimakaze"]
	battery_target["position"] = Vector2(2200.0, 995.0)
	battery_session.state["visible_by_faction"]["enemy"] = {battery_target["entity_id"]:true}
	battery_session._event_buffer = []
	battery_session._update_facility_weapons()
	_check(_has_event(battery_session._event_buffer, "FacilityWeaponFired") and not battery_session.delayed_attacks.is_empty() and battery_session.delayed_attacks[0].get("source_facility_id", "") == battery["facility_id"], "active coastal battery fires through the normal delayed attack pipeline")
	battery_session.facility_service.suppress(battery["facility_id"], 12.0, "test")
	battery_session.delayed_attacks.clear()
	battery_session._event_buffer = []
	battery_session._update_facility_weapons()
	_check(battery_session.delayed_attacks.is_empty(), "suppressed coastal battery cannot fire")

	var service_session = BattleSession.new(registry)
	service_session.create_battle("level.prototype_harbor_3v3", 1203)
	var service_unit: Dictionary = service_session.state["units_by_id"]["unit.player.shimakaze"]
	var supply_id := "facility.harbor.supply_west"
	var supply: Dictionary = service_session.facility_service.facilities_by_id[supply_id]
	supply["faction_id"] = "player"; supply["operation_state"] = "Active"; supply["previous_operation_state"] = "Active"
	service_unit["position"] = service_session.facility_service.interaction_center(supply_id)
	service_unit["current_speed"] = 0.0
	service_unit["weapon_states"][0]["reload_remaining"] = 10.0
	service_unit["skill_state"]["cooldown_remaining"] = 20.0
	_check(service_session.facility_service.request_service(supply_id, service_unit)["accepted"], "active friendly supply point accepts an independent berthing service transaction")
	var repair_id := "facility.harbor.repair_berth_east"
	var repair: Dictionary = service_session.facility_service.facilities_by_id[repair_id]
	repair["faction_id"] = "player"; repair["operation_state"] = "Active"; repair["previous_operation_state"] = "Active"
	service_unit["position"] = service_session.facility_service.interaction_center(repair_id)
	service_unit["current_speed"] = 0.0
	service_unit["heading"] = deg_to_rad(float(repair.get("heading", 0.0)))
	service_unit["current_hp"] = service_unit["max_hp"] * 0.30
	_check(service_session.facility_service.request_service(repair_id, service_unit)["accepted"], "repair berth accepts its own service transaction")

	var lifecycle_session = BattleSession.new(registry)
	lifecycle_session.create_battle("level.prototype_harbor_3v3", 1204)
	var lifecycle_id := "facility.harbor.battery_west"
	var lifecycle_battery: Dictionary = lifecycle_session.facility_service.facilities_by_id[lifecycle_id]
	lifecycle_battery["weapon_states"][0]["reload_remaining"] = 8.0
	var lifecycle_events: Array = lifecycle_session.facility_service.apply_damage(lifecycle_id, 130.0, "test")
	_check(_has_event(lifecycle_events, "FacilitySuppressed") and lifecycle_session.facility_service.facilities_by_id[lifecycle_id]["operation_state"] == "Suppressed", "facility damage crosses the authored suppression threshold")
	lifecycle_session.facility_service.advance(1.0, 1.0, lifecycle_session.state["units_by_id"])
	_check(is_equal_approx(float(lifecycle_battery["weapon_states"][0]["reload_remaining"]), 8.0), "suppressed coastal battery pauses reload when the facility definition forbids it")
	var recovery_events: Array = lifecycle_session.facility_service.advance(12.1, 12.1, lifecycle_session.state["units_by_id"])
	_check(_has_event(recovery_events, "FacilityRecovered") and lifecycle_session.facility_service.facilities_by_id[lifecycle_id]["operation_state"] == "Active", "facility suppression expires into its previous operation state")
	var interrupted_session = BattleSession.new(registry)
	interrupted_session.create_battle("level.prototype_harbor_3v3", 1216)
	var interrupted_unit: Dictionary = interrupted_session.state["units_by_id"]["unit.player.shimakaze"]
	var interrupted_id := "facility.harbor.observation_west"
	interrupted_unit["position"] = interrupted_session.facility_service.interaction_center(interrupted_id)
	_check(interrupted_session.facility_service.declare_control(interrupted_id, interrupted_unit)["accepted"], "dormant facility begins control from its authored interaction water")
	var interrupted_events: Array = interrupted_session.facility_service.apply_damage(interrupted_id, 1.0, "test")
	var interrupted_facility: Dictionary = interrupted_session.facility_service.facilities_by_id[interrupted_id]
	_check(_has_event(interrupted_events, "FacilityActionInterrupted") and interrupted_facility["control_state"].is_empty() and interrupted_facility["operation_state"] == "Dormant", "incoming damage interrupts control and preserves the prior operation state")
	var formula_session = BattleSession.new(registry)
	formula_session.create_battle("level.prototype_harbor_3v3", 1214)
	var formula_source: Dictionary = formula_session.state["units_by_id"]["unit.player.shimakaze"]
	var formula_facility_id := "facility.harbor.battery_west"
	var formula_hp_before := float(formula_session.facility_service.facilities_by_id[formula_facility_id]["current_hp"])
	formula_session._resolve_facility_attack({"attack_id":"facility.formula.test","source_unit_id":formula_source["entity_id"],"source_weapon_id":"weapon.warspite_381_he","target_facility_id":formula_facility_id,"target_position":formula_session.facility_service.facilities_by_id[formula_facility_id]["position"],"origin":formula_source["position"],"accuracy_modifier":0.0}, formula_source, true)
	_check(float(formula_session.facility_service.facilities_by_id[formula_facility_id]["current_hp"]) < formula_hp_before and _has_event(formula_session._event_buffer, "AttackResolved"), "facility attacks reuse the normal weapon formula and emit the shared damage result")

	var support_session = BattleSession.new(registry)
	support_session.create_battle("level.prototype_harbor_3v3", 1205)
	var support_target: Dictionary = support_session.state["units_by_id"]["unit.player.shimakaze"]
	var support_position: Vector2 = support_target["position"]
	var recon_request: Dictionary = support_session.facility_service.request_support("facility.harbor.airfield_east", "support_mission.air_recon", "enemy", support_position, 0.0, support_session.terrain_context_service.context_at(support_position))
	_check(recon_request["accepted"], "airfield validates state, dependency, range, weather, cooldown, and charges before accepting recon")
	for event in support_session.facility_service.advance(20.0, 20.0, support_session.state["units_by_id"]): support_session._handle_facility_event(event)
	_check(not support_session.state["support_effects_by_id"].is_empty(), "completed reconnaissance mission creates a timed aerial observation source")
	var patrol_event := {"event_type":"SupportMissionCompleted","mission_id":"mission.test.patrol","definition_id":"support_mission.fighter_patrol","facility_id":"facility.harbor.airfield_east","faction_id":"enemy","target_position":support_position}
	support_session._resolve_support_mission(patrol_event)
	_check(support_session._environment_accuracy_modifier("player", support_position, support_position, "Aviation") <= -0.28, "fighter patrol applies a real accuracy penalty to enemy aviation inside its area")
	support_session._event_buffer = []
	support_session._resolve_support_mission({"event_type":"SupportMissionCompleted","mission_id":"mission.test.strike","definition_id":"support_mission.airstrike","facility_id":"facility.harbor.airfield_east","faction_id":"enemy","target_position":support_position})
	_check(_has_event(support_session._event_buffer, "SupportMissionResolved") and _has_event(support_session._event_buffer, "AttackResolved"), "airstrike completion resolves through the existing weapon and damage service")
	var blocked_support_session = BattleSession.new(registry)
	blocked_support_session.create_battle("level.prototype_harbor_3v3", 1215)
	var weather_rejection: Dictionary = blocked_support_session.facility_service.request_support("facility.harbor.airfield_east", "support_mission.airstrike", "enemy", support_position, 0.0, {"aviation_condition":"Severe","aviation_delay_multiplier":1.6})
	blocked_support_session.facility_service.suppress("facility.harbor.communication_east", 10.0, "test")
	var dependency_rejection: Dictionary = blocked_support_session.facility_service.request_support("facility.harbor.airfield_east", "support_mission.airstrike", "enemy", support_position, 0.0, {})
	_check(weather_rejection.get("reason_code", "") == "AVIATION_WEATHER_BLOCKED" and dependency_rejection.get("reason_code", "") == "FACILITY_NOT_ACTIVE", "support missions cannot bypass severe weather or a disabled communication dependency")

	var mine_session = BattleSession.new(registry)
	mine_session.create_battle("level.prototype_harbor_3v3", 1206)
	var mined_unit: Dictionary = mine_session.state["units_by_id"]["unit.player.shimakaze"]
	var mine_trigger: Dictionary = mine_session.minefield_service.resolve_unit_motion(mined_unit, Vector2(1400,700), Vector2(1650,700))
	_check(mine_trigger["triggered"], "continuous minefield query finds entry outside the authored safe channel")
	mine_session.facility_service.suppress("facility.harbor.mine_control_west", 10.0, "test")
	var mine_state_events: Array = mine_session.minefield_service.sync_controllers(mine_session.facility_service.snapshot())
	_check(_has_event(mine_state_events, "MineFieldStateChanged") and mine_session.minefield_service.snapshot()["minefield.harbor_outer"]["operation_state"] == "Dormant", "suppressing the bound controller disables only its authored minefield")

	var ai_session = BattleSession.new(registry)
	ai_session.create_battle("level.prototype_harbor_3v3", 1207)
	var ai_unit: Dictionary = ai_session.state["units_by_id"]["unit.enemy.kirov"]
	var facility_plan := ai_session._ai_facility_plan(ai_unit, true)
	_check(not facility_plan.is_empty(), "AI creates a facility capture or activation objective from its legal faction view")
	var safe_waypoint: Vector2 = ai_session.minefield_service.avoidance_waypoint("enemy", Vector2(1400,700), Vector2(1650,700))
	_check(safe_waypoint != Vector2(1650,700), "AI redirects a route crossing a known active minefield through the authored safe channel")
	var rough_unit: Dictionary = ai_session.state["units_by_id"]["unit.enemy.anshan"]
	rough_unit["position"] = Vector2(3000,500); rough_unit["movement_state"] = {"mode":"AutoNavigate","target_position":Vector2(3400,500)}; rough_unit["current_speed"] = 0.0
	ai_session._update_movement(0.1)
	_check(float(rough_unit["current_speed"]) < float(rough_unit["stats"]["speed"]) * 0.1, "runtime ship acceleration consumes the high-sea movement multiplier")


func _find_clear_observation_point(session, origin: Vector2, distance: float) -> Vector2:
	for angle_index in range(24):
		var candidate := origin + Vector2.RIGHT.rotated(TAU * float(angle_index) / 24.0) * distance
		if session._inside_map(candidate) and session.terrain_query.can_occupy_circle(candidate, 20.0, ["Surface", "ShallowDraft"]) and session.terrain_query.has_surface_line_of_sight(origin, candidate): return candidate
	return origin


func _contains_chinese(value: String) -> bool:
	for index in range(value.length()):
		var code := value.unicode_at(index)
		if code >= 0x4E00 and code <= 0x9FFF:
			return true
	return false


func _test_runtime_baseline_scales() -> void:
	for ship in registry.all("ships"):
		_check(is_equal_approx(float(ship.get("speed", 0.0)), float(ship.get("base_speed", 0.0)) * 0.5), "%s uses the 0.5x runtime speed baseline" % ship.get("id", "?"))
		_check(is_equal_approx(float(ship.get("turn_speed", 0.0)), float(ship.get("base_turn_speed", 0.0)) * 0.5), "%s uses the 0.5x runtime turn baseline" % ship.get("id", "?"))
		_check(is_equal_approx(float(ship.get("detection_range", 0.0)), float(ship.get("base_detection_range", 0.0)) * 1.5), "%s uses the 1.5x runtime detection baseline" % ship.get("id", "?"))
		_check(is_equal_approx(float(ship.get("concealment_distance", 0.0)), float(ship.get("base_concealment_distance", 0.0)) * 1.5), "%s uses the 1.5x runtime concealment baseline" % ship.get("id", "?"))
		var collision_half_extents := CollisionGeometryService.half_extents(ship)
		_check(collision_half_extents.x >= collision_half_extents.y and collision_half_extents.y > 0.0, "%s exposes a longitudinal elliptical collision hull" % ship.get("id", "?"))
	for weapon in registry.all("weapons"):
		var base_range := float(weapon.get("base_range", 0.0))
		var effective_range := float(weapon.get("range", 0.0))
		_check(base_range > 0.0 and is_equal_approx(effective_range, base_range * 1.5), "%s uses the global 1.5x effective attack range" % weapon.get("id", "?"))
		var base_projectile_speed := float(weapon.get("base_projectile_speed", 0.0))
		_check(base_projectile_speed >= 0.0 and is_equal_approx(float(weapon.get("projectile_speed", 0.0)), base_projectile_speed * 0.5), "%s uses the 0.5x runtime attack speed baseline" % weapon.get("id", "?"))
		if weapon.get("mount_type", "") == "Gun" and int(weapon.get("mount_count", 0)) > 1:
			_check(not weapon.get("full_salvo_fire_arcs", []).is_empty(), "%s exposes the all-mount full-salvo firing sectors" % weapon.get("id", "?"))
		if weapon.get("mount_type", "") == "Gun":
			_check(is_equal_approx(float(weapon.get("impact_radius", 0.0)), float(weapon.get("base_impact_radius", 0.0)) * 0.5), "%s uses the halved shell impact radius" % weapon.get("id", "?"))
		if weapon.get("mount_type", "") == "Torpedo" and weapon.get("control_mode", "") == "ManualPrimary":
			var lane_spacing := float(weapon.get("torpedo_lane_spacing", 0.0))
			var expected_spread := rad_to_deg(2.0 * asin(lane_spacing / (2.0 * effective_range))) * float(int(weapon.get("shots_per_mount", 0)) - 1)
			_check(lane_spacing == 80.0 and absf(float(weapon.get("spread", 0.0)) - expected_spread) <= 0.001, "%s derives per-mount spread from the battleship-width lane baseline" % weapon.get("id", "?"))
			_check(is_equal_approx(float(weapon.get("torpedo_angular_sigma_ratio", 0.0)), 0.20), "%s uses the shared twenty-percent adjacent-angle torpedo sigma baseline" % weapon.get("id", "?"))
			_check(weapon.get("mount_fire_arcs", []).size() == int(weapon.get("mount_count", 0)) and float(weapon.get("mount_launch_interval", 0.0)) >= 1.0, "%s defines independent launcher arcs and the minimum launch interval" % weapon.get("id", "?"))
	for projectile in registry.all("projectiles"):
		var base_speed := float(projectile.get("base_speed", 0.0))
		_check(base_speed >= 0.0 and is_equal_approx(float(projectile.get("speed", 0.0)), base_speed * 0.5), "%s uses the 0.5x runtime projectile and aircraft speed baseline" % projectile.get("id", "?"))
	for formula in registry.all("formulas"):
		_check(is_equal_approx(float(formula.get("base_damage", 0.0)), float(formula.get("design_base_damage", 0.0)) * 0.25), "%s uses the 0.25x runtime base damage" % formula.get("id", "?"))
		_check(is_equal_approx(float(formula.get("power_coefficient", 0.0)), float(formula.get("design_power_coefficient", 0.0)) * 0.25), "%s uses the 0.25x runtime power coefficient" % formula.get("id", "?"))
		_check(is_equal_approx(float(formula.get("armor_coefficient", 0.0)), float(formula.get("design_armor_coefficient", 0.0)) * 0.25), "%s keeps armor reduction in the same 0.25x damage unit")
	for skill in registry.all("skills"):
		var base_cast_range := float(skill.get("base_cast_range", 0.0))
		var expected_cast_range := base_cast_range * 1.5 if base_cast_range > 0.0 else 0.0
		_check(is_equal_approx(float(skill.get("cast_range", 0.0)), expected_cast_range), "%s uses the 1.5x runtime skill range baseline" % skill.get("id", "?"))
	var warspite: Dictionary = registry.get_definition("ships", "ship.warspite")
	_check(CollisionGeometryService.half_extents(warspite).is_equal_approx(Vector2(75.0, 31.5)), "Warspite collision hull follows the rendered rig dimensions")
	_check(is_equal_approx(float(warspite.get("speed", 0.0)), 31.0) and is_equal_approx(float(warspite.get("turn_speed", 0.0)), 22.5), "ship movement uses the halved runtime speed and turn baseline")
	_check(is_equal_approx(float(warspite.get("detection_range", 0.0)), 585.0) and is_equal_approx(float(warspite.get("concealment_distance", 0.0)), 900.0), "ship detection and concealment use the 1.5x runtime distance baseline")
	_check(is_equal_approx(float(registry.get_definition("weapons", "weapon.warspite_381_ap").get("range", 0.0)), 1080.0), "main-gun UI and rules expose the 1.5x effective range")
	var large_ap: Dictionary = registry.get_definition("formulas", "formula.large_ap")
	var runtime_source := {"entity_id":"runtime.source", "position":Vector2.ZERO, "stats":{"gunnery_power":172.0}, "status_effects":[]}
	var runtime_target := {"entity_id":"runtime.target", "position":Vector2(100.0,0.0), "current_hp":10000.0, "stats":{"armor":98.0,"armor_thickness":"Heavy","evasion":0.0}, "status_effects":[]}
	var runtime_weapon := {"id":"runtime.weapon", "mount_type":"Gun", "range":1080.0, "accuracy_modifier":0.0, "armor_damage_modifiers":{"Heavy":1.0}}
	var design_formula := large_ap.duplicate(true)
	design_formula["base_damage"] = design_formula["design_base_damage"]
	design_formula["power_coefficient"] = design_formula["design_power_coefficient"]
	design_formula["armor_coefficient"] = design_formula["design_armor_coefficient"]
	var runtime_damage: Dictionary = DamageService.resolve({}, runtime_source, runtime_target, runtime_weapon, large_ap, SeededRandomSource.new(7), true)
	var design_damage: Dictionary = DamageService.resolve({}, runtime_source, runtime_target, runtime_weapon, design_formula, SeededRandomSource.new(7), true)
	var estimated_damage: Dictionary = DamageService.estimate_attack({}, runtime_source, runtime_target, runtime_weapon, large_ap)
	_check(is_equal_approx(float(runtime_damage["final_damage"]), float(design_damage["final_damage"]) * 0.25), "runtime damage result is exactly one quarter of the design-scale result")
	_check(is_equal_approx(float(estimated_damage["damage_on_hit"]), float(runtime_damage["final_damage"])) and is_equal_approx(float(estimated_damage["expected_damage"]), float(estimated_damage["damage_on_hit"]) * float(estimated_damage["hit_rate"])), "AI expected-damage input reuses the authoritative hit and damage formula without consuming randomness")
	_check(is_equal_approx(float(registry.get_definition("weapons", "weapon.shimakaze_610_torpedo").get("range", 0.0)), 765.0), "torpedo UI and rules expose the 1.5x effective range")
	_check(is_equal_approx(float(registry.get_definition("weapons", "weapon.enterprise_airstrike").get("range", 0.0)), 1140.0), "aviation UI and rules expose the 1.5x effective range")
	_check(is_equal_approx(float(registry.get_definition("weapons", "weapon.warspite_381_ap").get("projectile_speed", 0.0)), 210.0), "main-gun projectiles use the halved runtime attack speed baseline")
	_check(is_equal_approx(float(registry.get_definition("weapons", "weapon.warspite_381_ap").get("impact_radius", 0.0)), 23.0), "main-gun shell impact radius is halved from its 46-unit design radius")
	_check(is_equal_approx(float(registry.get_definition("weapons", "weapon.shimakaze_610_torpedo").get("projectile_speed", 0.0)), 85.0), "torpedoes use the halved runtime attack speed baseline")
	_check(is_equal_approx(float(registry.get_definition("weapons", "weapon.enterprise_airstrike").get("projectile_speed", 0.0)), 90.0), "aviation groups use the halved runtime attack speed baseline")
	_check(is_equal_approx(float(registry.get_definition("projectiles", "projectile.surface_torpedo").get("speed", 0.0)), 82.5), "projectile definitions use the halved runtime movement speed baseline")
	_check(is_equal_approx(float(registry.get_definition("projectiles", "aircraft.bomber").get("speed", 0.0)), 110.0), "aircraft definitions use the halved runtime movement speed baseline")
	_check(is_equal_approx(float(registry.get_definition("skills", "skill.warspite_veteran_aim").get("cast_range", 0.0)), 1095.0), "skill range uses the 1.5x runtime distance baseline")
	var gaussian_a = SeededRandomSource.new(20260629)
	var gaussian_b = SeededRandomSource.new(20260629)
	var gaussian_nonzero := false
	for index in range(6):
		var sample_a := gaussian_a.randfn(0.0, 0.25)
		var sample_b := gaussian_b.randfn(0.0, 0.25)
		_check(is_equal_approx(sample_a, sample_b), "fixed battle seed reproduces Gaussian sample %d" % index)
		gaussian_nonzero = gaussian_nonzero or not is_zero_approx(sample_a)
	_check(gaussian_nonzero, "Gaussian random source produces non-zero angular deviations")


func _test_gun_dispersion_rules() -> void:
	var settings: Dictionary = registry.get_definition("settings", "settings.combat").get("gun_dispersion", {})
	var sigma_scale := float(settings.get("sigma_scale", 0.0))
	var longitudinal_ratio := float(settings.get("longitudinal_sigma_ratio", 0.0))
	var warspite_sigmas := GunDispersionService.sigmas(1080.0, 14.0, sigma_scale, longitudinal_ratio)
	_check(warspite_sigmas.is_equal_approx(Vector2(150.0, 75.0)), "Warspite maximum-range dispersion calibrates to one battleship length laterally and half that longitudinally")
	_check(GunDispersionService.sigmas(540.0, 14.0, sigma_scale, longitudinal_ratio).is_equal_approx(Vector2(75.0, 37.5)), "gun dispersion sigma scales linearly with firing distance")
	var random := SeededRandomSource.new(140381)
	var lateral_sum := 0.0
	var longitudinal_sum := 0.0
	var lateral_square_sum := 0.0
	var longitudinal_square_sum := 0.0
	var sample_count := 6000
	for index in range(sample_count):
		var sample := GunDispersionService.sample(Vector2.ZERO, Vector2(1080.0, 0.0), 14.0, sigma_scale, longitudinal_ratio, random)
		var position: Vector2 = sample["position"]
		var longitudinal := position.x - 1080.0
		var lateral := position.y
		lateral_sum += lateral
		longitudinal_sum += longitudinal
		lateral_square_sum += lateral * lateral
		longitudinal_square_sum += longitudinal * longitudinal
	var lateral_mean := lateral_sum / float(sample_count)
	var longitudinal_mean := longitudinal_sum / float(sample_count)
	var lateral_stddev := sqrt(lateral_square_sum / float(sample_count) - lateral_mean * lateral_mean)
	var longitudinal_stddev := sqrt(longitudinal_square_sum / float(sample_count) - longitudinal_mean * longitudinal_mean)
	_check(absf(lateral_mean) < 6.0 and absf(longitudinal_mean) < 3.0, "sampled shell ellipse remains centered on the aimed point")
	_check(absf(lateral_stddev - 150.0) < 6.0 and absf(longitudinal_stddev - 75.0) < 3.0, "sampled shell ellipse reproduces the configured lateral and longitudinal sigma")
	var deterministic_a := SeededRandomSource.new(381)
	var deterministic_b := SeededRandomSource.new(381)
	var deterministic_samples := true
	for index in range(8):
		var first := GunDispersionService.sample(Vector2.ZERO, Vector2(1080.0, 0.0), 14.0, sigma_scale, longitudinal_ratio, deterministic_a)
		var second := GunDispersionService.sample(Vector2.ZERO, Vector2(1080.0, 0.0), 14.0, sigma_scale, longitudinal_ratio, deterministic_b)
		deterministic_samples = deterministic_samples and (first["position"] as Vector2).is_equal_approx(second["position"])
	_check(deterministic_samples, "fixed battle seed reproduces every independently sampled shell impact")
	var session = BattleSession.new(registry)
	session.create_battle("level.prototype_3v3", 381)
	var warspite: Dictionary = session.state["units_by_id"]["unit.player.warspite"]
	warspite["position"] = Vector2(500.0, 1000.0)
	var weapon: Dictionary = registry.get_definition("weapons", "weapon.warspite_381_ap")
	var weapon_state := _weapon_state(warspite, weapon["id"])
	warspite["status_effects"].append({"stat":"WeaponSpread", "operation":"PercentAdd", "value":-0.5, "category":"Gun"})
	var reduced_sample: Dictionary = session._sample_gun_impact(warspite["position"], Vector2(1580.0, 1000.0), weapon, warspite["status_effects"])
	_check(is_equal_approx(float(reduced_sample["lateral_sigma"]), 75.0) and is_equal_approx(float(session.get_primary_aim_status(warspite["entity_id"], Vector2(1580.0, 1000.0))["spread_degrees"]), 7.0), "WeaponSpread modifiers scale both runtime sigma and the aiming ellipse")
	warspite["status_effects"].clear()
	session.delayed_attacks.clear()
	session.drain_events()
	session._fire_weapon_at_position(warspite, Vector2(1580.0, 1000.0), weapon_state, weapon, true)
	var independent_positions := {}
	var metadata_valid: bool = session.delayed_attacks.size() == 8
	for attack in session.delayed_attacks:
		independent_positions[str(attack["target_position"])] = true
		metadata_valid = metadata_valid and is_equal_approx(float(attack.get("dispersion_lateral_sigma", 0.0)), 150.0) and is_equal_approx(float(attack.get("dispersion_longitudinal_sigma", 0.0)), 75.0)
	var fired_event: Dictionary = {}
	for event in session.drain_events():
		if event.get("event_type", "") == "WeaponFired": fired_event = event
	_check(metadata_valid and independent_positions.size() > 1, "every runtime shell receives its own Gaussian impact and diagnostic sigma metadata")
	_check(fired_event.get("impact_positions", []) == session.delayed_attacks.map(func(attack): return attack["target_position"]), "shell flight presentation receives the exact sampled combat impact positions")


func _test_elliptical_collision_geometry() -> void:
	var extents := Vector2(75.0, 31.5)
	_check(CollisionGeometryService.point_in_expanded_ellipse(Vector2(74.0, 0.0), Vector2.ZERO, 0.0, extents), "ellipse collision includes the visible longitudinal rig edge")
	_check(not CollisionGeometryService.point_in_expanded_ellipse(Vector2(0.0, 32.0), Vector2.ZERO, 0.0, extents), "ellipse collision excludes points beyond the lateral hull edge")
	_check(CollisionGeometryService.point_in_expanded_ellipse(Vector2(97.0, 0.0), Vector2.ZERO, 0.0, extents, 23.0), "halved shell impact circle intersects the expanded longitudinal hull")
	_check(not CollisionGeometryService.point_in_expanded_ellipse(Vector2(0.0, 55.0), Vector2.ZERO, 0.0, extents, 23.0), "shell impact outside the expanded lateral hull does not collide")
	var torpedo_hit := CollisionGeometryService.segment_expanded_ellipse_fraction(Vector2(-140.0, 40.0), Vector2(140.0, 40.0), Vector2.ZERO, 0.0, extents, 12.0)
	var torpedo_miss := CollisionGeometryService.segment_expanded_ellipse_fraction(Vector2(-140.0, 50.0), Vector2(140.0, 50.0), Vector2.ZERO, 0.0, extents, 12.0)
	_check(torpedo_hit >= 0.0 and torpedo_miss < 0.0, "continuous torpedo sweep uses the ship ellipse plus torpedo radius")
	_check(is_equal_approx(CollisionGeometryService.separation_distance(extents, 0.0, extents, 0.0, Vector2.RIGHT), 150.0), "head-to-head ship separation uses longitudinal ellipse extents")
	_check(is_equal_approx(CollisionGeometryService.separation_distance(extents, 0.0, extents, 0.0, Vector2.DOWN), 63.0), "broadside ship separation uses lateral ellipse extents")


func _test_hit_rate_floor() -> void:
	for formula in registry.all("formulas"):
		if str(formula.get("attack_type", "")) == "Gun":
			_check(is_equal_approx(float(formula.get("hit_rate_min", 0.0)), 0.05), "%s uses the 5 percent probabilistic hit floor" % formula.get("id", "?"))
			_check(is_equal_approx(float(formula.get("hit_rate_max", 0.0)), 0.95), "%s keeps the existing maximum hit rate" % formula.get("id", "?"))
		elif str(formula.get("attack_type", "")) == "Torpedo":
			_check(is_equal_approx(float(formula.get("hit_rate_min", 0.0)), 1.0), "%s keeps collision-forced torpedo accuracy" % formula.get("id", "?"))


func _test_full_roster_runtime_data() -> void:
	var roster_ids := {}
	var produced_phase2_assets := 0
	for ship in registry.all("ships"):
		var ship_id := str(ship.get("id", ""))
		var character_id := ship_id.trim_prefix("ship.")
		roster_ids[ship_id] = true
		var phase2_plan_path := "res://assets/characters/%s/postprocess_plan.json" % character_id
		var processed_manifest_path := "res://assets/characters/%s/processed/config/%s_postprocess_manifest.json" % [character_id, character_id]
		var phase2_pending_art := FileAccess.file_exists(phase2_plan_path) and not FileAccess.file_exists(processed_manifest_path)
		if not phase2_pending_art:
			_check(assets.has_character(character_id), "runtime art catalog contains %s" % ship_id)
			var character_assets: Dictionary = assets.character(character_id)
			var battle_assets: Dictionary = character_assets.get("battle_assets", {})
			var ui_assets: Dictionary = character_assets.get("ui_assets", {})
			_check(battle_assets.has("body_r") and battle_assets.has("rig_base"), "%s has battle body and rig assets" % ship_id)
			_check(ui_assets.has("ui_portrait") and ui_assets.has("illust_skill_cutin_alpha") and ui_assets.has("illust_full_alpha"), "%s has HUD, menu, and result artwork" % ship_id)
			if FileAccess.file_exists(phase2_plan_path):
				produced_phase2_assets += 1
		_check(UiText.character_name(character_id) != "未知角色", "%s has a localized UI name" % ship_id)
		_check(not ship.get("weapon_mounts", []).is_empty(), "%s has at least one runtime weapon" % ship_id)
		_check(not registry.get_definition("skills", str(ship.get("skill_id", ""))).is_empty(), "%s has a runtime skill" % ship_id)
		_check(not str(ship.get("primary_weapon_group_id", "")).is_empty(), "%s has an explicit primary weapon group" % ship_id)
	_check(produced_phase2_assets >= 4, "the accepted phase-two US batch is discoverable through the runtime art catalog")
	var level_roster := {}
	for level in registry.all("levels"):
		for fleet_name in ["player_fleet", "enemy_fleet"]:
			for member in level.get(fleet_name, []):
				level_roster[str(member.get("ship_id", ""))] = true
	_check(level_roster.size() == 24, "existing playable levels retain the 24-character phase-one roster")
	for ship_id in level_roster:
		_check(roster_ids.has(ship_id), "%s in a playable level resolves to runtime data" % ship_id)
	for ship in registry.all("ships"):
		var character_id := str(ship.get("id", "")).trim_prefix("ship.")
		if not FileAccess.file_exists("res://assets/characters/%s/postprocess_plan.json" % character_id):
			continue
		for weapon_id in ship.get("weapon_mounts", []):
			var weapon: Dictionary = registry.get_definition("weapons", str(weapon_id))
			_check(not assets.weapon_visual(character_id, str(weapon.get("weapon_group_id", ""))).is_empty(), "%s weapon group has a visual mapping" % weapon_id)


func _test_modifier_order() -> void:
	var effects := [
		{"stat":"Armor","operation":"FlatAdd","value":10.0,"category":"All"},
		{"stat":"Armor","operation":"PercentAdd","value":0.20,"category":"All"},
		{"stat":"Armor","operation":"StateMultiply","value":0.50,"category":"All"},
		{"stat":"Armor","operation":"IndependentMultiply","value":1.10,"category":"All"},
	]
	_check(is_equal_approx(ModifierService.calculate(100.0, effects, "Armor"), 72.6), "modifier order follows flat, percent, state, independent")
	var reload_effects := [{"stat":"ReloadSpeed","operation":"PercentAdd","value":0.50,"category":"Gun"}]
	_check(is_equal_approx(ModifierService.reload_time(10.0, reload_effects, "Gun"), 10.0 / 1.5), "reload speed uses divisor formula")


func _test_asset_catalog() -> void:
	_check(assets.has_character("bismarck"), "asset catalog discovers processed character packages")
	var idle: Dictionary = assets.animation_state("bismarck", "idle")
	_check(idle.get("frames", []).size() == 4 and str(idle["frames"][0]).begins_with("res://"), "character animation state resolves normalized frame paths")
	var wake: Dictionary = assets.vfx_role("bismarck", "wake")
	_check(str(wake.get("file", "")).ends_with("bismarck_vfx_wake.png"), "character VFX role resolves by semantic role")
	var shared_vfx: Dictionary = assets.vfx_role("kirov", "muzzle_flash_large")
	var shared_vfx_path := str(shared_vfx.get("file", ""))
	_check(
		shared_vfx.get("source", "") == "shared_class_template"
		and shared_vfx_path.begins_with("res://assets/vfx/combat/character_templates/")
		and FileAccess.file_exists(shared_vfx_path),
		"shared class-template VFX resolves to one public runtime asset",
	)
	var bind: Dictionary = assets.bind_points("bismarck", "bismarck_battle_rig_base.png")
	_check(bind.has("turret_mount_01"), "character bind points resolve per battle asset")
	_check(assets.battle_asset_path("bismarck", "rig_base").ends_with("bismarck_battle_rig_base.png"), "battle asset resolves by semantic suffix")
	_check(assets.ui_asset_path("ui.icon.torpedo", "2x").ends_with("/2x/ui_icon_torpedo.png"), "UI asset resolves by semantic key and export scale")
	_check(not assets.projectile_visual("projectile.surface_torpedo").is_empty(), "projectile visual resolves by projectile id")
	var small_shell_visual: Dictionary = assets.projectile_visual("visual.projectile.shell.small")
	var large_shell_visual: Dictionary = assets.projectile_visual("visual.projectile.shell.large")
	_check(
		float(large_shell_visual.get("shell_trail_caliber_pixel_multiplier", 0.0)) > float(small_shell_visual.get("shell_trail_caliber_pixel_multiplier", 0.0))
		and float(large_shell_visual.get("shell_trail_width", 0.0)) > float(small_shell_visual.get("shell_trail_width", 0.0)) * 3.0,
		"projectile visual data preserves strong caliber-based shell trail separation",
	)
	_check(assets.weapon_visual("shimakaze", "shimakaze_torpedo").get("fire_animation_state", "") == "firepower", "weapon visual resolves by character and weapon group")
	_check(float(assets.vfx_playback_profile("vfx.profile.shell_impact").get("duration", 0.0)) > 0.0, "VFX playback profile resolves by semantic id")
	_check(assets.combat_vfx_asset_path("impact.water.large").ends_with("vfx_impact_water_large_01.png"), "public large-caliber water-column art resolves by combat VFX semantic")


func _test_command_and_skill_rules() -> void:
	var session = BattleSession.new(registry)
	_check(session.create_battle("level.prototype_3v3", 9).get("ok", false), "3v3 battle can be created")
	var move_result: Dictionary = session.queue_command({"command_id":"move.1","command_type":"MoveUnits","issued_at_tick":0,"issuer_id":"player","unit_id":"unit.player.aurora","target_position":Vector2(400.0, 300.0)})
	_check(move_result.get("accepted", false), "valid move command enters shared command queue")
	session.advance_tick(0.1)
	_check(session.state["units_by_id"]["unit.player.aurora"]["movement_state"]["mode"] == "PlayerMoveOrder", "move command changes domain movement state")
	var hindenburg: Dictionary = session.state["units_by_id"]["unit.enemy.hindenburg"]
	hindenburg["skill_state"]["cooldown_remaining"] = 0.0
	var cast_result: Dictionary = session._cast_skill(hindenburg, {"type":"Self"}, "skill.1")
	_check(cast_result.get("accepted", false), "ready skill casts successfully")
	_check(float(hindenburg["skill_state"]["cooldown_remaining"]) == 40.0, "successful skill starts cooldown")
	_check(not hindenburg["status_effects"].is_empty(), "skill applies reusable status effects")
	var second_cast: Dictionary = session._cast_skill(hindenburg, {"type":"Self"}, "skill.2")
	_check(second_cast.get("reason_code", "") == "SKILL_ON_COOLDOWN", "skill on cooldown is rejected atomically")
	var aurora: Dictionary = session.state["units_by_id"]["unit.player.aurora"]
	session._sink_unit(aurora, "test")
	session.queue_command({"command_id":"move.sunk","command_type":"MoveUnits","issued_at_tick":1,"issuer_id":"player","unit_id":"unit.player.aurora","target_position":Vector2(500.0, 300.0)})
	var events: Array = session.advance_tick(0.1)
	_check(_has_event_reason(events, "CommandRejected", "UNIT_SUNK"), "sunk unit cannot accept tactical commands")


func _test_operation_design_rules() -> void:
	var original_level: Dictionary = registry.get_definition("levels", "level.prototype_1v1").duplicate(true)
	var weapon_state_level: Dictionary = original_level.duplicate(true)
	weapon_state_level["player_fleet"][0]["weapon_group_states"] = {"warspite_main":"Disabled", "warspite_secondary":"Disabled"}
	registry.definitions["levels"]["level.prototype_1v1"] = weapon_state_level
	var weapon_state_session = BattleSession.new(registry)
	weapon_state_session.create_battle("level.prototype_1v1", 20)
	registry.definitions["levels"]["level.prototype_1v1"] = original_level
	var configured_warspite: Dictionary = weapon_state_session.state["units_by_id"]["unit.player.warspite"]
	var configured_main_states := weapon_state_session._weapon_states_for_group(configured_warspite, "warspite_main", false)
	var configured_secondary_states := weapon_state_session._weapon_states_for_group(configured_warspite, "warspite_secondary", false)
	_check(configured_main_states.all(func(state): return state.get("availability_state", "") == "Disabled" and not bool(state.get("enabled", true))), "level member state disables every runtime instance in the configured main weapon group")
	_check(configured_secondary_states.all(func(state): return state.get("availability_state", "") == "Disabled" and not bool(state.get("enabled", true))), "level member state disables the configured automatic weapon group")
	var configured_enemy: Dictionary = weapon_state_session.state["units_by_id"]["unit.enemy.bismarck"]
	configured_warspite["position"] = Vector2(300.0, 350.0)
	configured_enemy["position"] = Vector2(700.0, 350.0)
	weapon_state_session.state["visible_by_faction"]["player"] = {configured_enemy["entity_id"]:true}
	weapon_state_session._update_weapons()
	_check(not _has_event_for_source(weapon_state_session.drain_events(), "WeaponFired", configured_warspite["entity_id"]), "automatic fire obeys the level-configured disabled weapon group state")
	weapon_state_session.queue_command({"command_id":"primary.disabled","command_type":"FirePrimaryWeapon","issued_at_tick":0,"issuer_id":"player","unit_id":configured_warspite["entity_id"],"target_position":configured_enemy["position"]})
	var disabled_fire_events: Array = weapon_state_session.advance_tick(0.1)
	_check(_has_event_reason(disabled_fire_events, "CommandRejected", "WEAPON_GROUP_DISABLED"), "manual primary fire obeys the level-configured disabled weapon group state")
	var session = BattleSession.new(registry)
	session.create_battle("level.prototype_1v1", 21)
	var player: Dictionary = session.state["units_by_id"]["unit.player.warspite"]
	var enemy: Dictionary = session.state["units_by_id"]["unit.enemy.bismarck"]
	player["position"] = Vector2(300.0, 350.0)
	enemy["position"] = Vector2(830.0, 350.0)
	player["heading"] = 0.0
	enemy["heading"] = PI
	player["movement_state"]["mode"] = "HoldPosition"
	enemy["movement_state"]["mode"] = "HoldPosition"
	for index in range(30): session.advance_tick(0.1)
	var auto_events := session.drain_events()
	_check(not _has_event_for_source(auto_events, "WeaponFired", player["entity_id"]), "player ManualPrimary weapon stays silent while primary auto fire is disabled")
	_check(session.get_player_slots()[0]["unit_id"] == "unit.player.warspite", "slot 1 selects the first fleet member")
	var gun_aim_status: Dictionary = session.get_primary_aim_status(player["entity_id"], enemy["position"])
	_check(gun_aim_status.get("fire_arcs", []).size() == 1 and gun_aim_status.get("full_salvo_fire_arcs", []).size() == 2, "main-gun aim exposes available and all-mount full-salvo firing sectors")
	session.queue_command({"command_id":"primary.1","command_type":"FirePrimaryWeapon","issued_at_tick":session.state["tick_index"],"issuer_id":"player","unit_id":"unit.player.warspite","target_position":enemy["position"]})
	var fire_events: Array = session.advance_tick(0.1)
	_check(_has_event(fire_events, "WeaponFired"), "E-style primary confirmation creates a weapon fire fact")
	var expected_reveal_remaining := float(player["stats"]["concealment_distance"]) / maxf(1.0, float(player["stats"]["speed"])) - 0.1
	_check(is_equal_approx(float(player["firing_reveal_remaining"]), expected_reveal_remaining), "firing reveal duration uses runtime concealment divided by runtime speed")
	var ap_state := _weapon_state(player, "weapon.warspite_381_ap")
	var he_state := _weapon_state(player, "weapon.warspite_381_he")
	_check(float(ap_state["reload_remaining"]) > 0.0 and is_equal_approx(float(ap_state["reload_remaining"]), float(he_state["reload_remaining"])), "HE/AP modes share cooldown after primary fire")
	var reload_after_fire := float(ap_state["reload_remaining"])
	var fired_ap_shell := false
	for attack in session.delayed_attacks:
		if str(attack.get("source_weapon_id", "")) == "weapon.warspite_381_ap":
			fired_ap_shell = true
			break
	_check(fired_ap_shell, "already-fired shell keeps launch-time ammo definition")
	session.queue_command({"command_id":"ammo.1","command_type":"SwitchAmmo","issued_at_tick":session.state["tick_index"],"issuer_id":"player","unit_id":"unit.player.warspite"})
	session.advance_tick(0.1)
	_check(player["ammo_state"]["warspite_main"] == "HE", "Q switches HE/AP ammo state")
	_check(float(ap_state["reload_remaining"]) < reload_after_fire and float(ap_state["reload_remaining"]) > 0.0, "Q does not reset shared reload progress")
	session._sink_unit(player, "test")
	_check(session.get_player_slots()[0]["unit_id"] == "unit.player.warspite", "slot remains stable after sinking")


func _test_runtime_ai_control_rules() -> void:
	var session = BattleSession.new(registry)
	_check(session.create_battle("level.prototype_3v3", 31).get("ok", false), "runtime AI control test battle can be created")
	var player: Dictionary = session.state["units_by_id"]["unit.player.aurora"]
	_check(not bool(player.get("movement_assist_enabled", true)) and player["movement_state"]["mode"] == "HoldPosition", "player ship defaults to stationary movement assist off")
	_check(bool(player.get("secondary_auto_fire_enabled", false)), "player ship defaults to secondary auto fire on")
	_check(not bool(player.get("primary_auto_fire_enabled", true)) and not bool(player.get("skill_auto_cast_enabled", true)), "player primary auto fire and skill auto cast default off")
	var player_ids: Array = []
	for slot_data in session.get_player_slots(): player_ids.append(str(slot_data["unit_id"]))
	session.queue_command({"command_id":"control.fleet","command_type":"SetUnitControlState","issued_at_tick":0,"issuer_id":"player","unit_ids":player_ids,"movement_assist_enabled":true,"secondary_auto_fire_enabled":false})
	session.advance_tick(0.1)
	var fleet_control_applied := true
	for unit_id in player_ids:
		var controlled: Dictionary = session.state["units_by_id"][unit_id]
		fleet_control_applied = fleet_control_applied and bool(controlled["movement_assist_enabled"]) and not bool(controlled["secondary_auto_fire_enabled"])
	_check(fleet_control_applied, "fleet-scoped X/C state command applies consistently to all player ships")
	var waypoint := (player["position"] as Vector2) + Vector2(120.0, 40.0)
	session.queue_command({"command_id":"route.append","command_type":"AppendMoveWaypoint","issued_at_tick":session.state["tick_index"],"issuer_id":"player","unit_id":player["entity_id"],"target_position":waypoint})
	session.advance_tick(0.1)
	_check(player["movement_state"]["mode"] == "PlayerWaypointRoute" and player.get("player_route_waypoints", []).size() == 1, "Z-style waypoint command creates a persistent player route")
	player["skill_state"]["cooldown_remaining"] = 0.0
	for index in range(12): session.advance_tick(0.1)
	var skill_events := session.drain_events()
	_check(not _has_event_for_source(skill_events, "SkillCast", player["entity_id"]), "player assist never releases skills automatically")
	player["position"] = Vector2(2.0, float(session.state["map"].get("height", 700.0)) * 0.5)
	player["heading"] = PI
	player["current_speed"] = 30.0
	player["navigation_state"]["trajectory_dirty"] = true
	session._update_navigation_plans()
	_check(player["navigation_state"].get("state", "") != "EmergencyEvasion", "boundary handling remains in normal navigation instead of attack evasion")
	_check(player["movement_state"]["mode"] == "PlayerWaypointRoute" and not player["movement_state"].get("corridor_points", []).is_empty(), "normal navigation preserves the player corridor intent")
	session.queue_command({"command_id":"route.clear","command_type":"ClearMoveRoute","issued_at_tick":session.state["tick_index"],"issuer_id":"player","unit_id":player["entity_id"]})
	session.advance_tick(0.1)
	player["movement_assist_enabled"] = true
	session._queue_ai_move(player, player["position"] + Vector2(100.0, 0.0), "PlayerAssistAI", "AssistNavigate")
	session.queue_command({"command_id":"control.move.off","command_type":"SetUnitControlState","issued_at_tick":session.state["tick_index"],"issuer_id":"player","unit_id":player["entity_id"],"movement_assist_enabled":false})
	var move_cancel_events: Array = session.advance_tick(0.1)
	_check(_has_event_reason(move_cancel_events, "CommandRejected", "MOVEMENT_ASSIST_DISABLED"), "X-off rejects an already queued non-emergency assist move")
	var fire_session = BattleSession.new(registry)
	fire_session.create_battle("level.prototype_1v1", 32)
	var gunner: Dictionary = fire_session.state["units_by_id"]["unit.player.warspite"]
	var target: Dictionary = fire_session.state["units_by_id"]["unit.enemy.bismarck"]
	gunner["position"] = Vector2(300.0, 350.0)
	target["position"] = Vector2(830.0, 350.0)
	gunner["heading"] = 0.0
	target["heading"] = PI
	fire_session.state["visible_by_faction"]["player"] = {target["entity_id"]: true}
	gunner["primary_auto_fire_enabled"] = true
	var enemy_weapon: Dictionary = fire_session._weapon_for_state(target["weapon_states"][0])
	target["ai_state"]["mode_id"] = "ReconAvoid"
	_check(not fire_session._automatic_weapon_allowed_by_ai_discipline(target, gunner, enemy_weapon), "ReconAvoid silent discipline blocks ordinary automatic weapon fire")
	target["ai_state"]["mode_id"] = "VanguardLine"
	fire_session._update_ai_primary_weapons()
	fire_session.queue_command({"command_id":"control.suspend","command_type":"SetUnitControlState","issued_at_tick":fire_session.state["tick_index"],"issuer_id":"player","unit_id":gunner["entity_id"],"primary_auto_fire_suspended":true})
	var suspended_events: Array = fire_session.advance_tick(0.1)
	_check(not _has_event_for_source(suspended_events, "WeaponFired", gunner["entity_id"]), "entering E aim suspends an already queued player auto-primary shot")
	fire_session.queue_command({"command_id":"control.resume","command_type":"SetUnitControlState","issued_at_tick":fire_session.state["tick_index"],"issuer_id":"player","unit_id":gunner["entity_id"],"primary_auto_fire_suspended":false})
	fire_session.advance_tick(0.1)
	gunner["ai_state"]["fire_decision_cooldown"] = 0.0
	fire_session._update_ai_primary_weapons()
	var primary_events: Array = fire_session.advance_tick(0.1)
	_check(_has_event_for_source(primary_events, "WeaponFired", gunner["entity_id"]), "V-enabled player primary auto fire commits a legal quantified attack window")
	_check(float(gunner["skill_state"]["cooldown_remaining"]) > 0.0, "player skill remains untouched by primary auto-fire execution")

	var tactic_scores := {"Attack": 90.0, "Defend": 20.0, "Kite": 30.0}
	target["ai_state"]["tactic_id"] = "Defend"
	target["ai_state"]["tactic_entered_at"] = 0.0
	fire_session.state["elapsed_time"] = 5.0
	_check(fire_session._update_ai_tactic(target, tactic_scores) == "Defend", "detected tactic requires a first confirmation before switching")
	_check(fire_session._update_ai_tactic(target, tactic_scores) == "Attack", "detected tactic switches after the same better action wins twice")
	_check(fire_session._fire_discipline_for_mode("CarrierStandoff") == "SelfDefense" and fire_session._fire_discipline_for_mode("DisengageRegroup") == "SelfDefense", "carrier standoff and disengage use their designed self-defense fire discipline")

	var target_session = BattleSession.new(registry)
	target_session.create_battle("level.prototype_3v3", 33)
	var target_source: Dictionary = target_session.state["units_by_id"]["unit.enemy.bismarck"]
	var held_target: Dictionary = target_session.state["units_by_id"]["unit.player.aurora"]
	var better_target: Dictionary = target_session.state["units_by_id"]["unit.player.warspite"]
	better_target["current_hp"] = 1.0
	target_session.state["visible_by_faction"]["enemy"] = {
		"unit.player.aurora": true,
		"unit.player.shimakaze": true,
		"unit.player.warspite": true,
	}
	target_session._ai_observations_by_faction.clear()
	target_source["targeting_state"]["current_target_id"] = held_target["entity_id"]
	target_source["ai_state"]["target_acquired_at"] = 0.0
	target_source["ai_state"]["target_switch_ready_at"] = 0.0
	target_session.state["elapsed_time"] = 5.0
	_check(target_session._select_target_with_hysteresis(target_source)["entity_id"] == held_target["entity_id"], "target selection holds the current legal target through the first better-candidate confirmation")
	_check(target_session._select_target_with_hysteresis(target_source)["entity_id"] == better_target["entity_id"], "target selection switches after the same materially better target wins twice")

	gunner["stats"]["cost"] = 100.0
	target["stats"]["cost"] = 100.0
	gunner["current_hp"] = gunner["max_hp"]
	target["current_hp"] = target["max_hp"]
	gunner["position"] = Vector2(500.0, 350.0)
	target["position"] = Vector2(650.0, 350.0)
	fire_session.state["visible_by_faction"]["player"] = {target["entity_id"]: true}
	fire_session._ai_local_power_cache.clear()
	fire_session._ai_observations_by_faction.clear()
	var equal_power_pressure := float(fire_session._local_power_context(gunner).get("pressure", -1.0))
	_check(is_equal_approx(equal_power_pressure, 1.0 / 6.0), "equal visible local power maps to mild pressure instead of maximum pressure")

	fire_session.state["visible_by_faction"]["enemy"] = {}
	fire_session._ai_observations_by_faction.clear()
	fire_session._ai_local_power_cache.clear()
	target["navigation_state"]["state"] = "NormalNavigation"
	target["ai_state"]["level_task"] = ""
	target["ai_state"]["mode_id"] = "ReconAvoid"
	target["ai_state"]["tactic_id"] = "Defend"
	target["ai_state"]["continuous_evasion_seconds"] = 22.0
	target["ai_state"]["no_effective_movement_seconds"] = 26.0
	target["ai_state"]["no_engagement_seconds"] = 36.0
	target["ai_state"]["last_effective_attack_at"] = 0.0
	target["ai_state"]["passive_sample_elapsed"] = 0.0
	fire_session.state["elapsed_time"] = 40.0
	fire_session.drain_events()
	fire_session._update_ai_engagement_memory(0.1)
	var passive_pressure := float(target["ai_state"].get("engagement_pressure", 0.0))
	_check(passive_pressure >= 0.25 and _has_event(fire_session.drain_events(), "AIEngagementPressureTriggered"), "full AI records passive timers and emits an explainable engagement-pressure trigger")
	target["navigation_state"]["state"] = "EmergencyEvasion"
	fire_session._ai_local_power_cache.clear()
	fire_session._update_ai_engagement_memory(0.1)
	_check(is_zero_approx(float(target["ai_state"].get("engagement_pressure", -1.0))), "real immediate danger pauses passive engagement pressure")
	target["navigation_state"]["state"] = "NormalNavigation"
	target["ai_state"]["level_task"] = "DefendFacility"
	var task_exemption: Dictionary = fire_session._ai_engagement_pressure_exemption(target)
	_check(float(task_exemption.get("multiplier", 1.0)) <= 0.35 and "LEVEL_TASK" in task_exemption.get("reasons", []), "explicit objective work reduces passive pressure without a forced-charge timeout")
	target["ai_state"]["level_task"] = ""
	target["ai_state"]["engagement_pressure_triggered"] = true
	target["ai_state"]["engagement_pressure_started_at"] = 35.0
	fire_session.drain_events()
	fire_session._mark_ai_effective_attack(target)
	var attack_reset_events: Array = fire_session.drain_events()
	_check(is_zero_approx(float(target["ai_state"].get("engagement_pressure", -1.0))) and is_zero_approx(float(target["ai_state"].get("no_effective_attack_seconds", -1.0))) and _has_event(attack_reset_events, "AIEngagementPressureResolved"), "effective fire resets attack passivity and records trigger-to-engagement time")


func _test_torpedo_fire_arc_rules() -> void:
	var session = BattleSession.new(registry)
	session.create_battle("level.prototype_5v5", 27)
	var shimakaze: Dictionary = session.state["units_by_id"]["unit.player.shimakaze"]
	shimakaze["position"] = Vector2(1200.0, 1200.0)
	shimakaze["heading"] = 0.0
	var starboard_status: Dictionary = session.get_primary_aim_status(shimakaze["entity_id"], shimakaze["position"] + Vector2(0.0, 300.0))
	var distant_starboard_status: Dictionary = session.get_primary_aim_status(shimakaze["entity_id"], shimakaze["position"] + Vector2(0.0, 3000.0))
	var port_status: Dictionary = session.get_primary_aim_status(shimakaze["entity_id"], shimakaze["position"] + Vector2(0.0, -300.0))
	var bow_status: Dictionary = session.get_primary_aim_status(shimakaze["entity_id"], shimakaze["position"] + Vector2(300.0, 0.0))
	var stern_status: Dictionary = session.get_primary_aim_status(shimakaze["entity_id"], shimakaze["position"] + Vector2(-300.0, 0.0))
	_check(bool(starboard_status.get("legal", false)) and bool(port_status.get("legal", false)), "surface torpedoes allow both broadside sectors")
	_check(bool(distant_starboard_status.get("legal", false)), "torpedo aim uses direction only and ignores cursor distance")
	_check(not bool(bow_status.get("legal", true)) and not bool(stern_status.get("legal", true)), "surface torpedoes reject bow and stern blind sectors")
	var shimakaze_weapon: Dictionary = registry.get_definition("weapons", "weapon.shimakaze_610_torpedo")
	var expected_shimakaze_spread := rad_to_deg(2.0 * asin(80.0 / (2.0 * float(shimakaze_weapon["range"])))) * 4.0
	_check(starboard_status.get("fire_arcs", []).size() == 2 and is_equal_approx(float(starboard_status.get("spread_degrees", 0.0)), expected_shimakaze_spread), "torpedo aim merges ready centerline-mount sectors and exposes lane-spacing-derived spread")
	var error_profile: Dictionary = session._torpedo_error_profile(shimakaze, shimakaze_weapon, int(shimakaze_weapon["shots_per_mount"]))
	var ideal_adjacent_angle := deg_to_rad(float(shimakaze_weapon["spread"])) / float(int(shimakaze_weapon["shots_per_mount"]) - 1)
	var expected_sigma := ideal_adjacent_angle * 0.20 * float(error_profile["environment_multiplier"])
	_check(is_equal_approx(float(error_profile["sigma_radians"]), expected_sigma), "torpedo launch sigma is twenty percent of adjacent ideal lane angle times the launch-point environment multiplier")
	var shimakaze_mount_states: Array = []
	for weapon_state in shimakaze["weapon_states"]:
		if weapon_state.get("definition_id", "") == shimakaze_weapon["id"]: shimakaze_mount_states.append(weapon_state)
	_check(shimakaze_mount_states.size() == 3, "each Shimakaze torpedo launcher creates an independent runtime weapon state")
	session.drain_events()
	var first_launch: Dictionary = session._fire_primary_weapon(shimakaze, shimakaze["position"] + Vector2(0.0, 300.0), "torpedo.mount.1")
	_check(bool(first_launch.get("accepted", false)) and session.state["projectiles_by_id"].size() == 5, "one player confirmation launches only one five-tube mount")
	var first_mount_attribution := true
	var first_errors: Array[float] = []
	var gaussian_metadata_valid := true
	for projectile in session.state["projectiles_by_id"].values():
		first_mount_attribution = first_mount_attribution and projectile.get("source_mount_id", "") == "mount_1"
		first_errors.append(float(projectile.get("angular_error", 0.0)))
		gaussian_metadata_valid = gaussian_metadata_valid and is_equal_approx(float(projectile.get("angular_sigma", 0.0)), expected_sigma) and is_equal_approx(float(projectile.get("heading", 0.0)) - float(projectile.get("ideal_heading", 0.0)), float(projectile.get("angular_error", 0.0)))
	_check(first_mount_attribution, "every torpedo in a salvo retains its physical source mount id")
	var independently_sampled := false
	for index in range(1, first_errors.size()): independently_sampled = independently_sampled or not is_equal_approx(first_errors[index], first_errors[0])
	_check(gaussian_metadata_valid and independently_sampled, "each torpedo stores its independently sampled launch error and sigma without altering the ideal lane heading")
	_check(float(shimakaze_mount_states[0]["reload_remaining"]) > 0.0 and is_zero_approx(float(shimakaze_mount_states[1]["reload_remaining"])) and is_zero_approx(float(shimakaze_mount_states[2]["reload_remaining"])), "only the selected torpedo mount enters its full reload")
	var immediate_launch: Dictionary = session._fire_primary_weapon(shimakaze, shimakaze["position"] + Vector2(0.0, 300.0), "torpedo.mount.too_soon")
	_check(immediate_launch.get("reason_code", "") == "TORPEDO_MOUNT_INTERVAL", "a second mount cannot launch inside the one-second group interval")
	session._update_cooldowns_and_statuses(1.0)
	var mount_operation_status: Dictionary = session.get_operation_status(shimakaze["entity_id"])
	_check(int(mount_operation_status.get("primary_mounts_ready", 0)) == 2 and int(mount_operation_status.get("primary_mounts_total", 0)) == 3, "operation status exposes ready and total torpedo mount counts")
	var second_launch: Dictionary = session._fire_primary_weapon(shimakaze, shimakaze["position"] + Vector2(0.0, 300.0), "torpedo.mount.2")
	_check(bool(second_launch.get("accepted", false)) and session.state["projectiles_by_id"].size() == 10 and float(shimakaze_mount_states[1]["reload_remaining"]) > 0.0, "the next ready mount can launch after one second without resetting the first mount")
	var adjacent_angle := deg_to_rad(float(shimakaze_weapon["spread"])) / 4.0
	_check(is_equal_approx(2.0 * float(shimakaze_weapon["range"]) * sin(adjacent_angle * 0.5), 80.0), "adjacent Shimakaze torpedo lanes are one battleship longitudinal half-extent apart at maximum range")
	var submarine: Dictionary = session.state["units_by_id"]["unit.player.hai_shih"]
	submarine["position"] = Vector2(2000.0, 1200.0)
	submarine["heading"] = 0.0
	var fore_status: Dictionary = session.get_primary_aim_status(submarine["entity_id"], submarine["position"] + Vector2(300.0, 0.0))
	var aft_status: Dictionary = session.get_primary_aim_status(submarine["entity_id"], submarine["position"] + Vector2(-300.0, 0.0))
	var beam_status: Dictionary = session.get_primary_aim_status(submarine["entity_id"], submarine["position"] + Vector2(0.0, 300.0))
	_check(bool(fore_status.get("legal", false)) and bool(aft_status.get("legal", false)), "submarine torpedoes retain fore and aft firing sectors")
	_check(not bool(beam_status.get("legal", true)), "submarine torpedoes reject broadside firing")
	_check(is_equal_approx(float(fore_status.get("spread_degrees", 0.0)), 20.8476) and is_equal_approx(float(aft_status.get("spread_degrees", 0.0)), 8.0481), "selected submarine direction exposes the matching lane-spacing-derived launcher spread")
	var side_session = BattleSession.new(registry)
	side_session.create_battle("level.prototype_11v11", 28)
	var san_diego: Dictionary = side_session.state["units_by_id"]["unit.player.san_diego"]
	san_diego["position"] = Vector2(1200.0, 1200.0)
	san_diego["heading"] = 0.0
	var port_launch: Dictionary = side_session._fire_primary_weapon(san_diego, san_diego["position"] + Vector2(0.0, -300.0), "torpedo.side.port")
	_check(bool(port_launch.get("accepted", false)) and side_session.state["projectiles_by_id"].size() == 4, "a cruiser broadside command launches only its port-side mount")
	side_session._update_cooldowns_and_statuses(1.0)
	var spent_port_status: Dictionary = side_session.get_primary_aim_status(san_diego["entity_id"], san_diego["position"] + Vector2(0.0, -300.0))
	var ready_starboard_status: Dictionary = side_session.get_primary_aim_status(san_diego["entity_id"], san_diego["position"] + Vector2(0.0, 300.0))
	_check(not bool(spent_port_status.get("legal", true)) and bool(ready_starboard_status.get("legal", false)), "a cruiser cannot substitute the opposite-side mount into the spent broadside arc")
	var torpedo_weapon: Dictionary = shimakaze_weapon
	session.state["projectiles_by_id"].clear()
	session.drain_events()
	session._spawn_projectile(shimakaze, torpedo_weapon, "attack.torpedo.range", PI * 0.5)
	var projectile_id := str(session.state["projectiles_by_id"].keys()[0])
	var launch_position: Vector2 = session.state["projectiles_by_id"][projectile_id]["position"]
	for index in range(70):
		session._update_projectiles(0.1)
	_check(session.state["projectiles_by_id"].has(projectile_id) and float(session.state["projectiles_by_id"][projectile_id].get("travelled_distance", 0.0)) > 300.0, "torpedo continues beyond the clicked direction point")
	for index in range(30):
		if not session.state["projectiles_by_id"].has(projectile_id): break
		session._update_projectiles(0.1)
	var expiry_position := Vector2.ZERO
	for event in session.drain_events():
		if event.get("event_type", "") == "ProjectileExpired" and event.get("projectile_id", "") == projectile_id:
			expiry_position = event.get("position", Vector2.ZERO)
	_check(not session.state["projectiles_by_id"].has(projectile_id), "torpedo disappears after reaching its maximum range")
	_check(is_equal_approx(launch_position.distance_to(expiry_position), float(torpedo_weapon["range"])), "torpedo expiry position matches the weapon maximum range")


func _test_automatic_lead_and_fixed_impacts() -> void:
	var session = BattleSession.new(registry)
	session.create_battle("level.prototype_3v3", 31)
	var source: Dictionary = session.state["units_by_id"]["unit.player.warspite"]
	var target: Dictionary = session.state["units_by_id"]["unit.enemy.bismarck"]
	source["position"] = Vector2(500.0, 500.0)
	source["heading"] = 0.0
	target["position"] = Vector2(850.0, 500.0)
	target["heading"] = PI * 0.5
	target["current_speed"] = 40.0
	var weapon: Dictionary = registry.get_definition("weapons", "weapon.warspite_152_he")
	var weapon_state := _weapon_state(source, weapon["id"])
	var solution: Dictionary = session._automatic_aim_solution(source, target, weapon)
	_check((solution.get("position", target["position"]) as Vector2).y > float(target["position"].y), "automatic fire leads a moving target along its current velocity")
	session.delayed_attacks.clear()
	session.drain_events()
	session._fire_weapon(source, target, weapon_state, weapon, solution)
	_check(session.delayed_attacks.size() == int(weapon["mount_count"]) * int(weapon["shots_per_mount"]), "automatic gun fire creates one fixed-area attack per shell")
	var fixed_area_attacks := true
	var latest_resolve_time := 0.0
	for attack in session.delayed_attacks:
		fixed_area_attacks = fixed_area_attacks and str(attack.get("target_unit_id", "")) == "" and str(attack.get("aimed_target_unit_id", "")) == target["entity_id"] and typeof(attack.get("target_position")) == TYPE_VECTOR2
		latest_resolve_time = maxf(latest_resolve_time, float(attack.get("resolve_at_time", 0.0)))
	_check(fixed_area_attacks, "automatic shells retain the aimed target only as metadata and resolve against fixed world positions")
	var hp_before := float(target["current_hp"])
	target["position"] = Vector2(1900.0, 1500.0)
	session.state["elapsed_time"] = latest_resolve_time + 0.01
	session._resolve_delayed_attacks()
	_check(is_equal_approx(float(target["current_hp"]), hp_before), "a target that leaves the predicted impact area is not tracked or damaged")
	var fixed_miss_event := false
	var fired_event_exposes_impacts := false
	for event in session.drain_events():
		var result: Dictionary = event.get("damage_result", {})
		if event.get("event_type", "") == "WeaponFired" and event.get("impact_positions", []).size() == int(weapon["mount_count"]) * int(weapon["shots_per_mount"]):
			fired_event_exposes_impacts = true
		if event.get("event_type", "") == "AttackResolved" and result.get("hit_reason", "") == "NO_TARGET_IN_AREA" and typeof(result.get("impact_position")) == TYPE_VECTOR2:
			fixed_miss_event = true
	_check(fired_event_exposes_impacts, "weapon fire presentation receives the same per-shell fixed impact coordinates as the domain")
	_check(fixed_miss_event, "fixed-area misses expose their impact position for presentation")
	var replacement: Dictionary = session.state["units_by_id"]["unit.enemy.hindenburg"]
	replacement["position"] = Vector2(900.0, 700.0)
	var replacement_hp_before := float(replacement["current_hp"])
	session._resolve_attack({"attack_id":"attack.fixed.replacement","source_unit_id":source["entity_id"],"source_weapon_id":weapon["id"],"aimed_target_unit_id":target["entity_id"],"target_unit_id":"","target_position":replacement["position"],"impact_radius":float(weapon["impact_radius"]),"origin":source["position"],"accuracy_modifier":0.0}, true)
	_check(float(replacement["current_hp"]) < replacement_hp_before, "a different enemy entering the fixed impact area can receive the shell damage")


func _test_detection_and_contact_ghost() -> void:
	var session = BattleSession.new(registry)
	session.create_battle("level.prototype_1v1", 11)
	var player: Dictionary = session.state["units_by_id"]["unit.player.warspite"]
	var enemy: Dictionary = session.state["units_by_id"]["unit.enemy.bismarck"]
	player["position"] = Vector2(400.0, 350.0)
	enemy["position"] = Vector2(740.0, 350.0)
	player["movement_state"]["mode"] = "HoldPosition"
	enemy["movement_state"]["mode"] = "HoldPosition"
	session._update_detection(0.1)
	_check(session.state["visible_by_faction"]["player"].has(enemy["entity_id"]), "dual detection boundary acquires target")
	enemy["position"] = Vector2(1000.0, 350.0)
	session._update_detection(0.1)
	var contact: Dictionary = session.state["contacts_by_faction"]["player"].get(enemy["entity_id"], {})
	_check(not contact.is_empty() and not contact.get("visible", true), "lost target creates a last-known-position contact")
	for index in range(599): session._update_detection(0.1)
	_check(session.state["contacts_by_faction"]["player"].has(enemy["entity_id"]), "contact ghost remains before the one-minute cap")
	session._update_detection(0.1)
	_check(not session.state["contacts_by_faction"]["player"].has(enemy["entity_id"]), "contact ghost expires after the one-minute cap")
	enemy["position"] = Vector2(740.0, 350.0)
	session._update_detection(0.1)
	enemy["position"] = Vector2(1000.0, 350.0)
	session._update_detection(0.1)
	enemy["position"] = Vector2(740.0, 350.0)
	session._update_detection(0.1)
	contact = session.state["contacts_by_faction"]["player"].get(enemy["entity_id"], {})
	_check(not contact.is_empty() and bool(contact.get("visible", false)) and is_equal_approx(float(contact.get("ghost_remaining", -1.0)), 0.0), "rediscovered target replaces the contact ghost immediately")


func _test_torpedo_observation_rules() -> void:
	var surface_torpedo: Dictionary = registry.get_definition("projectiles", "projectile.surface_torpedo")
	var submarine_torpedo: Dictionary = registry.get_definition("projectiles", "projectile.submarine_torpedo")
	var air_torpedo: Dictionary = registry.get_definition("projectiles", "projectile.air_torpedo")
	_check(float(surface_torpedo.get("minimum_detection_distance", 0.0)) == 150.0, "surface torpedo loads its 150-unit observation baseline")
	_check(float(submarine_torpedo.get("minimum_detection_distance", 0.0)) == 120.0, "submarine torpedo keeps the shortest observation baseline")
	_check(float(air_torpedo.get("minimum_detection_distance", 0.0)) == 165.0, "air torpedo keeps the longest observation baseline")
	var session = BattleSession.new(registry)
	session.create_battle("level.prototype_1v1", 29)
	var observer: Dictionary = session.state["units_by_id"]["unit.player.warspite"]
	observer["position"] = Vector2(400.0, 350.0)
	var projectile := {
		"entity_id":"projectile.observation.base", "definition_id":"projectile.surface_torpedo",
		"source_unit_id":"unit.enemy.bismarck", "source_weapon_id":"weapon.test", "faction_id":"enemy",
		"position":Vector2(551.0, 350.0), "heading":PI, "speed":82.5, "collision_radius":12.0,
		"minimum_detection_distance":150.0, "remaining_range":600.0, "travelled_distance":0.0, "target_types":["Surface"]
	}
	session.state["projectiles_by_id"][projectile["entity_id"]] = projectile
	session._update_projectile_observation()
	_check(session.snapshot("player", false)["projectiles"].is_empty(), "enemy torpedo remains hidden just outside its minimum detection distance")
	_check(session.snapshot("enemy", false)["projectiles"].has(projectile["entity_id"]), "a faction always sees its own torpedo")
	session._event_buffer = []
	projectile["position"] = Vector2(550.0, 350.0)
	session._update_projectile_observation()
	_check(session.snapshot("player", false)["projectiles"].has(projectile["entity_id"]) and _has_event(session._event_buffer, "ProjectileDetected"), "a torpedo at the distance boundary is detected and shared to the faction snapshot")
	projectile["position"] = Vector2(900.0, 350.0)
	session._update_projectile_observation()
	_check(session.snapshot("player", false)["projectiles"].has(projectile["entity_id"]), "an observed enemy torpedo remains shared after leaving the observing ship's range")
	var skill: Dictionary = registry.get_definition("skills", "skill.fletcher_fleet_hunter_screen")
	var warning_effect: Dictionary = {}
	for effect in skill.get("effects", []):
		if effect.get("stat", "") == "TorpedoDetectionDistance": warning_effect = effect.duplicate(true)
	_check(float(warning_effect.get("value", 0.0)) == 60.0 and warning_effect.get("scope", "") == "Self", "Fletcher skill exposes a self-only 60-unit torpedo observation bonus")
	observer["status_effects"].append(warning_effect)
	var boosted_projectile: Dictionary = projectile.duplicate(true)
	boosted_projectile["entity_id"] = "projectile.observation.boosted"
	boosted_projectile["position"] = Vector2(605.0, 350.0)
	session.state["projectiles_by_id"][boosted_projectile["entity_id"]] = boosted_projectile
	session._update_projectile_observation()
	_check(session.snapshot("player", false)["projectiles"].has(boosted_projectile["entity_id"]), "self skill distance modifier detects every torpedo model through the common observation stat")
	var anshan: Dictionary = registry.get_definition("skills", "skill.anshan_escort_alert")
	var anshan_bonus := 0.0
	for effect in anshan.get("effects", []):
		if effect.get("stat", "") == "TorpedoDetectionDistance": anshan_bonus = float(effect.get("value", 0.0))
	_check(anshan_bonus == 90.0, "Anshan escort alert exposes the 90-unit character baseline")


func _test_damage_zero_floor() -> void:
	var source := {"entity_id":"source","position":Vector2.ZERO,"stats":{"gunnery_power":1.0},"status_effects":[]}
	var target := {"entity_id":"target","position":Vector2(10.0,0.0),"current_hp":100.0,"stats":{"armor":999.0,"armor_thickness":"Heavy","evasion":0.0},"status_effects":[]}
	var weapon := {"mount_type":"Gun","range":100.0,"accuracy_modifier":0.0,"armor_damage_modifiers":{"Heavy":0.1}}
	var formula := {"base_damage":1.0,"base_hit_rate":1.0,"power_coefficient":1.0,"armor_coefficient":1.0,"evasion_coefficient":0.0,"distance_penalty_coefficient":0.0,"hit_rate_min":1.0,"hit_rate_max":1.0}
	var result: Dictionary = DamageService.resolve({"attack_id":"zero"}, source, target, weapon, formula, SeededRandomSource.new(1), true)
	_check(float(result["final_damage"]) == 0.0 and float(result["target_hp_after"]) == 100.0, "armor can reduce damage to zero and later bonuses do not revive it")


func _test_simultaneous_flagship_victory() -> void:
	var session = BattleSession.new(registry)
	session.create_battle("level.prototype_1v1", 17)
	session.state["units_by_id"]["unit.player.warspite"]["life_state"] = "Sunk"
	session.state["units_by_id"]["unit.player.warspite"]["current_hp"] = 0.0
	session.state["units_by_id"]["unit.enemy.bismarck"]["life_state"] = "Sunk"
	session.state["units_by_id"]["unit.enemy.bismarck"]["current_hp"] = 0.0
	session._check_victory()
	_check(session.state["result"].get("winner_faction", "") == "player", "simultaneous flagship sinking awards player victory")


func _test_determinism() -> void:
	var first := _simulate("level.prototype_1v1", 2468, 3200)
	var second := _simulate("level.prototype_1v1", 2468, 3200)
	_check(first["result"] == second["result"], "same seed produces same battle result")
	_check(first["events"] == second["events"], "same seed produces identical event type sequence")
	_check(first["stats"] == second["stats"], "same seed produces identical analytics")


func _test_sinking_action_boundary() -> void:
	var session = BattleSession.new(registry)
	session.create_battle("level.prototype_harbor_3v3", 20260709)
	var source: Dictionary = session.state["units_by_id"]["unit.player.shimakaze"]
	var target: Dictionary = session.state["units_by_id"]["unit.enemy.kirov"]
	var ally: Dictionary = session.state["units_by_id"]["unit.player.aurora"]
	var facility_id := "facility.harbor.observation_west"
	source["position"] = session.facility_service.interaction_center(facility_id)
	session.facility_service.declare_control(facility_id, source)
	session.command_queue = [
		{"command_id":"pending.move", "command_type":"MoveUnits", "unit_id":source["entity_id"]},
		{"command_id":"other.move", "command_type":"MoveUnits", "unit_id":ally["entity_id"]},
	]
	session.delayed_attacks = [
		{"attack_id":"launched", "source_unit_id":source["entity_id"], "launch_at_time":0.0, "resolve_at_time":10.0},
		{"attack_id":"not_launched", "source_unit_id":source["entity_id"], "launch_at_time":10.0, "resolve_at_time":12.0},
	]
	session.state["projectiles_by_id"]["projectile.sunk_source"] = {"entity_id":"projectile.sunk_source", "source_unit_id":source["entity_id"], "position":source["position"]}
	ally["status_effects"] = [
		{"status_id":"persist", "source_unit_id":source["entity_id"], "end_on_source_sunk":false, "remaining":5.0},
		{"status_id":"dependent", "source_unit_id":source["entity_id"], "end_on_source_sunk":true, "remaining":5.0},
	]
	session.state["skill_effects_by_id"]["effect.persist"] = {"source_unit_id":source["entity_id"], "end_on_source_sunk":false, "remaining":5.0}
	session.state["skill_effects_by_id"]["effect.dependent"] = {"source_unit_id":source["entity_id"], "end_on_source_sunk":true, "remaining":5.0}
	session._sink_unit(source, target["entity_id"])
	_check(source["movement_state"]["mode"] == "HoldPosition" and source["ai_state"]["level_task"].is_empty() and source["player_facility_target_id"].is_empty(), "sinking stops navigation, AI, tasks, and player facility intent")
	_check(session.command_queue.size() == 1 and session.command_queue[0]["unit_id"] == ally["entity_id"] and session.facility_service.active_action_for_unit(source["entity_id"]).is_empty(), "sinking removes pending commands and facility work")
	_check(session.delayed_attacks.size() == 1 and session.delayed_attacks[0]["attack_id"] == "launched" and session.state["projectiles_by_id"].has("projectile.sunk_source"), "sinking cancels unlaunched attacks but preserves launched attacks and projectiles")
	_check(ally["status_effects"].size() == 1 and ally["status_effects"][0]["status_id"] == "persist" and session.state["skill_effects_by_id"].has("effect.persist") and not session.state["skill_effects_by_id"].has("effect.dependent"), "continuous effects obey their own source dependency")
	var hp_before := float(target["current_hp"])
	session._resolve_attack({"attack_id":"post_sink_hit", "source_unit_id":source["entity_id"], "source_weapon_id":"weapon.warspite_381_ap", "target_unit_id":target["entity_id"], "target_position":target["position"], "origin":source["position"], "source_status_effects":[]}, true)
	_check(float(target["current_hp"]) < hp_before, "ammunition launched before sinking can still hit through the shared attack resolver")


func _test_battle_smoke(level_id: String, maximum_ticks: int) -> void:
	var started := Time.get_ticks_msec()
	print("SMOKE_START %s" % level_id)
	var simulation := _simulate(level_id, 20260614, maximum_ticks)
	print("SMOKE_END %s phase=%s duration=%.1f wall_ms=%d" % [level_id, simulation["phase"], float(simulation.get("stats", {}).get("duration", 0.0)), Time.get_ticks_msec() - started])
	_check(simulation["phase"] == "Finished", "%s headless battle reaches Finished" % level_id)
	_check(not simulation["result"].is_empty(), "%s records a battle result" % level_id)
	_check(simulation["events"].has("WeaponFired") and simulation["events"].has("AttackResolved") and simulation["events"].has("BattleFinished"), "%s emits complete combat event chain" % level_id)


func _simulate(level_id: String, seed_value: int, maximum_ticks: int) -> Dictionary:
	var session = BattleSession.new(registry)
	var creation: Dictionary = session.create_battle(level_id, seed_value)
	var event_types: Array[String] = []
	for event in session.drain_events(): event_types.append(str(event["event_type"]))
	if not creation.get("ok", false): return {"phase":"Failed","result":{},"events":event_types,"stats":{}}
	for index in range(maximum_ticks):
		var events: Array = session.advance_tick(0.1)
		for event in events: event_types.append(str(event["event_type"]))
		if session.state["phase"] == "Finished": break
	return {"phase":session.state["phase"],"result":session.state["result"].duplicate(true),"events":event_types,"stats":session.get_statistics()}


func _has_event_reason(events: Array, event_type: String, reason_code: String) -> bool:
	for event in events:
		if event.get("event_type", "") == event_type and event.get("reason_code", "") == reason_code: return true
	return false


func _has_event(events: Array, event_type: String) -> bool:
	for event in events:
		if event.get("event_type", "") == event_type: return true
	return false


func _has_event_for_source(events: Array, event_type: String, source_unit_id: String) -> bool:
	for event in events:
		if event.get("event_type", "") == event_type and str(event.get("source_unit_id", event.get("unit_id", ""))) == source_unit_id:
			return true
	return false


func _weapon_state(unit: Dictionary, weapon_id: String) -> Dictionary:
	for weapon_state in unit.get("weapon_states", []):
		if weapon_state.get("definition_id", "") == weapon_id: return weapon_state
	return {}


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
