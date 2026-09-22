"""Version-bound, per-output visual review shared by both postprocess adapters.

This records review evidence, not an automatic semantic/image-quality verdict.
"""
from __future__ import annotations

import hashlib
import argparse
import json
from pathlib import Path
from typing import Any

from generation_contract import image_facts


def review_path(root: Path, character_id: str) -> Path:
    return root / "assets" / "characters" / character_id / "processed" / "config" / f"{character_id}_delivery_review.json"


def package_snapshot(root: Path, character_id: str) -> tuple[dict[str, str], list[str]]:
    root = root.resolve()
    base = root / "assets" / "characters" / character_id
    files: set[Path] = set()
    for folder in ("concept", "ui", "battle", "vfx", "meta"):
        files.update((base / folder).glob("*.png"))
        files.update((base / folder).glob("*.json"))
    files.update(base.glob("postprocess_plan.json"))
    files.update((base / "processed").rglob("*.png"))
    files.update((base / "processed" / "config").glob("*.json"))
    files.discard(review_path(root, character_id))
    runtime = {path for path in files if path.suffix == ".png" and path.parent.name in {"ui", "battle", "anim", "vfx"}
               and base / "processed" in path.parents}
    # Shared VFX is part of this package's visual contract too.
    vfx = base / "processed" / "config" / f"{character_id}_vfx_config.json"
    if vfx.exists():
        data = json.loads(vfx.read_text(encoding="utf-8"))
        for item in data.get("roles", {}).values():
            if isinstance(item, dict) and item.get("file"):
                path = (root / item["file"]).resolve()
                path.relative_to(root.resolve())  # No arbitrary external reads.
                files.add(path)
                runtime.add(path)
    snapshot = {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
                if path.is_file() else "missing" for path in sorted(files)}
    return snapshot, sorted(str(path.relative_to(root)) for path in runtime)


def write_review(root: Path, character_id: str, manifest: dict[str, Any]) -> Path:
    snapshot, runtime = package_snapshot(root, character_id)
    path = review_path(root, character_id)
    previous: dict[str, Any] = {}
    if path.exists():
        try:
            previous = json.loads(path.read_text(encoding="utf-8"))
        except (ValueError, OSError):
            pass
    if not isinstance(previous, dict):
        previous = {}
    unchanged = previous.get("package_sha256") == snapshot
    previous_assets = previous.get("assets", {}) if unchanged else {}
    if not isinstance(previous_assets, dict):
        previous_assets = {}
    metadata = {item.get("path", item.get("file")): item
                for item in manifest.get("outputs", manifest.get("components", []))}
    assets = {}
    for filename in runtime:
        old = previous_assets.get(filename, {})
        if not isinstance(old, dict):
            old = {}
        entry = metadata.get(filename, {})
        crop = entry.get("crop", entry.get("source_crop_qa", {}))
        assets[filename] = {
            "sha256": snapshot[filename],
            "alpha_facts": image_facts(root / filename) if snapshot[filename] != "missing" else {},
            "crop_evidence": crop,
            "review": old.get("review", {"verdict": "pending", "reviewer": "", "observation": ""}),
        }
    document = {
        "schema_version": 1, "character_id": character_id,
        "scope": "Visual evidence only; technical contract must pass separately. Not runtime acceptance.",
        "checklist": ["identity_and_inventory", "no_truncation_or_neighbor_fragments",
                      "alpha_edges_and_small_scale_readability", "animation_consistency",
                      "mechanical_binding_and_vfx_semantics"],
        "package_sha256": snapshot, "assets": assets,
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return path


def inspect_review(root: Path, character_id: str) -> dict[str, Any]:
    path = review_path(root, character_id)
    if not path.exists():
        return {"status": "pending", "accepted": False, "issues": ["delivery visual review missing"]}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        snapshot, runtime = package_snapshot(root, character_id)
        if not isinstance(data, dict) or data.get("schema_version") != 1 or data.get("character_id") != character_id:
            raise ValueError("invalid review identity/schema")
        if data.get("package_sha256") != snapshot:
            return {"status": "stale", "accepted": False, "issues": ["source, crop, output or configuration changed"]}
        assets = data.get("assets")
        if not isinstance(assets, dict) or not runtime or set(assets) != set(runtime):
            raise ValueError("review does not cover exact runtime inventory")
        issues = []
        polish = False
        blocked = False
        for filename in runtime:
            entry = assets[filename]
            if not isinstance(entry, dict) or entry.get("sha256") != snapshot[filename] or snapshot[filename] == "missing":
                raise ValueError(f"invalid reviewed asset: {filename}")
            review = entry.get("review", {})
            if not isinstance(review, dict):
                raise ValueError(f"invalid review: {filename}")
            verdict = review.get("verdict")
            blocked |= verdict == "blocker"
            polish |= verdict == "polish"
            if verdict not in {"pass", "polish"} or not all(isinstance(review.get(key), str) and review[key].strip()
                                                            for key in ("reviewer", "observation")):
                issues.append(f"visual review pending/blocking: {filename}")
        status = "blocker" if blocked else "pending" if issues else "polish" if polish else "pass"
        return {"status": status, "accepted": not issues, "issues": issues}
    except (ValueError, OSError, TypeError, AttributeError) as exc:
        return {"status": "invalid", "accepted": False, "issues": [str(exc)]}


def main() -> int:
    parser = argparse.ArgumentParser(description="Prepare or inspect version-bound visual review; never auto-approve artwork.")
    parser.add_argument("character_ids", nargs="+")
    parser.add_argument("--prepare", action="store_true", help="Create/refresh review checklist without changing images or runtime configs.")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    accepted = True
    for character_id in args.character_ids:
        if not character_id or any(char not in "abcdefghijklmnopqrstuvwxyz0123456789_" for char in character_id):
            parser.error("character ids must be lowercase repository identifiers")
        if args.prepare:
            manifest_path = review_path(root, character_id).with_name(f"{character_id}_postprocess_manifest.json")
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            write_review(root, character_id, manifest)
        review = inspect_review(root, character_id)
        print(json.dumps({"character_id": character_id, **review}, ensure_ascii=False))
        accepted = accepted and review["accepted"]
    # Preparing a pending checklist is successful; inspection is a delivery gate.
    return 0 if args.prepare or accepted else 1


if __name__ == "__main__":
    raise SystemExit(main())
