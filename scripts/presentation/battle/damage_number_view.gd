extends Node2D

var target_unit_id := ""
var text_value := ""
var amount := 0
var hit_count := 1
var priority := 1
var duration := 0.55
var elapsed := 0.0
var font_size := 20
var rise_distance := 32.0
var side_distance := 0.0
var hold_seconds := 0.0
var fill_color := Color.WHITE
var inner_outline_color := Color(1.0, 1.0, 1.0, 0.0)
var outer_outline_color := Color(0.02, 0.08, 0.12, 0.92)
var outline_size := 3
var reduce_motion := false
var numeric := true


func configure(entry: Dictionary) -> void:
	target_unit_id = str(entry.get("target_unit_id", ""))
	amount = int(round(float(entry.get("amount", 0.0))))
	hit_count = int(entry.get("hit_count", 1))
	numeric = bool(entry.get("numeric", true))
	text_value = _format_text(str(entry.get("text", "")))
	priority = int(entry.get("priority", 1))
	duration = clampf(float(entry.get("duration", 0.55)), 0.2, 0.9)
	font_size = int(entry.get("font_size", 20))
	rise_distance = float(entry.get("rise_distance", 32.0))
	side_distance = float(entry.get("side_distance", 0.0))
	hold_seconds = float(entry.get("hold_seconds", 0.0))
	fill_color = entry.get("fill_color", fill_color)
	inner_outline_color = entry.get("inner_outline_color", inner_outline_color)
	outer_outline_color = entry.get("outer_outline_color", outer_outline_color)
	outline_size = int(entry.get("outline_size", 3))
	reduce_motion = bool(entry.get("reduce_motion", false))
	queue_redraw()


func can_absorb(entry: Dictionary) -> bool:
	return numeric and bool(entry.get("numeric", true)) and target_unit_id == str(entry.get("target_unit_id", "")) and elapsed <= 0.25


func absorb(entry: Dictionary) -> void:
	amount += int(round(float(entry.get("amount", 0.0))))
	hit_count += int(entry.get("hit_count", 1))
	text_value = _format_text("")
	priority = maxi(priority, int(entry.get("priority", priority)))
	elapsed = minf(elapsed, 0.12)
	duration = maxf(duration, float(entry.get("duration", duration)))
	queue_redraw()


func _format_text(fallback_text: String) -> String:
	if not numeric:
		return fallback_text
	if hit_count > 1:
		return "%d x%d" % [amount, hit_count]
	return str(amount)


func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= duration:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	if text_value.is_empty():
		return
	var progress := clampf(elapsed / duration, 0.0, 1.0)
	var fade_start := 0.76
	var alpha := 1.0 if progress < fade_start else clampf(1.0 - (progress - fade_start) / maxf(0.01, 1.0 - fade_start), 0.0, 1.0)
	var motion_progress := 0.0 if elapsed < hold_seconds else clampf((elapsed - hold_seconds) / maxf(0.01, duration - hold_seconds), 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - motion_progress, 2.0)
	var side := 0.0 if reduce_motion else side_distance * sin(eased * PI * 0.65)
	var offset := Vector2(side, -rise_distance * eased * (0.35 if reduce_motion else 1.0))
	var scale_value := 1.0
	if not reduce_motion:
		if elapsed < 0.12:
			scale_value = lerpf(0.90, 1.10, elapsed / 0.12)
		else:
			scale_value = lerpf(1.10, 0.98, clampf((elapsed - 0.12) / maxf(0.01, duration - 0.12), 0.0, 1.0))
	var font := ThemeDB.fallback_font
	var estimated_width := maxf(10.0, float(text_value.length()) * float(font_size) * 0.62)
	var text_position := Vector2(-estimated_width * 0.5, float(font_size) * 0.34)
	var fill := Color(fill_color.r, fill_color.g, fill_color.b, fill_color.a * alpha)
	var inner := Color(inner_outline_color.r, inner_outline_color.g, inner_outline_color.b, inner_outline_color.a * alpha)
	var outer := Color(outer_outline_color.r, outer_outline_color.g, outer_outline_color.b, outer_outline_color.a * alpha)
	draw_set_transform(offset, 0.0, Vector2(scale_value, scale_value))
	draw_string_outline(font, text_position, text_value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, outline_size + 2, outer)
	if inner.a > 0.0:
		draw_string_outline(font, text_position, text_value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, maxi(1, outline_size - 1), inner)
	draw_string(font, text_position, text_value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, fill)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
