# Phase 2 US Animation Split Test - Boxed vs Clean - 2026-06-25

Scope: Fletcher, Cleveland, Baltimore, and Wahoo Q-version animation masters.

## Source cleanup

Deleted previous generated animation masters, previous regeneration candidates, previous processed animation frames, previous animation alpha sources, previous animation configs, and stale postprocess manifests for the four US phase2 characters.

The accepted Q-version candidates were promoted to the standard source-master paths:

- `assets/characters/fletcher/battle/fletcher_anim_5x4_master.png`
- `assets/characters/cleveland/battle/cleveland_anim_5x4_master.png`
- `assets/characters/baltimore/battle/baltimore_anim_5x4_master.png`
- `assets/characters/wahoo/battle/wahoo_anim_5x4_master.png`

The original accepted candidate files remain for traceability:

- `assets/characters/fletcher/battle/fletcher_anim_5x4_master_candidate_q_20260625.png`
- `assets/characters/cleveland/battle/cleveland_anim_5x4_master_candidate_q_20260625.png`
- `assets/characters/baltimore/battle/baltimore_anim_5x4_master_candidate_q_20260625.png`
- `assets/characters/wahoo/battle/wahoo_anim_5x4_master_candidate_q_20260625.png`

## Split outputs

Two split modes were tested:

- Boxed split: fixed grid crop, preserving the original green background and grid-box context.
- Clean split: inset crop to avoid grid edges, green-screen removal, alpha trim, and per-character shared transparent canvas.

Output locations:

- Boxed frames: `assets/characters/{id}/qa/anim_split_boxed_20260625/`
- Clean frames: `assets/characters/{id}/qa/anim_split_clean_20260625/`
- Comparison overview: `assets/characters/qa/phase2_us_anim_split_boxed_vs_clean_20260625.png`
- Per-character comparisons and metrics: `assets/characters/qa/anim_split_compare_20260625/`

Frame counts:

- Fletcher: 20 boxed + 20 clean.
- Cleveland: 20 boxed + 20 clean.
- Baltimore: 20 boxed + 20 clean.
- Wahoo: 20 boxed + 20 clean.

## Technical result

Clean split output uses a consistent canvas per character:

- Fletcher: `329x266`
- Cleveland: `400x221`
- Baltimore: `400x221`
- Wahoo: `400x221`

No clean frame touches the output canvas edge in the automated alpha-bounds check.

## Visual conclusion

- Boxed split is useful for reviewing source layout and row/column ordering, but it retains green background and grid-box artifacts and is not suitable for runtime import.
- Clean split removes the box/background and produces transparent, centered frames suitable for the next postprocess/import step.
- The visual action content is preserved in both modes. The meaningful difference is mainly import cleanliness: boxed keeps source-sheet context; clean produces actual sprite frames.
- Fletcher's source master is square (`1254x1254`) while the other three are `1536x1024`; fixed grid splitting still produced 20 usable frames, but Fletcher should remain on the clean path with alpha-bound checks enabled.

## Recommendation

Use the clean split path for runtime animation frame generation. Keep boxed split only as QA evidence.
