from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path
from typing import Any

import check_character_asset_contract as contract
import character_roster
import postprocess_generated_character as generic_pipeline
import postprocess_trial_sheets as pipeline


ROOT = Path(__file__).resolve().parents[2]
CHAR_ROOT = ROOT / "assets" / "characters"
QA_ROOT = CHAR_ROOT / "qa"

LEGACY_BASE_SOURCE_FILES = (
    "concept/{id}_concept_full.png",
    "ui/{id}_illust_half.png",
    "ui/{id}_illust_skill_cutin.png",
    "ui/{id}_ui_sheet.png",
    "battle/{id}_battle_asset_sheet.png",
    "vfx/{id}_vfx_reference_sheet.png",
)

LEGACY_FOUR_FRAME_SOURCE_FILES = tuple(
    f"battle/{{id}}_anim_{state}_4f_sheet.png"
    for state in ("idle", "move", "attack", "hit", "firepower")
)

GENERATED_BASE_SOURCE_FILES = (
    "concept/{id}_concept_full.png",
    "ui/{id}_ui_sheet.png",
    "vfx/{id}_vfx_reference_sheet.png",
)

GENERATED_BATTLE_SOURCE_FILES = (
    "battle/{id}_battle_asset_grid.png",
    "battle/{id}_battle_asset_sheet.png",
)

GENERATED_ANIMATION_MASTER_FILE = "battle/{id}_anim_5x4_master.png"

GENERATED_ANIMATION_STATE_FILES = tuple(
    f"battle/{{id}}_anim_{state}_4f_sheet.png"
    for state in ("idle", "move", "attack", "hit", "firepower")
)

SOURCE_PROVENANCE_FILES = (
    "placeholder_source_provenance.json",
    "meta/{id}_source_provenance.json",
    "processed/config/{id}_postprocess_manifest.json",
)


def available_character_ids(phase: str = "phase1") -> list[str]:
    return [entry.character_id for entry in character_roster.load_roster(phase=phase)]


def provenance_quality_issues(character_id: str) -> list[str]:
    root = CHAR_ROOT / character_id
    issues: list[str] = []
    for pattern in SOURCE_PROVENANCE_FILES:
        path = root / pattern.format(id=character_id)
        if not path.exists():
            continue
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            issues.append(f"source provenance invalid JSON: {path.relative_to(ROOT)} ({exc})")
            continue
        candidates = [payload]
        if isinstance(payload.get("source_provenance"), dict):
            candidates.append(payload["source_provenance"])
        for candidate in candidates:
            if candidate.get("batch_ready_allowed") is False:
                source = candidate.get("source", path.relative_to(ROOT))
                kind = candidate.get("kind", "placeholder")
                issues.append(f"non-production source provenance: {kind} from {source}")
    return issues


