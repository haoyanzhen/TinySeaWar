#!/usr/bin/env python3
"""Build non-destructive 16:9 large-coast variants from reviewed templates."""

from __future__ import annotations

import argparse
import copy
import json
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
TEMPLATES_PATH = ROOT / "data/terrain/terrain_templates.json"
MAPS_PATH = ROOT / "data/terrain/authoring/terrain_maps.json"
PROTOTYPE_LEVELS_PATH = ROOT / "data/levels/prototype_levels.json"
ENVIRONMENT_PATH = ROOT / "data/environments/environment_zone_definitions.json"
FACILITIES_PATH = ROOT / "data/facilities/facility_definitions.json"
MINEFIELDS_PATH = ROOT / "data/facilities/minefield_definitions.json"
TERRAIN_MANIFEST_PATH = ROOT / "assets/environment/terrain/terrain_asset_manifest.json"
LAND_MANIFEST_PATH = ROOT / "assets/environment/land/land_asset_manifest.json"

LAND_IDS = [
	"harbor_mouth",
	"broken_atoll",
	"central_sandbar",
	"crescent_bay",
	"double_island_long_channel",
	"dual_channel_reef_line",
	"long_archipelago",
	"offset_large_island",
	"ring_lagoon",
	"scattered_islands",
]

LEGACY_SCALE_SAMPLE_MAP_ID = "terrain.map.large_coast_scale_sample"
LEGACY_SCALE_SAMPLE_LEVEL_ID = "level.prototype_large_coast_scale_sample_3v3"
MAP_SIZE = [6144.0, 3456.0]
MAP_CENTER = [3072.0, 1728.0]
RUNTIME_SIZE = [1920, 1080]
RUNTIME_SCALE = [2.6, 3.2]
MAP_COORDINATE_SCALE = 1.5


def _read(path: Path) -> dict:
	return json.loads(path.read_text(encoding="utf-8"))


def _write(path: Path, payload: dict) -> None:
	path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _replace_or_append(items: list[dict], replacement: dict) -> None:
	for index, item in enumerate(items):
		if item.get("id") == replacement["id"]:
			items[index] = replacement
			return
	items.append(replacement)


def _map_point(point: list[float]) -> list[float]:
	return [round(float(point[0]) * MAP_COORDINATE_SCALE, 3), round(float(point[1]) * MAP_COORDINATE_SCALE, 3)]


def _transform_template(land_id: str) -> dict:
	# Rebuilding must not resurrect legacy island fences or basin shallow water.
	layouts = _read(ROOT / "data/terrain/authoring/coastal_open_layouts.json")
	return copy.deepcopy(next(item for item in layouts["definitions"] if item["id"] == "terrain.template.%s_16x9" % land_id))


def _transform_map(base: dict, land_id: str) -> dict:
	result = copy.deepcopy(base)
	result["id"] = "terrain.map.%s_16x9" % land_id
	result["display_name"] = "%s（16:9 大型海岸）" % base.get("display_name", land_id)
	result["map_size"] = MAP_SIZE
	for instance in result.get("instances", []):
		instance["template_id"] = "terrain.template.%s_16x9" % land_id
		instance["position"] = MAP_CENTER
		instance["scale"] = RUNTIME_SCALE
		instance["rotation_degrees"] = 0.0
	for spawn in result.get("spawn_points", []):
		spawn["position"] = _map_point(spawn["position"])
	result["navigation_definition_id"] = "navigation.%s_16x9" % land_id
	if land_id == "harbor_mouth":
		result["facility_layout_id"] = "facility.layout.harbor_mouth_16x9"
		result["environment_zone_set_id"] = "environment.zone_set.harbor_mouth_16x9"
	return result


def _scale_environment_zone_set(document: dict) -> None:
	base = next(item for item in document["definitions"] if item.get("id") == "environment.zone_set.harbor_mouth")
	result = copy.deepcopy(base)
	result["id"] = "environment.zone_set.harbor_mouth_16x9"
	for zone in result.get("zones", []):
		zone["id"] = str(zone["id"]).replace("zone.harbor.", "zone.harbor_16x9.")
		zone["polygon"] = [_map_point(point) for point in zone.get("polygon", [])]
		if "position" in zone:
			zone["position"] = _map_point(zone["position"])
		if "drift_path" in zone:
			zone["drift_path"] = [_map_point(point) for point in zone["drift_path"]]
	_replace_or_append(document["definitions"], result)


