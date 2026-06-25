from __future__ import annotations

import json
from pathlib import Path

import character_roster


ROOT = Path(__file__).resolve().parents[2]
CHAR_ROOT = ROOT / "assets" / "characters"

SKILL_ROLES = {
    "fletcher": "fleet_hunter_screen", "cleveland": "layered_aa_net",
    "baltimore": "radar_ap_calibration", "wahoo": "continuous_hunt",
    "jervis": "flotilla_leader", "belfast": "radar_suppression",
    "illustrious": "armored_flight_deck", "upholder": "coastal_ambush",
    "tashkent": "blue_cruiser", "chapayev": "long_range_fire_control",
    "gangut": "steel_line", "k_21": "polar_tracking",
    "z23": "gun_torpedo_conversion", "nurnberg": "stern_evasion_fire",
    "scharnhorst": "high_speed_interception", "graf_zeppelin": "experimental_air_wing",
    "akizuki": "long_ten_cm_air_guard", "takao": "night_torpedo",
    "shokaku": "coordinated_strike_wave", "i_19": "floatplane_vanguard",
    "yat_sen": "mobile_command_post", "chang_chun": "forward_escort",
    "dingyuan": "ironclad_anchor", "hai_lung": "endurance_training",
}

BATTLE_ROLES = {
    "fletcher": ("battle_body_r", "battle_rig_base", "battle_turret_main_01", "battle_torpedo_tube_01", "battle_depth_charge_rack", "battle_sonar_node", "battle_aa_center", "battle_wake_origin_marker"),
    "cleveland": ("battle_body_r", "battle_rig_base", "battle_turret_main_01", "battle_turret_main_02", "battle_aa_center", "battle_radar_node", "battle_fire_control_node", "battle_wake_origin_marker"),
    "baltimore": ("battle_body_r", "battle_rig_base", "battle_turret_main_01", "battle_turret_main_02", "battle_turret_main_03", "battle_fire_control_node", "battle_aa_center", "battle_wake_origin_marker"),
    "wahoo": ("battle_body_r", "battle_rig_base", "battle_torpedo_tube_fore", "battle_torpedo_tube_aft", "battle_sonar_node", "battle_periscope_node", "battle_oxygen_indicator", "battle_submerged_shadow"),
    "jervis": ("battle_body_r", "battle_rig_base", "battle_turret_main_01", "battle_torpedo_tube_01", "battle_depth_charge_rack", "battle_command_node", "battle_aa_center", "battle_wake_origin_marker"),
    "belfast": ("battle_body_r", "battle_rig_base", "battle_turret_main_01", "battle_torpedo_tube_01", "battle_aa_center", "battle_radar_node", "battle_rangefinder_node", "battle_wake_origin_marker"),
    "illustrious": ("battle_body_r", "battle_rig_base", "battle_flight_deck", "battle_hangar", "battle_aircraft_group_01", "battle_aircraft_launch_marker", "battle_aircraft_recovery_marker", "battle_aa_center"),
    "upholder": ("battle_body_r", "battle_rig_base", "battle_torpedo_tube_fore", "battle_periscope_node", "battle_sonar_node", "battle_dive_plane", "battle_submerged_shadow", "battle_wake_origin_marker"),
    "tashkent": ("battle_body_r", "battle_rig_base", "battle_turret_main_01", "battle_torpedo_tube_01", "battle_propulsion_node", "battle_command_node", "battle_aa_center", "battle_wake_origin_marker"),
    "chapayev": ("battle_body_r", "battle_rig_base", "battle_turret_main_01", "battle_torpedo_tube_01", "battle_aa_center", "battle_rangefinder_node", "battle_fire_control_node", "battle_wake_origin_marker"),
    "gangut": ("battle_body_r", "battle_rig_base", "battle_turret_main_01", "battle_turret_secondary_01", "battle_armor_plate", "battle_smokestack_node", "battle_fire_control_node", "battle_wake_origin_marker"),
    "k_21": ("battle_body_r", "battle_rig_base", "battle_torpedo_tube_fore", "battle_torpedo_tube_aft", "battle_sonar_node", "battle_periscope_node", "battle_long_range_antenna", "battle_submerged_shadow"),
    "z23": ("battle_body_r", "battle_rig_base", "battle_turret_main_01", "battle_turret_main_02", "battle_torpedo_tube_01", "battle_fire_control_node", "battle_mode_indicator", "battle_wake_origin_marker"),
    "nurnberg": ("battle_body_r", "battle_rig_base", "battle_turret_main_01", "battle_turret_main_02", "battle_torpedo_tube_01", "battle_aa_center", "battle_turn_indicator", "battle_wake_origin_marker"),
    "scharnhorst": ("battle_body_r", "battle_rig_base", "battle_turret_main_01", "battle_turret_secondary_01", "battle_fire_control_node", "battle_propulsion_node", "battle_flagship_marker", "battle_wake_origin_marker"),
    "graf_zeppelin": ("battle_body_r", "battle_rig_base", "battle_flight_deck", "battle_aircraft_group_01", "battle_turret_secondary_01", "battle_aircraft_launch_marker", "battle_aircraft_recovery_marker", "battle_aa_center"),
    "akizuki": ("battle_body_r", "battle_rig_base", "battle_turret_main_01", "battle_torpedo_tube_01", "battle_aa_center", "battle_radar_node", "battle_support_node", "battle_wake_origin_marker"),
    "takao": ("battle_body_r", "battle_rig_base", "battle_turret_main_01", "battle_turret_main_02", "battle_torpedo_tube_01", "battle_fire_control_node", "battle_bridge_node", "battle_wake_origin_marker"),
    "shokaku": ("battle_body_r", "battle_rig_base", "battle_flight_deck", "battle_aircraft_group_01", "battle_aircraft_group_02", "battle_aircraft_launch_marker", "battle_aircraft_recovery_marker", "battle_aa_center"),
    "i_19": ("battle_body_r", "battle_rig_base", "battle_torpedo_tube_fore", "battle_floatplane", "battle_aircraft_launch_marker", "battle_periscope_node", "battle_sonar_node", "battle_submerged_shadow"),
    "yat_sen": ("battle_body_r", "battle_rig_base", "battle_turret_main_01", "battle_turret_secondary_01", "battle_aa_center", "battle_command_node", "battle_support_node", "battle_wake_origin_marker"),
    "chang_chun": ("battle_body_r", "battle_rig_base", "battle_turret_main_01", "battle_torpedo_tube_01", "battle_aa_center", "battle_radar_node", "battle_support_node", "battle_wake_origin_marker"),
    "dingyuan": ("battle_body_r", "battle_rig_base", "battle_turret_main_01", "battle_turret_secondary_01", "battle_armor_plate", "battle_smokestack_node", "battle_flagship_marker", "battle_wake_origin_marker"),
    "hai_lung": ("battle_body_r", "battle_rig_base", "battle_torpedo_tube_fore", "battle_torpedo_tube_aft", "battle_sonar_node", "battle_periscope_node", "battle_oxygen_indicator", "battle_submerged_shadow"),
}

