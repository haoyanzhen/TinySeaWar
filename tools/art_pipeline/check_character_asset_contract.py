from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image
import character_roster


ROOT = Path(__file__).resolve().parents[2]
CHAR_ROOT = ROOT / "assets" / "characters"

ROSTER = character_roster.roster_by_id()
SHIP_CLASSES = {character_id: entry.ship_class for character_id, entry in ROSTER.items()}

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

REQUIRED_ANIMATION_STATES = {"idle", "move", "attack", "hit", "firepower"}


def matches(character_id: str, pattern: str) -> list[Path]:
    formatted = pattern.format(id=character_id, ship_class=SHIP_CLASSES[character_id])
    return sorted((CHAR_ROOT / character_id).glob(formatted))


def validate_file(path: Path) -> str | None:
    try:
        if path.suffix == ".png":
            with Image.open(path) as image:
                if image.mode != "RGBA":
                    return f"PNG mode is {image.mode}, expected RGBA"
                alpha = image.getchannel("A")
                bbox = alpha.getbbox()
                if bbox is None:
                    return "PNG alpha is empty"
                left, top, right, bottom = bbox
                if min(left, top, image.width - right, image.height - bottom) == 0:
                    return "PNG alpha touches canvas edge"
                sample = alpha.copy()
                sample.thumbnail((256, 256), getattr(Image, "Resampling", Image).BOX)
                width, height = sample.size
                values = list(sample.getdata())
                weight = sum(values)
                if weight:
                    centroid_x = sum((index % width) * value for index, value in enumerate(values)) / weight
                    centroid_y = sum((index // width) * value for index, value in enumerate(values)) / weight
                    offset_x = abs(centroid_x - (width - 1) / 2) / width
                    offset_y = abs(centroid_y - (height - 1) / 2) / height
                    if max(offset_x, offset_y) > 0.10:
                        return f"PNG visual centroid is not centered ({offset_x:.3f}, {offset_y:.3f})"
        elif path.suffix == ".json":
            json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:  # Keep the audit readable when one file is corrupt.
        return str(exc)
    return None


def nearby_alpha(image: Image.Image, x: int, y: int, radius: int = 24) -> bool:
    alpha = image.getchannel("A")
    left = max(0, x - radius)
    top = max(0, y - radius)
    right = min(alpha.width, x + radius + 1)
    bottom = min(alpha.height, y + radius + 1)
    return alpha.crop((left, top, right, bottom)).getbbox() is not None


def validate_character_data(character_id: str) -> list[str]:
    root = CHAR_ROOT / character_id / "processed"
    issues: list[str] = []

    bind_path = root / "config" / f"{character_id}_meta_bind_points.json"
    if bind_path.exists():
        bind_data = json.loads(bind_path.read_text(encoding="utf-8"))
        for asset_name, points in bind_data.get("assets", {}).items():
            asset_path = root / "battle" / asset_name
            if not asset_path.exists():
                issues.append(f"bind asset missing: {asset_name}")
                continue
            with Image.open(asset_path) as image:
                rgba = image.convert("RGBA")
                for point_name, point in points.items():
                    x = point.get("x")
                    y = point.get("y")
                    if not isinstance(x, int) or not isinstance(y, int):
                        issues.append(f"invalid bind point: {asset_name}:{point_name}")
                    elif not (0 <= x < rgba.width and 0 <= y < rgba.height):
                        issues.append(f"bind point out of bounds: {asset_name}:{point_name}")
                    elif not nearby_alpha(rgba, x, y):
                        issues.append(f"bind point far from artwork: {asset_name}:{point_name}")

    anim_path = root / "config" / f"{character_id}_anim_config.json"
    if anim_path.exists():
        anim_data = json.loads(anim_path.read_text(encoding="utf-8"))
        states = anim_data.get("states", {})
        missing_states = sorted(REQUIRED_ANIMATION_STATES - set(states))
        if missing_states:
            issues.append(f"animation states missing: {', '.join(missing_states)}")
        for state, item in states.items():
            frames = item.get("frames")
            if frames is not None:
                if len(frames) != 4:
                    issues.append(f"animation state must contain four frames: {state}")
                frame_sizes: set[tuple[int, int]] = set()
                for frame in frames:
                    if not (ROOT / frame).exists():
                        issues.append(f"animation frame missing: {state}:{frame}")
                    else:
                        with Image.open(ROOT / frame) as image:
                            frame_sizes.add(image.size)
                if len(frame_sizes) > 1:
                    issues.append(f"animation frame canvas mismatch: {state}")
                if not isinstance(item.get("fps"), int) or item["fps"] <= 0:
                    issues.append(f"animation fps invalid: {state}")
                if not isinstance(item.get("loop"), bool):
                    issues.append(f"animation loop flag invalid: {state}")
            else:
                file_value = item.get("file", "")
                if not (ROOT / file_value).exists():
                    issues.append(f"animation file missing: {state}:{file_value}")

    vfx_path = root / "config" / f"{character_id}_vfx_config.json"
    if vfx_path.exists():
        vfx_data = json.loads(vfx_path.read_text(encoding="utf-8"))
        if vfx_data.get("ship_class") != SHIP_CLASSES[character_id]:
            issues.append("vfx ship_class does not match character contract")
        roles = vfx_data.get("roles", {})
        if not roles:
            issues.append("vfx roles are empty")
        for role, item in roles.items():
            file_value = item.get("file", "")
            if not (ROOT / file_value).exists():
                issues.append(f"vfx file missing: {role}:{file_value}")

    return issues


def audit(character_id: str) -> dict[str, object]:
    missing: list[str] = []
    invalid: list[dict[str, str]] = []
    found: dict[str, list[str]] = {}
    validated_paths: set[Path] = set()
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
            validated_paths.add(path)
            error = validate_file(path)
            if error:
                invalid.append({"role": role, "path": str(path.relative_to(ROOT)), "error": error})
    processed_root = CHAR_ROOT / character_id / "processed"
    for folder in ("ui", "battle", "anim", "vfx"):
        for path in sorted((processed_root / folder).glob("*.png")):
            if path in validated_paths:
                continue
            error = validate_file(path)
            if error:
                invalid.append({"role": "runtime_png", "path": str(path.relative_to(ROOT)), "error": error})
    data_issues = validate_character_data(character_id)
    return {
        "character_id": character_id,
        "ship_class": SHIP_CLASSES[character_id],
        "status": "complete" if not missing and not invalid and not data_issues else "incomplete",
        "missing_roles": missing,
        "invalid_files": invalid,
        "data_issues": data_issues,
        "found_roles": found,
    }


def write_report(results: list[dict[str, object]]) -> Path:
    result_ids = [str(result["character_id"]) for result in results]
    if set(result_ids) == set(SHIP_CLASSES):
        filename = "character_asset_contract_audit.md"
    else:
        filename = "character_asset_contract_audit_" + "_".join(result_ids) + ".md"
    out = CHAR_ROOT / "qa" / filename
    out.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "# Character Asset Contract Audit",
        "",
        "Contract source: `docs/40_art_direction_design.md` section 6.",
        "Roster source: `docs/41_character_art_design.md`.",
        "",
        "| Character | Prototype | Ship class | Status | Missing required roles | Data issues |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    for result in results:
        entry = ROSTER[str(result["character_id"])]
        missing = ", ".join(result["missing_roles"]) or "-"
        data_issues = "; ".join(result["data_issues"]) or "-"
        lines.append(
            f'| {result["character_id"]} | {entry.prototype} | {entry.ship_class_cn} | '
            f'{result["status"]} | {missing} | {data_issues} |'
        )
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
