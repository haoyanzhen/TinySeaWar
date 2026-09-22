from __future__ import annotations

import argparse
import hashlib
import itertools
import json
import re
import sys
from pathlib import Path

from PIL import Image
import character_roster
from generation_contract import strict_source_policy_issues


ROOT = Path(__file__).resolve().parents[2]
CHAR_ROOT = ROOT / "assets" / "characters"

ROSTER = character_roster.roster_by_id("all")
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
MAX_OPAQUE_WHITE_CANVAS_RATIO = 0.50
MAX_CHROMA_KEY_CANVAS_RATIO = 0.05
MAX_REGISTERED_ALPHA_IOU_BY_STATE = {
    "idle": 0.92,
    "move": 0.86,
    "attack": 0.78,
    "hit": 0.82,
    "firepower": 0.86,
}


def load_visual_definitions() -> list[dict[str, object]]:
    definitions: list[dict[str, object]] = []
    for path in sorted((ROOT / "data" / "visuals").glob("*.json")):
        document = json.loads(path.read_text(encoding="utf-8"))
        for item in document.get("definitions", []):
            if isinstance(item, dict):
                definitions.append(item)
    return definitions


VISUAL_DEFINITIONS = load_visual_definitions()
WEAPON_VISUALS = {
    (str(item.get("character_id", "")), str(item.get("weapon_group_id", ""))): item
    for item in VISUAL_DEFINITIONS
    if str(item.get("id", "")).startswith("weapon_visual.")
}
VFX_PROFILE_KEYS = {
    key
    for item in VISUAL_DEFINITIONS
    if str(item.get("id", "")).startswith("vfx.profile.")
    for key in [str(item.get("id", "")), *(str(alias) for alias in item.get("aliases", []))]
    if key
}


def matches(character_id: str, pattern: str) -> list[Path]:
    formatted = pattern.format(id=character_id, ship_class=SHIP_CLASSES[character_id])
    return sorted((CHAR_ROOT / character_id).glob(formatted))


def configured_vfx_paths(character_id: str) -> list[Path]:
    config_path = CHAR_ROOT / character_id / "processed" / "config" / f"{character_id}_vfx_config.json"
    if not config_path.exists():
        return []
    config = json.loads(config_path.read_text(encoding="utf-8"))
    return sorted(
        ROOT / item.get("file", "")
        for item in config.get("roles", {}).values()
        if item.get("file") and (ROOT / item["file"]).exists()
    )


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
                sample_image = image.copy()
                sample_image.thumbnail((256, 256), getattr(Image, "Resampling", Image).BOX)
                pixels = list(sample_image.getdata())
                opaque_white = sum(
                    1
                    for pixel in pixels
                    if pixel[3] >= 240 and min(pixel[:3]) >= 245
                )
                white_ratio = opaque_white / len(pixels)
                if white_ratio >= MAX_OPAQUE_WHITE_CANVAS_RATIO:
                    return f"PNG has opaque near-white background ({white_ratio:.1%} of canvas)"
                chroma_key = sum(
                    1
                    for pixel in pixels
                    if pixel[3] >= 128
                    and pixel[1] >= 150
                    and pixel[1] > pixel[0] + 70
                    and pixel[1] > pixel[2] + 70
                )
                chroma_ratio = chroma_key / len(pixels)
                if chroma_ratio >= MAX_CHROMA_KEY_CANVAS_RATIO:
                    return f"PNG has reserved green-screen residue ({chroma_ratio:.1%} of canvas)"
                sample = sample_image.getchannel("A")
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


