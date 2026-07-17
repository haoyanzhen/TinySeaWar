# 场景、环境与设施数据契约

## 1. 文档功能与边界

本文是地图、地形、导航引用、天气时段、局部环境、设施、支援任务和水雷的数据形状真源。玩法效果见 `docs/18_facility_weather_effect_design.md`；硬地形、环境运行时和设施 Domain 分别见 `docs/35_scene_combat_domain_design.md`、`docs/37_environment_runtime_domain_design.md`、`docs/38_facility_combat_domain_design.md`；导航技术预算见 `docs/technical/t00_coastal_ai_performance_solution.md`、`docs/technical/t01_inertial_navigation_and_emergency_avoidance.md`。

本文不定义 Shader、贴图路径、资产生产或当前地图完成度；对应真源见 `docs/43_scene_art_design.md`、`docs/45_art_asset_interface_design.md`、`docs/00_project_status.md`。

## 2. LevelMap

关卡内嵌地图字段：

```text
width, height, ocean_palette
terrain_definition_id?
navigation_definition_id?
environment_zone_set_id?
facility_layout_id?
```

- `width/height>0`。
- `ocean_palette` 必须解析为正式 `{weather}_{time}` ID，或通过显式兼容别名迁移。
- 四个可选引用为空时按开阔海域创建；非空时必须分别引用匹配的地形、导航、环境区和设施布局。
- LevelMap 不保存 Shader 参数、AI 私有路径或运行时设施状态。

## 3. OceanConditionDefinition

表现 palette 与战斗条件共享同一语义 ID，但属于不同数据对象，不能互读字段。

```text
WeatherBattleProfile
  weather
  context.base_sea_state
  context.wind_speed
  context.wind_heading
  context.optical_visibility_multiplier
  context.weapon_accuracy_modifier
  context.aviation_delay_multiplier
  context.aviation_condition

TimeBattleProfile
  time_of_day
  context.optical_visibility_multiplier
  context.weapon_accuracy_modifier
  context.aviation_delay_multiplier

OceanConditionRules
  minimum_optical_visibility_multiplier
  torpedo_sigma_reference_sea_state
  torpedo_sigma_sea_state_step
  torpedo_sigma_wind_threshold
  torpedo_sigma_wind_step
  torpedo_sigma_multiplier_max
  sea_state_rules[]

OceanConditionAliases
  aliases
```

- `weather`：`clear | cloudy | overcast | rain | thunderstorm`。
- `time_of_day`：`day | dawn | dusk | night`。
- `aviation_condition`：`Normal | Restricted | Severe | Grounded`。
- 倍率为非负值；`minimum_optical_visibility_multiplier` 在 `(0,1]`；海况规则按 `minimum_sea_state` 唯一排序。
- 兼容别名只用于旧数据迁移，新配置必须写正式 ID。

## 4. TerrainAssetTemplate

```text
id, definition_type # TerrainAssetTemplate
display_name, asset_id, texture
origin, local_size, review_status
obstacles[], regions[], visual_regions[], facility_anchors[]
```

- `obstacles` 保存审核多边形与 `block_mask`；合法阻挡语义为 `ShipMovement | TorpedoTravel | ShellTravel | SurfaceOpticalLineOfSight`。
- `regions` 使用 `DeepWater | CoastalWater | ShallowWater | ReefOrSandbar | NavigationChannel`，并声明通行标签与成本。
- `visual_regions` 只保存 `asset_semantic`、多边形、透明度和层级，不参与碰撞、视线或通行。
- `facility_anchors` 使用模板局部坐标并具有唯一 ID。
- 图片 alpha、候选碰撞边缘和生产 QA 不进入运行时模板契约。

## 5. TerrainMap

```text
id, definition_type # TerrainMap
display_name, map_size
obstacles[], regions[], visual_regions[], visual_instances[]
facility_anchors[], spawn_points[]
navigation_definition_id, navigation_revision
environment_zone_set_id?, facility_layout_id?
geometry_epsilon, source_document
```

`spawn_points[]`：

```text
id, faction_id, position, heading, radius, movement_tags[]
```

- 近岸地图保存 `player_1..player_11` 与 `enemy_1..enemy_11` 的确定性槽位。
- 槽位必须位于边界内，不与硬地形或非法水域相交，同阵营不重叠，并能通过相应导航 Profile 接入接敌区域。
- 1v1、3v3、5v5、11v11 使用每侧编号前 `1/3/5/11` 个槽；具体尺寸基线属于 13、35。
- 烘焙元数据只用于可追溯性，不得改变运行时几何。

## 6. NavigationDefinition

```text
id, definition_type # NavigationDefinition
terrain_definition_id, navigation_revision
profiles[]
  id, radius, movement_tags[], cell_size
  nodes[]
    id, position, neighbors[]
```

- 地形引用必须存在，所有节点和边必须位于对应地图合法区域。
- 玩家与 AI 读取同一 Profile；难度配置不得提供私有候选数、隐藏节点或绕过统一 Broker 的路线入口。
- 门间距、接入候选、常规/紧急航迹候选与请求预算不在本 Schema 配置，统一由 t00/t01 的共享技术设置拥有。

## 7. EnvironmentEffect 与 EnvironmentZoneSet

`EnvironmentEffect`：

```text
id, definition_type # EnvironmentEffect
zone_type, priority, stack_rule, context
```

