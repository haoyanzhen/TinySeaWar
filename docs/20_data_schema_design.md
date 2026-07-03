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
base_speed
speed
base_turn_speed
turn_speed
base_detection_range
detection_range
base_concealment_distance
concealment_distance
fire_concealment_multiplier
evasion
gunnery_power
torpedo_power
anti_air_power
aviation_power
max_oxygen
collision_radius
collision_half_extents
variant_tags
reference_ship_profile
weapon_mounts
primary_weapon_group_id
primary_weapon_control_type
ammo_selection_group_id
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
- `base_speed`：设计基线最大航速。
- `speed`：当前运行时最大航速。当前统一为 `base_speed * 0.5`。
- `base_turn_speed`：设计基线转向速度。
- `turn_speed`：当前运行时转向速度。当前统一为 `base_turn_speed * 0.5`。
- `base_detection_range`：设计基线侦查范围。
- `detection_range`：当前运行时侦查范围。当前统一为 `base_detection_range * 1.5`。
- `base_concealment_distance`：设计基线隐蔽距离。
- `concealment_distance`：当前运行时隐蔽距离，表示目标能被发现的最大距离，数值越小越难被发现。当前统一为 `base_concealment_distance * 1.5`。
- `fire_concealment_multiplier`：开火破隐比例。舰娘开火后，当前隐蔽距离按该比例放大。
- 开火后的再隐蔽时间不使用独立配置字段，运行时按 `实时 concealment_distance / 实时 speed` 计算。
- `evasion`：闪避能力。
- `gunnery_power`：火炮能力，影响主炮、副炮和炮击技能。
- `torpedo_power`：鱼雷能力，影响水面鱼雷、潜艇鱼雷和部分航空鱼雷表现。
- `anti_air_power`：防空能力，影响防空圈、敌机拦截和空袭削弱。
- `aviation_power`：航空能力，影响舰载机规模、空袭、侦察和出击效率。
- `max_oxygen`：最大氧气值，主要用于潜艇；非潜艇可为空或 0。
- `collision_radius`：旧圆形碰撞兼容值，同时保留给当前地形导航安全距离与旧数据回退；不再是舰船、炮弹和鱼雷相交判定的真源。
- `collision_half_extents`：随航向旋转的舰装碰撞椭圆半轴 `[纵向, 横向]`。纵向直径应接近运行时舰装绘制宽度；炮弹落区、鱼雷扫掠、舰船重叠分离和鼠标选取统一读取该字段。
- `variant_tags`：舰娘变体标签，例如 `FastScout`、`TorpedoSpecialist`、`AAEscort`、`HeavyArmor`、`LongRangeGunnery`。
- `reference_ship_profile`：现实舰船或舰型参考标识，只用于设计说明和调参依据，不作为强制模板。
- `weapon_mounts`：装备底座列表，描述火炮、鱼雷、防空、航空等装备的底座数量、装填、射角和目标类型。
- `primary_weapon_group_id`：按 `E` 控制的主要武器组。一个角色最多一个；没有可控主要武器时为空。
- `primary_weapon_control_type`：主要武器交互类型，可为 `Torpedo`、`BattleshipMainGun`、`AviationSquadron`、`OtherMainWeapon`。
- `ammo_selection_group_id`：按 `Q` 切换 HE/AP 的火炮组。没有双弹种时为空；该组可以与 `primary_weapon_group_id` 不同。
- `skill_id`：主动技能标识。
- `is_flagship_candidate`：是否可作为旗舰。

这些能力值不直接等同于最终伤害。最终结果还需要结合武器配置、射程、装填、命中、目标装甲、目标机动、侦查状态和技能修正。

兼容说明：

- 旧字段 `detectability` 不再作为主字段使用。MVP 以 `concealment_distance` 表达隐蔽能力。
- 潜艇下潜时可以使用状态修正降低 `concealment_distance`，不需要单独的水下侦查公式。
- 新代码不再使用 `main_weapon`、`torpedo_weapon`、`anti_air_weapon`、`air_wing` 或 `scout_wing` 作为独立入口，所有武器统一由 `weapon_mounts` 引用。

## 3. 装备底座配置

装备底座用于描述舰娘实际如何攻击。舰娘的分项能力决定擅长方向，装备底座决定攻击节奏、覆盖范围和可攻击目标。

基础字段：

