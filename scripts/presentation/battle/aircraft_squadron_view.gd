extends Node2D
const Payload = preload("res://scripts/presentation/battle/aviation_payload_view.gd")
var aircraft_kind := "bomber"
var texture: Texture2D
var payload: Node2D
var sample := {}
var clock := 0.0
var symbol_only := false
var selected := false
var screen_width := 36.0
var flight_from := Vector2.ZERO
var flight_to := Vector2.ZERO
var interpolation := 1.0
var interpolation_seconds := 0.1

func configure(visual: Dictionary, payload_visual: Dictionary = {}) -> void:
	var path := str(visual.get("sprite", ""))
	texture = load(path) if not path.is_empty() and ResourceLoader.exists(path) else null
	screen_width = float(visual.get("screen_canvas_width", 36.0))
	if payload == null:
		payload = Payload.new()
		payload.top_level = true
		payload.z_index = 23
		add_child(payload)
	payload.configure(payload_visual)
	sample.clear()
	set_process(true)
	modulate = Color.WHITE
	visible = true

func update_wave(wave: Dictionary, now: float, low_detail: bool, is_selected: bool) -> void:
	var previous_clock := clock
	var previous_phase := str(sample.get("phase", ""))
	var rebuilding := sample.is_empty()
	sample = wave
	clock = now
	selected = is_selected
	symbol_only = low_detail
	var destination: Vector2 = wave.get("position", Vector2.ZERO)
	if rebuilding or previous_phase != "Flying" or wave.get("phase", "") != "Flying":
		position = destination
		flight_to = destination
		interpolation = 1.0
	elif now > previous_clock:
		flight_from = position
		flight_to = destination
		interpolation = 0.0
		interpolation_seconds = clampf(now - previous_clock, 0.001, 0.1)
	var heading := float(wave.get("heading", 0.0))
	var end := float(wave.get("end_progress", 0.0))
	if wave.get("phase", "") == "Completed": position += Vector2.RIGHT.rotated(heading) * 65.0 * end
	modulate.a = 1.0 - end
	visible = wave.get("phase", "") not in ["Scheduled", "Cancelled"]
	var remaining := float(wave.get("remaining", 100))
	var bomb: bool = wave.get("aircraft_kind", "bomber") in ["bomber", "asw"] and wave.get("phase", "") == "Flying"
	payload.global_position = wave.get("target_position", position)
	payload.update_payload(1.0 - remaining / 0.45 if bomb and remaining <= 0.45 else -1.0)
	queue_redraw()

func reset() -> void:
	sample.clear()
	set_process(false)
	texture = null
	visible = false
	if payload: payload.update_payload(-1)

func _process(delta: float) -> void:
	if interpolation < 1.0:
		interpolation = minf(1.0, interpolation + delta / interpolation_seconds)
		position = flight_from.lerp(flight_to, interpolation)

func _draw() -> void:
	if sample.is_empty(): return
	var zoom := maxf(0.1, get_global_transform_with_canvas().get_scale().x)
	var heading := float(sample.get("heading", 0.0))
	var friendly: bool = sample.get("faction_id", "") == "player"
	var color := Color("#a5f3ef") if friendly else Color("#ffac83")
	var orbit: bool = sample.get("phase", "") == "Patrolling"
	if orbit and selected: draw_arc(Vector2.ZERO, float(sample.get("radius", 60)), 0, TAU, 64, Color(color, 0.3), 1 / zoom)
	var size := screen_width / zoom
	var spawn := clampf(float(sample.get("progress", 1)) * 10.0, 0.35, 1.0)
	var count := 1 if symbol_only or orbit else 3
	for index in range(count):
		var offset := Vector2(-absf(index - 1) * size * 0.55, (index - 1) * size * 0.72).rotated(heading) if count > 1 else Vector2.ZERO
		if orbit: offset = Vector2.RIGHT.rotated(clock * 0.6) * minf(48, float(sample.get("radius", 60)) * 0.25)
		draw_set_transform(offset + Vector2(5, 7) / zoom, heading, Vector2.ONE * spawn)
		if texture and not symbol_only: draw_texture_rect(texture, Rect2(-Vector2.ONE * size / 2, Vector2.ONE * size), false, Color(0.015, 0.06, 0.10, 0.30))
		draw_set_transform(offset, heading, Vector2.ONE * spawn)
		if texture and not symbol_only: draw_texture_rect(texture, Rect2(-Vector2.ONE * size / 2, Vector2.ONE * size), false)
		else:
			draw_colored_polygon(PackedVector2Array([Vector2(12, 0) / zoom, Vector2(-8, -7) / zoom, Vector2(-3, 0) / zoom, Vector2(-8, 7) / zoom]), color)
		draw_line(Vector2(-size * 0.35, -size * 0.15), Vector2(-size * 0.65, -size * 0.15), Color(color, 0.35), 1 / zoom)
		draw_line(Vector2(-size * 0.35, size * 0.15), Vector2(-size * 0.65, size * 0.15), Color(color, 0.35), 1 / zoom)
	draw_set_transform(Vector2.ZERO)
	var marker := Vector2(0, -size * 0.6)
	if friendly: draw_arc(marker, 3 / zoom, 0, TAU, 12, color, 1.4 / zoom)
	else: draw_rect(Rect2(marker - Vector2.ONE * 3 / zoom, Vector2.ONE * 6 / zoom), color, false, 1.4 / zoom)
	if sample.has("current_hp"):
		var ratio := float(sample.current_hp) / maxf(1, float(sample.get("max_hp", 1)))
		draw_line(Vector2(-12, 20) / zoom, Vector2(12, 20) / zoom, Color(0, 0, 0, 0.6), 3 / zoom)
		draw_line(Vector2(-12, 20) / zoom, Vector2(-12 + 24 * ratio, 20) / zoom, color, 2 / zoom)
