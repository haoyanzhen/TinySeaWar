from __future__ import annotations

from collections import deque
import argparse
import json
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw

import character_roster


ROOT = Path(__file__).resolve().parents[2]
CHAR_ROOT = ROOT / "assets" / "characters"
QA_ROOT = CHAR_ROOT / "qa"
ALPHA_THRESHOLD = 12
OUTPUT_PADDING = 24

UI_SLOT_NAMES = (
    "ui_portrait",
    "ui_portrait_small",
    "ui_chibi_head",
    "expr_default",
    "expr_serious",
    "expr_hit",
    "ui_skill",
)

ANIMATION_STATES = {
    "idle": {"fps": 5, "loop": True},
    "move": {"fps": 7, "loop": True},
    "attack": {"fps": 10, "loop": False},
    "hit": {"fps": 10, "loop": False},
    "firepower": {"fps": 12, "loop": False},
}

SKILL_ROLE_BY_CLASS = {
    "destroyer": "torpedo_rush",
    "light_cruiser": "escort_barrage",
    "heavy_cruiser": "fire_control",
    "battleship": "main_gun_salvo",
    "carrier": "airstrike",
    "submarine": "torpedo_ambush",
}

BATTLE_GRID_ROLES = {
    "destroyer": (
        "battle_body_r", "battle_rig_base", "battle_turret_main_01", "battle_torpedo_tube_01",
        "battle_torpedo_tube_02", "battle_propulsion_node", "battle_radar_node", "battle_wake_origin_marker",
    ),
    "light_cruiser": (
        "battle_body_r", "battle_rig_base", "battle_turret_main_01", "battle_turret_main_02",
        "battle_aa_center", "battle_radar_node", "battle_support_node", "battle_wake_origin_marker",
    ),
    "heavy_cruiser": (
        "battle_body_r", "battle_rig_base", "battle_turret_main_01", "battle_turret_main_02",
        "battle_turret_main_03", "battle_fire_control_node", "battle_turret_secondary_01", "battle_wake_origin_marker",
    ),
    "battleship": (
        "battle_body_r", "battle_rig_base", "battle_turret_main_01", "battle_turret_main_02",
        "battle_turret_main_03", "battle_fire_control_node", "battle_flagship_marker", "battle_wake_origin_marker",
    ),
    "carrier": (
        "battle_body_r", "battle_rig_base", "battle_flight_deck", "battle_aircraft_group_01",
        "battle_aircraft_launch_marker", "battle_aircraft_recovery_marker", "battle_radar_node", "battle_wake_origin_marker",
    ),
    "submarine": (
        "battle_body_r", "battle_rig_base", "battle_torpedo_tube_01", "battle_periscope_node",
        "battle_sonar_node", "battle_dive_plane", "battle_submerged_shadow", "battle_wake_origin_marker",
    ),
}

VFX_ROLES_BY_CLASS = {
    "destroyer": ("speed_wake", "torpedo_warning", "torpedo_launch_flash", "speed_lines", "water_splash", "smoke_screen", "skill_aura", "range_reticle"),
    "light_cruiser": ("aa_burst", "aa_circle", "muzzle_flash_medium", "shell_trail", "water_splash", "armor_sparks", "escort_aura", "wake_medium"),
    "heavy_cruiser": ("fire_control_lock_line", "muzzle_flash_large", "broadside_smoke", "shell_trail_heavy", "water_splash_large", "armor_sparks", "suppression_aura", "wake_heavy"),
    "battleship": ("fire_control_lock_line", "muzzle_flash_large", "broadside_smoke", "shell_trail_heavy", "water_splash_large", "armor_sparks", "command_aura", "wake_heavy"),
    "carrier": ("aircraft_path", "aircraft_launch_flash", "aircraft_formation", "aircraft_explosion", "airstrike_area", "aircraft_recovery", "aa_burst", "wake_carrier"),
    "submarine": ("bubble_trail", "sonar_pulse", "torpedo_launch_flash", "torpedo_trail", "underwater_shadow", "periscope_glint", "dive_ripple", "wake_subtle"),
}


