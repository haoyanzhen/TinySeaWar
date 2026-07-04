class_name AIObservation
extends RefCounted

var faction_id := ""
var elapsed_time := 0.0
var tick_index := 0
var friendly_units := {}
var visible_enemies := {}
var contact_ghosts := {}
var known_projectiles := {}
var known_facilities := {}
var known_minefields := {}
var environment_zones: Array = []
var global_environment := {}


static func from_battle_state(state: Dictionary, observer_faction: String):
	var observation = load("res://scripts/application/ai/ai_observation.gd").new()
	observation.faction_id = observer_faction
	observation.elapsed_time = float(state.get("elapsed_time", 0.0))
	observation.tick_index = int(state.get("tick_index", 0))
	var visible: Dictionary = state.get("visible_by_faction", {}).get(observer_faction, {})
	for unit_id in state.get("units_by_id", {}):
		var unit: Dictionary = state["units_by_id"][unit_id]
		if str(unit.get("faction_id", "")) == observer_faction:
			observation.friendly_units[unit_id] = unit.duplicate(true)
		elif visible.has(unit_id) and unit.get("life_state", "") == "Alive":
			var observed_unit: Dictionary = unit.duplicate(true)
			observed_unit["contact_types"] = state.get("contact_types_by_faction", {}).get(observer_faction, {}).get(unit_id, []).duplicate()
			observation.visible_enemies[unit_id] = observed_unit
	for contact_id in state.get("contacts_by_faction", {}).get(observer_faction, {}):
		var contact: Dictionary = state["contacts_by_faction"][observer_faction][contact_id]
		if not bool(contact.get("visible", false)):
			observation.contact_ghosts[contact_id] = contact.duplicate(true)
	var known: Dictionary = state.get("known_projectiles_by_faction", {}).get(observer_faction, {})
	for projectile_id in state.get("projectiles_by_id", {}):
		var projectile: Dictionary = state["projectiles_by_id"][projectile_id]
		if str(projectile.get("faction_id", "")) == observer_faction or known.has(projectile_id):
			var observed_projectile := projectile.duplicate(true)
			if str(projectile.get("faction_id", "")) != observer_faction:
				observed_projectile.erase("source_unit_id")
				observed_projectile.erase("source_status_effects")
				observed_projectile.erase("attack_id")
			observation.known_projectiles[projectile_id] = observed_projectile
	for facility_id in state.get("facilities_by_id", {}):
		var facility: Dictionary = state["facilities_by_id"][facility_id]
		var known_by: Array = facility.get("known_by_faction", [])
		var public_knowledge := bool(facility.get("publicly_known", known_by.is_empty()))
		if public_knowledge or str(facility.get("faction_id", "")) == observer_faction or observer_faction in known_by:
			observation.known_facilities[facility_id] = facility.duplicate(true)
	for minefield_id in state.get("minefields_by_id", {}):
		var minefield: Dictionary = state["minefields_by_id"][minefield_id]
		if str(minefield.get("owner_faction_id", "")) == observer_faction or observer_faction in minefield.get("known_by_faction", []):
			observation.known_minefields[minefield_id] = minefield.duplicate(true)
	observation.environment_zones = state.get("environment_zones", []).duplicate(true)
	observation.global_environment = state.get("global_environment", {}).duplicate(true)
	return observation


func visible_enemy_ids() -> Array:
	var result: Array = visible_enemies.keys()
	result.sort()
	return result


func friendly_unit_ids() -> Array:
	var result: Array = friendly_units.keys()
	result.sort()
	return result
