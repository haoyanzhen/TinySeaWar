---
name: tiny-sea-war-build-s-challenge-level
description: Design, implement, integrate, balance, and validate TinySeaWar S-type small challenge battle levels (S-01 through S-05). Use when creating or revising a 3v3 challenge's incremental mission, cancellation conditions, fixed fleets and total Cost, map deployment, reinforcement schedule, progression reward, runtime objective settlement, or formal 20-seed battle and damage reports.
---

# Build a TinySeaWar S-Type Challenge Level

Turn one S-row into a complete 3v3 challenge whose mission is the only victory condition, whose cancellation rules are explicit, and whose target difficulty is supported by a complete 20-seed battle-statistics report rather than selected runs.

## Establish the Baseline

1. Run `git status --short` and preserve unrelated work.
2. Read these sources before editing:
   - `docs/00_project_status.md`
   - sections 2, 3, 4, and 6 of `docs/15_battle_level_design.md`
   - `docs/technical/t02_level_objective_reinforcement_progress_solution.md`
   - `docs/14_character_balance_design.md` for Cost and roles
   - `docs/16_enemy_ai_behavior_design.md` for legal AI behavior
   - the level/objective and simulation sections of `docs/20_data_schema_design.md`
   - `docs/34_implementation_map.md`
   - `docs/36_balance_testing_design.md`
3. Inspect S-01 as the current vertical-slice reference:
   - `data/levels/formal_level_01.json`
   - `data/objectives/level_objectives.json`
   - `scripts/domain/services/level_objective_service.gd`
   - `scripts/application/battle_session.gd`
   - `scripts/presentation/battle/battle_hud.gd`
   - `scripts/tests/level_objective_runtime_test.gd`
   - `data/simulations/experiments/level_s01_win_rate_20.json`
4. Use `rg` to locate menu, display text, progress order, unlock reward, objective, reinforcement, and test references for the target S ID.

## Define the Challenge Contract

Record the following before implementation:

- the fixed player and enemy fleets, flagship, initial Cost, reserve Cost, and total Cost;
- the reviewed map, weather/time palette, terrain/navigation IDs, spawn formation, headings, and any local environment;
- an incremental ordered/all/any task expressed with whitelisted battle facts;
- immediate success behavior when the task completes;
- every irreversible cancellation condition;
- the same AI difficulty/profile for both sides in batch evaluation;
- the chapter target win rate and tolerance;
- the first-completion reward and next S-level unlock.

Use these S targets:

| Level | Target | Tolerance |
| --- | ---: | ---: |
| S-01 | 60% | ±5 points |
| S-02 | 45% | ±5 points |
| S-03 | 30% | ±5 points |
| S-04 | 20% | ±5 points |
| S-05 | 10% | ±3 points |

Finish the battle immediately when the mission completes. Do not require cleanup after success. Make enemy flagship sinking decisive only when the mission explicitly requires it.

Do not add an ordinary mission timer. Fail on a timer only when the level name, description, objective data, and HUD explicitly emphasize a time limit. Treat the runtime safety limit as a technical invalid sample, never as an HP-based winner.

## Build Fleets, Deployment, and Reinforcements

Use role interaction, Cost, geometry, environment, objectives, and reinforcement timing to shape difficulty.

- Keep S battles at no more than three simultaneously active ships per side.
- Count every reserve reinforcement in the side's total Cost.
- Validate every initial and reinforcement spawn against boundary, terrain, draft, separation, and navigation clearance.
- Register reinforcement members at battle creation, but keep them outside visibility, loss counts, and `units_by_id` until spawned.
- Spawn deterministically by earliest time, prerequisite, concurrent cap, wave ID, and reviewed spawn-point order.
- Cancel pending waves after battle end and prohibit a reserve flagship in the first implementation.

S-04 and S-05 require the reinforcement runtime described in `t02`; if that runtime is still missing, implement and test it or report the level blocked/partial. Do not silently remove the authored reinforcement to make the level runnable.

Never tune a challenge by modifying shared HP, damage, reload, range, detection, accuracy, or concealment values. Do not give one side hidden observation or AI quality advantages.

## Implement Through the Runtime Layers

