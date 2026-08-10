extends Node2D

const AnimationStateMachine = preload("res://scripts/presentation/battle/animation_state_machine.gd")
const CollisionGeometryService = preload("res://scripts/domain/services/collision_geometry_service.gd")

const DEFAULT_UNIT_SCALE := 0.28
const BODY_TARGET_MIN_WIDTH := 84.0
const BODY_TARGET_MAX_WIDTH := 126.0
const BODY_RADIUS_WIDTH_FACTOR := 3.8
const RIG_TARGET_MIN_WIDTH := 108.0
const RIG_TARGET_MAX_WIDTH := 162.0
const RIG_RADIUS_WIDTH_FACTOR := 5.0

var unit_id := ""
var character_id := ""
var unit := {}
var selected := false
var focused := false
var animation := AnimationStateMachine.new()
var texture_cache := {}
var body_texture: Texture2D
var rig_texture: Texture2D
var move_memory := 0.0
var body_art_scale := DEFAULT_UNIT_SCALE
var rig_art_scale := DEFAULT_UNIT_SCALE
var rig_heading_offset := 0.0


func configure(snapshot: Dictionary) -> void:
	unit_id = str(snapshot.get("entity_id", ""))
	character_id = str(snapshot.get("definition_id", "")).trim_prefix("ship.")
	animation.setup(character_id)
	_load_static_textures()
	update_unit(snapshot, false, false)


func update_unit(snapshot: Dictionary, is_selected: bool, is_focused: bool) -> void:
	var previous_position := position
	unit = snapshot.duplicate(true)
	selected = is_selected
	focused = is_focused
	position = snapshot.get("position", Vector2.ZERO)
	if previous_position.distance_to(position) > 0.08:
		move_memory = 0.22
	var scales := _unit_art_scales()
	body_art_scale = scales["body"]
	rig_art_scale = scales["rig"]
	queue_redraw()


func play_fire_state(state_name: String) -> void:
	animation.request_state(state_name, true)
	queue_redraw()


func play_hit_state() -> void:
	animation.request_state("hit", true)
	queue_redraw()


func current_animation_state() -> String:
	return animation.state_name


func bind_point_world(point_name: String) -> Vector2:
	var point := DataRegistry.assets.bind_point(character_id, point_name)
	if point.is_empty():
		return position
	var local := _bind_point_to_local(point)
	var asset_offset := deg_to_rad(DataRegistry.assets.heading_offset_degrees(character_id, str(point.get("asset_name", ""))))
	return position + local.rotated(float(unit.get("heading", 0.0)) + asset_offset)


func _process(delta: float) -> void:
	move_memory = maxf(0.0, move_memory - delta)
	var desired_state := "move" if move_memory > 0.0 else "idle"
	animation.update(delta, desired_state)
	queue_redraw()


func _draw() -> void:
	if unit.is_empty():
		return
	var radius := float(unit.get("collision_radius", 22.0))
	var collision_half_extents := CollisionGeometryService.half_extents(unit)
	var heading := float(unit.get("heading", 0.0))
	var friendly := str(unit.get("faction_id", "")) == "player"
	var fallback_color := Color("#63c7ff") if friendly else Color("#ff6b6b")
	if str(unit.get("life_state", "Alive")) == "Sunk":
		fallback_color = Color("#6c7780")
	draw_colored_polygon(_ellipse_points(collision_half_extents + Vector2(12.0, 12.0), heading), Color(0.02, 0.08, 0.12, 0.28))
	_draw_unit_art(fallback_color)
	draw_polyline(_ellipse_points(collision_half_extents, heading, true), Color(0.86, 0.97, 1.0, 0.58), 1.5, true)
	var heading_vector := Vector2.RIGHT.rotated(heading)
	draw_line(Vector2.ZERO, heading_vector * (collision_half_extents.x + 34.0), Color(1.0, 1.0, 1.0, 0.75), 2.5)
	if selected:
		_draw_ui_icon("ui_marker_selected", Vector2.ZERO, 0.85)
		draw_polyline(_ellipse_points(collision_half_extents + Vector2(19.0, 19.0), heading, true), Color("#f8ef9a"), 3.0, true)
	if focused:
		_draw_ui_icon("ui_marker_target", Vector2.ZERO, 0.9)
		draw_polyline(_ellipse_points(collision_half_extents + Vector2(25.0, 25.0), heading, true), Color("#ffb35c"), 3.0, true)
	if bool(unit.get("is_flagship", false)):
		_draw_ui_icon("ui_marker_flagship", Vector2(0.0, -radius - 34.0), 0.42)
	_draw_health_bar(radius, friendly)


