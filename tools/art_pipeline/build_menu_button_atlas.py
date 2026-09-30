"""Register reviewed regions without resampling or altering ImageGen's native alpha."""
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets/ui/raw/frames/menu_naval_buttons_20260930_v1.png"
DEST = ROOT / "assets/ui/processed/menu/buttons"
ROWS = [
    ("primary_normal", "primary_hover", "primary_pressed"),
    ("secondary_normal", "secondary_selected", "disabled"),
    ("light_normal", "light_hover", "light_pressed"),
    ("focus", "warning", "back"),
]


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    atlas = DEST / "ui_menu_buttons_atlas.png"
    shutil.copyfile(SOURCE, atlas)
    atlas_path = atlas.relative_to(ROOT).as_posix()
    assets = []
    # Individually reviewed gutters; constant cell dimensions avoid state-size jitter.
    for row, names in enumerate(ROWS):
        for col, state in enumerate(names):
            x, y = (18, 684, 1343)[col], (20, 200, 382, 568)[row]
            name = f"ui_button_naval_{state}"
            target = DEST / f"{name}.tres"
            target.write_text(
                '[gd_resource type="AtlasTexture" load_steps=2 format=3]\n\n'
                f'[ext_resource type="Texture2D" path="res://{atlas_path}" id="1"]\n\n'
                '[resource]\natlas = ExtResource("1")\n'
                f'region = Rect2({x}, {y}, 658, 170)\nfilter_clip = true\n',
                encoding="utf-8",
            )
            assets.append({"name": name, "kind": "button", "source": SOURCE.relative_to(ROOT).as_posix(),
                           "crop_box": [x, y, x + 658, y + 170], "size": [658, 170],
                           "output": target.relative_to(ROOT).as_posix(), "exports": []})
    manifest = {"generator": "Codex built-in ImageGen; lossless Godot AtlasTexture regions",
                "source_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
                "asset_count": len(assets), "assets": assets}
    (DEST.parent / "button_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
