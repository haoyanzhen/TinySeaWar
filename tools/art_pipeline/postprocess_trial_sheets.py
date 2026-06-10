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


def point(x: int, y: int, note: str) -> dict[str, Any]:
    return {"x": x, "y": y, "note": note}


SPECS: dict[str, list[CropSpec]] = {
    "enterprise_cv6": [
        CropSpec("concept/enterprise_cv6_concept_full.png", "processed/ui", "enterprise_cv6_illust_full_alpha.png", (0, 0, 1536, 1024), ("illustration", "full_body")),
        CropSpec("ui/enterprise_cv6_illust_half.png", "processed/ui", "enterprise_cv6_illust_half_alpha.png", (0, 0, 1536, 1024), ("illustration",)),
        CropSpec("ui/enterprise_cv6_illust_skill_cutin.png", "processed/ui", "enterprise_cv6_illust_skill_cutin_alpha.png", (0, 0, 1536, 1024), ("cutin",)),
        CropSpec("ui/enterprise_cv6_ui_sheet.png", "processed/ui", "enterprise_cv6_ui_portrait.png", (40, 200, 560, 795), ("ui", "portrait")),
        CropSpec("ui/enterprise_cv6_ui_sheet.png", "processed/ui", "enterprise_cv6_ui_portrait_small.png", (625, 350, 820, 660), ("ui", "portrait_small")),
        CropSpec("ui/enterprise_cv6_ui_sheet.png", "processed/ui", "enterprise_cv6_ui_skill_airstrike.png", (1015, 285, 1490, 780), ("ui", "skill")),
        CropSpec("battle/enterprise_cv6_battle_asset_sheet.png", "processed/battle", "enterprise_cv6_battle_body_r.png", (40, 70, 500, 460), ("battle", "body")),
        CropSpec("battle/enterprise_cv6_battle_asset_sheet.png", "processed/battle", "enterprise_cv6_battle_rig_base.png", (535, 90, 1485, 455), ("battle", "rig")),
        CropSpec("battle/enterprise_cv6_battle_asset_sheet.png", "processed/battle", "enterprise_cv6_battle_aircraft_01.png", (85, 505, 310, 625), ("battle", "aircraft")),
        CropSpec("battle/enterprise_cv6_battle_asset_sheet.png", "processed/battle", "enterprise_cv6_battle_aircraft_02.png", (400, 505, 640, 630), ("battle", "aircraft")),
        CropSpec("battle/enterprise_cv6_battle_asset_sheet.png", "processed/battle", "enterprise_cv6_battle_aircraft_03.png", (710, 505, 950, 625), ("battle", "aircraft")),
        CropSpec("battle/enterprise_cv6_battle_asset_sheet.png", "processed/battle", "enterprise_cv6_battle_aircraft_04.png", (1080, 505, 1320, 625), ("battle", "aircraft")),
        CropSpec("battle/enterprise_cv6_battle_asset_sheet.png", "processed/vfx", "enterprise_cv6_vfx_airstrike_marker_blue.png", (95, 665, 340, 765), ("vfx", "area")),
        CropSpec("battle/enterprise_cv6_battle_asset_sheet.png", "processed/vfx", "enterprise_cv6_vfx_airstrike_marker_gold.png", (420, 665, 665, 765), ("vfx", "area")),
        CropSpec("battle/enterprise_cv6_battle_asset_sheet.png", "processed/vfx", "enterprise_cv6_vfx_wake_fast.png", (40, 835, 350, 960), ("vfx", "wake")),
        CropSpec("battle/enterprise_cv6_battle_asset_sheet.png", "processed/vfx", "enterprise_cv6_vfx_wake_turn.png", (360, 805, 620, 945), ("vfx", "wake")),
        CropSpec("vfx/enterprise_cv6_vfx_reference_sheet.png", "processed/vfx", "enterprise_cv6_vfx_aircraft_beam_single.png", (80, 90, 660, 220), ("vfx", "aircraft_path")),
        CropSpec("vfx/enterprise_cv6_vfx_reference_sheet.png", "processed/vfx", "enterprise_cv6_vfx_aircraft_path_arc.png", (760, 45, 1465, 215), ("vfx", "aircraft_path")),
        CropSpec("vfx/enterprise_cv6_vfx_reference_sheet.png", "processed/vfx", "enterprise_cv6_vfx_aircraft_formation_trails.png", (95, 290, 650, 405), ("vfx", "aircraft_path")),
        CropSpec("vfx/enterprise_cv6_vfx_reference_sheet.png", "processed/vfx", "enterprise_cv6_vfx_aircraft_path_arrows.png", (745, 230, 1465, 430), ("vfx", "aircraft_path")),
        CropSpec("vfx/enterprise_cv6_vfx_reference_sheet.png", "processed/vfx", "enterprise_cv6_vfx_airstrike_area.png", (80, 445, 650, 620), ("vfx", "area")),
        CropSpec("vfx/enterprise_cv6_vfx_reference_sheet.png", "processed/vfx", "enterprise_cv6_vfx_deck_lane.png", (785, 450, 1440, 590), ("vfx", "deck_lane")),
        CropSpec("vfx/enterprise_cv6_vfx_reference_sheet.png", "processed/vfx", "enterprise_cv6_vfx_water_splash.png", (70, 660, 680, 760), ("vfx", "splash")),
        CropSpec("vfx/enterprise_cv6_vfx_reference_sheet.png", "processed/vfx", "enterprise_cv6_vfx_hit_sparks.png", (760, 655, 1405, 790), ("vfx", "hit")),
        CropSpec("battle/enterprise_cv6_anim_keyframes_sheet.png", "processed/anim", "enterprise_cv6_anim_idle_keyframe.png", (0, 30, 590, 445), ("anim", "idle")),
        CropSpec("battle/enterprise_cv6_anim_keyframes_sheet.png", "processed/anim", "enterprise_cv6_anim_move_keyframe.png", (590, 120, 1100, 445), ("anim", "move")),
        CropSpec("battle/enterprise_cv6_anim_keyframes_sheet.png", "processed/anim", "enterprise_cv6_anim_attack_keyframe.png", (1120, 45, 1770, 445), ("anim", "attack")),
        CropSpec("battle/enterprise_cv6_anim_keyframes_sheet.png", "processed/anim", "enterprise_cv6_anim_hit_keyframe.png", (180, 455, 810, 885), ("anim", "hit")),
        CropSpec("battle/enterprise_cv6_anim_keyframes_sheet.png", "processed/anim", "enterprise_cv6_anim_firepower_keyframe.png", (825, 435, 1670, 887), ("anim", "firepower")),
    ],
    "hai_shih": [
        CropSpec("concept/hai_shih_concept_full.png", "processed/ui", "hai_shih_illust_full_alpha.png", (0, 0, 1024, 1536), ("illustration", "full_body")),
        CropSpec("ui/hai_shih_illust_half.png", "processed/ui", "hai_shih_illust_half_alpha.png", (0, 0, 1024, 1536), ("illustration",)),
        CropSpec("ui/hai_shih_illust_skill_cutin.png", "processed/ui", "hai_shih_illust_skill_cutin_alpha.png", (0, 0, 1717, 916), ("cutin",)),
        CropSpec("ui/hai_shih_ui_sheet.png", "processed/ui", "hai_shih_ui_portrait.png", (10, 0, 520, 615), ("ui", "portrait")),
        CropSpec("ui/hai_shih_ui_sheet.png", "processed/ui", "hai_shih_ui_portrait_small.png", (600, 160, 885, 455), ("ui", "portrait_small")),
        CropSpec("ui/hai_shih_ui_sheet.png", "processed/ui", "hai_shih_ui_chibi_head.png", (1035, 135, 1360, 455), ("ui", "chibi")),
        CropSpec("ui/hai_shih_ui_sheet.png", "processed/ui", "hai_shih_expr_default.png", (105, 650, 380, 960), ("ui", "expression")),
        CropSpec("ui/hai_shih_ui_sheet.png", "processed/ui", "hai_shih_expr_serious.png", (470, 620, 760, 970), ("ui", "expression", "serious")),
        CropSpec("ui/hai_shih_ui_sheet.png", "processed/ui", "hai_shih_ui_skill_torpedo.png", (840, 625, 1120, 925), ("ui", "skill")),
        CropSpec("ui/hai_shih_ui_sheet.png", "processed/ui", "hai_shih_ui_class_submarine.png", (1190, 620, 1465, 925), ("ui", "class_icon")),
        CropSpec("battle/hai_shih_battle_asset_sheet.png", "processed/battle", "hai_shih_battle_body_r.png", (60, 130, 540, 455), ("battle", "body")),
        CropSpec("battle/hai_shih_battle_asset_sheet.png", "processed/battle", "hai_shih_battle_rig_base.png", (630, 180, 1080, 440), ("battle", "rig")),
        CropSpec("battle/hai_shih_battle_asset_sheet.png", "processed/battle", "hai_shih_battle_torpedo_tube_01.png", (1205, 85, 1450, 250), ("battle", "torpedo")),
        CropSpec("battle/hai_shih_battle_asset_sheet.png", "processed/battle", "hai_shih_battle_periscope_node.png", (1215, 285, 1365, 500), ("battle", "periscope")),
        CropSpec("battle/hai_shih_battle_asset_sheet.png", "processed/battle", "hai_shih_battle_sonar_node.png", (1200, 520, 1390, 760), ("battle", "sonar")),
        CropSpec("battle/hai_shih_battle_asset_sheet.png", "processed/vfx", "hai_shih_vfx_wake_strip.png", (40, 590, 710, 735), ("vfx", "wake")),
        CropSpec("battle/hai_shih_battle_asset_sheet.png", "processed/vfx", "hai_shih_vfx_underwater_shadow.png", (45, 745, 690, 900), ("vfx", "shadow")),
        CropSpec("battle/hai_shih_battle_asset_sheet.png", "processed/vfx", "hai_shih_vfx_bubbles_01.png", (765, 745, 875, 920), ("vfx", "bubble")),
        CropSpec("battle/hai_shih_battle_asset_sheet.png", "processed/vfx", "hai_shih_vfx_bubbles_02.png", (930, 730, 1075, 930), ("vfx", "bubble")),
        CropSpec("battle/hai_shih_battle_asset_sheet.png", "processed/vfx", "hai_shih_vfx_bubbles_03.png", (1100, 710, 1270, 930), ("vfx", "bubble")),
        CropSpec("battle/hai_shih_battle_asset_sheet.png", "processed/vfx", "hai_shih_vfx_bubbles_04.png", (1300, 705, 1490, 930), ("vfx", "bubble")),
        CropSpec("vfx/hai_shih_vfx_reference_sheet.png", "processed/vfx", "hai_shih_vfx_torpedo_trail.png", (60, 50, 1260, 190), ("vfx", "torpedo")),
        CropSpec("vfx/hai_shih_vfx_reference_sheet.png", "processed/vfx", "hai_shih_vfx_torpedo_launch_flash.png", (55, 305, 570, 455), ("vfx", "torpedo")),
        CropSpec("vfx/hai_shih_vfx_reference_sheet.png", "processed/vfx", "hai_shih_vfx_sonar_pulse.png", (590, 225, 950, 560), ("vfx", "sonar")),
        CropSpec("vfx/hai_shih_vfx_reference_sheet.png", "processed/vfx", "hai_shih_vfx_bubble_trail.png", (1100, 270, 1450, 470), ("vfx", "bubble")),
        CropSpec("vfx/hai_shih_vfx_reference_sheet.png", "processed/vfx", "hai_shih_vfx_shadow_fade.png", (65, 530, 760, 720), ("vfx", "shadow")),
        CropSpec("vfx/hai_shih_vfx_reference_sheet.png", "processed/vfx", "hai_shih_vfx_periscope_glint.png", (1070, 500, 1320, 730), ("vfx", "periscope")),
        CropSpec("vfx/hai_shih_vfx_reference_sheet.png", "processed/vfx", "hai_shih_vfx_water_ripple.png", (85, 790, 620, 960), ("vfx", "ripple")),
        CropSpec("vfx/hai_shih_vfx_reference_sheet.png", "processed/vfx", "hai_shih_vfx_stealth_shimmer.png", (850, 800, 1380, 965), ("vfx", "stealth")),
        CropSpec("battle/hai_shih_anim_keyframes_sheet.png", "processed/anim", "hai_shih_anim_idle_keyframe.png", (80, 50, 600, 410), ("anim", "idle")),
        CropSpec("battle/hai_shih_anim_keyframes_sheet.png", "processed/anim", "hai_shih_anim_move_keyframe.png", (610, 120, 1120, 410), ("anim", "move")),
        CropSpec("battle/hai_shih_anim_keyframes_sheet.png", "processed/anim", "hai_shih_anim_attack_keyframe.png", (1220, 40, 1750, 405), ("anim", "attack")),
        CropSpec("battle/hai_shih_anim_keyframes_sheet.png", "processed/anim", "hai_shih_anim_hit_keyframe.png", (330, 430, 845, 850), ("anim", "hit")),
        CropSpec("battle/hai_shih_anim_keyframes_sheet.png", "processed/anim", "hai_shih_anim_firepower_keyframe.png", (900, 490, 1700, 820), ("anim", "firepower")),
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
    ],
}