MOUNT_COUNTS = {
    "fletcher": {"turret_main": 5, "torpedo": 2}, "cleveland": {"turret_main": 4},
    "baltimore": {"turret_main": 3}, "wahoo": {"torpedo_fore": 6, "torpedo_aft": 4},
    "jervis": {"turret_main": 3, "torpedo": 2}, "belfast": {"turret_main": 4, "torpedo": 2},
    "illustrious": {"aircraft_launch": 2, "aircraft_recovery": 1}, "upholder": {"torpedo_fore": 6},
    "tashkent": {"turret_main": 3, "torpedo": 3}, "chapayev": {"turret_main": 4, "torpedo": 2},
    "gangut": {"turret_main": 4}, "k_21": {"torpedo_fore": 6, "torpedo_aft": 4},
    "z23": {"turret_main": 4, "torpedo": 2}, "nurnberg": {"turret_main": 3, "torpedo": 4},
    "scharnhorst": {"turret_main": 3}, "graf_zeppelin": {"aircraft_launch": 1, "aircraft_recovery": 1, "turret_secondary": 8},
    "akizuki": {"turret_main": 4, "torpedo": 1}, "takao": {"turret_main": 5, "torpedo": 4},
    "shokaku": {"aircraft_launch": 2, "aircraft_recovery": 1}, "i_19": {"torpedo_fore": 6, "aircraft_launch": 1},
    "yat_sen": {"turret_main": 1, "turret_secondary": 1}, "chang_chun": {"turret_main": 4, "torpedo": 2},
    "dingyuan": {"turret_main": 2, "turret_secondary": 2}, "hai_lung": {"torpedo_fore": 6, "torpedo_aft": 4},
}