def source_paths(character_id: str) -> dict[str, Path]:
    root = CHAR_ROOT / character_id
    paths = {
        "concept_full": root / "concept" / f"{character_id}_concept_full.png",
        "half_body": root / "ui" / f"{character_id}_illust_half.png",
        "skill_cutin": root / "ui" / f"{character_id}_illust_skill_cutin.png",
        "ui_sheet": root / "ui" / f"{character_id}_ui_sheet.png",
        "battle_sheet": root / "battle" / f"{character_id}_battle_asset_sheet.png",
        "battle_grid": root / "battle" / f"{character_id}_battle_asset_grid.png",
        "vfx_sheet": root / "vfx" / f"{character_id}_vfx_reference_sheet.png",
        "anim_master": root / "battle" / f"{character_id}_anim_5x4_master.png",
    }
    for state in ANIMATION_STATES:
        paths[f"anim_{state}"] = root / "battle" / f"{character_id}_anim_{state}_4f_sheet.png"
    return paths


def can_process(character_id: str) -> bool:
    paths = source_paths(character_id)
    required = ("concept_full", "ui_sheet", "vfx_sheet")
    if not all(paths[key].exists() for key in required):
        return False
    if not (paths["battle_grid"].exists() or paths["battle_sheet"].exists()):
        return False
    return paths["anim_master"].exists() or all(paths[f"anim_{state}"].exists() for state in ANIMATION_STATES)


def ensure_dirs(character_id: str) -> dict[str, Path]:
    root = CHAR_ROOT / character_id / "processed"
    dirs = {
        "root": root,
        "source_alpha": root / "source_alpha",
        "ui": root / "ui",
        "battle": root / "battle",
        "anim": root / "anim",
        "vfx": root / "vfx",
        "config": root / "config",
    }
    for path in dirs.values():
        path.mkdir(parents=True, exist_ok=True)
    return dirs


def remove_green_background(path: Path) -> Image.Image:
    img = Image.open(path).convert("RGBA")
    pixels = img.load()
    width, height = img.size
    mask = bytearray(width * height)
    queue: deque[tuple[int, int]] = deque()

    def is_green(x: int, y: int) -> bool:
        r, g, b, a = pixels[x, y]
        return a > 0 and g >= 105 and g > r + 30 and g > b + 30

    def enqueue(x: int, y: int) -> None:
        index = y * width + x
        if mask[index] or not is_green(x, y):
            return
        mask[index] = 1
        queue.append((x, y))

    for x in range(width):
        enqueue(x, 0)
        enqueue(x, height - 1)
    for y in range(height):
        enqueue(0, y)
        enqueue(width - 1, y)

    while queue:
        x, y = queue.popleft()
        r, g, b, _a = pixels[x, y]
        pixels[x, y] = (r, g, b, 0)
        if x > 0:
            enqueue(x - 1, y)
        if x + 1 < width:
            enqueue(x + 1, y)
        if y > 0:
            enqueue(x, y - 1)
        if y + 1 < height:
            enqueue(x, y + 1)

    # Hair, portrait frames, and rigging can enclose islands of the source key
    # color that are not connected to the canvas edge. Generated source sheets
    # therefore reserve bright green exclusively for chroma keying; clear any
    # remaining high-confidence key pixels while preserving darker teal/green art.
    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]
            if a > 0 and g >= 150 and g > r + 70 and g > b + 70:
                pixels[x, y] = (r, g, b, 0)
    return img


def alpha_bbox(img: Image.Image) -> tuple[int, int, int, int] | None:
    return img.getchannel("A").point(lambda value: 255 if value >= ALPHA_THRESHOLD else 0).getbbox()


