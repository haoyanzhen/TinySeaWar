# 战斗 AI 行为、玩家辅助控制、量化与验证设计

## 1. 文档功能与边界

本文是 Tiny Sea War 敌方完整 AI 与玩家受限辅助 AI 的决策设计真源，负责定义 AI 能看到什么、决策层级如何排序、目标/任务/模式/技能如何评分、如何迟滞切换以及难度如何改变决策质量，即“AI 为什么选择某个合法意图”。

本文不定义玩家按键、战斗公式、设施效果、导航算法实现、模拟样本方法或当前完成度。对应真源为 `docs/11_game_operation_design.md`、`docs/12_combat_formula_design.md`、`docs/18_facility_weather_effect_design.md`、`docs/technical/t00_coastal_ai_performance_solution.md`、`docs/technical/t01_inertial_navigation_and_emergency_avoidance.md`、`docs/36_balance_testing_design.md` 和 `docs/00_project_status.md`。

本文具体定义：

- 单舰从领域约束、即时生存、关卡任务、编组职责到战略模式的决策顺序。
- 单舰被发现后的进攻、防守、拉扯动作。
- 目标选择、预判攻击、技能预期收益和开火纪律。
- 战术编组、阵列、目标预留、攻击和技能协同。
- 鱼雷、近岸、设施、天气、雷区和复杂战况下的量化响应。
- 可执行量化模型、测试入口、场景矩阵和运行时验收标准。
- 玩家舰船的辅助航行、武器自动开火开关，以及与敌方完整 AI 的严格能力边界。

AI 的合法情报、角色能力、关卡目标、体验原则、配置字段和领域命令分别继承 `docs/10_game_core_mechanics.md`、`docs/13_balance_baseline.md`、`docs/14_character_balance_design.md`、`docs/15_battle_level_design.md`、`docs/17_play_design.md`、`docs/24_ai_data_schema.md` 和 `docs/32_domain_design_phase1.md`，本文不复制这些规则。

本文负责 AI 选择“为什么移动、移动到哪个战略目标以及何时改变意图”。战略路线请求、稀疏拓扑走廊、请求预算和近岸性能以 `t00` 为技术真源；舰船如何把战略意图转换为 `1s` 常规动力学控制、何时进入/退出 `0.1s` 紧急避险，以及等待、停车和倒车规则以 `t01` 为技术真源。本文不得另行定义折线跟随、全程精细路线或绕过统一 Broker 的导航入口。

本文量化公式必须有单一可执行参考，具体入口只在 `docs/34_implementation_map.md` 维护；哪些公式和验收已接入运行时只以 `docs/00_project_status.md` 为准。

---

## 2. 设计目标与原则

AI 的目标不是获得不可反制的最优解，而是形成稳定、可读、能被玩家推断且随战况响应的海面战术。

1. **公平情报**：AI 只读取己方完整状态、阵营当前可见敌人、合法残影、已知投射物、公开地形和阵营已知设施。
2. **领域对称**：玩家和 AI 使用同一移动、主要武器、技能、设施与支援命令；AI 不直接改位置、HP、设施状态或装填。
3. **分层决策**：鱼雷规避不做成战略模式，设施防守不做成开火例外，近岸通行不由角色脚本硬编码。
4. **低频思考，高频安全**：战略决策推荐每 `0.5s`；投射物、碰撞、边界和连招补发每个固定 Tick 检查。
5. **行动有承诺**：侧翼、斩首、占领和技能爆发都有驻留、暴露、航路或冷却代价。
6. **行为可解释**：每次模式、目标、技能、路径和开火选择都能输出分量、总分和原因。
7. **确定性**：同输入和固定种子产生同结果；同分使用稳定实体 ID，不用随机犯错制造难度。
8. **移动必须达成意图**：路线系统的首要目标是让角色顺利、持续且高效地向战术目标移动；降低请求数、失败数或计算量只有在没有永久停车、反复撞岸、无效绕行和大编队拥堵时才算优化。

---

## 3. 决策分层与控制权

单舰每次决策严格按以下层级处理：

```text
领域硬约束 Domain Constraint
  -> 即时生存 Immediate Survival
    -> 关卡任务 Level Objective
      -> 编组职责 Group Duty
        -> 单舰战略模式 Strategic Mode
          -> 被发现战术动作 Detected Tactic
            -> 移动 / 目标 / 开火 / 技能执行
```

| 层级 | 回答的问题 | 典型结果 |
|---|---|---|
| 领域硬约束 | 能否合法执行 | 拒绝穿岸、越界、隔岛开火、攻击隐藏目标 |
| 即时生存 | 是否存在已提交的迫近高威胁攻击 | 规避已发现鱼雷、白名单大口径主炮/航空/伤害技能 |
| 关卡任务 | 当前必须完成什么 | 占领、守点、反夺取、撤离、阻止突破 |
| 编组职责 | 在小队中承担什么 | 侦查、护航、牵制、侧翼、火力支援 |
| 战略模式 | 以什么长期姿态执行 | `ReconAvoid`、`TorpedoFlank`、`GunlineSupport` |
| 被发现动作 | 接敌后这一阶段怎么打 | `Attack`、`Defend`、`Kite` |
| 执行控制 | 何时、向哪里、用什么 | 航点、目标、主要武器、技能、设施命令 |

高层打断低层时记录 `interrupt_reason`、`interrupted_task` 和 `recovery_condition`。危险解除后重新评分，不无条件恢复过期航点。

### 3.1 敌方完整 AI 与玩家受限 AI

两种 AI 使用同一阵营可见视图、领域命令和合法性，但只允许以下能力：

