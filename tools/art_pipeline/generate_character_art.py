from __future__ import annotations

import argparse
import base64
from contextlib import ExitStack
from datetime import UTC, datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
from typing import Any

import openai
from openai import OpenAI

import character_roster
from generation_contract import (
    ALLOWED_GPT_IMAGE_MODELS,
    LEGACY_CHROMA_ROUTE,
    NATIVE_ALPHA_ROUTE,
    image_facts,
    legacy_chroma_issues,
    native_alpha_issues,
)


ROOT = Path(__file__).resolve().parents[2]
CHAR_ROOT = ROOT / "assets" / "characters"
RAW_ROOT = ROOT / "artifacts" / "art_pipeline" / "raw"
PROVENANCE_SCHEMA_VERSION = 2

ROLE_SPECS: dict[str, dict[str, Any]] = {
    "concept_full": {
        "section": "Style anchor",
        "path": "concept/{id}_concept_full.png",
        "size": "1024x1536",
        "reference": False,
    },
    "ui_sheet": {
        "section": "UI 4x2 sheet",
        "path": "ui/{id}_ui_sheet.png",
        "size": "1536x1024",
        "reference": True,
    },
    "battle_grid": {
        "section": "Battle 4x2 sheet",
        "path": "battle/{id}_battle_asset_grid.png",
        "size": "1536x1024",
        "reference": True,
    },
    "anim_idle": {
        "section": "Animation 2x2 state sheets",
        "path": "battle/{id}_anim_idle_4f_sheet.png",
        "size": "1024x1024",
        "reference": True,
        "state": "idle",
    },
    "anim_move": {
        "section": "Animation 2x2 state sheets",
        "path": "battle/{id}_anim_move_4f_sheet.png",
        "size": "1024x1024",
        "reference": True,
        "state": "move",
    },
    "anim_attack": {
        "section": "Animation 2x2 state sheets",
        "path": "battle/{id}_anim_attack_4f_sheet.png",
        "size": "1024x1024",
        "reference": True,
        "state": "attack",
    },
    "anim_hit": {
        "section": "Animation 2x2 state sheets",
        "path": "battle/{id}_anim_hit_4f_sheet.png",
        "size": "1024x1024",
        "reference": True,
        "state": "hit",
    },
    "anim_firepower": {
        "section": "Animation 2x2 state sheets",
        "path": "battle/{id}_anim_firepower_4f_sheet.png",
        "size": "1024x1024",
        "reference": True,
        "state": "firepower",
    },
    "vfx_sheet": {
        "section": "VFX 2x4 sheet",
        "path": "vfx/{id}_vfx_reference_sheet.png",
        "size": "1536x1024",
        "reference": True,
    },
}

