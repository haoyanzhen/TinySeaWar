# 长春号 PLAN Chang Chun Phase 2 Generation Brief

## Generation API contract

- Primary route: OpenAI Images API with `gpt-image-2.5-sunburst` or `gpt-image-2.5-flare`.
- Every isolated source request must set API-level `background: "transparent"` and `output_format: "png"`.
- Prompt prose is not a substitute for those API controls. An RGB checkerboard, white/black matte, or opaque RGBA file fails the source gate.
- The legacy chroma-key route is disabled by default. It may run only after native-alpha attempts fail and an operator explicitly supplies `--allow-legacy-chroma-fallback` with a recorded reason.

## Shared prompt core

2D anime shipgirl tactical naval game asset for TinySeaWar. Original design; do not imitate any existing shipgirl franchise.
Character origin: 长春号 PLAN Chang Chun.
Faction: 中系. MVP ship class: 驱逐. Level: 2 级.
Personality: 可靠护卫（稳健前卫）. Combat role: 接收初期炮击护航.
Core visual direction: 青蓝短披风叠加苏式直线剪裁，朱红仅作小面积识别；四座单装 130mm 炮、两座三联鱼雷管和早期雷达灯构成紧凑炮雷轮廓，禁止任何导弹发射架.
Required MVP asset focus: 全身/半身立绘、技能 cut-in、四座单炮、双三联鱼雷管、早期雷达/防空点、无导弹轮廓验收图、前出护航航迹和持续炮击动画.
Expected object inventory from the authoritative postprocess plan: {"torpedo": {"instances": 2}, "turret_main": {"instances": 4}}.
No real flags, no political symbols, no readable insignia text, no historical extremist symbols.
Clean readable silhouette, clear ship-class identity, high-quality anime linework, restrained cel shading, consistent face and hair. Character body, rig base, weapons and effect origins must remain visually separable.

## Style anchor

2D anime shipgirl tactical naval game asset for TinySeaWar. Original design; do not imitate any existing shipgirl franchise.
Character origin: 长春号 PLAN Chang Chun.
Faction: 中系. MVP ship class: 驱逐. Level: 2 级.
Personality: 可靠护卫（稳健前卫）. Combat role: 接收初期炮击护航.
Core visual direction: 青蓝短披风叠加苏式直线剪裁，朱红仅作小面积识别；四座单装 130mm 炮、两座三联鱼雷管和早期雷达灯构成紧凑炮雷轮廓，禁止任何导弹发射架.
Required MVP asset focus: 全身/半身立绘、技能 cut-in、四座单炮、双三联鱼雷管、早期雷达/防空点、无导弹轮廓验收图、前出护航航迹和持续炮击动画.
Expected object inventory from the authoritative postprocess plan: {"torpedo": {"instances": 2}, "turret_main": {"instances": 4}}.
No real flags, no political symbols, no readable insignia text, no historical extremist symbols.
Clean readable silhouette, clear ship-class identity, high-quality anime linework, restrained cel shading, consistent face and hair. Character body, rig base, weapons and effect origins must remain visually separable.
Create the definitive full-body style anchor concept on a transparent background. Front three-quarter standing pose, complete outfit and ship rigging visible, generous empty transparent margin, no environment, no ocean, no UI, no text. Show the body, rig base, weapon identity and core accessory clearly; the accepted anchor will be the sole identity reference for all derivative sheets.

## UI 4x2 sheet

Use the accepted style anchor as the only identity reference. Create exactly eight separated cells in a 4x2 grid: portrait, small portrait, chibi head, default expression, serious expression, hit expression, skill icon for `forward_escort`, and abstract `destroyer` class icon. True transparent background, no checkerboard, no matte, no text, no overlapping cells.

## Battle 4x2 sheet

Use the accepted style anchor as the only identity reference. Create exactly eight isolated orthographic game assets in a 4x2 grid, in this order: battle_body_r, battle_rig_base, battle_turret_main_01, battle_torpedo_tube_01, battle_aa_center, battle_radar_node, battle_support_node, battle_wake_origin_marker. True transparent background, no checkerboard or matte. Keep every component separated with clear empty transparent margins and readable pivots.

## Animation 2x2 state sheets

Use the accepted style anchor as the only identity reference. Create five separate chibi / SD battlefield-unit animation sheets, not full-body illustrations, portraits, half-body art, or skill cut-ins. Required files/states: idle, move, attack, hit, firepower. Each state is one 2-row by 2-column sheet ordered top-left, top-right, bottom-left, bottom-right as anticipation/start, action, feedback/recoil, recovery. Use an invisible logical grid: wide empty transparent gutters, no visible borders, no labels, no text. Every cell must contain the complete compact Q-version battle sprite matching the `battle_body_r` style: large readable head, small body, attached rigging and weapon nodes, clear small-scale silhouette, and at least 12% empty transparent margin on all sides. Identical face, hair, outfit, rigging, camera, scale, Q-version proportions, and equipment count in all four cells of each sheet. Animate only the chibi character body, attached rigging, weapon recoil, local muzzle flash/fire light, tiny local smoke/spark, local wake, local scan/aura cues, and pose changes. The four cells must be hand-drawn/generated as distinct key poses; do not duplicate the same character image with only translation, scale, tint, tiny rotation, aura, or external flash changes. Do not draw separate launched projectiles or detached attack objects: no flying shells, no bullets, no tracer streams, no torpedoes, no missiles, no aircraft, no detached depth charges, no large water impacts, no long projectile trails. True transparent background, no checkerboard or matte, no connected effects between cells.

## VFX 2x4 sheet

Create exactly eight isolated character-specific VFX overlays in a 2x4 grid, in this order: forward_escort_wake, early_radar_scan, torpedo_launch_flash, muzzle_flash_small, water_splash, aa_circle, skill_aura, range_reticle. Reusable projectile bodies and impacts are not duplicated. True transparent background, no checkerboard or matte, no text, crisp small-scale game VFX shapes.

## Acceptance rules

- Original TinySeaWar design; no real flags, political symbols, readable insignia, or extremist symbols.
- Character body, rig base, weapon nodes, and VFX must remain visually separable.
- Early gun-and-torpedo configuration only; no missile launcher.