```text
id
mount_type
display_name
weapon_group_id
control_mode
targeting_mode
ammo_type
mount_count
shots_per_mount
reload_time
base_range
range
minimum_range
fire_arc_center
fire_arc_degrees
fire_arcs
mount_fire_arcs
full_salvo_fire_arcs
turret_turn_speed
base_projectile_speed
projectile_speed
spread
torpedo_lane_spacing
torpedo_angular_sigma_ratio
mount_launch_interval
base_impact_radius
impact_radius
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
- `weapon_group_id`：同一物理底座或逻辑武器组的稳定 ID。HE/AP 模式必须使用相同组 ID。
- `control_mode`：控制方式，可为 `ManualPrimary` 或 `Automatic`。前者只响应玩家主要武器命令，后者按领域规则自动开火。
- `targeting_mode`：目标方式，可为 `Entity`、`Direction`、`Area` 或 `AutomaticArea`。手动主炮和空袭使用 `Area`，手动鱼雷使用 `Direction`。
- `ammo_type`：弹药类型，可为 `HE`、`AP` 或 `None`。鱼雷、航空、防空和无弹种切换的特殊武器使用 `None`。
- `mount_count`：同类底座数量，例如三座三联装主炮可写为 3。
- `shots_per_mount`：每个底座一次攻击发射数量，例如三联装可写为 3。
- `reload_time`：装填时间。
- `base_range`：角色数值设计中的首轮射程基线，用于保留调参来源。
- `range`：当前运行时最大射程，也是领域判定与 UI 绘制的直接真源。当前全武器实机调节统一为 `base_range * 1.5`。
- `minimum_range`：最小射程，可选。
- `fire_arc_center`：射角中心，通常相对舰娘航向或舰装底座方向。
- `fire_arc_degrees`：射角宽度。
- `fire_arcs`：可选的聚合多扇区射角数组，每项包含相对舰首的 `center` 与总宽度 `degrees`。它是非鱼雷武器的运行时射角真源，也是鱼雷配置的兼容摘要；手动鱼雷的权威射界改由 `mount_fire_arcs` 提供。
- `mount_fire_arcs`：手动鱼雷必填的逐底座射界数组，长度必须等于 `mount_count`。每项包含唯一 `mount_id` 和非空 `fire_arcs`。运行时合法性、瞄准叠层和底座选择以此字段为真源；聚合 `fire_arcs` 只作兼容摘要。舷侧管组只能声明自身一舷，中心线管组可声明左右舷。
- `full_salvo_fire_arcs`：多底座舰炮全部底座都能指向目标的齐射扇区。它必须是 `fire_arcs` 或兼容单扇区射界的子集，仅用于表达全底座齐射区与后续逐底座结算；瞄准界面以深绿色显示。
- `turret_turn_speed`：炮塔、鱼雷管或装备朝向调整速度。
- `base_projectile_speed`：武器配置中的炮弹、鱼雷、舰载机等攻击速度设计基线。
- `projectile_speed`：当前运行时攻击速度，也是炮弹飞行时间、鱼雷推进和航空编队移动表现的直接真源。当前统一为 `base_projectile_speed * 0.5`。
- `spread`：武器散布角。舰炮以它和实际发射距离计算椭圆高斯 sigma，每发独立抽样；鱼雷则把它解释为单座底座的联装总散布，并按 `torpedo_lane_spacing`、运行时 `range` 和 `shots_per_mount` 反算。两类武器不得再把全舰发数均匀塞入同一理想扇面或落点横排。
- `torpedo_lane_spacing`：鱼雷相邻中心雷道在运行时最大射程处的弦长，当前基线为 `80`。
- `torpedo_angular_sigma_ratio`：鱼雷基础角误差标准差相对相邻理想雷道张角的比例，当前强制基线为 `0.20`。每枚鱼雷在发射时独立抽样。
- `mount_launch_interval`：同一鱼雷武器组相邻两座底座发射的最小间隔，必须至少 `1s`。
- `base_impact_radius`：舰炮落点圆的设计基线半径。
- `impact_radius`：海域攻击的运行时结算半径。舰炮当前统一为 `base_impact_radius * 0.5`；空袭保留自身配置，鱼雷可为空或 0。
- `accuracy_modifier`：命中修正。
- `target_types`：可攻击目标类型，例如 `Surface`、`Air`、`Submerged`。
- `weapon_resource_id`：引用具体武器资源或表现资源。
- `armor_damage_modifiers`：对不同装甲厚度分档的伤害补正。
- `aircraft_config_id`：航空类底座引用的舰载机配置。

MVP 约定：

- 主炮和鱼雷必须使用射角。
- `mount_count > 1` 的舰炮必须配置非空 `full_salvo_fire_arcs`。
- `ManualPrimary` 鱼雷必须显式配置非空 `fire_arcs`；每个扇区的 `degrees` 必须大于 0 且不超过 360。
- `ManualPrimary` 鱼雷必须为每座底座配置唯一 `mount_fire_arcs`，并满足 `spread = degrees(2 * asin(torpedo_lane_spacing / (2 * range))) * (shots_per_mount - 1)` 与 `torpedo_angular_sigma_ratio = 0.20`。
- 鱼雷一次命令只选择一座合法、已装填底座；各底座独立冷却，同组使用 `mount_launch_interval` 节流。
- 防空可先简化为 360 度范围，但仍使用 `reload_time` 周期结算伤害。
- 航空可先使用固定出击点和目标区域。
- 反潜装备用于攻击已发现的下潜潜艇。
- 每名角色最多一个不同 `weapon_group_id` 的 `ManualPrimary` 武器组；同组 HE/AP 模式合计仍只算一个，其他武器组必须为 `Automatic`。
- HE 与 AP 若来自同一底座，必须拥有相同 `weapon_group_id` 和共享冷却组。
- 切换 `ammo_type` 只修改运行时选中模式，不重置或减少装填。
- 配置加载时必须校验角色引用的主要武器组存在且唯一，并校验 `BattleshipMainGun -> Area`、`Torpedo -> Direction`、`AviationSquadron -> Area` 的目标方式映射。

### 3.1 运行时武器选择状态

每场战斗的 `UnitState` 额外保存：

```text
selected_ammo_by_group
primary_weapon_group_id
control_authority
movement_assist_enabled
secondary_auto_fire_enabled
primary_auto_fire_enabled
primary_auto_fire_suspended
skill_auto_cast_enabled
player_route_waypoints
movement_state.waypoint_index
```

- `selected_ammo_by_group` 保存每个可切换炮组当前使用的 `HE` 或 `AP`。
- `control_authority`：`Player` 或 `EnemyAI`，用于选择控制策略，不改变阵营、武器或领域合法性。
- `movement_assist_enabled`：玩家单位普通移动是否允许受限辅助 AI 接管；默认 `false`。
- `secondary_auto_fire_enabled`：玩家单位非主要武器组是否允许自动攻击；默认 `true`。
- `primary_auto_fire_enabled`：玩家单位主要武器组是否允许受限 AI 提交主要武器命令；默认 `false`。
- `primary_auto_fire_suspended`：进入 `E` 手动瞄准时使用的单场瞬态互斥标记；它不改变 `primary_auto_fire_enabled` 的玩家偏好，退出瞄准后清除。
- `skill_auto_cast_enabled`：玩家单位固定为 `false`，不提供玩家可写配置或开关。敌方自动技能由完整 AI 策略决定，不复用该字段冒充玩家开关。
- `player_route_waypoints` 保存玩家显式添加的连续途径点；当前导航段索引复用 `movement_state.waypoint_index`。两者只属于单场战斗状态。
- 运行时选择不得写回 Definition。
- 已创建的攻击请求保存发射时的武器模式，后续切换不能改变在途攻击。

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

本节只定义公式配置需要存储的字段。具体计算顺序见 `docs/12_combat_formula_design.md`，MVP 初始参数见 `docs/13_balance_baseline.md`。

基础字段：

```text
id
attack_type
design_base_damage
base_damage
design_power_coefficient
power_coefficient
design_armor_coefficient
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
- `design_base_damage`：角色与平衡设计使用的基础伤害基线。
- `base_damage`：局内基础伤害，当前统一为 `design_base_damage * 0.25`。
- `design_power_coefficient`：分项作战能力参与设计伤害的系数基线。
- `power_coefficient`：局内作战能力伤害系数，当前统一为 `design_power_coefficient * 0.25`。
- `design_armor_coefficient`：设计量纲下的装甲固定减伤系数。
- `armor_coefficient`：局内装甲固定减伤系数，当前统一为 `design_armor_coefficient * 0.25`；它与两个伤害项同步缩放，避免换算后装甲异常压制所有攻击。
- `evasion_coefficient`：闪避参与命中或受击概率的系数。
- `accuracy_coefficient`：武器命中修正参与命中的系数。
- `area_damage_chance`：范围技能对未发现目标造成伤害的概率。
- `distance_penalty_coefficient`：距离对命中率的惩罚系数。
- `hit_rate_min`：命中率下限。
- `hit_rate_max`：命中率上限。

