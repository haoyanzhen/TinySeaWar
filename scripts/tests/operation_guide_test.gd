extends SceneTree

var checks := 0
var failures: Array[String] = []

func _init() -> void: call_deferred("_run")

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	root.add_child(viewport)
	var menu = load("res://scenes/menu/main_menu.tscn").instantiate()
	viewport.add_child(menu)
	menu._show_help()
	await process_frame
	await process_frame
	# Discover keys from the real handlers, so newly added shortcuts cannot silently
	# disappear from the player reference. Aliases only translate displayed names.
	var guide := JSON.stringify(menu.OperationGuide.SECTIONS)
	var source := FileAccess.get_file_as_string("res://scripts/presentation/battle/prototype_battle.gd")
	var pattern := RegEx.new()
	pattern.compile("KEY_([A-Z0-9]+)")
	var aliases := {"MINUS": "0 / -", "ESCAPE": "Esc", "SPACE": "Space", "BACKSPACE": "Backspace", "1": "1–9", "2": "1–9", "3": "1–9", "4": "1–9", "5": "1–9", "6": "1–9", "7": "1–9", "8": "1–9", "9": "1–9"}
	var seen := {}
	for result in pattern.search_all(source):
		var key: String = result.get_string(1)
		if seen.has(key): continue
		seen[key] = true
		_check(guide.contains(str(aliases.get(key, key))), "document actual battle key " + key)
	for gesture in ["Shift + 左键 / 拖框", "Alt / Cmd + X / C / V", "Ctrl / Cmd + K", "Shift + K", "海域内滚轮", "U / Backspace"]:
		_check(guide.contains(gesture), "document mouse/modifier gesture " + gesture)
	for index in range(menu.help_buttons.size()):
		menu.help_buttons[index].pressed.emit()
		await process_frame
		await process_frame
		_check(menu.help_buttons.filter(func(button): return button.button_pressed).size() == 1, "one selected tab %d" % index)
		_check(menu.help_buttons[index].button_pressed, "click selects section %d" % index)
		_check(menu.help_body.scroll_vertical == 0, "new section starts at top %d" % index)
		_check(menu.page_panel.get_global_rect().encloses(menu.help_hint.get_global_rect()), "footer inside page %d" % index)
		_check(menu.help_body.get_h_scroll_bar().max_value <= menu.help_body.size.x, "no horizontal scrolling %d" % index)
		var grid = menu.help_body.get_node("OperationGuideCards")
		_check(grid.get_child_count() == 2, "two visible cards %d" % index)
		var left: Rect2 = grid.get_child(0).get_global_rect()
		var right: Rect2 = grid.get_child(1).get_global_rect()
		_check(not left.intersects(right), "cards do not overlap %d" % index)
		for label in grid.find_children("*", "Label", true, false):
			var card: Control = grid.get_child(0) if grid.get_child(0).is_ancestor_of(label) else grid.get_child(1)
			_check(card.get_global_rect().grow(1).encloses(label.get_global_rect()), "text contained: " + label.text)
		# Tall content must remain reachable using the actual vertical scroll range.
		menu.help_body.scroll_vertical = 10000
		await process_frame
		_check(grid.get_global_rect().end.y <= menu.help_body.get_global_rect().end.y + 1, "last row reachable %d" % index)
	menu._show_home()
	menu._show_help()
	await process_frame
	_check(menu.help_buttons[0].button_pressed, "reopen starts on first section")
	for failure in failures: push_error(failure)
	print("Operation guide: %d/%d passed" % [checks - failures.size(), checks])
	viewport.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
