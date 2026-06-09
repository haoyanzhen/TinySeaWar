# Enterprise CV-6 Art Trial Log

## Scope

First TinySeaWar art pipeline trial using Codex Plus image generation, without API calls.

Generated assets:

- `concept/enterprise_cv6_concept_full.png`
- `ui/enterprise_cv6_illust_half.png`
- `ui/enterprise_cv6_illust_skill_cutin.png`
- `ui/enterprise_cv6_ui_sheet.png`
- `battle/enterprise_cv6_battle_asset_sheet.png`
- `battle/enterprise_cv6_anim_keyframes_sheet.png`
- `vfx/enterprise_cv6_vfx_reference_sheet.png`

## Result

The trial is useful as a visual style and production-reference pass.

Strengths:

- Carrier identity is readable through horizontal flight-deck rigging, aircraft silhouettes, launch paths, and blue-white aviation VFX.
- Character identity is mostly stable across full-body, half-body, cut-in, UI sheet, battle sheet, and animation keyframe sheet.
- Battle sheet separates body, rigging, aircraft, launch lights, and VFX well enough for manual crop planning.
- Animation keyframes clearly communicate idle, move, attack, hit, and firepower states.
- VFX sheet provides usable references for aircraft trails, airstrike areas, launch lights, wakes, and anti-air bursts.

Issues:

- All generated PNGs are RGB with no alpha channel; the apparent transparent/checkerboard background is not real transparency.
- Some aircraft/star markings are too close to real-world insignia language and should be abstracted during cleanup.
- Battle rigging and body still overlap in places; final game assets require manual split, crop, and pivot cleanup.
- Animation keyframes are reference poses only, not final import-ready animation frames.

## Required Postprocess

- Remove checkerboard/plain background and produce true transparent PNGs.
- Split asset sheets into individual files.
- Replace any realistic insignia-like marks with abstract faction marks.
- Annotate binding points for aircraft launch/recovery points, VFX origins, and rig base pivot.
- Recheck small battle-scale readability after cleanup.