### 8.1 投射物配置

实体投射物基础字段：

```text
id
behavior
base_speed
speed
lifetime
collision_radius
minimum_detection_distance
target_types
destroy_on_hit
pierce_count
```

- `minimum_detection_distance`：鱼雷进入敌方单舰该距离内时自动被其观测。所有鱼雷型号必须为正数；非鱼雷投射物可省略。
- 该字段是直接运行值，不套用通用距离倍率。技能通过观察舰状态中的 `TorpedoDetectionDistance` 修正它，不修改投射物 Definition 或 State 中的原始值。
- 观测成功后把投射物 ID 写入 `known_projectiles_by_faction`，阵营快照只返回己方投射物和该集合中的敌方投射物。

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

海面调色配置保存在 `data/environments/ocean_palettes.json`。关卡 `map.ocean_palette` 引用一个共享条件 ID：表现层据此选择海面与天气资产，Domain 据此从 `data/environments/ocean_battle_condition_definitions.json` 解析天气和时段战斗基线。palette 不改变硬碰撞或射程定义，但会通过 `TerrainContext` 影响侦查、移动、命中和航空条件。

海面调色基础字段：

```text
display_name
time_of_day
weather
base_texture
clear_glint_texture
weather_cloud_texture
foam_texture
rain_line_texture
rain_ripple_texture
storm_shadow_texture
lightning_mask_texture
snow_flake_texture
snow_haze_texture
deep_color
surface_color
shallow_color
highlight_color
cloud_color
warm_reflection_color
wave_strength
sparkle_strength
cloud_opacity
warm_reflection_strength
animation_speed
ai_texture_strength
foam_strength
rain_strength
mist_strength
lightning_strength
cloud_scale
cloud_cutoff
cloud_softness
wave_scale
foam_coverage
rain_angle
rain_density
rain_line_strength
rain_ripple_strength
squall_strength
snow_strength
snow_haze_strength
```

