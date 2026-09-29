extends RefCounted
## Application-only timeline. Never allocates rule entity IDs or draws randomness.
var waves: Dictionary = {}
var sequence := 0

func clear() -> void:
	waves.clear()
	sequence = 0

func register(attacks: Array, source: Dictionary, now: float) -> Dictionary:
	if attacks.is_empty(): return {}
	sequence += 1
	var first: Dictionary = attacks[0]
	var id := "aviation.%06d" % sequence
	var ids: Array = []
	for attack in attacks: ids.append(str(attack.attack_id))
	var wave := {"wave_id":id, "mission_id":id, "attack_ids":ids,
		"source_unit_id":str(first.get("source_unit_id", "")), "source_facility_id":str(first.get("source_facility_id", "")),
		"source_weapon_id":str(first.get("source_weapon_id", "")), "source_skill_id":str(first.get("source_skill_id", "")),
		"character_id":str(source.get("definition_id", "")).trim_prefix("ship."), "faction_id":str(source.get("faction_id", "")),
		"origin":first.get("origin", Vector2.ZERO), "target_position":first.get("target_position", Vector2.ZERO),
		"launch_at_time":float(first.get("launch_at_time", now)), "resolve_at_time":float(first.get("resolve_at_time", now)),
		"phase":"Scheduled", "position":first.get("origin", Vector2.ZERO), "ended_at_time":-1.0}
	waves[id] = wave
	return wave

func advance(now: float, units: Dictionary, active_ids: Dictionary) -> Array:
	var events: Array = []
	for id in waves.keys():
		var wave: Dictionary = waves[id]
		if float(wave.ended_at_time) >= 0.0:
			if now - float(wave.ended_at_time) > 0.65: waves.erase(id)
			continue
		var active := false
		for attack_id in wave.attack_ids:
			if active_ids.has(attack_id): active = true
		if not active:
			wave.phase = "Cancelled" if wave.phase == "Scheduled" else "Completed"
			wave.ended_at_time = now
			events.append(event_for(wave, "AviationWaveEnded"))
			continue
		if now < float(wave.launch_at_time): continue
		if wave.phase == "Scheduled":
			wave.spawn_position = units.get(wave.source_unit_id, {}).get("position", wave.origin)
			wave.phase = "Flying"
			events.append(event_for(wave, "AviationWaveLaunched"))
		var duration := maxf(0.001, float(wave.resolve_at_time) - float(wave.launch_at_time))
		wave.progress = clampf((now - float(wave.launch_at_time)) / duration, 0.0, 1.0)
		wave.position = (wave.spawn_position as Vector2).lerp(wave.target_position, wave.progress)
		wave.heading = ((wave.target_position as Vector2) - (wave.spawn_position as Vector2)).angle()
	return events

func event_for(wave: Dictionary, type: String) -> Dictionary:
	return {"event_type":type, "wave_id":wave.wave_id, "mission_id":wave.mission_id, "faction_id":wave.faction_id,
		"source_unit_id":wave.source_unit_id, "phase":wave.phase, "position":wave.position}

func snapshot(now: float, faction: String, omniscient: bool, effects: Dictionary, supports: Dictionary, missions: Array, facilities: Dictionary) -> Dictionary:
	var visible := {}
	for id in waves:
		var wave: Dictionary = waves[id]
		if not omniscient and wave.faction_id != faction: continue
		if wave.phase == "Cancelled": continue
		var item: Dictionary = wave.duplicate(true)
		item.remaining = maxf(0.0, float(wave.resolve_at_time) - now)
		item.end_progress = clampf((now - float(wave.ended_at_time)) / 0.65, 0, 1) if float(wave.ended_at_time) >= 0 else 0.0
		visible[id] = item
	for collection in [effects, supports]:
		for id in collection:
			var effect: Dictionary = collection[id]
			if effect.get("effect_type", "") not in ["Reconnaissance", "FighterPatrol"]: continue
			if not omniscient and effect.get("faction_id", "") != faction: continue
			var item: Dictionary = effect.duplicate(true)
			item.wave_id = "orbit." + str(id)
			item.phase = "Patrolling"
			item.aircraft_kind = "fighter" if effect.effect_type == "FighterPatrol" else "scout"
			item.heading = fmod(now * 0.6, TAU)
			item.progress = 1.0
			visible[item.wave_id] = item
	for mission in missions:
		if not omniscient and mission.get("faction_id", "") != faction: continue
		var item: Dictionary = mission.duplicate(true)
		item.wave_id = "support." + str(mission.mission_id)
		item.source_facility_id = mission.facility_id
		item.phase = "Scheduled" if mission.state == "Preparing" else "Flying"
		item.spawn_position = facilities.get(mission.facility_id, {}).get("position", mission.target_position)
		item.progress = clampf((now - float(mission.launch_at_time)) / maxf(0.001, float(mission.resolve_at_time) - float(mission.launch_at_time)), 0, 1)
		item.position = (item.spawn_position as Vector2).lerp(mission.target_position, item.progress)
		item.heading = ((mission.target_position as Vector2) - (item.spawn_position as Vector2)).angle()
		item.remaining = maxf(0, float(mission.resolve_at_time) - now)
		visible[item.wave_id] = item
	return visible
