extends RefCounted

const CATEGORY_PATHS := {
	"ships": "res://data/ships",
	"weapons": "res://data/weapons",
	"projectiles": "res://data/projectiles",
	"skills": "res://data/skills",
	"formulas": "res://data/formulas",
	"levels": "res://data/levels",
	"objectives": "res://data/objectives",
	"settings": "res://data/settings",
	"visuals": "res://data/visuals",
	"facilities": "res://data/facilities",
	"ai_profiles": "res://data/ai",
}
const CATEGORY_FILES := {
	"terrain": ["res://data/terrain/terrain_templates.json", "res://data/terrain/terrain_definitions.json"],
	"navigation": ["res://data/terrain/navigation_definitions.json"],
	"environment_zones": ["res://data/environments/environment_zone_definitions.json", "res://data/environments/ocean_battle_condition_definitions.json"],
}
const DISTANCE_BASELINE_MULTIPLIER := 1.5
const MOTION_BASELINE_MULTIPLIER := 0.5
const ATTACK_SPEED_BASELINE_MULTIPLIER := 0.5
const GUN_IMPACT_RADIUS_MULTIPLIER := 0.5
const DAMAGE_BASELINE_MULTIPLIER := 0.25

var definitions := {}
var errors: Array[String] = []


func load_all() -> bool:
	definitions.clear()
	errors.clear()
	var global_ids := {}
	var categories: Array = CATEGORY_PATHS.keys()
	for category in CATEGORY_FILES:
		if category not in categories:
			categories.append(category)
	categories.sort()
	for category in categories:
		definitions[category] = {}
		var files: Array = CATEGORY_FILES[category] if CATEGORY_FILES.has(category) else _json_files(CATEGORY_PATHS[category])
		for path in files:
			_load_file(category, path, global_ids)
	_validate_references()
	return errors.is_empty()


func get_definition(category: String, definition_id: String) -> Dictionary:
	return definitions.get(category, {}).get(definition_id, {})


func all(category: String) -> Array:
	var values: Array = definitions.get(category, {}).values()
	values.sort_custom(func(a, b): return a.get("id", "") < b.get("id", ""))
	return values


func _json_files(directory_path: String) -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(directory_path)
	if directory == null:
		errors.append("Missing data directory: %s" % directory_path)
		return result
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and file_name.ends_with(".json"):
			result.append("%s/%s" % [directory_path, file_name])
		file_name = directory.get_next()
	directory.list_dir_end()
	result.sort()
	return result


func _load_file(category: String, path: String, global_ids: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("Cannot read %s" % path)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("definitions")) != TYPE_ARRAY:
		errors.append("Invalid definition document: %s" % path)
		return
	for raw_definition in parsed["definitions"]:
		if typeof(raw_definition) != TYPE_DICTIONARY:
			errors.append("Non-object definition in %s" % path)
			continue
		var definition: Dictionary = raw_definition
		var definition_id := str(definition.get("id", ""))
		if definition_id.is_empty():
			errors.append("Definition without id in %s" % path)
			continue
		if global_ids.has(definition_id):
			errors.append("Duplicate definition id %s" % definition_id)
			continue
		global_ids[definition_id] = category
		definitions[category][definition_id] = definition.duplicate(true)


func _validate_references() -> void:
	for ship in all("ships"):
		_validate_ship(ship)
	for weapon in all("weapons"):
		_validate_weapon(weapon)
	for skill in all("skills"):
		_validate_skill(skill)
	for projectile in all("projectiles"):
		_validate_projectile(projectile)
	for formula in all("formulas"):
		_validate_formula(formula)
	for level in all("levels"):
		_validate_level(level)
	for objective in all("objectives"):
		_validate_objective(objective)
	for settings in all("settings"):
		_validate_settings(settings)
	for visual in all("visuals"):
		_validate_visual(visual)
	for terrain in all("terrain"):
		_validate_terrain(terrain)
	for navigation in all("navigation"):
		_validate_navigation(navigation)
	for environment_definition in all("environment_zones"):
		_validate_environment_definition(environment_definition)
	for facility_definition in all("facilities"):
		_validate_facility_definition(facility_definition)
	for profile in all("ai_profiles"):
		_validate_ai_profile(profile)


func _validate_ai_profile(profile: Dictionary) -> void:
	var profile_id := str(profile.get("id", "?"))
	if str(profile.get("difficulty", "")) not in ["Easy", "Standard", "Hard"]:
		errors.append("Invalid AI difficulty in %s" % profile_id)
	if float(profile.get("decision_interval", 0.0)) <= 0.0:
		errors.append("AI decision_interval must be positive in %s" % profile_id)
	if float(profile.get("skill_threshold", -1.0)) < 0.0 or float(profile.get("skill_threshold", 101.0)) > 100.0:
		errors.append("Invalid AI skill_threshold in %s" % profile_id)
	if int(profile.get("target_confirmations", 0)) < 1 or int(profile.get("route_candidate_count", 0)) < 1:
		errors.append("Invalid AI confirmation or route count in %s" % profile_id)


func _validate_projectile(projectile: Dictionary) -> void:
	var projectile_id := str(projectile.get("id", "?"))
	if projectile.get("behavior", "") not in ["Straight", "DelayedImpact", "PathFollow"]:
		errors.append("Unsupported projectile behavior in %s" % projectile_id)
	if float(projectile.get("collision_radius", 0.0)) <= 0.0:
		errors.append("Projectile radius must be positive in %s" % projectile_id)
	if projectile_id.begins_with("projectile.") and "torpedo" in projectile_id and float(projectile.get("minimum_detection_distance", 0.0)) <= 0.0:
		errors.append("Torpedo minimum_detection_distance must be positive in %s" % projectile_id)
	_validate_non_negative_scaled_field(projectile, "speed", "base_speed", ATTACK_SPEED_BASELINE_MULTIPLIER, projectile_id)


func _validate_formula(formula: Dictionary) -> void:
	var formula_id := str(formula.get("id", "?"))
	if formula.get("attack_type", "") not in ["Gun", "Torpedo", "Aviation", "AntiAir", "AntiSubmarine", "Skill"]:
		errors.append("Invalid attack_type in %s" % formula_id)
	_validate_scaled_field(formula, "base_damage", "design_base_damage", DAMAGE_BASELINE_MULTIPLIER, formula_id)
	_validate_scaled_field(formula, "power_coefficient", "design_power_coefficient", DAMAGE_BASELINE_MULTIPLIER, formula_id)
	_validate_non_negative_scaled_field(formula, "armor_coefficient", "design_armor_coefficient", DAMAGE_BASELINE_MULTIPLIER, formula_id)