- `display_name`：海域显示名称。
- `time_of_day`：时间段，当前取值为 `day`、`dawn`、`dusk`、`night`。
- `weather`：气候，当前取值为 `clear`、`cloudy`、`overcast`、`rain`、`thunderstorm`。
- `base_texture`：海面基础可平铺纹理路径。
- `clear_glint_texture`：晴朗波光和稀疏浪尖母版。
- `weather_cloud_texture`：当前气候使用的云影母版，例如多云、阴云或雷雨暗云。
- `foam_texture`：白沫、风纹和强风浪碎波母版。
- `rain_line_texture`：雨线母版。
- `rain_ripple_texture`：雨点落海涟漪母版。
- `storm_shadow_texture`：雷雨风暴暗云母版。
- `lightning_mask_texture`：雷雨闪电冷光遮罩母版。
- `snow_flake_texture`：雪粒飘落母版，供独立天气层使用。
- `snow_haze_texture`：雪雾/风雪遮罩母版，供独立天气层使用。
- `deep_color`、`surface_color`、`shallow_color`：深水、主海面和浅层反光色。
- `highlight_color`：波纹、高光、雨点涟漪和闪电冷光参考色。
- `cloud_color`：云影乘色层参考色。
- `warm_reflection_color`：黄昏或低角度天光反射色。
- `wave_strength`：中小波纹可见强度。
- `sparkle_strength`：短高光和碎闪强度。
- `cloud_opacity`：云影覆盖强度。
- `warm_reflection_strength`：暖色反光强度。
- `animation_speed`：海面、云影和天气层的整体动画速度倍率。
- `ai_texture_strength`：AI/后处理海面母版混入强度。
- `foam_strength`：白沫、风纹和强风浪碎波强度。
- `rain_strength`：雨线和雨点涟漪强度。
- `mist_strength`：低雾和雨幕空气感强度。
- `lightning_strength`：雷雨闪电对海面和云影的短时冷白照亮强度。
- `cloud_scale`：云影采样尺度。数值越小，云团越大，适合阴云和雷雨。
- `cloud_cutoff`：云影成形阈值。数值越低，云影覆盖越多。
- `cloud_softness`：云影边缘柔和度。晴朗和多云更软，阴云和雷雨更硬。
- `wave_scale`：波纹频率尺度。雷雨和雨天使用更高数值形成更碎、更急的海面。
- `foam_coverage`：白沫出现阈值。数值越低，白沫覆盖越多。
- `rain_angle`：雨线方向，使用弧度。
- `rain_density`：雨线密度。
- `rain_line_strength`：雨线可见强度。
- `rain_ripple_strength`：雨点落海涟漪强度。
- `squall_strength`：风暴暗云和局部压暗强度，用于阴云、雨和雷雨的环境差异。
- `snow_strength`：雪粒强度。当前 20 个基础组合默认 0，寒冷海域扩展时启用。
- `snow_haze_strength`：雪雾强度。当前 20 个基础组合默认 0，寒冷海域扩展时启用。

### 11.1 陆地资产与碰撞边缘配置

陆地资产清单保存在 `assets/environment/land/land_asset_manifest.json`，碰撞候选边缘保存在 `assets/environment/land/land_collision_manifest.json`。候选边缘不进入运行时；正式审核几何位于 `data/terrain/terrain_templates.json`，经烘焙写入 `data/terrain/terrain_definitions.json`。未引用地形的四个开阔海域关卡继续保持原规则，只有关卡显式配置 `terrain_definition_id` 时启用地形系统。

陆地资产清单字段：

```text
generated_by
asset_family
runtime_target_size
background_policy
collision_policy
assets
```

单个陆地资产字段：

```text
id
display_name
role
texture
source_chromakey
collision_source
collision_manifest
runtime_status
```

- `texture`：透明 PNG 运行时纹理路径，位于 `res://assets/environment/land/`。
- `source_chromakey`：imagegen 原始纯色背景源图，用于重新去背景或 QA。
- `collision_source`：碰撞候选边缘来源，当前为透明 PNG 的 alpha 通道。
- `runtime_status`：当前状态。`design_asset_ready_collision_review_required` 表示美术资产已生成，但碰撞边缘仍需人工审核后才能进入玩法真源。

陆地碰撞候选字段：

```text
generated_by
edge_source
usage
assets
```

单个碰撞资产字段：

```text
id
texture
size_px
alpha_threshold
component_count
collision_polygons
```

单个碰撞多边形字段：

```text
area_px
bounds_px
polygon_px
```

- `alpha_threshold`：生成候选边缘时使用的 alpha 阈值。当前默认 24。
- `component_count`：透明图中超过面积阈值的连通组件数量。
- `collision_polygons`：按组件生成的候选多边形数组。
- `polygon_px`：以图片左上角为原点的像素坐标点列。导入关卡后需按摆放位置、缩放和旋转转换到世界坐标。
- `bounds_px`：组件像素包围盒，用于快速预览和编辑器选择。

约束：

- 不能直接把所有 alpha 边缘等同于硬碰撞。浅水 halo、白沫、视觉阴影和小装饰礁石需要在关卡编辑阶段按语义拆分。
- 不能从 PNG 透明度在运行时临时推断碰撞真相；运行时应读取已经审核过的多边形配置。
- 关卡地图仍是通行、碰撞、视线遮挡和地形成本的真源。美术资产只提供候选边缘和视觉外形。

### 11.2 正式地形、导航、环境区与设施配置

运行时配置文件：

```text
data/terrain/terrain_templates.json
data/terrain/terrain_definitions.json
data/terrain/navigation_definitions.json
data/environments/environment_zone_definitions.json
data/environments/ocean_battle_condition_definitions.json
data/facilities/facility_definitions.json
data/facilities/support_mission_definitions.json
data/facilities/minefield_definitions.json
```

