#!/usr/bin/env python3
"""Render reviewed terrain semantics, safe boundaries, facilities, and paths."""

from __future__ import annotations

import argparse
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from terrain_geometry import read_json
from query_terrain import first_hit

ROOT = Path(__file__).resolve().parents[2]
LANCZOS = getattr(Image, "Resampling", Image).LANCZOS
BICUBIC = getattr(Image, "Resampling", Image).BICUBIC
REGION_COLORS = {
	"CoastalWater": (75, 177, 185, 72),
	"ShallowWater": (84, 218, 205, 105),
	"ReefOrSandbar": (218, 196, 126, 118),
	"NavigationChannel": (87, 195, 224, 95),
}


def _font(size: int):
	for path in ["/System/Library/Fonts/PingFang.ttc", "/System/Library/Fonts/Supplemental/Arial.ttf"]:
		if Path(path).exists():
			return ImageFont.truetype(path, size)
	return ImageFont.load_default()


def _background(size: tuple[int, int]) -> Image.Image:
	image = Image.new("RGBA", size, (20, 67, 82, 255))
	draw = ImageDraw.Draw(image)
	for y in range(18, size[1], 34):
		draw.line([(0, y), (size[0], y + 5)], fill=(67, 139, 151, 24), width=2)
	return image


def _fit_transform(source_size, target_box):
	x, y, width, height = target_box
	scale = min(width / float(source_size[0]), height / float(source_size[1]))
	offset = (x + (width - source_size[0] * scale) * 0.5, y + (height - source_size[1] * scale) * 0.5)
	return scale, offset


def _points(polygon, scale, offset):
	return [(offset[0] + float(point[0]) * scale, offset[1] + float(point[1]) * scale) for point in polygon]


def _draw_semantics(image: Image.Image, definition: dict, box, show_labels=True, spawn_count=0) -> None:
	draw = ImageDraw.Draw(image, "RGBA")
	source_size = definition.get("local_size", definition.get("map_size", [1024, 1024]))
	scale, offset = _fit_transform(source_size, box)
	for region in sorted(definition.get("regions", []), key=lambda item: int(item.get("priority", 0))):
		color = REGION_COLORS.get(region.get("region_type"), (125, 185, 185, 50))
		polygon = _points(region.get("polygon", []), scale, offset)
		if len(polygon) >= 3:
			draw.polygon(polygon, fill=color, outline=(*color[:3], 210))
			if region.get("region_type") == "NavigationChannel":
				center_x = sum(point[0] for point in polygon) / len(polygon)
				center_y = sum(point[1] for point in polygon) / len(polygon)
				draw.ellipse([center_x-3, center_y-3, center_x+3, center_y+3], fill=(190, 242, 237, 220))
	for obstacle in definition.get("obstacles", []):
		polygon = _points(obstacle.get("polygon", []), scale, offset)
		if len(polygon) >= 3:
			draw.line(polygon + [polygon[0]], fill=(237, 129, 107, 235), width=2)
	for anchor in definition.get("facility_anchors", []):
		position = _points([anchor.get("position", [0, 0])], scale, offset)[0]
		draw.ellipse([position[0]-5, position[1]-5, position[0]+5, position[1]+5], fill=(255, 206, 91, 255), outline=(47, 65, 66, 255), width=2)
		polygon = _points(anchor.get("interaction_water_polygon", []), scale, offset)
		if len(polygon) >= 3:
			draw.line(polygon + [polygon[0]], fill=(255, 206, 91, 190), width=2)
	for spawn in definition.get("spawn_points", []):
		spawn_suffix = str(spawn.get("id", "")).rsplit("_", 1)[-1]
		if spawn_count > 0 and spawn_suffix.isdigit() and int(spawn_suffix) > spawn_count:
			continue
		position = _points([spawn["position"]], scale, offset)[0]
		color = (98, 229, 184, 255) if spawn.get("faction_id") == "player" else (235, 105, 103, 255)
		radius = max(3.0, float(spawn.get("radius", 20.0)) * scale)
		draw.ellipse([position[0]-radius, position[1]-radius, position[0]+radius, position[1]+radius], outline=color, width=2)


def _paste_visuals(image: Image.Image, definition: dict, box) -> None:
	source_size = definition.get("local_size", definition.get("map_size", [1024, 1024]))
	scale, offset = _fit_transform(source_size, box)
	if definition.get("definition_type") == "TerrainAssetTemplate":
		path = ROOT / definition["texture"].removeprefix("res://")
		texture = Image.open(path).convert("RGBA")
		texture = texture.resize((round(texture.width * scale), round(texture.height * scale)), LANCZOS)
		image.alpha_composite(texture, (round(offset[0]), round(offset[1])))
		return
	for instance in definition.get("visual_instances", []):
		path = ROOT / instance["texture"].removeprefix("res://")
		texture = Image.open(path).convert("RGBA")
		world_width = float(instance["local_size"][0]) * float(instance["scale"][0])
		world_height = float(instance["local_size"][1]) * float(instance["scale"][1])
		texture = texture.resize((round(world_width * scale), round(world_height * scale)), LANCZOS)
		rotation = float(instance.get("rotation_degrees", 0.0))
		if rotation:
			texture = texture.rotate(-rotation, resample=BICUBIC, expand=True)
		position = _points([instance["position"]], scale, offset)[0]
		image.alpha_composite(texture, (round(position[0] - texture.width * 0.5), round(position[1] - texture.height * 0.5)))


