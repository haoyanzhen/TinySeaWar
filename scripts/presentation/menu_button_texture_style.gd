extends StyleBox

# Keep end caps and the central frame jewel proportional; stretch only plain spans.
var texture: Texture2D

func _draw(canvas: RID, rect: Rect2) -> void:
	if texture == null or rect.size.x <= 0 or rect.size.y <= 0:
		return
	var source := texture.get_size()
	var cap := 160.0
	var edge := minf(cap * rect.size.y / source.y, rect.size.x * 0.3)
	var middle_source := 48.0
	var middle := middle_source * edge / cap
	var span := (rect.size.x - edge * 2 - middle) * 0.5
	var source_span := (source.x - cap * 2 - middle_source) * 0.5
	texture.draw_rect_region(canvas, Rect2(rect.position, Vector2(edge, rect.size.y)), Rect2(0, 0, cap, source.y))
	texture.draw_rect_region(canvas, Rect2(rect.position + Vector2(edge, 0), Vector2(span, rect.size.y)), Rect2(cap, 0, source_span, source.y))
	texture.draw_rect_region(canvas, Rect2(rect.position + Vector2(edge + span, 0), Vector2(middle, rect.size.y)), Rect2(cap + source_span, 0, middle_source, source.y))
	texture.draw_rect_region(canvas, Rect2(rect.position + Vector2(edge + span + middle, 0), Vector2(span, rect.size.y)), Rect2(cap + source_span + middle_source, 0, source_span, source.y))
	texture.draw_rect_region(canvas, Rect2(rect.end.x - edge, rect.position.y, edge, rect.size.y), Rect2(source.x - cap, 0, cap, source.y))
