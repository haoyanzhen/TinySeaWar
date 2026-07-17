---
name: tiny-sea-war-build-tutorial-level
description: Design, implement, integrate, and validate TinySeaWar T-type tutorial battle levels (T-01 through T-08). Use when creating or revising a tutorial's teaching goals, required player actions, staged enemy behavior, ability restrictions, objective data, HUD/world guidance, menu/reward integration, deterministic tutorial policy, or 20-seed win-rate acceptance reports.
---

# Build a TinySeaWar T-Type Tutorial Level

Turn one teaching concept into a truthful runtime lesson: the player performs observable actions, the encounter unfolds naturally, the same public combat rules remain authoritative, and a deterministic legal solution succeeds in all 20 formal samples.

## Establish the Baseline

1. Run `git status --short` and preserve unrelated work.
2. Read these sources before editing:
   - `docs/00_project_status.md`
   - the target T-row and sections 2, 3, 4.2, and 5 of `docs/15_battle_level_design.md`
   - `docs/technical/t02_level_objective_reinforcement_progress_solution.md`
   - the level/objective and simulation sections of `docs/20_data_schema_design.md`
   - `docs/11_game_operation_design.md` for any taught input or toggle
   - `docs/34_implementation_map.md`
   - `docs/36_balance_testing_design.md`
3. Inspect the closest existing lesson as the runtime reference. `T-01` remains the
   navigation/selection vertical slice; `T-02`--`T-04` cover command-triggered
   unlocks and first-contact staging; `T-05`--`T-08` cover combat-event facts,
   shared contact, and multi-unit focus orders:
   - `data/levels/formal_level_01.json`
   - `data/levels/formal_tutorial_levels_02_04.json` and
     `data/levels/formal_tutorial_levels_05_08.json`
   - `data/objectives/level_objectives.json`
   - `scripts/domain/services/level_objective_service.gd`
   - `scripts/application/battle_session.gd`
   - `scripts/presentation/battle/battle_hud.gd`
   - `scripts/presentation/battle/prototype_battle.gd`
   - `scripts/tests/level_objective_runtime_test.gd`
   - the nearest `data/simulations/experiments/level_t0N_win_rate_20.json`
4. Use `rg` to find every reference to the new level ID, objective ID, display ID, reward, and menu row. Do not assume T-01 hard-coded lists automatically generalize.

## Define the Lesson Contract

Write the contract before code or coordinates. Record:

- one primary teaching outcome and only the prerequisite concepts needed to reach it;
- the exact observable actions the player must perform;
- the victory objective and the player's flagship-survival requirement;
- the automatic abilities, manual abilities, and toggles the player must understand;
- the abilities initially unavailable, their visible explanation, and the event that unlocks each one;
- the enemy's natural staging intent before engagement and its behavior after engagement;
- the map/weather concept introduced by this lesson;
- the first-completion ship unlock, if T-01 through T-06.

Represent player actions as structured facts such as selection, camera follow, waypoint placement, ammo switch, manual fire, skill cast, contact creation, torpedo hit, shared-target gun hit, or group command. A combat-event fact must identify the required player source and, when the lesson needs it, the intended target/category; do not accept an unrelated hit merely because it uses the same broad weapon class. Never infer completion from HUD state or prose.

For lessons that require a minimum surviving player fleet, make that threshold an
explicit objective condition and validate both the success boundary and the
one-unit-below failure boundary. Do not approximate it by protecting every unit.

Keep every tutorial victory condition dependent on the player's flagship remaining alive. Keep T-01 through T-08 open by default. Do not persist tutorial completion; persist only the idempotent ship unlock when applicable.

## Design Natural Staging and Restrictions

Use positions, reviewed routes, contact state, weapon windows, and explicit tutorial stages to create a readable encounter.

- Let an enemy sail to a reviewed training or patrol position through the normal navigation pipeline.
- Advance a stage on meaningful facts: required action, reviewed waypoint arrival, first contact, legal weapon window, hit, or ordered objective completion.
- Lock only abilities that would bypass the lesson. Show every lock and the current next action in the HUD.
- Restore the intended assist/automatic capability at the authored stage transition.
- Keep enemy movement, detection, collision, weapons, damage, and sinking on public runtime rules.