| 能力层 | 敌方完整 AI | 玩家受限辅助 AI |
|---|---:|---:|
| 领域硬约束 | 使用 | 使用 |
| 即时生存 | 使用 | 始终使用，即使 `X` 关闭也只做最小必要规避 |
| 玩家路径执行 | 不适用 | 使用，且优先于普通辅助航行 |
| 局部目标与开火执行 | 使用 | 仅在 `C/V` 对应开关开启时使用 |
| 被发现 `Attack/Defend/Kite` | 使用 | 仅 `X` 开启时产生普通移动；`X` 关闭时只能影响允许的开火判断 |
| 关卡任务、设施价值 | 使用 | 禁止 |
| 战术编组、阵型、目标预留 | 使用 | 禁止 |
| 单舰战略模式 | 使用 | 禁止 |
| 天气、海况和环境战术收益 | 使用 | 禁止评分，但仍受公共领域效果约束 |
| 自动技能与技能协同 | 使用 | 永久禁止 |

玩家受限辅助 AI 的决策链缩减为：

```text
领域硬约束
  -> 即时生存
    -> 玩家路径执行
      -> 局部执行控制
        -> 被发现动作（仅 X 开启时产生普通移动）
          -> 根据 C/V 开关决定是否提交攻击
```

它不得创建 `level_task`、`group_id`、`group_role`、`mode_id`、`skill_reserve_reason`、伤害预留或效果预留。实现上应使用独立能力白名单，不能先运行完整 AI 再丢弃部分结果。

### 3.2 推荐频率

| 决策 | 周期 | 立即重评事件 |
|---|---:|---|
| 敌方舰队方案 | `2-4s` | 旗舰受重创、关键设施易手、编组瓦解 |
| 关卡任务与编组 | `1.0s` | 占领中断、保护对象受击、关键接触出现 |
| 单舰模式、目标、技能 | `0.5s` | 当前目标非法、被发现、技能窗口出现 |
| 高威胁扫描/紧急航迹 | `0.1s` | 已发现鱼雷或白名单伤害攻击进入反应窗 |
| 常规动力学航迹 | `1.0s` | 岸线、边界、普通避碰、水流和战略走廊进展 |
| 武器/技能/移动合法性 | 每 Tick | 始终由战斗系统权威校验 |

玩家受限辅助 AI 不运行舰队方案、任务、编组和战略模式周期；局部执行和被发现动作可沿用 `0.5s`。玩家与敌方共用 `1.0s` 常规航迹和 `0.1s` 高威胁扫描，`X` 关闭也不会关闭已知致命攻击规避。

---

## 4. AI 可见视图

正式 AI 不应直接读取完整 `BattleState`，而应读取阵营过滤后的 `AIObservation`。

### 4.1 可读取

- 己方单位完整状态、装填、技能冷却、编组和任务。
- 当前可见敌舰的公开战斗状态与运动趋势。
- 残影的最后已知位置、航向、时间和置信度；不包含隐藏后的实时更新。
- 地图公开岸线、浅水、航道和天气趋势。
- 己方已知设施、已知雷区、活动支援任务和公开环境区。
- 己方已发现投射物的位置、航向、速度、类别和首次发现时间。

### 4.2 不可读取

- 隐藏敌舰的实时位置、技能冷却和移动命令。
- 未发现敌方设施或雷区的完整状态。
- 未进入阵营投射物观察规则的鱼雷。
- 玩家输入、未来随机结果和表现层粒子位置。

### 4.3 残影和投射物

- 残影可驱动搜索、区域风险和航线评估，不能成为普通实体攻击锁定。
- 投射物使用 `known_projectiles_by_faction` 进行阵营可见过滤；己方鱼雷始终可见，敌方鱼雷由任一己方舰娘进入其发现距离后同步全队。
- 鱼雷预警技能只增加观察舰自身的鱼雷发现距离，不改变鱼雷真实运动；观测后的阵营共享不额外增加距离。

---

## 5. 单舰行动

### 5.1 基础规则

- 单舰只输出意图和普通命令，不直接修改领域状态。
- 每艘舰同时最多有一个关卡任务、一个编组职责、一个战略模式和一个即时打断。
- `task_target` 与 `attack_target` 分离；任务可以指向设施、位置或残影，攻击必须指向合法可见目标或合法海域。
- 目标位置先转换为低频战略走廊，再由 `1.0s` 常规动力学航迹输出推力/转向控制；导航折线不直接成为运行时跟随航迹。
- `strategic_intent_target` 保存任务想去的语义目标，走廊终点可以是同一可达水域内、确实缩短剩余距离的阶段目标；阶段目标不能反向覆盖语义意图，也不能把“目标点落岸”退化为永久停车。
- 目标、模式、走廊和控制计划都使用驻留和滞回，避免射程边缘反复改变意图。
- 自动普通武器继续由领域系统处理；`ManualPrimary` 必须由 AI 提交与玩家相同的命令。

### 5.2 领域硬约束

以下约束不参与效用竞争，失败即拒绝：

- 单位存活、阵营和控制权合法。
- 目标类型、侦查、射程、射角、冷却和资源合法。
- 移动点、整段航路、吃水、碰撞半径和潮汐状态合法。
- 火炮路径、鱼雷发射方向和设施目标不被硬地形非法阻挡。
- 设施交互类型、所有权、状态、交互水域和依赖合法。
- 沉没、摧毁或失效对象不能继续产生行动。

硬约束不能因目标分高、难度高或关卡脚本而绕过。

### 5.3 即时生存

运行时航行状态统一为：

```text
NormalNavigation
  -> EmergencyEvasion
  -> NormalNavigation

无法生成完全安全控制
  -> SafetyHold
```

- `NormalNavigation` 以战略走廊为目标，按约 `1.0s` 处理岸线、边界、水流、普通避碰、编组和设施接近。
- `EmergencyEvasion` 仅由本阵营已发现鱼雷，或已经提交且公开落区/时刻的白名单大口径主炮、高等级航空编队、伤害类技能触发。
- `SafetyHold` 选择预计伤害最低或 CPA 最大的可执行控制；允许受控触岸/短停，随后通过简化倒车恢复。
- 仅被发现、锁定、进入射程，或遭受副炮、普通小口径、低等级航空和非伤害技能，不触发紧急状态。

