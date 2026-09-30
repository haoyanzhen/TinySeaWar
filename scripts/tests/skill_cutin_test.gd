extends SceneTree
const Session = preload("res://scripts/application/battle_session.gd")
var checks := 0
var failures: Array[String] = []
func _init(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures.append(label)
func cast_event(id: int, unit_id: String) -> Dictionary:
	return {"event_id":"event.%d" % id, "tick_index":1, "event_type":"SkillCast", "unit_id":unit_id, "skill_id":"skill.warspite_veteran_aim"}
func run():
	var registry = root.get_node("DataRegistry").registry
	var flow = root.get_node("GameFlow")
	var battle = load("res://scenes/battle/prototype_battle.tscn").instantiate()
	root.add_child(battle)
	battle.set_process(false)
	battle._start_battle("level.prototype_1v1")
	var overlay = battle.skill_cutin
	overlay.set_process(false)
	overlay.set_mode("full")
	battle._sync_skill_cutin()
	check(overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE, "overlay never intercepts input")
	var assets = root.get_node("DataRegistry").assets
	var ships: Array = registry.all("ships")
	check(ships.size() == 48, "48 character definitions")
	for ship in ships:
		var id: String = str(ship.id).trim_prefix("ship.")
		overlay.cache_character(id)
		check(overlay.textures[id].illustration is Texture2D, id + " cutin resolves and loads")
		check(overlay.textures[id].portrait is Texture2D, id + " portrait resolves and loads")
	var player := "unit.player.warspite"
	var enemy := "unit.enemy.bismarck"
	var events: Array = [cast_event(2, player), cast_event(1, player)]
	battle._consume_events(events)
	check(overlay.full.get("event_id") == "event.1" and overlay.compact.size() == 1, "batch sorted by sequence; one full and compact overflow")
	battle._consume_events(events)
	check(overlay.compact.size() == 1, "duplicate consumed events do not replay")
	overlay.advance(1.01)
	check(overlay.full.is_empty() and overlay.compact.is_empty(), "both displays expire in one second")
	battle.session.state.visible_by_faction.player = {}
	battle._consume_events([cast_event(3, enemy)])
	check(overlay.full.is_empty(), "hidden enemy produces no cutin")
	battle.session.state.visible_by_faction.player = {enemy:true}
	battle._consume_events([cast_event(4, enemy)])
	check(overlay.full.get("faction_id") == "enemy", "visible enemy gets enemy cue")
	check(overlay.full_rect().end.x < overlay.size.x * 0.5 and overlay.full_rect().position.x > 0, "transparent illustration stops left of central battle area")
	for i in range(5, 15): battle._consume_events([cast_event(i, player)])
	check(overlay.compact.size() == 3 and overlay.compact[0].event_id == "event.12", "bounded overflow keeps latest three")
	battle.operation_mode = battle.OperationMode.AIMING_PRIMARY
	battle._sync_skill_cutin()
	check(overlay.full.is_empty(), "starting aim demotes an existing full card")
	battle._consume_events([cast_event(15, player)])
	check(overlay.full.is_empty() and overlay.compact.size() == 3, "aiming receives compact only")
	battle.operation_mode = battle.OperationMode.NORMAL
	battle.selection_drag_active = true
	battle._consume_events([cast_event(16, player)])
	check(overlay.full.is_empty(), "drag selects compact")
	battle.selection_drag_active = false
	battle._sync_skill_cutin()
	overlay.set_mode("simple")
	battle._consume_events([cast_event(17, player)])
	check(overlay.full.is_empty() and overlay.compact.size() == 1, "simple clears previous cards and disables motion")
	overlay.set_mode("off")
	battle._consume_events([cast_event(18, player)])
	check(overlay.full.is_empty() and overlay.compact.is_empty() and not battle.recent_messages.is_empty(), "off still preserves battle logs")
	overlay.set_mode("full")
	overlay.textures.warspite.illustration = null
	battle._consume_events([cast_event(19, player)])
	check(overlay.full.is_empty() and overlay.compact.size() == 1, "missing illustration falls back to portrait")
	overlay.textures.warspite.portrait = null
	battle._consume_events([cast_event(20, player)])
	check(overlay.compact.size() == 2, "missing portrait retains text")
	battle.session.pause()
	battle._sync_skill_cutin()
	check(not overlay.visible and overlay.compact.is_empty(), "pause clears and hides")
	battle.session.resume()
	battle._sync_skill_cutin()
	check(overlay.visible and overlay.compact.is_empty(), "resume never replays")
	battle.session.state.phase = "Finished"
	battle._consume_events([cast_event(21, player)])
	check(overlay.full.is_empty() and overlay.compact.is_empty(), "terminal phase suppresses same-batch cast")
	battle._start_battle("level.prototype_1v1")
	battle._consume_events([cast_event(1, player)])
	check(overlay.full.get("event_id") == "event.1", "restart resets dedup and reloads assets")
	battle._consume_events([{"event_type":"CommandRejected", "command_type":"CastSkill", "issuer_type":"AI"}])
	check(overlay.compact.is_empty(), "rejected cast cannot create a card")
	battle.session.pause()
	battle._update_hud()
	await process_frame
	await process_frame
	check(battle.battle_hud.pause_panel.get_rect().end.y < battle.battle_hud.minimap_rect().position.y, "settings and pending plan fit above minimap")
	battle.battle_hud.skill_cutin_save_hint.text = "设置未保存，本次会话仍生效；请重新选择以重试"
	battle.battle_hud.skill_cutin_save_hint.show()
	await process_frame
	await process_frame
	check(battle.battle_hud.pause_panel.get_rect().end.y < battle.battle_hud.minimap_rect().position.y, "save failure warning does not cover minimap")
	battle.battle_hud.skill_cutin_save_hint.hide()
	var cfg := ConfigFile.new()
	var path := "user://skill_cutin_test.cfg"
	cfg.set_value("menu", "cover_id", "fixture")
	cfg.set_value("display", "width", 2560)
	cfg.save(path)
	var previous: String = flow.skill_cutin_mode
	check(flow.save_skill_cutin_mode("simple", path), "preference saves")
	cfg.load(path)
	check(cfg.get_value("battle", "skill_cutin_mode") == "simple" and cfg.get_value("menu", "cover_id") == "fixture" and cfg.get_value("display", "width") == 2560, "persistence preserves other sections")
	check(flow.normalize_skill_cutin_mode("unknown") == "full", "invalid legacy value defaults full")
	check(not flow.save_skill_cutin_mode("off", "user://missing-cutin-folder/settings.cfg") and flow.skill_cutin_mode == "off", "save failure keeps session preference")
	flow.skill_cutin_mode = previous
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	battle._start_battle("level.prototype_1v1")
	var picked_source: Dictionary = battle.session.state.units_by_id[player]
	var picked_target: Dictionary = battle.session.state.units_by_id[enemy]
	picked_target.position = picked_source.position + Vector2(200, 0)
	battle.session.state.visible_by_faction.player = {enemy:true}
	picked_source.skill_state.cooldown_remaining = 0.0
	battle.operation_mode = battle.OperationMode.TARGETING_SKILL
	battle.skill_target_type = "Enemy"
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = battle.get_global_transform_with_canvas() * picked_target.position
	check(battle._pointer_event_world_position(click.position).distance_to(picked_target.position) < 0.01, "button event projects correctly through battle camera")
	battle._unhandled_input(click)
	var clicked_events: Array = battle.session.advance_tick(0.1)
	check(clicked_events.any(func(e): return e.get("event_type") == "SkillCast" and e.get("unit_id") == player), "entity skill uses event position even when polled pointer differs")
	var signatures: Array = []
	for mode in ["full", "simple", "off"]:
		battle.player_command_sequence = 0
		battle._start_battle("level.prototype_1v1")
		overlay.set_mode(mode)
		var source: Dictionary = battle.session.state.units_by_id[player]
		var target: Dictionary = battle.session.state.units_by_id[enemy]
		source.position = Vector2(300,350)
		target.position = Vector2(750,350)
		battle.session.state.visible_by_faction.player = {enemy:true}
		source.skill_state.cooldown_remaining = 0.0
		var result: Dictionary = battle.session._cast_skill(source, {"type":"Entity", "entity_id":enemy}, "fixture.cast")
		check(result.get("accepted", false), mode + " real shared cast accepted")
		battle._consume_events(battle.session._event_buffer.duplicate(true))
		check((not overlay.full.is_empty()) if mode == "full" else (overlay.compact.size() == 1 if mode == "simple" else overlay.compact.is_empty()), mode + " real cast reaches expected UI")
		var facts: Array = []
		for tick in range(50):
			var tick_events: Array = battle.session.advance_tick(0.1)
			facts.append_array(tick_events.duplicate(true))
			battle._consume_events(tick_events)
			overlay.advance(0.1)
		signatures.append(var_to_str(without_timings({"facts":facts, "state":battle.session.snapshot()})))
	check(signatures[0] == signatures[1] and signatures[1] == signatures[2], "same seed and commands: facts and snapshot identical in all display modes over 50 ticks")
	battle.free()
	print("Skill cutin: %d checks, %d failures" % [checks, failures.size()])
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func without_timings(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key in value:
			if str(key).ends_with("_usec"): continue
			result[key] = without_timings(value[key])
		return result
	if value is Array:
		return value.map(without_timings)
	return value