func _validate_ship(ship: Dictionary) -> void:
	var ship_id := str(ship.get("id", "?"))
	if ship.get("ship_class", "") not in ["Destroyer", "LightCruiser", "HeavyCruiser", "Battleship", "Carrier", "Submarine"]:
		errors.append("Invalid ship class in %s" % ship_id)
	if int(ship.get("level", 0)) < 1 or int(ship.get("level", 0)) > 3:
		errors.append("Invalid level in %s" % ship_id)
	for field in ["max_hp", "speed", "turn_speed", "detection_range", "concealment_distance", "collision_radius"]:
		if float(ship.get(field, 0.0)) <= 0.0:
			errors.append("%s must be positive in %s" % [field, ship_id])
	for field in ["speed", "turn_speed"]:
		_validate_scaled_field(ship, field, "base_%s" % field, MOTION_BASELINE_MULTIPLIER, ship_id)
	for field in ["detection_range", "concealment_distance"]:
		_validate_scaled_field(ship, field, "base_%s" % field, DISTANCE_BASELINE_MULTIPLIER, ship_id)
	var collision_half_extents = ship.get("collision_half_extents", [])
	if not _valid_positive_pair(collision_half_extents):
		errors.append("collision_half_extents must be a positive pair in %s" % ship_id)
	elif float(collision_half_extents[0]) < float(collision_half_extents[1]):
		errors.append("collision_half_extents longitudinal axis must not be smaller than lateral axis in %s" % ship_id)
	for weapon_id in ship.get("weapon_mounts", []):
		if get_definition("weapons", weapon_id).is_empty():
			errors.append("Missing weapon %s referenced by %s" % [weapon_id, ship_id])
	var primary_group_id := str(ship.get("primary_weapon_group_id", ""))
	if primary_group_id.is_empty():
		errors.append("Missing primary_weapon_group_id in %s" % ship_id)
	var primary_count := 0
	var manual_primary_groups := {}
	var ammo_group_id := str(ship.get("ammo_selection_group_id", ""))
	var ammo_types := {}
	for weapon_id in ship.get("weapon_mounts", []):
		var weapon := get_definition("weapons", str(weapon_id))
		if weapon.is_empty(): continue
		if weapon.get("control_mode", "") == "ManualPrimary":
			manual_primary_groups[str(weapon.get("weapon_group_id", ""))] = true
		if str(weapon.get("weapon_group_id", "")) == primary_group_id:
			primary_count += 1
			if weapon.get("control_mode", "") != "ManualPrimary":
				errors.append("Primary weapon %s must be ManualPrimary for %s" % [weapon_id, ship_id])
		if not ammo_group_id.is_empty() and str(weapon.get("weapon_group_id", "")) == ammo_group_id:
			var ammo_type := str(weapon.get("ammo_type", ""))
			if ammo_type in ["HE", "AP"]: ammo_types[ammo_type] = true
	if primary_count == 0:
		errors.append("Primary weapon group %s has no mounted weapon in %s" % [primary_group_id, ship_id])
	if manual_primary_groups.size() > 1:
		errors.append("Only one ManualPrimary weapon group is allowed in %s" % ship_id)
	if str(ship.get("primary_weapon_control_type", "")) not in ["Area", "Direction", "Airstrike"]:
		errors.append("Invalid primary_weapon_control_type in %s" % ship_id)
	if not ammo_group_id.is_empty() and (not ammo_types.has("HE") or not ammo_types.has("AP")):
		errors.append("Ammo selection group %s must contain HE and AP in %s" % [ammo_group_id, ship_id])
	var skill_id := str(ship.get("skill_id", ""))
	if not skill_id.is_empty() and get_definition("skills", skill_id).is_empty():
		errors.append("Missing skill %s referenced by %s" % [skill_id, ship_id])


func _validate_weapon(weapon: Dictionary) -> void:
	var weapon_id := str(weapon.get("id", "?"))
	if weapon.get("mount_type", "") not in ["Gun", "Torpedo", "AntiAir", "Aviation", "AntiSubmarine", "Special"]:
		errors.append("Invalid mount type in %s" % weapon_id)
	if str(weapon.get("weapon_group_id", "")).is_empty():
		errors.append("Missing weapon_group_id in %s" % weapon_id)
	if weapon.get("control_mode", "") not in ["Automatic", "ManualPrimary"]:
		errors.append("Invalid control_mode in %s" % weapon_id)
	var ammo_type := str(weapon.get("ammo_type", ""))
	if not ammo_type.is_empty() and ammo_type not in ["HE", "AP"]:
		errors.append("Invalid ammo_type in %s" % weapon_id)
	for field in ["mount_count", "shots_per_mount", "reload_time", "range"]:
		if float(weapon.get(field, 0.0)) <= 0.0:
			errors.append("%s must be positive in %s" % [field, weapon_id])
	var base_range := float(weapon.get("base_range", 0.0))
	if base_range <= 0.0:
		errors.append("base_range must be positive in %s" % weapon_id)
	elif not is_equal_approx(float(weapon.get("range", 0.0)), base_range * DISTANCE_BASELINE_MULTIPLIER):
		errors.append("Effective range must be %.1fx base_range in %s" % [DISTANCE_BASELINE_MULTIPLIER, weapon_id])
	if float(weapon.get("minimum_range", 0.0)) > float(weapon.get("range", 0.0)):
		errors.append("Invalid range band in %s" % weapon_id)
	_validate_non_negative_scaled_field(weapon, "projectile_speed", "base_projectile_speed", ATTACK_SPEED_BASELINE_MULTIPLIER, weapon_id)
	if weapon.get("mount_type", "") == "Gun":
		_validate_scaled_field(weapon, "impact_radius", "base_impact_radius", GUN_IMPACT_RADIUS_MULTIPLIER, weapon_id)
	if float(weapon.get("fire_arc_degrees", 0.0)) <= 0.0 or float(weapon.get("fire_arc_degrees", 0.0)) > 360.0:
		errors.append("Invalid fire arc in %s" % weapon_id)
	var fire_arcs: Array = weapon.get("fire_arcs", [])
	if weapon.get("mount_type", "") == "Torpedo" and weapon.get("control_mode", "") == "ManualPrimary" and fire_arcs.is_empty():
		errors.append("Manual torpedo weapon must define fire_arcs in %s" % weapon_id)
	for arc_index in range(fire_arcs.size()):
		var arc = fire_arcs[arc_index]
		if not arc is Dictionary:
			errors.append("Invalid fire arc entry %s in %s" % [arc_index, weapon_id])
			continue
		if not arc.has("center") or not arc.has("degrees"):
			errors.append("Incomplete fire arc entry %s in %s" % [arc_index, weapon_id])
			continue
		var arc_degrees := float(arc.get("degrees", 0.0))
		if arc_degrees <= 0.0 or arc_degrees > 360.0:
			errors.append("Invalid fire arc entry %s in %s" % [arc_index, weapon_id])
	if weapon.get("mount_type", "") == "Torpedo":
		var sigma_ratio := float(weapon.get("torpedo_angular_sigma_ratio", -1.0))
		if absf(sigma_ratio - 0.2) > 0.0001:
			errors.append("torpedo_angular_sigma_ratio must use the 0.2 baseline in %s" % weapon_id)
	if weapon.get("mount_type", "") == "Torpedo" and weapon.get("control_mode", "") == "ManualPrimary":
		var mount_fire_arcs: Array = weapon.get("mount_fire_arcs", [])
		var mount_count := int(weapon.get("mount_count", 0))
		if mount_fire_arcs.size() != mount_count:
			errors.append("Manual torpedo weapon must define one mount_fire_arcs entry per mount in %s" % weapon_id)
		var mount_ids := {}
		for mount_index in range(mount_fire_arcs.size()):
			var mount = mount_fire_arcs[mount_index]
			if not mount is Dictionary or str(mount.get("mount_id", "")).is_empty() or mount_ids.has(str(mount.get("mount_id", ""))):
				errors.append("Invalid or duplicate torpedo mount %s in %s" % [mount_index, weapon_id])
				continue
			mount_ids[str(mount["mount_id"])] = true
			var mount_arcs: Array = mount.get("fire_arcs", [])
			if mount_arcs.is_empty():
				errors.append("Torpedo mount %s has no fire arcs in %s" % [mount_index, weapon_id])
			for mount_arc in mount_arcs:
				if not mount_arc is Dictionary or float(mount_arc.get("degrees", 0.0)) <= 0.0 or float(mount_arc.get("degrees", 0.0)) > 360.0:
					errors.append("Invalid torpedo mount fire arc %s in %s" % [mount_index, weapon_id])
		var lane_spacing := float(weapon.get("torpedo_lane_spacing", 0.0))
		var launch_interval := float(weapon.get("mount_launch_interval", 0.0))
		if lane_spacing <= 0.0:
			errors.append("torpedo_lane_spacing must be positive in %s" % weapon_id)
		if launch_interval < 1.0:
			errors.append("mount_launch_interval must be at least 1 second in %s" % weapon_id)
		var shot_count := int(weapon.get("shots_per_mount", 0))
		var effective_range := float(weapon.get("range", 0.0))
		if lane_spacing > 0.0 and effective_range > 0.0 and shot_count > 0:
			var adjacent_angle := 2.0 * asin(minf(1.0, lane_spacing / (2.0 * effective_range)))
			var expected_spread := rad_to_deg(adjacent_angle) * float(maxi(0, shot_count - 1))
			if absf(float(weapon.get("spread", -1.0)) - expected_spread) > 0.001:
				errors.append("Torpedo spread must derive from lane spacing at maximum range in %s" % weapon_id)
	var full_salvo_fire_arcs: Array = weapon.get("full_salvo_fire_arcs", [])
	if weapon.get("mount_type", "") == "Gun" and int(weapon.get("mount_count", 0)) > 1 and full_salvo_fire_arcs.is_empty():
		errors.append("Multi-mount gun must define full_salvo_fire_arcs in %s" % weapon_id)
	for arc_index in range(full_salvo_fire_arcs.size()):
		var arc = full_salvo_fire_arcs[arc_index]
		if not arc is Dictionary or not arc.has("center") or not arc.has("degrees"):
			errors.append("Invalid full-salvo fire arc entry %s in %s" % [arc_index, weapon_id])
			continue
		var arc_degrees := float(arc.get("degrees", 0.0))
		if arc_degrees <= 0.0 or arc_degrees > 360.0:
			errors.append("Invalid full-salvo fire arc entry %s in %s" % [arc_index, weapon_id])
	if get_definition("projectiles", str(weapon.get("projectile_id", ""))).is_empty():
		errors.append("Missing projectile referenced by %s" % weapon_id)
	if get_definition("formulas", str(weapon.get("formula_id", ""))).is_empty():
		errors.append("Missing formula referenced by %s" % weapon_id)