def registered_alpha_mask(path: Path, size: int = 320, subject_size: int = 256) -> Image.Image:
    """Return a centered subject mask so pure translation/scale does not count as animation."""
    with Image.open(path) as image:
        alpha = image.convert("RGBA").getchannel("A").point(lambda value: 255 if value > 24 else 0)
    bbox = alpha.getbbox()
    if bbox is None:
        return Image.new("L", (size, size), 0)
    subject = alpha.crop(bbox)
    resample = getattr(getattr(Image, "Resampling", Image), "LANCZOS")
    subject.thumbnail((subject_size, subject_size), resample)
    canvas = Image.new("L", (size, size), 0)
    canvas.paste(subject, ((size - subject.width) // 2, (size - subject.height) // 2))
    return canvas.point(lambda value: 255 if value > 32 else 0)


def alpha_mask_iou(left: Image.Image, right: Image.Image) -> float:
    left_pixels = list(left.getdata())
    right_pixels = list(right.getdata())
    intersection = sum(1 for a, b in zip(left_pixels, right_pixels) if a and b)
    union = sum(1 for a, b in zip(left_pixels, right_pixels) if a or b)
    return intersection / union if union else 1.0


def validate_animation_pose_variation(character_id: str, states: dict[str, object]) -> list[str]:
    """Catch four-frame sheets that are only the same sprite shifted/tinted or given a flash."""
    issues: list[str] = []
    if ROSTER[character_id].phase != "phase2":
        return issues
    for state, item in states.items():
        if not isinstance(item, dict):
            continue
        frames = item.get("frames")
        if not isinstance(frames, list) or len(frames) != 4:
            continue
        frame_paths = [ROOT / str(frame) for frame in frames]
        if any(not path.exists() for path in frame_paths):
            continue
        masks = [registered_alpha_mask(path) for path in frame_paths]
        ious = [
            alpha_mask_iou(left, right)
            for left, right in itertools.combinations(masks, 2)
        ]
        average_iou = sum(ious) / len(ious)
        threshold = MAX_REGISTERED_ALPHA_IOU_BY_STATE.get(state, 0.86)
        if average_iou >= threshold:
            issues.append(
                f"animation pose variation too low: {state} "
                f"(registered alpha IoU {average_iou:.3f} >= {threshold:.2f}; "
                "translations, tints, and detached flashes do not satisfy the action contract)"
            )
    return issues


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_source_provenance(source_provenance: object) -> list[str]:
    issues: list[str] = []
    if not isinstance(source_provenance, dict):
        return ["manifest schema v2 source_provenance missing"]
    generation = source_provenance.get("generation")
    if not isinstance(generation, dict):
        issues.append("source provenance generation metadata missing")
    else:
        required_generation = {
            "requested_model", "actual_model", "generation_tool", "endpoint", "quality",
            "size_control", "background_control", "output_format", "prompt_revision", "reference_inputs",
        }
        missing = sorted(key for key in required_generation if generation.get(key) in (None, "", []))
        if missing:
            issues.append(f"source provenance generation fields missing: {', '.join(missing)}")
        prompt_revision = generation.get("prompt_revision")
        if isinstance(prompt_revision, dict):
            prompt_path = ROOT / str(prompt_revision.get("path", ""))
            prompt_hash = str(prompt_revision.get("sha256", ""))
            if not prompt_path.exists():
                issues.append(f"source provenance prompt revision missing: {prompt_path}")
            elif not prompt_hash or sha256(prompt_path) != prompt_hash:
                issues.append("source provenance prompt revision hash mismatch")
    source_images = source_provenance.get("source_images")
    if not isinstance(source_images, list) or not source_images:
        issues.append("source provenance image inventory missing")
        return issues
    for item in source_images:
        if not isinstance(item, dict):
            issues.append("source provenance image entry is not an object")
            continue
        role = str(item.get("role", "?"))
        source_path = ROOT / str(item.get("path", ""))
        if not source_path.exists():
            issues.append(f"source provenance file missing: {role}:{source_path}")
            continue
        expected_hash = str(item.get("sha256", ""))
        if not expected_hash or sha256(source_path) != expected_hash:
            issues.append(f"source provenance hash mismatch: {role}")
        if item.get("qa_verdict") not in {"pass", "polish", "blocker"}:
            issues.append(f"source provenance QA verdict invalid: {role}")
        elif item.get("qa_verdict") == "blocker":
            issues.append(f"source provenance semantic QA is blocking: {role}")
        if not str(item.get("qa_observation", "")):
            issues.append(f"source provenance QA observation missing: {role}")
    issues.extend(strict_source_policy_issues(source_provenance, ROOT))
    return issues


def validate_manifest_v2(manifest_data: dict[str, object]) -> list[str]:
    issues = validate_source_provenance(manifest_data.get("source_provenance"))
    outputs = manifest_data.get("outputs")
    if not isinstance(outputs, list) or not outputs:
        return issues + ["manifest schema v2 outputs missing"]
    for output in outputs:
        if not isinstance(output, dict):
            issues.append("manifest output entry is not an object")
            continue
        role = str(output.get("role", "?"))
        for field in (
            "mode", "alpha_bbox", "alpha_pixel_count", "edge_margins", "output_padding",
            "alpha_centroid", "centroid_offset_normalized", "component_tags",
        ):
            if output.get(field) in (None, "", []):
                issues.append(f"manifest output metadata missing: {role}:{field}")
        if role.startswith("source_alpha:"):
            if output.get("source_edge_margins") in (None, ""):
                issues.append(f"manifest source edge margins missing: {role}")
            continue
        if role.endswith(":idle_master_override"):
            continue
        crop = output.get("crop")
        if not isinstance(crop, dict):
            issues.append(f"manifest crop metadata missing: {role}")
            continue
        for field in (
            "original_crop_hint", "final_crop_box", "auto_crop_method",
            "selected_component_samples", "output_edge_margins",
        ):
            if crop.get(field) in (None, "", []):
                issues.append(f"manifest crop metadata missing: {role}:{field}")
        if role.startswith("vfx:"):
            allowed_methods = {"full_cell_alpha_bbox", "connected_components_intersecting_initial_box"}
            if crop.get("auto_crop_method") not in allowed_methods or crop.get("cleanup_tags"):
                issues.append(f"VFX crop must preserve all components: {role}")
            if crop.get("source_alpha_pixel_count") != output.get("alpha_pixel_count"):
                issues.append(f"VFX crop changed alpha component area: {role}")
    return issues


def validate_weapon_binding_rules(
    character_id: str,
    plan: dict[str, object],
    bind_data: dict[str, object],
    vfx_data: dict[str, object],
) -> list[str]:
    issues: list[str] = []
    rules = plan.get("weapon_binding_rules", {})
    if not isinstance(rules, dict):
        return ["postprocess plan weapon_binding_rules must be an object"]
    assets = bind_data.get("assets", {}) if isinstance(bind_data, dict) else {}
    vfx_roles = vfx_data.get("roles", {}) if isinstance(vfx_data, dict) else {}
    for weapon_group_id, expected in rules.items():
        if not isinstance(expected, dict):
            issues.append(f"weapon binding rule invalid: {weapon_group_id}")
            continue
        visual = WEAPON_VISUALS.get((character_id, str(weapon_group_id)))
        if visual is None:
            issues.append(f"weapon visual missing for binding rule: {weapon_group_id}")
            continue
        for field in ("launch_bind", "muzzle_vfx_role", "impact_vfx_role", "launch_profile", "impact_profile"):
            if field in expected and visual.get(field) != expected[field]:
                issues.append(f"weapon visual rule mismatch: {weapon_group_id}:{field}")
        launch_bind = str(expected.get("launch_bind", ""))
        asset_role = str(expected.get("asset_role", ""))
        expected_asset = f"{character_id}_{asset_role}.png" if asset_role else ""
        if expected_asset and launch_bind not in assets.get(expected_asset, {}):
            issues.append(f"weapon launch bind missing on expected asset: {weapon_group_id}:{expected_asset}:{launch_bind}")
        for role_field in ("muzzle_vfx_role", "impact_vfx_role"):
            role_name = str(expected.get(role_field, ""))
            if role_name and role_name not in vfx_roles:
                issues.append(f"weapon VFX role missing: {weapon_group_id}:{role_name}")
        for profile_field in ("launch_profile", "impact_profile"):
            profile_name = str(expected.get(profile_field, ""))
            if profile_name and profile_name not in VFX_PROFILE_KEYS:
                issues.append(f"weapon VFX profile missing: {weapon_group_id}:{profile_name}")
    return issues


def validate_character_data(character_id: str) -> list[str]:
    root = CHAR_ROOT / character_id / "processed"
    issues: list[str] = []
    plan_path = CHAR_ROOT / character_id / "postprocess_plan.json"
    plan: dict[str, object] = {}
    if ROSTER[character_id].phase == "phase2":
        if not plan_path.exists():
            issues.append("phase2 postprocess plan missing")
        else:
            plan = json.loads(plan_path.read_text(encoding="utf-8"))
            if plan.get("character_id") != character_id:
                issues.append("postprocess plan character_id mismatch")
            if plan.get("ship_class") != SHIP_CLASSES[character_id]:
                issues.append("postprocess plan ship_class mismatch")
            expected_level_match = re.search(r"\d+", ROSTER[character_id].level)
            expected_level = int(expected_level_match.group()) if expected_level_match else None
            if expected_level is not None and plan.get("level") != expected_level:
                issues.append(f"postprocess plan level mismatch: expected {expected_level}")
            battle_roles = plan.get("battle_grid_roles", [])
            vfx_roles = plan.get("vfx_roles", [])
            if not isinstance(battle_roles, list) or len(battle_roles) != 8:
                issues.append("postprocess plan must define eight battle grid roles")
            if not isinstance(vfx_roles, list) or len(vfx_roles) != 8:
                issues.append("postprocess plan must define eight VFX roles")
            if len(set(battle_roles)) != len(battle_roles):
                issues.append("postprocess plan battle roles must be unique")
            if len(set(vfx_roles)) != len(vfx_roles):
                issues.append("postprocess plan VFX roles must be unique")
            if int(plan.get("manifest_schema_version", 1)) >= 2:
                mount_instances = plan.get("mount_instances", {})
                object_inventory = plan.get("object_inventory", {})
                if not isinstance(mount_instances, dict) or not isinstance(object_inventory, dict):
                    issues.append("postprocess plan object inventory missing")
                else:
                    for mount_name, count in mount_instances.items():
                        inventory = object_inventory.get(mount_name, {})
                        if not isinstance(inventory, dict) or inventory.get("instances") != count:
                            issues.append(f"postprocess plan object inventory mismatch: {mount_name}")
            binding_positions = plan.get("binding_positions", {})
            if binding_positions and not isinstance(binding_positions, dict):
                issues.append("postprocess plan binding_positions must be an object")
            elif isinstance(binding_positions, dict):
                for role, positions in binding_positions.items():
                    if not isinstance(positions, dict):
                        issues.append(f"postprocess plan binding positions invalid: {role}")
                        continue
                    for point_name, point in positions.items():
                        if not isinstance(point, dict) or not all(isinstance(point.get(axis), (int, float)) and 0.0 <= float(point[axis]) <= 1.0 for axis in ("x", "y")):
                            issues.append(f"postprocess plan normalized bind invalid: {role}:{point_name}")

    manifest_path = root / "config" / f"{character_id}_postprocess_manifest.json"
    if manifest_path.exists():
        manifest_data = json.loads(manifest_path.read_text(encoding="utf-8"))
        source_provenance = manifest_data.get("source_provenance")
        if isinstance(source_provenance, dict) and source_provenance.get("batch_ready_allowed") is False:
            source = source_provenance.get("source", "unknown")
            kind = source_provenance.get("kind", "placeholder")
            issues.append(f"non-production source provenance: {kind} from {source}")
        if int(manifest_data.get("schema_version", 1)) >= 2:
            issues.extend(validate_manifest_v2(manifest_data))

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
        if plan:
            configured_assets = bind_data.get("assets", {})
            for role, point_names in plan.get("bindings", {}).items():
                asset_name = f"{character_id}_{role}.png"
                configured_points = configured_assets.get(asset_name, {})
                for point_name in point_names:
                    if point_name not in configured_points:
                        issues.append(f"planned bind point missing: {asset_name}:{point_name}")

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
        if isinstance(states, dict):
            issues.extend(validate_animation_pose_variation(character_id, states))

    vfx_path = root / "config" / f"{character_id}_vfx_config.json"
    vfx_data: dict[str, object] = {}
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
            if plan and not item.get("public_semantic"):
                issues.append(f"VFX public semantic missing: {role}")
        if plan:
            for role in plan.get("vfx_roles", []):
                if role not in roles:
                    issues.append(f"planned VFX role missing: {role}")

    if plan:
        for role in plan.get("battle_grid_roles", []):
            path = root / "battle" / f"{character_id}_{role}.png"
            if not path.exists():
                issues.append(f"planned battle role missing: {role}")
        skill_role = str(plan.get("skill_role", ""))
        if not skill_role or not (root / "ui" / f"{character_id}_ui_skill_{skill_role}.png").exists():
            issues.append(f"planned skill icon missing: {skill_role or '?'}")
        if bind_path.exists() and vfx_path.exists():
            issues.extend(validate_weapon_binding_rules(character_id, plan, bind_data, vfx_data))

    return issues


def audit(character_id: str) -> dict[str, object]:
    missing: list[str] = []
    invalid: list[dict[str, str]] = []
    found: dict[str, list[str]] = {}
    validated_paths: set[Path] = set()
    for role, pattern in REQUIRED_PATTERNS.items():
        paths = matches(character_id, pattern)
        if role == "vfx" and not paths:
            paths = configured_vfx_paths(character_id)
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


def write_report(results: list[dict[str, object]], phase: str = "phase1") -> Path:
    result_ids = [str(result["character_id"]) for result in results]
    phase_ids = set(character_roster.roster_by_id(phase))
    if set(result_ids) == phase_ids:
        suffix = "" if phase == "phase1" else f"_{phase}"
        filename = f"character_asset_contract_audit{suffix}.md"
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
    parser = argparse.ArgumentParser(description="Audit TinySeaWar character asset contracts.")
    parser.add_argument("character_ids", nargs="*")
    parser.add_argument("--phase", choices=("phase1", "phase2", "all"), default="phase1")
    args = parser.parse_args()
    character_ids = args.character_ids or list(character_roster.roster_by_id(args.phase))
    unknown = [character_id for character_id in character_ids if character_id not in SHIP_CLASSES]
    if unknown:
        print(f"Unknown character ids: {', '.join(unknown)}", file=sys.stderr)
        return 2
    results = [audit(character_id) for character_id in character_ids]
    report = write_report(results, args.phase)
    print(json.dumps(results, ensure_ascii=False, indent=2))
    print(f"report: {report.relative_to(ROOT)}")
    return 1 if any(result["status"] != "complete" for result in results) else 0


if __name__ == "__main__":
    raise SystemExit(main())
