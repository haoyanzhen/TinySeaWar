extends RefCounted

const MATCHING_ID := "custom.matching.default"
const SCALES := {1: 12, 3: 22, 5: 34, 11: 64}


static func validate(rosters: Array, matching: Dictionary, ships: Dictionary, profiles: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not matching.get("cost_caps", null) is Dictionary or not matching.get("difficulties", null) is Dictionary:
		return ["CUSTOM_MATCHING_SHAPE_INVALID"]
	if not _positive_integer(matching.get("pool_version", 0)):
		errors.append("CUSTOM_POOL_VERSION_INVALID")
	for size in SCALES:
		if not _positive_integer(matching.cost_caps.get(str(size), 0)) or int(matching.cost_caps.get(str(size), 0)) != SCALES[size]: errors.append("CUSTOM_COST_CAP_INVALID")
	for difficulty in ["Easy", "Standard", "Hard"]:
		if not matching.difficulties.get(difficulty, null) is Dictionary:
			errors.append("CUSTOM_DIFFICULTY_RANGE_INVALID")
			continue
		var policy: Dictionary = matching.difficulties[difficulty]
		var low := int(policy.get("lower_percent", 0))
		var high := int(policy.get("upper_percent", 0))
		if not _positive_integer(policy.get("lower_percent", 0)) or not _positive_integer(policy.get("upper_percent", 0)) or low <= 0 or high < low: errors.append("CUSTOM_DIFFICULTY_RANGE_INVALID")
		if str(profiles.get(str(policy.get("enemy_ai_profile_id", "")), {}).get("difficulty", "")) != difficulty: errors.append("CUSTOM_AI_PROFILE_INVALID")
	var ids := {}
	var member_sets := {}
	for roster in rosters:
		if not roster is Dictionary or not roster.get("ship_ids", null) is Array:
			errors.append("CUSTOM_ROSTER_SHAPE_INVALID")
			continue
		var id := str(roster.get("id", ""))
		if id.is_empty() or ids.has(id) or str(roster.get("display_name", "")).is_empty(): errors.append("CUSTOM_ROSTER_ID_INVALID")
		ids[id] = true
		var size := int(roster.get("unit_count", 0))
		var members: Array = roster.get("ship_ids", [])
		if not _positive_integer(roster.get("unit_count", 0)) or size not in SCALES or members.size() != size: errors.append("CUSTOM_ROSTER_SIZE_INVALID")
		var unique := {}
		var cost := 0
		for ship_id in members:
			if not ship_id is String: errors.append("CUSTOM_ROSTER_SHIP_MISSING"); continue
			if unique.has(ship_id): errors.append("CUSTOM_ROSTER_DUPLICATE_SHIP")
			unique[ship_id] = true
			if not ships.has(ship_id): errors.append("CUSTOM_ROSTER_SHIP_MISSING")
			cost += int(ships.get(ship_id, {}).get("cost", 0))
		if cost <= 0 or cost > int(SCALES.get(size, 0)): errors.append("CUSTOM_ROSTER_COST_INVALID")
		if str(roster.get("flagship_ship_id", "")) not in members: errors.append("CUSTOM_ROSTER_FLAGSHIP_INVALID")
		var sorted_members := members.duplicate()
		sorted_members.sort()
		var key := JSON.stringify(sorted_members)
		if member_sets.has(key): errors.append("CUSTOM_ROSTER_DUPLICATE_SET")
		member_sets[key] = true
	return errors


static func _positive_integer(value) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]: return false
	return is_finite(float(value)) and float(value) > 0 and float(value) == floor(float(value))
