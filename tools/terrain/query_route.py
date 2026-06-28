#!/usr/bin/env python3
"""Query and visualize the player/AI shared baked navigation graph."""

from __future__ import annotations

import argparse
import heapq
import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw

from terrain_geometry import read_json

ROOT = Path(__file__).resolve().parents[2]


def _pair(value: str) -> list[float]:
	parts = value.split(",")
	if len(parts) != 2:
		raise argparse.ArgumentTypeError("expected X,Y")
	return [float(parts[0]), float(parts[1])]


def _profile(definition: dict, radius: float, tags: set[str]) -> dict | None:
	candidates = [item for item in definition.get("profiles", []) if float(item.get("radius", 0.0)) >= radius and (("ShallowDraft" in tags) == ("ShallowDraft" in item.get("movement_tags", [])))]
	return min(candidates, key=lambda item: (float(item["radius"]), item["id"])) if candidates else None


def _nearest(nodes: list[dict], point: list[float]) -> str:
	return min(nodes, key=lambda node: ((node["position"][0]-point[0])**2 + (node["position"][1]-point[1])**2, node["id"]))["id"]


def _path(profile: dict, start: list[float], end: list[float]) -> list[list[float]]:
	by_id = {node["id"]: node for node in profile.get("nodes", [])}
	start_id, end_id = _nearest(list(by_id.values()), start), _nearest(list(by_id.values()), end)
	queue = [(0.0, start_id)]
	cost = {start_id: 0.0}
	parent: dict[str, str] = {}
	while queue:
		_, current = heapq.heappop(queue)
		if current == end_id:
			ids = [current]
			while current in parent:
				current = parent[current]
				ids.append(current)
			ids.reverse()
			return [start] + [by_id[node_id]["position"] for node_id in ids] + [end]
		position = by_id[current]["position"]
		for neighbor in by_id[current].get("neighbors", []):
			neighbor_position = by_id[neighbor]["position"]
			candidate = cost[current] + math.dist(position, neighbor_position)
			if candidate >= cost.get(neighbor, math.inf):
				continue
			cost[neighbor] = candidate
			parent[neighbor] = current
			heapq.heappush(queue, (candidate + math.dist(neighbor_position, end), neighbor))
	return []


def _render(path: Path, terrain: dict, profile: dict, route: list[list[float]]) -> None:
	width, height = 1280, 720
	map_width, map_height = terrain["map_size"]
	image = Image.new("RGBA", (width, height), (20, 67, 82, 255))
	draw = ImageDraw.Draw(image, "RGBA")
	convert = lambda point: (float(point[0]) / map_width * width, float(point[1]) / map_height * height)
	for obstacle in terrain.get("obstacles", []):
		draw.polygon([convert(point) for point in obstacle["polygon"]], fill=(48, 68, 62, 240), outline=(234, 132, 105, 245))
	for node in profile.get("nodes", []):
		x, y = convert(node["position"])
		draw.ellipse([x-1, y-1, x+1, y+1], fill=(112, 202, 202, 90))
	if route:
		draw.line([convert(point) for point in route], fill=(104, 239, 187, 255), width=5, joint="curve")
	path.parent.mkdir(parents=True, exist_ok=True)
	image.save(path)


def main() -> int:
	parser = argparse.ArgumentParser()
	parser.add_argument("--from", dest="start", type=_pair, required=True)
	parser.add_argument("--to", dest="end", type=_pair, required=True)
	parser.add_argument("--radius", type=float, default=20.0)
	parser.add_argument("--tags", default="Surface,ShallowDraft")
	parser.add_argument("--map-id", default="terrain.map.harbor_mouth")
	parser.add_argument("--out")
	args = parser.parse_args()
	terrains = read_json(ROOT / "data/terrain/terrain_definitions.json").get("definitions", [])
	navigation = read_json(ROOT / "data/terrain/navigation_definitions.json").get("definitions", [])
	terrain = next((item for item in terrains if item["id"] == args.map_id), None)
	definition = next((item for item in navigation if item.get("terrain_definition_id") == args.map_id), None)
	profile = _profile(definition or {}, args.radius, set(filter(None, args.tags.split(","))))
	if terrain is None or profile is None or args.radius < 0.0:
		print("no compatible terrain/navigation profile", file=sys.stderr)
		return 1
	route = _path(profile, args.start, args.end)
	if not route:
		print("no navigation path", file=sys.stderr)
		return 1
	result = {"ok": True, "profile_id": profile["id"], "radius": args.radius, "movement_tags": args.tags.split(","), "waypoints": route, "distance": round(sum(math.dist(route[index], route[index+1]) for index in range(len(route)-1)), 3)}
	print(json.dumps(result, ensure_ascii=False, sort_keys=True))
	if args.out:
		_render(Path(args.out), terrain, profile, route)
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
