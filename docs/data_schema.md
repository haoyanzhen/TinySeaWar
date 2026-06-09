# 数据结构设计文档

## 1. 设计目标

本文件定义 Tinny Sea War MVP 阶段使用的核心数据结构。技术设计文档只保留系统说明，具体字段以本文档为准。

MVP 阶段建议使用 Godot Resource 或 JSON 配置数据。早期推荐优先使用 Godot Resource，便于在编辑器中调参；当配置量变大或需要外部表格工具时，再考虑导入 JSON、CSV 或表格数据。

## 2. 舰娘配置

舰娘不使用单一“火力”字段。为了表现同一舰娘对炮击、鱼雷、防空和航空作战的差异，基础攻击能力拆为多个分项。

基础字段：

```text
id
display_name
ship_class
level
cost
max_hp
armor
armor_thickness
speed
turn_speed
detection_range
concealment_distance
fire_concealment_multiplier
evasion
gunnery_power
torpedo_power
anti_air_power
aviation_power
max_oxygen
variant_tags
reference_ship_profile
weapon_mounts
main_weapon
torpedo_weapon
anti_air_weapon
air_wing
scout_wing
skill_id
is_flagship_candidate
```

字段含义：

- `id`：舰娘唯一标识。
- `display_name`：显示名称。
- `ship_class`：舰种。
- `level`：舰娘等级，MVP 为 1 到 3 级。
- `cost`：出击资源消耗。
- `max_hp`：最大生命值。
- `armor`：装甲值，用于伤害公式中的固定减伤。
- `armor_thickness`：装甲厚度分档，用于武器对不同护甲厚度的伤害补正。
- `speed`：最大航速。
- `turn_speed`：转向速度。
- `detection_range`：侦查范围。
- `concealment_distance`：隐蔽距离，表示目标能被发现的最大距离，数值越小越难被发现。
- `fire_concealment_multiplier`：开火破隐比例。舰娘开火后，当前隐蔽距离按该比例放大。
- `evasion`：闪避能力。
- `gunnery_power`：火炮能力，影响主炮、副炮和炮击技能。
- `torpedo_power`：鱼雷能力，影响水面鱼雷、潜艇鱼雷和部分航空鱼雷表现。
- `anti_air_power`：防空能力，影响防空圈、敌机拦截和空袭削弱。
- `aviation_power`：航空能力，影响舰载机规模、空袭、侦察和出击效率。
- `max_oxygen`：最大氧气值，主要用于潜艇；非潜艇可为空或 0。
- `variant_tags`：舰娘变体标签，例如 `FastScout`、`TorpedoSpecialist`、`AAEscort`、`HeavyArmor`、`LongRangeGunnery`。
- `reference_ship_profile`：现实舰船或舰型参考标识，只用于设计说明和调参依据，不作为强制模板。
- `weapon_mounts`：装备底座列表，描述火炮、鱼雷、防空、航空等装备的底座数量、装填、射角和目标类型。
- `main_weapon`：主武器引用，MVP 可作为兼容字段。
- `torpedo_weapon`：鱼雷武器引用，MVP 可作为兼容字段。
- `anti_air_weapon`：防空武器引用，MVP 可作为兼容字段。
- `air_wing`：舰载机或航空队引用。
- `scout_wing`：侦查机配置引用，主要用于航母。
- `skill_id`：主动技能标识。
- `is_flagship_candidate`：是否可作为旗舰。

这些能力值不直接等同于最终伤害。最终结果还需要结合武器配置、射程、装填、命中、目标装甲、目标机动、侦查状态和技能修正。

兼容说明：

- 旧字段 `detectability` 不再作为主字段使用。MVP 以 `concealment_distance` 表达隐蔽能力。
- 潜艇下潜时可以使用状态修正降低 `concealment_distance`，不需要单独的水下侦查公式。

## 3. 装备底座配置

装备底座用于描述舰娘实际如何攻击。舰娘的分项能力决定擅长方向，装备底座决定攻击节奏、覆盖范围和可攻击目标。

基础字段：

```text
id
mount_type
display_name
mount_count
shots_per_mount
reload_time
range
minimum_range
fire_arc_center
fire_arc_degrees
turret_turn_speed
projectile_speed
spread
accuracy_modifier
target_types
weapon_resource_id
armor_damage_modifiers
aircraft_config_id
```

字段含义：

