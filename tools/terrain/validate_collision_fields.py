#!/usr/bin/env python3
"""Validate collision-field integrity, determinism, and no-false-clear safety."""

from __future__ import annotations

import argparse
import copy
import hashlib
import math
import random
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

from bake_collision_fields import (
	ALGORITHM_VERSION,
	HEADER,
	MAGIC,
	SCHEMA_VERSION,
	_file_name,
	_supercover_cells,
	source_geometry_checksum,
)
from terrain_geometry import distance_point_to_segment, point_in_polygon, read_json, segments_intersect


ROOT = Path(__file__).resolve().parents[2]


def _path(value: str | Path) -> Path:
	path = Path(value)
	return path if path.is_absolute() else ROOT / path


def _segment_distance(a: list[float], b: list[float], c: list[float], d: list[float]) -> float:
	if segments_intersect(a, b, c, d):
		return 0.0
	return min(
		distance_point_to_segment(a, c, d),
		distance_point_to_segment(b, c, d),
		distance_point_to_segment(c, a, b),
		distance_point_to_segment(d, a, b),
	)


def _exact_clear(terrain: dict, start: list[float], end: list[float], radius: float) -> bool:
	width, height = (float(value) for value in terrain.get("map_size", [0.0, 0.0]))
	for point in (start, end):
		if point[0] - radius < 0.0 or point[1] - radius < 0.0 or point[0] + radius > width or point[1] + radius > height:
			return False
	for obstacle in terrain.get("obstacles", []):
		if "ShipMovement" not in obstacle.get("block_mask", []):
			continue
		polygon = obstacle.get("polygon", [])
		if point_in_polygon(start, polygon) or point_in_polygon(end, polygon):
			return False
		for index, edge_start in enumerate(polygon):
			if _segment_distance(start, end, edge_start, polygon[(index + 1) % len(polygon)]) <= radius + 1.0e-6:
				return False
	return True


def _parse_field(path: Path) -> dict:
	data = path.read_bytes()
	if len(data) < HEADER.size:
		raise ValueError("truncated header")
	(
		magic, schema_version, algorithm_version, width, height, cell_size,
		map_width, map_height, navigation_revision, terrain_id_length,
		source_checksum, payload_checksum, occupancy_length, distance_length, restriction_length,
	) = HEADER.unpack_from(data)
	if magic != MAGIC or schema_version != SCHEMA_VERSION or algorithm_version != ALGORITHM_VERSION:
		raise ValueError("invalid header")
	offset = HEADER.size
	end_id = offset + terrain_id_length
	end_occupancy = end_id + occupancy_length
	end_distance = end_occupancy + distance_length
	end_restriction = end_distance + restriction_length
	if end_restriction != len(data):
		raise ValueError("invalid payload lengths")
	terrain_id = data[offset:end_id].decode("utf-8")
	occupancy = data[end_id:end_occupancy]
	distances = data[end_occupancy:end_distance]
	restrictions = data[end_distance:end_restriction]
	payload = occupancy + distances + restrictions
	if hashlib.sha256(payload).digest() != payload_checksum:
		raise ValueError("payload checksum mismatch")
	if occupancy_length != math.ceil(width * height / 8) or distance_length != width * height * 2 or restriction_length != width * height:
		raise ValueError("payload size mismatch")
	return {
		"data":data,
		"terrain_id":terrain_id,
		"source_checksum":source_checksum.hex(),
		"payload_checksum":payload_checksum.hex(),
		"width":width,
		"height":height,
		"cell_size":cell_size,
		"map_size":[map_width, map_height],
		"navigation_revision":navigation_revision,
		"occupancy":occupancy,
		"distances":distances,
		"restrictions":restrictions,
	}


def _distance(field: dict, cell_x: int, cell_y: int) -> int:
	if cell_x < 0 or cell_y < 0 or cell_x >= field["width"] or cell_y >= field["height"]:
		return 0
	offset = (cell_y * field["width"] + cell_x) * 2
	return struct.unpack_from("<H", field["distances"], offset)[0]


def _definitely_clear(field: dict, start: list[float], end: list[float], radius: float) -> bool:
	cell_size = float(field["cell_size"])
	map_width, map_height = (float(value) for value in field["map_size"])
	if any(point[0] < 0.0 or point[1] < 0.0 or point[0] > map_width or point[1] > map_height for point in (start, end)):
		return False
	start_grid = (start[0] / cell_size, start[1] / cell_size)
	end_grid = (end[0] / cell_size, end[1] / cell_size)
	for cell_x, cell_y in _supercover_cells(start_grid, end_grid, field["width"], field["height"]):
		if _distance(field, cell_x, cell_y) <= radius:
			return False
	return True


def _field_restriction_mask(field: dict, start: list[float], end: list[float]) -> int:
	cell_size = float(field["cell_size"])
	start_grid = (start[0] / cell_size, start[1] / cell_size)
	end_grid = (end[0] / cell_size, end[1] / cell_size)
	result = 0
	for cell_x, cell_y in _supercover_cells(start_grid, end_grid, field["width"], field["height"]):
		result |= field["restrictions"][cell_y * field["width"] + cell_x]
	return result


