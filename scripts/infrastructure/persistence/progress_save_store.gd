class_name ProgressSaveStore
extends RefCounted


func load_best(primary_path: String) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for path in _paths(primary_path):
		var document := _read_valid(path, path != "%s.next" % primary_path)
		if not document.is_empty():
			candidates.append({"path": path, "document": document})
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var revision_a := int(a["document"].get("revision", 0))
		var revision_b := int(b["document"].get("revision", 0))
		if revision_a == revision_b:
			return str(a["path"]) == primary_path
		return revision_a > revision_b
	)
	return candidates[0]["document"].duplicate(true)


func save(primary_path: String, document: Dictionary) -> bool:
	var next_path := "%s.next" % primary_path
	var backup_path := "%s.backup" % primary_path
	var prepared := document.duplicate(true)
	prepared["revision"] = maxi(int(load_best(primary_path).get("revision", 0)), int(prepared.get("revision", 0))) + 1
	prepared.erase("checksum_sha256")
	prepared["checksum_sha256"] = _checksum(prepared)
	if not _write_document(next_path, prepared):
		return false
	var verified := _read_valid(next_path, false)
	if verified.is_empty() or str(verified.get("checksum_sha256", "")) != str(prepared.get("checksum_sha256", "")):
		_remove(next_path)
		return false

	# Keep one known-good slot throughout the switch. If promotion fails, startup
	# recovery can still select either the backup or the verified next slot.
	_remove(backup_path)
	if FileAccess.file_exists(primary_path):
		if not _rename(primary_path, backup_path):
			return false
	if not _rename(next_path, primary_path):
		return false
	return true


func is_valid_document(document: Variant) -> bool:
	if document is not Dictionary:
		return false
	if int(document.get("schema_version", 0)) < 1:
		return false
	if document.get("unlocked_ship_ids", null) is not Array:
		return false
	if document.get("completed_challenge_level_ids", []) is not Array:
		return false
	var checksum := str(document.get("checksum_sha256", ""))
	if checksum.is_empty():
		return true # Legacy schema-1 saves are migrated on their next successful write.
	var unsigned: Dictionary = document.duplicate(true)
	unsigned.erase("checksum_sha256")
	return checksum == _checksum(unsigned)


func _read_valid(path: String, allow_legacy: bool = true) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {}
	var parsed = parser.data
	if parsed is Dictionary and not allow_legacy and str(parsed.get("checksum_sha256", "")).is_empty():
		return {}
	return parsed if is_valid_document(parsed) else {}


func _write_document(path: String, document: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(document, "  "))
	file.flush()
	file.close()
	return FileAccess.file_exists(path)


func _checksum(document: Dictionary) -> String:
	# Hash the JSON-normalized representation so numeric types are identical
	# before and after Godot parses the persisted document.
	var normalized = JSON.parse_string(JSON.stringify(document))
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify(normalized).to_utf8_buffer())
	return context.finish().hex_encode()


func _paths(primary_path: String) -> Array[String]:
	return [primary_path, "%s.next" % primary_path, "%s.backup" % primary_path]


func _remove(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return true
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK


func _rename(from_path: String, to_path: String) -> bool:
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(from_path), ProjectSettings.globalize_path(to_path)) == OK
