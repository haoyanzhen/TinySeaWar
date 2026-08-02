extends SceneTree

const OceanSurface = preload("res://scripts/presentation/battle/ocean_surface.gd")
const TerrainView = preload("res://scripts/presentation/battle/terrain_view.gd")

const OCEAN_SHADER_PATH := "res://assets/environments/ocean/common/ocean_surface.gdshader"
const TERRAIN_TEMPLATE_PATH := "res://data/terrain/terrain_templates.json"
const DEFAULT_OUTPUT := "res://artifacts/scene_review/runtime_full_map_view.png"
const DEFAULT_SHIPS := [
	{"ship_id": "ship.yamato", "position": Vector2(1180.0, 1728.0), "heading_degrees": 0.0},
	{"ship_id": "ship.aurora", "position": Vector2(820.0, 1370.0), "heading_degrees": 0.0},
	{"ship_id": "ship.shimakaze", "position": Vector2(820.0, 2086.0), "heading_degrees": 0.0},
]

var output_path := DEFAULT_OUTPUT
var output_size := Vector2i(3840, 2160)
var map_size := Vector2(6144.0, 3456.0)
var palette_id := "clear_day"
var terrain_template_id := "terrain.template.scattered_islands"
var terrain_position := Vector2(3900.0, 1728.0)
var terrain_scale := Vector2(2.43, 2.43)
var terrain_rotation_degrees := 0.0
var ship_specs: Array = DEFAULT_SHIPS.duplicate(true)
var help_requested := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var parse_error := _parse_arguments()
	if not parse_error.is_empty():
		push_error(parse_error)
		quit(2)
		return
	if help_requested:
		quit(0)
		return
	await process_frame
	var data_registry = root.get_node_or_null("DataRegistry")
	if data_registry == null or data_registry.registry == null or data_registry.assets == null:
		push_error("DataRegistry is unavailable; run this tool with --path pointing at the TinySeaWar project")
		quit(2)
		return
	var terrain_template := _terrain_template(terrain_template_id)
	if terrain_template.is_empty():
		push_error("Unknown terrain template: %s" % terrain_template_id)
		quit(2)
		return

	var viewport := SubViewport.new()
	viewport.name = "RuntimeFullMapReviewViewport"
	viewport.size = output_size
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	var world := Node2D.new()
	world.name = "RuntimeVisualWorld"
	var world_scale := minf(
		float(output_size.x) / map_size.x,
		float(output_size.y) / map_size.y
	)
	world.scale = Vector2.ONE * world_scale
	world.position = (Vector2(output_size) - map_size * world_scale) * 0.5
	viewport.add_child(world)

	var ocean := OceanSurface.new()
	ocean.name = "OceanSurface"
	ocean.z_index = -100
	var ocean_material := ShaderMaterial.new()
	ocean_material.shader = load(OCEAN_SHADER_PATH)
	ocean.material = ocean_material
	world.add_child(ocean)
	ocean.configure(map_size, palette_id)
	ocean.set_animation_paused(true)

	var terrain := TerrainView.new()
	terrain.name = "TerrainView"
	terrain.z_index = -60
	world.add_child(terrain)
	terrain.configure(_synthetic_terrain_map(terrain_template), data_registry.assets)

	var units := Node2D.new()
	units.name = "RuntimeUnitViews"
	world.add_child(units)
	var ship_unit_view_script: GDScript = load("res://scripts/presentation/battle/ship_unit_view.gd")
	if ship_unit_view_script == null:
		push_error("Could not load ShipUnitView after DataRegistry initialization")
		viewport.queue_free()
		quit(2)
		return
	for index in range(ship_specs.size()):
		var spec: Dictionary = ship_specs[index]
		var ship_id := str(spec.get("ship_id", ""))
		var ship_definition: Dictionary = data_registry.registry.get_definition("ships", ship_id)
		if ship_definition.is_empty():
			push_error("Unknown ship definition: %s" % ship_id)
			viewport.queue_free()
			quit(2)
			return
		var unit_view: Node2D = ship_unit_view_script.new()
		unit_view.name = ship_id.trim_prefix("ship.")
		units.add_child(unit_view)
		unit_view.configure(_ship_snapshot(ship_definition, spec, index))

	await process_frame
	await process_frame
	RenderingServer.force_draw(false)
	await process_frame
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("The active renderer did not return a viewport image; run without --headless")
		viewport.queue_free()
		quit(3)
		return
	var resolved_output := ProjectSettings.globalize_path(output_path)
	DirAccess.make_dir_recursive_absolute(resolved_output.get_base_dir())
	var save_error := image.save_png(resolved_output)
	viewport.queue_free()
	if save_error != OK:
		push_error("Could not save runtime full-map view: %s" % resolved_output)
		quit(4)
		return
	print("SAVED: %s" % resolved_output)
	print("MAP: %.0fx%.0f -> %dx%d (%.6f px/world unit)" % [
		map_size.x, map_size.y, output_size.x, output_size.y, world_scale,
	])
	print("VISUALS: palette=%s terrain=%s scale=%.3fx%.3f ships=%d" % [
		palette_id, terrain_template_id, terrain_scale.x, terrain_scale.y, ship_specs.size(),
	])
	quit(0)


