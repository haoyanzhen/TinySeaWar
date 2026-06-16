extends SceneTree

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://scenes/battle/prototype_battle.tscn")
	var battle = scene.instantiate()
	root.add_child(battle)
	await process_frame
	await process_frame
	var viewport_size: Vector2 = battle.get_viewport_rect().size
	var map_data: Dictionary = battle.session.state["map"]
	_check(viewport_size == Vector2(1920.0, 1080.0), "logical viewport is 1920x1080")
	_check(float(map_data["width"]) > viewport_size.x * 2.0, "map width exceeds two visible screens")
	_check(float(map_data["height"]) > viewport_size.y * 2.0, "map height exceeds two visible screens")
	var player_center: Vector2 = battle._player_fleet_center()
	_check(battle.battle_camera.position.is_equal_approx(player_center), "initial camera centers on player fleet")
	_check(battle.camera_mode == "Manual", "initial camera remains in manual mode")

	battle.selected_unit_id = "unit.player.warspite"
	battle._toggle_follow_selected()
	_check(battle.camera_mode == "Follow", "follow mode activates for selected friendly unit")
	var followed: Dictionary = battle.session.state["units_by_id"]["unit.player.warspite"]
	followed["position"] = Vector2(2200.0, 1300.0)
	battle._update_camera(0.1)
	_check(battle.battle_camera.position.is_equal_approx(followed["position"]), "follow camera tracks the selected friendly unit")

	battle._set_ocean_palette("dusk")
	_check(battle.current_palette_id == "dusk", "ocean palette can switch at runtime")
	var ocean_material := battle.ocean_surface.material as ShaderMaterial
	_check(is_zero_approx(float(ocean_material.get_shader_parameter("ai_texture_strength"))), "runtime ocean palette applies the configured AI texture weight")
	var camera_before_input: Vector2 = battle.battle_camera.position
	Input.action_press("camera_right")
	await process_frame
	Input.action_release("camera_right")
	_check(battle.camera_mode == "Manual" and battle.battle_camera.position.x > camera_before_input.x, "WASD input exits follow mode and moves the camera")
	battle.battle_camera.position = Vector2(-1000.0, -1000.0)
	battle._clamp_camera_to_map()
	_check(battle.battle_camera.position.x > 0.0 and battle.battle_camera.position.y > 0.0, "camera clamp prevents exposing outside the map")

	battle.queue_free()
	if failures.is_empty():
		print("PASS: %d scene presentation checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error("FAIL: %s" % failure)
		print("FAILED: %d of %d scene presentation checks" % [failures.size(), checks])
		quit(1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
