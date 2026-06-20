extends Node2D

var projectile_id := ""
var texture: Texture2D
var visual := {}
var heading := 0.0


func configure(projectile: Dictionary, new_visual: Dictionary) -> void:
	projectile_id = str(projectile.get("entity_id", ""))
	visual = new_visual.duplicate(true)
	texture = load(str(visual.get("sprite", ""))) as Texture2D
	update_projectile(projectile)


func update_projectile(projectile: Dictionary) -> void:
	position = projectile.get("position", Vector2.ZERO)
	heading = float(projectile.get("heading", 0.0))
	queue_redraw()


func _draw() -> void:
	var color := Color(str(visual.get("trail_color", "#ffe37a")))
	var trail_length := float(visual.get("trail_length", 24.0))
	draw_line(Vector2.RIGHT.rotated(heading + PI) * trail_length, Vector2.ZERO, Color(color.r, color.g, color.b, 0.58), 3.0)
	if texture == null:
		draw_circle(Vector2.ZERO, 5.0, Color(color.r, color.g, color.b, 0.9))
		return
	var scale_value := float(visual.get("scale", 0.3))
	draw_set_transform(Vector2.ZERO, heading, Vector2(scale_value, scale_value))
	draw_texture(texture, -texture.get_size() * 0.5, Color.WHITE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
