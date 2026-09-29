extends SceneTree
var checks := 0
var failures: Array[String] = []
func _init() -> void: call_deferred("_run")
func _check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)
func _run() -> void:
	var flow = root.get_node("GameFlow")
	var menu = load("res://scenes/menu/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	menu._show_home()
	_check(menu.covers.size() == 7, "seven approved covers available")
	for index in range(menu.covers.size()):
		menu._switch_cover(index, false)
		_check(menu.cover_front.texture != null, "cover loads %d" % index)
	_check(menu.home_actions.map(func(button): return button.text) == ["教学关", "挑战关", "自定义战斗"], "home uses concise mode labels")
	_check(["tutorial", "challenge", "custom"].all(func(key): return not menu.nav_buttons[key].is_visible_in_tree()), "no duplicate home mode entries")
	menu.home_actions[0].grab_focus()
	var background_tint: Color = menu.cover_front.self_modulate
	menu.set_viewing(true)
	_check(menu.clock_panel.visible and menu.clock_time.text.length() == 5, "view mode shows local clock")
	_check(menu.cover_front.self_modulate == background_tint, "view mode preserves background tint")
	_check(not menu.chrome.visible and get_root().gui_get_focus_owner() == null, "viewing removes hidden controls and keyboard focus")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	menu._input(click)
	_check(not menu.viewing and menu.page == "home" and root.is_input_handled(), "first click restores without navigating")
	_check(not menu.clock_panel.visible, "clock hides on return to menu")
	menu._show_gallery()
	menu._show_tutorial()
	_check(menu.gallery == null and menu.level_buttons.size() == 8, "navigation closes gallery and exposes teaching choices")
	menu._show_custom()
	var owned: Array = flow.unlocked_ship_ids
	menu._toggle_ship(true, str(owned[0]))
	menu._show_help()
	menu._show_custom()
	_check(str(owned[0]) in menu.selected_ship_ids, "fleet survives page navigation")
	menu.search_text = "不存在的舰娘"
	menu._filter_ships()
	_check(menu.ship_buttons.values().all(func(button): return not button.visible), "search filters every card")
	_check(menu.selected_ship_ids.size() == 1, "filter does not erase fleet")
	var locked := ""
	for id in menu.ship_buttons:
		if not flow.is_ship_unlocked(id): locked = id; break
	if not locked.is_empty():
		menu._toggle_ship(true, locked)
		_check(locked not in menu.selected_ship_ids, "locked ship cannot be selected")
	menu._show_home()
	menu._on_progress_save_status_changed({"status":"Failed", "message":"保存失败", "can_retry":true})
	menu.set_viewing(true)
	_check(not menu.viewing and menu.progress_failure_banner.visible, "save failure remains visible")
	for failure in failures: push_error(failure)
	print("Menu cover flow: %d/%d passed" % [checks - failures.size(), checks])
	menu.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