- `id`：装备底座唯一标识。
- `mount_type`：装备类型，可为 `Gun`、`Torpedo`、`AntiAir`、`Aviation`、`AntiSubmarine`、`Special`。
- `display_name`：显示名称。
- `mount_count`：同类底座数量，例如三座三联装主炮可写为 3。
- `shots_per_mount`：每个底座一次攻击发射数量，例如三联装可写为 3。
- `reload_time`：装填时间。
- `range`：最大射程。
- `minimum_range`：最小射程，可选。
- `fire_arc_center`：射角中心，通常相对舰娘航向或舰装底座方向。
- `fire_arc_degrees`：射角宽度。
- `turret_turn_speed`：炮塔、鱼雷管或装备朝向调整速度。
- `projectile_speed`：投射物速度。
- `spread`：散布。
- `accuracy_modifier`：命中修正。
- `target_types`：可攻击目标类型，例如 `Surface`、`Air`、`Submerged`。
- `weapon_resource_id`：引用具体武器资源或表现资源。
- `armor_damage_modifiers`：对不同装甲厚度分档的伤害补正。
- `aircraft_config_id`：航空类底座引用的舰载机配置。

MVP 约定：

- 主炮和鱼雷必须使用射角。
- 防空可先简化为 360 度范围，但仍使用 `reload_time` 周期结算伤害。
- 航空可先使用固定出击点和目标区域。
- 反潜装备用于攻击已发现的下潜潜艇。

## 4. 装甲厚度枚举

MVP 使用离散装甲厚度分档，具体数值可随调参变化。

```text
Unarmored
Light
Medium
Heavy
Submerged
Air
```

字段含义：

- `Unarmored`：无装甲或极轻装甲目标。
- `Light`：驱逐、轻型单位。
- `Medium`：巡洋舰等中型单位。
- `Heavy`：战列等重装甲单位。
- `Submerged`：下潜潜艇。
- `Air`：舰载机和侦查机。

## 5. 舰种枚举

```text
Destroyer
LightCruiser
HeavyCruiser
Battleship
Carrier
Submarine
```

## 6. 资源消耗配置

资源消耗可以使用表格或公式配置。MVP 推荐先使用表格，便于人工调参。

基础字段：

```text
ship_class
level
cost
```

字段含义：

- `ship_class`：舰种。
- `level`：舰娘等级，MVP 为 1 到 3 级。
- `cost`：出击资源消耗。

约束：

- 同舰种高等级资源消耗应高于低等级。
- 同等级下，航母、战列和潜艇通常比轻巡、驱逐消耗更高。
- 关卡通过 `resource_limit` 限制舰队总消耗。

## 7. 舰种基准与个体差异

现实舰船的装甲、航速、转向、武器底座数量、联装数量、口径和对不同装甲厚度的补正，只作为舰种基准范围和设计参考，不作为同舰种所有舰娘的固定值。

MVP 数值应采用三层结构：

1. 舰种基准：定义该舰种常见范围，例如驱逐通常高速、轻装甲、多鱼雷；战列通常重装甲、大口径、慢转向。
2. 等级修正：定义 1 到 3 级的整体强度、成本和装备规模差异。
3. 个体配置：每名舰娘可以在舰种范围内拥有独立装甲、航速、转向、底座数量、联装数量、口径、装填、射程和补正。

设计约束：

- 同舰种舰娘不应只改生命值和攻击力。
- 同舰种内可以存在高速低甲、低速重甲、防空强化、鱼雷强化、主炮强化、侦查强化等不同变体。
- 武器底座数量和联装数量可以参考现实舰型，但允许为了玩法做抽象。
- 口径决定伤害补正倾向，但不应单独决定最终强度。
- 资源消耗应反映舰娘的整体价值，而不是只由舰种和等级决定。

## 8. 伤害与命中公式配置

本节只定义公式配置需要存储的字段。具体计算顺序见 `docs/combat_formula.md`，MVP 初始参数见 `docs/balance_baseline.md`。

基础字段：

```text
id
attack_type
base_damage
power_coefficient
armor_coefficient
evasion_coefficient
accuracy_coefficient
area_damage_chance
distance_penalty_coefficient
hit_rate_min
hit_rate_max
```

字段含义：

