# K-21 Phase 2 Generation Brief

## Shared prompt core

2D anime shipgirl tactical naval game asset for TinySeaWar. Original design; do not imitate any existing shipgirl franchise.
Character origin: K-21.
Faction: 苏系. MVP ship class: 潜艇. Level: 2 级.
Personality: 神秘潜行（冷峻巡猎）. Combat role: 远洋侦查伏击.
Core visual direction: 极地灰潜航服、毛领与低亮冰蓝镜片；长航艇身、六艏四艉鱼雷口、远洋天线和较大声呐件形成耐寒远洋轮廓.
Required MVP asset focus: 全身/半身立绘、技能 cut-in、长航潜艇底座、艏/艉鱼雷口、远洋天线、声呐/扫描点、冰白追踪圈、慢速长程鱼雷和极地侦查动画.
No real flags, no political symbols, no readable insignia text, no historical extremist symbols.
Clean readable silhouette, clear ship-class identity, high-quality anime linework, restrained cel shading, consistent face and hair. Character body, rig base, weapons and effect origins must remain visually separable.

## Style anchor

2D anime shipgirl tactical naval game asset for TinySeaWar. Original design; do not imitate any existing shipgirl franchise.
Character origin: K-21.
Faction: 苏系. MVP ship class: 潜艇. Level: 2 级.
Personality: 神秘潜行（冷峻巡猎）. Combat role: 远洋侦查伏击.
Core visual direction: 极地灰潜航服、毛领与低亮冰蓝镜片；长航艇身、六艏四艉鱼雷口、远洋天线和较大声呐件形成耐寒远洋轮廓.
Required MVP asset focus: 全身/半身立绘、技能 cut-in、长航潜艇底座、艏/艉鱼雷口、远洋天线、声呐/扫描点、冰白追踪圈、慢速长程鱼雷和极地侦查动画.
No real flags, no political symbols, no readable insignia text, no historical extremist symbols.
Clean readable silhouette, clear ship-class identity, high-quality anime linework, restrained cel shading, consistent face and hair. Character body, rig base, weapons and effect origins must remain visually separable.
Create the definitive full-body style anchor concept on a transparent background. Front three-quarter standing pose, complete outfit and ship rigging visible, generous empty transparent margin, no environment, no ocean, no UI, no text. Show the body, rig base, weapon identity and core accessory clearly; the accepted anchor will be the sole identity reference for all derivative sheets.

## UI 4x2 sheet

Use the accepted style anchor as the only identity reference. Create exactly eight separated cells in a 4x2 grid: portrait, small portrait, chibi head, default expression, serious expression, hit expression, skill icon for `polar_tracking`, and abstract `submarine` class icon. Flat reserved green background, no text, no overlapping cells.

## Battle 4x2 sheet

Use the accepted style anchor as the only identity reference. Create exactly eight isolated orthographic game assets in a 4x2 grid, in this order: battle_body_r, battle_rig_base, battle_torpedo_tube_fore, battle_torpedo_tube_aft, battle_sonar_node, battle_periscope_node, battle_long_range_antenna, battle_submerged_shadow. Flat reserved green background. Keep every component separated with clear empty margins and readable pivots.

## Animation 2x2 state sheets

Use the accepted style anchor as the only identity reference. Create five separate chibi / SD battlefield-unit animation sheets, not full-body illustrations, portraits, half-body art, or skill cut-ins. Required files/states: idle, move, attack, hit, firepower. Each state is one 2-row by 2-column sheet ordered top-left, top-right, bottom-left, bottom-right as anticipation/start, action, feedback/recoil, recovery. Use an invisible logical grid: wide empty gutters, no visible borders, no labels, no text. Every cell must contain the complete compact Q-version battle sprite matching the `battle_body_r` style: large readable head, small body, attached rigging and weapon nodes, clear small-scale silhouette, and at least 12% empty reserved-green margin on all sides. Identical face, hair, outfit, rigging, camera, scale, Q-version proportions, and equipment count in all four cells of each sheet. Animate only the chibi character body, attached rigging, weapon recoil, local muzzle flash/fire light, tiny local smoke/spark, local wake, local scan/aura cues, and pose changes. The four cells must be hand-drawn/generated as distinct key poses; do not duplicate the same character image with only translation, scale, tint, tiny rotation, aura, or external flash changes. Do not draw separate launched projectiles or detached attack objects: no flying shells, no bullets, no tracer streams, no torpedoes, no missiles, no aircraft, no detached depth charges, no large water impacts, no long projectile trails. Flat reserved green background, no connected effects between cells.

## VFX 2x4 sheet

Create exactly eight isolated character-specific VFX overlays in a 2x4 grid, in this order: polar_tracking_ring, ice_torpedo_trail, sonar_pulse, torpedo_launch_flash, torpedo_trail, underwater_shadow, dive_ripple, skill_aura. Reusable projectile bodies and impacts are not duplicated. Flat reserved green background, no text, crisp small-scale game VFX shapes.

## Acceptance rules

- Original TinySeaWar design; no real flags, political symbols, readable insignia, or extremist symbols.
- Character body, rig base, weapon nodes, and VFX must remain visually separable.
- Submarine character must wear fitted waterproof or tactical boots; no swim fins on feet.
