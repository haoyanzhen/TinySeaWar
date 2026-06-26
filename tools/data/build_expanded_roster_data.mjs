import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const DISTANCE_BASELINE_MULTIPLIER = 1.5;
const ATTACK_SPEED_BASELINE_MULTIPLIER = 0.5;
const output = (path, definitions) => {
  const absolute = resolve(root, path);
  mkdirSync(dirname(absolute), { recursive: true });
  writeFileSync(absolute, `${JSON.stringify({ definitions }, null, 2)}\n`);
};

const armor = {
  small_he: { Unarmored: 1.2, Light: 1.15, Medium: 0.45, Heavy: 0.13, Submerged: 0, Air: 0 },
  medium_he: { Unarmored: 1.15, Light: 1.2, Medium: 0.8, Heavy: 0.45, Submerged: 0, Air: 0 },
  medium_ap: { Unarmored: 0.8, Light: 0.65, Medium: 1.05, Heavy: 0.95, Submerged: 0, Air: 0 },
  large_he: { Unarmored: 1, Light: 1.1, Medium: 0.95, Heavy: 0.75, Submerged: 0, Air: 0 },
  large_ap: { Unarmored: 0.65, Light: 0.45, Medium: 1.1, Heavy: 1.25, Submerged: 0, Air: 0 },
  torpedo: { Unarmored: 0.7, Light: 0.7, Medium: 1, Heavy: 1.25, Submerged: 1, Air: 0 },
  aviation: { Unarmored: 1.1, Light: 1, Medium: 0.9, Heavy: 0.75, Submerged: 0, Air: 0 },
  aa: { Unarmored: 0, Light: 0, Medium: 0, Heavy: 0, Submerged: 0, Air: 1 },
};

const common = (id, name, group, mode, type, mounts, shots, reload, range, speed, spread, accuracy) => ({
  id, display_name: name, weapon_group_id: group, control_mode: mode, ammo_type: "", mount_type: type,
  mount_count: mounts, shots_per_mount: shots, reload_time: reload, base_range: range, range: range * DISTANCE_BASELINE_MULTIPLIER, minimum_range: 0,
  fire_arc_center: 0, fire_arc_degrees: 360, base_projectile_speed: speed, projectile_speed: speed * ATTACK_SPEED_BASELINE_MULTIPLIER, spread,
  impact_radius: 36, accuracy_modifier: accuracy, shared_cooldown_group: "",
});

const gun = ({ id, name, group, mode = "Automatic", ammo = "HE", mounts, shots, reload, range, arc, speed, spread, accuracy, formula }) => ({
  ...common(id, name, group, mode, "Gun", mounts, shots, reload, range, speed, spread, accuracy),
  ammo_type: ammo, fire_arc_degrees: Math.min(360, arc * 2), projectile_id: "projectile.shell",
  formula_id: `formula.${formula}`, impact_radius: formula.startsWith("large") ? 48 : formula.startsWith("medium") ? 40 : 30,
  shared_cooldown_group: ammo === "AP" || ammo === "HE" ? group : "", armor_damage_modifiers: armor[formula], target_types: ["Surface"],
});

const torpedo = ({ id, name, group, mounts, shots, reload, range, arc, speed, spread, submarine = false, center = null }) => {
  const definition = {
    ...common(id, name, group, "ManualPrimary", "Torpedo", mounts, shots, reload, range, speed, spread, 0),
    minimum_range: 20, projectile_id: submarine ? "projectile.submarine_torpedo" : "projectile.surface_torpedo",
    formula_id: submarine ? "formula.submarine_torpedo" : "formula.surface_torpedo", impact_radius: 0,
    armor_damage_modifiers: armor.torpedo, target_types: ["Surface", "Submerged"],
  };
  if (center === null) {
    definition.fire_arc_center = 90;
    definition.fire_arc_degrees = arc;
    definition.fire_arcs = [{ center: -90, degrees: arc }, { center: 90, degrees: arc }];
  } else {
    definition.fire_arc_center = center;
    definition.fire_arc_degrees = arc * 2;
    definition.fire_arcs = [{ center, degrees: arc * 2 }];
  }
  return definition;
};

const aa = ({ id, name, group, mounts, shots, reload, range }) => ({
  ...common(id, name, group, "Automatic", "AntiAir", mounts, shots, reload, range, 320, 0, 0),
  projectile_id: "projectile.shell", formula_id: "formula.small_he", impact_radius: 18,
  armor_damage_modifiers: armor.aa, target_types: ["Air"],
});

