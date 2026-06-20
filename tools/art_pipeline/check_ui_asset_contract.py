from __future__ import annotations

import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "assets" / "ui" / "qa" / "ui_asset_manifest.json"


REQUIRED_PREFIX_COUNTS = {
    "ui_panel_": 16,
    "ui_button_": 29,
    "ui_frame_portrait_": 8,
    "ui_icon_": 42,
    "ui_marker_": 11,
    "ui_minimap_": 7,
    "ui_log_": 4,
    "ui_result_": 8,
    "ui_bar_": 7,
    "ui_ring_": 3,
    "ui_badge_": 2,
}

REQUIRED_NAMES = {
    "ui_panel_top_expanded", "ui_panel_top_collapsed", "ui_panel_fleet_tray_2x6",
    "ui_panel_minimap_open_sea", "ui_panel_battle_log", "ui_panel_selected_ship",
    "ui_panel_pause_dialog", "ui_panel_result_dialog", "ui_panel_confirm_dialog",
    "ui_panel_menu_title", "ui_panel_menu_info", "ui_panel_menu_footer",
    "ui_panel_menu_cover_label", "ui_panel_menu_mode_card", "ui_panel_menu_keybind_card",
    "ui_panel_menu_intro_step_card",
    "ui_button_auto_move_on", "ui_button_auto_weapon_on", "ui_button_auto_skill_on",
    "ui_button_auto_move_off", "ui_button_auto_weapon_off", "ui_button_auto_skill_off",
    "ui_button_small_default", "ui_button_small_hover", "ui_button_small_pressed",
    "ui_button_small_disabled", "ui_button_size_small_default", "ui_button_size_medium_default",
    "ui_button_size_large_default", "ui_button_size_small_selected",
    "ui_button_size_medium_selected", "ui_button_size_large_selected",
    "ui_button_size_small_warning", "ui_button_size_medium_warning", "ui_button_size_large_warning",
    "ui_button_menu_primary_default", "ui_button_menu_primary_hover",
    "ui_button_menu_primary_pressed", "ui_button_menu_primary_selected",
    "ui_button_menu_primary_disabled", "ui_button_menu_secondary_default",
    "ui_button_menu_secondary_hover", "ui_button_menu_secondary_pressed",
    "ui_button_menu_secondary_selected", "ui_button_menu_secondary_disabled",
    "ui_frame_portrait_player", "ui_frame_portrait_enemy", "ui_frame_portrait_unknown",
    "ui_frame_portrait_selected", "ui_frame_portrait_flagship", "ui_frame_portrait_sunk",
    "ui_frame_portrait_skill_ready", "ui_frame_portrait_low_hp",
    "ui_icon_auto_move", "ui_icon_auto_weapon", "ui_icon_auto_skill", "ui_icon_pause",
    "ui_icon_continue", "ui_icon_expand", "ui_icon_collapse", "ui_icon_camera_follow",
    "ui_icon_health", "ui_icon_oxygen", "ui_icon_skill_ready", "ui_icon_cooldown",
    "ui_icon_selected", "ui_icon_target_lock", "ui_icon_detection", "ui_icon_lost_vision",
    "ui_icon_flagship", "ui_icon_submerged", "ui_icon_surfaced", "ui_icon_gunfire",
    "ui_icon_torpedo", "ui_icon_airstrike", "ui_icon_antiair", "ui_icon_antisubmarine",
    "ui_icon_sunk", "ui_icon_hit", "ui_icon_warning", "ui_icon_unknown_contact",
    "ui_icon_class_destroyer", "ui_icon_class_light_cruiser", "ui_icon_class_heavy_cruiser",
    "ui_icon_class_battleship", "ui_icon_class_carrier", "ui_icon_class_submarine",
    "ui_icon_confirm", "ui_icon_cancel", "ui_icon_restart", "ui_icon_exit",
    "ui_icon_menu_start", "ui_icon_menu_modes", "ui_icon_menu_guide", "ui_icon_menu_intro",
    "ui_marker_selected", "ui_marker_target", "ui_marker_heading", "ui_marker_destination",
    "ui_marker_path_endpoint", "ui_marker_offscreen_player", "ui_marker_offscreen_enemy",
    "ui_marker_offscreen_danger", "ui_marker_flagship", "ui_marker_skill_area",
    "ui_marker_danger_area", "ui_minimap_camera_frame", "ui_minimap_surface_player",
    "ui_minimap_surface_enemy", "ui_minimap_submarine_player", "ui_minimap_submarine_enemy",
    "ui_minimap_aircraft_player", "ui_minimap_aircraft_enemy",
    "ui_log_contact_friendly", "ui_log_contact_enemy", "ui_log_aircraft_wave",
    "ui_log_last_contact", "ui_result_victory_header", "ui_result_defeat_header",
    "ui_result_pause_header", "ui_result_confirm_header", "ui_result_victory_flourish",
    "ui_result_defeat_flourish", "ui_result_sparkles", "ui_result_ripples",
    "ui_bar_track_empty", "ui_bar_hp_healthy", "ui_bar_hp_warning", "ui_bar_hp_critical",
    "ui_bar_oxygen", "ui_bar_skill_charge", "ui_bar_damage_trail",
    "ui_ring_cooldown_empty", "ui_ring_cooldown_half", "ui_ring_skill_ready",
    "ui_badge_flagship_critical", "ui_badge_unknown_status",
}