def center_alpha_with_padding(img: Image.Image, pad: int) -> Image.Image:
    bbox = alpha_bbox(img)
    if bbox is None:
        return img
    alpha = img.getchannel("A")
    pixels = alpha.load()
    weighted_x = 0
    weighted_y = 0
    weight = 0
    left, top, right, bottom = bbox
    for y in range(top, bottom):
        for x in range(left, right):
            value = pixels[x, y]
            if value < ALPHA_THRESHOLD:
                continue
            weighted_x += x * value
            weighted_y += y * value
            weight += value
    if weight == 0:
        return img
    centroid_x = weighted_x / weight
    centroid_y = weighted_y / weight
    half_width = int(max(centroid_x - left, right - centroid_x) + pad + 0.999)
    half_height = int(max(centroid_y - top, bottom - centroid_y) + pad + 0.999)
    canvas = Image.new("RGBA", (max(2, half_width * 2), max(2, half_height * 2)), (0, 0, 0, 0))
    target_x = canvas.width / 2
    target_y = canvas.height / 2
    canvas.alpha_composite(img, (round(target_x - centroid_x), round(target_y - centroid_y)))
    return canvas


def crop_with_padding(img: Image.Image, pad: int = OUTPUT_PADDING) -> tuple[Image.Image, dict[str, Any]]:
    bbox = alpha_bbox(img)
    if bbox is None:
        return img, {"content_bbox": None, "padding": None}
    left, top, right, bottom = bbox
    left = max(0, left - pad)
    top = max(0, top - pad)
    right = min(img.width, right + pad)
    bottom = min(img.height, bottom + pad)
    cropped = center_alpha_with_padding(img.crop((left, top, right, bottom)), pad)
    margins = alpha_margins(cropped)
    return cropped, {
        "content_bbox": list(bbox),
        "final_crop_box": [left, top, right, bottom],
        "output_edge_margins": margins,
    }


def keep_largest_alpha_component(img: Image.Image) -> Image.Image:
    components = connected_components(img, min_area=1)
    if not components:
        return img
    keep_box = components[0]["bbox"]
    alpha = img.getchannel("A")
    pixels = alpha.load()
    width, height = alpha.size
    seen: set[tuple[int, int]] = set()
    keep_pixels: set[tuple[int, int]] = set()
    left, top, right, bottom = keep_box
    for y in range(top, bottom):
        for x in range(left, right):
            if pixels[x, y] < ALPHA_THRESHOLD or (x, y) in seen:
                continue
            q: deque[tuple[int, int]] = deque([(x, y)])
            current: set[tuple[int, int]] = set()
            seen.add((x, y))
            while q:
                cx, cy = q.popleft()
                current.add((cx, cy))
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if (
                        0 <= nx < width
                        and 0 <= ny < height
                        and (nx, ny) not in seen
                        and pixels[nx, ny] >= ALPHA_THRESHOLD
                    ):
                        seen.add((nx, ny))
                        q.append((nx, ny))
            if len(current) == components[0]["area"]:
                keep_pixels = current
                break
        if keep_pixels:
            break
    if not keep_pixels:
        return img
    out = img.copy()
    out_pixels = out.load()
    for y in range(height):
        for x in range(width):
            if pixels[x, y] >= ALPHA_THRESHOLD and (x, y) not in keep_pixels:
                r, g, b, _a = out_pixels[x, y]
                out_pixels[x, y] = (r, g, b, 0)
    return out


def alpha_margins(img: Image.Image) -> dict[str, int] | None:
    bbox = alpha_bbox(img)
    if bbox is None:
        return None
    left, top, right, bottom = bbox
    return {
        "left": left,
        "top": top,
        "right": img.width - right,
        "bottom": img.height - bottom,
    }


def save_image(img: Image.Image, path: Path) -> dict[str, Any]:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)
    return {
        "path": str(path.relative_to(ROOT)),
        "size": list(img.size),
        "edge_margins": alpha_margins(img),
    }


def split_grid(img: Image.Image, rows: int, cols: int) -> list[Image.Image]:
    width, height = img.size
    cell_width = width // cols
    cell_height = height // rows
    cells: list[Image.Image] = []
    for row in range(rows):
        for col in range(cols):
            left = col * cell_width
            top = row * cell_height
            right = width if col == cols - 1 else (col + 1) * cell_width
            bottom = height if row == rows - 1 else (row + 1) * cell_height
            cells.append(img.crop((left, top, right, bottom)))
    return cells


