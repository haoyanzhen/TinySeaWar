from __future__ import annotations

import json
import math
import re
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
DOC = ROOT / "docs" / "14_character_balance_design.md"
PLAN_ROOT = ROOT / "assets" / "characters"
DISTANCE_BASELINE_MULTIPLIER = 1.5
MOTION_BASELINE_MULTIPLIER = 0.5
ATTACK_SPEED_BASELINE_MULTIPLIER = 0.5
GUN_IMPACT_RADIUS_MULTIPLIER = 0.5
TORPEDO_LANE_SPACING = 80.0
TORPEDO_MOUNT_LAUNCH_INTERVAL = 1.0
WING_TORPEDO_CHARACTERS = {"belfast", "chapayev", "nurnberg", "takao"}


def torpedo_spread_degrees(effective_range: float, shots_per_mount: int) -> float:
    if shots_per_mount <= 1:
        return 0.0
    adjacent_angle = 2.0 * math.asin(min(1.0, TORPEDO_LANE_SPACING / (2.0 * effective_range)))
    return math.degrees(adjacent_angle) * (shots_per_mount - 1)


def torpedo_mount_fire_arcs(character_id: str, mount_count: int, fire_arc: float, equipment: str) -> list[dict[str, Any]]:
    if "前部" in equipment:
        arcs = lambda _index: [{"center": 0, "degrees": fire_arc * 2.0}]
    elif "后部" in equipment:
        arcs = lambda _index: [{"center": 180, "degrees": fire_arc * 2.0}]
    elif character_id in WING_TORPEDO_CHARACTERS:
        arcs = lambda index: [{"center": -90 if index < mount_count / 2 else 90, "degrees": fire_arc}]
    else:
        arcs = lambda _index: [{"center": -90, "degrees": fire_arc}, {"center": 90, "degrees": fire_arc}]
    return [{"mount_id": f"mount_{index + 1}", "fire_arcs": arcs(index)} for index in range(mount_count)]


def full_salvo_fire_arcs(center: float, degrees: float, mount_count: int) -> list[dict[str, float]]:
    if mount_count <= 1:
        return [{"center": center, "degrees": degrees}]
    broadside_degrees = max(30.0, min(120.0, degrees - 180.0))
    return [
        {"center": center - 90.0, "degrees": broadside_degrees},
        {"center": center + 90.0, "degrees": broadside_degrees},
    ]


def collision_half_extents(radius: float) -> list[float]:
    longitudinal = max(54.0, min(81.0, radius * 2.5))
    lateral = max(radius, longitudinal * 0.42)
    return [round(longitudinal, 2), round(lateral, 2)]

SHORT_TO_ID = {
    "弗莱彻": "fletcher", "克利夫兰": "cleveland", "巴尔的摩": "baltimore", "刺尾鱼": "wahoo",
    "杰维斯": "jervis", "贝尔法斯特": "belfast", "光辉": "illustrious", "拥护者": "upholder",
    "塔什干": "tashkent", "恰巴耶夫": "chapayev", "甘古特": "gangut", "K-21": "k_21",
    "Z23": "z23", "纽伦堡": "nurnberg", "沙恩霍斯特": "scharnhorst", "齐柏林伯爵": "graf_zeppelin",
    "秋月": "akizuki", "高雄": "takao", "翔鹤": "shokaku", "伊-19": "i_19",
    "逸仙": "yat_sen", "长春": "chang_chun", "定远": "dingyuan", "海龙": "hai_lung",
}

FACTIONS = {
    "美系": "United States Navy", "英系": "Royal Navy", "苏系": "Soviet Navy",
    "德系": "Kriegsmarine", "日系": "Imperial Japanese Navy", "中系": "Chinese Navy",
}
SHIP_CLASSES = {
    "驱逐": "Destroyer", "轻巡": "LightCruiser", "重巡": "HeavyCruiser",
    "战列": "Battleship", "航母": "Carrier", "潜艇": "Submarine",
}
COLLISION_RADIUS = {"Destroyer": 17.0, "LightCruiser": 22.0, "HeavyCruiser": 25.0, "Battleship": 31.0, "Carrier": 30.0, "Submarine": 15.0}