func _validate_skill(skill: Dictionary) -> void:
	var skill_id := str(skill.get("id", "?"))
	var base_cast_range := float(skill.get("base_cast_range", skill.get("cast_range", 0.0)))
	if base_cast_range < 0.0:
		errors.append("base_cast_range cannot be negative in %s" % skill_id)
	elif base_cast_range <= 0.0:
		if not is_equal_approx(float(skill.get("cast_range", 0.0)), 0.0):
			errors.append("Zero-range skill must keep cast_range 0 in %s" % skill_id)
	elif not skill.has("base_cast_range"):
		errors.append("Missing base_cast_range in %s" % skill_id)
	elif not is_equal_approx(float(skill.get("cast_range", 0.0)), base_cast_range * DISTANCE_BASELINE_MULTIPLIER):
		errors.append("Effective cast_range must be %.1fx base_cast_range in %s" % [DISTANCE_BASELINE_MULTIPLIER, skill_id])


func _validate_scaled_field(definition: Dictionary, effective_field: String, base_field: String, multiplier: float, definition_id: String) -> void:
	var base_value := float(definition.get(base_field, 0.0))
	if base_value <= 0.0:
		errors.append("%s must be positive in %s" % [base_field, definition_id])
		return
	if not is_equal_approx(float(definition.get(effective_field, 0.0)), base_value * multiplier):
		errors.append("%s must be %.1fx %s in %s" % [effective_field, multiplier, base_field, definition_id])


func _validate_non_negative_scaled_field(definition: Dictionary, effective_field: String, base_field: String, multiplier: float, definition_id: String) -> void:
	if not definition.has(base_field):
		errors.append("Missing %s in %s" % [base_field, definition_id])
		return
	var base_value := float(definition.get(base_field, 0.0))
	if base_value < 0.0:
		errors.append("%s cannot be negative in %s" % [base_field, definition_id])
		return
	if not is_equal_approx(float(definition.get(effective_field, 0.0)), base_value * multiplier):
		errors.append("%s must be %.1fx %s in %s" % [effective_field, multiplier, base_field, definition_id])


