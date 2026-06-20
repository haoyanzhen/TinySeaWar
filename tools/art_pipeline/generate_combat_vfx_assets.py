#!/usr/bin/env python3
import argparse
import json
import math
import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[2]
COMBAT_ROOT = ROOT / "assets" / "vfx" / "combat"


def rgba(hex_color, alpha=255):
    text = hex_color.lstrip("#")
    return tuple(int(text[index:index + 2], 16) for index in (0, 2, 4)) + (alpha,)


def canvas(size):
    return Image.new("RGBA", (size, size), (0, 0, 0, 0))


def save(image, relative_path, manifest, semantic, category, source):
    path = COMBAT_ROOT / relative_path
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)
    manifest.append({
        "semantic": semantic,
        "category": category,
        "file": str(path.relative_to(ROOT)),
        "source": source,
        "width": image.width,
        "height": image.height,
        "alpha": True,
    })


def glow(size, center, color, radius, strength=1.0):
    layer = canvas(size)
    draw = ImageDraw.Draw(layer)
    for step in range(8, 0, -1):
        current = radius * step / 8.0
        alpha = int(22 * strength * (step / 8.0) ** 2)
        draw.ellipse((center[0] - current, center[1] - current, center[0] + current, center[1] + current), fill=(*color[:3], alpha))
    return layer.filter(ImageFilter.GaussianBlur(radius * 0.16))


