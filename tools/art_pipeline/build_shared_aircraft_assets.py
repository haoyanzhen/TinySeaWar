"""Build reviewed native-alpha aircraft sources; never synthesize aircraft artwork.

Run with uv run --locked python tools/art_pipeline/build_shared_aircraft_assets.py.
--check validates hashes, native alpha, runtime files and visual references read-only.
"""
import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "assets/vfx/combat"
SOURCE = BASE / "source/aircraft_shared_v2"
MANIFEST = BASE / "aircraft/shared_aircraft_manifest.json"
KINDS = ("fighter", "bomber", "torpedo_bomber", "scout", "asw")
OBSERVATIONS = {
    "fighter": "Single top-down compact tapered-wing fighter, retracted gear, no glow or payload.",
    "bomber": "Single intact broad-wing bomber, top-down right-facing, no baked flight effects.",
    "torpedo_bomber": "Long narrow fuselage and short angular wings; clean replacement after two rejected glow attempts.",
    "scout": "Distinct long narrow wings and light fuselage, no detached parts or baked shadow.",
    "asw": "Two intact symmetric wing engines and tail sensor boom; no extra engines or external ordnance.",
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def relative(path):
    return path.relative_to(ROOT).as_posix()


def read_source(kind):
    path = SOURCE / f"{kind}.png"
    image = Image.open(path)
    assert image.mode == "RGBA", f"native RGBA required: {path}"
    alpha = image.getchannel("A")
    assert alpha.getextrema() == (0, 255), f"transparent and opaque pixels required: {path}"
    assert alpha.histogram()[0] > image.width * image.height * 0.25, f"opaque background: {path}"
    box = alpha.getbbox()
    assert box and box[0] > 0 and box[1] > 0 and box[2] < image.width and box[3] < image.height, f"clipped source: {path}"
    return image, box


def runtime_image(kind):
    image, box = read_source(kind)
    # Single isolated source, not a grid sheet. Preserve all nonzero-alpha pixels.
    sprite = image.crop(box)
    sprite.thumbnail((224, 224), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (256, 256))
    canvas.alpha_composite(sprite, ((256 - sprite.width) // 2, (256 - sprite.height) // 2))
    return canvas, box


def public_entries():
    """Authoritative replacements for the legacy procedural VFX generator."""
    if not MANIFEST.exists():
        return []
    return [{"semantic": f"aircraft.{e['kind']}", "category": "aircraft", "file": e["file"],
             "source": "codex_builtin_imagegen", "width": 256, "height": 256, "alpha": True,
             "provenance": relative(MANIFEST)} for e in json.loads(MANIFEST.read_text())["assets"]]


def build_preview(entries):
    qa = BASE / "qa"
    qa.mkdir(exist_ok=True)
    sheet = Image.new("RGB", (1100, 760), "#142a38")
    draw = ImageDraw.Draw(sheet)
    draw.text((24, 16), "SHARED AIRCRAFT v2 | top-down / nose right / native alpha", fill="white")
    draw.text((24, 38), "Static asset review only. Runtime flight, shadows, markers and LOD remain pending.", fill="#bfd3df")
    for i, e in enumerate(entries):
        x = i * 216 + 10
        im = Image.open(ROOT / e["file"])
        draw.text((x + 8, 74), e["kind"], fill="white")
        for j, color in enumerate(("#142a38", "#e7eef2", "checker")):
            y = 102 + j * 154
            tile = Image.new("RGBA", (196, 140), color if color != "checker" else "#b1bcc6")
            if color == "checker":
                td = ImageDraw.Draw(tile)
                for xx in range(0, 196, 14):
                    for yy in range(0, 140, 14):
                        if (xx // 14 + yy // 14) % 2:
                            td.rectangle((xx, yy, xx + 13, yy + 13), fill="#dce4ea")
            thumb = im.copy()
            thumb.thumbnail((138, 138), Image.Resampling.LANCZOS)
            tile.alpha_composite(thumb, ((196 - thumb.width)//2, (140 - thumb.height)//2))
            sheet.paste(tile.convert("RGB"), (x, y))
        for j, size in enumerate((18, 24, 28, 48)):
            y = 584 + j * 38
            thumb = im.resize((size, size), Image.Resampling.LANCZOS)
            sheet.paste(thumb, (x + 18, y), thumb)
            draw.text((x + 82, y + 4), f"{size}px canvas", fill="white")
    sheet.save(qa / "shared_aircraft_v2_contact.png")


def build():
    entries = []
    for kind in KINDS:
        canvas, box = runtime_image(kind)
        path = BASE / f"aircraft/aircraft_{kind}_v2.png"
        canvas.save(path)
        entries.append({"kind": kind, "semantic": f"visual.projectile.aircraft.{kind}",
                        "file": relative(path), "source_file": relative(SOURCE / f"{kind}.png"),
                        "source_sha256": sha(SOURCE / f"{kind}.png"), "sha256": sha(path),
                        "source_alpha_bbox": list(box), "canvas_size": [256, 256],
                        "heading_degrees": 0, "reviewer": "Codex static pixel review",
                        "review": "pass", "observation": OBSERVATIONS[kind], "in_engine_review": "pending"})
    MANIFEST.write_text(json.dumps({"schema_version": 1, "generation": relative(SOURCE / "generation.json"),
        "processing": "full-alpha bounding trim, proportional Lanczos resize to 224px max, centered 256px canvas; no chroma key or alpha replacement",
        "assets": entries}, indent=2) + "\n")
    public = BASE / "qa/combat_vfx_asset_manifest.json"
    data = json.loads(public.read_text())
    replacements = {e["semantic"]: e for e in public_entries()}
    data["assets"] = [replacements.pop(e["semantic"], e) for e in data["assets"]]
    data["assets"].extend(replacements.values())
    public.write_text(json.dumps(data, indent=2) + "\n")
    build_preview(entries)


def check():
    manifest = json.loads(MANIFEST.read_text())
    visuals = {v["id"]: v for v in json.loads((ROOT / "data/visuals/projectile_visuals.json").read_text())["definitions"]}
    public = {v["semantic"]: v for v in json.loads((BASE / "qa/combat_vfx_asset_manifest.json").read_text())["assets"]}
    assert {e["kind"] for e in manifest["assets"]} == set(KINDS)
    for e in manifest["assets"]:
        expected, _ = runtime_image(e["kind"])
        actual = Image.open(ROOT / e["file"])
        assert expected.tobytes() == actual.tobytes(), f"stale runtime image: {e['kind']}"
        assert sha(ROOT / e["source_file"]) == e["source_sha256"]
        assert sha(ROOT / e["file"]) == e["sha256"]
        assert visuals[e["semantic"]]["sprite"] == e["file"]
        assert public[f"aircraft.{e['kind']}"]["file"] == e["file"]
    print("PASS: 5 native-alpha sources, 5 reproducible sprites, hashes and both semantic mappings")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if not args.check:
        build()
    check()