`TerrainAssetTemplate` 使用资产局部坐标保存 `obstacles`、`regions`、`visual_regions` 和 `facility_anchors`；`TerrainMap` 保存烘焙后的世界坐标、`visual_instances`、出生点以及导航/环境区/设施布局引用。硬地形 `block_mask` 显式使用 `ShipMovement`、`TorpedoTravel`、`ShellTravel`、`SurfaceOpticalLineOfSight`，水域 `region_type` 使用 `DeepWater`、`CoastalWater`、`ShallowWater`、`ReefOrSandbar`、`NavigationChannel`。`visual_regions` 只保存 `asset_semantic`、透明度、层级和多边形，不进入碰撞、视线或通行查询。

导航配置按碰撞半径和通行标签分 profile，玩家与 AI 只读同一份节点/边。环境区保存规则形状、方向、漂移速度、相对起点的 `drift_path`、强度、阶段、持续时间和公开趋势，不保存 Shader 参数；有路径时沿折线定速推进，无路径时才按 `heading` 直线漂移。设施 layout 只引用审核后的岸线挂点；设施 Definition 保存能力组合和规则字段，资产 manifest 只保存语义与路径。

`MinefieldDefinition` 必须保存 `terrain_definition_id`、审核多边形、`safe_channels`、`controller_facility_id`、所有权和 `known_by_faction`。正式阵营快照只包含该阵营已知或拥有的雷区；全量边界只允许进入全知调试快照。

场景战术结果使用以下正式扩展字段：

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

global_environment.sea_state_rules[]
  minimum_sea_state
  movement_speed_multiplier
  weapon_accuracy_modifier
  aviation_delay_multiplier
  aviation_condition

global_environment.tide
  initial_phase
  phases
  phase_duration
  open_phases

FacilityDefinition
  armor
  armor_thickness
  suppression_damage_threshold
  suppression_duration
  observation_range
  gunnery_power
  aviation_power
  weapon_id | weapon_ids
  reload_during_suppression
  service_profile

SupportMissionDefinition
  mission_type
  max_range
  effect_radius
  effect_duration
  blocked_aviation_conditions
  enemy_aviation_accuracy_modifier
  salvo_count
  weapon_id

MinefieldDefinition
  damage
  controller_rules.on_active
  controller_rules.on_suppressed
  controller_rules.on_destroyed