高威胁扫描每 `0.1s` 只做空间索引筛选、白名单、反应窗、解析 CPA/落区相交；只有进入阈值满足才生成最多 `5` 个基础、扩展后最多 `7` 个紧急控制候选。紧急详细预测为 `0.8-1.5s`，只承诺执行前 `0.1-0.3s`，且不读取战略走廊、阵位、武器舷角或设施收益。

#### 鱼雷风险

只评估己方已发现且正在接近的鱼雷：

```text
time_pressure     = clamp01(1 - time_to_cpa / reaction_horizon)
miss_pressure     = clamp01(1 - cpa_distance / danger_radius)
damage_pressure   = clamp01(expected_damage / current_hp)
maneuver_pressure = 1 - maneuver_margin

torpedo_risk = 100 * confidence * (
  0.35 * time_pressure
  + 0.30 * miss_pressure
  + 0.20 * damage_pressure
  + 0.15 * maneuver_pressure
)
```

- `reaction_horizon` 建议驱逐 `6s`、巡洋 `7s`、战列/航母 `8s`。
- `danger_radius` 使用舰船碰撞椭圆横向尺度、鱼雷半径和安全余量推导。
- `maneuver_margin` 比较剩余时间与完成候选转向所需时间。
- `time_to_cpa > reaction_horizon` 或 `cpa_distance > 1.5 * danger_radius` 时风险记 `0`。

规避比较保持、左/右转、左/右转并制动、加速穿越、最大制动和受控触岸。轨迹不能穿陆地，但当岸线接触/短停代价小于预计重创时可以在首次接触前停止，之后倒车脱离。

#### 岸线风险

岸线不再是紧急状态触发器。常规轨迹对每个候选做地形、水深、潮汐和地图边界扫掠；普通候选触岸即拒绝。Domain 每 Tick 继续阻止非法位移。只有高威胁避险的最后手段允许“受控岸线接触”，并且轨迹在接触前终止。

#### 边界和友军

- 边界与友军冲突属于常规航迹，不进入 `EmergencyEvasion`。
- 友军冲突优先由低任务优先级、高机动、非旗舰单位让路；同级按稳定实体 ID。
- 让路优先减速或向编组外侧偏转，不把整列舰船推向同一方向。
- 廉价交通 CPA 可以提前触发一次受限常规重算，但不得退化为固定 `0.1s` 常规规划。

退出紧急状态要求全部已知威胁在判断窗内均不再相交、风险低于退出阈值、没有更早新威胁，并存在一条不会立即重新触发同一攻击的合法常规航迹；条件连续保持 `0.3-0.5s` 后退出。

### 5.4 关卡任务

关卡任务不是单舰战略模式。推荐任务类型：

```text
CaptureFacility
ServiceFacility
AirportSupport
MineDeployment
DefendFacility
SuppressFacility
BlockPassage
EscortObjective
SearchArea
RetreatToZone
HoldDecisiveLine
```

任务必须声明：任务对象、任务价值、需要角色数、允许舰种、开始/完成/取消条件、最大偏离和回退任务。

#### 设施占领评分

```text
capture_score = 100 * (
  0.25 * facility_value
  + 0.17 * survival
  + 0.15 * path_quality
  + 0.13 * role_fit
  + 0.12 * ownership_need
  + 0.10 * followup_value
  + 0.08 * time_margin
  - 0.20 * contest_pressure
  - 0.15 * assignment_saturation
)
```

- `facility_value` 由观察、岸炮、机场、通信、水雷控制、补给和维修能力组合决定。
- `assignment_saturation` 防止全队涌向同一设施；达到任务所需舰数后取 `1`。
- 占领舰被攻击、敌方进入防守半径或生存分显著下降时，不必坚持读条；重新比较继续、撤离和请求护航。
- 完整 AI 只从本阵营 `AIObservation.known_facilities` 创建 `CaptureFacility`、`ServiceFacility`、`AirportSupport` 或 `MineDeployment`。区域控制先声明一次，进入水域后由 Domain 自动累计；靠泊条件满足后才申请一次服务，不逐 Tick 重复命令。
- 设施行动中断后立即清除当前任务；首次失败对该设施施加递增重评冷却，同一单位对同一设施两次失败后本局放弃。单次设施任务连续占用超过 `12s` 时无条件放弃并恢复搜索或接敌，避免任务长期锁死战斗决策。
- 玩家受限辅助只执行玩家指定设施的接近路线，不运行设施评分、任务分配、远程支援或布雷决策。

#### 设施防守评分

```text
defense_score = 100 * (
  0.27 * facility_value
  + 0.25 * capture_threat
  + 0.15 * reach_quality
  + 0.12 * role_fit
  + 0.11 * ally_need
  + 0.10 * defensive_position
  - 0.15 * local_disadvantage
  - 0.10 * assignment_saturation
)
```

防守拆成三种位置：

- `InnerGuard`：交互区附近阻止夺取，适合低速或耐久舰。
- `ApproachIntercept`：在入口和航道提前拦截，适合驱逐、轻巡。
- `FireSupport`：在合法炮线或航空范围支援，不挤占交互区。

关键设施防守分达到 `60` 时可覆盖普通追击；达到 `80` 时可打断斩首和侧翼任务，但不能覆盖即时生存。

### 5.5 编组职责

单舰编组职责：

| 职责 | 任务 |
|---|---|
| `Scout` | 前出建立接触并保持可撤离距离 |
| `Screen` | 在保护对象和主要威胁之间形成拦截层 |
| `Fixer` | 正面牵制，使敌人难以转向侧翼 |
| `Flanker` | 从侧翼产生交叉火力或鱼雷夹角 |
| `FireSupport` | 保持炮线、航空范围和技能跟进能力 |
| `ObjectiveRunner` | 占领、激活、补给或维修 |
| `Reserve` | 保留机动、技能或火力处理突发事件 |

