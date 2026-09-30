extends RefCounted

# One bounded allocation per order. Paths remain independent Broker requests.
const MAX_CANDIDATES := 81
const ENDPOINT_MARGIN := 48.0

static func allocate(members: Array, center: Vector2, can_occupy: Callable) -> Dictionary:
	if members.is_empty(): return {}
	var origin := Vector2.ZERO
	var spacing := 120.0
	for member in members:
		origin += member.position
		spacing = maxf(spacing, float(member.extent) * 2.0 + ENDPOINT_MARGIN)
	origin /= members.size()
	var forward := (center - origin).normalized()
	if forward == Vector2.ZERO: forward = Vector2.RIGHT
	var side := forward.orthogonal()
	var columns := mini(3, members.size())
	var rows := ceili(float(members.size()) / columns)
	var slots: Array = []
	for index in range(members.size()):
		var row := index / columns
		var row_count := mini(columns, members.size() - row * columns)
		slots.append(side * (float(index % columns) - float(row_count - 1) * 0.5) * spacing - forward * (float(row) - float(rows - 1) * 0.5) * spacing)
	# Assign nearest translated positions first, with deterministic ties. This
	# retains spatial order instead of making entity-ID order cross the fleet.
	var pairs: Array = []
	for member in members:
		for index in range(slots.size()):
			pairs.append({"id":member.id, "slot":index, "cost":((member.position as Vector2) - origin).distance_squared_to(slots[index])})
	pairs.sort_custom(func(a, b):
		if not is_equal_approx(a.cost, b.cost): return a.cost < b.cost
		return str(a.id) < str(b.id) if a.id != b.id else a.slot < b.slot)
	var assigned := {}
	var used := {}
	for pair in pairs:
		if assigned.has(pair.id) or used.has(pair.slot): continue
		assigned[pair.id] = slots[pair.slot]
		used[pair.slot] = true
	var ordered := members.duplicate()
	ordered.sort_custom(func(a, b): return str(a.id) < str(b.id))
	# Remove improving pair swaps after greedy matching. For <=11 members this
	# is cheap and avoids unnecessary crossing when the fleet turns around.
	for _pass in range(ordered.size()):
		var improved := false
		for first in range(ordered.size()):
			for second in range(first + 1, ordered.size()):
				var a: Dictionary = ordered[first]
				var b: Dictionary = ordered[second]
				var pa: Vector2 = a.position - origin
				var pb: Vector2 = b.position - origin
				var old_cost := pa.distance_squared_to(assigned[a.id]) + pb.distance_squared_to(assigned[b.id])
				var new_cost := pa.distance_squared_to(assigned[b.id]) + pb.distance_squared_to(assigned[a.id])
				if new_cost + 0.01 >= old_cost: continue
				var temporary: Vector2 = assigned[a.id]
				assigned[a.id] = assigned[b.id]
				assigned[b.id] = temporary
				improved = true
		if not improved: break
	var result := {}
	var reserved: Array = []
	for member in ordered:
		var desired: Vector2 = center + assigned[member.id]
		var candidates: Array = [desired]
		# Search behind and alongside the destination before expanding ahead.
		for row in range(9):
			for column in range(9):
				var lateral := float((column + 1) / 2) * (-1.0 if column % 2 == 1 else 1.0)
				candidates.append(desired - forward * spacing * row + side * spacing * lateral)
		for index in range(mini(MAX_CANDIDATES, candidates.size())):
			var candidate: Vector2 = candidates[index]
			if candidate.distance_to(desired) > spacing * 3.0: continue
			var clear := true
			for previous in reserved:
				if candidate.distance_to(previous.position) < float(member.extent) + float(previous.extent) + ENDPOINT_MARGIN:
					clear = false
					break
			if not clear or not bool(can_occupy.call(member.id, candidate)): continue
			result[member.id] = candidate
			reserved.append({"position":candidate, "extent":member.extent})
			break
	return result

static func slot_offset(formation: String, index: int, count: int, spacing: float) -> Vector2:
	if index == 0: return Vector2.ZERO
	match formation:
		"Column": return Vector2(-spacing * index, 0.0)
		"LineAbreast": return Vector2(0.0, spacing * float((index + 1) / 2) * (-1.0 if index % 2 == 1 else 1.0))
		"Screen", "Dispersed": return Vector2.RIGHT.rotated(PI + (float(index - 1) - float(count - 2) * 0.5) * 1.1) * spacing * (1.5 if formation == "Dispersed" else 1.0)
		_: return Vector2(-spacing, spacing * (-1.0 if index % 2 == 1 else 1.0)) * float((index + 1) / 2)