def source_check(character_id: str) -> dict[str, Any]:
    root = CHAR_ROOT / character_id
    source_quality_issues = provenance_quality_issues(character_id)
    legacy_base_complete = all(
        (root / pattern.format(id=character_id)).exists()
        for pattern in LEGACY_BASE_SOURCE_FILES
    )
    legacy_animation_complete = all(
        (root / pattern.format(id=character_id)).exists()
        for pattern in LEGACY_FOUR_FRAME_SOURCE_FILES
    )
    generated_base_complete = all(
        (root / pattern.format(id=character_id)).exists()
        for pattern in GENERATED_BASE_SOURCE_FILES
    ) and any(
        (root / pattern.format(id=character_id)).exists()
        for pattern in GENERATED_BATTLE_SOURCE_FILES
    )
    generated_animation_master_complete = (
        root / GENERATED_ANIMATION_MASTER_FILE.format(id=character_id)
    ).exists()
    generated_animation_state_complete = all(
        (root / pattern.format(id=character_id)).exists()
        for pattern in GENERATED_ANIMATION_STATE_FILES
    )
    generated_animation_complete = generated_animation_state_complete or generated_animation_master_complete

    legacy_complete = legacy_base_complete and legacy_animation_complete
    generated_complete = generated_base_complete and generated_animation_complete
    if generated_complete:
        route = "generated_state_sheets" if generated_animation_state_complete else "generated_master"
        required = GENERATED_BASE_SOURCE_FILES + (
            GENERATED_ANIMATION_STATE_FILES if generated_animation_state_complete else (GENERATED_ANIMATION_MASTER_FILE,)
        )
        missing = []
    elif legacy_complete:
        route = "legacy_sheets"
        required = LEGACY_BASE_SOURCE_FILES + LEGACY_FOUR_FRAME_SOURCE_FILES
        missing = []
    else:
        route = "incomplete"
        generated_required = GENERATED_BASE_SOURCE_FILES + GENERATED_ANIMATION_STATE_FILES
        missing = [
            pattern.format(id=character_id)
            for pattern in generated_required
            if not (root / pattern.format(id=character_id)).exists()
        ]
        if not generated_animation_state_complete and not generated_animation_master_complete:
            missing.append(GENERATED_ANIMATION_MASTER_FILE.format(id=character_id))
        if not any(
            (root / pattern.format(id=character_id)).exists()
            for pattern in GENERATED_BATTLE_SOURCE_FILES
        ):
            missing.append("battle/{id}_battle_asset_grid.png|battle/{id}_battle_asset_sheet.png".format(id=character_id))
    return {
        "complete": (legacy_complete or generated_complete) and not source_quality_issues,
        "missing": missing,
        "source_quality_issues": source_quality_issues,
        "base_complete": legacy_base_complete or generated_base_complete,
        "four_frame_complete": legacy_animation_complete or generated_animation_complete,
        "production_route": route,
    }


def configuration_check(character_id: str) -> dict[str, bool]:
    return {
        "crop_specs": character_id in pipeline.SPECS,
        "runtime_config": character_id in pipeline.CONFIGS,
        "postprocess_plan": (CHAR_ROOT / character_id / "postprocess_plan.json").exists(),
        "generic_postprocess": generic_pipeline.can_process(character_id),
        "contract_ship_class": character_id in contract.SHIP_CLASSES,
    }


def is_configured(configuration: dict[str, bool]) -> bool:
    hardcoded = configuration["crop_specs"] and configuration["runtime_config"]
    return configuration["contract_ship_class"] and (
        hardcoded or configuration["postprocess_plan"] or configuration["generic_postprocess"]
    )


def inspect_character(character_id: str) -> dict[str, Any]:
    sources = source_check(character_id)
    configuration = configuration_check(character_id)
    can_audit = configuration["contract_ship_class"]
    audit = contract.audit(character_id) if can_audit else None
    configured = is_configured(configuration)
    contract_complete = bool(audit and audit["status"] == "complete")
    return {
        "character_id": character_id,
        "sources": sources,
        "configuration": configuration,
        "contract": audit,
        "batch_ready": sources["complete"] and configured and contract_complete,
        "postprocess_ready": sources["complete"] and configured,
    }


def process_one(character_id: str, preview: bool) -> dict[str, Any]:
    started = time.monotonic()
    before = inspect_character(character_id)
    if not before["postprocess_ready"]:
        return {
            "character_id": character_id,
            "status": "blocked",
            "elapsed_seconds": round(time.monotonic() - started, 2),
            "inspection": before,
        }
    try:
        if before["configuration"]["crop_specs"] and before["configuration"]["runtime_config"]:
            pipeline.process_character(character_id)
        else:
            generic_pipeline.process_character(character_id)
        preview_path = None
        if preview:
            preview_path = pipeline.build_edge_qa_preview((character_id,))
        after = inspect_character(character_id)
        return {
            "character_id": character_id,
            "status": "complete" if after["batch_ready"] else "incomplete",
            "elapsed_seconds": round(time.monotonic() - started, 2),
            "preview": str(preview_path.relative_to(ROOT)) if preview_path else None,
            "inspection": after,
        }
    except Exception as exc:
        return {
            "character_id": character_id,
            "status": "failed",
            "elapsed_seconds": round(time.monotonic() - started, 2),
            "error": f"{type(exc).__name__}: {exc}",
            "inspection": inspect_character(character_id),
        }


