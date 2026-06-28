#!/usr/bin/env python3
"""Bake authoring transforms and semantic polygons into runtime world coordinates."""

from __future__ import annotations

import argparse
import sys

from terrain_geometry import ensure_clockwise, read_json, transform_point, transform_polygon, write_json


def _transform_anchor(anchor: dict, instance: dict, origin: list[float]) -> dict:
	result = anchor.copy()
	result["id"] = "%s.%s" % (instance["id"], anchor["id"].split(".")[-1])
	result["position"] = transform_point(
		[anchor["position"][0] - origin[0], anchor["position"][1] - origin[1]],
		instance["position"], instance["scale"], instance.get("rotation_degrees", 0.0),
	)
	result["heading"] = round(float(anchor.get("heading", 0.0)) + float(instance.get("rotation_degrees", 0.0)), 3)
	if "muzzle_position" in anchor:
		result["muzzle_position"] = transform_point(
			[anchor["muzzle_position"][0] - origin[0], anchor["muzzle_position"][1] - origin[1]],
			instance["position"], instance["scale"], instance.get("rotation_degrees", 0.0),
		)
	if "observation_position" in anchor:
		result["observation_position"] = transform_point(
			[anchor["observation_position"][0] - origin[0], anchor["observation_position"][1] - origin[1]],
			instance["position"], instance["scale"], instance.get("rotation_degrees", 0.0),
		)
	result["interaction_water_polygon"] = transform_polygon(anchor["interaction_water_polygon"], instance["position"], instance["scale"], instance.get("rotation_degrees", 0.0), origin)
	result["shore_obstacle_id"] = "%s.%s" % (instance["id"], anchor["shore_obstacle_id"].split(".")[-1])
	return result


def bake_map(map_source: dict, templates: dict) -> dict:
	obstacles, regions, visual_regions, anchors, visual_instances = [], [], [], [], []
	for instance in sorted(map_source.get("instances", []), key=lambda item: item["id"]):
		template = templates.get(instance["template_id"])
		if template is None:
			raise ValueError("Unknown terrain template %s" % instance["template_id"])
		origin = template.get("origin", [0.0, 0.0])
		for obstacle in template.get("obstacles", []):
			baked = obstacle.copy()
			baked["id"] = "%s.%s" % (instance["id"], obstacle["id"].split(".")[-1])
			baked["source_asset_id"] = template["asset_id"]
			baked["source_instance_id"] = instance["id"]
			baked["polygon"] = transform_polygon(obstacle["polygon"], instance["position"], instance["scale"], instance.get("rotation_degrees", 0.0), origin)
			obstacles.append(baked)
		for region in template.get("regions", []):
			baked = region.copy()
			baked["id"] = "%s.%s" % (instance["id"], region["id"].split(".")[-1])
			baked["source_instance_id"] = instance["id"]
			baked["polygon"] = transform_polygon(region["polygon"], instance["position"], instance["scale"], instance.get("rotation_degrees", 0.0), origin)
			regions.append(baked)
		for visual_region in template.get("visual_regions", []):
			baked = visual_region.copy()
			baked["id"] = "%s.%s" % (instance["id"], visual_region["id"].split(".")[-1])
			baked["source_instance_id"] = instance["id"]
			baked["polygon"] = transform_polygon(visual_region["polygon"], instance["position"], instance["scale"], instance.get("rotation_degrees", 0.0), origin)
			visual_regions.append(baked)
		for anchor in template.get("facility_anchors", []):
			anchors.append(_transform_anchor(anchor, instance, origin))
		visual_instances.append({
			"id": instance["id"],
			"asset_id": template["asset_id"],
			"texture": template["texture"],
			"position": instance["position"],
			"scale": instance["scale"],
			"rotation_degrees": instance.get("rotation_degrees", 0.0),
			"local_size": template["local_size"],
		})
	return {
		"id": map_source["id"],
		"definition_type": "TerrainMap",
		"display_name": map_source.get("display_name", map_source["id"]),
		"map_size": map_source["map_size"],
		"geometry_epsilon": map_source.get("geometry_epsilon", 0.001),
		"navigation_revision": 1,
		"source_document": "res://data/terrain/authoring/terrain_maps.json",
		"obstacles": sorted(obstacles, key=lambda item: item["id"]),
		"regions": sorted(regions, key=lambda item: (-int(item.get("priority", 0)), item["id"])),
		"visual_regions": sorted(visual_regions, key=lambda item: (int(item.get("z_index", 0)), item["id"])),
		"facility_anchors": sorted(anchors, key=lambda item: item["id"]),
		"visual_instances": visual_instances,
		"spawn_points": map_source.get("spawn_points", []),
		"facility_layout_id": map_source.get("facility_layout_id", ""),
		"environment_zone_set_id": map_source.get("environment_zone_set_id", ""),
		"navigation_definition_id": map_source.get("navigation_definition_id", ""),
	}


def main() -> int:
	parser = argparse.ArgumentParser()
	parser.add_argument("--templates", default="data/terrain/terrain_templates.json")
	parser.add_argument("--maps", default="data/terrain/authoring/terrain_maps.json")
	parser.add_argument("--out", default="data/terrain/terrain_definitions.json")
	args = parser.parse_args()
	try:
		templates_doc = read_json(args.templates)
		maps_doc = read_json(args.maps)
		templates = {item["id"]: item for item in templates_doc.get("definitions", [])}
		definitions = [bake_map(item, templates) for item in maps_doc.get("maps", [])]
		write_json(args.out, {"schema_version": 1, "generated_by": "tools/terrain/bake_terrain_definition.py", "definitions": definitions})
		return 0
	except (KeyError, TypeError, ValueError) as error:
		print("terrain bake failed: %s" % error, file=sys.stderr)
		return 1


if __name__ == "__main__":
	raise SystemExit(main())
