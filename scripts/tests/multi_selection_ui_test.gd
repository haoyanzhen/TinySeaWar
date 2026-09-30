extends SceneTree

var checks := 0
var failures: Array[String] = []
var battle

func _init() -> void: call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _key(code: Key, fleet: bool = false, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.alt_pressed = fleet
	event.echo = echo
	battle._unhandled_input(event)

func _orders(kind: String) -> Array:
	return battle.session.pending_player_commands().filter(func(c): return c.get("command_type") == kind)

func _select_all() -> Array:
	battle._select_in_rect(Rect2(-Vector2.ONE * 10000, Vector2.ONE * 30000), battle.session.snapshot("player", false))
	return battle._selected_live_ids()

func _run() -> void:
	battle = load("res://scenes/battle/prototype_battle.tscn").instantiate()
	root.add_child(battle)
	battle.set_process(false)
	battle.session.pause()
	var ids := _select_all()
	_check(ids.size() == 3, "box selects all three friendlies")
	_key(KEY_1)
	var focus: String = battle.selected_unit_id
	_key(KEY_A)
	_check(battle._selected_live_ids().size() == 1, "A no longer selects fleet")
	_key(KEY_T)
	_check(battle._selected_live_ids().size() == ids.size() and battle.selected_unit_id == focus, "T selects whole fleet and preserves focus while paused")
	var camera_bindings := {"camera_left": KEY_A, "camera_right": KEY_D, "camera_up": KEY_W, "camera_down": KEY_S}
	for action in camera_bindings:
		_check(InputMap.action_get_events(action).all(func(e): return not e is InputEventKey or (e.physical_keycode != KEY_T and e.keycode != KEY_T)), "T has no camera binding: " + action)
		_check(InputMap.action_get_events(action).any(func(e): return e is InputEventKey and e.physical_keycode == camera_bindings[action]), "WASD restored: " + action)
	battle._sync_visuals()
	for id in ids:
		_check(battle.effect_director.unit_views[id].selected, "unit draws own selection marker: " + id)
	_check(battle.effect_director.unit_views.values().filter(func(v): return v.primary_selected).size() == 1, "one primary emphasis within group")
	_check(battle.effect_director.unit_views.values().filter(func(v): return v.selected).size() == ids.size(), "enemy views are not selected")
	for code in [KEY_X, KEY_V, KEY_C]:
		_key(code)
		var order: Dictionary = _orders("SetUnitControlState")[-1]
		_check(order.get("unit_ids", []).size() == ids.size(), "shortcut covers selected group: %s" % code)
		var count := _orders("SetUnitControlState").size()
		_key(code, false, true)
		_check(_orders("SetUnitControlState").size() == count, "key repeat does not retoggle: %s" % code)
	_key(KEY_V)
	_check(ids.all(func(id): return not battle.session.get_planned_control_state(id)["primary_auto_fire_enabled"]), "second paused V disables whole group")
	_key(KEY_Q)
	_check(_orders("SwitchAmmo").size() == ids.filter(func(id): return battle.session.get_operation_status(id).get("q_enabled", false)).size(), "Q queues each applicable ship")
	_key(KEY_Z)
	battle._append_route_waypoint(Vector2(1000, 1000))
	_check(_orders("AppendMoveWaypoint").size() == ids.size(), "Z waypoint applies to group")
	_key(KEY_ESCAPE)
	_key(KEY_E)
	_check(battle.primary_aim_unit_ids.size() == ids.size(), "E captures all ready ships")
	_check(ids.all(func(id): return battle.session.get_planned_control_state(id).get("primary_auto_fire_suspended", false)), "E suspends every aiming ship")
	_key(KEY_T)
	_check(battle.operation_mode == battle.OperationMode.NORMAL and ids.all(func(id): return not battle.session.get_planned_control_state(id).get("primary_auto_fire_suspended", false)), "T cancels group aiming and releases locks")
	_key(KEY_E)
	_key(KEY_1)
	_check(ids.all(func(id): return not battle.session.get_planned_control_state(id).get("primary_auto_fire_suspended", false)), "changing selection releases original group aim locks")
	_check(battle.primary_aim_unit_ids.is_empty(), "changing selection clears pending aim group")
	_select_all()
	for id in ids: battle.session.state.units_by_id[id].skill_state.cooldown_remaining = 0.0
	_key(KEY_F)
	for id in ids:
		_check(_orders("CastSkill").any(func(c): return c.get("unit_id") == id) or id in battle.skill_target_unit_ids, "F dispatches or requests target for each ready ship: " + id)
	_key(KEY_ESCAPE)
	_key(KEY_1)
	battle._sync_visuals()
	_check(battle.effect_director.unit_views.values().filter(func(v): return v.selected).size() == 1, "single selection clears other markers")
	_key(KEY_V, true)
	_check(_orders("SetUnitControlState")[-1].get("unit_ids", []).size() == ids.size(), "Alt V retains fleet scope")
	# A common aim point is evaluated independently for each selected weapon.
	_select_all()
	_key(KEY_E)
	var target := Vector2.ZERO
	var legal_ids: Array = []
	for x in range(400, 2000, 200):
		for y in range(200, 1600, 200):
			var candidate := Vector2(x, y)
			var legal := ids.filter(func(id): return battle.session.get_primary_aim_status(id, candidate).get("legal", false))
			if legal.size() > legal_ids.size():
				target = candidate
				legal_ids = legal
	_check(legal_ids.size() >= 2, "fixture provides at least two legal shooters")
	battle._confirm_primary_aim(target)
	_check(_orders("FirePrimaryWeapon").size() == legal_ids.size(), "confirmation queues all and only legal shooters")
	_check(_orders("FirePrimaryWeapon").all(func(c): return c.target_position == target), "all shots share clicked point")
	_check(ids.all(func(id): return not battle.session.get_planned_control_state(id).get("primary_auto_fire_suspended", false)), "confirmation releases every aim lock")
	# Different skill target types share a click without duplicating Self skills.
	battle._start_battle("level.prototype_3v3")
	battle.session.pause()
	ids = _select_all()
	for id in ids: battle.session.state.units_by_id[id].skill_state.cooldown_remaining = 0.0
	battle.session.state.units_by_id[ids[0]].skill_state.definition_id = "skill.shimakaze_torpedo_storm"
	battle.session.state.units_by_id[ids[1]].skill_state.definition_id = "skill.enterprise_multi_wave"
	battle.session.state.units_by_id[ids[2]].skill_state.definition_id = "skill.iowa_radar_salvo"
	_key(KEY_F)
	_check(_orders("CastSkill").size() == 1 and battle.skill_target_unit_ids.size() == 2, "mixed F casts Self and waits for Area/Enemy")
	var enemy: Dictionary = battle.session.state.units_by_id.values().filter(func(u): return u.faction_id == "enemy")[0]
	battle.session.state.visible_by_faction.player[enemy.entity_id] = true
	battle._confirm_skill_target(enemy.position, battle.session.snapshot("player", false))
	_check(_orders("CastSkill").size() == 3, "mixed confirmation dispatches every skill once")
	_check(_orders("CastSkill").any(func(c): return c.unit_id == ids[1] and c.target_ref.type == "Position"), "Area gets click position")
	_check(_orders("CastSkill").any(func(c): return c.unit_id == ids[2] and c.target_ref.type == "Entity"), "Enemy gets clicked entity")
	# Mixed surface/submarine selection must not inherit the primary ship's C meaning.
	battle._start_battle("level.challenge.s04")
	battle.session.pause()
	ids = _select_all()
	_key(KEY_C)
	var subs := ids.filter(func(id): return battle.session.state.units_by_id[id].stats.ship_class == "Submarine")
	_check(not subs.is_empty(), "mixed fixture contains submarine")
	_check(_orders("SetSubmarineDepth").size() == subs.size(), "C requests depth for each submarine")
	_check(_orders("SetUnitControlState")[-1].unit_ids.all(func(id): return id not in subs), "C excludes submarines from secondary toggle")
	var before := _orders("SetSubmarineDepth").size()
	_key(KEY_C, true)
	_check(_orders("SetSubmarineDepth").size() == before, "fleet C preserves submarine depth")
	var sunk: String = ids[0]
	battle.session.state.units_by_id[sunk].life_state = "Sunk"
	_key(KEY_T)
	_check(sunk not in battle.selected_unit_ids and battle.selected_unit_ids.size() == ids.size() - 1, "T skips sunk fleet members")
	_key(KEY_X)
	_check(sunk not in _orders("SetUnitControlState")[-1].unit_ids, "sunk selection excluded from orders")
	battle.session.resume()
	battle.session.advance_tick(0.1)
	_check(ids.filter(func(id): return id != sunk).all(func(id): return battle.session.state.units_by_id[id].movement_assist_enabled), "group commands execute on resume")
	print("Multi-selection UI: %d/%d passed" % [checks - failures.size(), checks])
	for failure in failures: push_error(failure)
	battle.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
