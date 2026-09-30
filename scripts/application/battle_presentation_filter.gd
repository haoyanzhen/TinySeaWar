extends RefCounted
## All presentation consumers receive these copies, never the raw aviation events.
static func events(raw: Array, state: Dictionary, registry, faction: String) -> Array:
	var published: Array = []
	var visible: Dictionary = state.get("visible_by_faction", {}).get(faction, {})
	var units: Dictionary = state.get("units_by_id", {})
	for original in raw:
		var event: Dictionary = original.duplicate(true)
		var type := str(event.get("event_type", ""))
		if type in ["AviationPayloadRejected", "FormationTransitChanged"]: continue
		var source_id := str(event.get("unit_id", event.get("source_unit_id", "")))
		var source_known := known(source_id, units, visible, faction)
		if type in ["WeaponFired", "SkillCast", "SkillAttackScheduled", "UnitSunk"] and not source_known: continue
		if type == "WeaponFired":
			var weapon: Dictionary = registry.get_definition("weapons", str(event.get("weapon_id", "")))
			if weapon.get("mount_type", "") == "Aviation":
				# The launch is owned by the wave, not the old muzzle VFX.
				continue
		if type == "SkillCast":
			var ref: Dictionary = event.get("target_ref", {})
			if units.get(source_id, {}).get("faction_id", "") != faction or not known(str(ref.get("entity_id", "")), units, visible, faction):
				event["target_ref"] = {"type":"Self"}
		if type.begins_with("AviationWave"):
			if event.get("faction_id", "") != faction: continue
		if type in ["AntiAirFired", "AircraftDamaged", "AircraftDestroyed", "AviationPayloadReleased"]:
			# Session attaches an already observer-sanitized aviation fact.
			var views: Dictionary = event.get("presentation_by_faction", {})
			if not views.has(faction): continue
			event = views[faction].duplicate(true)
			event.event_id = original.event_id
			event.tick_index = original.tick_index
		if type == "ProjectileHit" and not known(str(event.get("target_unit_id", "")), units, visible, faction): continue
		if type == "AttackResolved":
			var result: Dictionary = event.get("damage_result", {})
			var target_id := str(result.get("target_unit_id", ""))
			var weapon: Dictionary = registry.get_definition("weapons", str(result.get("source_weapon_id", "")))
			if weapon.get("mount_type", "") == "Aviation":
				if not known(target_id, units, visible, faction):
					# The same neutral arrival for a miss and an unobserved hit: no result oracle.
					# A colliding torpedo's secret contact point is not a committed bomb aim point.
					if result.get("hit_reason", "") == "COLLISION": continue
					var own_attack: bool = units.get(str(result.get("source_unit_id", "")), {}).get("faction_id", "") == faction
					if own_attack or position_known(result.get("impact_position", Vector2.ZERO), units, faction):
						published.append({"event_id":event.get("event_id", ""), "tick_index":event.get("tick_index", 0), "event_type":"AviationArrival", "position":result.get("impact_position", Vector2.ZERO)})
					continue
				event.event_type = "AviationImpact"
				result.erase("aimed_target_unit_id")
				if not known(str(result.get("source_unit_id", "")), units, visible, faction):
					for key in result.keys():
						if str(key).begins_with("source_") or str(key).begins_with("buff_"): result.erase(key)
		if type == "SupportMissionResolved":
			# Airstrike results exclusively use AviationImpact, patrols use persistent snapshots.
			continue
		if type in ["SkillReconDeployed", "SkillReconDestroyed", "SkillWorldEffectExpired", "SupportMissionStarted", "SupportMissionLaunched", "SupportMissionCancelled", "SupportMissionCompleted"]: continue
		published.append(event)
	return published

static func known(id: String, units: Dictionary, visible: Dictionary, faction: String) -> bool:
	return not id.is_empty() and (visible.has(id) or units.get(id, {}).get("faction_id", "") == faction)

static func position_known(position: Vector2, units: Dictionary, faction: String) -> bool:
	# Conservative feedback-only area, not a new detection rule.
	for unit in units.values():
		if unit.get("faction_id", "") == faction and unit.get("life_state", "") == "Alive" and (unit.position as Vector2).distance_to(position) <= 120.0: return true
	return false
