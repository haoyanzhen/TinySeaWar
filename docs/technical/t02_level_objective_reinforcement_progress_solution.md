# 关卡目标、接替增援与进度存档技术契约

> 状态：设计完成；T-01/S-01 目标、结算、正式数据、专项测试与 20 场实验已实施，接替增援及其余 21 关待实施。

## 1. 边界

本契约为 `docs/15_battle_level_design.md` 的 23 个教学/挑战关定义声明式目标、确定性增援和幂等长期进度。Battle Domain 拥有局内事实、目标状态和唯一结果；Application 调度增援并把可信结算转换为进度事务；Infrastructure 验证 Definition 并原子写存档；Presentation 只展示状态。

## 2. 关卡目标

```text
ObjectiveSetDefinition
  id
  completion: ConditionGroupDefinition
  failure: ConditionGroupDefinition?
  hud_title_key
  hud_description_key
  progress_visible

ConditionGroupDefinition
  operator: All | Any | Ordered
  conditions: ObjectiveConditionDefinition[]

ObjectiveConditionDefinition
  id
  type
  params
```

配置只能组合白名单原子条件，不接受表达式、脚本路径或回调名：

| `type` | 语义 |
|---|---|
| `BattleOutcome` | 基础战斗结果为 `PlayerVictory`。 |
| `UnitAlive` / `UnitHpRatio` | 指定单位存活，或结算时 HP 比例高于阈值。 |
| `FactionSurvivorCount` / `FactionLossCount` | 阵营存活/损失数；损失包含已入场增援，不包含预备队。 |
| `UnitSunk` / `TaggedUnitSunkCount` | 指定单位或指定标签单位沉没数。 |
| `BattleTimeLimit` | 仅供明确强调限时的任务使用；到时未完成立即失败。普通挑战不配置。 |
| `EventCount` | 统计白名单领域事件和结构化过滤，用于教学操作。 |
| `WaypointSequence` | 指定单位按顺序进入审核航点区。 |
| `ContactThenHit` | 指定侦察者建立阵营接触，随后指定攻击者命中该共享目标。 |

`Ordered` 按子目标首次完成 Tick 推进且不回退。条件只读 `BattleState` 与已发生领域事件，不读 HUD 或隐藏敌人实时位置。每 Tick 在伤害、沉没、接触和任务取消事实产生后评估一次。挑战关的任务完成即 `PlayerVictory` 并立即结束；保护目标沉没、顺序被破坏或明确限时结束等不可恢复条件使任务取消并立即 `PlayerDefeat`。敌旗舰沉没只有在任务要求时才有结算意义。没有 `objective_set_id` 的原型关保持现有旗舰/超时兼容路径。最终只产生一个 `LevelFinished(level_id, result, reason_code, objective_snapshot, elapsed_time, tick_index)`。

### 2.1 二十三关目标映射

| 关卡 | `objective_set_id` | 完成契约 |
|---|---|---|
| T-01 | `objective.t01_navigation` | 两航点顺序 + 胜利 + 己旗舰存活 |
| T-02 | `objective.t02_gunnery` | 手动主炮开火≥1 + 切弹≥1 + 胜利 |
| T-03 | `objective.t03_skill` | 指定技能成功施放≥1 + 胜利 |
| T-04 | `objective.t04_armor` | 胜利 + 厌战存活 |
| T-05 | `objective.t05_torpedo` | 鱼雷命中≥1 + 胜利 + 两驱逐均存活 |
| T-06 | `objective.t06_carrier_hunt` | 百眼巨人沉没 + 己方存活≥2 + 己旗舰存活 |
| T-07 | `objective.t07_shared_contact` | 沃德建立接触 -> 衣阿华命中共享目标 + 胜利 |
| T-08 | `objective.t08_command` | 双舰集火指令≥1 + 胜利 + 己方存活≥2 |
| S-01 | `objective.s01_flagship` | 敌旗舰沉没；己旗舰沉没则取消 |
| S-02 | `objective.s02_escort` | 胜利 + 重庆/雪风任一存活 |
| S-03 | `objective.s03_carrier_first` | 百眼巨人沉没 -> 俾斯麦沉没 |
| S-04 | `objective.s04_ambush` | 衣阿华沉没 + 胡德 HP>30%；条件不可满足时取消 |
| S-05 | `objective.s05_wolfpack` | 敌方损失≥3 + 敌旗舰沉没；己旗舰沉没则取消 |
| M-01 | `objective.m01_harbor` | 敌旗舰沉没；己旗舰沉没则取消 |
| M-02 | `objective.m02_carrier_escort` | 百眼巨人沉没 -> 俾斯麦沉没 + 凤翔存活 |
| M-03 | `objective.m03_flanks` | 愤怒与鞍山沉没 -> 衣阿华沉没；顺序被破坏则取消 |
| M-04 | `objective.m04_storm` | 敌旗舰沉没 + 己方损失≤2；第 3 艘沉没则取消 |
| M-05 | `objective.m05_blockade` | 衣阿华沉没 + 敌方损失≥4；己旗舰沉没则取消 |
| L-01 | `objective.l01_deployment` | 敌旗舰沉没；己旗舰沉没则取消 |
| L-02 | `objective.l02_air_corridor` | 两艘非旗舰敌航母沉没 -> 企业沉没 + 百眼巨人存活 |
| L-03 | `objective.l03_gun_lane` | 雪风与海狮均沉没 -> 大和沉没 |
| L-04 | `objective.l04_encirclement` | 衣阿华沉没；胡德/百眼巨人任一沉没则取消 |
| L-05 | `objective.l05_finale` | 敌方损失≥8 + 大和沉没；己旗舰沉没则取消 |

