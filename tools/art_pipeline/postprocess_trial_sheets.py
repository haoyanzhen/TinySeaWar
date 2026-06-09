from __future__ import annotations

import json
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


def add_transparent_padding(img: Image.Image, pad: int = 16) -> Image.Image:
    out = Image.new("RGBA", (img.width + pad * 2, img.height + pad * 2), (0, 0, 0, 0))
    out.alpha_composite(img, (pad, pad))
    return out


def save_crop(src: Image.Image, box: tuple[int, int, int, int], out: Path) -> dict[str, Any]:
    crop = rgba_with_alpha_from_light_bg(src.crop(box))
    crop = trim_alpha(crop)
    crop = add_transparent_padding(crop)
    out.parent.mkdir(parents=True, exist_ok=True)
    crop.save(out)
    return {"file": rel(out), "size": list(crop.size), "mode": crop.mode, "source_box": list(box)}


def rel(path: Path) -> str:
    return str(path.relative_to(ROOT))


def point(x: int, y: int, note: str) -> dict[str, Any]:
    return {"x": x, "y": y, "note": note}


SPECS: dict[str, list[CropSpec]] = {
    "enterprise_cv6": [
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
        CropSpec("ui/hai_shih_illust_half.png", "processed/ui", "hai_shih_illust_half_alpha.png", (0, 0, 1024, 1536), ("illustration",)),
        CropSpec("ui/hai_shih_illust_skill_cutin.png", "processed/ui", "hai_shih_illust_skill_cutin_alpha.png", (0, 0, 1717, 916), ("cutin",)),
        CropSpec("ui/hai_shih_ui_sheet.png", "processed/ui", "hai_shih_ui_portrait.png", (10, 0, 520, 615), ("ui", "portrait")),
        CropSpec("ui/hai_shih_ui_sheet.png", "processed/ui", "hai_shih_ui_portrait_small.png", (600, 160, 885, 455), ("ui", "portrait_small")),
        CropSpec("ui/hai_shih_ui_sheet.png", "processed/ui", "hai_shih_ui_chibi_head.png", (1035, 135, 1360, 455), ("ui", "chibi")),
        CropSpec("ui/hai_shih_ui_sheet.png", "processed/ui", "hai_shih_expr_default.png", (105, 650, 380, 960), ("ui", "expression")),
        CropSpec("ui/hai_shih_ui_sheet.png", "processed/ui", "hai_shih_expr_alert.png", (470, 620, 760, 970), ("ui", "expression")),
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
    root = CHAR_ROOT / character_id
    manifest: dict[str, Any] = {
        "character_id": character_id,
        "pipeline_stage": "postprocess_trial_sheet_v1",
        "source_alpha": write_source_alpha(character_id),
        "components": [],
    }
    opened: dict[str, Image.Image] = {}
    for spec in SPECS[character_id]:
        src_path = root / spec.source
        if spec.source not in opened:
            opened[spec.source] = Image.open(src_path)
        out = root / spec.out_dir / spec.name
        item = save_crop(opened[spec.source], spec.box, out)
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


def main() -> None:
    for character_id in ("enterprise_cv6", "hai_shih"):
        process_character(character_id)


if __name__ == "__main__":
    main()
