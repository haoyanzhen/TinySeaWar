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

The runtime registry currently contains 48 character definitions. The 24 phase-one
characters remain split between `prototype_*.json` and `expanded_roster_*.json`;
the 24 phase-two characters live in `phase2_*.json`. All definitions are loaded
into one registry and use globally unique IDs. The four playable levels currently
cover only the 24 phase-one characters: `level.prototype_11v11` uses 22 unique
characters, while the 1v1 roster supplies the remaining Warspite and Bismarck.
Phase-two definitions are validated but are not yet included in a playable level.

`tools/data/build_expanded_roster_data.mjs` regenerates the expanded weapon and
skill JSON from the reviewed roster values. Ship and level placement data remain
hand-authored.

`tools/data/build_phase2_roster_data.py` regenerates the phase-two ship, weapon,
skill, and weapon-visual JSON. Phase-two art completion and playable-level coverage
are tracked separately in `docs/00_project_status.md`.

To add a surface character:

1. Add or reuse weapon, projectile, formula, and skill definitions.
2. Add one ship definition using only stable IDs.
3. Add the ship to a level fleet with a battle-unique `entity_id`.
4. Run `godot --headless --path . --script res://scripts/tests/test_runner.gd`.

The registry rejects duplicate IDs, missing references, unsupported enums,
invalid ranges, non-positive core values, and invalid flagship counts before a
battle can start.

Runtime data keeps design baselines and effective values side by side. Current
battlefield tuning uses:

- weapon `range == base_range * 1.5`;
- weapon `projectile_speed == base_projectile_speed * 0.5`;
- projectile and aircraft definition `speed == base_speed * 0.5`;
- ship `detection_range` and `concealment_distance` at 1.5x their `base_*`
  fields;
- skill `cast_range == base_cast_range * 1.5` for non-self skills;
- ship `speed` and `turn_speed` at 0.5x their `base_*` fields.

Minimum weapon range is not scaled.
