extends RefCounted

const Catalog = preload("res://scripts/infrastructure/data/custom_battle_catalog.gd")
const TerrainQuery = preload("res://scripts/domain/services/terrain_query_service.gd")

var registry

func _init(config_registry) -> void:
	registry = config_registry


func cost_interval(count: int, player_cost: int, difficulty: String) -> Dictionary:
	var settings: Dictionary = registry.get_definition("custom_matching", Catalog.MATCHING_ID)
	var policy: Dictionary = settings.get("difficulties", {}).get(difficulty, {})
	var cap := int(settings.get("cost_caps", {}).get(str(count), 0))
	if policy.is_empty() or cap == 0: return {"ok":false, "error":"CUSTOM_DIFFICULTY_OR_SCALE_INVALID"}
	var costs: Array = registry.all("ships").map(func(ship): return int(ship.cost))
	costs.sort()
	var minimum := 0
	for index in range(count): minimum += costs[index]
	if player_cost < minimum or player_cost > cap: return {"ok":false, "error":"CUSTOM_PLAYER_COST_INVALID"}
	var lower := clampi(int(ceil(float(player_cost * int(policy.lower_percent)) / 100.0)), minimum, cap)
	var upper := maxi(lower, mini(cap, int(floor(float(player_cost * int(policy.upper_percent)) / 100.0))))
	return {"ok":true, "lower":lower, "upper":upper, "player_cost":player_cost, "unit_count":count, "difficulty":difficulty, "enemy_ai_profile_id":policy.enemy_ai_profile_id, "pool_version":settings.pool_version}


func fleet_cost(ship_ids: Array) -> int:
	var result := 0
	for id in ship_ids: result += int(registry.get_definition("ships", str(id)).get("cost", 0))
	return result


func spawns_legal(ship_ids: Array, slots: Array, map: Dictionary) -> bool:
	if slots.size() < ship_ids.size(): return false
	var query = TerrainQuery.new()
	var terrain_id := str(map.get("terrain_definition_id", ""))
	var terrain: Dictionary = registry.get_definition("terrain", terrain_id)
	if not terrain_id.is_empty() and terrain.is_empty(): return false
	query.configure(terrain if not terrain.is_empty() else {"map_size":[map.get("width", 0), map.get("height", 0)]})
	var positions: Array[Vector2] = []
	var radii: Array[float] = []
	for index in range(ship_ids.size()):
		var ship: Dictionary = registry.get_definition("ships", str(ship_ids[index]))
		var raw: Array = slots[index].get("position", [])
		if ship.is_empty() or raw.size() != 2: return false
		var position := Vector2(float(raw[0]), float(raw[1]))
		var radius := float(ship.get("collision_radius", 0))
		var tags: Array = ["Surface"]
		if ship.get("ship_class", "") in ["Destroyer", "LightCruiser"]: tags.append("ShallowDraft")
		if not query.can_occupy_circle(position, radius, tags): return false
		for previous in range(positions.size()):
			if position.distance_to(positions[previous]) <= radius + radii[previous]: return false
		positions.append(position)
		radii.append(radius)
	return true


func choose(count: int, player_cost: int, difficulty: String, slots: Array, map: Dictionary, roster_seed: int) -> Dictionary:
	var result := cost_interval(count, player_cost, difficulty)
	if not result.ok: return result
	var candidates: Array = []
	var spawn_rejections := 0
	for roster in registry.all("custom_rosters"):
		if int(roster.unit_count) != count: continue
		var cost := fleet_cost(roster.ship_ids)
		if cost < result.lower or cost > result.upper: continue
		if not spawns_legal(roster.ship_ids, slots, map):
			spawn_rejections += 1
			continue
		candidates.append(roster)
	result["candidate_count"] = candidates.size()
	result["spawn_rejections"] = spawn_rejections
	result["candidate_ids"] = candidates.map(func(roster): return str(roster.id))
	if candidates.is_empty():
		result["ok"] = false
		result["error"] = "CUSTOM_NO_ENEMY_ROSTER"
		return result
	var rng := RandomNumberGenerator.new()
	rng.seed = roster_seed
	var chosen: Dictionary = candidates[rng.randi_range(0, candidates.size() - 1)]
	result["roster"] = chosen.duplicate(true)
	result["enemy_cost"] = fleet_cost(chosen.ship_ids)
	result["roster_seed"] = roster_seed
	return result
