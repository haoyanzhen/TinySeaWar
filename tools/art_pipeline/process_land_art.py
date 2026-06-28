#!/usr/bin/env python3
import argparse
import json
import math
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


def _boundary_loops(component: dict) -> list[list[tuple[int, int]]]:
	"""Trace pixel-cell edges in contour order instead of radial angle order."""
	point_set = set(component["points"])
	edges: list[tuple[tuple[int, int], tuple[int, int]]] = []
	for x, y in component["points"]:
		if (x, y - 1) not in point_set:
			edges.append(((x, y), (x + 1, y)))
		if (x + 1, y) not in point_set:
			edges.append(((x + 1, y), (x + 1, y + 1)))
		if (x, y + 1) not in point_set:
			edges.append(((x + 1, y + 1), (x, y + 1)))
		if (x - 1, y) not in point_set:
			edges.append(((x, y + 1), (x, y)))

	remaining = set(edges)
	loops: list[list[tuple[int, int]]] = []
	while remaining:
		start_edge = min(remaining)
		remaining.remove(start_edge)
		start, current = start_edge
		loop = [start, current]
		while current != start:
			candidates = sorted(edge for edge in remaining if edge[0] == current)
			if not candidates:
				break
			next_edge = candidates[0]
			remaining.remove(next_edge)
			current = next_edge[1]
			loop.append(current)
		if len(loop) >= 4 and loop[-1] == loop[0]:
			loops.append(loop[:-1])
	return loops


def _point_line_distance(point: tuple[int, int], start: tuple[int, int], end: tuple[int, int]) -> float:
	if start == end:
		return math.dist(point, start)
	dx, dy = end[0] - start[0], end[1] - start[1]
	return abs(dy * point[0] - dx * point[1] + end[0] * start[1] - end[1] * start[0]) / math.hypot(dx, dy)


def _rdp(points: list[tuple[int, int]], epsilon: float) -> list[tuple[int, int]]:
	if len(points) <= 2:
		return points
	maximum_distance = 0.0
	maximum_index = 0
	for index in range(1, len(points) - 1):
		distance = _point_line_distance(points[index], points[0], points[-1])
		if distance > maximum_distance:
			maximum_distance = distance
			maximum_index = index
	if maximum_distance <= epsilon:
		return [points[0], points[-1]]
	left = _rdp(points[: maximum_index + 1], epsilon)
	right = _rdp(points[maximum_index:], epsilon)
	return left[:-1] + right


def _simplify_contour(points: list[tuple[int, int]], target: int) -> list[list[int]]:
	if len(points) <= target:
		return [[int(x), int(y)] for x, y in points]
	anchor_index = min(range(len(points)), key=lambda index: points[index])
	ordered = points[anchor_index:] + points[:anchor_index]
	closed = ordered + [ordered[0]]
	epsilon = 0.75
	simplified = closed
	while len(simplified) - 1 > target and epsilon <= 32.0:
		simplified = _rdp(closed, epsilon)
		epsilon *= 1.25
	result = simplified[:-1]
	if len(result) > target:
		step = len(result) / float(target)
		result = [result[int(index * step)] for index in range(target)]
	return [[int(x), int(y)] for x, y in result]


def build_collision_entry(path: Path, alpha_threshold: int, min_area: int, max_vertices: int) -> dict:
	image, mask = _load_alpha(path, alpha_threshold)
	width, height = image.size
	components = _component_masks(mask, min_area)
	polygons = []
	for component in components:
		loops = _boundary_loops(component)
		if not loops:
			continue
		boundary = max(loops, key=len)
		polygon = _simplify_contour(boundary, max_vertices)
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
		if path.name.endswith("_source.png") or path.name.endswith("_contact_sheet.png") or path.name.endswith("_runtime.png"):
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
