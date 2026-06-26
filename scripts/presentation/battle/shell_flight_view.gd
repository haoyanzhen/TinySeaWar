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


func configure(
	origin: Vector2,
	destination: Vector2,
	visual: Dictionary,
	color_value: Color,
	trail_length_px: float,
	trail_width_px: float,
	duration_seconds: float,
	trail_fade_seconds: float
) -> void:
	start_position = origin
	end_position = destination
	position = start_position
	var delta := end_position - start_position
	heading = delta.angle() if delta.length_squared() > 0.01 else 0.0
	texture = load(str(visual.get("sprite", ""))) as Texture2D
	shell_scale = float(visual.get("scale", 0.35))
	trail_color = color_value
	trail_length = maxf(1.0, trail_length_px)
	trail_width = maxf(0.5, trail_width_px)
	duration = maxf(0.06, duration_seconds)
	trail_fade_duration = clampf(trail_fade_seconds, 0.03, duration)
	elapsed = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	elapsed += delta
	var progress := clampf(elapsed / duration, 0.0, 1.0)
	position = start_position.lerp(end_position, progress)
	if elapsed >= duration:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var remaining := maxf(0.0, duration - elapsed)
	var alpha := clampf(remaining / trail_fade_duration, 0.0, 1.0) if remaining < trail_fade_duration else 1.0
	var direction := Vector2.RIGHT.rotated(heading + PI)
	var core_width := maxf(0.45, trail_width * 0.55)
	var segments := 8
	for index in range(segments):
		var t0 := float(index) / float(segments)
		var t1 := float(index + 1) / float(segments)
		var p0 := direction * trail_length * (1.0 - t0)
		var p1 := direction * trail_length * (1.0 - t1)
		var segment_alpha := alpha * pow(t1, 1.55)
		var segment_width := core_width * lerpf(0.28, 1.0, t1)
		draw_line(p0, p1, Color(trail_color.r, trail_color.g, trail_color.b, 0.14 * segment_alpha), segment_width * 2.0)
		draw_line(p0, p1, Color(trail_color.r, trail_color.g, trail_color.b, 0.70 * segment_alpha), segment_width)
	if texture == null:
		draw_circle(Vector2.ZERO, maxf(2.0, trail_width * 1.6), Color(trail_color.r, trail_color.g, trail_color.b, 0.9 * alpha))
		return
	draw_set_transform(Vector2.ZERO, heading, Vector2(shell_scale, shell_scale))
	draw_texture(texture, -texture.get_size() * 0.5, Color(1.0, 1.0, 1.0, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
