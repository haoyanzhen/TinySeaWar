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
speed
turn_speed
detection_range
detectability
evasion
gunnery_power
torpedo_power
anti_air_power
aviation_power
weapon_mounts
main_weapon
torpedo_weapon
anti_air_weapon
air_wing
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
- `armor`：装甲能力。
- `speed`：最大航速。
- `turn_speed`：转向速度。
- `detection_range`：侦查范围。
- `detectability`：可侦查性，数值越高越容易被发现。
- `evasion`：闪避能力。
- `gunnery_power`：火炮能力，影响主炮、副炮和炮击技能。
- `torpedo_power`：鱼雷能力，影响水面鱼雷、潜艇鱼雷和部分航空鱼雷表现。
- `anti_air_power`：防空能力，影响防空圈、敌机拦截和空袭削弱。
- `aviation_power`：航空能力，影响舰载机规模、空袭、侦察和出击效率。
- `weapon_mounts`：装备底座列表，描述火炮、鱼雷、防空、航空等装备的底座数量、装填、射角和目标类型。
- `main_weapon`：主武器引用，MVP 可作为兼容字段。
- `torpedo_weapon`：鱼雷武器引用，MVP 可作为兼容字段。
- `anti_air_weapon`：防空武器引用，MVP 可作为兼容字段。
- `air_wing`：舰载机或航空队引用。
- `skill_id`：主动技能标识。
- `is_flagship_candidate`：是否可作为旗舰。

这些能力值不直接等同于最终伤害。最终结果还需要结合武器配置、射程、装填、命中、目标装甲、目标机动、侦查状态和技能修正。

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

MVP 约定：

- 主炮和鱼雷必须使用射角。
- 防空可先简化为 360 度范围。
- 航空可先使用固定出击点和目标区域。
- 反潜装备字段预留，第一版不强制实现。

## 4. 舰种枚举

```text
Destroyer
LightCruiser
HeavyCruiser
Battleship
Carrier
Submarine
```

## 5. 关卡配置

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

## 6. 技能配置

基础字段：

```text
id
display_name
cooldown
target_type
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
- `effect_type`：效果类型，例如炮击强化、鱼雷发射、空袭、防空强化、闪避提升。
- `effect_value`：效果数值。
- `duration`：持续时间，瞬发技能可为 0。
- `vfx_id`：表现资源标识。