PRIMARY_KIND = {
    "fletcher": "torpedo", "cleveland": "main", "baltimore": "main", "wahoo": "torpedo",
    "jervis": "torpedo", "belfast": "torpedo", "illustrious": "airstrike", "upholder": "torpedo",
    "tashkent": "torpedo", "chapayev": "torpedo", "gangut": "main", "k_21": "torpedo",
    "z23": "torpedo", "nurnberg": "torpedo", "scharnhorst": "main", "graf_zeppelin": "airstrike",
    "akizuki": "torpedo", "takao": "torpedo", "shokaku": "airstrike", "i_19": "torpedo",
    "yat_sen": "main", "chang_chun": "torpedo", "dingyuan": "main", "hai_lung": "torpedo",
}

ARMOR = {
    "small_he": {"Unarmored": 1.2, "Light": 1.15, "Medium": 0.45, "Heavy": 0.13, "Submerged": 0, "Air": 0},
    "medium_he": {"Unarmored": 1.15, "Light": 1.2, "Medium": 0.8, "Heavy": 0.45, "Submerged": 0, "Air": 0},
    "medium_ap": {"Unarmored": 0.8, "Light": 0.65, "Medium": 1.05, "Heavy": 0.95, "Submerged": 0, "Air": 0},
    "large_he": {"Unarmored": 1, "Light": 1.1, "Medium": 0.95, "Heavy": 0.75, "Submerged": 0, "Air": 0},
    "large_ap": {"Unarmored": 0.65, "Light": 0.45, "Medium": 1.1, "Heavy": 1.25, "Submerged": 0, "Air": 0},
    "surface_torpedo": {"Unarmored": 0.7, "Light": 0.7, "Medium": 1, "Heavy": 1.25, "Submerged": 1, "Air": 0},
    "submarine_torpedo": {"Unarmored": 0.7, "Light": 0.7, "Medium": 1, "Heavy": 1.25, "Submerged": 1, "Air": 0},
    "aviation": {"Unarmored": 1.1, "Light": 1, "Medium": 0.9, "Heavy": 0.75, "Submerged": 0, "Air": 0},
    "aa": {"Unarmored": 0, "Light": 0, "Medium": 0, "Heavy": 0, "Submerged": 0, "Air": 1},
}


def effect(scope: str, stat: str, operation: str, value: float, category: str, group: str, **extra: Any) -> dict[str, Any]:
    return {"scope": scope, "stat": stat, "operation": operation, "value": value, "category": category, "stack_group": group, "stack_rule": "Refresh", **extra}


