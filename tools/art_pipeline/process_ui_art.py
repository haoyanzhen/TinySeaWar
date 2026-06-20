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


PALETTE = {
    "panel": "#F7FCFF",
    "secondary": "#E8F7FB",
    "border": "#8DD9E8",
    "text": "#244B5A",
    "soft": "#5A7883",
    "friendly": "#2FBAE6",
    "enemy": "#FF7180",
    "danger": "#E83F5B",
    "selected": "#FFC857",
    "target": "#FF9F43",
    "positive": "#35C99A",
    "skill": "#8A78F0",
}


def rgba(hex_color: str, alpha: int = 255) -> tuple[int, int, int, int]:
    hex_color = hex_color.lstrip("#")
    return (
        int(hex_color[0:2], 16),
        int(hex_color[2:4], 16),
        int(hex_color[4:6], 16),
        alpha,
    )


def rounded_panel(size: tuple[int, int], radius: int = 22, accent: str = "border") -> Image.Image:
    image = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    width, height = size
    shadow = Image.new("RGBA", size, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle((8, 10, width - 5, height - 4), radius, fill=(82, 140, 158, 34))
    image.alpha_composite(shadow)
    draw.rounded_rectangle((3, 3, width - 9, height - 9), radius, fill=rgba(PALETTE["panel"], 232), outline=rgba(PALETTE["border"], 205), width=3)
    draw.rounded_rectangle((10, 11, width - 16, height - 16), max(4, radius - 8), outline=rgba("#FFFFFF", 110), width=1)
    draw.rounded_rectangle((14, 15, width - 20, 26), max(4, radius - 10), fill=rgba(PALETTE[accent], 150))
    for index in range(3):
        y = height - 28 - index * 16
        draw.arc((24 + index * 18, y - 10, 190 + index * 22, y + 34), 190, 350, fill=rgba(PALETTE["border"], 70 - index * 12), width=2)
    return image


def empty_text_lines(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], lines: int, color: str = "border") -> None:
    left, top, right, bottom = box
    step = max(20, (bottom - top) // max(1, lines))
    for index in range(lines):
        y = top + index * step
        width = int((right - left) * (0.92 - (index % 3) * 0.12))
        draw.rounded_rectangle((left, y, left + width, y + 9), 5, fill=rgba(PALETTE[color], 48))


def draw_compass(draw: ImageDraw.ImageDraw, center: tuple[int, int], radius: int, color: str = "selected") -> None:
    x, y = center
    draw.ellipse((x - radius, y - radius, x + radius, y + radius), outline=rgba(PALETTE[color], 150), width=3)
    draw.line((x, y - radius - 8, x, y + radius + 8), fill=rgba(PALETTE[color], 120), width=2)
    draw.line((x - radius - 8, y, x + radius + 8, y), fill=rgba(PALETTE[color], 120), width=2)
    draw.polygon([(x, y - radius + 7), (x + 8, y), (x, y + radius - 7), (x - 8, y)], fill=rgba(PALETTE[color], 125))


def button_surface(size: tuple[int, int], state: str, accent: str = "friendly") -> Image.Image:
    image = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    width, height = size
    fills = {
        "default": rgba(PALETTE["panel"], 238),
        "hover": rgba(PALETTE["secondary"], 248),
        "pressed": rgba("#D7EEF5", 248),
        "selected": rgba("#FFF8D8", 248),
        "disabled": rgba("#DDE8EC", 180),
    }
    outlines = {
        "default": rgba(PALETTE["border"], 205),
        "hover": rgba(PALETTE[accent], 225),
        "pressed": rgba("#54B8D3", 225),
        "selected": rgba(PALETTE["selected"], 235),
        "disabled": rgba("#AFC1C8", 160),
    }
    inset = 3 if state == "pressed" else 0
    draw.rounded_rectangle((4 + inset, 5 + inset, width - 8 + inset, height - 8 + inset), 17, fill=fills[state], outline=outlines[state], width=3)
    draw.rounded_rectangle((15 + inset, 16 + inset, 50 + inset, height - 19 + inset), 12, fill=rgba(PALETTE[accent], 62 if state != "disabled" else 30))
    draw.line((62 + inset, height - 13 + inset, width - 24 + inset, height - 13 + inset), fill=rgba(PALETTE[accent], 55 if state != "disabled" else 24), width=2)
    return image


def icon_menu_start() -> Image.Image:
    image = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw_compass(draw, (128, 128), 82, "friendly")
    draw.polygon([(108, 76), (178, 128), (108, 180)], fill=rgba(PALETTE["positive"], 220))
    draw.line((76, 191, 180, 68), fill=rgba(PALETTE["selected"], 190), width=8)
    return image


def icon_menu_modes() -> Image.Image:
    image = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    for index, (x, y, color) in enumerate(((82, 88, "friendly"), (150, 116, "skill"), (116, 174, "selected"))):
        draw.rounded_rectangle((x - 34, y - 25, x + 34, y + 25), 13, fill=rgba(PALETTE[color], 88), outline=rgba(PALETTE[color], 220), width=5)
        draw.line((x - 18, y, x + 18, y), fill=rgba("#FFFFFF", 220), width=5)
    draw.line((105, 98, 130, 112), fill=rgba(PALETTE["border"], 185), width=5)
    draw.line((135, 139, 124, 154), fill=rgba(PALETTE["border"], 185), width=5)
    return image


def icon_menu_guide() -> Image.Image:
    image = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((58, 48, 198, 208), 24, fill=rgba(PALETTE["panel"], 235), outline=rgba(PALETTE["friendly"], 220), width=7)
    for y, width in ((82, 92), (116, 104), (150, 82)):
        draw.rounded_rectangle((82, y, 82 + width, y + 12), 6, fill=rgba(PALETTE["soft"], 120))
    draw.ellipse((76, 178, 100, 202), fill=rgba(PALETTE["selected"], 200))
    draw.ellipse((116, 178, 140, 202), fill=rgba(PALETTE["positive"], 200))
    return image


def icon_menu_intro() -> Image.Image:
    image = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.ellipse((46, 46, 210, 210), fill=rgba(PALETTE["secondary"], 210), outline=rgba(PALETTE["border"], 230), width=7)
    draw.line((128, 78, 128, 138), fill=rgba(PALETTE["friendly"], 230), width=10)
    draw.ellipse((119, 164, 137, 182), fill=rgba(PALETTE["selected"], 240))
    draw.arc((88, 92, 168, 172), 205, 335, fill=rgba(PALETTE["skill"], 180), width=7)
    return image


PROCEDURAL_ASSETS = [
    ("ui_panel_menu_title", "menu", "panel", (620, 190), "panel"),
    ("ui_panel_menu_info", "menu", "panel", (650, 420), "panel"),
    ("ui_panel_menu_footer", "menu", "panel", (650, 88), "panel"),
    ("ui_panel_menu_cover_label", "menu", "panel", (520, 74), "cover_label"),
    ("ui_panel_menu_mode_card", "menu", "panel", (600, 112), "panel"),
    ("ui_panel_menu_keybind_card", "menu", "panel", (600, 72), "panel"),
    ("ui_panel_menu_intro_step_card", "menu", "panel", (184, 128), "panel"),
    ("ui_button_menu_primary_default", "common/buttons", "button", (180, 48), "button_primary_default"),
    ("ui_button_menu_primary_hover", "common/buttons", "button", (180, 48), "button_primary_hover"),
    ("ui_button_menu_primary_pressed", "common/buttons", "button", (180, 48), "button_primary_pressed"),
    ("ui_button_menu_primary_selected", "common/buttons", "button", (180, 48), "button_primary_selected"),
    ("ui_button_menu_primary_disabled", "common/buttons", "button", (180, 48), "button_primary_disabled"),
    ("ui_button_menu_secondary_default", "common/buttons", "button", (180, 48), "button_secondary_default"),
    ("ui_button_menu_secondary_hover", "common/buttons", "button", (180, 48), "button_secondary_hover"),
    ("ui_button_menu_secondary_pressed", "common/buttons", "button", (180, 48), "button_secondary_pressed"),
    ("ui_button_menu_secondary_selected", "common/buttons", "button", (180, 48), "button_secondary_selected"),
    ("ui_button_menu_secondary_disabled", "common/buttons", "button", (180, 48), "button_secondary_disabled"),
    ("ui_icon_menu_start", "common/icons", "icon", (256, 256), "icon_menu_start"),
    ("ui_icon_menu_modes", "common/icons", "icon", (256, 256), "icon_menu_modes"),
    ("ui_icon_menu_guide", "common/icons", "icon", (256, 256), "icon_menu_guide"),
    ("ui_icon_menu_intro", "common/icons", "icon", (256, 256), "icon_menu_intro"),
]


def procedural_surface(role: str, size: tuple[int, int]) -> Image.Image:
    if role == "cover_label":
        image = Image.new("RGBA", size, (0, 0, 0, 0))
        draw = ImageDraw.Draw(image)
        width, height = size
        draw.rounded_rectangle((4, 4, width - 8, height - 8), 22, fill=(8, 38, 50, 125), outline=rgba(PALETTE["border"], 150), width=2)
        draw.arc((24, height - 52, 220, height + 34), 190, 345, fill=(255, 255, 255, 54), width=2)
        return image
    if role == "panel":
        image = rounded_panel(size)
        draw = ImageDraw.Draw(image)
        width, height = size
        if height > 120:
            draw_compass(draw, (width - 70, 68), 28, "selected")
        else:
            draw.arc((24, height - 30, 180, height + 18), 195, 340, fill=rgba(PALETTE["border"], 58), width=2)
        return image
    if role.startswith("button_primary_"):
        return button_surface(size, role.replace("button_primary_", ""), "friendly")
    if role.startswith("button_secondary_"):
        return button_surface(size, role.replace("button_secondary_", ""), "skill")
    if role == "icon_menu_start":
        return icon_menu_start()
    if role == "icon_menu_modes":
        return icon_menu_modes()
    if role == "icon_menu_guide":
        return icon_menu_guide()
    if role == "icon_menu_intro":
        return icon_menu_intro()
    raise ValueError(f"Unknown procedural UI role: {role}")


def save_procedural_assets() -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for name, out_dir, kind, size, role in PROCEDURAL_ASSETS:
        image = procedural_surface(role, size)
        output_dir = PROCESSED_ROOT / out_dir
        output_dir.mkdir(parents=True, exist_ok=True)
        output_path = output_dir / f"{name}.png"
        exports: list[str] = []
        if kind in {"icon", "marker"}:
            image = place_on_square(trim_alpha(image), 256)
            exports = save_scaled_icon_exports(image, name)
        image.save(output_path)
        alpha_bbox = image.getchannel("A").getbbox()
        if alpha_bbox is None:
            raise ValueError(f"{name} produced empty alpha")
        records.append(
            {
                "name": name,
                "kind": kind,
                "source": "procedural_textless_ui",
                "crop_box": [0, 0, image.width, image.height],
                "output": str(output_path.relative_to(ROOT)),
                "size": [image.width, image.height],
                "alpha_bbox": list(alpha_bbox),
                "exports": exports,
            }
        )
    return records


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


def draw_wrapped_text(draw: ImageDraw.ImageDraw, xy: tuple[int, int], text: str, width: int, font: ImageFont.ImageFont, fill: str, line_height: int = 24) -> None:
    x, y = xy
    line = ""
    for paragraph in text.split("\n"):
        if not paragraph:
            y += line_height
            continue
        for char in paragraph:
            candidate = line + char
            if draw.textlength(candidate, font=font) > width and line:
                draw.text((x, y), line, font=font, fill=fill)
                y += line_height
                line = char
            else:
                line = candidate
        if line:
            draw.text((x, y), line, font=font, fill=fill)
            y += line_height
            line = ""


def load_font(size: int) -> ImageFont.ImageFont:
    candidates = [
        "/System/Library/Fonts/PingFang.ttc",
        "/System/Library/Fonts/STHeiti Light.ttc",
        "/Library/Fonts/Arial Unicode.ttf",
    ]
    for candidate in candidates:
        try:
            return ImageFont.truetype(candidate, size=size)
        except OSError:
            continue
    return ImageFont.load_default()


def paste_asset(canvas: Image.Image, asset_path: str, xy: tuple[int, int]) -> None:
    asset = Image.open(ROOT / asset_path).convert("RGBA")
    canvas.alpha_composite(asset, xy)


def text_slot_manifest() -> dict[str, Any]:
    return {
        "schema": "tiny_sea_war.ui_text_slots.v1",
        "coordinate_space": [1920, 1080],
        "notes": [
            "Runtime UI art does not bake text into PNG assets.",
            "QA preview images may render sample text only for readability checks.",
        ],
        "screens": {
            "main_menu": {
                "background": "programmatic_ocean",
                "panels": [
                    {"asset": "ui_panel_menu_title", "rect": [56, 56, 620, 190]},
                    {"asset": "ui_panel_menu_info", "rect": [56, 284, 650, 420]},
                    {"asset": "ui_panel_menu_footer", "rect": [56, 938, 650, 88]},
                    {"asset": "ui_panel_menu_cover_label", "rect": [844, 930, 520, 74]},
                ],
                "buttons": [
                    {"id": "btn_mode_1v1", "asset": "ui_button_menu_primary_default", "rect": [84, 724, 180, 48], "text_slot": [146, 734, 104, 28]},
                    {"id": "btn_mode_3v3", "asset": "ui_button_menu_primary_default", "rect": [284, 724, 180, 48], "text_slot": [346, 734, 104, 28]},
                    {"id": "btn_more_modes", "asset": "ui_button_menu_secondary_default", "rect": [484, 724, 180, 48], "text_slot": [546, 734, 104, 28]},
                    {"id": "btn_operation", "asset": "ui_button_menu_secondary_default", "rect": [84, 786, 180, 48], "text_slot": [146, 796, 104, 28]},
                    {"id": "btn_game_intro", "asset": "ui_button_menu_secondary_default", "rect": [284, 786, 180, 48], "text_slot": [346, 796, 104, 28]},
                    {"id": "btn_mode_help", "asset": "ui_button_menu_secondary_selected", "rect": [484, 786, 180, 48], "text_slot": [546, 796, 104, 28]},
                ],
                "text_slots": [
                    {"id": "title", "rect": [84, 92, 540, 56], "font_size": 44, "color": "text"},
                    {"id": "subtitle", "rect": [84, 156, 540, 28], "font_size": 20, "color": "soft"},
                    {"id": "tagline", "rect": [84, 194, 540, 28], "font_size": 18, "color": "text"},
                    {"id": "info_title", "rect": [84, 316, 570, 38], "font_size": 28, "color": "text"},
                    {"id": "info_body", "rect": [84, 392, 594, 260], "font_size": 18, "color": "text", "line_height": 26},
                    {"id": "footer_line_1", "rect": [82, 966, 596, 24], "font_size": 18, "color": "soft"},
                    {"id": "footer_line_2", "rect": [82, 998, 596, 22], "font_size": 16, "color": "soft"},
                    {"id": "cover_label", "rect": [884, 954, 440, 26], "font_size": 20, "color": "inverse"},
                ],
            },
            "pause_dialog": {
                "panels": [{"asset": "ui_panel_pause_dialog", "rect": [750, 484, 420, 112]}],
                "icons": [{"asset": "ui_icon_pause", "rect": [780, 518, 44, 44]}],
                "text_slots": [
                    {"id": "pause_title", "rect": [842, 520, 280, 34], "font_size": 28, "color": "text"},
                    {"id": "pause_hint", "rect": [842, 560, 280, 24], "font_size": 16, "color": "soft"},
                ],
            },
            "battle_result": {
                "panels": [{"asset": "ui_panel_result_dialog", "rect": [470, 230, 980, 620]}],
                "text_slots": [
                    {"id": "result_title", "rect": [1000, 320, 360, 70], "font_size": 54, "color": "text"},
                    {"id": "result_subtitle", "rect": [1002, 386, 360, 34], "font_size": 22, "color": "soft"},
                    {"id": "result_rows", "rect": [1004, 456, 360, 190], "font_size": 22, "color": "text", "line_height": 42},
                    {"id": "review_tip", "rect": [1004, 668, 360, 54], "font_size": 18, "color": "soft"},
                ],
                "buttons": [
                    {"id": "btn_return_main", "asset": "ui_button_menu_secondary_default", "rect": [944, 746, 180, 48], "text_slot": [986, 756, 118, 28]},
                    {"id": "btn_restart", "asset": "ui_button_menu_primary_default", "rect": [1144, 746, 180, 48], "text_slot": [1186, 756, 118, 28]},
                ],
            },
        },
    }


def ocean_preview(size: tuple[int, int]) -> Image.Image:
    image = Image.new("RGBA", size, rgba("#D8EEF3", 255))
    draw = ImageDraw.Draw(image)
    for index in range(18):
        y = index * 74 + 28
        draw.line((0, y, size[0], y + int(__import__("math").sin(index) * 28)), fill=(77, 171, 199, 34 if index % 2 == 0 else 22), width=3)
    overlay = Image.new("RGBA", size, (255, 255, 255, 56))
    image.alpha_composite(overlay)
    return image


def build_menu_preview(records_by_name: dict[str, dict[str, Any]], filename: str, title: str, body: str) -> None:
    canvas = ocean_preview((1920, 1080))
    draw = ImageDraw.Draw(canvas)
    paste_asset(canvas, records_by_name["ui_panel_menu_title"]["output"], (56, 56))
    paste_asset(canvas, records_by_name["ui_panel_menu_info"]["output"], (56, 284))
    paste_asset(canvas, records_by_name["ui_panel_menu_footer"]["output"], (56, 938))
    draw.rounded_rectangle((840, 86, 1800, 920), 38, fill=(255, 255, 255, 58), outline=rgba(PALETTE["border"], 110), width=2)
    draw_compass(draw, (1340, 490), 178, "selected")
    paste_asset(canvas, records_by_name["ui_panel_menu_cover_label"]["output"], (844, 930))
    buttons = [
        ("ui_button_menu_primary_default", (84, 724), "开始 1v1", "ui_icon_menu_start"),
        ("ui_button_menu_primary_default", (284, 724), "开始 3v3", "ui_icon_menu_start"),
        ("ui_button_menu_secondary_default", (484, 724), "更多模式", "ui_icon_menu_modes"),
        ("ui_button_menu_secondary_default", (84, 786), "操作说明", "ui_icon_menu_guide"),
        ("ui_button_menu_secondary_default", (284, 786), "游戏介绍", "ui_icon_menu_intro"),
        ("ui_button_menu_secondary_selected", (484, 786), "选择模式", "ui_icon_menu_modes"),
    ]
    font_button = load_font(18)
    for asset_name, xy, label, icon_name in buttons:
        paste_asset(canvas, records_by_name[asset_name]["output"], xy)
        icon = Image.open(ROOT / records_by_name[icon_name]["exports"][1]).convert("RGBA")
        canvas.alpha_composite(icon, (xy[0] + 16, xy[1] - 8))
        draw.text((xy[0] + 68, xy[1] + 14), label, font=font_button, fill=PALETTE["text"])
    font_title = load_font(44)
    font_subtitle = load_font(20)
    font_body = load_font(18)
    draw.text((84, 92), "Tiny Sea War", font=font_title, fill=PALETTE["text"])
    draw.text((84, 156), "Open Sea Fleet Tactics Prototype", font=font_subtitle, fill=PALETTE["soft"])
    draw.text((84, 194), "选择模式，阅读操作，再把舰队带上海面。", font=font_body, fill=PALETTE["text"])
    draw.text((84, 316), title, font=load_font(28), fill=PALETTE["text"])
    draw.rounded_rectangle((84, 348, 180, 352), 2, fill=PALETTE["selected"])
    draw_wrapped_text(draw, (84, 392), body, 594, font_body, PALETTE["text"], 26)
    draw.text((82, 966), "提示：先用 1v1 熟悉 E 瞄准和右键取消，再进入 3v3 练习多角色切换。", font=font_body, fill=PALETTE["soft"])
    draw.text((82, 998), "主界面封面每次启动随机从角色横向技能立绘中选择。", font=load_font(16), fill=PALETTE["soft"])
    draw.text((884, 954), "Today's Cover: Warspite", font=font_subtitle, fill="#FFFFFF")
    QA_ROOT.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(QA_ROOT / filename)


def build_result_preview(records_by_name: dict[str, dict[str, Any]]) -> None:
    canvas = ocean_preview((1920, 1080))
    overlay = Image.new("RGBA", canvas.size, (0, 15, 26, 82))
    canvas.alpha_composite(overlay)
    draw = ImageDraw.Draw(canvas)
    rect = (470, 230)
    panel = Image.open(ROOT / records_by_name["ui_panel_result_dialog"]["output"]).convert("RGBA").resize((980, 620), RESAMPLE_LANCZOS)
    canvas.alpha_composite(panel, rect)
    draw.rounded_rectangle((504, 258, 904, 806), 30, fill=(232, 247, 251, 120), outline=rgba(PALETTE["border"], 180), width=2)
    draw_compass(draw, (704, 530), 130, "selected")
    font_title = load_font(54)
    font_body = load_font(22)
    draw.text((1000, 320), "胜利", font=font_title, fill=PALETTE["text"])
    draw.rounded_rectangle((1002, 384, 1134, 389), 3, fill=PALETTE["positive"])
    draw.text((1002, 420), "敌方旗舰已经失去作战能力。", font=font_body, fill=PALETTE["soft"])
    rows = ["战斗模式：prototype_3v3", "战斗时长：03:42", "结算原因：FLAGSHIP_SUNK", "胜利阵营：player"]
    for index, row in enumerate(rows):
        draw.text((1004, 506 + index * 42), row, font=font_body, fill=PALETTE["text"])
    draw.text((1004, 704), "复盘提示：留意主要武器待发时间、集火目标和旗舰位置。", font=load_font(18), fill=PALETTE["soft"])
    paste_asset(canvas, records_by_name["ui_button_menu_secondary_default"]["output"], (944, 746))
    paste_asset(canvas, records_by_name["ui_button_menu_primary_default"]["output"], (1144, 746))
    draw.text((990, 760), "返回主界面", font=load_font(18), fill=PALETTE["text"])
    draw.text((1198, 760), "再玩一次", font=load_font(18), fill=PALETTE["text"])
    canvas.convert("RGB").save(QA_ROOT / "ui_result_filled_preview.png")


def build_filled_previews(records: list[dict[str, Any]]) -> None:
    records_by_name = {record["name"]: record for record in records}
    build_menu_preview(
        records_by_name,
        "ui_menu_mode_filled_preview.png",
        "选择模式",
        "请选择本次出击模式。\n\n1v1：单舰对决，适合熟悉镜头、选择、主要武器瞄准和旗舰胜负。\n\n3v3：小队舰队战，适合练习角色槽位切换、集火目标、技能和小地图阅读。\n\n更多模式：展示后续扩展方向，当前作为设计预览。",
    )
    build_menu_preview(
        records_by_name,
        "ui_menu_operation_filled_preview.png",
        "操作说明",
        "基础 UI：顶部左右为敌我舰队头像栏，左下角是战术小地图，右侧是战斗日志和选中单位信息。\n\n键鼠操作：1-9 / 0 / - 切换己方角色；左键选择或确认瞄准；右键移动或取消；E 主要武器；Q 切换 HE/AP；F 技能；V 跟踪镜头；WASD 移动镜头；Space 暂停；Esc 取消。",
    )
    build_result_preview(records_by_name)


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

    records.extend(save_procedural_assets())

    manifest = {
        "generator": "OpenAI built-in image generation + procedural textless UI surfaces",
        "model": "gpt-image-2 + Pillow",
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
    layout_root = UI_ROOT / "layout"
    layout_root.mkdir(parents=True, exist_ok=True)
    (layout_root / "ui_text_slots.json").write_text(
        json.dumps(text_slot_manifest(), indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    build_contact_sheet(records, "checker", "ui_asset_contact.png")
    build_contact_sheet(records, "#173746", "ui_asset_contact_dark.png")
    build_contact_sheet(records, "#ffffff", "ui_asset_contact_light.png")
    build_one_x_contact(records)
    build_24px_contact(records)
    build_filled_previews(records)
    print(f"Processed {len(records)} UI assets")
    print(QA_ROOT / "ui_asset_manifest.json")
    print(layout_root / "ui_text_slots.json")
    print(QA_ROOT / "ui_asset_contact.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
