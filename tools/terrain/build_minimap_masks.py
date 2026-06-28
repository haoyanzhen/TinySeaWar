#!/usr/bin/env python3
"""Build minimap semantic masks from the reviewed runtime terrain definition."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw

from terrain_geometry import read_json

ROOT = Path(__file__).resolve().parents[2]


def main() -> int:
	parser = argparse.ArgumentParser()
	parser.add_argument("--terrain", default="data/terrain/terrain_definitions.json")
	parser.add_argument("--out-dir", default="assets/ui/processed/battle/terrain")
	parser.add_argument("--width", type=int, default=512)
	args = parser.parse_args()
	if args.width < 64:
		return 1
	document = read_json(ROOT / args.terrain)
	manifest = {"schema_version": 1, "generated_by": "tools/terrain/build_minimap_masks.py", "masks": []}
	for terrain in document.get("definitions", []):
		map_width, map_height = terrain["map_size"]
		height = max(1, round(args.width * map_height / map_width))
		image = Image.new("RGBA", (args.width, height), (0, 0, 0, 0))
		draw = ImageDraw.Draw(image, "RGBA")
		def points(polygon):
			return [(float(point[0]) / map_width * args.width, float(point[1]) / map_height * height) for point in polygon]
		for region in sorted(terrain.get("regions", []), key=lambda item: int(item.get("priority", 0))):
			color = {"ShallowWater": (65, 208, 197, 130), "NavigationChannel": (80, 185, 230, 160), "ReefOrSandbar": (220, 188, 105, 165)}.get(region.get("region_type"), (71, 143, 160, 75))
			draw.polygon(points(region["polygon"]), fill=color)
		for obstacle in terrain.get("obstacles", []):
			draw.polygon(points(obstacle["polygon"]), fill=(53, 73, 67, 245), outline=(218, 225, 196, 220))
		filename = "minimap_%s.png" % terrain["id"].replace(".", "_")
		path = ROOT / args.out_dir / filename
		path.parent.mkdir(parents=True, exist_ok=True)
		image.save(path)
		manifest["masks"].append({"terrain_definition_id": terrain["id"], "path": "res://%s" % path.relative_to(ROOT).as_posix(), "size": [args.width, height]})
	manifest_path = ROOT / args.out_dir / "terrain_minimap_manifest.json"
	manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
