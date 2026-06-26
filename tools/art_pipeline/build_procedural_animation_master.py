from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance

import postprocess_generated_character as pipeline


ROOT = Path(__file__).resolve().parents[2]
CHAR_ROOT = ROOT / "assets" / "characters"
QA_ROOT = CHAR_ROOT / "qa" / "procedural_animation_placeholders"
GREEN = (0, 255, 0, 255)
CELL_SIZE = (384, 512)
ANIMATION_STATES = ("idle", "move", "attack", "hit", "firepower")


def _fit_subject(subject: Image.Image, maximum: tuple[int, int]) -> Image.Image:
    fitted = subject.copy()
    fitted.thumbnail(maximum, getattr(Image, "Resampling", Image).LANCZOS)
    return fitted


def _tint(subject: Image.Image, color: tuple[int, int, int], strength: float) -> Image.Image:
    solid = Image.new("RGBA", subject.size, (*color, 255))
    tinted = Image.blend(subject, solid, strength)
    tinted.putalpha(subject.getchannel("A"))
    return tinted


def _frame(
    subject: Image.Image,
    state: str,
    index: int,
) -> Image.Image:
    width, height = CELL_SIZE
    frame = Image.new("RGBA", CELL_SIZE, GREEN)
    draw = ImageDraw.Draw(frame, "RGBA")

    y_offsets = {
        "idle": (2, 0, -2, 0),
        "move": (4, 1, -1, 2),
        "attack": (0, 0, 1, 0),
        "hit": (0, 3, -1, 1),
        "firepower": (2, 0, -2, 0),
    }
    x_offsets = {
        "idle": (0, 0, 0, 0),
        "move": (-5, -1, 4, 0),
        "attack": (0, -4, -8, 0),
        "hit": (0, -7, 5, 0),
        "firepower": (0, 0, 0, 0),
    }
    rotations = {
        "idle": (0.0, 0.4, 0.0, -0.4),
        "move": (-1.2, -0.4, 0.7, 0.0),
        "attack": (0.0, -1.0, -1.8, 0.0),
        "hit": (0.0, -2.0, 1.5, 0.0),
        "firepower": (0.0, 0.5, 0.0, -0.5),
    }
    scales = {
        "idle": (1.0, 1.006, 1.012, 1.006),
        "move": (1.0, 1.0, 1.0, 1.0),
        "attack": (1.0, 1.01, 1.015, 1.0),
        "hit": (1.0, 0.99, 1.01, 1.0),
        "firepower": (1.0, 1.015, 1.025, 1.01),
    }

    if state == "firepower":
        radius = (112, 122, 132, 120)[index]
        cx, cy = width // 2, int(height * 0.56)
        draw.ellipse(
            (cx - radius, cy - radius // 2, cx + radius, cy + radius // 2),
            outline=(70, 190, 255, 130),
            width=5,
        )
        draw.ellipse(
            (cx - radius + 14, cy - radius // 2 + 7, cx + radius - 14, cy + radius // 2 - 7),
            outline=(190, 235, 255, 95),
            width=3,
        )

    transformed = subject
    scale = scales[state][index]
    if scale != 1.0:
        transformed = transformed.resize(
            (max(1, round(subject.width * scale)), max(1, round(subject.height * scale))),
            getattr(Image, "Resampling", Image).LANCZOS,
        )
    angle = rotations[state][index]
    if angle:
        transformed = transformed.rotate(
            angle,
            resample=getattr(Image, "Resampling", Image).BICUBIC,
            expand=True,
        )
    if state == "hit" and index in (1, 2):
        transformed = _tint(transformed, (255, 105, 90), 0.13)
    if state == "attack" and index in (1, 2):
        transformed = ImageEnhance.Contrast(transformed).enhance(1.05)

    x = (width - transformed.width) // 2 + x_offsets[state][index]
    y = height - transformed.height - 28 + y_offsets[state][index]
    frame.alpha_composite(transformed, (x, y))

    if state == "attack" and index in (1, 2):
        flash_x = min(width - 44, x + transformed.width - 30)
        flash_y = max(48, y + transformed.height // 2)
        size = 18 if index == 1 else 28
        draw.polygon(
            [
                (flash_x - size, flash_y),
                (flash_x, flash_y - size // 3),
                (flash_x + size, flash_y),
                (flash_x, flash_y + size // 3),
            ],
            fill=(255, 188, 55, 220),
        )
        draw.ellipse(
            (flash_x - 7, flash_y - 7, flash_x + 7, flash_y + 7),
            fill=(255, 250, 220, 245),
        )

    return frame


def write_placeholder_provenance(character_id: str, out_root: Path, outputs: list[Path]) -> Path:
    path = out_root / "placeholder_source_provenance.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "character_id": character_id,
        "source": "tools/art_pipeline/build_procedural_animation_master.py",
        "kind": "procedural_animation_placeholder",
        "batch_ready_allowed": False,
        "notes": (
            "Smoke-test placeholder only. These sheets are derived from one battle-body cell using "
            "programmatic transforms. They do not satisfy the final TinySeaWar character animation contract."
        ),
        "outputs": [str(path.relative_to(ROOT)) for path in outputs],
    }
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return path


def build(character_id: str) -> list[Path]:
    root = CHAR_ROOT / character_id
    battle_path = root / "battle" / f"{character_id}_battle_asset_grid.png"
    if not battle_path.exists():
        raise FileNotFoundError(f"battle grid missing: {battle_path}")

    alpha_grid = pipeline.remove_generated_background(battle_path)
    body_cell = pipeline.split_grid(alpha_grid, rows=2, cols=4)[0]
    body_cell = pipeline.keep_largest_alpha_component(body_cell)
    subject, _meta = pipeline.crop_with_padding(body_cell, pad=20)
    subject = _fit_subject(subject, (CELL_SIZE[0] - 72, CELL_SIZE[1] - 72))

    outputs: list[Path] = []
    out_root = QA_ROOT / character_id / "battle"
    for state in ANIMATION_STATES:
        sheet = Image.new("RGBA", (CELL_SIZE[0] * 2, CELL_SIZE[1] * 2), GREEN)
        for col in range(4):
            sheet.alpha_composite(
                _frame(subject, state, col),
                ((col % 2) * CELL_SIZE[0], (col // 2) * CELL_SIZE[1]),
            )

        out = out_root / f"{character_id}_anim_{state}_4f_sheet.png"
        out.parent.mkdir(parents=True, exist_ok=True)
        sheet.convert("RGB").save(out)
        outputs.append(out)
    outputs.append(write_placeholder_provenance(character_id, QA_ROOT / character_id, outputs))
    return outputs


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Build placeholder 2x2 animation state sheets from one approved battle-body cell. "
            "This command never writes runtime source assets and cannot produce batch-ready character art."
        )
    )
    parser.add_argument(
        "--allow-placeholder",
        action="store_true",
        help="Required acknowledgement: write non-production placeholder sheets under assets/characters/qa/.",
    )
    parser.add_argument("character_ids", nargs="+")
    args = parser.parse_args()
    if not args.allow_placeholder:
        parser.error(
            "procedural animation fallback generation is disabled for production. "
            "Use --allow-placeholder only for smoke tests; missing real animation assets must remain missing."
        )
    for character_id in args.character_ids:
        for path in build(character_id):
            print(f"placeholder: {path.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
