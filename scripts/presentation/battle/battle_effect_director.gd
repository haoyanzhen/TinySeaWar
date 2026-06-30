extends Node

const ShipUnitView = preload("res://scripts/presentation/battle/ship_unit_view.gd")
const ProjectileView = preload("res://scripts/presentation/battle/projectile_view.gd")
const BattleVfx = preload("res://scripts/presentation/battle/battle_vfx.gd")
const DamageNumberView = preload("res://scripts/presentation/battle/damage_number_view.gd")
const ShellFlightView = preload("res://scripts/presentation/battle/shell_flight_view.gd")
const LARGE_GUN_CALIBER_MM := 280.0

var unit_layer: Node2D
var projectile_layer: Node2D
var vfx_layer: Node2D
var unit_views := {}
var projectile_views := {}
var damage_number_views_by_target := {}
var terrain_collision_tick_by_unit := {}


func setup(new_unit_layer: Node2D, new_projectile_layer: Node2D, new_vfx_layer: Node2D) -> void:
	unit_layer = new_unit_layer
	projectile_layer = new_projectile_layer
	vfx_layer = new_vfx_layer
	clear()


func clear() -> void:
	for view in unit_views.values():
		if is_instance_valid(view):
			view.queue_free()
	for view in projectile_views.values():
		if is_instance_valid(view):
			view.queue_free()
	unit_views.clear()
	projectile_views.clear()
	damage_number_views_by_target.clear()
	terrain_collision_tick_by_unit.clear()
	if projectile_layer != null:
		for child in projectile_layer.get_children():
			child.queue_free()
	if vfx_layer != null:
		for child in vfx_layer.get_children():
			child.queue_free()


func sync_snapshot(snapshot: Dictionary, selected_unit_id: String, focused_target_id: String) -> void:
	_sync_units(snapshot.get("units", {}), selected_unit_id, focused_target_id)
	_sync_projectiles(snapshot.get("projectiles", {}))


func consume_events(events: Array, session) -> void:
	for event in events:
		match str(event.get("event_type", "")):
			"WeaponFired": _handle_weapon_fired(event, session)
			"ProjectileHit": _handle_projectile_hit(event, session)
			"ProjectileBlockedByTerrain": _handle_projectile_blocked(event)
			"ShellBlockedByTerrain": _handle_shell_blocked(event)
			"UnitTerrainCollision": _handle_unit_terrain_collision(event)
			"MineTriggered": _spawn_environment_marker("environment.mine_trigger", event.get("position", Vector2.ZERO), "vfx.profile.shell_impact")
			"FacilityDamaged", "FacilityDestroyed": _handle_facility_damage(event, session)
			"SupportMissionResolved": _handle_support_resolved(event)
			"AttackResolved": _handle_attack_resolved(event, session)
			"SkillCast": _handle_skill_cast(event, session)


func _sync_units(units: Dictionary, selected_unit_id: String, focused_target_id: String) -> void:
	var live_ids := {}
	for unit_id in units:
		live_ids[unit_id] = true
		var unit: Dictionary = units[unit_id]
		var view: ShipUnitView = unit_views.get(unit_id, null)
		if view == null:
			view = ShipUnitView.new()
			unit_layer.add_child(view)
			view.configure(unit)
			unit_views[unit_id] = view
		view.update_unit(unit, str(unit_id) == selected_unit_id, str(unit_id) == focused_target_id)
	for unit_id in unit_views.keys():
		if live_ids.has(unit_id):
			continue
		var old_view: Node = unit_views[unit_id]
		unit_views.erase(unit_id)
		if is_instance_valid(old_view):
			old_view.queue_free()


func _sync_projectiles(projectiles: Dictionary) -> void:
	var live_ids := {}
	for projectile_id in projectiles:
		live_ids[projectile_id] = true
		var projectile: Dictionary = projectiles[projectile_id]
		var view: ProjectileView = projectile_views.get(projectile_id, null)
		if view == null:
			view = ProjectileView.new()
			projectile_layer.add_child(view)
			view.configure(projectile, DataRegistry.assets.projectile_visual(str(projectile.get("definition_id", ""))))
			projectile_views[projectile_id] = view
		else:
			view.update_projectile(projectile)
	for projectile_id in projectile_views.keys():
		if live_ids.has(projectile_id):
			continue
		var old_view: Node = projectile_views[projectile_id]
		projectile_views.erase(projectile_id)
		if is_instance_valid(old_view):
			old_view.queue_free()


