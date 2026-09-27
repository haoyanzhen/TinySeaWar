extends SceneTree

const BattleSession = preload("res://scripts/application/battle_session.gd")
var failures: Array[String] = []
var checks := 0

func _init() -> void:
	call_deferred("_run")

func _command(id: String, kind: String, extra: Dictionary = {}) -> Dictionary:
	var command := {"command_id": id, "command_type": kind, "issuer_id": "player", "issuer_type": "Player", "unit_id": "unit.player.s01.warspite"}
	command.merge(extra)
	return command

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _run() -> void:
	var session = BattleSession.new(root.get_node("DataRegistry").registry)
	_check(session.create_battle("level.challenge.s01", 9301).get("ok", false), "battle creates")
	var unit: Dictionary = session.state["units_by_id"]["unit.player.s01.warspite"]
	session.pause()
	var before: Dictionary = session.state.duplicate(true)
	_check(session.get_operation_status(unit["entity_id"])["primary_reason"] != "BATTLE_NOT_RUNNING", "paused weapon inspection remains available")
	_check(session.get_primary_aim_status(unit["entity_id"], unit["position"] + Vector2(200, 0)).get("reason_code") != "BATTLE_NOT_RUNNING", "paused aim uses ordinary weapon legality")
	_check(session.queue_command(_command("z-first", "SetUnitControlState", {"secondary_auto_fire_enabled": false})).get("staged", false), "paused commands explicitly staged")
	session.queue_command(_command("a-last", "SetUnitControlState", {"secondary_auto_fire_enabled": true}))
	_check(session.get_planned_control_state(unit["entity_id"])["secondary_auto_fire_enabled"], "toggle preview follows authored order")
	session.queue_command(_command("cancel-me", "CastSkill"))
	_check(session.cancel_pending_player_command("cancel-me").get("accepted", false), "pending action can be cancelled")
	_check(not session.cancel_pending_player_command("cancel-me").get("accepted", false), "cancel cannot repeat")
	var detached: Array = session.pending_player_commands()
	detached[0]["secondary_auto_fire_enabled"] = true
	_check(not session.pending_player_commands()[0]["secondary_auto_fire_enabled"], "plan inspection cannot mutate commands")
	for _index in range(10): session.advance_tick(0.1)
	_check(session.state == before, "pause freezes whole authoritative state including time cooldown and projectiles")
	session.resume()
	_check(session.state["tick_index"] == before["tick_index"], "resume alone does not advance simulation")
	session.advance_tick(0.1)
	_check(unit["secondary_auto_fire_enabled"], "resume executes staged controls FIFO despite lexical IDs")
	_check(session.pending_player_commands().is_empty(), "staged plan consumed once")
	session.pause()
	unit["skill_state"]["cooldown_remaining"] = 20.0
	session.queue_command(_command("cooldown", "CastSkill", {"target_ref": {}}))
	session.resume()
	var events: Array = session.advance_tick(0.1)
	_check(events.any(func(event): return event.get("event_type") == "CommandRejected" and event.get("reason_code") == "SKILL_ON_COOLDOWN"), "resume revalidates public cooldown rules")
	_check(not session.advance_tick(0.1).any(func(event): return event.get("event_type") == "CommandRejected" and event.get("command_id") == "cooldown"), "rejected order never silently retries")
	session.state["phase"] = "Finished"
	_check(not session.queue_command(_command("late", "CastSkill")).get("accepted", false), "settled battle rejects new orders")
	print("Tactical pause: %d/%d passed" % [checks - failures.size(), checks])
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
