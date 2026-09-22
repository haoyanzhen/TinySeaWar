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
from delivery_review import inspect_review
from generation_contract import is_frozen_legacy_package


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

def available_character_ids(phase: str = "phase1") -> list[str]:
    return [entry.character_id for entry in character_roster.load_roster(phase=phase)]


def provenance_quality_issues(character_id: str) -> list[str]:
    root = CHAR_ROOT / character_id
    issues: list[str] = []
    plan_path = root / "postprocess_plan.json"
    provenance_path = root / "meta" / f"{character_id}_source_provenance.json"
    versioned_provenance_path = root / "meta" / f"{character_id}_source_provenance_v2.json"
    require_schema_v2 = False
    legacy_exempt = False
    if plan_path.exists():
        plan = json.loads(plan_path.read_text(encoding="utf-8"))
        legacy_manifest_path = (
            root / "processed" / "config" / f"{character_id}_postprocess_manifest.json"
        )
        legacy_exempt = is_frozen_legacy_package(character_id, legacy_manifest_path)
        require_schema_v2 = int(plan.get("manifest_schema_version", 1)) >= 2
        if (
            require_schema_v2
            and not provenance_path.exists()
            and not versioned_provenance_path.exists()
            and not legacy_exempt
        ):
            issues.append("schema-v2 source provenance missing")
    source_path = versioned_provenance_path if versioned_provenance_path.exists() else provenance_path
    if (
        require_schema_v2
        and source_path.exists()
        and (not legacy_exempt or versioned_provenance_path.exists())
    ):
        try:
            source_payload = json.loads(source_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            pass
        else:
            if int(source_payload.get("schema_version", 1)) < 2:
                issues.append("schema-v2 source provenance required; schema-v1 is historical only")
    candidate_paths = [root / "placeholder_source_provenance.json", source_path]
    if not versioned_provenance_path.exists():
        candidate_paths.append(
            root / "processed" / "config" / f"{character_id}_postprocess_manifest.json"
        )
    for path in candidate_paths:
        if not path.exists():
            continue
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            issues.append(f"source provenance invalid JSON: {path.relative_to(ROOT)} ({exc})")
            continue
        nested = payload.get("source_provenance")
        candidates = [nested] if isinstance(nested, dict) else [payload]
        for candidate in candidates:
            if candidate.get("batch_ready_allowed") is False:
                source = candidate.get("source", path.relative_to(ROOT))
                kind = candidate.get("kind", "placeholder")
                issues.append(f"non-production source provenance: {kind} from {source}")
            if int(candidate.get("schema_version", 1)) >= 2:
                issues.extend(
                    f"strict source provenance: {issue}"
                    for issue in contract.validate_source_provenance(candidate)
                )
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
        hardcoded or configuration["generic_postprocess"]
    )


