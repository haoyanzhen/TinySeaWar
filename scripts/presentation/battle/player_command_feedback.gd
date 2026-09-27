extends RefCounted

const UiText = preload("res://scripts/presentation/ui_text.gd")
const VISIBLE_SECONDS := 3.0
const MERGE_SECONDS := 1.5
const HISTORY_LIMIT := 8

var entries: Array[Dictionary] = []


func clear() -> void:
	entries.clear()


func reject(command: Dictionary, reason_code: String, now_seconds: float) -> bool:
	if str(command.get("issuer_type", "Player")) != "Player" or str(command.get("issuer_id", "player")) != "player":
		return false
	var command_type := str(command.get("command_type", ""))
	# Tutorial bookkeeping and the temporary aim lock are not player actions.
	if command_type == "RecordTutorialAction" or command.has("primary_auto_fire_suspended"):
		return false
	var partial: bool = not command.get("successful_unit_ids", []).is_empty()
	var failed_count: int = command.get("rejected_unit_ids", []).size()
	var total_count: int = failed_count + command.get("successful_unit_ids", []).size()
	var key := "%s:%s:%s:%d:%d" % [command_type, reason_code, partial, failed_count, total_count]
	var message := "%s未执行：%s" % [command_name(command_type), UiText.reason_name(reason_code)]
	if partial: message = "部分舰艇%s未执行（%d/%d）：%s" % [command_name(command_type), failed_count, total_count, UiText.reason_name(reason_code)]
	for entry in entries:
		if str(entry["key"]) == key and now_seconds - float(entry["last_at"]) <= MERGE_SECONDS:
			entry["count"] = int(entry["count"]) + 1
			entry["last_at"] = now_seconds
			return true
	entries.push_front({"key": key, "command_type": command_type, "reason_code": reason_code,
		"text": message,
		"count": 1, "last_at": now_seconds})
	if entries.size() > HISTORY_LIMIT:
		entries.resize(HISTORY_LIMIT)
	return true


func current(now_seconds: float) -> Dictionary:
	var latest: Dictionary = {}
	for entry in entries:
		if now_seconds - float(entry["last_at"]) <= VISIBLE_SECONDS and (latest.is_empty() or float(entry["last_at"]) > float(latest["last_at"])):
			latest = entry
	if latest.is_empty(): return {}
	var result := latest.duplicate(true)
	if int(result["count"]) > 1:
		result["text"] = "%s（%d 次）" % [result["text"], result["count"]]
	return result


static func command_name(command_type: String) -> String:
	match command_type:
		"MoveUnits", "AppendMoveWaypoint", "ClearMoveRoute": return "航行指令"
		"FocusTarget": return "集火指令"
		"FirePrimaryWeapon": return "主要武器"
		"CastSkill": return "技能"
		"SwitchAmmo": return "弹药切换"
		"SetUnitControlState": return "辅助开关"
		"SetSubmarineDepth": return "深度指令"
		_: return "指令"
