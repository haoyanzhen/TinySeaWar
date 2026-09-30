extends RefCounted

const TRAIL_LIMIT := 512
const TRAIL_STEP := 6.0

static func record(trail: Array, position: Vector2, heading: float) -> void:
	if trail.is_empty():
		trail.append({"position":position, "heading":heading, "distance":0.0})
		return
	var previous: Dictionary = trail[-1]
	var travelled := position.distance_to(previous.position)
	if travelled < TRAIL_STEP and absf(angle_difference(float(previous.heading), heading)) < 0.1: return
	if travelled < 0.01: return
	trail.append({"position":position, "heading":heading, "distance":float(previous.distance) + travelled})
	if trail.size() > TRAIL_LIMIT: trail.pop_front()

static func point_at(trail: Array, distance: float) -> Vector2:
	if distance <= float(trail[0].distance): return trail[0].position
	var low := 0
	var high := trail.size() - 1
	while low + 1 < high:
		var middle := (low + high) / 2
		if float(trail[middle].distance) < distance: low = middle
		else: high = middle
	var a: Dictionary = trail[low]
	var b: Dictionary = trail[high]
	return (a.position as Vector2).lerp(b.position, clampf((distance - float(a.distance)) / maxf(0.001, float(b.distance) - float(a.distance)), 0.0, 1.0))

static func follow(trail: Array, position: Vector2, spacing: float, cursor: float, speed: float) -> Dictionary:
	if trail.is_empty(): return {}
	if cursor > float(trail[-1].distance) + 0.001: cursor = 0.0
	var stop := maxf(float(trail[0].distance), float(trail[-1].distance) - spacing)
	if float(trail[-1].distance) - float(trail[0].distance) < spacing:
		return {"goal":position, "cursor":cursor, "waiting":true, "next_goals":[], "stop_distance":stop}
	var nearest := maxf(float(trail[0].distance), cursor)
	var minimum := INF
	for index in range(trail.size() - 1):
		var a: Dictionary = trail[index]
		var b: Dictionary = trail[index + 1]
		if float(b.distance) < cursor: continue
		var projection := Geometry2D.get_closest_point_to_segment(position, a.position, b.position)
		var distance := position.distance_squared_to(projection)
		if distance >= minimum: continue
		minimum = distance
		nearest = maxf(cursor, float(a.distance) + (a.position as Vector2).distance_to(projection))
	if nearest >= stop - 16.0:
		return {"goal":position, "cursor":nearest, "waiting":true, "next_goals":[], "stop_distance":stop}
	var target_distance := minf(stop, nearest + maxf(180.0, speed * 6.0))
	var goal := point_at(trail, target_distance)
	var lookahead_goal := goal
	# Return the first corner before the lookahead. A follower must not aim
	# across the inside of a bend just because its predecessor is now beyond it.
	for index in range(1, trail.size() - 1):
		var sample: Dictionary = trail[index]
		if float(sample.distance) < nearest + 24.0 or float(sample.distance) >= target_distance: continue
		var incoming: Vector2 = sample.position - point_at(trail, maxf(nearest, float(sample.distance) - 36.0))
		var outgoing: Vector2 = point_at(trail, minf(target_distance, float(sample.distance) + 36.0)) - sample.position
		if incoming.length() > 1.0 and outgoing.length() > 1.0 and absf(incoming.angle_to(outgoing)) > 0.3:
			goal = sample.position
			target_distance = float(sample.distance)
			break
	return {"goal":goal, "lookahead_goal":lookahead_goal, "cursor":nearest, "waiting":nearest >= stop - 16.0 and position.distance_to(goal) < 24.0, "next_goals":[point_at(trail, minf(stop, target_distance + 100.0))], "stop_distance":stop}
