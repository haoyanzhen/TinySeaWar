extends SceneTree

const ConfigRegistry = preload("res://scripts/infrastructure/data/config_registry.gd")
const BattleSession = preload("res://scripts/application/battle_session.gd")

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
		_check(session.state.get("terrain_map", {}).get("id", "") == "terrain.map.%s" % coastal_id, "%s loads its authored terrain map" % level_id)
		_check(not session.navigation_definition.is_empty(), "%s loads its navigation graph" % level_id)
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


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
