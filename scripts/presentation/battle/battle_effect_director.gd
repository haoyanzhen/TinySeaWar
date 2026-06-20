extends Node

const ShipUnitView = preload("res://scripts/presentation/battle/ship_unit_view.gd")
const ProjectileView = preload("res://scripts/presentation/battle/projectile_view.gd")
const BattleVfx = preload("res://scripts/presentation/battle/battle_vfx.gd")

var unit_layer: Node2D
var projectile_layer: Node2D
var vfx_layer: Node2D
var unit_views := {}
var projectile_views := {}


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


func _handle_attack_resolved(event: Dictionary, session) -> void:
	var result: Dictionary = event.get("damage_result", {})
	var target_id := str(result.get("target_unit_id", ""))
	if target_id.is_empty():
		return
	var target: Dictionary = session.state.get("units_by_id", {}).get(target_id, {})
	if target.is_empty():
		return
	var target_view: ShipUnitView = unit_views.get(target_id, null)
	if target_view != null and bool(result.get("hit", false)):
		target_view.play_hit_state()
	var source: Dictionary = session.state.get("units_by_id", {}).get(str(result.get("source_unit_id", "")), {})
	var source_character := str(source.get("definition_id", "")).trim_prefix("ship.")
	var weapon: Dictionary = DataRegistry.registry.get_definition("weapons", str(result.get("source_weapon_id", "")))
	var visual := DataRegistry.assets.weapon_visual(source_character, str(weapon.get("weapon_group_id", "")))
	var target_position: Vector2 = target.get("position", Vector2.ZERO)
	_spawn_role_vfx(source_character, str(visual.get("impact_vfx_role", "")), target_position, 0.0, str(visual.get("impact_profile", "vfx.profile.shell_impact")))


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
