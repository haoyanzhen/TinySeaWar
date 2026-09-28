extends SceneTree

var checks := 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _run() -> void:
	var scene: PackedScene = load("res://scenes/battle/prototype_battle.tscn")
	var battle = scene.instantiate()
	root.add_child(battle)
	battle.set_process(false)
	battle.session.pause()
	var unit_id := str(battle.session.get_player_slots()[0]["unit_id"])
	battle.selected_unit_id = unit_id
	var original_session = battle.session
	var key := InputEventKey.new()
	key.keycode = KEY_R
	key.pressed = true
	battle._unhandled_input(key)
	_check(battle.session == original_session, "R does not restart")
	var original: bool = battle.session.get_planned_control_state(unit_id)["secondary_auto_fire_enabled"]
	battle._toggle_control_state("secondary_auto_fire_enabled", "副武器", false)
	battle._toggle_control_state("secondary_auto_fire_enabled", "副武器", false)
	_check(battle.session.get_planned_control_state(unit_id)["secondary_auto_fire_enabled"] == original, "double toggle uses planned state")
	var pending: Array = battle.session.pending_player_commands()
	_check(pending.size() >= 2 and pending[-1]["command_id"] != pending[-2]["command_id"], "same-tick UI commands have distinct IDs")
	battle._update_hud()
	_check(battle.battle_hud.pause_panel.visible, "pause tools visible")
	_check(not battle.battle_hud.restart_button.visible, "result buttons remain distinct")
	battle.battle_hud._pause_action("重新开始")
	_check(battle.battle_hud.pause_confirmation.visible and battle.session == original_session, "restart waits for confirmation")
	battle.battle_hud.pause_confirmation.hide()
	battle.battle_hud.pending_cancel_requested.emit(str(pending[-1]["command_id"]))
	_check(battle.session.pending_player_commands().size() == pending.size() - 1, "cancel signal removes exact staged order")
	battle.operation_mode = battle.OperationMode.TARGETING_SKILL
	battle._reject_player_action("FirePrimaryWeapon", "WEAPON_RELOADING")
	battle._update_hud()
	_check(not battle.battle_hud.snapshot.get("command_feedback", {}).is_empty(), "rejection reaches passive HUD")
	_check(battle.operation_mode == battle.OperationMode.TARGETING_SKILL and battle.selected_unit_id == unit_id, "feedback does not change targeting or selection")
	_check(battle.command_feedback.current(Time.get_ticks_msec() / 1000.0 + 4.0).is_empty(), "feedback expires on real time while paused")
	battle._consume_events([{"event_type":"CommandRejected", "issuer_type":"AI", "issuer_id":"enemy", "command_type":"CastSkill", "reason_code":"SKILL_ON_COOLDOWN"}])
	_check(battle.command_feedback.entries.size() == 1, "AI failures do not enter player feedback")
	battle.battle_hud.resume_requested.emit()
	_check(battle.session.state["phase"] == "Running", "continue signal resumes")
	battle._select_in_rect(Rect2(Vector2(-10000, -10000), Vector2(30000, 30000)), battle.session.snapshot("player", false))
	_check(battle._selected_live_ids().size() == battle.session.get_player_slots().size(), "drag selection selects all living friendly ships only")
	var selected_ids: Array = battle._selected_live_ids()
	battle._select_in_rect(Rect2(Vector2(-10000, -10000), Vector2.ONE), battle.session.snapshot("player", false), true)
	_check(battle._selected_live_ids() == selected_ids, "shift drag preserves earlier selection")
	_check(battle.battle_hud.interaction_controls.size() == 32, "portraits and operation cards use real GUI buttons")
	var target_id := ""
	for id in battle.session.state["units_by_id"]:
		if battle.session.state["units_by_id"][id]["faction_id"] == "enemy":
			target_id = id
			break
	battle.session.state["visible_by_faction"]["player"][target_id] = true
	var batch: Dictionary = battle.session._apply_command({"command_id":"group-check", "command_type":"FocusTarget", "issuer_id":"player", "issuer_type":"Player", "unit_ids":[selected_ids[0], target_id, selected_ids[0]], "target_unit_id":target_id, "group_order_id":"test-group"})
	_check(batch.get("successful_unit_ids", []).size() == 1 and batch.get("rejected_unit_ids", []).size() == 1, "group order validates ownership and deduplicates members")
	battle.command_feedback.clear()
	batch.merge({"command_type":"FocusTarget", "issuer_type":"Player", "issuer_id":"player"})
	battle.command_feedback.reject(batch, str(batch.get("reason_code")), 1.0)
	_check(str(battle.command_feedback.current(1.0).get("text", "")).contains("部分舰艇") and str(battle.command_feedback.current(1.0).get("text", "")).contains("1/2"), "partial failure reports subset and count")
	battle.battle_hud.snapshot["result"] = {"winner_faction":"player", "reason":"FLAGSHIP_SUNK"}
	battle.battle_hud.snapshot["progress_save_state"] = {"status":"Failed", "can_retry":true}
	battle.battle_hud._sync_interaction_controls()
	_check(battle.battle_hud.retry_save_button.visible, "failed save exposes persistent retry control")
	battle.session.pause()
	battle._queue_primary_auto_suspend(true)
	battle._queue_primary_auto_suspend(false)
	var locks: Array = battle.session.pending_player_commands().filter(func(command): return command.has("primary_auto_fire_suspended"))
	_check(not battle.session.cancel_pending_player_command(str(locks[-1]["command_id"])).get("accepted", false), "backend refuses cancelling internal aim release")
	battle._update_hud()
	_check(battle.battle_hud.snapshot["pending_player_commands"].all(func(command): return not command.has("primary_auto_fire_suspended") and command.get("command_type") != "RecordTutorialAction"), "frontend hides aim locks and tutorial bookkeeping")
	battle.battle_hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	for width in [1280.0, 1600.0, 1920.0]:
		battle.battle_hud.size = Vector2(width, 1080.0)
		battle.battle_hud._sync_interaction_controls()
		var objective_rect: Rect2 = battle.battle_hud.objective_scroll.get_rect()
		_check(battle.battle_hud.interaction_controls.slice(0, 24).all(func(button): return not objective_rect.intersects(button.get_rect())), "objective avoids every actual roster button at width %d" % width)
	battle.session.resume()
	battle.session.advance_tick(0.1)
	_check(not battle.session.state["units_by_id"][battle.selected_unit_id].get("primary_auto_fire_suspended", false), "internal aim release executes after protected cancellation")
	print("Tactical pause UI: %d/%d passed" % [checks - failures.size(), checks])
	for failure in failures: push_error(failure)
	battle.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
