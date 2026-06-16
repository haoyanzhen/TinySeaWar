extends RefCounted

const CATEGORY_PATHS := {
	"ships": "res://data/ships",
	"weapons": "res://data/weapons",
	"projectiles": "res://data/projectiles",
	"skills": "res://data/skills",
	"formulas": "res://data/formulas",
	"levels": "res://data/levels",
}

var definitions := {}
var errors: Array[String] = []


func load_all() -> bool:
	definitions.clear()
	errors.clear()
	var global_ids := {}
	for category in CATEGORY_PATHS:
		definitions[category] = {}
		var files := _json_files(CATEGORY_PATHS[category])
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
	for projectile in all("projectiles"):
		if projectile.get("behavior", "") not in ["Straight", "DelayedImpact"]:
			errors.append("Unsupported projectile behavior in %s" % projectile.get("id", "?"))
		if float(projectile.get("collision_radius", 0.0)) <= 0.0:
			errors.append("Projectile radius must be positive in %s" % projectile.get("id", "?"))
	for level in all("levels"):
		_validate_level(level)


func _validate_ship(ship: Dictionary) -> void:
	var ship_id := str(ship.get("id", "?"))
	if ship.get("ship_class", "") not in ["Destroyer", "LightCruiser", "HeavyCruiser", "Battleship", "Carrier", "Submarine"]:
		errors.append("Invalid ship class in %s" % ship_id)
	if int(ship.get("level", 0)) < 1 or int(ship.get("level", 0)) > 3:
		errors.append("Invalid level in %s" % ship_id)
	for field in ["max_hp", "speed", "turn_speed", "detection_range", "concealment_distance", "collision_radius"]:
		if float(ship.get(field, 0.0)) <= 0.0:
			errors.append("%s must be positive in %s" % [field, ship_id])
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
	if float(weapon.get("minimum_range", 0.0)) > float(weapon.get("range", 0.0)):
		errors.append("Invalid range band in %s" % weapon_id)
	if float(weapon.get("fire_arc_degrees", 0.0)) <= 0.0 or float(weapon.get("fire_arc_degrees", 0.0)) > 360.0:
		errors.append("Invalid fire arc in %s" % weapon_id)
	if get_definition("projectiles", str(weapon.get("projectile_id", ""))).is_empty():
		errors.append("Missing projectile referenced by %s" % weapon_id)
	if get_definition("formulas", str(weapon.get("formula_id", ""))).is_empty():
		errors.append("Missing formula referenced by %s" % weapon_id)


func _validate_level(level: Dictionary) -> void:
	var level_id := str(level.get("id", "?"))
	for fleet_name in ["player_fleet", "enemy_fleet"]:
		var fleet: Array = level.get(fleet_name, [])
		var flagship_count := 0
		var entity_ids := {}
		for member in fleet:
			if get_definition("ships", str(member.get("ship_id", ""))).is_empty():
				errors.append("Missing ship in %s/%s" % [level_id, fleet_name])
			var entity_id := str(member.get("entity_id", ""))
			if entity_id.is_empty() or entity_ids.has(entity_id):
				errors.append("Invalid or duplicate entity id in %s/%s" % [level_id, fleet_name])
			entity_ids[entity_id] = true
			if bool(member.get("is_flagship", false)):
				flagship_count += 1
		if flagship_count != 1:
			errors.append("%s/%s must contain exactly one flagship" % [level_id, fleet_name])