编组职责效用达到 `58` 时覆盖普通模式动作。保护对象沉没、任务完成或组长失效时立即重分配。

### 5.6 单舰战略模式

| 模式 | 长期意图 | 默认开火纪律 | 主要回退 |
|---|---|---|---|
| `ReconAvoid` | 维持侦查边缘，控制暴露 | `SelfDefense` / `Silent` | `DisengageRegroup` |
| `VanguardLine` | 占据前锋并压制突破者 | `FreeFire` | `DisengageRegroup` |
| `TorpedoFlank` | 形成侧向雷击和发射后脱离 | `HoldUntilWindow` | `ReconAvoid` |
| `FlagshipRaid` | 以高承诺绕袭旗舰/航母 | `HoldUntilWindow` | `DisengageRegroup` |
| `EscortScreen` | 保护旗舰、航母或任务舰 | `SelfDefense` | `VanguardLine` |
| `GunlineSupport` | 保持中远炮线和射角 | `FreeFire` | `DisengageRegroup` |
| `CarrierStandoff` | 维持远离水面威胁的航空输出 | `SelfDefense` | `DisengageRegroup` |
| `DisengageRegroup` | 脱离、恢复阵位、等待冷却 | `SelfDefense` | 配置的主模式 |

舰种限制合理模式集合，但不锁死唯一模式。岛风可配置 `ReconAvoid`、`TorpedoFlank`、`FlagshipRaid`、`VanguardLine` 和 `DisengageRegroup`。

`AntiAirEscort` 与 `SubmarineAmbush` 只有在对应航空、防空、潜航、氧气和反潜闭环通过运行时与动态验收后才能启用；当前启用状态以 `docs/00_project_status.md` 为准。

### 5.7 被发现后的战术动作

“被发现”不自动等于冲锋或撤退。AI 在当前任务和模式范围内比较三种短期动作：

```text
Attack：推进、抢射角、完成爆发
Defend：守住目标、利用掩体、等待支援或冷却
Kite：保持火力的同时拉开、侧切或诱导追击
```

```text
U_Attack = 100 * (
  0.24 * local_advantage
  + 0.19 * weapon_ready
  + 0.16 * target_opportunity
  + 0.15 * skill_attack_value
  + 0.14 * group_followup
  + 0.12 * attack_route_quality
  - 0.15 * exposure_risk
)

U_Defend = 100 * (
  0.25 * local_pressure
  + 0.21 * objective_defense
  + 0.18 * cover_quality
  + 0.16 * survival_pressure
  + 0.11 * cooldown_need
  + 0.09 * group_support
)

U_Kite = 100 * (
  0.23 * range_advantage
  + 0.19 * speed_advantage
  + 0.19 * local_pressure
  + 0.16 * exit_quality
  + 0.13 * survival_pressure
  + 0.10 * weapon_cycle_value
)
```

动作至少保持 `1.5s`；若新动作高出当前 `12` 分并连续两次胜出才切换。即时生存不受此限制。

#### 玩家受限版本

玩家舰船不读取任务、编组、战略模式、技能收益或天气战术价值，使用独立简化公式：

```text
U_AssistAttack = 100 * (
  0.32 * local_advantage
  + 0.26 * weapon_ready
  + 0.22 * target_opportunity
  + 0.20 * movement_safety
  - 0.15 * exposure_risk
)

U_AssistDefend = 100 * (
  0.36 * local_pressure
  + 0.30 * survival_pressure
  + 0.20 * position_safety
  + 0.14 * cooldown_need
)

U_AssistKite = 100 * (
  0.28 * range_advantage
  + 0.24 * speed_advantage
  + 0.22 * local_pressure
  + 0.16 * exit_quality
  + 0.10 * weapon_cycle_value
)
```

- `X` 开启时，最高分动作可生成普通移动意图。
- `X` 关闭时，除即时生存外不产生移动；动作只供 `C/V` 开火判断使用。
- `position_safety` 和 `movement_safety` 只表示候选点是否满足岸线、边界、碰撞和通行约束，不搜索设施、天气优势或战略掩体。
- 没有可见接触时不生成搜索、巡逻、占领或编队回归动作。

---

## 6. 单舰进攻

### 6.1 目标评分

目标先通过存活、阵营、可见性和目标类型硬门槛，再计算：

```text
target_score = 100 * (
  0.30 * mission_value
  + 0.20 * threat
  + 0.17 * weapon_fit
  + 0.11 * range_fit
  + 0.09 * kill_opportunity
  + 0.07 * focus_fire
  + 0.06 * objective_relevance
  - 0.12 * pursuit_cost
  - 0.10 * overkill
)
```

- `mission_value`：模式和任务对该舰种、旗舰、设施或突破者的价值。
- `threat`：对自身、保护对象、设施或任务线的威胁。
- `weapon_fit`：武器目标类型、装甲修正、装填和射角适配。
- `range_fit`：与当前模式期望距离带的匹配。
- `focus_fire`：编组当前合法目标。
- `overkill`：已预留重武器预计伤害相对目标剩余 HP。

目标切换基线：最短保持 `2s`、新目标高出 `12` 分、连续两次确认、切换后冷却 `1.5s`。目标失去侦查或非法时立即清除，不使用滞回。

玩家受限辅助 AI 优先使用玩家当前合法集火目标；没有集火目标时只做局部执行选择：

```text
assist_target_score = 100 * (
  0.35 * immediate_threat
  + 0.30 * weapon_fit
  + 0.20 * range_fit
  + 0.15 * kill_opportunity
  - 0.10 * turn_cost
)
```

