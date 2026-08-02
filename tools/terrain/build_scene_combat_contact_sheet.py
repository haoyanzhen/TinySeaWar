#!/usr/bin/env python3
"""Build the project-level terrain/facility/environment/path QA overview."""

from __future__ import annotations

import argparse
import json
import math
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from terrain_geometry import sample_polyline
from query_route import _path

ROOT = Path(__file__).resolve().parents[2]
LANCZOS = getattr(Image, "Resampling", Image).LANCZOS


def _font(size):
	path = Path("/System/Library/Fonts/PingFang.ttc")
	return ImageFont.truetype(str(path), size) if path.exists() else ImageFont.load_default()


def _asset_grid() -> Image.Image:
	paths = [
		"assets/environment/terrain/terrain_shallow_water_fill_tile.png", "assets/environment/terrain/terrain_reef_sandbar_overlay.png",
		"assets/environment/weather/zones/environment_sea_fog_mask.png", "assets/environment/weather/zones/environment_rain_squall_mask.png",
		"assets/environment/facilities/facility_coastal_observation_post_base.png", "assets/environment/facilities/facility_coastal_battery_base.png",
		"assets/environment/facilities/facility_forward_supply_point_base.png", "assets/environment/facilities/facility_coastal_airfield_base.png",
		"assets/environment/facilities/facility_radar_station_base.png", "assets/environment/facilities/facility_communication_station_base.png",
		"assets/environment/facilities/facility_mine_control_station_base.png", "assets/environment/facilities/facility_repair_berth_base.png",
		"assets/vfx/combat/environment/vfx_environment_shell_terrain_impact_large_01.png", "assets/vfx/combat/environment/vfx_environment_torpedo_terrain_impact_01.png",
	]
	image = Image.new("RGBA", (920, 1010), (20, 67, 82, 255))
	draw = ImageDraw.Draw(image)
	for index, relative_path in enumerate(paths):
		asset = Image.open(ROOT / relative_path).convert("RGBA")
		asset.thumbnail((190, 175), LANCZOS)
		x = 20 + (index % 4) * 225 + (190 - asset.width) // 2
		y = 25 + (index // 4) * 235
		image.alpha_composite(asset, (x, y))
		draw.text((18 + (index % 4) * 225, y + 182), Path(relative_path).stem.replace("facility_", "").replace("environment_", "")[:25], font=_font(14), fill=(226, 245, 241, 255))
	return image


def _navigation_panel() -> Image.Image:
	terrain = json.loads((ROOT / "data/terrain/terrain_definitions.json").read_text(encoding="utf-8"))["definitions"][0]
	navigation_profiles = json.loads((ROOT / "data/terrain/navigation_definitions.json").read_text(encoding="utf-8"))["definitions"][0]["profiles"]
	layouts = json.loads((ROOT / "data/facilities/facility_definitions.json").read_text(encoding="utf-8"))["definitions"]
	layout = next(item for item in layouts if item["id"] == "facility.layout.harbor_mouth")
	image = Image.new("RGBA", (1240, 620), (20, 67, 82, 255))
	draw = ImageDraw.Draw(image, "RGBA")
	sx, sy = 1240 / terrain["map_size"][0], 620 / terrain["map_size"][1]
	convert = lambda point: (float(point[0]) * sx, float(point[1]) * sy)
	for obstacle in terrain.get("obstacles", []):
		draw.polygon([convert(point) for point in obstacle["polygon"]], fill=(46, 65, 60, 235), outline=(231, 134, 105, 240))
	for node in navigation_profiles[0].get("nodes", []):
		x, y = convert(node["position"])
		draw.ellipse([x-1, y-1, x+1, y+1], fill=(105, 197, 197, 105))
	anchors = {item["id"]: item for item in terrain.get("facility_anchors", [])}
	placements = {item["id"]: item for item in layout.get("placements", [])}
	for placement in placements.values():
		position = convert(anchors[placement["anchor_id"]]["position"])
		for dependency in placement.get("requires_all_active", []):
			if dependency in placements:
				dependency_position = convert(anchors[placements[dependency]["anchor_id"]]["position"])
				draw.line([position, dependency_position], fill=(240, 200, 95, 175), width=3)
		draw.ellipse([position[0]-5, position[1]-5, position[0]+5, position[1]+5], fill=(247, 210, 105, 255), outline=(35, 55, 57, 255), width=2)
	mines = json.loads((ROOT / "data/facilities/minefield_definitions.json").read_text(encoding="utf-8"))["definitions"]
	for minefield in mines:
		draw.polygon([convert(point) for point in minefield.get("polygon", [])], fill=(245, 76, 67, 50), outline=(247, 112, 92, 210))
		for safe_channel in minefield.get("safe_channels", []):
			draw.line([convert(point) for point in safe_channel] + [convert(safe_channel[0])], fill=(91, 239, 179, 225), width=3)
	# Draw the actual A* routes shared by player and AI for all supported hull profiles.
	start, end = [2048.0, 1870.0], [2048.0, 250.0]
	route_colors = [(101, 232, 190, 245), (102, 188, 240, 235), (246, 205, 92, 230)]
	for index, profile in enumerate(navigation_profiles):
		route = _path(profile, start, end)
		if route:
			draw.line([convert(point) for point in route], fill=route_colors[index % len(route_colors)], width=5 - index, joint="curve")
		draw.text((20 + index * 310, 54), "%s  r=%d" % (profile["id"].removeprefix("navigation.profile."), int(profile["radius"])), font=_font(15), fill=route_colors[index % len(route_colors)])
	draw.text((20, 18), "Shared A* navigation + facility dependencies + mine safety QA", font=_font(25), fill=(238, 250, 246, 255))
	return image


def _timeline_panel() -> Image.Image:
	document = json.loads((ROOT / "data/environments/environment_zone_definitions.json").read_text(encoding="utf-8"))
	zone_set = next(item for item in document["definitions"] if item["id"] == "environment.zone_set.harbor_mouth")
	image = Image.new("RGBA", (1240, 620), (20, 67, 82, 255))
	draw = ImageDraw.Draw(image, "RGBA")
	colors = [(215,235,232,75),(64,91,106,100),(210,244,238,65),(79,183,186,55),(198,221,207,60),(85,216,207,65),(154,198,166,60)]
	for frame_index, seconds in enumerate((0, 60, 120, 180)):
		x0 = 12 + frame_index * 306
		y0 = 58
		width, height = 292, 520
		draw.rectangle([x0, y0, x0+width, y0+height], fill=(16, 55, 70, 255), outline=(108, 188, 194, 180), width=2)
		for zone_index, zone in enumerate(zone_set.get("zones", [])):
			if not zone.get("active", True) or (zone.get("duration", 0.0) > 0.0 and seconds >= float(zone["duration"])):
				continue
			distance = float(zone.get("drift_speed", 0.0)) * seconds
			if len(zone.get("drift_path", [])) >= 2:
				offset = sample_polyline(zone["drift_path"], distance)
			else:
				heading = math.radians(float(zone.get("heading", 0.0)))
				offset = (math.cos(heading) * distance, math.sin(heading) * distance)
			points = [(x0 + (float(point[0])+offset[0]) / 4096.0 * width, y0 + (float(point[1])+offset[1]) / 2304.0 * height) for point in zone["polygon"]]
			draw.polygon(points, fill=colors[zone_index % len(colors)], outline=(*colors[zone_index % len(colors)][:3], 150))
		draw.text((x0+10, y0+8), "T+%ds" % seconds, font=_font(20), fill=(236, 249, 245, 255))
	draw.text((16, 16), "Fixed-tick environment timeline (same definitions, deterministic drift)", font=_font(25), fill=(238, 250, 246, 255))
	return image


def main() -> int:
	parser = argparse.ArgumentParser()
	parser.add_argument("--out", default="assets/environment/qa/scene_combat_contact_sheet.png")
	args = parser.parse_args()
	qa_dir = ROOT / "assets/environment/qa"
	qa_dir.mkdir(parents=True, exist_ok=True)
	commands = [
		[sys.executable, "tools/terrain/render_terrain_qa.py", "--mode", "templates", "--out", "assets/environment/qa/terrain_template_review.png"],
		[sys.executable, "tools/terrain/render_terrain_qa.py", "--mode", "map", "--out", "assets/environment/qa/harbor_map_review.png"],
		[sys.executable, "tools/terrain/build_minimap_masks.py"],
	]
	for command in commands:
		result = subprocess.run(command, cwd=ROOT, check=False)
		if result.returncode != 0:
			return result.returncode
	templates = Image.open(qa_dir / "terrain_template_review.png").convert("RGBA")
	harbor = Image.open(qa_dir / "harbor_map_review.png").convert("RGBA")
	assets = _asset_grid()
	navigation = _navigation_panel()
	timeline = _timeline_panel()
	canvas = Image.new("RGBA", (2560, 2990), (15, 54, 67, 255))
	draw = ImageDraw.Draw(canvas)
	draw.text((38, 22), "TinySeaWar Scene Combat Terrain QA", font=_font(36), fill=(240, 251, 247, 255))
	canvas.alpha_composite(templates.resize((2500, 1125), LANCZOS), (30, 80))
	canvas.alpha_composite(harbor.resize((1550, 872), LANCZOS), (30, 1235))
	canvas.alpha_composite(assets.resize((920, 1010), LANCZOS), (1610, 1235))
	canvas.alpha_composite(navigation, (30, 2260))
	canvas.alpha_composite(timeline, (1290, 2260))
	draw.text((35, 2935), "Single source: authored templates -> baked world geometry -> navigation/minimap/runtime/QA", font=_font(25), fill=(157, 211, 211, 255))
	path = ROOT / args.out
	path.parent.mkdir(parents=True, exist_ok=True)
	canvas.save(path)
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
