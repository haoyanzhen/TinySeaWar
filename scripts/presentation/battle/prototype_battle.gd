extends Node2D

const BattleSession = preload("res://scripts/application/battle_session.gd")

const FIXED_STEP := 0.1
const CAMERA_SPEED := 900.0
const CAMERA_EDGE_MARGIN := 28.0
const CAMERA_FOLLOW_DAMPING := 7.5

enum OperationMode { NORMAL, AIMING_PRIMARY, TARGETING_SKILL }

@onready var ocean_surface: Node2D = $OceanSurface
@onready var battle_camera: Camera2D = $BattleCamera
@onready var battle_hud: Control = $HUD/BattleHud

var session
var level_id := "level.prototype_3v3"
var accumulator := 0.0
var selected_unit_id := ""
var focused_target_id := ""
var recent_messages: Array[String] = []
var camera_mode := "Manual"
var camera_follow_unit_id := ""
var operation_mode := OperationMode.NORMAL
var skill_target_type := ""
var current_palette_id := "cloudy"
var palette_override := ""


func _ready() -> void:
	_ensure_camera_input_actions()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--level="): level_id = argument.trim_prefix("--level=")
		elif argument.begins_with("--palette="): palette_override = argument.trim_prefix("--palette=")
	_start_battle(level_id)
	if not palette_override.is_empty(): _set_ocean_palette(palette_override)


func _process(delta: float) -> void:
	if session == null: return
	accumulator += minf(delta, 0.25)
	while accumulator >= FIXED_STEP:
		accumulator -= FIXED_STEP
		var events: Array = session.advance_tick(FIXED_STEP)
		_consume_events(events)
	_update_camera(delta)
	ocean_surface.set_animation_paused(session.state.get("phase", "") == "Paused")
	_update_hud()
	queue_redraw()


func _draw() -> void:
	if session == null or session.state.is_empty(): return
	var snapshot: Dictionary = session.snapshot("player", false)
	_draw_map_boundary(snapshot)
	for contact in snapshot["contacts"].values():
		var ghost_position: Vector2 = contact["last_known_position"]
		draw_circle(ghost_position, 22.0, Color(0.9, 0.3, 0.3, 0.2))
		draw_arc(ghost_position, 29.0, 0.0, TAU, 28, Color(1.0, 0.55, 0.6, 0.55), 2.0)
	for projectile in snapshot["projectiles"].values():
		draw_circle(projectile["position"], 5.0, Color("#f5d76e"))
	for unit in snapshot["units"].values():
		_draw_unit(unit)
	_draw_operation_overlay()


func _draw_map_boundary(snapshot: Dictionary) -> void:
	var source: Dictionary = snapshot.get("map", {})
	var size := Vector2(float(source.get("width", 4096.0)), float(source.get("height", 2304.0)))
	draw_rect(Rect2(Vector2.ZERO, size), Color("#72bed1"), false, 4.0)


func _draw_unit(unit: Dictionary) -> void:
	var position: Vector2 = unit["position"]
	var friendly: bool = unit["faction_id"] == "player"
	var color := Color("#63c7ff") if friendly else Color("#ff6b6b")
	if unit["life_state"] == "Sunk": color = Color("#6c7780")
	var radius := 25.0 if unit["is_flagship"] else 19.0
	draw_circle(position, radius + 5.0, Color(0.02, 0.08, 0.12, 0.55))
	draw_circle(position, radius, color)
	var heading_vector := Vector2.RIGHT.rotated(float(unit["heading"]))
	draw_line(position, position + heading_vector * 42.0, Color.WHITE, 3.0)
	if unit["entity_id"] == selected_unit_id:
		draw_arc(position, radius + 12.0, 0.0, TAU, 40, Color("#f8ef9a"), 3.0)
	if unit["entity_id"] == focused_target_id:
		draw_arc(position, radius + 16.0, 0.0, TAU, 40, Color("#ffb35c"), 3.0)
	var hp_ratio := float(unit["current_hp"]) / maxf(1.0, float(unit["max_hp"]))
	draw_rect(Rect2(position + Vector2(-34.0, -43.0), Vector2(68.0, 7.0)), Color("#202931"), true)
	draw_rect(Rect2(position + Vector2(-34.0, -43.0), Vector2(68.0 * hp_ratio, 7.0)), Color("#70db84"), true)
	var label := ("[F] " if unit["is_flagship"] else "") + str(unit["display_name"])
	draw_string(ThemeDB.fallback_font, position + Vector2(-54.0, 62.0), label, HORIZONTAL_ALIGNMENT_CENTER, 108.0, 18, Color.WHITE)


