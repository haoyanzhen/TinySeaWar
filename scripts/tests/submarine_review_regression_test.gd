extends SceneTree

const Registry = preload("res://scripts/infrastructure/data/config_registry.gd")
const Session = preload("res://scripts/application/battle_session.gd")
const Recorder = preload("res://scripts/infrastructure/analytics/battle_recorder.gd")
const Aggregator = preload("res://scripts/infrastructure/simulation/simulation_aggregator.gd")
const Writer = preload("res://scripts/infrastructure/simulation/simulation_report_writer.gd")

class WallTerrain extends RefCounted:
	func is_configured() -> bool: return true
	func is_navigation_segment_clear(start: Vector2, finish: Vector2, _radius: float, _tags: Array) -> bool:
		return not (minf(start.x, finish.x) < 2100.0 and maxf(start.x, finish.x) > 2100.0 and maxf(start.y, finish.y) > 1000.0)

var registry
var failures: Array[String] = []
var checks := 0

func _init() -> void:
	call_deferred("_run")

func _fixture(visible: bool = true) -> Dictionary:
	var session = Session.new(registry)
	assert(session.create_battle("level.prototype_5v5", 112).get("ok", false))
	session.configure_full_ai_factions(["player", "enemy"])
	var submarine: Dictionary = session.state["units_by_id"]["unit.player.hai_shih"]
	var target: Dictionary = session.state["units_by_id"]["unit.enemy.hindenburg"]
	submarine["position"] = Vector2(2000, 1100)
	submarine["heading"] = 0.0
	submarine["current_speed"] = 0.0
	submarine["depth_hold_remaining"] = 0.0
	submarine["depth_transition"]["active"] = false
	target["position"] = Vector2(2260, 1100)
	target["current_speed"] = 0.0
	for id in session._sorted_unit_ids():
		var other: Dictionary = session.state["units_by_id"][id]
		if id in [submarine["entity_id"], target["entity_id"]]: continue
		other["position"] = Vector2(400, 300) if other["faction_id"] == "player" else Vector2(3700, 300)
	for weapon in submarine["weapon_states"]: weapon["reload_remaining"] = 0.0
	session.state["visible_by_faction"]["player"] = {target["entity_id"]:["Optical"]} if visible else {}
	session._ai_observations_by_faction.clear()
	submarine["targeting_state"]["current_target_id"] = target["entity_id"]
	submarine["ai_state"]["submarine_target_id"] = target["entity_id"]
	submarine["ai_state"]["decision_cooldown"] = 0.0
	session.command_queue.clear()
	session.drain_events()
	return {"session":session, "submarine":submarine, "target":target}