SKILL_EFFECTS = {
    "fletcher": [effect("Self", "DetectionRange", "FlatAdd", 55, "All", "fletcher_skill"), effect("Self", "Damage", "PercentAdd", .18, "AntiSubmarine", "fletcher_skill"), effect("Self", "TorpedoDetectionDistance", "FlatAdd", 60, "Torpedo", "fletcher_skill")],
    "cleveland": [effect("Self", "ReloadSpeed", "PercentAdd", .30, "AntiAir", "cleveland_skill"), effect("Self", "Damage", "PercentAdd", .18, "AntiAir", "cleveland_skill"), effect("Self", "WeaponRange", "FlatAdd", 50, "AntiAir", "cleveland_skill")],
    "baltimore": [effect("Self", "AccuracyPoint", "FlatAdd", .18, "Gun", "baltimore_skill", consume_on_fire=True, persistent_until_consumed=True, consume_weapon_group_id="baltimore_main", bind_selected_target=True), effect("Self", "WeaponSpread", "PercentAdd", -.24, "Gun", "baltimore_skill", consume_on_fire=True, persistent_until_consumed=True, consume_weapon_group_id="baltimore_main", bind_selected_target=True), effect("Self", "ArmorDamageModifier", "PercentAdd", .12, "Gun", "baltimore_skill", consume_on_fire=True, persistent_until_consumed=True, consume_weapon_group_id="baltimore_main", bind_selected_target=True, target_armor_classes=["Medium", "Heavy"])],
    "wahoo": [effect("Self", "ReloadSpeed", "PercentAdd", .28, "Torpedo", "wahoo_skill"), effect("Self", "Damage", "PercentAdd", .12, "Torpedo", "wahoo_skill", consume_on_fire=True, persistent_until_consumed=True, consume_weapon_group_id="wahoo_torpedo"), effect("Self", "OxygenConsumptionRate", "PercentAdd", .35, "All", "wahoo_skill")],
    "jervis": [effect("AlliesInArea", "TurnSpeed", "PercentAdd", .10, "All", "jervis_skill", recipient_ship_classes=["Destroyer", "LightCruiser"]), effect("AlliesInArea", "Speed", "PercentAdd", .06, "All", "jervis_skill", recipient_ship_classes=["Destroyer", "LightCruiser"]), effect("AlliesInArea", "WeaponSpread", "PercentAdd", -.08, "Torpedo", "jervis_skill", recipient_ship_classes=["Destroyer", "LightCruiser"])],
    "belfast": [effect("EnemiesInArea", "ConcealmentDistance", "FlatAdd", 90, "All", "belfast_skill"), effect("AlliesInArea", "AccuracyPoint", "FlatAdd", .07, "Gun", "belfast_skill"), effect("Self", "FiringRevealMultiplier", "PercentAdd", -.10, "All", "belfast_skill")],
    "illustrious": [effect("Self", "DamageReduction", "PercentAdd", .18, "All", "illustrious_skill"), effect("Self", "AircraftHP", "PercentAdd", .22, "Aviation", "illustrious_skill"), effect("Self", "ReloadSpeed", "PercentAdd", -.10, "Aviation", "illustrious_skill")],
    "upholder": [effect("Self", "ConcealmentDistance", "StateMultiply", .82, "All", "upholder_skill", requires_submerged=True), effect("Self", "ProjectileSpeed", "PercentAdd", .12, "Torpedo", "upholder_skill"), effect("Self", "WeaponSpread", "PercentAdd", -.12, "Torpedo", "upholder_skill")],
    "tashkent": [effect("Self", "Speed", "PercentAdd", .20, "All", "tashkent_skill"), effect("Self", "ReloadSpeed", "PercentAdd", .22, "Gun", "tashkent_skill"), effect("Self", "TurnSpeed", "PercentAdd", -.14, "All", "tashkent_skill")],
    "chapayev": [effect("Self", "WeaponSpread", "PercentAdd", -.24, "Gun", "chapayev_skill"), effect("Self", "AccuracyPoint", "FlatAdd", .09, "Gun", "chapayev_skill"), effect("Self", "FiringRevealMultiplier", "PercentAdd", .12, "All", "chapayev_skill")],
    "gangut": [effect("Self", "Armor", "FlatAdd", 8, "All", "gangut_skill"), effect("Self", "DamageReduction", "PercentAdd", .08, "All", "gangut_skill"), effect("Self", "Speed", "PercentAdd", -.18, "All", "gangut_skill"), effect("Self", "WeaponSpread", "PercentAdd", -.10, "Gun", "gangut_skill")],
    "k_21": [effect("Self", "DetectionRange", "FlatAdd", 80, "All", "k21_skill"), effect("Self", "ProjectileRadius", "FlatAdd", 8, "Torpedo", "k21_skill", consume_on_fire=True, persistent_until_consumed=True, consume_weapon_group_id="k_21_torpedo"), effect("Self", "ProjectileSpeed", "PercentAdd", -.08, "Torpedo", "k21_skill")],
    "z23": [effect("Self", "ReloadSpeed", "PercentAdd", .18, "Gun", "z23_skill"), effect("Self", "WeaponSpread", "PercentAdd", -.15, "Torpedo", "z23_skill", consume_on_fire=True, persistent_until_consumed=True, consume_weapon_group_id="z23_torpedo"), effect("Self", "Speed", "PercentAdd", -.08, "All", "z23_skill")],
    "nurnberg": [effect("Self", "TurnSpeed", "PercentAdd", .16, "All", "nurnberg_skill"), effect("Self", "Evasion", "PercentAdd", .16, "All", "nurnberg_skill"), effect("Self", "AccuracyPoint", "FlatAdd", .04, "Gun", "nurnberg_skill")],
    "scharnhorst": [effect("Self", "Speed", "PercentAdd", .14, "All", "scharnhorst_skill"), effect("Self", "ReloadSpeed", "PercentAdd", .20, "Gun", "scharnhorst_skill"), effect("Self", "ArmorDamageModifier", "PercentAdd", .12, "Gun", "scharnhorst_skill", bind_selected_target=True, target_armor_classes=["Light", "Medium"])],
    "graf_zeppelin": [effect("Self", "Damage", "PercentAdd", .15, "Aviation", "graf_skill"), effect("Self", "AircraftHP", "PercentAdd", .10, "Aviation", "graf_skill"), effect("Self", "ReloadSpeed", "PercentAdd", .20, "Gun", "graf_skill")],
    "akizuki": [effect("Self", "Damage", "PercentAdd", .18, "AntiAir", "akizuki_skill"), effect("Self", "ReloadSpeed", "PercentAdd", .16, "AntiAir", "akizuki_skill"), effect("AlliesInArea", "DamageReduction", "PercentAdd", .10, "Aviation", "akizuki_skill")],
    "takao": [effect("Self", "Damage", "PercentAdd", .18, "Torpedo", "takao_skill", consume_on_fire=True, persistent_until_consumed=True, consume_weapon_group_id="takao_torpedo"), effect("Self", "ProjectileSpeed", "PercentAdd", .10, "Torpedo", "takao_skill", consume_on_fire=True, persistent_until_consumed=True, consume_weapon_group_id="takao_torpedo"), effect("Self", "FiringRevealMultiplier", "PercentAdd", .22, "All", "takao_skill", consume_on_fire=True, persistent_until_consumed=True, consume_weapon_group_id="takao_torpedo")],
    "shokaku": [],
    "i_19": [effect("Self", "ProjectileSpeed", "PercentAdd", .10, "Torpedo", "i19_skill", requires_scouted_target=True), effect("Self", "ProjectileRadius", "FlatAdd", 8, "Torpedo", "i19_skill", requires_scouted_target=True)],
    "yat_sen": [effect("AlliesInArea", "DetectionRange", "FlatAdd", 55, "All", "yat_sen_skill"), effect("AlliesInArea", "AccuracyPoint", "FlatAdd", .05, "Gun", "yat_sen_skill"), effect("Self", "Armor", "FlatAdd", 6, "All", "yat_sen_skill")],
    "chang_chun": [effect("Self", "DetectionRange", "FlatAdd", 75, "All", "chang_chun_skill"), effect("Self", "ReloadSpeed", "PercentAdd", .16, "Gun", "chang_chun_skill"), effect("AlliesInArea", "Evasion", "FlatAdd", 8, "All", "chang_chun_skill")],
    "dingyuan": [effect("Self", "Armor", "FlatAdd", 18, "All", "dingyuan_skill"), effect("Self", "DamageReduction", "PercentAdd", .20, "All", "dingyuan_skill"), effect("Self", "TurnSpeed", "PercentAdd", -.22, "All", "dingyuan_skill"), effect("Self", "WeaponSpread", "PercentAdd", -.20, "Gun", "dingyuan_skill", consume_on_fire=True, persistent_until_consumed=True, consume_weapon_group_id="dingyuan_main")],
    "hai_lung": [effect("Self", "OxygenConsumptionRate", "PercentAdd", -.30, "All", "hai_lung_skill"), effect("Self", "Speed", "PercentAdd", .10, "All", "hai_lung_skill", requires_submerged=True), effect("Self", "ReloadSpeed", "PercentAdd", -.12, "Torpedo", "hai_lung_skill")],
}

