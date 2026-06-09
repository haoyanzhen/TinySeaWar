# Warspite Art Trial Log

## Scope

Second full-pipeline TinySeaWar art trial using Codex Plus image generation, without API calls.

Generated assets:

- `concept/warspite_concept_full.png`
- `ui/warspite_illust_half.png`
- `ui/warspite_illust_skill_cutin.png`
- `ui/warspite_ui_sheet.png`
- `battle/warspite_battle_asset_sheet.png`
- `battle/warspite_anim_keyframes_sheet.png`
- `vfx/warspite_vfx_reference_sheet.png`

## Result

The trial is useful as a battleship style and production-reference pass.

Strengths:

- Battleship identity is readable through large main turrets, heavy rig base, rangefinder details, broad wake, and water-column impacts.
- Veteran flagship personality is consistent across full-body, half-body, cut-in, UI sheet, battle sheet, and animation keyframe sheet.
- Battle sheet separates compact battle body, rig base, main guns, fire-control device, muzzle flashes, and water-column VFX well enough for manual crop planning.
- Animation keyframes communicate idle, slow move, attack alignment, hit reaction, and firepower salvo clearly.
- VFX sheet provides usable references for muzzle flash, shell trail, calibration line, water column, heavy wake, armor sparks, and command aura.

Issues:

- Generated PNGs should be treated as raw RGB references unless postprocessed; do not assume true alpha transparency.
- Some shield/cross-like badge shapes are too close to real heraldic or military symbol language and should be abstracted during cleanup.
- Cut-in and VFX sheets include dramatic background effects that must be separated before game import.
- Animation keyframes are reference poses only, not final import-ready animation frames.

## Required Postprocess

- Remove checkerboard/plain backgrounds and produce true transparent PNGs.
- Split battle and VFX sheets into individual files.
- Replace shield/cross-like marks with abstract TinySeaWar British-faction naval motifs.
- Annotate pivots for main turrets, rig base, muzzle points, shell origins, and VFX origins.
- Recheck small battle-scale readability after cleanup.