def _segment_intersects_polygon(start: list[float], end: list[float], polygon: list[list[float]]) -> bool:
	if point_in_polygon(start, polygon) or point_in_polygon(end, polygon):
		return True
	return any(segments_intersect(start, end, edge_start, polygon[(index + 1) % len(polygon)]) for index, edge_start in enumerate(polygon))


def _exact_restriction_mask(terrain: dict, start: list[float], end: list[float]) -> int:
	result = 0
	for region in terrain.get("regions", []):
		region_mask = {"ShallowWater": 1, "ReefOrSandbar": 2}.get(region.get("region_type"), 0)
		polygon = region.get("polygon", [])
		if region_mask and len(polygon) >= 3 and _segment_intersects_polygon(start, end, polygon):
			result |= region_mask
	return result


def _structured_queries(terrain: dict, radius: float, sample_count: int, random_source: random.Random) -> list[tuple[list[float], list[float]]]:
	width, height = (float(value) for value in terrain["map_size"])
	queries: list[tuple[list[float], list[float]]] = []
	for _ in range(sample_count):
		start = [random_source.uniform(0.0, width), random_source.uniform(0.0, height)]
		angle = random_source.uniform(0.0, math.tau)
		length = random_source.uniform(0.0, min(720.0, math.hypot(width, height)))
		end = [
			max(0.0, min(width, start[0] + math.cos(angle) * length)),
			max(0.0, min(height, start[1] + math.sin(angle) * length)),
		]
		queries.append((start, end))
	# Degenerate segments are point queries and exercise open-water, boundary, and
	# near-obstacle cells without introducing a separate safety implementation.
	for _ in range(max(8, sample_count // 8)):
		point = [random_source.uniform(0.0, width), random_source.uniform(0.0, height)]
		queries.append((point, point.copy()))
	# Explicit map-edge cases must never be declared clear for the requested hull.
	for inset in (max(0.0, radius - 0.25), radius, radius + 0.25):
		queries.extend([
			([inset, height * 0.25], [inset, height * 0.75]),
			([width - inset, height * 0.25], [width - inset, height * 0.75]),
			([width * 0.25, inset], [width * 0.75, inset]),
			([width * 0.25, height - inset], [width * 0.75, height - inset]),
		])
	# Offset short lines on both sides of representative obstacle edges. These
	# cover tangent/barely-clear transitions around convex, concave, and thin
	# author geometry; conservative fields may send any of them to exact narrowphase.
	edge_budget = 16
	for obstacle in terrain.get("obstacles", []):
		if "ShipMovement" not in obstacle.get("block_mask", []):
			continue
		polygon = obstacle.get("polygon", [])
		for index, edge_start in enumerate(polygon):
			if edge_budget <= 0:
				break
			edge_end = polygon[(index + 1) % len(polygon)]
			dx = float(edge_end[0]) - float(edge_start[0])
			dy = float(edge_end[1]) - float(edge_start[1])
			length = math.hypot(dx, dy)
			if length <= 1.0e-6:
				continue
			normal = [-dy / length, dx / length]
			for side in (-1.0, 1.0):
				for offset in (max(0.0, radius - 0.25), radius + 0.25):
					start = [float(edge_start[0]) + normal[0] * offset * side, float(edge_start[1]) + normal[1] * offset * side]
					end = [float(edge_end[0]) + normal[0] * offset * side, float(edge_end[1]) + normal[1] * offset * side]
					queries.append((start, end))
			edge_budget -= 1
		if edge_budget <= 0:
			break
	return queries


def _differential_errors(terrain: dict, field: dict, sample_count: int) -> tuple[list[str], int, int, int]:
	errors: list[str] = []
	seed = int(hashlib.sha256(str(terrain["id"]).encode("utf-8")).hexdigest()[:16], 16)
	random_source = random.Random(seed)
	definitely_clear = 0
	exact_checks_avoided = 0
	region_checks_avoided = 0
	for radius in (19.0, 20.0, 21.0, 31.0, 32.0, 33.0, 45.0, 46.0, 47.0):
		for start, end in _structured_queries(terrain, radius, sample_count, random_source):
			field_restrictions = _field_restriction_mask(field, start, end)
			exact_restrictions = _exact_restriction_mask(terrain, start, end)
			if exact_restrictions & ~field_restrictions:
				errors.append("false region clear: %s field=%d exact=%d start=%s end=%s" % (terrain["id"], field_restrictions, exact_restrictions, start, end))
				if len(errors) >= 10:
					return errors, definitely_clear, exact_checks_avoided, region_checks_avoided
			if field_restrictions == 0:
				region_checks_avoided += 1
			if not _definitely_clear(field, start, end, radius):
				continue
			definitely_clear += 1
			if not _exact_clear(terrain, start, end, radius):
				errors.append("false DefinitelyClear: %s radius=%s start=%s end=%s" % (terrain["id"], radius, start, end))
				if len(errors) >= 10:
					return errors, definitely_clear, exact_checks_avoided, region_checks_avoided
			else:
				exact_checks_avoided += 1
	return errors, definitely_clear, exact_checks_avoided, region_checks_avoided


def _determinism_errors(terrain_path: Path, canonical_manifest: Path, canonical_dir: Path) -> list[str]:
	errors: list[str] = []
	with tempfile.TemporaryDirectory(dir=ROOT / ".godot") as temporary:
		root = Path(temporary)
		outputs = []
		for name in ("first", "second"):
			out_dir = root / name / "fields"
			manifest = root / name / "manifest.json"
			result = subprocess.run([
				sys.executable, "tools/terrain/bake_collision_fields.py",
				"--terrain", str(terrain_path), "--out-dir", str(out_dir), "--manifest", str(manifest),
			], cwd=ROOT, capture_output=True, text=True)
			if result.returncode != 0:
				return ["deterministic collision-field bake failed: %s" % result.stderr.strip()]
			outputs.append((out_dir, manifest))
		if outputs[0][1].read_bytes() != outputs[1][1].read_bytes():
			errors.append("collision-field manifests are not deterministic")
		if outputs[0][1].read_bytes() != canonical_manifest.read_bytes():
			errors.append("committed collision-field manifest is stale")
		for path in sorted(outputs[0][0].glob("*.tscf")):
			peer = outputs[1][0] / path.name
			canonical = canonical_dir / path.name
			if not peer.is_file() or path.read_bytes() != peer.read_bytes():
				errors.append("collision field is not deterministic: %s" % path.name)
			if not canonical.is_file() or path.read_bytes() != canonical.read_bytes():
				errors.append("committed collision field is stale: %s" % path.name)
	return errors


def main() -> int:
	parser = argparse.ArgumentParser()
	parser.add_argument("--terrain", default="data/terrain/terrain_definitions.json")
	parser.add_argument("--manifest", default="data/terrain/collision_field_manifest.json")
	parser.add_argument("--fields-dir", default="data/terrain/collision_fields")
	parser.add_argument("--samples", type=int, default=160)
	parser.add_argument("--skip-determinism", action="store_true")
	args = parser.parse_args()
	terrain_path = _path(args.terrain)
	manifest_path = _path(args.manifest)
	fields_dir = _path(args.fields_dir)
	terrains = {item["id"]: item for item in read_json(terrain_path).get("definitions", []) if item.get("definition_type") == "TerrainMap"}
	manifest = read_json(manifest_path)
	definitions = {item["terrain_definition_id"]: item for item in manifest.get("definitions", [])}
	errors: list[str] = []
	total_definitely_clear = 0
	total_exact_avoided = 0
	total_region_avoided = 0
	for terrain_id, terrain in sorted(terrains.items()):
		definition = definitions.get(terrain_id)
		if definition is None:
			errors.append("missing collision field definition: %s" % terrain_id)
			continue
		path = fields_dir / _file_name(terrain_id)
		try:
			field = _parse_field(path)
		except (OSError, UnicodeDecodeError, ValueError) as error:
			errors.append("invalid collision field %s: %s" % (terrain_id, error))
			continue
		if hashlib.sha256(field["data"]).hexdigest() != definition.get("file_checksum"):
			errors.append("file checksum mismatch: %s" % terrain_id)
		if field["terrain_id"] != terrain_id or field["source_checksum"] != source_geometry_checksum(terrain):
			errors.append("source geometry mismatch: %s" % terrain_id)
		if field["navigation_revision"] != int(terrain.get("navigation_revision", 0)):
			errors.append("navigation revision mismatch: %s" % terrain_id)
		visual_only_change = copy.deepcopy(terrain)
		visual_only_change.setdefault("visual_regions", []).append({"id":"validation.visual_only", "polygon":[[0.0, 0.0], [1.0, 0.0], [0.0, 1.0]]})
		if source_geometry_checksum(visual_only_change) != source_geometry_checksum(terrain):
			errors.append("visual-only data changed collision source checksum: %s" % terrain_id)
		field_errors, definitely_clear, exact_avoided, region_avoided = _differential_errors(terrain, field, max(1, args.samples))
		errors.extend(field_errors)
		total_definitely_clear += definitely_clear
		total_exact_avoided += exact_avoided
		total_region_avoided += region_avoided
	if set(definitions) != set(terrains):
		errors.append("collision field manifest terrain set differs from TerrainMap set")
	if not args.skip_determinism:
		errors.extend(_determinism_errors(terrain_path, manifest_path, fields_dir))
	if errors:
		for error in errors:
			print("collision-field validation failed: %s" % error, file=sys.stderr)
		return 1
	avoidance_ratio = float(total_exact_avoided) / max(1, total_definitely_clear)
	print("collision fields valid: maps=%d definitely_clear=%d exact_avoided=%d ratio=%.3f region_exact_avoided=%d" % (len(terrains), total_definitely_clear, total_exact_avoided, avoidance_ratio, total_region_avoided))
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
