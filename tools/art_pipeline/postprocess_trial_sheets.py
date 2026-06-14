from __future__ import annotations

import base64
from html import escape
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from collections import deque

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
CHAR_ROOT = ROOT / "assets" / "characters"


@dataclass(frozen=True)
class CropSpec:
    source: str
    out_dir: str
    name: str
    box: tuple[int, int, int, int]
    tags: tuple[str, ...] = ()


SOURCE_EDGE_SAFE_MARGIN = 16
SOURCE_SEARCH_MARGIN = 160
SOURCE_COMPONENT_ALPHA_THRESHOLD = 8
OUTPUT_BASE_PADDING = 24
OUTPUT_MAX_RECENTER_PADDING = 160


def is_sheet_background_pixel(r: int, g: int, b: int) -> bool:
    hi = max(r, g, b)
    lo = min(r, g, b)
    sat = hi - lo
    # Match plain white and pale checkerboard sheet backgrounds. This function is
    # intentionally conservative; only border-connected pixels are removed.
    return hi >= 218 and sat <= 28


def rgba_with_alpha_from_light_bg(img: Image.Image) -> Image.Image:
    rgba = img.convert("RGBA")
    pixels = rgba.load()
    w, h = rgba.size
    seen: set[tuple[int, int]] = set()
    q: deque[tuple[int, int]] = deque()

    for x in range(w):
        q.append((x, 0))
        q.append((x, h - 1))
    for y in range(h):
        q.append((0, y))
        q.append((w - 1, y))

    while q:
        x, y = q.popleft()
        if (x, y) in seen:
            continue
        seen.add((x, y))
        r, g, b, a = pixels[x, y]
        if not is_sheet_background_pixel(r, g, b):
            continue
        pixels[x, y] = (r, g, b, 0)
        if x > 0:
            q.append((x - 1, y))
        if x < w - 1:
            q.append((x + 1, y))
        if y > 0:
            q.append((x, y - 1))
        if y < h - 1:
            q.append((x, y + 1))
    return rgba


def trim_alpha(img: Image.Image, pad: int = 8) -> Image.Image:
    alpha = img.getchannel("A")
    box = alpha.getbbox()
    if not box:
        return img
    l, t, r, b = box
    l = max(0, l - pad)
    t = max(0, t - pad)
    r = min(img.width, r + pad)
    b = min(img.height, b + pad)
    return img.crop((l, t, r, b))


def alpha_weighted_centroid(img: Image.Image) -> tuple[float, float] | None:
    alpha = img.getchannel("A")
    pixels = alpha.load()
    total = 0
    weighted_x = 0
    weighted_y = 0
    for y in range(alpha.height):
        for x in range(alpha.width):
            weight = pixels[x, y]
            if weight:
                total += weight
                weighted_x += x * weight
                weighted_y += y * weight
    if total == 0:
        return None
    return (weighted_x / total, weighted_y / total)


def balanced_margin(length: int, centroid: float, pad: int, max_extra: int) -> tuple[int, int]:
    left = round(length + pad - 2 * centroid)
    right = pad
    if left < pad:
        left = pad
        right = round(2 * centroid + left - length)
    left = max(pad, min(pad + max_extra, left))
    right = max(pad, min(pad + max_extra, right))
    return left, right


def add_balanced_padding(
    img: Image.Image,
    pad: int = OUTPUT_BASE_PADDING,
    max_extra: int = OUTPUT_MAX_RECENTER_PADDING,
) -> tuple[Image.Image, dict[str, Any]]:
    alpha = img.getchannel("A")
    bbox = alpha.getbbox()
    if not bbox:
        return img, {"content_bbox": None, "centroid": None}

    tight = img.crop(bbox)
    centroid = alpha_weighted_centroid(tight)
    if centroid is None:
        return tight, {"content_bbox": list(bbox), "centroid": None}

    left, right = balanced_margin(tight.width, centroid[0], pad, max_extra)
    top, bottom = balanced_margin(tight.height, centroid[1], pad, max_extra)
    out = Image.new("RGBA", (tight.width + left + right, tight.height + top + bottom), (0, 0, 0, 0))
    out.alpha_composite(tight, (left, top))

    out_centroid = alpha_weighted_centroid(out)
    offset = None
    if out_centroid is not None:
        offset = {
            "x": round(out_centroid[0] - out.width / 2, 2),
            "y": round(out_centroid[1] - out.height / 2, 2),
        }
    return out, {
        "content_bbox": list(bbox),
        "centroid_before_padding": [round(centroid[0], 2), round(centroid[1], 2)],
        "padding": {"left": left, "top": top, "right": right, "bottom": bottom},
        "centroid_offset_after_padding": offset,
    }


def edge_margins_from_alpha(img: Image.Image) -> dict[str, int] | None:
    bbox = img.getchannel("A").getbbox()
    if not bbox:
        return None
    l, t, r, b = bbox
    return {
        "left": l,
        "top": t,
        "right": img.width - r,
        "bottom": img.height - b,
    }


def remove_small_alpha_islands(img: Image.Image, relative_area: float = 0.005) -> Image.Image:
    alpha = img.getchannel("A")
    pixels = alpha.load()
    seen: set[tuple[int, int]] = set()
    components: list[list[tuple[int, int]]] = []
    for y in range(alpha.height):
        for x in range(alpha.width):
            if (x, y) in seen or pixels[x, y] == 0:
                continue
            q: deque[tuple[int, int]] = deque([(x, y)])
            seen.add((x, y))
            component: list[tuple[int, int]] = []
            while q:
                cx, cy = q.popleft()
                component.append((cx, cy))
                for nx, ny in ((cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)):
                    if nx < 0 or nx >= alpha.width or ny < 0 or ny >= alpha.height:
                        continue
                    if (nx, ny) in seen or pixels[nx, ny] == 0:
                        continue
                    seen.add((nx, ny))
                    q.append((nx, ny))
            components.append(component)
    if not components:
        return img
    minimum = max(64, round(max(len(component) for component in components) * relative_area))
    cleaned = img.copy()
    cleaned_alpha = cleaned.getchannel("A")
    cleaned_pixels = cleaned_alpha.load()
    for component in components:
        if len(component) < minimum:
            for x, y in component:
                cleaned_pixels[x, y] = 0
    cleaned.putalpha(cleaned_alpha)
    return cleaned


def keep_largest_alpha_component(img: Image.Image) -> Image.Image:
    alpha = img.getchannel("A")
    pixels = alpha.load()
    seen: set[tuple[int, int]] = set()
    components: list[list[tuple[int, int]]] = []
    for y in range(alpha.height):
        for x in range(alpha.width):
            if (x, y) in seen or pixels[x, y] == 0:
                continue
            q: deque[tuple[int, int]] = deque([(x, y)])
            seen.add((x, y))
            component: list[tuple[int, int]] = []
            while q:
                cx, cy = q.popleft()
                component.append((cx, cy))
                for nx, ny in ((cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)):
                    if nx < 0 or nx >= alpha.width or ny < 0 or ny >= alpha.height:
                        continue
                    if (nx, ny) in seen or pixels[nx, ny] == 0:
                        continue
                    seen.add((nx, ny))
                    q.append((nx, ny))
            components.append(component)
    if not components:
        return img
    largest = max(components, key=len)
    keep = set(largest)
    cleaned = img.copy()
    cleaned_alpha = cleaned.getchannel("A")
    cleaned_pixels = cleaned_alpha.load()
    for y in range(alpha.height):
        for x in range(alpha.width):
            if pixels[x, y] and (x, y) not in keep:
                cleaned_pixels[x, y] = 0
    cleaned.putalpha(cleaned_alpha)
    return cleaned


def intersects(a: tuple[int, int, int, int], b: tuple[int, int, int, int]) -> bool:
    return a[0] < b[2] and a[2] > b[0] and a[1] < b[3] and a[3] > b[1]


def clipped_box(
    box: tuple[int, int, int, int],
    width: int,
    height: int,
) -> tuple[int, int, int, int]:
    l, t, r, b = box
    return (max(0, l), max(0, t), min(width, r), min(height, b))


def connected_components_in_roi(
    src_alpha: Image.Image,
    box: tuple[int, int, int, int],
    search_margin: int = SOURCE_SEARCH_MARGIN,
) -> list[dict[str, Any]]:
    alpha = src_alpha.getchannel("A")
    roi = clipped_box(
        (box[0] - search_margin, box[1] - search_margin, box[2] + search_margin, box[3] + search_margin),
        src_alpha.width,
        src_alpha.height,
    )
    rl, rt, rr, rb = roi
    pixels = alpha.load()
    seen: set[tuple[int, int]] = set()
    components: list[dict[str, Any]] = []

    for y in range(rt, rb):
        for x in range(rl, rr):
            if (x, y) in seen or pixels[x, y] <= SOURCE_COMPONENT_ALPHA_THRESHOLD:
                continue

            q: deque[tuple[int, int]] = deque([(x, y)])
            seen.add((x, y))
            count = 0
            overlap = 0
            l = r = x
            t = b = y

            while q:
                cx, cy = q.popleft()
                count += 1
                if box[0] <= cx < box[2] and box[1] <= cy < box[3]:
                    overlap += 1
                l = min(l, cx)
                t = min(t, cy)
                r = max(r, cx)
                b = max(b, cy)

                for nx, ny in ((cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)):
                    if nx < rl or nx >= rr or ny < rt or ny >= rb:
                        continue
                    if (nx, ny) in seen or pixels[nx, ny] <= SOURCE_COMPONENT_ALPHA_THRESHOLD:
                        continue
                    seen.add((nx, ny))
                    q.append((nx, ny))

            components.append({
                "bbox": [l, t, r + 1, b + 1],
                "pixel_count": count,
                "overlap_pixels": overlap,
            })

    return components


def determine_source_box(
    src_alpha: Image.Image,
    box: tuple[int, int, int, int],
    safe_margin: int = SOURCE_EDGE_SAFE_MARGIN,
) -> tuple[tuple[int, int, int, int], dict[str, Any]]:
    original = box
    components = connected_components_in_roi(src_alpha, box)
    selected = [
        component
        for component in components
        if component["overlap_pixels"] > 0
    ]

    if selected:
        l = min(component["bbox"][0] for component in selected)
        t = min(component["bbox"][1] for component in selected)
        r = max(component["bbox"][2] for component in selected)
        b = max(component["bbox"][3] for component in selected)
        current = clipped_box(
            (l - safe_margin, t - safe_margin, r + safe_margin, b + safe_margin),
            src_alpha.width,
            src_alpha.height,
        )
    else:
        current = box

    final_crop = src_alpha.crop(current)
    final_margins = edge_margins_from_alpha(final_crop)
    warnings = []
    if final_margins:
        warnings = [edge for edge, value in final_margins.items() if value < safe_margin]
    expanded = {
        "left": original[0] - current[0],
        "top": original[1] - current[1],
        "right": current[2] - original[2],
        "bottom": current[3] - original[3],
    }
    info = {
        "original_box": list(original),
        "final_box": list(current),
        "expanded": expanded,
        "auto_crop_method": "connected_components_intersecting_initial_box",
        "component_count": len(components),
        "selected_component_count": len(selected),
        "selected_component_samples": selected[:20],
        "source_edge_safe_margin": safe_margin,
        "final_edge_margins": final_margins,
        "edge_warnings": warnings,
    }
    return current, info


def save_crop(
    src_alpha: Image.Image,
    box: tuple[int, int, int, int],
    out: Path,
    tags: tuple[str, ...] = (),
) -> dict[str, Any]:
    final_box, source_crop_qa = determine_source_box(src_alpha, box)
    crop = src_alpha.crop(final_box)
    if "keep_largest_component" in tags:
        crop = keep_largest_alpha_component(crop)
    if "remove_small_islands" in tags:
        crop = remove_small_alpha_islands(crop)
    crop = trim_alpha(crop, pad=0)
    crop, output_layout = add_balanced_padding(crop)
    out.parent.mkdir(parents=True, exist_ok=True)
    crop.save(out)
    return {
        "file": rel(out),
        "size": list(crop.size),
        "mode": crop.mode,
        "source_box": list(final_box),
        "source_crop_qa": source_crop_qa,
        "output_layout": output_layout,
    }


def rel(path: Path) -> str:
    return str(path.relative_to(ROOT))


