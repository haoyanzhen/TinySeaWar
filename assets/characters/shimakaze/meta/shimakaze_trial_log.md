# Shimakaze Art Trial Log

## Scope

Third full-pipeline TinySeaWar art trial using Codex Plus image generation, without API calls.

Generated assets:

- `concept/shimakaze_concept_full.png`
- `ui/shimakaze_illust_half.png`
- `ui/shimakaze_illust_skill_cutin.png`
- `ui/shimakaze_ui_sheet.png`
- `battle/shimakaze_battle_asset_sheet.png`
- `battle/shimakaze_anim_keyframes_sheet.png`
- `vfx/shimakaze_vfx_reference_sheet.png`

## Result

The trial is useful as a destroyer/torpedo style and production-reference pass.

Strengths:

- Destroyer identity is readable through lightweight rigging, small guns, propulsion parts, and prominent torpedo tubes.
- High-speed torpedo role is clear across half-body, cut-in, UI sheet, battle sheet, animation keyframes, and VFX sheet.
- Battle sheet is the most separable sheet so far, with body, rig base, torpedo tubes, small guns, propulsion parts, torpedoes, warning lines, and wake swatches.
- Animation keyframes communicate idle, high-speed movement, torpedo aim, hit reaction, and multi-torpedo firepower.
- VFX sheet provides usable references for torpedo warning lines, torpedo wakes, speed-slice wakes, launch flashes, and torpedo impact splashes.

Issues:

- Generated PNGs should be treated as raw RGB references unless postprocessed; do not assume true alpha transparency.
- Flower/fan-like accessories and marks should be abstracted further to avoid real-symbol or existing shipgirl-design resemblance.
- Some cut-in and keyframe motion effects need separation before engine import.

## Required Postprocess

- Remove checkerboard/plain backgrounds and produce true transparent PNGs.
- Split battle and VFX sheets into individual files.
- Replace flower/fan-like marks with abstract TinySeaWar wave or propulsion motifs.
- Annotate pivots for torpedo tubes, small guns, rig base, propulsion points, torpedo launch points, and VFX origins.
- Recheck small battle-scale readability after cleanup.
