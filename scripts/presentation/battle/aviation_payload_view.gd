extends Node2D
## Independent visual payload, driven solely by the published flight clock.
var texture: Texture2D
var progress := -1.0
func configure(visual: Dictionary) -> void:
	var path := str(visual.get("sprite", ""))
	texture = load(path) if not path.is_empty() and ResourceLoader.exists(path) else null
func update_payload(value: float) -> void:
	progress = value
	visible = progress >= 0.0 and progress < 1.0
	queue_redraw()
func _draw() -> void:
	if not visible: return
	for index in range(2):
		var point := Vector2(-12 + index * 24, -34 * (1.0 - progress))
		if texture: draw_texture_rect(texture, Rect2(point - Vector2(5, 8), Vector2(10, 16)), false)
		else: draw_circle(point, 3, Color("#e7d9a4"))
