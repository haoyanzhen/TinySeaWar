import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const DISTANCE_BASELINE_MULTIPLIER = 1.5;
const ATTACK_SPEED_BASELINE_MULTIPLIER = 0.5;
const GUN_IMPACT_RADIUS_MULTIPLIER = 0.5;
const TORPEDO_LANE_SPACING = 80;
const TORPEDO_MOUNT_LAUNCH_INTERVAL = 1;
const torpedoSpreadDegrees = (effectiveRange, shots) => shots <= 1 ? 0 :
  2 * Math.asin(Math.min(1, TORPEDO_LANE_SPACING / (2 * effectiveRange))) * 180 / Math.PI * (shots - 1);
const torpedoMountFireArcs = (mounts, arc, layout, center) => Array.from({ length: mounts }, (_, index) => {
  let fireArcs;
  if (center !== null) fireArcs = [{ center, degrees: arc * 2 }];
  else if (layout === "wing") fireArcs = [{ center: index < mounts / 2 ? -90 : 90, degrees: arc }];
  else fireArcs = [{ center: -90, degrees: arc }, { center: 90, degrees: arc }];
  return { mount_id: `mount_${index + 1}`, fire_arcs: fireArcs };
});
const fullSalvoFireArcs = (center, degrees, mounts) => {
  if (mounts <= 1) return [{ center, degrees }];
  const broadsideDegrees = Math.max(30, Math.min(120, degrees - 180));
  return [
    { center: center - 90, degrees: broadsideDegrees },
    { center: center + 90, degrees: broadsideDegrees },
  ];
};
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

const gun = ({ id, name, group, mode = "Automatic", ammo = "HE", mounts, shots, reload, range, arc, speed, spread, accuracy, formula }) => {
  const fireArcDegrees = Math.min(360, arc * 2);
  const baseImpactRadius = formula.startsWith("large") ? 48 : formula.startsWith("medium") ? 40 : 30;
  return {
    ...common(id, name, group, mode, "Gun", mounts, shots, reload, range, speed, spread, accuracy),
    ammo_type: ammo, fire_arc_degrees: fireArcDegrees,
    full_salvo_fire_arcs: fullSalvoFireArcs(0, fireArcDegrees, mounts), projectile_id: "projectile.shell",
    formula_id: `formula.${formula}`, base_impact_radius: baseImpactRadius, impact_radius: baseImpactRadius * GUN_IMPACT_RADIUS_MULTIPLIER,
    shared_cooldown_group: ammo === "AP" || ammo === "HE" ? group : "", armor_damage_modifiers: armor[formula], target_types: ["Surface"],
  };
};