SKILL_RUNTIME = {
    "fletcher": {"target_type": "Self", "effect_radius": 420, "ai_tags": ["Recon", "AntiSubmarine", "TorpedoWarning", "Defense"]},
    "cleveland": {"target_type": "Self", "ai_tags": ["AntiAir", "Defense"]},
    "baltimore": {"target_type": "Enemy", "ai_tags": ["Burst", "TargetAttack"]},
    "wahoo": {"target_type": "Self", "ai_tags": ["Burst", "Torpedo"]},
    "jervis": {"target_type": "Self", "effect_radius": 495, "ai_tags": ["Mobility", "AreaSupport"]},
    "belfast": {"target_type": "Area", "effect_radius": 240, "ai_tags": ["Recon", "Control", "AreaSupport"]},
    "illustrious": {"target_type": "Self", "ai_tags": ["Defense", "Aviation"]},
    "upholder": {"target_type": "Self", "ai_tags": ["Concealment", "Torpedo"]},
    "tashkent": {"target_type": "Self", "ai_tags": ["Burst", "Mobility"]},
    "chapayev": {"target_type": "Self", "ai_tags": ["Burst"]},
    "gangut": {"target_type": "Self", "ai_tags": ["Defense", "Burst"]},
    "k_21": {"target_type": "Self", "ai_tags": ["Recon", "Torpedo"]},
    "z23": {"target_type": "Self", "ai_tags": ["Burst", "Torpedo"]},
    "nurnberg": {"target_type": "Self", "ai_tags": ["Defense", "Mobility"]},
    "scharnhorst": {"target_type": "Enemy", "ai_tags": ["Burst", "TargetAttack", "Mobility"]},
    "graf_zeppelin": {"target_type": "Area", "effect_radius": 65, "ai_tags": ["Aviation", "AreaAttack"], "triggered_attacks": [{"weapon_id": "weapon.graf_zeppelin_bomber"}]},
    "akizuki": {"target_type": "Self", "effect_radius": 450, "ai_tags": ["AntiAir", "Defense", "AreaSupport"]},
    "takao": {"target_type": "Self", "ai_tags": ["Burst", "Torpedo"]},
    "shokaku": {"target_type": "Area", "effect_radius": 75, "ai_tags": ["Aviation", "AreaAttack", "Burst"], "triggered_attacks": [
        {"weapon_id": "weapon.shokaku_bomber", "modifiers": [effect("Self", "Damage", "PercentAdd", .18, "Aviation", "shokaku_skill"), effect("Self", "AircraftHP", "PercentAdd", .08, "Aviation", "shokaku_skill")]},
        {"weapon_id": "weapon.shokaku_torpedo_bomber", "charge_time": 2.0, "modifiers": [effect("Self", "Damage", "PercentAdd", .18, "Aviation", "shokaku_skill"), effect("Self", "AccuracyPoint", "FlatAdd", .08, "Aviation", "shokaku_skill"), effect("Self", "AircraftHP", "PercentAdd", .08, "Aviation", "shokaku_skill")]},
    ]},
    "i_19": {"target_type": "Area", "effect_radius": 600, "ai_tags": ["Recon", "Torpedo"], "recon_zones": [{"radius": 600, "duration": 18, "aircraft_hp": 350}]},
    "yat_sen": {"target_type": "Self", "effect_radius": 480, "ai_tags": ["Recon", "AreaSupport"]},
    "chang_chun": {"target_type": "Self", "effect_radius": 570, "ai_tags": ["Recon", "AreaSupport"]},
    "dingyuan": {"target_type": "Self", "ai_tags": ["Defense", "Burst"]},
    "hai_lung": {"target_type": "Self", "ai_tags": ["Resource", "Concealment"]},
}