func _draw_operation_overlay() -> void:
	if selected_unit_id.is_empty() or operation_mode == OperationMode.NORMAL: return
	var selected: Dictionary = session.state.get("units_by_id", {}).get(selected_unit_id, {})
	if selected.is_empty(): return
	var cursor := get_global_mouse_position()
	if operation_mode == OperationMode.AIMING_PRIMARY:
		var aim_status: Dictionary = session.get_primary_aim_status(selected_unit_id, cursor)
		var legal: bool = bool(aim_status.get("legal", false))
		var color := Color(0.25, 1.0, 0.55, 0.75) if legal else Color(1.0, 0.25, 0.2, 0.75)
		var range_value := float(aim_status.get("range", 0.0))
		draw_arc(selected["position"], range_value, 0.0, TAU, 96, color, 2.0)
		draw_line(selected["position"], cursor, color, 2.0)
		if aim_status.get("control_type", "") == "Direction":
			var heading := (cursor - (selected["position"] as Vector2)).angle()
			draw_line(selected["position"], selected["position"] + Vector2.RIGHT.rotated(heading - 0.18) * range_value, color, 1.5)
			draw_line(selected["position"], selected["position"] + Vector2.RIGHT.rotated(heading + 0.18) * range_value, color, 1.5)
		else:
			draw_circle(cursor, 42.0, Color(color.r, color.g, color.b, 0.12))
			draw_arc(cursor, 42.0, 0.0, TAU, 36, color, 2.0)
		draw_string(ThemeDB.fallback_font, cursor + Vector2(18.0, -18.0), str(aim_status.get("reason_code", "OK")), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, color)
	elif operation_mode == OperationMode.TARGETING_SKILL:
		var color := Color(0.45, 0.75, 1.0, 0.75)
		draw_circle(cursor, 48.0, Color(color.r, color.g, color.b, 0.12))
		draw_arc(cursor, 48.0, 0.0, TAU, 36, color, 2.0)
		draw_string(ThemeDB.fallback_font, cursor + Vector2(18.0, -18.0), "Skill target: %s" % skill_target_type, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, color)


func _unhandled_input(event: InputEvent) -> void:
	if session == null: return
	if event is InputEventKey and event.pressed and not event.echo:
		var slot := _slot_for_key(event.keycode)
		if slot > 0:
			_select_slot(slot)
			return
		match event.keycode:
			KEY_SPACE:
				if session.state["phase"] == "Paused": session.resume()
				else: session.pause()
			KEY_R: _start_battle(level_id)
			KEY_E: _begin_primary_aim()
			KEY_Q: _switch_selected_ammo()
			KEY_F: _begin_or_cast_skill()
			KEY_V: _toggle_follow_selected()
			KEY_ESCAPE: _cancel_operation_mode()
	if event is InputEventMouseButton and event.pressed:
		var snapshot: Dictionary = session.snapshot("player", false)
		var world_position := get_global_mouse_position()
		if event.button_index == MOUSE_BUTTON_LEFT:
			if operation_mode == OperationMode.AIMING_PRIMARY: _confirm_primary_aim(world_position)
			elif operation_mode == OperationMode.TARGETING_SKILL: _confirm_skill_target(world_position, snapshot)
			else: _select_at(world_position, snapshot)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if operation_mode == OperationMode.AIMING_PRIMARY:
				_cancel_operation_mode()
			elif operation_mode == OperationMode.NORMAL and not selected_unit_id.is_empty():
				session.queue_command({"command_id": "ui.move.%s" % session.state["tick_index"], "command_type": "MoveUnits", "issued_at_tick": session.state["tick_index"], "issuer_id": "player", "unit_id": selected_unit_id, "target_position": world_position})


