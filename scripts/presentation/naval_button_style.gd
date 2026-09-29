extends StyleBox

var fill := Color("#173c4b")
var edge := Color("#c8b580")
var hero := false
var focus_only := false

func _draw(canvas: RID, rect: Rect2) -> void:
	var r := rect.grow(-1)
	var cut := 12.0 if hero else 7.0
	var points := PackedVector2Array([
		r.position + Vector2(cut, 0), Vector2(r.end.x, r.position.y),
		Vector2(r.end.x, r.end.y - cut), Vector2(r.end.x - cut, r.end.y),
		Vector2(r.position.x, r.end.y), r.position + Vector2(0, cut)])
	if not focus_only: RenderingServer.canvas_item_add_polygon(canvas, points, PackedColorArray([fill]))
	for i in range(points.size()):
		RenderingServer.canvas_item_add_line(canvas, points[i], points[(i + 1) % points.size()], edge, 2.0 if focus_only else 1.0, true)
	if focus_only: return
	var inner := Color(edge, 0.32)
	RenderingServer.canvas_item_add_line(canvas, r.position + Vector2(20, 5), Vector2(r.end.x - 8, r.position.y + 5), inner, 1.0, true)
	RenderingServer.canvas_item_add_line(canvas, Vector2(r.position.x + 8, r.end.y - 5), r.end - Vector2(20, 5), inner, 1.0, true)
	if hero:
		var c := r.position + Vector2(35, r.size.y * 0.5)
		var diamond := PackedVector2Array([c + Vector2(0,-14), c + Vector2(9,0), c + Vector2(0,14), c + Vector2(-9,0)])
		for i in range(4): RenderingServer.canvas_item_add_line(canvas, diamond[i], diamond[(i+1)%4], edge, 1.0, true)
		RenderingServer.canvas_item_add_line(canvas, c + Vector2(-15,0), c + Vector2(15,0), inner, 1.0, true)
		RenderingServer.canvas_item_add_line(canvas, c + Vector2(0,-19), c + Vector2(0,19), edge, 1.0, true)
		for i in range(3):
			var x := r.end.x - 35 + i * 6
			RenderingServer.canvas_item_add_line(canvas, Vector2(x, c.y+6), Vector2(x+4, c.y-6), Color(edge, 0.5), 2.0, true)