def table_rows(start: str, end: str) -> list[list[str]]:
    text = DOC.read_text(encoding="utf-8")
    section = text.split(start, 1)[1].split(end, 1)[0]
    rows = []
    for line in section.splitlines():
        if not line.startswith("|"):
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if cells and cells[0] not in {"角色", "---"} and not cells[0].startswith("---"):
            rows.append(cells)
    return rows


def character_id(value: str) -> str:
    for short_name, identifier in SHORT_TO_ID.items():
        if value.startswith(short_name):
            return identifier
    raise ValueError(f"Unknown phase2 character: {value}")


def number(value: str) -> float:
    match = re.search(r"-?\d+(?:\.\d+)?", value)
    if not match:
        raise ValueError(f"No numeric value in {value}")
    return float(match.group())


def count(value: str) -> int:
    values = re.findall(r"\d+", value)
    return int(values[-1])


def formula_key(label: str) -> str:
    if "潜艇鱼雷" in label: return "submarine_torpedo"
    if "水面舰鱼雷" in label or "航空鱼雷" in label: return "surface_torpedo"
    if "大口径穿甲" in label: return "large_ap"
    if "大口径高爆" in label: return "large_he"
    if "中口径穿甲" in label: return "medium_ap"
    if "中口径高爆" in label: return "medium_he"
    if "小口径高爆" in label or "深水炸弹" in label: return "small_he"
    if "航空炸弹" in label: return "aviation"
    if "防空" in label: return "aa"
    if "侦查" in label or "侦察" in label: return "aviation"
    raise ValueError(f"Unknown formula label: {label}")


