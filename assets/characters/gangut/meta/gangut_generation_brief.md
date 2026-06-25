# 甘古特号 Gangut Phase 2 Generation Brief

## Shared prompt core

2D anime shipgirl tactical naval game asset for TinySeaWar. Original design; do not imitate any existing shipgirl franchise.
Character origin: 甘古特号 Gangut.
Faction: 苏系. MVP ship class: 战列. Level: 1 级.
Personality: 威严旗舰（坚韧老兵）. Combat role: 低速持续齐射.
Core visual direction: 深红旧式军大衣、磨损金属和补丁式护甲；低矮超长底座承载四座三联主炮，现代化构件以附加层出现，使用老式基础边框表现“低等级资本舰”特例.
Required MVP asset focus: 全身/半身立绘、技能 cut-in、低矮长舰装、四座三联主炮、副炮节点、旧钢板/改装层、宽重航迹、钢铁阵线展开与持续舷侧齐射动画.
No real flags, no political symbols, no readable insignia text, no historical extremist symbols.
Clean readable silhouette, clear ship-class identity, high-quality anime linework, restrained cel shading, consistent face and hair. Character body, rig base, weapons and effect origins must remain visually separable.

## Style anchor

2D anime shipgirl tactical naval game asset for TinySeaWar. Original design; do not imitate any existing shipgirl franchise.
Character origin: 甘古特号 Gangut.
Faction: 苏系. MVP ship class: 战列. Level: 1 级.
Personality: 威严旗舰（坚韧老兵）. Combat role: 低速持续齐射.
Core visual direction: 深红旧式军大衣、磨损金属和补丁式护甲；低矮超长底座承载四座三联主炮，现代化构件以附加层出现，使用老式基础边框表现“低等级资本舰”特例.
Required MVP asset focus: 全身/半身立绘、技能 cut-in、低矮长舰装、四座三联主炮、副炮节点、旧钢板/改装层、宽重航迹、钢铁阵线展开与持续舷侧齐射动画.
No real flags, no political symbols, no readable insignia text, no historical extremist symbols.
Clean readable silhouette, clear ship-class identity, high-quality anime linework, restrained cel shading, consistent face and hair. Character body, rig base, weapons and effect origins must remain visually separable.
Create the definitive full-body style anchor concept on a transparent background. Front three-quarter standing pose, complete outfit and ship rigging visible, generous empty transparent margin, no environment, no ocean, no UI, no text. Show the body, rig base, weapon identity and core accessory clearly; the accepted anchor will be the sole identity reference for all derivative sheets.

## UI 4x2 sheet

Use the accepted style anchor as the only identity reference. Create exactly eight separated cells in a 4x2 grid: portrait, small portrait, chibi head, default expression, serious expression, hit expression, skill icon for `steel_line`, and abstract `battleship` class icon. Flat reserved green background, no text, no overlapping cells.

## Battle 4x2 sheet

Use the accepted style anchor as the only identity reference. Create exactly eight isolated orthographic game assets in a 4x2 grid, in this order: battle_body_r, battle_rig_base, battle_turret_main_01, battle_turret_secondary_01, battle_armor_plate, battle_smokestack_node, battle_fire_control_node, battle_wake_origin_marker. Flat reserved green background. Keep every component separated with clear empty margins and readable pivots.

## Animation 5x4 master

Use the accepted style anchor as the only identity reference. Create a chibi / SD battlefield-unit animation master, not a full-body illustration, portrait, half-body, or skill cut-in. The character must use compact Q-version battle-sprite proportions matching the `battle_body_r` style: large readable head, small body, attached rigging and weapon nodes, clear small-scale silhouette. Create a 5-row by 4-column animation master. Rows in order: idle, move, attack, hit, firepower. Each row has anticipation/start, action, feedback/recoil, recovery. Identical face, hair, outfit, rigging, camera, scale, Q-version proportions, and equipment count in all twenty cells. Animate only the chibi character body, attached rigging, weapon recoil, local muzzle flash/fire light, tiny local smoke/spark, local wake, local scan/aura cues, and pose changes. Do not draw separate launched projectiles or detached attack objects: no flying shells, no bullets, no tracer streams, no torpedoes, no missiles, no aircraft, no detached depth charges, no large water impacts, no long projectile trails. Flat reserved green background, no labels, no connected effects between cells.

## VFX 2x4 sheet

Create exactly eight isolated character-specific VFX overlays in a 2x4 grid, in this order: steel_line_aura, coal_smoke_wake, broadside_smoke, shell_trail_heavy, armor_sparks, command_aura, water_splash_large, fire_control_lock. Reusable projectile bodies and impacts are not duplicated. Flat reserved green background, no text, crisp small-scale game VFX shapes.

## Acceptance rules

- Original TinySeaWar design; no real flags, political symbols, readable insignia, or extremist symbols.
- Character body, rig base, weapon nodes, and VFX must remain visually separable.
