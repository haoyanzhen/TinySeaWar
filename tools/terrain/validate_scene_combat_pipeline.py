#!/usr/bin/env python3
"""Production gate for scene-combat assets and deterministic terrain outputs."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

from terrain_geometry import read_json, sample_polyline

ROOT = Path(__file__).resolve().parents[2]


def _hash(path: Path) -> str:
	return hashlib.sha256(path.read_bytes()).hexdigest()


def _manifest_paths() -> tuple[set[str], list[str]]:
	errors: list[str] = []
	paths: set[str] = set()
	semantics: set[str] = set()
	for relative in [
		"assets/environment/terrain/terrain_asset_manifest.json",
		"assets/environment/facilities/facility_asset_manifest.json",
		"assets/environment/weather/zones/environment_zone_asset_manifest.json",
	]:
		manifest = read_json(ROOT / relative)
		for asset in manifest.get("assets", []):
			semantic = str(asset.get("semantic", ""))
			if not semantic or semantic in semantics:
				errors.append("asset has missing or duplicate semantic: %s in %s" % (semantic or "<empty>", relative))
			semantics.add(semantic)
			path = str(asset.get("path", "")).removeprefix("res://")
			if not path:
				errors.append("asset without path in %s" % relative)
				continue
			paths.add(path)
			source_masters = asset.get("source_masters", [])
			is_coastal_land = semantic.startswith("land_") and semantic.endswith("_16x9_runtime")
			generation_method = str(asset.get("generation_method", ""))
			if source_masters and is_coastal_land and generation_method not in {
				"gpt-image-2 edit reference + reviewed alpha mask",
				"reviewed source edit + deterministic irregular alpha mask; built-in gpt-image-2 candidate rejected for composition drift",
			}:
				errors.append("coastal land asset has an unsupported generation method: %s" % semantic)
			elif source_masters and not is_coastal_land and generation_method != "weather_master_alpha_composite":
				errors.append("weather asset with source masters has an unsupported generation method: %s" % semantic)
			for source in source_masters:
				source_path = str(source).removeprefix("res://")
				expected_root = "assets/environment/land/source/" if is_coastal_land else "assets/environment/weather/"
				expected_size = (3840, 2160) if is_coastal_land else (1024, 1024)
				if not source_path.startswith(expected_root) or (not is_coastal_land and "/zones/" in source_path):
					errors.append("%s source master is outside the source directory: %s" % ("coastal land" if is_coastal_land else "weather", source))
					continue
				if not (ROOT / source_path).is_file():
					errors.append("%s source master is missing: %s" % ("coastal land" if is_coastal_land else "weather", source_path))
					continue
				try:
					with Image.open(ROOT / source_path) as source_image:
						if source_image.size != expected_size:
							errors.append("%s source master has wrong size: %s" % ("coastal land" if is_coastal_land else "weather", source_path))
				except OSError as error:
					errors.append("%s source master cannot be decoded: %s (%s)" % ("coastal land" if is_coastal_land else "weather", source_path, error))
			if semantic in {"rain_squall_mask", "rain_squall_edge_mask"}:
				expected_sources = {
					"res://assets/environment/weather/ocean_weather_storm_shadow_master.png",
					"res://assets/environment/weather/ocean_weather_rain_lines_master.png",
					"res://assets/environment/weather/ocean_weather_rain_ripples_master.png",
				}
				if set(source_masters) != expected_sources:
					errors.append("rain squall asset must trace storm, rain-line, and ripple masters: %s" % semantic)
			if not (ROOT / path).is_file():
				errors.append("manifest path is missing: %s" % path)
				continue
			if not re.fullmatch(r"[a-z0-9_]+\.png", Path(path).name):
				errors.append("runtime asset name is not lowercase_snake_case: %s" % path)
			try:
				with Image.open(ROOT / path) as image:
					expected_size = tuple(int(value) for value in asset.get("size", []))
					if len(expected_size) == 2 and image.size != expected_size:
						errors.append("asset size differs from manifest: %s expected %s got %s" % (path, expected_size, image.size))
					if bool(asset.get("alpha", False)):
						if "A" not in image.getbands():
							errors.append("asset requires an alpha channel: %s" % path)
						elif image.getchannel("A").getextrema() == (255, 255):
							errors.append("asset alpha is fully opaque: %s" % path)
					if path.startswith("assets/ui/processed/battle/terrain/"):
						export_path = ROOT / "assets/ui/export/2x" / Path(path).name
						if not export_path.is_file():
							errors.append("missing 2x UI export: %s" % export_path.relative_to(ROOT))
						else:
							with Image.open(export_path) as export_image:
								if export_image.size != (image.width * 2, image.height * 2):
									errors.append("2x UI export has wrong size: %s" % export_path.relative_to(ROOT))
			except OSError as error:
				errors.append("asset cannot be decoded: %s (%s)" % (path, error))
	minimap_manifest = read_json(ROOT / "assets/ui/processed/battle/terrain/terrain_minimap_manifest.json")
	for mask in minimap_manifest.get("masks", []):
		paths.add(str(mask["path"]).removeprefix("res://"))
	return paths, errors


def _unreferenced_assets(referenced: set[str]) -> list[str]:
	errors: list[str] = []
	for directory in [
		"assets/environment/terrain", "assets/environment/facilities", "assets/environment/weather/zones",
		"assets/ui/processed/battle/terrain", "assets/vfx/combat/environment",
	]:
		for path in sorted((ROOT / directory).glob("*.png")):
			relative = path.relative_to(ROOT).as_posix()
			if relative not in referenced:
				errors.append("unreferenced runtime asset: %s" % relative)
	return errors


def _deterministic_bake() -> list[str]:
	errors: list[str] = []
	with tempfile.TemporaryDirectory() as temporary:
		first = Path(temporary) / "first.json"
		second = Path(temporary) / "second.json"
		for output in (first, second):
			result = subprocess.run([sys.executable, "tools/terrain/bake_terrain_definition.py", "--out", str(output)], cwd=ROOT, capture_output=True, text=True)
			if result.returncode != 0:
				errors.append("deterministic terrain bake failed: %s" % result.stderr.strip())
				return errors
		if first.read_bytes() != second.read_bytes():
			errors.append("terrain bake output is not deterministic")
		if first.read_bytes() != (ROOT / "data/terrain/terrain_definitions.json").read_bytes():
			errors.append("committed terrain definitions are stale; run bake_terrain_definition.py")
	return errors


def _deterministic_qa_outputs() -> list[str]:
	errors: list[str] = []
	with tempfile.TemporaryDirectory(dir=ROOT / ".godot") as temporary:
		root = Path(temporary)
		navigation_outputs = [root / "navigation_a.json", root / "navigation_b.json"]
		for output in navigation_outputs:
			result = subprocess.run([sys.executable, "tools/terrain/bake_navigation_graph.py", "--out", str(output)], cwd=ROOT, capture_output=True, text=True)
			if result.returncode != 0:
				return ["deterministic navigation bake failed: %s" % result.stderr.strip()]
		if navigation_outputs[0].read_bytes() != navigation_outputs[1].read_bytes():
			errors.append("navigation bake output is not deterministic")
		if navigation_outputs[0].read_bytes() != (ROOT / "data/terrain/navigation_definitions.json").read_bytes():
			errors.append("committed navigation definitions are stale; run bake_navigation_graph.py")
		minimap_dir = root / "minimap"
		minimap_snapshots = []
		for _ in range(2):
			result = subprocess.run([sys.executable, "tools/terrain/build_minimap_masks.py", "--out-dir", str(minimap_dir)], cwd=ROOT, capture_output=True, text=True)
			if result.returncode != 0:
				return ["deterministic minimap build failed: %s" % result.stderr.strip()]
			minimap_snapshots.append({path.relative_to(minimap_dir).as_posix(): path.read_bytes() for path in minimap_dir.rglob("*") if path.is_file()})
		if minimap_snapshots[0] != minimap_snapshots[1]:
			errors.append("minimap output is not deterministic")
		canonical_minimap = ROOT / "assets/ui/processed/battle/terrain/minimap_terrain_map_harbor_mouth.png"
		generated_minimap = minimap_dir / "minimap_terrain_map_harbor_mouth.png"
		if generated_minimap.read_bytes() != canonical_minimap.read_bytes():
			errors.append("committed terrain minimap is stale; run build_minimap_masks.py")
		contact_outputs = [root / "contact_a.png", root / "contact_b.png"]
		for output in contact_outputs:
			result = subprocess.run([sys.executable, "tools/terrain/build_scene_combat_contact_sheet.py", "--out", str(output)], cwd=ROOT, capture_output=True, text=True)
			if result.returncode != 0:
				return ["deterministic contact sheet build failed: %s" % result.stderr.strip()]
		if contact_outputs[0].read_bytes() != contact_outputs[1].read_bytes():
			errors.append("scene-combat contact sheet is not deterministic")
		if contact_outputs[0].read_bytes() != (ROOT / "assets/environment/qa/scene_combat_contact_sheet.png").read_bytes():
			errors.append("committed scene-combat contact sheet is stale")
	return errors


def _check_navigation_profiles() -> list[str]:
	errors: list[str] = []
	document = read_json(ROOT / "data/terrain/navigation_definitions.json")
	for definition in document.get("definitions", []):
		for profile in definition.get("profiles", []):
			nodes = profile.get("nodes", [])
			if not nodes:
				errors.append("empty navigation profile: %s" % profile.get("id", "?"))
				continue
			by_id = {node["id"]: node for node in nodes}
			for node in nodes:
				for neighbor in node.get("neighbors", []):
					if neighbor not in by_id:
						errors.append("navigation node references missing neighbor: %s/%s" % (node["id"], neighbor))
					elif node["id"] not in by_id[neighbor].get("neighbors", []):
						errors.append("navigation edge is not symmetric: %s/%s" % (node["id"], neighbor))
	return errors


def _check_environment_replay() -> list[str]:
	document = read_json(ROOT / "data/environments/environment_zone_definitions.json")
	zone_set = next(item for item in document.get("definitions", []) if item.get("definition_type") == "EnvironmentZoneSet")
	def replay() -> list[tuple]:
		result = []
		for tick in range(1200):
			seconds = tick * 0.1
			for zone in zone_set.get("zones", []):
				active = bool(zone.get("active", True)) and (float(zone.get("duration", 0.0)) <= 0.0 or seconds < float(zone["duration"]))
				if tick in (0, 599, 1199):
					distance = float(zone.get("drift_speed", 0.0)) * seconds
					path = zone.get("drift_path", [])
					offset = sample_polyline(path, distance) if len(path) >= 2 else [distance, 0.0]
					result.append((tick, zone["id"], active, round(offset[0], 6), round(offset[1], 6), zone.get("phase", "")))
		return result
	return [] if replay() == replay() else ["fixed-tick environment replay is not deterministic"]


def _check_forbidden_runtime_references() -> list[str]:
	errors = []
	for relative in [
		"data/terrain/terrain_definitions.json", "data/terrain/navigation_definitions.json",
		"data/environments/environment_zone_definitions.json", "data/facilities/facility_definitions.json",
		"data/facilities/support_mission_definitions.json", "data/facilities/minefield_definitions.json",
	]:
		text = (ROOT / relative).read_text(encoding="utf-8")
		if "/source/" in text or "assets/environment/qa/" in text or "land_collision_manifest" in text:
			errors.append("runtime data references candidate/source/QA content: %s" % relative)
	return errors


def _check_authoring_roundtrip() -> list[str]:
	errors: list[str] = []
	with tempfile.TemporaryDirectory() as temporary:
		root = Path(temporary)
		template_snapshot = root / "template_snapshot.json"
		map_snapshot = root / "map_snapshot.json"
		commands = [
			[sys.executable, "tools/terrain/build_authoring_snapshot.py", "--mode", "Template", "--template-id", "terrain.template.harbor_mouth", "--out", str(template_snapshot)],
			[sys.executable, "tools/terrain/build_authoring_snapshot.py", "--mode", "Map", "--map-id", "terrain.map.harbor_mouth", "--out", str(map_snapshot)],
		]
		for command in commands:
			result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
			if result.returncode != 0:
				return ["authoring snapshot build failed: %s" % result.stderr.strip()]
		pairs = {
			"templates": "data/terrain/terrain_templates.json",
			"maps": "data/terrain/authoring/terrain_maps.json",
			"environment": "data/environments/environment_zone_definitions.json",
			"facilities": "data/facilities/facility_definitions.json",
			"minefields": "data/facilities/minefield_definitions.json",
		}
		copies = {}
		for name, relative in pairs.items():
			copies[name] = root / (name + ".json")
			shutil.copy2(ROOT / relative, copies[name])
		commands = [
			[sys.executable, "tools/terrain/apply_authoring_snapshot.py", "--snapshot", str(template_snapshot), "--templates", str(copies["templates"])],
			[sys.executable, "tools/terrain/apply_authoring_snapshot.py", "--snapshot", str(map_snapshot), "--maps", str(copies["maps"]), "--environment", str(copies["environment"]), "--facilities", str(copies["facilities"]), "--minefields", str(copies["minefields"])],
		]
		for command in commands:
			result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
			if result.returncode != 0:
				return ["authoring snapshot apply failed: %s" % result.stderr.strip()]
		for name, relative in pairs.items():
			if read_json(ROOT / relative) != read_json(copies[name]):
				errors.append("authoring roundtrip changes canonical %s data" % name)
		invalid_payload = read_json(map_snapshot)
		first, second = invalid_payload["facilities"][0], invalid_payload["facilities"][1]
		first.setdefault("metadata", {})["requires_all_active"] = [second["id"]]
		second.setdefault("metadata", {})["requires_all_active"] = [first["id"]]
		invalid_snapshot = root / "invalid_cycle_snapshot.json"
		invalid_snapshot.write_text(json.dumps(invalid_payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
		before = {name: _hash(path) for name, path in copies.items()}
		result = subprocess.run([
			sys.executable, "tools/terrain/apply_authoring_snapshot.py", "--snapshot", str(invalid_snapshot),
			"--maps", str(copies["maps"]), "--environment", str(copies["environment"]),
			"--facilities", str(copies["facilities"]), "--minefields", str(copies["minefields"]),
		], cwd=ROOT, capture_output=True, text=True)
		if result.returncode == 0:
			errors.append("authoring apply accepts a facility dependency cycle")
		if before != {name: _hash(path) for name, path in copies.items()}:
			errors.append("failed authoring apply modified canonical data copies")
	return errors


def main() -> int:
	parser = argparse.ArgumentParser()
	parser.add_argument("--skip-regenerate", action="store_true")
	args = parser.parse_args()
	referenced, errors = _manifest_paths()
	errors += _unreferenced_assets(referenced)
	errors += _deterministic_bake()
	errors += _deterministic_qa_outputs()
	errors += _check_navigation_profiles()
	errors += _check_environment_replay()
	errors += _check_forbidden_runtime_references()
	errors += _check_authoring_roundtrip()
	if not args.skip_regenerate:
		before = {path: _hash(ROOT / path) for path in referenced if (ROOT / path).is_file()}
		result = subprocess.run([sys.executable, "tools/terrain/build_scene_combat_assets.py"], cwd=ROOT, capture_output=True, text=True)
		if result.returncode != 0:
			errors.append("asset regeneration failed: %s" % result.stderr.strip())
		else:
			after = {path: _hash(ROOT / path) for path in before}
			if before != after:
				errors.append("scene-combat asset generation is not deterministic")
	if errors:
		for error in errors:
			print(error, file=sys.stderr)
		return 1
	print("scene-combat pipeline validation passed")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
