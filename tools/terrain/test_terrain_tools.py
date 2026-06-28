#!/usr/bin/env python3
"""Negative fixtures proving invalid terrain cannot enter runtime data."""

from __future__ import annotations

import argparse
import copy
import json
import subprocess
import tempfile
from pathlib import Path

from validate_terrain_definition import validate

ROOT = Path(__file__).resolve().parents[2]


def _load(relative: str) -> dict:
	return json.loads((ROOT / relative).read_text(encoding="utf-8"))


def _write(path: Path, document: dict) -> None:
	path.write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> int:
	base = {
		"templates": _load("data/terrain/terrain_templates.json"),
		"terrain": _load("data/terrain/terrain_definitions.json"),
		"navigation": _load("data/terrain/navigation_definitions.json"),
		"facilities": _load("data/facilities/facility_definitions.json"),
		"minefields": _load("data/facilities/minefield_definitions.json"),
		"environment": _load("data/environments/environment_zone_definitions.json"),
	}
	fixtures = []

	self_intersection = copy.deepcopy(base)
	self_intersection["templates"]["definitions"][0]["obstacles"][0]["polygon"] = [[10, 10], [90, 90], [10, 90], [90, 10]]
	fixtures.append(("self-intersection", self_intersection, "self-intersects"))

	spawn_on_land = copy.deepcopy(base)
	polygon = spawn_on_land["terrain"]["definitions"][0]["obstacles"][0]["polygon"]
	spawn_on_land["terrain"]["definitions"][0]["spawn_points"][0]["position"] = polygon[0]
	fixtures.append(("spawn-on-land", spawn_on_land, "intersects hard terrain"))

	missing_anchor = copy.deepcopy(base)
	layout = next(item for item in missing_anchor["facilities"]["definitions"] if item["definition_type"] == "FacilityLayout")
	layout["placements"][0]["anchor_id"] = "missing.anchor"
	fixtures.append(("missing-anchor", missing_anchor, "unknown facility anchor"))

	blocked_battery = copy.deepcopy(base)
	terrain = blocked_battery["terrain"]["definitions"][0]
	battery_anchor = next(item for item in terrain["facility_anchors"] if item["id"].endswith("battery_west"))
	battery_anchor["muzzle_position"] = terrain["obstacles"][0]["polygon"][0]
	fixtures.append(("blocked-battery", blocked_battery, "muzzle is blocked"))

	dependency_cycle = copy.deepcopy(base)
	layout = next(item for item in dependency_cycle["facilities"]["definitions"] if item["definition_type"] == "FacilityLayout")
	first, second = layout["placements"][0], layout["placements"][1]
	first["requires_all_active"] = [second["id"]]
	second["requires_all_active"] = [first["id"]]
	fixtures.append(("dependency-cycle", dependency_cycle, "dependency graph contains a cycle"))

	invalid_drift = copy.deepcopy(base)
	zone_set = next(item for item in invalid_drift["environment"]["definitions"] if item["definition_type"] == "EnvironmentZoneSet")
	zone_set["zones"][0]["drift_path"] = [[0, 0], [5000, 0]]
	fixtures.append(("environment-out-of-bounds", invalid_drift, "drift path leaves map bounds"))

	missing_controller = copy.deepcopy(base)
	missing_controller["minefields"]["definitions"][0]["controller_facility_id"] = "facility.missing.controller"
	fixtures.append(("missing-mine-controller", missing_controller, "missing controller facility"))

	invalid_safe_channel = copy.deepcopy(base)
	invalid_safe_channel["minefields"]["definitions"][0]["safe_channels"][0] = [[1880, 420], [2220, 1160], [1880, 1160], [2220, 420]]
	fixtures.append(("invalid-safe-channel", invalid_safe_channel, "self-intersects"))

	with tempfile.TemporaryDirectory() as temporary:
		root = Path(temporary)
		for fixture_name, documents, expected in fixtures:
			paths = {}
			for key, document in documents.items():
				path = root / ("%s_%s.json" % (fixture_name, key))
				_write(path, document)
				paths[key] = str(path)
			errors = validate(argparse.Namespace(**paths))
			if not any(expected in error for error in errors):
				print("negative fixture failed: %s expected %r, got %r" % (fixture_name, expected, errors))
				return 1
		invalid_maps = _load("data/terrain/authoring/terrain_maps.json")
		invalid_maps["maps"][0]["spawn_points"][0]["position"] = base["terrain"]["definitions"][0]["obstacles"][0]["polygon"][0]
		invalid_maps_path = root / "transaction_invalid_maps.json"
		terrain_out = root / "transaction_terrain.json"
		navigation_out = root / "transaction_navigation.json"
		_write(invalid_maps_path, invalid_maps)
		terrain_out.write_bytes((ROOT / "data/terrain/terrain_definitions.json").read_bytes())
		navigation_out.write_bytes((ROOT / "data/terrain/navigation_definitions.json").read_bytes())
		before = (terrain_out.read_bytes(), navigation_out.read_bytes())
		result = subprocess.run([
			"python3", "tools/terrain/build_scene_combat_pipeline.py", "--maps", str(invalid_maps_path),
			"--terrain-out", str(terrain_out), "--navigation-out", str(navigation_out), "--skip-qa",
		], cwd=ROOT, capture_output=True, text=True)
		if result.returncode == 0 or before != (terrain_out.read_bytes(), navigation_out.read_bytes()):
			print("negative fixture failed: transactional pipeline published invalid spawn data")
			return 1
	print("terrain tool negative fixtures passed: %d" % (len(fixtures) + 1))
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
