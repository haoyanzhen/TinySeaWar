extends SceneTree

const ObjectiveService = preload("res://scripts/domain/services/level_objective_service.gd")
const ConfigRegistry = preload("res://scripts/infrastructure/data/config_registry.gd")
var checks := 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = root.get_node("DataRegistry").registry
	var normal := _scenario(registry, "s03")
	normal.service.refresh_challenge_progress(normal.state)
	_check(normal.service.snapshot()["mission_steps"].size() == 1, "optional escort is not a mandatory mission step")
	_check(not normal.service.snapshot()["mission_steps"][0]["completed"], "alive target initially incomplete")
	_sink(normal.state, "unit.enemy.s03.argus")
	_check(normal.service.advance(normal.state)["terminal"].is_empty(), "escort sinking alone does not win")
	_check(normal.service.snapshot()["optional_order_progress"] == 1, "first optional step recorded")
	_sink(normal.state, "unit.enemy.s03.bismarck")
	_check(normal.service.advance(normal.state)["terminal"].get("winner_faction") == "player", "ordered kills complete main mission")
	_check(normal.service.snapshot()["optional_mastery"].contains("已完成"), "legal order earns optional mastery")
	_check(normal.service.snapshot()["mission_steps"][0]["completed"], "terminal snapshot marks required target complete")
	var simultaneous := _scenario(registry, "s03")
	_sink(simultaneous.state, "unit.enemy.s03.argus")
	_sink(simultaneous.state, "unit.enemy.s03.bismarck")
	_check(simultaneous.service.advance(simultaneous.state)["terminal"].get("winner_faction") == "player", "simultaneous target kills still win")
	_check(not simultaneous.service.snapshot()["optional_order_failed"] and simultaneous.service.snapshot()["optional_order_progress"] == 2, "same Tick targets satisfy mastery without synthetic order")
	var early := _scenario(registry, "s03")
	_sink(early.state, "unit.enemy.s03.bismarck")
	_check(early.service.advance(early.state)["terminal"].get("winner_faction") == "player", "early flagship never cancels mission")
	_check(early.service.snapshot()["optional_order_failed"] and early.service.snapshot()["optional_mastery"].contains("不影响通关奖励"), "missed mastery clearly separate from reward")
	_check(early.service.advance(early.state)["events"].is_empty(), "terminal event emitted only once")
	var protection := _scenario(registry, "s02")
	protection.service.refresh_challenge_progress(protection.state)
	_check("/".join(protection.service.snapshot()["protection_lines"]).contains("至少存活1艘"), "either escort protection is visible")
	_sink(protection.state, "unit.player.s02.chongqing")
	_check(protection.service.advance(protection.state)["terminal"].is_empty(), "one surviving escort preserves mission")
	_sink(protection.state, "unit.player.s02.yukikaze")
	_check(protection.service.advance(protection.state)["terminal"].get("reason_code", "").ends_with("REQUIRED_ANY_PLAYER_SURVIVORS_LOST"), "real protection violation still cancels")
	var flagship := _scenario(registry, "s03")
	_sink(flagship.state, "unit.enemy.s03.bismarck")
	_sink(flagship.state, "unit.player.s03.warspite")
	_check(flagship.service.advance(flagship.state)["terminal"].get("reason_code", "").ends_with("PLAYER_FLAGSHIP_SUNK"), "same Tick mission completion does not bypass protected flagship")
	var wave := _scenario(registry, "s04")
	wave.service.refresh_challenge_progress(wave.state)
	_check(wave.service.snapshot()["reinforcement_hint"].contains("北侧入口") and wave.service.snapshot()["reinforcement_hint"].contains("120秒"), "public reinforcement entrance and earliest time visible")
	_check(wave.state.units_by_id.size() == 6, "reserve does not enter active units for display")
	wave.state.elapsed_time = 120.0
	wave.service.refresh_challenge_progress(wave.state)
	_check(wave.service.snapshot()["reinforcement_hint"].contains("等待出战空位"), "due reinforcement does not promise an unconditional spawn")
	wave.state.reinforcement_waves[0].status = "Spawned"
	wave.service.refresh_challenge_progress(wave.state)
	_check(wave.service.snapshot()["reinforcement_hint"].is_empty(), "spawned wave removed from pending hint")
	var duplicate_protection := _scenario(registry, "s03")
	duplicate_protection.service.definition["protected_player_unit_ids"] = ["unit.player.s03.warspite"]
	duplicate_protection.service.refresh_challenge_progress(duplicate_protection.state)
	_check(duplicate_protection.service.snapshot()["protection_lines"].size() == 1, "flagship protection shown once")
	var counted := _scenario(registry, "s05")
	_sink(counted.state, "unit.enemy.s05.hindenburg")
	counted.service.refresh_challenge_progress(counted.state)
	_check(counted.service.snapshot()["mission_steps"][1]["label"].contains("1/3"), "kill count reports actual entered-unit progress")
	for invalid in ["not-an-array", [], ["unit.enemy.s03.argus"], ["unit.enemy.s03.argus", "unit.enemy.s03.argus"], ["unit.enemy.missing", "unit.enemy.s03.bismarck"], ["unit.player.s03.warspite", "unit.enemy.s03.bismarck"]]:
		var validator = ConfigRegistry.new()
		validator.definitions = registry.definitions
		var bad: Dictionary = registry.get_definition("objectives", "objective.s03_carrier_first").duplicate(true)
		bad["optional_ordered_enemy_unit_ids"] = invalid
		validator._validate_objective(bad)
		_check(not validator.errors.is_empty(), "invalid optional definition rejected: %s" % str(invalid))
	for failure in failures:
		push_error(failure)
	print("Challenge mission feedback: %d/%d passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)


func _scenario(registry, code: String) -> Dictionary:
	var level: Dictionary = registry.get_definition("levels", "level.challenge." + code)
	var service = ObjectiveService.new()
	service.setup(registry.get_definition("objectives", level["objective_set_id"]))
	var state := {"units_by_id": {}, "fleets_by_id": {}, "tick_index": 1, "elapsed_time": 0.0, "reinforcement_waves": []}
	for faction in ["player", "enemy"]:
		var fleet := {"unit_ids": [], "flagship_unit_id": ""}
		for member in level[faction + "_fleet"]:
			var id: String = member["entity_id"]
			state.units_by_id[id] = {"entity_id": id, "faction_id": faction, "life_state": "Alive", "current_hp": 100.0, "max_hp": 100.0, "display_name": registry.get_definition("ships", member["ship_id"])["display_name"]}
			fleet.unit_ids.append(id)
			if member.get("is_flagship", false): fleet.flagship_unit_id = id
		state.fleets_by_id["fleet." + faction] = fleet
	for wave in level.get("reinforcement_waves", []):
		state.reinforcement_waves.append({"definition": wave.duplicate(true), "status": "Pending"})
	return {"service": service, "state": state}


func _sink(state: Dictionary, id: String) -> void:
	state.units_by_id[id].life_state = "Sunk"
	state.units_by_id[id].current_hp = 0.0


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
