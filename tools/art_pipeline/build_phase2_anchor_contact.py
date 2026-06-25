from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw

import character_roster


ROOT = Path(__file__).resolve().parents[2]
CHAR_ROOT = ROOT / "assets" / "characters"
QA_ROOT = CHAR_ROOT / "qa"
FACTION_IDS = {
    "us": ("fletcher", "cleveland", "baltimore", "wahoo"),
    "uk": ("jervis", "belfast", "illustrious", "upholder"),
    "soviet": ("tashkent", "chapayev", "gangut", "k_21"),
    "german": ("z23", "nurnberg", "scharnhorst", "graf_zeppelin"),
    "japan": ("akizuki", "takao", "shokaku", "i_19"),
    "china": ("yat_sen", "chang_chun", "dingyuan", "hai_lung"),
}


def main() -> int:
    parser = argparse.ArgumentParser(description="Build phase-two style-anchor contact sheets.")
    parser.add_argument("faction", choices=tuple(FACTION_IDS))
    args = parser.parse_args()
    roster = character_roster.roster_by_id("phase2")
    tile_width, tile_height = 440, 660
    canvas = Image.new("RGB", (tile_width * 4, tile_height), "#14202a")
    draw = ImageDraw.Draw(canvas)
    resampling = getattr(Image, "Resampling", Image)
    for index, character_id in enumerate(FACTION_IDS[args.faction]):
        x = index * tile_width
        draw.rectangle((x + 8, 8, x + tile_width - 8, tile_height - 8), fill="#23333e", outline="#718895", width=2)
        draw.text((x + 20, 18), f"{character_id}  {roster[character_id].ship_class}", fill="#f3f7f9")
        path = CHAR_ROOT / character_id / "concept" / f"{character_id}_concept_full.png"
        if not path.exists():
            draw.line((x + 20, 60, x + tile_width - 20, tile_height - 24), fill="#d34b4b", width=5)
            draw.line((x + tile_width - 20, 60, x + 20, tile_height - 24), fill="#d34b4b", width=5)
            continue
        image = Image.open(path).convert("RGB")
        image.thumbnail((tile_width - 32, tile_height - 86), resampling.LANCZOS)
        px = x + (tile_width - image.width) // 2
        py = 58 + (tile_height - 74 - image.height) // 2
        canvas.paste(image, (px, py))
    QA_ROOT.mkdir(parents=True, exist_ok=True)
    out = QA_ROOT / f"phase2_{args.faction}_anchor_contact.png"
    canvas.save(out)
    print(out.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
