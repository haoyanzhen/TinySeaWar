# 关卡目标、接替增援与进度存档技术契约

> 当前可用字段见 `23`；T/S/M/L 共 23 关数据、目标、菜单、进度与接替增援已接入。可玩接入不代表正式平衡或真人验收通过；各关最新验证与阻塞统一见 `00`。

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

`Ordered` 按子目标首次完成 Tick 推进且不回退。条件只读 `BattleState` 与已发生领域事件，不读 HUD 或隐藏敌人实时位置。每 Tick 在伤害、沉没、接触和任务取消事实产生后评估一次。挑战关的任务完成即 `PlayerVictory` 并立即结束；保护目标沉没或明确限时结束等不可恢复条件使任务取消并立即 `PlayerDefeat`。普通挑战的顺序要求属于可选精通，单独记录结果，不参与主任务取消、奖励与进度；同 Tick 完成的连续精通目标视为同时满足。严格顺序取消只供另行明确标注的特殊任务。敌旗舰沉没只有在任务要求时才有结算意义。没有 `objective_set_id` 的原型关保持现有旗舰/超时兼容路径。最终只产生一个 `LevelFinished(level_id, result, reason_code, objective_snapshot, elapsed_time, tick_index)`。

### 2.1 二十三关目标映射

| 关卡 | `objective_set_id` | 完成契约 |
|---|---|---|
| T-01 | `objective.t01_navigation` | 两航点顺序 + 胜利 + 己旗舰存活 |
| T-02 | `objective.t02_gunnery` | 手动主炮开火≥1 + 切弹≥1 + 胜利 |
| T-03 | `objective.t03_skill` | 指定技能成功施放≥1 + 胜利 |
| T-04 | `objective.t04_armor` | 胜利 + 厌战存活 |
| T-05 | `objective.t05_torpedo` | 鱼雷命中≥1 + 胜利 + 两驱逐均存活 |
| T-06 | `objective.t06_carrier_hunt` | 百眼巨人沉没 + 己方存活≥2 + 己旗舰存活 |
| T-07 | `objective.t07_shared_contact` | 沃德进入前出侦查区并建立接触 -> 衣阿华手动主炮命中共享目标 + 胜利；无需进入海峡南口，己方全程禁用自动航行与自动主武器，仅保留自动副武器 |
| T-08 | `objective.t08_command` | 双舰集火指令≥1 + 胜利 + 己方存活≥2 |
| S-01 | `objective.s01_flagship` | 敌旗舰沉没；己旗舰沉没则取消 |
| S-02 | `objective.s02_escort` | 胜利 + 重庆/雪风任一存活 |
| S-03 | `objective.s03_carrier_first` | 俾斯麦沉没 + 己旗舰存活；可选精通：百眼巨人沉没 -> 俾斯麦沉没 |
| S-04 | `objective.s04_ambush` | 衣阿华沉没；仅己方旗舰胡德沉没时取消，重庆与海狮损失不单独取消任务 |
| S-05 | `objective.s05_wolfpack` | 敌方损失≥3 + 敌旗舰沉没；己旗舰沉没则取消 |
| M-01 | `objective.m01_harbor` | 敌旗舰沉没；己旗舰沉没则取消 |
| M-02 | `objective.m02_carrier_escort` | 俾斯麦沉没 + 凤翔与己旗舰存活；可选精通：百眼巨人沉没 -> 俾斯麦沉没 |
| M-03 | `objective.m03_flanks` | 衣阿华沉没 + 己旗舰存活；可选精通：愤怒与鞍山均沉没 -> 衣阿华沉没，前两舰内部无顺序 |
| M-04 | `objective.m04_storm` | 敌旗舰沉没 + 己旗舰存活 + 己方损失≤2；己旗舰或第 3 艘己舰沉没则取消 |
| M-05 | `objective.m05_blockade` | 衣阿华沉没 + 敌方损失≥4；己旗舰沉没则取消 |
| L-01 | `objective.l01_deployment` | 敌旗舰沉没；己旗舰沉没则取消 |
| L-02 | `objective.l02_air_corridor` | 企业沉没 + 百眼巨人与己旗舰存活；可选精通：两艘非旗舰敌航母均沉没 -> 企业沉没，前两舰内部无顺序 |
| L-03 | `objective.l03_gun_lane` | 大和沉没 + 己旗舰存活；可选精通：雪风与海狮均沉没 -> 大和沉没，前两舰内部无顺序 |
| L-04 | `objective.l04_encirclement` | 衣阿华沉没；胡德/百眼巨人任一沉没则取消 |
| L-05 | `objective.l05_finale` | 敌方损失≥8 + 大和沉没；己旗舰沉没则取消 |