def connected_components(img: Image.Image, min_area: int = 800) -> list[dict[str, Any]]:
    alpha = img.getchannel("A")
    pixels = alpha.load()
    width, height = alpha.size
    seen: set[tuple[int, int]] = set()
    components: list[dict[str, Any]] = []
    for y in range(height):
        for x in range(width):
            if (x, y) in seen or pixels[x, y] < ALPHA_THRESHOLD:
                continue
            q: deque[tuple[int, int]] = deque([(x, y)])
            seen.add((x, y))
            xs: list[int] = []
            ys: list[int] = []
            while q:
                cx, cy = q.popleft()
                xs.append(cx)
                ys.append(cy)
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if (
                        0 <= nx < width
                        and 0 <= ny < height
                        and (nx, ny) not in seen
                        and pixels[nx, ny] >= ALPHA_THRESHOLD
                    ):
                        seen.add((nx, ny))
                        q.append((nx, ny))
            area = len(xs)
            if area >= min_area:
                bbox = (min(xs), min(ys), max(xs) + 1, max(ys) + 1)
                components.append({"area": area, "bbox": bbox})
    return sorted(components, key=lambda item: item["area"], reverse=True)


def crop_component(img: Image.Image, component: dict[str, Any], pad: int = OUTPUT_PADDING) -> tuple[Image.Image, dict[str, Any]]:
    left, top, right, bottom = component["bbox"]
    left = max(0, left - pad)
    top = max(0, top - pad)
    right = min(img.width, right + pad)
    bottom = min(img.height, bottom + pad)
    cropped = center_alpha_with_padding(img.crop((left, top, right, bottom)), pad)
    return cropped, {
        "component_bbox": list(component["bbox"]),
        "final_crop_box": [left, top, right, bottom],
        "component_area": component["area"],
        "output_edge_margins": alpha_margins(cropped),
    }


def battle_roles_for_components(components: list[dict[str, Any]], ship_class: str) -> list[tuple[str, dict[str, Any]]]:
    if ship_class == "battleship":
        roles: list[tuple[str, dict[str, Any]]] = []
        body = next((item for item in components if item["bbox"][0] < 500 and item["bbox"][1] < 560), None)
        rig = next((item for item in components if item["bbox"][0] < 600 and item["bbox"][1] >= 560), None)
        turrets = sorted(
            [item for item in components if item["bbox"][1] < 520 and item["bbox"][0] >= 430],
            key=lambda item: item["bbox"][0],
        )[:3]
        secondary = next(
            (item for item in components if 560 <= item["bbox"][1] and 560 <= item["bbox"][0] < 930),
            None,
        )
        fire_control = next(
            (item for item in components if 560 <= item["bbox"][1] and 900 <= item["bbox"][0] < 1180),
            None,
        )
        marker = next((item for item in components if item["bbox"][0] >= 1150 and item["bbox"][1] < 760), None)
        wake = next((item for item in components if item["bbox"][0] >= 1150 and item["bbox"][1] >= 720), None)
        if body:
            roles.append(("battle_body_r", body))
        if rig:
            roles.append(("battle_rig_base", rig))
        for index, component in enumerate(turrets, start=1):
            roles.append((f"battle_turret_main_{index:02d}", component))
        if secondary:
            roles.append(("battle_turret_secondary_01", secondary))
        if fire_control:
            roles.append(("battle_fire_control_node", fire_control))
        if marker:
            roles.append(("battle_flagship_marker", marker))
        if wake:
            roles.append(("battle_wake_origin_marker", wake))
        return roles

    fallback_roles = ["battle_body_r", "battle_rig_base", "battle_turret_main_01", "battle_weapon_main_02"]
    return [(role, component) for role, component in zip(fallback_roles, components)]


