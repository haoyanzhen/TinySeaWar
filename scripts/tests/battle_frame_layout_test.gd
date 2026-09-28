extends SceneTree

var checks := 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _run() -> void:
	var battle = load("res://scenes/battle/prototype_battle.tscn").instantiate()
	root.add_child(battle)
	battle.set_process(false)
	await process_frame
	var hud = battle.battle_hud
	var sea: Rect2 = hud.battle_rect()
	_check(sea.size == Vector2(1496, 756), "sea retains dedicated top and bottom operation margins")
	for control in hud.interaction_controls:
		_check(not sea.intersects(control.get_rect()), "interactive HUD stays outside the sea")
	_check(not sea.intersects(hud.objective_scroll.get_rect()), "mission scroll stays outside the sea")
	_check(not sea.intersects(hud.minimap_rect()), "minimap stays outside the sea")
	battle.session.pause()
	battle._update_hud()
	await process_frame
	_check(not sea.intersects(hud.pause_panel.get_rect()), "pause planning leaves sea unobstructed")
	battle.battle_camera.position = Vector2(2000, 1400)
	battle._clamp_camera_to_map()
	battle.battle_camera.reset_smoothing()
	battle.battle_camera.force_update_scroll()
	var screen: Vector2 = battle.get_canvas_transform() * battle.battle_camera.position
	_check(screen.distance_to(sea.get_center()) < 1.0, "camera target projects into sea centre")
	var anchor := sea.position + sea.size * Vector2(0.35, 0.6)
	var world_before: Vector2 = battle.get_canvas_transform().affine_inverse() * anchor
	battle._adjust_camera_zoom(1.1, anchor)
	battle.battle_camera.reset_smoothing()
	battle.battle_camera.force_update_scroll()
	var world_after: Vector2 = battle.get_canvas_transform().affine_inverse() * anchor
	_check(world_before.distance_to(world_after) < 0.1, "real canvas transform preserves zoom anchor")
	var pending_before: int = battle.session.pending_player_commands().size()
	for point in [Vector2(800, 100), Vector2(1450, 1000), Vector2(1910, 500), Vector2(10, 500)]:
		var mouse := InputEventMouseButton.new()
		mouse.position = point
		mouse.button_index = MOUSE_BUTTON_RIGHT
		mouse.pressed = true
		battle._unhandled_input(mouse)
	_check(battle.session.pending_player_commands().size() == pending_before, "frame clicks never issue world movement")
	battle.battle_hud.pause_button.pressed.emit()
	_check(battle.session.state["phase"] == "Running", "pause icon resumes through the public HUD action")
	battle.battle_hud.pause_button.pressed.emit()
	_check(battle.session.state["phase"] == "Paused", "pause icon pauses through the public HUD action")
	_check(hud._skin_style("ui_frame_portrait_selected", 0) != null and hud._skin_style("ui_button_menu_primary_default", 12) != null, "existing UI skins resolve through AssetCatalog")
	print("Battle frame layout: %d/%d passed" % [checks - failures.size(), checks])
	for failure in failures: push_error(failure)
	battle.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
