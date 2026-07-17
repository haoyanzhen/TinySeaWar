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
```

State 的所有敌情来源必须可追溯到阵营过滤的 AIObservation。

## 5. 兼容、扩展与校验

- 旧 `target_priority`、`preferred_range`、`special_behavior` 已退出当前配置，新数据不得继续写入。
- Profile ID 唯一，关卡的 `enemy_ai_profile_id` 必须存在。
- 玩家辅助固定策略 `player_assist_local_execution` 只允许领域约束、即时生存、玩家路径、局部执行和被发现动作；禁止关卡任务、编组、战略模式、天气收益和自动技能。
- 舰队方案、可配置模式和 Rule Set 当前没有注册表 Definition；它们仍由 16 号设计与程序白名单拥有，只有在加载器、负例和迁移策略落地后才能加入本契约。
