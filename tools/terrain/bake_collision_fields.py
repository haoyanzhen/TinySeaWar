#!/usr/bin/env python3
"""Bake conservative ship-movement occupancy and clearance fields.

The field is a derived acceleration structure. TerrainMap ShipMovement polygons
and the map boundary remain authoritative; ambiguous cells fall back to exact
polygon sweeps at runtime.
"""

from __future__ import annotations

import argparse
import hashlib
import math
import struct
import sys
from array import array
from pathlib import Path

from PIL import Image, ImageDraw

from terrain_geometry import read_json, write_json


ROOT = Path(__file__).resolve().parents[2]
MAGIC = b"TSCF"
SCHEMA_VERSION = 2
ALGORITHM_VERSION = 2
DEFAULT_CELL_SIZE = 8.0
QUANTIZATION_GUARD = 1.0
HEADER = struct.Struct("<4sHHIIfffIH32s32sIII")
INFINITY = 1.0e30
RESTRICTION_MASKS = {"ShallowWater": 1, "ReefOrSandbar": 2}


def _path(value: str | Path) -> Path:
	path = Path(value)
	return path if path.is_absolute() else ROOT / path


def _field_id(terrain_id: str) -> str:
	return "collision_field.%s" % terrain_id


def _file_name(terrain_id: str) -> str:
	return terrain_id.replace("terrain.map.", "terrain_map_").replace(".", "_") + ".tscf"


def source_geometry_text(terrain: dict) -> str:
	map_size = terrain.get("map_size", [0.0, 0.0])
	parts = [
		str(terrain.get("id", "")),
		str(int(terrain.get("navigation_revision", 0))),
		"%.3f,%.3f" % (float(map_size[0]), float(map_size[1])),
	]
	obstacles = [item for item in terrain.get("obstacles", []) if "ShipMovement" in item.get("block_mask", [])]
	for obstacle in sorted(obstacles, key=lambda item: str(item.get("id", ""))):
		parts.append(str(obstacle.get("id", "")))
		parts.append(",".join(sorted(str(value) for value in obstacle.get("block_mask", []))))
		parts.append(";".join("%.3f,%.3f" % (float(point[0]), float(point[1])) for point in obstacle.get("polygon", [])))
	restricted_regions = [item for item in terrain.get("regions", []) if item.get("region_type") in RESTRICTION_MASKS]
	for region in sorted(restricted_regions, key=lambda item: str(item.get("id", ""))):
		parts.append(str(region.get("id", "")))
		parts.append(str(region.get("region_type", "")))
		parts.append(str(int(region.get("priority", 0))))
		parts.append(";".join("%.3f,%.3f" % (float(point[0]), float(point[1])) for point in region.get("polygon", [])))
	return "|".join(parts)


def source_geometry_checksum(terrain: dict) -> str:
	return hashlib.sha256(source_geometry_text(terrain).encode("utf-8")).hexdigest()


def _supercover_cells(start: tuple[float, float], end: tuple[float, float], width: int, height: int):
	"""Yield every grid cell touched by a line, including corner side-cells."""
	x0, y0 = start
	x1, y1 = end
	cell_x, cell_y = math.floor(x0), math.floor(y0)
	end_x, end_y = math.floor(x1), math.floor(y1)
	step_x = 1 if x1 > x0 else -1 if x1 < x0 else 0
	step_y = 1 if y1 > y0 else -1 if y1 < y0 else 0
	dx, dy = x1 - x0, y1 - y0
	t_delta_x = abs(1.0 / dx) if step_x else INFINITY
	t_delta_y = abs(1.0 / dy) if step_y else INFINITY
	next_x = float(cell_x + 1) if step_x > 0 else float(cell_x)
	next_y = float(cell_y + 1) if step_y > 0 else float(cell_y)
	t_max_x = (next_x - x0) / dx if step_x else INFINITY
	t_max_y = (next_y - y0) / dy if step_y else INFINITY
	seen: set[tuple[int, int]] = set()
	while True:
		if 0 <= cell_x < width and 0 <= cell_y < height and (cell_x, cell_y) not in seen:
			seen.add((cell_x, cell_y))
			yield cell_x, cell_y
		if cell_x == end_x and cell_y == end_y:
			break
		# Once one coordinate reaches an endpoint cell, do not let floating-point
		# ordering at t=1 step it past the target while the other axis catches up.
		effective_t_max_x = t_max_x if cell_x != end_x else INFINITY
		effective_t_max_y = t_max_y if cell_y != end_y else INFINITY
		if effective_t_max_x < effective_t_max_y:
			cell_x += step_x
			t_max_x += t_delta_x
		elif effective_t_max_y < effective_t_max_x:
			cell_y += step_y
			t_max_y += t_delta_y
		else:
			for side in ((cell_x + step_x, cell_y), (cell_x, cell_y + step_y)):
				if 0 <= side[0] < width and 0 <= side[1] < height and side not in seen:
					seen.add(side)
					yield side
			cell_x += step_x
			cell_y += step_y
			t_max_x += t_delta_x
			t_max_y += t_delta_y