func _validate_level(level: Dictionary) -> void:
	var level_id := str(level.get("id", "?"))
	var map: Dictionary = level.get("map", {})
	var ocean_palette := str(map.get("ocean_palette", ""))
	if ocean_palette.is_empty() or not _ocean_condition_exists(ocean_palette):
		errors.append("Missing ocean battle condition for palette %s referenced by %s" % [ocean_palette, level_id])
	var terrain_definition_id := str(map.get("terrain_definition_id", ""))
	if not terrain_definition_id.is_empty() and get_definition("terrain", terrain_definition_id).is_empty():
		errors.append("Missing terrain %s referenced by %s" % [terrain_definition_id, level_id])
	var navigation_definition_id := str(map.get("navigation_definition_id", ""))
	if not navigation_definition_id.is_empty() and get_definition("navigation", navigation_definition_id).is_empty():
		errors.append("Missing navigation %s referenced by %s" % [navigation_definition_id, level_id])
	var environment_zone_set_id := str(map.get("environment_zone_set_id", ""))
	if not environment_zone_set_id.is_empty() and get_definition("environment_zones", environment_zone_set_id).is_empty():
		errors.append("Missing environment zone set %s referenced by %s" % [environment_zone_set_id, level_id])
	var facility_layout_id := str(map.get("facility_layout_id", ""))
	if not facility_layout_id.is_empty() and get_definition("facilities", facility_layout_id).is_empty():
		errors.append("Missing facility layout %s referenced by %s" % [facility_layout_id, level_id])
	var ai_profile_id := str(level.get("enemy_ai_profile_id", "ai.profile.standard"))
	if get_definition("ai_profiles", ai_profile_id).is_empty():
		errors.append("Missing AI profile %s referenced by %s" % [ai_profile_id, level_id])
	var objective_set_id := str(level.get("objective_set_id", ""))
	if not objective_set_id.is_empty() and get_definition("objectives", objective_set_id).is_empty():
		errors.append("Missing objective %s referenced by %s" % [objective_set_id, level_id])
	for fleet_name in ["player_fleet", "enemy_fleet"]:
		var fleet: Array = level.get(fleet_name, [])
		var flagship_count := 0
		var entity_ids := {}
		for member in fleet:
			var ship: Dictionary = get_definition("ships", str(member.get("ship_id", "")))
			if ship.is_empty():
				errors.append("Missing ship in %s/%s" % [level_id, fleet_name])
			var group_states = member.get("weapon_group_states", {})
			if typeof(group_states) != TYPE_DICTIONARY:
				errors.append("Invalid weapon_group_states in %s/%s" % [level_id, fleet_name])
			else:
				var mounted_group_ids := {}
				for weapon_id in ship.get("weapon_mounts", []):
					var weapon: Dictionary = get_definition("weapons", str(weapon_id))
					mounted_group_ids[str(weapon.get("weapon_group_id", ""))] = true
				for group_id_value in group_states:
					var group_id := str(group_id_value)
					if group_id.is_empty() or not mounted_group_ids.has(group_id):
						errors.append("Unknown weapon group %s in %s/%s" % [group_id, level_id, fleet_name])
					if str(group_states[group_id_value]) not in ["Enabled", "Disabled"]:
						errors.append("Invalid weapon group state for %s in %s/%s" % [group_id, level_id, fleet_name])
			var entity_id := str(member.get("entity_id", ""))
			if entity_id.is_empty() or entity_ids.has(entity_id):
				errors.append("Invalid or duplicate entity id in %s/%s" % [level_id, fleet_name])
			entity_ids[entity_id] = true
			if bool(member.get("is_flagship", false)):
				flagship_count += 1
		if flagship_count != 1:
			errors.append("%s/%s must contain exactly one flagship" % [level_id, fleet_name])
	if bool(level.get("require_equal_fleet_cost", false)):
		var fleet_costs := {}
		for fleet_name in ["player_fleet", "enemy_fleet"]:
			var total_cost := 0
			for member in level.get(fleet_name, []):
				total_cost += int(get_definition("ships", str(member.get("ship_id", ""))).get("cost", 0))
			fleet_costs[fleet_name] = total_cost
		if int(fleet_costs.get("player_fleet", 0)) != int(fleet_costs.get("enemy_fleet", 0)):
			errors.append("Equal-cost level %s has player/enemy costs %d/%d" % [level_id, fleet_costs.get("player_fleet", 0), fleet_costs.get("enemy_fleet", 0)])


func _validate_objective(objective: Dictionary) -> void:
	var objective_id := str(objective.get("id", "?"))
	var kind := str(objective.get("objective_kind", ""))
	if kind not in ["TutorialNavigation", "FlagshipMission"]:
		errors.append("Unsupported objective kind in %s" % objective_id)
	if str(objective.get("title", "")).is_empty():
		errors.append("Missing objective title in %s" % objective_id)
	if kind == "TutorialNavigation":
		var zones: Array = objective.get("waypoint_zones", [])
		if zones.size() != 2:
			errors.append("Tutorial navigation objective %s must contain two waypoint zones" % objective_id)
		for zone in zones:
			if not _valid_positive_pair(zone.get("position", [])) or float(zone.get("radius", 0.0)) <= 0.0:
				errors.append("Invalid waypoint zone in %s" % objective_id)
		if not _valid_positive_pair(objective.get("enemy_staging_position", [])):
			errors.append("Invalid enemy staging position in %s" % objective_id)
		var action_ids := {}
		for requirement in objective.get("required_actions", []):
			var action_id := str(requirement.get("action_id", ""))
			if action_id.is_empty() or action_ids.has(action_id) or int(requirement.get("required_count", 0)) <= 0:
				errors.append("Invalid or duplicate tutorial action in %s" % objective_id)
			action_ids[action_id] = true


func _validate_settings(settings: Dictionary) -> void:
	var settings_id := str(settings.get("id", "?"))
	if settings_id == "settings.combat":
		_validate_combat_settings(settings)
		return
	if settings_id != "settings.presentation":
		errors.append("Unsupported settings definition id: %s" % settings_id)
		return
	var window: Dictionary = settings.get("window", {})
	var logical_size: Array = window.get("logical_size", [])
	var default_size: Array = window.get("default_size", [])
	var size_options: Array = window.get("size_options", [])
	if not _valid_positive_pair(logical_size):
		errors.append("Invalid logical window size in %s" % settings_id)
	if not _valid_positive_pair(default_size):
		errors.append("Invalid default window size in %s" % settings_id)
	if size_options.is_empty():
		errors.append("Window size options cannot be empty in %s" % settings_id)
	for size_option in size_options:
		if not _valid_positive_pair(size_option):
			errors.append("Invalid window size option in %s" % settings_id)
	if not default_size.is_empty() and default_size not in size_options:
		errors.append("Default window size must be listed in size_options in %s" % settings_id)
	var camera: Dictionary = settings.get("camera", {})
	if not _valid_positive_pair(camera.get("min_visible_size", [])):
		errors.append("Invalid camera min_visible_size in %s" % settings_id)
	var max_fraction := float(camera.get("max_map_visible_fraction", 0.0))
	if max_fraction <= 0.0 or max_fraction > 1.0:
		errors.append("Camera max_map_visible_fraction must be in (0, 1] in %s" % settings_id)
	if float(camera.get("zoom_step", 0.0)) <= 1.0:
		errors.append("Camera zoom_step must be greater than 1 in %s" % settings_id)
	if float(camera.get("default_zoom", 0.0)) <= 0.0:
		errors.append("Camera default_zoom must be positive in %s" % settings_id)


func _validate_combat_settings(settings: Dictionary) -> void:
	var dispersion: Dictionary = settings.get("gun_dispersion", {})
	var sigma_scale := float(dispersion.get("sigma_scale", 0.0))
	var longitudinal_ratio := float(dispersion.get("longitudinal_sigma_ratio", 0.0))
	var reference_range := float(dispersion.get("reference_range", 0.0))
	var reference_spread := float(dispersion.get("reference_spread_degrees", 0.0))
	var reference_length := float(dispersion.get("reference_battleship_length", 0.0))
	if sigma_scale <= 0.0 or longitudinal_ratio <= 0.0 or longitudinal_ratio > 1.0:
		errors.append("Invalid gun dispersion sigma ratios in settings.combat")
	if reference_range <= 0.0 or reference_spread <= 0.0 or reference_length <= 0.0:
		errors.append("Invalid gun dispersion reference values in settings.combat")
	elif not is_equal_approx(reference_range * deg_to_rad(reference_spread) * sigma_scale, reference_length):
		errors.append("Gun dispersion reference does not reproduce the battleship-length sigma in settings.combat")
	if get_definition("ships", str(dispersion.get("reference_ship_id", ""))).is_empty():
		errors.append("Gun dispersion references a missing ship in settings.combat")
	if get_definition("weapons", str(dispersion.get("reference_weapon_id", ""))).is_empty():
		errors.append("Gun dispersion references a missing weapon in settings.combat")


