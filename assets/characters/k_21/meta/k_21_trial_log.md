# K-21 Phase 2 Trial Log

## 2026-09-14 production result

- Batch: `phase2_soviet_quartet_20260914`, together with Tashkent, Chapayev, and Gangut.
- Generation route: TinySeaWar art-pipeline skill plus the built-in image-generation tool. The backend model identifier was not exposed, so provenance records `tool-managed/unknown`.
- Accepted source format: mixed native-alpha and reserved near-`#00FF00` PNG, both normalized by the deterministic postprocessor.
- Hard inventory: exactly six bow tube openings and four stern tube openings, plus sonar, periscope, long-range antenna, long low rig, and tactical boots without swim fins.
- Final status: `complete`; contract missing roles `0`, invalid files `0`, data issues `0`.

## Attempt and rejection history

1. The first firepower sheet baked a checkerboard; rejected and replaced with a green-background correction.
2. The first idle, attack, and hit sheets failed pose variation at `0.930 >= 0.92`, `0.880 >= 0.78`, and `0.840 >= 0.82`. All three were redrawn with materially different body silhouettes, and their baked-checker candidates were converted to reserved green before acceptance. Thresholds were not relaxed.
3. An attempted minor correction to the first attack candidate failed at the image-service network layer and produced no file; it is not represented as an accepted source.
4. Processed contact review found the initial submerged-shadow asset crossing into the long-range-antenna cell. The complete battle grid was replaced with a strictly separated version; the regenerated antenna and shadow now resolve as independent correct roles.

## Final QA evidence

- Processed contact: `assets/characters/qa/k_21_processed_contact.png`.
- Contract audit: `assets/characters/qa/character_asset_contract_audit_tashkent_chapayev_gangut_k_21.md`.
- Binding overlay review confirms six bow and four stern mount points cluster at the corresponding ends of the visible hull, with rig, skill, and stern wake points on valid artwork.
- The torpedo launch overlay maps to `torpedo.launch.submerged`; the decorative ice trail remains a trail rather than being played as the muzzle event.