## 3. 激活与接替增援

教学使用 `tutorial_stage_plan` 自然组织遭遇：由航点到达、首次接触、玩家完成前置操作或进入合法武器窗口推进阶段，并通过出生距离、审核待机航点、侦查状态和敌方交战意图让战斗逐步展开。阶段可以限制玩家单位选择、自动航行、主/副武器自动开火、弹药、主要武器和技能，也可限制敌方主动攻击策略；每项限制必须在 HUD 明示，并在讲解后开放。T-01 的沃德在交战解锁前沿公共航行管线驶向训练待机区，解锁后恢复正式 AI，不使用静止靶、无敌、锁血或修改伤害/命中规则。

```text
ReinforcementWaveDefinition
  wave_id, faction_id, earliest_time, concurrent_unit_cap
  prerequisite_sunk_unit_ids[], spawn_point_ids[], members[]

ReinforcementWaveState
  wave_id
  status: Pending | Spawned | Cancelled
  spawned_at_tick
  selected_spawn_point_ids[]
```

每波创建战斗时就验证舰船引用、唯一实体 ID、阵营、出生点和 AI 覆盖，但触发前不进入 `units_by_id`、不占视野、不算损失。关卡双方的“全部 Cost”必须包含所有初始单位与预备增援，平衡报告同时输出初始 Cost、预备 Cost、全部 Cost 和实际入场 Cost。达到最早时间且阵营在场数小于上限时，按 `wave_id` 顺序尝试；无空位保持 `Pending`。按候选出生点顺序选首个未占用的审核点，全部占用则等待，禁止全图随机搜点。一 Tick 最多一波，产生 `ReinforcementWaveSpawned` 和逐舰 `UnitSpawned`。战斗结束后取消待入场波次。首轮禁止预备旗舰。

| 关卡 | 波次 | 触发 | 单位 | 点 |
|---|---|---:|---|---|
| S-04 | `wave.s04.01` | 120s + 空位 | 沃德 | RN |
| S-05 | `wave.s05.01` | 90s + 空位 | 愤怒 | RS |
| M-04 | `wave.m04.01` | 150s + 空位 | 沃德 | RN |
| M-05 | `wave.m05.01` | 120s + 空位 | 胜利 | RS |
| L-04 | `wave.l04.01` | 210s + 空位 | 愤怒 | RN |
| L-05 | `wave.l05.01` | 180s + 空位 | 胡德 | RN |
| L-05 | `wave.l05.02` | 300s + 空位 | 海狮 | RS |

## 4. 进度存档

长期进度不进入 `BattleState`。存档只保存稳定 ID 与已获得事实，菜单每次根据完成事实和当前规则重算可用关卡，不存派生的 `unlocked_level_ids`。

```text
PlayerProgressSave
  schema_version, profile_id, revision, updated_at_utc
  completed_challenge_level_ids[]
  unlocked_ship_ids[]
```

T-01～T-08 默认全部开放且完成状态不写存档。S/M/L 三个挑战分类默认分别开放第一关；每个分类只根据 `completed_challenge_level_ids` 顺序开放同分类下一关，分类之间互不作为前置。舰船解锁按 `docs/15_battle_level_design.md`：教学奖励第一期 6 艘 1 级舰，其余由挑战逐关首通提供。

挑战首通处理为幂等事务：在内存副本同时合并挑战成功状态和舰船解锁。存档使用同目录正式槽、候选槽与恢复槽；候选槽带递增 `revision` 和 SHA-256 校验，写后必须重新读取验证，再将旧正式槽保留为恢复槽并提升候选槽。启动时从三个槽中选择校验有效且 revision 最高者，因此切换中断时仍至少保留一个可恢复版本。教学完成只合并对应舰船解锁，不写教学完成记录。重复结算、崩溃恢复和重玩不重复解锁。未知 ID 保留供前向兼容，但不产生当前解锁。

只有正式菜单启动、未使用 Definition 覆盖且产生 `PlayerVictory` 的教学/挑战 `LevelFinished` 能写入相应舰船解锁；只有挑战胜利额外写 `completed_challenge_level_ids`。模拟器、测试、调试跳关、自定义战斗、失败和中途退出都不写。存档不保存、恢复或保护任何局内战斗状态。

## 5. 验收

- 加载拒绝未知条件/参数、重复 ID、缺失单位/航点/技能引用、非法比较符与预备旗舰。
- 增援测试覆盖 Cost、同时上限、实体 ID、出生点、等待和确定性顺序。
- 目标测试覆盖双旗舰同 Tick 沉没、顺序目标、增援损失计数、教学事件过滤和唯一 `LevelFinished`。
- 存档测试覆盖挑战首通、教学舰船解锁、重玩、重复事件、正式槽损坏、候选槽残留、恢复槽回退、校验失败、版本迁移、未知 ID 和不可信战斗来源。
- 契约实施不等于 23 关完成；仍须分别记录正式数据、菜单接入、模拟验收和人工实机验收。