def _duplicate_harbor_facility_layout(document: dict) -> None:
	base = next(item for item in document["definitions"] if item.get("id") == "facility.layout.harbor_mouth")
	result = copy.deepcopy(base)
	result["id"] = "facility.layout.harbor_mouth_16x9"
	result["terrain_definition_id"] = "terrain.map.harbor_mouth_16x9"
	_replace_or_append(document["definitions"], result)


def _duplicate_harbor_minefield(document: dict) -> None:
	base = next(item for item in document["definitions"] if item.get("id") == "minefield.harbor_outer")
	result = copy.deepcopy(base)
	result["id"] = "minefield.harbor_outer_16x9"
	result["terrain_definition_id"] = "terrain.map.harbor_mouth_16x9"
	result["polygon"] = [_map_point(point) for point in result.get("polygon", [])]
	result["safe_channels"] = [[_map_point(point) for point in polygon] for polygon in result.get("safe_channels", [])]
	_replace_or_append(document["definitions"], result)


def _update_prototype_levels(document: dict, maps: dict[str, dict]) -> None:
	for land_id in LAND_IDS:
		level_id = "level.prototype_harbor_3v3" if land_id == "harbor_mouth" else "level.prototype_%s_3v3" % land_id
		level = next(item for item in document["definitions"] if item.get("id") == level_id)
		level_map = level["map"]
		level_map["width"], level_map["height"] = MAP_SIZE
		level_map["terrain_definition_id"] = "terrain.map.%s_16x9" % land_id
		level_map["navigation_definition_id"] = "navigation.%s_16x9" % land_id
		if land_id == "harbor_mouth":
			level_map["environment_zone_set_id"] = "environment.zone_set.harbor_mouth_16x9"
			level_map["facility_layout_id"] = "facility.layout.harbor_mouth_16x9"
		else:
			level_map.pop("environment_zone_set_id", None)
			level_map.pop("facility_layout_id", None)
		spawns = maps[land_id]["spawn_points"]
		for faction_id in ("player", "enemy"):
			available = [spawn for spawn in spawns if spawn["faction_id"] == faction_id]
			available.sort(key=lambda spawn: int(str(spawn["id"]).rsplit("_", 1)[-1]))
			for index, member in enumerate(level["%s_fleet" % faction_id]):
				member["position"] = available[index]["position"]
				member["heading"] = available[index]["heading"]


def _navigation_spawns(terrain_id: str, navigation_by_terrain: dict[str, dict], faction_id: str) -> list[dict]:
	navigation = navigation_by_terrain.get(terrain_id, {})
	profile = next(
		(item for item in navigation.get("profiles", []) if item.get("id") == "navigation.profile.large_deep"),
		None,
	)
	if profile is None:
		raise ValueError("missing large-deep navigation profile for %s" % terrain_id)
	anchor = [780.0, 1728.0] if faction_id == "player" else [5364.0, 1728.0]
	side_limit = MAP_CENTER[0] - 720.0 if faction_id == "player" else MAP_CENTER[0] + 720.0
	candidates = []
	for node in profile.get("nodes", []):
		position = [float(node["position"][0]), float(node["position"][1])]
		if faction_id == "player" and position[0] >= side_limit:
			continue
		if faction_id == "enemy" and position[0] <= side_limit:
			continue
		distance = math.dist(position, anchor)
		lateral = abs(position[1] - anchor[1])
		forward = abs(position[0] - anchor[0])
		candidates.append((distance + lateral * 0.18 + forward * 0.05, lateral, forward, str(node["id"]), position))
	candidates.sort()
	chosen: list[list[float]] = []
	for candidate in candidates:
		position = candidate[-1]
		if all(math.dist(position, previous) >= 180.0 for previous in chosen):
			chosen.append(position)
		if len(chosen) == 11:
			break
	if len(chosen) != 11:
		raise ValueError("unable to place 11 safe %s slots for %s" % (faction_id, terrain_id))
	heading = 0.0 if faction_id == "player" else 180.0
	return [
		{
			"id": "%s_%d" % (faction_id, index + 1),
			"faction_id": faction_id,
			"position": [round(position[0], 3), round(position[1], 3)],
			"heading": heading,
			"radius": 46.0,
			"movement_tags": ["Surface"],
		}
		for index, position in enumerate(chosen)
	]