BATCH_ROLES = {
    "anchor": ("concept_full",),
    "ui": ("ui_sheet",),
    "battle": ("battle_grid",),
    "animation": ("anim_idle", "anim_move", "anim_attack", "anim_hit", "anim_firepower"),
    "vfx": ("vfx_sheet",),
}


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def sha256_path(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def generation_brief_path(character_id: str) -> Path:
    root = CHAR_ROOT / character_id / "meta"
    native_path = root / f"{character_id}_generation_brief_v2.md"
    if native_path.exists():
        return native_path
    return root / f"{character_id}_generation_brief.md"


def source_provenance_path(character_id: str) -> Path:
    root = CHAR_ROOT / character_id / "meta"
    versioned_path = root / f"{character_id}_source_provenance_v2.json"
    if versioned_path.exists():
        return versioned_path
    canonical_path = root / f"{character_id}_source_provenance.json"
    native_brief = root / f"{character_id}_generation_brief_v2.md"
    if native_brief.exists() and canonical_path.exists():
        canonical = json.loads(canonical_path.read_text(encoding="utf-8"))
        if int(canonical.get("schema_version", 1)) < PROVENANCE_SCHEMA_VERSION:
            return versioned_path
    return canonical_path


def markdown_section(document: str, heading: str) -> str:
    match = re.search(
        rf"^## {re.escape(heading)}\s*$\n(?P<body>.*?)(?=^## |\Z)",
        document,
        flags=re.MULTILINE | re.DOTALL,
    )
    if not match:
        raise ValueError(f"generation brief section missing: {heading}")
    return match.group("body").strip()


def prompt_for_role(document: str, role: str, legacy_chroma: bool = False) -> str:
    spec = ROLE_SPECS[role]
    shared = markdown_section(document, "Shared prompt core")
    section = markdown_section(document, str(spec["section"]))
    acceptance = markdown_section(document, "Acceptance rules")
    if role == "concept_full":
        prompt = f"{section}\n\nAcceptance rules:\n{acceptance}"
    else:
        prompt = f"{shared}\n\n{section}\n\nAcceptance rules:\n{acceptance}"
    state = spec.get("state")
    if state:
        prompt += (
            f"\n\nGenerate only the {state} state as one 2x2 four-frame sheet; "
            "do not include any other animation state."
        )
    if legacy_chroma:
        prompt += (
            "\n\nLAST-RESORT LEGACY FALLBACK: this clause overrides earlier native-transparent "
            "output wording for this request only. Render one flat reserved near-#00FF00 "
            "background with no gradient, shadow, texture, or checkerboard. Do not use that key color in the artwork."
        )
    else:
        prompt += (
            "\n\nOUTPUT CONTRACT: return native transparency. Do not paint white, black, gray, "
            "green, or checkerboard pixels as a background."
        )
    return prompt


def request_image(
    client: OpenAI,
    *,
    prompt: str,
    model: str,
    quality: str,
    size: str,
    background: str,
    reference: Path | None,
) -> tuple[bytes, str, str]:
    common: dict[str, Any] = {
        "model": model,
        "prompt": prompt,
        "background": background,
        "output_format": "png",
        "quality": quality,
        "size": size,
        "response_format": "b64_json",
    }
    if reference is None:
        raw_response = client.images.with_raw_response.generate(**common)
        endpoint = "/v1/images/generations"
    else:
        with ExitStack() as stack:
            reference_file = stack.enter_context(reference.open("rb"))
            raw_response = client.images.with_raw_response.edit(
                image=reference_file,
                input_fidelity="high",
                **common,
            )
        endpoint = "/v1/images/edits"
    parsed = raw_response.parse()
    if not parsed.data or not parsed.data[0].b64_json:
        raise RuntimeError("OpenAI Images API returned no base64 image payload")
    request_id = str(raw_response.headers.get("x-request-id", "not-exposed"))
    return base64.b64decode(parsed.data[0].b64_json), request_id, endpoint


def save_raw_candidate(character_id: str, role: str, payload: bytes, request_id: str, attempt: str) -> Path:
    timestamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    safe_request_id = re.sub(r"[^A-Za-z0-9_.-]+", "_", request_id)
    path = RAW_ROOT / character_id / f"{timestamp}_{role}_{attempt}_{safe_request_id}.png"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)
    return path


def write_accepted_source(raw_path: Path, output_path: Path, overwrite: bool) -> None:
    if output_path.exists() and not overwrite:
        raise FileExistsError(f"source already exists; pass --overwrite to replace it: {output_path}")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    temporary = output_path.with_suffix(output_path.suffix + ".tmp")
    shutil.copyfile(raw_path, temporary)
    temporary.replace(output_path)