- `zone_type`：`SeaFog | RainSquall | HighSea | LeeWater | MoonlitLane | StrongCurrent | TidalWater`。
- `stack_rule`：`Highest | Override | VectorAdd`；`context` 只允许公共环境上下文字段。

`EnvironmentZoneSet`：

```text
id, definition_type # EnvironmentZoneSet
global_environment
zones[]
  id, effect_id, polygon
  position, heading, drift_speed, drift_path[]?
  intensity, phase, duration, active?
  public_trend
```

- `effect_id` 必须引用合法环境效果；`polygon` 至少包含三个点。
- `drift_path` 有值时按折线推进；无路径才使用 `heading`。
- 环境区保存规则空间和公开趋势，不保存 Shader 参数或未来精确位置。

## 8. FacilityDefinition

```text
id, display_name, asset_semantic
capabilities[], operation_modes[]
initial_state_profiles
area_control?
berthing_service?
remote_command?
automatic_operation?
observation_rules?
activation_rules?
radar_rules?
combat_disposition?
max_hp?, armor?, armor_thickness?
durability_reference_id?
weapon_mount_reference?
suppression_damage_threshold?, suppression_duration?
target_radius?
```

`operation_modes` 只允许：

```text
AreaControl | BerthingService | RemoteCommand | AutomaticOperation | CombatDisposition
```

声明某模式时必须同时提供对应对象。

### 8.1 area_control

```text
enabled, capturable, duration
```

### 8.2 berthing_service

```text
service_type # Supply | Repair
duration, berth_count, max_entry_speed, heading_tolerance_degrees
berth_state, dock_position_policy?, hold_while_docked?
interrupt_on_leave, interrupt_on_move_order?
interrupt_on_heavy_damage_ratio?
interrupt_on_facility_damage
interrupt_on_facility_unavailable?, interrupt_on_sink?, interrupt_on_undock?
progress_on_interrupt # Reset
weapon_reload_recovery_ratio?, skill_cooldown_recovery?
hp_restore_ratio?, repair_cap_ratio?
```

- `Repair` 必须使用 `berth_state=Docked`、`dock_position_policy=EntryPosition`、`hold_while_docked=true`，并显式声明移动、重击、设施失效、沉没和离泊中断。
- 单泊位由单场 `service_state` 独占；Definition 不保存占用舰或进度。

### 8.3 remote_command

```text
command_type, mission_ids[]?
control_radius, area_side_length?, duration?
mine_count?, cooldown, charges
random_seed_policy?
mine_trigger_radius?
detection_reference?
damage_reference?
in_progress_facility_policy?
deployed_mine_controller_policy?
```

- `MineDeployment` 使用 `detection_reference={ship_id, full_length_multiplier}` 与 `damage_reference={ship_id, weapon_id}`；旧 `mine_damage`、`detection_distance` 不得进入新配置。
- 引用舰船与武器必须存在，且武器实际挂载于引用舰船。
- `in_progress_facility_policy` 的合法结果为 `Cancel | Continue`；已布设水雷使用 `Independent` 时不随控制站失效清除。

### 8.4 observation_rules 与 radar_rules

- 光学观察必须声明天气、时段、局部能见度和视线是否影响。
- 雷达必须使用独立 `radar_rules`，声明接触类型、范围、精度与隐身破除策略，不能继承光学默认值。

### 8.5 combat_disposition

```text
suppressible, destroyable, silentable, damage_floor_ratio
```

可摧毁设施 `damage_floor_ratio=0`；不可摧毁设施使用 `(0,1)`。武器设施通过 `durability_reference_id`、`weapon_mount_reference` 复用合法舰船与武器 Definition。

## 9. FacilityLayout

```text
id, terrain_definition_id
placements[]
  id, definition_id, anchor_id, faction_id
  operation_state, initial_state_profile
  requires_all_active[]?, requires_any_active[]?
  dependency_rules.requires_matching_faction?
system_handover_rules[]?
  event_id, control_facility_id, facility_ids[]
```

- 放置 ID、锚点和设施引用唯一且存在。
- 依赖与整套易手必须显式列出，不允许通过通信站占领隐式转移全部设施。

## 10. SupportMissionDefinition

```text
id, definition_type # SupportMissionDefinition
display_name, mission_type, target_type
cooldown, charges
launch_time, arrival_time
max_range, effect_radius, effect_duration
blocked_aviation_conditions[]
enemy_aviation_accuracy_modifier?
salvo_count?, weapon_id?
facility_state_policy
  Preparing # Cancel | Continue
  EnRoute # Cancel | Continue
```

`launch_time` 必须早于 `arrival_time`；攻击任务引用合法 WeaponDefinition。阶段策略只决定任务取消或继续，不绕过公共航空、侦查和伤害规则。

## 11. MinefieldDefinition

```text
id, definition_type # MinefieldDefinition
display_name, terrain_definition_id
polygon, safe_channels[]
controller_facility_id?
owner_faction_id, operation_state
known_by_faction[]
detection_reference
damage_reference
controller_rules?
```

- 多边形和安全航道通过地形校验。
- 阵营快照只返回该阵营已知或拥有的雷区；全量边界只进入全知调试。
- 水雷触发复用第 8.3 节的引用规则，不保存独立易漂移伤害副本。
