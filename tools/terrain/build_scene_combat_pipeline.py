#!/usr/bin/env python3
"""Transactionally bake, validate, and publish scene-combat terrain outputs."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def _path(value: str) -> Path:
	path = Path(value)
	return path if path.is_absolute() else ROOT / path


def _run(command: list[str]) -> tuple[bool, str]:
	result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
	output = "\n".join(part.strip() for part in [result.stdout, result.stderr] if part.strip())
	return result.returncode == 0, output


def main() -> int:
	parser = argparse.ArgumentParser()
	parser.add_argument("--templates", default="data/terrain/terrain_templates.json")
	parser.add_argument("--maps", default="data/terrain/authoring/terrain_maps.json")
	parser.add_argument("--terrain-out", default="data/terrain/terrain_definitions.json")
	parser.add_argument("--navigation-out", default="data/terrain/navigation_definitions.json")
	parser.add_argument("--facilities", default="data/facilities/facility_definitions.json")
	parser.add_argument("--minefields", default="data/facilities/minefield_definitions.json")
	parser.add_argument("--environment", default="data/environments/environment_zone_definitions.json")
	parser.add_argument("--skip-qa", action="store_true")
	args = parser.parse_args()
	try:
		with tempfile.TemporaryDirectory(dir=ROOT / ".godot") as temporary:
			temporary_root = Path(temporary)
			terrain_candidate = temporary_root / "terrain_definitions.json"
			navigation_candidate = temporary_root / "navigation_definitions.json"
			commands = [
				[sys.executable, "tools/terrain/bake_terrain_definition.py", "--templates", str(_path(args.templates)), "--maps", str(_path(args.maps)), "--out", str(terrain_candidate)],
				[
					sys.executable, "tools/terrain/validate_terrain_definition.py", "--templates", str(_path(args.templates)),
					"--terrain", str(terrain_candidate), "--navigation", str(_path(args.navigation_out)),
					"--facilities", str(_path(args.facilities)), "--minefields", str(_path(args.minefields)),
					"--environment", str(_path(args.environment)), "--skip-navigation",
				],
				[sys.executable, "tools/terrain/bake_navigation_graph.py", "--terrain", str(terrain_candidate), "--out", str(navigation_candidate)],
				[
					sys.executable, "tools/terrain/validate_terrain_definition.py", "--templates", str(_path(args.templates)),
					"--terrain", str(terrain_candidate), "--navigation", str(navigation_candidate),
					"--facilities", str(_path(args.facilities)), "--minefields", str(_path(args.minefields)),
					"--environment", str(_path(args.environment)),
				],
			]
			for command in commands:
				ok, output = _run(command)
				if not ok:
					print("scene-combat transaction rejected:\n%s" % output, file=sys.stderr)
					return 1
			terrain_out = _path(args.terrain_out)
			navigation_out = _path(args.navigation_out)
			terrain_out.parent.mkdir(parents=True, exist_ok=True)
			navigation_out.parent.mkdir(parents=True, exist_ok=True)
			os.replace(terrain_candidate, terrain_out)
			os.replace(navigation_candidate, navigation_out)
		if not args.skip_qa:
			for command in [
				[sys.executable, "tools/terrain/build_minimap_masks.py", "--terrain", str(_path(args.terrain_out))],
				[sys.executable, "tools/terrain/build_scene_combat_contact_sheet.py"],
			]:
				ok, output = _run(command)
				if not ok:
					print("scene-combat publish QA failed:\n%s" % output, file=sys.stderr)
					return 1
		print("scene-combat terrain transaction published")
		return 0
	except OSError as error:
		print("scene-combat transaction failed: %s" % error, file=sys.stderr)
		return 1


if __name__ == "__main__":
	raise SystemExit(main())
