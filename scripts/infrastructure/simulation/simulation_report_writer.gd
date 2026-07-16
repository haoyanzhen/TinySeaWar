class_name SimulationReportWriter
extends RefCounted


func write_all(output_directory: String, result: Dictionary) -> Dictionary:
	var absolute_directory := ProjectSettings.globalize_path(output_directory)
	var error := DirAccess.make_dir_recursive_absolute(absolute_directory)
	if error != OK:
		return {"ok": false, "errors": ["Cannot create simulation output directory: %s" % output_directory]}
	var errors: Array[String] = []
	_write_text(output_directory.path_join("resolved_manifest.json"), JSON.stringify(result.get("resolved_manifest", {}), "  "), errors)
	_write_text(output_directory.path_join("metadata.json"), JSON.stringify(result.get("metadata", {}), "  "), errors)
	_write_text(output_directory.path_join("aggregate.json"), JSON.stringify(result.get("aggregate", {}), "  "), errors)
	_write_runs(output_directory.path_join("runs.jsonl"), result.get("runs", []), errors)
	_write_text(output_directory.path_join("summary.csv"), _csv(result), errors)
	_write_text(output_directory.path_join("unit_damage.csv"), _unit_damage_csv(result), errors)
	_write_text(output_directory.path_join("unit_damage.md"), _unit_damage_markdown(result), errors)
	_write_text(output_directory.path_join("report.md"), _markdown(result), errors)
	return {"ok": errors.is_empty(), "errors": errors, "output_directory": output_directory}


func _write_runs(path: String, runs: Array, errors: Array[String]) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		errors.append("Cannot write %s" % path)
		return
	for run in runs:
		file.store_line(JSON.stringify(run))


func _write_text(path: String, content: String, errors: Array[String]) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		errors.append("Cannot write %s" % path)
		return
	file.store_string(content)


func _csv(result: Dictionary) -> String:
	var lines := ["run_id,scenario_id,level_definition_id,seed,side_variant,end_state,winner_faction,winner_lineup,finish_reason,duration,ticks_executed,enemy_damage_before_engagement,policy_command_rejections"]
	for run in result.get("runs", []):
		lines.append(",".join([
			_csv_cell(run.get("run_id", "")),
			_csv_cell(run.get("scenario_id", "")),
			_csv_cell(run.get("level_definition_id", "")),
			str(int(run.get("seed", 0))),
			_csv_cell(run.get("side_variant", "")),
			_csv_cell(run.get("end_state", "")),
			_csv_cell(run.get("winner_faction", "")),
			_csv_cell(run.get("winner_lineup", "")),
			_csv_cell(run.get("finish_reason", "")),
			"%.3f" % float(run.get("duration", 0.0)),
			str(int(run.get("ticks_executed", 0))),
			"%.3f" % float(run.get("enemy_damage_before_engagement", 0.0)),
			str(int(run.get("policy_command_rejections", 0))),
		]))
	return "\n".join(lines) + "\n"


func _csv_cell(value: Variant) -> String:
	var text := str(value)
	return '"%s"' % text.replace('"', '""') if "," in text or '"' in text or "\n" in text else text


func _unit_damage_csv(result: Dictionary) -> String:
	var categories := ["main_gun", "secondary_gun", "torpedo", "aviation", "anti_air", "anti_submarine", "skill", "buff", "mine", "other"]
	var header := ["run_id", "scenario_id", "seed", "side_variant", "lineup_id", "faction_id", "unit_id", "definition_id", "display_name", "damage_dealt", "damage_taken", "overkill_damage", "contribution_damage", "shots", "hits"]
	header.append_array(categories)
	var lines := [",".join(header)]
	for run in result.get("runs", []):
		var unit_ids: Array = run.get("units", {}).keys()
		unit_ids.sort()
		for unit_id in unit_ids:
			var unit: Dictionary = run["units"][unit_id]
			var row := [
				_csv_cell(run.get("run_id", "")), _csv_cell(run.get("scenario_id", "")), str(run.get("seed", 0)),
				_csv_cell(run.get("side_variant", "")), _csv_cell(unit.get("lineup_id", "")), _csv_cell(unit.get("faction_id", "")),
				_csv_cell(unit_id), _csv_cell(unit.get("definition_id", "")), _csv_cell(unit.get("display_name", "")),
				"%.3f" % float(unit.get("damage_dealt", 0.0)), "%.3f" % float(unit.get("damage_taken", 0.0)),
				"%.3f" % float(unit.get("overkill_damage", 0.0)), "%.3f" % float(unit.get("contribution_damage", 0.0)),
				str(unit.get("shots", 0)), str(unit.get("hits", 0)),
			]
			for category in categories:
				row.append("%.3f" % float(unit.get("damage_by_category", {}).get(category, 0.0)))
			lines.append(",".join(row))
	return "\n".join(lines) + "\n"