def load_provenance(path: Path, character_id: str) -> dict[str, Any]:
    if not path.exists():
        return {
            "schema_version": PROVENANCE_SCHEMA_VERSION,
            "character_id": character_id,
            "kind": "openai_api_generated_art",
            "source": "openai_images_api",
            "batch_ready_allowed": True,
            "generation_policy": {
                "primary_route": NATIVE_ALPHA_ROUTE,
                "legacy_fallback": {
                    "authorized": False,
                    "activation": "--allow-legacy-chroma-fallback",
                    "reason": "",
                },
            },
            "source_images": [],
        }
    payload = json.loads(path.read_text(encoding="utf-8"))
    if int(payload.get("schema_version", 1)) < PROVENANCE_SCHEMA_VERSION:
        raise RuntimeError(f"refusing to mix schema-v1 provenance with the new generator: {path}")
    if payload.get("character_id") != character_id:
        raise RuntimeError(f"source provenance character mismatch: {path}")
    return payload


def update_provenance(
    *,
    path: Path,
    character_id: str,
    brief_path: Path,
    role: str,
    output_path: Path,
    facts: dict[str, Any],
    model: str,
    quality: str,
    size: str,
    route: str,
    background: str,
    request_id: str,
    endpoint: str,
    raw_path: Path,
    fallback_reason: str,
    native_failures: list[str],
) -> None:
    payload = load_provenance(path, character_id)
    fallback = payload["generation_policy"]["legacy_fallback"]
    if route == LEGACY_CHROMA_ROUTE:
        fallback.update(
            {
                "authorized": True,
                "activation": "--allow-legacy-chroma-fallback",
                "reason": fallback_reason,
                "native_failures": native_failures,
            }
        )
        payload["kind"] = "openai_api_generated_art_with_explicit_legacy_fallback"
    payload["generation"] = {
        "requested_model": model,
        "actual_model": model,
        "generation_tool": f"openai-python/{openai.__version__}",
        "endpoint": "OpenAI Images API; see per-source endpoint",
        "quality": quality,
        "size_control": "per-source explicit size",
        "background_control": "per-source explicit background",
        "output_format": "PNG",
        "prompt_revision": {
            "path": str(brief_path.relative_to(ROOT)),
            "sha256": sha256_path(brief_path),
        },
        "reference_inputs": [] if role == "concept_full" else [
            {
                "path": str((CHAR_ROOT / character_id / "concept" / f"{character_id}_concept_full.png").relative_to(ROOT)),
                "role": "accepted_style_anchor",
            }
        ],
    }
    record = {
        "role": role,
        "path": str(output_path.relative_to(ROOT)),
        "sha256": sha256_path(output_path),
        "size": [facts["width"], facts["height"]],
        "source_mode": facts["source_mode"],
        "background": "native_transparent" if route == NATIVE_ALPHA_ROUTE else "reserved_green_chroma_key",
        "generation_route": route,
        "model": model,
        "quality": quality,
        "size_control": size,
        "background_control": background,
        "output_format": facts["format"],
        "endpoint": endpoint,
        "request_id": request_id,
        "raw_response_path": str(raw_path.relative_to(ROOT)),
        "raw_response_sha256": sha256_path(raw_path),
        "accepted_source_is_raw_response": True,
        "alpha": {
            "has_alpha_channel": facts["has_alpha_channel"],
            "min": facts["alpha_min"],
            "max": facts["alpha_max"],
            "transparent_canvas_ratio": facts["transparent_canvas_ratio"],
            "transparent_border_ratio": facts["transparent_border_ratio"],
        },
        "technical_qa_verdict": "pass",
        "qa_verdict": "pending",
        "qa_observation": "Technical background gate passed; semantic object-integrity review is pending.",
    }
    payload["source_images"] = [
        item for item in payload.get("source_images", []) if item.get("role") != role
    ] + [record]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def record_review(path: Path, role: str, verdict: str, observation: str) -> None:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if int(payload.get("schema_version", 1)) < PROVENANCE_SCHEMA_VERSION:
        raise ValueError("schema-v1 provenance is immutable history and cannot use the v2 review command")
    for item in payload.get("source_images", []):
        if item.get("role") == role:
            item["qa_verdict"] = verdict
            item["qa_observation"] = observation
            path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            return
    raise ValueError(f"source provenance role not found: {role}")


