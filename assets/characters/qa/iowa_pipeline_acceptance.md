# Iowa Pipeline Acceptance

Status: `pass for MVP binding test`

## Checks

| Area | Result | Notes |
| --- | --- | --- |
| Source package | pass | All base sources and five four-frame animation sheets exist. |
| Processed contract | pass | `check_character_asset_contract.py iowa` reports `complete`. |
| UI assets | pass | Required portrait, small portrait, chibi head, expressions, skill icon, and class icon exist. |
| Battle assets | pass | Body, rig base, main turrets, secondary turret, fire-control node, flagship marker, and wake marker were split. |
| Animation | pass | Five states have four normalized frames and config entries. |
| VFX | pass | Character-specific VFX references and config exist. |
| Visual crop QA | pass with polish | No blocking crop cuts or neighboring-fragment contamination after largest-component cleanup. |

## Remaining Polish

- Replace concrete cap emblem with a more abstract TinySeaWar naval ornament in a future art pass.
- Confirm battle body scale and silhouette in Godot tactical view.
- Keep public shell, impact, water splash, and projectile behavior on the shared combat VFX profiles; do not duplicate them as Iowa-only runtime effects unless a skill needs a unique override.
