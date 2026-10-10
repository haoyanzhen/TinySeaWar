extends "res://scripts/presentation/battle/prototype_battle.gd"
const ReviewAssets = preload("res://tools/art_review/far_view/review_assets.gd")
const PilotView = preload("res://tools/art_review/far_view/pilot_view.gd")
var review_assets = ReviewAssets.new()
var candidate_enabled := true
var candidate_height := 56.0
func _ready() -> void:
	progress_recording_enabled = false
	super._ready()
	unit_layer.y_sort_enabled = true
	battle_camera.zoom = Vector2.ONE * camera_zoom_min
	_clamp_camera_to_map()
func _sync_visuals() -> void:
	super._sync_visuals()
	apply_review_views()
func apply_review_views() -> void:
	if effect_director == null: return
	for id in effect_director.unit_views.keys():
		var view = effect_director.unit_views[id]
		var pilot: bool = view.get_script() == PilotView
		var wanted: bool = candidate_enabled and review_assets.has_character(view.character_id)
		if wanted != pilot:
			var next = PilotView.new() if wanted else load("res://scripts/presentation/battle/ship_unit_view.gd").new()
			unit_layer.add_child(next)
			next.configure(view.unit)
			if wanted: next.setup_review(review_assets)
			next.update_unit(view.unit,view.selected,view.focused,view.primary_selected)
			effect_director.unit_views[id] = next
			view.hide()
			view.queue_free()
			view = next
		if wanted:
			view.review_zoom = battle_camera.zoom.x
			view.far_zoom = camera_zoom_min
			view.target_height = candidate_height
			view.frozen = session.state.get("phase","") != "Running"
			view.hovered = _pointer_over_battle(view)
func _pointer_over_battle(view) -> bool:
	return view.hit_score(get_global_mouse_position()) < 1.0 and battle_hud.battle_rect().has_point(get_viewport().get_mouse_position())
func _unit_at(world_position: Vector2, snapshot: Dictionary) -> Dictionary:
	if not candidate_enabled: return super._unit_at(world_position,snapshot)
	var best: Dictionary = {}
	var score := INF
	var ids: Array = snapshot.get("units",{}).keys()
	ids.sort()
	for id in ids:
		var unit: Dictionary = snapshot.units[id]
		var view = effect_director.unit_views.get(id)
		var value := INF
		if view != null and view.get_script() == PilotView:
			value = view.hit_score(world_position)
		else:
			var distance := CollisionGeometryService.normalized_distance(world_position,unit.position,float(unit.heading),CollisionGeometryService.half_extents(unit),8.0)
			if distance <= 1.0: value = 1.0 + distance
		if value < score:
			score = value
			best = unit
	return best
func _select_at(world_position: Vector2, snapshot: Dictionary, additive: bool = false) -> void:
	var picked := _unit_at(world_position,snapshot)
	if picked.is_empty():
		# Preserve facility handling, but do not use hidden units from the session.
		super._select_at(world_position,{"units":{},"facilities":snapshot.get("facilities",[])},additive)
		return
	var single := snapshot.duplicate()
	single["units"] = {str(picked.entity_id):picked}
	super._select_at(picked.position,single,additive)
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F6:
			candidate_enabled = not candidate_enabled
			_sync_visuals()
			_push_message("评审：" + ("候选 %dpx" % candidate_height if candidate_enabled else "原版"))
			return
		if event.keycode == KEY_F7:
			candidate_height = 48.0 if candidate_height == 64.0 else candidate_height+8.0
			_sync_visuals()
			_push_message("评审：候选 %dpx" % candidate_height)
			return
	super._unhandled_input(event)
