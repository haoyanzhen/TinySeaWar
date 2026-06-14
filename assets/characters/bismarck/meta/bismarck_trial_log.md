# Bismarck Trial Log

## Scope

- Character: Bismarck
- Faction: German
- MVP type: battleship
- Tier: 3
- Personality: dignified flagship
- Combat role: high-armor decisive heavy firepower

## Style Anchor

- Ash-blonde hair, steel-gray eyes, black-silver long coat and flagship mantle.
- Heavy twin-gun battleship rigging, thick angular armor and optical rangefinder.
- Graphite black, silver, gunmetal, cold white and restrained crimson palette.
- Real flags, political symbols, readable insignia and historical extremist symbols are prohibited.

## Trial Package

- Full-body concept/style anchor.
- Half-body illustration and skill cut-in.
- Complete eight-item UI sheet.
- Battle body, rig base, two main turrets, rangefinder, flagship marker and battle VFX sheet.
- Five animation keyframe references.
- Five ordered four-frame animation sheets: idle, move, attack, hit and firepower.
- Ten-item VFX reference sheet.

## QA Focus

- Verify all required character-art contract roles are present.
- Verify automatic crops do not merge neighboring UI items, animation poses or VFX.
- Verify turret pivots and muzzle points, rangefinder origin, animation mappings and VFX mappings match the split images.
- Verify every processed animation state contains four ordered frames on one normalized canvas size; Godot uses independent turret and VFX nodes over the body sequence.