const torpedo = ({ id, name, group, mounts, shots, reload, range, arc, speed, spread: _legacySpread, submarine = false, center = null, layout = "centerline" }) => {
  const effectiveRange = range * DISTANCE_BASELINE_MULTIPLIER;
  const spread = torpedoSpreadDegrees(effectiveRange, shots);
  const mountFireArcs = torpedoMountFireArcs(mounts, arc, layout, center);
  const definition = {
    ...common(id, name, group, "ManualPrimary", "Torpedo", mounts, shots, reload, range, speed, spread, 0),
    minimum_range: 20, projectile_id: submarine ? "projectile.submarine_torpedo" : "projectile.surface_torpedo",
    formula_id: submarine ? "formula.submarine_torpedo" : "formula.surface_torpedo", impact_radius: 0,
    armor_damage_modifiers: armor.torpedo, target_types: ["Surface", "Submerged"],
    torpedo_lane_spacing: TORPEDO_LANE_SPACING, mount_launch_interval: TORPEDO_MOUNT_LAUNCH_INTERVAL,
    torpedo_angular_sigma_ratio: 0.2,
    mount_fire_arcs: mountFireArcs,
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
  torpedo({ id:"weapon.san_diego_torpedo", name:"533毫米鱼雷", group:"san_diego_torpedo", mounts:2, shots:4, reload:18, range:400, arc:70, speed:140, spread:14, layout:"wing" }),
  aa({ id:"weapon.san_diego_aa_heavy", name:"127毫米两用炮防空", group:"san_diego_aa_heavy", mounts:8, shots:2, reload:1.2, range:310 }),
  aa({ id:"weapon.san_diego_aa_rapid", name:"防空炮阵", group:"san_diego_aa_rapid", mounts:8, shots:4, reload:0.45, range:300 }),
  gun({ id:"weapon.ward_102_he", name:"102毫米主炮高爆", group:"ward_gun", mounts:4, shots:1, reload:2.8, range:330, arc:150, speed:300, spread:20, accuracy:0.02, formula:"small_he" }),
  torpedo({ id:"weapon.ward_torpedo", name:"533毫米鱼雷", group:"ward_torpedo", mounts:4, shots:3, reload:16, range:420, arc:70, speed:150, spread:14, layout:"wing" }),
  gun({ id:"weapon.hood_381_ap", name:"381毫米主炮（穿甲弹）", group:"hood_main", mode:"ManualPrimary", ammo:"AP", mounts:4, shots:2, reload:9.8, range:700, arc:145, speed:420, spread:18, accuracy:0.03, formula:"large_ap" }),
  gun({ id:"weapon.hood_381_he", name:"381毫米主炮（高爆弹）", group:"hood_main", mode:"ManualPrimary", ammo:"HE", mounts:4, shots:2, reload:9.8, range:670, arc:145, speed:390, spread:24, accuracy:0, formula:"large_he" }),
  gun({ id:"weapon.hood_secondary", name:"护航副炮", group:"hood_secondary", mounts:6, shots:1, reload:3.6, range:320, arc:150, speed:300, spread:18, accuracy:0.01, formula:"medium_he" }),
  gun({ id:"weapon.sirius_133_he", name:"133毫米两用炮高爆", group:"sirius_main", mode:"ManualPrimary", mounts:5, shots:2, reload:3.2, range:400, arc:155, speed:330, spread:18, accuracy:0.03, formula:"small_he" }),
  aa({ id:"weapon.sirius_aa", name:"天狼星号防空炮阵", group:"sirius_aa", mounts:7, shots:4, reload:0.6, range:290 }),
  aviation({ id:"weapon.argus_airstrike", name:"基础空袭队", group:"argus_airstrike", mounts:1, shots:4, reload:16, range:660, speed:150, spread:28, accuracy:0 }),
  aa({ id:"weapon.argus_aa", name:"百眼巨人号轻防空", group:"argus_aa", mounts:4, shots:1, reload:1.4, range:220 }),
  gun({ id:"weapon.kirov_180_ap", name:"180毫米主炮（穿甲弹）", group:"kirov_main", ammo:"AP", mounts:3, shots:3, reload:5, range:540, arc:150, speed:380, spread:16, accuracy:0.03, formula:"medium_ap" }),
  gun({ id:"weapon.kirov_180_he", name:"180毫米主炮（高爆弹）", group:"kirov_main", ammo:"HE", mounts:3, shots:3, reload:4.7, range:510, arc:150, speed:350, spread:22, accuracy:0.01, formula:"medium_he" }),
  torpedo({ id:"weapon.kirov_torpedo", name:"533毫米鱼雷", group:"kirov_torpedo", mounts:2, shots:3, reload:15, range:430, arc:70, speed:145, spread:12, layout:"wing" }),
  aviation({ id:"weapon.pobeda_bomber", name:"攻击机编队", group:"pobeda_airstrike", mounts:2, shots:6, reload:15, range:730, speed:170, spread:24, accuracy:0.03 }),
  aviation({ id:"weapon.pobeda_ap_bomber", name:"航空穿甲弹编队", group:"pobeda_airstrike", mounts:1, shots:4, reload:20, range:710, speed:160, spread:18, accuracy:0.02, formula:"large_ap" }),
  gun({ id:"weapon.gnevny_130_he", name:"130毫米主炮高爆", group:"gnevny_gun", mounts:4, shots:1, reload:2.7, range:360, arc:150, speed:320, spread:20, accuracy:0.01, formula:"small_he" }),
  torpedo({ id:"weapon.gnevny_torpedo", name:"533毫米鱼雷", group:"gnevny_torpedo", mounts:2, shots:3, reload:14, range:440, arc:70, speed:150, spread:12 }),
  gun({ id:"weapon.prinz_203_ap", name:"203毫米主炮（穿甲弹）", group:"prinz_main", ammo:"AP", mounts:4, shots:2, reload:5.3, range:530, arc:150, speed:380, spread:16, accuracy:0.04, formula:"medium_ap" }),
  gun({ id:"weapon.prinz_203_he", name:"203毫米主炮（高爆弹）", group:"prinz_main", ammo:"HE", mounts:4, shots:2, reload:4.8, range:500, arc:150, speed:350, spread:22, accuracy:0.01, formula:"medium_he" }),
  torpedo({ id:"weapon.prinz_torpedo", name:"533毫米鱼雷", group:"prinz_torpedo", mounts:2, shots:3, reload:16, range:430, arc:75, speed:145, spread:12, layout:"wing" }),
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
  torpedo({ id:"weapon.ning_torpedo", name:"533毫米鱼雷", group:"ning_torpedo", mounts:2, shots:2, reload:17, range:400, arc:70, speed:140, spread:14, layout:"wing" }),
  aa({ id:"weapon.ning_aa", name:"宁海号防空节点", group:"ning_aa", mounts:5, shots:2, reload:0.9, range:260 }),
  gun({ id:"weapon.anshan_130_he", name:"130毫米主炮高爆", group:"anshan_gun", mounts:4, shots:1, reload:2.7, range:370, arc:155, speed:330, spread:18, accuracy:0.03, formula:"small_he" }),
  torpedo({ id:"weapon.anshan_torpedo", name:"533毫米鱼雷", group:"anshan_torpedo", mounts:2, shots:3, reload:15, range:440, arc:70, speed:150, spread:12 }),
  aa({ id:"weapon.anshan_aa", name:"鞍山号轻防空", group:"anshan_aa", mounts:4, shots:2, reload:0.95, range:250 }),
  gun({ id:"weapon.chongqing_152_he", name:"152毫米主炮（高爆弹）", group:"chongqing_main", ammo:"HE", mounts:4, shots:3, reload:3.6, range:420, arc:150, speed:330, spread:20, accuracy:0.03, formula:"medium_he" }),
  gun({ id:"weapon.chongqing_152_ap", name:"152毫米主炮（穿甲弹）", group:"chongqing_main", ammo:"AP", mounts:4, shots:3, reload:4, range:410, arc:150, speed:350, spread:16, accuracy:0.01, formula:"medium_ap" }),
  torpedo({ id:"weapon.chongqing_torpedo", name:"533毫米鱼雷", group:"chongqing_torpedo", mounts:2, shots:3, reload:18, range:410, arc:70, speed:140, spread:14, layout:"wing" }),
  aa({ id:"weapon.chongqing_aa", name:"重庆号防空节点", group:"chongqing_aa", mounts:6, shots:2, reload:0.8, range:270 }),
];

const effect = (scope, stat, operation, value, category, group, extra={}) => ({ scope, stat, operation, value, category, stack_group: group, stack_rule: "Refresh", ...extra });
const skill = (id, name, cooldown, target_type, cast_range, duration, effects, extra={}) => ({
  id, display_name:name, cooldown, target_type,
  base_cast_range: cast_range,
  cast_range: cast_range > 0 ? cast_range * DISTANCE_BASELINE_MULTIPLIER : 0,
  duration, effects, implementation_status:"supported", unsupported_effects:[], ...extra,
});
const skills = [
  skill("skill.enterprise_multi_wave","多波次空袭",45,"Area",760,12,[],{description:"指定区域连续派出两批攻击机。",design_values:"2 波；每波 6 机；航空伤害 +20%；对已侦查目标命中率 +10 个百分点",effect_radius:60,ai_tags:["Burst","AreaAttack","Aviation"],triggered_attacks:[{weapon_id:"weapon.enterprise_airstrike",waves:2,wave_interval:2,shots_per_wave:6,modifiers:[effect("Self","Damage","PercentAdd",.2,"Aviation","enterprise_skill"),effect("Self","AccuracyPoint","FlatAdd",.1,"Aviation","enterprise_skill",{requires_scouted_target:true})]}]}),
  skill("skill.iowa_radar_salvo","雷达校准齐射",42,"Enemy",760,8,[effect("Self","AccuracyPoint","FlatAdd",.18,"Gun","iowa_skill",{consume_on_fire:true,persistent_until_consumed:true,consume_weapon_group_id:"iowa_main",bind_selected_target:true}),effect("Self","ArmorDamageModifier","PercentAdd",.1,"Gun","iowa_skill",{consume_on_fire:true,persistent_until_consumed:true,consume_weapon_group_id:"iowa_main",bind_selected_target:true}),effect("Self","FiringRevealMultiplier","PercentAdd",.2,"All","iowa_skill",{consume_on_fire:true,persistent_until_consumed:true,consume_weapon_group_id:"iowa_main"})],{description:"主炮进入校准状态，对选定目标集中射击。",ai_tags:["Burst","TargetAttack"]}),
  skill("skill.san_diego_aa_center","防空弹幕中心",36,"Self",0,10,[effect("AlliesInArea","ReloadSpeed","PercentAdd",.33,"AntiAir","san_diego_skill"),effect("AlliesInArea","Damage","PercentAdd",.2,"AntiAir","san_diego_skill"),effect("AlliesInArea","WeaponRange","FlatAdd",60,"AntiAir","san_diego_skill"),effect("AlliesInArea","DamageReduction","PercentAdd",.2,"Aviation","san_diego_skill")],{base_effect_radius:330,effect_radius:495,description:"强化自身防空圈并保护附近友军。",ai_tags:["Defense","AntiAir","AreaSupport"]}),
  skill("skill.ward_first_alert","第一警戒",28,"Self",0,12,[effect("Self","DetectionRange","FlatAdd",90,"All","ward_skill"),effect("Self","Speed","PercentAdd",0.12,"All","ward_skill"),effect("Self","ReloadSpeed","PercentAdd",0.25,"Gun","ward_skill")],{description:"提升侦查并快速压制近距离目标。",ai_tags:["Recon","Mobility","Burst"]}),
  skill("skill.hood_fleet_glory","舰队荣光",48,"Self",0,14,[effect("AlliesInArea","Speed","PercentAdd",.1,"All","hood_skill"),effect("AlliesInArea","TurnSpeed","PercentAdd",.12,"All","hood_skill"),effect("AlliesInArea","FiringRevealMultiplier","PercentAdd",-.08,"All","hood_skill")],{base_effect_radius:430,effect_radius:645,description:"提升周围友军机动和士气。",ai_tags:["Mobility","AreaSupport"]}),
  skill("skill.sirius_silver_escort","银白护航圈",38,"Self",0,12,[effect("AlliesInArea","ReloadSpeed","PercentAdd",.25,"AntiAir","sirius_skill"),effect("AlliesInArea","AccuracyPoint","FlatAdd",.06,"Gun","sirius_skill"),effect("AlliesInArea","DetectionRange","FlatAdd",40,"All","sirius_skill")],{base_effect_radius:310,effect_radius:465,description:"展开护航光环，拦截航空并提升友军命中。",ai_tags:["AntiAir","AreaSupport"]}),
  skill("skill.argus_training_scout","训练侦察队",32,"Area",820,35,[],{effect_radius:570,description:"部署早期侦查机，暴露指定空域。",ai_tags:["Recon","AreaSupport"],recon_zones:[{radius:570,duration:35,aircraft_hp:350,destroyed_cooldown_penalty:8}]}),
  skill("skill.kirov_ice_suppression","冰线压制",38,"Area",540,6,[],{effect_radius:60,description:"向扇形区域进行高压炮击。",ai_tags:["Burst","AreaAttack","Control"],triggered_attacks:[{weapon_id:"weapon.kirov_180_ap",shots_per_wave:9,modifiers:[effect("Self","Damage","PercentAdd",.12,"Gun","kirov_skill")],on_hit_effects:[effect("EnemiesInArea","TurnSpeed","PercentAdd",-.15,"All","kirov_slow",{duration:6})]}]}),
  skill("skill.pobeda_air_support","方案航空支援",44,"Area",740,14,[],{effect_radius:70,description:"派出混合航空编队支援前线。",ai_tags:["Burst","AreaAttack","Aviation"],triggered_attacks:[{weapon_id:"weapon.pobeda_bomber",modifiers:[effect("Self","AircraftHP","PercentAdd",.2,"Aviation","pobeda_skill")]},{weapon_id:"weapon.pobeda_ap_bomber",modifiers:[effect("Self","AircraftHP","PercentAdd",.2,"Aviation","pobeda_skill"),effect("Self","AviationDamageFloor","FlatAdd",.35,"Aviation","pobeda_skill")]}]}),
  skill("skill.gnevny_snow_torpedo","雪线雷击",32,"Self",0,6,[effect("Self","Speed","PercentAdd",.18,"All","gnevny_skill"),effect("Self","ExtraShots","FlatAdd",2,"Torpedo","gnevny_skill",{consume_on_fire:true,persistent_until_consumed:true,consume_weapon_group_id:"gnevny_torpedo"}),effect("Self","WeaponSpread","PercentAdd",-.2,"Torpedo","gnevny_skill",{consume_on_fire:true,persistent_until_consumed:true,consume_weapon_group_id:"gnevny_torpedo"})],{description:"快速突进并发射密集鱼雷。",ai_tags:["Burst","Torpedo","Mobility"]}),
  skill("skill.prinz_precision_evasion","精密规避",34,"Self",0,8,[effect("Self","Evasion","FlatAdd",35,"All","prinz_skill"),effect("Self","AccuracyPoint","FlatAdd",.12,"Gun","prinz_skill",{consume_on_fire:true,persistent_until_consumed:true,consume_weapon_group_id:"prinz_main"})],{description:"进行规避机动并强化下一轮炮击。",ai_tags:["Defense","Burst"]}),
  skill("skill.u47_silent_ambush","静默伏击",36,"Self",0,12,[effect("Self","ConcealmentDistance","StateMultiply",.75,"All","u47_skill",{requires_submerged:true}),effect("Self","Damage","PercentAdd",.18,"Torpedo","u47_skill",{consume_on_fire:true,persistent_until_consumed:true,consume_weapon_group_id:"u47_torpedo"}),effect("Self","OxygenConsumptionRate","PercentAdd",.3,"All","u47_skill")],{description:"降低暴露并准备伏击鱼雷。",ai_tags:["Concealment","Burst","Torpedo"]}),
  skill("skill.yamato_full_salvo","主炮全开",55,"Area",790,2,[],{effect_radius:70,description:"超重型主炮齐射，压制远距离目标。",ai_tags:["Burst","AreaAttack"],triggered_attacks:[{weapon_id:"weapon.yamato_460_ap",shots_per_wave:9,charge_time:2,firing_reveal_multiplier:1.25,modifiers:[effect("Self","Damage","PercentAdd",.25,"Gun","yamato_skill"),effect("Self","WeaponSpread","PercentAdd",.1,"Gun","yamato_skill")]}]}),
  skill("skill.yukikaze_lucky_evasion","幸运回避",34,"Self",0,10,[effect("Self","Evasion","FlatAdd",45,"All","yukikaze_skill"),effect("Self","ProjectileSpeed","PercentAdd",.12,"Torpedo","yukikaze_skill"),effect("AlliesInArea","ReloadSpeed","PercentAdd",.11,"All","yukikaze_aura",{duration:6})],{base_effect_radius:360,effect_radius:540,description:"提升自身闪避，并在规避窗口加快附近友军装填。",ai_tags:["Defense","AreaSupport"]}),
  skill("skill.hosho_light_training","轻型空袭训练",34,"Area",660,10,[],{effect_radius:440,description:"派出小规模训练航空队。",ai_tags:["AreaAttack","Aviation","Recon"],triggered_attacks:[{weapon_id:"weapon.hosho_airstrike",shots_per_wave:4,modifiers:[effect("Self","Damage","PercentAdd",.15,"Aviation","hosho_skill"),effect("Self","AircraftHP","PercentAdd",-.1,"Aviation","hosho_skill")]}],recon_zones:[{radius:440,duration:10,aircraft_hp:315}]}),
  skill("skill.ning_coastal_escort","近海护卫",36,"Self",0,12,[effect("AlliesInArea","Damage","PercentAdd",.25,"AntiAir","ning_skill"),effect("AlliesInArea","Armor","FlatAdd",8,"All","ning_skill"),effect("AlliesInArea","ReloadSpeed","PercentAdd",.14,"Gun","ning_skill")],{base_effect_radius:300,effect_radius:450,description:"强化近海防卫和中近程火力。",ai_tags:["Defense","AreaSupport"]}),
  skill("skill.anshan_escort_alert","护航警戒",34,"Self",0,12,[effect("Self","DetectionRange","FlatAdd",80,"All","anshan_skill"),effect("Self","TorpedoDetectionDistance","FlatAdd",90,"Torpedo","anshan_skill"),effect("AlliesInArea","Evasion","FlatAdd",10,"All","anshan_aura")],{base_effect_radius:520,effect_radius:780,description:"展开早期驱逐护航警戒，提高侦查和鱼雷预警。",ai_tags:["Recon","TorpedoWarning","Defense","AreaSupport"]}),
  skill("skill.chongqing_turning_support","转折支援",40,"Self",0,12,[effect("AlliesInArea","AccuracyPoint","FlatAdd",.08,"Gun","chongqing_skill"),effect("AlliesInArea","ReloadSpeed","PercentAdd",.18,"AntiAir","chongqing_skill"),effect("AlliesInArea","ZeroDamageReloadProc","FlatAdd",.09,"All","chongqing_skill",{proc_duration:3})],{base_effect_radius:420,effect_radius:630,description:"提供近海支援范围光，提升友军持续作战。",ai_tags:["Defense","AreaSupport"]}),
];

output("data/weapons/expanded_roster_weapons.json", weapons);
output("data/skills/expanded_roster_skills.json", skills);