- `id`：公式配置唯一标识。
- `attack_type`：攻击类型，例如 `Gun`、`Torpedo`、`Aviation`、`AntiAir`、`AntiSubmarine`、`Skill`。
- `base_damage`：基础伤害。
- `power_coefficient`：分项作战能力参与伤害的系数。
- `armor_coefficient`：攻击类型或弹种配置的装甲减伤系数，数值越高越容易被目标装甲值抵消。
- `evasion_coefficient`：闪避参与命中或受击概率的系数。
- `accuracy_coefficient`：武器命中修正参与命中的系数。
- `area_damage_chance`：范围技能对未发现目标造成伤害的概率。
- `distance_penalty_coefficient`：距离对命中率的惩罚系数。
- `hit_rate_min`：命中率下限。
- `hit_rate_max`：命中率上限。

## 9. 舰载机配置

基础字段：

```text
id
display_name
max_hp
speed
attack_type
damage_formula_id
duration
vision_range
redeploy_cooldown
```

字段含义：

- `id`：舰载机或侦查机唯一标识。
- `display_name`：显示名称。
- `max_hp`：最大生命值。
- `speed`：飞行速度。
- `attack_type`：攻击类型，例如空袭、侦查、防空诱饵。
- `damage_formula_id`：引用伤害公式。
- `duration`：存在时间上限。
- `vision_range`：提供视野范围，侦查机使用。
- `redeploy_cooldown`：重新部署冷却，侦查机 MVP 为 30 秒。

规则：

- 舰载机受损后造成伤害按剩余生命值百分比结算。
- 舰载机和侦查机可以被防空周期伤害击落。
- 舰载机不需要返航。

## 10. 阵型配置

基础字段：

```text
id
display_name
slots
move_speed_modifier
turn_speed_modifier
```

字段含义：

- `id`：阵型唯一标识。
- `display_name`：显示名称。
- `slots`：阵型槽位列表，描述每个舰娘相对阵型中心的位置。
- `move_speed_modifier`：阵型统一移动时的航速修正。
- `turn_speed_modifier`：阵型统一转向时的转向修正。

## 11. 地图配置

基础字段：

```text
id
display_name
width
height
boundary_type
collision_damage
```

字段含义：

- `id`：地图唯一标识。
- `display_name`：显示名称。
- `width`：战场宽度。
- `height`：战场高度。
- `boundary_type`：边界类型，MVP 固定为不可离开的固定边界。
- `collision_damage`：单位碰撞卡住时造成的生命值损失。

## 12. 关卡配置

基础字段：

```text
id
display_name
battle_mode
resource_limit
max_player_units
enemy_fleet
enemy_flagship_id
map_id
difficulty_index
time_limit
stalemate_duration
enemy_ai_profile_id
```

字段含义：

- `id`：关卡唯一标识。
- `display_name`：显示名称。
- `battle_mode`：战斗模式。MVP 固定为 `OpenSeaEqualBattle`。
- `resource_limit`：玩家出击资源上限。
- `max_player_units`：玩家最大出击舰娘数量。
- `enemy_fleet`：敌方舰队配置。
- `enemy_flagship_id`：敌方旗舰标识。
- `map_id`：地图标识。
- `difficulty_index`：难度索引。
- `time_limit`：关卡时间限制，MVP 默认 20 分钟。
- `stalemate_duration`：无伤害记录多久后允许手动结束，MVP 默认 60 秒。
- `enemy_ai_profile_id`：敌方 AI 行为配置引用，用于覆盖默认目标优先级或特殊操作。

## 13. AI 配置

基础字段：

```text
id
target_priority
preferred_range
special_behavior
```

字段含义：

- `id`：AI 配置唯一标识。
- `target_priority`：目标优先级列表，默认顺序为潜艇/航母、驱逐、战列、重巡、轻巡。
- `preferred_range`：期望作战距离，例如保持距离、正面作战或近距离攻击。
- `special_behavior`：特殊行为，例如绕后、斩首、保护旗舰或集火指定舰种。

## 14. 技能配置

基础字段：

```text
id
display_name
cooldown
target_type
cast_range
effect_type
effect_value
duration
vfx_id
```

字段含义：

- `id`：技能唯一标识。
- `display_name`：显示名称。
- `cooldown`：冷却时间。
- `target_type`：目标类型，例如自身、敌方、区域、旗舰。
- `cast_range`：释放距离。
- `effect_type`：效果类型，例如炮击强化、鱼雷发射、空袭、防空强化、闪避提升。
- `effect_value`：效果数值。
- `duration`：持续时间，瞬发技能可为 0。
- `vfx_id`：表现资源标识。

MVP 约定：

- 技能冷却从开局起算。
- 技能可以不需要目标，也可以是目标指向性技能。
- 技能不设计射角。