VFX_ROLES = {
    "destroyer": ("wake_fast", "torpedo_warning", "torpedo_launch_flash", "muzzle_flash_small", "water_splash", "aa_circle", "skill_aura", "range_reticle"),
    "light_cruiser": ("wake_cruiser", "muzzle_flash_medium", "shell_trail", "aa_burst", "aa_circle", "radar_scan", "skill_aura", "water_splash"),
    "heavy_cruiser": ("wake_heavy", "muzzle_flash_large", "shell_trail_heavy", "armor_sparks", "fire_control_lock", "skill_aura", "water_splash_large", "torpedo_warning"),
    "battleship": ("wake_heavy", "muzzle_flash_large", "broadside_smoke", "shell_trail_heavy", "armor_sparks", "command_aura", "water_splash_large", "fire_control_lock"),
    "carrier": ("wake_carrier", "aircraft_path", "aircraft_launch_flash", "aircraft_formation", "airstrike_area", "aircraft_recovery", "aa_burst", "skill_aura"),
    "submarine": ("wake_subtle", "bubble_trail", "sonar_pulse", "torpedo_launch_flash", "torpedo_trail", "underwater_shadow", "dive_ripple", "skill_aura"),
}

SPECIAL_VFX = {
    "fletcher": ("escort_warning_fan", "depth_charge_drop"), "cleveland": ("layered_aa_net", "radar_calibration"),
    "baltimore": ("ap_calibration_frame", "radar_lock_line"), "wahoo": ("shark_shadow", "reload_pulse"),
    "jervis": ("formation_signal", "flotilla_aura"), "belfast": ("radar_suppression_sector", "support_salvo"),
    "illustrious": ("armored_deck_sparks", "steady_launch_lane"), "upholder": ("coastal_ambush_sector", "surface_ripple"),
    "tashkent": ("blue_speed_wake", "blade_wake"), "chapayev": ("rectangular_fire_grid", "ice_impact_marker"),
    "gangut": ("steel_line_aura", "coal_smoke_wake"), "k_21": ("polar_tracking_ring", "ice_torpedo_trail"),
    "z23": ("mode_switch_indicator", "heavy_destroyer_muzzle"), "nurnberg": ("turn_scale_ring", "curved_stern_wake"),
    "scharnhorst": ("interception_line", "high_speed_heavy_wake"), "graf_zeppelin": ("unfinished_plan_overlay", "experimental_flight_lane"),
    "akizuki": ("moonwhite_aa_ring", "escort_interception"), "takao": ("night_target_line", "heavy_torpedo_sector"),
    "shokaku": ("dual_wave_path", "crane_formation_marker"), "i_19": ("floatplane_scan", "long_range_torpedo_trail"),
    "yat_sen": ("mobile_command_ring", "jade_support_light"), "chang_chun": ("forward_escort_wake", "early_radar_scan"),
    "dingyuan": ("ironclad_guard_aura", "coal_smoke_wake"), "hai_lung": ("training_sonar_ring", "endurance_shadow"),
}

SPECIAL_RULES = {
    "cleveland": ["No torpedo tube or torpedo VFX may appear."],
    "baltimore": ["No torpedo tube may appear; preserve the clean radar heavy-cruiser silhouette."],
    "upholder": ["Only bow torpedo ports; no stern torpedo node."],
    "i_19": ["Only bow torpedo ports; no stern torpedo node; floatplane remains separable."],
    "chang_chun": ["Early gun-and-torpedo configuration only; no missile launcher."],
    "dingyuan": ["Pre-dreadnought ironclad silhouette; no radar or modern anti-aircraft equipment."],
    "graf_zeppelin": ["Clearly unfinished experimental carrier structure; UI plan marker only, no readable text."],
}


