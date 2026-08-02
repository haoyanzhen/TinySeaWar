extends SceneTree

const ConfigRegistry = preload("res://scripts/infrastructure/data/config_registry.gd")
const BattleSession = preload("res://scripts/application/battle_session.gd")
const TerrainQueryService = preload("res://scripts/domain/services/terrain_query_service.gd")
const RoutePlanner = preload("res://scripts/application/navigation/route_planner.gd")

const TERRAIN_MASKS := [
	"ShipMovement",
	"TorpedoTravel",
	"ShellTravel",
	"SurfaceOpticalLineOfSight",
]

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = ConfigRegistry.new()
	_check(registry.load_all(), "configuration registry loads")
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
		_check(session.state.get("terrain_map", {}).get("id", "") == "terrain.map.%s_16x9" % coastal_id, "%s loads its authored 16:9 terrain map" % level_id)
		_check(not session.navigation_definition.is_empty(), "%s loads its navigation graph" % level_id)
		var terrain_map: Dictionary = session.state.get("terrain_map", {})
		var terrain_query = TerrainQueryService.new()
		terrain_query.configure(terrain_map)
		var visual_instances: Array = terrain_map.get("visual_instances", [])
		var visual_instance: Dictionary = visual_instances[0] if visual_instances.size() == 1 else {}
		_check(_as_vector2(terrain_map.get("map_size", [])).is_equal_approx(Vector2(6144.0, 3456.0)), "%s keeps the reviewed 6144 x 3456 map size" % level_id)
		_check(_as_vector2(visual_instance.get("position", [])).is_equal_approx(Vector2(3072.0, 1728.0)), "%s centers its coast on the ocean" % level_id)
		_check(_as_vector2(visual_instance.get("scale", [])).is_equal_approx(Vector2(2.6, 3.2)), "%s uses the reviewed 2.6 x 3.2 coast display scale" % level_id)
		if coastal_id == "ring_lagoon":
			var obstacles: Array = terrain_map.get("obstacles", [])
			var regions: Array = terrain_map.get("regions", [])
			_check(_horizontal_gap(obstacles, "land_01", "land_02") >= 727.0, "ring lagoon north entrance keeps the reviewed wide manual-control gap")
			_check(_horizontal_gap(obstacles, "land_04", "land_03") >= 727.0, "ring lagoon south entrance keeps the reviewed wide manual-control gap")
			_check(_passage_width(regions, "north_passage") >= 623.0 and _passage_width(regions, "south_passage") >= 623.0, "ring lagoon navigation channels remain inside both widened entrances")
			_check(obstacles.size() == 6, "ring lagoon hard geometry is split into six island sections around six entrances")
			_check(_minimum_passage_width(regions, "northwest_passage") >= 415.0 and _minimum_passage_width(regions, "northeast_passage") >= 415.0, "ring lagoon adds navigable northwest and northeast entrances")
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
			_check(all_match, "%s %s fleet uses reviewed terrain spawns" % [level_id, faction_id])
		_test_navigation_profiles(coastal_id, terrain_map, session.navigation_definition, terrain_query)
		_test_shore_queries(coastal_id, terrain_map, terrain_query)
	if failures.is_empty():
		print("PASS: %d coastal runtime checks" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAILED: %d of %d coastal runtime checks" % [failures.size(), checks])
		quit(1)


func _as_vector2(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


func _horizontal_gap(obstacles: Array, left_suffix: String, right_suffix: String) -> float:
	var left_max := -INF
	var right_min := INF
	for obstacle in obstacles:
		var obstacle_id := str(obstacle.get("id", ""))
		if obstacle_id.ends_with(left_suffix):
			for point in obstacle.get("polygon", []):
				left_max = maxf(left_max, _as_vector2(point).x)
		elif obstacle_id.ends_with(right_suffix):
			for point in obstacle.get("polygon", []):
				right_min = minf(right_min, _as_vector2(point).x)
	return right_min - left_max


func _passage_width(regions: Array, suffix: String) -> float:
	for region in regions:
		if str(region.get("id", "")).ends_with(suffix):
			var minimum := INF
			var maximum := -INF
			for point in region.get("polygon", []):
				var x := _as_vector2(point).x
				minimum = minf(minimum, x)
				maximum = maxf(maximum, x)
			return maximum - minimum
	return 0.0


func _minimum_passage_width(regions: Array, suffix: String) -> float:
	for region in regions:
		if str(region.get("id", "")).ends_with(suffix):
			var polygon: Array = region.get("polygon", [])
			var minimum := INF
			for index in polygon.size():
				var start := _as_vector2(polygon[index])
				var finish := _as_vector2(polygon[(index + 1) % polygon.size()])
				minimum = minf(minimum, start.distance_to(finish))
			return minimum
	return 0.0


func _test_navigation_profiles(coastal_id: String, terrain_map: Dictionary, navigation: Dictionary, terrain_query) -> void:
	var player_spawn := _spawn_position(terrain_map, "player_1")
	var enemy_spawn := _spawn_position(terrain_map, "enemy_1")
	for profile in navigation.get("profiles", []):
		var profile_id := str(profile.get("id", ""))
		var radius := float(profile.get("radius", 0.0))
		var movement_tags: Array = profile.get("movement_tags", [])
		var nodes_by_id := {}
		for node in profile.get("nodes", []):
			nodes_by_id[str(node.get("id", ""))] = node
		var invalid_edge := ""
		for node_id in nodes_by_id:
			var node: Dictionary = nodes_by_id[node_id]
			for neighbor_id in node.get("neighbors", []):
				if str(neighbor_id) <= str(node_id):
					continue
				var neighbor: Dictionary = nodes_by_id.get(str(neighbor_id), {})
				var edge_start := _as_vector2(node.get("position", Vector2.ZERO))
				var edge_end := _as_vector2(neighbor.get("position", Vector2.ZERO))
				if neighbor.is_empty() or not terrain_query.is_navigation_segment_clear(
					edge_start,
					edge_end,
					radius,
					movement_tags,
				):
					var hit: Dictionary = terrain_query.first_segment_hit(edge_start, edge_end, "ShipMovement", radius)
					invalid_edge = "%s -> %s (%s)" % [node_id, neighbor_id, hit]
					break
			if not invalid_edge.is_empty():
				break
		_check(invalid_edge.is_empty(), "%s %s baked edges remain exact-query legal: %s" % [coastal_id, profile_id, invalid_edge])
		var route: Dictionary = RoutePlanner.new().plan_path(
			terrain_query,
			navigation,
			player_spawn,
			enemy_spawn,
			radius,
			movement_tags,
		)
		var waypoints: Array = route.get("waypoints", [])
		_check(bool(route.get("ok", false)) and not waypoints.is_empty(), "%s %s connects the opposing approach areas" % [coastal_id, profile_id])
		var previous := player_spawn
		var all_segments_clear := true
		for raw_waypoint in waypoints:
			var waypoint := _as_vector2(raw_waypoint)
			all_segments_clear = all_segments_clear and terrain_query.is_movement_segment_clear(previous, waypoint, radius, movement_tags)
			previous = waypoint
		_check(all_segments_clear, "%s %s coarse route segments remain legal for its radius and draft" % [coastal_id, profile_id])
		_check(previous.distance_to(enemy_spawn) < 0.1, "%s %s route preserves its reviewed enemy attachment target" % [coastal_id, profile_id])


func _test_shore_queries(coastal_id: String, terrain_map: Dictionary, terrain_query) -> void:
	var obstacles: Array = terrain_map.get("obstacles", [])
	for obstacle in obstacles:
		var polygon: Array = obstacle.get("polygon", [])
		for edge_index in range(polygon.size()):
			var start := _as_vector2(polygon[edge_index])
			var finish := _as_vector2(polygon[(edge_index + 1) % polygon.size()])
			var edge := finish - start
			if edge.length() < 4.0:
				continue
			var midpoint := (start + finish) * 0.5
			var normal := Vector2(-edge.y, edge.x).normalized()
			var sample_distance := minf(48.0, edge.length() * 0.2)
			for mask in TERRAIN_MASKS:
				var hit: Dictionary = terrain_query.first_segment_hit(
					midpoint + normal * sample_distance,
					midpoint - normal * sample_distance,
					mask,
				)
				_check(
					bool(hit.get("hit", false))
					and str(hit.get("obstacle_id", "")) == str(obstacle.get("id", ""))
					and (_as_vector2(hit.get("normal", Vector2.ZERO))).length() > 0.9,
					"%s %s edge %d blocks %s with a stable shore normal" % [coastal_id, obstacle.get("id", "?"), edge_index, mask],
				)
	var open_start := _spawn_position(terrain_map, "player_1")
	var open_finish := _spawn_position(terrain_map, "player_2")
	for mask in TERRAIN_MASKS:
		_check(
			terrain_query.is_segment_clear(open_start, open_finish, mask),
			"%s deployment-side open water does not falsely block %s" % [coastal_id, mask],
		)


func _spawn_position(terrain_map: Dictionary, spawn_id: String) -> Vector2:
	for spawn in terrain_map.get("spawn_points", []):
		if spawn.get("id", "") == spawn_id:
			return _as_vector2(spawn.get("position", Vector2.ZERO))
	return Vector2.ZERO


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