def inspect_character(character_id: str) -> dict[str, Any]:
    sources = source_check(character_id)
    configuration = configuration_check(character_id)
    can_audit = configuration["contract_ship_class"]
    audit = contract.audit(character_id) if can_audit else None
    configured = is_configured(configuration)
    contract_complete = bool(audit and audit["status"] == "complete")
    visual_review = inspect_review(ROOT, character_id)
    technical_ready = sources["complete"] and configured and contract_complete
    return {
        "character_id": character_id,
        "sources": sources,
        "configuration": configuration,
        "contract": audit,
        "batch_ready": technical_ready,
        "technical_ready": technical_ready,
        "visual_review": visual_review,
        "delivery_ready": technical_ready and visual_review["accepted"],
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
        pipeline.process_character(character_id)
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


def write_reports(mode: str, results: list[dict[str, Any]], phase: str = "phase1", report_tag: str | None = None,
                  require_delivery: bool = False) -> tuple[Path, Path]:
    if report_tag is not None and (not report_tag or any(char not in "abcdefghijklmnopqrstuvwxyz0123456789_-" for char in report_tag)):
        raise ValueError("report tag must contain lowercase letters, digits, underscores or hyphens")
    QA_ROOT.mkdir(parents=True, exist_ok=True)
    suffix = "" if phase == "phase1" else f"_{phase}"
    if report_tag:
        suffix += f"_{report_tag}"
    json_path = QA_ROOT / f"character_art_batch_report{suffix}.json"
    markdown_path = QA_ROOT / f"character_art_batch_report{suffix}.md"
    payload = {
        "mode": mode,
        "required_gate": "delivery_ready" if require_delivery else "technical_ready",
        "gate_passed": batch_exit_code(results, require_delivery) == 0,
        "summary": {
            "characters": len(results),
            "batch_ready": sum(
                bool(result.get("inspection", result).get("batch_ready"))
                for result in results
            ),
            "complete": sum(result.get("status") == "complete" for result in results),
            "delivery_ready": sum(bool(result.get("inspection", result).get("delivery_ready")) for result in results),
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
        f"Required gate: `{payload['required_gate']}`; passed: `{payload['gate_passed']}`.",
        "",
        "Roster source: `docs/41_character_art_design.md`.",
        "",
        "| Character | Prototype | Source route | Sources | Four-frame | Source blockers | Configured | Contract | Technical ready | Visual review | Delivery ready | Run status |",
        "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
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
            f'{"yes" if inspection["batch_ready"] else "no"} | '
            f'{inspection.get("visual_review", {}).get("status", "pending")} | '
            f'{"yes" if inspection.get("delivery_ready") else "no"} | {run_status} |'
        )
    lines.extend([
        "",
        "A character is batch-ready only when either the legacy sheet route or generated source route is complete, no non-production source provenance is present, a valid postprocess route exists, and the processed asset contract passes.",
        "batch_ready is the backward-compatible technical_ready flag, not a visual verdict. delivery_ready additionally requires current, per-output visual review; neither proves in-engine acceptance.",
        "Failures are isolated per character and do not stop later characters in the batch.",
        "",
    ])
    markdown_path.write_text("\n".join(lines), encoding="utf-8")
    return json_path, markdown_path


def batch_exit_code(results: list[dict[str, Any]], require_delivery: bool = False) -> int:
    if not results:
        return 1
    field = "delivery_ready" if require_delivery else "batch_ready"
    return int(any(result.get("status") not in {None, "complete"}
                   or not result.get("inspection", result).get(field, False) for result in results))


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate or run TinySeaWar character-art batches.")
    parser.add_argument("character_ids", nargs="*", help="Defaults to all characters in docs/41_character_art_design.md.")
    parser.add_argument("--process", action="store_true", help="Run postprocess instead of dry-run inspection.")
    parser.add_argument("--preview", action="store_true", help="Build per-character embedded QA previews.")
    parser.add_argument("--phase", choices=("phase1", "phase2", "all"), default="phase1")
    parser.add_argument("--require-delivery", action="store_true", help="Fail unless current visual review and technical gates both pass.")
    parser.add_argument("--report-tag", help="Keep this batch report separate from the phase-wide report.")
    args = parser.parse_args()

    character_ids = args.character_ids or available_character_ids(args.phase)
    known_ids = set(available_character_ids("all"))
    if any(character_id not in known_ids for character_id in character_ids):
        parser.error("unknown character id; use a roster identifier")
    if args.report_tag is not None and (not args.report_tag or any(char not in "abcdefghijklmnopqrstuvwxyz0123456789_-" for char in args.report_tag)):
        parser.error("invalid --report-tag")
    if args.process:
        results = [process_one(character_id, args.preview) for character_id in character_ids]
        mode = "process"
    else:
        results = [inspect_character(character_id) for character_id in character_ids]
        mode = "dry-run"
    json_path, markdown_path = write_reports(mode, results, args.phase, args.report_tag, args.require_delivery)
    print(json.dumps({"mode": mode, "results": results}, ensure_ascii=False, indent=2))
    print(f"json_report: {json_path.relative_to(ROOT)}")
    print(f"markdown_report: {markdown_path.relative_to(ROOT)}")
    return batch_exit_code(results, args.require_delivery)


if __name__ == "__main__":
    raise SystemExit(main())
