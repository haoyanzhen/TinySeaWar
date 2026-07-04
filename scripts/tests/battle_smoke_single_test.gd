extends SceneTree

const ConfigRegistry = preload("res://scripts/infrastructure/data/config_registry.gd")
const BattleSession = preload("res://scripts/application/battle_session.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var level_id := str(args[0]) if not args.is_empty() else "level.prototype_harbor_3v3"
	var maximum_ticks := int(args[1]) if args.size() > 1 else 4400
	var registry = ConfigRegistry.new()
	if not registry.load_all():
		push_error("Configuration errors: %s" % registry.errors)
		quit(1)
		return
	var session = BattleSession.new(registry)
	var creation: Dictionary = session.create_battle(level_id, 20260614)
	if not bool(creation.get("ok", false)):
		push_error("Battle creation failed: %s" % creation.get("errors", []))
		quit(1)
		return
	if args.size() <= 2 or str(args[2]) != "default_control":
		session.configure_full_ai_factions(["player", "enemy"])
	var profile_result: Dictionary = session.configure_ai_profile("ai.profile.standard")
	if not bool(profile_result.get("accepted", false)):
		push_error("AI profile configuration failed: %s" % profile_result)
		quit(1)
		return
	var event_types := {}
	var diagnostic_events: Array = []
	var ticks := 0
	while session.state.get("phase", "") == "Running" and ticks < maximum_ticks:
		for event in session.advance_tick(0.1):
			var event_type := str(event.get("event_type", ""))
			event_types[event_type] = true
			if event_type in ["FacilityControlDeclared", "FacilityControlCompleted", "FacilityServiceStarted", "FacilityServiceCompleted", "FacilityActionInterrupted", "CommandRejected"]:
				diagnostic_events.append(event.duplicate(true))
		ticks += 1
	var passed: bool = session.state.get("phase", "") == "Finished" and event_types.has("WeaponFired") and event_types.has("AttackResolved") and event_types.has("BattleFinished")
	print("SINGLE_SMOKE level=%s phase=%s ticks=%d duration=%.1f result=%s" % [level_id, session.state.get("phase", ""), ticks, float(session.state.get("elapsed_time", 0.0)), session.state.get("result", {})])
	print("SINGLE_SMOKE_DIAGNOSTICS=%s" % JSON.stringify(diagnostic_events))
	if not passed: push_error("Single battle smoke did not reach the complete combat chain")
	quit(0 if passed else 1)
