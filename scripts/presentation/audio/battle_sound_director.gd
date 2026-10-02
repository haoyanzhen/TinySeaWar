extends RefCounted
## Only filtered events and non-omniscient snapshots may enter this adapter.
const Feedback = preload("res://scripts/presentation/battle/player_command_feedback.gd")
var audio
var seen: Dictionary = {}
var retired_event := 0
var highest_event := 0
var attacks: Dictionary = {}
var waves: Dictionary = {}
var previous_units: Dictionary = {}
var known_projectiles: Dictionary = {}
var low_intervals: Dictionary = {}
var critical_intervals: Dictionary = {}
var rejection_times: Dictionary = {}
var time_warned := false
var time_limit := 1200.0
var physical := false
var stage_tick := -1
var terminal := false

func setup(manager, large: bool, limit: float, is_physical: bool = false) -> void:
	audio = manager
	audio.begin_battle(large)
	retired_event = 0; highest_event = 0
	seen.clear(); attacks.clear(); waves.clear(); previous_units.clear()
	known_projectiles.clear()
	low_intervals.clear(); critical_intervals.clear(); rejection_times.clear()
	time_warned = false
	time_limit = limit
	physical = is_physical
	terminal = false
	stage_tick = -1

func own(unit: Dictionary) -> bool: return unit.get("faction_id", "") == "player"

func emit(id: String, owner: String = "", position: Vector2 = Vector2.INF, cooldown: float = -1) -> void:
	if audio.dense and id in ["W13a", "W13b", "W14", "W08", "W19"] and not position.is_equal_approx(Vector2.INF) and owner != audio.selected_id:
		var cell := float(audio.mix("impact_cell_size", 180))
		owner = "impact.%d.%d" % [floori(position.x / cell), floori(position.y / cell)]
	audio.play(id, owner, position, cooldown)

func reject(command: Dictionary, reason: String) -> void:
	if str(command.get("issuer_type", "Player")) != "Player" or str(command.get("issuer_id", "player")) != "player" or bool(command.get("internal", false)): return
	if command.get("command_type", "") == "RecordTutorialAction" or command.has("primary_auto_fire_suspended"): return
	var partial: bool = not command.get("successful_unit_ids", []).is_empty()
	var key := "%s:%s:%s:%d:%d" % [command.get("command_type", ""), reason, partial, command.get("rejected_unit_ids", []).size(), command.get("successful_unit_ids", []).size() + command.get("rejected_unit_ids", []).size()]
	var t: float = audio.now()
	var last := float(rejection_times.get(key, -100))
	rejection_times[key] = t
	if t - last > Feedback.MERGE_SECONDS: emit("U05a", key, Vector2.INF, 0)

