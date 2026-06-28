#!/usr/bin/env python3
"""Validate reviewed terrain, references, spawns, facilities, and reachability."""

from __future__ import annotations

import argparse
import collections
import math
import sys

from terrain_geometry import circle_clear, point_in_polygon, polygon_area, polygon_self_intersections, read_json, segments_intersect, signed_area

BLOCK_MASKS = {"ShipMovement", "TorpedoTravel", "ShellTravel", "SurfaceOpticalLineOfSight"}
REGION_TYPES = {"DeepWater", "CoastalWater", "ShallowWater", "ReefOrSandbar", "NavigationChannel"}


def _definitions(path: str) -> dict[str, dict]:
	return {item["id"]: item for item in read_json(path).get("definitions", [])}


def _validate_polygon(label: str, polygon: list, map_size: list[float] | None, errors: list[str]) -> None:
	if len(polygon) < 3:
		errors.append("%s has fewer than 3 vertices" % label)
		return
	if polygon_area(polygon) < 4.0:
		errors.append("%s is degenerate" % label)
	if signed_area(polygon) >= 0.0:
		errors.append("%s must use clockwise winding" % label)
	if polygon_self_intersections(polygon):
		errors.append("%s self-intersects" % label)
	for index, point in enumerate(polygon):
		previous = polygon[index - 1]
		if point == previous:
			errors.append("%s has duplicate consecutive vertices" % label)
		if map_size and not (0.0 <= float(point[0]) <= float(map_size[0]) and 0.0 <= float(point[1]) <= float(map_size[1])):
			errors.append("%s is outside map bounds" % label)


def _has_dependency_cycle(facilities: dict[str, dict]) -> bool:
	graph = {key: set(value.get("facility_dependencies", [])) for key, value in facilities.items() if value.get("definition_type") == "FacilityDefinition"}
	visiting, visited = set(), set()
	def visit(node: str) -> bool:
		if node in visiting:
			return True
		if node in visited:
			return False
		visiting.add(node)
		if any(dependency in graph and visit(dependency) for dependency in sorted(graph.get(node, []))):
			return True
		visiting.remove(node)
		visited.add(node)
		return False
	return any(visit(node) for node in sorted(graph))


def _graph_has_cycle(graph: dict[str, set[str]]) -> bool:
	visiting, visited = set(), set()
	def visit(node: str) -> bool:
		if node in visiting:
			return True
		if node in visited:
			return False
		visiting.add(node)
		if any(dependency in graph and visit(dependency) for dependency in sorted(graph.get(node, []))):
			return True
		visiting.remove(node)
		visited.add(node)
		return False
	return any(visit(node) for node in sorted(graph))


def _reachable(profile: dict, start: list[float], end: list[float]) -> bool:
	nodes = profile.get("nodes", [])
	if not nodes:
		return False
	by_id = {node["id"]: node for node in nodes}
	start_node = min(nodes, key=lambda node: (node["position"][0] - start[0]) ** 2 + (node["position"][1] - start[1]) ** 2)
	end_node = min(nodes, key=lambda node: (node["position"][0] - end[0]) ** 2 + (node["position"][1] - end[1]) ** 2)
	queue = collections.deque([start_node["id"]])
	seen = {start_node["id"]}
	while queue:
		current = queue.popleft()
		if current == end_node["id"]:
			return True
		for neighbor in by_id[current].get("neighbors", []):
			if neighbor not in seen:
				seen.add(neighbor)
				queue.append(neighbor)
	return False


def _segment_blocked(start: list[float], end: list[float], obstacles: list[dict]) -> bool:
	for obstacle in obstacles:
		polygon = obstacle.get("polygon", [])
		if point_in_polygon(start, polygon) or point_in_polygon(end, polygon):
			return True
		for index, point in enumerate(polygon):
			if segments_intersect(start, end, point, polygon[(index + 1) % len(polygon)]):
				return True
	return False


def _movement_allowed(position: list[float], tags: list[str], regions: list[dict]) -> bool:
	matches = [region for region in regions if point_in_polygon(position, region.get("polygon", []))]
	if not matches:
		return True
	region = sorted(matches, key=lambda item: (-int(item.get("priority", 0)), item.get("id", "")))[0]
	if region.get("region_type") == "ShallowWater":
		return "ShallowDraft" in tags
	if region.get("region_type") == "ReefOrSandbar":
		return "ReefCapable" in tags
	return True


