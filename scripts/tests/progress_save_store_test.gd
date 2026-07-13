extends SceneTree

const ProgressSaveStore = preload("res://scripts/infrastructure/persistence/progress_save_store.gd")

var checks := 0
var failures: Array[String] = []
var base_path := "user://progress_save_store_test.json"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()
	var store = ProgressSaveStore.new()
	var first := _document(["ship.ward"], [])
	_check(store.save(base_path, first), "first verified save succeeds")
	var loaded := store.load_best(base_path)
	_check(int(loaded.get("revision", 0)) == 1 and "ship.ward" in loaded.get("unlocked_ship_ids", []), "primary slot loads revision one")

	var second := _document(["ship.ward", "ship.anshan"], ["level.challenge.s01"])
	_check(store.save(base_path, second), "second verified save succeeds")
	loaded = store.load_best(base_path)
	_check(int(loaded.get("revision", 0)) == 2 and "ship.anshan" in loaded.get("unlocked_ship_ids", []), "new primary slot has the highest revision")
	_check(FileAccess.file_exists("%s.backup" % base_path), "previous valid primary remains as backup")

	_write_text(base_path, "{broken")
	loaded = store.load_best(base_path)
	_check(int(loaded.get("revision", 0)) == 1 and "ship.ward" in loaded.get("unlocked_ship_ids", []), "corrupt primary recovers from valid backup")

	_check(store.save(base_path, second), "save after recovery succeeds")
	var newest := store.load_best(base_path)
	_write_text("%s.next" % base_path, JSON.stringify(newest))
	_write_text(base_path, "{broken")
	loaded = store.load_best(base_path)
	_check(int(loaded.get("revision", 0)) == int(newest.get("revision", 0)), "verified residual next slot recovers interrupted promotion")

	var tampered := newest.duplicate(true)
	tampered["unlocked_ship_ids"] = ["ship.invalid"]
	_write_text("%s.next" % base_path, JSON.stringify(tampered))
	loaded = store.load_best(base_path)
	_check("ship.invalid" not in loaded.get("unlocked_ship_ids", []), "checksum rejects a tampered candidate")
	var unsigned_candidate := newest.duplicate(true)
	unsigned_candidate.erase("checksum_sha256")
	unsigned_candidate["revision"] = 999
	_write_text("%s.next" % base_path, JSON.stringify(unsigned_candidate))
	loaded = store.load_best(base_path)
	_check(int(loaded.get("revision", 0)) != 999, "unsigned residual candidate cannot override a trusted slot")

	_cleanup()
	if failures.is_empty():
		print("PASS: %d progress save store checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error("FAIL: %s" % failure)
		print("FAILED: %d of %d progress save store checks" % [failures.size(), checks])
		quit(1)


func _document(ships: Array, challenges: Array) -> Dictionary:
	return {"schema_version":1, "profile_id":"default", "unlocked_ship_ids":ships, "completed_challenge_level_ids":challenges}


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _cleanup() -> void:
	for path in [base_path, "%s.next" % base_path, "%s.backup" % base_path]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
