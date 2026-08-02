#!/usr/bin/env python3
"""Build a Godot-editable terrain authoring snapshot from canonical JSON data."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from terrain_geometry import read_json, write_json

ROOT = Path(__file__).resolve().parents[2]


def _path(value: str) -> Path:
	path = Path(value)
	return path if path.is_absolute() else ROOT / path


def _definitions(path: str) -> dict[str, dict]:
	return {item["id"]: item for item in read_json(_path(path)).get("definitions", [])}


def _template_snapshot(args: argparse.Namespace) -> dict:
	templates = _definitions(args.templates)
	template = templates.get(args.template_id)
	if template is None:
		raise ValueError("unknown template %s" % args.template_id)
	polygons = []
	for obstacle in template.get("obstacles", []):
		metadata = {key: value for key, value in obstacle.items() if key not in {"id", "polygon"}}
		semantic = "HardLand" if "ShipMovement" in obstacle.get("block_mask", []) else "SightBlocker"
		polygons.append({"id": obstacle["id"], "semantic_type": semantic, "polygon": obstacle["polygon"], "metadata": metadata})
	for region in template.get("regions", []):
		metadata = {key: value for key, value in region.items() if key not in {"id", "polygon", "region_type"}}
		polygons.append({"id": region["id"], "semantic_type": region["region_type"], "polygon": region["polygon"], "metadata": metadata})
	for visual_region in template.get("visual_regions", []):
		metadata = {key: value for key, value in visual_region.items() if key not in {"id", "polygon"}}
		polygons.append({"id": visual_region["id"], "semantic_type": "VisualOnly", "polygon": visual_region["polygon"], "metadata": metadata})
	anchors = []
	for anchor in template.get("facility_anchors", []):
		anchors.append({
			"id": anchor["id"],
			"position": anchor["position"],
			"interaction_water_polygon": anchor.get("interaction_water_polygon", []),
			"metadata": {key: value for key, value in anchor.items() if key not in {"id", "position", "interaction_water_polygon"}},
		})
	return {
		"schema_version": 1,
		"mode": "Template",
		"source_id": template["id"],
		"display_name": template.get("display_name", template["id"]),
		"map_size": template["local_size"],
		"polygons": polygons,
		"anchors": anchors,
		"facilities": [],
		"instances": [{"id": "reference.%s" % template["id"], "template_id": template["id"], "texture": template["texture"], "position": template.get("origin", [template["local_size"][0] * 0.5, template["local_size"][1] * 0.5]), "scale": [1.0, 1.0], "rotation_degrees": 0.0, "reference_only": True}],
	}


def _map_snapshot(args: argparse.Namespace) -> dict:
	terrains = _definitions(args.terrain)
	terrain = terrains.get(args.map_id)
	if terrain is None:
		raise ValueError("unknown terrain map %s" % args.map_id)
	environment = _definitions(args.environment)
	zone_set = environment.get(terrain.get("environment_zone_set_id"), {})
	facilities = _definitions(args.facilities)
	layout = facilities.get(terrain.get("facility_layout_id"), {})
	mines = _definitions(args.minefields)
	templates = _definitions(args.templates)
	maps_document = read_json(_path(args.maps))
	map_source = next((item for item in maps_document.get("maps", []) if item.get("id") == args.map_id), None)
	if map_source is None:
		raise ValueError("unknown authoring map %s" % args.map_id)
	polygons = []
	for obstacle in terrain.get("obstacles", []):
		polygons.append({"id": "reference.%s" % obstacle["id"], "semantic_type": "ReferenceOnly", "polygon": obstacle["polygon"], "metadata": {"source_obstacle_id": obstacle["id"], "locked": True}})
	for zone in zone_set.get("zones", []):
		polygons.append({
			"id": zone["id"],
			"semantic_type": "EnvironmentZone",
			"polygon": zone["polygon"],
			"metadata": {key: value for key, value in zone.items() if key not in {"id", "polygon"}},
		})
	for mine in sorted(mines.values(), key=lambda item: item["id"]):
		if mine.get("definition_type") != "MinefieldDefinition":
			continue
		if mine.get("terrain_definition_id", terrain["id"]) != terrain["id"]:
			continue
		metadata = {key: value for key, value in mine.items() if key not in {"id", "polygon", "safe_channels", "definition_type", "display_name"}}
		metadata["display_name"] = mine.get("display_name", mine["id"])
		polygons.append({"id": mine["id"], "semantic_type": "Minefield", "polygon": mine["polygon"], "metadata": metadata})
		for index, safe_channel in enumerate(mine.get("safe_channels", []), 1):
			polygons.append({"id": "%s.safe_channel_%02d" % (mine["id"], index), "semantic_type": "SafeChannel", "polygon": safe_channel, "metadata": {"minefield_id": mine["id"], "order": index}})
	anchors_by_id = {anchor["id"]: anchor for anchor in terrain.get("facility_anchors", [])}
	placements = []
	for placement in layout.get("placements", []):
		anchor = anchors_by_id.get(placement.get("anchor_id"), {})
		placements.append({
			"id": placement["id"],
			"position": anchor.get("position", [0.0, 0.0]),
			"metadata": {key: value for key, value in placement.items() if key != "id"},
		})
	instances = []
	for instance in map_source.get("instances", []):
		template = templates.get(instance.get("template_id"), {})
		instances.append({**instance, "texture": template.get("texture", ""), "reference_only": False})
	return {
		"schema_version": 1,
		"mode": "Map",
		"source_id": terrain["id"],
		"display_name": terrain.get("display_name", terrain["id"]),
		"map_size": terrain["map_size"],
		"environment_zone_set_id": zone_set.get("id", ""),
		"facility_layout_id": layout.get("id", ""),
		"polygons": polygons,
		"anchors": [],
		"facilities": placements,
		"instances": instances,
	}


def main() -> int:
	parser = argparse.ArgumentParser()
	parser.add_argument("--mode", choices=("Template", "Map"), required=True)
	parser.add_argument("--template-id", default="terrain.template.harbor_mouth")
	parser.add_argument("--map-id", default="terrain.map.harbor_mouth")
	parser.add_argument("--templates", default="data/terrain/terrain_templates.json")
	parser.add_argument("--terrain", default="data/terrain/terrain_definitions.json")
	parser.add_argument("--maps", default="data/terrain/authoring/terrain_maps.json")
	parser.add_argument("--environment", default="data/environments/environment_zone_definitions.json")
	parser.add_argument("--facilities", default="data/facilities/facility_definitions.json")
	parser.add_argument("--minefields", default="data/facilities/minefield_definitions.json")
	parser.add_argument("--out", default="data/terrain/authoring/editor_snapshot.json")
	args = parser.parse_args()
	try:
		payload = _template_snapshot(args) if args.mode == "Template" else _map_snapshot(args)
		write_json(_path(args.out), payload)
		print("authoring snapshot built: %s" % args.out)
		return 0
	except (OSError, KeyError, TypeError, ValueError) as error:
		print("authoring snapshot build failed: %s" % error, file=sys.stderr)
		return 1


if __name__ == "__main__":
	raise SystemExit(main())
