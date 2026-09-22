# dingyuan Codex native-alpha production brief — 2026-09-20

Route: Codex built-in ImageGen, transparent PNG requested. Model/request ID account managed and not exposed. Follow docs/46; legacy API paragraph superseded for this run.

## Shared prompt core

2D anime shipgirl tactical naval game asset for TinySeaWar. Original design; do not imitate any existing shipgirl franchise.
Character origin: 定远号 Dingyuan.
Faction: 中系. MVP ship class: 战列. Level: 3 级.
Personality: 威严旗舰（沉着中坚）. Combat role: 前无畏铁甲承伤.
Core visual direction: 黛青、象牙白与旧铜金的北洋海军色彩转译，厚重礼服不使用现代军帽；宽短铁甲底座、两座双联露炮台和低矮烟囱形成前无畏旗舰轮廓，明确无雷达与现代防空.
Required MVP asset focus: 全身/半身立绘、高规格技能 cut-in、宽短铁甲底座、双联露炮台、单装副炮、装甲/烟囱节点、无现代防空验收图、煤烟重航迹、铁甲中坚与低速齐射动画.
Expected object inventory from the authoritative postprocess plan: {"turret_main": {"instances": 2}, "turret_secondary": {"instances": 2}}.
No real flags, no political symbols, no readable insignia text, no historical extremist symbols.
Clean readable silhouette, clear ship-class identity, high-quality anime linework, restrained cel shading, consistent face and hair. Character body, rig base, weapons and effect origins must remain visually separable.

## Style anchor

2D anime shipgirl tactical naval game asset for TinySeaWar. Original design; do not imitate any existing shipgirl franchise.
Character origin: 定远号 Dingyuan.
Faction: 中系. MVP ship class: 战列. Level: 3 级.
Personality: 威严旗舰（沉着中坚）. Combat role: 前无畏铁甲承伤.
Core visual direction: 黛青、象牙白与旧铜金的北洋海军色彩转译，厚重礼服不使用现代军帽；宽短铁甲底座、两座双联露炮台和低矮烟囱形成前无畏旗舰轮廓，明确无雷达与现代防空.
Required MVP asset focus: 全身/半身立绘、高规格技能 cut-in、宽短铁甲底座、双联露炮台、单装副炮、装甲/烟囱节点、无现代防空验收图、煤烟重航迹、铁甲中坚与低速齐射动画.
Expected object inventory from the authoritative postprocess plan: {"turret_main": {"instances": 2}, "turret_secondary": {"instances": 2}}.
No real flags, no political symbols, no readable insignia text, no historical extremist symbols.
Clean readable silhouette, clear ship-class identity, high-quality anime linework, restrained cel shading, consistent face and hair. Character body, rig base, weapons and effect origins must remain visually separable.
Create the definitive full-body style anchor concept on a transparent background. Front three-quarter standing pose, complete outfit and ship rigging visible, generous empty transparent margin, no environment, no ocean, no UI, no text. Show the body, rig base, weapon identity and core accessory clearly; the accepted anchor will be the sole identity reference for all derivative sheets.

## UI 4x2 sheet

Use the accepted style anchor as the only identity reference. Create exactly eight separated cells in a 4x2 grid: portrait, small portrait, chibi head, default expression, serious expression, hit expression, skill icon for `ironclad_anchor`, and abstract `battleship` class icon. True transparent background, no checkerboard, no matte, no text, no overlapping cells.

## Battle 4x2 sheet

Use the accepted style anchor as the only identity reference. Create exactly eight isolated orthographic game assets in a 4x2 grid, in this order: battle_body_r, battle_rig_base, battle_turret_main_01, battle_turret_secondary_01, battle_armor_plate, battle_smokestack_node, battle_flagship_marker, battle_wake_origin_marker. True transparent background, no checkerboard or matte. Keep every component separated with clear empty transparent margins and readable pivots.

## Animation 2x2 state sheets

Use the accepted style anchor as the only identity reference. Create five separate chibi / SD battlefield-unit animation sheets, not full-body illustrations, portraits, half-body art, or skill cut-ins. Required files/states: idle, move, attack, hit, firepower. Each state is one 2-row by 2-column sheet ordered top-left, top-right, bottom-left, bottom-right as anticipation/start, action, feedback/recoil, recovery. Use an invisible logical grid: wide empty transparent gutters, no visible borders, no labels, no text. Every cell must contain the complete compact Q-version battle sprite matching the `battle_body_r` style: large readable head, small body, attached rigging and weapon nodes, clear small-scale silhouette, and at least 12% empty transparent margin on all sides. Identical face, hair, outfit, rigging, camera, scale, Q-version proportions, and equipment count in all four cells of each sheet. Animate only the chibi character body, attached rigging, weapon recoil, local muzzle flash/fire light, tiny local smoke/spark, local wake, local scan/aura cues, and pose changes. The four cells must be hand-drawn/generated as distinct key poses; do not duplicate the same character image with only translation, scale, tint, tiny rotation, aura, or external flash changes. Do not draw separate launched projectiles or detached attack objects: no flying shells, no bullets, no tracer streams, no torpedoes, no missiles, no aircraft, no detached depth charges, no large water impacts, no long projectile trails. True transparent background, no checkerboard or matte, no connected effects between cells.

## VFX 2x4 sheet

Create exactly eight isolated character-specific VFX overlays in a 2x4 grid, in this order: ironclad_guard_aura, coal_smoke_wake, broadside_smoke, shell_trail_heavy, armor_sparks, command_aura, water_splash_large, fire_control_lock. Reusable projectile bodies and impacts are not duplicated. True transparent background, no checkerboard or matte, no text, crisp small-scale game VFX shapes.

## Acceptance rules

- Original TinySeaWar design; no real flags, political symbols, readable insignia, or extremist symbols.
- Character body, rig base, weapon nodes, and VFX must remain visually separable.
- Pre-dreadnought ironclad silhouette; no radar or modern anti-aircraft equipment.

## Actual production refinement — 2026-09-20
Animation requests use BODY LAYER ONLY, no hull/weapons/projectiles/VFX, preserving identity from accepted idle chibi sheet for move/attack/hit/firepower. Precise ship machinery stays in independent battle components. Every state has four distinct key poses; source order TL/TR/BL/BR. This replaces the attached-rig wording above for this run. References: concept for UI/battle/idle, idle for the other four animation states. VFX independently generated from the eight role inventory. Review records and crop specs are separate hash-bound files.
