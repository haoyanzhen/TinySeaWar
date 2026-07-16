extends Node2D

var start_position := Vector2.ZERO
var end_position := Vector2.ZERO
var heading := 0.0
var duration := 0.35
var elapsed := 0.0
var texture: Texture2D
var shell_scale := 0.35
var trail_length := 12.0
var trail_width := 1.5
var trail_color := Color.WHITE
var trail_fade_duration := 0.18
var trail_outer_width_multiplier := 2.0
var trail_outer_alpha := 0.14
var head_glow_radius := 2.0
var afterimage_seconds := 0.0
var afterimage_samples := 0
var trail_segment_count := 6
var arrived := false
var arrival_elapsed := 0.0
var history_sample_elapsed := 0.0
var history_points: Array[Dictionary] = []


func configure(
	origin: Vector2,
	destination: Vector2,
	visual: Dictionary,
	color_value: Color,
	trail_profile: Dictionary,
	duration_seconds: float
) -> void:
	start_position = origin
	end_position = destination
	position = start_position
	var delta := end_position - start_position
	heading = delta.angle() if delta.length_squared() > 0.01 else 0.0
	texture = load(str(visual.get("sprite", ""))) as Texture2D
	shell_scale = float(visual.get("scale", 0.35))
	trail_color = color_value
	trail_length = maxf(1.0, float(trail_profile.get("length", 12.0)))
	trail_width = maxf(0.5, float(trail_profile.get("width", 1.5)))
	duration = maxf(0.06, duration_seconds)
	trail_fade_duration = maxf(0.03, float(trail_profile.get("fade_duration", 0.18)))
	trail_outer_width_multiplier = maxf(1.0, float(trail_profile.get("outer_width_multiplier", 2.0)))
	trail_outer_alpha = clampf(float(trail_profile.get("outer_alpha", 0.14)), 0.0, 1.0)
	head_glow_radius = maxf(0.0, float(trail_profile.get("head_glow_radius", 2.0)))
	afterimage_seconds = maxf(0.0, float(trail_profile.get("afterimage_seconds", 0.0)))
	afterimage_samples = clampi(int(trail_profile.get("afterimage_samples", 0)), 0, 8)
	trail_segment_count = clampi(int(trail_profile.get("segment_count", 6)), 2, 12)
	elapsed = 0.0
	arrived = false
	arrival_elapsed = 0.0
	history_sample_elapsed = 0.0
	history_points.clear()
	_record_history_point(true)
	queue_redraw()


func _process(delta: float) -> void:
	_age_history(delta)
	if arrived:
		arrival_elapsed += delta
		if arrival_elapsed >= trail_fade_duration:
			queue_free()
			return
		queue_redraw()
		return
	elapsed += delta
	var progress := clampf(elapsed / duration, 0.0, 1.0)
	position = start_position.lerp(end_position, progress)
	_record_history_point(false, delta)
	if elapsed >= duration:
		position = end_position
		arrived = true
		arrival_elapsed = 0.0
		_record_history_point(true)
	queue_redraw()


func _draw() -> void:
	var alpha := clampf(1.0 - arrival_elapsed / trail_fade_duration, 0.0, 1.0) if arrived else 1.0
	var screen_compensation := _screen_space_compensation()
	var direction := Vector2.RIGHT.rotated(heading + PI)
	var compensated_length := trail_length * screen_compensation
	var core_width := maxf(0.45, trail_width * 0.55) * screen_compensation
	_draw_afterimages(alpha, screen_compensation)
	for index in range(trail_segment_count):
		var t0 := float(index) / float(trail_segment_count)
		var t1 := float(index + 1) / float(trail_segment_count)
		var p0 := direction * compensated_length * (1.0 - t0)
		var p1 := direction * compensated_length * (1.0 - t1)
		var segment_alpha := alpha * pow(t1, 1.55)
		var segment_width := core_width * lerpf(0.28, 1.0, t1)
		draw_line(p0, p1, Color(trail_color.r, trail_color.g, trail_color.b, trail_outer_alpha * segment_alpha), segment_width * trail_outer_width_multiplier, true)
		draw_line(p0, p1, Color(trail_color.r, trail_color.g, trail_color.b, 0.70 * segment_alpha), segment_width)
	if not arrived and head_glow_radius > 0.0:
		var glow_radius := head_glow_radius * screen_compensation
		draw_circle(Vector2.ZERO, glow_radius * 1.8, Color(trail_color.r, trail_color.g, trail_color.b, trail_outer_alpha * 0.45))
		draw_circle(Vector2.ZERO, glow_radius, Color(trail_color.r, trail_color.g, trail_color.b, 0.28))
	if arrived:
		return
	if texture == null:
		draw_circle(Vector2.ZERO, maxf(2.0, trail_width * 1.6) * screen_compensation, Color(trail_color.r, trail_color.g, trail_color.b, 0.9 * alpha))
		return
	draw_set_transform(Vector2.ZERO, heading, Vector2(shell_scale, shell_scale))
	draw_texture(texture, -texture.get_size() * 0.5, Color(1.0, 1.0, 1.0, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _screen_space_compensation() -> float:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return 1.0
	return clampf(1.0 / maxf(camera.zoom.x, 0.01), 0.85, 1.6)


func _age_history(delta: float) -> void:
	if history_points.is_empty():
		return
	for point in history_points:
		point["age"] = float(point.get("age", 0.0)) + delta
	if afterimage_seconds <= 0.0:
		history_points.clear()
		return
	while not history_points.is_empty() and float(history_points[0].get("age", 0.0)) > afterimage_seconds:
		history_points.pop_front()


func _record_history_point(force: bool, delta: float = 0.0) -> void:
	if afterimage_seconds <= 0.0 or afterimage_samples <= 0:
		return
	history_sample_elapsed += delta
	var interval := afterimage_seconds / float(afterimage_samples)
	if not force and history_sample_elapsed < interval:
		return
	history_sample_elapsed = 0.0
	history_points.append({"position": position, "age": 0.0})
	while history_points.size() > afterimage_samples + 1:
		history_points.pop_front()


func _draw_afterimages(alpha: float, screen_compensation: float) -> void:
	if afterimage_seconds <= 0.0 or history_points.size() < 2:
		return
	var previous := history_points[0].get("position", position) as Vector2
	for index in range(1, history_points.size()):
		var point: Dictionary = history_points[index]
		var current := point.get("position", position) as Vector2
		var age_alpha := clampf(1.0 - float(point.get("age", 0.0)) / afterimage_seconds, 0.0, 1.0) * alpha
		var from_local := previous - position
		var to_local := current - position
		draw_line(from_local, to_local, Color(trail_color.r, trail_color.g, trail_color.b, trail_outer_alpha * 0.45 * age_alpha), trail_width * trail_outer_width_multiplier * screen_compensation, true)
		draw_line(from_local, to_local, Color(trail_color.r, trail_color.g, trail_color.b, 0.24 * age_alpha), maxf(0.5, trail_width * 0.35) * screen_compensation, true)
		previous = current