func consume(events: Array, view: Dictionary) -> void:
	if audio == null: return
	var units: Dictionary = view.get("units", {})
	var facilities: Dictionary = view.get("facilities", {})
	var partial_commands := {}
	for event in events:
		if event.get("event_type", "") == "CommandRejected" and not event.get("successful_unit_ids", []).is_empty(): partial_commands[str(event.get("command_type", ""))] = true
	var sunk := {}
	var result_cued := events.any(func(e): return e.get("event_type", "") in ["LevelObjectiveCompleted", "LevelObjectiveFailed"])
	var finishing := false
	for event in events:
		if event.get("event_type", "") == "UnitSunk": sunk[str(event.get("unit_id", ""))] = true
		if event.get("event_type", "") == "BattleFinished": finishing = true
	# Important own warnings take priority over physical transients in this batch.
	if not finishing: sync_warnings(view)
	for event in events:
		var event_id := str(event.get("event_id", ""))
		if not event_id.is_empty():
			var number := int(event_id.get_slice(".", 1))
			if number <= retired_event or seen.has(event_id): continue
			highest_event = maxi(highest_event, number)
			seen[event_id] = true
		var type := str(event.get("event_type", ""))
		var id := str(event.get("unit_id", event.get("source_unit_id", "")))
		var unit: Dictionary = units.get(id, {})
		var position: Vector2 = unit.get("position", Vector2.INF)
		var friendly := own(unit)
		if terminal and type != "BattleFinished": continue
		if type == "CommandRejected": reject(event, str(event.get("reason_code", "UNKNOWN"))); continue
		if type.begins_with("AudioSupportMission"):
			var mission := str(event.get("mission_id", ""))
			match type:
				"AudioSupportMissionStarted": emit("U04b", "support")
				"AudioSupportMissionLaunched":
					if not waves.has("support."+mission): waves["support."+mission] = true; emit("A01", "support", event.get("position", Vector2.INF))
				"AudioSupportMissionCompleted": emit("N11a", "support", Vector2.INF, 1.5)
				"AudioSupportMissionCancelled": emit("U02", "support")
			continue
		if type == "AudioEnvironmentDissipated": emit("N10", "environment", Vector2.INF, 3); continue
		if type == "BattleFinished":
			if terminal: continue
			terminal = true
			audio.sync_loops({})
			if not result_cued: emit("U11", "result", Vector2.INF, 0)
			continue
		if view.get("phase", "") == "Paused": continue
		if type in ["MoveOrderAccepted", "MoveOrderQueued", "MoveWaypointQueued", "FocusTargetChanged", "AmmoSwitched"]:
			if friendly:
				if partial_commands.has({"MoveOrderAccepted":"MoveUnits", "MoveOrderQueued":"MoveUnits", "MoveWaypointQueued":"AppendMoveWaypoint", "FocusTargetChanged":"FocusTarget", "AmmoSwitched":"SwitchAmmo"}[type]): continue
				if type == "FocusTargetChanged" and str(event.get("new_target_id", "")).is_empty(): continue
				emit({"MoveOrderAccepted":"U04a", "MoveOrderQueued":"U04b", "MoveWaypointQueued":"U04b", "FocusTargetChanged":"U04c", "AmmoSwitched":"U06"}[type], "player_intent")
		elif type == "UnitControlStateChanged" and friendly:
			var previous: Dictionary = previous_units.get(id, {})
			for field in ["movement_assist_enabled", "secondary_auto_fire_enabled", "primary_auto_fire_enabled"]:
				if previous.has(field) and bool(previous[field]) != bool(event.get(field, previous[field])):
					emit("U07a" if bool(event[field]) else "U07b", "player_intent")
			previous_units[id] = event.duplicate()
		elif type == "WeaponFired" and not unit.is_empty():
			var weapon: Dictionary = audio.manifest.get("weapons", {}).get(str(event.get("weapon_id", "")), {})
			if weapon.get("mount_type", "") != "Aviation" and not weapon.is_empty():
				emit(str(weapon.fire), id, position)
				# Both stages share the authoritative ASW launch, not an invented delayed hit.
				if weapon.get("mount_type", "") == "AntiSubmarine": emit("W07b", id, position)
		elif type == "AntiAirFired":
			# B publishes a sanitized position even when the source identity is absent.
			if event.has("position"):
				var fire := "W09"
				var ship: Dictionary = audio.manifest.get("ships", {}).get(str(unit.get("definition_id", "")), {})
				for weapon_id in ship.get("weapons", []):
					var weapon: Dictionary = audio.manifest.weapons.get(weapon_id, {})
					if weapon.get("mount_type", "") == "AntiAir": fire = str(weapon.fire); break
				emit(fire, id, event.position, 0.8 if audio.dense else 0.4)
		elif type in ["AttackResolved", "AviationImpact"]:
			var result: Dictionary = event.get("damage_result", {})
			var target_id := str(result.get("target_unit_id", ""))
			var target: Dictionary = units.get(target_id, {})
			# The generic visual filter does not sanitize all non-aviation damage events.
			# Target position always comes from a currently public snapshot, never raw impact data.
			if target.is_empty(): continue
			var attack_id := str(result.get("attack_id", event_id))
			if attacks.has(attack_id): continue
			attacks[attack_id] = true
			if not bool(result.get("hit", false)) or float(result.get("final_damage", 0)) <= 0:
				if type == "AviationImpact": emit("W15a", "arrival", result.get("impact_position", target.position))
				continue
			if sunk.has(target_id): continue
			var kind := str(result.get("damage_type", ""))
			var hit := "W14" if kind == "Torpedo" else ("W08" if kind == "AntiSubmarine" else ("W13b" if float(result.get("final_damage", 0)) >= 200 else "W13a"))
			emit(hit, target_id, target.position)
		elif type == "AviationArrival":
			# Neutral published arrival has identical sound for hidden hit and miss.
			if event.has("position"): emit("W15a", "arrival", event.position)
		elif type == "UnitSunk" and not unit.is_empty(): emit("W19", id, position)
		elif type == "ShellBlockedByTerrain" and not unit.is_empty():
			if event.has("position") and public_position(event.position, view): emit("W15a", "shore", event.position)
		elif type == "ProjectileBlockedByTerrain":
			if (friendly or known_projectiles.has(str(event.get("projectile_id", "")))) and event.has("position"): emit("W15a", "shore", event.position)
		elif type == "AviationWaveLaunched" and friendly:
			var wave_id := str(event.get("wave_id", ""))
			if not waves.has(wave_id):
				waves[wave_id] = true
				emit("A01", id, position)
		elif type == "AviationPayloadReleased":
			if event.has("position"): emit("A05" if event.has("projectile_id") else "A03", str(event.get("wave_id", "")), event.position)
		elif type == "SubmarineDepthTransitionStarted" and not unit.is_empty(): emit("S01" if event.get("target_depth_state", "") == "Submerged" else "S02", id, position)
		elif type == "SubmarineDepthChanged" and friendly: emit("S03a" if event.get("target_depth_state", "") == "Submerged" else "S03b", "depth")
		elif type == "ContactAcquired" and event.get("observer_faction", "") == "player": emit("N01", "contact", Vector2.INF, 4)
		elif type in ["TutorialStageChanged", "LevelObjectiveAdvanced"] and not finishing and not result_cued:
			if stage_tick != int(event.get("tick_index", -2)):
				stage_tick = int(event.get("tick_index", -2)); emit("N10", "stage", Vector2.INF, 0.5)
		elif type in ["LevelObjectiveCompleted", "LevelObjectiveFailed"]:
			emit("N11a" if type == "LevelObjectiveCompleted" else "N11b", "objective", Vector2.INF, 1.5)
		elif type == "MineTriggered" and not unit.is_empty(): emit("W14", id, position)
		elif type.begins_with("Facility") or type.begins_with("MineDeployment"):
			var facility_id := str(event.get("facility_id", ""))
			if not facilities.has(facility_id): continue
			# No facts about enemy activity from raw facility events.
			if not friendly and facilities[facility_id].get("faction_id", "") != "player" and not (type == "FacilityOwnershipChanged" and event.get("old_faction_id", "") == "player" and event.get("faction_id", "") == facilities[facility_id].get("faction_id", "")): continue
			match type:
				"FacilityControlDeclared": emit("F01a", "facility")
				"FacilityControlCompleted": emit("F01b", "facility")
				"FacilityOwnershipChanged":
					# Controlling already owns completion; autonomous ownership change is distinct.
					var controlled := false
					for other in events:
						if other.get("event_type", "") == "FacilityControlCompleted" and other.get("facility_id", "") == facility_id: controlled = true
					if not controlled: emit("F02", "facility")
				"FacilityActivated", "FacilityRecovered": emit("F03a", "facility")
				"FacilitySuppressed": emit("F03b", "facility")
				"FacilityOperationStateChanged": emit("F03a" if event.get("operation_state", "") == "Active" else "F03b", "facility")
				"FacilityDockingCompleted": emit("F04", "facility")
				"FacilityServiceStarted":
					if str(event.get("service_type", "")) == "Supply": emit("F05a", "facility")
				"FacilityActionInterrupted": emit("U02" if event.get("reason_code", "") in ["CANCELLED", "UNDOCKED"] else "U05a", "facility")
				"MineDeploymentStarted": emit("F09a", "facility")
				"MineDeploymentCompleted": emit("F09b", "facility")
				"MineDeploymentCancelled": emit("U02", "facility")
	# Keep only dedup entries within a bounded tick window; old events cannot replay.
	if seen.size() > 4096:
		retired_event = highest_event - 2048
		for key in seen.keys():
			if int(str(key).get_slice(".", 1)) <= retired_event: seen.erase(key)
	if attacks.size() > 4096: attacks.clear()