1. Add the formal level and objective data under `data/levels/` and `data/objectives/`.
2. Add loader validation for new objective conditions, unit references, ordered steps, protection targets, reinforcement waves, Cost totals, and spawn points.
3. Keep objective evaluation in Domain code and consume only battle state/events.
4. Coordinate reinforcement scheduling, unique terminal results, technical limits, and trusted progress transactions in Application code.
5. Render task title, completed steps, current step, protection conditions, cancellation reason, and final result in Presentation.
6. Register the S row in `scripts/presentation/menu/main_menu.gd` and `scripts/presentation/ui_text.gd`.
7. Register chapter order and first-clear reward in `scripts/application/game_flow.gd` and validate `scripts/infrastructure/persistence/progress_save_store.gd`.
8. Unlock the next S level only after a trusted formal challenge victory. Keep failure, simulation, test, debug, custom battle, and override sessions unable to write progress.
9. Update `docs/20_data_schema_design.md` for every data-contract change.

## Tune With Controlled Evidence

Start from the authored fleet and map. If the challenge misses its target, adjust in this order:

1. mission completion or cancellation conditions;
2. reviewed spawn distance, heading, and formation;
3. reinforcement timing and entry point;
4. fleet composition and total Cost;
5. the same AI profile for both sides.

Change one declared factor at a time and retain the prior report as a tuning record. Watch for discontinuities: a tiny spawn change that causes a large win-rate jump is a risk, not evidence of robust balance.

Reject a statistically passing layout when its report shows pathological play, including:

- a carrier or other authored role contributing zero damage/utility across the batch;
- repeated path-stuck or long-idle behavior;
- high command-rejection counts;
- technical-limit samples;
- one unit or one spawn threshold solely deciding every result;
- victory driven by an AI defect, unavailable player behavior, or hidden information.

## Run the Formal 20-Battle Gate

Create a `LevelWinRateEvaluation` manifest modeled on `level_s01_win_rate_20.json`:

- exactly 20 planned battles and 20 distinct seeds;
- `side_swap=false` for this settlement experiment;
- `LatestRuntimeAI` on both factions;
- the same authored AI profile on both factions;
- the S-level target and tolerance from the table above;
- `settlement_source: BattleStatisticsReport`;
- an output directory under `artifacts/simulations/`.

Run:

```bash
godot --headless --path . --script scripts/tests/level_objective_runtime_test.gd
godot --headless --path . --script scripts/tests/battle_simulator_test.gd
godot --headless --path . --script tools/simulation/run_experiment.gd -- \
  data/simulations/experiments/<s-level-win-rate-manifest>.json
godot --headless --path . --quit-after 2
```

Settle only from the aggregate battle-statistics report. Require 20/20 valid battles and a win rate inside the target interval. Use `runs.jsonl`, `unit_damage.md`, and `unit_damage.csv` to explain the result, never to select which battles count.

Review at least:

- completion/cancellation counts and reasons;
- duration distribution, first contact, first fire, and flagship sinking time;
- per-ship and per-category damage, contribution, and damage taken;
- route/path anomalies, passive time, skill holds, command rejections, and technical limits;
- initial/reserve/total/entered Cost when reinforcements exist.

Run a separate non-settlement side-swap experiment when evaluating side fairness; do not reuse paired seeds inside the formal 20-battle settlement gate.

## Validate Progress and Manual Play

Add focused tests for success, every cancellation path, simultaneous terminal events, objective ordering, technical-limit invalidation, reinforcement waiting/spawn/cancel order, reward idempotency, and next-level unlock.

Manually verify that:

- the mission and cancellation conditions are understandable before contact;
- terrain and environment boundaries are visible;
- the intended fleet roles participate;
- the level remains playable by a human rather than only by the batch AI;
- success ends immediately and failure explains the cancelled condition.

## Report Completion Truthfully

Update `docs/15_battle_level_design.md`, `docs/00_project_status.md`, and `docs/34_implementation_map.md` with separate status for data, runtime, reinforcement, menu/progress, automated checks, 20-battle reports, and manual play.

State any zero-contribution role, spawn sensitivity, AI anomaly, technical sample, missing reinforcement runtime, or missing manual review. A passing target win rate alone does not make an S level complete.
