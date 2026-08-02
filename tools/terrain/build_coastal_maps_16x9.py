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
TEMPLATE_CENTER = [512.0, 512.0]
RUNTIME_CENTER = [960.0, 540.0]
LOCAL_SCALE = [1.51875, 0.94921875]
MAP_COORDINATE_SCALE = 1.5
RING_LAGOON_GAP_LEFT = 820.0
RING_LAGOON_GAP_RIGHT = 1100.0
RING_LAGOON_CHANNEL_LEFT = 840.0
RING_LAGOON_CHANNEL_RIGHT = 1080.0
RING_LAGOON_SECONDARY_GAP_WIDTH = 200.0
RING_LAGOON_SECONDARY_CHANNEL_WIDTH = 160.0
RING_LAGOON_NORTHWEST_PASSAGE = ([250.0, -50.0], [750.0, 380.0])
RING_LAGOON_NORTHEAST_PASSAGE = ([1670.0, -50.0], [1170.0, 380.0])
RING_LAGOON_NORTHWEST_CHANNEL = ([460.0, 140.0], [730.0, 360.0])
RING_LAGOON_NORTHEAST_CHANNEL = ([1460.0, 140.0], [1190.0, 360.0])


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


def _template_point(point: list[float]) -> list[float]:
	return [
		round(RUNTIME_CENTER[0] + (float(point[0]) - TEMPLATE_CENTER[0]) * LOCAL_SCALE[0], 3),
		round(RUNTIME_CENTER[1] + (float(point[1]) - TEMPLATE_CENTER[1]) * LOCAL_SCALE[1], 3),
	]


def _map_point(point: list[float]) -> list[float]:
	return [round(float(point[0]) * MAP_COORDINATE_SCALE, 3), round(float(point[1]) * MAP_COORDINATE_SCALE, 3)]


def _clip_polygon_x(polygon: list[list[float]], boundary: float, keep_left: bool) -> list[list[float]]:
	if not polygon:
		return []

	def inside(point: list[float]) -> bool:
		return float(point[0]) <= boundary if keep_left else float(point[0]) >= boundary

	def intersection(start: list[float], end: list[float]) -> list[float]:
		delta_x = float(end[0]) - float(start[0])
		if abs(delta_x) <= 1e-9:
			return [round(boundary, 3), round(float(start[1]), 3)]
		t = (boundary - float(start[0])) / delta_x
		return [
			round(boundary, 3),
			round(float(start[1]) + (float(end[1]) - float(start[1])) * t, 3),
		]

	result: list[list[float]] = []
	previous = polygon[-1]
	previous_inside = inside(previous)
	for current in polygon:
		current_inside = inside(current)
		if current_inside:
			if not previous_inside:
				result.append(intersection(previous, current))
			result.append([round(float(current[0]), 3), round(float(current[1]), 3)])
		elif previous_inside:
			result.append(intersection(previous, current))
		previous = current
		previous_inside = current_inside
	return result


def _clip_polygon_scalar(
	polygon: list[list[float]],
	normal: tuple[float, float],
	boundary: float,
	keep_lower: bool,
) -> list[list[float]]:
	if not polygon:
		return []

	def scalar(point: list[float]) -> float:
		return (
			(float(point[0]) - RUNTIME_CENTER[0]) * normal[0]
			+ (float(point[1]) - RUNTIME_CENTER[1]) * normal[1]
		)

	def inside(value: float) -> bool:
		return value <= boundary if keep_lower else value >= boundary

	result: list[list[float]] = []
	previous = polygon[-1]
	previous_scalar = scalar(previous)
	previous_inside = inside(previous_scalar)
	for current in polygon:
		current_scalar = scalar(current)
		current_inside = inside(current_scalar)
		if current_inside != previous_inside:
			denominator = current_scalar - previous_scalar
			t = 0.0 if abs(denominator) <= 1e-9 else (boundary - previous_scalar) / denominator
			result.append([
				round(float(previous[0]) + (float(current[0]) - float(previous[0])) * t, 3),
				round(float(previous[1]) + (float(current[1]) - float(previous[1])) * t, 3),
			])
		if current_inside:
			result.append([round(float(current[0]), 3), round(float(current[1]), 3)])
		previous = current
		previous_scalar = current_scalar
		previous_inside = current_inside
	return result


def _passage_normal(start: list[float], end: list[float]) -> tuple[float, float]:
	delta_x = float(end[0]) - float(start[0])
	delta_y = float(end[1]) - float(start[1])
	length = math.hypot(delta_x, delta_y)
	if length <= 1e-9:
		raise ValueError("passage endpoints must be distinct")
	return (-delta_y / length, delta_x / length)


def _corridor_polygon(
	start: list[float],
	end: list[float],
	width: float,
) -> list[list[float]]:
	normal = _passage_normal(start, end)
	offset_x = normal[0] * width * 0.5
	offset_y = normal[1] * width * 0.5
	return [
		[round(start[0] + offset_x, 3), round(start[1] + offset_y, 3)],
		[round(end[0] + offset_x, 3), round(end[1] + offset_y, 3)],
		[round(end[0] - offset_x, 3), round(end[1] - offset_y, 3)],
		[round(start[0] - offset_x, 3), round(start[1] - offset_y, 3)],
	]


