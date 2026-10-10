extends SceneTree

const ConfigRegistry = preload("res://scripts/infrastructure/data/config_registry.gd")
const BattleSession = preload("res://scripts/application/battle_session.gd")

var failures: Array[String] = []
var checks := 0

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _run() -> void:
	var registry = ConfigRegistry.new()
	_check(registry.load_all(), "current data loads")
	var session = BattleSession.new(registry)
	_check(session.create_battle("level.challenge.l02", 20261002).get("ok", false), "L-02 creates")
	# Isolate the old tick-638 shore/current geometry. Full battle decisions may
	# change earlier after the fix, so do not require a specific event at 639.
	var motion := {"position":Vector2(1533.242,880.0867), "heading":-0.243324332160509, "speed":-16.5, "maximum_speed":66.0, "base_maximum_speed":66.0, "reverse_speed":16.5, "acceleration":66.0, "braking":132.0, "turn_rate_limit":1.26536370769589, "current_vector":Vector2(9,0), "collision_half_extents":Vector2(54,22.68)}
	var retreat := {"direction":Vector2(-0.287513,0.957777)}
	var tags := ["Surface", "ShallowDraft"]
	var ordinary: Dictionary = session.trajectory_planner.plan_normal(motion, Vector2(1600,704), 17.0, tags, session.terrain_query, session.terrain_context_service)
	var safe: Dictionary = session.trajectory_planner.plan_normal(motion, Vector2(1600,704), 17.0, tags, session.terrain_query, session.terrain_context_service, [], false, [], false, retreat)
	_check(not ordinary.get("ok",false), "old rejoin candidates cannot clear this shore")
	_check(safe.get("ok",false) and str(safe.get("candidate_id", "")).begins_with("recovery_"), "current-aware rejoin keeps a validated retreat within the same search")
	_check(int(safe.get("candidate_count", 99)) <= 6 and int(safe.get("segments_simulated", 999)) <= 360, "fallback search stays within six candidates and six-second predictions")
	session.configure_full_ai_factions(["player", "enemy"])
	var unit_id := "unit.player.l02.yukikaze"
	var contacts := 0
	var contract_failures := 0
	var stalls := 0
	var initial_window_stalls := 0
	var budget_ok := true
	var position_after_contact_window := Vector2.ZERO
	var counts := {}
	var full_battle := "--full-battle" in OS.get_cmdline_user_args()
	for index in range(6000 if full_battle else 1000):
		if session.state["phase"] != "Running": break
		for event in session.advance_tick(0.1):
			var kind := str(event.get("event_type", ""))
			if kind in ["UnitTerrainCollision", "NavigationCollisionContractViolated", "NavigationStalled", "NavigationRecoveryStarted", "NavigationRecoveryCompleted", "WeaponFired"]:
				counts[kind] = int(counts.get(kind, 0)) + 1
			if kind == "NavigationStalled": print("L02_STALL ", event)
			if kind == "TrajectoryPlanned" and str(event.get("mode", "")) != "EmergencyEvasion":
				budget_ok = budget_ok and int(event.get("candidate_count", 0)) <= 6
			if str(event.get("unit_id", "")) != unit_id: continue
			if kind == "UnitTerrainCollision": contacts += 1
			if kind == "NavigationCollisionContractViolated": contract_failures += 1
			if kind == "NavigationStalled":
				stalls += 1
				if int(session.state["tick_index"]) <= 1000: initial_window_stalls += 1
		if int(session.state["tick_index"]) == 695:
			position_after_contact_window = session.state["units_by_id"][unit_id]["position"]
	var unit: Dictionary = session.state["units_by_id"][unit_id]
	_check(budget_ok, "ordinary planned candidates remain within six")
	_check(contacts == 0 and contract_failures == 0, "snow destroyer has no shore contact or committed-plan violation")
	_check(initial_window_stalls == 0, "snow destroyer has no stalled recovery in the original 100-second failure window")
	_check((unit["position"] as Vector2).distance_to(position_after_contact_window) > 50.0, "snow destroyer continues moving after the old tick 695 contact window")
	if full_battle: _check(session.state["phase"] == "Finished", "same-seed extended run reaches an authoritative result within 600 seconds")
	print("L02_CURRENT_REJOIN ticks=", session.state["tick_index"], " position=", unit["position"], " stage=", unit["navigation_state"].get("recovery", {}).get("stage", ""), " snow_stalls_total=", stalls, " events=", counts)
	for failure in failures: push_error("FAIL: " + failure)
	print("PASS: %d current/rejoin checks" % checks if failures.is_empty() else "FAILED: %d of %d current/rejoin checks" % [failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
