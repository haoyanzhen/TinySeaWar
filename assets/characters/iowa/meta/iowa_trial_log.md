# Iowa Trial Log

Character source: `docs/41_character_art_design.md`

## Generation Summary

- Generated with built-in image generation using gpt-image-2 style prompts and flat green-screen background.
- Source package completed:
  - `concept/iowa_concept_full.png`
  - `ui/iowa_illust_half.png`
  - `ui/iowa_illust_skill_cutin.png`
  - `ui/iowa_ui_sheet.png`
  - `battle/iowa_battle_asset_sheet.png`
  - `vfx/iowa_vfx_reference_sheet.png`
  - five `battle/iowa_anim_*_4f_sheet.png` animation sheets
- Postprocessed with `tools/art_pipeline/postprocess_generated_character.py iowa`.

## QA Notes

- Contract audit passed after fixing auto muzzle-point placement.
- Visual QA found first-pass crop contamination in UI/battle single assets; fixed by keeping the largest alpha component for single-piece UI and battle outputs.
- Current MVP-polish notes:
  - The officer cap emblem is more concrete than ideal; replace with a more abstract compass/star ornament in a final art pass.
  - Battle body is a compact chibi-style simplification, acceptable for tactical-scale MVP but should be checked in-engine.
  - VFX sheet includes character-specific references only; public projectile and impact assets should still come from `docs/42_combat_art_design.md`.

## Accepted Pipeline Learnings

- Strict 4x2 UI sheet prompts work better than freeform UI-sheet prompts.
- Battleship battle asset sheets can be auto-split reliably when the prompt asks for separated body, rig base, turrets, fire-control node, flagship marker, and wake marker.
- For single-piece assets, crop padding can pull in neighboring art; apply largest-component cleanup to UI/battle outputs, not to VFX or animation frames.