func _valid_positive_pair(value: Variant) -> bool:
	return value is Array and value.size() == 2 and float(value[0]) > 0.0 and float(value[1]) > 0.0


func _validate_visual(visual: Dictionary) -> void:
	var visual_id := str(visual.get("id", "?"))
	if visual_id.begins_with("visual.projectile."):
		var projectile_id := str(visual.get("projectile_id", ""))
		if projectile_id.is_empty():
			errors.append("Missing projectile_id in %s" % visual_id)
		elif get_definition("projectiles", projectile_id).is_empty():
			errors.append("Missing projectile %s referenced by %s" % [projectile_id, visual_id])
		var sprite := str(visual.get("sprite", ""))
		if sprite.is_empty():
			errors.append("Missing sprite in %s" % visual_id)
		elif not _resource_exists(sprite):
			errors.append("Missing sprite resource %s in %s" % [sprite, visual_id])
		var trail_sprite := str(visual.get("trail_sprite", ""))
		if not trail_sprite.is_empty() and not _resource_exists(trail_sprite):
			errors.append("Missing trail sprite resource %s in %s" % [trail_sprite, visual_id])
		if str(visual.get("projectile_type", "")) == "Shell":
			if float(visual.get("shell_trail_caliber_pixel_multiplier", 0.0)) <= 0.0:
				errors.append("Shell trail caliber multiplier must be positive in %s" % visual_id)
			if float(visual.get("shell_trail_width", 0.0)) <= 0.0:
				errors.append("Shell trail width must be positive in %s" % visual_id)
			if float(visual.get("shell_trail_duration", 0.0)) <= 0.0:
				errors.append("Shell trail duration must be positive in %s" % visual_id)
	elif visual_id.begins_with("weapon_visual."):
		if str(visual.get("character_id", "")).is_empty():
			errors.append("Missing character_id in %s" % visual_id)
		var weapon_id := str(visual.get("weapon_id", ""))
		var weapon_group_id := str(visual.get("weapon_group_id", ""))
		if weapon_group_id.is_empty() and weapon_id.is_empty():
			errors.append("Missing weapon_group_id or weapon_id in %s" % visual_id)
		elif not weapon_id.is_empty() and get_definition("weapons", weapon_id).is_empty():
			errors.append("Missing weapon %s referenced by %s" % [weapon_id, visual_id])
		elif not weapon_group_id.is_empty() and not _weapon_group_exists(weapon_group_id):
			errors.append("Missing weapon group %s referenced by %s" % [weapon_group_id, visual_id])
		var projectile_visual_id := str(visual.get("projectile_visual_id", ""))
		if projectile_visual_id.is_empty():
			errors.append("Missing projectile_visual_id in %s" % visual_id)
		elif get_definition("visuals", projectile_visual_id).is_empty():
			errors.append("Missing projectile visual %s referenced by %s" % [projectile_visual_id, visual_id])
	elif visual_id.begins_with("vfx.profile."):
		if float(visual.get("duration", 0.0)) <= 0.0:
			errors.append("VFX duration must be positive in %s" % visual_id)
	else:
		errors.append("Unsupported visual definition id: %s" % visual_id)


func _validate_terrain(definition: Dictionary) -> void:
	var definition_id := str(definition.get("id", "?"))
	var definition_type := str(definition.get("definition_type", ""))
	if definition_type not in ["TerrainAssetTemplate", "TerrainMap"]:
		errors.append("Unsupported terrain definition type in %s" % definition_id)
		return
	for obstacle in definition.get("obstacles", []):
		if obstacle.get("polygon", []).size() < 3:
			errors.append("Terrain obstacle has fewer than 3 vertices in %s" % definition_id)
		for block_mask in obstacle.get("block_mask", []):
			if block_mask not in ["ShipMovement", "TorpedoTravel", "ShellTravel", "SurfaceOpticalLineOfSight"]:
				errors.append("Unknown terrain block mask in %s" % definition_id)
	for region in definition.get("regions", []):
		if region.get("region_type", "") not in ["DeepWater", "CoastalWater", "ShallowWater", "ReefOrSandbar", "NavigationChannel"]:
			errors.append("Unknown terrain region type in %s" % definition_id)
	for visual_region in definition.get("visual_regions", []):
		if visual_region.get("polygon", []).size() < 3 or str(visual_region.get("asset_semantic", "")).is_empty():
			errors.append("Invalid visual-only terrain region in %s" % definition_id)
	if definition_type == "TerrainMap":
		var map_size: Array = definition.get("map_size", [])
		if not _valid_positive_pair(map_size):
			errors.append("Invalid terrain map size in %s" % definition_id)
		var spawn_ids := {}
		for faction_id in ["player", "enemy"]:
			var faction_spawns: Array = definition.get("spawn_points", []).filter(func(spawn): return str(spawn.get("faction_id", "")) == faction_id)
			if faction_spawns.size() != 11:
				errors.append("Terrain map %s must provide 11 %s spawn slots" % [definition_id, faction_id])
			for spawn in faction_spawns:
				var spawn_id := str(spawn.get("id", ""))
				if spawn_id.is_empty() or spawn_ids.has(spawn_id): errors.append("Terrain map has missing or duplicate spawn id in %s" % definition_id)
				spawn_ids[spawn_id] = true
				if not _valid_positive_pair(spawn.get("position", [])) or float(spawn.get("radius", 0.0)) < 46.0 or not spawn.has("heading") or spawn.get("movement_tags", []) != ["Surface"]:
					errors.append("Terrain map has invalid large-fleet spawn contract in %s" % definition_id)


func _validate_navigation(definition: Dictionary) -> void:
	var definition_id := str(definition.get("id", "?"))
	if definition.get("definition_type", "") != "NavigationGraph":
		errors.append("Unsupported navigation definition type in %s" % definition_id)
	if get_definition("terrain", str(definition.get("terrain_definition_id", ""))).is_empty():
		errors.append("Navigation graph references missing terrain in %s" % definition_id)
	if definition.get("profiles", []).is_empty():
		errors.append("Navigation graph has no profiles in %s" % definition_id)


