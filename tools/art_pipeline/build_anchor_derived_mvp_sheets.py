from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance

import postprocess_generated_character as pipeline


ROOT = Path(__file__).resolve().parents[2]
CHAR_ROOT = ROOT / "assets" / "characters"
GREEN = (0, 255, 0, 255)
UI_CELL = (448, 448)
BATTLE_CELL = (448, 448)

PORTRAIT_BOXES = {
    "baltimore": (220, 100, 760, 700),
    "wahoo": (500, 100, 1060, 650),
}


def _fit(image: Image.Image, size: tuple[int, int], margin: int = 42) -> Image.Image:
    fitted = image.copy()
    fitted.thumbnail(
        (size[0] - margin * 2, size[1] - margin * 2),
        getattr(Image, "Resampling", Image).LANCZOS,
    )
    return fitted


def _cell_with(image: Image.Image, size: tuple[int, int], y_bias: int = 0) -> Image.Image:
    cell = Image.new("RGBA", size, GREEN)
    fitted = _fit(image, size)
    cell.alpha_composite(
        fitted,
        ((size[0] - fitted.width) // 2, (size[1] - fitted.height) // 2 + y_bias),
    )
    return cell


def _portrait(full: Image.Image, character_id: str) -> Image.Image:
    box = PORTRAIT_BOXES.get(character_id)
    if box is None:
        bbox = pipeline.alpha_bbox(full) or (0, 0, full.width, full.height)
        left, top, right, bottom = bbox
        box = (left, top, right, top + int((bottom - top) * 0.52))
    portrait = full.crop(box)
    portrait, _meta = pipeline.crop_with_padding(portrait, pad=16)
    return portrait


def _tint(image: Image.Image, color: tuple[int, int, int], amount: float) -> Image.Image:
    overlay = Image.new("RGBA", image.size, (*color, 255))
    result = Image.blend(image, overlay, amount)
    result.putalpha(image.getchannel("A"))
    return result


def _skill_icon(character_id: str) -> Image.Image:
    icon = Image.new("RGBA", UI_CELL, GREEN)
    draw = ImageDraw.Draw(icon, "RGBA")
    cx, cy = UI_CELL[0] // 2, UI_CELL[1] // 2
    draw.ellipse((76, 76, 372, 372), fill=(14, 44, 78, 255), outline=(180, 225, 255, 255), width=12)
    if character_id == "baltimore":
        for radius in (52, 92, 132):
            draw.arc((cx - radius, cy - radius, cx + radius, cy + radius), 205, 335, fill=(75, 205, 255, 230), width=8)
        draw.line((132, 316, 318, 132), fill=(255, 205, 80, 255), width=20)
        draw.polygon(((306, 118), (346, 104), (332, 144)), fill=(255, 238, 180, 255))
    else:
        draw.polygon(((112, 258), (214, 176), (344, 222), (240, 236)), fill=(18, 26, 48, 255))
        draw.polygon(((214, 176), (236, 112), (258, 202)), fill=(18, 26, 48, 255))
        for radius in (72, 112):
            draw.arc((cx - radius, cy - radius, cx + radius, cy + radius), 15, 165, fill=(75, 205, 255, 230), width=8)
    return icon


def _class_icon(ship_class: str) -> Image.Image:
    icon = Image.new("RGBA", UI_CELL, GREEN)
    draw = ImageDraw.Draw(icon, "RGBA")
    draw.ellipse((76, 76, 372, 372), fill=(14, 44, 78, 255), outline=(180, 225, 255, 255), width=12)
    if ship_class == "submarine":
        draw.ellipse((112, 196, 336, 268), fill=(76, 105, 132, 255), outline=(220, 238, 248, 255), width=8)
        draw.rectangle((210, 166, 250, 220), fill=(76, 105, 132, 255))
        draw.line((230, 166, 230, 126), fill=(220, 238, 248, 255), width=8)
    else:
        draw.polygon(((100, 270), (148, 202), (310, 190), (352, 250), (310, 280), (144, 292)), fill=(76, 105, 132, 255), outline=(220, 238, 248, 255))
        draw.rectangle((188, 150, 274, 216), fill=(76, 105, 132, 255), outline=(220, 238, 248, 255), width=6)
    return icon


def build_ui(character_id: str, ship_class: str, full: Image.Image) -> Path:
    portrait = _portrait(full, character_id)
    small = portrait.resize((max(1, portrait.width // 2), max(1, portrait.height // 2)), getattr(Image, "Resampling", Image).LANCZOS)
    chibi = ImageEnhance.Color(full).enhance(1.08)
    cells = [
        _cell_with(portrait, UI_CELL),
        _cell_with(small, UI_CELL),
        _cell_with(chibi, UI_CELL),
        _cell_with(portrait, UI_CELL),
        _cell_with(_tint(portrait, (80, 125, 175), 0.06), UI_CELL),
        _cell_with(_tint(portrait, (220, 95, 85), 0.10), UI_CELL),
        _skill_icon(character_id),
        _class_icon(ship_class),
    ]
    sheet = Image.new("RGBA", (UI_CELL[0] * 4, UI_CELL[1] * 2), GREEN)
    for index, cell in enumerate(cells):
        sheet.alpha_composite(cell, ((index % 4) * UI_CELL[0], (index // 4) * UI_CELL[1]))
    out = CHAR_ROOT / character_id / "ui" / f"{character_id}_ui_sheet.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.convert("RGB").save(out)
    return out


def _node(role: str) -> Image.Image:
    cell = Image.new("RGBA", BATTLE_CELL, GREEN)
    draw = ImageDraw.Draw(cell, "RGBA")
    steel = (78, 92, 108, 255)
    edge = (205, 225, 238, 255)
    blue = (68, 190, 250, 255)
    cx, cy = BATTLE_CELL[0] // 2, BATTLE_CELL[1] // 2

    if role == "battle_rig_base":
        draw.ellipse((100, 190, 348, 310), fill=steel, outline=edge, width=8)
        draw.ellipse((156, 216, 292, 284), fill=(34, 44, 58, 255), outline=edge, width=6)
    elif "turret" in role:
        draw.rounded_rectangle((128, 178, 300, 304), radius=24, fill=steel, outline=edge, width=7)
        barrels = 3 if "main" in role else 2
        for index in range(barrels):
            y = 210 + index * 30
            draw.rounded_rectangle((280, y, 390, y + 16), radius=8, fill=steel, outline=edge, width=3)
    elif "torpedo_tube_fore" in role or "torpedo_tube_aft" in role:
        count = 6 if "fore" in role else 4
        start = cx - (count * 44) // 2
        for index in range(count):
            x = start + index * 44
            draw.ellipse((x, 182, x + 38, 220), fill=(25, 32, 42, 255), outline=edge, width=5)
            draw.rounded_rectangle((x, 202, x + 38, 318), radius=16, fill=steel, outline=edge, width=4)
    elif "fire_control" in role or "radar" in role or "sonar" in role:
        draw.ellipse((138, 138, 310, 310), outline=blue, width=10)
        for radius in (38, 74):
            draw.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), outline=(140, 230, 255, 190), width=6)
        draw.line((cx, 110, cx, 338), fill=edge, width=5)
        draw.line((110, cy, 338, cy), fill=edge, width=5)
    elif "aa_center" in role:
        draw.rounded_rectangle((150, 224, 298, 310), radius=18, fill=steel, outline=edge, width=7)
        for angle in (-44, -15, 15, 44):
            draw.line((cx, 238, cx + angle * 2, 132), fill=edge, width=10)
    elif "periscope" in role:
        draw.rounded_rectangle((202, 104, 246, 336), radius=16, fill=steel, outline=edge, width=6)
        draw.rounded_rectangle((222, 104, 324, 148), radius=16, fill=steel, outline=edge, width=6)
    elif "oxygen" in role:
        draw.rounded_rectangle((176, 92, 272, 356), radius=32, fill=(24, 34, 48, 255), outline=edge, width=7)
        draw.rectangle((195, 124, 253, 238), fill=(55, 188, 250, 255))
        draw.rectangle((195, 238, 253, 324), fill=(255, 145, 55, 255))
    elif "submerged_shadow" in role:
        draw.ellipse((62, 184, 386, 286), fill=(8, 25, 48, 180), outline=(50, 140, 200, 170), width=7)
    elif "wake" in role:
        for radius in (52, 88, 124):
            draw.ellipse((cx - radius, cy - radius // 3, cx + radius, cy + radius // 3), outline=(205, 245, 255, 220), width=7)
    else:
        draw.ellipse((148, 148, 300, 300), fill=steel, outline=edge, width=8)
    return cell


def build_battle(character_id: str, full: Image.Image, roles: list[str]) -> Path:
    cells = [_cell_with(full, BATTLE_CELL, y_bias=8)] + [_node(role) for role in roles[1:]]
    sheet = Image.new("RGBA", (BATTLE_CELL[0] * 4, BATTLE_CELL[1] * 2), GREEN)
    for index, cell in enumerate(cells[:8]):
        sheet.alpha_composite(cell, ((index % 4) * BATTLE_CELL[0], (index // 4) * BATTLE_CELL[1]))
    out = CHAR_ROOT / character_id / "battle" / f"{character_id}_battle_asset_grid.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.convert("RGB").save(out)
    return out


def build(character_id: str) -> list[Path]:
    root = CHAR_ROOT / character_id
    plan = json.loads((root / "postprocess_plan.json").read_text(encoding="utf-8"))
    concept = root / "concept" / f"{character_id}_concept_full.png"
    full = pipeline.remove_generated_background(concept)
    return [
        build_ui(character_id, str(plan["ship_class"]), full),
        build_battle(character_id, full, list(plan["battle_grid_roles"])),
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description="Build identity-safe MVP sheets directly from approved anchors.")
    parser.add_argument("character_ids", nargs="+")
    args = parser.parse_args()
    for character_id in args.character_ids:
        for path in build(character_id):
            print(f"generated: {path.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