def normalize_animation_sequence_canvases(character_id: str, states: dict[str, Any]) -> None:
    anim_dir = CHAR_ROOT / character_id / "processed" / "anim"
    for state in states:
        paths = [anim_dir / f"{character_id}_anim_{state}_frame_{index:02d}.png" for index in range(1, 5)]
        images = [Image.open(path).convert("RGBA") for path in paths]
        width = max(image.width for image in images)
        height = max(image.height for image in images)
        for path, image in zip(paths, images):
            canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
            canvas.alpha_composite(image, ((width - image.width) // 2, (height - image.height) // 2))
            canvas.save(path)


def point(x: int, y: int, note: str) -> dict[str, Any]:
    return {"x": x, "y": y, "note": note}


SPECS: dict[str, list[CropSpec]] = {
    "enterprise_cv6": [
        CropSpec("concept/enterprise_cv6_concept_full.png", "processed/ui", "enterprise_cv6_illust_full_alpha.png", (0, 0, 1023, 1537), ("illustration", "full_body")),
        CropSpec("ui/enterprise_cv6_illust_half.png", "processed/ui", "enterprise_cv6_illust_half_alpha.png", (0, 0, 1402, 1122), ("illustration",)),
        CropSpec("ui/enterprise_cv6_illust_skill_cutin.png", "processed/ui", "enterprise_cv6_illust_skill_cutin_alpha.png", (0, 0, 1774, 887), ("cutin",)),
        CropSpec("ui/enterprise_cv6_ui_sheet.png", "processed/ui", "enterprise_cv6_ui_portrait.png", (16, 16, 368, 496), ("ui", "portrait")),
        CropSpec("ui/enterprise_cv6_ui_sheet.png", "processed/ui", "enterprise_cv6_ui_portrait_small.png", (400, 16, 752, 496), ("ui", "portrait_small")),
        CropSpec("ui/enterprise_cv6_ui_sheet.png", "processed/ui", "enterprise_cv6_ui_chibi_head.png", (784, 16, 1136, 496), ("ui", "chibi")),
        CropSpec("ui/enterprise_cv6_ui_sheet.png", "processed/ui", "enterprise_cv6_expr_default.png", (1168, 16, 1520, 496), ("ui", "expression")),
        CropSpec("ui/enterprise_cv6_ui_sheet.png", "processed/ui", "enterprise_cv6_expr_serious.png", (16, 528, 368, 1008), ("ui", "expression", "serious")),
        CropSpec("ui/enterprise_cv6_ui_sheet.png", "processed/ui", "enterprise_cv6_expr_hit.png", (400, 528, 752, 1008), ("ui", "expression", "hit")),
        CropSpec("ui/enterprise_cv6_ui_sheet.png", "processed/ui", "enterprise_cv6_ui_skill_airstrike.png", (784, 528, 1136, 1008), ("ui", "skill")),
        CropSpec("ui/enterprise_cv6_ui_sheet.png", "processed/ui", "enterprise_cv6_ui_class_carrier.png", (1168, 528, 1520, 1008), ("ui", "class_icon")),
        CropSpec("battle/enterprise_cv6_battle_asset_sheet.png", "processed/battle", "enterprise_cv6_battle_body_r.png", (16, 16, 300, 400), ("battle", "body")),
        CropSpec("battle/enterprise_cv6_battle_asset_sheet.png", "processed/battle", "enterprise_cv6_battle_rig_base.png", (300, 16, 840, 420), ("battle", "rig")),
        CropSpec("battle/enterprise_cv6_battle_asset_sheet.png", "processed/battle", "enterprise_cv6_battle_aircraft_01.png", (850, 40, 1190, 390), ("battle", "aircraft")),
        CropSpec("battle/enterprise_cv6_battle_asset_sheet.png", "processed/battle", "enterprise_cv6_battle_aircraft_02.png", (1210, 40, 1520, 390), ("battle", "aircraft")),
        CropSpec("battle/enterprise_cv6_battle_asset_sheet.png", "processed/battle", "enterprise_cv6_battle_aircraft_03.png", (16, 420, 370, 700), ("battle", "aircraft")),
        CropSpec("battle/enterprise_cv6_battle_asset_sheet.png", "processed/battle", "enterprise_cv6_battle_aircraft_04.png", (390, 420, 750, 700), ("battle", "aircraft")),
        CropSpec("battle/enterprise_cv6_battle_asset_sheet.png", "processed/battle", "enterprise_cv6_battle_launch_marker.png", (780, 420, 1160, 700), ("battle", "launch_marker")),
        CropSpec("battle/enterprise_cv6_battle_asset_sheet.png", "processed/battle", "enterprise_cv6_battle_air_control_node.png", (1190, 420, 1520, 700), ("battle", "air_control")),
        CropSpec("battle/enterprise_cv6_battle_asset_sheet.png", "processed/vfx", "enterprise_cv6_vfx_wake_fast.png", (16, 720, 370, 1008), ("vfx", "wake")),
        CropSpec("battle/enterprise_cv6_battle_asset_sheet.png", "processed/vfx", "enterprise_cv6_vfx_wake_turn.png", (390, 720, 750, 1008), ("vfx", "wake")),
        CropSpec("battle/enterprise_cv6_battle_asset_sheet.png", "processed/vfx", "enterprise_cv6_vfx_launch_trail.png", (780, 720, 1160, 1008), ("vfx", "aircraft_path")),
        CropSpec("battle/enterprise_cv6_battle_asset_sheet.png", "processed/vfx", "enterprise_cv6_vfx_deck_hit_sparks.png", (1190, 720, 1520, 1008), ("vfx", "hit")),
        CropSpec("vfx/enterprise_cv6_vfx_reference_sheet.png", "processed/vfx", "enterprise_cv6_vfx_aircraft_beam_single.png", (16, 16, 368, 325), ("vfx", "aircraft_path")),
        CropSpec("vfx/enterprise_cv6_vfx_reference_sheet.png", "processed/vfx", "enterprise_cv6_vfx_aircraft_path_arc.png", (400, 16, 752, 325), ("vfx", "aircraft_path")),
        CropSpec("vfx/enterprise_cv6_vfx_reference_sheet.png", "processed/vfx", "enterprise_cv6_vfx_aircraft_formation_trails.png", (784, 16, 1136, 325), ("vfx", "aircraft_path")),
        CropSpec("vfx/enterprise_cv6_vfx_reference_sheet.png", "processed/vfx", "enterprise_cv6_vfx_aircraft_path_arrows.png", (1168, 16, 1520, 325), ("vfx", "aircraft_path")),
        CropSpec("vfx/enterprise_cv6_vfx_reference_sheet.png", "processed/vfx", "enterprise_cv6_vfx_airstrike_area.png", (16, 349, 368, 667), ("vfx", "area")),
        CropSpec("vfx/enterprise_cv6_vfx_reference_sheet.png", "processed/vfx", "enterprise_cv6_vfx_deck_launch_lane.png", (400, 349, 752, 667), ("vfx", "deck_lane")),
        CropSpec("vfx/enterprise_cv6_vfx_reference_sheet.png", "processed/vfx", "enterprise_cv6_vfx_deck_recovery_lane.png", (784, 349, 1136, 667), ("vfx", "deck_lane")),
        CropSpec("vfx/enterprise_cv6_vfx_reference_sheet.png", "processed/vfx", "enterprise_cv6_vfx_aa_interception_ring.png", (1168, 349, 1520, 667), ("vfx", "area")),
        CropSpec("vfx/enterprise_cv6_vfx_reference_sheet.png", "processed/vfx", "enterprise_cv6_vfx_water_splash.png", (16, 691, 368, 1008), ("vfx", "splash")),
        CropSpec("vfx/enterprise_cv6_vfx_reference_sheet.png", "processed/vfx", "enterprise_cv6_vfx_hit_sparks.png", (400, 691, 752, 1008), ("vfx", "hit")),
        CropSpec("vfx/enterprise_cv6_vfx_reference_sheet.png", "processed/vfx", "enterprise_cv6_vfx_wake_reference.png", (784, 691, 1136, 1008), ("vfx", "wake")),
        CropSpec("vfx/enterprise_cv6_vfx_reference_sheet.png", "processed/vfx", "enterprise_cv6_vfx_command_aura.png", (1168, 691, 1520, 1008), ("vfx", "area")),
        CropSpec("battle/enterprise_cv6_anim_idle_4f_sheet.png", "processed/anim", "enterprise_cv6_anim_idle_keyframe.png", (80, 60, 547, 567), ("anim", "idle")),
        CropSpec("battle/enterprise_cv6_anim_move_4f_sheet.png", "processed/anim", "enterprise_cv6_anim_move_keyframe.png", (80, 60, 547, 567), ("anim", "move")),
        CropSpec("battle/enterprise_cv6_anim_attack_4f_sheet.png", "processed/anim", "enterprise_cv6_anim_attack_keyframe.png", (80, 60, 547, 567), ("anim", "attack")),
        CropSpec("battle/enterprise_cv6_anim_hit_4f_sheet.png", "processed/anim", "enterprise_cv6_anim_hit_keyframe.png", (80, 60, 547, 567), ("anim", "hit")),
        CropSpec("battle/enterprise_cv6_anim_firepower_4f_sheet.png", "processed/anim", "enterprise_cv6_anim_firepower_keyframe.png", (80, 60, 547, 567), ("anim", "firepower")),
        *[
            CropSpec(
                f"battle/enterprise_cv6_anim_{state}_4f_sheet.png",
                "processed/anim",
                f"enterprise_cv6_anim_{state}_frame_{index:02d}.png",
                box,
                ("anim", state, f"frame_{index:02d}"),
            )
            for state in ("idle", "move", "attack", "hit", "firepower")
            for index, box in enumerate(
                ((80, 60, 547, 567), (707, 60, 1174, 567), (80, 687, 547, 1194), (707, 687, 1174, 1194)),
                1,
            )
        ],
    ],
    "hai_shih": [
        CropSpec("concept/hai_shih_concept_full.png", "processed/ui", "hai_shih_illust_full_alpha.png", (0, 0, 1024, 1536), ("illustration", "full_body")),
        CropSpec("ui/hai_shih_illust_half.png", "processed/ui", "hai_shih_illust_half_alpha.png", (0, 0, 1254, 1254), ("illustration",)),
        CropSpec("ui/hai_shih_illust_skill_cutin.png", "processed/ui", "hai_shih_illust_skill_cutin_alpha.png", (0, 0, 1536, 1024), ("cutin",)),
        CropSpec("ui/hai_shih_ui_sheet.png", "processed/ui", "hai_shih_ui_portrait.png", (45, 45, 268, 582), ("ui", "portrait")),
        CropSpec("ui/hai_shih_ui_sheet.png", "processed/ui", "hai_shih_ui_portrait_small.png", (358, 45, 581, 582), ("ui", "portrait_small")),
        CropSpec("ui/hai_shih_ui_sheet.png", "processed/ui", "hai_shih_ui_chibi_head.png", (672, 45, 895, 582), ("ui", "chibi")),
        CropSpec("ui/hai_shih_ui_sheet.png", "processed/ui", "hai_shih_expr_default.png", (985, 45, 1208, 582), ("ui", "expression")),
        CropSpec("ui/hai_shih_ui_sheet.png", "processed/ui", "hai_shih_expr_serious.png", (45, 672, 268, 1209), ("ui", "expression", "serious")),
        CropSpec("ui/hai_shih_ui_sheet.png", "processed/ui", "hai_shih_expr_hit.png", (358, 672, 581, 1209), ("ui", "expression", "hit")),
        CropSpec("ui/hai_shih_ui_sheet.png", "processed/ui", "hai_shih_ui_skill_torpedo.png", (672, 672, 895, 1209), ("ui", "skill")),
        CropSpec("ui/hai_shih_ui_sheet.png", "processed/ui", "hai_shih_ui_class_submarine.png", (985, 672, 1208, 1209), ("ui", "class_icon")),
        CropSpec("battle/hai_shih_battle_asset_sheet.png", "processed/battle", "hai_shih_battle_body_r.png", (45, 45, 268, 373), ("battle", "body")),
        CropSpec("battle/hai_shih_battle_asset_sheet.png", "processed/battle", "hai_shih_battle_rig_base.png", (358, 45, 581, 373), ("battle", "rig")),
        CropSpec("battle/hai_shih_battle_asset_sheet.png", "processed/battle", "hai_shih_battle_torpedo_tube_01.png", (760, 90, 900, 330), ("battle", "torpedo")),
        CropSpec("battle/hai_shih_battle_asset_sheet.png", "processed/battle", "hai_shih_battle_periscope_node.png", (985, 45, 1208, 373), ("battle", "periscope")),
        CropSpec("battle/hai_shih_battle_asset_sheet.png", "processed/battle", "hai_shih_battle_sonar_node.png", (45, 463, 268, 791), ("battle", "sonar")),
        CropSpec("battle/hai_shih_battle_asset_sheet.png", "processed/battle", "hai_shih_battle_guide_light_node.png", (358, 463, 581, 791), ("battle", "guide_light")),
        CropSpec("battle/hai_shih_battle_asset_sheet.png", "processed/vfx", "hai_shih_vfx_wake_short.png", (672, 463, 895, 791), ("vfx", "wake")),
        CropSpec("battle/hai_shih_battle_asset_sheet.png", "processed/vfx", "hai_shih_vfx_wake_turn.png", (985, 463, 1208, 791), ("vfx", "wake")),
        CropSpec("battle/hai_shih_battle_asset_sheet.png", "processed/vfx", "hai_shih_vfx_underwater_shadow.png", (45, 881, 268, 1209), ("vfx", "shadow")),
        CropSpec("battle/hai_shih_battle_asset_sheet.png", "processed/vfx", "hai_shih_vfx_bubbles_small.png", (358, 881, 581, 1209), ("vfx", "bubble")),
        CropSpec("battle/hai_shih_battle_asset_sheet.png", "processed/vfx", "hai_shih_vfx_bubbles_medium.png", (672, 881, 895, 1209), ("vfx", "bubble")),
        CropSpec("battle/hai_shih_battle_asset_sheet.png", "processed/vfx", "hai_shih_vfx_submerged_launch_trail.png", (985, 881, 1208, 1209), ("vfx", "torpedo")),
        CropSpec("vfx/hai_shih_vfx_reference_sheet.png", "processed/vfx", "hai_shih_vfx_torpedo_trail.png", (45, 45, 268, 373), ("vfx", "torpedo")),
        CropSpec("vfx/hai_shih_vfx_reference_sheet.png", "processed/vfx", "hai_shih_vfx_torpedo_launch_flash.png", (358, 45, 581, 373), ("vfx", "torpedo")),
        CropSpec("vfx/hai_shih_vfx_reference_sheet.png", "processed/vfx", "hai_shih_vfx_sonar_pulse.png", (672, 45, 895, 373), ("vfx", "sonar")),
        CropSpec("vfx/hai_shih_vfx_reference_sheet.png", "processed/vfx", "hai_shih_vfx_periscope_glint.png", (985, 45, 1208, 373), ("vfx", "periscope")),
        CropSpec("vfx/hai_shih_vfx_reference_sheet.png", "processed/vfx", "hai_shih_vfx_stealth_shimmer.png", (45, 463, 268, 791), ("vfx", "stealth")),
        CropSpec("vfx/hai_shih_vfx_reference_sheet.png", "processed/vfx", "hai_shih_vfx_shadow_fade.png", (358, 463, 581, 791), ("vfx", "shadow")),
        CropSpec("vfx/hai_shih_vfx_reference_sheet.png", "processed/vfx", "hai_shih_vfx_bubble_stream_small.png", (672, 463, 895, 791), ("vfx", "bubble")),
        CropSpec("vfx/hai_shih_vfx_reference_sheet.png", "processed/vfx", "hai_shih_vfx_bubble_stream_large.png", (985, 463, 1208, 791), ("vfx", "bubble")),
        CropSpec("vfx/hai_shih_vfx_reference_sheet.png", "processed/vfx", "hai_shih_vfx_water_ripple.png", (45, 881, 268, 1209), ("vfx", "ripple")),
        CropSpec("vfx/hai_shih_vfx_reference_sheet.png", "processed/vfx", "hai_shih_vfx_water_splash.png", (358, 881, 581, 1209), ("vfx", "splash")),
        CropSpec("vfx/hai_shih_vfx_reference_sheet.png", "processed/vfx", "hai_shih_vfx_ambush_target.png", (672, 881, 895, 1209), ("vfx", "area")),
        CropSpec("vfx/hai_shih_vfx_reference_sheet.png", "processed/vfx", "hai_shih_vfx_command_aura.png", (985, 881, 1208, 1209), ("vfx", "area")),
        *[
            CropSpec(f"battle/hai_shih_anim_{state}_4f_sheet.png", "processed/anim", f"hai_shih_anim_{state}_keyframe.png", (80, 60, 547, 567), ("anim", state))
            for state in ("idle", "move", "attack", "hit", "firepower")
        ],
        *[
            CropSpec(
                f"battle/hai_shih_anim_{state}_4f_sheet.png",
                "processed/anim",
                f"hai_shih_anim_{state}_frame_{index:02d}.png",
                box,
                ("anim", state, f"frame_{index:02d}"),
            )
            for state in ("idle", "move", "attack", "hit", "firepower")
            for index, box in enumerate(((80, 60, 547, 567), (707, 60, 1174, 567), (80, 687, 547, 1194), (707, 687, 1174, 1194)), 1)
        ],
    ],
    "hindenburg": [
        CropSpec("concept/hindenburg_concept_full.png", "processed/ui", "hindenburg_illust_full_alpha.png", (0, 0, 1024, 1536), ("illustration", "full_body")),
        CropSpec("ui/hindenburg_illust_half.png", "processed/ui", "hindenburg_illust_half_alpha.png", (0, 0, 1402, 1122), ("illustration",)),
        CropSpec("ui/hindenburg_illust_skill_cutin.png", "processed/ui", "hindenburg_illust_skill_cutin_alpha.png", (0, 0, 1774, 887), ("cutin",)),
        CropSpec("ui/hindenburg_ui_sheet.png", "processed/ui", "hindenburg_ui_portrait.png", (35, 50, 545, 510), ("ui", "portrait")),
        CropSpec("ui/hindenburg_ui_sheet.png", "processed/ui", "hindenburg_ui_portrait_small.png", (575, 100, 820, 420), ("ui", "portrait_small")),
        CropSpec("ui/hindenburg_ui_sheet.png", "processed/ui", "hindenburg_ui_chibi_head.png", (920, 190, 1090, 420), ("ui", "chibi", "remove_small_islands")),
        CropSpec("ui/hindenburg_ui_sheet.png", "processed/ui", "hindenburg_expr_default.png", (35, 545, 385, 940), ("ui", "expression", "default")),
        CropSpec("ui/hindenburg_ui_sheet.png", "processed/ui", "hindenburg_expr_serious.png", (395, 545, 735, 940), ("ui", "expression", "serious")),
        CropSpec("ui/hindenburg_ui_sheet.png", "processed/ui", "hindenburg_expr_hit.png", (745, 545, 1100, 940), ("ui", "expression", "hit")),
        CropSpec("ui/hindenburg_ui_sheet.png", "processed/ui", "hindenburg_ui_skill_fire_control.png", (1140, 100, 1490, 420), ("ui", "skill")),
        CropSpec("ui/hindenburg_ui_sheet.png", "processed/ui", "hindenburg_ui_class_heavy_cruiser.png", (1185, 525, 1515, 920), ("ui", "class_icon")),
        CropSpec("battle/hindenburg_battle_asset_sheet.png", "processed/battle", "hindenburg_battle_body_r.png", (45, 45, 570, 445), ("battle", "body")),
        CropSpec("battle/hindenburg_battle_asset_sheet.png", "processed/battle", "hindenburg_battle_rig_base.png", (610, 35, 1120, 450), ("battle", "rig")),
        CropSpec("battle/hindenburg_battle_asset_sheet.png", "processed/battle", "hindenburg_battle_turret_main_01.png", (1195, 70, 1505, 250), ("battle", "turret")),
        CropSpec("battle/hindenburg_battle_asset_sheet.png", "processed/battle", "hindenburg_battle_turret_main_02.png", (1220, 285, 1485, 410), ("battle", "turret")),
        CropSpec("battle/hindenburg_battle_asset_sheet.png", "processed/battle", "hindenburg_battle_fire_control_node.png", (1230, 455, 1415, 620), ("battle", "fire_control")),
        CropSpec("battle/hindenburg_battle_asset_sheet.png", "processed/vfx", "hindenburg_vfx_reticle_01.png", (45, 540, 260, 730), ("vfx", "reticle")),
        CropSpec("battle/hindenburg_battle_asset_sheet.png", "processed/vfx", "hindenburg_vfx_reticle_02.png", (300, 540, 515, 730), ("vfx", "reticle")),
        CropSpec("battle/hindenburg_battle_asset_sheet.png", "processed/vfx", "hindenburg_vfx_reticle_03.png", (555, 540, 760, 730), ("vfx", "reticle")),
        CropSpec("battle/hindenburg_battle_asset_sheet.png", "processed/vfx", "hindenburg_vfx_muzzle_flash.png", (780, 505, 1200, 705), ("vfx", "muzzle_flash")),
        CropSpec("battle/hindenburg_battle_asset_sheet.png", "processed/vfx", "hindenburg_vfx_wake_wide.png", (65, 775, 610, 965), ("vfx", "wake")),
        CropSpec("battle/hindenburg_battle_asset_sheet.png", "processed/vfx", "hindenburg_vfx_water_impact.png", (620, 760, 940, 980), ("vfx", "impact")),
        CropSpec("vfx/hindenburg_vfx_reference_sheet.png", "processed/vfx", "hindenburg_vfx_heavy_muzzle_cone.png", (45, 45, 555, 220), ("vfx", "muzzle_flash")),
        CropSpec("vfx/hindenburg_vfx_reference_sheet.png", "processed/vfx", "hindenburg_vfx_smoke_burst.png", (565, 45, 780, 235), ("vfx", "smoke")),
        CropSpec("vfx/hindenburg_vfx_reference_sheet.png", "processed/vfx", "hindenburg_vfx_scan_beam.png", (800, 275, 1490, 485), ("vfx", "scan")),
        CropSpec("vfx/hindenburg_vfx_reference_sheet.png", "processed/vfx", "hindenburg_vfx_suppression_ring.png", (635, 520, 1405, 750), ("vfx", "area")),
        CropSpec("vfx/hindenburg_vfx_reference_sheet.png", "processed/vfx", "hindenburg_vfx_shell_trail.png", (55, 760, 690, 845), ("vfx", "shell")),
        CropSpec("vfx/hindenburg_vfx_reference_sheet.png", "processed/vfx", "hindenburg_vfx_wake.png", (790, 765, 1400, 870), ("vfx", "wake")),
        CropSpec("battle/hindenburg_anim_keyframes_sheet.png", "processed/anim", "hindenburg_anim_idle_keyframe.png", (70, 50, 540, 410), ("anim", "idle")),
        CropSpec("battle/hindenburg_anim_keyframes_sheet.png", "processed/anim", "hindenburg_anim_move_keyframe.png", (640, 55, 1120, 420), ("anim", "move")),
        CropSpec("battle/hindenburg_anim_keyframes_sheet.png", "processed/anim", "hindenburg_anim_attack_keyframe.png", (1180, 50, 1720, 420), ("anim", "attack")),
        CropSpec("battle/hindenburg_anim_keyframes_sheet.png", "processed/anim", "hindenburg_anim_hit_keyframe.png", (260, 465, 800, 855), ("anim", "hit")),
        CropSpec("battle/hindenburg_anim_keyframes_sheet.png", "processed/anim", "hindenburg_anim_firepower_keyframe.png", (930, 450, 1675, 865), ("anim", "firepower")),
        CropSpec("concept/hindenburg_concept_full.png", "processed/ui", "hindenburg_illust_full_alpha.png", (0, 0, 1024, 1536), ("illustration", "full_body")),
        CropSpec("ui/hindenburg_illust_half.png", "processed/ui", "hindenburg_illust_half_alpha.png", (0, 0, 1254, 1254), ("illustration",)),
        CropSpec("ui/hindenburg_illust_skill_cutin.png", "processed/ui", "hindenburg_illust_skill_cutin_alpha.png", (0, 0, 1717, 916), ("cutin",)),
        *[
            CropSpec("ui/hindenburg_ui_sheet.png", "processed/ui", name, box, tags)
            for name, box, tags in (
                ("hindenburg_ui_portrait.png", (45, 45, 268, 582), ("ui", "portrait")),
                ("hindenburg_ui_portrait_small.png", (358, 45, 581, 582), ("ui", "portrait_small")),
                ("hindenburg_ui_chibi_head.png", (672, 45, 895, 582), ("ui", "chibi")),
                ("hindenburg_expr_default.png", (985, 45, 1208, 582), ("ui", "expression")),
                ("hindenburg_expr_serious.png", (45, 672, 268, 1209), ("ui", "expression", "serious")),
                ("hindenburg_expr_hit.png", (358, 672, 581, 1209), ("ui", "expression", "hit")),
                ("hindenburg_ui_skill_fire_control.png", (672, 672, 895, 1209), ("ui", "skill")),
                ("hindenburg_ui_class_heavy_cruiser.png", (985, 672, 1208, 1209), ("ui", "class_icon")),
            )
        ],
        *[
            CropSpec("battle/hindenburg_battle_asset_sheet.png", out_dir, name, box, tags)
            for out_dir, name, box, tags in (
                ("processed/battle", "hindenburg_battle_body_r.png", (45, 45, 268, 373), ("battle", "body")),
                ("processed/battle", "hindenburg_battle_rig_base.png", (358, 45, 581, 373), ("battle", "rig")),
                ("processed/battle", "hindenburg_battle_turret_main_01.png", (672, 45, 895, 373), ("battle", "turret")),
                ("processed/battle", "hindenburg_battle_turret_main_02.png", (985, 45, 1208, 373), ("battle", "turret")),
                ("processed/battle", "hindenburg_battle_fire_control_node.png", (45, 463, 268, 791), ("battle", "fire_control")),
                ("processed/battle", "hindenburg_battle_armor_plate_01.png", (358, 463, 581, 791), ("battle", "armor")),
                ("processed/battle", "hindenburg_battle_lock_emitter_node.png", (672, 463, 895, 791), ("battle", "fire_control")),
                ("processed/vfx", "hindenburg_vfx_wake_narrow.png", (985, 463, 1208, 791), ("vfx", "wake")),
                ("processed/vfx", "hindenburg_vfx_wake_wide.png", (45, 881, 268, 1209), ("vfx", "wake")),
                ("processed/vfx", "hindenburg_vfx_heavy_muzzle_cone.png", (358, 881, 581, 1209), ("vfx", "muzzle")),
                ("processed/vfx", "hindenburg_vfx_shell_trail.png", (672, 881, 895, 1209), ("vfx", "shell")),
                ("processed/vfx", "hindenburg_vfx_armor_sparks.png", (985, 881, 1208, 1209), ("vfx", "hit")),
            )
        ],
        *[
            CropSpec("vfx/hindenburg_vfx_reference_sheet.png", "processed/vfx", name, box, tags)
            for name, box, tags in (
                ("hindenburg_vfx_lock_line.png", (45, 45, 268, 373), ("vfx", "lock")),
                ("hindenburg_vfx_precision_reticle.png", (358, 45, 581, 373), ("vfx", "reticle")),
                ("hindenburg_vfx_scan_beam.png", (672, 45, 895, 373), ("vfx", "scan")),
                ("hindenburg_vfx_range_arc.png", (985, 45, 1208, 373), ("vfx", "range")),
                ("hindenburg_vfx_muzzle_flash.png", (45, 463, 268, 791), ("vfx", "muzzle")),
                ("hindenburg_vfx_shell_trails.png", (358, 463, 581, 791), ("vfx", "shell")),
                ("hindenburg_vfx_suppression_ring.png", (672, 463, 895, 791), ("vfx", "area")),
                ("hindenburg_vfx_armor_deflection.png", (985, 463, 1208, 791), ("vfx", "hit")),
                ("hindenburg_vfx_wake.png", (45, 881, 268, 1209), ("vfx", "wake")),
                ("hindenburg_vfx_turn_wake.png", (358, 881, 581, 1209), ("vfx", "wake")),
                ("hindenburg_vfx_water_impact.png", (672, 881, 895, 1209), ("vfx", "impact")),
                ("hindenburg_vfx_smoke_burst.png", (985, 881, 1208, 1209), ("vfx", "smoke")),
            )
        ],
        *[
            CropSpec(f"battle/hindenburg_anim_{state}_4f_sheet.png", "processed/anim", f"hindenburg_anim_{state}_keyframe.png", (80, 60, 547, 567), ("anim", state))
            for state in ("idle", "move", "attack", "hit", "firepower")
        ],
        *[
            CropSpec(f"battle/hindenburg_anim_{state}_4f_sheet.png", "processed/anim", f"hindenburg_anim_{state}_frame_{index:02d}.png", box, ("anim", state, f"frame_{index:02d}"))
            for state in ("idle", "move", "attack", "hit", "firepower")
            for index, box in enumerate(((80, 60, 547, 567), (707, 60, 1174, 567), (80, 687, 547, 1194), (707, 687, 1174, 1194)), 1)
        ],
    ],
    "shimakaze": [
        CropSpec("concept/shimakaze_concept_full.png", "processed/ui", "shimakaze_illust_full_alpha.png", (0, 0, 1024, 1536), ("illustration", "full_body")),
        CropSpec("ui/shimakaze_illust_half.png", "processed/ui", "shimakaze_illust_half_alpha.png", (0, 0, 1536, 1024), ("illustration",)),
        CropSpec("ui/shimakaze_illust_skill_cutin.png", "processed/ui", "shimakaze_illust_skill_cutin_alpha.png", (0, 0, 1536, 1024), ("cutin",)),
        CropSpec("ui/shimakaze_ui_sheet.png", "processed/ui", "shimakaze_ui_portrait.png", (55, 175, 670, 745), ("ui", "portrait")),
        CropSpec("ui/shimakaze_ui_sheet.png", "processed/ui", "shimakaze_ui_portrait_small.png", (745, 210, 1135, 675), ("ui", "portrait_small")),
        CropSpec("ui/shimakaze_ui_sheet.png", "processed/ui", "shimakaze_ui_skill_torpedo_rush.png", (1235, 205, 1635, 655), ("ui", "skill")),
        CropSpec("battle/shimakaze_battle_asset_sheet.png", "processed/battle", "shimakaze_battle_body_r.png", (70, 55, 430, 420), ("battle", "body")),
        CropSpec("battle/shimakaze_battle_asset_sheet.png", "processed/battle", "shimakaze_battle_rig_base.png", (490, 85, 1080, 390), ("battle", "rig")),
        CropSpec("battle/shimakaze_battle_asset_sheet.png", "processed/battle", "shimakaze_battle_torpedo_tube_01.png", (1160, 130, 1400, 260), ("battle", "torpedo")),
        CropSpec("battle/shimakaze_battle_asset_sheet.png", "processed/battle", "shimakaze_battle_torpedo_tube_02.png", (1400, 135, 1640, 260), ("battle", "torpedo")),
        CropSpec("battle/shimakaze_battle_asset_sheet.png", "processed/battle", "shimakaze_battle_turret_main_01.png", (430, 440, 570, 560), ("battle", "turret")),
        CropSpec("battle/shimakaze_battle_asset_sheet.png", "processed/battle", "shimakaze_battle_thruster_01.png", (70, 715, 195, 830), ("battle", "thruster")),
        CropSpec("battle/shimakaze_battle_asset_sheet.png", "processed/vfx", "shimakaze_vfx_torpedo_warning_01.png", (460, 585, 880, 665), ("vfx", "torpedo_warning")),
        CropSpec("battle/shimakaze_battle_asset_sheet.png", "processed/vfx", "shimakaze_vfx_torpedo_trail_01.png", (1095, 485, 1535, 560), ("vfx", "torpedo")),
        CropSpec("battle/shimakaze_battle_asset_sheet.png", "processed/vfx", "shimakaze_vfx_torpedo_trail_02.png", (970, 665, 1490, 750), ("vfx", "torpedo")),
        CropSpec("battle/shimakaze_battle_asset_sheet.png", "processed/vfx", "shimakaze_vfx_wake_fast.png", (435, 760, 780, 850), ("vfx", "wake")),
        CropSpec("battle/shimakaze_battle_asset_sheet.png", "processed/vfx", "shimakaze_vfx_wake_long.png", (770, 735, 1330, 850), ("vfx", "wake")),
        CropSpec("battle/shimakaze_battle_asset_sheet.png", "processed/vfx", "shimakaze_vfx_water_impact.png", (1375, 740, 1660, 870), ("vfx", "impact")),
        CropSpec("vfx/shimakaze_vfx_reference_sheet.png", "processed/vfx", "shimakaze_vfx_warning_line_long.png", (45, 65, 1360, 145), ("vfx", "torpedo_warning")),
        CropSpec("vfx/shimakaze_vfx_reference_sheet.png", "processed/vfx", "shimakaze_vfx_torpedo_trail_long.png", (60, 305, 670, 395), ("vfx", "torpedo")),
        CropSpec("vfx/shimakaze_vfx_reference_sheet.png", "processed/vfx", "shimakaze_vfx_wake_blade.png", (700, 220, 1390, 390), ("vfx", "wake")),
        CropSpec("vfx/shimakaze_vfx_reference_sheet.png", "processed/vfx", "shimakaze_vfx_wake_surge.png", (670, 420, 1325, 610), ("vfx", "wake")),
        CropSpec("vfx/shimakaze_vfx_reference_sheet.png", "processed/vfx", "shimakaze_vfx_water_impact_large.png", (1220, 500, 1460, 685), ("vfx", "impact")),
        CropSpec("vfx/shimakaze_vfx_reference_sheet.png", "processed/vfx", "shimakaze_vfx_speed_lines.png", (690, 690, 1200, 870), ("vfx", "speed")),
        CropSpec("battle/shimakaze_anim_keyframes_sheet.png", "processed/anim", "shimakaze_anim_idle_keyframe.png", (55, 55, 500, 410), ("anim", "idle")),
        CropSpec("battle/shimakaze_anim_keyframes_sheet.png", "processed/anim", "shimakaze_anim_move_keyframe.png", (500, 55, 1130, 425), ("anim", "move")),
        CropSpec("battle/shimakaze_anim_keyframes_sheet.png", "processed/anim", "shimakaze_anim_attack_keyframe.png", (1120, 55, 1700, 425), ("anim", "attack")),
        CropSpec("battle/shimakaze_anim_keyframes_sheet.png", "processed/anim", "shimakaze_anim_hit_keyframe.png", (260, 450, 820, 850), ("anim", "hit")),
        CropSpec("battle/shimakaze_anim_keyframes_sheet.png", "processed/anim", "shimakaze_anim_firepower_keyframe.png", (910, 440, 1685, 855), ("anim", "firepower")),
        CropSpec("concept/shimakaze_concept_full.png", "processed/ui", "shimakaze_illust_full_alpha.png", (0, 0, 1024, 1536), ("illustration", "full_body")),
        CropSpec("ui/shimakaze_illust_half.png", "processed/ui", "shimakaze_illust_half_alpha.png", (0, 0, 1122, 1402), ("illustration",)),
        CropSpec("ui/shimakaze_illust_skill_cutin.png", "processed/ui", "shimakaze_illust_skill_cutin_alpha.png", (0, 0, 1774, 887), ("cutin",)),
        *[
            CropSpec("ui/shimakaze_ui_sheet.png", "processed/ui", name, box, tags)
            for name, box, tags in (
                ("shimakaze_ui_portrait.png", (45, 45, 268, 582), ("ui", "portrait")),
                ("shimakaze_ui_portrait_small.png", (358, 45, 581, 582), ("ui", "portrait_small")),
                ("shimakaze_ui_chibi_head.png", (672, 45, 895, 582), ("ui", "chibi")),
                ("shimakaze_expr_default.png", (985, 45, 1208, 582), ("ui", "expression")),
                ("shimakaze_expr_serious.png", (45, 672, 268, 1209), ("ui", "expression", "serious")),
                ("shimakaze_expr_hit.png", (358, 672, 581, 1209), ("ui", "expression", "hit")),
                ("shimakaze_ui_skill_torpedo_rush.png", (672, 672, 895, 1209), ("ui", "skill")),
                ("shimakaze_ui_class_destroyer.png", (985, 672, 1208, 1209), ("ui", "class_icon")),
            )
        ],
        *[
            CropSpec("battle/shimakaze_battle_asset_sheet.png", out_dir, name, box, tags)
            for out_dir, name, box, tags in (
                ("processed/battle", "shimakaze_battle_body_r.png", (45, 45, 268, 373), ("battle", "body")),
                ("processed/battle", "shimakaze_battle_rig_base.png", (358, 45, 581, 373), ("battle", "rig")),
                ("processed/battle", "shimakaze_battle_torpedo_tube_01.png", (672, 45, 895, 373), ("battle", "torpedo")),
                ("processed/battle", "shimakaze_battle_torpedo_tube_02.png", (985, 45, 1208, 373), ("battle", "torpedo")),
                ("processed/battle", "shimakaze_battle_turret_main_01.png", (45, 463, 268, 791), ("battle", "turret")),
                ("processed/battle", "shimakaze_battle_thruster_01.png", (358, 463, 581, 791), ("battle", "thruster")),
                ("processed/battle", "shimakaze_battle_warning_emitter.png", (672, 463, 895, 791), ("battle", "torpedo_warning")),
                ("processed/vfx", "shimakaze_vfx_wake_fast.png", (985, 463, 1208, 791), ("vfx", "wake")),
                ("processed/vfx", "shimakaze_vfx_wake_long.png", (45, 881, 268, 1209), ("vfx", "wake")),
                ("processed/vfx", "shimakaze_vfx_torpedo_trail_group.png", (358, 881, 581, 1209), ("vfx", "torpedo")),
                ("processed/vfx", "shimakaze_vfx_water_impact.png", (672, 881, 895, 1209), ("vfx", "impact")),
                ("processed/vfx", "shimakaze_vfx_speed_lines.png", (985, 881, 1208, 1209), ("vfx", "speed")),
            )
        ],
        *[
            CropSpec("vfx/shimakaze_vfx_reference_sheet.png", "processed/vfx", name, box, tags)
            for name, box, tags in (
                ("shimakaze_vfx_warning_line_single.png", (45, 45, 268, 373), ("vfx", "torpedo_warning")),
                ("shimakaze_vfx_warning_fan.png", (358, 45, 581, 373), ("vfx", "torpedo_warning")),
                ("shimakaze_vfx_torpedo_trail_long.png", (672, 45, 895, 373), ("vfx", "torpedo")),
                ("shimakaze_vfx_torpedo_trail_curved.png", (985, 45, 1208, 373), ("vfx", "torpedo")),
                ("shimakaze_vfx_wake_blade.png", (45, 463, 268, 791), ("vfx", "wake")),
                ("shimakaze_vfx_speed_wake.png", (358, 463, 581, 791), ("vfx", "wake")),
                ("shimakaze_vfx_wake_surge.png", (672, 463, 895, 791), ("vfx", "wake")),
                ("shimakaze_vfx_propulsion_burst.png", (985, 463, 1208, 791), ("vfx", "speed")),
                ("shimakaze_vfx_water_impact_large.png", (45, 881, 268, 1209), ("vfx", "impact")),
                ("shimakaze_vfx_smoke_screen.png", (358, 881, 581, 1209), ("vfx", "smoke")),
                ("shimakaze_vfx_speed_lines_reference.png", (672, 881, 895, 1209), ("vfx", "speed")),
                ("shimakaze_vfx_torpedo_rush_target.png", (985, 881, 1208, 1209), ("vfx", "area")),
                ("shimakaze_vfx_torpedo_trail_01.png", (672, 45, 895, 373), ("vfx", "torpedo")),
                ("shimakaze_vfx_torpedo_trail_02.png", (985, 45, 1208, 373), ("vfx", "torpedo")),
            )
        ],
        *[
            CropSpec(f"battle/shimakaze_anim_{state}_4f_sheet.png", "processed/anim", f"shimakaze_anim_{state}_keyframe.png", (80, 60, 547, 567), ("anim", state))
            for state in ("idle", "move", "attack", "hit", "firepower")
        ],
        *[
            CropSpec(f"battle/shimakaze_anim_{state}_4f_sheet.png", "processed/anim", f"shimakaze_anim_{state}_frame_{index:02d}.png", box, ("anim", state, f"frame_{index:02d}"))
            for state in ("idle", "move", "attack", "hit", "firepower")
            for index, box in enumerate(((80, 60, 547, 567), (707, 60, 1174, 567), (80, 687, 547, 1194), (707, 687, 1174, 1194)), 1)
        ],
    ],
    "aurora": [
        CropSpec("concept/aurora_concept_full.png", "processed/ui", "aurora_illust_full_alpha.png", (0, 0, 1024, 1536), ("illustration", "full_body")),
        CropSpec("ui/aurora_illust_half.png", "processed/ui", "aurora_illust_half_alpha.png", (0, 0, 1536, 1024), ("illustration",)),
        CropSpec("ui/aurora_illust_skill_cutin.png", "processed/ui", "aurora_illust_skill_cutin_alpha.png", (0, 0, 1536, 1024), ("cutin",)),
        CropSpec("ui/aurora_ui_sheet.png", "processed/ui", "aurora_ui_portrait.png", (40, 75, 655, 820), ("ui", "portrait")),
        CropSpec("ui/aurora_ui_sheet.png", "processed/ui", "aurora_ui_portrait_small.png", (710, 250, 1085, 660), ("ui", "portrait_small")),
        CropSpec("ui/aurora_ui_sheet.png", "processed/ui", "aurora_ui_skill_searchlight_support.png", (1160, 245, 1600, 725), ("ui", "skill")),
        CropSpec("battle/aurora_battle_asset_sheet.png", "processed/battle", "aurora_battle_body_r.png", (50, 60, 430, 430), ("battle", "body")),
        CropSpec("battle/aurora_battle_asset_sheet.png", "processed/battle", "aurora_battle_rig_base.png", (455, 75, 905, 410), ("battle", "rig")),
        CropSpec("battle/aurora_battle_asset_sheet.png", "processed/battle", "aurora_battle_turret_main_01.png", (1065, 105, 1235, 255), ("battle", "turret")),
        CropSpec("battle/aurora_battle_asset_sheet.png", "processed/battle", "aurora_battle_turret_main_02.png", (1280, 105, 1470, 255), ("battle", "turret")),
        CropSpec("battle/aurora_battle_asset_sheet.png", "processed/battle", "aurora_battle_searchlight_node.png", (55, 500, 245, 690), ("battle", "searchlight")),
        CropSpec("battle/aurora_battle_asset_sheet.png", "processed/battle", "aurora_battle_signal_lamp_node.png", (290, 500, 455, 695), ("battle", "signal_lamp")),
        CropSpec("battle/aurora_battle_asset_sheet.png", "processed/vfx", "aurora_vfx_support_ring_01.png", (575, 575, 690, 665), ("vfx", "support_area")),
        CropSpec("battle/aurora_battle_asset_sheet.png", "processed/vfx", "aurora_vfx_support_ring_02.png", (810, 575, 925, 665), ("vfx", "support_area")),
        CropSpec("battle/aurora_battle_asset_sheet.png", "processed/vfx", "aurora_vfx_support_ring_03.png", (1025, 575, 1125, 665), ("vfx", "support_area")),
        CropSpec("battle/aurora_battle_asset_sheet.png", "processed/vfx", "aurora_vfx_wake_long_01.png", (160, 835, 520, 920), ("vfx", "wake")),
        CropSpec("battle/aurora_battle_asset_sheet.png", "processed/vfx", "aurora_vfx_wake_long_02.png", (760, 835, 1080, 920), ("vfx", "wake")),
        CropSpec("battle/aurora_battle_asset_sheet.png", "processed/vfx", "aurora_vfx_hit_sparks.png", (1200, 760, 1505, 965), ("vfx", "hit")),
        CropSpec("vfx/aurora_vfx_reference_sheet.png", "processed/vfx", "aurora_vfx_searchlight_beam.png", (35, 65, 690, 260), ("vfx", "searchlight")),
        CropSpec("vfx/aurora_vfx_reference_sheet.png", "processed/vfx", "aurora_vfx_command_ring.png", (830, 50, 1460, 310), ("vfx", "support_area")),
        CropSpec("vfx/aurora_vfx_reference_sheet.png", "processed/vfx", "aurora_vfx_muzzle_flash_01.png", (45, 350, 415, 515), ("vfx", "muzzle_flash")),
        CropSpec("vfx/aurora_vfx_reference_sheet.png", "processed/vfx", "aurora_vfx_muzzle_flash_02.png", (505, 375, 790, 470), ("vfx", "muzzle_flash")),
        CropSpec("vfx/aurora_vfx_reference_sheet.png", "processed/vfx", "aurora_vfx_wake.png", (155, 610, 545, 715), ("vfx", "wake")),
        CropSpec("vfx/aurora_vfx_reference_sheet.png", "processed/vfx", "aurora_vfx_water_splash.png", (720, 560, 990, 760), ("vfx", "splash")),
        CropSpec("vfx/aurora_vfx_reference_sheet.png", "processed/vfx", "aurora_vfx_signal_lamp_aura.png", (1040, 520, 1370, 750), ("vfx", "signal_lamp")),
        CropSpec("vfx/aurora_vfx_reference_sheet.png", "processed/vfx", "aurora_vfx_morale_aura.png", (1115, 850, 1430, 970), ("vfx", "support_area")),
        CropSpec("battle/aurora_anim_keyframes_sheet.png", "processed/anim", "aurora_anim_idle_keyframe.png", (30, 55, 485, 405), ("anim", "idle")),
        CropSpec("battle/aurora_anim_keyframes_sheet.png", "processed/anim", "aurora_anim_move_keyframe.png", (520, 60, 1060, 420), ("anim", "move")),
        CropSpec("battle/aurora_anim_keyframes_sheet.png", "processed/anim", "aurora_anim_attack_keyframe.png", (1120, 40, 1760, 420), ("anim", "attack")),
        CropSpec("battle/aurora_anim_keyframes_sheet.png", "processed/anim", "aurora_anim_hit_keyframe.png", (190, 445, 690, 830), ("anim", "hit")),
        CropSpec("battle/aurora_anim_keyframes_sheet.png", "processed/anim", "aurora_anim_firepower_keyframe.png", (770, 435, 1565, 850), ("anim", "firepower")),
        CropSpec("concept/aurora_concept_full.png", "processed/ui", "aurora_illust_full_alpha.png", (0, 0, 1024, 1536), ("illustration", "full_body")),
        CropSpec("ui/aurora_illust_half.png", "processed/ui", "aurora_illust_half_alpha.png", (0, 0, 1122, 1402), ("illustration",)),
        CropSpec("ui/aurora_illust_skill_cutin.png", "processed/ui", "aurora_illust_skill_cutin_alpha.png", (0, 0, 1774, 887), ("cutin",)),
        *[
            CropSpec("ui/aurora_ui_sheet.png", "processed/ui", name, box, tags)
            for name, box, tags in (
                ("aurora_ui_portrait.png", (15, 20, 375, 500), ("ui", "portrait")),
                ("aurora_ui_portrait_small.png", (400, 20, 760, 500), ("ui", "portrait_small")),
                ("aurora_ui_chibi_head.png", (785, 20, 1145, 500), ("ui", "chibi")),
                ("aurora_expr_default.png", (1160, 20, 1520, 500), ("ui", "expression")),
                ("aurora_expr_serious.png", (15, 530, 375, 1005), ("ui", "expression", "serious")),
                ("aurora_expr_hit.png", (400, 530, 760, 1005), ("ui", "expression", "hit")),
                ("aurora_ui_skill_searchlight_support.png", (785, 530, 1145, 1005), ("ui", "skill")),
                ("aurora_ui_class_light_cruiser.png", (1160, 530, 1520, 1005), ("ui", "class_icon")),
            )
        ],
        *[
            CropSpec("battle/aurora_battle_asset_sheet.png", out_dir, name, box, tags)
            for out_dir, name, box, tags in (
                ("processed/battle", "aurora_battle_body_r.png", (35, 130, 300, 390), ("battle", "body")),
                ("processed/battle", "aurora_battle_rig_base.png", (390, 140, 670, 390), ("battle", "rig")),
                ("processed/battle", "aurora_battle_turret_main_01.png", (740, 230, 940, 380), ("battle", "turret")),
                ("processed/battle", "aurora_battle_turret_main_02.png", (1010, 230, 1210, 380), ("battle", "turret")),
                ("processed/battle", "aurora_battle_searchlight_node.png", (55, 520, 270, 780), ("battle", "searchlight")),
                ("processed/battle", "aurora_battle_signal_lamp_node.png", (405, 520, 600, 780), ("battle", "signal_lamp")),
                ("processed/battle", "aurora_battle_command_emitter.png", (705, 530, 900, 780), ("battle", "support")),
                ("processed/vfx", "aurora_vfx_wake.png", (1000, 560, 1210, 760), ("vfx", "wake")),
                ("processed/vfx", "aurora_vfx_turn_wake.png", (30, 930, 290, 1160), ("vfx", "wake")),
                ("processed/vfx", "aurora_vfx_muzzle_flash_01.png", (390, 930, 610, 1130), ("vfx", "muzzle_flash")),
                ("processed/vfx", "aurora_vfx_water_splash.png", (720, 920, 930, 1160), ("vfx", "splash")),
                ("processed/vfx", "aurora_vfx_morale_aura.png", (1000, 920, 1210, 1160), ("vfx", "support_area")),
            )
        ],
        *[
            CropSpec("vfx/aurora_vfx_reference_sheet.png", "processed/vfx", name, box, tags)
            for name, box, tags in (
                ("aurora_vfx_searchlight_beam.png", (15, 10, 375, 330), ("vfx", "searchlight")),
                ("aurora_vfx_searchlight_beam_narrow.png", (400, 10, 760, 330), ("vfx", "searchlight")),
                ("aurora_vfx_command_ring.png", (785, 10, 1145, 330), ("vfx", "support_area")),
                ("aurora_vfx_signal_lamp_aura.png", (1160, 10, 1520, 330), ("vfx", "signal_lamp")),
                ("aurora_vfx_muzzle_flash_02.png", (15, 350, 375, 670), ("vfx", "muzzle_flash")),
                ("aurora_vfx_shell_trails.png", (400, 350, 760, 670), ("vfx", "projectile")),
                ("aurora_vfx_support_area.png", (785, 350, 1145, 670), ("vfx", "support_area")),
                ("aurora_vfx_morale_aura.png", (1160, 350, 1520, 670), ("vfx", "support_area")),
                ("aurora_vfx_wake.png", (15, 690, 375, 1015), ("vfx", "wake")),
                ("aurora_vfx_turn_wake.png", (400, 690, 760, 1015), ("vfx", "wake")),
                ("aurora_vfx_water_splash.png", (785, 690, 1145, 1015), ("vfx", "splash")),
                ("aurora_vfx_hit_sparks.png", (1160, 690, 1520, 1015), ("vfx", "hit")),
            )
        ],
        *[
            CropSpec(f"battle/aurora_anim_{state}_4f_sheet.png", "processed/anim", f"aurora_anim_{state}_keyframe.png", (80, 60, 547, 567), ("anim", state))
            for state in ("idle", "move", "attack", "hit", "firepower")
        ],
        *[
            CropSpec(f"battle/aurora_anim_{state}_4f_sheet.png", "processed/anim", f"aurora_anim_{state}_frame_{index:02d}.png", box, ("anim", state, f"frame_{index:02d}"))
            for state in ("idle", "move", "attack", "hit", "firepower")
            for index, box in enumerate(((80, 60, 547, 567), (707, 60, 1174, 567), (80, 687, 547, 1194), (707, 687, 1174, 1194)), 1)
        ],
    ],
    "warspite": [
        CropSpec("concept/warspite_concept_full.png", "processed/ui", "warspite_illust_full_alpha.png", (0, 0, 1536, 1024), ("illustration", "full_body")),
        CropSpec("ui/warspite_illust_half.png", "processed/ui", "warspite_illust_half_alpha.png", (0, 0, 1536, 1024), ("illustration",)),
        CropSpec("ui/warspite_illust_skill_cutin.png", "processed/ui", "warspite_illust_skill_cutin_alpha.png", (0, 0, 1536, 1024), ("cutin",)),
        CropSpec("ui/warspite_ui_sheet.png", "processed/ui", "warspite_ui_portrait.png", (70, 80, 660, 795), ("ui", "portrait")),
        CropSpec("ui/warspite_ui_sheet.png", "processed/ui", "warspite_ui_portrait_small.png", (735, 170, 1120, 625), ("ui", "portrait_small")),
        CropSpec("ui/warspite_ui_sheet.png", "processed/ui", "warspite_ui_skill_precision_barrage.png", (1220, 155, 1680, 650), ("ui", "skill")),
        CropSpec("battle/warspite_battle_asset_sheet.png", "processed/battle", "warspite_battle_body_r.png", (110, 95, 445, 405), ("battle", "body")),
        CropSpec("battle/warspite_battle_asset_sheet.png", "processed/battle", "warspite_battle_rig_base.png", (620, 45, 1375, 385), ("battle", "rig")),
        CropSpec("battle/warspite_battle_asset_sheet.png", "processed/battle", "warspite_battle_turret_main_01.png", (65, 475, 295, 610), ("battle", "turret")),
        CropSpec("battle/warspite_battle_asset_sheet.png", "processed/battle", "warspite_battle_turret_main_02.png", (330, 475, 570, 610), ("battle", "turret")),
        CropSpec("battle/warspite_battle_asset_sheet.png", "processed/battle", "warspite_battle_turret_main_03.png", (600, 475, 840, 610), ("battle", "turret")),
        CropSpec("battle/warspite_battle_asset_sheet.png", "processed/battle", "warspite_battle_rangefinder_node.png", (905, 455, 1035, 620), ("battle", "rangefinder")),
        CropSpec("battle/warspite_battle_asset_sheet.png", "processed/battle", "warspite_battle_radar_node.png", (1240, 475, 1370, 610), ("battle", "radar")),
        CropSpec("battle/warspite_battle_asset_sheet.png", "processed/vfx", "warspite_vfx_muzzle_small.png", (60, 690, 240, 800), ("vfx", "muzzle_flash")),
        CropSpec("battle/warspite_battle_asset_sheet.png", "processed/vfx", "warspite_vfx_muzzle_medium.png", (300, 680, 560, 805), ("vfx", "muzzle_flash")),
        CropSpec("battle/warspite_battle_asset_sheet.png", "processed/vfx", "warspite_vfx_muzzle_large.png", (685, 655, 1005, 815), ("vfx", "muzzle_flash")),
        CropSpec("battle/warspite_battle_asset_sheet.png", "processed/vfx", "warspite_vfx_splash_small.png", (90, 850, 220, 990), ("vfx", "splash")),
        CropSpec("battle/warspite_battle_asset_sheet.png", "processed/vfx", "warspite_vfx_splash_medium.png", (330, 840, 520, 995), ("vfx", "splash")),
        CropSpec("battle/warspite_battle_asset_sheet.png", "processed/vfx", "warspite_vfx_splash_large.png", (660, 825, 900, 1000), ("vfx", "splash")),
        CropSpec("vfx/warspite_vfx_reference_sheet.png", "processed/vfx", "warspite_vfx_heavy_muzzle_cone.png", (50, 75, 640, 270), ("vfx", "muzzle_flash")),
        CropSpec("vfx/warspite_vfx_reference_sheet.png", "processed/vfx", "warspite_vfx_reticle_main.png", (695, 60, 1035, 305), ("vfx", "reticle")),
        CropSpec("vfx/warspite_vfx_reference_sheet.png", "processed/vfx", "warspite_vfx_range_scale.png", (1115, 55, 1470, 305), ("vfx", "rangefinder")),
        CropSpec("vfx/warspite_vfx_reference_sheet.png", "processed/vfx", "warspite_vfx_splash_sequence_01.png", (65, 410, 315, 650), ("vfx", "splash")),
        CropSpec("vfx/warspite_vfx_reference_sheet.png", "processed/vfx", "warspite_vfx_splash_sequence_02.png", (350, 410, 625, 650), ("vfx", "splash")),
        CropSpec("vfx/warspite_vfx_reference_sheet.png", "processed/vfx", "warspite_vfx_wake.png", (820, 455, 1395, 660), ("vfx", "wake")),
        CropSpec("vfx/warspite_vfx_reference_sheet.png", "processed/vfx", "warspite_vfx_shell_trails.png", (70, 705, 830, 795), ("vfx", "shell")),
        CropSpec("vfx/warspite_vfx_reference_sheet.png", "processed/vfx", "warspite_vfx_impact_burst.png", (90, 850, 720, 1000), ("vfx", "impact")),
        CropSpec("vfx/warspite_vfx_reference_sheet.png", "processed/vfx", "warspite_vfx_royal_area.png", (905, 710, 1465, 1000), ("vfx", "area")),
        CropSpec("battle/warspite_anim_keyframes_sheet.png", "processed/anim", "warspite_anim_idle_keyframe.png", (55, 80, 540, 410), ("anim", "idle")),
        CropSpec("battle/warspite_anim_keyframes_sheet.png", "processed/anim", "warspite_anim_move_keyframe.png", (560, 85, 1120, 420), ("anim", "move")),
        CropSpec("battle/warspite_anim_keyframes_sheet.png", "processed/anim", "warspite_anim_attack_keyframe.png", (1180, 75, 1710, 410), ("anim", "attack")),
        CropSpec("battle/warspite_anim_keyframes_sheet.png", "processed/anim", "warspite_anim_hit_keyframe.png", (155, 460, 650, 800), ("anim", "hit")),
        CropSpec("battle/warspite_anim_keyframes_sheet.png", "processed/anim", "warspite_anim_firepower_keyframe.png", (760, 450, 1610, 820), ("anim", "firepower")),
        CropSpec("concept/warspite_concept_full.png", "processed/ui", "warspite_illust_full_alpha.png", (0, 0, 1024, 1536), ("illustration", "full_body")),
        CropSpec("ui/warspite_illust_half.png", "processed/ui", "warspite_illust_half_alpha.png", (0, 0, 1122, 1402), ("illustration",)),
        CropSpec("ui/warspite_illust_skill_cutin.png", "processed/ui", "warspite_illust_skill_cutin_alpha.png", (0, 0, 1774, 887), ("cutin",)),
        *[
            CropSpec("ui/warspite_ui_sheet.png", "processed/ui", name, box, tags)
            for name, box, tags in (
                ("warspite_ui_portrait.png", (15, 20, 375, 500), ("ui", "portrait")),
                ("warspite_ui_portrait_small.png", (400, 20, 760, 500), ("ui", "portrait_small")),
                ("warspite_ui_chibi_head.png", (785, 20, 1145, 500), ("ui", "chibi")),
                ("warspite_expr_default.png", (1160, 20, 1520, 500), ("ui", "expression")),
                ("warspite_expr_serious.png", (15, 530, 375, 1005), ("ui", "expression", "serious")),
                ("warspite_expr_hit.png", (400, 530, 760, 1005), ("ui", "expression", "hit")),
                ("warspite_ui_skill_precision_barrage.png", (785, 530, 1145, 1005), ("ui", "skill")),
                ("warspite_ui_class_battleship.png", (1160, 530, 1520, 1005), ("ui", "class_icon")),
            )
        ],
        *[
            CropSpec("battle/warspite_battle_asset_sheet.png", out_dir, name, box, tags)
            for out_dir, name, box, tags in (
                ("processed/battle", "warspite_battle_body_r.png", (35, 120, 300, 390), ("battle", "body")),
                ("processed/battle", "warspite_battle_rig_base.png", (380, 130, 630, 390), ("battle", "rig")),
                ("processed/battle", "warspite_battle_turret_main_01.png", (735, 220, 940, 385), ("battle", "turret")),
                ("processed/battle", "warspite_battle_turret_main_02.png", (1010, 220, 1210, 385), ("battle", "turret")),
                ("processed/battle", "warspite_battle_turret_main_03.png", (55, 545, 285, 745), ("battle", "turret")),
                ("processed/battle", "warspite_battle_rangefinder_node.png", (405, 515, 600, 770), ("battle", "rangefinder")),
                ("processed/battle", "warspite_battle_command_emitter.png", (705, 515, 900, 770), ("battle", "support")),
                ("processed/battle", "warspite_battle_radar_node.png", (705, 515, 900, 770), ("battle", "support")),
                ("processed/vfx", "warspite_vfx_wake.png", (1000, 550, 1210, 760), ("vfx", "wake")),
                ("processed/vfx", "warspite_vfx_turn_wake.png", (30, 930, 290, 1160), ("vfx", "wake")),
                ("processed/vfx", "warspite_vfx_muzzle_large.png", (390, 930, 610, 1130), ("vfx", "muzzle_flash")),
                ("processed/vfx", "warspite_vfx_splash_large.png", (720, 920, 930, 1160), ("vfx", "splash")),
                ("processed/vfx", "warspite_vfx_armor_sparks.png", (1000, 920, 1210, 1160), ("vfx", "hit")),
            )
        ],
        *[
            CropSpec("vfx/warspite_vfx_reference_sheet.png", "processed/vfx", name, box, tags)
            for name, box, tags in (
                ("warspite_vfx_heavy_muzzle_cone.png", (15, 10, 375, 330), ("vfx", "muzzle_flash")),
                ("warspite_vfx_precision_muzzle.png", (400, 10, 760, 330), ("vfx", "muzzle_flash")),
                ("warspite_vfx_reticle_main.png", (785, 10, 1145, 330), ("vfx", "reticle")),
                ("warspite_vfx_range_scale.png", (1160, 10, 1520, 330), ("vfx", "rangefinder")),
                ("warspite_vfx_shell_trails.png", (15, 350, 375, 670), ("vfx", "shell")),
                ("warspite_vfx_broadside_smoke.png", (400, 350, 760, 670), ("vfx", "smoke")),
                ("warspite_vfx_royal_area.png", (785, 350, 1145, 670), ("vfx", "area")),
                ("warspite_vfx_precision_aura.png", (1160, 350, 1520, 670), ("vfx", "area")),
                ("warspite_vfx_wake.png", (15, 690, 375, 1015), ("vfx", "wake")),
                ("warspite_vfx_turn_wake.png", (400, 690, 760, 1015), ("vfx", "wake")),
                ("warspite_vfx_splash_sequence_02.png", (785, 690, 1145, 1015), ("vfx", "splash")),
                ("warspite_vfx_armor_sparks.png", (1160, 690, 1520, 1015), ("vfx", "impact")),
            )
        ],
        *[
            CropSpec(f"battle/warspite_anim_{state}_4f_sheet.png", "processed/anim", f"warspite_anim_{state}_keyframe.png", (80, 60, 547, 567), ("anim", state))
            for state in ("idle", "move", "attack", "hit", "firepower")
        ],
        *[
            CropSpec(f"battle/warspite_anim_{state}_4f_sheet.png", "processed/anim", f"warspite_anim_{state}_frame_{index:02d}.png", box, ("anim", state, f"frame_{index:02d}"))
            for state in ("idle", "move", "attack", "hit", "firepower")
            for index, box in enumerate(((80, 60, 547, 567), (707, 60, 1174, 567), (80, 687, 547, 1194), (707, 687, 1174, 1194)), 1)
        ],
    ],
    "bismarck": [
        CropSpec("concept/bismarck_concept_full.png", "processed/ui", "bismarck_illust_full_alpha.png", (0, 0, 1023, 1537), ("illustration", "full_body")),
        CropSpec("ui/bismarck_illust_half.png", "processed/ui", "bismarck_illust_half_alpha.png", (0, 0, 1402, 1122), ("illustration", "half_body")),
        CropSpec("ui/bismarck_illust_skill_cutin.png", "processed/ui", "bismarck_illust_skill_cutin_alpha.png", (0, 0, 1774, 887), ("illustration", "cutin")),
        CropSpec("ui/bismarck_ui_sheet.png", "processed/ui", "bismarck_ui_portrait.png", (145, 150, 300, 335), ("ui", "portrait")),
        CropSpec("ui/bismarck_ui_sheet.png", "processed/ui", "bismarck_ui_portrait_small.png", (520, 175, 650, 335), ("ui", "portrait_small")),
        CropSpec("ui/bismarck_ui_sheet.png", "processed/ui", "bismarck_ui_chibi_head.png", (885, 190, 1010, 350), ("ui", "chibi", "remove_small_islands")),
        CropSpec("ui/bismarck_ui_sheet.png", "processed/ui", "bismarck_expr_default.png", (1240, 165, 1410, 350), ("ui", "expression", "default")),
        CropSpec("ui/bismarck_ui_sheet.png", "processed/ui", "bismarck_expr_serious.png", (115, 625, 280, 795), ("ui", "expression", "serious")),
        CropSpec("ui/bismarck_ui_sheet.png", "processed/ui", "bismarck_expr_hit.png", (500, 625, 650, 795), ("ui", "expression", "hit")),
        CropSpec("ui/bismarck_ui_sheet.png", "processed/ui", "bismarck_ui_skill_decisive_salvo.png", (870, 650, 1030, 825), ("ui", "skill")),
        CropSpec("ui/bismarck_ui_sheet.png", "processed/ui", "bismarck_ui_class_battleship.png", (1260, 650, 1400, 825), ("ui", "class_icon")),
        CropSpec("battle/bismarck_battle_asset_sheet.png", "processed/battle", "bismarck_battle_body_r.png", (105, 155, 190, 285), ("battle", "body")),
        CropSpec("battle/bismarck_battle_asset_sheet.png", "processed/battle", "bismarck_battle_rig_base.png", (420, 170, 700, 310), ("battle", "rig", "keep_largest_component")),
        CropSpec("battle/bismarck_battle_asset_sheet.png", "processed/battle", "bismarck_battle_turret_main_01.png", (910, 190, 1050, 295), ("battle", "turret", "keep_largest_component")),
        CropSpec("battle/bismarck_battle_asset_sheet.png", "processed/battle", "bismarck_battle_turret_main_02.png", (1260, 190, 1410, 295), ("battle", "turret")),
        CropSpec("battle/bismarck_battle_asset_sheet.png", "processed/battle", "bismarck_battle_rangefinder_node.png", (115, 500, 210, 610), ("battle", "rangefinder")),
        CropSpec("battle/bismarck_battle_asset_sheet.png", "processed/battle", "bismarck_battle_flagship_marker_node.png", (445, 500, 535, 610), ("battle", "flagship_marker")),
        CropSpec("battle/bismarck_battle_asset_sheet.png", "processed/vfx", "bismarck_vfx_lock_reticle.png", (790, 500, 900, 610), ("vfx", "reticle")),
        CropSpec("battle/bismarck_battle_asset_sheet.png", "processed/vfx", "bismarck_vfx_muzzle_flash.png", (1190, 500, 1370, 610), ("vfx", "muzzle_flash")),
        CropSpec("battle/bismarck_battle_asset_sheet.png", "processed/vfx", "bismarck_vfx_wake_wide.png", (190, 820, 430, 930), ("vfx", "wake")),
        CropSpec("battle/bismarck_battle_asset_sheet.png", "processed/vfx", "bismarck_vfx_water_impact.png", (735, 790, 920, 930), ("vfx", "impact")),
        CropSpec("battle/bismarck_battle_asset_sheet.png", "processed/vfx", "bismarck_vfx_armor_hit.png", (1230, 805, 1390, 925), ("vfx", "hit")),
        CropSpec("vfx/bismarck_vfx_reference_sheet.png", "processed/vfx", "bismarck_vfx_heavy_muzzle_cone.png", (105, 155, 285, 260), ("vfx", "muzzle_flash")),
        CropSpec("vfx/bismarck_vfx_reference_sheet.png", "processed/vfx", "bismarck_vfx_smoke_burst.png", (560, 150, 690, 285), ("vfx", "smoke")),
        CropSpec("vfx/bismarck_vfx_reference_sheet.png", "processed/vfx", "bismarck_vfx_lock_line.png", (900, 175, 1080, 260), ("vfx", "lock_line")),
        CropSpec("vfx/bismarck_vfx_reference_sheet.png", "processed/vfx", "bismarck_vfx_precision_reticle.png", (1280, 135, 1430, 290), ("vfx", "reticle")),
        CropSpec("vfx/bismarck_vfx_reference_sheet.png", "processed/vfx", "bismarck_vfx_range_arc.png", (125, 475, 350, 600), ("vfx", "range_scale")),
        CropSpec("vfx/bismarck_vfx_reference_sheet.png", "processed/vfx", "bismarck_vfx_shell_trail.png", (565, 500, 750, 600), ("vfx", "shell")),
        CropSpec("vfx/bismarck_vfx_reference_sheet.png", "processed/vfx", "bismarck_vfx_wake.png", (1050, 470, 1360, 610), ("vfx", "wake")),
        CropSpec("vfx/bismarck_vfx_reference_sheet.png", "processed/vfx", "bismarck_vfx_splash_large.png", (140, 760, 380, 925), ("vfx", "splash")),
        CropSpec("vfx/bismarck_vfx_reference_sheet.png", "processed/vfx", "bismarck_vfx_armor_sparks.png", (600, 760, 780, 925), ("vfx", "hit")),
        CropSpec("vfx/bismarck_vfx_reference_sheet.png", "processed/vfx", "bismarck_vfx_decisive_area.png", (1050, 760, 1400, 925), ("vfx", "area")),
        CropSpec("battle/bismarck_anim_keyframes_sheet.png", "processed/anim", "bismarck_anim_idle_keyframe.png", (160, 170, 360, 350), ("anim", "idle")),
        CropSpec("battle/bismarck_anim_keyframes_sheet.png", "processed/anim", "bismarck_anim_move_keyframe.png", (680, 175, 880, 360), ("anim", "move")),
        CropSpec("battle/bismarck_anim_keyframes_sheet.png", "processed/anim", "bismarck_anim_attack_keyframe.png", (1190, 170, 1395, 355), ("anim", "attack")),
        CropSpec("battle/bismarck_anim_keyframes_sheet.png", "processed/anim", "bismarck_anim_hit_keyframe.png", (380, 650, 615, 850), ("anim", "hit")),
        CropSpec("battle/bismarck_anim_keyframes_sheet.png", "processed/anim", "bismarck_anim_firepower_keyframe.png", (950, 650, 1190, 850), ("anim", "firepower")),
        CropSpec("battle/bismarck_anim_idle_4f_sheet.png", "processed/anim", "bismarck_anim_idle_frame_01.png", (120, 120, 500, 520), ("anim", "idle", "frame_01")),
        CropSpec("battle/bismarck_anim_idle_4f_sheet.png", "processed/anim", "bismarck_anim_idle_frame_02.png", (750, 120, 1130, 520), ("anim", "idle", "frame_02")),
        CropSpec("battle/bismarck_anim_idle_4f_sheet.png", "processed/anim", "bismarck_anim_idle_frame_03.png", (120, 750, 500, 1130), ("anim", "idle", "frame_03")),
        CropSpec("battle/bismarck_anim_idle_4f_sheet.png", "processed/anim", "bismarck_anim_idle_frame_04.png", (750, 750, 1130, 1130), ("anim", "idle", "frame_04")),
        CropSpec("battle/bismarck_anim_move_4f_sheet.png", "processed/anim", "bismarck_anim_move_frame_01.png", (90, 105, 520, 525), ("anim", "move", "frame_01")),
        CropSpec("battle/bismarck_anim_move_4f_sheet.png", "processed/anim", "bismarck_anim_move_frame_02.png", (735, 105, 1150, 525), ("anim", "move", "frame_02")),
        CropSpec("battle/bismarck_anim_move_4f_sheet.png", "processed/anim", "bismarck_anim_move_frame_03.png", (90, 735, 520, 1150), ("anim", "move", "frame_03")),
        CropSpec("battle/bismarck_anim_move_4f_sheet.png", "processed/anim", "bismarck_anim_move_frame_04.png", (735, 735, 1150, 1150), ("anim", "move", "frame_04")),
        CropSpec("battle/bismarck_anim_attack_4f_sheet.png", "processed/anim", "bismarck_anim_attack_frame_01.png", (110, 105, 520, 520), ("anim", "attack", "frame_01")),
        CropSpec("battle/bismarck_anim_attack_4f_sheet.png", "processed/anim", "bismarck_anim_attack_frame_02.png", (735, 105, 1150, 520), ("anim", "attack", "frame_02")),
        CropSpec("battle/bismarck_anim_attack_4f_sheet.png", "processed/anim", "bismarck_anim_attack_frame_03.png", (110, 735, 520, 1150), ("anim", "attack", "frame_03")),
        CropSpec("battle/bismarck_anim_attack_4f_sheet.png", "processed/anim", "bismarck_anim_attack_frame_04.png", (735, 735, 1150, 1150), ("anim", "attack", "frame_04")),
        CropSpec("battle/bismarck_anim_hit_4f_sheet.png", "processed/anim", "bismarck_anim_hit_frame_01.png", (100, 100, 520, 520), ("anim", "hit", "frame_01")),
        CropSpec("battle/bismarck_anim_hit_4f_sheet.png", "processed/anim", "bismarck_anim_hit_frame_02.png", (735, 100, 1150, 520), ("anim", "hit", "frame_02")),
        CropSpec("battle/bismarck_anim_hit_4f_sheet.png", "processed/anim", "bismarck_anim_hit_frame_03.png", (100, 735, 520, 1150), ("anim", "hit", "frame_03")),
        CropSpec("battle/bismarck_anim_hit_4f_sheet.png", "processed/anim", "bismarck_anim_hit_frame_04.png", (735, 735, 1150, 1150), ("anim", "hit", "frame_04")),
        CropSpec("battle/bismarck_anim_firepower_4f_sheet.png", "processed/anim", "bismarck_anim_firepower_frame_01.png", (100, 80, 680, 440), ("anim", "firepower", "frame_01")),
        CropSpec("battle/bismarck_anim_firepower_4f_sheet.png", "processed/anim", "bismarck_anim_firepower_frame_02.png", (860, 80, 1440, 440), ("anim", "firepower", "frame_02")),
        CropSpec("battle/bismarck_anim_firepower_4f_sheet.png", "processed/anim", "bismarck_anim_firepower_frame_03.png", (100, 590, 680, 950), ("anim", "firepower", "frame_03")),
        CropSpec("battle/bismarck_anim_firepower_4f_sheet.png", "processed/anim", "bismarck_anim_firepower_frame_04.png", (860, 590, 1440, 950), ("anim", "firepower", "frame_04")),
    ],
}


CONFIGS: dict[str, dict[str, Any]] = {
    "enterprise_cv6": {
        "ship_class": "carrier",
        "battle_bind_points": {
            "enterprise_cv6_battle_body_r.png": {
                "origin": point(143, 286, "battle body ground/sea contact between the boots"),
                "rig_mount": point(70, 205, "left-side carrier rig mount behind the coat"),
            },
            "enterprise_cv6_battle_rig_base.png": {
                "origin": point(300, 320, "carrier hull visual center near the waterline"),
                "aircraft_launch_01": point(467, 273, "forward deck launch point"),
                "aircraft_launch_02": point(370, 238, "mid-deck launch point"),
                "aircraft_recovery": point(190, 185, "aft deck recovery point"),
            },
            "enterprise_cv6_battle_launch_marker.png": {
                "origin": point(147, 98, "center of the deck launch marker"),
            },
            "enterprise_cv6_battle_air_control_node.png": {
                "origin": point(120, 200, "air-control pedestal base"),
                "scan_origin": point(120, 75, "radar array scan center"),
            },
        },
        "animation_states": {
            "idle": "enterprise_cv6_anim_idle_keyframe.png",
            "move": "enterprise_cv6_anim_move_keyframe.png",
            "attack": "enterprise_cv6_anim_attack_keyframe.png",
            "hit": "enterprise_cv6_anim_hit_keyframe.png",
            "firepower": "enterprise_cv6_anim_firepower_keyframe.png",
        },
        "animation_sequences": {
            "idle": {"fps": 5, "loop": True},
            "move": {"fps": 7, "loop": True},
            "attack": {"fps": 10, "loop": False},
            "hit": {"fps": 10, "loop": False},
            "firepower": {"fps": 12, "loop": False},
        },
        "vfx_roles": {
            "airstrike_area": "enterprise_cv6_vfx_airstrike_area.png",
            "aircraft_path": "enterprise_cv6_vfx_aircraft_path_arrows.png",
            "deck_lane": "enterprise_cv6_vfx_deck_launch_lane.png",
            "wake": "enterprise_cv6_vfx_wake_fast.png",
            "hit": "enterprise_cv6_vfx_hit_sparks.png",
        },
    },
    "hai_shih": {
        "ship_class": "submarine",
        "battle_bind_points": {
            "hai_shih_battle_body_r.png": {
                "origin": point(170, 320, "battle body waterline center below the hull"),
                "torpedo_port": point(288, 235, "glowing bow torpedo direction"),
                "wake_origin": point(42, 275, "rear wake source"),
            },
            "hai_shih_battle_rig_base.png": {
                "origin": point(190, 235, "submarine hull visual center"),
                "torpedo_port": point(345, 180, "glowing bow torpedo port"),
                "periscope_point": point(228, 28, "conning-tower mast top"),
                "sonar_origin": point(345, 180, "bow sonar and guide-light origin"),
            },
            "hai_shih_battle_torpedo_tube_01.png": {
                "origin": point(135, 85, "tube rotation and attachment center"),
                "torpedo_port": point(45, 84, "cyan launch muzzle"),
            },
            "hai_shih_battle_periscope_node.png": {
                "origin": point(87, 222, "periscope pedestal pivot"),
                "view_origin": point(112, 65, "periscope lens center"),
            },
            "hai_shih_battle_sonar_node.png": {
                "origin": point(105, 215, "sonar pedestal pivot"),
                "sonar_origin": point(92, 90, "sonar dish center"),
            },
        },
        "animation_states": {
            "idle": "hai_shih_anim_idle_keyframe.png",
            "move": "hai_shih_anim_move_keyframe.png",
            "attack": "hai_shih_anim_attack_keyframe.png",
            "hit": "hai_shih_anim_hit_keyframe.png",
            "firepower": "hai_shih_anim_firepower_keyframe.png",
        },
        "animation_sequences": {
            "idle": {"fps": 5, "loop": True},
            "move": {"fps": 7, "loop": True},
            "attack": {"fps": 10, "loop": False},
            "hit": {"fps": 10, "loop": False},
            "firepower": {"fps": 12, "loop": False},
        },
        "vfx_roles": {
            "torpedo_trail": "hai_shih_vfx_torpedo_trail.png",
            "sonar_pulse": "hai_shih_vfx_sonar_pulse.png",
            "bubble_trail": "hai_shih_vfx_bubble_trail.png",
            "underwater_shadow": "hai_shih_vfx_underwater_shadow.png",
            "stealth": "hai_shih_vfx_stealth_shimmer.png",
        },
    },
    "hindenburg": {
        "ship_class": "heavy_cruiser",
        "battle_bind_points": {
            "hindenburg_battle_body_r.png": {
                "origin": point(135, 260, "battle body sea contact below the boots"),
                "rig_mount": point(58, 185, "rear heavy-cruiser rig mount"),
                "fire_control_point": point(220, 115, "single-eye rangefinder direction"),
            },
            "hindenburg_battle_rig_base.png": {
                "origin": point(185, 292, "heavy-cruiser hull visual center"),
                "turret_mount_01": point(265, 255, "forward heavy turret mount"),
                "fire_control_point": point(205, 92, "central fire-control tower"),
            },
            "hindenburg_battle_turret_main_01.png": {
                "origin": point(165, 142, "turret rotation center"),
                "muzzle_01": point(320, 92, "upper barrel muzzle"),
                "muzzle_02": point(320, 128, "lower barrel muzzle"),
            },
            "hindenburg_battle_turret_main_02.png": {
                "origin": point(162, 138, "turret rotation center"),
                "muzzle_01": point(316, 91, "upper barrel muzzle"),
                "muzzle_02": point(316, 126, "lower barrel muzzle"),
            },
            "hindenburg_battle_fire_control_node.png": {
                "origin": point(108, 278, "fire-control pedestal pivot"),
                "scan_origin": point(110, 112, "optical scan origin at reticle center"),
            },
            "hindenburg_battle_lock_emitter_node.png": {
                "origin": point(108, 170, "lock emitter base"),
                "scan_origin": point(108, 93, "cold-white lock emitter center"),
            },
        },
        "animation_states": {
            "idle": "hindenburg_anim_idle_keyframe.png",
            "move": "hindenburg_anim_move_keyframe.png",
            "attack": "hindenburg_anim_attack_keyframe.png",
            "hit": "hindenburg_anim_hit_keyframe.png",
            "firepower": "hindenburg_anim_firepower_keyframe.png",
        },
        "animation_sequences": {
            "idle": {"fps": 5, "loop": True},
            "move": {"fps": 7, "loop": True},
            "attack": {"fps": 10, "loop": False},
            "hit": {"fps": 10, "loop": False},
            "firepower": {"fps": 12, "loop": False},
        },
        "vfx_roles": {
            "reticle": "hindenburg_vfx_precision_reticle.png",
            "muzzle_flash": "hindenburg_vfx_heavy_muzzle_cone.png",
            "scan_beam": "hindenburg_vfx_scan_beam.png",
            "suppression_area": "hindenburg_vfx_suppression_ring.png",
            "shell_trail": "hindenburg_vfx_shell_trail.png",
            "wake": "hindenburg_vfx_wake.png",
        },
    },
    "shimakaze": {
        "ship_class": "destroyer",
        "battle_bind_points": {
            "shimakaze_battle_body_r.png": {
                "origin": point(175, 350, "battle body sea contact below the hull"),
                "torpedo_mount": point(88, 205, "rear five-tube launcher mount"),
                "wake_origin": point(45, 310, "rear high-speed wake source"),
            },
            "shimakaze_battle_rig_base.png": {
                "origin": point(175, 292, "destroyer hull visual center"),
                "torpedo_mount": point(250, 230, "torpedo rack attachment area"),
                "wake_origin": point(105, 255, "rear wake source at the aft hull"),
            },
            "shimakaze_battle_torpedo_tube_01.png": {
                "origin": point(145, 138, "five-tube launcher rotation center"),
                "torpedo_port_01": point(48, 92, "upper torpedo port at red cap"),
                "torpedo_port_02": point(48, 150, "lower torpedo port at red cap"),
            },
            "shimakaze_battle_torpedo_tube_02.png": {
                "origin": point(150, 160, "five-tube launcher rotation center"),
                "torpedo_port_01": point(50, 112, "upper torpedo port at red cap"),
                "torpedo_port_02": point(50, 170, "lower torpedo port at red cap"),
            },
            "shimakaze_battle_turret_main_01.png": {
                "origin": point(145, 135, "small turret rotation center"),
                "muzzle_01": point(30, 112, "main gun muzzle"),
            },
        },
        "animation_states": {
            "idle": "shimakaze_anim_idle_keyframe.png",
            "move": "shimakaze_anim_move_keyframe.png",
            "attack": "shimakaze_anim_attack_keyframe.png",
            "hit": "shimakaze_anim_hit_keyframe.png",
            "firepower": "shimakaze_anim_firepower_keyframe.png",
        },
        "animation_sequences": {
            "idle": {"fps": 5, "loop": True},
            "move": {"fps": 8, "loop": True},
            "attack": {"fps": 11, "loop": False},
            "hit": {"fps": 10, "loop": False},
            "firepower": {"fps": 13, "loop": False},
        },
        "vfx_roles": {
            "torpedo_warning": "shimakaze_vfx_warning_fan.png",
            "torpedo_trail": "shimakaze_vfx_torpedo_trail_long.png",
            "wake_fast": "shimakaze_vfx_wake_blade.png",
            "wake_surge": "shimakaze_vfx_wake_surge.png",
            "speed_lines": "shimakaze_vfx_speed_lines.png",
            "water_impact": "shimakaze_vfx_water_impact_large.png",
        },
    },
    "aurora": {
        "ship_class": "light_cruiser",
        "battle_bind_points": {
            "aurora_battle_body_r.png": {
                "origin": point(180, 330, "battle body sea contact"),
                "rig_mount": point(170, 230, "old light-cruiser rig mount"),
                "searchlight_point": point(285, 145, "hand/searchlight direction"),
            },
            "aurora_battle_rig_base.png": {
                "origin": point(210, 260, "light cruiser rig center"),
                "turret_mount_01": point(310, 235, "forward turret mount"),
                "searchlight_mount": point(120, 130, "searchlight pedestal"),
            },
            "aurora_battle_turret_main_01.png": {
                "origin": point(150, 150, "turret rotation center"),
                "muzzle_01": point(300, 145, "main gun muzzle"),
            },
            "aurora_battle_searchlight_node.png": {
                "origin": point(120, 145, "searchlight pivot"),
                "beam_origin": point(125, 100, "light beam origin"),
            },
        },
        "animation_states": {
            "idle": "aurora_anim_idle_keyframe.png",
            "move": "aurora_anim_move_keyframe.png",
            "attack": "aurora_anim_attack_keyframe.png",
            "hit": "aurora_anim_hit_keyframe.png",
            "firepower": "aurora_anim_firepower_keyframe.png",
        },
        "animation_sequences": {
            "idle": {"fps": 5, "loop": True},
            "move": {"fps": 7, "loop": True},
            "attack": {"fps": 10, "loop": False},
            "hit": {"fps": 10, "loop": False},
            "firepower": {"fps": 12, "loop": False},
        },
        "vfx_roles": {
            "searchlight_beam": "aurora_vfx_searchlight_beam.png",
            "support_area": "aurora_vfx_command_ring.png",
            "muzzle_flash": "aurora_vfx_muzzle_flash_02.png",
            "wake": "aurora_vfx_wake.png",
            "water_splash": "aurora_vfx_water_splash.png",
            "morale_aura": "aurora_vfx_morale_aura.png",
        },
    },
    "warspite": {
        "ship_class": "battleship",
        "battle_bind_points": {
            "warspite_battle_body_r.png": {
                "origin": point(180, 350, "battle body sea contact"),
                "rig_mount": point(130, 220, "battleship rig mount"),
                "muzzle_group": point(270, 250, "side gun direction"),
            },
            "warspite_battle_rig_base.png": {
                "origin": point(170, 300, "battleship hull center"),
                "turret_mount_01": point(235, 250, "forward main turret mount"),
                "turret_mount_02": point(120, 230, "aft main turret mount"),
            },
            "warspite_battle_turret_main_01.png": {
                "origin": point(180, 175, "turret rotation center"),
                "muzzle_01": point(330, 145, "upper barrel muzzle"),
                "muzzle_02": point(295, 165, "lower barrel muzzle"),
            },
            "warspite_battle_rangefinder_node.png": {
                "origin": point(105, 300, "rangefinder pivot"),
                "scan_origin": point(55, 235, "optical scan origin"),
            },
        },
        "animation_states": {
            "idle": "warspite_anim_idle_keyframe.png",
            "move": "warspite_anim_move_keyframe.png",
            "attack": "warspite_anim_attack_keyframe.png",
            "hit": "warspite_anim_hit_keyframe.png",
            "firepower": "warspite_anim_firepower_keyframe.png",
        },
        "animation_sequences": {
            "idle": {"fps": 5, "loop": True},
            "move": {"fps": 7, "loop": True},
            "attack": {"fps": 10, "loop": False},
            "hit": {"fps": 10, "loop": False},
            "firepower": {"fps": 12, "loop": False},
        },
        "vfx_roles": {
            "heavy_muzzle": "warspite_vfx_heavy_muzzle_cone.png",
            "reticle": "warspite_vfx_reticle_main.png",
            "range_scale": "warspite_vfx_range_scale.png",
            "splash": "warspite_vfx_splash_sequence_02.png",
            "wake": "warspite_vfx_wake.png",
            "royal_area": "warspite_vfx_royal_area.png",
        },
    },
    "bismarck": {
        "ship_class": "battleship",
        "battle_bind_points": {
            "bismarck_battle_body_r.png": {
                "origin": point(136, 299, "battle body sea contact"),
                "rig_mount": point(136, 210, "heavy battleship rig mount behind torso"),
                "command_origin": point(158, 205, "flagship command gesture origin near hands"),
            },
            "bismarck_battle_rig_base.png": {
                "origin": point(290, 276, "battleship hull center"),
                "turret_mount_01": point(426, 267, "forward circular main turret socket"),
                "turret_mount_02": point(178, 222, "aft circular main turret socket"),
                "rangefinder_mount": point(264, 72, "optical rangefinder mount on superstructure"),
            },
            "bismarck_battle_turret_main_01.png": {
                "origin": point(225, 155, "twin turret rotation center"),
                "muzzle_01": point(420, 140, "far barrel muzzle"),
                "muzzle_02": point(380, 160, "near barrel muzzle"),
            },
            "bismarck_battle_turret_main_02.png": {
                "origin": point(220, 155, "twin turret rotation center"),
                "muzzle_01": point(405, 143, "far barrel muzzle"),
                "muzzle_02": point(373, 166, "near barrel muzzle"),
            },
            "bismarck_battle_rangefinder_node.png": {
                "origin": point(115, 210, "rangefinder pedestal pivot"),
                "scan_origin": point(75, 82, "optical lens and cold-white lock line origin"),
            },
            "bismarck_battle_flagship_marker_node.png": {
                "origin": point(111, 270, "flagship marker base"),
                "aura_origin": point(111, 150, "command area origin at banner center"),
            },
        },
        "animation_states": {
            "idle": "bismarck_anim_idle_keyframe.png",
            "move": "bismarck_anim_move_keyframe.png",
            "attack": "bismarck_anim_attack_keyframe.png",
            "hit": "bismarck_anim_hit_keyframe.png",
            "firepower": "bismarck_anim_firepower_keyframe.png",
        },
        "animation_sequences": {
            "idle": {"fps": 5, "loop": True},
            "move": {"fps": 7, "loop": True},
            "attack": {"fps": 10, "loop": False},
            "hit": {"fps": 10, "loop": False},
            "firepower": {"fps": 12, "loop": False},
        },
        "vfx_roles": {
            "heavy_muzzle": "bismarck_vfx_heavy_muzzle_cone.png",
            "lock_line": "bismarck_vfx_lock_line.png",
            "precision_reticle": "bismarck_vfx_precision_reticle.png",
            "range_arc": "bismarck_vfx_range_arc.png",
            "wake": "bismarck_vfx_wake.png",
            "water_impact": "bismarck_vfx_splash_large.png",
            "armor_hit": "bismarck_vfx_armor_sparks.png",
            "decisive_area": "bismarck_vfx_decisive_area.png",
        },
    },
}


def write_source_alpha(character_id: str) -> list[dict[str, Any]]:
    out_items = []
    root = CHAR_ROOT / character_id
    out_dir = root / "processed" / "source_alpha"
    out_dir.mkdir(parents=True, exist_ok=True)
    for src in sorted(root.glob("*/*.png")):
        if "processed" in src.parts:
            continue
        img = Image.open(src)
        cleaned = rgba_with_alpha_from_light_bg(img)
        out = out_dir / f"{src.stem}_alpha.png"
        cleaned.save(out)
        out_items.append({"source": rel(src), "file": rel(out), "size": list(cleaned.size), "mode": cleaned.mode})
    return out_items


def process_character(character_id: str) -> None:
    if character_id not in SPECS:
        raise SystemExit(f"Missing crop specs for character: {character_id}")
    if character_id not in CONFIGS:
        raise SystemExit(f"Missing config for character: {character_id}")
    root = CHAR_ROOT / character_id
    manifest: dict[str, Any] = {
        "character_id": character_id,
        "pipeline_stage": "postprocess_trial_sheet_v1",
        "source_alpha": write_source_alpha(character_id),
        "components": [],
    }
    opened_alpha: dict[str, Image.Image] = {}
    for spec in SPECS[character_id]:
        src_path = root / spec.source
        if spec.source not in opened_alpha:
            opened_alpha[spec.source] = rgba_with_alpha_from_light_bg(Image.open(src_path))
        out = root / spec.out_dir / spec.name
        item = save_crop(opened_alpha[spec.source], spec.box, out, spec.tags)
        item.update({"source": rel(src_path), "tags": list(spec.tags)})
        manifest["components"].append(item)

    cfg = CONFIGS[character_id]
    if "animation_sequences" in cfg:
        normalize_animation_sequence_canvases(character_id, cfg["animation_sequences"])
    config_dir = root / "processed" / "config"
    config_dir.mkdir(parents=True, exist_ok=True)

    bind_points = {
        "character_id": character_id,
        "coordinate_system": "pixel_top_left_per_split_asset",
        "notes": "Initial binding points from trial sheet postprocess; verify manually before engine import.",
        "assets": cfg["battle_bind_points"],
    }
    bind_path = config_dir / f"{character_id}_meta_bind_points.json"
    bind_path.write_text(json.dumps(bind_points, ensure_ascii=False, indent=2) + "\n")

    anim_config = {
        "character_id": character_id,
        "type": "keyframe_reference",
        "notes": "Generated keyframes are visual references, not final runtime animation curves.",
        "states": {
            state: {
                "file": f"assets/characters/{character_id}/processed/anim/{file}",
                "recommended_runtime": "split-layer tween or skeletal pass",
            }
            for state, file in cfg["animation_states"].items()
        },
    }
    if "animation_sequences" in cfg:
        anim_config["type"] = "four_frame_sequence"
        anim_config["notes"] = "Four-frame MVP body sequences. Precise weapons and gameplay VFX remain independent runtime nodes."
        for state, sequence in cfg["animation_sequences"].items():
            anim_config["states"][state] = {
                "frames": [
                    f"assets/characters/{character_id}/processed/anim/{character_id}_anim_{state}_frame_{index:02d}.png"
                    for index in range(1, 5)
                ],
                "fps": sequence["fps"],
                "loop": sequence["loop"],
                "reference_file": f"assets/characters/{character_id}/processed/anim/{cfg['animation_states'][state]}",
                "runtime_notes": "Use the four-frame body sequence; keep precise weapon rotation and VFX on independent nodes.",
            }
    anim_path = config_dir / f"{character_id}_anim_config.json"
    anim_path.write_text(json.dumps(anim_config, ensure_ascii=False, indent=2) + "\n")

    vfx_config = {
        "character_id": character_id,
        "type": "vfx_reference",
        "ship_class": cfg["ship_class"],
        "roles": {
            role: {
                "file": f"assets/characters/{character_id}/processed/vfx/{file}",
                "origin": "center unless overridden by runtime binding",
            }
            for role, file in cfg["vfx_roles"].items()
        },
    }
    vfx_path = config_dir / f"{character_id}_vfx_config.json"
    vfx_path.write_text(json.dumps(vfx_config, ensure_ascii=False, indent=2) + "\n")

    manifest["config"] = {
        "bind_points": rel(bind_path),
        "animation": rel(anim_path),
        "vfx": rel(vfx_path),
    }
    manifest_path = config_dir / f"{character_id}_postprocess_manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")


def edge_qa_preview_name(character_ids: tuple[str, ...]) -> str:
    return "edge_qa_" + "_".join(character_ids) + ".html"


def build_edge_qa_preview(character_ids: tuple[str, ...]) -> Path:
    qa_dir = CHAR_ROOT / "qa"
    qa_dir.mkdir(parents=True, exist_ok=True)
    out = qa_dir / edge_qa_preview_name(character_ids)
    css = (
        'body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;margin:0;'
        "background:#1c1e22;color:#f2f4f8}"
        "header{position:sticky;top:0;background:#111;padding:14px 20px;z-index:2;border-bottom:1px solid #333}"
        "h1{font-size:18px;margin:0}section{padding:18px 20px}h2{font-size:16px;margin:12px 0}"
        ".grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:16px}"
        ".card{border:1px solid #444;background:#252932;padding:10px;border-radius:8px}"
        ".name{font-size:12px;line-height:1.35;color:#d8dde8;word-break:break-all;margin-bottom:8px}"
        ".row{display:grid;grid-template-columns:1fr 1fr 1fr;gap:6px}"
        ".slot{height:170px;display:flex;align-items:center;justify-content:center;overflow:hidden;border:1px solid #555}"
        ".checker{background-color:#ddd;background-image:linear-gradient(45deg,#bbb 25%,transparent 25%),"
        "linear-gradient(-45deg,#bbb 25%,transparent 25%),linear-gradient(45deg,transparent 75%,#bbb 75%),"
        "linear-gradient(-45deg,transparent 75%,#bbb 75%);background-size:20px 20px;"
        "background-position:0 0,0 10px,10px -10px,-10px 0}"
        ".dark{background:#05070a}.light{background:#f8f8f2}"
        ".slot img{max-width:96%;max-height:96%;image-rendering:auto}"
        ".label{font-size:10px;text-align:center;color:#aaa;margin-top:3px}"
        ".warn{color:#ffd27d}.note{font-size:12px;color:#bac3d4;margin-top:5px}"
    )
    parts = [
        '<!doctype html><meta charset="utf-8">',
        f"<title>TinySeaWar {' '.join(character_ids)} Edge QA</title>",
        f"<style>{css}</style>",
        "<header><h1>TinySeaWar Edge QA "
        f'<span class="warn">{escape(", ".join(character_ids))} processed PNGs</span></h1>'
        '<div class="note">Embedded preview of import-ready split PNGs on checker, dark, and light backgrounds. '
        "Source alpha sheets are intentionally excluded.</div></header>",
    ]
    for character_id in character_ids:
        parts.append(f'<section><h2>{escape(character_id)}</h2><div class="grid">')
        files = [
            path
            for path in sorted((CHAR_ROOT / character_id / "processed").rglob("*.png"))
            if "source_alpha" not in path.parts
        ]
        for path in files:
            data = base64.b64encode(path.read_bytes()).decode("ascii")
            src = f"data:image/png;base64,{data}"
            label = rel(path)
            parts.append('<div class="card">')
            parts.append(f'<div class="name">{escape(label)}</div>')
            parts.append('<div class="row">')
            for class_name, label_name in (("checker", "checker"), ("dark", "dark"), ("light", "light")):
                parts.append(
                    f'<div><div class="slot {class_name}"><img src="{src}"></div>'
                    f'<div class="label">{label_name}</div></div>'
                )
            parts.append("</div></div>")
        parts.append("</div></section>")
    out.write_text("\n".join(parts), encoding="utf-8")
    return out


def main() -> None:
    args = [arg for arg in sys.argv[1:] if arg != "--preview"]
    build_preview = "--preview" in sys.argv[1:]
    character_ids = tuple(args) or ("enterprise_cv6", "hai_shih", "hindenburg", "shimakaze")
    for character_id in character_ids:
        process_character(character_id)
    if build_preview:
        preview = build_edge_qa_preview(character_ids)
        print(rel(preview))


if __name__ == "__main__":
    main()
