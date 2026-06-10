# Hindenburg + Shimakaze Semi-Automated Art Pipeline QA

## Scope

- Characters: `hindenburg`, `shimakaze`
- Source: generated trial sheets under each character's `ui/`, `battle/`, `vfx/`, and concept folders
- Output: split transparent PNGs, source-alpha trace copies, bind-point config, animation config, VFX config, embedded edge QA previews
- QA method: automated PNG/config checks plus Codex Computer Use visual confirmation in Safari

## Generated Outputs

- `assets/characters/hindenburg/processed/`
  - 32 import-ready split PNGs
  - 7 `source_alpha` trace PNGs
  - 4 config JSON files
- `assets/characters/shimakaze/processed/`
  - 28 import-ready split PNGs
  - 7 `source_alpha` trace PNGs
  - 4 config JSON files
- `assets/characters/qa/edge_qa_hindenburg_shimakaze.html`
- `assets/characters/qa/edge_qa_shimakaze.html`
- `assets/characters/qa/edge_qa_hindenburg_shimakaze_contact.png`

## Automated QA

- `hindenburg`: 32 import PNGs checked, 0 invalid alpha/mode issues, 0 edge-touch issues.
- `shimakaze`: 28 import PNGs checked, 0 invalid alpha/mode issues, 0 edge-touch issues.
- All 8 config JSON files parsed successfully.
- Full `source_alpha` sheets can touch their image borders because they preserve whole generated sheets; they are trace/intermediate files and are excluded from import-asset edge QA.
- The postprocess script now treats crop boxes as target hints. On the cached alpha source sheet, it finds foreground connected components intersecting the initial box, unions their true bounding boxes, and adds a source safety margin to determine the final crop.
- The output layout now uses alpha-weighted centroid balancing to add asymmetric transparent padding and keep content closer to the sub-image center.

## Codex Visual QA

- The first relative-path preview exposed a browser-local loading issue, so the stable QA page now embeds PNG data directly in the HTML.
- Hindenburg visible check: animation keyframes, battle body, fire-control node, turret, and rig assets display correctly on checker, dark, and light backgrounds. No obvious white halo, crop cut, or missing texture was visible. Very dark rigging has low contrast on dark backgrounds, which is a readability/palette concern rather than an alpha failure.
- Shimakaze visible check: animation keyframes, battle body, rig base, thruster, torpedo tube, and turret assets display correctly. Edges are clean, hard-surface parts remain readable, and the destroyer/torpedo identity is clear at preview scale.
- Contact-sheet review: VFX assets for both characters are present and generally readable. Hindenburg's muzzle, reticle, scan, smoke, wake, and impact effects are coherent; Shimakaze's torpedo trail, warning line, speed line, wake, and impact effects are coherent.
- Correction after focused review: `shimakaze_anim_move_keyframe.png` originally passed output-edge checks but the source crop box cut into the right-side face/hair. The crop was widened from `(560, 55, 1050, 425)` to `(500, 55, 1130, 425)`, then regenerated. The fixed PNG is `625x338` with 24px transparent margin on all sides.

## Character Result Evaluation

### Hindenburg

Overall result: good for MVP import testing.

Strengths:

- Heavy-cruiser silhouette is clear through large turrets, dark armored rigging, fire-control optics, reticles, and heavy muzzle effects.
- Crop layout is clean and predictable; the generated sheet structure is friendly to semi-automated splitting.
- Bind-point candidates for body, rig, turret, and fire-control node are plausible as first-pass runtime data.

Risks:

- Dark faction palette may lose detail on dark sea/background scenes unless runtime outline, rim light, or UI card lighting is added.
- Smoke and black rigging should be checked again after engine scaling because small dark shapes may merge visually.

### Shimakaze

Overall result: good, and a stronger stress test than Hindenburg because the source sheets include more thin trails, speed effects, and small weapon parts.

Strengths:

- Destroyer/high-speed torpedo role is immediately readable.
- Torpedo tubes, small turret, thruster, wake, torpedo warnings, and long trails survived splitting well.
- Animation keyframes keep a coherent chibi battle identity across idle, move, attack, hit, and firepower states.

Risks:

- Thin speed-line and torpedo-warning effects are visually correct but may need extra runtime padding/extrusion depending on atlas packing.
- Some very pale blue/white water effects are intentionally preserved; they should not be removed by future global white-background cleanup.

## Pipeline Assessment

Result: feasible and effective for MVP asset production.

What worked:

- One command now handles postprocess for selected characters; embedded QA preview generation is available through `--preview` so the default path stays faster.
- Border-connected background removal avoided the earlier issue where pale interior details could be erased.
- Programmatic alpha/edge checks caught the difference between import assets and trace-only `source_alpha` sheets.
- Codex Computer Use visual confirmation caught the local-image preview failure, which led to the embedded-preview fix.
- Focused user review caught a class of issue not covered by edge checks: source-crop truncation can still occur even when the final PNG has transparent padding. Future QA should include a crop-overlay review against the original sheet for every animation/key pose.
- A later iteration replaced edge-after-crop expansion with connected-component crop determination. This fixes cases where the initial crop already cut into an object, such as `hindenburg_ui_class_heavy_cruiser.png`.

What still needs improvement:

- Crop boxes and bind points are still code constants. The next step is moving them to per-character `postprocess_plan.json` files.
- Embedded HTML previews are reliable but large; full batches should be paginated by character or asset type.
- Source-edge warnings are intentionally conservative. A warning means the crop should be visually checked against the original sheet; it does not always mean the final split PNG is unusable.
- Engine-scale QA is still separate: these assets are ready for import testing, but final runtime scale, pivots, outlines, and animation curves still need engine verification.
