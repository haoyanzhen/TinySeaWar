# AI 配置数据契约

## 1. 文档功能与边界

本文是当前敌方 AI 难度 Profile 与技能 AI 标签的数据形状真源，并划清单场 AIState 的保存边界。决策语义、硬编码模式和评分只见 `docs/16_enemy_ai_behavior_design.md`；导航候选、走廊和请求预算只见 t00/t01，不属于 AI 难度配置。

玩家受限辅助使用固定能力边界，不读取敌方 Profile，也不通过关卡或难度扩权。

## 2. AIDifficultyProfile

```text
id, difficulty
decision_interval
skill_threshold
target_confirmations
coordination_threshold
effect_reservations
```

- `difficulty`：`Easy | Standard | Hard`。
- `decision_interval>0`；`skill_threshold`、`coordination_threshold` 位于 `[0,100]`；`target_confirmations>=1`。
- 难度只改变决策周期、选择阈值、确认次数和协同深度，不修改舰船属性、观察权限、公共导航候选预算或 Domain 合法性。
- 旧 `route_candidate_count` 已退出契约；统一航迹链使用 t00/t01 的共享固定预算。

## 3. Skill AI 元数据

SkillDefinition 可声明：

```text
ai_tags[]
```

`ai_tags` 当前允许 `AntiAir | AntiSubmarine | AreaAttack | AreaSupport | Aviation | Burst | Concealment | Control | Defense | Mobility | Recon | Resource | TargetAttack | Torpedo | TorpedoWarning`，只用于用途分类，不改变技能效果或施放合法性。

## 4. 单场 AIState 边界

以下属于运行时 State，不写回 Profile：

```text
current_mode_id, mode_candidate_id, mode_confirmations
current_tactic, current_target_id
target_memory, contact_confidence
group_id, group_role, formation_slot
objective_assignment, reservation_state
last_decision_tick, hold_until_tick
interrupt_state, recovery_state
submarine_combat_phase, submarine_phase_entered_at
submarine_phase_reason, submarine_attack_completed
submarine_target_id
submarine_contact_lost_at
submarine_last_asw_damage_at, submarine_last_dive_at, submarine_depth_intent
submarine_target_rejections, submarine_eligible_target_count
planned_torpedo_weapon_state_instance_id
planned_torpedo_aim_position
planned_attack_position, planned_exit_position
torpedo_opportunity_expires_at
torpedo_opportunity_key, torpedo_opportunity_last_trigger_tick
requested_depth_state, depth_request_reason
last_depth_request_tick, depth_hold_until_tick
projected_oxygen_margin, surface_attack_deadline
last_submarine_fire_tick
```

State 的所有敌情来源必须可追溯到阵营过滤的 AIObservation。

`submarine_contact_lost_at` 为浮点战斗秒数，默认 `-1` 表示无接触等待；`submarine_target_rejections` 为最近一次目标筛选的原因码到非负整数计数映射，默认 `{}`；`submarine_eligible_target_count` 为该次筛选的合格目标数，默认 `0`。以上均为运行时 State，不进入难度配置。

`submarine_combat_phase` 只允许以下六个值：

```text
Search | Approach | SurfaceForAttack | AttackRun | BreakContact | RecoverOxygen
```

不定义 `Redive` 阶段。重新下潜由 `RecoverOxygen` 中的 `requested_depth_state=Submerged`、`depth_request_reason`、`last_depth_request_tick` 和实际 `UnitState.depth_state` 表达；只有稳定进入 `Submerged` 才切回 `Search`，拒绝或再次强制上浮时仍保持 `RecoverOxygen`。

潜艇深度状态仍由战斗 `UnitState` 权威持有；AIState 只保存战斗阶段、原子雷击解、机会有效期/稳定键/最近触发 Tick、资源预测、最近请求与迟滞记忆。计划发射器、瞄准点、攻击点和出口必须同时建立与清除，不能把旧候选与新航行解拼接。潜艇的 `current_mode_id` 和开火纪律是阶段投影，不独立评分或迟滞；`current_tactic` 不用于持久化潜艇 `Attack/Defend/Kite`。目标和雷击解分别复用公共 `target_score`、`attack_window` 后按稳定分层键排序，不增加 `submarine_target_score`、`torpedo_solution_score` 或对应权重字段。深度意图独立于移动和战斗阶段，策略见 `docs/16_enemy_ai_behavior_design.md`；补氧目标不是 Domain 下潜门槛。

上述潜艇字段是完整 AI 接入必须遵守的正式 State 形状；字段写入消费者和当前运行时覆盖只见 `docs/00_project_status.md`。

## 5. 兼容、扩展与校验

- 旧 `target_priority`、`preferred_range`、`special_behavior` 已退出当前配置，新数据不得继续写入。
- Profile ID 唯一，关卡的 `enemy_ai_profile_id` 必须存在。
- 玩家辅助固定策略 `player_assist_local_execution` 只允许领域约束、即时生存、玩家路径、局部执行和被发现动作；禁止关卡任务、编组、战略模式、天气收益和自动技能。
- 舰队方案、可配置模式和 Rule Set 当前没有注册表 Definition；它们仍由 16 号设计与程序白名单拥有，只有在加载器、负例和迁移策略落地后才能加入本契约。

`submarine_last_asw_damage_at`、`submarine_last_dive_at` 为战斗秒数，默认 `-INF`；前者只记录有效反潜伤害，后者只记录权威下潜完成。`submarine_depth_intent` 枚举为 `Attack | SelfDefense | Conceal | Recover | Hunt`，默认 `Hunt`，不新增持久战斗阶段。

航空真实模式观察对象增加 `visible_aircraft: Dictionary`，从 `aviation_observations_by_faction` 读取当前合法敌机片段，仅含公共ID、机型、位置、航向、HP及飞行状态。没有来源舰、武器、目标落点、剩余航时或隐藏路线；不作为舰船导航实体。抽象模式不凭新航空视图扩展AI观察权限。
