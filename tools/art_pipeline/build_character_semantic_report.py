from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import character_roster


ROOT = Path(__file__).resolve().parents[2]
CHAR_ROOT = ROOT / "assets" / "characters"
QA_ROOT = CHAR_ROOT / "qa"

POINT_SEMANTICS = {
    "pivot": "asset.pivot",
    "rig_mount": "rig.mount",
    "muzzle_01": "weapon.muzzle.01",
    "muzzle_02": "weapon.muzzle.02",
    "muzzle_group": "weapon.muzzle.group",
    "turret_mount_01": "weapon.turret_mount.01",
    "turret_mount_02": "weapon.turret_mount.02",
    "torpedo_mount": "weapon.torpedo_mount",
    "torpedo_port": "weapon.torpedo_port.legacy",
    "torpedo_port_01": "weapon.torpedo_port.01",
    "torpedo_port_02": "weapon.torpedo_port.02",
    "aircraft_launch_01": "aircraft.launch.01",
    "aircraft_launch_02": "aircraft.launch.02",
    "aircraft_recovery": "aircraft.recovery",
    "wake_origin": "wake.origin",
    "scan_origin": "scan.origin",
    "sonar_origin": "scan.sonar_origin",
    "periscope_point": "scan.periscope",
    "skill_origin": "skill.origin",
    "command_origin": "skill.command_origin",
    "aura_origin": "skill.aura_origin",
    "fire_control_point": "skill.fire_control_origin",
    "searchlight_point": "skill.searchlight_origin",
    "searchlight_mount": "skill.searchlight_mount",
    "rangefinder_mount": "skill.rangefinder_mount",
    "beam_origin": "skill.beam_origin",
    "origin": "effect.origin",
    "view_origin": "view.origin",
}

ROLE_SEMANTICS = {
    "aa_burst": "aa.burst",
    "aa_circle": "aa.circle",
    "aircraft_explosion": "aircraft.intercept_hit",
    "aircraft_formation": "aircraft.formation",
    "aircraft_launch_flash": "aircraft.launch_flash",
    "aircraft_path": "aircraft.path",
    "aircraft_recovery": "aircraft.recovery",
    "airstrike_area": "aircraft.airstrike_area",
    "armor_hit": "impact.armor.spark",
    "armor_sparks": "impact.armor.spark",
    "broadside_smoke": "muzzle_smoke.heavy",
    "bubble_trail": "submarine.bubble_trail",
    "deck_lane": "aircraft.launch_trail",
    "dive_ripple": "submarine.dive_ripple",
    "heavy_muzzle": "muzzle_flash.large",
    "hit": "aircraft.intercept_hit",
    "muzzle_flash": "muzzle_flash.medium",
    "muzzle_flash_large": "muzzle_flash.large",
    "muzzle_flash_medium": "muzzle_flash.medium",
    "periscope_glint": "submarine.periscope_glint",
    "shell_trail": "shell.trail.medium",
    "shell_trail_heavy": "shell.trail.long",
    "smoke_screen": "skill.area.smoke",
    "sonar_pulse": "submarine.sonar_pulse",
    "speed_lines": "wake.destroyer_fast",
    "speed_wake": "wake.destroyer_fast",
    "torpedo_launch_flash": "torpedo.launch_flash",
    "torpedo_trail": "torpedo.trail",
    "torpedo_warning": "torpedo.warning.fan",
    "underwater_shadow": "submarine.underwater_shadow",
    "wake": "wake.class_profile",
    "wake_carrier": "wake.carrier_wide",
    "wake_fast": "wake.destroyer_fast",
    "wake_heavy": "wake.heavy",
    "wake_medium": "wake.cruiser",
    "wake_subtle": "wake.submarine",
    "water_impact": "impact.water.class_profile",
    "water_splash": "impact.water.class_profile",
    "water_splash_large": "impact.water.large",
}


def semantic_for_role(role: str) -> str:
    if role in ROLE_SEMANTICS:
        return ROLE_SEMANTICS[role]
    if any(token in role for token in ("aura", "area")):
        return "skill.area"
    if any(token in role for token in ("reticle", "lock", "range")):
        return "targeting.overlay"
    if "beam" in role:
        return "skill.beam"
    return f"character.{role}"


def build() -> dict[str, Any]:
    characters: dict[str, Any] = {}
    for entry in character_roster.load_roster():
        config_root = CHAR_ROOT / entry.character_id / "processed" / "config"
        bind_path = config_root / f"{entry.character_id}_meta_bind_points.json"
        vfx_path = config_root / f"{entry.character_id}_vfx_config.json"
        bind_data = json.loads(bind_path.read_text(encoding="utf-8"))
        vfx_data = json.loads(vfx_path.read_text(encoding="utf-8"))
        point_assets: dict[str, list[str]] = {}
        for asset_name, points in bind_data.get("assets", {}).items():
            for point_name in points:
                point_assets.setdefault(point_name, []).append(asset_name)
        characters[entry.character_id] = {
            "ship_class": entry.ship_class,
            "binding_semantics": {
                point: {
                    "semantic": POINT_SEMANTICS.get(point, f"character.{point}"),
                    "assets": sorted(assets),
                }
                for point, assets in sorted(point_assets.items())
            },
            "vfx_roles": {
                role: {
                    "semantic": semantic_for_role(role),
                    "file": item.get("file", ""),
                }
                for role, item in sorted(vfx_data.get("roles", {}).items())
            },
        }
    return {"characters": characters}


def write(payload: dict[str, Any]) -> tuple[Path, Path]:
    QA_ROOT.mkdir(parents=True, exist_ok=True)
    json_path = QA_ROOT / "character_runtime_semantic_mappings.json"
    md_path = QA_ROOT / "character_runtime_semantic_mappings.md"
    json_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    lines = [
        "# Character Runtime Semantic Mappings",
        "",
        "Generated from every character's processed binding-point and VFX configuration.",
        "",
        "| Character | Ship class | Binding semantics | VFX roles |",
        "| --- | --- | ---: | ---: |",
    ]
    for character_id, item in payload["characters"].items():
        lines.append(
            f"| {character_id} | {item['ship_class']} | "
            f"{len(item['binding_semantics'])} | {len(item['vfx_roles'])} |"
        )
    lines.extend(["", "Detailed semantic names, source assets, and VFX files are stored in the JSON report.", ""])
    md_path.write_text("\n".join(lines), encoding="utf-8")
    return json_path, md_path


def main() -> int:
    json_path, md_path = write(build())
    print(json_path.relative_to(ROOT))
    print(md_path.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