func _parse_arguments() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument == "--help":
			print("Usage: godot --path . --script tools/scene_review/render_runtime_full_map_view.gd -- [options]")
			print("  --output=res://artifacts/scene_review/runtime_full_map_view.png")
			print("  --size=3840x2160 --map-size=6144x3456 --palette=clear_day")
			print("  --terrain-template=terrain.template.scattered_islands")
			print("  --terrain-position=3900,1728 --terrain-scale=2.43,2.43 --terrain-rotation=0")
			print("  --ships=ship.yamato@1180,1728,0;ship.aurora@820,1370,0;ship.shimakaze@820,2086,0")
			help_requested = true
			return ""
		if argument.begins_with("--output="):
			output_path = argument.trim_prefix("--output=")
		elif argument.begins_with("--size="):
			var value := _parse_size(argument.trim_prefix("--size="))
			if value == Vector2i.ZERO:
				return "Invalid --size; expected WIDTHxHEIGHT"
			output_size = value
		elif argument.begins_with("--map-size="):
			var value := _parse_pair(argument.trim_prefix("--map-size="), "x")
			if value == Vector2.ZERO:
				return "Invalid --map-size; expected WIDTHxHEIGHT"
			map_size = value
		elif argument.begins_with("--palette="):
			palette_id = argument.trim_prefix("--palette=")
		elif argument.begins_with("--terrain-template="):
			terrain_template_id = argument.trim_prefix("--terrain-template=")
		elif argument.begins_with("--terrain-position="):
			terrain_position = _parse_pair(argument.trim_prefix("--terrain-position="), ",")
		elif argument.begins_with("--terrain-scale="):
			terrain_scale = _parse_pair(argument.trim_prefix("--terrain-scale="), ",")
		elif argument.begins_with("--terrain-rotation="):
			terrain_rotation_degrees = float(argument.trim_prefix("--terrain-rotation="))
		elif argument.begins_with("--ships="):
			var parsed_ships := _parse_ships(argument.trim_prefix("--ships="))
			if parsed_ships.is_empty():
				return "Invalid --ships; expected ship.id@X,Y,HEADING entries separated by semicolons"
			ship_specs = parsed_ships
	if output_size.x <= 0 or output_size.y <= 0:
		return "Output size must be positive"
	if map_size.x <= 0.0 or map_size.y <= 0.0:
		return "Map size must be positive"
	if terrain_scale.x <= 0.0 or terrain_scale.y <= 0.0:
		return "Terrain scale must be positive"
	for spec in ship_specs:
		var position: Vector2 = spec.get("position", Vector2.INF)
		if position.x < 0.0 or position.y < 0.0 or position.x > map_size.x or position.y > map_size.y:
			return "Ship %s lies outside the map" % spec.get("ship_id", "")
	return ""


func _parse_size(raw: String) -> Vector2i:
	var pair := _parse_pair(raw, "x")
	return Vector2i(roundi(pair.x), roundi(pair.y))


func _parse_pair(raw: String, separator: String) -> Vector2:
	var parts := raw.split(separator)
	if parts.size() != 2 or not parts[0].is_valid_float() or not parts[1].is_valid_float():
		return Vector2.ZERO
	return Vector2(float(parts[0]), float(parts[1]))


func _parse_ships(raw: String) -> Array:
	var result: Array = []
	for entry in raw.split(";", false):
		var sides := entry.split("@", false, 1)
		if sides.size() != 2:
			return []
		var values := sides[1].split(",")
		if values.size() != 3:
			return []
		if not values[0].is_valid_float() or not values[1].is_valid_float() or not values[2].is_valid_float():
			return []
		result.append({
			"ship_id": str(sides[0]),
			"position": Vector2(float(values[0]), float(values[1])),
			"heading_degrees": float(values[2]),
		})
	return result


func _terrain_template(template_id: String) -> Dictionary:
	var file := FileAccess.open(TERRAIN_TEMPLATE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var document = JSON.parse_string(file.get_as_text())
	if typeof(document) != TYPE_DICTIONARY:
		return {}
	for definition in document.get("definitions", []):
		if str(definition.get("id", "")) == template_id:
			return definition
	return {}


func _synthetic_terrain_map(template: Dictionary) -> Dictionary:
	return {
		"id": "terrain.review.synthetic",
		"regions": [],
		"visual_regions": [],
		"visual_instances": [{
			"id": "runtime_review_land",
			"asset_id": str(template.get("asset_id", "")),
			"texture": str(template.get("texture", "")),
			"position": terrain_position,
			"scale": terrain_scale,
			"rotation_degrees": terrain_rotation_degrees,
			"local_size": template.get("local_size", [1024.0, 1024.0]),
		}],
	}


func _ship_snapshot(ship: Dictionary, spec: Dictionary, index: int) -> Dictionary:
	var half_extents: Array = ship.get("collision_half_extents", [54.0, 22.0])
	var maximum_hp := float(ship.get("max_hp", 1.0))
	return {
		"entity_id": "review.unit.%02d" % (index + 1),
		"definition_id": str(ship.get("id", "")),
		"display_name": str(ship.get("display_name", ship.get("id", ""))),
		"faction_id": "player",
		"position": spec.get("position", Vector2.ZERO),
		"heading": deg_to_rad(float(spec.get("heading_degrees", 0.0))),
		"collision_radius": float(ship.get("collision_radius", 22.0)),
		"collision_half_extents": Vector2(float(half_extents[0]), float(half_extents[1])),
		"current_hp": maximum_hp,
		"max_hp": maximum_hp,
		"life_state": "Alive",
		"is_flagship": index == 0,
	}
