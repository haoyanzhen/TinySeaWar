# Chapayev Phase 2 Trial Log

## 2026-09-14 production result

- Batch: `phase2_soviet_quartet_20260914`, together with Tashkent, Gangut, and K-21.
- Generation route: TinySeaWar art-pipeline skill plus the built-in image-generation tool. The backend model identifier was not exposed, so provenance records `tool-managed/unknown`.
- Accepted source format: PNG on reserved near-`#00FF00` green, followed by deterministic alpha removal and semantic splitting.
- Hard inventory: exactly four triple 152 mm main turrets and two triple 533 mm torpedo launchers.
- Final status: `complete`; contract missing roles `0`, invalid files `0`, data issues `0`.

## Attempt and rejection history

1. The first concept candidate used oversized ambiguous torpedo clusters; rejected and corrected to two readable triple launchers.
2. The first battle grid's reusable torpedo component had four openings; rejected and corrected to exactly three.
3. The accepted idle candidate initially had a gray studio background; a green-only edit preserved the character and equipment.
4. The first attack request failed at the image-service network layer. Its later candidate still failed the pose gate at `0.824 >= 0.78`; the firepower sheet also failed at `0.866 >= 0.86`. Both were redrawn with distinct crouch, extension, lunge/recoil, and one-knee recovery silhouettes. Thresholds were not relaxed.

## Final QA evidence

- Processed contact: `assets/characters/qa/chapayev_processed_contact.png`.
- Contract audit: `assets/characters/qa/character_asset_contract_audit_tashkent_chapayev_gangut_k_21.md`.
- Binding overlay review confirms four main-turret sockets, two torpedo mounts, and central rig/skill/wake origins land on visible structures.
- Main-gun and torpedo presentation now rely on their public launch profiles instead of misusing the AA burst or skill grid as a muzzle effect.
