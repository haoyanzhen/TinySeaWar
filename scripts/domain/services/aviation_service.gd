extends RefCounted
## One HP budget per launch wave. Decoration count never participates in combat.
var waves := {}
var attack_wave := {}

func clear() -> void:
	waves.clear()
	attack_wave.clear()

func register(wave: Dictionary, hp: float, floor_ratio: float, weapon: Dictionary) -> void:
	var task: Dictionary = wave.duplicate(true)
	task.max_hp = hp
	task.current_hp = hp
	task.damage_floor = floor_ratio
	task.payload = str(weapon.get("aviation_payload", "Bomb"))
	task.aircraft_kind = {"aircraft.scout":"scout", "aircraft.fighter":"fighter", "aircraft.asw":"asw"}.get(str(weapon.get("projectile_id", "")), "torpedo_bomber" if task.payload == "Torpedo" else "bomber")
	task.drop_distance = float(weapon.get("air_torpedo_drop_distance", 0))
	task.phase = "Scheduled"
	waves[task.wave_id] = task
	for id in task.attack_ids: attack_wave[id] = task.wave_id

func advance(now: float, units: Dictionary, active_ids: Dictionary) -> Array:
	var events: Array = []
	for id in waves.keys():
		var task: Dictionary = waves[id]
		if task.phase in ["Destroyed", "Released", "Cancelled"]:
			if now - float(task.get("ended_at_time", now)) > 0.65 and not (str(id).begins_with("support.") and active_ids.has(id)):
				for attack_id in task.attack_ids: attack_wave.erase(attack_id)
				waves.erase(id)
			continue
		var active := false
		for attack_id in task.attack_ids:
			if active_ids.has(attack_id): active = true
		if not active:
			task.phase = "Cancelled"
			task.ended_at_time = now
			continue
		if now < float(task.launch_at_time): continue
		if task.phase == "Scheduled":
			task.spawn_position = units.get(task.source_unit_id, {}).get("position", task.origin)
			var vector: Vector2 = task.target_position - task.spawn_position
			task.heading = vector.angle()
			var distance := vector.length()
			var stand_off := minf(float(task.drop_distance), distance * 0.5) if task.payload == "Torpedo" else 0.0
			task.release_position = (task.target_position as Vector2) - vector.normalized() * stand_off
			task.release_at_time = float(task.launch_at_time) + (float(task.resolve_at_time) - float(task.launch_at_time)) * (1.0 - stand_off / maxf(0.001, distance))
			task.phase = "Flying"
		var duration := maxf(0.001, float(task.release_at_time) - float(task.launch_at_time))
		task.progress = clampf((now - float(task.launch_at_time)) / duration, 0, 1)
		task.position = (task.spawn_position as Vector2).lerp(task.release_position, task.progress)
	return events

func fire_round(source_id: String, faction: String, origin: Vector2, radius: float, damage: float, targets: Dictionary, observed: Dictionary) -> Array:
	var events: Array = []
	var ids: Array = targets.keys()
	ids.sort()
	for id in ids:
		var target: Dictionary = targets[id]
		if target.get("phase", "Flying") != "Flying" or float(target.get("current_hp", 0)) <= 0: continue
		if target.get("faction_id", "") == faction or not observed.has(id): continue
		if origin.distance_squared_to(target.position) > radius * radius + 0.0001: continue
		if events.is_empty(): events.append({"event_type":"AntiAirFired", "source_unit_id":source_id, "faction_id":faction, "position":origin})
		var before := float(target.current_hp)
		target.current_hp = maxf(0, before - damage)
		events.append({"event_type":"AircraftDamaged", "wave_id":id, "source_unit_id":source_id, "faction_id":target.faction_id, "position":target.position, "damage":before - float(target.current_hp), "current_hp":target.current_hp})
		if float(target.current_hp) <= 0:
			target.phase = "Destroyed"
			events.append({"event_type":"AircraftDestroyed", "wave_id":id, "source_unit_id":source_id, "faction_id":target.faction_id, "position":target.position})
	return events

func task_for_attack(id: String) -> Dictionary:
	return waves.get(attack_wave.get(id, ""), {})

func payload_ratio(task: Dictionary) -> float:
	if float(task.get("current_hp", 0)) <= 0: return 0.0
	return maxf(float(task.damage_floor), clampf(float(task.current_hp) / maxf(1, float(task.max_hp)), 0, 1))
