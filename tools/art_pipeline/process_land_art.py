#!/usr/bin/env python3
import argparse
import json
from collections import deque
from pathlib import Path

from PIL import Image


def _load_alpha(path: Path, alpha_threshold: int) -> tuple[Image.Image, list[list[bool]]]:
	image = Image.open(path).convert("RGBA")
	alpha = image.getchannel("A")
	width, height = image.size
	mask = [[False for _ in range(width)] for _ in range(height)]
	for y in range(height):
		for x in range(width):
			mask[y][x] = alpha.getpixel((x, y)) >= alpha_threshold
	return image, mask


def _component_masks(mask: list[list[bool]], min_area: int) -> list[dict]:
	height = len(mask)
	width = len(mask[0]) if height > 0 else 0
	seen = [[False for _ in range(width)] for _ in range(height)]
	components = []
	for y in range(height):
		for x in range(width):
			if seen[y][x] or not mask[y][x]:
				continue
			queue = deque([(x, y)])
			seen[y][x] = True
			points = []
			while queue:
				px, py = queue.popleft()
				points.append((px, py))
				for nx, ny in ((px + 1, py), (px - 1, py), (px, py + 1), (px, py - 1)):
					if nx < 0 or ny < 0 or nx >= width or ny >= height:
						continue
					if seen[ny][nx] or not mask[ny][nx]:
						continue
					seen[ny][nx] = True
					queue.append((nx, ny))
			if len(points) >= min_area:
				components.append({"area": len(points), "points": points})
	return sorted(components, key=lambda item: item["area"], reverse=True)


def _boundary_points(component: dict, width: int, height: int) -> list[tuple[int, int]]:
	point_set = set(component["points"])
	boundary = []
	for x, y in component["points"]:
		for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
			if nx < 0 or ny < 0 or nx >= width or ny >= height or (nx, ny) not in point_set:
				boundary.append((x, y))
				break
	center_x = sum(point[0] for point in boundary) / max(1, len(boundary))
	center_y = sum(point[1] for point in boundary) / max(1, len(boundary))
	return sorted(boundary, key=lambda point: __import__("math").atan2(point[1] - center_y, point[0] - center_x))


def _simplify_radial(points: list[tuple[int, int]], target: int) -> list[list[int]]:
	if len(points) <= target:
		return [[int(x), int(y)] for x, y in points]
	step = len(points) / float(target)
	simplified = []
	for index in range(target):
		x, y = points[int(index * step)]
		simplified.append([int(x), int(y)])
	return simplified


def build_collision_entry(path: Path, alpha_threshold: int, min_area: int, max_vertices: int) -> dict:
	image, mask = _load_alpha(path, alpha_threshold)
	width, height = image.size
	components = _component_masks(mask, min_area)
	polygons = []
	for component in components:
		boundary = _boundary_points(component, width, height)
		polygon = _simplify_radial(boundary, max_vertices)
		x_values = [point[0] for point in component["points"]]
		y_values = [point[1] for point in component["points"]]
		polygons.append({
			"area_px": component["area"],
			"bounds_px": [min(x_values), min(y_values), max(x_values), max(y_values)],
			"polygon_px": polygon,
		})
	return {
		"id": path.stem,
		"texture": "res://%s" % path.as_posix(),
		"size_px": [width, height],
		"alpha_threshold": alpha_threshold,
		"component_count": len(polygons),
		"collision_polygons": polygons,
	}


def main() -> None:
	parser = argparse.ArgumentParser()
	parser.add_argument("--land-dir", default="assets/environment/land")
	parser.add_argument("--out", default="assets/environment/land/land_collision_manifest.json")
	parser.add_argument("--alpha-threshold", type=int, default=24)
	parser.add_argument("--min-area", type=int, default=3200)
	parser.add_argument("--max-vertices", type=int, default=72)
	args = parser.parse_args()

	land_dir = Path(args.land_dir)
	entries = []
	for path in sorted(land_dir.glob("land_*.png")):
		if path.name.endswith("_source.png") or path.name.endswith("_contact_sheet.png"):
			continue
		entries.append(build_collision_entry(path, args.alpha_threshold, args.min_area, args.max_vertices))
	output = {
		"generated_by": "tools/art_pipeline/process_land_art.py",
		"edge_source": "alpha channel",
		"usage": "Collision polygons are gameplay/navigation candidates; tune per level before enabling obstruction rules.",
		"assets": entries,
	}
	Path(args.out).write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
	main()
