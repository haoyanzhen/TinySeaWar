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
```

- `battle_mode`：`OpenSeaEqualBattle | CoastalEqualBattle | TutorialBattle | ChallengeBattle | CustomBattle`。新增模式必须同步加载校验和菜单/结算语义。
- `map` 遵守 `docs/22_scene_environment_data_schema.md`。
- `time_limit>0`。
- `objective_set_id` 省略时使用核心旗舰/超时兼容结算；存在时引用合法 ObjectiveSetDefinition。
- `enemy_ai_profile_id` 省略时使用 `ai.profile.standard`；显式值必须引用合法 AI Profile。
- `require_equal_fleet_cost` 默认 `false`；为 `true` 时加载器按所有初始成员引用舰船 Cost 校验两侧相等。
- 旗舰引用必须属于对应舰队且每侧恰有一个有效旗舰。

## 3. FleetMemberDefinition

```text
entity_id, ship_id, position, heading, is_flagship
weapon_group_states?
```

- `entity_id` 在关卡双方初始舰队中唯一。
- `ship_id` 必须存在；`position/heading` 通过地图、地形和出生合法性校验。
- `weapon_group_states={group_id: Enabled | Disabled}`；组 ID 必须属于引用舰船实际挂载。

## 4. ObjectiveSetDefinition

当前注册表接受以下结构：

```text
id, objective_kind
title, completion_text, failure_text
player_unit_id?
player_flagship_unit_id?, enemy_flagship_unit_id?
protected_player_unit_ids[]?, required_enemy_unit_ids[]?
contact_target_unit_ids[]?
required_actions[]?
world_markers[]?
locked_player_commands[]?
locked_player_commands_until_engagement[]?
initial_player_control_state?
engagement_player_control_state?
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

- `objective_kind` 当前只允许 `TutorialNavigation | TutorialGunnery | TutorialSkill | TutorialArmor | FlagshipMission`。
- 教学动作、命令锁、世界标识、控制状态和单位引用必须属于加载器白名单并能在引用关卡中解析。
- 教学能力限制必须显式列出；不得通过修改 HP、伤害、命中、装填或无敌状态模拟教学。
- 通用条件树、分阶段计划和接替增援仍只存在于 t02 技术方案，尚未成为当前运行配置字段；实施时必须先扩展本契约和加载负例。

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

## 6. 校验要求

加载至少拒绝：

- 未知 battle mode、目标类型、命令、事件或比较参数。
- 重复实体、航点或世界标识 ID。
- 缺失舰船、技能、武器组、AI Profile、地图或出生点引用。
- 多旗舰、无旗舰或等 Cost 关卡预算不一致。
- 教学目标引用隐藏脚本、未知动作/命令、错误阵营单位或非法世界标识。
