# Character Art Batch Production Validation

## Conclusion

Result: **ready for supervised batch production**.

The pipeline can now plan, process and audit multiple characters as one batch while isolating failures. It is not yet suitable for fully unattended production because every new character still needs a visually accepted style anchor, initial crop hints and binding-point verification.

## Validation Performed

### Full dry-run

The controller inspected all existing character directories for:

- base source sheets;
- five four-frame animation sheets;
- crop and runtime configuration;
- processed asset-contract completion.

Only Bismarck currently satisfies the new complete batch standard. Other existing trial characters were correctly excluded because they lack five four-frame animation sheets and, in several cases, complete UI assets.

### Processing smoke test

Test batch: `missing_batch_probe`, `bismarck`.

- `missing_batch_probe`: blocked immediately because sources and configuration do not exist.
- `bismarck`: continued independently and completed successfully.
- Bismarck postprocess and audit time: approximately 87.5 seconds on the current machine.
- The blocked item did not stop or corrupt the valid character.

This verifies per-character failure isolation and continued batch execution.

## Batch Production Unit

One new character currently requires approximately eleven generated source images:

1. style anchor/full body;
2. half-body illustration;
3. skill cut-in;
4. complete UI sheet;
5. battle asset sheet;
6. VFX sheet;
7. idle four-frame sheet;
8. move four-frame sheet;
9. attack four-frame sheet;
10. hit four-frame sheet;
11. firepower four-frame sheet.

After source generation, the deterministic stage cleans backgrounds, splits components, normalizes animation canvases, writes configuration, validates references and produces QA artifacts.

## What Can Be Batched Reliably

- Character brief and prompt assembly from project documents.
- Source-package presence checks.
- Background cleanup and alpha conversion.
- Configured component splitting and centering.
- Four-frame sequence splitting and canvas normalization.
- Animation/VFX configuration generation.
- PNG, JSON, reference, frame-count, frame-size and binding-point audits.
- Per-character failure isolation and batch reports.

## Required Supervision

- Accept or reject the style anchor before derivative generation.
- Check face, hair, outfit and rigging identity across generated sheets.
- Establish initial crop hints for a new sheet layout.
- Visually reject neighboring-component contamination or damaged alpha edges.
- Calibrate pivots, muzzle points, mounts and effect origins against artwork.
- Verify real political or historical extremist symbols are absent.

## Recommended Batch Size

- Generate anchors in groups of 4 to 6 characters.
- Accept anchors before generating derivatives.
- Generate derivative sheets for 2 to 3 accepted characters at a time.
- Run postprocess and automatic audit for the whole ready group.
- Perform visual QA per character before starting the next group.

This keeps identity drift and regeneration costs contained while still benefiting from batch processing.

## Commands

```bash
python3 tools/art_pipeline/batch_character_art.py
python3 tools/art_pipeline/batch_character_art.py bismarck --process --preview
```

Batch reports:

- `assets/characters/qa/character_art_batch_report.json`
- `assets/characters/qa/character_art_batch_report.md`

