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

The runtime roster currently contains 24 characters. The original six prototype
definitions remain in `prototype_*.json`; the other 18 characters and their
weapons/skills live in `expanded_roster_*.json`. All definitions are loaded into
one registry and use globally unique IDs. `level.prototype_11v11` uses 22 unique
characters, while the 1v1 roster supplies the remaining Warspite and Bismarck.

`tools/data/build_expanded_roster_data.mjs` regenerates the expanded weapon and
skill JSON from the reviewed roster values. Ship and level placement data remain
hand-authored.

To add a surface character:

1. Add or reuse weapon, projectile, formula, and skill definitions.
2. Add one ship definition using only stable IDs.
3. Add the ship to a level fleet with a battle-unique `entity_id`.
4. Run `godot --headless --path . --script res://scripts/tests/test_runner.gd`.

The registry rejects duplicate IDs, missing references, unsupported enums,
invalid ranges, non-positive core values, and invalid flagship counts before a
battle can start.

Every weapon keeps both `base_range` and the effective runtime `range`. The
current battlefield tuning uses `range == base_range * 2` for guns, torpedoes,
anti-air weapons, and aviation alike. Minimum range is not scaled.
