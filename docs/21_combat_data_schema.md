# 战斗单位与结算数据契约

## 1. 文档功能与边界

本文是舰船、武器、公式、投射物、航空、技能、增减益和公共战斗设置的数据形状真源。玩法与公式语义分别见 `docs/10_game_core_mechanics.md`、`docs/12_combat_formula_design.md`，公共数值范围与角色设计见 `docs/13_balance_baseline.md`、`docs/14_character_balance_design.md`。

本文不保存当前角色覆盖、测试数量或代码路径；运行状态见 `docs/00_project_status.md`，入口见 `docs/34_implementation_map.md`。

## 2. ShipDefinition

```text
id, display_name, faction, ship_class, level, cost
max_hp, armor, armor_thickness
base_speed, speed, base_turn_speed, turn_speed
base_detection_range, detection_range
base_concealment_distance, concealment_distance
fire_concealment_multiplier
evasion, gunnery_power, torpedo_power, anti_air_power, aviation_power
max_oxygen?, oxygen_consumption_rate?, oxygen_recovery_rate? # Submarine 必填；其他舰种可省略
redive_oxygen_ratio?, depth_transition_duration?, depth_state_minimum_hold? # Submarine 必填；其他舰种可省略
can_launch_torpedoes_submerged? # Submarine 必填；其他舰种可省略
collision_radius, collision_half_extents
variant_tags[], asset_root
weapon_mounts[], primary_weapon_group_id?
primary_weapon_control_type?, ammo_selection_group_id?
initial_ammo_type?, skill_id?, is_flagship_candidate
```

关键约束：

- `ship_class`：`Destroyer | LightCruiser | HeavyCruiser | Battleship | Carrier | Submarine`。
- `level` 为 `1..3`；`cost`、HP、能力值和碰撞尺寸不得为负。
- `armor_thickness`：`Unarmored | Light | Medium | Heavy | Submerged | Air`。
- `speed`、`turn_speed`、`detection_range`、`concealment_distance` 是运行值；对应 `base_*` 保存设计基线。倍率依据只见 `docs/13_balance_baseline.md`。
- `collision_radius` 只用于旧数据与导航兼容；舰船、炮弹和鱼雷几何接触以随航向旋转的 `collision_half_extents=[纵向, 横向]` 为准。
- `weapon_mounts` 引用 WeaponDefinition；主要武器组至多一个，弹药选择组必须属于本舰实际挂载组。
- `primary_weapon_control_type`：`Torpedo | BattleshipMainGun | AviationSquadron | OtherMainWeapon`。
- `Submarine` 必须显式配置正数 `max_oxygen`、`oxygen_consumption_rate`、`oxygen_recovery_rate`、`depth_transition_duration`、`depth_state_minimum_hold`，并显式配置 `[0,1]` 内的 `redive_oxygen_ratio` 和布尔值 `can_launch_torpedoes_submerged`；普通潜艇也必须写入 `false`，只有特殊潜射角色才写入 `true`。这些字段对其他舰种可省略。
- 潜艇 `base_detection_range = base_concealment_distance * 1.5`；运行值继续遵守公共距离倍率。稳定深度下的侦查与被侦察派生值不重复写入 Definition。

旧字段 `detectability`、`main_weapon`、`torpedo_weapon`、`anti_air_weapon`、`air_wing`、`scout_wing` 不得进入新配置。

## 3. WeaponDefinition

```text
id, display_name, mount_type
weapon_group_id, shared_cooldown_group?
control_mode, ammo_type
mount_count, shots_per_mount, reload_time
base_range, range, minimum_range?
fire_arc_center?, fire_arc_degrees?, fire_arcs[]?
mount_fire_arcs[]?, full_salvo_fire_arcs[]?
base_projectile_speed, projectile_speed
spread, torpedo_lane_spacing?, torpedo_angular_sigma_ratio?
mount_launch_interval?
base_impact_radius?, impact_radius?
accuracy_modifier, target_types[]
formula_id, projectile_id, armor_damage_modifiers
```

枚举：

- `mount_type`：`Gun | Torpedo | AntiAir | Aviation | AntiSubmarine | Special`。
- `control_mode`：`ManualPrimary | Automatic`。
- `targeting_mode`：`Entity | Direction | Area | AutomaticArea`。
- `ammo_type`：`HE | AP | None`。
- `target_types`：`Surface | Air | Submerged` 的非空合法组合。

交叉校验：

- 同一物理 HE/AP 底座共享 `weapon_group_id` 和冷却组；切弹不重置装填。
- 每舰最多一个不同组 ID 的 `ManualPrimary` 组；其余武器组为 `Automatic`。
- `mount_count > 1` 的舰炮配置非空 `full_salvo_fire_arcs`，且它是聚合射界的子集。
- 手动鱼雷为每座底座配置唯一 `mount_fire_arcs`，长度等于 `mount_count`；一次命令只选择一座合法且已装填底座。
- 鱼雷满足 `spread = degrees(2 * asin(torpedo_lane_spacing / (2 * range))) * (shots_per_mount - 1)`；`torpedo_angular_sigma_ratio=0.20`；`mount_launch_interval>=1s`。
- 射程、投射速度、散布和结算半径的数值依据只见 12、13，不在 Schema 中复制调参说明。