func _update_camera(delta: float) -> void:
	var input_direction := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	if input_direction.length_squared() > 0.0:
		camera_mode = "Manual"
		camera_follow_unit_id = ""
		battle_camera.position += input_direction.normalized() * CAMERA_SPEED * delta
	elif camera_mode == "Follow":
		var target: Dictionary = session.state.get("units_by_id", {}).get(camera_follow_unit_id, {})
		if target.is_empty() or target.get("life_state", "") != "Alive" or target.get("faction_id", "") != "player":
			camera_mode = "Manual"
			camera_follow_unit_id = ""
		else:
			var weight := 1.0 - exp(-CAMERA_FOLLOW_DAMPING * delta)
			battle_camera.position = battle_camera.position.lerp(target["position"], weight)
	_clamp_camera_to_map()


func _ensure_camera_input_actions() -> void:
	var bindings := {
		"camera_left": KEY_A,
		"camera_right": KEY_D,
		"camera_up": KEY_W,
		"camera_down": KEY_S,
	}
	for action in bindings:
		if not InputMap.has_action(action): InputMap.add_action(action)
		var has_key := false
		for existing_event in InputMap.action_get_events(action):
			if existing_event is InputEventKey and existing_event.physical_keycode == bindings[action]:
				has_key = true
				break
		if has_key: continue
		var key_event := InputEventKey.new()
		key_event.physical_keycode = bindings[action]
		InputMap.action_add_event(action, key_event)


func _clamp_camera_to_map() -> void:
	if session == null or session.state.is_empty(): return
	var source: Dictionary = session.state.get("map", {})
	var map_size := Vector2(float(source.get("width", 4096.0)), float(source.get("height", 2304.0)))
	var half_view := get_viewport_rect().size * 0.5
	var minimum := half_view + Vector2.ONE * CAMERA_EDGE_MARGIN
	var maximum := map_size - half_view - Vector2.ONE * CAMERA_EDGE_MARGIN
	if maximum.x < minimum.x:
		minimum.x = map_size.x * 0.5
		maximum.x = minimum.x
	if maximum.y < minimum.y:
		minimum.y = map_size.y * 0.5
		maximum.y = minimum.y
	battle_camera.position = battle_camera.position.clamp(minimum, maximum)


func _toggle_follow_selected() -> void:
	if selected_unit_id.is_empty(): return
	var selected: Dictionary = session.state.get("units_by_id", {}).get(selected_unit_id, {})
	if selected.is_empty() or selected.get("faction_id", "") != "player": return
	if selected.get("life_state", "") != "Alive":
		_push_message("V disabled: UNIT_SUNK")
		return
	if camera_mode == "Follow" and camera_follow_unit_id == selected_unit_id:
		camera_mode = "Manual"
		camera_follow_unit_id = ""
	else:
		camera_mode = "Follow"
		camera_follow_unit_id = selected_unit_id
		_clamp_camera_to_map()


func _slot_for_key(keycode: int) -> int:
	match keycode:
		KEY_1: return 1
		KEY_2: return 2
		KEY_3: return 3
		KEY_4: return 4
		KEY_5: return 5
		KEY_6: return 6
		KEY_7: return 7
		KEY_8: return 8
		KEY_9: return 9
		KEY_0: return 10
		KEY_MINUS: return 11
		_: return 0


func _select_slot(slot: int) -> void:
	for slot_data in session.get_player_slots():
		if int(slot_data["slot"]) != slot: continue
		selected_unit_id = str(slot_data["unit_id"])
		operation_mode = OperationMode.NORMAL
		if camera_mode == "Follow": camera_follow_unit_id = selected_unit_id
		_push_message("Selected slot %d: %s" % [slot, slot_data.get("display_name", selected_unit_id)])
		return
	_push_message("Slot %d unavailable" % slot)


