extends SceneTree

const Store = preload("res://scripts/infrastructure/persistence/progress_save_store.gd")
var failures: Array[String] = []
var checks := 0

class InterruptedStore extends RefCounted:
	var actual = preload("res://scripts/infrastructure/persistence/progress_save_store.gd").new()
	var writes := 0
	var fail_writes := 2
	var stale_read := false
	func save(path: String, document: Dictionary) -> bool:
		writes += 1
		if fail_writes > 0:
			fail_writes -= 1
			return false
		return actual.save(path, document)
	func load_best(path: String) -> Dictionary:
		return {"unlocked_ship_ids": [], "completed_challenge_level_ids": []} if stale_read else actual.load_best(path)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var flow = load("res://scripts/application/game_flow.gd").new()
	var path := "/tmp/tinyseawar-progress-retry-%d.json" % Time.get_ticks_usec()
	var store := InterruptedStore.new()
	flow._progress_path = path
	flow._progress_store = store
	flow._apply_loaded_progress({"schema_version": 1, "unlocked_ship_ids": ["ship.argus", "ship.future"], "completed_challenge_level_ids": []})
	_check(flow.progress_save_state()["status"] == "Idle", "initial status quiet")
	_check(flow.retry_progress_save() and store.writes == 0, "idle retry does not write")
	_check(not flow.record_level_victory("level.challenge.s01"), "first failed write reported")
	_check(flow.is_ship_unlocked("ship.anshan"), "failed save preserves current reward")
	_check("level.challenge.s01" in flow.completed_challenge_level_ids, "failed save preserves chapter completion")
	_check(flow.progress_save_state()["status"] == "Failed" and flow.progress_save_state()["can_retry"], "failed result exposes retry")
	_check(not FileAccess.file_exists(path), "simulated failure did not touch user save or temp primary")
	_check(not flow.record_level_victory("level.challenge.s02"), "second victory can accumulate while storage unavailable")
	_check(flow.progress_save_state()["pending_level_ids"].size() == 2, "pending victories accumulate")
	var before: Array = flow.unlocked_ship_ids.duplicate()
	_check(flow.retry_progress_save(), "retry persists accumulated facts")
	_check(flow.unlocked_ship_ids == before, "retry does not replay rewards")
	_check(flow.progress_save_state()["status"] == "Saved" and not flow.progress_save_state()["can_retry"], "readback confirms saved status")
	var persisted: Dictionary = Store.new().load_best(path)
	_check("ship.future" in persisted.get("unlocked_ship_ids", []), "unknown prior fact survives persistence")
	_check(persisted.get("completed_challenge_level_ids", []).size() == 2, "both victories persisted once")
	var writes_before := store.writes
	_check(flow.retry_progress_save() and store.writes == writes_before, "repeated retry does not write again")
	var reloaded = load("res://scripts/application/game_flow.gd").new()
	reloaded._progress_path = path
	reloaded._load_unlocked_ships()
	_check(reloaded.is_ship_unlocked("ship.anshan") and reloaded.is_ship_unlocked("ship.aurora"), "fresh session restores retried rewards")
	store.stale_read = true
	_check(not flow.record_level_victory("level.challenge.s03"), "write returning success with stale read is not trusted")
	_check(flow.progress_save_state()["can_retry"] and flow.is_ship_unlocked("ship.sirius"), "unverified write retains pending facts")
	store.stale_read = false
	_check(flow.retry_progress_save(), "readback failure remains recoverable")
	_check(flow.unlocked_ship_ids.count("ship.sirius") == 1, "recovery has no duplicate reward")
	var menu = load("res://scripts/presentation/menu/main_menu.gd").new()
	root.add_child(menu)
	menu._on_progress_save_status_changed({"status": "Failed", "message": "进度保存失败", "can_retry": true})
	_check(menu.progress_failure_banner.visible and not menu.progress_retry_button.disabled, "menu preserves visible failure and retry entry")
	menu._show_tutorial()
	_check(menu.progress_failure_banner.visible, "changing menu pages does not dismiss save failure")
	menu._on_progress_save_status_changed({"status": "Saved", "message": "进度已保存", "can_retry": false})
	_check(not menu.progress_failure_banner.visible, "successful save removes failure banner")
	menu.free()
	flow.free()
	reloaded.free()
	for suffix in ["", ".next", ".backup"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)
	for failure in failures:
		push_error(failure)
	print("Progress save retry: %d/%d passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
