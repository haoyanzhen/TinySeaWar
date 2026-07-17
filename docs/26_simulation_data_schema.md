# 战斗模拟实验数据契约

## 1. 文档功能与边界

本文是无图形战斗实验清单的数据形状真源。平台执行、确定性和产物职责见 `docs/19_battle_simulator_design.md`；样本、阈值、授权和结论边界只见 `docs/36_balance_testing_design.md`。

实验配置不得进入可玩关卡菜单、修改正式 Definition 或写入玩家进度。

## 2. SimulationExperiment

```text
schema_version
experiment_id, description
simulation_kind
authorization?
player_policy_id, enemy_policy_id
ai_profile_id?
ai_mode_locks?
tick_seconds, maximum_ticks
side_swap
seed_plan
win_rate_evaluation?
scenarios[]
output_directory
```

- `schema_version` 为正整数，不兼容版本拒绝加载。
- `simulation_kind`：`FullBattleSimulation | RuleRegression | LevelWinRateEvaluation`。
- `tick_seconds>0`、`maximum_ticks>0`；达到最大 Tick 记录为 `GuardLimit`，不得伪装成关卡超时。
- 双方策略分别声明；旧单一 `policy_id` 只允许由迁移器转换。
- `authorization` 只记录人工授权事实，不由模拟器自行扩大样本。

## 3. SimulationPolicy 引用

首轮有限策略 ID：

```text
SessionAutonomy
BaselineAutopilot
LatestRuntimeAI
TutorialT01Deterministic
```

新增策略必须通过普通命令驱动 BattleSession，不得直接改 HP、位置、装填、侦查或目标状态。教学确定性策略只能执行关卡要求的合法操作。

## 4. SeedPlan

```text
type # ExplicitList | SequentialRange
values[]? # ExplicitList
start?, count? # SequentialRange
```

- 实际展开种子必须稳定、可记录且符合实验种类要求。
- 正式报告保存实际种子列表，不只保存数量。

## 5. SimulationScenario

```text
scenario_id
level_definition_id
seeds[]?
maximum_ticks?
```

- `scenario_id` 在实验内唯一。
- `level_definition_id` 引用 `docs/23_level_progress_data_schema.md` 的正式关卡。
- 场景级种子覆盖必须满足实验级样本与唯一性校验。

## 6. SideSwap

`side_swap=true` 时，同一场景和种子展开 `original` 与 `swapped`：交换双方阵容和出生侧，同时保留阵容内部顺序、角色与旗舰归属。关卡语义不允许交换时必须为 `false` 并在报告元数据中说明。

## 7. LevelWinRateEvaluation

```text
settlement_source # BattleStatisticsReport
target_player_win_rate
tolerance
minimum_p10_duration?
require_engagement_unlocked?
required_objective_action_ids[]?
maximum_enemy_damage_before_engagement?
maximum_policy_command_rejections?
```

- 仅 `simulation_kind=LevelWinRateEvaluation` 可声明。
- 按 `docs/36_balance_testing_design.md` 使用恰好 20 个互不重复种子，并要求 `side_swap=false`。
- `target_player_win_rate` 与 `tolerance` 位于 `[0,1]`；20 场都必须形成有效战斗统计后才能判定门禁。
- 教学验收可额外声明最短 P10 时长、交战解锁、必需目标动作、交战前敌方伤害和策略命令拒绝上限；这些字段只检查报告事实，不修改战斗规则。
- 侧别公平性另建非胜率结算实验，不复用本实验种子制造配对局。

## 8. 输出与未来扩展

- `output_directory` 必须指向允许写入的实验产物目录，不得覆盖正式数据。
- 结果至少能关联实验 ID、场景、策略、AI Profile、种子、侧别、配置指纹和代码版本。
- Definition 覆盖、临时舰队、Acceptance Profile 和并行恢复字段只有在隔离校验实现后才能加入正式契约；当前完成度只见 `docs/00_project_status.md`。