def _split_ring_item(
	item: dict,
	passages: tuple[tuple[list[float], list[float]], ...],
	original_id: str,
	new_id: str,
	keep_lower_as_original: bool,
) -> list[dict]:
	polygon = item.get("polygon", [])
	if len(polygon) < 3:
		return [item]
	start, end = passages[0]
	normal = _passage_normal(start, end)
	half_width = RING_LAGOON_SECONDARY_GAP_WIDTH * 0.5
	lower = _clip_polygon_scalar(polygon, normal, -half_width, True)
	upper = _clip_polygon_scalar(polygon, normal, half_width, False)
	original_polygon = lower if keep_lower_as_original else upper
	new_polygon = upper if keep_lower_as_original else lower
	result: list[dict] = []
	if len(original_polygon) >= 3:
		original = copy.deepcopy(item)
		original["id"] = original_id
		original["polygon"] = original_polygon
		result.append(original)
	if len(new_polygon) >= 3:
		added = copy.deepcopy(item)
		added["id"] = new_id
		added["polygon"] = new_polygon
		result.append(added)
	return result


def _widen_ring_lagoon_passages(template: dict) -> None:
	for obstacle in template.get("obstacles", []):
		suffix = str(obstacle.get("id", "")).rsplit("_", 1)[-1]
		if suffix in ("01", "04"):
			obstacle["polygon"] = _clip_polygon_x(obstacle["polygon"], RING_LAGOON_GAP_LEFT, True)
		elif suffix in ("02", "03"):
			obstacle["polygon"] = _clip_polygon_x(obstacle["polygon"], RING_LAGOON_GAP_RIGHT, False)
	split_obstacles: list[dict] = []
	for obstacle in template.get("obstacles", []):
		obstacle_id = str(obstacle.get("id", ""))
		if obstacle_id.endswith(".land_01"):
			split_obstacles.extend(_split_ring_item(
				obstacle,
				(RING_LAGOON_NORTHWEST_PASSAGE,),
				obstacle_id,
				obstacle_id.rsplit("_", 1)[0] + "_05",
				True,
			))
		elif obstacle_id.endswith(".land_02"):
			split_obstacles.extend(_split_ring_item(
				obstacle,
				(RING_LAGOON_NORTHEAST_PASSAGE,),
				obstacle_id,
				obstacle_id.rsplit("_", 1)[0] + "_06",
				False,
			))
		else:
			split_obstacles.append(obstacle)
	template["obstacles"] = split_obstacles
	for visual_region in template.get("visual_regions", []):
		suffix = str(visual_region.get("id", "")).rsplit("_", 1)[-1]
		if suffix in ("01", "04"):
			visual_region["polygon"] = _clip_polygon_x(visual_region["polygon"], RING_LAGOON_GAP_LEFT, True)
		elif suffix in ("02", "03"):
			visual_region["polygon"] = _clip_polygon_x(visual_region["polygon"], RING_LAGOON_GAP_RIGHT, False)
	split_visual_regions: list[dict] = []
	for visual_region in template.get("visual_regions", []):
		region_id = str(visual_region.get("id", ""))
		if region_id.endswith("_01"):
			split_visual_regions.extend(_split_ring_item(
				visual_region,
				(RING_LAGOON_NORTHWEST_PASSAGE,),
				region_id,
				region_id.rsplit("_", 1)[0] + "_05",
				True,
			))
		elif region_id.endswith("_02"):
			split_visual_regions.extend(_split_ring_item(
				visual_region,
				(RING_LAGOON_NORTHEAST_PASSAGE,),
				region_id,
				region_id.rsplit("_", 1)[0] + "_06",
				False,
			))
		else:
			split_visual_regions.append(visual_region)
	template["visual_regions"] = split_visual_regions
	for region in template.get("regions", []):
		region_id = str(region.get("id", ""))
		if region_id.endswith("north_passage") or region_id.endswith("south_passage"):
			for point in region.get("polygon", []):
				point[0] = RING_LAGOON_CHANNEL_LEFT if float(point[0]) < RUNTIME_CENTER[0] else RING_LAGOON_CHANNEL_RIGHT
	for suffix, passage in (
		("northwest_passage", RING_LAGOON_NORTHWEST_CHANNEL),
		("northeast_passage", RING_LAGOON_NORTHEAST_CHANNEL),
	):
		template.setdefault("regions", []).append({
			"id": "land_ring_lagoon.%s" % suffix,
			"region_type": "NavigationChannel",
			"polygon": _corridor_polygon(
				passage[0],
				passage[1],
				RING_LAGOON_SECONDARY_CHANNEL_WIDTH,
			),
			"priority": 82,
			"access_tags": ["Surface"],
			"effect_profile_id": "terrain.effect.navigationchannel",
		})
	template["review_status"] = "reviewed_semantic_source_16x9_ring_passages_v3"


