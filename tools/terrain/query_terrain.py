#!/usr/bin/env python3
"""Deterministic command-line line/sweep terrain query tester."""

from __future__ import annotations

import argparse
import json
import math
import sys

from terrain_geometry import circle_clear, distance_point_to_segment, read_json


def _pair(value: str) -> list[float]:
	parts = value.split(",")
	if len(parts) != 2:
		raise argparse.ArgumentTypeError("expected X,Y")
	return [float(parts[0]), float(parts[1])]


def first_hit(terrain: dict, start: list[float], end: list[float], radius: float, block_mask: str) -> dict:
	obstacles = [item for item in terrain.get("obstacles", []) if block_mask in item.get("block_mask", [])]
	distance = math.dist(start, end)
	steps = max(1, int(math.ceil(distance / max(1.0, min(8.0, radius * 0.35 if radius > 0.0 else 4.0)))))
	for index in range(steps + 1):
		t = float(index) / float(steps)
		position = [start[0] + (end[0] - start[0]) * t, start[1] + (end[1] - start[1]) * t]
		for obstacle in sorted(obstacles, key=lambda item: item["id"]):
			if not circle_clear(position, radius, [obstacle]):
				previous_t = float(max(0, index - 1)) / float(steps)
				for _ in range(16):
					mid = (previous_t + t) * 0.5
					midpoint = [start[0] + (end[0] - start[0]) * mid, start[1] + (end[1] - start[1]) * mid]
					if circle_clear(midpoint, radius, [obstacle]):
						previous_t = mid
					else:
						t = mid
				position = [start[0] + (end[0] - start[0]) * t, start[1] + (end[1] - start[1]) * t]
				polygon = obstacle.get("polygon", [])
				nearest_index = min(range(len(polygon)), key=lambda edge_index: distance_point_to_segment(position, polygon[edge_index], polygon[(edge_index + 1) % len(polygon)]))
				a, b = polygon[nearest_index], polygon[(nearest_index + 1) % len(polygon)]
				dx, dy = float(b[0]) - float(a[0]), float(b[1]) - float(a[1])
				length = max(1.0e-9, math.hypot(dx, dy))
				normal = [-dy / length, dx / length]
				return {"hit": True, "obstacle_id": obstacle["id"], "position": [round(v, 3) for v in position], "normal": [round(v, 6) for v in normal], "fraction": round(t, 6), "distance": round(distance * t, 3), "block_mask": block_mask}
	return {"hit": False, "obstacle_id": "", "position": end, "normal": [0.0, 0.0], "fraction": 1.0, "distance": distance, "block_mask": block_mask}


def main() -> int:
	parser = argparse.ArgumentParser()
	parser.add_argument("--terrain", default="data/terrain/terrain_definitions.json")
	parser.add_argument("--map-id", default="terrain.map.harbor_mouth")
	parser.add_argument("--from", dest="start", type=_pair, required=True)
	parser.add_argument("--to", dest="end", type=_pair, required=True)
	parser.add_argument("--mask", choices=["ShipMovement", "TorpedoTravel", "ShellTravel", "SurfaceOpticalLineOfSight"], default="ShipMovement")
	parser.add_argument("--radius", type=float, default=0.0)
	args = parser.parse_args()
	document = read_json(args.terrain)
	terrain = next((item for item in document.get("definitions", []) if item.get("id") == args.map_id), None)
	if terrain is None or args.radius < 0.0:
		print("invalid terrain query", file=sys.stderr)
		return 1
	print(json.dumps(first_hit(terrain, args.start, args.end, args.radius, args.mask), ensure_ascii=False, sort_keys=True))
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