func _validate_environment_definition(definition: Dictionary) -> void:
	var definition_id := str(definition.get("id", "?"))
	var definition_type := str(definition.get("definition_type", ""))
	if definition_type not in ["EnvironmentEffect", "EnvironmentZoneSet", "WeatherBattleProfile", "TimeBattleProfile", "OceanConditionRules", "OceanConditionAliases"]:
		errors.append("Unsupported environment definition type in %s" % definition_id)
		return
	if definition_type == "WeatherBattleProfile":
		if definition.get("weather", "") not in ["clear", "cloudy", "overcast", "rain", "thunderstorm"]:
			errors.append("Unsupported weather battle profile in %s" % definition_id)
		_validate_environment_context(definition.get("context", {}), definition_id, true)
	elif definition_type == "EnvironmentEffect":
		var effect_context: Dictionary = definition.get("context", {})
		if float(effect_context.get("wind_speed", 0.0)) < 0.0 or float(effect_context.get("wind_speed_add", 0.0)) < 0.0:
			errors.append("Invalid environment wind value in %s" % definition_id)
	elif definition_type == "TimeBattleProfile":
		if definition.get("time_of_day", "") not in ["day", "dawn", "dusk", "night"]:
			errors.append("Unsupported time battle profile in %s" % definition_id)
		_validate_environment_context(definition.get("context", {}), definition_id, false)
	elif definition_type == "OceanConditionRules":
		if float(definition.get("minimum_optical_visibility_multiplier", 0.0)) <= 0.0 or float(definition.get("minimum_optical_visibility_multiplier", 0.0)) > 1.0:
			errors.append("Invalid minimum optical visibility in %s" % definition_id)
		if int(definition.get("torpedo_sigma_reference_sea_state", -1)) < 0 or int(definition.get("torpedo_sigma_reference_sea_state", 6)) > 5:
			errors.append("Invalid torpedo sigma reference sea state in %s" % definition_id)
		if float(definition.get("torpedo_sigma_sea_state_step", -1.0)) < 0.0 or float(definition.get("torpedo_sigma_wind_threshold", -1.0)) < 0.0 or float(definition.get("torpedo_sigma_wind_step", -1.0)) < 0.0 or float(definition.get("torpedo_sigma_multiplier_max", 0.0)) < 1.0:
			errors.append("Invalid torpedo environmental sigma policy in %s" % definition_id)
		_validate_sea_state_rules(definition.get("sea_state_rules", []), definition_id)
	elif definition_type == "OceanConditionAliases":
		for alias in definition.get("aliases", {}):
			if not _formal_ocean_condition_exists(str(definition["aliases"][alias])):
				errors.append("Ocean condition alias %s has invalid target in %s" % [alias, definition_id])
	elif definition_type == "EnvironmentZoneSet":
		var global_environment: Dictionary = definition.get("global_environment", {})
		_validate_sea_state_rules(global_environment.get("sea_state_rules", []), definition_id)
		var tide: Dictionary = global_environment.get("tide", {})
		if not tide.is_empty():
			var phases: Array = tide.get("phases", [])
			if phases.is_empty() or str(tide.get("initial_phase", "")) not in phases or float(tide.get("phase_duration", 0.0)) <= 0.0:
				errors.append("Environment zone set has invalid tide cycle in %s" % definition_id)
			for open_phase in tide.get("open_phases", []):
				if open_phase not in phases: errors.append("Environment zone set has unknown open tide phase in %s" % definition_id)
		var zone_ids := {}
		for zone in definition.get("zones", []):
			var zone_id := str(zone.get("id", ""))
			if zone_id.is_empty() or zone_ids.has(zone_id):
				errors.append("Environment zone has missing or duplicate id in %s" % definition_id)
			zone_ids[zone_id] = true
			if get_definition("environment_zones", str(zone.get("effect_id", ""))).is_empty():
				errors.append("Environment zone references missing effect in %s" % definition_id)
			if zone.get("polygon", []).size() < 3:
				errors.append("Environment zone has invalid polygon in %s" % definition_id)
			if float(zone.get("heading", -1.0)) < 0.0 or float(zone.get("heading", 360.0)) >= 360.0:
				errors.append("Environment zone has invalid heading in %s" % definition_id)
			if float(zone.get("drift_speed", -1.0)) < 0.0 or float(zone.get("duration", -1.0)) < 0.0:
				errors.append("Environment zone has invalid drift or duration in %s" % definition_id)
			if float(zone.get("intensity", -1.0)) < 0.0 or float(zone.get("intensity", 2.0)) > 1.0:
				errors.append("Environment zone has invalid intensity in %s" % definition_id)
			var drift_path: Array = zone.get("drift_path", [])
			var invalid_path_start := false
			if drift_path.size() >= 2:
				var first_path_point: Array = drift_path[0]
				invalid_path_start = first_path_point.size() != 2 or not is_zero_approx(float(first_path_point[0])) or not is_zero_approx(float(first_path_point[1]))
			if drift_path.size() == 1 or invalid_path_start:
				errors.append("Environment zone has invalid drift path in %s" % definition_id)
			if str(zone.get("phase", "")).is_empty() or str(zone.get("public_trend", "")).is_empty():
				errors.append("Environment zone lacks phase or public trend in %s" % definition_id)


func _validate_environment_context(context: Dictionary, definition_id: String, require_sea_state: bool) -> void:
	if require_sea_state and (int(context.get("base_sea_state", -1)) < 0 or int(context.get("base_sea_state", 6)) > 5):
		errors.append("Invalid base sea state in %s" % definition_id)
	if float(context.get("optical_visibility_multiplier", 0.0)) <= 0.0 or float(context.get("aviation_delay_multiplier", 0.0)) <= 0.0:
		errors.append("Invalid environment multiplier in %s" % definition_id)
	if context.has("wind_speed") and float(context.get("wind_speed", -1.0)) < 0.0:
		errors.append("Invalid environment wind speed in %s" % definition_id)
	if context.has("aviation_condition") and context.get("aviation_condition", "") not in ["Normal", "Restricted", "Severe", "Grounded"]:
		errors.append("Invalid aviation condition in %s" % definition_id)


func _validate_sea_state_rules(rules: Array, definition_id: String) -> void:
	for rule in rules:
		if int(rule.get("minimum_sea_state", -1)) < 0 or float(rule.get("movement_speed_multiplier", 0.0)) <= 0.0 or float(rule.get("aviation_delay_multiplier", 0.0)) <= 0.0:
			errors.append("Invalid sea-state rule in %s" % definition_id)


func _ocean_condition_exists(palette_id: String) -> bool:
	var aliases: Dictionary = get_definition("environment_zones", "environment.condition_aliases.ocean").get("aliases", {})
	return _formal_ocean_condition_exists(str(aliases.get(palette_id, palette_id)))


func _formal_ocean_condition_exists(palette_id: String) -> bool:
	var parts := palette_id.split("_")
	return parts.size() == 2 and not get_definition("environment_zones", "environment.weather.%s" % parts[0]).is_empty() and not get_definition("environment_zones", "environment.time.%s" % parts[1]).is_empty()