def _transform_template(base: dict, land_id: str) -> dict:
	result = copy.deepcopy(base)
	result["id"] = "terrain.template.%s_16x9" % land_id
	result["display_name"] = "%s 16:9 Large Coast" % base.get("display_name", land_id)
	result["asset_id"] = "land_%s_16x9" % land_id
	result["texture"] = "res://assets/environment/land/land_%s_16x9_runtime.png" % land_id
	result["local_size"] = RUNTIME_SIZE
	result["origin"] = RUNTIME_CENTER
	result["review_status"] = "reviewed_semantic_source_16x9"
	for collection_name in ("obstacles", "regions", "visual_regions"):
		for item in result.get(collection_name, []):
			item["polygon"] = [_template_point(point) for point in item.get("polygon", [])]
	for anchor in result.get("facility_anchors", []):
		for key in ("position", "muzzle_position", "observation_position"):
			if key in anchor:
				anchor[key] = _template_point(anchor[key])
		anchor["interaction_water_polygon"] = [
			_template_point(point) for point in anchor.get("interaction_water_polygon", [])
		]
	if land_id == "ring_lagoon":
		_widen_ring_lagoon_passages(result)
	return result


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
			"size": RUNTIME_SIZE,
			"alpha": True,
			"source_masters": ["res://assets/environment/land/source/land_%s_source.png" % land_id],
			"generation_method": "gpt-image-2 edit reference + reviewed alpha mask",
		}
		if land_id == "ring_lagoon":
			asset.pop("navigation_channel_world_width", None)
			asset.update({
				"revision": "ring_passages_v3",
				"reviewed_entrance_count": 6,
				"reviewed_primary_gap_world": 728,
				"reviewed_secondary_gap_world": 520,
				"primary_navigation_channel_world_width": 624,
				"secondary_navigation_channel_world_width": 416,
				"generation_method": "reviewed source edit + deterministic irregular alpha mask; built-in gpt-image-2 candidate rejected for composition drift",
			})
		for index, current in enumerate(document.get("assets", [])):
			if current.get("semantic") == asset["semantic"]:
				document["assets"][index] = asset
				break
		else:
			document.setdefault("assets", []).append(asset)


def _update_land_manifest(document: dict) -> None:
	document.pop("runtime_uniform_scale_16x9", None)
	document.update({
		"generated_by": "imagegen built-in tool + chroma-key postprocess + reviewed alpha-mask finalization",
		"background_policy": "runtime textures are transparent PNG; generation and keyed intermediates are retained under generated/",
		"source_master_size_16x9": [3840, 2160],
		"runtime_target_size_16x9": RUNTIME_SIZE,
		"map_size_16x9": [6144, 3456],
		"world_center_16x9": [3072, 1728],
		"legacy_equivalent_scale": [4.86, 3.0375],
		"runtime_display_scale_16x9": RUNTIME_SCALE,
		"generation_manifest_16x9": "res://assets/environment/land/source/coastal_16x9_generation_manifest.json",
	})
	for asset in document.get("assets", []):
		land_id = str(asset.get("id", "")).removeprefix("land_")
		if land_id not in LAND_IDS:
			continue
		asset.pop("runtime_uniform_scale", None)
		asset.update({
			"source_chromakey": "res://assets/environment/land/generated/raw/land_%s_generated.png" % land_id,
			"source_keyed": "res://assets/environment/land/generated/keyed/land_%s_generated.png" % land_id,
			"source_master": "res://assets/environment/land/source/land_%s_source.png" % land_id,
			"runtime_texture_16x9": "res://assets/environment/land/land_%s_16x9_runtime.png" % land_id,
			"runtime_semantic_16x9": "land_%s_16x9_runtime" % land_id,
			"source_size": [3840, 2160],
			"runtime_size_16x9": RUNTIME_SIZE,
			"map_size_16x9": [6144, 3456],
			"world_center_16x9": [3072, 1728],
			"legacy_equivalent_scale": [4.86, 3.0375],
			"runtime_display_scale": RUNTIME_SCALE,
			"generation_method": "gpt-image-2 edit reference + reviewed alpha mask",
			"runtime_status_16x9": "runtime_asset_ready",
		})
		if land_id == "ring_lagoon":
			asset.pop("navigation_channel_world_width", None)
			asset.update({
				"revision_16x9": "ring_passages_v3",
				"reviewed_entrance_count": 6,
				"reviewed_primary_gap_world": 728,
				"reviewed_secondary_gap_world": 520,
				"primary_navigation_channel_world_width": 624,
				"secondary_navigation_channel_world_width": 416,
				"generation_method": "reviewed source edit + deterministic irregular alpha mask; built-in gpt-image-2 candidate rejected for composition drift",
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
	base_templates = {item["id"]: item for item in templates_document["definitions"]}
	for land_id in LAND_IDS:
		base = base_templates["terrain.template.%s" % land_id]
		_replace_or_append(templates_document["definitions"], _transform_template(base, land_id))
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