func public_position(position: Vector2, view: Dictionary) -> bool:
	for unit in view.get("units", {}).values():
		if own(unit) and (unit.get("position", Vector2.INF) as Vector2).distance_to(position) <= 120: return true
	return false

func sync_warnings(view: Dictionary) -> void:
	if view.get("phase", "") != "Running": return
	for id in view.get("units", {}):
		var unit: Dictionary = view.units[id]
		if not own(unit) or unit.get("life_state", "") != "Alive": continue
		var ratio := float(unit.get("current_hp", 0)) / maxf(1, float(unit.get("max_hp", 1)))
		if bool(unit.get("is_flagship", false)):
			if ratio >= float(audio.mix("critical_hp_rearm", 0.4)): critical_intervals.erase(id)
			if ratio <= float(audio.mix("critical_hp_ratio", 0.25)) and not critical_intervals.has(id):
				critical_intervals[id] = true; emit("N06", str(id), Vector2.INF, 0)
		var oxygen: Dictionary = unit.get("oxygen_state", {})
		if float(oxygen.get("maximum", 0)) <= 0: continue
		var oxygen_ratio := float(oxygen.get("current", 0)) / maxf(1, float(oxygen.maximum))
		if oxygen_ratio >= float(audio.mix("low_oxygen_rearm", 0.35)): low_intervals.erase(id)
		if oxygen_ratio <= float(audio.mix("low_oxygen_ratio", 0.2)) and not low_intervals.has(id):
			low_intervals[id] = true; emit("S04", str(id), Vector2.INF, 0)
	if time_limit - float(view.get("elapsed_time", 0)) <= float(audio.mix("time_warning_seconds", 60)) and not time_warned:
		time_warned = true; emit("N13", "time", Vector2.INF, 0)