const aviation = ({ id, name, group, mounts, shots, reload, range, speed, spread, accuracy, formula = "medium_he" }) => ({
  ...common(id, name, group, "ManualPrimary", "Aviation", mounts, shots, reload, range, speed, spread, accuracy),
  projectile_id: "projectile.aircraft_bomb", formula_id: `formula.${formula}`, impact_radius: 48,
  shared_cooldown_group: group, armor_damage_modifiers: armor.aviation, target_types: ["Surface"],
});

const weapons = [
  aviation({ id:"weapon.enterprise_airstrike", name:"舰载机攻击队", group:"enterprise_airstrike", mounts:2, shots:8, reload:14, range:760, speed:180, spread:24, accuracy:0.06 }),
  aa({ id:"weapon.enterprise_aa", name:"企业号防空炮阵", group:"enterprise_aa", mounts:8, shots:4, reload:0.6, range:270 }),
  gun({ id:"weapon.iowa_406_ap", name:"406毫米主炮（穿甲弹）", group:"iowa_main", mode:"ManualPrimary", ammo:"AP", mounts:3, shots:3, reload:10, range:740, arc:145, speed:430, spread:18, accuracy:0.03, formula:"large_ap" }),
  gun({ id:"weapon.iowa_406_he", name:"406毫米主炮（高爆弹）", group:"iowa_main", mode:"ManualPrimary", ammo:"HE", mounts:3, shots:3, reload:10, range:700, arc:145, speed:400, spread:24, accuracy:0, formula:"large_he" }),
  gun({ id:"weapon.iowa_127_he", name:"127毫米副炮", group:"iowa_secondary", mounts:10, shots:2, reload:3.2, range:340, arc:160, speed:320, spread:18, accuracy:0.02, formula:"small_he" }),
  aa({ id:"weapon.iowa_aa", name:"衣阿华号防空炮阵", group:"iowa_aa", mounts:10, shots:4, reload:0.55, range:280 }),
  gun({ id:"weapon.san_diego_127_he", name:"127毫米两用炮高爆", group:"san_diego_gun", mounts:8, shots:2, reload:3.2, range:410, arc:160, speed:330, spread:18, accuracy:0.03, formula:"small_he" }),
  torpedo({ id:"weapon.san_diego_torpedo", name:"533毫米鱼雷", group:"san_diego_torpedo", mounts:2, shots:4, reload:18, range:400, arc:70, speed:140, spread:14 }),
  aa({ id:"weapon.san_diego_aa_heavy", name:"127毫米两用炮防空", group:"san_diego_aa_heavy", mounts:8, shots:2, reload:1.2, range:310 }),
  aa({ id:"weapon.san_diego_aa_rapid", name:"防空炮阵", group:"san_diego_aa_rapid", mounts:8, shots:4, reload:0.45, range:300 }),
  gun({ id:"weapon.ward_102_he", name:"102毫米主炮高爆", group:"ward_gun", mounts:4, shots:1, reload:2.8, range:330, arc:150, speed:300, spread:20, accuracy:0.02, formula:"small_he" }),
  torpedo({ id:"weapon.ward_torpedo", name:"533毫米鱼雷", group:"ward_torpedo", mounts:4, shots:3, reload:16, range:420, arc:70, speed:150, spread:14 }),
  gun({ id:"weapon.hood_381_ap", name:"381毫米主炮（穿甲弹）", group:"hood_main", mode:"ManualPrimary", ammo:"AP", mounts:4, shots:2, reload:9.8, range:700, arc:145, speed:420, spread:18, accuracy:0.03, formula:"large_ap" }),
  gun({ id:"weapon.hood_381_he", name:"381毫米主炮（高爆弹）", group:"hood_main", mode:"ManualPrimary", ammo:"HE", mounts:4, shots:2, reload:9.8, range:670, arc:145, speed:390, spread:24, accuracy:0, formula:"large_he" }),
  gun({ id:"weapon.hood_secondary", name:"护航副炮", group:"hood_secondary", mounts:6, shots:1, reload:3.6, range:320, arc:150, speed:300, spread:18, accuracy:0.01, formula:"medium_he" }),
  gun({ id:"weapon.sirius_133_he", name:"133毫米两用炮高爆", group:"sirius_main", mode:"ManualPrimary", mounts:5, shots:2, reload:3.2, range:400, arc:155, speed:330, spread:18, accuracy:0.03, formula:"small_he" }),
  aa({ id:"weapon.sirius_aa", name:"天狼星号防空炮阵", group:"sirius_aa", mounts:7, shots:4, reload:0.6, range:290 }),
  aviation({ id:"weapon.argus_airstrike", name:"基础空袭队", group:"argus_airstrike", mounts:1, shots:4, reload:16, range:660, speed:150, spread:28, accuracy:0 }),
  aa({ id:"weapon.argus_aa", name:"百眼巨人号轻防空", group:"argus_aa", mounts:4, shots:1, reload:1.4, range:220 }),
  gun({ id:"weapon.kirov_180_ap", name:"180毫米主炮（穿甲弹）", group:"kirov_main", ammo:"AP", mounts:3, shots:3, reload:5, range:540, arc:150, speed:380, spread:16, accuracy:0.03, formula:"medium_ap" }),
  gun({ id:"weapon.kirov_180_he", name:"180毫米主炮（高爆弹）", group:"kirov_main", ammo:"HE", mounts:3, shots:3, reload:4.7, range:510, arc:150, speed:350, spread:22, accuracy:0.01, formula:"medium_he" }),
  torpedo({ id:"weapon.kirov_torpedo", name:"533毫米鱼雷", group:"kirov_torpedo", mounts:2, shots:3, reload:15, range:430, arc:70, speed:145, spread:12 }),
  aviation({ id:"weapon.pobeda_bomber", name:"攻击机编队", group:"pobeda_airstrike", mounts:2, shots:6, reload:15, range:730, speed:170, spread:24, accuracy:0.03 }),
  aviation({ id:"weapon.pobeda_ap_bomber", name:"航空穿甲弹编队", group:"pobeda_airstrike", mounts:1, shots:4, reload:20, range:710, speed:160, spread:18, accuracy:0.02, formula:"large_ap" }),
  gun({ id:"weapon.gnevny_130_he", name:"130毫米主炮高爆", group:"gnevny_gun", mounts:4, shots:1, reload:2.7, range:360, arc:150, speed:320, spread:20, accuracy:0.01, formula:"small_he" }),
  torpedo({ id:"weapon.gnevny_torpedo", name:"533毫米鱼雷", group:"gnevny_torpedo", mounts:2, shots:3, reload:14, range:440, arc:70, speed:150, spread:12 }),
  gun({ id:"weapon.prinz_203_ap", name:"203毫米主炮（穿甲弹）", group:"prinz_main", ammo:"AP", mounts:4, shots:2, reload:5.3, range:530, arc:150, speed:380, spread:16, accuracy:0.04, formula:"medium_ap" }),
  gun({ id:"weapon.prinz_203_he", name:"203毫米主炮（高爆弹）", group:"prinz_main", ammo:"HE", mounts:4, shots:2, reload:4.8, range:500, arc:150, speed:350, spread:22, accuracy:0.01, formula:"medium_he" }),
  torpedo({ id:"weapon.prinz_torpedo", name:"533毫米鱼雷", group:"prinz_torpedo", mounts:2, shots:3, reload:16, range:430, arc:75, speed:145, spread:12 }),
  torpedo({ id:"weapon.u47_fore_torpedo", name:"前部鱼雷发射管", group:"u47_torpedo", mounts:1, shots:4, reload:16, range:470, arc:55, speed:155, spread:8, submarine:true, center:0 }),
  torpedo({ id:"weapon.u47_aft_torpedo", name:"后部鱼雷发射管", group:"u47_torpedo", mounts:1, shots:1, reload:18, range:400, arc:45, speed:145, spread:10, submarine:true, center:180 }),
  gun({ id:"weapon.yamato_460_ap", name:"460毫米主炮（穿甲弹）", group:"yamato_main", mode:"ManualPrimary", ammo:"AP", mounts:3, shots:3, reload:12, range:780, arc:135, speed:440, spread:20, accuracy:0.02, formula:"large_ap" }),
  gun({ id:"weapon.yamato_460_he", name:"460毫米主炮（高爆弹）", group:"yamato_main", mode:"ManualPrimary", ammo:"HE", mounts:3, shots:3, reload:12, range:740, arc:135, speed:400, spread:28, accuracy:0, formula:"large_he" }),
  gun({ id:"weapon.yamato_155_he", name:"155毫米副炮", group:"yamato_secondary", mounts:4, shots:3, reload:4.5, range:360, arc:140, speed:320, spread:22, accuracy:0.01, formula:"medium_he" }),
  gun({ id:"weapon.yukikaze_127_he", name:"127毫米主炮高爆", group:"yukikaze_gun", mounts:3, shots:2, reload:2.6, range:360, arc:155, speed:320, spread:18, accuracy:0.03, formula:"small_he" }),
  torpedo({ id:"weapon.yukikaze_torpedo", name:"610毫米鱼雷", group:"yukikaze_torpedo", mounts:2, shots:4, reload:15, range:500, arc:70, speed:165, spread:10 }),
  aviation({ id:"weapon.hosho_airstrike", name:"轻空袭队", group:"hosho_airstrike", mounts:1, shots:4, reload:16, range:650, speed:150, spread:28, accuracy:0 }),
  gun({ id:"weapon.ning_140_he", name:"140毫米主炮（高爆弹）", group:"ning_main", ammo:"HE", mounts:3, shots:2, reload:3.6, range:400, arc:150, speed:320, spread:20, accuracy:0.02, formula:"medium_he" }),
  gun({ id:"weapon.ning_140_ap", name:"140毫米主炮（穿甲弹）", group:"ning_main", ammo:"AP", mounts:3, shots:2, reload:4, range:390, arc:150, speed:340, spread:16, accuracy:0, formula:"medium_ap" }),
  torpedo({ id:"weapon.ning_torpedo", name:"533毫米鱼雷", group:"ning_torpedo", mounts:2, shots:2, reload:17, range:400, arc:70, speed:140, spread:14 }),
  aa({ id:"weapon.ning_aa", name:"宁海号防空节点", group:"ning_aa", mounts:5, shots:2, reload:0.9, range:260 }),
  gun({ id:"weapon.anshan_130_he", name:"130毫米主炮高爆", group:"anshan_gun", mounts:4, shots:1, reload:2.7, range:370, arc:155, speed:330, spread:18, accuracy:0.03, formula:"small_he" }),
  torpedo({ id:"weapon.anshan_torpedo", name:"533毫米鱼雷", group:"anshan_torpedo", mounts:2, shots:3, reload:15, range:440, arc:70, speed:150, spread:12 }),
  aa({ id:"weapon.anshan_aa", name:"鞍山号轻防空", group:"anshan_aa", mounts:4, shots:2, reload:0.95, range:250 }),
  gun({ id:"weapon.chongqing_152_he", name:"152毫米主炮（高爆弹）", group:"chongqing_main", ammo:"HE", mounts:4, shots:3, reload:3.6, range:420, arc:150, speed:330, spread:20, accuracy:0.03, formula:"medium_he" }),
  gun({ id:"weapon.chongqing_152_ap", name:"152毫米主炮（穿甲弹）", group:"chongqing_main", ammo:"AP", mounts:4, shots:3, reload:4, range:410, arc:150, speed:350, spread:16, accuracy:0.01, formula:"medium_ap" }),
  torpedo({ id:"weapon.chongqing_torpedo", name:"533毫米鱼雷", group:"chongqing_torpedo", mounts:2, shots:3, reload:18, range:410, arc:70, speed:140, spread:14 }),
  aa({ id:"weapon.chongqing_aa", name:"重庆号防空节点", group:"chongqing_aa", mounts:6, shots:2, reload:0.8, range:270 }),
];

