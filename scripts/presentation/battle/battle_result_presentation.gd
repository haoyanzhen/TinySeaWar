extends RefCounted

## Pure presentation of the authoritative result; never infer winners from HP.
static func describe(result: Dictionary) -> Dictionary:
	if result.is_empty(): return {}
	var reason := str(result.get("reason", ""))
	var winner := str(result.get("winner_faction", ""))
	var view := {"kind": "Invalid", "title": "本局无效", "subtitle": "本局未形成有效战斗结果。", "color": Color("#9aaeb6")}
	if reason == "LEVEL_TECHNICAL_LIMIT":
		view["subtitle"] = "达到技术保护上限；本局不判定任务胜负，也不写入进度。"
	elif winner == "player":
		view = {"kind": "Victory", "title": "胜利", "subtitle": "已达成胜利条件。", "color": Color("#70db84")}
	elif winner == "enemy":
		view = {"kind": "Defeat", "title": "失败", "subtitle": "本次作战未能达成目标。", "color": Color("#ff9a8c")}
	elif winner.is_empty() and reason in ["FLAGSHIP_SUNK_SIMULTANEOUS", "TIME_LIMIT", "DRAW"]:
		view = {"kind": "Draw", "title": "平局", "subtitle": "双方未分出胜负。", "color": Color("#8dd9e8")}
	if reason == "FLAGSHIP_SUNK_SIMULTANEOUS":
		view["subtitle"] = "双方旗舰在同一时刻沉没。"
	elif reason == "FLAGSHIP_SUNK":
		view["subtitle"] = "敌方旗舰已经失去作战能力。" if winner == "player" else "己方旗舰失去作战能力。"
	elif reason == "TIME_LIMIT":
		view["subtitle"] = "时间耗尽，按双方剩余总耐久比例结算。"
	var summary := str(result.get("reason_summary", ""))
	if not summary.is_empty(): view["subtitle"] = summary
	return view
