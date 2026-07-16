#!/usr/bin/env python3
"""Expand every reviewed coastal map to deterministic 1/3/5/11-ship spawn slots."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

from terrain_geometry import read_json


MAX_SLOTS_PER_FACTION = 11
SPAWN_RADIUS = 46.0
MINIMUM_SLOT_SEPARATION = 180.0


def _write_authoring_maps(path: str, document: dict) -> None:
	lines = ["{", '  "schema_version": %d,' % int(document.get("schema_version", 1)), '  "maps": [']
	for map_index, terrain_map in enumerate(document.get("maps", [])):
		lines.append("    {")
		keys = [key for key in terrain_map if key not in ("instances", "spawn_points")]
		ordered_keys = [key for key in ("id", "display_name", "map_size", "geometry_epsilon") if key in keys]
		ordered_keys += ["instances", "spawn_points"]
		ordered_keys += [key for key in keys if key not in ordered_keys]
		for key_index, key in enumerate(ordered_keys):
			comma = "," if key_index < len(ordered_keys) - 1 else ""
			if key in ("instances", "spawn_points"):
				lines.append('      "%s": [' % key)
				values = terrain_map.get(key, [])
				for value_index, value in enumerate(values):
					value_comma = "," if value_index < len(values) - 1 else ""
					lines.append("        %s%s" % (json.dumps(value, ensure_ascii=False, separators=(",", ": ")), value_comma))
				lines.append("      ]%s" % comma)
			else:
				lines.append('      %s: %s%s' % (json.dumps(key, ensure_ascii=False), json.dumps(terrain_map[key], ensure_ascii=False, separators=(",", ": ")), comma))
		lines.append("    }%s" % ("," if map_index < len(document.get("maps", [])) - 1 else ""))
	lines.extend(["  ]", "}"])
	Path(path).write_text("\n".join(lines) + "\n", encoding="utf-8")


def _ordered_existing(spawns: list[dict], faction_id: str) -> list[dict]:
	result = [item.copy() for item in spawns if item.get("faction_id") == faction_id]
	result.sort(key=lambda item: int(str(item.get("id", "")).removeprefix("%s_" % faction_id)))
	return result


def _heading(start: list[float], target: list[float]) -> float:
	return round(math.degrees(math.atan2(float(target[1]) - float(start[1]), float(target[0]) - float(start[0]))), 3)


def _projection(point: list[float], origin: list[float], direction: list[float]) -> float:
	return (float(point[0]) - float(origin[0])) * direction[0] + (float(point[1]) - float(origin[1])) * direction[1]


def _expand_faction(existing: list[dict], opposing: list[dict], profile: dict, faction_id: str) -> list[dict]:
	anchor = [float(value) for value in existing[0]["position"]]
	opposing_anchor = [float(value) for value in opposing[0]["position"]]
	direction = [opposing_anchor[0] - anchor[0], opposing_anchor[1] - anchor[1]]
	length = math.hypot(*direction)
	direction = [direction[0] / length, direction[1] / length]
	midpoint = [(anchor[0] + opposing_anchor[0]) * 0.5, (anchor[1] + opposing_anchor[1]) * 0.5]
	chosen = [[float(value) for value in item["position"]] for item in existing]
	candidates = []
	for node in profile.get("nodes", []):
		position = [float(value) for value in node["position"]]
		# Keep each fleet on its reviewed side of the battlefield and near its approach area.
		if _projection(position, midpoint, direction) >= -MINIMUM_SLOT_SEPARATION:
			continue
		if math.dist(position, anchor) > 1050.0:
			continue
		if any(math.dist(position, selected) < MINIMUM_SLOT_SEPARATION for selected in chosen):
			continue
		forward_offset = abs(_projection(position, anchor, direction))
		lateral_offset = abs((position[0] - anchor[0]) * -direction[1] + (position[1] - anchor[1]) * direction[0])
		candidates.append((forward_offset * 0.45 + lateral_offset, lateral_offset, forward_offset, node["id"], position))
	candidates.sort()
	while len(chosen) < MAX_SLOTS_PER_FACTION:
		match = next((candidate for candidate in candidates if all(math.dist(candidate[-1], selected) >= MINIMUM_SLOT_SEPARATION for selected in chosen)), None)
		if match is None:
			raise ValueError("Unable to place %d safe %s slots" % (MAX_SLOTS_PER_FACTION, faction_id))
		chosen.append(match[-1])
		candidates.remove(match)
	heading = _heading(anchor, opposing_anchor)
	return [
		{
			"id": "%s_%d" % (faction_id, index + 1),
			"faction_id": faction_id,
			"position": [round(position[0], 3), round(position[1], 3)],
			"heading": heading,
			"radius": SPAWN_RADIUS,
			"movement_tags": ["Surface"],
		}
		for index, position in enumerate(chosen)
	]


def main() -> int:
	parser = argparse.ArgumentParser()
	parser.add_argument("--maps", default="data/terrain/authoring/terrain_maps.json")
	parser.add_argument("--navigation", default="data/terrain/navigation_definitions.json")
	args = parser.parse_args()
	maps_document = read_json(args.maps)
	navigation_by_terrain = {
		item["terrain_definition_id"]: item for item in read_json(args.navigation).get("definitions", [])
	}
	for terrain_map in maps_document.get("maps", []):
		navigation = navigation_by_terrain.get(terrain_map["id"], {})
		profile = next((item for item in navigation.get("profiles", []) if item.get("id") == "navigation.profile.large_deep"), None)
		if profile is None:
			raise ValueError("Missing large deep navigation profile for %s" % terrain_map["id"])
		player = _ordered_existing(terrain_map.get("spawn_points", []), "player")
		enemy = _ordered_existing(terrain_map.get("spawn_points", []), "enemy")
		if len(player) < 3 or len(enemy) < 3:
			raise ValueError("Map %s lacks its reviewed 3v3 seed slots" % terrain_map["id"])
		terrain_map["spawn_points"] = _expand_faction(player[:3], enemy[:3], profile, "player") + _expand_faction(enemy[:3], player[:3], profile, "enemy")
	_write_authoring_maps(args.maps, maps_document)
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