Do not use a frozen target, invulnerability, HP locking, hidden damage/accuracy changes, arbitrary timers, teleports, direct sink injection, or simulation-only permissions to make the lesson pass. Do not change shared ship or weapon definitions for a tutorial.

## Implement Through the Runtime Layers

1. Add or extend the formal `LevelDefinition` and `ObjectiveSetDefinition` under `data/levels/` and `data/objectives/`.
2. Add configuration validation for every new field, enum, unit reference, action ID, waypoint, skill, weapon group, event fact, survival threshold, or stage transition. Add both valid and invalid test cases when extending an objective kind or action whitelist.
3. Keep objective state and condition evaluation in Domain services. Read battle facts and events; do not read scene nodes.
4. Coordinate control authority, AI staging, commands, stage transitions, terminal results, and technical limits in Application code.
5. Make Presentation report real player actions and render:
   - objective title and progress;
   - one current instruction;
   - current ability restrictions and unlocks;
   - world-space waypoint/target markers when spatial guidance is required;
   - completion or cancellation feedback.
6. Register the level in `scripts/presentation/menu/main_menu.gd`, `scripts/presentation/ui_text.gd`, and any data-driven selection path. A multi-unit teaching command must be expressible through normal player input as well as through the deterministic policy.
7. Register the reward in `scripts/application/game_flow.gd`; verify `progress_save_store.gd` remains idempotent and never stores an in-battle snapshot.
8. Update `docs/20_data_schema_design.md` whenever the runtime data contract changes.

Treat a formal level's ordinary `time_limit` as a technical guard unless the tutorial explicitly teaches a time limit. A technical guard result is an invalid sample, not a winner chosen by remaining HP.

## Build the Deterministic Correct Solution

Add a tutorial-specific simulation policy and register it in both the experiment loader allowlist and `SimulationRunner`. It must perform only the required legal actions in their intended order. For an event-fact lesson, it must wait for the same public contact, range, reload and fire-arc conditions as a player; it must not inject the fact directly. After the lesson enables normal assist or automatic combat, let those runtime capabilities finish the battle. Do not add privileged damage, direct state mutation, or bypasses unavailable to a real player.

Create a `LevelWinRateEvaluation` manifest modeled on `level_t01_win_rate_20.json`:

- exactly 20 planned battles;
- 20 distinct seeds;
- `side_swap=false`;
- target win rate `1.0`, tolerance `0.0`;
- `settlement_source: BattleStatisticsReport`;
- an output directory under `artifacts/simulations/`.

Require P10 completion time of at least 10 seconds. If a sample hits a guard/technical limit, fix the lesson or runtime behavior; do not count it as a win.

## Validate in Increasing Scope

Run the smallest relevant checks first:

```bash
godot --headless --path . --script scripts/tests/level_objective_runtime_test.gd
godot --headless --path . --script scripts/tests/battle_simulator_test.gd
godot --headless --path . --quit-after 2
```

Run the formal experiment only after the functional path passes:

```bash
godot --headless --path . --script tools/simulation/run_experiment.gd -- \
  data/simulations/experiments/<t-level-win-rate-manifest>.json
```

Require all of the following:

- 20/20 valid battles and 100% report win rate;
- battle statistics plus `unit_damage.md` and `unit_damage.csv`;
- no enemy damage while the authored lesson says it cannot attack;
- no command rejection caused by the deterministic policy;
- no path-stuck, technical-limit, or hidden-action workaround;
- all required actions present in the final objective snapshot;
- each required combat/contact/group-command fact has the required source, target and category in the event evidence;
- any declared minimum-survivor threshold is met at completion and is rejected when it is no longer recoverable;
- manual play confirms instruction timing, marker readability, control locks, automatic abilities, and victory explanation.

Run broader tests proportional to changed systems. Record unrelated pre-existing failures separately instead of hiding them.

## Report Completion Truthfully

Update `docs/15_battle_level_design.md`, `docs/00_project_status.md`, `docs/23_level_progress_data_schema.md` (when the objective contract changes), and `docs/34_implementation_map.md` with separate status for:

- formal data and load validation;
- runtime objective and terminal result;
- menu, HUD, markers, and reward;
- automated functional checks;
- 20-seed battle and damage reports;
- manual play/readability review.

Do not call the tutorial complete when only JSON exists, when the deterministic policy uses privileged behavior, or while manual readability remains unreviewed.