def _update_terrain_manifest(document: dict) -> None:
	for land_id in LAND_IDS:
		asset = {
			"semantic": "land_%s_16x9_runtime" % land_id,
			"path": "res://assets/environment/land/land_%s_16x9_runtime.png" % land_id,
			"size": RUNTIME_SIZE, "alpha": True,
			"source_masters": ["res://assets/environment/land/source/land_%s_source.png" % land_id],
			"revision": "open_coasts_v1",
			"generation_method": "built-in imagegen; transparent alpha retained; canvas registration",
		}
		document["assets"] = [item for item in document.get("assets", []) if item.get("semantic") != asset["semantic"]]
		document["assets"].append(asset)


def _update_land_manifest(document: dict) -> None:
	document.update({
		"generated_by": "built-in imagegen + canvas registration",
		"background_policy": "transparent PNG; raw generation and original alpha retained",
		"generation_manifest_16x9": "res://assets/environment/land/source/open_coasts_v1/manifest.json",
		"runtime_display_scale_16x9": RUNTIME_SCALE,
	})
	for asset in document.get("assets", []):
		land_id = str(asset.get("id", "")).removeprefix("land_")
		if land_id not in LAND_IDS:
			continue
		for key in list(asset):
			if key.startswith("reviewed_") or "channel_world_width" in key:
				asset.pop(key)
		asset.update({
			"source_master": "res://assets/environment/land/source/land_%s_source.png" % land_id,
			"runtime_texture_16x9": "res://assets/environment/land/land_%s_16x9_runtime.png" % land_id,
			"runtime_semantic_16x9": "land_%s_16x9_runtime" % land_id,
			"revision_16x9": "open_coasts_v1",
			"generation_method": "built-in imagegen; transparent alpha retained; canvas registration",
			"runtime_status_16x9": "runtime_asset_ready",
		})


def main() -> int:
	parser = argparse.ArgumentParser()
	parser.add_argument("--navigation", default="")
	args = parser.parse_args()
	navigation_by_terrain: dict[str, dict] = {}
	if args.navigation:
		navigation_document = _read(Path(args.navigation))
		navigation_by_terrain = {
			item["terrain_definition_id"]: item for item in navigation_document.get("definitions", [])
		}

	templates_document = _read(TEMPLATES_PATH)
	for land_id in LAND_IDS:
		_replace_or_append(templates_document["definitions"], _transform_template(land_id))
	_write(TEMPLATES_PATH, templates_document)

	maps_document = _read(MAPS_PATH)
	maps_document["maps"] = [
		item for item in maps_document["maps"]
		if item.get("id") != LEGACY_SCALE_SAMPLE_MAP_ID
	]
	base_maps = {item["id"]: item for item in maps_document["maps"]}
	new_maps: dict[str, dict] = {}
	for land_id in LAND_IDS:
		new_map = _transform_map(base_maps["terrain.map.%s" % land_id], land_id)
		if navigation_by_terrain:
			new_map["spawn_points"] = (
				_navigation_spawns(new_map["id"], navigation_by_terrain, "player")
				+ _navigation_spawns(new_map["id"], navigation_by_terrain, "enemy")
			)
		_replace_or_append(maps_document["maps"], new_map)
		new_maps[land_id] = new_map
	_write(MAPS_PATH, maps_document)

	environment_document = _read(ENVIRONMENT_PATH)
	_scale_environment_zone_set(environment_document)
	_write(ENVIRONMENT_PATH, environment_document)

	facilities_document = _read(FACILITIES_PATH)
	_duplicate_harbor_facility_layout(facilities_document)
	_write(FACILITIES_PATH, facilities_document)

	minefields_document = _read(MINEFIELDS_PATH)
	_duplicate_harbor_minefield(minefields_document)
	_write(MINEFIELDS_PATH, minefields_document)

	prototype_document = _read(PROTOTYPE_LEVELS_PATH)
	prototype_document["definitions"] = [
		item for item in prototype_document["definitions"]
		if item.get("id") != LEGACY_SCALE_SAMPLE_LEVEL_ID
	]
	_update_prototype_levels(prototype_document, new_maps)
	_write(PROTOTYPE_LEVELS_PATH, prototype_document)

	terrain_manifest = _read(TERRAIN_MANIFEST_PATH)
	_update_terrain_manifest(terrain_manifest)
	_write(TERRAIN_MANIFEST_PATH, terrain_manifest)

	land_manifest = _read(LAND_MANIFEST_PATH)
	_update_land_manifest(land_manifest)
	_write(LAND_MANIFEST_PATH, land_manifest)

	print("built %d 16:9 coastal templates, maps, runtime bindings, and prototype entries" % len(LAND_IDS))
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
