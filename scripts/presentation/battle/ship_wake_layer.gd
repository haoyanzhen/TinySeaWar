extends Node2D
## Local water displacement ribbons. Never consumes hidden or remembered contacts.
@export var lifetime := 2.8
@export var max_samples := 40
@export var width_pixels := 14.0
@export var opacity := 0.42
var trails: Dictionary = {}
var last_positions: Dictionary = {}
var clock := 0.0
var zoom := 1.0

func clear() -> void:
	trails.clear()
	last_positions.clear()
	clock = 0.0
	queue_redraw()

func sync_snapshot(snapshot: Dictionary, camera_zoom: float) -> void:
	zoom = maxf(camera_zoom, 0.01)
	var now := float(snapshot.get("elapsed_time", 0.0))
	if now < clock: clear()
	clock = now
	var visible_units: Dictionary = snapshot.get("units", {})
	for id in last_positions.keys():
		if not visible_units.has(id):
			last_positions.erase(id)
			trails.erase(id)
	for id in visible_units:
		var unit: Dictionary = visible_units[id]
		if str(unit.get("life_state", "Alive")) != "Alive" or (str(unit.get("ship_class", "")) == "Submarine" and str(unit.get("depth_state", "Surface")) != "Surface"):
			trails.erase(id)
			last_positions.erase(id)
			continue
		var p: Vector2 = unit.get("position", Vector2.ZERO)
		var points: Array = trails.get(id, [])
		while not points.is_empty() and clock - float(points[0].time) > lifetime:
			points.pop_front()
		if last_positions.has(id):
			var previous: Dictionary = last_positions[id]
			var distance := p.distance_to(previous.position)
			if distance > 300.0 or clock - float(previous.time) > 0.5:
				points.clear()
			elif clock > float(previous.time) and distance > 0.7:
				var direction := (p - Vector2(previous.position)).normalized()
				points.append({"position": p - direction * 22.0 / zoom, "time": clock, "normal": direction.orthogonal()})
				while points.size() > max_samples: points.pop_front()
		if not last_positions.has(id) or clock > float(last_positions[id].time):
			last_positions[id] = {"position": p, "time": clock}
		trails[id] = points
	queue_redraw()

func _draw() -> void:
	for points in trails.values():
		for i in range(1, points.size()):
			var a: Dictionary = points[i-1]
			var b: Dictionary = points[i]
			var fade_a := clampf(1.0 - (clock - float(a.time)) / lifetime, 0.0, 1.0)
			var fade_b := clampf(1.0 - (clock - float(b.time)) / lifetime, 0.0, 1.0)
			var wa: Vector2 = a.normal * width_pixels / zoom * (1.0 + (1.0 - fade_a) * 0.8)
			var wb: Vector2 = b.normal * width_pixels / zoom * (1.0 + (1.0 - fade_b) * 0.8)
			var ca := Color(0.38, 0.72, 0.78, opacity * fade_a * minf(float(i-1) / 4.0, 1.0))
			var cb := Color(0.38, 0.72, 0.78, opacity * fade_b * minf(float(i) / 4.0, 1.0))
			var clear_a := Color(ca, 0.0)
			var clear_b := Color(cb, 0.0)
			# Feather across the width instead of drawing a hard rectangular strip.
			for side in [-1.0, 1.0]:
				draw_primitive(PackedVector2Array([a.position, b.position, b.position+wb*side]), PackedColorArray([ca,cb,clear_b]), PackedVector2Array())
				draw_primitive(PackedVector2Array([a.position, b.position+wb*side, a.position+wa*side]), PackedColorArray([ca,clear_b,clear_a]), PackedVector2Array())
				draw_line(a.position + wa * side * 0.55, b.position + wb * side * 0.55, Color(0.53,0.82,0.86, ca.a * fade_b * 0.6), 2.0 / zoom, true)