func _handle_weapon_fired(event: Dictionary, session) -> void:
	var source_unit_id := str(event.get("unit_id", ""))
	var source: Dictionary = session.state.get("units_by_id", {}).get(source_unit_id, {})
	if source.is_empty():
		return
	var character_id := str(source.get("definition_id", "")).trim_prefix("ship.")
	var weapon: Dictionary = DataRegistry.registry.get_definition("weapons", str(event.get("weapon_id", "")))
	var visual := DataRegistry.assets.weapon_visual(character_id, str(weapon.get("weapon_group_id", "")))
	var view: ShipUnitView = unit_views.get(source_unit_id, null)
	if view != null:
		view.play_fire_state(str(visual.get("fire_animation_state", "attack")))
		var launch_position := view.bind_point_world(str(visual.get("launch_bind", "")))
		_spawn_shell_flights(event, session, weapon, visual, source, launch_position)
		_spawn_role_vfx(character_id, str(visual.get("muzzle_vfx_role", "")), launch_position, float(source.get("heading", 0.0)), str(visual.get("launch_profile", "vfx.profile.muzzle_flash")))


func _handle_projectile_hit(event: Dictionary, session) -> void:
	var projectile_id := str(event.get("projectile_id", ""))
	var projectile_view: Node = projectile_views.get(projectile_id, null)
	if projectile_view != null and is_instance_valid(projectile_view):
		projectile_view.queue_free()
		projectile_views.erase(projectile_id)
	var target_id := str(event.get("target_unit_id", ""))
	var target: Dictionary = session.state.get("units_by_id", {}).get(target_id, {})
	if target.is_empty():
		return
	var character_id := str(target.get("definition_id", "")).trim_prefix("ship.")
	var target_view: ShipUnitView = unit_views.get(target_id, null)
	if target_view != null:
		target_view.play_hit_state()
	_spawn_role_vfx(character_id, _impact_role_for_target(character_id), event.get("position", target.get("position", Vector2.ZERO)), 0.0, "vfx.profile.torpedo_impact")


func _handle_projectile_blocked(event: Dictionary) -> void:
	var projectile_id := str(event.get("projectile_id", ""))
	var projectile_view: Node = projectile_views.get(projectile_id, null)
	if projectile_view != null and is_instance_valid(projectile_view):
		projectile_view.queue_free()
		projectile_views.erase(projectile_id)
	_spawn_public_vfx("environment.torpedo_terrain_impact", event.get("position", Vector2.ZERO), "vfx.profile.torpedo_impact")


func _handle_shell_blocked(event: Dictionary) -> void:
	var weapon: Dictionary = DataRegistry.registry.get_definition("weapons", str(event.get("source_weapon_id", "")))
	var size := "small"
	var caliber := _weapon_caliber_mm(weapon, {}, {})
	if caliber >= 280.0: size = "large"
	elif caliber >= 155.0: size = "medium"
	_spawn_public_vfx("environment.shell_terrain_impact.%s" % size, event.get("position", Vector2.ZERO), "vfx.profile.water_impact.large")


func _handle_unit_terrain_collision(event: Dictionary) -> void:
	var unit_id := str(event.get("unit_id", ""))
	var tick := int(event.get("tick_index", 0))
	if tick - int(terrain_collision_tick_by_unit.get(unit_id, -1000)) < 8:
		return
	terrain_collision_tick_by_unit[unit_id] = tick
	_spawn_environment_marker("terrain_collision", event.get("position", Vector2.ZERO), "vfx.profile.skill_area")


func _handle_facility_damage(event: Dictionary, session) -> void:
	var facility: Dictionary = session.state.get("facilities_by_id", {}).get(str(event.get("facility_id", "")), {})
	if facility.is_empty(): return
	_spawn_public_vfx("environment.shell_terrain_impact.medium", facility.get("position", Vector2.ZERO), "vfx.profile.shell_impact")


func _handle_support_resolved(event: Dictionary) -> void:
	if str(event.get("effect_type", "")) == "Airstrike":
		_spawn_public_vfx("impact.water.large", event.get("target_position", Vector2.ZERO), "vfx.profile.water_impact.large")