func _validate_facility_definition(definition: Dictionary) -> void:
	var definition_id := str(definition.get("id", "?"))
	var definition_type := str(definition.get("definition_type", ""))
	if definition_type not in ["FacilityDefinition", "FacilityLayout", "SupportMissionDefinition", "MinefieldDefinition"]:
		errors.append("Unsupported facility definition type in %s" % definition_id)
	elif definition_type == "FacilityDefinition":
		var durability_reference_id := str(definition.get("durability_reference_id", ""))
		if durability_reference_id.is_empty() and float(definition.get("max_hp", 0.0)) <= 0.0:
			errors.append("Facility max_hp must be positive in %s" % definition_id)
		elif not durability_reference_id.is_empty() and get_definition("ships", durability_reference_id).is_empty():
			errors.append("Facility durability reference is missing in %s" % definition_id)
		var operation_modes: Array = definition.get("operation_modes", [])
		var allowed_modes := ["AreaControl", "BerthingService", "RemoteCommand", "AutomaticOperation", "CombatDisposition"]
		if operation_modes.is_empty(): errors.append("Facility lacks operation_modes in %s" % definition_id)
		for mode in operation_modes:
			if mode not in allowed_modes: errors.append("Facility has invalid operation mode %s in %s" % [mode, definition_id])
		if "AreaControl" in operation_modes:
			var area_control: Dictionary = definition.get("area_control", {})
			if not bool(area_control.get("enabled", false)) or not bool(area_control.get("capturable", false)) or float(area_control.get("duration", 0.0)) <= 0.0:
				errors.append("Area-control facility lacks valid control rules in %s" % definition_id)
			if "Ownable" not in definition.get("capabilities", []) or "Interactable" not in definition.get("capabilities", []):
				errors.append("Capturable facility lacks Ownable/Interactable capabilities in %s" % definition_id)
		if "BerthingService" in operation_modes:
			var berth: Dictionary = definition.get("berthing_service", {})
			if str(berth.get("service_type", "")) not in ["Supply", "Repair"] or float(berth.get("duration", 0.0)) <= 0.0 or int(berth.get("berth_count", 0)) <= 0 or float(berth.get("max_entry_speed", -1.0)) < 0.0 or float(berth.get("heading_tolerance_degrees", -1.0)) < 0.0:
				errors.append("Berthing-service facility lacks valid service rules in %s" % definition_id)
			if not berth.has("interrupt_on_leave") or not berth.has("interrupt_on_facility_damage") or str(berth.get("progress_on_interrupt", "")) not in ["Reset"]:
				errors.append("Berthing-service facility lacks interruption rules in %s" % definition_id)
			if str(berth.get("service_type", "")) == "Repair" and (str(berth.get("berth_state", "")) != "Docked" or str(berth.get("dock_position_policy", "")) != "EntryPosition" or not bool(berth.get("hold_while_docked", false)) or not bool(berth.get("interrupt_on_move_order", false)) or float(berth.get("interrupt_on_heavy_damage_ratio", 0.0)) <= 0.0 or not bool(berth.get("interrupt_on_facility_unavailable", false)) or not bool(berth.get("interrupt_on_sink", false)) or not bool(berth.get("interrupt_on_undock", false))):
				errors.append("Repair berth lacks docking or interruption rules in %s" % definition_id)
		if "RemoteCommand" in operation_modes and str(definition.get("remote_command", {}).get("command_type", "")).is_empty():
			errors.append("Remote-command facility lacks command rules in %s" % definition_id)
		var remote_command: Dictionary = definition.get("remote_command", {})
		if str(remote_command.get("command_type", "")) == "MineDeployment":
			for field in ["control_radius", "area_side_length", "duration", "mine_count", "cooldown", "charges", "mine_trigger_radius"]:
				if float(remote_command.get(field, 0.0)) <= 0.0: errors.append("Mine deployment %s must be positive in %s" % [field, definition_id])
			_validate_mine_references(remote_command, definition_id)
		if "AutomaticOperation" in operation_modes and definition.get("automatic_operation", {}).get("capability_ids", []).is_empty():
			errors.append("Automatic facility lacks capability rules in %s" % definition_id)
		if "ObservationSource" in definition.get("capabilities", []):
			var observation_rules: Dictionary = definition.get("observation_rules", {})
			if str(observation_rules.get("contact_type", "")) != "Optical" or not observation_rules.has("weather_affected") or not observation_rules.has("time_affected") or not observation_rules.has("local_visibility_affected") or not observation_rules.has("line_of_sight_required") or float(definition.get("observation_range", 0.0)) <= 0.0:
				errors.append("Optical observation facility lacks explicit sensor rules in %s" % definition_id)
		if "SensorSource" in definition.get("capabilities", []):
			var radar_rules: Dictionary = definition.get("radar_rules", {})
			if str(radar_rules.get("contact_type", "")) != "Radar" or float(radar_rules.get("detection_range", 0.0)) <= 0.0 or bool(radar_rules.get("weather_affected", true)) or bool(radar_rules.get("time_affected", true)) or bool(radar_rules.get("local_visibility_affected", true)) or bool(radar_rules.get("line_of_sight_required", true)) or str(radar_rules.get("contact_accuracy", "")) != "ExactPosition" or str(radar_rules.get("stealth_break_policy", "")) != "ExplicitStateOnly":
				errors.append("Radar facility lacks independent sensor rules in %s" % definition_id)
			var activation_rules: Dictionary = definition.get("activation_rules", {})
			if str(activation_rules.get("type", "")) != "ScenarioEvent" or str(activation_rules.get("event_id", "")).is_empty():
				errors.append("Radar facility lacks scenario activation rules in %s" % definition_id)
		if "CombatDisposition" in operation_modes:
			var disposition: Dictionary = definition.get("combat_disposition", {})
			for field in ["suppressible", "destroyable", "silentable", "damage_floor_ratio"]:
				if not disposition.has(field): errors.append("Combat facility lacks %s in %s" % [field, definition_id])
			var floor_ratio := float(disposition.get("damage_floor_ratio", -1.0))
			if bool(disposition.get("destroyable", true)) and not is_zero_approx(floor_ratio):
				errors.append("Destroyable facility must use zero damage floor in %s" % definition_id)
			if not bool(disposition.get("destroyable", true)) and (floor_ratio <= 0.0 or floor_ratio >= 1.0):
				errors.append("Non-destroyable facility requires a damage floor between zero and one in %s" % definition_id)
			if bool(disposition.get("suppressible", false)) != ("Suppressible" in definition.get("capabilities", [])):
				errors.append("Suppressible capability and disposition disagree in %s" % definition_id)
		if "Suppressible" in definition.get("capabilities", []) and (float(definition.get("suppression_damage_threshold", 0.0)) <= 0.0 or float(definition.get("suppression_duration", 0.0)) <= 0.0):
			errors.append("Suppressible facility lacks positive suppression rules in %s" % definition_id)
		var weapon_ids: Array = definition.get("weapon_ids", [])
		if not str(definition.get("weapon_id", "")).is_empty(): weapon_ids.append(str(definition["weapon_id"]))
		var mount_reference: Dictionary = definition.get("weapon_mount_reference", {})
		weapon_ids.append_array(mount_reference.get("weapon_ids", []))
		if not mount_reference.is_empty() and (int(mount_reference.get("mount_count", 0)) <= 0 or int(mount_reference.get("shots_per_mount", 0)) <= 0 or str(mount_reference.get("default_ammo_type", "")) not in ["AP", "HE"]):
			errors.append("Facility weapon mount reference is invalid in %s" % definition_id)
		var referenced_ammo_types: Array[String] = []
		for weapon_id in weapon_ids:
			var referenced_weapon: Dictionary = get_definition("weapons", str(weapon_id))
			if referenced_weapon.is_empty(): errors.append("Facility references missing weapon %s in %s" % [weapon_id, definition_id])
			elif not str(referenced_weapon.get("ammo_type", "")).is_empty(): referenced_ammo_types.append(str(referenced_weapon.get("ammo_type", "")))
		if not mount_reference.is_empty() and str(mount_reference.get("default_ammo_type", "")) not in referenced_ammo_types:
			errors.append("Facility default ammo is not provided by its weapon references in %s" % definition_id)
		var profiles: Dictionary = definition.get("initial_state_profiles", {})
		for profile_id in profiles:
			var profile: Dictionary = profiles[profile_id]
			if str(profile.get("operation_state", "")) not in ["Dormant", "Active"] or str(profile.get("control_policy", "")) not in ["LockedWhileActive", "ActivateOwnerOnly", "SeizeOrActivate"] or str(profile.get("faction_id", "")).is_empty():
				errors.append("Facility initial state profile %s is invalid in %s" % [profile_id, definition_id])
		for mission_id in definition.get("support_mission_ids", []):
			if get_definition("facilities", str(mission_id)).is_empty(): errors.append("Facility references missing support mission %s in %s" % [mission_id, definition_id])
	elif definition_type == "SupportMissionDefinition":
		if definition.get("mission_type", "") not in ["Reconnaissance", "FighterPatrol", "Airstrike"]:
			errors.append("Unsupported support mission type in %s" % definition_id)
		for field in ["cooldown", "arrival_time", "charges", "max_range", "effect_radius"]:
			if float(definition.get(field, 0.0)) <= 0.0: errors.append("Support mission %s must be positive in %s" % [field, definition_id])
		if float(definition.get("launch_time", -1.0)) < 0.0 or float(definition.get("launch_time", 0.0)) >= float(definition.get("arrival_time", 0.0)):
			errors.append("Support mission launch_time must precede arrival in %s" % definition_id)
		var state_policy: Dictionary = definition.get("facility_state_policy", {})
		if str(state_policy.get("Preparing", "")) not in ["Cancel", "Continue"] or str(state_policy.get("EnRoute", "")) not in ["Cancel", "Continue"]:
			errors.append("Support mission lacks valid facility state policy in %s" % definition_id)
		var support_weapon_id := str(definition.get("weapon_id", ""))
		if definition.get("mission_type", "") == "Airstrike" and get_definition("weapons", support_weapon_id).is_empty():
			errors.append("Airstrike mission references missing weapon in %s" % definition_id)
	elif definition_type == "FacilityLayout":
		var terrain: Dictionary = get_definition("terrain", str(definition.get("terrain_definition_id", "")))
		if terrain.is_empty():
			errors.append("Facility layout references missing terrain in %s" % definition_id)
		var anchor_ids := {}
		for anchor in terrain.get("facility_anchors", []): anchor_ids[str(anchor.get("id", ""))] = true
		var placement_ids := {}
		for placement in definition.get("placements", []): placement_ids[str(placement.get("id", ""))] = true
		for placement in definition.get("placements", []):
			var placed_definition: Dictionary = get_definition("facilities", str(placement.get("definition_id", "")))
			if placed_definition.is_empty():
				errors.append("Facility layout references missing facility in %s" % definition_id)
			if not anchor_ids.has(str(placement.get("anchor_id", ""))):
				errors.append("Facility layout references missing anchor in %s" % definition_id)
			var initial_profile_id := str(placement.get("initial_state_profile", ""))
			var initial_profile: Dictionary = placed_definition.get("initial_state_profiles", {}).get(initial_profile_id, {})
			if not initial_profile_id.is_empty() and initial_profile.is_empty():
				errors.append("Facility layout references missing initial state profile in %s" % definition_id)
			if str(placement.get("operation_state", initial_profile.get("operation_state", ""))) not in ["Dormant", "Active"]:
				errors.append("Facility placement has invalid initial operation state in %s" % definition_id)
			var all_dependencies: Array = placement.get("requires_all_active", []) + placement.get("requires_any_active", [])
			var seen_dependencies := {}
			for dependency_id in all_dependencies:
				if not placement_ids.has(str(dependency_id)):
					errors.append("Facility layout references missing dependency in %s" % definition_id)
				if str(dependency_id) == str(placement.get("id", "")) or seen_dependencies.has(str(dependency_id)):
					errors.append("Facility layout has self or duplicate dependency in %s" % definition_id)
				seen_dependencies[str(dependency_id)] = true
			if not all_dependencies.is_empty() and not placement.get("dependency_rules", {}).has("requires_matching_faction"):
				errors.append("Facility dependency lacks faction rule in %s" % definition_id)
		var handover_event_ids := {}
		for rule in definition.get("system_handover_rules", []):
			var event_id := str(rule.get("event_id", ""))
			var control_id := str(rule.get("control_facility_id", ""))
			var facility_ids: Array = rule.get("facility_ids", [])
			if event_id.is_empty() or handover_event_ids.has(event_id) or not placement_ids.has(control_id) or facility_ids.is_empty():
				errors.append("Facility layout has invalid system handover rule in %s" % definition_id)
			handover_event_ids[event_id] = true
			for facility_id in facility_ids:
				if not placement_ids.has(str(facility_id)) or str(facility_id) == control_id:
					errors.append("Facility handover references invalid member in %s" % definition_id)
	elif definition_type == "MinefieldDefinition":
		if get_definition("terrain", str(definition.get("terrain_definition_id", ""))).is_empty():
			errors.append("Minefield references missing terrain in %s" % definition_id)
		if definition.get("polygon", []).size() < 3:
			errors.append("Minefield has invalid polygon in %s" % definition_id)
		for safe_channel in definition.get("safe_channels", []):
			if safe_channel.size() < 3:
				errors.append("Minefield has invalid safe channel in %s" % definition_id)
		var controller_id := str(definition.get("controller_facility_id", ""))
		if not controller_id.is_empty() and not _facility_placement_exists(controller_id):
			errors.append("Minefield references missing controller in %s" % definition_id)
		_validate_mine_references(definition, definition_id)


