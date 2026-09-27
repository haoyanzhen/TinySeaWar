extends RefCounted

const CATEGORIES := ["DefaultOwned", "TutorialReward", "ChallengeReward", "Pending"]
const CATALOG_ID := "progress.ship_acquisition"


static func validate(catalog: Dictionary, ships: Dictionary, levels: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if catalog.is_empty() or catalog.get("ships") is not Array:
		errors.append("Ship acquisition catalog is missing or invalid")
		return errors
	var planned = catalog.get("planned_challenge_level_ids")
	if planned is not Array:
		errors.append("Planned challenge ids must be an array")
		return errors
	var pattern := RegEx.new()
	pattern.compile("^level\\.challenge\\.[ml]0[1-5]$")
	var planned_seen := {}
	for id in planned:
		if id is not String or pattern.search(str(id)) == null or planned_seen.has(id):
			errors.append("Invalid or duplicate planned challenge id: %s" % id)
		planned_seen[id] = true
	var seen := {}
	for entry in catalog["ships"]:
		if entry is not Dictionary:
			errors.append("Ship acquisition entry must be an object")
			continue
		var ship_id := str(entry.get("ship_id", ""))
		var category := str(entry.get("category", ""))
		var source := str(entry.get("source_level_id", ""))
		if not ships.has(ship_id) or seen.has(ship_id):
			errors.append("Unknown or duplicate acquisition ship: %s" % ship_id)
		seen[ship_id] = true
		if category not in CATEGORIES:
			errors.append("Unknown acquisition category: %s" % category)
		if category in ["DefaultOwned", "Pending"] and not source.is_empty():
			errors.append("Non-reward ship has a reward source: %s" % ship_id)
		if category in ["TutorialReward", "ChallengeReward"]:
			var prefix := "level.tutorial." if category == "TutorialReward" else "level.challenge."
			if not source.begins_with(prefix) or (not levels.has(source) and source not in planned):
				errors.append("Invalid acquisition reward source for %s: %s" % [ship_id, source])
			elif levels.has(source):
				var mode := "TutorialBattle" if category == "TutorialReward" else "ChallengeBattle"
				if levels[source].get("battle_mode") != mode:
					errors.append("Acquisition reward source mode mismatch: %s" % source)
	for ship_id in ships:
		if not seen.has(ship_id):
			errors.append("Ship missing acquisition category: %s" % ship_id)
	return errors


static func entry(catalog: Dictionary, ship_id: String) -> Dictionary:
	for item in catalog.get("ships", []):
		if str(item.get("ship_id", "")) == ship_id:
			return item
	return {}


static func defaults(catalog: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for item in catalog.get("ships", []):
		if item.get("category") == "DefaultOwned":
			result.append(str(item["ship_id"]))
	return result


static func rewards(catalog: Dictionary, level_id: String) -> Array[String]:
	var result: Array[String] = []
	for item in catalog.get("ships", []):
		if item.get("category") in ["TutorialReward", "ChallengeReward"] and str(item.get("source_level_id", "")) == level_id:
			result.append(str(item["ship_id"]))
	return result