### 2.2 M/L 十关的实现映射

逐关战术、地图配方、完成/取消、奖励与体验验收以 `15` 第 3.7、7、8、10.3 节为准；本节只规定安全落地方式。十关使用稳定 ID `level.challenge.m01..m05/l01..l05`，目标 ID 保持上表，不因换用 16:9 地图实例而改变。当前注册表仍采用 `23` 的扁平字段，不能直接把本方案条件树写进正式 JSON 并声称可加载。

| 关卡 | 当前字段可表达的主任务 | 可选精通/补充约束 |
|---|---|---|
| M-01 / L-01 | 当前用 `ChallengeMission` 显式指定双方旗舰，等价于 `FlagshipMission` | 无 |
| M-02 | `ChallengeMission`，`required_enemy_unit_ids` 指向俾斯麦，`protected_player_unit_ids` 含凤翔；己旗舰公共保护 | 百眼巨人→俾斯麦可用现有单序列精通 |
| M-03 | 指定衣阿华沉没，己旗舰公共保护 | 无序前置组 `{愤怒, 鞍山}`→衣阿华的精通 |
| M-04 | 指定俾斯麦沉没；将我方五个初始实体写入 `required_any_player_unit_ids`，`minimum_required_any_player_alive=3`；己旗舰公共保护 | 无；本关无玩家增援，五舰存活至少三舰等价于最多损失两舰 |
| M-05 | 指定衣阿华沉没，`minimum_enemy_sunk=4`；己旗舰公共保护 | 无 |
| L-02 | 指定企业沉没，保护己方百眼巨人；己旗舰公共保护 | 无序前置组 `{敌胜利, 敌百眼巨人}`→企业的精通 |
| L-03 | 指定大和沉没，己旗舰公共保护 | 无序前置组 `{敌雪风, 敌海狮}`→大和的精通 |
| L-04 | 指定衣阿华沉没，保护百眼巨人；胡德为公共保护旗舰 | 无 |
| L-05 | 指定大和沉没，`minimum_enemy_sunk=8`；己旗舰公共保护 | 无 |

分组精通实现为**有序阶段、阶段内 All**：独立的可选条件树 `Ordered(All(UnitSunk(A), UnitSunk(B)), UnitSunk(C))`，不加入主任务 completion/failure。只记录实际沉没 Tick；`max(tA,tB) <= tC` 时精通成立；C 已沉而任一前置仍存活时精通永久未达成。验证组非空、成员唯一、引用均为敌方、阶段无循环，同 Tick 按完整事件批次评估。现有平面序列无法表达该关系，不得将 A/B 固定排序、删除精通或把它变成硬取消。当前正式字段 `optional_enemy_sunk_stages` 已加入 `23`、加载器、快照与测试。

M/L 每 Tick 必须先收集完整沉没事实，再检查己旗舰/保护舰/存活数取消，最后判断完成，防止同时击沉目标和保护舰产生双结果。M-05/L-05 的敌旗舰提前沉没不进入基础旗舰结算，剩余敌人仍受本阵营完整 AI 管理；实际入场增援按唯一实体计入沉没数。结束后不得再生成增援或发第二次奖励。

目标负例至少覆盖：M-04 旗舰死但其他四舰活、非旗舰第 2/3 艘死、完成与取消同 Tick；M-05/L-05 数量先到/旗舰先死/同 Tick 满足；分组精通 A/B 两种先后与三者同 Tick；同名敌我航母引用混淆；未入场波次不能被计作沉没。前置组/地图/AI 战术意图的工程缺口不得通过放宽玩法悄悄消除。

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
| M-04 | `wave.m04.01` | 60s + 空位 | 沃德 | RN |
| M-05 | `wave.m05.01` | 120s + 空位 | 胜利 | RS |
| L-04 | `wave.l04.01` | 210s + 空位 | 愤怒 | RN |
| L-05 | `wave.l05.01` | 180s + 空位 | 胡德 | RN |
| L-05 | `wave.l05.02` | 300s + 空位 | 海狮 | RS |