func _select_at(world_position: Vector2, snapshot: Dictionary) -> void:
	var nearest: Dictionary = {}
	var nearest_distance := 48.0
	for unit in snapshot["units"].values():
		var distance := (unit["position"] as Vector2).distance_to(world_position)
		if distance < nearest_distance:
			nearest = unit
			nearest_distance = distance
	if nearest.is_empty(): return
	if nearest["faction_id"] == "player":
		selected_unit_id = nearest["entity_id"]
		if camera_mode == "Follow": camera_follow_unit_id = selected_unit_id
	else:
		focused_target_id = nearest["entity_id"]
		if not selected_unit_id.is_empty(): session.queue_command({"command_id": "ui.focus.%s" % session.state["tick_index"], "command_type": "FocusTarget", "issued_at_tick": session.state["tick_index"], "issuer_id": "player", "unit_id": selected_unit_id, "target_unit_id": focused_target_id})


func _begin_primary_aim() -> void:
	if selected_unit_id.is_empty(): return
	var selected: Dictionary = session.state["units_by_id"].get(selected_unit_id, {})
	if selected.is_empty(): return
	var operation_status: Dictionary = session.get_operation_status(selected_unit_id)
	if not bool(operation_status.get("primary_ready", false)):
		_push_message("E disabled: %s" % operation_status.get("primary_reason", "PRIMARY_WEAPON_UNAVAILABLE"))
		return
	operation_mode = OperationMode.AIMING_PRIMARY
	_push_message("Aiming %s" % operation_status.get("primary_name", "primary weapon"))


func _confirm_primary_aim(world_position: Vector2) -> void:
	if selected_unit_id.is_empty(): return
	var aim_status: Dictionary = session.get_primary_aim_status(selected_unit_id, world_position)
	if not bool(aim_status.get("legal", false)):
		_push_message("Primary rejected: %s" % aim_status.get("reason_code", "INVALID_TARGET"))
		return
	session.queue_command({"command_id": "ui.primary.%s" % session.state["tick_index"], "command_type": "FirePrimaryWeapon", "issued_at_tick": session.state["tick_index"], "issuer_id": "player", "unit_id": selected_unit_id, "target_position": world_position})
	operation_mode = OperationMode.NORMAL


func _switch_selected_ammo() -> void:
	if selected_unit_id.is_empty(): return
	var operation_status: Dictionary = session.get_operation_status(selected_unit_id)
	if not bool(operation_status.get("q_enabled", false)):
		_push_message("Q disabled: AMMO_SWITCH_DISABLED")
		return
	session.queue_command({"command_id": "ui.ammo.%s" % session.state["tick_index"], "command_type": "SwitchAmmo", "issued_at_tick": session.state["tick_index"], "issuer_id": "player", "unit_id": selected_unit_id})


func _begin_or_cast_skill() -> void:
	if selected_unit_id.is_empty(): return
	var selected: Dictionary = session.state["units_by_id"].get(selected_unit_id, {})
	if selected.is_empty(): return
	var operation_status: Dictionary = session.get_operation_status(selected_unit_id)
	if not bool(operation_status.get("skill_ready", false)):
		_push_message("F disabled: SKILL_ON_COOLDOWN")
		return
	var skill: Dictionary = DataRegistry.registry.get_definition("skills", str(selected["skill_state"]["definition_id"]))
	skill_target_type = str(skill.get("target_type", "Self"))
	if skill_target_type == "Self":
		_queue_skill_command({"type": "Self"})
	else:
		operation_mode = OperationMode.TARGETING_SKILL
		_push_message("Select skill target: %s" % skill_target_type)


func _confirm_skill_target(world_position: Vector2, snapshot: Dictionary) -> void:
	if selected_unit_id.is_empty(): return
	if skill_target_type == "Area":
		_queue_skill_command({"type": "Position", "position": world_position})
		operation_mode = OperationMode.NORMAL
		return
	var clicked := _unit_at(world_position, snapshot)
	if clicked.is_empty() or clicked.get("faction_id", "") == "player":
		_push_message("Skill rejected: INVALID_TARGET_TYPE")
		return
	_queue_skill_command({"type": "Entity", "entity_id": clicked["entity_id"]})
	operation_mode = OperationMode.NORMAL


