# Gangut Phase 2 Trial Log

## 2026-09-14 production result

- Batch: `phase2_soviet_quartet_20260914`, together with Tashkent, Chapayev, and K-21.
- Generation route: TinySeaWar art-pipeline skill plus the built-in image-generation tool. The backend model identifier was not exposed, so provenance records `tool-managed/unknown`.
- Accepted source format: PNG on reserved near-`#00FF00` green, followed by deterministic alpha removal and semantic splitting.
- Hard inventory: exactly four triple 305 mm main turrets and eight compact single-barrel secondary mounts.
- Final status: `complete`; contract missing roles `0`, invalid files `0`, data issues `0`.

## Attempt and rejection history

1. Concept, UI, battle grid, and VFX sources passed first-round object and role review; the battle grid provides reusable triple-main and single-secondary components while multiplicity remains in data and bindings.
2. The accepted idle candidate initially had a gray studio background and was converted to reserved green without changing the unit.
3. One attack request failed at the image-service network layer. The later candidate failed the pose gate at `0.800 >= 0.78`; it was replaced with distinct low brace, extended command, heavy recoil, and one-knee recovery silhouettes. The threshold was not relaxed.

## Final QA evidence

- Processed contact: `assets/characters/qa/gangut_processed_contact.png`.
- Contract audit: `assets/characters/qa/character_asset_contract_audit_tashkent_chapayev_gangut_k_21.md`.
- Binding overlay review confirms four main-turret rings and all eight secondary mounts land on visible sockets along both sides of the hull.
- Main and secondary guns now use their public muzzle profiles rather than treating the Steel Line skill aura as a muzzle flash.
