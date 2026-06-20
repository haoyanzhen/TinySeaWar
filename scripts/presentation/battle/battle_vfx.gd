extends Node2D

var texture: Texture2D
var duration := 0.35
var elapsed := 0.0
var base_scale := 1.0
var fade_out := true
var tint := Color.WHITE


func configure(texture_path: String, profile: Dictionary, new_rotation := 0.0, new_tint := Color.WHITE) -> void:
	texture = load(texture_path) as Texture2D
	duration = maxf(0.05, float(profile.get("duration", 0.35)))
	base_scale = float(profile.get("scale", 1.0))
	fade_out = bool(profile.get("fade_out", true))
	rotation = new_rotation
	tint = new_tint
	queue_redraw()


func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= duration:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	if texture == null:
		return
	var alpha := 1.0
	if fade_out:
		alpha = clampf(1.0 - elapsed / duration, 0.0, 1.0)
	var pulse := 1.0 + 0.18 * sin((elapsed / duration) * PI)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(base_scale * pulse, base_scale * pulse))
	draw_texture(texture, -texture.get_size() * 0.5, Color(tint.r, tint.g, tint.b, tint.a * alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
