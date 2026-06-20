extends RefCounted

var character_id := ""
var states := {}
var state_name := "idle"
var frame_index := 0
var elapsed := 0.0


func setup(new_character_id: String) -> void:
	character_id = new_character_id
	states = DataRegistry.assets.animation_states(character_id)
	state_name = "idle" if states.has("idle") else _first_state_name()
	frame_index = 0
	elapsed = 0.0


func request_state(new_state_name: String, force := false) -> void:
	if new_state_name.is_empty() or not states.has(new_state_name):
		return
	if not force and state_name == new_state_name:
		return
	state_name = new_state_name
	frame_index = 0
	elapsed = 0.0


func update(delta: float, fallback_state: String) -> void:
	if states.is_empty():
		return
	if not states.has(state_name):
		request_state(fallback_state, true)
		return
	var state: Dictionary = states[state_name]
	var frames: Array = state.get("frames", [])
	if frames.is_empty():
		return
	var fps := maxf(1.0, float(state.get("fps", 6.0)))
	var frame_time := 1.0 / fps
	elapsed += delta
	while elapsed >= frame_time:
		elapsed -= frame_time
		frame_index += 1
		if frame_index < frames.size():
			continue
		if bool(state.get("loop", true)):
			frame_index = 0
		else:
			request_state(fallback_state, true)
		break


func current_frame_path() -> String:
	if not states.has(state_name):
		return ""
	var frames: Array = states[state_name].get("frames", [])
	if frames.is_empty():
		return ""
	return str(frames[clampi(frame_index, 0, frames.size() - 1)])


func _first_state_name() -> String:
	var names := states.keys()
	names.sort()
	return "" if names.is_empty() else str(names[0])