```

- `map.ocean_palette` 必须能解析为 `{weather}_{time}`，或由 `OceanConditionAliases` 映射到正式组合。当前兼容入口为 `day_clear -> clear_day`、`cloudy -> cloudy_day`、`dusk -> cloudy_dusk`。
- `ocean_palettes.json` 保存表现参数，`ocean_battle_condition_definitions.json` 保存战斗规则；二者共享 palette 语义但不能互相读取 Shader/规则字段。
- 天气和时段上下文先组合为全图环境基线，局部环境区随后叠加；光学倍率最终受 `minimum_optical_visibility_multiplier` 下限保护。
- `sea_state_rules` 按不超过最终海况的最高 `minimum_sea_state` 取一档；背风等区域先改变最终海况，再选择档位。
- `WeatherBattleProfile.context.wind_speed` 为非负风速标量；局部 `EnvironmentEffect.context.wind_speed_add` 可继续叠加。当前飑线使用 `+6`。
- 鱼雷环境误差倍率为 `clamp(1 + max(0, sea_state - torpedo_sigma_reference_sea_state) * torpedo_sigma_sea_state_step + max(0, wind_speed - torpedo_sigma_wind_threshold) * torpedo_sigma_wind_step, 1, torpedo_sigma_multiplier_max)`；当前字段值分别为 `1 / 0.35 / 4 / 0.06 / 3`。
- `tide` 使用固定阶段时长循环；`open_phases` 允许新进入潮滩，其他阶段只允许已经位于区内的单位撤离。
- `service_profile.service_type` 当前为 `Supply` 或 `Repair`。补给使用 `weapon_reload_recovery_ratio`、`skill_cooldown_recovery`；维修使用 `hp_restore_ratio`、`repair_cap_ratio`。
- `weapon_id` 必须引用现有 Weapon Definition。岸炮和空袭继续使用普通命中、装甲和伤害公式。
- `reload_during_suppression` 控制武器设施受压制期间是否继续装填；当前岸防炮为 `false`。
- `blocked_aviation_conditions` 当前支持 `Severe` 与 `Grounded`；`Restricted` 通过到达时间和命中修正表达，不等同于无条件禁飞。
- `controller_rules` 只切换绑定雷区状态。水雷触发、伤害、阵营知识和安全航道由独立水雷服务处理。

Godot 制作插件通过 `build_authoring_snapshot.py` 将正式模板或地图数据装入可编辑场景，并通过 `apply_authoring_snapshot.py` 回写。`editor_snapshot.json` 只是被忽略的交换文件，不是运行时真源；生产门禁会对模板、环境区、设施布局和雷区执行无损往返测试。

港湾关卡 `map` 新增可选字段：

```text
terrain_definition_id
navigation_definition_id
environment_zone_set_id
facility_layout_id
```

这些字段全部为空时，关卡按既有开阔海域规则运行。

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

AI 配置分为舰队方案、单舰模式和运行时状态。具体行为语义见 `docs/16_enemy_ai_behavior_design.md`。

运行时已建立 `data/ai/ai_profiles.json` 配置类别与加载校验。当前首轮 Profile 使用下列已消费字段；更完整的 doctrine、formation plan 和显式 group assignment 仍属于扩展契约。

```text
id
difficulty
decision_interval
skill_threshold
target_confirmations
route_candidate_count
coordination_threshold
effect_reservations
```

舰队 AI Profile 基础字段：

```text
id
doctrine_id
difficulty
common_rule_set_id
formation_plan_id
objective_policy_id
coordination_policy_id
group_assignments
unit_mode_overrides
```

字段含义：

- `id`：AI 配置唯一标识。
- `doctrine_id`：舰队战术方案引用，例如标准推进、旗舰固守、单翼突击或航空消耗。
- `difficulty`：决策质量档位，只影响决策间隔、评分项和协同程度，不修改战斗属性。
- `common_rule_set_id`：可选。通用行进、避碰、边界、搜索和地形利用规则引用；省略时使用开阔海域默认规则。
- `formation_plan_id`：可选。开局阵型、阵位职责、阵位容差和允许转换的阵型方案引用；省略时以关卡出生阵位形成弹性编组，不主动转换阵型。
- `objective_policy_id`：可选。关卡任务的设施价值、占领饱和、守点半径、中断和回退策略引用；不复制设施状态或地图几何。
- `coordination_policy_id`：可选。目标伤害预留、技能效果预留、协同窗口和过量伤害处理策略引用。
- `group_assignments`：战术编组、保护对象、侧翼和组内职责配置。
- `unit_mode_overrides`：按参战单位 ID 覆盖初始单舰模式和回退模式。

单舰 AI Mode 基础字段：

```text
id
movement_policy
attack_policy
skill_policy
detected_tactic_policy
preferred_range_ratio
exposure_tolerance
fire_discipline
target_weights
enter_conditions
exit_conditions
fallback_mode_id
minimum_hold_time
```

- `movement_policy`：行动策略，例如避战侦查、前锋对线、侧翼雷击或保持炮线。
- `attack_policy`：目标评分、追击限制、主要武器窗口和过量伤害规则。
- `skill_policy`：技能用途标签、释放阈值、保留条件和同类效果错峰规则。
- `detected_tactic_policy`：被发现后 `Attack`、`Defend`、`Kite` 的允许集合、评分修正、最短驻留和紧急退出规则。
- `preferred_range_ratio`：相对当前主要武器射程的期望距离带，不直接复制绝对射程。
- `exposure_tolerance`：允许持续暴露、承受局部威胁和脱队的风险阈值。
- `fire_discipline`：`FreeFire`、`SelfDefense`、`HoldUntilWindow` 或 `Silent`。
- `target_weights`：舰种、旗舰、航母、威胁、距离、武器适配和击沉收益等评分权重。
- `enter_conditions`、`exit_conditions`：模式进入与退出条件；条件只读取合法态势信息。
- `fallback_mode_id`：当前任务失效、完成或紧急脱离后的回退模式。
- `minimum_hold_time`：非紧急模式最短驻留时间，用于避免射程边缘反复切换。

通用 AI Rule Set 基础字段：

```text
id
navigation_policy
formation_policy
collision_policy
boundary_policy
avoidance_policy
search_policy
terrain_policy
environment_costs
projectile_observation_policy
```

- `navigation_policy`：短航路长度、重算间隔、转弯前减速和航点到达容差。
- `formation_policy`：舒适圈、修正圈、脱队圈、阵型转换冷却和阵位重排规则。
- `collision_policy`：预测时间、最小接近距离、让路优先级和卡住恢复规则。
- `boundary_policy`：软警戒距离、转出空间和贴边路径成本。
- `avoidance_policy`：鱼雷、持续危险区和已知环境威胁的规避权重与恢复时间。
- `search_policy`：残影置信度衰减、搜索扇区、搜索时限和回归条件。
- `terrain_policy`：是否允许寻找掩体、最低出口数、最大停留时间和地形类型权重。MVP 开阔海域固定禁用岛屿掩体。
- `environment_costs`：浅水、海峡、雷区、风暴等公开环境类型的通行或威胁成本。
- `projectile_observation_policy`：己方已发现投射物的反应窗、危险半径、置信度和规避恢复参数；不能授予对未发现投射物的读取权限。

地图负责提供碰撞多边形、可通行区域、视线遮挡和地形类型；AI Rule Set 只保存使用这些事实的偏好，不复制地图几何，也不能覆盖玩家与 AI 共用的通行合法性。

舰船定义可增加 `allowed_ai_mode_ids`，或由稳定的 `variant_tags` 映射可选模式。关卡只允许从该集合中选择初始和回退模式。AI 模式运行时的当前目标、编组记忆、残影置信度和切换原因属于单场战斗状态，不写回配置定义。

为兼容首轮原型，旧式 `target_priority`、`preferred_range` 和 `special_behavior` 可在加载时转换为一个匿名单舰模式；新配置不再把多个特殊行为压缩为单个字符串。

玩家受限辅助策略不读取敌方 AI Profile，首轮使用程序支持的固定策略 ID `player_assist_local_execution`。其允许层固定为领域约束、即时生存、玩家路径、局部执行控制和被发现动作；禁止关卡任务、编组、战略模式、天气收益和技能策略。关卡、角色和难度配置不得覆盖这些禁止项。

## 14. 技能配置

基础字段：

```text
id
display_name
cooldown
target_type
base_cast_range
cast_range
base_effect_radius
effect_radius
effect_type
effect_value
modifiers
effects
triggered_attacks
recon_zones
duration
description
design_values
vfx_id
ai_tags
ai_policy_id
implementation_status
unsupported_effects
```

字段含义：

- `id`：技能唯一标识。
- `display_name`：显示名称。
- `cooldown`：冷却时间。
- `target_type`：目标类型，例如自身、敌方、区域、旗舰。
- `base_cast_range`：设计基线释放距离。自身技能或无距离限制技能为 `0`。
- `cast_range`：当前运行时释放距离。当前统一为 `base_cast_range * 1.5`；自身技能或无距离限制技能保持 `0`。
- `base_effect_radius`、`effect_radius`：设计与运行时作用半径。它们与施法距离独立；区域中心最远可放到 `cast_range`，但只影响中心周围 `effect_radius` 内的对象。
- `effect_type`：效果类型，例如炮击强化、鱼雷发射、空袭、防空强化、闪避提升。
- `effect_value`：效果数值。
- `modifiers`：结构化增益/减益列表，复杂技能优先使用该字段。
- `effects`：当前结构化状态效果列表。除基础修正字段外，可声明 `consume_on_fire`、`persistent_until_consumed`、`consume_weapon_group_id`、`bind_selected_target`、`target_armor_classes`、`recipient_ship_classes`、`requires_submerged` 和 `requires_scouted_target`。
- `triggered_attacks`：技能直接产生的攻击波次，声明武器、波数、间隔、每波数量、蓄力、开火暴露、临时修正和命中后状态；仍经过公共落点、航空、防空、命中与伤害管线。
- `recon_zones`：技能部署的可被防空摧毁侦察区，声明视野半径、持续时间、航空单位 HP 和被击落后的额外冷却。
- `duration`：持续时间，瞬发技能可为 0。
- `vfx_id`：表现资源标识。
- `ai_tags`：可选。技能 AI 用途标签，例如 `Burst`、`Defense`、`Recon`、`Mobility`、`AreaSupport`；不改变技能效果。
- `ai_policy_id`：可选。引用程序支持的有限技能评估策略；不得包含可执行表达式。省略时敌方 AI 使用按目标类型分类的兼容策略。
- `implementation_status`：可选。取值 `supported` 或 `partial`，用于标记该技能的结构化效果是否已被当前战斗系统完整消费。
- `unsupported_effects`：可选字符串数组。记录已进入配置但尚无对应运行时机制的效果语义；不得将其误报为已生效。
- `design_values`：可选。保留角色数值文档中的完整技能描述，供审计和后续机制实现对照，不直接执行。

当前 48 名角色技能均要求 `implementation_status = supported` 且 `unsupported_effects` 为空；若后续新增尚未实现的说明项，必须恢复为 `partial`，不能仅写入文本。

技能状态在武器发射时保存修正快照，炮弹或鱼雷到达后不得读取已经过期的新状态。“下一轮”效果保存到指定武器组成功开火并随后消费；自动副炮不能抢先消费战列主炮校射。目标技能可把修正绑定到选中实体或装甲级别，攻击其他目标时不获得该部分收益。

MVP 约定：

- 技能冷却从开局起算。
- 技能可以不需要目标，也可以是目标指向性技能。
- 技能不设计射角。

## 15. 增益与减益配置

基础字段：

```text
stat
operation
value
category
stack_group
stack_rule
source_type
duration
limit_min
limit_max
```

字段含义：

- `stat`：被修改属性，例如 `ReloadSpeed`、`Damage`、`AccuracyPoint`、`WeaponSpread`、`Evasion`、`Armor`、`DetectionRange`、`ConcealmentDistance`、`TorpedoDetectionDistance`。
- `operation`：运算类型，可为 `FlatAdd`、`PercentAdd`、`StateMultiply`、`IndependentMultiply`。
- `value`：修正值。百分比使用小数，例如 `0.20` 表示 `+20%`。
- `category`：增益类别，例如 `GunDamage`、`TorpedoDamage`、`AllDamage`、`AntiAirReloadSpeed`。
- `stack_group`：叠加组。同组效果根据 `stack_rule` 处理。
- `stack_rule`：叠加方式，可为 `Add`、`Highest`、`Refresh`、`Replace`。
- `source_type`：来源，例如技能、阵型、状态、关卡或装备。
- `duration`：持续时间，永久效果可为 0 或使用专用标记。
- `limit_min`：该属性最终下限，可选。
- `limit_max`：该属性最终上限，可选。

MVP 约定：

- 普通技能默认使用 `FlatAdd` 或 `PercentAdd`。
- 阵型、潜航、损伤状态默认使用 `StateMultiply`。
- `IndependentMultiply` 只用于明确标记的少量核心技能。
- 命中率增益使用 `AccuracyPoint`，表示增加百分点，不使用命中倍率。
- 装填增益使用 `ReloadSpeed`，不使用普通的装填时间百分比减少。
- 鱼雷预警使用 `TorpedoDetectionDistance` 和距离值，不使用“提前秒数”；首轮只允许 `Self` 范围，发现后再由阵营共享。

## 16. 表现设置配置

当前运行时配置位于 `data/settings/presentation_settings.json`，定义窗口尺寸候选和战斗镜头缩放边界。

基础字段：

```text
id
window.logical_size
window.default_size
window.size_options
camera.default_zoom
camera.zoom_step
camera.min_visible_size
camera.max_map_visible_fraction
```

字段含义：

- `id`：MVP 固定为 `settings.presentation`。
- `window.logical_size`：界面设计使用的固定逻辑画布尺寸。窗口尺寸变化时，根窗口按比例缩放该画布，而不是改变界面布局坐标。
- `window.default_size`：首次启动使用的窗口宽高。
- `window.size_options`：开始界面允许玩家选择的窗口宽高列表；默认尺寸必须包含在列表中。
- `camera.default_zoom`：每场战斗开始时的镜头缩放倍率。
- `camera.zoom_step`：一次滚轮输入的缩放倍率，必须大于 `1`。
- `camera.min_visible_size`：最近视角仍需保留的最小世界像素宽高，MVP 为 `[500, 500]`。
- `camera.max_map_visible_fraction`：最远视角在每个轴上最多显示的地图比例，MVP 为 `2/3`。

窗口尺寸属于用户偏好，选中值保存到 `user://tiny_sea_war_settings.cfg`，不写回项目配置。镜头缩放属于表现层状态，不进入 Domain 战斗状态，也不影响模拟随机数。