func _validate_mine_references(source: Dictionary, definition_id: String) -> void:
	var detection_reference: Dictionary = source.get("detection_reference", {})
	var length_ship: Dictionary = get_definition("ships", str(detection_reference.get("ship_id", "")))
	if length_ship.is_empty() or float(detection_reference.get("full_length_multiplier", 0.0)) <= 0.0:
		errors.append("Mine detection reference is invalid in %s" % definition_id)
	var damage_reference: Dictionary = source.get("damage_reference", {})
	var damage_ship := str(damage_reference.get("ship_id", ""))
	var damage_weapon := str(damage_reference.get("weapon_id", ""))
	if get_definition("ships", damage_ship).is_empty() or get_definition("weapons", damage_weapon).is_empty() or damage_weapon not in get_definition("ships", damage_ship).get("weapon_mounts", []):
		errors.append("Mine damage reference is invalid in %s" % definition_id)


func _facility_placement_exists(placement_id: String) -> bool:
	for definition in all("facilities"):
		if definition.get("definition_type", "") != "FacilityLayout": continue
		for placement in definition.get("placements", []):
			if str(placement.get("id", "")) == placement_id: return true
	return false


func _weapon_group_exists(weapon_group_id: String) -> bool:
	for weapon in all("weapons"):
		if str(weapon.get("weapon_group_id", "")) == weapon_group_id:
			return true
	return false


func _resource_exists(path: String) -> bool:
	var resource_path := path
	if resource_path.begins_with("assets/") or resource_path.begins_with("data/"):
		resource_path = "res://%s" % resource_path
	return FileAccess.file_exists(resource_path)