func _draw_unit_art(fallback_color: Color) -> void:
	var heading := float(unit.get("heading", 0.0))
	var tint := Color.WHITE
	if str(unit.get("life_state", "Alive")) == "Sunk":
		tint = Color(0.5, 0.58, 0.62, 0.65)
	if rig_texture != null:
		_draw_texture_centered(rig_texture, heading + rig_heading_offset, rig_art_scale, tint)
	var frame_texture := _texture(animation.current_frame_path())
	if frame_texture != null:
		_draw_texture_centered(frame_texture, heading, body_art_scale, tint)
	elif body_texture != null:
		_draw_texture_centered(body_texture, heading, body_art_scale, tint)
	elif rig_texture == null:
		draw_colored_polygon(_ellipse_points(CollisionGeometryService.half_extents(unit), heading), fallback_color)


func _draw_health_bar(radius: float, friendly: bool) -> void:
	var hp_ratio := float(unit.get("current_hp", 0.0)) / maxf(1.0, float(unit.get("max_hp", 1.0)))
	var bar_width := maxf(68.0, radius * 3.2)
	draw_rect(Rect2(Vector2(-bar_width * 0.5, -radius - 28.0), Vector2(bar_width, 7.0)), Color("#202931"), true)
	draw_rect(Rect2(Vector2(-bar_width * 0.5, -radius - 28.0), Vector2(bar_width * hp_ratio, 7.0)), Color("#70db84") if friendly else Color("#ff9a8c"), true)
	var label := ("[旗舰] " if bool(unit.get("is_flagship", false)) else "") + str(unit.get("display_name", unit_id))
	draw_string(ThemeDB.fallback_font, Vector2(-72.0, radius + 36.0), label, HORIZONTAL_ALIGNMENT_CENTER, 144.0, 18, Color.WHITE)


func _draw_ui_icon(icon_name: String, offset: Vector2, scale_value: float) -> void:
	var texture := _texture(DataRegistry.assets.ui_asset_path(icon_name, "2x"))
	if texture == null:
		texture = _texture(DataRegistry.assets.ui_asset_path("ui.marker.%s" % icon_name.trim_prefix("ui_marker_"), "2x"))
	if texture == null:
		return
	draw_set_transform(offset, 0.0, Vector2(scale_value, scale_value))
	draw_texture(texture, -texture.get_size() * 0.5, Color.WHITE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_texture_centered(texture: Texture2D, rotation_value: float, scale_value: float, tint: Color) -> void:
	draw_set_transform(Vector2.ZERO, rotation_value, Vector2(scale_value, scale_value))
	draw_texture(texture, -texture.get_size() * 0.5, tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _bind_point_to_local(point: Dictionary) -> Vector2:
	var asset_name := str(point.get("asset_name", ""))
	var use_rig := asset_name.contains("_rig_") or asset_name.contains("rig_base")
	var base_texture := rig_texture if use_rig and rig_texture != null else body_texture
	if base_texture == null:
		base_texture = rig_texture
	if base_texture == null:
		return Vector2.ZERO
	var pixel := Vector2(float(point.get("x", base_texture.get_width() * 0.5)), float(point.get("y", base_texture.get_height() * 0.5)))
	var scale_value := rig_art_scale if use_rig else body_art_scale
	return (pixel - base_texture.get_size() * 0.5) * scale_value


func _load_static_textures() -> void:
	body_texture = _texture(DataRegistry.assets.battle_asset_path(character_id, "body_r"))
	var rig_path := DataRegistry.assets.battle_asset_path(character_id, "rig_base")
	rig_texture = _texture(rig_path)
	rig_heading_offset = deg_to_rad(DataRegistry.assets.heading_offset_degrees(character_id, rig_path.get_file()))


func _unit_art_scales() -> Dictionary:
	var radius := float(unit.get("collision_radius", 22.0))
	var collision_half_extents := CollisionGeometryService.half_extents(unit)
	var body_scale := DEFAULT_UNIT_SCALE
	var rig_scale := DEFAULT_UNIT_SCALE
	if body_texture != null:
		var body_target_width := clampf(radius * BODY_RADIUS_WIDTH_FACTOR, BODY_TARGET_MIN_WIDTH, BODY_TARGET_MAX_WIDTH)
		body_scale = body_target_width / maxf(1.0, float(body_texture.get_width()))
	if rig_texture != null:
		var rig_target_width := collision_half_extents.x * 2.0
		rig_scale = rig_target_width / maxf(1.0, float(rig_texture.get_width()))
	else:
		rig_scale = body_scale
	return {"body": body_scale, "rig": rig_scale}


func _ellipse_points(extents: Vector2, heading: float, close: bool = false) -> PackedVector2Array:
	var points := PackedVector2Array()
	var segment_count := 64
	for index in range(segment_count + (1 if close else 0)):
		var angle := TAU * float(index % segment_count) / float(segment_count)
		points.append(Vector2(cos(angle) * extents.x, sin(angle) * extents.y).rotated(heading))
	return points


func _texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if texture_cache.has(path):
		return texture_cache[path]
	var resource := load(path)
	texture_cache[path] = resource if resource is Texture2D else null
	return texture_cache[path]