### 16.1 战斗规则设置

`data/settings/combat_settings.json` 保存所有舰船共享、需要数据校验的战斗常量：

```text
id = settings.combat
gun_dispersion.sigma_scale
gun_dispersion.longitudinal_sigma_ratio
gun_dispersion.reference_ship_id
gun_dispersion.reference_weapon_id
gun_dispersion.reference_range
gun_dispersion.reference_spread_degrees
gun_dispersion.reference_battleship_length
```

- `sigma_scale` 必须为正；当前为 `0.5684105110424833`。
- `longitudinal_sigma_ratio` 必须位于 `(0, 1]`；当前为 `0.5`。
- 三个 reference 数值必须满足 `reference_range × radians(reference_spread_degrees) × sigma_scale = reference_battleship_length`，加载时强制校验。
- reference ID 只记录标定来源并接受引用校验；运行时所有舰炮仍使用同一组系数，不读取角色私有覆盖。

## 17. 公共战斗表现配置

当前运行时配置位于 `data/visuals/`，由 `AssetCatalog` 读取，供表现层按语义查询炮弹、鱼雷、舰载机、武器表现映射和 VFX 播放参数。

炮弹类 `projectile_visual` 可选字段：

```text
shell_trail_caliber_pixel_multiplier
shell_trail_width
shell_trail_duration
shell_trail_color_key
shell_trail_color_palette
```

