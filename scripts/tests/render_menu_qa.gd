extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var target := Vector2i(1920, 1080)
	var output := "/tmp/tsw_menu_home.png"
	var page := "home"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--page="): page = arg.trim_prefix("--page=")
		elif arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		elif arg == "--1440": target = Vector2i(2560, 1440)
	var viewport := SubViewport.new()
	viewport.size = target
	viewport.size_2d_override = Vector2i(1920, 1080)
	viewport.size_2d_override_stretch = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var menu = load("res://scenes/menu/main_menu.tscn").instantiate()
	viewport.add_child(menu)
	if page == "gallery": menu._show_home(); menu._show_gallery()
	elif page == "view": menu._show_home(); menu.set_viewing(true)
	else: menu.call("_show_" + page)
	await create_timer(0.7).timeout
	await process_frame
	var result := viewport.get_texture().get_image().save_png(output)
	print("MENU_QA %s %s" % [page, result])
	quit(0 if result == OK else 1)