def write_reports(mode: str, results: list[dict[str, Any]], phase: str = "phase1") -> tuple[Path, Path]:
    QA_ROOT.mkdir(parents=True, exist_ok=True)
    suffix = "" if phase == "phase1" else f"_{phase}"
    json_path = QA_ROOT / f"character_art_batch_report{suffix}.json"
    markdown_path = QA_ROOT / f"character_art_batch_report{suffix}.md"
    payload = {
        "mode": mode,
        "summary": {
            "characters": len(results),
            "batch_ready": sum(
                bool(result.get("inspection", result).get("batch_ready"))
                for result in results
            ),
            "complete": sum(result.get("status") == "complete" for result in results),
            "blocked": sum(result.get("status") == "blocked" for result in results),
            "failed": sum(result.get("status") == "failed" for result in results),
        },
        "results": results,
    }
    json_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    roster = character_roster.roster_by_id("all")
    lines = [
        "# Character Art Batch Report",
        "",
        f"Mode: `{mode}`",
        "",
        "Roster source: `docs/41_character_art_design.md`.",
        "",
        "| Character | Prototype | Source route | Sources | Four-frame | Source blockers | Configured | Contract | Batch ready | Run status |",
        "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for result in results:
        inspection = result.get("inspection", result)
        entry = roster.get(inspection["character_id"])
        prototype = entry.prototype if entry else "-"
        sources = inspection["sources"]
        configured = is_configured(inspection["configuration"])
        audit = inspection.get("contract")
        contract_status = audit["status"] if audit else "unavailable"
        run_status = result.get("status", "dry-run")
        lines.append(
            f'| {inspection["character_id"]} | '
            f'{prototype} | '
            f'{sources["production_route"]} | '
            f'{"yes" if sources["base_complete"] else "no"} | '
            f'{"yes" if sources["four_frame_complete"] else "no"} | '
            f'{", ".join(sources.get("source_quality_issues", [])) or "-"} | '
            f'{"yes" if configured else "no"} | {contract_status} | '
            f'{"yes" if inspection["batch_ready"] else "no"} | {run_status} |'
        )
    lines.extend([
        "",
        "A character is batch-ready only when either the legacy sheet route or generated source route is complete, no non-production source provenance is present, a valid postprocess route exists, and the processed asset contract passes.",
        "Failures are isolated per character and do not stop later characters in the batch.",
        "",
    ])
    markdown_path.write_text("\n".join(lines), encoding="utf-8")
    return json_path, markdown_path


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate or run TinySeaWar character-art batches.")
    parser.add_argument("character_ids", nargs="*", help="Defaults to all characters in docs/41_character_art_design.md.")
    parser.add_argument("--process", action="store_true", help="Run postprocess instead of dry-run inspection.")
    parser.add_argument("--preview", action="store_true", help="Build per-character embedded QA previews.")
    parser.add_argument("--phase", choices=("phase1", "phase2", "all"), default="phase1")
    args = parser.parse_args()

    character_ids = args.character_ids or available_character_ids(args.phase)
    if args.process:
        results = [process_one(character_id, args.preview) for character_id in character_ids]
        mode = "process"
    else:
        results = [inspect_character(character_id) for character_id in character_ids]
        mode = "dry-run"
    json_path, markdown_path = write_reports(mode, results, args.phase)
    print(json.dumps({"mode": mode, "results": results}, ensure_ascii=False, indent=2))
    print(f"json_report: {json_path.relative_to(ROOT)}")
    print(f"markdown_report: {markdown_path.relative_to(ROOT)}")
    if args.process:
        return 1 if any(result["status"] != "complete" for result in results) else 0
    return 1 if any(not result["batch_ready"] for result in results) else 0


if __name__ == "__main__":
    raise SystemExit(main())
