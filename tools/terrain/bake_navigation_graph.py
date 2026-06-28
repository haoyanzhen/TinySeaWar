#!/usr/bin/env python3
"""Bake deterministic shared navigation graphs from reviewed terrain geometry."""

from __future__ import annotations

import argparse
import heapq
import math
import sys

from terrain_geometry import circle_clear, point_in_polygon, read_json, write_json

PROFILES = [
	{"id": "navigation.profile.small_shallow", "radius": 20.0, "movement_tags": ["Surface", "ShallowDraft"]},
	{"id": "navigation.profile.standard_shallow", "radius": 32.0, "movement_tags": ["Surface", "ShallowDraft"]},
	{"id": "navigation.profile.large_deep", "radius": 46.0, "movement_tags": ["Surface"]},
]


def _region_allows(point: list[float], regions: list[dict], tags: set[str]) -> bool:
	matches = [region for region in regions if point_in_polygon(point, region.get("polygon", []))]
	matches.sort(key=lambda item: (-int(item.get("priority", 0)), item["id"]))
	if not matches:
		return True
	region = matches[0]
	region_type = region.get("region_type", "DeepWater")
	if region_type == "ShallowWater":
		return "ShallowDraft" in tags
	if region_type == "ReefOrSandbar":
		return "ReefCapable" in tags
	return True


def _segment_clear(start: list[float], end: list[float], radius: float, obstacles: list[dict], regions: list[dict], tags: set[str]) -> bool:
	distance = math.dist(start, end)
	steps = max(1, int(math.ceil(distance / max(6.0, radius * 0.4))))
	for index in range(steps + 1):
		t = float(index) / float(steps)
		point = [start[0] + (end[0] - start[0]) * t, start[1] + (end[1] - start[1]) * t]
		if not circle_clear(point, radius, obstacles):
			return False
		if not _region_allows(point, regions, tags):
			return False
	return True


def bake_profile(terrain: dict, profile: dict, cell_size: float) -> dict:
	width, height = terrain["map_size"]
	radius = float(profile["radius"])
	tags = set(profile["movement_tags"])
	columns = int(math.floor(width / cell_size))
	rows = int(math.floor(height / cell_size))
	nodes: dict[tuple[int, int], dict] = {}
	for row in range(rows):
		for column in range(columns):
			position = [(column + 0.5) * cell_size, (row + 0.5) * cell_size]
			if position[0] < radius or position[1] < radius or position[0] > width - radius or position[1] > height - radius:
				continue
			if not circle_clear(position, radius, terrain.get("obstacles", [])):
				continue
			if not _region_allows(position, terrain.get("regions", []), tags):
				continue
			node_id = "n_%02d_%02d" % (column, row)
			nodes[(column, row)] = {"id": node_id, "position": [round(position[0], 3), round(position[1], 3)], "neighbors": []}
	for coordinate, node in sorted(nodes.items()):
		column, row = coordinate
		for dx, dy in ((-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)):
			neighbor = nodes.get((column + dx, row + dy))
			if neighbor is None or not _segment_clear(node["position"], neighbor["position"], radius, terrain.get("obstacles", []), terrain.get("regions", []), tags):
				continue
			node["neighbors"].append(neighbor["id"])
		node["neighbors"].sort()
	return {**profile, "cell_size": cell_size, "nodes": [nodes[key] for key in sorted(nodes)]}


def main() -> int:
	parser = argparse.ArgumentParser()
	parser.add_argument("--terrain", default="data/terrain/terrain_definitions.json")
	parser.add_argument("--out", default="data/terrain/navigation_definitions.json")
	parser.add_argument("--cell-size", type=float, default=128.0)
	args = parser.parse_args()
	try:
		terrain_doc = read_json(args.terrain)
		definitions = []
		for terrain in terrain_doc.get("definitions", []):
			definitions.append({
				"id": str(terrain.get("navigation_definition_id", "navigation.%s" % terrain["id"].split(".")[-1])),
				"definition_type": "NavigationGraph",
				"terrain_definition_id": terrain["id"],
				"navigation_revision": terrain.get("navigation_revision", 1),
				"profiles": [bake_profile(terrain, profile, args.cell_size) for profile in PROFILES],
			})
		write_json(args.out, {"schema_version": 1, "generated_by": "tools/terrain/bake_navigation_graph.py", "definitions": definitions})
		return 0
	except (KeyError, TypeError, ValueError) as error:
		print("navigation bake failed: %s" % error, file=sys.stderr)
		return 1


if __name__ == "__main__":
	raise SystemExit(main())