def _rasterized_coverage(items: list[dict], cell_size: float, width: int, height: int) -> bytearray:
	image = Image.new("1", (width, height), 0)
	draw = ImageDraw.Draw(image)
	for item in sorted(items, key=lambda value: str(value.get("id", ""))):
		polygon = [(float(point[0]) / cell_size, float(point[1]) / cell_size) for point in item.get("polygon", [])]
		if len(polygon) < 3:
			continue
		# Pillow fills the interior cheaply. Exact supercover edges below make the
		# raster conservative even when an edge only clips a cell corner.
		draw.polygon([(math.floor(x), math.floor(y)) for x, y in polygon], fill=1)
		for index, start in enumerate(polygon):
			end = polygon[(index + 1) % len(polygon)]
			for cell_x, cell_y in _supercover_cells(start, end, width, height):
				image.putpixel((cell_x, cell_y), 1)
	pixels = image.get_flattened_data() if hasattr(image, "get_flattened_data") else image.getdata()
	return bytearray(1 if value else 0 for value in pixels)


def _occupancy(terrain: dict, cell_size: float, width: int, height: int) -> bytearray:
	ship_obstacles = [item for item in terrain.get("obstacles", []) if "ShipMovement" in item.get("block_mask", [])]
	return _rasterized_coverage(ship_obstacles, cell_size, width, height)


def _restriction_masks(terrain: dict, cell_size: float, width: int, height: int) -> bytes:
	result = bytearray(width * height)
	for region_type, mask in RESTRICTION_MASKS.items():
		regions = [item for item in terrain.get("regions", []) if item.get("region_type") == region_type]
		coverage = _rasterized_coverage(regions, cell_size, width, height)
		for index, covered in enumerate(coverage):
			if covered:
				result[index] |= mask
	return bytes(result)


def _edt_1d(values: list[float]) -> list[float]:
	"""Felzenszwalb/Huttenlocher exact squared Euclidean transform."""
	n = len(values)
	if n == 0:
		return []
	if min(values) >= INFINITY * 0.5:
		return [INFINITY] * n
	v = [0] * n
	z = [-INFINITY] + [0.0] * (n - 1) + [INFINITY]
	k = 0
	for q in range(1, n):
		s = ((values[q] + q * q) - (values[v[k]] + v[k] * v[k])) / (2.0 * (q - v[k]))
		while s <= z[k]:
			k -= 1
			s = ((values[q] + q * q) - (values[v[k]] + v[k] * v[k])) / (2.0 * (q - v[k]))
		k += 1
		v[k] = q
		z[k] = s
		z[k + 1] = INFINITY
	result = [0.0] * n
	k = 0
	for q in range(n):
		while z[k + 1] < q:
			k += 1
		difference = q - v[k]
		result[q] = difference * difference + values[v[k]]
	return result


def _distance_lower_bounds(occupancy: bytearray, map_size: tuple[float, float], cell_size: float, width: int, height: int) -> array:
	row_pass = array("d", [0.0]) * (width * height)
	for y in range(height):
		base = y * width
		row = [0.0 if occupancy[base + x] else INFINITY for x in range(width)]
		row_pass[base:base + width] = array("d", _edt_1d(row))
	result = array("H", [0]) * (width * height)
	cell_double_half_diagonal = math.sqrt(2.0) * cell_size
	for x in range(width):
		column = _edt_1d([row_pass[y * width + x] for y in range(height)])
		for y, squared_cells in enumerate(column):
			cell_min_x = x * cell_size
			cell_max_x = min(map_size[0], (x + 1) * cell_size)
			cell_min_y = y * cell_size
			cell_max_y = min(map_size[1], (y + 1) * cell_size)
			boundary_lower = min(cell_min_x, map_size[0] - cell_max_x, cell_min_y, map_size[1] - cell_max_y)
			obstacle_lower = math.sqrt(squared_cells) * cell_size - cell_double_half_diagonal - QUANTIZATION_GUARD
			lower = max(0.0, min(boundary_lower, obstacle_lower))
			result[y * width + x] = min(65535, math.floor(lower))
	if sys.byteorder != "little":
		result.byteswap()
	return result