def main() -> int:
    if not MANIFEST.exists():
        print(f"Missing manifest: {MANIFEST}")
        return 1
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    assets = manifest.get("assets", [])
    errors: list[str] = []
    names = [asset.get("name", "") for asset in assets]
    if len(names) != len(set(names)):
        errors.append("Duplicate UI asset names")
    missing_names = sorted(REQUIRED_NAMES - set(names))
    extra_names = sorted(set(names) - REQUIRED_NAMES)
    if missing_names:
        errors.append("Missing semantic roles: " + ", ".join(missing_names))
    if extra_names:
        errors.append("Unexpected semantic roles: " + ", ".join(extra_names))

    for prefix, minimum in REQUIRED_PREFIX_COUNTS.items():
        count = sum(name.startswith(prefix) for name in names)
        if count < minimum:
            errors.append(f"{prefix}: expected at least {minimum}, found {count}")

    for asset in assets:
        output = ROOT / asset["output"]
        if not output.exists():
            errors.append(f"Missing output: {output}")
            continue
        image = Image.open(output)
        if image.mode != "RGBA":
            errors.append(f"Not RGBA: {output} ({image.mode})")
            continue
        alpha = image.getchannel("A")
        if alpha.getbbox() is None:
            errors.append(f"Empty alpha: {output}")
        if alpha.getextrema()[0] != 0:
            errors.append(f"No transparent pixels: {output}")
        if min(image.size) < 24:
            errors.append(f"Asset too small: {output} {image.size}")
        suspicious_key_pixels = 0
        for red, green, blue, alpha_value in image.getdata():
            if alpha_value <= 16:
                continue
            if green > 225 and red < 35 and blue < 55:
                suspicious_key_pixels += 1
            if red > 210 and blue > 180 and green < 70:
                suspicious_key_pixels += 1
        if suspicious_key_pixels > max(8, image.width * image.height // 2000):
            errors.append(f"Possible chroma-key residue: {output} ({suspicious_key_pixels} pixels)")
        if asset["kind"] in {"icon", "marker"}:
            exports = asset.get("exports", [])
            if len(exports) != 3:
                errors.append(f"Missing 1x/2x/4x exports: {output}")
            for export in exports:
                export_path = ROOT / export
                if not export_path.exists():
                    errors.append(f"Missing export: {export_path}")

    if manifest.get("asset_count") != len(assets):
        errors.append("Manifest asset_count does not match records")

    if errors:
        print("UI asset contract: FAIL")
        for error in errors:
            print(f"- {error}")
        return 1
    print(f"UI asset contract: PASS ({len(assets)} assets)")
    for prefix, minimum in REQUIRED_PREFIX_COUNTS.items():
        count = sum(name.startswith(prefix) for name in names)
        print(f"- {prefix} {count} (minimum {minimum})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