M/L 每波只有一舰，M 类上限为 5、L 类为 11；`prerequisite_sunk_unit_ids` 不指定某艘前置，任何合法空位均可接替。没有空位或审核入口被占用就保持 Pending；RN/RS 为 15 的作者入口语义，须在正式数据中绑定 `23` 当前支持的单个 `spawn_point_id`，不能把本方案尚未落地的候选点数组直接下发。L-05 两波同时到时且只有一个空位时先处理 `.01`，`.02` 继续等待；目标达成时取消两者的未生成部分，不要求为预备舰拖延通关。

## 4. 进度存档

长期进度不进入 `BattleState`。存档只保存稳定 ID 与已获得事实，菜单每次根据完成事实和当前规则重算可用关卡，不存派生的 `unlocked_level_ids`。

```text
PlayerProgressSave
  schema_version, profile_id, revision, updated_at_utc
  completed_challenge_level_ids[]
  unlocked_ship_ids[]
```

T-01～T-08 默认全部开放且完成状态不写存档。S/M/L 三个挑战分类默认分别开放第一关；每个分类只根据 `completed_challenge_level_ids` 顺序开放同分类下一关，分类之间互不作为前置。舰船获取归属严格分为默认拥有、教学奖励、挑战奖励和待处理四类，具体分配见 `docs/15_battle_level_design.md`，唯一运行清单与旧存档保留契约见 `docs/23_level_progress_data_schema.md`。计划中的奖励关未开放时不发奖，待处理角色不虚构获取途径。

挑战首通处理为幂等事务：在内存副本同时合并挑战成功状态和舰船解锁。存档使用同目录正式槽、候选槽与恢复槽；候选槽带递增 `revision` 和 SHA-256 校验，写后必须重新读取验证，再将旧正式槽保留为恢复槽并提升候选槽。启动时从三个槽中选择校验有效且 revision 最高者，因此切换中断时仍至少保留一个可恢复版本。教学完成只合并对应舰船解锁，不写教学完成记录。重复结算、崩溃恢复和重玩不重复解锁。未知 ID 保留供前向兼容，但不产生当前解锁。

只有正式菜单启动、未使用 Definition 覆盖且产生 `PlayerVictory` 的教学/挑战 `LevelFinished` 能写入相应舰船解锁；只有挑战胜利额外写 `completed_challenge_level_ids`。模拟器、测试、调试跳关、自定义战斗、失败和中途退出都不写。存档不保存、恢复或保护任何局内战斗状态。

## 5. 验收

- 加载拒绝未知条件/参数、重复 ID、缺失单位/航点/技能引用、非法比较符与预备旗舰。
- 增援测试覆盖 Cost、同时上限、实体 ID、出生点、等待和确定性顺序。
- 目标测试覆盖双旗舰同 Tick 沉没、顺序目标、增援损失计数、教学事件过滤和唯一 `LevelFinished`。
- 存档测试覆盖挑战首通、教学舰船解锁、重玩、重复事件、正式槽损坏、候选槽残留、恢复槽回退、校验失败、版本迁移、未知 ID 和不可信战斗来源。
- 每个完成实现的教学关按 `36_balance_testing_design.md` 执行三轮互不重叠种子的设计路线实验；任一轮不是 100% 无异常时，修复后重跑全部三轮。
- 契约实施不等于 23 关完成；仍须分别记录正式数据、菜单接入、模拟验收和人工实机验收。

### 教学事实的顺序与正常操作一致性

当前教学子集用 `required_actions.prerequisite_action_id` 表达局部顺序，字段归属与加载约束见 `23`。T-02 记录发射前真实 HE 选择，T-03 记录成功主炮发射前的指定技能消耗效果；失败命令不计数。T-04 接触后仍要求玩家主炮决策。T-05 以命中后的物理区域到达证明脱离，并显式允许目标沉没后完成该动作。T-06 优先目标来自实际 FocusTarget。T-08 来自同一批量 FocusTarget 的成功成员，不再扫描单位目标状态推断编队操作。正常 UI 和确定性策略必须提交同一公开命令，策略不可注入命中、Buff 或抵达事实。教学状态持续提供当前未完成动作与说明，完成教学动作不等于已经通过正常耐久的实战迁移验收。
