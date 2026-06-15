extends Node2D

const BattleSession = preload("res://scripts/application/battle_session.gd")

const FIXED_STEP := 0.1
const MARGIN := Vector2(42.0, 70.0)

var session
var level_id := "level.prototype_3v3"
var accumulator := 0.0
var selected_unit_id := ""
var focused_target_id := ""
var recent_messages: Array[String] = []


func _ready() -> void:
	_start_battle(level_id)


func _process(delta: float) -> void:
	if session == null: return
	accumulator += minf(delta, 0.25)
	while accumulator >= FIXED_STEP:
		accumulator -= FIXED_STEP
		var events: Array = session.advance_tick(FIXED_STEP)
		_consume_events(events)
	queue_redraw()


func _draw() -> void:
	if session == null or session.state.is_empty(): return
	var snapshot: Dictionary = session.snapshot("player", false)
	var map_size := _map_size(snapshot)
	draw_rect(Rect2(MARGIN, map_size), Color("#183b52"), true)
	draw_rect(Rect2(MARGIN, map_size), Color("#72bed1"), false, 2.0)
	for contact in snapshot["contacts"].values():
		var ghost_position := _to_screen(contact["last_known_position"], snapshot)
		draw_circle(ghost_position, 12.0, Color(0.9, 0.3, 0.3, 0.25))
		draw_string(ThemeDB.fallback_font, ghost_position + Vector2(16.0, 4.0), "last contact", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color(1.0, 0.7, 0.7, 0.8))
	for projectile in snapshot["projectiles"].values():
		draw_circle(_to_screen(projectile["position"], snapshot), 3.5, Color("#f5d76e"))
	for unit in snapshot["units"].values():
		_draw_unit(unit, snapshot)
	var title := "Tiny Sea War - %s  |  %.1fs  |  %s" % [level_id.trim_prefix("level."), float(snapshot["elapsed_time"]), snapshot["phase"]]
	draw_string(ThemeDB.fallback_font, Vector2(42.0, 36.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22, Color.WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(42.0, 58.0), "Left click select/focus  Right click move  Q skill  Space pause  R restart  1/3 switch level", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color("#bddbe4"))
	var y := 705.0
	for message in recent_messages:
		draw_string(ThemeDB.fallback_font, Vector2(42.0, y), message, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color("#e6edf0"))
		y -= 17.0
	if not snapshot["result"].is_empty():
		var result_text := "%s wins - %s" % [snapshot["result"].get("winner_faction", "?"), snapshot["result"].get("reason", "")]
		draw_rect(Rect2(Vector2(390.0, 300.0), Vector2(500.0, 90.0)), Color(0.02, 0.05, 0.08, 0.9), true)
		draw_string(ThemeDB.fallback_font, Vector2(455.0, 355.0), result_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 28, Color.WHITE)


func _draw_unit(unit: Dictionary, snapshot: Dictionary) -> void:
	var position := _to_screen(unit["position"], snapshot)
	var friendly: bool = unit["faction_id"] == "player"
	var color := Color("#63c7ff") if friendly else Color("#ff6b6b")
	if unit["life_state"] == "Sunk": color = Color("#6c7780")
	var radius := 14.0 if unit["is_flagship"] else 10.0
	draw_circle(position, radius, color)
	draw_line(position, position + Vector2.RIGHT.rotated(float(unit["heading"])) * 22.0, Color.WHITE, 2.0)
	if unit["entity_id"] == selected_unit_id: draw_arc(position, radius + 7.0, 0.0, TAU, 32, Color("#f8ef9a"), 2.0)
	if unit["entity_id"] == focused_target_id: draw_arc(position, radius + 9.0, 0.0, TAU, 32, Color("#ffb35c"), 2.0)
	var hp_ratio := float(unit["current_hp"]) / maxf(1.0, float(unit["max_hp"]))
	draw_rect(Rect2(position + Vector2(-20.0, -25.0), Vector2(40.0, 4.0)), Color("#202931"), true)
	draw_rect(Rect2(position + Vector2(-20.0, -25.0), Vector2(40.0 * hp_ratio, 4.0)), Color("#70db84"), true)
	var label := ("[F] " if unit["is_flagship"] else "") + str(unit["display_name"])
	draw_string(ThemeDB.fallback_font, position + Vector2(-35.0, 38.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color.WHITE)


func _unhandled_input(event: InputEvent) -> void:
	if session == null: return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				if session.state["phase"] == "Paused": session.resume()
				else: session.pause()
			KEY_R: _start_battle(level_id)
			KEY_1:
				level_id = "level.prototype_1v1"
				_start_battle(level_id)
			KEY_3:
				level_id = "level.prototype_3v3"
				_start_battle(level_id)
			KEY_Q: _cast_selected_skill()
	if event is InputEventMouseButton and event.pressed:
		var snapshot: Dictionary = session.snapshot("player", false)
		var world_position := _to_world(event.position, snapshot)
		if event.button_index == MOUSE_BUTTON_LEFT: _select_at(world_position, snapshot)
		elif event.button_index == MOUSE_BUTTON_RIGHT and not selected_unit_id.is_empty():
			session.queue_command({"command_id": "ui.move.%s" % session.state["tick_index"], "command_type": "MoveUnits", "issued_at_tick": session.state["tick_index"], "issuer_id": "player", "unit_id": selected_unit_id, "target_position": world_position})


func _select_at(world_position: Vector2, snapshot: Dictionary) -> void:
	var nearest: Dictionary = {}
	var nearest_distance := 32.0
	for unit in snapshot["units"].values():
		var distance := (unit["position"] as Vector2).distance_to(world_position)
		if distance < nearest_distance:
			nearest = unit
			nearest_distance = distance
	if nearest.is_empty(): return
	if nearest["faction_id"] == "player":
		selected_unit_id = nearest["entity_id"]
	else:
		focused_target_id = nearest["entity_id"]
		if not selected_unit_id.is_empty(): session.queue_command({"command_id": "ui.focus.%s" % session.state["tick_index"], "command_type": "FocusTarget", "issued_at_tick": session.state["tick_index"], "issuer_id": "player", "unit_id": selected_unit_id, "target_unit_id": focused_target_id})


func _cast_selected_skill() -> void:
	if selected_unit_id.is_empty(): return
	var target_ref := {"type": "Self"}
	if not focused_target_id.is_empty(): target_ref = {"type": "Entity", "entity_id": focused_target_id}
	var selected: Dictionary = session.state["units_by_id"].get(selected_unit_id, {})
	if selected.is_empty(): return
	var skill: Dictionary = DataRegistry.registry.get_definition("skills", str(selected["skill_state"]["definition_id"]))
	if skill.get("target_type", "Self") == "Area" and not focused_target_id.is_empty():
		var target: Dictionary = session.state["units_by_id"].get(focused_target_id, {})
		if not target.is_empty(): target_ref = {"type": "Position", "position": target["position"]}
	session.queue_command({"command_id": "ui.skill.%s" % session.state["tick_index"], "command_type": "CastSkill", "issued_at_tick": session.state["tick_index"], "issuer_id": "player", "unit_id": selected_unit_id, "target_ref": target_ref})


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
	if not result.get("ok", false): push_error("Battle creation failed: %s" % result.get("errors", []))
	accumulator = 0.0
	selected_unit_id = ""
	focused_target_id = ""
	recent_messages.clear()
	queue_redraw()


func _map_size(snapshot: Dictionary) -> Vector2:
	var source: Dictionary = snapshot.get("map", {})
	var available := get_viewport_rect().size - Vector2(MARGIN.x * 2.0, 150.0)
	var scale_factor := minf(available.x / float(source.get("width", 1200.0)), available.y / float(source.get("height", 700.0)))
	return Vector2(float(source.get("width", 1200.0)), float(source.get("height", 700.0))) * scale_factor


func _to_screen(world_position: Vector2, snapshot: Dictionary) -> Vector2:
	var source: Dictionary = snapshot.get("map", {})
	var map_size := _map_size(snapshot)
	return MARGIN + Vector2(world_position.x / float(source.get("width", 1200.0)) * map_size.x, world_position.y / float(source.get("height", 700.0)) * map_size.y)


func _to_world(screen_position: Vector2, snapshot: Dictionary) -> Vector2:
	var source: Dictionary = snapshot.get("map", {})
	var map_size := _map_size(snapshot)
	var local := screen_position - MARGIN
	return Vector2(clampf(local.x / map_size.x, 0.0, 1.0) * float(source.get("width", 1200.0)), clampf(local.y / map_size.y, 0.0, 1.0) * float(source.get("height", 700.0)))