def validate(args: argparse.Namespace) -> list[str]:
	errors: list[str] = []
	skip_navigation = bool(getattr(args, "skip_navigation", False))
	templates = _definitions(args.templates)
	terrains = _definitions(args.terrain)
	navigation = _definitions(args.navigation)
	facilities = _definitions(args.facilities)
	minefields = _definitions(args.minefields)
	environment = _definitions(args.environment)
	for template_id, template in sorted(templates.items()):
		for obstacle in template.get("obstacles", []):
			_validate_polygon("%s/%s" % (template_id, obstacle["id"]), obstacle.get("polygon", []), template.get("local_size"), errors)
			unknown = set(obstacle.get("block_mask", [])) - BLOCK_MASKS
			if unknown:
				errors.append("%s uses unknown block mask %s" % (obstacle["id"], sorted(unknown)))
		for region in template.get("regions", []):
			_validate_polygon("%s/%s" % (template_id, region["id"]), region.get("polygon", []), template.get("local_size"), errors)
			if region.get("region_type") not in REGION_TYPES:
				errors.append("%s uses unknown region type" % region["id"])
		for visual_region in template.get("visual_regions", []):
			_validate_polygon("%s/%s" % (template_id, visual_region["id"]), visual_region.get("polygon", []), template.get("local_size"), errors)
			if not str(visual_region.get("asset_semantic", "")):
				errors.append("%s visual region has no asset semantic" % visual_region["id"])
	for terrain_id, terrain in sorted(terrains.items()):
		map_size = terrain.get("map_size", [])
		if len(map_size) != 2 or min(map_size) <= 0:
			errors.append("%s has invalid map size" % terrain_id)
		obstacles = terrain.get("obstacles", [])
		obstacle_ids = {item["id"] for item in obstacles}
		if len(obstacle_ids) != len(obstacles):
			errors.append("%s has duplicate obstacle ids" % terrain_id)
		for obstacle in obstacles:
			_validate_polygon("%s/%s" % (terrain_id, obstacle["id"]), obstacle.get("polygon", []), map_size, errors)
		for region in terrain.get("regions", []):
			_validate_polygon("%s/%s" % (terrain_id, region["id"]), region.get("polygon", []), map_size, errors)
		for visual_region in terrain.get("visual_regions", []):
			_validate_polygon("%s/%s" % (terrain_id, visual_region["id"]), visual_region.get("polygon", []), map_size, errors)
		for spawn in terrain.get("spawn_points", []):
			position, radius = spawn.get("position", []), float(spawn.get("radius", 0.0))
			if len(position) != 2 or not circle_clear(position, radius, obstacles):
				errors.append("%s spawn %s intersects hard terrain" % (terrain_id, spawn.get("id", "?")))
		for anchor in terrain.get("facility_anchors", []):
			_validate_polygon("%s/%s interaction" % (terrain_id, anchor["id"]), anchor.get("interaction_water_polygon", []), map_size, errors)
			if anchor.get("shore_obstacle_id") not in obstacle_ids:
				errors.append("%s anchor %s references missing shore obstacle" % (terrain_id, anchor["id"]))
		if not skip_navigation and terrain.get("navigation_definition_id") not in navigation:
			errors.append("%s references missing navigation graph" % terrain_id)
		if terrain.get("facility_layout_id") and terrain.get("facility_layout_id") not in facilities:
			errors.append("%s references missing facility layout" % terrain_id)
		if terrain.get("environment_zone_set_id") and terrain.get("environment_zone_set_id") not in environment:
			errors.append("%s references missing environment zone set" % terrain_id)
		nav = navigation.get(terrain.get("navigation_definition_id"), {}) if not skip_navigation else {}
		profiles = nav.get("profiles", [])
		if profiles:
			spawns = terrain.get("spawn_points", [])
			for faction in sorted({spawn.get("faction_id") for spawn in spawns}):
				faction_spawns = [spawn for spawn in spawns if spawn.get("faction_id") == faction]
				for spawn in faction_spawns[1:]:
					if not _reachable(profiles[0], faction_spawns[0]["position"], spawn["position"]):
						errors.append("%s faction %s spawns are not mutually reachable" % (terrain_id, faction))
			player_spawns = [spawn for spawn in spawns if spawn.get("faction_id") == "player"]
			enemy_spawns = [spawn for spawn in spawns if spawn.get("faction_id") == "enemy"]
			for profile in profiles:
				profile_id = profile.get("id", "?")
				radius = float(profile.get("radius", 0.0))
				tags = profile.get("movement_tags", [])
				for node in profile.get("nodes", []):
					if not circle_clear(node["position"], radius, obstacles) or not _movement_allowed(node["position"], tags, terrain.get("regions", [])):
						errors.append("%s contains an invalid navigation node %s" % (profile_id, node.get("id", "?")))
						break
				if player_spawns and enemy_spawns and not _reachable(profile, player_spawns[0]["position"], enemy_spawns[0]["position"]):
					errors.append("%s cannot connect opposing fleet approach areas" % profile_id)
	if _has_dependency_cycle(facilities):
		errors.append("facility dependency graph contains a cycle")
	for definition_id, definition in facilities.items():
		if definition.get("definition_type") == "FacilityLayout":
			terrain = terrains.get(definition.get("terrain_definition_id"), {})
			anchors_by_id = {item["id"]: item for item in terrain.get("facility_anchors", [])}
			anchors = set(anchors_by_id)
			placements_by_id = {item["id"]: item for item in definition.get("placements", [])}
			dependency_graph = {item["id"]: set(item.get("requires_all_active", [])) | set(item.get("requires_any_active", [])) for item in definition.get("placements", [])}
			if _graph_has_cycle(dependency_graph):
				errors.append("%s facility placement dependency graph contains a cycle" % definition_id)
			for placement in definition.get("placements", []):
				if placement.get("definition_id") not in facilities:
					errors.append("%s references unknown facility definition" % definition_id)
				if placement.get("anchor_id") not in anchors:
					errors.append("%s references unknown facility anchor" % definition_id)
				for dependency in dependency_graph.get(placement["id"], set()):
					if dependency not in placements_by_id:
						errors.append("%s references unknown facility dependency %s" % (definition_id, dependency))
				facility_definition = facilities.get(placement.get("definition_id"), {})
				anchor = anchors_by_id.get(placement.get("anchor_id"), {})
				if "WeaponPlatform" in facility_definition.get("capabilities", []):
					muzzle = anchor.get("muzzle_position")
					if not muzzle or not circle_clear(muzzle, 2.0, terrain.get("obstacles", [])):
						errors.append("%s shore battery muzzle is blocked by its own terrain" % placement["id"])
					elif anchor.get("shore_obstacle_id"):
						own_obstacles = [obstacle for obstacle in terrain.get("obstacles", []) if obstacle.get("id") == anchor.get("shore_obstacle_id")]
						heading = float(anchor.get("heading", 0.0))
						blocked_rays = []
						for offset in (-15.0, 0.0, 15.0):
							angle = math.radians(heading + offset)
							target = [float(muzzle[0]) + math.cos(angle) * 420.0, float(muzzle[1]) + math.sin(angle) * 420.0]
							blocked_rays.append(_segment_blocked(muzzle, target, own_obstacles))
						if all(blocked_rays):
							errors.append("%s shore battery has no legal firing ray" % placement["id"])
				if "ObservationSource" in facility_definition.get("capabilities", []):
					observation_position = anchor.get("observation_position")
					if not observation_position or not circle_clear(observation_position, 2.0, terrain.get("obstacles", [])):
						errors.append("%s observation source has no clear authored observation position" % placement["id"])
				if not skip_navigation and "ServiceProvider" in facility_definition.get("capabilities", []):
					polygon = anchor.get("interaction_water_polygon", [])
					if polygon:
						center = [sum(float(point[0]) for point in polygon) / len(polygon), sum(float(point[1]) for point in polygon) / len(polygon)]
						navigation_definition = navigation.get(terrain.get("navigation_definition_id"), {})
						nodes = navigation_definition.get("profiles", [{}])[0].get("nodes", [])
						if not nodes or min((node["position"][0] - center[0]) ** 2 + (node["position"][1] - center[1]) ** 2 for node in nodes) > 220.0 ** 2:
							errors.append("%s has no legal water approach node" % placement["id"])
	for definition_id, definition in environment.items():
		if definition.get("definition_type") == "EnvironmentEffect" and definition.get("stack_rule") not in {"Highest", "Override", "VectorAdd"}:
			errors.append("%s has an unsupported environment overlap rule" % definition_id)
	effect_ids = {definition_id for definition_id, definition in environment.items() if definition.get("definition_type") == "EnvironmentEffect"}
	zone_set_map_sizes: dict[str, list[list[float]]] = collections.defaultdict(list)
	for terrain in terrains.values():
		zone_set_id = str(terrain.get("environment_zone_set_id", ""))
		if zone_set_id:
			zone_set_map_sizes[zone_set_id].append(terrain.get("map_size", []))
	for definition_id, definition in environment.items():
		if definition.get("definition_type") != "EnvironmentZoneSet":
			continue
		if definition_id not in zone_set_map_sizes:
			errors.append("%s is not referenced by a terrain map" % definition_id)
		zone_ids = [str(zone.get("id", "")) for zone in definition.get("zones", [])]
		if len(zone_ids) != len(set(zone_ids)):
			errors.append("%s contains duplicate zone ids" % definition_id)
		for zone in definition.get("zones", []):
			label = "%s/%s" % (definition_id, zone.get("id", "?"))
			if zone.get("effect_id") not in effect_ids:
				errors.append("%s references unknown environment effect" % label)
			position = zone.get("position", [0.0, 0.0])
			if not isinstance(position, list) or len(position) != 2:
				errors.append("%s has invalid position" % label)
				position = [0.0, 0.0]
			world_polygon = [[float(point[0]) + float(position[0]), float(point[1]) + float(position[1])] for point in zone.get("polygon", [])]
			for map_size in zone_set_map_sizes.get(definition_id, [None]):
				_validate_polygon(label, world_polygon, map_size, errors)
			heading = float(zone.get("heading", 0.0))
			drift_speed = float(zone.get("drift_speed", 0.0))
			duration = float(zone.get("duration", 0.0))
			intensity = float(zone.get("intensity", 1.0))
			if not 0.0 <= heading < 360.0:
				errors.append("%s heading must be in [0, 360)" % label)
			if drift_speed < 0.0 or duration < 0.0:
				errors.append("%s has negative drift speed or duration" % label)
			if not 0.0 <= intensity <= 1.0:
				errors.append("%s intensity must be in [0, 1]" % label)
			if not str(zone.get("phase", "")) or not str(zone.get("public_trend", "")):
				errors.append("%s must declare phase and public trend" % label)
			path = zone.get("drift_path", [])
			if path and len(path) < 2:
				errors.append("%s drift path needs at least two points" % label)
			if len(path) >= 2:
				if [float(path[0][0]), float(path[0][1])] != [0.0, 0.0]:
					errors.append("%s drift path must start at [0, 0]" % label)
				if all(math.hypot(float(path[index][0]) - float(path[index - 1][0]), float(path[index][1]) - float(path[index - 1][1])) <= 1.0e-6 for index in range(1, len(path))):
					errors.append("%s drift path has no length" % label)
				for offset in path:
					translated = [[point[0] + float(offset[0]), point[1] + float(offset[1])] for point in world_polygon]
					for map_size in zone_set_map_sizes.get(definition_id, []):
						if any(point[0] < 0.0 or point[1] < 0.0 or point[0] > float(map_size[0]) or point[1] > float(map_size[1]) for point in translated):
							errors.append("%s drift path leaves map bounds" % label)
							break
			elif drift_speed > 0.0:
				if duration <= 0.0:
					errors.append("%s drifts forever without a bounded path" % label)
				else:
					distance = drift_speed * duration
					offset = [math.cos(math.radians(heading)) * distance, math.sin(math.radians(heading)) * distance]
					translated = [[point[0] + offset[0], point[1] + offset[1]] for point in world_polygon]
					for map_size in zone_set_map_sizes.get(definition_id, []):
						if any(point[0] < 0.0 or point[1] < 0.0 or point[0] > float(map_size[0]) or point[1] > float(map_size[1]) for point in translated):
							errors.append("%s drift timeline leaves map bounds" % label)
							break
	placements_by_id = {
		placement["id"]: placement
		for definition in facilities.values() if definition.get("definition_type") == "FacilityLayout"
		for placement in definition.get("placements", [])
	}
	for definition_id, definition in minefields.items():
		if definition.get("definition_type") != "MinefieldDefinition":
			errors.append("%s has unsupported minefield definition type" % definition_id)
			continue
		terrain = terrains.get(definition.get("terrain_definition_id"), {})
		if not terrain:
			errors.append("%s references missing terrain map" % definition_id)
			continue
		_validate_polygon("%s polygon" % definition_id, definition.get("polygon", []), terrain.get("map_size"), errors)
		for index, safe_channel in enumerate(definition.get("safe_channels", []), 1):
			_validate_polygon("%s safe channel %d" % (definition_id, index), safe_channel, terrain.get("map_size"), errors)
		controller_id = str(definition.get("controller_facility_id", ""))
		if controller_id and controller_id not in placements_by_id:
			errors.append("%s references missing controller facility" % definition_id)
		if not str(definition.get("owner_faction_id", "")):
			errors.append("%s has no owner faction" % definition_id)
		if not isinstance(definition.get("known_by_faction", []), list):
			errors.append("%s has invalid faction visibility" % definition_id)
	return errors


def main() -> int:
	parser = argparse.ArgumentParser()
	parser.add_argument("--templates", default="data/terrain/terrain_templates.json")
	parser.add_argument("--terrain", default="data/terrain/terrain_definitions.json")
	parser.add_argument("--navigation", default="data/terrain/navigation_definitions.json")
	parser.add_argument("--facilities", default="data/facilities/facility_definitions.json")
	parser.add_argument("--minefields", default="data/facilities/minefield_definitions.json")
	parser.add_argument("--environment", default="data/environments/environment_zone_definitions.json")
	parser.add_argument("--skip-navigation", action="store_true")
	args = parser.parse_args()
	try:
		errors = validate(args)
	except (OSError, KeyError, TypeError, ValueError) as error:
		print("terrain validation failed: %s" % error, file=sys.stderr)
		return 1
	if errors:
		for error in errors:
			print(error, file=sys.stderr)
		return 1
	print("terrain validation passed")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
