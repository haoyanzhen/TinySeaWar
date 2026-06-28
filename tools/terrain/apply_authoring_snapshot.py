#!/usr/bin/env python3
"""Apply a reviewed Godot terrain snapshot back to canonical authoring data."""

from __future__ import annotations

import argparse
import copy
import sys
from pathlib import Path

from terrain_geometry import polygon_area, polygon_self_intersections, read_json, signed_area, write_json

ROOT = Path(__file__).resolve().parents[2]
REGION_TYPES = {"DeepWater", "CoastalWater", "ShallowWater", "ReefOrSandbar", "NavigationChannel"}


def _clockwise(points: list) -> list:
	result = copy.deepcopy(points)
	if signed_area(result) > 0.0:
		result.reverse()
	return result


def _path(value: str) -> Path:
	path = Path(value)
	return path if path.is_absolute() else ROOT / path


def _replace_definition(document: dict, definition_id: str, replacement: dict) -> None:
	for index, definition in enumerate(document.get("definitions", [])):
		if definition.get("id") == definition_id:
			document["definitions"][index] = replacement
			return
	raise ValueError("unknown definition %s" % definition_id)


def _has_cycle(graph: dict[str, set[str]]) -> bool:
	visiting: set[str] = set()
	visited: set[str] = set()
	def visit(node: str) -> bool:
		if node in visiting:
			return True
		if node in visited:
			return False
		visiting.add(node)
		if any(visit(dependency) for dependency in sorted(graph.get(node, set()))):
			return True
		visiting.remove(node)
		visited.add(node)
		return False
	return any(visit(node) for node in sorted(graph))


def _validate_snapshot(snapshot: dict) -> None:
	polygon_ids = [str(item.get("id", "")) for item in snapshot.get("polygons", [])]
	if "" in polygon_ids or len(polygon_ids) != len(set(polygon_ids)):
		raise ValueError("snapshot contains missing or duplicate polygon ids")
	for item in snapshot.get("polygons", []):
		polygon = item.get("polygon", [])
		if len(polygon) < 3 or polygon_area(polygon) < 4.0 or polygon_self_intersections(polygon):
			raise ValueError("snapshot contains invalid polygon %s" % item.get("id", "?"))
	for anchor in snapshot.get("anchors", []):
		polygon = anchor.get("interaction_water_polygon", [])
		if len(polygon) < 3 or polygon_self_intersections(polygon):
			raise ValueError("snapshot contains invalid facility interaction %s" % anchor.get("id", "?"))
	placements = snapshot.get("facilities", [])
	placement_ids = [str(item.get("id", "")) for item in placements]
	if "" in placement_ids or len(placement_ids) != len(set(placement_ids)):
		raise ValueError("snapshot contains missing or duplicate facility ids")
	known = set(placement_ids)
	graph: dict[str, set[str]] = {}
	for placement in placements:
		metadata = placement.get("metadata", {})
		dependencies = set(str(value) for value in metadata.get("requires_all_active", [])) | set(str(value) for value in metadata.get("requires_any_active", []))
		if not dependencies <= known:
			raise ValueError("snapshot facility %s references an unknown dependency" % placement["id"])
		graph[str(placement["id"])] = dependencies
	if _has_cycle(graph):
		raise ValueError("snapshot facility dependency graph contains a cycle")
	instance_ids = [str(item.get("id", "")) for item in snapshot.get("instances", []) if not bool(item.get("reference_only", False))]
	if "" in instance_ids or len(instance_ids) != len(set(instance_ids)):
		raise ValueError("snapshot contains missing or duplicate land instance ids")


def _apply_template(snapshot: dict, args: argparse.Namespace) -> None:
	path = _path(args.templates)
	document = read_json(path)
	template = next((copy.deepcopy(item) for item in document.get("definitions", []) if item.get("id") == snapshot.get("source_id")), None)
	if template is None:
		raise ValueError("unknown template %s" % snapshot.get("source_id"))
	obstacles, regions, visual_regions = [], [], []
	for item in snapshot.get("polygons", []):
		semantic = item.get("semantic_type")
		if semantic in {"HardLand", "SightBlocker"}:
			obstacle = {"id": item["id"], "polygon": _clockwise(item["polygon"])}
			obstacle.update(copy.deepcopy(item.get("metadata", {})))
			if semantic == "HardLand" and "ShipMovement" not in obstacle.get("block_mask", []):
				obstacle["block_mask"] = ["ShipMovement", "TorpedoTravel", "ShellTravel", "SurfaceOpticalLineOfSight"]
			obstacles.append(obstacle)
		elif semantic in REGION_TYPES:
			region = {"id": item["id"], "region_type": semantic, "polygon": _clockwise(item["polygon"])}
			region.update(copy.deepcopy(item.get("metadata", {})))
			regions.append(region)
		elif semantic == "VisualOnly":
			visual_region = {"id": item["id"], "polygon": _clockwise(item["polygon"])}
			visual_region.update(copy.deepcopy(item.get("metadata", {})))
			visual_regions.append(visual_region)
	anchors = []
	for item in snapshot.get("anchors", []):
		anchor = {"id": item["id"], "position": item["position"], "interaction_water_polygon": _clockwise(item.get("interaction_water_polygon", []))}
		anchor.update(copy.deepcopy(item.get("metadata", {})))
		anchors.append(anchor)
	template["obstacles"] = obstacles
	template["regions"] = regions
	template["visual_regions"] = visual_regions
	template["facility_anchors"] = anchors
	_replace_definition(document, template["id"], template)
	write_json(path, document)


