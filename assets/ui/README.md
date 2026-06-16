# TinySeaWar MVP UI Art

This package contains the generated and postprocessed MVP UI art defined by
`docs/ui_art_design.md`.

## Layout

```text
raw/                         Original gpt-image-2 generations
processed/source_alpha/      Cleaned full-sheet RGBA sources
processed/common/            Shared icons, buttons and bars
processed/battle/            HUD, fleet, minimap, log, marker and result assets
export/1x/                    32 px icon and marker exports
export/2x/                    64 px icon and marker exports
export/4x/                    128 px icon and marker exports
qa/                          Manifest, contact sheets, prompts and QA report
```

## Rebuild And Verify

```bash
python3 tools/art_pipeline/process_ui_art.py
python3 tools/art_pipeline/check_ui_asset_contract.py
```

The processed package contains 116 semantic assets. Runtime text is intentionally
not baked into the images. Panels and buttons are intended for nine-slice or
equivalent scalable UI use; tactical paths, range fills and cooldown progress can
be animated or masked by Godot over the generated art.

Character portraits remain under `assets/characters/*/processed/ui/` and should
be clipped into the fleet portrait frames at runtime.