func _queue_skill_command(target_ref: Dictionary) -> void:
	session.queue_command({"command_id": "ui.skill.%s" % session.state["tick_index"], "command_type": "CastSkill", "issued_at_tick": session.state["tick_index"], "issuer_id": "player", "unit_id": selected_unit_id, "target_ref": target_ref})


func _cancel_operation_mode() -> void:
	if operation_mode == OperationMode.NORMAL: return
	operation_mode = OperationMode.NORMAL
	skill_target_type = ""
	_push_message("Operation cancelled")


func _unit_at(world_position: Vector2, snapshot: Dictionary) -> Dictionary:
	var nearest: Dictionary = {}
	var nearest_distance := 48.0
	for unit in snapshot["units"].values():
		var distance := (unit["position"] as Vector2).distance_to(world_position)
		if distance < nearest_distance:
			nearest = unit
			nearest_distance = distance
	return nearest


func _consume_events(events: Array) -> void:
	for event in events:
		match event.get("event_type", ""):
			"UnitSunk": _push_message("%s was sunk" % event.get("unit_id", "unit"))
			"SkillCast": _push_message("%s cast %s" % [event.get("unit_id", "unit"), event.get("skill_id", "skill")])
			"BattleFinished": _push_message("Battle finished: %s" % event.get("result", {}).get("winner_faction", "?"))


func _push_message(message: String) -> void:
	recent_messages.push_front(message)
	if recent_messages.size() > 5: recent_messages.resize(5)


func _start_battle(new_level_id: String) -> void:
	session = BattleSession.new(DataRegistry.registry)
	var result: Dictionary = session.create_battle(new_level_id, 20260614)
	if not result.get("ok", false):
		push_error("Battle creation failed: %s" % result.get("errors", []))
		return
	accumulator = 0.0
	selected_unit_id = ""
	focused_target_id = ""
	operation_mode = OperationMode.NORMAL
	skill_target_type = ""
	camera_mode = "Manual"
	camera_follow_unit_id = ""
	recent_messages.clear()
	var map_data: Dictionary = session.state.get("map", {})
	current_palette_id = str(map_data.get("ocean_palette", "day_clear"))
	ocean_surface.configure(Vector2(float(map_data.get("width", 4096.0)), float(map_data.get("height", 2304.0))), current_palette_id)
	_configure_camera_limits(map_data)
	_select_slot(1)
	battle_camera.position = _player_fleet_center()
	battle_camera.reset_smoothing()
	_clamp_camera_to_map()
	_update_hud()
	queue_redraw()


func _configure_camera_limits(map_data: Dictionary) -> void:
	battle_camera.limit_left = 0
	battle_camera.limit_top = 0
	battle_camera.limit_right = int(float(map_data.get("width", 4096.0)))
	battle_camera.limit_bottom = int(float(map_data.get("height", 2304.0)))


func _player_fleet_center() -> Vector2:
	var total := Vector2.ZERO
	var count := 0
	for unit in session.state.get("units_by_id", {}).values():
		if unit.get("faction_id", "") != "player" or unit.get("life_state", "") != "Alive": continue
		total += unit["position"]
		count += 1
	return total / float(maxi(count, 1))


func _set_ocean_palette(palette_id: String) -> void:
	current_palette_id = palette_id
	ocean_surface.set_palette(palette_id)
	_update_hud()


func _update_hud() -> void:
	if session == null or session.state.is_empty(): return
	var selected_name := "None"
	var selected: Dictionary = session.state.get("units_by_id", {}).get(selected_unit_id, {})
	if not selected.is_empty(): selected_name = str(selected.get("display_name", selected_unit_id))
	battle_hud.update_state(session.snapshot("player", false), level_id, recent_messages, camera_mode, selected_name, current_palette_id, session.get_operation_status(selected_unit_id), _operation_mode_name(), session.get_player_slots())


func _operation_mode_name() -> String:
	match operation_mode:
		OperationMode.AIMING_PRIMARY: return "AIMING_PRIMARY"
		OperationMode.TARGETING_SKILL: return "TARGETING_SKILL"
		_: return "NORMAL"