字段含义：

- `shell_trail_caliber_pixel_multiplier`：炮弹曳尾长度倍率。运行时按 `武器口径 mm * 倍率` 计算像素长度，MVP 默认 `0.1`。
- `shell_trail_width`：曳尾线宽，仅影响表现。
- `shell_trail_duration`：曳尾淡出时间，仅影响表现。
- `shell_trail_color_key`：默认颜色键，例如 `clean_white`、`fire_yellow`、`sunset_red`。
- `shell_trail_color_palette`：颜色键到十六进制颜色的映射。

这些字段只属于表现层，不进入 Domain 伤害、命中、弹速、射程或碰撞计算。武器或 `weapon_visual` 可用 `shell_caliber_mm` / `caliber_mm` 显式覆盖口径；未配置时，表现层可从武器名称中的 `xxxmm` 读取，并按炮弹档位兜底。

## 18. 战斗模拟实验配置

当前实验清单位于 `data/simulations/experiments/`，由无图形战斗模拟器读取，不进入可玩关卡菜单，也不修改正式战斗 Definition。

首版字段：

```text
schema_version
experiment_id
description
simulation_kind
player_policy_id
enemy_policy_id
tick_seconds
maximum_ticks
side_swap
seed_plan
scenarios
output_directory
```

字段含义：

- `schema_version`：当前固定为 `1`，用于拒绝不兼容清单。
- `experiment_id`：稳定实验 ID，同时用于生成单局 `run_id`。
- `description`：报告中的实验说明。
- `simulation_kind`：当前使用 `FullBattleSimulation` 或 `RuleRegression`。
- `player_policy_id`、`enemy_policy_id`：分别声明双方策略。首版支持 `SessionAutonomy`、`BaselineAutopilot` 和 `LatestRuntimeAI`。`LatestRuntimeAI` 让对应阵营使用 `BattleSession` 当前完整量化 AI，包括目标评分、模式迟滞、局部战术、预判主要武器、技能收益和即时规避；正常玩家战斗默认仍使用玩家控制/受限辅助。旧式单一 `policy_id` 只作为双方相同策略的兼容字段。
- `tick_seconds`：固定模拟步长，必须为正数；正式对比使用与运行时一致的 `0.1` 秒。
- `maximum_ticks`：程序保护上限。达到上限记为 `GuardLimit`，不伪装成关卡超时结算。
- `side_swap`：为 `true` 时，每个场景和种子运行 `original` 与 `swapped` 两局。交换局将原敌方阵容放到玩家出生槽位，将原玩家阵容放到敌方出生槽位，同时保留各阵容的旗舰、角色和内部顺序。
- `seed_plan`：种子方案。`ExplicitList` 使用 `values`；`SequentialRange` 使用 `start` 和 `count`。
- `scenarios`：场景数组，每项包含稳定 `scenario_id` 和正式 `level_definition_id`，可选用 `seeds` 覆盖实验级种子。
- `output_directory`：报告输出目录。当前示例写入被 Git 忽略的 `artifacts/simulations/`。

首版实验必须引用正式关卡配置。Definition 参数覆盖、临时舰队和验收 Profile 在实现相应隔离校验前不得写入正式清单。
