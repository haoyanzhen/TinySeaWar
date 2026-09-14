# jervis Phase 2 Trial Log

## 2026-09-14 production result

- Source of truth: `docs/40_art_direction_design.md`, `docs/41_character_art_design.md`, `docs/46_character_art_asset_pipeline.md`, `docs/91_character_phase2_historical_validation.md`, runtime ship/weapon data, and `assets/characters/jervis/postprocess_plan.json`.
- Generation route: TinySeaWar art-pipeline skill plus the built-in image-generation tool. The tool did not expose its backend model identifier, so the actual model is recorded as `tool-managed/unknown`; this run does not claim a verified GPT Image 2.5 model ID.
- Accepted source format: PNG on reserved flat `#00FF00` background, followed by deterministic project-side alpha removal and role splitting. Native-alpha attempts were not used because transparency behavior was inconsistent.
- Final status: `complete`; `batch_ready=true`; `postprocess_ready=true`; contract missing roles `0`, invalid files `0`, data issues `0`.
- Godot 4.6.3 imported all Jervis source and regenerated processed PNG files successfully. A character-specific runtime smoke test confirmed catalog discovery, 8 battle roles, 8 UI roles, all five four-frame animation states, 8 character-specific VFX roles plus the public ASW impact reference, and the three-turret/two-torpedo/two-ASW mount bindings.

## 2026-09-14 post-production audit and repair

1. The first retained processed VFX output incorrectly cropped every VFX cell around only its largest connected alpha component. This silently reduced `aa_circle` to a horizontal fragment and `range_reticle` to a partial arc even though the accepted source sheet was correct. The pipeline now crops VFX by the full cell alpha bounds, records all-component samples and pre/post alpha area, and has a disconnected-component regression test. Both circular effects were reprocessed and visually confirmed complete.
2. The initial planned rig bindings were automatically distributed along one horizontal line and did not land on the visible mechanical sockets. `binding_positions` now provides audited normalized targets: three turret sockets, two torpedo sockets, two stern ASW drop points, the rig/skill center, and wake origin. A rendered overlay confirmed that each point lands on the intended rig structure.
3. `weapon_visual.jervis_asw` previously used `muzzle_01` and a gun muzzle flash. It now launches from `asw_launch_01`, uses the character water-splash overlay at release, and resolves the public `asw.underwater_blast` asset at impact through dedicated ASW playback profiles. Torpedo launch overlays now map to `torpedo.launch.surface` instead of the unrelated trail semantic.
4. The checked-in plan incorrectly declared level 2 despite the roster/runtime level 1 contract. It now declares level 1 and records the exact `3 x twin gun`, `2 x quintuple torpedo`, and `2 x depth-charge rack` inventory. The plan builder produces byte-equivalent structured data for Jervis, preventing a later regeneration from restoring the bad values.
5. Manifest schema v2 now embeds honest source provenance and source hashes, including `gpt-image-2.5` as the pipeline target but `tool-managed/unknown` as the actual unexposed backend. It also records prompt revision, reference input, source QA verdicts, crop hints/methods, component samples/tags, alpha area, padding, and visual centroid. The two unretained raw attack candidates and unavailable generation IDs remain explicitly marked as non-replayable history; no identifiers were invented.

## Character and object review

- Character: young Royal Navy destroyer-flotilla leader, brown hair, blue eyes, white-and-navy uniform, royal-blue short capelet, gold cords, compass/laurel command motif, calm command gestures.
- Required equipment inventory: exactly three twin 120 mm main-gun turrets, exactly two quintuple 533 mm torpedo launchers with five visible tubes each, and two stern depth-charge racks.
- Accepted anchor and battle/animation sheets preserve the required inventory. Human review found no extra barrels, merged weapons, impossible mounts, duplicated limbs, broken hands, floating fragments, clipped silhouettes, or baked checkerboard backgrounds.
- Runtime battle roles are split into body, rig base, main turret, quintuple torpedo launcher, depth-charge rack, command node, AA center, and wake marker. Mount multiplicity remains authoritative in data/bindings rather than duplicating common runtime textures.

## Attempt and rejection history

1. The first anchor request failed at the image-service network layer and produced no candidate.
2. The next anchor had the correct three twin turrets but rendered both launchers as six-tube objects; rejected at the hard object-integrity gate.
3. A corrected five-tube edit baked a checkerboard into RGB instead of providing usable transparency; rejected as a formal source.
4. The accepted anchor retained the corrected equipment and used the reserved green background for deterministic alpha cleanup.
5. UI and battle role grids passed manual semantic and object review on their first accepted versions.
6. The automated pose-variation gate rejected low-motion idle, hit, and attack candidates. Idle and hit were regenerated. The final attack sheet was assembled deterministically from two generated candidates so that all four frames retain the exact weapon inventory while frame 1 supplies a clearly distinct attack pose; no anchor-derived or procedural placeholder art was substituted.
7. The first VFX sheet used a two-column/four-row layout, while the postprocessor expects four columns/two rows. Although the file contract passed, manual review caught the semantic role mismatch; that source was rejected and replaced with a correctly ordered wide sheet.

## Final QA evidence

- Processed contact sheet: `assets/characters/qa/jervis_processed_contact.png`.
- Character-specific contract audit: `assets/characters/qa/character_asset_contract_audit_jervis.md`.
- The 65 MB data-URI edge preview was generated and reviewed during production, then omitted from formal assets; the compact contact sheet is the retained visual evidence.
- Source alpha, UI, battle, animation, VFX, bind-point, animation-config, VFX-config, and manifest outputs are all present under `assets/characters/jervis/processed/`.
- The character asset checker passes with zero missing roles, invalid files, or data issues, including the new manifest-v2, provenance-hash, VFX alpha-retention, plan-level/inventory, and weapon-binding rules.
- Four art-pipeline regression tests pass: disconnected VFX retention, explicit binding placement, checked-in/generated Jervis plan parity, and all-phase-two plan-level parity.
- The full phase-two configuration test completed `291/292` checks; all seven new Jervis ASW/binding assertions pass. Its only failure is the pre-existing repository-wide AssetCatalog error for 15 first-phase characters without `processed/vfx` directories, not a Jervis asset failure.
- The full core test runner completed `1844/1845` checks and all five battle smokes; its same sole failure is the pre-existing 15-character AssetCatalog directory error. Headless editor import/parse exited successfully.
- The new roster-level check exposed and corrected the same stale hard-coded level in eight other phase-two plans (`fletcher`, `baltimore`, `tashkent`, `gangut`, `nurnberg`, `scharnhorst`, `akizuki`, `dingyuan`). No images or runtime character values were changed by those metadata corrections.
