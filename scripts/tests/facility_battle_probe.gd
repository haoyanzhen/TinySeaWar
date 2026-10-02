extends SceneTree
const Registry = preload("res://scripts/infrastructure/data/config_registry.gd")
const Session = preload("res://scripts/application/battle_session.gd")
func _init(): call_deferred("run")
func run():
	var registry = Registry.new()
	if not registry.load_all(): push_error(str(registry.errors)); quit(1); return
	var seed_value := 42021
	var deployment := "original"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("deployment="): deployment = arg.trim_prefix("deployment=")
		if arg.begins_with("seed="): seed_value = int(arg.trim_prefix("seed="))
	var session = Session.new(registry)
	var level: Dictionary = registry.get_definition("levels", "level.prototype_harbor_3v3").duplicate(true)
	if deployment == "facilities":
		# Tactical deployment fixture uses legal approach water, not teleports during play.
		session.create_battle("level.prototype_harbor_3v3", seed_value)
		var reserved: Array[Vector2] = []
		for fleet in ["player_fleet", "enemy_fleet"]:
			var facility_id := "facility.harbor.supply_west" if fleet == "player_fleet" else "facility.harbor.communication_east"
			var center: Vector2 = session.facility_service.interaction_center(facility_id)
			for member in level[fleet]:
				var unit: Dictionary = session.state.units_by_id[member.entity_id]
				var found := false
				for radius in [350.0, 550.0, 750.0]:
					for step in range(24):
						var point: Vector2 = center + Vector2.RIGHT.rotated(TAU * step / 24.0) * radius
						if not session._inside_map(point) or not session.terrain_context_service.can_enter(point): continue
						if not session.terrain_query.is_navigation_segment_clear(point, center, float(unit.stats.collision_radius) + 4.0, session._movement_tags(unit)): continue
						if reserved.any(func(p): return p.distance_to(point) < 180.0): continue
						member.position = [point.x,point.y]
						member.heading = rad_to_deg((center-point).angle())
						reserved.append(point)
						found = true
						break
					if found: break
				if not found: push_error("no legal facility deployment"); quit(1); return
	if not session.create_battle_from_definition(level, seed_value).get("ok", false): quit(1); return
	session.configure_full_ai_factions(["player", "enemy"])
	var counts := {}
	var facts: Array = []
	var damage := {}
	var started := Time.get_ticks_msec()
	for tick in range(6000):
		if session.state.phase != "Running": break
		for event in session.advance_tick(0.1):
			var kind := str(event.get("event_type", ""))
			if kind.begins_with("Facility") or kind.begins_with("Support") or kind.begins_with("Mine") or kind in ["UnitServiced", "CommandRejected", "NavigationRequestFailed", "AIPathStuck", "TrajectoryPlanFailed", "BattleFinished"]:
				counts[kind] = int(counts.get(kind, 0)) + 1
				if kind not in ["TrajectoryPlanFailed", "FacilityWeaponFired"]: facts.append(event)
			if kind == "AttackResolved":
				var result: Dictionary = event.get("damage_result", {})
				var source := str(result.get("source_facility_id", ""))
				if not source.is_empty(): damage[source] = float(damage.get(source, 0)) + maxf(0.0, float(result.get("target_hp_before", 0)) - float(result.get("target_hp_after", 0)))
		if tick % 600 == 599:
			var tasks := {}
			for unit in session.state.units_by_id.values():
				if unit.life_state == "Alive": tasks[unit.entity_id] = {"task":unit.ai_state.get("level_task", ""), "facility":unit.ai_state.get("task_target_ref", {}), "position":unit.position, "intent":unit.navigation_state.get("strategic_intent_target"), "goal":session._current_corridor_goal(unit), "mode":unit.movement_state.get("mode"), "timeout":unit.ai_state.get("task_timeout")}
			print("PROGRESS ", session.state.elapsed_time, " ", JSON.stringify(tasks))
	var result := {"seed":seed_value, "deployment":deployment, "phase":session.state.phase, "elapsed":session.state.elapsed_time, "wall_seconds":(Time.get_ticks_msec()-started)/1000.0, "counts":counts, "facility_damage":damage, "facts":facts}
	var output := "res://reports/facilities/20261002-runtime"
	DirAccess.make_dir_recursive_absolute(output)
	var file := FileAccess.open(output + "/battle_%s_%d.json" % [deployment, seed_value], FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	result.erase("facts")
	print("RESULT ", JSON.stringify(result))
	quit(0 if session.state.phase == "Finished" else 1)