该分数不包含旗舰、Cost、关卡目标、设施、编组集火、追击价值或天气修正。`X` 关闭时目标不能驱动追击，只能供已开启的 `C/V` 选择射界内合法攻击。

### 6.2 预判性攻击

AI 不直接瞄准移动目标当前位置。火炮、鱼雷和航空各自使用其合法攻击速度求恒速拦截点：

```text
|target_position + target_velocity * t - origin| = projectile_speed * t
```

取最小正根；无正根、超过武器允许预测时间或预判点非法时，不伪造命中，改用当前位置、区域封锁或继续等待。

预判只使用目标当前合法可见运动。目标进入遮挡后，普通攻击不得继续更新预判点。

鱼雷进攻额外评估：

- 到达时间内目标可达扇区。
- 目标转向余量和航道宽度。
- 目标是否被 `Fixer` 编组牵制。
- 鱼雷散布覆盖与友军航线风险。
- 发射后脱离航线是否存在。
- 岸线是否会先于目标截断鱼雷。

### 6.3 攻击窗口

```text
attack_window = 100 * (
  0.19 * target_value
  + 0.16 * hit_quality
  + 0.14 * weapon_ready
  + 0.14 * expected_damage
  + 0.13 * skill_synergy
  + 0.12 * group_sync
  + 0.07 * kill_opportunity
  + 0.05 * objective_relevance
  - 0.12 * exposure_risk
  - 0.10 * overkill
  - 0.08 * friendly_risk
)
```

武器不合法、目标不可见或弹道被阻挡时直接为 `0`。

玩家自动主要武器使用不含战略项的简化窗口：

```text
assist_primary_window = 100 * (
  0.25 * target_value
  + 0.20 * hit_quality
  + 0.20 * weapon_ready
  + 0.15 * expected_damage
  + 0.10 * kill_opportunity
  + 0.10 * position_safety
  - 0.10 * exposure_risk
  - 0.10 * friendly_risk
)
```

`V` 开启且分数达到 `54` 时可以提交主要武器命令。这里的 `target_value` 只取局部威胁和武器适配，不加入任务、旗舰或编组价值；技能与协同收益固定不参与。

### 6.4 开火纪律

| 纪律 | 阈值 | 行为 |
|---|---:|---|
| `FreeFire` | `54` | 普通炮线和前锋有合格窗口即可开火 |
| `SelfDefense` | `48` | 仅在自身、保护对象或任务区受威胁时启用，否则禁火 |
| `HoldUntilWindow` | `68` | 保存主炮、鱼雷、航空等高价值攻击 |
| `Silent` | `101` | 正常禁火；紧急自卫阈值 `72` |

开火后必须记录破隐成本。`ReconAvoid` 和 `TorpedoFlank` 不应为了低价值自动火力破坏主要任务；必要时由模式禁用特定自动武器组，而不是绕过领域武器规则。

玩家舰船不从战略模式继承开火纪律：`C` 开启时副武器采用领域自动武器的合法即开火规则；`V` 开启时主要武器采用上述 `assist_primary_window`。两者均不能触发技能。

### 6.5 技能预期收益参与进攻

敌方完整 AI 的进攻决策不能采用“技能好了就放”。技能预期收益：

```text
skill_value = 100 * (
  0.24 * direct_value
  + 0.18 * coverage_value
  + 0.18 * attack_synergy
  + 0.15 * defense_urgency
  + 0.13 * objective_value
  + 0.12 * group_followup
  - 0.17 * waste_risk
  - 0.10 * exposure_cost
)
```

标准释放阈值 `60`；简单难度 `70`，困难难度 `52`。防御技能遇到致命威胁可以绕过普通阈值，但仍需合法。

技能标签：`Burst`、`Defense`、`Recon`、`Mobility`、`Escort`、`AreaSupport`、`AntiAir`、`Ambush`。

技能与主要武器连招使用显式状态：

```text
pending_combo = {
  type = "FirePrimaryAfterSkill",
  target_id = "...",
  expires_at = battle_time + 0.8
}
```

不能依赖命令 ID 排序隐式制造连招。

玩家受限辅助 AI 不调用本节评分，不建立 `pending_combo`，也不提交自动技能命令；玩家手动技能完成后，自动主武器仍按下一次正常局部决策独立评估，不能暗中把玩家技能当作预定连招。

---

## 7. 路径、近岸与掩体

### 7.1 路线候选

目标确定后生成有限候选：直达、左绕、右绕、沿航道、沿掩体、编组回归、威胁外扩和撤离。每条候选先通过共享 `RoutePlanner` 与 Domain 合法性，再评分：

```text
route_utility = 100 * (
  0.24 * time_efficiency
  + 0.17 * depth_safety
  + 0.16 * threat_safety
  + 0.14 * exposure_safety
  + 0.11 * turn_room
  + 0.08 * congestion_safety
  + 0.06 * formation_fit
  + 0.04 * objective_fit
)
```

因此较长但安全的近岸路线可以优于穿越岸炮射界的最短路线。未知雷区不进入成本；已知活动雷区按阵营情报处理。

### 7.2 重算与卡住恢复

AI 只决定战略目标、路线偏好和重新评估原因。统一 Broker、稀疏走廊、常规/紧急航迹周期、停车、倒车和卡住恢复的技术规则只以 `t00`、`t01` 为准；AI 必须消费其结果，不能建立平行导航入口。

目标点不能直接接入拓扑时，路线层应在动态可达分量内选择能够减少剩余距离的阶段目标，并保留原语义目标供后续重评。只有起点无法安全接图、动态分量没有正向进展、拓扑断开或走廊门为空时才报告分类失败。相同语义目标的排队请求必须去重；失败后按稳定退避重试，并在单位取得明显位移后允许提前重评。退避只是防止失败风暴，不能替代阶段推进、局部恢复或新的合法意图。

### 7.3 岛岸掩体

掩体是候选战术位置，不是“靠岛停船”：

