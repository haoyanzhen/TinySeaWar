# Trial Batch 01 Summary

## Scope

Trial batch generated through Codex Plus image generation, without OpenAI API calls.

Target representatives:

- Enterprise CV-6: US carrier, level 3.
- Warspite: British battleship, level 3.
- Aurora: Soviet light cruiser, level 2.
- Hindenburg: German heavy cruiser, level 3.
- Shimakaze: Japanese destroyer, level 2.
- Hai Shih: Chinese submarine, level 1.

This batch covers the six MVP ship classes: carrier, battleship, light cruiser, heavy cruiser, destroyer, and submarine.

## Generated Files

Each representative currently has a complete first-pass package:

- `enterprise_cv6/concept/enterprise_cv6_concept_full.png`
- `enterprise_cv6/ui/enterprise_cv6_illust_half.png`
- `enterprise_cv6/ui/enterprise_cv6_illust_skill_cutin.png`
- `enterprise_cv6/ui/enterprise_cv6_ui_sheet.png`
- `enterprise_cv6/battle/enterprise_cv6_battle_asset_sheet.png`
- `enterprise_cv6/battle/enterprise_cv6_anim_keyframes_sheet.png`
- `enterprise_cv6/vfx/enterprise_cv6_vfx_reference_sheet.png`
- `enterprise_cv6/meta/enterprise_cv6_trial_log.md`
- `warspite/concept/warspite_concept_full.png`
- `warspite/ui/warspite_illust_half.png`
- `warspite/ui/warspite_illust_skill_cutin.png`
- `warspite/ui/warspite_ui_sheet.png`
- `warspite/battle/warspite_battle_asset_sheet.png`
- `warspite/battle/warspite_anim_keyframes_sheet.png`
- `warspite/vfx/warspite_vfx_reference_sheet.png`
- `warspite/meta/warspite_trial_log.md`
- `aurora/concept/aurora_concept_full.png`
- `aurora/ui/aurora_illust_half.png`
- `aurora/ui/aurora_illust_skill_cutin.png`
- `aurora/ui/aurora_ui_sheet.png`
- `aurora/battle/aurora_battle_asset_sheet.png`
- `aurora/battle/aurora_anim_keyframes_sheet.png`
- `aurora/vfx/aurora_vfx_reference_sheet.png`
- `aurora/meta/aurora_trial_log.md`
- `hindenburg/concept/hindenburg_concept_full.png`
- `hindenburg/ui/hindenburg_illust_half.png`
- `hindenburg/ui/hindenburg_illust_skill_cutin.png`
- `hindenburg/ui/hindenburg_ui_sheet.png`
- `hindenburg/battle/hindenburg_battle_asset_sheet.png`
- `hindenburg/battle/hindenburg_anim_keyframes_sheet.png`
- `hindenburg/vfx/hindenburg_vfx_reference_sheet.png`
- `hindenburg/meta/hindenburg_trial_log.md`
- `shimakaze/concept/shimakaze_concept_full.png`
- `shimakaze/ui/shimakaze_illust_half.png`
- `shimakaze/ui/shimakaze_illust_skill_cutin.png`
- `shimakaze/ui/shimakaze_ui_sheet.png`
- `shimakaze/battle/shimakaze_battle_asset_sheet.png`
- `shimakaze/battle/shimakaze_anim_keyframes_sheet.png`
- `shimakaze/vfx/shimakaze_vfx_reference_sheet.png`
- `shimakaze/meta/shimakaze_trial_log.md`
- `hai_shih/concept/hai_shih_concept_full.png`
- `hai_shih/ui/hai_shih_illust_half.png`
- `hai_shih/ui/hai_shih_illust_skill_cutin.png`
- `hai_shih/ui/hai_shih_ui_sheet.png`
- `hai_shih/battle/hai_shih_battle_asset_sheet.png`
- `hai_shih/battle/hai_shih_anim_keyframes_sheet.png`
- `hai_shih/vfx/hai_shih_vfx_reference_sheet.png`
- `hai_shih/meta/hai_shih_trial_log.md`

## QA Findings

Overall:

- The Codex Plus image-generation workflow is effective for first-pass style anchors, UI illustration references, cut-in references, battle sheets, animation keyframe sheets, and VFX reference sheets.
- Generated images currently arrive as RGB PNGs with no alpha channel, even when the prompt asks for transparent background.
- Treat all generated images as raw art references or cutting sheets. They require transparent-background cleanup before engine import.
- Short, explicit prompts were more stable than dense production prompts, especially for submarine UI sheets and heavy-cruiser animation sheets.
- The six representatives are enough to validate the current MVP class coverage before scaling to all 24 character prototypes.

Per-character notes:

- Enterprise CV-6: Carrier identity is clear through deck rigging, aircraft silhouettes, launch paths, and airstrike VFX. Aircraft/star-like marks should be abstracted during cleanup.
- Warspite: Battleship identity, veteran flagship posture, royal-blue uniform, cape, heavy gun rigging, battle sheet, animation keyframes, and VFX references are clear. Badge shapes need abstract cleanup.
- Aurora: Old light-cruiser identity, searchlight, smoke funnels, deep red-gray palette, and support/command mood are clear. Star-like ornaments should become gear, ice, or signal geometry.
- Hindenburg: Tier 3 heavy-cruiser identity, large turret mass, fire-control gear, angular armor, and suppression VFX are clear. Remove any motif that reads like a real historical emblem.
- Shimakaze: Destroyer speed and torpedo identity are clear through high-speed posture, torpedo tubes, torpedo warnings, and speed VFX. Head accessories should be redesigned as original propulsion-fin or signal motifs.
- Hai Shih: Submarine identity is clear through low-profile rigging, periscope, sonar headset, bubbles, torpedo lines, and underwater shadow. UI sheet generation works best with a reduced portrait/icon request.

## Required Postprocess Before Import

- Remove checkerboard/plain backgrounds and produce true transparent PNGs.
- Split sheets into individual assets.
- Crop weapon nodes and VFX components with clear margins.
- Annotate pivots, muzzle points, torpedo ports, launch/recovery points, searchlight origins, sonar origins, support centers, and VFX origins.
- Replace realistic or overly recognizable insignia-like marks with TinySeaWar abstract faction motifs.
- Recheck battle-scale readability after cleanup.
- Preserve the accepted concept anchor for each character as the reference source during cleanup and later regenerations.

## Skill Updates To Carry Forward

- Keep character data in `docs/character_art_design.md`; do not duplicate the full roster inside the skill.
- Use short prompt variants when image generation returns repeated temporary failures.
- For animation, request a simple pose sheet first, then derive production keyframes during cleanup.
- For UI sheets, reduce to portrait, avatar, chibi head, two expressions, one skill icon, and one class icon if the full sheet fails.
- For submarine assets, avoid full underwater scenes and request plain separated asset sheets.

## Next Recommended Trial Step

Move from generation into postprocess validation:

1. Clean backgrounds for one representative from each complexity tier: Hai Shih, Aurora, and Enterprise CV-6.
2. Split their battle sheets into body, rig base, weapon nodes, class nodes, and VFX swatches.
3. Create binding-point metadata for torpedo ports, turret pivots, aircraft launch points, searchlight origins, and sonar origins.
4. Verify game-scale readability after cleanup, then decide whether to scale generation to all 24 character prototypes.
