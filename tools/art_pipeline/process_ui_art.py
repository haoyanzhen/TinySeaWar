from __future__ import annotations

import json
from collections import deque
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[2]
UI_ROOT = ROOT / "assets" / "ui"
ALPHA_ROOT = UI_ROOT / "processed" / "source_alpha"
PROCESSED_ROOT = UI_ROOT / "processed"
EXPORT_ROOT = UI_ROOT / "export"
QA_ROOT = UI_ROOT / "qa"
RESAMPLE_LANCZOS = getattr(getattr(Image, "Resampling", Image), "LANCZOS", Image.LANCZOS)


def grid_entries(
    source: str,
    columns: int,
    rows: int,
    names: list[tuple[str, str, str]],
) -> list[dict[str, Any]]:
    if len(names) != columns * rows:
        raise ValueError(f"{source}: expected {columns * rows} names, got {len(names)}")
    return [
        {
            "source": source,
            "grid": [columns, rows],
            "cell": [index % columns, index // columns],
            "name": name,
            "out_dir": out_dir,
            "kind": kind,
        }
        for index, (name, out_dir, kind) in enumerate(names)
    ]


ASSETS: list[dict[str, Any]] = []

ASSETS += grid_entries(
    "ui_icons_controls_sheet_alpha.png",
    4,
    4,
    [
        ("ui_icon_auto_move", "common/icons", "icon"),
        ("ui_icon_auto_weapon", "common/icons", "icon"),
        ("ui_icon_auto_skill", "common/icons", "icon"),
        ("ui_icon_pause", "common/icons", "icon"),
        ("ui_icon_continue", "common/icons", "icon"),
        ("ui_icon_expand", "common/icons", "icon"),
        ("ui_icon_collapse", "common/icons", "icon"),
        ("ui_icon_camera_follow", "common/icons", "icon"),
        ("ui_icon_health", "common/icons", "icon"),
        ("ui_icon_oxygen", "common/icons", "icon"),
        ("ui_icon_skill_ready", "common/icons", "icon"),
        ("ui_icon_cooldown", "common/icons", "icon"),
        ("ui_icon_selected", "common/icons", "icon"),
        ("ui_icon_target_lock", "common/icons", "icon"),
        ("ui_icon_detection", "common/icons", "icon"),
        ("ui_icon_lost_vision", "common/icons", "icon"),
    ],
)

ASSETS += grid_entries(
    "ui_icons_combat_sheet_alpha.png",
    4,
    4,
    [
        ("ui_icon_flagship", "common/icons", "icon"),
        ("ui_icon_submerged", "common/icons", "icon"),
        ("ui_icon_surfaced", "common/icons", "icon"),
        ("ui_icon_gunfire", "common/icons", "icon"),
        ("ui_icon_torpedo", "common/icons", "icon"),
        ("ui_icon_airstrike", "common/icons", "icon"),
        ("ui_icon_antiair", "common/icons", "icon"),
        ("ui_icon_antisubmarine", "common/icons", "icon"),
        ("ui_icon_sunk", "common/icons", "icon"),
        ("ui_icon_hit", "common/icons", "icon"),
        ("ui_icon_warning", "common/icons", "icon"),
        ("ui_icon_unknown_contact", "common/icons", "icon"),
        ("ui_log_contact_friendly", "battle/log", "icon"),
        ("ui_log_contact_enemy", "battle/log", "icon"),
        ("ui_log_aircraft_wave", "battle/log", "icon"),
        ("ui_log_last_contact", "battle/log", "icon"),
    ],
)

ASSETS += grid_entries(
    "ui_icons_classes_minimap_sheet_alpha.png",
    4,
    3,
    [
        ("ui_icon_class_destroyer", "common/icons", "icon"),
        ("ui_icon_class_light_cruiser", "common/icons", "icon"),
        ("ui_icon_class_heavy_cruiser", "common/icons", "icon"),
        ("ui_icon_class_battleship", "common/icons", "icon"),
        ("ui_icon_class_carrier", "common/icons", "icon"),
        ("ui_icon_class_submarine", "common/icons", "icon"),
        ("ui_minimap_surface_player", "battle/minimap", "icon"),
        ("ui_minimap_surface_enemy", "battle/minimap", "icon"),
        ("ui_minimap_submarine_player", "battle/minimap", "icon"),
        ("ui_minimap_submarine_enemy", "battle/minimap", "icon"),
        ("ui_minimap_aircraft_player", "battle/minimap", "icon"),
        ("ui_minimap_aircraft_enemy", "battle/minimap", "icon"),
    ],
)

ASSETS += grid_entries(
    "ui_panels_sheet_alpha.png",
    3,
    3,
    [
        ("ui_panel_top_expanded", "battle/hud", "panel"),
        ("ui_panel_top_collapsed", "battle/hud", "panel"),
        ("ui_panel_fleet_tray_2x6", "battle/fleet", "panel"),
        ("ui_panel_minimap_open_sea", "battle/minimap", "panel"),
        ("ui_panel_battle_log", "battle/log", "panel"),
        ("ui_panel_selected_ship", "battle/hud", "panel"),
        ("ui_panel_pause_dialog", "battle/results", "panel"),
        ("ui_panel_result_dialog", "battle/results", "panel"),
        ("ui_panel_confirm_dialog", "battle/results", "panel"),
    ],
)

ASSETS += grid_entries(
    "ui_frames_buttons_sheet_alpha.png",
    4,
    3,
    [
        ("ui_frame_portrait_player", "battle/fleet", "frame"),
        ("ui_frame_portrait_enemy", "battle/fleet", "frame"),
        ("ui_frame_portrait_unknown", "battle/fleet", "frame"),
        ("ui_frame_portrait_selected", "battle/fleet", "frame"),
        ("ui_frame_portrait_flagship", "battle/fleet", "frame"),
        ("ui_frame_portrait_sunk", "battle/fleet", "frame"),
        ("ui_frame_portrait_skill_ready", "battle/fleet", "frame"),
        ("ui_frame_portrait_low_hp", "battle/fleet", "frame"),
        ("ui_button_small_default", "common/buttons", "button"),
        ("ui_button_small_hover", "common/buttons", "button"),
        ("ui_button_small_pressed", "common/buttons", "button"),
        ("ui_button_small_disabled", "common/buttons", "button"),
    ],
)

ASSETS += grid_entries(
    "ui_markers_sheet_alpha.png",
    4,
    3,
    [
        ("ui_marker_selected", "battle/markers", "marker"),
        ("ui_marker_target", "battle/markers", "marker"),
        ("ui_marker_heading", "battle/markers", "marker"),
        ("ui_marker_destination", "battle/markers", "marker"),
        ("ui_marker_path_endpoint", "battle/markers", "marker"),
        ("ui_marker_offscreen_player", "battle/markers", "marker"),
        ("ui_marker_offscreen_enemy", "battle/markers", "marker"),
        ("ui_marker_offscreen_danger", "battle/markers", "marker"),
        ("ui_marker_flagship", "battle/markers", "marker"),
        ("ui_minimap_camera_frame", "battle/minimap", "marker"),
        ("ui_marker_skill_area", "battle/markers", "marker"),
        ("ui_marker_danger_area", "battle/markers", "marker"),
    ],
)

ASSETS += grid_entries(
    "ui_results_decor_sheet_alpha.png",
    4,
    2,
    [
        ("ui_result_victory_header", "battle/results", "decor"),
        ("ui_result_defeat_header", "battle/results", "decor"),
        ("ui_result_pause_header", "battle/results", "decor"),
        ("ui_result_confirm_header", "battle/results", "decor"),
        ("ui_result_victory_flourish", "battle/results", "decor"),
        ("ui_result_defeat_flourish", "battle/results", "decor"),
        ("ui_result_sparkles", "battle/results", "decor"),
        ("ui_result_ripples", "battle/results", "decor"),
    ],
)

ASSETS += grid_entries(
    "ui_auto_toggles_sheet_alpha.png",
    3,
    2,
    [
        ("ui_button_auto_move_on", "common/buttons", "button"),
        ("ui_button_auto_weapon_on", "common/buttons", "button"),
        ("ui_button_auto_skill_on", "common/buttons", "button"),
        ("ui_button_auto_move_off", "common/buttons", "button"),
        ("ui_button_auto_weapon_off", "common/buttons", "button"),
        ("ui_button_auto_skill_off", "common/buttons", "button"),
    ],
)

ASSETS += grid_entries(
    "ui_buttons_sizes_states_sheet_alpha.png",
    3,
    3,
    [
        ("ui_button_size_small_default", "common/buttons", "button"),
        ("ui_button_size_medium_default", "common/buttons", "button"),
        ("ui_button_size_large_default", "common/buttons", "button"),
        ("ui_button_size_small_selected", "common/buttons", "button"),
        ("ui_button_size_medium_selected", "common/buttons", "button"),
        ("ui_button_size_large_selected", "common/buttons", "button"),
        ("ui_button_size_small_warning", "common/buttons", "button"),
        ("ui_button_size_medium_warning", "common/buttons", "button"),
        ("ui_button_size_large_warning", "common/buttons", "button"),
    ],
)

ASSETS += grid_entries(
    "ui_icons_dialog_actions_sheet_alpha.png",
    2,
    2,
    [
        ("ui_icon_confirm", "common/icons", "icon"),
        ("ui_icon_cancel", "common/icons", "icon"),
        ("ui_icon_restart", "common/icons", "icon"),
        ("ui_icon_exit", "common/icons", "icon"),
    ],
)

BAR_BOXES = [
    ("ui_bar_track_empty", (0, 170, 410, 340), "bar"),
    ("ui_bar_hp_healthy", (390, 170, 780, 340), "bar"),
    ("ui_bar_hp_warning", (755, 170, 1145, 340), "bar"),
    ("ui_bar_hp_critical", (1130, 170, 1536, 340), "bar"),
    ("ui_bar_oxygen", (0, 420, 410, 600), "bar"),
    ("ui_bar_skill_charge", (390, 420, 805, 600), "bar"),
    ("ui_bar_damage_trail", (790, 420, 1280, 600), "bar"),
    ("ui_ring_cooldown_empty", (0, 620, 320, 930), "icon"),
    ("ui_ring_cooldown_half", (320, 620, 620, 930), "icon"),
    ("ui_ring_skill_ready", (620, 620, 930, 930), "icon"),
    ("ui_badge_flagship_critical", (910, 620, 1220, 930), "icon"),
    ("ui_badge_unknown_status", (1220, 620, 1536, 930), "icon"),
]

for name, box, kind in BAR_BOXES:
    ASSETS.append(
        {
            "source": "ui_bars_status_sheet_alpha.png",
            "box": list(box),
            "name": name,
            "out_dir": "common/bars",
            "kind": kind,
        }
    )

for asset in ASSETS:
    if asset["name"] == "ui_icon_airstrike":
        asset["source"] = "ui_icon_airstrike_replacement_alpha.png"
        asset["full"] = True
    if asset["name"] == "ui_marker_danger_area":
        asset["source"] = "ui_marker_danger_area_replacement_alpha.png"
        asset["full"] = True
    if asset["name"].startswith("ui_button_auto_"):
        asset["source"] = "ui_auto_toggles_sheet_v2_alpha.png"
    if asset["name"] == "ui_bar_hp_healthy":
        asset["source"] = "ui_bar_hp_healthy_replacement_alpha.png"
        asset["full"] = True
        asset["resize"] = [376, 120]

COMBAT_ICON_CROP_OVERRIDES = {
    "ui_icon_sunk": [0, 627, 314, 895],
    "ui_icon_hit": [314, 627, 627, 895],
    "ui_icon_warning": [627, 627, 940, 895],
    "ui_icon_unknown_contact": [940, 627, 1254, 895],
}
for asset in ASSETS:
    if asset["name"] in COMBAT_ICON_CROP_OVERRIDES:
        asset["box"] = COMBAT_ICON_CROP_OVERRIDES[asset["name"]]

PANEL_CROP_OVERRIDES = {
    "ui_panel_top_expanded": [0, 70, 780, 270],
    "ui_panel_top_collapsed": [775, 100, 1005, 255],
    "ui_panel_fleet_tray_2x6": [985, 20, 1536, 335],
    "ui_panel_minimap_open_sea": [45, 300, 475, 650],
    "ui_panel_battle_log": [545, 285, 975, 665],
    "ui_panel_selected_ship": [1005, 340, 1490, 645],
    "ui_panel_pause_dialog": [25, 635, 505, 995],
    "ui_panel_result_dialog": [515, 630, 1000, 1005],
    "ui_panel_confirm_dialog": [995, 645, 1490, 1005],
}
for asset in ASSETS:
    if asset["name"] in PANEL_CROP_OVERRIDES:
        asset["box"] = PANEL_CROP_OVERRIDES[asset["name"]]

FRAME_CROP_OVERRIDES = {
    "ui_frame_portrait_player": [45, 10, 405, 390],
    "ui_frame_portrait_enemy": [415, 10, 775, 390],
    "ui_frame_portrait_unknown": [765, 10, 1120, 390],
    "ui_frame_portrait_selected": [1125, 20, 1510, 390],
    "ui_frame_portrait_flagship": [40, 370, 410, 760],
    "ui_frame_portrait_sunk": [415, 370, 775, 760],
    "ui_frame_portrait_skill_ready": [765, 370, 1120, 760],
    "ui_frame_portrait_low_hp": [1125, 370, 1510, 760],
}
for asset in ASSETS:
    if asset["name"] in FRAME_CROP_OVERRIDES:
        asset["box"] = FRAME_CROP_OVERRIDES[asset["name"]]

BUTTON_CROP_OVERRIDES = {
    "ui_button_small_default": [40, 755, 400, 990],
    "ui_button_small_hover": [405, 755, 775, 990],
    "ui_button_small_pressed": [765, 755, 1125, 990],
    "ui_button_small_disabled": [1125, 755, 1536, 990],
}
for asset in ASSETS:
    if asset["name"] in BUTTON_CROP_OVERRIDES:
        asset["box"] = BUTTON_CROP_OVERRIDES[asset["name"]]


def trim_alpha(image: Image.Image, padding: int = 10) -> Image.Image:
    bbox = image.getchannel("A").getbbox()
    if bbox is None:
        raise ValueError("empty alpha crop")
    left, top, right, bottom = bbox
    return image.crop(
        (
            max(0, left - padding),
            max(0, top - padding),
            min(image.width, right + padding),
            min(image.height, bottom + padding),
        )
    )


def remove_tiny_alpha_islands(image: Image.Image, relative_area: float = 0.0008) -> Image.Image:
    alpha = image.getchannel("A")
    pixels = alpha.load()
    seen: set[tuple[int, int]] = set()
    components: list[list[tuple[int, int]]] = []
    for y in range(alpha.height):
        for x in range(alpha.width):
            if (x, y) in seen or pixels[x, y] < 8:
                continue
            queue: deque[tuple[int, int]] = deque([(x, y)])
            seen.add((x, y))
            component: list[tuple[int, int]] = []
            while queue:
                cx, cy = queue.popleft()
                component.append((cx, cy))
                for nx, ny in ((cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)):
                    if nx < 0 or ny < 0 or nx >= alpha.width or ny >= alpha.height:
                        continue
                    if (nx, ny) in seen or pixels[nx, ny] < 8:
                        continue
                    seen.add((nx, ny))
                    queue.append((nx, ny))
            components.append(component)
    if not components:
        return image
    cutoff = max(8, round(max(len(component) for component in components) * relative_area))
    cleaned = image.copy()
    cleaned_alpha = cleaned.getchannel("A")
    cleaned_pixels = cleaned_alpha.load()
    for component in components:
        if len(component) < cutoff:
            for x, y in component:
                cleaned_pixels[x, y] = 0
    cleaned.putalpha(cleaned_alpha)
    return cleaned


def crop_box(asset: dict[str, Any], size: tuple[int, int]) -> tuple[int, int, int, int]:
    if asset.get("full"):
        return (0, 0, size[0], size[1])
    if "box" in asset:
        return tuple(asset["box"])
    columns, rows = asset["grid"]
    column, row = asset["cell"]
    width, height = size
    return (
        round(column * width / columns),
        round(row * height / rows),
        round((column + 1) * width / columns),
        round((row + 1) * height / rows),
    )


def place_on_square(image: Image.Image, size: int = 256, margin: int = 18) -> Image.Image:
    available = size - margin * 2
    scale = min(available / image.width, available / image.height)
    target = (
        max(1, round(image.width * scale)),
        max(1, round(image.height * scale)),
    )
    resized = image.resize(target, RESAMPLE_LANCZOS)
    output = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    output.alpha_composite(resized, ((size - target[0]) // 2, (size - target[1]) // 2))
    return output


def save_scaled_icon_exports(master: Image.Image, name: str) -> list[str]:
    outputs: list[str] = []
    for scale_name, size in (("1x", 32), ("2x", 64), ("4x", 128)):
        directory = EXPORT_ROOT / scale_name
        directory.mkdir(parents=True, exist_ok=True)
        path = directory / f"{name}.png"
        master.resize((size, size), RESAMPLE_LANCZOS).save(path)
        outputs.append(str(path.relative_to(ROOT)))
    return outputs


def checker(size: tuple[int, int], cell: int = 12) -> Image.Image:
    image = Image.new("RGB", size, "#dce8eb")
    draw = ImageDraw.Draw(image)
    for y in range(0, size[1], cell):
        for x in range(0, size[0], cell):
            if (x // cell + y // cell) % 2:
                draw.rectangle((x, y, x + cell - 1, y + cell - 1), fill="#f8fcfd")
    return image


def build_contact_sheet(records: list[dict[str, Any]], background: str, filename: str) -> None:
    thumb_size = 128
    card_width = 190
    card_height = 174
    columns = 7
    rows = (len(records) + columns - 1) // columns
    sheet = Image.new("RGB", (columns * card_width, rows * card_height), "#b8ced5")
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default()
    for index, record in enumerate(records):
        x = (index % columns) * card_width
        y = (index // columns) * card_height
        draw.rounded_rectangle(
            (x + 5, y + 5, x + card_width - 5, y + card_height - 5),
            radius=10,
            fill="#f7fcff",
            outline="#5a7883",
            width=1,
        )
        if background == "checker":
            preview = checker((thumb_size, thumb_size))
        else:
            preview = Image.new("RGB", (thumb_size, thumb_size), background)
        asset = Image.open(ROOT / record["output"]).convert("RGBA")
        scale = min((thumb_size - 12) / asset.width, (thumb_size - 12) / asset.height)
        rendered = asset.resize(
            (max(1, round(asset.width * scale)), max(1, round(asset.height * scale))),
            RESAMPLE_LANCZOS,
        )
        preview_rgba = preview.convert("RGBA")
        preview_rgba.alpha_composite(
            rendered,
            ((thumb_size - rendered.width) // 2, (thumb_size - rendered.height) // 2),
        )
        sheet.paste(preview_rgba.convert("RGB"), (x + 31, y + 12))
        label = record["name"]
        if len(label) > 26:
            label = label[:23] + "..."
        draw.text((x + 10, y + 145), label, font=font, fill="#244b5a")
    QA_ROOT.mkdir(parents=True, exist_ok=True)
    sheet.save(QA_ROOT / filename)


def build_one_x_contact(records: list[dict[str, Any]]) -> None:
    icon_records = [record for record in records if record["kind"] in {"icon", "marker"}]
    cell = 112
    columns = 10
    rows = (len(icon_records) + columns - 1) // columns
    sheet = Image.new("RGB", (columns * cell, rows * cell), "#e8f7fb")
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default()
    for index, record in enumerate(icon_records):
        x = (index % columns) * cell
        y = (index // columns) * cell
        draw.rounded_rectangle((x + 3, y + 3, x + cell - 3, y + cell - 3), 8, "#f7fcff", "#5a7883")
        one_x = Image.open(ROOT / record["exports"][0]).convert("RGBA")
        enlarged = one_x.resize((96, 96), Image.Resampling.NEAREST if hasattr(Image, "Resampling") else Image.NEAREST)
        sheet.paste(enlarged, (x + 8, y + 5), enlarged)
        short = record["name"].replace("ui_", "")
        if len(short) > 17:
            short = short[:14] + "..."
        draw.text((x + 6, y + 98), short, font=font, fill="#244b5a")
    sheet.save(QA_ROOT / "ui_icons_1x_contact.png")


def build_24px_contact(records: list[dict[str, Any]]) -> None:
    icon_records = [record for record in records if record["kind"] in {"icon", "marker"}]
    cell = 112
    columns = 10
    rows = (len(icon_records) + columns - 1) // columns
    sheet = Image.new("RGB", (columns * cell, rows * cell), "#e8f7fb")
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default()
    nearest = Image.Resampling.NEAREST if hasattr(Image, "Resampling") else Image.NEAREST
    for index, record in enumerate(icon_records):
        x = (index % columns) * cell
        y = (index // columns) * cell
        draw.rounded_rectangle((x + 3, y + 3, x + cell - 3, y + cell - 3), 8, "#f7fcff", "#5a7883")
        master = Image.open(ROOT / record["output"]).convert("RGBA")
        small = master.resize((24, 24), RESAMPLE_LANCZOS)
        enlarged = small.resize((96, 96), nearest)
        sheet.paste(enlarged, (x + 8, y + 5), enlarged)
        short = record["name"].replace("ui_", "")
        if len(short) > 17:
            short = short[:14] + "..."
        draw.text((x + 6, y + 98), short, font=font, fill="#244b5a")
    sheet.save(QA_ROOT / "ui_icons_24px_contact.png")


def main() -> int:
    records: list[dict[str, Any]] = []
    for asset in ASSETS:
        source_path = ALPHA_ROOT / asset["source"]
        source = Image.open(source_path).convert("RGBA")
        box = crop_box(asset, source.size)
        cropped = trim_alpha(source.crop(box))
        cropped = remove_tiny_alpha_islands(cropped)
        cropped = trim_alpha(cropped)
        if "resize" in asset:
            cropped = cropped.resize(tuple(asset["resize"]), RESAMPLE_LANCZOS)
        output_dir = PROCESSED_ROOT / asset["out_dir"]
        output_dir.mkdir(parents=True, exist_ok=True)
        output_path = output_dir / f"{asset['name']}.png"
        exports: list[str] = []
        if asset["kind"] in {"icon", "marker"}:
            cropped = place_on_square(cropped)
            exports = save_scaled_icon_exports(cropped, asset["name"])
        cropped.save(output_path)
        alpha_bbox = cropped.getchannel("A").getbbox()
        if alpha_bbox is None:
            raise ValueError(f"{asset['name']} produced empty alpha")
        records.append(
            {
                "name": asset["name"],
                "kind": asset["kind"],
                "source": str(source_path.relative_to(ROOT)),
                "crop_box": list(box),
                "output": str(output_path.relative_to(ROOT)),
                "size": list(cropped.size),
                "alpha_bbox": list(alpha_bbox),
                "exports": exports,
            }
        )

    manifest = {
        "generator": "OpenAI built-in image generation",
        "model": "gpt-image-2",
        "palette": {
            "panel": "#F7FCFF",
            "secondary": "#E8F7FB",
            "border": "#8DD9E8",
            "text": "#244B5A",
            "friendly": "#2FBAE6",
            "enemy": "#FF7180",
            "danger": "#E83F5B",
            "selected": "#FFC857",
            "target": "#FF9F43",
            "positive": "#35C99A",
            "skill": "#8A78F0",
        },
        "asset_count": len(records),
        "assets": records,
    }
    QA_ROOT.mkdir(parents=True, exist_ok=True)
    (QA_ROOT / "ui_asset_manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    build_contact_sheet(records, "checker", "ui_asset_contact.png")
    build_contact_sheet(records, "#173746", "ui_asset_contact_dark.png")
    build_contact_sheet(records, "#ffffff", "ui_asset_contact_light.png")
    build_one_x_contact(records)
    build_24px_contact(records)
    print(f"Processed {len(records)} UI assets")
    print(QA_ROOT / "ui_asset_manifest.json")
    print(QA_ROOT / "ui_asset_contact.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