def weapon_identity(character: str, equipment: str, mount_type: str, index: int) -> tuple[str, str]:
    if "前部鱼雷" in equipment: suffix, group = "fore_torpedo", "torpedo"
    elif "后部鱼雷" in equipment: suffix, group = "aft_torpedo", "torpedo"
    elif "鱼雷" in equipment and mount_type == "Torpedo": suffix, group = "torpedo", "torpedo"
    elif "深水炸弹" in equipment: suffix, group = "depth_charge", "asw"
    elif "侦查" in equipment or "侦察" in equipment: suffix, group = "scout", "scout"
    elif "航空鱼雷" in equipment: suffix, group = "torpedo_bomber", "airstrike"
    elif mount_type == "Aviation": suffix, group = "bomber", "airstrike"
    elif mount_type == "AntiAir": suffix, group = f"aa_{index:02d}", f"aa_{index:02d}"
    elif "副炮" in equipment or "舰炮" in equipment: suffix, group = f"secondary_{index:02d}", "secondary"
    elif "穿甲" in equipment: suffix, group = "main_ap", "main"
    else: suffix, group = "main_he", "main"
    return f"weapon.{character}_{suffix}", f"{character}_{group}"


def build_weapons() -> tuple[list[dict[str, Any]], dict[str, list[str]], dict[str, dict[str, Any]]]:
    definitions = []
    mounts: dict[str, list[str]] = {identifier: [] for identifier in SHORT_TO_ID.values()}
    group_info: dict[str, dict[str, Any]] = {}
    per_character_index: dict[str, int] = {}
    for row in table_rows("## 8. ", "## 9. "):
        if len(row) != 12:
            continue
        cid = character_id(row[0])
        per_character_index[cid] = per_character_index.get(cid, 0) + 1
        weapon_id, group = weapon_identity(cid, row[1], row[2], per_character_index[cid])
        key = formula_key(row[11])
        mount_type = row[2]
        primary_group = f"{cid}_{PRIMARY_KIND[cid]}"
        control_mode = "ManualPrimary" if group == primary_group else "Automatic"
        projectile_id = "projectile.shell"
        target_types = ["Surface"]
        formula_id = f"formula.{key}"
        if key == "surface_torpedo":
            projectile_id, target_types = "projectile.surface_torpedo", ["Surface", "Submerged"]
        elif key == "submarine_torpedo":
            projectile_id, target_types = "projectile.submarine_torpedo", ["Surface", "Submerged"]
        elif mount_type == "Aviation":
            projectile_id = "projectile.aircraft_bomb"
            target_types = [] if group.endswith("_scout") else ["Surface"]
            formula_id = "formula.medium_he" if key == "aviation" else formula_id
        elif mount_type == "AntiAir":
            target_types, formula_id = ["Air"], "formula.small_he"
        elif mount_type == "AntiSubmarine":
            target_types, formula_id = ["Submerged"], "formula.small_he"
        fire_arc = number(row[7])
        fire_arcs = []
        fire_center = 0.0
        fire_degrees = min(360.0, fire_arc * 2.0)
        if mount_type == "Torpedo":
            if "前部" in row[1]:
                fire_arcs = [{"center": 0, "degrees": fire_degrees}]
            elif "后部" in row[1]:
                fire_center = 180.0
                fire_arcs = [{"center": 180, "degrees": fire_degrees}]
            else:
                fire_center, fire_degrees = 90.0, fire_arc
                fire_arcs = [{"center": -90, "degrees": fire_arc}, {"center": 90, "degrees": fire_arc}]
        ammo = "AP" if "穿甲" in row[1] else "HE" if mount_type == "Gun" else ""
        definition = {
            "id": weapon_id, "display_name": row[1], "weapon_group_id": group,
            "control_mode": control_mode, "ammo_type": ammo, "mount_type": mount_type,
            "mount_count": int(number(row[3])), "shots_per_mount": count(row[4]),
            "reload_time": number(row[5]), "base_range": number(row[6]), "range": number(row[6]) * DISTANCE_BASELINE_MULTIPLIER,
            "minimum_range": 20 if mount_type == "Torpedo" else 0,
            "fire_arc_center": fire_center, "fire_arc_degrees": fire_degrees, "fire_arcs": fire_arcs,
            "base_projectile_speed": number(row[8]), "projectile_speed": number(row[8]) * ATTACK_SPEED_BASELINE_MULTIPLIER, "spread": number(row[9]),
            "base_impact_radius": 36 if mount_type == "Gun" else 0,
            "impact_radius": 36 * GUN_IMPACT_RADIUS_MULTIPLIER if mount_type == "Gun" else 36,
            "accuracy_modifier": number(row[10]), "projectile_id": projectile_id, "formula_id": formula_id,
            "shared_cooldown_group": group if ammo in {"HE", "AP"} and group.endswith("_main") else "",
            "armor_damage_modifiers": ARMOR[key if key in ARMOR else "aviation"], "target_types": target_types,
        }
        if mount_type == "Torpedo":
            definition["torpedo_lane_spacing"] = TORPEDO_LANE_SPACING
            definition["mount_launch_interval"] = TORPEDO_MOUNT_LAUNCH_INTERVAL
            definition["torpedo_angular_sigma_ratio"] = 0.2
            definition["spread"] = torpedo_spread_degrees(definition["range"], definition["shots_per_mount"])
            definition["mount_fire_arcs"] = torpedo_mount_fire_arcs(
                cid, definition["mount_count"], fire_arc, row[1]
            )
        if mount_type == "Gun":
            definition["full_salvo_fire_arcs"] = full_salvo_fire_arcs(
                fire_center, fire_degrees, definition["mount_count"]
            )
        definitions.append(definition)
        mounts[cid].append(weapon_id)
        group_info.setdefault(group, {"character_id": cid, "mount_type": mount_type, "formula": key, "weapon_ids": []})["weapon_ids"].append(weapon_id)
    return definitions, mounts, group_info