CONFIGS: dict[str, dict[str, Any]] = {
    "enterprise_cv6": {
        "ship_class": "carrier",
        "battle_bind_points": {
            "enterprise_cv6_battle_body_r.png": {
                "origin": point(226, 322, "battle body ground/sea contact"),
                "rig_mount": point(95, 210, "left-side rig mount from source sheet crop"),
            },
            "enterprise_cv6_battle_rig_base.png": {
                "origin": point(475, 270, "carrier rig center"),
                "aircraft_launch_01": point(795, 110, "forward deck launch lane"),
                "aircraft_launch_02": point(650, 150, "mid deck launch lane"),
                "aircraft_recovery": point(190, 150, "rear recovery lane"),
            },
        },
        "animation_states": {
            "idle": "enterprise_cv6_anim_idle_keyframe.png",
            "move": "enterprise_cv6_anim_move_keyframe.png",
            "attack": "enterprise_cv6_anim_attack_keyframe.png",
            "hit": "enterprise_cv6_anim_hit_keyframe.png",
            "firepower": "enterprise_cv6_anim_firepower_keyframe.png",
        },
        "vfx_roles": {
            "airstrike_area": "enterprise_cv6_vfx_airstrike_area.png",
            "aircraft_path": "enterprise_cv6_vfx_aircraft_path_arrows.png",
            "deck_lane": "enterprise_cv6_vfx_deck_lane.png",
            "wake": "enterprise_cv6_vfx_wake_fast.png",
            "hit": "enterprise_cv6_vfx_hit_sparks.png",
        },
    },
    "hai_shih": {
        "ship_class": "submarine",
        "battle_bind_points": {
            "hai_shih_battle_body_r.png": {
                "origin": point(250, 245, "battle body waterline center"),
                "torpedo_port": point(460, 205, "front torpedo direction"),
                "wake_origin": point(55, 255, "rear wake source"),
            },
            "hai_shih_battle_rig_base.png": {
                "origin": point(235, 165, "submarine hull center"),
                "torpedo_port": point(415, 145, "front torpedo tube"),
                "periscope_point": point(240, 36, "periscope mast top"),
                "sonar_origin": point(415, 145, "front sonar/guide light"),
            },
            "hai_shih_battle_torpedo_tube_01.png": {
                "origin": point(122, 79, "tube center"),
                "torpedo_port": point(224, 78, "launch muzzle"),
            },
        },
        "animation_states": {
            "idle": "hai_shih_anim_idle_keyframe.png",
            "move": "hai_shih_anim_move_keyframe.png",
            "attack": "hai_shih_anim_attack_keyframe.png",
            "hit": "hai_shih_anim_hit_keyframe.png",
            "firepower": "hai_shih_anim_firepower_keyframe.png",
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
                "origin": point(260, 325, "battle body sea contact"),
                "rig_mount": point(135, 210, "rear heavy-cruiser rig mount"),
                "fire_control_point": point(340, 155, "rangefinder visor direction"),
            },
            "hindenburg_battle_rig_base.png": {
                "origin": point(250, 315, "heavy cruiser rig center"),
                "turret_mount_01": point(405, 235, "front heavy turret mount"),
                "fire_control_point": point(320, 105, "central fire-control tower"),
            },
            "hindenburg_battle_turret_main_01.png": {
                "origin": point(165, 105, "turret rotation center"),
                "muzzle_01": point(300, 72, "upper barrel muzzle"),
                "muzzle_02": point(300, 115, "lower barrel muzzle"),
            },
            "hindenburg_battle_fire_control_node.png": {
                "origin": point(92, 86, "fire-control node center"),
                "scan_origin": point(112, 78, "optical scan origin"),
            },
        },
        "animation_states": {
            "idle": "hindenburg_anim_idle_keyframe.png",
            "move": "hindenburg_anim_move_keyframe.png",
            "attack": "hindenburg_anim_attack_keyframe.png",
            "hit": "hindenburg_anim_hit_keyframe.png",
            "firepower": "hindenburg_anim_firepower_keyframe.png",
        },
        "vfx_roles": {
            "reticle": "hindenburg_vfx_reticle_02.png",
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
                "origin": point(185, 300, "battle body sea contact"),
                "torpedo_mount": point(75, 210, "carried torpedo launcher mount"),
                "wake_origin": point(35, 260, "rear high-speed wake source"),
            },
            "shimakaze_battle_rig_base.png": {
                "origin": point(300, 230, "destroyer rig center"),
                "torpedo_mount": point(470, 165, "torpedo rack mount"),
                "wake_origin": point(90, 235, "rear wake source"),
            },
            "shimakaze_battle_torpedo_tube_01.png": {
                "origin": point(120, 72, "torpedo tube rotation center"),
                "torpedo_port_01": point(225, 58, "upper torpedo port"),
                "torpedo_port_02": point(225, 92, "lower torpedo port"),
            },
            "shimakaze_battle_turret_main_01.png": {
                "origin": point(72, 76, "small turret rotation center"),
                "muzzle_01": point(135, 66, "main gun muzzle"),
            },
        },
        "animation_states": {
            "idle": "shimakaze_anim_idle_keyframe.png",
            "move": "shimakaze_anim_move_keyframe.png",
            "attack": "shimakaze_anim_attack_keyframe.png",
            "hit": "shimakaze_anim_hit_keyframe.png",
            "firepower": "shimakaze_anim_firepower_keyframe.png",
        },
        "vfx_roles": {
            "torpedo_warning": "shimakaze_vfx_warning_line_long.png",
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
                "origin": point(190, 305, "battle body sea contact"),
                "rig_mount": point(80, 215, "old light-cruiser rig mount"),
                "searchlight_point": point(310, 150, "hand/searchlight direction"),
            },
            "aurora_battle_rig_base.png": {
                "origin": point(235, 250, "light cruiser rig center"),
                "turret_mount_01": point(410, 175, "forward turret mount"),
                "searchlight_mount": point(110, 110, "searchlight pedestal"),
            },
            "aurora_battle_turret_main_01.png": {
                "origin": point(84, 74, "turret rotation center"),
                "muzzle_01": point(165, 70, "main gun muzzle"),
            },
            "aurora_battle_searchlight_node.png": {
                "origin": point(93, 88, "searchlight pivot"),
                "beam_origin": point(92, 82, "light beam origin"),
            },
        },
        "animation_states": {
            "idle": "aurora_anim_idle_keyframe.png",
            "move": "aurora_anim_move_keyframe.png",
            "attack": "aurora_anim_attack_keyframe.png",
            "hit": "aurora_anim_hit_keyframe.png",
            "firepower": "aurora_anim_firepower_keyframe.png",
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
                "origin": point(190, 275, "battle body sea contact"),
                "rig_mount": point(90, 190, "battleship rig mount"),
                "muzzle_group": point(310, 185, "side gun direction"),
            },
            "warspite_battle_rig_base.png": {
                "origin": point(430, 285, "battleship hull center"),
                "turret_mount_01": point(470, 185, "forward main turret mount"),
                "turret_mount_02": point(710, 180, "aft main turret mount"),
            },
            "warspite_battle_turret_main_01.png": {
                "origin": point(115, 80, "turret rotation center"),
                "muzzle_01": point(220, 68, "upper barrel muzzle"),
                "muzzle_02": point(220, 102, "lower barrel muzzle"),
            },
            "warspite_battle_rangefinder_node.png": {
                "origin": point(65, 82, "rangefinder pivot"),
                "scan_origin": point(70, 55, "optical scan origin"),
            },
        },
        "animation_states": {
            "idle": "warspite_anim_idle_keyframe.png",
            "move": "warspite_anim_move_keyframe.png",
            "attack": "warspite_anim_attack_keyframe.png",
            "hit": "warspite_anim_hit_keyframe.png",
            "firepower": "warspite_anim_firepower_keyframe.png",
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
