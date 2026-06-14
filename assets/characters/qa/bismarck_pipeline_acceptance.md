# Bismarck Art Pipeline Acceptance

## Result

Overall result: **pass for binding and gameplay prototype use**.

The Bismarck package was produced from a new style anchor and trial sheets, then cleaned, split, centered, configured and audited through the TinySeaWar character-art pipeline.

## 1. Asset Completeness

Status: **pass**.

- 57 import PNGs, excluding cached alpha source sheets.
- UI/illustration: full body, half body, skill cut-in, default/serious/hit expressions, portrait, small portrait, chibi head, skill icon and battleship class icon.
- Battle: character body, rig base, two independent twin-gun turrets, rangefinder and flagship marker.
- Animation: idle, move, attack, hit and firepower; each state contains four ordered transparent frames on a normalized per-state canvas.
- VFX: heavy muzzle, muzzle flash, lock line, reticles, range arc, shell trail, wake, water impact, armor hit, smoke and decisive-battle area.
- Data: bind points, animation mapping, VFX mapping and postprocess manifest.

The asset-contract checker reports `complete`, with no missing roles, invalid files or data issues.

## 2. Split And Crop Quality

Status: **pass after two correction iterations**.

First pass exposed neighboring-component contamination in UI items, rigging, animation frames and several VFX crops. Crop hints were moved inside each intended subject so connected-component expansion selected the correct artwork.

The rig base and first turret still contained isolated neighboring fragments after the hint correction. Because these assets are explicitly single connected subjects, their specifications now use a keep-largest-component cleanup. This rule is not applied to multi-part VFX.

Final visual QA found:

- no neighboring UI item mixed into portraits, expressions, chibi head or icons;
- no adjacent animation pose mixed into any of the five keyframes;
- no neighboring VFX mixed into the final VFX assets;
- no visible hard crop through character, rig, turret barrel, wake or effect silhouette;
- transparent padding and content centering are suitable for import tests.

## 3. Data And Artwork Match

Status: **pass**.

- Turret rotation points overlay the circular turret bases.
- Both muzzle points overlay the corresponding barrel tips.
- Rig turret mounts overlay the two circular deck sockets.
- Rangefinder scan origin overlays the optical lens.
- Flagship marker origin and aura origin overlay the marker base and banner center.
- Animation states reference the matching idle, move, attack, hit and firepower images.
- Each animation state references exactly four existing frames with valid FPS and loop behavior: idle 5 FPS loop, move 7 FPS loop, attack 10 FPS once, hit 10 FPS once and firepower 12 FPS once.
- VFX roles reference visually matching muzzle, lock, reticle, range, wake, impact, armor-hit and command-area images.
- All referenced files exist; bind points are within image bounds and close to non-transparent artwork.

## Remaining Production Notes

- Four-frame images drive the MVP body pose. Precise turret rotation, muzzle placement, projectile launch, recoil offsets and VFX remain independent Godot nodes and tweens.
- The compass-like geometric accessories must remain abstract during final polish; do not replace them with real flags or historical political insignia.
- Final engine-scale testing should verify the thin cold-white lock lines remain readable after texture compression.

## QA Artifacts

- Raw source contact: `assets/characters/qa/bismarck_raw_sources_contact.png`
- Final processed contact: `assets/characters/qa/bismarck_processed_contact_final.png`
- Final bind-point overlay: `assets/characters/qa/bismarck_bind_points_overlay_final.png`
- Four-frame source contact: `assets/characters/qa/bismarck_anim_4f_sources_contact.png`
- Four-frame processed contact: `assets/characters/qa/bismarck_anim_4f_processed_contact.png`
- Automated contract report: `assets/characters/qa/character_asset_contract_audit_bismarck.md`
