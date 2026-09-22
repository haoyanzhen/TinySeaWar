from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

from generation_contract import (
    CODEX_BUILTIN_MODEL,
    CODEX_BUILTIN_ROUTE,
    EXPECTED_SOURCE_ROLES,
    image_facts,
    native_alpha_issues,
)


ROOT = Path(__file__).resolve().parents[2]
CHAR_ROOT = ROOT / "assets" / "characters"


def sha256_path(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def source_paths(character_id: str) -> dict[str, Path]:
    if not character_id or any(char not in "abcdefghijklmnopqrstuvwxyz0123456789_" for char in character_id):
        raise ValueError("character id must be a lowercase repository identifier")
    root = CHAR_ROOT / character_id
    paths = {
        "concept_full": root / "concept" / f"{character_id}_concept_full.png",
        "ui_sheet": root / "ui" / f"{character_id}_ui_sheet.png",
        "battle_grid": root / "battle" / f"{character_id}_battle_asset_grid.png",
        "vfx_sheet": root / "vfx" / f"{character_id}_vfx_reference_sheet.png",
    }
    for state in ("idle", "move", "attack", "hit", "firepower"):
        paths[f"anim_{state}"] = (
            root / "battle" / f"{character_id}_anim_{state}_4f_sheet.png"
        )
    return paths


def load_reviews(character_id: str) -> dict[str, Any]:
    path = CHAR_ROOT / character_id / "meta" / f"{character_id}_source_review.json"
    if not path.exists():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or data.get("character_id") != character_id:
        raise ValueError("source review character_id mismatch or invalid document")
    sources = data.get("sources")
    if not isinstance(sources, dict) or any(not isinstance(item, dict) for item in sources.values()):
        raise ValueError("source review sources must contain review objects")
    if set(sources) - EXPECTED_SOURCE_ROLES:
        raise ValueError("source review contains unknown source roles")
    return data


def reviewed_source(review: dict[str, Any], checksum: str) -> bool:
    return (
        review.get("sha256") == checksum
        and review.get("verdict") in ("pass", "polish", "blocker")
        and all(isinstance(review.get(key), str) and review[key].strip()
                for key in ("reviewer", "observation"))
    )


def prepare_source_review(character_id: str) -> Path:
    """Refresh a checklist without approving sources or relabeling stale evidence."""
    paths = source_paths(character_id)
    previous = load_reviews(character_id).get("sources", {})
    sources = {}
    for role, path in paths.items():
        checksum = sha256_path(path) if path.is_file() else "missing"
        old = previous.get(role, {})
        if old.get("sha256") == checksum and (old.get("verdict") == "pending" or
                                               (checksum != "missing" and reviewed_source(old, checksum))):
            sources[role] = old
        else:
            sources[role] = {"sha256": checksum, "verdict": "pending", "reviewer": "", "observation": ""}
            if old:
                sources[role]["previous_review"] = {key: old.get(key) for key in
                                                     ("sha256", "verdict", "reviewer", "observation")}
    output = CHAR_ROOT / character_id / "meta" / f"{character_id}_source_review.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps({"character_id": character_id, "sources": sources}, ensure_ascii=False, indent=2) + "\n",
                      encoding="utf-8")
    return output