## 4. 单场武器与控制状态

UnitState 可保存：

```text
selected_ammo_by_group
primary_weapon_group_id
control_authority # Player | EnemyAI
movement_assist_enabled
secondary_auto_fire_enabled
primary_auto_fire_enabled
primary_auto_fire_suspended
skill_auto_cast_enabled
player_route_waypoints[]
movement_state.waypoint_index
radar_stealth_state # Exposed | Stealthed
depth_state # Surface | Submerged
depth_transition # target_depth_state, remaining, duration
depth_hold_remaining
oxygen_state # current, maximum
```

- 玩家默认 `movement=false`、`secondary=true`、`primary=false`、`skill_auto_cast=false`；技能自动释放权限不通过玩家配置开放。
- `primary_auto_fire_suspended` 是手动瞄准期间的瞬态互斥，不覆盖玩家偏好。
- 在途攻击固定保存发射时的弹种与修正快照。
- 关卡成员可声明 `weapon_group_states: {group_id: Enabled | Disabled}`；组 ID 必须属于实际挂载，未声明组默认 `Enabled`。

## 5. DamageFormulaDefinition

```text
id, attack_type
design_base_damage, base_damage
design_power_coefficient, power_coefficient
design_armor_coefficient, armor_coefficient
base_hit_rate, evasion_coefficient, distance_penalty_coefficient
hit_rate_min, hit_rate_max
```

- `attack_type`：`Gun | Torpedo | Aviation | AntiAir | AntiSubmarine | Skill`。
- 所有采用概率命中公式的火炮、航空、反潜和技能 Formula 必须使用 `hit_rate_min=0.05`。
- 实体碰撞鱼雷以几何接触强制命中，Formula 使用 `hit_rate_min=hit_rate_max=1.0`，不属于概率下限例外扩散的依据。
- `0 <= hit_rate_min <= hit_rate_max <= 1`；其他系数不得为负，除非所属公式明确允许有符号修正。
- 设计值到运行值的倍率只见 `docs/13_balance_baseline.md`，加载器负责校验成对字段一致。

## 6. ProjectileDefinition

```text
id, behavior
base_speed, speed, lifetime, collision_radius
minimum_detection_distance?
target_types[], destroy_on_hit, pierce_count
```

- `behavior`：`Straight | DelayedImpact | PathFollow`。
- `collision_radius>0`、`lifetime>0`、`pierce_count>=0`。
- 鱼雷 `minimum_detection_distance` 必填且为正，直接使用运行距离，不套用通用距离倍率；非鱼雷可省略。

## 7. SkillDefinition

```text
id, display_name, cooldown, target_type
base_cast_range, cast_range
base_effect_radius, effect_radius
effects[], triggered_attacks[], recon_zones[]
duration, description
vfx_id?, ai_tags[]?
implementation_status?, unsupported_effects[]?
design_values?
```

- `cast_range` 与 `effect_radius` 独立；自身或无距离限制技能可为 `0`。
- `effects` 内的 `modifiers` 使用第 8 节结构；`triggered_attacks` 与 `recon_zones` 必须引用合法武器、目标和航空配置。
- `implementation_status` 仅允许 `supported | partial`；它是加载审计元数据，不足以证明关卡覆盖或动态平衡完成。
- `partial` 必须列出非空 `unsupported_effects`；当前覆盖状态只见 `docs/00_project_status.md`。
- `design_values` 是非执行审计文本，不得作为运行时效果回退来源。

## 8. ModifierDefinition

```text
stat, operation, value, category
stack_group, stack_rule, source_type
duration, limit_min?, limit_max?
```

- `operation`：`FlatAdd | PercentAdd | StateMultiply | IndependentMultiply`。
- `stack_rule`：`Add | Highest | Refresh | Replace`。
- 命中百分点使用 `AccuracyPoint`，装填速度使用 `ReloadSpeed`，鱼雷观察距离使用 `TorpedoDetectionDistance`。
- `IndependentMultiply` 只允许明确标记的效果；叠加顺序和上下限语义只见 12、13。

## 9. CombatSettings

`data/settings/combat_settings.json` 的公共字段：

```text
id # settings.combat
gun_dispersion.sigma_scale
gun_dispersion.longitudinal_sigma_ratio
gun_dispersion.reference_ship_id
gun_dispersion.reference_weapon_id
gun_dispersion.reference_range
gun_dispersion.reference_spread_degrees
gun_dispersion.reference_battleship_length
```

- `sigma_scale>0`；`0 < longitudinal_sigma_ratio <= 1`。
- 两个 reference ID 必须存在；三个 reference 数值满足 12 号文档定义的标定关系。
- 运行时所有舰炮共享该设置，不允许角色私有 sigma 覆盖。
