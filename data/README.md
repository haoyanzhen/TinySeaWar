# Runtime Data

`data/` is the single source of truth for battle configuration. Runtime state is
created fresh by `BattleSession` and is never written back to these files.

Definition groups:

- `ships/`: character stats plus `weapon_mounts` and `skill_id` references.
- `weapons/`: mount cadence, range, arc, projectile, formula, and armor table.
- `projectiles/`: domain movement and collision behavior.
- `skills/`: target rules and reusable status modifiers.
- `formulas/`: hit and damage coefficients.
- `levels/`: map, fleets, spawn positions, and exactly one flagship per side.

To add a surface character:

1. Add or reuse weapon, projectile, formula, and skill definitions.
2. Add one ship definition using only stable IDs.
3. Add the ship to a level fleet with a battle-unique `entity_id`.
4. Run `godot --headless --path . --script res://scripts/tests/test_runner.gd`.

The registry rejects duplicate IDs, missing references, unsupported enums,
invalid ranges, non-positive core values, and invalid flagship counts before a
battle can start.