func _handle_attack_resolved(event: Dictionary, session) -> void:
	var result: Dictionary = event.get("damage_result", {})
	var source: Dictionary = session.state.get("units_by_id", {}).get(str(result.get("source_unit_id", "")), {})
	var source_character := str(source.get("definition_id", "")).trim_prefix("ship.")
	var weapon: Dictionary = DataRegistry.registry.get_definition("weapons", str(result.get("source_weapon_id", "")))
	var visual := DataRegistry.assets.weapon_visual(source_character, str(weapon.get("weapon_group_id", "")))
	var target_id := str(result.get("target_unit_id", ""))
	if target_id.is_empty():
		_spawn_large_gun_water_column(result, weapon, visual)
		return
	var target: Dictionary = session.state.get("units_by_id", {}).get(target_id, {})
	if target.is_empty():
		return
	var target_view: ShipUnitView = unit_views.get(target_id, null)
	if target_view != null and bool(result.get("hit", false)):
		target_view.play_hit_state()
	_spawn_damage_number(result, session)
	if not bool(result.get("hit", false)):
		_spawn_large_gun_water_column(result, weapon, visual)
		return
	var target_position: Vector2 = target.get("position", Vector2.ZERO)
	_spawn_role_vfx(source_character, str(visual.get("impact_vfx_role", "")), target_position, 0.0, str(visual.get("impact_profile", "vfx.profile.shell_impact")))


func _spawn_large_gun_water_column(result: Dictionary, weapon: Dictionary, weapon_visual: Dictionary) -> void:
	if not _is_large_caliber_gun(weapon, weapon_visual):
		return
	var impact_position = result.get("impact_position")
	if typeof(impact_position) != TYPE_VECTOR2:
		return
	_spawn_public_vfx("impact.water.large", impact_position, "vfx.profile.water_impact.large")


func _is_large_caliber_gun(weapon: Dictionary, weapon_visual: Dictionary) -> bool:
	if weapon.get("mount_type", "") != "Gun":
		return false
	var projectile_visual_id := str(weapon_visual.get("projectile_visual_id", weapon.get("projectile_id", "")))
	var projectile_visual := DataRegistry.assets.projectile_visual(projectile_visual_id)
	return _weapon_caliber_mm(weapon, weapon_visual, projectile_visual) >= LARGE_GUN_CALIBER_MM


func _handle_skill_cast(event: Dictionary, session) -> void:
	var source: Dictionary = session.state.get("units_by_id", {}).get(str(event.get("unit_id", "")), {})
	if source.is_empty():
		return
	var character_id := str(source.get("definition_id", "")).trim_prefix("ship.")
	var role := _skill_role_for_character(character_id)
	var target_position: Vector2 = source.get("position", Vector2.ZERO)
	var target_ref: Dictionary = event.get("target_ref", {})
	if typeof(target_ref.get("position")) == TYPE_VECTOR2:
		target_position = target_ref["position"]
	elif not str(target_ref.get("entity_id", "")).is_empty():
		var target: Dictionary = session.state.get("units_by_id", {}).get(str(target_ref.get("entity_id", "")), {})
		if not target.is_empty():
			target_position = target.get("position", target_position)
	_spawn_role_vfx(character_id, role, target_position, 0.0, "vfx.profile.skill_area")


func _spawn_role_vfx(character_id: String, role_name: String, world_position: Vector2, rotation_value: float, profile_id: String) -> void:
	if character_id.is_empty() or role_name.is_empty() or vfx_layer == null:
		return
	var role := DataRegistry.assets.vfx_role(character_id, role_name)
	if role.is_empty():
		return
	var effect := BattleVfx.new()
	effect.position = world_position
	vfx_layer.add_child(effect)
	effect.configure(str(role.get("file", "")), DataRegistry.assets.vfx_playback_profile(profile_id), rotation_value)


func _spawn_public_vfx(semantic: String, world_position: Vector2, profile_id: String) -> void:
	if vfx_layer == null:
		return
	var texture_path := DataRegistry.assets.combat_vfx_asset_path(semantic)
	if texture_path.is_empty():
		return
	var effect := BattleVfx.new()
	effect.position = world_position
	vfx_layer.add_child(effect)
	effect.configure(texture_path, DataRegistry.assets.vfx_playback_profile(profile_id))


func _spawn_environment_marker(semantic: String, world_position: Vector2, profile_id: String) -> void:
	if vfx_layer == null:
		return
	var texture_path := DataRegistry.assets.environment_asset_path(semantic)
	if texture_path.is_empty():
		return
	var effect := BattleVfx.new()
	effect.position = world_position
	vfx_layer.add_child(effect)
	effect.configure(texture_path, DataRegistry.assets.vfx_playback_profile(profile_id))