```text
cover_score = 100 * (
  0.23 * shell_block
  + 0.18 * line_of_sight_break
  + 0.16 * exit_quality
  + 0.15 * weapon_access
  + 0.12 * turn_room
  + 0.09 * distance_fit
  + 0.07 * group_support
  - 0.22 * dead_end_risk
  - 0.16 * depth_risk
)
```

必须至少有一个合法出口；一般战术掩体推荐两个出口。掩体最大停留时间、允许舰种和最低出口质量由 Rule Set 配置。大型舰不得进入只能由浅吃水小舰安全转出的凹湾。

不同模式对掩体的用途不同：

- `ReconAvoid`：利用视线遮挡断开接触，不长期停留。
- `TorpedoFlank`：利用岛端遮挡接近，但发射方向和脱离航线必须合法。
- `GunlineSupport`：使用射界边缘，不为遮挡牺牲全部武器通道。
- `DefendFacility`：优先控制入口与交互区，而不是躲到无法支援的位置。

---

## 8. 敌方编队、阵列与协同

### 8.1 战术编组

推荐每组 `1-4` 艘；11v11 拆为多个编组，不维持刚性全舰大阵。

典型组合：

- 侦查舰 + 炮线支援舰。
- `Fixer` 正面牵制舰 + `Flanker` 鱼雷舰。
- 航母 + 防空/水面护航舰。
- 旗舰 + 内层护卫 + 外层侦查。
- 任务舰 + 护航舰 + 远程支援舰。

组长沉没后按职责优先级、指挥能力和稳定实体 ID 接替。编组共享的只是阵营合法信息与任务，不共享隐藏敌人事实。

### 8.2 阵列

| 阵列 | 用途 | 主要限制 |
|---|---|---|
| `Column` | 狭窄航道、快速通过岸线入口 | 防止纵向密集承受鱼雷 |
| `LineAbreast` | 大范围侦查、正面接触 | 转向前需预留横向空间 |
| `Wedge` | 标准推进、前锋建立接触 | 前锋压力过高时自动收缩 |
| `EchelonLeft/Right` | 单翼突击和侧翼保护 | 弱侧需要保留预备舰 |
| `Screen` | 旗舰、航母、任务舰护航 | 护卫不得被低价值目标诱离 |
| `Dispersed` | 对抗范围技能、航空和密集鱼雷 | 降低集火和技能覆盖效率 |

阵列不提供隐藏属性加成。阵位有舒适圈、修正圈和脱队圈；紧急动作优先，危险解除后再回位。

### 8.3 目标预留与过量伤害

编组登记主炮轮次、鱼雷波、航空波和高伤害技能的保守预计伤害：

```text
overkill = clamp01(assigned_heavy_damage / max(target_current_hp, 1))
```

自动小口径武器不参与预留。预留在武器取消、目标失效、预计到达超时或攻击结算后释放。

### 8.4 攻击与技能协同

```text
coordination_score = 100 * (
  0.28 * readiness_alignment
  + 0.23 * target_window
  + 0.19 * skill_synergy
  + 0.14 * crossfire_quality
  + 0.10 * reservation_fit
  + 0.06 * objective_timing
  - 0.20 * overkill
)
```

默认协同阈值 `70`。编组不要求所有武器同时开火：

- `Fixer` 可以先开火迫使目标保持航向。
- 侦查或压制技能先释放，建立 `0.5-1.5s` 跟进窗口。
- 鱼雷侧翼在窗口内提交主要武器，随后立即执行脱离航线。
- 炮线舰按目标预留决定齐射或转移次目标。
- 防御和撤离技能不为追求整齐而延迟到致命风险之后。

同类不可叠加技能需要 `effect_reservation`，记录作用组、预计开始/结束和覆盖对象，避免多舰同时浪费。

---

## 9. 敌方战略模式量化

通用输入全部归一化到 `[0,1]`：

```text
H  = hp_safety
L  = 1 - H
Q  = local_pressure
B  = 1 - boundary_risk
Wr = weapon_ready
C  = cohesion
Vn = vision_need
Vt = valid_target
Eq = exit_quality
```

首轮公式由 `AIQuantitativeModel.mode_scores()` 作为可执行真源。主要权重：

| 模式 | 高权重输入 |
|---|---|
| `DisengageRegroup` | `0.34L + 0.25Q + 0.21 boundary_risk + 0.20Eq` |
| `ReconAvoid` | `0.34Vn + 0.24H + 0.20B + 0.12C + 0.10 recon_route` |
| `VanguardLine` | `0.28Vt + 0.22H + 0.18C + 0.17(1-Q) + 0.15Wr` |
| `TorpedoFlank` | 侧翼质量 `0.26`、武器就绪 `0.22`、高价值暴露 `0.20`，其余为生存、边界和牵制 |
| `GunlineSupport` | 有效目标 `0.25`、武器就绪 `0.21`、凝聚 `0.18`，其余为边界、生存和炮线 |
| `CarrierStandoff` | 低压力 `0.25`、边界安全 `0.21`、生存 `0.18`，其余为目标、出口和护航 |
| `EscortScreen` | 保护对象威胁 `0.28`、拦截质量 `0.20`、凝聚 `0.18`，其余为生存、技能和边界 |

局部压力只统计合法可见敌人：

```text
unit_power = cost * hp_ratio
power_ratio = visible_enemy_power / max(friendly_power, 1)
local_pressure = clamp01((power_ratio - 0.8) / 1.2)
```

局部半径建议取自身主要武器射程 `1.2` 倍；设施任务可使用设施防守半径。

---

## 10. 驻留、切换与运行时记忆

### 10.1 模式切换

```text
mode_minimum_hold       = 4.0s
mode_enter_threshold    = 60
mode_switch_margin      = 15
mode_confirmations      = 2
mode_recovery_time      = 1.5s
```

流程：