func update(view: Dictionary, camera: Vector2, focus: String, nearby_coast: bool = false) -> void:
	if audio == null: return
	audio.listener_position = camera
	audio.selected_id = focus
	audio.paused = view.get("phase", "") == "Paused"
	sync_warnings(view)
	if terminal or view.get("phase", "") == "Finished": audio.sync_loops({}); return
	var desired := {}
	var environment: Dictionary = view.get("global_environment", {})
	var sea := float(environment.get("base_sea_state", 1))
	var wind := float(environment.get("wind_speed", 2))
	# Only own public local contexts can strengthen the global mix.
	for id in view.get("terrain_contexts", {}):
		if not own(view.get("units", {}).get(id, {})): continue
		var unit: Dictionary = view.units[id]
		if (unit.position as Vector2).distance_to(camera) > 600: continue
		var context: Dictionary = view.terrain_contexts[id]
		sea = maxf(sea, float(context.get("sea_state", context.get("base_sea_state", sea))))
		wind = maxf(wind, float(context.get("wind_speed", wind)))
	var wave := "E01" if sea < 2 else ("E02a" if sea < 4 else "E02b")
	desired[wave] = {"id":wave, "level":0.7}
	var wind_id := "E03b" if wind >= 7 else "E03a"
	desired[wind_id] = {"id":wind_id, "level":0.55}
	if environment.get("weather", "") in ["rain", "thunderstorm"]:
		var rain := "E04b" if environment.weather == "thunderstorm" else "E04a"
		desired[rain] = {"id":rain, "level":0.65}
	if nearby_coast: desired["E06"] = {"id":"E06", "level":0.45}
	var candidates: Array = []
	for id in view.get("aviation", {}):
		var wave_view: Dictionary = view.aviation[id]
		if wave_view.get("phase", "") not in ["Flying", "Patrolling"] or not wave_view.has("position"): continue
		if (wave_view.position as Vector2).distance_to(camera) > float(audio.mix("dense_max_distance" if audio.dense else "max_distance", 1800)): continue
		candidates.append({"id":str(id), "view":wave_view, "distance":(wave_view.position as Vector2).distance_squared_to(camera)})
		if not waves.has(id) and wave_view.get("aircraft_kind", "") in ["scout", "fighter", "asw"]:
			waves[id] = true; emit("N10", "patrol", Vector2.INF, 2)
		if not physical and not waves.has(str(id)+".drop") and float(wave_view.get("progress", 0)) >= 0.9:
			var weapon_id := str(wave_view.get("source_weapon_id", ""))
			if audio.manifest.get("weapons", {}).get(weapon_id, {}).get("mount_type", "") == "Aviation" and wave_view.get("aircraft_kind", "") not in ["scout", "fighter", "asw", "torpedo_bomber"] and audio.manifest.weapons.get(weapon_id, {}).get("aviation_payload", "Bomb") != "Torpedo":
				waves[str(id)+".drop"] = true; emit("A03", str(id), wave_view.position)
	candidates.sort_custom(func(a, b): return a.distance < b.distance if a.distance != b.distance else a.id < b.id)
	for index in range(mini(candidates.size(), int(audio.mix("aircraft_loops", 2)))):
		var candidate: Dictionary = candidates[index]
		desired["air."+candidate.id] = {"id":"A02", "position":candidate.view.position, "level":0.35 * (1 - sqrt(float(candidate.distance)) / float(audio.mix("dense_max_distance" if audio.dense else "max_distance", 1800)))}
	audio.sync_loops(desired)
	known_projectiles = {}
	for id in view.get("projectiles", {}): known_projectiles[id] = true
	previous_units.clear()
	for id in view.get("units", {}):
		var unit: Dictionary = view.units[id]
		if not own(unit): continue
		previous_units[id] = {}
		for field in ["movement_assist_enabled", "secondary_auto_fire_enabled", "primary_auto_fire_enabled"]:
			previous_units[id][field] = bool(unit.get(field, false))
