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

`LatestRuntimeAI` 对清单声明的双方阵营授予仅限本次实验的完整运行时 AI 控制。执行器必须在首个 Tick 前初始化双方现有单位，并把相同授权应用到之后实际生成的接替增援；初始化至少覆盖控制权、自动航行、主副武器、自动技能和战略模式。该策略授权不得写回正式关卡或把正常玩家的 `X/C/V` 受限辅助提升为完整 AI。

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
required_objective_action_sequence[]?
maximum_enemy_damage_before_engagement?
maximum_policy_command_rejections?
maximum_behavior_anomalies?
```

- 仅 `simulation_kind=LevelWinRateEvaluation` 可声明。
- 按 `docs/36_balance_testing_design.md` 使用恰好 20 个互不重复种子，并要求 `side_swap=false`。
- `target_player_win_rate` 与 `tolerance` 位于 `[0,1]`；20 场都必须形成有效战斗统计后才能判定门禁。
- 教学验收可额外声明最短 P10 时长、交战解锁、必需目标动作、完整动作顺序、交战前敌方伤害、策略命令拒绝上限和行为异常上限；这些字段只检查每局报告事实并形成聚合门禁，不修改战斗规则。
- 教学关制作完成后必须为设计路线建立三份独立 `LevelWinRateEvaluation` 清单。三份清单各使用 20 个种子，彼此种子集合不相交，并使用不同 `experiment_id` 与 `output_directory`。每份都要求 `target_player_win_rate=1.0`、`tolerance=0.0`、`maximum_policy_command_rejections=0`、`maximum_behavior_anomalies=0`，并声明关卡要求的 `required_objective_action_ids` 与 `required_objective_action_sequence`。
- 三份实验必须各自达到 20/20 有效、100% 完成、动作与路线证据 100% 符合、零技术上限、零寻路卡死/路线不可用、零策略拒绝和零禁止阶段伤害。任一份或任一单局异常都会使三份证据整体失效；修复后必须用三份新实验重新验收，不能对三轮取平均。
- 侧别公平性另建非胜率结算实验，不复用本实验种子制造配对局。

## 8. 输出与未来扩展

- `output_directory` 必须指向允许写入的实验产物目录，不得覆盖正式数据。
- 结果至少能关联实验 ID、场景、策略、AI Profile、种子、侧别、配置指纹和代码版本。
- 每局 `finish_reason` 保存具体终局原因码，`finish_reason_summary` 保存由实际触发条件生成的人类可读说明，`finish_reason_context` 保存触发单位、阈值或计数等结构化事实；挑战取消不得以整关静态失败文案代替本局事实。
- 每局 `submarine_ai{unit_id}` 为潜艇长期诊断对象，至少包含：

```text
definition_id, display_name, faction_id, lineup_id?
decision_samples, visible_target_samples
selected_target_samples, eligible_target_samples, weapon_evaluation_samples
target_rejections_by_reason{}
ready_weapon_samples, legal_solution_samples
scored_window_samples, window_score_total, window_score_max
window_threshold_total, outcomes_by_reason{}, rejections_by_reason{}
friendly_risk_ignored_samples, friendly_risk_observed_samples
friendly_risk_observed_max
fire_commitments, weapon_fires, fires_by_phase{}
first_fire_tick, first_fire_time
first_fire_weapon_state_instance_id, first_fire_phase
selected_weapon_instances{}
opportunities_observed, opportunities_expired
opportunity_expiry_reasons{}, opportunity_forced_samples
attack_run_timeouts
phase_transitions{}, phase_reasons{}, phase_dwell_seconds{}
depth_dwell_seconds{}, depth_changes, depth_changes_by_target{}
forced_surfaces, depth_requests, depth_requests_by_target{}
depth_request_holds_by_reason{}
oxygen_dwell_seconds{}, oxygen_min_ratio, oxygen_max_ratio
normal_full_cycles, submerged_launch_cycles
incomplete_attack_cycles, recovery_self_defense_fires
cycle_examples[]
zero_fire_classification
```

  - `visible_target_samples` 统计阵营真实观察中存在可见敌人的决策样本，与阶段是否执行武器评估无关；`selected_target_samples`、`eligible_target_samples`、`weapon_evaluation_samples` 分别统计已选中目标、最近目标筛选存在合格目标、实际执行武器评估的样本，均为非负整数，默认 `0`。`target_rejections_by_reason` 累加样本中最近一次筛选的拒绝计数，默认 `{}`，不是独立目标数量。无合格目标和阶段未评估分别允许分类为 `SUBMARINE_NO_ELIGIBLE_TARGET`、`SUBMARINE_PHASE_HELD`，不得伪报无可见目标。

  - `zero_fire_classification` 至少区分 `FIRED | SUBMARINE_NO_FIRE_DECISIONS | SUBMARINE_NO_VISIBLE_TARGET | SUBMARINE_NO_READY_WEAPON | SUBMARINE_NO_LEGAL_SOLUTION | SUBMARINE_ELIGIBLE_WINDOW_NO_FIRE | SUBMARINE_COMMITTED_WITHOUT_FIRE | SUBMARINE_DISCIPLINE_HELD | SUBMARINE_ZERO_FIRE_UNCLASSIFIED`。
  - 潜艇窗口暂不使用友军风险评分：`friendly_risk_ignored_samples` 记录显式归零的评分样本，`friendly_risk_observed_samples/max` 只保留同一发射器雷道的实际观察事实，不能反向参与本轮开火判定。
  - 聚合结果的 `submarine_ai` 按总体和 `lineup_id|definition_id` 汇总上述计数、原因、阶段/深度/氧气驻留、完整循环、超时和开火样本率；CSV/Markdown 派生产物固定为 `submarine_ai.csv` 与 `submarine_ai.md`。
- Definition 覆盖、临时舰队、Acceptance Profile 和并行恢复字段只有在隔离校验实现后才能加入正式契约；当前完成度只见 `docs/00_project_status.md`。

航空迁移诊断的 recorder summary 增加 `aviation`：`waves_launched/waves_completed/anti_air_rounds/waves_destroyed/payloads_released: int`、`aircraft_damage: float`。飞机HP损失单独统计，不混入逐舰对舰伤害；炸弹/鱼雷仍由一次 `AttackResolved` 计入原攻击分类。性能明细增加 `aviation_runtime_usec`，与表现帧成本分开。

### 挑战诊断补充（2026-09-30）

每局公共 `navigation` 统计不限于完整AI：`event_counts`计入Navigation事件、TrajectoryPlanFailed、UnitTerrainCollision及UnitTideAccessRestricted；`failures_by_reason`按拒绝原因细分。`separation_distance`为每次权威分离实际执行距离之和，`separation_applied/rejected`区分允许与拒绝的单舰处理次数，均不是独立事故数。聚合的`navigation_all_attempts/navigation_invalid_attempts`分别保留全部尝试与无效局数值，不能因未正常结算漏计。

`ai_behavior.navigation_events`同时保留导航报警、水域拒绝、地形碰撞、无安全航迹事实。恢复取消含duration、attempts、stage，沉没以UNIT_SUNK取消；ARRIVED完成须在权威分离后的真实位置满足终点容差。终局尚未结束的恢复由测量工具记录为截尾，不能补记成功。高频分离事件只做数值汇总，不追加到该事实数组。

每局 `fleet_cost` 按阵营记录 initial / reserve / total / entered；预备 Cost 不冒充已经入场的作战规模。`ai_behavior.route_unavailable` 同时统计 AIRouteUnavailable 与 NavigationRequestFailed，并按 reason_code 与 unit_id 分类。`navigation_events` 保留请求失败和恢复事件的时间及结构化上下文；其中 `elapsed_usec` 及 `route_profile` 的 `*_usec` 是机器耗时诊断，不属于确定性战斗事实，复现比对必须排除这些计时字段。聚合的 `ai_behavior` 仍仅针对 Finished 有效局；`ai_behavior_all_attempts` / `ai_behavior_invalid_attempts` 分别递归汇总全部尝试和无效局数值，包括原因与单位分项。数组事件留在每局 runs.jsonl，不纳入胜率分母。技术无效不得通过漏聚合隐藏。

十个 `level_{m01..l05}_win_rate_20.json` 为独立正式清单，固定20种子、不换边、双方同档 LatestRuntimeAI 和默认航空规则。三种子行为核查用独立 FullBattleSimulation 副本，不能输出正式平衡通过结论。