func _unit_damage_markdown(result: Dictionary) -> String:
	var lines: Array[String] = ["# 逐局单舰伤害", "", "伤害由 `damage_statistics.gd` 统计；直接伤害为有效伤害，Buff 贡献单列且不重复计入。", ""]
	for run in result.get("runs", []):
		lines.append("## %s / seed %s / %s" % [run.get("scenario_id", ""), run.get("seed", 0), run.get("side_variant", "")])
		lines.append("")
		lines.append("| 阵容 | 舰船 | 阵营 | 总伤害 | 承伤 | Buff贡献 | 主炮 | 副炮 | 鱼雷 | 航空 | 技能 |")
		lines.append("| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
		var unit_ids: Array = run.get("units", {}).keys()
		unit_ids.sort()
		for unit_id in unit_ids:
			var unit: Dictionary = run["units"][unit_id]
			var categories: Dictionary = unit.get("damage_by_category", {})
			lines.append("| %s | %s | %s | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f |" % [
				unit.get("lineup_id", ""), unit.get("display_name", unit_id), unit.get("faction_id", ""),
				float(unit.get("damage_dealt", 0.0)), float(unit.get("damage_taken", 0.0)), float(unit.get("contribution_damage", 0.0)),
				float(categories.get("main_gun", 0.0)), float(categories.get("secondary_gun", 0.0)), float(categories.get("torpedo", 0.0)),
				float(categories.get("aviation", 0.0)), float(categories.get("skill", 0.0)),
			])
		lines.append("")
	return "\n".join(lines)


func _markdown(result: Dictionary) -> String:
	var metadata: Dictionary = result.get("metadata", {})
	var aggregate: Dictionary = result.get("aggregate", {})
	var duration: Dictionary = aggregate.get("duration", {})
	var interval: Array = aggregate.get("player_win_rate_95", [0.0, 0.0])
	var evaluation: Dictionary = aggregate.get("win_rate_evaluation", {})
	var lines: Array[String] = [
		"# 战斗模拟报告",
		"",
		"- 实验：`%s`" % metadata.get("experiment_id", ""),
		"- 说明：%s" % metadata.get("description", ""),
		"- 类型：`%s`" % metadata.get("simulation_kind", ""),
		"- 玩家侧策略：`%s`" % metadata.get("player_policy_id", ""),
		"- 敌方侧策略：`%s`" % metadata.get("enemy_policy_id", ""),
		"- 阵容与出生侧交换：`%s`" % ("是" if metadata.get("side_swap", false) else "否"),
		"- Godot：`%s`" % metadata.get("godot_version", ""),
		"- 固定步长：`%.3fs`" % float(metadata.get("tick_seconds", 0.0)),
		"- 墙钟耗时：`%.3fs`" % float(metadata.get("wall_time_seconds", 0.0)),
		"",
		"## 结果摘要",
		"",
		"| 指标 | 结果 |",
		"| --- | ---: |",
		"| 计划运行 | %d |" % int(aggregate.get("planned_runs", 0)),
		"| 正常结束 | %d |" % int(aggregate.get("finished_runs", 0)),
		"| 完成率 | %.1f%% |" % (float(aggregate.get("completion_rate", 0.0)) * 100.0),
		"| 玩家侧胜率 | %.1f%% |" % (float(aggregate.get("player_win_rate", 0.0)) * 100.0),
		"| 原玩家阵容胜率 | %.1f%% |" % (float(aggregate.get("original_player_lineup_win_rate", 0.0)) * 100.0),
		"| 玩家出生侧胜率 | %.1f%% |" % (float(aggregate.get("spawn_side_player_win_rate", 0.0)) * 100.0),
		"| 设施使用局占比 | %.1f%% |" % (float(aggregate.get("facility_usage_rate", 0.0)) * 100.0),
		"| 超时率 | %.1f%% |" % (float(aggregate.get("timeout_rate", 0.0)) * 100.0),
		"| 行为异常/局 | %.2f |" % float(aggregate.get("behavior_anomalies_per_run", 0.0)),
		"| 教学解锁前敌方伤害 | %.2f |" % float(aggregate.get("enemy_damage_before_engagement", 0.0)),
		"| 教学策略命令拒绝 | %d |" % int(aggregate.get("policy_command_rejections", 0)),
		"| 玩家侧胜率 95%% 区间 | %.1f%% - %.1f%% |" % [float(interval[0]) * 100.0, float(interval[1]) * 100.0],
		"| 平均战斗时长 | %.2fs |" % float(duration.get("mean", 0.0)),
		"| 中位战斗时长 | %.2fs |" % float(duration.get("median", 0.0)),
		"| P10 / P90 时长 | %.2fs / %.2fs |" % [float(duration.get("p10", 0.0)), float(duration.get("p90", 0.0))],
		"",
		"结束状态：`%s`" % JSON.stringify(aggregate.get("result_counts", {})),
		"",
		"结束原因：`%s`" % JSON.stringify(aggregate.get("finish_reason_counts", {})),
		"",
	]
	if not evaluation.is_empty():
		lines.append_array([
			"## 胜率结算",
			"",
			"本实验固定运行 20 场不同种子；是否达标只读取本战斗统计报告的聚合结果，不以单场日志代替结算。",
			"",
			"| 结算项 | 结果 |",
			"| --- | ---: |",
			"| 有效场次 | %d / 20 |" % int(evaluation.get("valid_battles", 0)),
			"| 目标胜率 | %.1f%% |" % (float(evaluation.get("target_player_win_rate", 0.0)) * 100.0),
			"| 允许误差 | ±%.1f 个百分点 |" % (float(evaluation.get("tolerance", 0.0)) * 100.0),
			"| 报告胜率 | %.1f%% |" % (float(evaluation.get("observed_player_win_rate", 0.0)) * 100.0),
			"| P10 时长门槛 / 实测 | %.2fs / %.2fs |" % [float(evaluation.get("minimum_p10_duration", 0.0)), float(evaluation.get("observed_p10_duration", 0.0))],
			"| 必做动作证据 | %s |" % ("通过" if bool(evaluation.get("objective_evidence_passed", false)) else "未通过"),
			"| 解锁前敌方伤害 | %.2f / %.2f |" % [float(evaluation.get("observed_enemy_damage_before_engagement", 0.0)), float(evaluation.get("maximum_enemy_damage_before_engagement", 0.0))],
			"| 教学策略命令拒绝 | %d / %d |" % [int(evaluation.get("observed_policy_command_rejections", 0)), int(evaluation.get("maximum_policy_command_rejections", 0))],
			"| 结算 | %s |" % ("通过" if bool(evaluation.get("passed", false)) else "未通过"),
			"",
		])
	lines.append_array([
		"## AI 行为指标",
		"",
		"| 指标 | 结果 |",
		"| --- | ---: |",
		"| 模式切换/分钟 | %.2f |" % float(aggregate.get("ai_behavior", {}).get("mode_switches_per_minute", 0.0)),
		"| 战术切换/分钟 | %.2f |" % float(aggregate.get("ai_behavior", {}).get("tactic_switches_per_minute", 0.0)),
		"| 目标切换/分钟 | %.2f |" % float(aggregate.get("ai_behavior", {}).get("target_switches_per_minute", 0.0)),
		"| 即时规避恢复率 | %.1f%% |" % (float(aggregate.get("ai_behavior", {}).get("interrupt_recovery_rate", 0.0)) * 100.0),
		"| 设施交互完成率 | %.1f%% |" % (float(aggregate.get("ai_behavior", {}).get("facility_completion_rate", 0.0)) * 100.0),
		"| 平均技能评分 | %.2f |" % float(aggregate.get("ai_behavior", {}).get("average_skill_score", 0.0)),
		"| 平均协同评分 | %.2f |" % float(aggregate.get("ai_behavior", {}).get("average_coordination_score", 0.0)),
		"| 过量伤害率 | %.2f%% |" % (float(aggregate.get("ai_behavior", {}).get("overkill_ratio", 0.0)) * 100.0),
		"| 路径卡住事件 | %d |" % int(aggregate.get("ai_behavior", {}).get("path_stuck_events", 0)),
		"| 掩体候选采用 | %d |" % int(aggregate.get("ai_behavior", {}).get("cover_selections", 0)),
		"| 技能保留次数 | %d |" % int(aggregate.get("ai_behavior", {}).get("skill_holds", 0)),
		"| 累计消极时长 | %.2fs |" % float(aggregate.get("ai_behavior", {}).get("passive_duration_seconds", 0.0)),
		"| 接敌压力触发次数 | %d |" % int(aggregate.get("ai_behavior", {}).get("engagement_pressure_triggers", 0)),
		"| 触发后平均接敌时间 | %.2fs |" % float(aggregate.get("ai_behavior", {}).get("average_engagement_response_seconds", 0.0)),
		"| 长期原地不动次数 | %d |" % int(aggregate.get("ai_behavior", {}).get("long_idle_events", 0)),
		"",
		"## 分场景结果",
		"",
		"| 场景 | 完成 | 玩家侧胜率 | 平均时长 | 玩家/敌方射击 |",
		"| --- | ---: | ---: | ---: | ---: |",
	])
	var by_scenario: Dictionary = aggregate.get("by_scenario_variant", {})
	var scenario_ids: Array = by_scenario.keys()
	scenario_ids.sort()
	for scenario_id in scenario_ids:
		var scenario: Dictionary = by_scenario[scenario_id]
		var combat: Dictionary = scenario.get("faction_combat", {})
		lines.append("| `%s` | %d/%d | %.1f%% | %.2fs | %d / %d |" % [
			scenario_id,
			int(scenario.get("finished_runs", 0)),
			int(scenario.get("planned_runs", 0)),
			float(scenario.get("player_win_rate", 0.0)) * 100.0,
			float(scenario.get("duration", {}).get("mean", 0.0)),
			int(combat.get("player", {}).get("shots", 0)),
			int(combat.get("enemy", {}).get("shots", 0)),
		])
	lines.append_array([
		"",
		"逐局、逐舰、分类伤害详见 `unit_damage.md` 与 `unit_damage.csv`。",
		"",
		"## 单局结果",
		"",
		"| 种子 | 场景 | 侧别 | 状态 | 胜方阵营 | 胜方原始阵容 | 原因 | 时长 |",
		"| ---: | --- | --- | --- | --- | --- | --- | ---: |",
	])
	for run in result.get("runs", []):
		lines.append("| %d | `%s` | %s | %s | %s | %s | %s | %.2fs |" % [
			int(run.get("seed", 0)), str(run.get("scenario_id", "")), str(run.get("side_variant", "")), str(run.get("end_state", "")),
			str(run.get("winner_faction", "-")), str(run.get("winner_lineup", "-")), str(run.get("finish_reason", "")), float(run.get("duration", 0.0)),
		])
	lines.append_array(["", "## 单位平均伤害", "", "| 单位 | 平均伤害 |", "| --- | ---: |"])
	var damage: Dictionary = aggregate.get("average_damage_by_unit", {})
	var unit_ids: Array = damage.keys()
	unit_ids.sort()
	for unit_id in unit_ids:
		lines.append("| `%s` | %.2f |" % [unit_id, float(damage[unit_id])])
	lines.append_array(["", "## 按原始阵容与舰船平均伤害", "", "| 阵容 | 舰船 | 场次 | 平均伤害 | 平均承伤 | 平均 Buff 贡献 |", "| --- | --- | ---: | ---: | ---: | ---: |"])
	var ship_damage: Dictionary = aggregate.get("average_damage_by_ship", {})
	var ship_keys: Array = ship_damage.keys()
	ship_keys.sort()
	for key in ship_keys:
		var entry: Dictionary = ship_damage[key]
		lines.append("| %s | %s | %d | %.2f | %.2f | %.2f |" % [
			entry.get("lineup_id", ""), entry.get("display_name", entry.get("definition_id", "")), int(entry.get("battles", 0)),
			float(entry.get("average_damage_dealt", 0.0)), float(entry.get("average_damage_taken", 0.0)), float(entry.get("average_contribution_damage", 0.0)),
		])
	lines.append_array([
		"",
		"> 本报告来自无图形完整规则模拟。它可用于规则回归和数值筛查，不能替代玩家操作、视觉反馈与趣味性验收。",
		"",
	])
	return "\n".join(lines)
