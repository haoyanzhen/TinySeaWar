#!/usr/bin/env python3
"""Bake only 16:9 coastal navigation graphs in parallel and merge them."""

from __future__ import annotations

import argparse
import concurrent.futures
import json
from pathlib import Path
import subprocess
import sys
import tempfile

from terrain_geometry import read_json, write_json


ROOT = Path(__file__).resolve().parents[2]


def _bake_one(payload: tuple[Path, Path, float]) -> dict:
	terrain_path, output_path, cell_size = payload
	result = subprocess.run(
		[
			sys.executable,
			str(ROOT / "tools/terrain/bake_navigation_graph.py"),
			"--terrain", str(terrain_path),
			"--out", str(output_path),
			"--cell-size", str(cell_size),
		],
		cwd=ROOT,
		capture_output=True,
		text=True,
	)
	if result.returncode != 0:
		raise RuntimeError(result.stdout + result.stderr)
	return read_json(output_path)["definitions"][0]


def main() -> int:
	parser = argparse.ArgumentParser()
	parser.add_argument("--terrain", required=True)
	parser.add_argument("--base-navigation", default="data/terrain/navigation_definitions.json")
	parser.add_argument("--out", required=True)
	parser.add_argument("--cell-size", type=float, default=128.0)
	parser.add_argument("--workers", type=int, default=4)
	parser.add_argument("--terrain-id", action="append", default=[])
	args = parser.parse_args()

	all_terrains = [
		item for item in read_json(args.terrain).get("definitions", [])
		if str(item.get("id", "")).endswith("_16x9")
	]
	if len(all_terrains) != 10:
		raise ValueError("expected 10 coastal 16:9 terrains, found %d" % len(all_terrains))
	selected_ids = set(args.terrain_id)
	terrains = [item for item in all_terrains if not selected_ids or item.get("id") in selected_ids]
	if selected_ids and {item.get("id") for item in terrains} != selected_ids:
		missing = sorted(selected_ids - {item.get("id") for item in terrains})
		raise ValueError("unknown 16:9 terrain ids: %s" % ", ".join(missing))
	with tempfile.TemporaryDirectory(dir=ROOT / ".godot") as temporary:
		temporary_root = Path(temporary)
		payloads = []
		for index, terrain in enumerate(terrains):
			terrain_path = temporary_root / ("terrain_%02d.json" % index)
			output_path = temporary_root / ("navigation_%02d.json" % index)
			terrain_path.write_text(
				json.dumps({"schema_version": 1, "definitions": [terrain]}, ensure_ascii=False),
				encoding="utf-8",
			)
			payloads.append((terrain_path, output_path, args.cell_size))
		with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.workers)) as executor:
			baked = list(executor.map(_bake_one, payloads))

	base_path = Path(args.base_navigation)
	base_document = read_json(base_path) if base_path.is_file() else {"schema_version": 1, "definitions": []}
	replacements = {item["id"]: item for item in baked}
	merged = [
		item for item in base_document.get("definitions", [])
		if item.get("id") not in replacements
	]
	merged.extend(sorted(baked, key=lambda item: item["id"]))
	write_json(args.out, {
		"schema_version": 1,
		"generated_by": "tools/terrain/bake_coastal16_navigation.py",
		"definitions": merged,
	})
	print("baked and merged %d coastal 16:9 navigation graphs" % len(baked))
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