def draw_shell(size, color, length, width):
    image = canvas(size)
    center = size / 2
    draw = ImageDraw.Draw(image)
    draw.line((center - length * 0.45, center, center + length * 0.32, center), fill=rgba(color, 210), width=width)
    draw.ellipse((center + length * 0.15, center - width * 1.3, center + length * 0.48, center + width * 1.3), fill=rgba("#fff7c8", 245))
    draw.polygon([(center + length * 0.52, center), (center + length * 0.22, center - width * 1.1), (center + length * 0.22, center + width * 1.1)], fill=rgba(color, 255))
    draw.line((center - length * 0.42, center, center - length * 0.08, center), fill=rgba("#ffffff", 130), width=max(1, width // 2))
    image.alpha_composite(glow(size, (center + length * 0.28, center), rgba(color), length * 0.45, 0.8))
    return image


def draw_torpedo(size, body, glow_color, long=False):
    image = canvas(size)
    center = size / 2
    length = size * (0.62 if long else 0.5)
    height = size * 0.12
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((center - length * 0.45, center - height * 0.45, center + length * 0.3, center + height * 0.45), radius=height * 0.35, fill=rgba(body, 245), outline=rgba("#d8fbff", 180), width=2)
    draw.polygon([(center + length * 0.46, center), (center + length * 0.24, center - height * 0.52), (center + length * 0.24, center + height * 0.52)], fill=rgba(body, 250))
    draw.polygon([(center - length * 0.46, center), (center - length * 0.34, center - height * 0.8), (center - length * 0.34, center + height * 0.8)], fill=rgba("#6c8492", 230))
    for index in range(5):
        x = center - length * (0.58 + index * 0.10)
        r = max(2.0, size * (0.034 - index * 0.003))
        draw.ellipse((x - r, center - r, x + r, center + r), fill=rgba(glow_color, max(42, 150 - index * 20)))
    image.alpha_composite(glow(size, (center + length * 0.08, center), rgba(glow_color), size * 0.22, 0.6))
    return image


def draw_aircraft(size, body, accent, kind="fighter"):
    image = canvas(size)
    draw = ImageDraw.Draw(image)
    center = size / 2
    length = size * (0.56 if kind != "bomber" else 0.62)
    wing = size * (0.34 if kind != "torpedo_bomber" else 0.38)
    tail = size * 0.16
    draw.polygon([
        (center + length * 0.48, center),
        (center + length * 0.08, center - size * 0.055),
        (center - length * 0.42, center - size * 0.04),
        (center - length * 0.48, center),
        (center - length * 0.42, center + size * 0.04),
        (center + length * 0.08, center + size * 0.055),
    ], fill=rgba(body, 245), outline=rgba("#ecf8ff", 150))
    draw.polygon([
        (center + length * 0.06, center - size * 0.035),
        (center - length * 0.16, center - wing),
        (center - length * 0.02, center - size * 0.025),
    ], fill=rgba(accent, 230))
    draw.polygon([
        (center + length * 0.06, center + size * 0.035),
        (center - length * 0.16, center + wing),
        (center - length * 0.02, center + size * 0.025),
    ], fill=rgba(accent, 230))
    draw.polygon([
        (center - length * 0.38, center - size * 0.025),
        (center - length * 0.5, center - tail),
        (center - length * 0.44, center),
    ], fill=rgba(body, 230))
    draw.polygon([
        (center - length * 0.38, center + size * 0.025),
        (center - length * 0.5, center + tail),
        (center - length * 0.44, center),
    ], fill=rgba(body, 230))
    if kind == "bomber":
        draw.ellipse((center - 8, center - 8, center + 8, center + 8), fill=rgba("#ffd166", 210))
    if kind == "torpedo_bomber":
        draw.rounded_rectangle((center - length * 0.1, center - 4, center + length * 0.28, center + 4), radius=3, fill=rgba("#5ec8ff", 210))
    image.alpha_composite(glow(size, (center, center), rgba(accent), size * 0.16, 0.35))
    return image


def draw_bomb(size, color="#5f6872"):
    image = canvas(size)
    draw = ImageDraw.Draw(image)
    center = size / 2
    length = size * 0.52
    width = size * 0.13
    draw.ellipse((center - width, center - length * 0.42, center + width, center + length * 0.2), fill=rgba(color, 245), outline=rgba("#ecf8ff", 120))
    draw.polygon([(center, center + length * 0.42), (center - width * 0.85, center + length * 0.16), (center + width * 0.85, center + length * 0.16)], fill=rgba(color, 245))
    draw.line((center - width * 0.55, center - length * 0.12, center + width * 0.55, center - length * 0.12), fill=rgba("#ffd166", 170), width=2)
    return image


def draw_aircraft_path(size, color):
    image = canvas(size)
    draw = ImageDraw.Draw(image)
    center = size / 2
    for index in range(4):
        y = center - size * 0.2 + index * size * 0.13
        draw.line((size * 0.18, y, size * 0.72, y + size * 0.06), fill=rgba(color, 95 - index * 12), width=3)
        draw.polygon([(size * 0.74, y + size * 0.06), (size * 0.66, y + size * 0.01), (size * 0.67, y + size * 0.1)], fill=rgba(color, 120 - index * 12))
    return image.filter(ImageFilter.GaussianBlur(0.25))


def draw_aircraft_fall(size):
    image = canvas(size)
    draw = ImageDraw.Draw(image)
    center = size / 2
    for radius, alpha, color in [(36, 80, "#ff6b35"), (24, 150, "#ffb347"), (12, 230, "#fff0a0")]:
        draw.ellipse((center - radius, center - radius, center + radius, center + radius), fill=rgba(color, alpha))
    for index in range(8):
        angle = index * math.tau / 8.0
        draw.line((center, center, center + math.cos(angle) * size * 0.34, center + math.sin(angle) * size * 0.34), fill=rgba("#ffcf73", 180), width=2)
    return image.filter(ImageFilter.GaussianBlur(0.2))


def draw_muzzle(size, color, smoke=False):
    image = canvas(size)
    center = size / 2
    draw = ImageDraw.Draw(image)
    if smoke:
        for index, offset in enumerate([-15, 0, 16]):
            draw.ellipse((center - 10 + offset, center - 14 - index * 3, center + 18 + offset, center + 15 + index * 2), fill=rgba("#9ea9aa", 55))
    points = []
    for index in range(16):
        angle = index * math.tau / 16.0
        radius = size * (0.17 if index % 2 == 0 else 0.38)
        points.append((center + math.cos(angle) * radius, center + math.sin(angle) * radius))
    draw.polygon(points, fill=rgba(color, 220))
    draw.ellipse((center - size * 0.15, center - size * 0.15, center + size * 0.15, center + size * 0.15), fill=rgba("#fff8d9", 250))
    image.alpha_composite(glow(size, (center, center), rgba(color), size * 0.34, 1.1))
    return image


def draw_splash(size, color, scale):
    image = canvas(size)
    draw = ImageDraw.Draw(image)
    center = size / 2
    for index in range(10):
        angle = -math.pi * 0.9 + index * math.pi * 1.8 / 9.0
        length = size * scale * (0.35 + 0.16 * (index % 3))
        start = (center + math.cos(angle) * size * 0.04, center + math.sin(angle) * size * 0.02)
        end = (center + math.cos(angle) * length, center + math.sin(angle) * length * 0.75)
        draw.line((*start, *end), fill=rgba(color, 210), width=max(2, int(size * scale * 0.035)))
        r = size * scale * 0.035
        draw.ellipse((end[0] - r, end[1] - r, end[0] + r, end[1] + r), fill=rgba("#f7fdff", 235))
    draw.ellipse((center - size * scale * 0.34, center - size * scale * 0.14, center + size * scale * 0.34, center + size * scale * 0.14), outline=rgba(color, 150), width=max(2, int(size * 0.02)))
    return image.filter(ImageFilter.GaussianBlur(0.25))


def draw_spark(size, color):
    image = canvas(size)
    draw = ImageDraw.Draw(image)
    center = size / 2
    for index in range(14):
        angle = index * math.tau / 14.0
        length = size * (0.22 + 0.18 * (index % 4) / 3.0)
        draw.line((center, center, center + math.cos(angle) * length, center + math.sin(angle) * length), fill=rgba(color, 230), width=2)
    draw.ellipse((center - 5, center - 5, center + 5, center + 5), fill=rgba("#fff8dc", 255))
    image.alpha_composite(glow(size, (center, center), rgba(color), size * 0.26, 0.9))
    return image


def draw_ring(size, color, width=4, dash=False, fill_alpha=18):
    image = canvas(size)
    draw = ImageDraw.Draw(image)
    margin = size * 0.15
    if fill_alpha:
        draw.ellipse((margin, margin, size - margin, size - margin), fill=rgba(color, fill_alpha))
    if dash:
        center = size / 2
        radius = size / 2 - margin
        for index in range(16):
            start = index * math.tau / 16.0
            end = start + math.tau / 32.0
            draw.arc((center - radius, center - radius, center + radius, center + radius), math.degrees(start), math.degrees(end), fill=rgba(color, 230), width=width)
    else:
        draw.ellipse((margin, margin, size - margin, size - margin), outline=rgba(color, 230), width=width)
    return image


def draw_fan(size, color):
    image = canvas(size)
    draw = ImageDraw.Draw(image)
    center = (size * 0.5, size * 0.78)
    box = (center[0] - size * 0.62, center[1] - size * 0.62, center[0] + size * 0.62, center[1] + size * 0.62)
    draw.pieslice(box, 220, 320, fill=rgba(color, 28), outline=rgba(color, 210), width=4)
    for angle in [220, 250, 290, 320]:
        rad = math.radians(angle)
        draw.line((center[0], center[1], center[0] + math.cos(rad) * size * 0.62, center[1] + math.sin(rad) * size * 0.62), fill=rgba(color, 150), width=2)
    return image


def draw_wake(size, color, wide=1.0):
    image = canvas(size)
    draw = ImageDraw.Draw(image)
    center = size / 2
    for side in [-1, 1]:
        points = []
        for index in range(9):
            t = index / 8.0
            x = center - size * 0.42 + size * 0.84 * t
            y = center + side * (size * 0.07 + wide * size * 0.19 * math.sin(t * math.pi))
            points.append((x, y))
        draw.line(points, fill=rgba(color, 150), width=max(2, int(size * 0.025 * wide)))
    for index in range(14):
        x = center - size * 0.4 + index * size * 0.06
        y = center + math.sin(index) * size * 0.035
        r = size * 0.018
        draw.ellipse((x - r, y - r, x + r, y + r), fill=rgba("#effdff", 100))
    return image.filter(ImageFilter.GaussianBlur(0.15))


def generate_assets(source_sheet):
    manifest = []
    source = "codex_procedural"

    save(draw_shell(96, "#ffd05e", 44, 4), Path("projectiles/shells/projectile_shell_small.png"), manifest, "visual.projectile.shell.small", "projectile", source)
    save(draw_shell(112, "#ffd777", 56, 5), Path("projectiles/shells/projectile_shell_medium.png"), manifest, "visual.projectile.shell.medium", "projectile", source)
    save(draw_shell(128, "#ffe089", 68, 6), Path("projectiles/shells/projectile_shell_large.png"), manifest, "visual.projectile.shell.large", "projectile", source)
    save(draw_shell(144, "#fff0a8", 80, 8), Path("projectiles/shells/projectile_shell_superheavy.png"), manifest, "visual.projectile.shell.superheavy", "projectile", source)

    save(draw_torpedo(128, "#465b68", "#85edff"), Path("projectiles/torpedoes/projectile_torpedo_surface.png"), manifest, "visual.projectile.torpedo.surface", "projectile", source)
    save(draw_torpedo(128, "#3e6573", "#9ff7ff", True), Path("projectiles/torpedoes/projectile_torpedo_fast.png"), manifest, "visual.projectile.torpedo.fast", "projectile", source)
    save(draw_torpedo(144, "#56616c", "#75d9ff", True), Path("projectiles/torpedoes/projectile_torpedo_heavy.png"), manifest, "visual.projectile.torpedo.heavy", "projectile", source)
    save(draw_torpedo(128, "#314a61", "#5ec8ff"), Path("projectiles/torpedoes/projectile_torpedo_submerged.png"), manifest, "visual.projectile.torpedo.submerged", "projectile", source)
    save(draw_torpedo(112, "#50616c", "#9eefff"), Path("projectiles/torpedoes/projectile_torpedo_air.png"), manifest, "visual.projectile.torpedo.air", "projectile", source)
    save(draw_bomb(96), Path("projectiles/bombs/projectile_air_bomb.png"), manifest, "visual.projectile.aircraft.bomb", "projectile", source)

    save(draw_aircraft(112, "#3d5368", "#8fd7ff", "fighter"), Path("aircraft/aircraft_fighter_01.png"), manifest, "aircraft.fighter", "aircraft", source)
    save(draw_aircraft(120, "#4c5968", "#ffd166", "bomber"), Path("aircraft/aircraft_bomber_01.png"), manifest, "aircraft.bomber", "aircraft", source)
    save(draw_aircraft(120, "#465b68", "#7de2ff", "torpedo_bomber"), Path("aircraft/aircraft_torpedo_bomber_01.png"), manifest, "aircraft.torpedo_bomber", "aircraft", source)
    save(draw_aircraft(104, "#40596b", "#c8f7ff", "scout"), Path("aircraft/aircraft_scout_01.png"), manifest, "aircraft.scout", "aircraft", source)
    save(draw_aircraft(112, "#445d62", "#9ff7ff", "asw"), Path("aircraft/aircraft_asw_01.png"), manifest, "aircraft.asw", "aircraft", source)

    save(draw_muzzle(128, "#ffd166"), Path("muzzle/vfx_muzzle_gun_small_01.png"), manifest, "muzzle_flash.small", "muzzle", source)
    save(draw_muzzle(144, "#ffbf69", True), Path("muzzle/vfx_muzzle_gun_medium_01.png"), manifest, "muzzle_flash.medium", "muzzle", source)
    save(draw_muzzle(160, "#ff9f43", True), Path("muzzle/vfx_muzzle_gun_large_01.png"), manifest, "muzzle_flash.large", "muzzle", source)
    save(draw_muzzle(112, "#bdf7ff"), Path("muzzle/vfx_muzzle_aa_high_angle_01.png"), manifest, "muzzle_flash.aa_high_angle", "muzzle", source)

    save(draw_shell(96, "#ffe37a", 38, 3), Path("trails/vfx_trail_shell_short_01.png"), manifest, "shell.trail.short", "trail", source)
    save(draw_shell(112, "#ffd36a", 52, 4), Path("trails/vfx_trail_shell_medium_01.png"), manifest, "shell.trail.medium", "trail", source)
    save(draw_shell(128, "#ffc45c", 68, 5), Path("trails/vfx_trail_shell_long_01.png"), manifest, "shell.trail.long", "trail", source)
    save(draw_wake(160, "#8fe8ff", 0.6), Path("trails/vfx_trail_torpedo_surface_01.png"), manifest, "torpedo.trail.surface", "trail", source)
    save(draw_wake(144, "#5fc8ff", 0.45), Path("trails/vfx_trail_torpedo_submerged_01.png"), manifest, "torpedo.trail.submerged", "trail", source)
    save(draw_spark(80, "#95f6ff"), Path("trails/vfx_particle_torpedo_bubble_01.png"), manifest, "torpedo.bubble.particle", "trail", source)

    save(draw_splash(112, "#dffbff", 0.62), Path("impacts/vfx_impact_water_small_01.png"), manifest, "impact.water.small", "impact", source)
    save(draw_splash(144, "#d4f6ff", 0.72), Path("impacts/vfx_impact_water_medium_01.png"), manifest, "impact.water.medium", "impact", source)
    save(draw_splash(176, "#c9f2ff", 0.82), Path("impacts/vfx_impact_water_large_01.png"), manifest, "impact.water.large", "impact", source)
    save(draw_spark(112, "#ffbf69"), Path("impacts/vfx_impact_armor_spark_01.png"), manifest, "impact.armor.spark", "impact", source)
    save(draw_spark(128, "#fff0a0"), Path("impacts/vfx_impact_armor_flash_01.png"), manifest, "impact.armor.flash", "impact", source)
    save(draw_ring(144, "#7fdcff", 5, False, 24), Path("impacts/vfx_impact_torpedo_underwater_01.png"), manifest, "impact.torpedo.underwater", "impact", source)

    save(draw_ring(128, "#ff5964", 4, True, 18), Path("warnings/vfx_warning_shell_area_01.png"), manifest, "warning.shell.area", "warning", source)
    save(draw_ring(128, "#ff5964", 5, False, 10), Path("warnings/vfx_warning_torpedo_line_01.png"), manifest, "torpedo.warning.line", "warning", source)
    save(draw_fan(160, "#ff5964"), Path("warnings/vfx_warning_torpedo_fan_01.png"), manifest, "torpedo.warning.fan", "warning", source)
    save(draw_ring(160, "#ffd166", 4, True, 16), Path("warnings/vfx_warning_airstrike_area_01.png"), manifest, "aircraft.airstrike_area", "warning", source)

    save(draw_shell(96, "#bdf7ff", 48, 2), Path("antiair/vfx_antiair_tracer_light_01.png"), manifest, "aa.tracer.light", "antiair", source)
    save(draw_shell(112, "#d4fbff", 56, 3), Path("antiair/vfx_antiair_tracer_medium_01.png"), manifest, "aa.tracer.medium", "antiair", source)
    save(draw_spark(96, "#dffbff"), Path("antiair/vfx_antiair_burst_small_01.png"), manifest, "aa.burst.small", "antiair", source)
    save(draw_spark(80, "#ffcf73"), Path("antiair/vfx_aircraft_intercept_hit_01.png"), manifest, "aircraft.intercept_hit", "antiair", source)
    save(draw_aircraft_fall(112), Path("antiair/vfx_aircraft_fall_explosion_01.png"), manifest, "aircraft.fall", "antiair", source)

    save(draw_ring(144, "#72d6ff", 4, True, 12), Path("antisubmarine/vfx_asw_sonar_pulse_01.png"), manifest, "submarine.sonar_pulse", "antisubmarine", source)
    save(draw_splash(128, "#9eefff", 0.52), Path("antisubmarine/vfx_asw_bubble_column_01.png"), manifest, "submarine.bubble_trail", "antisubmarine", source)
    save(draw_ring(128, "#9ce8ff", 5, False, 20), Path("antisubmarine/vfx_asw_underwater_blast_01.png"), manifest, "asw.underwater_blast", "antisubmarine", source)

    save(draw_wake(128, "#dffbff", 0.45), Path("wakes/vfx_wake_destroyer_fast_01.png"), manifest, "wake.destroyer_fast", "wake", source)
    save(draw_wake(144, "#d7f7ff", 0.68), Path("wakes/vfx_wake_cruiser_01.png"), manifest, "wake.cruiser", "wake", source)
    save(draw_wake(176, "#d4f1f5", 1.0), Path("wakes/vfx_wake_battleship_heavy_01.png"), manifest, "wake.battleship_heavy", "wake", source)
    save(draw_wake(176, "#d9f7ff", 1.22), Path("wakes/vfx_wake_carrier_wide_01.png"), manifest, "wake.carrier_wide", "wake", source)
    save(draw_wake(128, "#7bcfff", 0.3), Path("wakes/vfx_wake_submarine_low_01.png"), manifest, "wake.submarine_low", "wake", source)

    save(draw_ring(144, "#f8ef9a", 5, True, 22), Path("skills/vfx_skill_charge_common_01.png"), manifest, "skill.charge.common", "skill", source)
    save(draw_ring(128, "#ffb35c", 5, False, 8), Path("skills/vfx_skill_target_marker_01.png"), manifest, "skill.target_marker", "skill", source)
    save(draw_aircraft_path(128, "#bdefff"), Path("aircraft/vfx_aircraft_path_01.png"), manifest, "aircraft.path", "aircraft", source)
    save(draw_aircraft_path(112, "#dffbff"), Path("aircraft/vfx_aircraft_launch_trail_01.png"), manifest, "aircraft.launch_trail", "aircraft", source)
    save(draw_aircraft_path(112, "#c9f2ff"), Path("aircraft/vfx_aircraft_landing_trail_01.png"), manifest, "aircraft.landing_trail", "aircraft", source)

    if source_sheet:
        source_path = Path(source_sheet).expanduser()
        if source_path.exists():
            target = COMBAT_ROOT / "source" / "combat_vfx_gpt_image_2_source_sheet.png"
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source_path, target)
            manifest.append({
                "semantic": "source.gpt_image_2.combat_vfx_sheet",
                "category": "source",
                "file": str(target.relative_to(ROOT)),
                "source": "gpt-image-2",
                "width": None,
                "height": None,
                "alpha": False,
            })

    qa_dir = COMBAT_ROOT / "qa"
    qa_dir.mkdir(parents=True, exist_ok=True)
    (qa_dir / "combat_vfx_asset_manifest.json").write_text(json.dumps({"assets": manifest}, indent=2) + "\n", encoding="utf-8")
    (qa_dir / "combat_vfx_generation_report.md").write_text(build_report(manifest), encoding="utf-8")
    build_preview(manifest, qa_dir / "combat_vfx_preview.html")
    build_contact_sheet(manifest, qa_dir / "combat_vfx_contact_sheet.png")


def build_report(manifest):
    lines = [
        "# Combat VFX Generation Report",
        "",
        "Generated public TinySeaWar combat VFX assets for the runtime `data/visuals` profiles.",
        "",
        "- Source sheet: gpt-image-2 style source retained when available.",
        "- Runtime assets: transparent PNG generated by Codex for low-cost deterministic MVP hookup.",
        "- QA status: preliminary pass; requires in-engine scale/readability review during battle scene testing.",
        "",
        "| Category | Count |",
        "| --- | ---: |",
    ]
    counts = {}
    for item in manifest:
        counts[item["category"]] = counts.get(item["category"], 0) + 1
    for key in sorted(counts):
        lines.append(f"| {key} | {counts[key]} |")
    lines.extend(["", "## Assets", ""])
    for item in manifest:
        lines.append(f"- `{item['semantic']}` -> `{item['file']}`")
    lines.append("")
    return "\n".join(lines)


def build_preview(manifest, path):
    cards = []
    for item in manifest:
        if item["category"] == "source":
            continue
        rel = Path("..") / Path(item["file"]).relative_to("assets/vfx/combat")
        cards.append(f"<article><img src='{rel.as_posix()}'><strong>{item['semantic']}</strong><span>{item['file']}</span></article>")
    html = """<!doctype html>
<html><head><meta charset="utf-8"><title>Combat VFX Preview</title>
<style>
body{font-family:-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif;background:#121922;color:#eef6fb;margin:0;padding:24px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(190px,1fr));gap:14px}
article{background:#1e2a35;border:1px solid #314352;border-radius:8px;padding:12px;min-height:190px}
img{width:128px;height:128px;object-fit:contain;display:block;margin:0 auto 10px;background:linear-gradient(45deg,#26323d 25%,transparent 25%),linear-gradient(-45deg,#26323d 25%,transparent 25%),linear-gradient(45deg,transparent 75%,#26323d 75%),linear-gradient(-45deg,transparent 75%,#26323d 75%);background-size:24px 24px;background-position:0 0,0 12px,12px -12px,-12px 0}
strong{display:block;font-size:13px;color:#f8ef9a}span{display:block;font-size:11px;color:#9fb5c4;word-break:break-all;margin-top:5px}
</style></head><body><h1>Combat VFX Preview</h1><div class="grid">""" + "\n".join(cards) + """</div></body></html>"""
    path.write_text(html, encoding="utf-8")


def build_contact_sheet(manifest, path):
    files = [ROOT / item["file"] for item in manifest if item["category"] not in ["source", "qa"]]
    if not files:
        return
    thumb = 128
    label_h = 42
    cols = 6
    rows = math.ceil(len(files) / cols)
    sheet = Image.new("RGB", (cols * 180, rows * (thumb + label_h) + 20), (18, 25, 34))
    draw = ImageDraw.Draw(sheet)
    for index, file_path in enumerate(files):
        x = (index % cols) * 180 + 26
        y = (index // cols) * (thumb + label_h) + 12
        background = Image.new("RGB", (thumb, thumb), (34, 45, 55))
        bg_draw = ImageDraw.Draw(background)
        for cy in range(0, thumb, 16):
            for cx in range(0, thumb, 16):
                if (cx // 16 + cy // 16) % 2 == 0:
                    bg_draw.rectangle((cx, cy, cx + 15, cy + 15), fill=(43, 57, 68))
        image = Image.open(file_path).convert("RGBA")
        image.thumbnail((thumb, thumb), Image.LANCZOS)
        sheet.paste(background, (x, y))
        sheet.paste(image, (x + (thumb - image.width) // 2, y + (thumb - image.height) // 2), image)
        name = file_path.stem.replace("projectile_", "").replace("vfx_", "")[:22]
        draw.text((x, y + thumb + 4), name, fill=(238, 246, 251))
    sheet.save(path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-sheet", default="", help="Optional gpt-image-2 source sheet to retain under assets/vfx/combat/source.")
    args = parser.parse_args()
    generate_assets(args.source_sheet)


if __name__ == "__main__":
    main()
