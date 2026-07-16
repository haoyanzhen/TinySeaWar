extends RefCounted

const DEFAULT_MAX_REQUESTS_PER_TICK := 1
const DEFAULT_TIME_BUDGET_USEC := 2000

var _queue: Array = []
var _sequence := 0
var max_requests_per_tick := DEFAULT_MAX_REQUESTS_PER_TICK
var time_budget_usec := DEFAULT_TIME_BUDGET_USEC


func clear() -> void:
	_queue.clear()
	_sequence = 0


func configure(request_budget: int = DEFAULT_MAX_REQUESTS_PER_TICK, usec_budget: int = DEFAULT_TIME_BUDGET_USEC) -> void:
	max_requests_per_tick = maxi(1, request_budget)
	time_budget_usec = maxi(100, usec_budget)


func submit(request: Dictionary) -> String:
	_sequence += 1
	var queued := request.duplicate(true)
	queued["request_id"] = str(request.get("request_id", "navigation.request.%d" % _sequence))
	queued["sequence"] = _sequence
	_queue.append(queued)
	return str(queued["request_id"])


func advance(route_planner, terrain_query, navigation_definition: Dictionary, terrain_context) -> Array:
	_queue.sort_custom(func(a, b):
		var priority_a := int(a.get("priority", 10))
		var priority_b := int(b.get("priority", 10))
		return priority_a < priority_b if priority_a != priority_b else int(a.get("sequence", 0)) < int(b.get("sequence", 0)))
	var results: Array = []
	var started_usec := Time.get_ticks_usec()
	while not _queue.is_empty() and results.size() < max_requests_per_tick:
		if not results.is_empty() and Time.get_ticks_usec() - started_usec >= time_budget_usec: break
		var request: Dictionary = _queue.pop_front()
		var result: Dictionary = route_planner.plan_path(
			terrain_query,
			navigation_definition,
			request.get("start", Vector2.ZERO),
			request.get("target", Vector2.ZERO),
			float(request.get("radius", 20.0)),
			request.get("movement_tags", []),
			terrain_context
		)
		results.append({"request":request, "result":result, "elapsed_usec":Time.get_ticks_usec() - started_usec, "route_profile":route_planner.get_last_profile()})
	return results


func pending_count() -> int:
	return _queue.size()


func cancel_for_unit(unit_id: String) -> int:
	var cancelled := 0
	for index in range(_queue.size() - 1, -1, -1):
		if str(_queue[index].get("unit_id", "")) == unit_id:
			_queue.remove_at(index)
			cancelled += 1
	return cancelled