def build_skills() -> tuple[list[dict[str, Any]], dict[str, str]]:
    definitions = []
    ids = {}
    for row in table_rows("## 10. ", "## 11. "):
        if len(row) != 8:
            continue
        cid = character_id(row[0])
        plan = json.loads((PLAN_ROOT / cid / "postprocess_plan.json").read_text(encoding="utf-8"))
        skill_id = f"skill.{cid}_{plan['skill_role']}"
        ids[cid] = skill_id
        is_self = row[4] == "自身"
        runtime = SKILL_RUNTIME.get(cid, {})
        target_type = str(runtime.get("target_type", "Self" if is_self else "Area"))
        definition = {
            "id": skill_id, "display_name": row[1], "cooldown": number(row[3]),
            "target_type": target_type, "base_cast_range": 0 if target_type == "Self" else number(row[4]), "cast_range": 0 if target_type == "Self" else number(row[4]) * DISTANCE_BASELINE_MULTIPLIER,
            "duration": number(row[5]), "description": row[6], "design_values": row[7],
            "effects": SKILL_EFFECTS[cid], "implementation_status": "supported",
            "unsupported_effects": [], "vfx_id": f"{cid}.{plan['skill_role']}",
        }
        definition.update(runtime)
        definitions.append(definition)
    return definitions, ids


def display_name(prototype: str) -> str:
    if prototype.startswith("K-21"): return "K-21号"
    if prototype.startswith("Z23"): return "Z23号"
    chinese = re.match(r"[\u4e00-\u9fff\-]+", prototype)
    return chinese.group() if chinese else prototype


def build_ships(mounts: dict[str, list[str]], skill_ids: dict[str, str], weapons: list[dict[str, Any]]) -> list[dict[str, Any]]:
    weapon_by_id = {item["id"]: item for item in weapons}
    definitions = []
    for row in table_rows("## 7. ", "## 8. "):
        if len(row) != 20:
            continue
        cid = character_id(row[0])
        ship_class = SHIP_CLASSES[row[2]]
        primary_group = f"{cid}_{PRIMARY_KIND[cid]}"
        primary_weapons = [weapon_by_id[item] for item in mounts[cid] if weapon_by_id[item]["weapon_group_id"] == primary_group]
        ammo_types = {item["ammo_type"] for item in primary_weapons}
        ammo_group = primary_group if {"HE", "AP"}.issubset(ammo_types) else ""
        definitions.append({
            "id": f"ship.{cid}", "display_name": display_name(row[0]), "faction": FACTIONS[row[1]],
            "ship_class": ship_class, "level": int(row[3]), "cost": int(row[4]), "max_hp": number(row[5]),
            "armor": number(row[6]), "armor_thickness": row[7],
            "base_speed": number(row[8]), "speed": number(row[8]) * MOTION_BASELINE_MULTIPLIER,
            "base_turn_speed": number(row[9]), "turn_speed": number(row[9]) * MOTION_BASELINE_MULTIPLIER,
            "base_detection_range": number(row[10]), "detection_range": number(row[10]) * DISTANCE_BASELINE_MULTIPLIER,
            "base_concealment_distance": number(row[11]), "concealment_distance": number(row[11]) * DISTANCE_BASELINE_MULTIPLIER,
            "fire_concealment_multiplier": number(row[12]), "evasion": number(row[13]),
            "gunnery_power": number(row[14]), "torpedo_power": number(row[15]), "anti_air_power": number(row[16]),
            "aviation_power": number(row[17]), "max_oxygen": number(row[18]), "collision_radius": COLLISION_RADIUS[ship_class],
            "collision_half_extents": collision_half_extents(COLLISION_RADIUS[ship_class]),
            "variant_tags": [item.strip() for item in row[19].split(",")], "weapon_mounts": mounts[cid],
            "primary_weapon_group_id": primary_group,
            "primary_weapon_control_type": {"main": "Area", "torpedo": "Direction", "airstrike": "Airstrike"}[PRIMARY_KIND[cid]],
            "ammo_selection_group_id": ammo_group, "initial_ammo_type": "AP" if ammo_group else "HE",
            "skill_id": skill_ids[cid], "is_flagship_candidate": ship_class in {"LightCruiser", "HeavyCruiser", "Battleship", "Carrier"},
            "asset_root": f"res://assets/characters/{cid}/processed",
        })
    return definitions


