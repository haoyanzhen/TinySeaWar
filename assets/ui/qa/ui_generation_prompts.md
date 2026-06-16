# UI Generation Prompt Set

All source art was generated with `gpt-image-2` through the built-in image
generation workflow. The common production constraints were:

- Bright, relaxed 2D anime naval tactics UI for TinySeaWar.
- Sea-salt white, pale aqua, sky blue, deep teal, sunlight yellow, mint green,
  coral and violet palette from `docs/ui_art_design.md`.
- Friendly and premium, playful but not childish, never a dark military terminal.
- Isolated components with large gaps and no readable text, logos, flags,
  political symbols, national insignia or watermarks.
- Flat chroma-key background for local alpha extraction.

## Accepted Batches

| Raw source | Final prompt focus | Result |
| --- | --- | --- |
| `style_anchor/ui_style_anchor_sheet.png` | Complete bright UI material and component style anchor | Accepted as the style reference |
| `icons/ui_icons_controls_sheet.png` | 4x4 automatic control, pause, expansion, health, oxygen, selection and visibility icons | Accepted |
| `icons/ui_icons_combat_sheet.png` | 4x4 combat, status, minimap and battle-log icons | Accepted except airstrike icon |
| `panels/ui_panels_sheet.png` | 3x3 empty HUD, fleet, minimap, log, selected ship and dialog panels | Accepted with component-boundary crops |
| `frames/ui_frames_buttons_sheet.png` | 4x3 portrait-state frames and small button states | Accepted with component-boundary crops |
| `markers/ui_markers_sheet.png` | 4x3 selection, target, movement, off-screen, flagship and area markers | Accepted except danger-area tile |
| `icons/ui_icons_classes_minimap_sheet.png` | Six ship classes and six friendly/enemy minimap glyphs | Accepted |
| `results/ui_results_decor_sheet.png` | Victory, defeat, pause, confirmation and decorative result assets | Accepted |
| `frames/ui_auto_toggles_sheet_v2.png` | Six clean automatic movement/weapon/skill on/off buttons on magenta key | Accepted; replaces v1 |
| `bars/ui_bars_status_sheet.png` | Bar tracks, warning/critical/oxygen/skill/damage and ring/badge states | Accepted except healthy HP bar |
| `icons/ui_icon_airstrike_replacement.png` | Plain unmarked aircraft and targeting arc | Accepted; removes insignia risk |
| `markers/ui_marker_danger_area_replacement.png` | Coral/red striped quarter-circle danger tile with transparent gaps | Accepted |
| `bars/ui_bar_hp_healthy_replacement.png` | Clean continuous mint healthy HP bar on magenta key | Accepted |
| `frames/ui_buttons_sizes_states_sheet.png` | Small/medium/large default, focused and warning buttons | Accepted |
| `icons/ui_icons_dialog_actions_sheet.png` | Confirm, cancel, restart battle and exit battle icons | Accepted |

## Superseded Or Rejected Batches

- `frames/ui_auto_toggles_sheet.png`: superseded because green-key removal damaged
  mint fills.
- `bars/ui_bars_status_sheet_v2.png`: rejected because the model introduced dark
  contamination into several fills and badges.

Raw generations are retained for traceability. Only files referenced by
`ui_asset_manifest.json` belong to the accepted processed package.
