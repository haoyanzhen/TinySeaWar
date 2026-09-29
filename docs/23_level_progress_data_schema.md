# 关卡、目标与进度数据契约

## 1. 文档功能与边界

本文是当前关卡、舰队成员、目标和长期进度的数据形状真源。关卡内容意图见 `docs/15_battle_level_design.md`；尚未进入运行配置的分阶段目标、接替增援和事务存档扩展方案见 `docs/technical/t02_level_objective_reinforcement_progress_solution.md`。

本文不维护具体 23 关任务副本、目标胜率、当前实施数量或测试结果；它们分别归 15、36、00。

## 2. LevelDefinition

```text
id, display_name, battle_mode
objective_set_id?
enemy_ai_profile_id?
map
time_limit
require_equal_fleet_cost?
player_fleet[], enemy_fleet[]
reinforcement_waves[]?
```

- `battle_mode`：`OpenSeaEqualBattle | CoastalEqualBattle | TutorialBattle | ChallengeBattle | CustomBattle`。新增模式必须同步加载校验和菜单/结算语义。
- `map` 遵守 `docs/22_scene_environment_data_schema.md`。
- `time_limit>0`。
- `objective_set_id` 省略时使用核心旗舰/超时兼容结算；存在时引用合法 ObjectiveSetDefinition。
- `enemy_ai_profile_id` 省略时使用 `ai.profile.standard`；显式值必须引用合法 AI Profile。
- `require_equal_fleet_cost` 默认 `false`；为 `true` 时加载器按所有初始成员引用舰船 Cost 校验两侧相等。
- 旗舰引用必须属于对应舰队且每侧恰有一个有效旗舰。

`reinforcement_waves[]` 的成员在开局不进入舰队、视野或损失统计；运行时按 `earliest_time`、`concurrent_unit_cap`、`wave_id` 与审核出生点顺序生成。每波包含 `wave_id, faction_id, earliest_time, concurrent_unit_cap, spawn_point_id, members[]`；波 ID 与所有初始/预备实体 ID 必须唯一，预备成员不得是旗舰。

## 3. FleetMemberDefinition

```text
entity_id, ship_id, position, heading, is_flagship
weapon_group_states?
initial_hp_ratio?
```

- `entity_id` 在关卡双方初始舰队中唯一。
- `ship_id` 必须存在；`position/heading` 通过地图、地形和出生合法性校验。
- `weapon_group_states={group_id: Enabled | Disabled}`；组 ID 必须属于引用舰船实际挂载。
- `initial_hp_ratio` 默认 `1.0`，合法范围为 `(0, 1]`；仅用于关卡明确设计的战损初始状态，不改变舰船 Definition 的最大耐久。

## 4. ObjectiveSetDefinition

当前注册表接受以下结构：

```text
id, objective_kind
title, completion_text, failure_text
player_unit_id?
player_flagship_unit_id?, enemy_flagship_unit_id?
protected_player_unit_ids[]?, required_enemy_unit_ids[]?
required_any_player_unit_ids[]?, minimum_required_any_player_alive?
ordered_enemy_unit_ids[]?, minimum_enemy_sunk?
optional_ordered_enemy_unit_ids[]?
minimum_player_hp_ratio_unit_id?, minimum_player_hp_ratio?
contact_target_unit_ids[]?
required_actions[]?
world_markers[]?
locked_player_commands[]?
locked_player_commands_until_engagement[]?
initial_player_control_state?
engagement_player_control_state?
player_weapon_locked_unit_ids_until_action[]?
player_weapon_unlock_action_id?
enemy_weapon_unlock_action_id?
engagement_trigger?
enemy_staging_position?, enemy_staging_positions?
engagement_enemy_mode_locks?
scout_player_unit_id?, shared_contact_target_unit_id?
command_target_unit_id?, command_player_unit_ids[]?, minimum_group_focus_count?
lock_enemy_primary_and_skill?, lock_enemy_automatic_weapons?
intro_text?, pre_engagement_instruction?, engagement_instruction?
ability_limit_text?, engagement_ability_text?
waypoint_zones[]?
```