def _pack_occupancy(occupancy: bytearray) -> bytes:
	packed = bytearray((len(occupancy) + 7) // 8)
	for index, occupied in enumerate(occupancy):
		if occupied:
			packed[index >> 3] |= 1 << (index & 7)
	return bytes(packed)


def bake_field(terrain: dict, output: Path, cell_size: float, resource_path: str | None = None) -> dict:
	terrain_id = str(terrain["id"])
	map_size = (float(terrain["map_size"][0]), float(terrain["map_size"][1]))
	width = int(math.ceil(map_size[0] / cell_size))
	height = int(math.ceil(map_size[1] / cell_size))
	occupancy_cells = _occupancy(terrain, cell_size, width, height)
	occupancy = _pack_occupancy(occupancy_cells)
	distances = _distance_lower_bounds(occupancy_cells, map_size, cell_size, width, height).tobytes()
	restrictions = _restriction_masks(terrain, cell_size, width, height)
	payload = occupancy + distances + restrictions
	source_checksum = source_geometry_checksum(terrain)
	payload_checksum = hashlib.sha256(payload).hexdigest()
	terrain_id_bytes = terrain_id.encode("utf-8")
	header = HEADER.pack(
		MAGIC, SCHEMA_VERSION, ALGORITHM_VERSION, width, height, cell_size,
		map_size[0], map_size[1], int(terrain.get("navigation_revision", 0)),
		len(terrain_id_bytes), bytes.fromhex(source_checksum), bytes.fromhex(payload_checksum),
		len(occupancy), len(distances), len(restrictions),
	)
	data = header + terrain_id_bytes + payload
	output.parent.mkdir(parents=True, exist_ok=True)
	output.write_bytes(data)
	return {
		"id": _field_id(terrain_id),
		"definition_type": "TerrainCollisionField",
		"schema_version": SCHEMA_VERSION,
		"algorithm_version": ALGORITHM_VERSION,
		"terrain_definition_id": terrain_id,
		"navigation_revision": int(terrain.get("navigation_revision", 0)),
		"map_size": [map_size[0], map_size[1]],
		"cell_size": cell_size,
		"grid_size": [width, height],
		"path": "res://%s" % (resource_path or output.relative_to(ROOT).as_posix()),
		"source_checksum": source_checksum,
		"payload_checksum": payload_checksum,
		"file_checksum": hashlib.sha256(data).hexdigest(),
		"occupancy_bytes": len(occupancy),
		"distance_bytes": len(distances),
		"restriction_bytes": len(restrictions),
	}


def main() -> int:
	parser = argparse.ArgumentParser()
	parser.add_argument("--terrain", default="data/terrain/terrain_definitions.json")
	parser.add_argument("--out-dir", default="data/terrain/collision_fields")
	parser.add_argument("--resource-dir", default="data/terrain/collision_fields")
	parser.add_argument("--manifest", default="data/terrain/collision_field_manifest.json")
	parser.add_argument("--cell-size", type=float, default=DEFAULT_CELL_SIZE)
	args = parser.parse_args()
	if args.cell_size <= 0.0:
		print("collision-field cell size must be positive", file=sys.stderr)
		return 1
	try:
		terrain_document = read_json(_path(args.terrain))
		out_dir = _path(args.out_dir)
		definitions = []
		for terrain in sorted(terrain_document.get("definitions", []), key=lambda item: str(item.get("id", ""))):
			if terrain.get("definition_type") != "TerrainMap":
				continue
			file_name = _file_name(str(terrain["id"]))
			resource_path = (Path(args.resource_dir) / file_name).as_posix()
			definitions.append(bake_field(terrain, out_dir / file_name, args.cell_size, resource_path))
		write_json(_path(args.manifest), {
			"schema_version": SCHEMA_VERSION,
			"generated_by": "tools/terrain/bake_collision_fields.py",
			"definitions": definitions,
		})
		print("baked %d terrain collision fields" % len(definitions))
		return 0
	except (KeyError, OSError, TypeError, ValueError, struct.error) as error:
		print("collision-field bake failed: %s" % error, file=sys.stderr)
		return 1


if __name__ == "__main__":
	raise SystemExit(main())
