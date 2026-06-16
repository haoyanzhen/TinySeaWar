# UI Asset QA Report

## Result

**PASS** for the TinySeaWar MVP UI art contract.

- Model: `gpt-image-2`.
- Raw generated PNGs: 17.
- Accepted semantic assets: 116.
- 1x/2x/4x icon and marker exports: 195.
- All accepted outputs are RGBA PNGs with non-empty alpha and transparent pixels.
- Exact semantic-role contract: pass.
- Chroma-key residue scan: pass.

## Coverage

| Category | Accepted |
| --- | ---: |
| Panels | 9 |
| Buttons | 19 |
| Portrait frames | 8 |
| General icons | 38 |
| Battle markers | 11 |
| Minimap assets | 7 |
| Battle-log icons | 4 |
| Result decorations | 8 |
| Bars | 7 |
| Rings | 3 |
| Badges | 2 |

The package covers the top expanded/collapsed HUD, three automatic controls,
2x6 fleet tray, open-sea minimap, fixed-bottom battle log, selected-ship panel,
pause/result/confirmation dialogs, fleet portrait states, tactical markers,
combat and visibility states, six ship classes, minimap contacts, battle events,
victory/defeat decoration, health/oxygen/skill/cooldown and dialog actions.

## Visual QA

Inspected outputs on checker, dark and light backgrounds:

- No rectangular green or magenta background residue remains in accepted assets.
- Pale borders and white highlights remain visible on dark backgrounds.
- Sky-blue outlines remain visible on light backgrounds.
- No accepted aircraft icon contains national or historical insignia.
- No real flags, political symbols or readable generated text are present.
- The dedicated minimap panel contains an open-ocean grid and no islands.
- Portrait-frame and panel crops no longer contain neighboring components.
- Automatic-control enabled states and the healthy HP bar have continuous fills.
- The danger-area tile uses coral/red stripes with transparent gaps and no green.

Small-scale review:

- 32 px exports remain distinguishable by silhouette.
- 24 px QA previews retain the required control, combat, class, contact and
  marker meanings. Fine decorative detail is reduced, but core silhouettes hold.
- Selected, target, enemy, danger and skill states remain distinct by shape as
  well as color.

## Evidence

- `ui_asset_manifest.json`: source, crop, output, size, alpha and export records.
- `ui_asset_contact.png`: checker-background contact sheet.
- `ui_asset_contact_dark.png`: dark-background edge review.
- `ui_asset_contact_light.png`: light-background edge review.
- `ui_icons_1x_contact.png`: 32 px export review.
- `ui_icons_24px_contact.png`: 24 px readability review.
- `tools/art_pipeline/check_ui_asset_contract.py`: exact role, RGBA, alpha,
  residue, dimension and export validation.

## Runtime Handoff

- Use runtime fonts; do not add baked text to these images.
- Import panel and button masters as nine-slice assets where appropriate.
- Use `export/1x`, `2x` and `4x` for fixed-size icons, or use processed masters
  when Godot performs controlled downsampling.
- Continue using procedural drawing for variable-length paths, ranges and
  cooldown masks over the generated borders and markers.
- Clip character portraits from `assets/characters/*/processed/ui/` into the
  generated portrait frames.
