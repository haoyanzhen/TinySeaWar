# 纽伦堡号 Nürnberg Phase 2 Generation Brief

## Shared prompt core

2D anime shipgirl tactical naval game asset for TinySeaWar. Original design; do not imitate any existing shipgirl franchise.
Character origin: 纽伦堡号 Nürnberg.
Faction: 德系. MVP ship class: 轻巡. Level: 1 级.
Personality: 傲慢精英（灵活技师）. Combat role: 艉向火力与规避.
Core visual direction: 银灰修身短外套与机械裙甲；三座三联炮中两座明显后置，四组三联鱼雷管形成宽侧舷，转向刻度和弧形尾流强调边撤边打，边框和特效保持轻量.
Required MVP asset focus: 全身/半身立绘、技能 cut-in、前一后二三联炮组、四组鱼雷节点、防空中心、转向刻度环、弧形尾流、艉向规避射击动画.
No real flags, no political symbols, no readable insignia text, no historical extremist symbols.
Clean readable silhouette, clear ship-class identity, high-quality anime linework, restrained cel shading, consistent face and hair. Character body, rig base, weapons and effect origins must remain visually separable.

## Style anchor

2D anime shipgirl tactical naval game asset for TinySeaWar. Original design; do not imitate any existing shipgirl franchise.
Character origin: 纽伦堡号 Nürnberg.
Faction: 德系. MVP ship class: 轻巡. Level: 1 级.
Personality: 傲慢精英（灵活技师）. Combat role: 艉向火力与规避.
Core visual direction: 银灰修身短外套与机械裙甲；三座三联炮中两座明显后置，四组三联鱼雷管形成宽侧舷，转向刻度和弧形尾流强调边撤边打，边框和特效保持轻量.
Required MVP asset focus: 全身/半身立绘、技能 cut-in、前一后二三联炮组、四组鱼雷节点、防空中心、转向刻度环、弧形尾流、艉向规避射击动画.
No real flags, no political symbols, no readable insignia text, no historical extremist symbols.
Clean readable silhouette, clear ship-class identity, high-quality anime linework, restrained cel shading, consistent face and hair. Character body, rig base, weapons and effect origins must remain visually separable.
Create the definitive full-body style anchor concept on a transparent background. Front three-quarter standing pose, complete outfit and ship rigging visible, generous empty transparent margin, no environment, no ocean, no UI, no text. Show the body, rig base, weapon identity and core accessory clearly; the accepted anchor will be the sole identity reference for all derivative sheets.

## UI 4x2 sheet

Use the accepted style anchor as the only identity reference. Create exactly eight separated cells in a 4x2 grid: portrait, small portrait, chibi head, default expression, serious expression, hit expression, skill icon for `stern_evasion_fire`, and abstract `light_cruiser` class icon. Flat reserved green background, no text, no overlapping cells.

## Battle 4x2 sheet

Use the accepted style anchor as the only identity reference. Create exactly eight isolated orthographic game assets in a 4x2 grid, in this order: battle_body_r, battle_rig_base, battle_turret_main_01, battle_turret_main_02, battle_torpedo_tube_01, battle_aa_center, battle_turn_indicator, battle_wake_origin_marker. Flat reserved green background. Keep every component separated with clear empty margins and readable pivots.

## Animation 5x4 master

Use the accepted style anchor as the only identity reference. Create a chibi / SD battlefield-unit animation master, not a full-body illustration, portrait, half-body, or skill cut-in. The character must use compact Q-version battle-sprite proportions matching the `battle_body_r` style: large readable head, small body, attached rigging and weapon nodes, clear small-scale silhouette. Create a 5-row by 4-column animation master. Rows in order: idle, move, attack, hit, firepower. Each row has anticipation/start, action, feedback/recoil, recovery. Identical face, hair, outfit, rigging, camera, scale, Q-version proportions, and equipment count in all twenty cells. Animate only the chibi character body, attached rigging, weapon recoil, local muzzle flash/fire light, tiny local smoke/spark, local wake, local scan/aura cues, and pose changes. Do not draw separate launched projectiles or detached attack objects: no flying shells, no bullets, no tracer streams, no torpedoes, no missiles, no aircraft, no detached depth charges, no large water impacts, no long projectile trails. Flat reserved green background, no labels, no connected effects between cells.

## VFX 2x4 sheet

Create exactly eight isolated character-specific VFX overlays in a 2x4 grid, in this order: turn_scale_ring, curved_stern_wake, shell_trail, aa_burst, aa_circle, radar_scan, skill_aura, water_splash. Reusable projectile bodies and impacts are not duplicated. Flat reserved green background, no text, crisp small-scale game VFX shapes.

## Acceptance rules

- Original TinySeaWar design; no real flags, political symbols, readable insignia, or extremist symbols.
- Character body, rig base, weapon nodes, and VFX must remain visually separable.
