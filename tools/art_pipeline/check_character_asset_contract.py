from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
CHAR_ROOT = ROOT / "assets" / "characters"

SHIP_CLASSES = {
    "enterprise_cv6": "carrier",
    "hai_shih": "submarine",
    "hindenburg": "heavy_cruiser",
    "shimakaze": "destroyer",
    "aurora": "light_cruiser",
    "warspite": "battleship",
}

REQUIRED_PATTERNS = {
    "full_body": "processed/ui/{id}_illust_full_alpha.png",
    "half_body": "processed/ui/{id}_illust_half_alpha.png",
    "skill_cutin": "processed/ui/{id}_illust_skill_cutin_alpha.png",
    "expression_default": "processed/ui/{id}_expr_default.png",
    "expression_serious": "processed/ui/{id}_expr_serious.png",
    "expression_hit": "processed/ui/{id}_expr_hit.png",
    "portrait": "processed/ui/{id}_ui_portrait.png",
    "portrait_small": "processed/ui/{id}_ui_portrait_small.png",
    "chibi_head": "processed/ui/{id}_ui_chibi_head.png",
    "skill_icon": "processed/ui/{id}_ui_skill_*.png",
    "class_icon": "processed/ui/{id}_ui_class_{ship_class}.png",
    "battle_body": "processed/battle/{id}_battle_body_r.png",
    "rig_base": "processed/battle/{id}_battle_rig_base.png",
    "main_weapon": "processed/battle/{id}_battle_*.png",
    "anim_idle": "processed/anim/{id}_anim_idle_keyframe.png",
    "anim_move": "processed/anim/{id}_anim_move_keyframe.png",
    "anim_attack": "processed/anim/{id}_anim_attack_keyframe.png",
    "anim_hit": "processed/anim/{id}_anim_hit_keyframe.png",
    "anim_firepower": "processed/anim/{id}_anim_firepower_keyframe.png",
    "vfx": "processed/vfx/{id}_vfx_*.png",
    "bind_points": "processed/config/{id}_meta_bind_points.json",
    "anim_config": "processed/config/{id}_anim_config.json",
    "vfx_config": "processed/config/{id}_vfx_config.json",
    "manifest": "processed/config/{id}_postprocess_manifest.json",
}


def matches(character_id: str, pattern: str) -> list[Path]:
    formatted = pattern.format(id=character_id, ship_class=SHIP_CLASSES[character_id])
    return sorted((CHAR_ROOT / character_id).glob(formatted))


def validate_file(path: Path) -> str | None:
    try:
        if path.suffix == ".png":
            with Image.open(path) as image:
                if image.mode != "RGBA":
                    return f"PNG mode is {image.mode}, expected RGBA"
                if image.getchannel("A").getbbox() is None:
                    return "PNG alpha is empty"
        elif path.suffix == ".json":
            json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:  # Keep the audit readable when one file is corrupt.
        return str(exc)
    return None


def audit(character_id: str) -> dict[str, object]:
    missing: list[str] = []
    invalid: list[dict[str, str]] = []
    found: dict[str, list[str]] = {}
    for role, pattern in REQUIRED_PATTERNS.items():
        paths = matches(character_id, pattern)
        if role == "main_weapon":
            paths = [
                path for path in paths
                if any(token in path.name for token in ("turret", "torpedo", "aircraft"))
            ]
        if not paths:
            missing.append(role)
            continue
        found[role] = [str(path.relative_to(ROOT)) for path in paths]
        for path in paths:
            error = validate_file(path)
            if error:
                invalid.append({"role": role, "path": str(path.relative_to(ROOT)), "error": error})
    return {
        "character_id": character_id,
        "ship_class": SHIP_CLASSES[character_id],
        "status": "complete" if not missing and not invalid else "incomplete",
        "missing_roles": missing,
        "invalid_files": invalid,
        "found_roles": found,
    }


def write_report(results: list[dict[str, object]]) -> Path:
    out = CHAR_ROOT / "qa" / "character_asset_contract_audit.md"
    out.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "# Character Asset Contract Audit",
        "",
        "Contract source: `docs/art_design.md` section 6.",
        "",
        "| Character | Status | Missing required roles |",
        "| --- | --- | --- |",
    ]
    for result in results:
        missing = ", ".join(result["missing_roles"]) or "-"
        lines.append(f'| {result["character_id"]} | {result["status"]} | {missing} |')
    lines.extend([
        "",
        "A character may pass edge and file-format QA while remaining incomplete. Missing required roles are blockers.",
        "",
    ])
    out.write_text("\n".join(lines), encoding="utf-8")
    return out


def main() -> int:
    character_ids = sys.argv[1:] or list(SHIP_CLASSES)
    unknown = [character_id for character_id in character_ids if character_id not in SHIP_CLASSES]
    if unknown:
        print(f"Unknown character ids: {', '.join(unknown)}", file=sys.stderr)
        return 2
    results = [audit(character_id) for character_id in character_ids]
    report = write_report(results)
    print(json.dumps(results, ensure_ascii=False, indent=2))
    print(f"report: {report.relative_to(ROOT)}")
    return 1 if any(result["status"] != "complete" for result in results) else 0


if __name__ == "__main__":
    raise SystemExit(main())
