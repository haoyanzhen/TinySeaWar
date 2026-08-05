extends SceneTree

const ConfigRegistry = preload("res://scripts/infrastructure/data/config_registry.gd")
const BattleSession = preload("res://scripts/application/battle_session.gd")
const TerrainQueryService = preload("res://scripts/domain/services/terrain_query_service.gd")
const TerrainCollisionFieldLoader = preload("res://scripts/infrastructure/data/terrain_collision_field_loader.gd")
const TerrainCollisionField = preload("res://scripts/domain/services/terrain_collision_field.gd")
const TrajectoryPlanner = preload("res://scripts/application/navigation/trajectory_planner.gd")
const ShipMotionService = preload("res://scripts/domain/services/ship_motion_service.gd")

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = ConfigRegistry.new()
	_check(registry.load_all(), "configuration registry loads collision-field definitions")
	_test_all_fields_load(registry)
	_test_fixed_tick_motion_expansion()
	_test_player_fast_turn_then_straight()
	_test_motion_context_equivalence(registry)
	_test_continuous_nearshore_fixtures()
	_test_region_restriction_masks()
	_test_corrupt_field_fallback(registry)
	_test_collision_immediately_invalidates_plan(registry)
	if failures.is_empty():
		print("PASS: %d collision-field and continuous-trajectory checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error("FAIL: %s" % failure)
		print("FAILED: %d of %d collision-field and continuous-trajectory checks" % [failures.size(), checks])
		quit(1)


func _test_all_fields_load(registry) -> void:
	var loader = TerrainCollisionFieldLoader.new()
	var definitions: Array = registry.all("collision_fields")
	var first_loaded_field = null
	_check(definitions.size() == 20, "all 20 terrain maps have collision fields")
	for definition in definitions:
		var terrain: Dictionary = registry.get_definition("terrain", str(definition.get("terrain_definition_id", "")))
		var result := loader.load_field(definition, terrain)
		_check(bool(result.get("ok", false)), "collision field loads with checksum and revision: %s" % definition.get("id", "?"))
		if first_loaded_field == null and bool(result.get("ok", false)):
			first_loaded_field = result.get("field")
	if first_loaded_field != null:
		var stationary: Dictionary = first_loaded_field.query_trajectory_samples([{"position":Vector2(0.5, 0.5)}, {"position":Vector2(0.5, 0.5)}], 20.0)
		_check(int(stationary.get("definitely_clear", PackedByteArray())[0]) == 0, "stationary trajectory samples still validate boundary clearance")


func _test_fixed_tick_motion_expansion() -> void:
	var initial := {"position":Vector2(120.0, 180.0), "heading":0.25, "speed":18.0, "maximum_speed":42.0, "base_maximum_speed":42.0, "reverse_speed":10.5, "acceleration":32.0, "braking":64.0, "turn_rate_limit":0.7, "current_vector":Vector2(2.0, -1.0)}
	var controls := [{"duration":0.4, "thrust_ratio":1.0, "turn_ratio":1.0}, {"duration":0.6, "thrust_ratio":0.5, "turn_ratio":0.0}]
	_assert_motion_case("full turn and partial thrust", initial, controls, 1.0, func(_position): return {"current_vector":Vector2(2.0, -1.0), "movement_speed_multiplier":1.0})
	var stationary_initial := initial.duplicate(true)
	stationary_initial["speed"] = 0.0
	_assert_motion_case("stationary full-thrust start", stationary_initial, [{"duration":1.0, "thrust_ratio":1.0, "turn_ratio":0.0}], 1.0, func(_position): return {"current_vector":Vector2.ZERO, "movement_speed_multiplier":1.0})
	var reverse_initial := initial.duplicate(true)
	reverse_initial["speed"] = 38.0
	_assert_motion_case("brake then reverse", reverse_initial, [{"duration":0.6, "thrust_ratio":0.0, "turn_ratio":-0.5}, {"duration":0.8, "thrust_ratio":-1.0, "turn_ratio":0.25}], 1.4, func(_position): return {"current_vector":Vector2.ZERO, "movement_speed_multiplier":1.0})
	_assert_motion_case("current and movement multiplier changes", initial, [{"duration":1.6, "thrust_ratio":1.0, "turn_ratio":-1.0}], 1.6, func(position): return {"current_vector":Vector2(3.0, -2.0) if position.x < 145.0 else Vector2(-1.0, 4.0), "movement_speed_multiplier":0.82 if position.y < 190.0 else 1.08})


func _test_player_fast_turn_then_straight() -> void:
	var planner = TrajectoryPlanner.new()
	var state := {"position":Vector2(500.0, 500.0), "heading":0.0, "speed":20.0, "maximum_speed":50.0, "base_maximum_speed":50.0, "reverse_speed":12.5, "acceleration":50.0, "braking":100.0, "turn_rate_limit":1.0, "current_vector":Vector2.ZERO, "map_width":2000.0, "map_height":1200.0, "previous_control":{"thrust_ratio":0.0, "turn_ratio":0.0}}
	var goal: Vector2 = (state["position"] as Vector2) + Vector2.RIGHT.rotated(0.55) * 700.0
	var result := planner.plan_normal(state, goal, 20.0, ["Surface"], null, null, [], false, [], true)
	var controls: Array = result.get("controls", [])
	_check(bool(result.get("ok", false)) and str(result.get("candidate_id", "")) == "player_fast_direct", "player target prioritizes the safe full-speed direct template")
	_check(controls.size() >= 2 and is_equal_approx(float(controls[0].get("thrust_ratio", 0.0)), 1.0) and absf(float(controls[0].get("turn_ratio", 0.0))) >= 0.99, "player route starts with full propulsion and maximum useful rudder")
	_check(is_equal_approx(float(controls[-1].get("thrust_ratio", 0.0)), 1.0) and absf(float(controls[-1].get("turn_ratio", 1.0))) <= 0.001, "player route changes to full-speed straight travel after alignment")
	var long_turn_controls: Array = planner._turn_then_straight_controls(1.8, 1.0, 1.0)
	_check(float(long_turn_controls[0].get("duration", 0.0)) >= 1.79 and absf(float(long_turn_controls[0].get("turn_ratio", 0.0))) >= 0.99, "player prediction keeps maximum rudder beyond one planning interval when alignment needs it")
	_check(absf(float(long_turn_controls[-1].get("turn_ratio", 1.0))) <= 0.001 and is_equal_approx(float(long_turn_controls[-1].get("thrust_ratio", 0.0)), 1.0), "long player turns still transition to full-speed straight travel")


func _test_motion_context_equivalence(registry) -> void:
	var session = BattleSession.new(registry)
	_check(session.create_battle("level.prototype_harbor_3v3", 20260803).get("ok", false), "motion-context equivalence fixture starts")
	for zone in session.terrain_context_service.zones:
		var polygon: PackedVector2Array = zone.get("base_polygon_packed", PackedVector2Array())
		if polygon.is_empty():
			continue
		var position: Vector2 = zone.get("position", Vector2.ZERO)
		for point in polygon:
			position += point / float(polygon.size())
		var complete: Dictionary = session.terrain_context_service.context_at(position)
		var motion: Dictionary = session.terrain_context_service.motion_context_at(position)
		var same_motion := (complete.get("current_vector", Vector2.ZERO) as Vector2).distance_to(motion.get("current_vector", Vector2.ZERO)) <= 0.0001
		same_motion = same_motion and is_equal_approx(float(complete.get("movement_speed_multiplier", 1.0)), float(motion.get("movement_speed_multiplier", 1.0)))
		same_motion = same_motion and int(complete.get("sea_state", 0)) == int(motion.get("sea_state", 0))
		_check(same_motion, "lightweight motion context matches complete context at %s" % zone.get("id", "?"))


func _test_continuous_nearshore_fixtures() -> void:
	var terrain = TerrainQueryService.new()
	terrain.configure({
		"id":"terrain.fixture.continuous", "map_size":[1000.0, 800.0], "obstacles":[
			{"id":"fixture.land", "block_mask":["ShipMovement"], "polygon":[[420.0, 250.0], [620.0, 250.0], [620.0, 550.0], [420.0, 550.0]]},
		], "regions":[],
	})
	var planner = TrajectoryPlanner.new()
	var fixtures := [
		{"position":Vector2(330.0, 610.0), "heading":0.0, "speed":70.0, "goal":Vector2(760.0, 330.0)},
		{"position":Vector2(360.0, 190.0), "heading":PI * 0.5, "speed":62.0, "goal":Vector2(700.0, 620.0)},
		{"position":Vector2(690.0, 600.0), "heading":PI, "speed":75.0, "goal":Vector2(300.0, 320.0)},
	]
	for fixture_index in range(fixtures.size()):
		var fixture: Dictionary = fixtures[fixture_index]
		var state := {"position":fixture["position"], "heading":fixture["heading"], "speed":fixture["speed"], "maximum_speed":80.0, "base_maximum_speed":80.0, "reverse_speed":20.0, "acceleration":40.0, "braking":90.0, "turn_rate_limit":0.65, "current_vector":Vector2.ZERO, "map_width":1000.0, "map_height":800.0, "previous_control":{"thrust_ratio":1.0, "turn_ratio":0.0}}
		var result := planner.plan_normal(state, fixture["goal"], 30.0, ["Surface"], terrain, null, [], false, [], true)
		_check(bool(result.get("ok", false)), "nearshore fixture %d finds a safe alternative" % (fixture_index + 1))
		var samples: Array = result.get("predicted_samples", [])
		var continuously_clear := true
		for sample_index in range(1, samples.size()):
			var start: Vector2 = samples[sample_index - 1].get("position", Vector2.ZERO)
			var finish: Vector2 = samples[sample_index].get("position", Vector2.ZERO)
			if not terrain.is_movement_segment_clear(start, finish, 34.0, ["Surface"]):
				continuously_clear = false
				break
		_check(continuously_clear, "nearshore fixture %d validates every fixed-tick swept hull segment" % (fixture_index + 1))
	var margin_stationary: Dictionary = terrain.validate_movement_trajectory([{"position":Vector2(389.0, 400.0)}, {"position":Vector2(389.0, 400.0)}], 30.0, ["Surface"], 4.0)
	_check(str(margin_stationary.get("status", "")) == "ExactClear", "a Domain-legal stationary hull inside only the soft navigation margin remains a safe fallback")
	var margin_departure: Dictionary = terrain.validate_movement_trajectory([{"position":Vector2(389.0, 400.0)}, {"position":Vector2(387.0, 400.0)}], 30.0, ["Surface"], 4.0)
	_check(str(margin_departure.get("status", "")) == "ExactClear", "a Domain-legal hull may depart outward from the soft navigation margin over a short fixed-Tick segment")
	var margin_entry: Dictionary = terrain.validate_movement_trajectory([{"position":Vector2(389.0, 400.0)}, {"position":Vector2(391.0, 400.0)}], 30.0, ["Surface"], 4.0)
	_check(str(margin_entry.get("status", "")) == "Collides", "the soft navigation margin still rejects a short segment that moves toward land")


func _test_region_restriction_masks() -> void:
	var field = TerrainCollisionField.new()
	var distances := PackedByteArray()
	distances.resize(8)
	distances.fill(255)
	_check(field.configure({"terrain_definition_id":"terrain.fixture.region_mask", "navigation_revision":1, "map_size":Vector2(200.0, 200.0), "cell_size":100.0, "grid_size":Vector2i(2, 2)}, PackedByteArray([0]), distances, PackedByteArray([0, 1, 0, 0])), "restriction-field fixture configures")
	var terrain = TerrainQueryService.new()
	terrain.configure({
		"id":"terrain.fixture.region_mask", "map_size":[200.0, 200.0], "obstacles":[], "regions":[
			{"id":"fixture.shallow", "region_type":"ShallowWater", "priority":10, "polygon":[[100.0, 0.0], [200.0, 0.0], [200.0, 100.0], [100.0, 100.0]]},
		],
	}, field)
	var crossing_samples := [{"position":Vector2(50.0, 50.0)}, {"position":Vector2(150.0, 50.0)}]
	var deep_draft := terrain.validate_movement_trajectory(crossing_samples, 20.0, ["Surface"])
	var shallow_draft := terrain.validate_movement_trajectory(crossing_samples, 20.0, ["Surface", "ShallowDraft"])
	var open_water := terrain.validate_movement_trajectory([{"position":Vector2(20.0, 150.0)}, {"position":Vector2(80.0, 150.0)}], 20.0, ["Surface"])
	var diagnostics := terrain.collision_field_diagnostics()
	_check(str(deep_draft.get("status", "")) == "Collides" and str(deep_draft.get("hit", {}).get("obstacle_id", "")) == "water_access", "collision-field restriction mask keeps shallow water illegal for deep-draft movement")
	_check(str(shallow_draft.get("status", "")) == "DefinitelyClear", "movement tags can prove a shallow-water segment legal without polygon sampling")
	_check(str(open_water.get("status", "")) == "DefinitelyClear" and int(diagnostics.get("collision_field_region_definitely_clear", 0)) >= 2, "open-water restriction masks skip exact region sampling")
	var exact_fallback = TerrainQueryService.new()
	exact_fallback.configure(terrain.terrain_definition)
	_check(str(exact_fallback.validate_movement_trajectory(crossing_samples, 20.0, ["Surface"]).get("status", "")) == "Collides", "missing fields preserve authoritative shallow-water fallback")


func _test_corrupt_field_fallback(registry) -> void:
	var collision_id := "collision_field.terrain.map.harbor_mouth_16x9"
	var original: Dictionary = registry.get_definition("collision_fields", collision_id).duplicate(true)
	var terrain: Dictionary = registry.get_definition("terrain", str(original.get("terrain_definition_id", "")))
	var loader = TerrainCollisionFieldLoader.new()
	var original_bytes := FileAccess.get_file_as_bytes(str(original.get("path", "")))
	_check(str(loader.load_field({}, terrain).get("reason_code", "")) == "MISSING_COLLISION_FIELD_DEFINITION", "missing collision fields have a stable fallback reason")
	var corrupted_path := "res://artifacts/simulations/terrain_collision_field_corrupted.tscf"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/simulations"))
	var bad_magic_bytes := original_bytes.duplicate()
	bad_magic_bytes[0] = 66
	bad_magic_bytes[1] = 65
	bad_magic_bytes[2] = 68
	bad_magic_bytes[3] = 33
	if not _write_bytes(corrupted_path, bad_magic_bytes):
		_check(false, "corrupt-field fixture can create its temporary file")
		return
	var corrupted := original.duplicate(true)
	corrupted["path"] = corrupted_path
	corrupted["file_checksum"] = _sha256(FileAccess.get_file_as_bytes(corrupted_path))
	_check(str(loader.load_field(corrupted, terrain).get("reason_code", "")) == "COLLISION_FIELD_BAD_MAGIC", "bad collision-field magic has a stable failure reason")
	var unsupported_bytes := original_bytes.duplicate()
	unsupported_bytes[4] = 99
	unsupported_bytes[5] = 0
	_write_bytes(corrupted_path, unsupported_bytes)
	corrupted["file_checksum"] = _sha256(unsupported_bytes)
	_check(str(loader.load_field(corrupted, terrain).get("reason_code", "")) == "COLLISION_FIELD_UNSUPPORTED_VERSION", "unknown collision-field versions are rejected")
	var truncated_bytes := original_bytes.slice(0, 48)
	_write_bytes(corrupted_path, truncated_bytes)
	corrupted["file_checksum"] = _sha256(truncated_bytes)
	_check(str(loader.load_field(corrupted, terrain).get("reason_code", "")) in ["COLLISION_FIELD_INVALID_LENGTH", "COLLISION_FIELD_TRAILING_OR_TRUNCATED_DATA"], "truncated collision-field payloads are rejected")
	var invalid_length_bytes := original_bytes.duplicate()
	invalid_length_bytes[98] = 0
	invalid_length_bytes[99] = 0
	invalid_length_bytes[100] = 0
	invalid_length_bytes[101] = 0
	_write_bytes(corrupted_path, invalid_length_bytes)
	corrupted["file_checksum"] = _sha256(invalid_length_bytes)
	_check(str(loader.load_field(corrupted, terrain).get("reason_code", "")) == "COLLISION_FIELD_PAYLOAD_SIZE_MISMATCH", "illegal collision-field payload offsets are rejected")
	var payload_corrupted_bytes := original_bytes.duplicate()
	payload_corrupted_bytes[-1] = int(payload_corrupted_bytes[-1]) ^ 1
	_write_bytes(corrupted_path, payload_corrupted_bytes)
	corrupted["file_checksum"] = _sha256(payload_corrupted_bytes)
	_check(str(loader.load_field(corrupted, terrain).get("reason_code", "")) == "COLLISION_FIELD_PAYLOAD_CHECKSUM_MISMATCH", "collision-field payload checksum mismatches are rejected")
	corrupted["file_checksum"] = str(original.get("file_checksum", ""))
	_check(str(loader.load_field(corrupted, terrain).get("reason_code", "")) == "COLLISION_FIELD_FILE_CHECKSUM_MISMATCH", "collision-field file checksum mismatches are rejected before parsing")
	var stale_revision := original.duplicate(true)
	stale_revision["navigation_revision"] = int(stale_revision.get("navigation_revision", 0)) + 1
	_check(str(loader.load_field(stale_revision, terrain).get("reason_code", "")) == "COLLISION_FIELD_REVISION_MISMATCH", "stale collision-field navigation revisions are rejected")
	var changed_map_size := terrain.duplicate(true)
	changed_map_size["map_size"][0] = float(changed_map_size["map_size"][0]) + 8.0
	_check(str(loader.load_field(original, changed_map_size).get("reason_code", "")) == "COLLISION_FIELD_MAP_SIZE_MISMATCH", "changed map dimensions invalidate the old collision field")
	var changed_terrain := terrain.duplicate(true)
	changed_terrain["obstacles"][0]["polygon"][0][0] = float(changed_terrain["obstacles"][0]["polygon"][0][0]) + 1.0
	_check(str(loader.load_field(original, changed_terrain).get("reason_code", "")) == "COLLISION_FIELD_SOURCE_CHECKSUM_MISMATCH", "changed rule geometry invalidates the old collision field")
	var visual_only_change := terrain.duplicate(true)
	visual_only_change["visual_regions"].append({"id":"validation.visual_only", "polygon":[[0.0, 0.0], [1.0, 0.0], [0.0, 1.0]]})
	_check(loader.source_geometry_checksum(visual_only_change) == loader.source_geometry_checksum(terrain), "visual-only data does not change the collision-field rule checksum")
	var restricted_region_change := terrain.duplicate(true)
	var restricted_region_index: int = restricted_region_change.get("regions", []).find_custom(func(region): return str(region.get("region_type", "")) in ["ShallowWater", "ReefOrSandbar"])
	if restricted_region_index >= 0:
		restricted_region_change["regions"][restricted_region_index]["polygon"][0][0] = float(restricted_region_change["regions"][restricted_region_index]["polygon"][0][0]) + 1.0
		_check(loader.source_geometry_checksum(restricted_region_change) != loader.source_geometry_checksum(terrain), "restricted-water geometry changes invalidate the collision field")
	_write_bytes(corrupted_path, bad_magic_bytes)
	corrupted["file_checksum"] = _sha256(FileAccess.get_file_as_bytes(corrupted_path))
	registry.definitions["collision_fields"][collision_id] = corrupted
	var session = BattleSession.new(registry)
	var creation := session.create_battle("level.prototype_harbor_3v3", 20260803)
	_check(bool(creation.get("ok", false)), "corrupt collision field deterministically falls back without blocking battle creation")
	_check(not session.terrain_query.collision_field_available(), "corrupt collision field fallback uses exact polygon queries")
	_check(session.drain_events().any(func(event): return str(event.get("event_type", "")) == "TerrainCollisionFieldUnavailable" and str(event.get("reason_code", "")) == "COLLISION_FIELD_BAD_MAGIC"), "corrupt field fallback emits a stable reason")
	var fallback_stationary: Dictionary = session.terrain_query.validate_movement_trajectory([{"position":Vector2(0.5, 0.5)}, {"position":Vector2(0.5, 0.5)}], 20.0, ["Surface"])
	_check(str(fallback_stationary.get("status", "")) == "Collides", "exact fallback still rejects a stationary sample inside boundary clearance")
	registry.definitions["collision_fields"][collision_id] = original
	DirAccess.remove_absolute(ProjectSettings.globalize_path(corrupted_path))


func _test_collision_immediately_invalidates_plan(registry) -> void:
	var session = BattleSession.new(registry)
	_check(session.create_battle("level.prototype_harbor_3v3", 20260803).get("ok", false), "collision invalidation fixture starts")
	var unit: Dictionary = session.state["units_by_id"]["unit.player.shimakaze"]
	var radius := float(unit.get("stats", {}).get("collision_radius", 20.0))
	unit["position"] = Vector2(radius + 0.2, 900.0)
	unit["heading"] = PI
	unit["current_speed"] = float(unit.get("stats", {}).get("speed", 60.0))
	unit["movement_state"] = session._new_movement_state("PlayerMoveOrder", Vector2(500.0, 900.0), [Vector2(500.0, 900.0)])
	unit["navigation_state"]["trajectory_plan"] = {"ok":true, "candidate_id":"injected_unsafe", "planned_at_tick":session.state.get("tick_index", 0), "terrain_revision":int(session.state.get("terrain_map", {}).get("navigation_revision", 0)), "controls":[{"duration":1.0, "thrust_ratio":1.0, "turn_ratio":0.0}]}
	unit["navigation_state"]["current_control"] = {"thrust_ratio":1.0, "turn_ratio":0.0}
	session._update_movement(0.1)
	var navigation: Dictionary = unit["navigation_state"]
	_check(navigation.get("trajectory_plan", {}).is_empty() and is_zero_approx(float(navigation.get("current_control", {}).get("thrust_ratio", 1.0))), "terrain collision immediately invalidates the dangerous plan and control")
	_check(int(navigation.get("next_normal_plan_tick", -1)) == int(session.state.get("tick_index", 0)) + 1 and navigation.has("last_collision"), "terrain collision schedules recovery on the next executable tick with collision facts")
	_check(session.drain_events().any(func(event): return str(event.get("event_type", "")) == "NavigationCollisionContractViolated"), "an intentionally unsafe committed plan triggers the collision contract diagnostic")


func _sha256(value: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(value)
	return context.finish().hex_encode()


func _assert_motion_case(label: String, initial: Dictionary, controls: Array, horizon: float, context_sampler: Callable) -> void:
	var samples := ShipMotionService.simulate_control_sequence(initial, controls, 0.1, horizon, context_sampler)
	var stepped := initial.duplicate(true)
	var consistent := samples.size() == roundi(horizon / 0.1) + 1
	for tick_index in range(1, samples.size()):
		var context: Dictionary = context_sampler.call(stepped.get("position", Vector2.ZERO))
		stepped["current_vector"] = context.get("current_vector", stepped.get("current_vector", Vector2.ZERO))
		stepped["maximum_speed"] = float(stepped.get("base_maximum_speed", stepped.get("maximum_speed", 0.0))) * float(context.get("movement_speed_multiplier", 1.0))
		stepped = ShipMotionService.step(stepped, _control_at_elapsed(controls, float(tick_index - 1) * 0.1), 0.1)
		var sample: Dictionary = samples[tick_index]
		consistent = consistent and (sample.get("position", Vector2.ZERO) as Vector2).distance_to(stepped.get("position", Vector2.ZERO)) <= 0.0001
		consistent = consistent and absf(float(sample.get("heading", 0.0)) - float(stepped.get("heading", 0.0))) <= 0.0001
		consistent = consistent and absf(float(sample.get("speed", 0.0)) - float(stepped.get("speed", 0.0))) <= 0.0001
	_check(consistent, "%s prediction matches every Domain fixed Tick" % label)


func _control_at_elapsed(controls: Array, elapsed: float) -> Dictionary:
	var boundary := 0.0
	for index in range(controls.size()):
		boundary += float(controls[index].get("duration", 0.0))
		if elapsed < boundary - 0.000001 or index == controls.size() - 1:
			return controls[index]
	return controls[-1] if not controls.is_empty() else {"thrust_ratio":0.0, "turn_ratio":0.0}


func _write_bytes(path: String, value: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(value)
	file.close()
	return true


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