def _apply_map(snapshot: dict, args: argparse.Namespace) -> None:
	maps_path = _path(args.maps)
	maps_document = read_json(maps_path)
	map_source = next((copy.deepcopy(item) for item in maps_document.get("maps", []) if item.get("id") == snapshot.get("source_id")), None)
	if map_source is None:
		raise ValueError("unknown authoring map %s" % snapshot.get("source_id"))
	map_source["instances"] = [
		{key: copy.deepcopy(value) for key, value in instance.items() if key not in {"texture", "reference_only"}}
		for instance in snapshot.get("instances", []) if not bool(instance.get("reference_only", False))
	]
	for index, item in enumerate(maps_document.get("maps", [])):
		if item.get("id") == map_source["id"]:
			maps_document["maps"][index] = map_source
			break
	write_json(maps_path, maps_document)

	environment_path = _path(args.environment)
	environment = read_json(environment_path)
	zone_set_id = snapshot.get("environment_zone_set_id")
	zone_set = next((copy.deepcopy(item) for item in environment.get("definitions", []) if item.get("id") == zone_set_id), None)
	if zone_set is None:
		raise ValueError("unknown environment zone set %s" % zone_set_id)
	zones = []
	for item in snapshot.get("polygons", []):
		if item.get("semantic_type") != "EnvironmentZone":
			continue
		zone = {"id": item["id"], "polygon": _clockwise(item["polygon"])}
		zone.update(copy.deepcopy(item.get("metadata", {})))
		zones.append(zone)
	zone_set["zones"] = zones
	_replace_definition(environment, zone_set_id, zone_set)
	write_json(environment_path, environment)

	facilities_path = _path(args.facilities)
	facilities = read_json(facilities_path)
	layout_id = snapshot.get("facility_layout_id")
	layout = next((copy.deepcopy(item) for item in facilities.get("definitions", []) if item.get("id") == layout_id), None)
	if layout is None:
		raise ValueError("unknown facility layout %s" % layout_id)
	placements = []
	for item in snapshot.get("facilities", []):
		placement = {"id": item["id"]}
		placement.update(copy.deepcopy(item.get("metadata", {})))
		placements.append(placement)
	layout["placements"] = placements
	_replace_definition(facilities, layout_id, layout)
	write_json(facilities_path, facilities)

	minefields_path = _path(args.minefields)
	minefields = read_json(minefields_path)
	mine_polygons = {item["id"]: item for item in snapshot.get("polygons", []) if item.get("semantic_type") == "Minefield"}
	safe_channels: dict[str, list[dict]] = {}
	for item in snapshot.get("polygons", []):
		if item.get("semantic_type") == "SafeChannel":
			safe_channels.setdefault(str(item.get("metadata", {}).get("minefield_id", "")), []).append(item)
	for definition_id, item in mine_polygons.items():
		definition = next((copy.deepcopy(value) for value in minefields.get("definitions", []) if value.get("id") == definition_id), None)
		if definition is None:
			raise ValueError("unknown minefield %s" % definition_id)
		definition["polygon"] = _clockwise(item["polygon"])
		definition.update(copy.deepcopy(item.get("metadata", {})))
		definition["id"] = definition_id
		definition["definition_type"] = "MinefieldDefinition"
		definition["safe_channels"] = [_clockwise(channel["polygon"]) for channel in sorted(safe_channels.get(definition_id, []), key=lambda channel: int(channel.get("metadata", {}).get("order", 0)))]
		_replace_definition(minefields, definition_id, definition)
	write_json(minefields_path, minefields)


def main() -> int:
	parser = argparse.ArgumentParser()
	parser.add_argument("--snapshot", default="data/terrain/authoring/editor_snapshot.json")
	parser.add_argument("--templates", default="data/terrain/terrain_templates.json")
	parser.add_argument("--maps", default="data/terrain/authoring/terrain_maps.json")
	parser.add_argument("--environment", default="data/environments/environment_zone_definitions.json")
	parser.add_argument("--facilities", default="data/facilities/facility_definitions.json")
	parser.add_argument("--minefields", default="data/facilities/minefield_definitions.json")
	args = parser.parse_args()
	try:
		snapshot = read_json(_path(args.snapshot))
		if snapshot.get("schema_version") != 1:
			raise ValueError("unsupported snapshot schema")
		_validate_snapshot(snapshot)
		if snapshot.get("mode") == "Template":
			_apply_template(snapshot, args)
		elif snapshot.get("mode") == "Map":
			_apply_map(snapshot, args)
		else:
			raise ValueError("unknown authoring mode")
		print("authoring snapshot applied: %s" % snapshot.get("source_id", "?"))
		return 0
	except (OSError, KeyError, TypeError, ValueError) as error:
		print("authoring snapshot apply failed: %s" % error, file=sys.stderr)
		return 1


if __name__ == "__main__":
	raise SystemExit(main())
