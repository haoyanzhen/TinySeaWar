extends SceneTree
var checks := 0
var failures: Array[String] = []
func _init() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)
func run() -> void:
	var menu = load("res://scenes/menu/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	var catalog = root.get_node("DataRegistry").assets
	for friendly in [true, false]:
		var parent := VBoxContainer.new()
		menu.add_child(parent)
		menu._fleet_preview(parent, "fixture", [{"ship_id":"ship.warspite","is_flagship":true}], friendly)
		var grid = parent.get_child(0).get_child(1)
		var slot = grid.get_child(0).get_child(0)
		check(slot.custom_minimum_size == Vector2(96,96), "square consistent slot")
		check("旗舰" in slot.tooltip_text, "flagship identity retained in tooltip")
		check(slot.get_node("PortraitImage").texture == menu._portrait("ship.warspite"), "unframed character semantic")
		var expected := "ui_frame_portrait_player" if friendly else "ui_frame_portrait_enemy"
		check(slot.get_node("PortraitFrame").texture.resource_path == catalog.ui_asset_path(expected), "frame follows side independently of character")
		check(slot.get_node("PortraitImage").mouse_filter == Control.MOUSE_FILTER_IGNORE, "image does not block tooltip")
		parent.queue_free()
	var saved: Dictionary = catalog.ui_assets["ui_frame_portrait_enemy"]
	catalog.ui_assets.erase("ui_frame_portrait_enemy")
	var parent := VBoxContainer.new()
	menu.add_child(parent)
	menu._fleet_preview(parent,"missing frame",[{"ship_id":"ship.warspite"}],false)
	var slot = parent.get_child(0).get_child(1).get_child(0).get_child(0)
	check(slot.get_node("PortraitFrame").texture == null, "missing public texture tolerated")
	check(slot.get_child(1) is Panel and slot.get_node("PortraitImage").texture != null, "program frame fallback preserves portrait")
	catalog.ui_assets["ui_frame_portrait_enemy"] = saved
	parent.queue_free()
	for failure in failures: push_error(failure)
	print("Menu portrait frames: %d/%d passed" % [checks-failures.size(),checks])
	menu.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