func _spawn_shell_flights(event: Dictionary, session, weapon: Dictionary, weapon_visual: Dictionary, source: Dictionary, launch_position: Vector2) -> void:
	if projectile_layer == null or str(weapon.get("mount_type", "")) != "Gun":
		return
	var projectile_visual_id := str(weapon_visual.get("projectile_visual_id", weapon.get("projectile_id", "")))
	var projectile_visual := DataRegistry.assets.projectile_visual(projectile_visual_id)
	if projectile_visual.is_empty() or str(projectile_visual.get("projectile_type", "")) != "Shell":
		return
	var multiplier := float(weapon_visual.get("shell_trail_caliber_pixel_multiplier", projectile_visual.get("shell_trail_caliber_pixel_multiplier", 0.1)))
	var caliber_mm := _weapon_caliber_mm(weapon, weapon_visual, projectile_visual)
	var length_px := maxf(1.0, caliber_mm * multiplier)
	var width_px := float(weapon_visual.get("shell_trail_width", projectile_visual.get("shell_trail_width", 1.5)))
	var trail_fade_seconds := float(weapon_visual.get("shell_trail_duration", projectile_visual.get("shell_trail_duration", 0.18)))
	var color := _shell_trail_color(weapon, weapon_visual, projectile_visual)
	for destination in _shell_flight_destinations(event, session, weapon, source, launch_position):
		var travel_seconds := launch_position.distance_to(destination) / maxf(1.0, float(weapon.get("projectile_speed", 1.0)))
		var duration_seconds := maxf(float(weapon_visual.get("shell_flight_min_duration", 0.08)), travel_seconds)
		var flight := ShellFlightView.new()
		flight.z_index = 18
		projectile_layer.add_child(flight)
		flight.configure(launch_position, destination, projectile_visual, color, length_px, width_px, duration_seconds, trail_fade_seconds)


func _shell_flight_destinations(event: Dictionary, session, weapon: Dictionary, source: Dictionary, launch_position: Vector2) -> Array:
	var count := clampi(int(event.get("shot_count", 1)), 1, 12)
	var fixed_impact_positions: Array = event.get("impact_positions", [])
	if not fixed_impact_positions.is_empty():
		var fixed_destinations: Array = []
		for index in range(mini(count, fixed_impact_positions.size())):
			if typeof(fixed_impact_positions[index]) == TYPE_VECTOR2:
				fixed_destinations.append(fixed_impact_positions[index])
		return fixed_destinations
	var base_destination := _weapon_fire_destination(event, session, source, launch_position)
	var destinations: Array = []
	for shot_index in range(count): destinations.append(base_destination)
	return destinations


func _weapon_fire_destination(event: Dictionary, session, source: Dictionary, launch_position: Vector2) -> Vector2:
	if typeof(event.get("target_position")) == TYPE_VECTOR2:
		return event["target_position"]
	var target_id := str(event.get("target_unit_id", ""))
	if not target_id.is_empty():
		var target: Dictionary = session.state.get("units_by_id", {}).get(target_id, {})
		if not target.is_empty():
			return target.get("position", launch_position)
	return launch_position + Vector2.RIGHT.rotated(float(source.get("heading", 0.0))) * 160.0


func _weapon_caliber_mm(weapon: Dictionary, weapon_visual: Dictionary, projectile_visual: Dictionary) -> float:
	for field in ["shell_caliber_mm", "caliber_mm"]:
		if weapon_visual.has(field):
			return maxf(1.0, float(weapon_visual.get(field, 0.0)))
		if weapon.has(field):
			return maxf(1.0, float(weapon.get(field, 0.0)))
	var parsed := _parse_caliber_mm("%s %s" % [weapon.get("display_name", ""), weapon.get("id", "")])
	if parsed > 0.0:
		return parsed
	var visual_id := str(projectile_visual.get("id", ""))
	if visual_id.contains("superheavy"):
		return 460.0
	if visual_id.contains("large"):
		return 381.0
	if visual_id.contains("medium"):
		return 203.0
	if visual_id.contains("small"):
		return 127.0
	return 152.0


func _parse_caliber_mm(text: String) -> float:
	var expression := RegEx.new()
	if expression.compile("(\\d+(?:\\.\\d+)?)\\s*(?:mm|毫米)") != OK:
		return 0.0
	var result := expression.search(text)
	if result == null:
		return 0.0
	return float(result.get_string(1))