def accepted_anchor_issues(provenance: dict[str, Any], anchor: Path) -> list[str]:
    issues: list[str] = []
    if int(provenance.get("schema_version", 1)) < PROVENANCE_SCHEMA_VERSION:
        return ["accepted style anchor requires schema-v2 provenance"]
    record = next(
        (item for item in provenance.get("source_images", []) if item.get("role") == "concept_full"),
        None,
    )
    if not isinstance(record, dict):
        return ["accepted style anchor provenance is missing"]
    if record.get("qa_verdict") != "pass":
        issues.append("style anchor semantic QA verdict must be pass")
    if record.get("technical_qa_verdict") != "pass":
        issues.append("style anchor technical QA verdict must be pass")
    if not anchor.exists():
        issues.append(f"accepted style anchor file is missing: {anchor}")
    elif record.get("sha256") != sha256_path(anchor):
        issues.append("accepted style anchor hash does not match provenance")
    return issues


def resolve_roles(role: list[str], batch: str | None) -> list[str]:
    if role and batch:
        raise ValueError("use --role or --batch, not both")
    if batch:
        return list(BATCH_ROLES[batch])
    if role:
        return list(dict.fromkeys(role))
    raise ValueError("provide at least one --role or one --batch")


def dry_run_plan(character_id: str, roles: list[str], model: str, quality: str) -> list[dict[str, Any]]:
    root = CHAR_ROOT / character_id
    return [
        {
            "character_id": character_id,
            "role": role,
            "model": model,
            "endpoint": "/v1/images/edits" if ROLE_SPECS[role]["reference"] else "/v1/images/generations",
            "background": "transparent",
            "output_format": "png",
            "quality": quality,
            "size": ROLE_SPECS[role]["size"],
            "output": str((root / ROLE_SPECS[role]["path"].format(id=character_id)).relative_to(ROOT)),
        }
        for role in roles
    ]


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate TinySeaWar character sources through GPT Image 2.5 with native-alpha enforcement."
    )
    parser.add_argument("character_id")
    parser.add_argument("--role", action="append", choices=tuple(ROLE_SPECS))
    parser.add_argument("--batch", choices=tuple(BATCH_ROLES))
    parser.add_argument("--model", choices=tuple(sorted(ALLOWED_GPT_IMAGE_MODELS)), default="gpt-image-2.5-sunburst")
    parser.add_argument("--quality", choices=("low", "medium", "high", "xhigh", "max", "auto"), default="high")
    parser.add_argument("--native-attempts", type=int, default=2)
    parser.add_argument("--allow-legacy-chroma-fallback", action="store_true")
    parser.add_argument("--fallback-reason", default="")
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--record-review", choices=tuple(ROLE_SPECS))
    parser.add_argument("--verdict", choices=("pass", "polish", "blocker"))
    parser.add_argument("--observation", default="")
    args = parser.parse_args()

    roster = character_roster.roster_by_id("all")
    if args.character_id not in roster:
        parser.error(f"unknown character id: {args.character_id}")
    root = CHAR_ROOT / args.character_id
    brief_path = generation_brief_path(args.character_id)
    provenance_path = source_provenance_path(args.character_id)

    if args.record_review:
        if not args.verdict or not args.observation.strip():
            parser.error("--record-review requires --verdict and a non-empty --observation")
        record_review(provenance_path, args.record_review, args.verdict, args.observation.strip())
        print(f"reviewed: {args.character_id}:{args.record_review}:{args.verdict}")
        return 0

    try:
        roles = resolve_roles(args.role or [], args.batch)
    except ValueError as exc:
        parser.error(str(exc))
    if args.native_attempts < 1:
        parser.error("--native-attempts must be at least 1")
    if args.allow_legacy_chroma_fallback and not args.fallback_reason.strip():
        parser.error("legacy chroma fallback requires --fallback-reason")
    if not brief_path.exists():
        parser.error(f"generation brief missing: {brief_path}")
    if args.dry_run:
        print(json.dumps(dry_run_plan(args.character_id, roles, args.model, args.quality), indent=2))
        return 0
    if not os.environ.get("OPENAI_API_KEY"):
        parser.error("OPENAI_API_KEY is required for GPT Image 2.5 generation")

    document = brief_path.read_text(encoding="utf-8")
    client = OpenAI()
    anchor = root / "concept" / f"{args.character_id}_concept_full.png"
    provenance = load_provenance(provenance_path, args.character_id)
    for role in roles:
        spec = ROLE_SPECS[role]
        reference = anchor if spec["reference"] else None
        output_path = root / spec["path"].format(id=args.character_id)
        if output_path.exists() and not args.overwrite:
            raise SystemExit(f"source already exists; pass --overwrite to replace it: {output_path}")
        if reference is not None:
            anchor_issues = accepted_anchor_issues(provenance, reference)
            if anchor_issues:
                raise SystemExit(
                    "accepted style anchor is required before derivative generation: "
                    + "; ".join(anchor_issues)
                )
        accepted: tuple[Path, dict[str, Any], str, str, str] | None = None
        native_failures: list[str] = []
        for attempt in range(1, args.native_attempts + 1):
            try:
                payload, request_id, endpoint = request_image(
                    client,
                    prompt=prompt_for_role(document, role),
                    model=args.model,
                    quality=args.quality,
                    size=spec["size"],
                    background="transparent",
                    reference=reference,
                )
            except Exception as exc:
                native_failures.append(
                    f"attempt {attempt}: API request failed: {type(exc).__name__}: {exc}"
                )
                continue
            raw_path = save_raw_candidate(args.character_id, role, payload, request_id, f"native{attempt}")
            facts = image_facts(payload)
            issues = native_alpha_issues(facts)
            if not issues:
                accepted = (raw_path, facts, NATIVE_ALPHA_ROUTE, request_id, endpoint)
                break
            native_failures.append(f"attempt {attempt}: {', '.join(issues)}; raw={raw_path.relative_to(ROOT)}")

        if accepted is None and args.allow_legacy_chroma_fallback:
            try:
                payload, request_id, endpoint = request_image(
                    client,
                    prompt=prompt_for_role(document, role, legacy_chroma=True),
                    model=args.model,
                    quality=args.quality,
                    size=spec["size"],
                    background="opaque",
                    reference=reference,
                )
            except Exception as exc:
                native_failures.append(
                    f"legacy fallback API request failed: {type(exc).__name__}: {exc}"
                )
            else:
                raw_path = save_raw_candidate(args.character_id, role, payload, request_id, "legacy-chroma")
                issues = legacy_chroma_issues(payload)
                if not issues:
                    accepted = (raw_path, image_facts(payload), LEGACY_CHROMA_ROUTE, request_id, endpoint)
                else:
                    native_failures.append(
                        f"legacy fallback: {', '.join(issues)}; raw={raw_path.relative_to(ROOT)}"
                    )
        if accepted is None:
            raise SystemExit(f"native-alpha generation failed for {role}: {' | '.join(native_failures)}")

        raw_path, facts, route, request_id, endpoint = accepted
        write_accepted_source(raw_path, output_path, args.overwrite)
        update_provenance(
            path=provenance_path,
            character_id=args.character_id,
            brief_path=brief_path,
            role=role,
            output_path=output_path,
            facts=facts,
            model=args.model,
            quality=args.quality,
            size=spec["size"],
            route=route,
            background="transparent" if route == NATIVE_ALPHA_ROUTE else "opaque",
            request_id=request_id,
            endpoint=endpoint,
            raw_path=raw_path,
            fallback_reason=args.fallback_reason.strip(),
            native_failures=native_failures,
        )
        provenance = load_provenance(provenance_path, args.character_id)
        print(f"generated: {args.character_id}:{role}:{route}:{output_path.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