def point_near_center(img: Image.Image) -> dict[str, int]:
    bbox = alpha_bbox(img)
    if bbox is None:
        return {"x": img.width // 2, "y": img.height // 2}
    left, top, right, bottom = bbox
    center_x = (left + right) // 2
    center_y = (top + bottom) // 2
    alpha = img.getchannel("A")
    pixels = alpha.load()
    if pixels[center_x, center_y] >= ALPHA_THRESHOLD:
        return {"x": center_x, "y": center_y}
    best: tuple[int, int, int] | None = None
    for y in range(top, bottom):
        for x in range(left, right):
            if pixels[x, y] < ALPHA_THRESHOLD:
                continue
            distance = (x - center_x) ** 2 + (y - center_y) ** 2
            if best is None or distance < best[0]:
                best = (distance, x, y)
    if best is None:
        return {"x": center_x, "y": center_y}
    return {"x": best[1], "y": best[2]}


def point_near_right_edge(img: Image.Image) -> dict[str, int]:
    alpha = img.getchannel("A")
    pixels = alpha.load()
    rightmost: list[tuple[int, int]] = []
    max_x = -1
    for y in range(alpha.height):
        for x in range(alpha.width):
            if pixels[x, y] < ALPHA_THRESHOLD:
                continue
            if x > max_x:
                max_x = x
                rightmost = [(x, y)]
            elif x == max_x:
                rightmost.append((x, y))
    if not rightmost:
        return {"x": img.width // 2, "y": img.height // 2}
    y_values = sorted(point[1] for point in rightmost)
    return {"x": max_x, "y": y_values[len(y_values) // 2]}


def derive_half_and_cutin(full: Image.Image) -> tuple[Image.Image, Image.Image]:
    bbox = alpha_bbox(full)
    if bbox is None:
        return full.copy(), full.copy()
    left, top, right, bottom = bbox
    subject_height = bottom - top
    half_bottom = min(full.height, top + int(subject_height * 0.72))
    half, _meta = crop_with_padding(full.crop((0, 0, full.width, half_bottom)), pad=16)

    cut_bottom = min(full.height, top + int(subject_height * 0.58))
    cut_source = full.crop((0, top, full.width, cut_bottom))
    cutin, _meta = crop_with_padding(cut_source, pad=16)
    target_width = max(cutin.width, int(cutin.height * 1.8))
    canvas = Image.new("RGBA", (target_width, cutin.height), (0, 0, 0, 0))
    canvas.alpha_composite(cutin, ((target_width - cutin.width) // 2, 0))
    return half, canvas


def battle_points(role: str, img: Image.Image) -> dict[str, dict[str, int]]:
    points = {"pivot": point_near_center(img)}
    if "turret" in role:
        points["muzzle_01"] = point_near_right_edge(img)
    if "torpedo_tube" in role:
        points["torpedo_port_01"] = point_near_right_edge(img)
    if role == "battle_rig_base":
        points["rig_mount"] = point_near_center(img)
    if role == "battle_wake_origin_marker":
        points["wake_origin"] = point_near_center(img)
    if role == "battle_aircraft_launch_marker":
        points["aircraft_launch_01"] = point_near_center(img)
    if role == "battle_aircraft_recovery_marker":
        points["aircraft_recovery"] = point_near_center(img)
    if role in {"battle_radar_node", "battle_sonar_node", "battle_periscope_node"}:
        points["scan_origin"] = point_near_center(img)
    if role in {"battle_support_node", "battle_fire_control_node", "battle_flagship_marker"}:
        points["skill_origin"] = point_near_center(img)
    return points


def build_contact_sheet(character_id: str, processed_root: Path) -> Path:
    paths = []
    for folder in ("ui", "battle", "anim", "vfx"):
        paths.extend(sorted((processed_root / folder).glob("*.png")))
    cell_width, cell_height = 240, 210
    columns = 6
    rows = (len(paths) + columns - 1) // columns
    canvas = Image.new("RGB", (columns * cell_width, max(1, rows) * cell_height), "#18242d")
    draw = ImageDraw.Draw(canvas)
    for index, path in enumerate(paths):
        x = (index % columns) * cell_width
        y = (index // columns) * cell_height
        checker = Image.new("RGBA", (cell_width - 12, cell_height - 34), "#dce3e7")
        checker_draw = ImageDraw.Draw(checker)
        block = 16
        for cy in range(0, checker.height, block):
            for cx in range(0, checker.width, block):
                if (cx // block + cy // block) % 2:
                    checker_draw.rectangle((cx, cy, cx + block - 1, cy + block - 1), fill="#b9c5cc")
        image = Image.open(path).convert("RGBA")
        resampling = getattr(Image, "Resampling", Image)
        image.thumbnail((checker.width - 16, checker.height - 16), resampling.LANCZOS)
        checker.alpha_composite(image, ((checker.width - image.width) // 2, (checker.height - image.height) // 2))
        canvas.paste(checker.convert("RGB"), (x + 6, y + 6))
        label = path.stem.removeprefix(f"{character_id}_")[:36]
        draw.text((x + 8, y + cell_height - 24), label, fill="#edf4f7")
    out = CHAR_ROOT / "qa" / f"{character_id}_processed_contact.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out)
    return out


def build_roster_contact_sheet() -> Path:
    roster = character_roster.load_roster()
    tile_width, tile_height = 420, 320
    columns = 4
    rows = (len(roster) + columns - 1) // columns
    canvas = Image.new("RGB", (columns * tile_width, rows * tile_height), "#101a21")
    draw = ImageDraw.Draw(canvas)
    resampling = getattr(Image, "Resampling", Image)

    for index, entry in enumerate(roster):
        x = (index % columns) * tile_width
        y = (index // columns) * tile_height
        draw.rectangle((x + 6, y + 6, x + tile_width - 6, y + tile_height - 6), fill="#22313a", outline="#607985")
        draw.text((x + 16, y + 14), f"{entry.character_id}  {entry.ship_class}", fill="#f1f6f8")
        root = CHAR_ROOT / entry.character_id / "processed"
        candidates = (
            (root / "ui" / f"{entry.character_id}_illust_full_alpha.png", (16, 42, 176, 300)),
            (root / "ui" / f"{entry.character_id}_ui_portrait.png", (188, 42, 294, 146)),
            (root / "battle" / f"{entry.character_id}_battle_body_r.png", (304, 42, 404, 146)),
            (root / "anim" / f"{entry.character_id}_anim_move_keyframe.png", (188, 158, 294, 294)),
            (root / "anim" / f"{entry.character_id}_anim_firepower_keyframe.png", (304, 158, 404, 294)),
        )
        for path, (left, top, right, bottom) in candidates:
            draw.rectangle((x + left, y + top, x + right, y + bottom), fill="#d6e0e5")
            if not path.exists():
                draw.line((x + left, y + top, x + right, y + bottom), fill="#b93636", width=3)
                draw.line((x + right, y + top, x + left, y + bottom), fill="#b93636", width=3)
                continue
            image = Image.open(path).convert("RGBA")
            image.thumbnail((right - left - 12, bottom - top - 12), resampling.LANCZOS)
            px = x + left + ((right - left) - image.width) // 2
            py = y + top + ((bottom - top) - image.height) // 2
            canvas.paste(image.convert("RGB"), (px, py), image.getchannel("A"))

    out = QA_ROOT / "character_roster_processed_contact.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out)
    return out


def process_character(character_id: str) -> None:
    roster = character_roster.roster_by_id()
    if character_id not in roster:
        raise SystemExit(f"Unknown character id: {character_id}")
    if not can_process(character_id):
        raise SystemExit(f"Source package is incomplete for {character_id}")

    entry = roster[character_id]
    dirs = ensure_dirs(character_id)
    paths = source_paths(character_id)
    manifest: dict[str, Any] = {
        "character_id": character_id,
        "source": "tools/art_pipeline/postprocess_generated_character.py",
        "method": "green_screen_auto_grid_and_component_split",
        "outputs": [],
    }

    alpha_sources: dict[str, Image.Image] = {}
    for key, path in paths.items():
        if not path.exists():
            continue
        alpha = remove_green_background(path)
        alpha_sources[key] = alpha
        out = dirs["source_alpha"] / f"{path.stem}_alpha_source.png"
        manifest["outputs"].append({"role": f"source_alpha:{key}", **save_image(alpha, out)})

    full, full_meta = crop_with_padding(alpha_sources["concept_full"], pad=12)
    manifest["outputs"].append({"role": "full_body", "crop": full_meta, **save_image(full, dirs["ui"] / f"{character_id}_illust_full_alpha.png")})
    derived_half, derived_cutin = derive_half_and_cutin(full)
    half_source = alpha_sources.get("half_body", derived_half)
    cutin_source = alpha_sources.get("skill_cutin", derived_cutin)
    half, half_meta = crop_with_padding(half_source, pad=16)
    manifest["outputs"].append({"role": "half_body", "crop": half_meta, **save_image(half, dirs["ui"] / f"{character_id}_illust_half_alpha.png")})
    cutin, cutin_meta = crop_with_padding(cutin_source, pad=16)
    manifest["outputs"].append({"role": "skill_cutin", "crop": cutin_meta, **save_image(cutin, dirs["ui"] / f"{character_id}_illust_skill_cutin_alpha.png")})

    ui_cells = split_grid(alpha_sources["ui_sheet"], rows=2, cols=4)
    for slot_name, cell in zip(UI_SLOT_NAMES, ui_cells[:7]):
        cropped, crop_meta = crop_with_padding(cell, pad=18)
        cropped = keep_largest_alpha_component(cropped)
        resolved_slot = f"ui_skill_{SKILL_ROLE_BY_CLASS[entry.ship_class]}" if slot_name == "ui_skill" else slot_name
        out_name = f"{character_id}_{resolved_slot}.png"
        manifest["outputs"].append({"role": slot_name, "crop": crop_meta, **save_image(cropped, dirs["ui"] / out_name)})
    class_cell = ui_cells[7]
    class_img, class_meta = crop_with_padding(class_cell, pad=18)
    class_img = keep_largest_alpha_component(class_img)
    class_name = f"{character_id}_ui_class_{entry.ship_class}.png"
    manifest["outputs"].append({"role": "class_icon", "crop": class_meta, **save_image(class_img, dirs["ui"] / class_name)})

    battle_source_key = "battle_grid" if "battle_grid" in alpha_sources else "battle_sheet"
    if battle_source_key == "battle_grid":
        battle_roles = []
        for role, cell in zip(BATTLE_GRID_ROLES[entry.ship_class], split_grid(alpha_sources[battle_source_key], rows=2, cols=4)):
            components = connected_components(cell, min_area=300)
            if components:
                battle_roles.append((role, cell, components[0]))
    else:
        components = connected_components(alpha_sources[battle_source_key], min_area=2_000)
        battle_roles = [(role, alpha_sources[battle_source_key], component) for role, component in battle_roles_for_components(components, entry.ship_class)]
    bind_assets: dict[str, dict[str, dict[str, int]]] = {}
    for role, source, component in battle_roles:
        cropped, crop_meta = crop_component(source, component, pad=18)
        cropped = keep_largest_alpha_component(cropped)
        out_name = f"{character_id}_{role}.png"
        out_path = dirs["battle"] / out_name
        manifest["outputs"].append({"role": role, "crop": crop_meta, **save_image(cropped, out_path)})
        bind_assets[out_name] = battle_points(role, cropped)

    anim_states: dict[str, Any] = {}
    master_rows = split_grid(alpha_sources["anim_master"], rows=5, cols=1) if "anim_master" in alpha_sources else None
    idle_body: Image.Image | None = None
    for state_index, (state, playback) in enumerate(ANIMATION_STATES.items()):
        cells = split_grid(master_rows[state_index], rows=1, cols=4) if master_rows else split_grid(alpha_sources[f"anim_{state}"], rows=2, cols=2)
        frames: list[str] = []
        normalized: list[Image.Image] = []
        for cell in cells:
            if master_rows:
                # A generated master can place hair, flashes, or radar fragments just over a
                # mathematical row boundary. Animation frames are single-subject assets; precise
                # weapon effects remain on independent runtime nodes.
                cell = keep_largest_alpha_component(cell)
            cropped, _crop_meta = crop_with_padding(cell, pad=16)
            normalized.append(cropped)
        max_width = max(img.width for img in normalized)
        max_height = max(img.height for img in normalized)
        for index, frame in enumerate(normalized, start=1):
            canvas = Image.new("RGBA", (max_width, max_height), (0, 0, 0, 0))
            canvas.alpha_composite(frame, ((max_width - frame.width) // 2, (max_height - frame.height) // 2))
            out_path = dirs["anim"] / f"{character_id}_anim_{state}_frame_{index:02d}.png"
            manifest["outputs"].append({"role": f"anim_{state}_frame_{index:02d}", **save_image(canvas, out_path)})
            frames.append(str(out_path.relative_to(ROOT)))
            if index == 1:
                keyframe_path = dirs["anim"] / f"{character_id}_anim_{state}_keyframe.png"
                manifest["outputs"].append({"role": f"anim_{state}_keyframe", **save_image(canvas, keyframe_path)})
                if state == "idle" and master_rows:
                    idle_body = canvas.copy()
        anim_states[state] = {"frames": frames, "fps": playback["fps"], "loop": playback["loop"]}

    if idle_body is not None:
        body_name = f"{character_id}_battle_body_r.png"
        body_path = dirs["battle"] / body_name
        manifest["outputs"].append({"role": "battle_body_r:idle_master_override", **save_image(idle_body, body_path)})
        bind_assets[body_name] = {"pivot": point_near_center(idle_body)}

    vfx_cells = split_grid(alpha_sources["vfx_sheet"], rows=2, cols=4)
    vfx_roles: dict[str, Any] = {}
    for role_name, cell in zip(VFX_ROLES_BY_CLASS[entry.ship_class], vfx_cells):
        components = connected_components(cell, min_area=120)
        if not components:
            continue
        cropped, crop_meta = crop_component(cell, components[0], pad=18)
        out_name = f"{character_id}_vfx_{role_name}.png"
        out_path = dirs["vfx"] / out_name
        manifest["outputs"].append({"role": f"vfx:{role_name}", "crop": crop_meta, **save_image(cropped, out_path)})
        vfx_roles[role_name] = {"file": str(out_path.relative_to(ROOT)), "source": "character_specific"}

    (dirs["config"] / f"{character_id}_meta_bind_points.json").write_text(
        json.dumps({"character_id": character_id, "assets": bind_assets}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    (dirs["config"] / f"{character_id}_anim_config.json").write_text(
        json.dumps({"character_id": character_id, "states": anim_states}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    (dirs["config"] / f"{character_id}_vfx_config.json").write_text(
        json.dumps({"character_id": character_id, "ship_class": entry.ship_class, "roles": vfx_roles}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    (dirs["config"] / f"{character_id}_postprocess_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    build_contact_sheet(character_id, dirs["root"])


def main() -> int:
    parser = argparse.ArgumentParser(description="Postprocess generated green-screen TinySeaWar character sheets.")
    parser.add_argument("character_ids", nargs="*")
    parser.add_argument("--roster-contact", action="store_true", help="Build a compact 24-character visual QA sheet.")
    args = parser.parse_args()
    for character_id in args.character_ids:
        process_character(character_id)
        print(f"processed: {character_id}")
    if args.roster_contact:
        print(f"roster_contact: {build_roster_contact_sheet().relative_to(ROOT)}")
    if not args.character_ids and not args.roster_contact:
        parser.error("provide at least one character id or --roster-contact")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