def render_templates(path: Path) -> None:
	document = read_json(ROOT / "data/terrain/terrain_templates.json")
	definitions = sorted(document.get("definitions", []), key=lambda item: item["id"])
	cell_width, cell_height = 520, 540
	image = _background((cell_width * 5, cell_height * 2 + 80))
	draw = ImageDraw.Draw(image)
	for index, definition in enumerate(definitions):
		x = (index % 5) * cell_width
		y = (index // 5) * cell_height + 60
		box = (x + 20, y + 10, cell_width - 40, cell_height - 70)
		_draw_semantics(image, definition, box)
		_paste_visuals(image, definition, box)
		name = definition["id"].removeprefix("terrain.template.")
		draw.text((x + 22, y + cell_height - 50), name, font=_font(22), fill=(232, 247, 243, 255))
		draw.text((x + 22, y + cell_height - 25), "%d hard / %d water regions" % (len(definition.get("obstacles", [])), len(definition.get("regions", []))), font=_font(15), fill=(159, 206, 207, 255))
	draw.text((28, 18), "TinySeaWar terrain templates: turquoise=shallow, blue=channel, sand=reef, coral=hard boundary", font=_font(24), fill=(238, 250, 246, 255))
	path.parent.mkdir(parents=True, exist_ok=True)
	image.save(path)


def render_map(path: Path, terrain_id: str, spawn_count: int, view_size: tuple[float, float] | None) -> None:
	definitions = read_json(ROOT / "data/terrain/terrain_definitions.json")["definitions"]
	definition = next((item for item in definitions if item["id"] == terrain_id), None)
	if definition is None:
		raise ValueError("Unknown terrain map %s" % terrain_id)
	image = _background((1920, 1080))
	box = (30, 40, 1860, 1000)
	_draw_semantics(image, definition, box, spawn_count=spawn_count)
	_paste_visuals(image, definition, box)
	draw = ImageDraw.Draw(image, "RGBA")
	scale, offset = _fit_transform(definition["map_size"], box)
	query_specs = []
	if terrain_id == "terrain.map.harbor_mouth":
		query_specs = [
			("ShipMovement", [700, 1060], [2050, 1060], 28.0, (104, 236, 190, 210)),
			("TorpedoTravel", [700, 1120], [2050, 1120], 8.0, (246, 213, 91, 220)),
			("ShellTravel", [700, 1180], [2050, 1180], 0.0, (240, 139, 105, 220)),
			("SurfaceOpticalLineOfSight", [700, 1240], [2050, 1240], 0.0, (194, 169, 239, 220)),
		]
	for mask, start, end, radius, color in query_specs:
		hit = first_hit(definition, start, end, radius, mask)
		start_draw, end_draw = _points([start, end], scale, offset)
		draw.line([start_draw, end_draw], fill=color, width=3)
		if hit["hit"]:
			hit_draw = _points([hit["position"]], scale, offset)[0]
			draw.ellipse([hit_draw[0]-6, hit_draw[1]-6, hit_draw[0]+6, hit_draw[1]+6], fill=color, outline=(255,255,255,240), width=2)
			normal = hit.get("normal", [0.0, 0.0])
			draw.line([hit_draw, (hit_draw[0]+normal[0]*30, hit_draw[1]+normal[1]*30)], fill=(255,255,255,230), width=2)
	if view_size is not None:
		map_width, map_height = definition["map_size"]
		view_width, view_height = view_size
		view_origin = [(map_width - view_width) * 0.5, (map_height - view_height) * 0.5]
		top_left, bottom_right = _points(
			[view_origin, [view_origin[0] + view_width, view_origin[1] + view_height]],
			scale,
			offset,
		)
		draw.rectangle([top_left, bottom_right], outline=(255, 225, 112, 245), width=4)
		draw.text((top_left[0] + 14, top_left[1] + 12), "current coastal max view  %.0f x %.0f" % view_size, font=_font(20), fill=(255, 235, 146, 255))
	draw.rectangle([30, 40, 1890, 1040], outline=(125, 206, 211, 230), width=3)
	draw.text((52, 54), "%s: reviewed geometry + %s-ship fleet slots" % (definition["id"], spawn_count), font=_font(27), fill=(239, 251, 247, 255))
	path.parent.mkdir(parents=True, exist_ok=True)
	image.save(path)


def main() -> None:
	parser = argparse.ArgumentParser()
	parser.add_argument("--mode", choices=["templates", "map"], default="templates")
	parser.add_argument("--out", default="assets/environment/qa/terrain_template_review.png")
	parser.add_argument("--terrain-id", default="terrain.map.harbor_mouth")
	parser.add_argument("--spawn-count", type=int, default=3)
	parser.add_argument("--view-size", default="")
	args = parser.parse_args()
	view_size = None
	if args.view_size:
		parts = args.view_size.lower().split("x")
		if len(parts) != 2:
			raise ValueError("--view-size must use WIDTHxHEIGHT")
		view_size = (float(parts[0]), float(parts[1]))
	if args.mode == "templates":
		render_templates(ROOT / args.out)
	else:
		render_map(ROOT / args.out, args.terrain_id, args.spawn_count, view_size)


if __name__ == "__main__":
	main()