1. 当前模式非法或即时生存触发：立即切换。
2. 未达到最短驻留：保持当前模式。
3. 候选低于进入阈值，或未高出当前模式 `15` 分：清除确认次数。
4. 同一候选连续两次满足条件：切换。

目标和被发现战术动作使用相同机制，但采用各自阈值。参考实现为 `switch_with_hysteresis()`。

### 10.2 运行时状态

```text
mode_id
mode_entered_at
mode_candidate_id
mode_candidate_confirmations
detected_tactic_id
level_task
group_id
group_role
task_target_ref
attack_target_id
target_acquired_at
target_candidate_id
target_candidate_confirmations
active_interrupt
interrupted_task
route_plan
route_revision
skill_reserve_reason
pending_combo
damage_reservations
effect_reservations
recent_damage_by_source
decision_cooldown
continuous_evasion_seconds
no_effective_movement_seconds
no_engagement_seconds
no_effective_attack_seconds
engagement_pressure
```

这些状态属于 Application/策略层，不进入 Presentation，也不把关卡行为脚本堆入 `UnitState`。

### 10.3 长时间消极行为的接敌压力

完整 AI 按单位累计连续回避、无有效位移、无可见接敌和无有效攻击时长。四项计时超过各自宽限后归一化，并等权合成为 `engagement_pressure`；它是可解释评分项，不是到点强制冲锋：压力提高 `Attack`、`VanguardLine`、`TorpedoFlank`、`GunlineSupport`、设施争夺和合法开火窗口评分，同时降低 `Defend`、`Kite`、`ReconAvoid`、`DisengageRegroup` 与 `CarrierStandoff` 评分。

即时威胁或耐久低于 `35%` 时暂停压力；主要武器处于装填低就绪、正在执行明确关卡任务或护航时将压力倍率降至最多 `0.35`。有效开火、进入合法接敌窗口、完成设施任务或显著位移会重置对应计时；威胁与回避结束后计时按衰减而非硬切换处理。运行时在压力达到 `0.25` 时输出触发原因、四项分量、豁免倍率和评分修正，并记录累计消极时长、触发次数、触发后接敌时间与连续 `20s` 无显著位移事件。

---

## 11. 数据与程序结构

AI Profile 应组合而不是复制规则：

```json
{
  "id": "ai_profile_shimakaze_elite",
  "doctrine_id": "doctrine_single_wing_pressure",
  "allowed_modes": ["ReconAvoid", "TorpedoFlank", "VanguardLine", "DisengageRegroup"],
  "default_mode": "ReconAvoid",
  "fallback_mode": "DisengageRegroup",
  "common_rule_set_id": "ai_rules_surface_advanced",
  "formation_plan_id": "formation_wedge_fast_flank",
  "objective_policy_id": "objective_fast_capture",
  "coordination_policy_id": "coordination_torpedo_crossfire",
  "difficulty": "Standard"
}
```

有限策略 ID 由程序实现，配置不能存放可执行表达式。

程序职责应分离为会话协调、阵营观察过滤、运行时记忆、量化评估、任务评估、编组协调、路线候选和攻击规划；具体文件位置与当前拆分状态只见 `docs/34_implementation_map.md`，不能用候选结构判断能力是否已经运行。

玩家受限辅助 AI 不引用敌方 Profile，使用固定能力策略：

```json
{
  "id": "player_assist_local_execution",
  "allowed_layers": ["DomainConstraint", "ImmediateSurvival", "PlayerRoute", "ExecutionControl", "DetectedTactic"],
  "forbidden_layers": ["LevelObjective", "GroupDuty", "StrategicMode", "WeatherTactics", "SkillPolicy"],
  "default_movement_assist": false,
  "default_secondary_auto_fire": true,
  "default_primary_auto_fire": false,
  "skill_auto_cast": false
}
```

这组能力是程序常量或经过校验的有限策略，关卡和角色配置不得将禁用层重新开启。

---

## 12. 敌方 AI 难度设计

难度不修改 HP、伤害、装填、射程或侦查属性。

| 参数 | 简单 | 标准 | 困难 |
|---|---:|---:|---:|
| 完整决策间隔 | `0.75s` | `0.5s` | `0.35s` |
| 技能阈值 | `70` | `60` | `52` |
| 目标切换确认 | `3` | `2` | `2` |
| 目标预留 | 无或仅主炮 | 重武器 | 重武器与技能 |
| 导航候选预算 | 共享 `t00/t01` 固定预算 | 共享 `t00/t01` 固定预算 | 共享 `t00/t01` 固定预算 |
| 编组协同 | 基础集火 | 目标与技能错峰 | 完整预留和交叉攻击 |

简单难度允许较慢反应和较保守技能，不允许读取额外信息或故意违反规则。

玩家受限辅助 AI 不随敌方难度变化，也不读取关卡 `difficulty`。其响应周期、局部目标公式和安全阈值在所有难度下保持一致。

---

## 13. 复杂战况预期

