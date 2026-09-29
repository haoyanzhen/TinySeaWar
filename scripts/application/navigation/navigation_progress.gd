extends RefCounted

# Shared by authored routes, player assist and full AI. No terrain queries and
# no route-revision resets: replanning itself is not evidence of movement.
const RECOVERY_SECONDS := 4.0
const TURN_GRACE_SECONDS := 4.0
const EXECUTION_GRACE_SECONDS := 6.0
const STUCK_SECONDS := 20.0
const PROGRESS_DISTANCE := 18.0


static func observe(memory: Dictionary, position: Vector2, heading: float, goal: Vector2, delta: float, suspended: bool = false, productive_control: bool = false) -> void:
	if memory.is_empty():
		memory.merge({"goal":goal, "best_distance":position.distance_to(goal), "progress_distance":0.0, "stalled_seconds":0.0, "best_heading_error":PI, "turn_grace":0.0, "stuck_reported":false})
	if suspended:
		return
	var previous_goal: Vector2 = memory["goal"]
	var distance := position.distance_to(previous_goal)
	var best_distance := minf(float(memory["best_distance"]), distance)
	memory["progress_distance"] = float(memory["progress_distance"]) + float(memory["best_distance"]) - best_distance
	memory["best_distance"] = best_distance
	# Arrival control intentionally slows down. Its monotonic approach must not
	# be mistaken for a blocked cruise simply because it covers less than 18.
	var required_progress := minf(PROGRESS_DISTANCE, maxf(1.0, distance * 0.08))
	if float(memory["progress_distance"]) >= required_progress:
		memory["progress_distance"] = 0.0
		memory["stalled_seconds"] = 0.0
		memory["turn_grace"] = 0.0
		memory["execution_grace"] = 0.0
		memory["best_heading_error"] = PI
		memory["stuck_reported"] = false
	else:
		memory["stalled_seconds"] = float(memory["stalled_seconds"]) + delta
	if previous_goal.distance_squared_to(goal) > 1.0:
		memory["goal"] = goal
		memory["best_distance"] = position.distance_to(goal)
		# Preserve earned partial progress across tactical target refreshes.
		# A target refresh cannot buy more turning time.
	var heading_error := absf(angle_difference(heading, (goal - position).angle()))
	var actually_turned := absf(angle_difference(float(memory.get("last_heading", heading)), heading)) > 0.0001
	memory["last_heading"] = heading
	if heading_error < float(memory["best_heading_error"]) - deg_to_rad(1.0):
		memory["best_heading_error"] = heading_error
		memory["turn_grace"] = minf(TURN_GRACE_SECONDS, float(memory["stalled_seconds"]))
		# Only actual heading convergence plus a live safe forward plan earns
		# this one bounded allowance. Replanning or target refresh cannot renew it.
		if productive_control and actually_turned: memory["execution_grace"] = EXECUTION_GRACE_SECONDS


static func needs_recovery(memory: Dictionary) -> bool:
	return float(memory.get("stalled_seconds", 0.0)) >= RECOVERY_SECONDS + float(memory.get("turn_grace", 0.0)) + float(memory.get("execution_grace", 0.0))
