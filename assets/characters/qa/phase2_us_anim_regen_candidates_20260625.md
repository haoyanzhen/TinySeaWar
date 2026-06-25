# Phase 2 US Animation Regeneration Candidates - 2026-06-25

Scope: manual-confirmation candidates only. These images are not wired into `processed/` and do not replace the current runtime animation sources.

Update after manual review: this candidate set is superseded by the stricter animation-master prompt. Import is blocked until the affected animation masters are regenerated as Q-version battlefield-unit sprites with no detached launched projectiles.

Generated from the previous phase2 animation-master brief:

> Use the accepted style anchor as the only identity reference. Create a 5-row by 4-column animation master. Rows in order: idle, move, attack, hit, firepower. Each row has anticipation/start, action, feedback/recoil, recovery. Identical face, hair, outfit, rigging, camera, scale and equipment count in all twenty cells. Flat reserved green background, no labels, no connected effects between cells.

## Candidate files

- `assets/characters/fletcher/battle/fletcher_anim_5x4_master_candidate_regen_20260625.png`
- `assets/characters/cleveland/battle/cleveland_anim_5x4_master_candidate_regen_20260625.png`
- `assets/characters/baltimore/battle/baltimore_anim_5x4_master_candidate_regen_20260625.png`
- `assets/characters/wahoo/battle/wahoo_anim_5x4_master_candidate_regen_20260625.png`

Rejected trace:

- `assets/characters/cleveland/battle/cleveland_anim_5x4_master_candidate_regen_20260625_rejected_identity_drift.png` - rejected because the first Cleveland candidate drifted to blonde hair and no longer matched the accepted anchor identity.

## Quick visual pre-screen

- Fletcher: 5x4 layout present; action rows have muzzle/torpedo/water feedback; identity broadly matches the accepted blonde destroyer anchor.
- Cleveland: regenerated after identity drift; 5x4 layout present; dark blue hair, radar mast, cruiser gun silhouette and no torpedo tubes are visible.
- Baltimore: 5x4 layout present, but the candidate uses full-body illustration proportions instead of Q-version battlefield-unit proportions. Not usable for Q-version runtime animation.
- Wahoo: 5x4 layout present; submarine low silhouette and front/aft torpedo/underwater effects are visible; no foot flippers observed at overview scale.

## Status

Superseded. Do not postprocess/import this set. Regenerate animation masters with the updated prompt requiring Q-version battlefield-unit proportions and forbidding detached launched shells, bullets, torpedoes, aircraft, depth charges, long trails, and large water impacts. Local muzzle flash/fire light remains allowed.
