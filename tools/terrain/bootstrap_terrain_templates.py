#!/usr/bin/env python3
"""Build reviewed terrain templates from land candidates plus authored water regions.

The output is committed authoring data. Runtime never reads pixels or this bootstrap
script; changing a gameplay boundary requires regenerating and reviewing QA output.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from terrain_geometry import ellipse_polygon, ensure_clockwise, read_json, write_json


REGION_SPECS = {
	"land_broken_atoll": [
		("lagoon", "ShallowWater", ellipse_polygon((512, 512), (400, 395), 32), 30, ["ShallowDraft"]),
		("east_passage", "NavigationChannel", [[780, 335], [956, 390], [948, 610], [790, 650]], 70, ["Surface"]),
	],
	"land_central_sandbar": [
		("sand_flat", "ShallowWater", ellipse_polygon((510, 520), (405, 155), 28, -2), 45, ["ShallowDraft"]),
		("reef_margin", "ReefOrSandbar", ellipse_polygon((510, 520), (330, 105), 24, -2), 60, ["ReefCapable"]),
	],
	"land_crescent_bay": [
		("inner_bay", "ShallowWater", ellipse_polygon((665, 520), (285, 315), 30, -8), 45, ["ShallowDraft"]),
		("bay_entrance", "NavigationChannel", [[745, 242], [986, 280], [984, 655], [780, 690], [725, 585]], 70, ["Surface"]),
	],
	"land_double_island_long_channel": [
		("central_channel", "NavigationChannel", [[452, 65], [570, 65], [570, 959], [452, 959]], 80, ["Surface"]),
	],
	"land_dual_channel_reef_line": [
		("west_channel", "NavigationChannel", [[92, 245], [165, 175], [800, 860], [728, 920]], 80, ["Surface"]),
		("east_channel", "NavigationChannel", [[310, 75], [390, 55], [990, 690], [920, 760]], 80, ["Surface"]),
	],
	"land_harbor_mouth": [
		("inner_harbor", "ShallowWater", [[305, 235], [430, 135], [594, 135], [720, 235], [772, 590], [682, 792], [512, 875], [338, 792], [250, 590]], 45, ["ShallowDraft"]),
		("harbor_channel", "NavigationChannel", [[444, 80], [580, 80], [610, 760], [512, 842], [414, 760]], 85, ["Surface"]),
	],
	"land_long_archipelago": [
		("west_channel", "NavigationChannel", [[275, 60], [365, 55], [430, 975], [340, 980]], 78, ["Surface"]),
		("east_channel", "NavigationChannel", [[600, 45], [690, 45], [770, 980], [680, 980]], 78, ["Surface"]),
	],
	"land_offset_large_island": [
		("northeast_cove", "ShallowWater", ellipse_polygon((695, 300), (160, 108), 22, 8), 45, ["ShallowDraft"]),
		("east_cove", "ShallowWater", ellipse_polygon((715, 515), (145, 100), 22, -5), 45, ["ShallowDraft"]),
		("southeast_cove", "ShallowWater", ellipse_polygon((680, 745), (175, 112), 22, 12), 45, ["ShallowDraft"]),
	],
	"land_ring_lagoon": [
		("lagoon", "ShallowWater", ellipse_polygon((512, 515), (360, 345), 32), 46, ["ShallowDraft"]),
		("north_passage", "NavigationChannel", [[455, 15], [575, 15], [575, 245], [455, 245]], 82, ["Surface"]),
		("south_passage", "NavigationChannel", [[455, 785], [575, 785], [575, 1010], [455, 1010]], 82, ["Surface"]),
	],
	"land_scattered_islands": [
		("northwest_shelf", "ShallowWater", ellipse_polygon((260, 260), (180, 145), 24, -18), 44, ["ShallowDraft"]),
		("northeast_shelf", "ShallowWater", ellipse_polygon((760, 250), (160, 125), 24, -22), 44, ["ShallowDraft"]),
		("southwest_shelf", "ShallowWater", ellipse_polygon((285, 740), (155, 130), 24, 20), 44, ["ShallowDraft"]),
		("southeast_shelf", "ShallowWater", ellipse_polygon((760, 735), (175, 135), 24, 16), 44, ["ShallowDraft"]),
	],
}

AUTO_SHELF_ASSETS = {
	"land_double_island_long_channel": 1.11,
	"land_dual_channel_reef_line": 1.16,
	"land_long_archipelago": 1.13,
}

FACILITY_ANCHOR_SPECS = {
	"land_harbor_mouth": [
		("observation_west", [220, 245], -20, "land_harbor_mouth.land_02", [[350, 210], [455, 220], [455, 330], [345, 320]]),
		("battery_west", [220, 410], -5, "land_harbor_mouth.land_02", [[374, 350], [500, 355], [500, 465], [382, 470]]),
		("mine_control_west", [170, 565], 5, "land_harbor_mouth.land_02", [[320, 510], [430, 520], [430, 625], [320, 620]]),
		("supply_west", [225, 715], 18, "land_harbor_mouth.land_02", [[365, 645], [492, 650], [492, 785], [380, 790]]),
		("radar_east", [820, 245], 200, "land_harbor_mouth.land_01", [[570, 215], [680, 210], [690, 320], [575, 330]]),
		("communication_east", [850, 410], 185, "land_harbor_mouth.land_01", [[525, 355], [652, 350], [646, 472], [525, 465]]),
		("airfield_east", [855, 610], 170, "land_harbor_mouth.land_01", [[535, 535], [685, 525], [695, 655], [540, 665]]),
		("repair_berth_east", [795, 738], 155, "land_harbor_mouth.land_01", [[520, 665], [665, 650], [690, 790], [540, 812]]),
	],
}


def build_templates(candidates: dict) -> list[dict]:
	entries = {entry["id"]: entry for entry in candidates.get("assets", [])}
	templates = []
	for asset_id in sorted(REGION_SPECS):
		candidate = entries[asset_id]
		obstacles = []
		for index, component in enumerate(candidate.get("collision_polygons", [])):
			if int(component.get("area_px", 0)) < 3200:
				continue
			obstacles.append({
				"id": "%s.land_%02d" % (asset_id, index + 1),
				"polygon": ensure_clockwise(component["polygon_px"]),
				"block_mask": ["ShipMovement", "TorpedoTravel", "ShellTravel", "SurfaceOpticalLineOfSight"],
				"height_class": "Island",
			})
		regions = []
		if asset_id in AUTO_SHELF_ASSETS:
			factor = AUTO_SHELF_ASSETS[asset_id]
			for index, obstacle in enumerate(obstacles):
				polygon = obstacle["polygon"]
				center_x = sum(point[0] for point in polygon) / len(polygon)
				center_y = sum(point[1] for point in polygon) / len(polygon)
				shelf_polygon = []
				for point in polygon:
					candidate_point = [
						max(0.0, min(float(candidate["size_px"][0]), center_x + (point[0] - center_x) * factor)),
						max(0.0, min(float(candidate["size_px"][1]), center_y + (point[1] - center_y) * factor)),
					]
					if not shelf_polygon or candidate_point != shelf_polygon[-1]:
						shelf_polygon.append(candidate_point)
				if len(shelf_polygon) > 2 and shelf_polygon[0] == shelf_polygon[-1]:
					shelf_polygon.pop()
				regions.append({
					"id": "%s.shelf_%02d" % (asset_id, index + 1),
					"region_type": "ShallowWater",
					"polygon": ensure_clockwise(shelf_polygon),
					"priority": 44,
					"access_tags": ["ShallowDraft"],
					"effect_profile_id": "terrain.effect.shallowwater",
				})
		for suffix, region_type, polygon, priority, access_tags in REGION_SPECS[asset_id]:
			regions.append({
				"id": "%s.%s" % (asset_id, suffix),
				"region_type": region_type,
				"polygon": ensure_clockwise(polygon),
				"priority": priority,
				"access_tags": access_tags,
				"effect_profile_id": "terrain.effect.%s" % region_type.lower(),
			})
		visual_regions = []
		for index, obstacle in enumerate(obstacles):
			polygon = obstacle["polygon"]
			center_x = sum(point[0] for point in polygon) / len(polygon)
			center_y = sum(point[1] for point in polygon) / len(polygon)
			for suffix, factor, semantic, z_index, opacity in [
				("sediment", 1.075, "shore_sediment_overlay", 5, 0.13),
				("breaker", 1.045, "shore_breaker_overlay", 7, 0.22),
				("wet_rock", 1.018, "shore_wet_rock_overlay", 8, 0.16),
			]:
				expanded = []
				for point in polygon:
					candidate_point = [
						max(0.0, min(float(candidate["size_px"][0]), center_x + (point[0] - center_x) * factor)),
						max(0.0, min(float(candidate["size_px"][1]), center_y + (point[1] - center_y) * factor)),
					]
					if not expanded or candidate_point != expanded[-1]:
						expanded.append(candidate_point)
				if len(expanded) > 2 and expanded[0] == expanded[-1]:
					expanded.pop()
				if len(expanded) >= 3:
					visual_regions.append({
						"id": "%s.%s_%02d" % (asset_id, suffix, index + 1),
						"polygon": ensure_clockwise(expanded),
						"asset_semantic": semantic,
						"z_index": z_index,
						"opacity": opacity,
					})
		anchors = []
		for suffix, position, heading, shore_obstacle_id, interaction_polygon in FACILITY_ANCHOR_SPECS.get(asset_id, []):
			anchor = {
				"id": "%s.%s" % (asset_id, suffix),
				"position": position,
				"heading": heading,
				"interaction_water_polygon": ensure_clockwise(interaction_polygon),
				"target_shape": {"shape_type": "Circle", "radius": 28.0},
				"shore_obstacle_id": shore_obstacle_id,
			}
			if suffix == "battery_west":
				anchor["muzzle_position"] = [405, 410]
			if suffix == "observation_west":
				anchor["observation_position"] = [390, 245]
			anchors.append(anchor)
		templates.append({
			"id": "terrain.template.%s" % asset_id.removeprefix("land_"),
			"definition_type": "TerrainAssetTemplate",
			"display_name": asset_id.removeprefix("land_").replace("_", " ").title(),
			"asset_id": asset_id,
			"texture": candidate["texture"],
			"local_size": candidate["size_px"],
			"origin": [candidate["size_px"][0] / 2.0, candidate["size_px"][1] / 2.0],
			"review_status": "reviewed_semantic_source",
			"obstacles": obstacles,
			"regions": regions,
			"visual_regions": visual_regions,
			"facility_anchors": anchors,
		})
	return templates


def main() -> None:
	parser = argparse.ArgumentParser()
	parser.add_argument("--candidates", default="assets/environment/land/land_collision_manifest.json")
	parser.add_argument("--out", default="data/terrain/terrain_templates.json")
	args = parser.parse_args()
	candidates = read_json(args.candidates)
	write_json(args.out, {"schema_version": 1, "definitions": build_templates(candidates)})


if __name__ == "__main__":
	main()
