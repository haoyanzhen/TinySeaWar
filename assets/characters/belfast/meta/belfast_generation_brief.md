# 贝尔法斯特号 HMS Belfast Phase 2 Generation Brief

## Shared prompt core

2D anime shipgirl tactical naval game asset for TinySeaWar. Original design; do not imitate any existing shipgirl franchise.
Character origin: 贝尔法斯特号 HMS Belfast.
Faction: 英系. MVP ship class: 轻巡. Level: 2 级.
Personality: 冷静指挥（机敏参谋）. Combat role: 雷达控制与炮击支援.
Core visual direction: 城市灰蓝礼装与象牙白领口；四座三联炮形成稳定中型轮廓，雷达屏、测距仪和三联鱼雷管分层布置；柔和绿白扫描扇区区别于敌方危险区.
Required MVP asset focus: 全身/半身立绘、技能 cut-in、四座三联炮、鱼雷管、防空中心、雷达/测距节点、区域扫描扇区、雷达压制和支援炮击动画.
No real flags, no political symbols, no readable insignia text, no historical extremist symbols.
Clean readable silhouette, clear ship-class identity, high-quality anime linework, restrained cel shading, consistent face and hair. Character body, rig base, weapons and effect origins must remain visually separable.

## Style anchor

2D anime shipgirl tactical naval game asset for TinySeaWar. Original design; do not imitate any existing shipgirl franchise.
Character origin: 贝尔法斯特号 HMS Belfast.
Faction: 英系. MVP ship class: 轻巡. Level: 2 级.
Personality: 冷静指挥（机敏参谋）. Combat role: 雷达控制与炮击支援.
Core visual direction: 城市灰蓝礼装与象牙白领口；四座三联炮形成稳定中型轮廓，雷达屏、测距仪和三联鱼雷管分层布置；柔和绿白扫描扇区区别于敌方危险区.
Required MVP asset focus: 全身/半身立绘、技能 cut-in、四座三联炮、鱼雷管、防空中心、雷达/测距节点、区域扫描扇区、雷达压制和支援炮击动画.
No real flags, no political symbols, no readable insignia text, no historical extremist symbols.
Clean readable silhouette, clear ship-class identity, high-quality anime linework, restrained cel shading, consistent face and hair. Character body, rig base, weapons and effect origins must remain visually separable.
Create the definitive full-body style anchor concept on a transparent background. Front three-quarter standing pose, complete outfit and ship rigging visible, generous empty transparent margin, no environment, no ocean, no UI, no text. Show the body, rig base, weapon identity and core accessory clearly; the accepted anchor will be the sole identity reference for all derivative sheets.

## UI 4x2 sheet

Use the accepted style anchor as the only identity reference. Create exactly eight separated cells in a 4x2 grid: portrait, small portrait, chibi head, default expression, serious expression, hit expression, skill icon for `radar_suppression`, and abstract `light_cruiser` class icon. Flat reserved green background, no text, no overlapping cells.

## Battle 4x2 sheet

Use the accepted style anchor as the only identity reference. Create exactly eight isolated orthographic game assets in a 4x2 grid, in this order: battle_body_r, battle_rig_base, battle_turret_main_01, battle_torpedo_tube_01, battle_aa_center, battle_radar_node, battle_rangefinder_node, battle_wake_origin_marker. Flat reserved green background. Keep every component separated with clear empty margins and readable pivots.

## Animation 2x2 state sheets

Use the accepted style anchor as the only identity reference. Create five separate chibi / SD battlefield-unit animation sheets, not full-body illustrations, portraits, half-body art, or skill cut-ins. Required files/states: idle, move, attack, hit, firepower. Each state is one 2-row by 2-column sheet ordered top-left, top-right, bottom-left, bottom-right as anticipation/start, action, feedback/recoil, recovery. Use an invisible logical grid: wide empty gutters, no visible borders, no labels, no text. Every cell must contain the complete compact Q-version battle sprite matching the `battle_body_r` style: large readable head, small body, attached rigging and weapon nodes, clear small-scale silhouette, and at least 12% empty reserved-green margin on all sides. Identical face, hair, outfit, rigging, camera, scale, Q-version proportions, and equipment count in all four cells of each sheet. Animate only the chibi character body, attached rigging, weapon recoil, local muzzle flash/fire light, tiny local smoke/spark, local wake, local scan/aura cues, and pose changes. The four cells must be hand-drawn/generated as distinct key poses; do not duplicate the same character image with only translation, scale, tint, tiny rotation, aura, or external flash changes. Do not draw separate launched projectiles or detached attack objects: no flying shells, no bullets, no tracer streams, no torpedoes, no missiles, no aircraft, no detached depth charges, no large water impacts, no long projectile trails. Flat reserved green background, no connected effects between cells.

## VFX 2x4 sheet

Create exactly eight isolated character-specific VFX overlays in a 2x4 grid, in this order: radar_suppression_sector, support_salvo, shell_trail, aa_burst, aa_circle, radar_scan, skill_aura, water_splash. Reusable projectile bodies and impacts are not duplicated. Flat reserved green background, no text, crisp small-scale game VFX shapes.

## Acceptance rules

- Original TinySeaWar design; no real flags, political symbols, readable insignia, or extremist symbols.
- Character body, rig base, weapon nodes, and VFX must remain visually separable.