const effect = (scope, stat, operation, value, category, group) => ({ scope, stat, operation, value, category, stack_group: group, stack_rule: "Refresh" });
const skill = (id, name, cooldown, target_type, cast_range, duration, effects) => ({ id, display_name:name, cooldown, target_type, base_cast_range: cast_range, cast_range: cast_range > 0 ? cast_range * DISTANCE_BASELINE_MULTIPLIER : 0, duration, effects });
const skills = [
  skill("skill.enterprise_multi_wave","多波次空袭",45,"Area",760,12,[effect("Self","Damage","PercentAdd",0.2,"Aviation","enterprise_skill"),effect("Self","AccuracyPoint","FlatAdd",0.1,"Aviation","enterprise_skill")]),
  skill("skill.iowa_radar_salvo","雷达校准齐射",42,"Enemy",760,8,[effect("Self","AccuracyPoint","FlatAdd",0.18,"Gun","iowa_skill"),effect("Self","ArmorDamageModifier","PercentAdd",0.1,"Gun","iowa_skill")]),
  skill("skill.san_diego_aa_center","防空弹幕中心",36,"Area",330,10,[effect("AlliesInArea","ReloadSpeed","PercentAdd",0.33,"AntiAir","san_diego_skill"),effect("AlliesInArea","Damage","PercentAdd",0.2,"AntiAir","san_diego_skill"),effect("AlliesInArea","DamageReduction","PercentAdd",0.2,"Aviation","san_diego_skill")]),
  skill("skill.ward_first_alert","第一警戒",28,"Self",0,12,[effect("Self","DetectionRange","FlatAdd",90,"All","ward_skill"),effect("Self","Speed","PercentAdd",0.12,"All","ward_skill"),effect("Self","ReloadSpeed","PercentAdd",0.25,"Gun","ward_skill")]),
  skill("skill.hood_fleet_glory","舰队荣光",48,"Area",430,14,[effect("AlliesInArea","Speed","PercentAdd",0.1,"All","hood_skill"),effect("AlliesInArea","TurnSpeed","PercentAdd",0.12,"All","hood_skill"),effect("AlliesInArea","ConcealmentDistance","PercentAdd",-0.08,"All","hood_skill")]),
  skill("skill.sirius_silver_escort","银白护航圈",38,"Area",310,12,[effect("AlliesInArea","ReloadSpeed","PercentAdd",0.25,"AntiAir","sirius_skill"),effect("AlliesInArea","AccuracyPoint","FlatAdd",0.06,"Gun","sirius_skill"),effect("AlliesInArea","DetectionRange","FlatAdd",40,"All","sirius_skill")]),
  skill("skill.argus_training_scout","训练侦察队",32,"Self",0,35,[effect("Self","DetectionRange","FlatAdd",80,"All","argus_skill"),effect("Self","AccuracyPoint","FlatAdd",0.06,"Aviation","argus_skill")]),
  skill("skill.kirov_ice_suppression","冰线压制",38,"Area",540,6,[effect("Self","Damage","PercentAdd",0.12,"Gun","kirov_skill"),effect("EnemiesInArea","TurnSpeed","PercentAdd",-0.15,"All","kirov_slow")]),
  skill("skill.pobeda_air_support","方案航空支援",44,"Self",0,14,[effect("Self","Damage","PercentAdd",0.2,"Aviation","pobeda_skill"),effect("Self","AccuracyPoint","FlatAdd",0.08,"Aviation","pobeda_skill")]),
  skill("skill.gnevny_snow_torpedo","雪线雷击",32,"Self",0,6,[effect("Self","Speed","PercentAdd",0.18,"All","gnevny_skill"),effect("Self","ExtraShots","FlatAdd",2,"Torpedo","gnevny_skill")]),
  skill("skill.prinz_precision_evasion","精密规避",34,"Self",0,8,[effect("Self","Evasion","FlatAdd",35,"All","prinz_skill"),effect("Self","AccuracyPoint","FlatAdd",0.12,"Gun","prinz_skill")]),
  skill("skill.u47_silent_ambush","静默伏击",36,"Self",0,12,[effect("Self","ConcealmentDistance","StateMultiply",0.75,"All","u47_skill"),effect("Self","Damage","PercentAdd",0.18,"Torpedo","u47_skill")]),
  skill("skill.yamato_full_salvo","主炮全开",55,"Self",0,8,[effect("Self","Damage","PercentAdd",0.25,"Gun","yamato_skill"),effect("Self","AccuracyPoint","FlatAdd",-0.03,"Gun","yamato_skill")]),
  skill("skill.yukikaze_lucky_evasion","幸运回避",34,"Area",360,10,[effect("Self","Evasion","FlatAdd",45,"All","yukikaze_skill"),effect("Self","ProjectileSpeed","PercentAdd",0.12,"Torpedo","yukikaze_skill"),effect("AlliesInArea","ReloadSpeed","PercentAdd",0.11,"All","yukikaze_aura")]),
  skill("skill.hosho_light_training","轻型空袭训练",34,"Self",0,10,[effect("Self","Damage","PercentAdd",0.15,"Aviation","hosho_skill"),effect("Self","DetectionRange","FlatAdd",60,"All","hosho_skill")]),
  skill("skill.ning_coastal_escort","近海护卫",36,"Area",300,12,[effect("AlliesInArea","Damage","PercentAdd",0.25,"AntiAir","ning_skill"),effect("AlliesInArea","Armor","FlatAdd",8,"All","ning_skill"),effect("AlliesInArea","ReloadSpeed","PercentAdd",0.14,"Gun","ning_skill")]),
  skill("skill.anshan_escort_alert","护航警戒",34,"Area",520,12,[effect("Self","DetectionRange","FlatAdd",80,"All","anshan_skill"),effect("AlliesInArea","Evasion","FlatAdd",10,"All","anshan_aura")]),
  skill("skill.chongqing_turning_support","转折支援",40,"Area",420,12,[effect("AlliesInArea","AccuracyPoint","FlatAdd",0.08,"Gun","chongqing_skill"),effect("AlliesInArea","ReloadSpeed","PercentAdd",0.18,"AntiAir","chongqing_skill")]),
];

output("data/weapons/expanded_roster_weapons.json", weapons);
output("data/skills/expanded_roster_skills.json", skills);