- `objective_kind` 当前只允许 `TutorialNavigation | TutorialGunnery | TutorialSkill | TutorialArmor | TutorialTorpedo | TutorialCarrierHunt | TutorialSharedContact | TutorialCommand | FlagshipMission | ChallengeMission`。
- `ChallengeMission` 只使用白名单任务事实：指定目标沉没、指定敌方沉没数量、按列出的敌方 ID 顺序沉没、指定保护舰存活、指定集合的最少存活数和单舰 HP 比例下限。`ordered_enemy_unit_ids` 是特殊任务的硬顺序条件；`optional_ordered_enemy_unit_ids` 是独立可选精通，不参与取消、通关、奖励或章节开放。保护舰沉没、集合存活不足或 HP 触及下限仍立即取消。
- `optional_ordered_enemy_unit_ids` 只用于 `ChallengeMission`，省略时为空；提供时必须是至少两个唯一、可解析、敌方实体 ID 的数组。每 Tick 消费连续已经沉没的目标；同 Tick 完成的连续目标同时满足，不虚构先后。后续目标已沉没而前置目标仍存活时，将精通标记为未达成且不回退。M/L 设计中的“前置一组全部完成后再完成旗舰”不等于组内严格顺序，尚未接入的分组条件表达仍归 t02，不用当前平面数组替代。
- 教学动作、命令锁、世界标识、控制状态和单位引用必须属于加载器白名单并能在引用关卡中解析。
- 教学能力限制必须显式列出；除 `FleetMemberDefinition.initial_hp_ratio` 所声明的开局战损外，不得在运行中修改 HP、伤害、命中、装填或无敌状态模拟教学。
- `player_weapon_locked_unit_ids_until_action` 与 `player_weapon_unlock_action_id` 必须成对出现；前者只能引用己方单位，后者必须引用本目标的必做动作。指定单位的主武器、技能和自动武器在该动作首次获得合法证据前保持锁定。
- `enemy_weapon_unlock_action_id` 必须引用本目标的必做动作；教学进入交战阶段后，敌方主武器、技能和自动武器仍保持锁定，直至该动作首次取得合法证据。该字段不锁敌方移动、侦查、受击或碰撞。
- 通用条件树和教学分阶段计划仍只存在于 t02 技术方案；当前接替增援已成为关卡 Definition 字段，加载器校验波、成员与目标引用。

教学动作增量字段：

- `required_actions[].prerequisite_action_id?: String`：只能引用同列表更早的动作 ID；该动作达到 required_count 后当前事实才可计数，禁止前向引用与循环。
- `required_actions[].ammo_type?: String`：仅 `ManualPrimaryFire` 可用，枚举 `HE | AP`；校验实际成功发射前所选弹药。
- `required_actions[].required_active_skill_id?: String`：仅 `ManualPrimaryFire` 可用，引用已加载技能；要求实际发射前存在该技能对应的待本主炮组消耗效果。
- 动作白名单增加 `FocusPriorityTarget`（成功的普通集火命令，按己方来源/敌方目标过滤）、`ReachRetreatZone`（实际区域到达，必须以前置 `TorpedoHit` 约束）。
- `retreat_zone?: {id:String, unit_id:String, position:Vector2Array, radius:float}`：仅 `TutorialTorpedo`；己方单位、合法正坐标对、正半径，动作 unit_id/route_zone_id 必须与区域一致。
- `allow_post_sink_actions?: bool`：默认 false，仅带合法 retreat_zone 的 `TutorialTorpedo` 可用；已取得必做 TorpedoHit 后目标沉没仍保留脱离动作；未命中即失去目标仍为顺序失败，保护条件仍立即评估。
- `GroupFocusTarget` 事实必须携带非空 `group_order_id` 和成功成员 `group_unit_ids`，包含指定教学成员且达到 minimum_group_focus_count；不能由多个独立集火状态推断。
- 教学运行快照 `next_action_id:String` 表示当前首个未完成动作，空字符串表示无未完成动作；`instruction` 是相应当前说明。
- 外部 `RecordTutorialAction` 仅接受选择与镜头跟随；命令、交战和到达事实只能由对应权威处理点记录。

教学类型的专属约束：

| `objective_kind` | 交战触发与必需事实 |
|---|---|
| `TutorialNavigation` | 恰好两个合法 `waypoint_zones`，并提供 `enemy_staging_position`。 |
| `TutorialGunnery` | `engagement_trigger=RequiredActionsComplete`；`required_actions` 同时包含 `SwitchAmmo` 与 `ManualPrimaryFire`。 |
| `TutorialSkill` | `engagement_trigger=RequiredActionsComplete`；`required_actions` 包含 `CastSkill`，且技能属于动作单位。 |
| `TutorialArmor` | `engagement_trigger=FirstContact`；提供非空 `contact_target_unit_ids`。 |
| `TutorialTorpedo` | `engagement_trigger=FirstContact | RequiredActionsComplete`；提供非空 `contact_target_unit_ids`，以白名单动作 `TorpedoHit` 记录必做命中。 |
| `TutorialCarrierHunt` | `engagement_trigger=FirstContact | RequiredActionsComplete`；提供非空 `contact_target_unit_ids`，由 `required_enemy_unit_ids` 表达必须击沉的航母目标。 |
| `TutorialSharedContact` | `engagement_trigger=RequiredActionsComplete`；提供 `scout_player_unit_id`、`shared_contact_target_unit_id`，并以 `EstablishSharedContact`、`SharedTargetGunHit` 记录共享接触与后续命中。 |
| `TutorialCommand` | `engagement_trigger=RequiredActionsComplete`；提供 `command_target_unit_id`、`command_player_unit_ids` 和正数 `minimum_group_focus_count`，并以 `GroupFocusTarget` 记录集火。 |