func _shell_trail_color(weapon: Dictionary, weapon_visual: Dictionary, projectile_visual: Dictionary) -> Color:
	var color_key := str(weapon_visual.get("shell_trail_color_key", projectile_visual.get("shell_trail_color_key", "")))
	if color_key.is_empty():
		color_key = "clean_white" if str(weapon.get("ammo_type", "")) == "AP" else "fire_yellow"
	var palette = projectile_visual.get("shell_trail_color_palette", {})
	if palette is Dictionary and palette.has(color_key):
		return Color(str(palette[color_key]))
	return Color(str(projectile_visual.get("trail_color", "#ffd777")))


func _spawn_damage_number(result: Dictionary, session) -> void:
	if vfx_layer == null or not _damage_result_visible_to_player(result, session):
		return
	var entry := _damage_number_entry(result, session)
	if entry.is_empty():
		return
	var target_id := str(entry.get("target_unit_id", ""))
	var active_views := _active_damage_number_views(target_id)
	for view in active_views:
		if view.can_absorb(entry):
			view.absorb(entry)
			damage_number_views_by_target[target_id] = active_views
			return
	if active_views.size() >= 3:
		active_views.sort_custom(func(a, b): return int(a.priority) < int(b.priority))
		var lowest: DamageNumberView = active_views[0]
		if int(entry.get("priority", 1)) <= int(lowest.priority):
			if lowest.can_absorb(entry):
				lowest.absorb(entry)
			damage_number_views_by_target[target_id] = active_views
			return
		lowest.queue_free()
		active_views.remove_at(0)
	var number := DamageNumberView.new()
	number.position = entry.get("position", Vector2.ZERO)
	number.z_index = 35
	vfx_layer.add_child(number)
	number.configure(entry)
	active_views.append(number)
	damage_number_views_by_target[target_id] = active_views


func _active_damage_number_views(target_id: String) -> Array:
	var result: Array = []
	for view in damage_number_views_by_target.get(target_id, []):
		if is_instance_valid(view) and not view.is_queued_for_deletion():
			result.append(view)
	return result


func _damage_result_visible_to_player(result: Dictionary, session) -> bool:
	var target_id := str(result.get("target_unit_id", ""))
	if target_id.is_empty():
		return false
	var target: Dictionary = session.state.get("units_by_id", {}).get(target_id, {})
	if target.is_empty():
		return false
	if str(target.get("faction_id", "")) == "player":
		return true
	return session.state.get("visible_by_faction", {}).get("player", {}).has(target_id)


func _damage_number_entry(result: Dictionary, session) -> Dictionary:
	var target_id := str(result.get("target_unit_id", ""))
	if target_id.is_empty():
		return {}
	var target: Dictionary = session.state.get("units_by_id", {}).get(target_id, {})
	if target.is_empty():
		return {}
	var source: Dictionary = session.state.get("units_by_id", {}).get(str(result.get("source_unit_id", "")), {})
	var weapon: Dictionary = DataRegistry.registry.get_definition("weapons", str(result.get("source_weapon_id", "")))
	var style := _damage_number_style(result, weapon)
	if style.is_empty():
		return {}
	var target_position: Vector2 = target.get("position", Vector2.ZERO)
	var anchor := target_position + Vector2(0.0, -float(target.get("stats", {}).get("collision_radius", 20.0)) - 42.0)
	var side := 0.0
	if not source.is_empty():
		var from_source := target_position - (source.get("position", target_position) as Vector2)
		if absf(from_source.x) > 0.1:
			side = signf(from_source.x) * float(style.get("side_distance", 0.0))
	var amount := float(result.get("final_damage", 0.0))
	var numeric := bool(style.get("numeric", true))
	var text := str(style.get("text", ""))
	if numeric:
		text = str(int(round(amount)))
	return {
		"target_unit_id": target_id,
		"position": anchor,
		"amount": amount,
		"hit_count": 1,
		"numeric": numeric,
		"text": text,
		"priority": int(style.get("priority", 1)),
		"duration": float(style.get("duration", 0.55)),
		"font_size": int(style.get("font_size", 20)),
		"rise_distance": float(style.get("rise_distance", 32.0)),
		"side_distance": side,
		"hold_seconds": float(style.get("hold_seconds", 0.0)),
		"fill_color": style.get("fill_color", Color.WHITE),
		"inner_outline_color": style.get("inner_outline_color", Color(1.0, 1.0, 1.0, 0.0)),
		"outer_outline_color": style.get("outer_outline_color", Color(0.02, 0.08, 0.12, 0.92)),
		"outline_size": int(style.get("outline_size", 3)),
	}