func _run() -> void:
	registry = Registry.new()
	assert(registry.load_all())
	_test_oxygen()
	_test_contact_recovery()
	_test_exit_and_tail()
	_test_diagnostics()
	_test_confirmed_route()
	_test_depth_policy_and_asw()
	_test_torpedo_budget()
	for failure in failures: push_error(failure)
	print("SUBMARINE_REVIEW_REGRESSION: %d/%d passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _test_oxygen() -> void:
	for visible in [false, true]:
		var f := _fixture(visible)
		var s = f.session
		var u: Dictionary = f.submarine
		u.oxygen_state.current = 6.0
		s._set_submarine_phase(u, "Approach", "TEST")
		s._update_submarine_ai_intent(u)
		_check(u.ai_state.submarine_combat_phase == "RecoverOxygen", "low oxygen precedes target filtering, visible=%s" % visible)
		_check(s.command_queue.any(func(c): return c.get("command_type") == "SetSubmarineDepth" and c.get("target_depth_state") == "Surface"), "proactive surface uses a public command")
	var f := _fixture()
	var s = f.session
	var u: Dictionary = f.submarine
	var baseline: float = s._submarine_projected_oxygen_margin(u, f.target)
	u.status_effects.append({"stat":"OxygenConsumptionRate", "operation":"PercentAdd", "value":0.3, "remaining":12.0})
	_check(is_equal_approx(s._submarine_oxygen_consumption(u), 1.3), "oxygen budget consumes the same skill modifier as Domain")
	_check(s._submarine_projected_oxygen_margin(u, f.target) < baseline, "skill oxygen cost reduces the mission margin")
	u.heading = PI * 0.5
	_check(s._submarine_alignment_time(u, {"weapon":s._weapon_for_state(u.weapon_states[0]), "aim_position":f.target.position}) > 0.0, "alignment consumes mission time")

func _test_contact_recovery() -> void:
	var f := _fixture(false)
	var s = f.session
	var u: Dictionary = f.submarine
	s._set_submarine_phase(u, "SurfaceForAttack", "TEST")
	u.depth_transition = {"active":true, "from_depth_state":"Submerged", "target_depth_state":"Surface", "remaining":1.0, "duration":2.0}
	s._update_submarine_ai_intent(u)
	_check(u.ai_state.submarine_combat_phase == "SurfaceForAttack", "brief lost contact does not reclassify an attack as recovery")
	s._update_submarine_ai_primary_weapon(u)
	_check(not s.command_queue.any(func(c): return c.get("command_type") == "FirePrimaryWeapon"), "hidden contact cannot authorize a shot")
	_check(str(u.ai_state.planned_torpedo_weapon_state_instance_id).is_empty(), "lost contact clears the atomic firing solution")
	s.state.elapsed_time = 1.0
	u.depth_state = "Surface"
	u.depth_transition.active = false
	u.ai_state.decision_cooldown = 0.0
	s.state.visible_by_faction.player = {f.target.entity_id:["Optical"]}
	s._ai_observations_by_faction.clear()
	s._update_submarine_ai_intent(u)
	_check(u.ai_state.submarine_combat_phase == "AttackRun", "fresh visible contact resumes attack after authoritative surfacing")
	_check(s._submarine_fire_discipline(u) == "HoldUntilWindow", "resumed attack retains attack discipline")
	s.state.visible_by_faction.player = {}
	s._ai_observations_by_faction.clear()
	u.ai_state.decision_cooldown = 0.0
	s._update_submarine_ai_intent(u)
	s.state.elapsed_time = 3.1
	u.ai_state.decision_cooldown = 0.0
	s._update_submarine_ai_intent(u)
	_check(u.ai_state.submarine_combat_phase == "RecoverOxygen", "expired contact task cannot remain an indefinite attack")

func _test_exit_and_tail() -> void:
	var f := _fixture()
	var s = f.session
	var u: Dictionary = f.submarine
	u.depth_state = "Surface"
	u.heading = PI
	u.ai_state.submarine_attack_completed = true
	u.ai_state.planned_exit_position = Vector2(1700, 1100)
	s._set_submarine_phase(u, "BreakContact", "TEST")
	s.state.elapsed_time = 3.1
	s._update_submarine_break_contact_intent(u, f.target)
	_check(u.ai_state.submarine_combat_phase == "BreakContact", "three seconds alone cannot complete escape")
	var solution: Dictionary = s._select_submarine_torpedo_solution(u, f.target)
	_check(not solution.is_empty() and str(solution.get("weapon", {}).get("id", "")).contains("aft"), "only a natural stern solution is permitted during escape")
	_check(solution.get("exit_position", Vector2.ZERO) == Vector2(1700, 1100), "stern shot preserves committed exit")
	# Make this a valuable finishing window, then exercise the actual public
	# command path rather than only checking candidate construction.
	f.target.current_hp = 490.0
	u.skill_state.cooldown_remaining = 0.0
	s._ai_observations_by_faction.clear()
	s._ai_local_power_cache.clear()
	s._update_submarine_ai_primary_weapon(u)
	var shots: Array = s.command_queue.filter(func(c): return c.get("command_type") == "FirePrimaryWeapon")
	if shots.is_empty(): print("TAIL_FIRE_DIAGNOSTIC=", s.drain_events())
	_check(shots.size() == 1, "valuable stern follow-up submits a public firing command")
	if not shots.is_empty():
		var result: Dictionary = s._apply_command(shots[0])
		_check(bool(result.get("accepted", false)), "stern follow-up passes Domain validation")
		_check(u.ai_state.planned_torpedo_weapon_state_instance_id == shots[0].weapon_state_instance_id and u.ai_state.planned_exit_position == Vector2(1700, 1100), "committed launcher and exit remain atomic after actual follow-up")
		for weapon in u.weapon_states: weapon.reload_remaining = 0.0
	u.ai_state.submarine_attack_completed = false
	_check(s._select_submarine_torpedo_solution(u, f.target).is_empty(), "an aborted attack cannot claim a follow-up shot")
	u.ai_state.submarine_attack_completed = true
	u.heading = 0.0
	_check(s._select_submarine_torpedo_solution(u, f.target).is_empty(), "follow-up cannot turn the ship away from escape")
	u.position = Vector2(1700, 1100)
	s._update_submarine_break_contact_intent(u, f.target)
	_check(u.ai_state.submarine_combat_phase == "RecoverOxygen", "reaching the safe exit allows recovery")

func _test_diagnostics() -> void:
	var f := _fixture()
	var s = f.session
	var u: Dictionary = f.submarine
	s._set_submarine_phase(u, "Search", "TEST")
	s._select_submarine_target_with_hysteresis(u)
	s._update_submarine_ai_primary_weapon(u)
	var events: Array = s.drain_events()
	var samples: Array = events.filter(func(e): return e.get("event_type") == "AISubmarineFireDecisionSample")
	_check(samples.size() == 1 and bool(samples[0].visible_target), "phase-inactive does not mean no visible enemy")
	_check(int(samples[0].ready_weapon_count) == 2 and not bool(samples[0].weapon_evaluated), "ready launchers are independent of whether this phase evaluated firing")
	var recorder = Recorder.new()
	recorder.reset("review", 112)
	recorder.register_units(s.state.units_by_id)
	recorder.consume(events, 0.1)
	var entry: Dictionary = recorder.summary.submarine_ai[u.entity_id]
	_check(entry.zero_fire_classification == "SUBMARINE_PHASE_HELD", "phase gate is not misclassified as a perception failure")
	var runs := [{"submarine_ai":{u.entity_id:entry}}]
	var aggregate: Dictionary = Aggregator.new()._aggregate_submarine_ai(runs)
	_check(aggregate.eligible_target_samples == 1 and aggregate.weapon_evaluation_samples == 0, "new diagnostic counters survive aggregation")
	var csv: String = Writer.new()._submarine_ai_csv({"runs":runs})
	_check(csv.contains("target_rejections_by_reason") and csv.contains("SUBMARINE_PHASE_HELD"), "CSV exports separate target and phase evidence")

func _test_confirmed_route() -> void:
	var f := _fixture()
	var s = f.session
	var u: Dictionary = f.submarine
	s.terrain_query = WallTerrain.new()
	_check(not is_finite(s._submarine_route_eta(u, Vector2(2260, 1100))), "blocked direct route without a confirmed corridor has no fabricated ETA")
	u.movement_state.corridor_points = [Vector2(2000, 900), Vector2(2200, 900), Vector2(2260, 1100)]
	u.movement_state.corridor_index = 0
	var eta: float = s._submarine_route_eta(u, Vector2(2260, 1100))
	_check(is_finite(eta) and eta > 260.0 / float(u.stats.speed), "confirmed detour distance contributes to oxygen ETA")
	_check(not s._submarine_segment_safe(u, Vector2(2260, 1100), Vector2(2000, 1100)), "exit must be reachable from the attack position, not just occupiable")

func _test_depth_policy_and_asw() -> void:
	var f := _fixture()
	var s = f.session
	var u: Dictionary = f.submarine
	u.depth_state = "Surface"
	u.current_hp = 1.0
	_check(not s._is_unit_under_threat(u, f.target), "half HP and nearby enemies do not authorize submarine self-defense")
	for damage in [{"damage_type":"AntiSubmarine", "hit":false, "final_damage":10.0}, {"damage_type":"AntiSubmarine", "hit":true, "final_damage":0.0}, {"damage_type":"Gun", "hit":true, "final_damage":10.0}]:
		s._record_submarine_asw_damage(u, damage)
		_check(not s._is_unit_under_threat(u, f.target), "only effective ASW damage opens self-defense")
	s._record_submarine_asw_damage(u, {"damage_type":"AntiSubmarine", "hit":true, "final_damage":1.0})
	_check(s._is_unit_under_threat(u, f.target), "effective ASW damage authorizes self-defense")
	s.state.elapsed_time = 6.1
	_check(not s._is_unit_under_threat(u, f.target), "self-defense expires without renewed damage")
	u.oxygen_state.current = 0.0
	_check(s._submarine_depth_change_rejection(u, "Submerged") == "SUBMARINE_OXYGEN_TOO_LOW", "zero oxygen cannot dive")
	u.oxygen_state.current = 0.001
	_check(s._submarine_depth_change_rejection(u, "Submerged") == "OK", "any positive oxygen can dive")
	s._set_submarine_phase(u, "RecoverOxygen", "TEST")
	s.command_queue.clear()
	s._update_submarine_depth_intent(u)
	_check(u.ai_state.submarine_depth_intent == "Conceal" and s.command_queue.any(func(c): return c.get("target_depth_state") == "Submerged"), "surface pressure permits concealment far below the old oxygen thresholds")
	_check(s.command_queue.all(func(c): return c.get("command_type") == "SetSubmarineDepth"), "depth choice does not impose a movement destination")
	u.oxygen_state.current = u.oxygen_state.maximum
	s.command_queue.clear()
	s._update_submarine_depth_intent(u)
	_check(u.ai_state.submarine_depth_intent == "Hunt", "sufficient recovery chooses hunting depth")
	u.depth_state = "Submerged"
	for w in u.weapon_states: w.reload_remaining = 10.0
	_check(not s._submarine_surface_lead_reached(u, f.target, {}), "in-range but reloading launchers cannot authorize early attack surfacing")
	for w in u.weapon_states: w.reload_remaining = 0.0
	u.heading = PI * 0.5
	_check(not s._submarine_surface_lead_reached(u, f.target, {}), "out-of-arc launchers cannot authorize early attack surfacing")
	u.heading = 0.0
	u.current_hp = u.max_hp
	f.target.current_hp = 1800.0
	u.skill_state.cooldown_remaining = 0.0
	s._ai_observations_by_faction.clear()
	s._ai_local_power_cache.clear()
	_check(s._submarine_surface_lead_reached(u, s._ai_observation_for("player").visible_enemies[f.target.entity_id], {}), "ready valuable aligned window allows attack surfacing")
	u.depth_state = "Surface"
	s._set_submarine_phase(u, "RecoverOxygen", "TEST")
	s._update_submarine_recovery_intent(u)
	_check(u.ai_state.submarine_combat_phase == "SurfaceForAttack" and not s._submarine_has_asw_damage(u), "replenishment can start a deliberate attack through the normal threshold without inventing self-defense")
	for w in u.weapon_states: w.reload_remaining = 999.0
	_check(s._select_submarine_target_with_hysteresis(u).is_empty(), "unready torpedoes do not authorize an attack")
	s._queue_submarine_tracking_intent(u)
	_check(u.ai_state.submarine_target_id == f.target.entity_id, "unready torpedoes do not discard a visible tracking contact")

func _test_torpedo_budget() -> void:
	for ship in registry.all("ships"):
		if ship.ship_class != "Submarine": continue
		var level := int(ship.level)
		var reference: Dictionary = registry.get_definition("ships", "ship.jervis" if level == 1 else "ship.shimakaze")
		var ratio := _ideal_torpedo_dps(ship) / _ideal_torpedo_dps(reference)
		_check(ratio >= 1.95 and ratio <= 2.05, "%s sustains about twice same-tier torpedo destroyer paper DPS" % ship.id)
		_check(float(ship.redive_oxygen_ratio) == 0.0 and float(ship.oxygen_recovery_rate) == (3.0 if level == 1 else 4.5), "%s uses positive-oxygen rule and tier recovery" % ship.id)

func _ideal_torpedo_dps(ship: Dictionary) -> float:
	var total := 0.0
	for id in ship.weapon_mounts:
		var weapon: Dictionary = registry.get_definition("weapons", id)
		if weapon.mount_type != "Torpedo": continue
		var formula: Dictionary = registry.get_definition("formulas", weapon.formula_id)
		var raw := float(formula.base_damage) + float(ship.torpedo_power) * float(formula.power_coefficient)
		var hit := raw * float(weapon.armor_damage_modifiers.Heavy) - 80.0 * float(formula.armor_coefficient)
		total += hit * float(weapon.mount_count) * float(weapon.shots_per_mount) / float(weapon.reload_time)
	return total
