# Tashkent Phase 2 Trial Log

## 2026-09-14 production result

- Batch: `phase2_soviet_quartet_20260914`, together with Chapayev, Gangut, and K-21.
- Generation route: TinySeaWar art-pipeline skill plus the built-in image-generation tool. The backend model identifier was not exposed, so provenance records `tool-managed/unknown` and does not claim a verified model ID.
- Accepted source format: PNG on reserved near-`#00FF00` green, followed by deterministic alpha removal and semantic splitting.
- Hard inventory: exactly three twin 130 mm main turrets and three triple 533 mm torpedo launchers.
- Final status: `complete`; contract missing roles `0`, invalid files `0`, data issues `0`.

## Attempt and rejection history

1. The first transparent anchor candidate baked a checkerboard into the image; rejected. A green-background correction preserving the equipment became the accepted anchor.
2. The first battle grid showed four main-turret sockets instead of three; rejected and regenerated with three turret sockets and three triple torpedo positions.
3. The initial four-character animation request and one individual retry failed at the image-service network layer and produced no files. The accepted idle candidate initially had a gray studio background, which was replaced by reserved green without changing the character.
4. The first retained attack sheet failed the automated pose gate at registered alpha IoU `0.842 >= 0.78`; it was replaced with distinct crouch, lunge, recoil, and one-knee recovery silhouettes. The threshold was not relaxed.

## Final QA evidence

- Processed contact: `assets/characters/qa/tashkent_processed_contact.png`.
- Contract audit: `assets/characters/qa/character_asset_contract_audit_tashkent_chapayev_gangut_k_21.md`.
- Binding overlay review confirms the three gun sockets and three torpedo mounts land on the visible rig base rather than an automatically distributed horizontal line.
- Main-gun and surface-torpedo runtime mappings resolve the correct weapon asset, launch binding, and public VFX semantic.
