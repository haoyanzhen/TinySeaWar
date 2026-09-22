# 齐柏林伯爵号 Graf Zeppelin Phase 2 Generation Brief

## Generation route contract

- Primary route: Codex account built-in ImageGen; it does not require a project SDK or user-supplied API key.
- Ask the built-in generator for a transparent PNG (`background: "transparent"` as the generation intent), preserve its accepted output byte-for-byte, and verify the actual PNG Alpha channel and transparent canvas/border pixels before postprocessing.
- Codex-managed model and request identifiers must be recorded honestly as managed/not exposed; they are not replaced with invented Images API model names, endpoints, or request IDs.
- The direct Images API helper remains an explicit fallback for non-Codex batch environments. The legacy chroma-key route remains disabled by default and requires a recorded native-alpha failure reason.

## Shared prompt core

2D anime shipgirl tactical naval game asset for TinySeaWar. Original design; do not imitate any existing shipgirl franchise.
Character origin: 齐柏林伯爵号 Graf Zeppelin.
Faction: 德系. MVP ship class: 航母. Level: 2 级.
Personality: 傲慢精英（试验主义）. Combat role: 假想航空与舰炮自卫.
Core visual direction: 黑铁试验飞行服、未封闭装甲接缝和可拆设计板；横向甲板保留未完成结构线，舷侧 150mm 炮与试验飞行灯并列；“方案”只在 UI 标注层表达.
Required MVP asset focus: 全身/半身立绘、技能 cut-in、未完成甲板/机库、舰载机小图、起飞/回收点、重型舷炮和防空节点、方案标注 UI 层、试验编队出击与舰炮自卫动画.
Expected object inventory from the authoritative postprocess plan: {"aircraft_launch": {"instances": 1}, "aircraft_recovery": {"instances": 1}, "turret_secondary": {"barrels_per_instance": 2, "instances": 8, "layout": "four_per_side"}}.
No real flags, no political symbols, no readable insignia text, no historical extremist symbols.
Clean readable silhouette, clear ship-class identity, high-quality anime linework, restrained cel shading, consistent face and hair. Character body, rig base, weapons and effect origins must remain visually separable.

## Style anchor

2D anime shipgirl tactical naval game asset for TinySeaWar. Original design; do not imitate any existing shipgirl franchise.
Character origin: 齐柏林伯爵号 Graf Zeppelin.
Faction: 德系. MVP ship class: 航母. Level: 2 级.
Personality: 傲慢精英（试验主义）. Combat role: 假想航空与舰炮自卫.
Core visual direction: 黑铁试验飞行服、未封闭装甲接缝和可拆设计板；横向甲板保留未完成结构线，舷侧 150mm 炮与试验飞行灯并列；“方案”只在 UI 标注层表达.
Required MVP asset focus: 全身/半身立绘、技能 cut-in、未完成甲板/机库、舰载机小图、起飞/回收点、重型舷炮和防空节点、方案标注 UI 层、试验编队出击与舰炮自卫动画.
Expected object inventory from the authoritative postprocess plan: {"aircraft_launch": {"instances": 1}, "aircraft_recovery": {"instances": 1}, "turret_secondary": {"barrels_per_instance": 2, "instances": 8, "layout": "four_per_side"}}.
No real flags, no political symbols, no readable insignia text, no historical extremist symbols.
Clean readable silhouette, clear ship-class identity, high-quality anime linework, restrained cel shading, consistent face and hair. Character body, rig base, weapons and effect origins must remain visually separable.
Create the definitive full-body style anchor concept on a transparent background. Front three-quarter standing pose, complete outfit and ship rigging visible, generous empty transparent margin, no environment, no ocean, no UI, no text. Show the body, rig base, weapon identity and core accessory clearly; the accepted anchor will be the sole identity reference for all derivative sheets.

## UI 4x2 sheet

Use the accepted style anchor as the only identity reference. Create exactly eight separated cells in a 4x2 grid: portrait, small portrait, chibi head, default expression, serious expression, hit expression, skill icon for `experimental_air_wing`, and abstract `carrier` class icon. True transparent background, no checkerboard, no matte, no text, no overlapping cells.

## Battle 4x2 sheet

Use the accepted style anchor as the only identity reference. Create exactly eight isolated orthographic game assets in a 4x2 grid, in this order: battle_body_r, battle_rig_base, battle_flight_deck, battle_aircraft_group_01, battle_turret_secondary_01, battle_aircraft_launch_marker, battle_aircraft_recovery_marker, battle_aa_center. True transparent background, no checkerboard or matte. Keep every component separated with clear empty transparent margins and readable pivots.

## Animation 2x2 state sheets

Use the accepted style anchor as the only identity reference. Create five separate chibi / SD battlefield-unit animation sheets, not full-body illustrations, portraits, half-body art, or skill cut-ins. Required files/states: idle, move, attack, hit, firepower. Each state is one 2-row by 2-column sheet ordered top-left, top-right, bottom-left, bottom-right as anticipation/start, action, feedback/recoil, recovery. Use an invisible logical grid: wide empty transparent gutters, no visible borders, no labels, no text. Every cell must contain the complete compact Q-version battle sprite matching the `battle_body_r` style: large readable head, small body, attached rigging and weapon nodes, clear small-scale silhouette, and at least 12% empty transparent margin on all sides. Identical face, hair, outfit, rigging, camera, scale, Q-version proportions, and equipment count in all four cells of each sheet. Animate only the chibi character body, attached rigging, weapon recoil, local muzzle flash/fire light, tiny local smoke/spark, local wake, local scan/aura cues, and pose changes. The four cells must be hand-drawn/generated as distinct key poses; do not duplicate the same character image with only translation, scale, tint, tiny rotation, aura, or external flash changes. Do not draw separate launched projectiles or detached attack objects: no flying shells, no bullets, no tracer streams, no torpedoes, no missiles, no aircraft, no detached depth charges, no large water impacts, no long projectile trails. True transparent background, no checkerboard or matte, no connected effects between cells.

## VFX 2x4 sheet

Create exactly eight isolated character-specific VFX overlays in a 2x4 grid, in this order: unfinished_plan_overlay, experimental_flight_lane, aircraft_launch_flash, aircraft_formation, airstrike_area, aircraft_recovery, aa_burst, skill_aura. Reusable projectile bodies and impacts are not duplicated. True transparent background, no checkerboard or matte, no text, crisp small-scale game VFX shapes.

## Acceptance rules

- Original TinySeaWar design; no real flags, political symbols, readable insignia, or extremist symbols.
- Character body, rig base, weapon nodes, and VFX must remain visually separable.
- Clearly unfinished experimental carrier structure; UI plan marker only, no readable text.
