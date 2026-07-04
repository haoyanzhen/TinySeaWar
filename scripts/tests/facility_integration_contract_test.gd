extends SceneTree

const ConfigRegistry = preload("res://scripts/infrastructure/data/config_registry.gd")
const BattleSession = preload("res://scripts/application/battle_session.gd")
const TerrainView = preload("res://scripts/presentation/battle/terrain_view.gd")

const FACILITY_IDS := [
	"facility.coastal_observation_post",
	"facility.coastal_battery",
	"facility.forward_supply_point",
	"facility.coastal_airfield",
	"facility.radar_station",
	"facility.communication_station",
	"facility.mine_control_station",
	"facility.repair_berth",
]

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = ConfigRegistry.new()
	_check(registry.load_all(), "integrated facility configuration loads")
	var definitions_complete := true
	for facility_id in FACILITY_IDS:
		var definition: Dictionary = registry.get_definition("facilities", facility_id)
		definitions_complete = definitions_complete and not definition.is_empty() and not definition.get("operation_modes", []).is_empty() and definition.has("combat_disposition") and not str(definition.get("asset_semantic", "")).is_empty()
	_check(definitions_complete, "all eight facility types declare modes, combat disposition, and visual semantics")

	var layout: Dictionary = registry.get_definition("facilities", "facility.layout.harbor_mouth")
	var placed_definitions: Array = layout.get("placements", []).map(func(placement): return str(placement.get("definition_id", "")))
	_check(FACILITY_IDS.all(func(facility_id): return facility_id in placed_definitions), "harbor level places every reviewed facility type")
	_check(_all_negative_contracts_rejected(registry), "invalid field variants for all eight facility types are rejected")

	var manifest = _read_json("res://assets/environment/facilities/facility_asset_manifest.json")
	var semantics := {}
	for asset in manifest.get("assets", []): semantics[str(asset.get("semantic", ""))] = str(asset.get("path", ""))
	var facility_assets_complete := true
	for facility_id in FACILITY_IDS:
		var semantic := str(registry.get_definition("facilities", facility_id).get("asset_semantic", ""))
		facility_assets_complete = facility_assets_complete and semantics.has("facility.%s.base" % semantic) and semantics.has("facility.%s.destroyed" % semantic)
	_check(facility_assets_complete, "all facility types provide base and destroyed presentation assets")
	_check(["facility.state.active", "facility.state.suppressed", "facility.state.offline", "facility.state.communication_disrupted", "facility.state.servicing"].all(func(semantic): return semantics.has(semantic)), "active, suppressed, silent/offline, and servicing overlays are present")
	var hud_source := FileAccess.get_file_as_string("res://scripts/presentation/battle/battle_hud.gd")
	_check(hud_source.contains("不可摧毁") and hud_source.contains("primary_contact_type") and hud_source.contains("ui_marker_minefield_known"), "HUD distinguishes durability, radar contacts, and known dynamic mines")

	var session = BattleSession.new(registry)
	_check(session.create_battle("level.prototype_harbor_3v3", 42017).get("ok", false), "integrated harbor fixture starts")
	var player: Dictionary = session.state["units_by_id"]["unit.player.shimakaze"]
	var observation_id := "facility.harbor.observation_west"
	player["position"] = session.facility_service.interaction_center(observation_id)
	session._ai_observations_by_faction.clear()
	var status: Dictionary = session.get_facility_action_status(player["entity_id"], observation_id)
	_check(["control_progress_ratio", "service_progress_ratio", "suppression_progress_ratio", "inside_interaction_water", "last_interruption_reason", "destroyable"].all(func(field): return status.has(field)), "player facility status exposes intent, progress, berth, interruption, and durability feedback")

	var enemy: Dictionary = session.state["units_by_id"]["unit.enemy.anshan"]
	session._set_ai_facility_task(enemy, {"task_type":"CaptureFacility", "facility_id":observation_id, "score":75.0})
	_check(enemy["ai_state"].get("level_task") == "CaptureFacility" and enemy["ai_state"].get("task_target_ref", {}).get("facility_id") == observation_id, "AI retains one explicit facility intent")
	session._record_ai_facility_failure(enemy, observation_id)
	var first_block := float(enemy["ai_state"].get("task_blocked_until", 0.0))
	session._set_ai_facility_task(enemy, {"task_type":"CaptureFacility", "facility_id":observation_id, "score":75.0})
	session._record_ai_facility_failure(enemy, observation_id)
	_check(first_block > float(session.state.get("elapsed_time", 0.0)) and is_inf(float(enemy["ai_state"].get("task_blocked_until", 0.0))) and str(enemy["ai_state"].get("level_task", "")).is_empty(), "AI interruption re-evaluates once and abandons the same facility after two failures")
	var pressure_adjustments: Dictionary = session._ai_engagement_score_adjustments(1.0)
	_check(float(pressure_adjustments.get("attack", 0.0)) > 0.0 and float(pressure_adjustments.get("facility_capture", 0.0)) > 0.0 and float(pressure_adjustments.get("defend", 0.0)) < 0.0, "long-term passive pressure favors engagement and facility action")

	var placement_by_id := {}
	for placement in layout.get("placements", []): placement_by_id[str(placement.get("id", ""))] = placement
	var communication_id := "facility.harbor.communication_east"
	var battery_placement: Dictionary = placement_by_id["facility.harbor.battery_west"]
	var airfield_placement: Dictionary = placement_by_id["facility.harbor.airfield_east"]
	var radar_placement: Dictionary = placement_by_id["facility.harbor.radar_east"]
	_check(communication_id in battery_placement.get("requires_any_active", []) and communication_id in airfield_placement.get("requires_any_active", []) and battery_placement.get("dependency_rules", {}).get("requires_matching_faction") and airfield_placement.get("dependency_rules", {}).get("requires_matching_faction"), "battery and airfield require an active same-faction communication source")
	_check(radar_placement.get("requires_any_active", []).is_empty() and layout.get("system_handover_rules", [])[0].get("facility_ids", []).has("facility.harbor.radar_east"), "current radar remains independent while explicit system handover is future-ready")

	var battery: Dictionary = session.facility_service.definition_for("facility.harbor.battery_west")
	_check(battery.get("durability_reference_id") == "ship.warspite" and battery.get("weapon_mount_reference", {}).get("weapon_ids", []) == ["weapon.warspite_381_ap", "weapon.warspite_381_he"] and int(battery.get("weapon_mount_reference", {}).get("mount_count", 0)) == 1 and int(battery.get("weapon_mount_reference", {}).get("shots_per_mount", 0)) == 2, "battery durability and twin-gun AP/HE mount trace to stable Warspite references")
	var level: Dictionary = registry.get_definition("levels", "level.prototype_harbor_3v3")
	_check(level.get("require_equal_fleet_cost", false) and _fleet_cost(registry, level.get("player_fleet", [])) == _fleet_cost(registry, level.get("enemy_fleet", [])), "harbor validation level keeps equal fleet cost")

	if failures.is_empty():
		print("PASS: %d facility integration contract checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error("FAIL: %s" % failure)
		print("FAILED: %d of %d facility integration contract checks" % [failures.size(), checks])
		quit(1)


func _all_negative_contracts_rejected(registry) -> bool:
	var variants: Array[Dictionary] = []
	var observation: Dictionary = registry.get_definition("facilities", "facility.coastal_observation_post").duplicate(true)
	observation["observation_rules"] = {}
	variants.append(observation)
	var battery: Dictionary = registry.get_definition("facilities", "facility.coastal_battery").duplicate(true)
	battery["durability_reference_id"] = "ship.missing"
	variants.append(battery)
	var supply: Dictionary = registry.get_definition("facilities", "facility.forward_supply_point").duplicate(true)
	supply["berthing_service"].erase("interrupt_on_leave")
	variants.append(supply)
	var airfield: Dictionary = registry.get_definition("facilities", "facility.coastal_airfield").duplicate(true)
	airfield["support_mission_ids"] = ["support_mission.missing"]
	variants.append(airfield)
	var radar: Dictionary = registry.get_definition("facilities", "facility.radar_station").duplicate(true)
	radar["radar_rules"] = {}
	variants.append(radar)
	var communication: Dictionary = registry.get_definition("facilities", "facility.communication_station").duplicate(true)
	communication["automatic_operation"]["capability_ids"] = []
	variants.append(communication)
	var mine_control: Dictionary = registry.get_definition("facilities", "facility.mine_control_station").duplicate(true)
	mine_control["remote_command"]["detection_reference"] = {}
	variants.append(mine_control)
	var repair: Dictionary = registry.get_definition("facilities", "facility.repair_berth").duplicate(true)
	repair["berthing_service"]["hold_while_docked"] = false
	variants.append(repair)
	for variant in variants:
		var before: int = registry.errors.size()
		registry._validate_facility_definition(variant)
		if registry.errors.size() <= before: return false
	return true


func _fleet_cost(registry, members: Array) -> int:
	var result := 0
	for member in members: result += int(registry.get_definition("ships", str(member.get("ship_id", ""))).get("cost", 0))
	return result


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	return JSON.parse_string(file.get_as_text()) if file != null else {}


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