def public_semantic(role: str, ship_class: str) -> str:
    if "wake" in role:
        return {"destroyer": "wake.destroyer_fast", "light_cruiser": "wake.cruiser", "heavy_cruiser": "wake.cruiser", "battleship": "wake.battleship_heavy", "carrier": "wake.carrier_wide", "submarine": "wake.submarine_low"}[ship_class]
    if "muzzle" in role:
        return "muzzle_flash.large" if ship_class in {"heavy_cruiser", "battleship"} else "muzzle_flash.small" if ship_class == "destroyer" else "muzzle_flash.medium"
    if "torpedo_warning" in role or "sector" in role:
        return "torpedo.warning.fan"
    if "torpedo" in role:
        return "torpedo.trail.submerged" if ship_class == "submarine" else "torpedo.trail.surface"
    if "aircraft" in role or "flight" in role or "airstrike" in role:
        return "aircraft.path"
    if "aa_" in role or "interception" in role:
        return "aa.burst.small"
    if "sonar" in role or "scan" in role or "tracking" in role:
        return "submarine.sonar_pulse"
    if "splash" in role:
        return "impact.water.large" if ship_class in {"heavy_cruiser", "battleship"} else "impact.water.medium"
    if "shell_trail" in role:
        return "shell.trail.long" if ship_class in {"heavy_cruiser", "battleship"} else "shell.trail.medium"
    if "spark" in role:
        return "impact.armor.spark"
    return "skill.area"


def rig_bindings(character_id: str) -> list[str]:
    names = ["rig_mount", "wake_origin", "skill_origin"]
    for kind, count in MOUNT_COUNTS[character_id].items():
        stem = {
            "turret_main": "turret_mount", "turret_secondary": "secondary_mount",
            "torpedo": "torpedo_mount", "torpedo_fore": "torpedo_fore_mount",
            "torpedo_aft": "torpedo_aft_mount", "aircraft_launch": "aircraft_launch",
            "aircraft_recovery": "aircraft_recovery",
        }[kind]
        names.extend(f"{stem}_{index:02d}" for index in range(1, count + 1))
    return names


def build_plan(entry: character_roster.CharacterRosterEntry) -> dict[str, object]:
    character_id = entry.character_id
    base_vfx = list(VFX_ROLES[entry.ship_class])
    base_vfx[:2] = SPECIAL_VFX[character_id]
    if character_id == "baltimore":
        base_vfx[-1] = "aa_interception"
    return {
        "character_id": character_id,
        "phase": "phase2",
        "ship_class": entry.ship_class,
        "level": int(entry.level.split()[0]),
        "skill_role": SKILL_ROLES[character_id],
        "battle_grid_roles": list(BATTLE_ROLES[character_id]),
        "mount_instances": MOUNT_COUNTS[character_id],
        "bindings": {"battle_rig_base": rig_bindings(character_id)},
        "vfx_roles": base_vfx,
        "public_vfx_profiles": {role: public_semantic(role, entry.ship_class) for role in base_vfx},
        "acceptance_rules": [
            "Original TinySeaWar design; no real flags, political symbols, readable insignia, or extremist symbols.",
            "Character body, rig base, weapon nodes, and VFX must remain visually separable.",
            *(["Submarine character must wear fitted waterproof or tactical boots; no swim fins on feet."] if entry.ship_class == "submarine" else []),
            *SPECIAL_RULES.get(character_id, []),
        ],
    }


def main() -> int:
    for entry in character_roster.load_roster(phase="phase2"):
        root = CHAR_ROOT / entry.character_id
        for folder in ("concept", "battle", "ui", "vfx", "meta"):
            (root / folder).mkdir(parents=True, exist_ok=True)
        (root / "postprocess_plan.json").write_text(
            json.dumps(build_plan(entry), ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