def record_character(character_id: str) -> Path:
    paths = source_paths(character_id)
    if set(paths) != EXPECTED_SOURCE_ROLES:
        raise RuntimeError("Codex built-in source role map does not match the production contract")
    missing = [str(path.relative_to(ROOT)) for path in paths.values() if not path.exists()]
    if missing:
        raise FileNotFoundError("source package is incomplete: " + ", ".join(missing))

    brief_path = (
        CHAR_ROOT
        / character_id
        / "meta"
        / f"{character_id}_generation_brief_v2.md"
    )
    if not brief_path.exists():
        raise FileNotFoundError(f"generation brief missing: {brief_path.relative_to(ROOT)}")

    reviews = load_reviews(character_id)
    records: list[dict[str, Any]] = []
    for role, path in paths.items():
        facts = image_facts(path)
        issues = native_alpha_issues(facts)
        if issues:
            raise ValueError(f"{role} failed native-alpha QA: {'; '.join(issues)}")
        checksum = sha256_path(path)
        review = reviews.get("sources", {}).get(role, {})
        reviewed = reviewed_source(review, checksum)
        records.append(
            {
                "role": role,
                "path": str(path.relative_to(ROOT)),
                "sha256": checksum,
                "size": [facts["width"], facts["height"]],
                "source_mode": facts["source_mode"],
                "background": "native_transparent",
                "generation_route": CODEX_BUILTIN_ROUTE,
                "model": CODEX_BUILTIN_MODEL,
                "quality": "Codex account-managed",
                "size_control": "Codex account-managed",
                "background_control": "transparent",
                "output_format": facts["format"],
                "endpoint": "codex_builtin_imagegen",
                "request_id": "not_exposed_by_codex_builtin",
                "raw_response_sha256": checksum,
                "accepted_source_is_raw_response": True,
                "alpha": {
                    "has_alpha_channel": facts["has_alpha_channel"],
                    "min": facts["alpha_min"],
                    "max": facts["alpha_max"],
                    "transparent_canvas_ratio": facts["transparent_canvas_ratio"],
                    "transparent_border_ratio": facts["transparent_border_ratio"],
                },
                "technical_qa_verdict": "pass",
                "qa_verdict": review["verdict"] if reviewed else "pending",
                "qa_reviewer": review["reviewer"] if reviewed else "",
                "qa_observation": review["observation"] if reviewed else "Awaiting current-hash visual review.",
            }
        )

    payload = {
        "schema_version": 2,
        "character_id": character_id,
        "kind": "codex_builtin_generated_art",
        "source": "Codex built-in ImageGen",
        "batch_ready_allowed": all(record["qa_verdict"] in ("pass", "polish") for record in records),
        "generation_policy": {
            "primary_route": CODEX_BUILTIN_ROUTE,
            "legacy_fallback": {
                "authorized": False,
                "activation": "--allow-legacy-chroma-fallback",
                "reason": "",
                "native_failures": [],
            },
        },
        "generation": {
            "requested_model": CODEX_BUILTIN_MODEL,
            "actual_model": CODEX_BUILTIN_MODEL,
            "generation_tool": "Codex built-in ImageGen",
            "endpoint": "Codex account-managed image generation",
            "quality": "Codex account-managed",
            "size_control": "per-asset Codex account-managed output",
            "background_control": "transparent requested and pixel-verified",
            "output_format": "PNG",
            "prompt_revision": {
                "path": str(brief_path.relative_to(ROOT)),
                "sha256": sha256_path(brief_path),
            },
            "reference_inputs": [
                {
                    "path": str(paths["concept_full"].relative_to(ROOT)),
                    "role": "accepted_style_anchor_for_derivative_sheets",
                }
            ],
            "reproducibility_note": (
                "The Codex account manages the underlying image model and request IDs; "
                "those implementation details are not exposed. Accepted PNG outputs are "
                "preserved byte-for-byte and tracked by SHA-256."
            ),
        },
        "source_images": records,
    }
    output_path = (
        CHAR_ROOT
        / character_id
        / "meta"
        / f"{character_id}_source_provenance_v2.json"
    )
    output_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return output_path


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Record native-alpha art generated by Codex built-in ImageGen."
    )
    parser.add_argument("character_ids", nargs="+")
    parser.add_argument("--prepare-review", action="store_true",
                        help="Prepare/refresh source checklist only; never approve or record provenance.")
    args = parser.parse_args()
    for character_id in args.character_ids:
        output_path = prepare_source_review(character_id) if args.prepare_review else record_character(character_id)
        print(output_path.relative_to(ROOT))


if __name__ == "__main__":
    main()
