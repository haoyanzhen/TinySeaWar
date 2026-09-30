extends "res://scripts/tests/ship_acquisition_test.gd"

func _run() -> void:
	var flow = root.get_node("GameFlow")
	var original_store = flow._progress_store
	var store := MemoryStore.new()
	flow._progress_store = store
	flow._apply_loaded_progress({"schema_version":1, "unlocked_ship_ids":["ship.akizuki", "ship.future"], "completed_challenge_level_ids":[]})
	var menu = load("res://scenes/menu/main_menu.tscn").instantiate()
	root.add_child(menu)
	for chapter in [1, 2]:
		menu.challenge_chapter = chapter
		menu._show_challenge()
		var prefix := "m" if chapter == 1 else "l"
		_check(menu.level_buttons["level.challenge." + prefix + "01"].text.contains("可出击"), prefix + " first independently open")
		for index in range(1, 6):
			var id := "level.challenge.%s%02d" % [prefix, index]
			if index < 5:
				_check(menu.level_buttons["level.challenge.%s%02d" % [prefix, index + 1]].text.contains("前一关"), "next locked before completion")
			_check(flow.record_level_victory(id), id + " records victory")
			var owned: Array = flow.unlocked_ship_ids.duplicate()
			flow.record_level_victory(id)
			_check(flow.unlocked_ship_ids == owned and flow.completed_challenge_level_ids.count(id) == 1, id + " idempotent reward facts")
			menu._show_challenge()
			_check(menu.level_buttons[id].text.contains(["铜章", "银章", "金章", "精锐章", "本章完成"][index - 1]), id + " medal/chapter derived from completion facts")
			if index < 5: _check(menu.level_buttons["level.challenge.%s%02d" % [prefix, index + 1]].text.contains("可出击"), "next unlocked after completion")
	_check("ship.future" in store.document.unlocked_ship_ids and flow.is_ship_unlocked("ship.akizuki"), "legacy unknown and pending ownership retained")
	menu.free()
	flow.select_level("level.challenge.l01")
	var battle = load("res://scenes/battle/prototype_battle.tscn").instantiate()
	battle.progress_recording_enabled = false
	root.add_child(battle)
	battle.set_process(false)
	var writes_before := store.writes
	battle._consume_events([{"event_type":"BattleFinished", "result":{"winner_faction":"player", "reason_code":"TEST"}}])
	_check(store.writes == writes_before, "debug victory cannot write progress")
	battle.progress_recording_enabled = true
	battle._consume_events([{"event_type":"BattleFinished", "result":{"winner_faction":"enemy", "reason_code":"TEST"}}])
	_check(store.writes == writes_before, "loss cannot write progress")
	battle.free()
	flow._progress_store = original_store
	for failure in failures: push_error(failure)
	print("M/L progress: %d/%d passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