def build_visuals(group_info: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    definitions = []
    for group, info in sorted(group_info.items()):
        cid, mount_type, key = info["character_id"], info["mount_type"], info["formula"]
        plan = json.loads((PLAN_ROOT / cid / "postprocess_plan.json").read_text(encoding="utf-8"))
        vfx_roles = plan["vfx_roles"]
        if mount_type == "Torpedo":
            visual = "visual.projectile.torpedo.submerged" if key == "submarine_torpedo" else "visual.projectile.torpedo.heavy" if cid == "takao" else "visual.projectile.torpedo.surface"
            launch_bind, animation = "torpedo_port_01", "firepower"
            launch_profile, impact_profile = "vfx.profile.torpedo_launch", "vfx.profile.torpedo_impact"
            muzzle_role = next((role for role in vfx_roles if "torpedo" in role), vfx_roles[0])
        elif mount_type == "Aviation":
            visual = "visual.projectile.aircraft.scout" if group.endswith("_scout") else "visual.projectile.aircraft.torpedo_bomber" if key == "surface_torpedo" else "visual.projectile.aircraft.bomber"
            launch_bind, animation = "aircraft_launch_01", "firepower"
            launch_profile, impact_profile = "vfx.profile.aircraft.launch_trail", "vfx.profile.airstrike_impact"
            muzzle_role = next((role for role in vfx_roles if "aircraft" in role or "flight" in role), vfx_roles[0])
        else:
            visual = "visual.projectile.shell.large" if key.startswith("large") else "visual.projectile.shell.small" if key in {"small_he", "aa"} else "visual.projectile.shell.medium"
            launch_bind, animation = "muzzle_01", "attack" if mount_type not in {"Gun", "AntiSubmarine"} else "firepower"
            launch_profile = "vfx.profile.muzzle_flash.large" if key.startswith("large") else "vfx.profile.muzzle_flash.medium"
            impact_profile = "vfx.profile.shell_impact.large" if key.startswith("large") else "vfx.profile.shell_impact.medium"
            muzzle_role = next((role for role in vfx_roles if "muzzle" in role or "depth" in role or "aa_" in role), vfx_roles[0])
        definitions.append({
            "id": f"weapon_visual.{group}", "aliases": [group, *info["weapon_ids"]],
            "character_id": cid, "weapon_group_id": group, "projectile_visual_id": visual,
            "fire_animation_state": animation, "launch_bind": launch_bind, "muzzle_vfx_role": muzzle_role,
            "launch_profile": launch_profile, "impact_profile": impact_profile,
            "vfx_role_mappings": {role: semantic for role, semantic in plan["public_vfx_profiles"].items()},
        })
    return definitions


def output(path: str, definitions: list[dict[str, Any]]) -> None:
    destination = ROOT / path
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps({"definitions": definitions}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    weapons, mounts, groups = build_weapons()
    skills, skill_ids = build_skills()
    ships = build_ships(mounts, skill_ids, weapons)
    visuals = build_visuals(groups)
    if not (len(ships) == 24 and len(skills) == 24):
        raise RuntimeError(f"phase2 generation incomplete: ships={len(ships)} skills={len(skills)}")
    output("data/ships/phase2_ships.json", ships)
    output("data/weapons/phase2_weapons.json", weapons)
    output("data/skills/phase2_skills.json", skills)
    output("data/visuals/phase2_weapon_visuals.json", visuals)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