| 战况 | 预期决策链 |
|---|---|
| 侦查舰未接敌 | `ReconAvoid -> 侦查航线 -> Silent` |
| 侦查舰被发现且敌强 | `Kite -> 断开视线/外扩 -> 回到侦查边缘` |
| 前锋被发现且己方占优 | `Attack -> 抢射角 -> FreeFire` |
| 岛风侧翼、目标被牵制 | `TorpedoFlank -> 技能增益 -> 预判雷击 -> 发射后脱离` |
| 可见鱼雷进入碰撞窗 | 立即 `TorpedoEvasion`，完成后重新评估原任务 |
| 鱼雷从远处安全掠过 | 保持当前任务，不无意义大转向 |
| 高价值中立观察站安全 | 分配一艘合适任务舰占领，其余保持警戒 |
| 占领区出现强敌 | 中止孤立占领，比较撤离、护航和反击 |
| 己方机场即将被夺取 | `DefendFacility` 覆盖普通追击，分配内守、拦截、火援 |
| 最短航线经过岸炮射界 | 选择稍长的掩体/航道路由 |
| 岛后位置无出口 | 不把遮挡误认为优质掩体 |
| 多舰准备同一爆发 | 先侦查/压制，后主炮与鱼雷错峰，过量伤害舰转移目标 |
| 技能冷却完成但收益低 | 保留技能，不因冷却完成立即释放 |
| 旗舰遭侧翼威胁 | `EscortScreen` 和关卡保护优先于普通模式追击 |
| 玩家舰船默认状态 | 保持原地；副武器自动；主要武器与技能不自动 |
| 玩家开启 `X` | 只在局部接敌时选择进攻、防守或拉扯，不接管关卡任务 |
| 玩家关闭 `X`、开启 `V` | 舰船不追击，只对当前射界内合法目标自动使用主要武器 |
| 玩家布置多航点 | 按顺序执行；即时规避后回到下一合法途径点 |
| 玩家按 `Cmd/Alt + C` | 混合状态统一开启；全部开启时统一关闭 |
| 玩家控制舰技能就绪 | 始终等待玩家 `F`，任何辅助开关都不自动释放 |

---

## 14. 数值测试与验证

### 14.1 可执行测试要求

量化模型必须提供不依赖场景树、贴图或非确定随机数的纯计算测试，并输出各评分分量与总分；控制器与整局行为另由集成测试和固定种子模拟验证。测试入口与运行命令只在 `docs/34_implementation_map.md` 维护。

### 14.2 验证职责

本文只规定 AI 必须验证哪些行为，不记录易过期的检查数量、历史分数或完成状态。当前实现矩阵和最近测试结果以 `docs/00_project_status.md`、测试输出和正式报告为准。

### 14.3 测试边界

纯计算测试只验证“量化模型对给定态势是否选择预期行为”。完整 AI 必须再通过两级验收：

1. **控制器集成测试**：用构造的 `AIObservation` 验证命令、记忆、驻留、目标预留和打断恢复。
2. **整局动态测试**：在 1v1、3v3、5v5、11v11 和港湾关卡用固定种子运行多局模拟。

玩家辅助控制集成测试必须覆盖默认开关、`Z` 多航点、`X/C/V` 状态、舰队范围命令、`G` 镜头入口、自动主武器窗口、技能恒不自动、即时边界规避与恢复驻留；同时验证真实鱼雷打断后的路径恢复、混合开关组合、输入级 `Cmd/Alt`，以及编组、任务、设施或天气收益输入不越过局部决策边界。当前覆盖状态只见 `docs/00_project_status.md` 与正式测试输出。

### 14.4 整局动态指标

接入运行时后，批量模拟至少记录：

- 模式和战术动作驻留时间、每分钟切换次数。
- 发现至首次响应延迟。
- 鱼雷真实威胁规避率、安全鱼雷误规避率。
- 岸线碰撞、卡住、无路可达和边界强制钳制次数。
- 占领成功率、占领中断原因、设施失守后的响应时间。
- 主要武器空转率、非法命令拒绝率、技能浪费率。
- 集火过量伤害比例、协同窗口跟进率。
- 侦查模式暴露时间、炮线有效射击时间、航母受近身威胁时间。
- 胜率、旗舰击沉率和平均战斗时长；这些只用于平衡，不反向给予 AI 属性加成。

样本量、侧别交换和大版本统计授权只由 `docs/36_balance_testing_design.md` 定义。行为验收优先于胜率：即使胜率接近 50%，若 AI 高频撞岸、乱放技能或全队争抢同一设施，也不能通过。

---

## 15. 实现与状态边界

AI 的实施顺序是“合法观察与记忆 → 单舰战术与攻击 → 任务、编组与协同 → 整局动态验收”。具体代码落点见 `docs/34_implementation_map.md`，导航实现见 `t00/t01`，当前各阶段完成度与历史验证只在 `docs/00_project_status.md` 维护。本文的评分项存在不等于运行时接入或动态验收完成。

---

## 16. 调试事件

至少记录：

```text
AIDecisionEvaluated
AIInterruptEntered
AIInterruptCleared
AIModeCandidateChanged
AIModeChanged
AITacticChanged
AITargetChanged
AIObjectiveAssigned
AIObjectiveCancelled
AIGroupRoleChanged
AIRouteSelected
AIPathStuck
AISkillHeld
AISkillCommitted
AIFireHeld
AIFireCommitted
AIDamageReserved
AIEffectReserved
```

事件包含单位、时间、旧值、新值、最终分、关键分量和原因码。调试事件不改变战斗结果，也不消耗随机数。

---

## 17. 完成标准

- AI 只使用阵营合法信息，未发现鱼雷、敌舰、设施和雷区不会影响决策。
- 领域约束、即时生存、任务、编组、模式和战术动作的优先级稳定。
- 同一角色配置不同模式时能表现出明显不同的侦查、雷击、炮线或护航行为。
- 被发现后能够根据局部优势、目标价值、技能窗口、航路和生存压力选择进攻、防守或拉扯。
- 能在近岸绕行、利用有出口的掩体、拒绝死胡同，并对关键设施执行占领和分层防守。
- 合法移动意图能够形成持续正向进展；不可直接接入的目标会转为可达阶段目标，而不是以少请求、少失败或 `SafetyHold` 掩盖原地不动。
- 高价值攻击使用预判、开火纪律、技能收益和编组预留，不因冷却结束立即浪费。
- 固定种子可复现；评分变化不会造成高频目标和模式抖动。
- 量化模型测试、控制器集成测试、整局动态测试和人工可读性复核全部通过。
- 玩家舰船默认静止、副武器自动、主要武器与技能不自动；受限 AI 永远不能进入编组、战略、天气收益、关卡任务或技能决策。
