# Character Art Full-Roster Acceptance

Date: `2026-06-20`

Sources of truth:

- `docs/40_art_direction_design.md` section 6
- `docs/41_character_art_design.md`
- `docs/45_art_asset_interface_design.md`
- `docs/46_art_pipeline_design.md`

## Result

- Roster: `24/24 complete`
- Batch production readiness: `24/24 batch_ready`
- Runtime PNG assets: `1325`
- Empty-alpha PNGs: `0`
- PNGs touching a canvas edge: `0`
- PNGs with visible reserved chroma key: `0`
- Required animation states: `5/5 per character`
- Frames per animation state: `4/4 on a shared canvas`
- Runtime semantic report: `24 characters`, `163 binding semantics`, `178 VFX roles`
- Per-character processed contact sheets: `24/24`

## Per-Character Coverage

| Character | UI | Battle | Animation | VFX | Runtime PNG total | Contract |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| enterprise_cv6 | 11 | 8 | 25 | 19 | 63 | complete |
| iowa | 11 | 9 | 25 | 9 | 54 | complete |
| san_diego | 11 | 8 | 25 | 8 | 52 | complete |
| ward | 11 | 8 | 25 | 8 | 52 | complete |
| warspite | 11 | 8 | 25 | 20 | 64 | complete |
| hood | 11 | 8 | 25 | 8 | 52 | complete |
| sirius | 11 | 8 | 25 | 8 | 52 | complete |
| argus | 11 | 8 | 25 | 8 | 52 | complete |
| aurora | 11 | 7 | 25 | 18 | 61 | complete |
| kirov | 11 | 8 | 25 | 8 | 52 | complete |
| pobeda | 11 | 8 | 25 | 8 | 52 | complete |
| gnevny | 11 | 8 | 25 | 8 | 52 | complete |
| bismarck | 11 | 6 | 25 | 15 | 57 | complete |
| prinz_eugen | 11 | 8 | 25 | 8 | 52 | complete |
| hindenburg | 11 | 7 | 25 | 20 | 63 | complete |
| u_47 | 11 | 8 | 25 | 8 | 52 | complete |
| yamato | 11 | 8 | 25 | 8 | 52 | complete |
| yukikaze | 11 | 8 | 25 | 8 | 52 | complete |
| shimakaze | 11 | 7 | 25 | 21 | 64 | complete |
| hosho | 11 | 8 | 25 | 8 | 52 | complete |
| ning_hai | 11 | 8 | 25 | 8 | 52 | complete |
| anshan | 11 | 8 | 25 | 8 | 52 | complete |
| chongqing | 11 | 8 | 25 | 8 | 52 | complete |
| hai_shih | 12 | 6 | 25 | 24 | 67 | complete |

Different battle/VFX totals are intentional class and legacy-route differences. Every package satisfies the semantic minimum for its ship class and the common character-art contract.

## Visual QA

Codex inspected `assets/characters/qa/character_roster_processed_contact.png` after the final postprocess pass. The review covers full-body identity, portrait consistency, battle-body silhouette, move keyframe, and firepower keyframe for every character.

The final pass removed enclosed chroma-key remnants, retained transparent safety padding, and rebuilt per-character contact sheets. No blocking crop, wrong-character, empty-cell, or obvious cross-cell contamination remains in the roster overview.

## Runtime Verification

- `godot --headless --path . --script res://scripts/tests/test_runner.gd`: `PASS: 92 checks`
- `godot --headless --path . --script res://scripts/tests/scene_presentation_test.gd`: `PASS: 41 scene presentation checks`
- Current configured body target-width ratio: `1.4024`
- Current configured rig target-width ratio: `1.4352`

Both runtime visual-size ratios remain below the project limit of `1.5`. Raw PNG dimensions may differ because Godot normalizes body and rig display widths from collision radius.

## Acceptance

All 24 character packages are accepted for the current MVP character-art contract and runtime binding workflow. Later hand-painted polish may improve edge softness or animation nuance, but it is not a missing-asset or integration blocker.