func _damage_number_style(result: Dictionary, weapon: Dictionary) -> Dictionary:
	var damage_type := str(result.get("damage_type", weapon.get("mount_type", "")))
	var hit := bool(result.get("hit", false))
	var final_damage := float(result.get("final_damage", 0.0))
	if not hit:
		return _label_damage_style("未命中", damage_type)
	if final_damage <= 0.0:
		var weapon_id := str(result.get("source_weapon_id", ""))
		return _label_damage_style("跳弹" if weapon_id.contains("_ap") else "格挡", damage_type)
	var weapon_id := str(result.get("source_weapon_id", ""))
	var formula_id := str(weapon.get("formula_id", ""))
	if damage_type == "Torpedo":
		return {"font_size": 24, "duration": 0.82, "rise_distance": 42.0, "side_distance": 28.0, "priority": 4, "fill_color": Color("#ff6f61"), "inner_outline_color": Color(1.0, 1.0, 1.0, 0.92), "outer_outline_color": Color("#12304f"), "outline_size": 4}
	if damage_type == "Aviation":
		return {"font_size": 24, "duration": 0.70, "rise_distance": 38.0, "priority": 4, "fill_color": Color("#c77dff") if formula_id.contains("ap") else Color("#ffa53a"), "inner_outline_color": Color(1.0, 1.0, 1.0, 0.82), "outer_outline_color": Color("#1e2444"), "outline_size": 4}
	if damage_type == "AntiAir":
		return {"font_size": 12, "duration": 0.48, "rise_distance": 22.0, "priority": 1, "fill_color": Color("#d7f7ff"), "outer_outline_color": Color("#234256"), "outline_size": 3}
	if damage_type == "AntiSubmarine":
		return {"font_size": 40, "duration": 0.80, "rise_distance": 48.0, "priority": 4, "fill_color": Color("#4db5ff"), "inner_outline_color": Color(1.0, 1.0, 1.0, 0.82), "outer_outline_color": Color("#092a44"), "outline_size": 4}
	if formula_id.contains("_ap") or weapon_id.contains("_ap"):
		return {"font_size": 48, "duration": 0.78, "rise_distance": 52.0, "hold_seconds": 0.08, "priority": 5, "fill_color": Color("#ffd54f"), "inner_outline_color": Color(1.0, 1.0, 1.0, 0.86), "outer_outline_color": Color("#02060a"), "outline_size": 5}
	if formula_id.contains("large"):
		return {"font_size": 50, "duration": 0.76, "rise_distance": 52.0, "priority": 5, "fill_color": Color("#ffae35"), "outer_outline_color": Color("#123a48"), "outline_size": 5}
	if formula_id.contains("medium"):
		return {"font_size": 24, "duration": 0.58, "rise_distance": 36.0, "priority": 3, "fill_color": Color("#64cfff"), "inner_outline_color": Color(1.0, 1.0, 1.0, 0.82), "outer_outline_color": Color("#083542"), "outline_size": 4}
	return {"font_size": 12, "duration": 0.46, "rise_distance": 24.0, "priority": 1, "fill_color": Color("#bec6cf"), "outer_outline_color": Color("#1d252d"), "outline_size": 3}


func _label_damage_style(label: String, damage_type: String) -> Dictionary:
	var base_size := 14
	var fill := Color("#d9e2ec")
	if damage_type == "Torpedo":
		base_size = 18
		fill = Color("#ffb0a6")
	elif damage_type == "Aviation":
		base_size = 18
		fill = Color("#e1c6ff")
	elif damage_type == "AntiSubmarine":
		base_size = 28
		fill = Color("#9bdcff")
	return {"numeric": false, "text": label, "font_size": base_size, "duration": 0.48, "rise_distance": 18.0, "priority": 0, "fill_color": fill, "outer_outline_color": Color("#10202b"), "outline_size": 3}


func _impact_role_for_target(character_id: String) -> String:
	var roles := DataRegistry.assets.vfx_roles(character_id)
	for candidate in ["water_impact", "splash", "water_splash", "armor_hit", "bubble_trail"]:
		if roles.has(candidate):
			return candidate
	return ""


func _skill_role_for_character(character_id: String) -> String:
	var roles := DataRegistry.assets.vfx_roles(character_id)
	for candidate in ["royal_area", "decisive_area", "support_area", "suppression_area", "stealth", "sonar_pulse"]:
		if roles.has(candidate):
			return candidate
	return ""