除 `TutorialNavigation` 外，所有教学类型都必须提供非空 `protected_player_unit_ids`、`required_enemy_unit_ids`、`enemy_staging_positions`、`initial_player_control_state` 和 `engagement_player_control_state`；其中单位 ID 必须属于引用本目标的关卡，且阵营与字段语义一致。

挑战目标快照增加以下只读字段，表现层直接消费，不保存到玩家进度：

| 字段 | 类型 / 默认值 | 约束 |
|---|---|---|
| `mission_steps` | Object[] / `[]` | 每项 `label:String, completed:bool`；必需击沉目标与实际入场敌舰损失进度，不包含可选精通 |
| `protection_lines` | String[] / `[]` | 旗舰、指定保护舰、集合存活和耐久阈值说明；旗舰不重复显示 |
| `reinforcement_hint` | String / `""` | 只列 Pending 波；来自公开作者配置的最早时间、空位条件与已知入口名，不揭示隐藏单位状态；未知入口名省略 |
| `optional_order_progress` | int / `0` | 已连续满足的精通目标数量 |
| `optional_order_failed` | bool / `false` | 一旦提前击沉后续目标即为 true，不撤销主任务胜利 |
| `optional_mastery` | String / `""` | 独立说明精通进度、已完成或未达成，并明确不影响通关奖励 |

## 5. PlayerProgressSave

```text
schema_version, profile_id, revision, updated_at_utc
completed_challenge_level_ids[]
unlocked_ship_ids[]
checksum
```

- 只保存稳定事实，不保存派生的关卡开放列表或任何局内 BattleState。
- 挑战完成 ID 和舰船 ID 去重；未知 ID 可为前向兼容保留，但不产生当前解锁。
- 正式、候选、恢复三槽的事务顺序、SHA-256 校验和可信结算来源只见 t02。
- 模拟器、测试、调试、自定义、失败和中途退出不得写进度。

保存结果视图为会话状态，不写入进度文件：`status` 为 `Idle/Saved/Failed`，`message` 为面向玩家的说明，`can_retry` 为布尔值，`pending_level_ids` 为尚待持久化的正式胜利来源 ID 数组。保存失败保留当前会话已取得的角色和挑战完成事实；后续重试保存同一累计事实，不重复结算奖励。只有写入成功且重新读取包含全部待保存事实后才切换为 `Saved` 并清空待保存来源；无待保存事实的重试不写磁盘。跨场景保留失败状态，退出应用后的恢复仍以三槽有效文件为准，不把内存中的成功结算等同于磁盘保存成功。

## 6. ShipAcquisitionCatalog

`progress.ship_acquisition` 是角色获取归属的唯一运行时清单。

| 字段 | 类型 / 必填性 | 约束 |
|---|---|---|
| `id` | String / 必填 | 固定为 `progress.ship_acquisition` |
| `planned_challenge_level_ids` | String[] / 必填 | 尚未配置的 `level.challenge.m01..m05/l01..l05`，不得重复 |
| `ships` | Object[] / 必填 | 覆盖所有已加载舰船，每舰恰有一项 |
| `ships[].ship_id` | String / 必填 | 有效舰船引用，唯一 |
| `ships[].category` | String / 必填 | `DefaultOwned`、`TutorialReward`、`ChallengeReward`、`Pending` 四选一 |
| `ships[].source_level_id` | String / 奖励类必填 | 教学类引用已加载教学关；挑战类引用已加载挑战关或上述计划列表；非奖励类不得设置 |

默认拥有集合从清单派生；持久化的已拥有集合独立于获取归属。载入旧存档时并入默认拥有，不撤销既有合法舰船；未知舰船 ID 保留在原存档事实中但不参与当前编成。`Pending` 不产生新奖励；旧存档已拥有的角色不因重新分类而消失。只有已加载的正式教学/挑战关可以发放清单中的对应奖励，计划关卡不能通过单独传入 ID 发奖。

## 7. 校验要求

加载至少拒绝：

- 角色获取清单缺失、漏舰、重复舰、未知分类、无效来源或非奖励类携带来源。

- 未知 battle mode、目标类型、命令、事件或比较参数。
- 重复实体、航点或世界标识 ID。
- 缺失舰船、技能、武器组、AI Profile、地图或出生点引用。
- 多旗舰、无旗舰或等 Cost 关卡预算不一致。
- 教学目标引用隐藏脚本、未知动作/命令、错误阵营单位或非法世界标识。

关卡可选 `aviation_rules_mode: Abstract | Physical`，不配置时使用CombatSettings。该覆盖用于航空迁移实验和可操作演示，创建后固定，不进入进度存档或奖励判定。
