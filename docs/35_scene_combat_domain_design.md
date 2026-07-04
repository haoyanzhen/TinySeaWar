# 场景对战斗影响的程序与 Domain 设计

## 1. 文档目的

本文定义场景环境进入战斗规则后的程序与 Domain 设计，覆盖：

- 岛屿、岸线和陆地对舰船、鱼雷、炮弹与水面视线的阻挡。
- 深水、浅水、航道和软地形的领域语义。
- 玩家与 AI 共用的移动合法性、路线规划和地形查询。
- 动态天气区域的权威状态与确定性推进。
- 岸防、观察、补给、机场等岸基设施的通用领域模型。
- 地形相关命令、事件、快照、拒绝原因和测试边界。

本文把 `docs/17_play_design.md` 中“环境应改变玩家计划”的趣味目标下沉为程序契约。它不定义具体地形数值、设施强度、关卡摆放、美术资产或 UI 样式。

相关文档：

- 核心战斗规则：`docs/10_game_core_mechanics.md`。
- 操作与瞄准：`docs/11_game_operation_design.md`。
- 地图和陆地候选数据：`docs/20_data_schema_design.md`。
- 第一阶段 Domain 边界：`docs/32_domain_design_phase1.md`。
- 战斗表现事件：`docs/33_domain_design_phase2.md`。
- AI 地形利用：`docs/16_enemy_ai_behavior_design.md`。
- 当前实现位置：`docs/34_implementation_map.md`。

本文设计已在 `level.prototype_harbor_3v3` 形成首个完整运行闭环：硬地形查询、共享导航、浅水/航道、动态环境战术结果、观察与岸炮、补给维修、机场支援、水雷、设施生命周期、AI 环境意图、表现、小地图、调试与 QA 均已接入。其余九套岛屿模板仍属于关卡编排与内容覆盖，不作为 Domain 主链路是否完成的替代指标，状态以 `docs/00_project_status.md` 为准。

### 1.1 当前实现基线

| 审计项 | 当前运行结果 | 主要入口 |
| --- | --- | --- |
| 全局时间天气 | `map.ocean_palette` 同时选择表现 palette 和天气/时段战斗 Profile；20 个正式组合与 3 个旧别名均可解析 | `TerrainContextService.configure()`、`ocean_battle_condition_definitions.json` |
| 高海况与背风水域 | 从基础海况向区域目标海况插值，最终海况决定航速、武器命中修正和航空延迟；背风区先降低最终海况再选规则档位 | `TerrainContextService.context_at()`、`BattleSession._update_movement()`、`_environment_accuracy_modifier()` |
| 航空条件 | 普通航空武器和机场任务读取起点/目标天气；恶劣条件增加到达时间，`Severe/Grounded` 拒绝任务，战斗机巡逻降低敌方航空命中 | `_can_fire_at_position()`、`FacilityService.request_support()`、`_resolve_support_mission()` |
| 潮汐通行 | `Flood/High` 开放潮滩，`Ebb/Low` 拒绝新进入；已在区内单位可撤离，离开后不能重新进入 | `TerrainContextService.movement_segment_access()`、共享 `RoutePlanner`、权威移动 |
| 海岸观察站 | 活跃且依赖合法时作为固定光学观察源，继续受隐蔽、海雾与岛岸视线阻挡；压制/摧毁后立即移除 | `FacilityService.observation_sources()`、`BattleSession._fleet_detects()` |
| 岸防炮 | 使用正式武器 Definition、阵营接触、射程、射界、岛岸阻挡、延迟炮击和 `DamageService`；压制、依赖失效或摧毁后停火 | `_update_facility_weapons()`、`_resolve_facility_attack()` |
| 补给与维修 | 补给恢复武器装填和技能冷却资源；维修恢复结构 HP 且受单场维修上限约束；离开服务区或设施失效会中断 | `FacilityService.advance()`、`_apply_facility_service()` |
| 机场任务 | 侦察生成限时航空观察区，巡逻生成限时航空防护区，空袭复用现有航空武器与伤害公式 | `_resolve_support_mission()`、`support_effects_by_id` |
| 水雷 | 连续检测进入雷区且排除安全航道；触发固定伤害、只触发单舰一次并向受害阵营公开边界；绑定控制站可停用或转移所有权 | `MinefieldService`、`_apply_mine_trigger()` |
| 设施生命周期 | 设施拥有 HP、装甲、压制阈值、恢复计时与不可逆摧毁态；依赖失效只关闭能力，不连锁摧毁或改旗 | `FacilityService.apply_damage()`、`suppress()`、`advance()` |
| AI 场景战术 | 敌方可争夺/激活已知设施、低耐久时寻找维修、自动申请机场任务、规避已知雷区并在无接触时寻找背风水域；所有意图仍转为普通命令 | `_ai_facility_plan()`、`_update_ai_support_intents()`、共享 `RoutePlanner` |

雷达站继续遵守 13.8 节约束：在独立雷达传感器规则建立前保持 `enabled = false`，不会用光学观察规则冒充雷达。十套岛屿均有审核模板，但当前仅港湾入口具备出生、导航、环境、设施和节奏验收；其余九套不虚构为“已完成关卡”。

---

## 2. 已确定规则

以下规则是本设计的固定前提：

1. 岛屿和岸边使用同一类硬地形语义。
2. 硬地形阻挡水面舰船，舰船不能穿越岛屿或驶入岸上。
3. 硬地形阻挡鱼雷，鱼雷命中岛屿或岸线后立即失效。
4. 硬地形阻挡炮弹，炮弹不能越过岛屿或岸线攻击其后的目标或海域。
5. 第一版不模拟炮弹凭借弹道高度飞越低矮岛屿；所有岛岸均视为完整炮弹阻挡体。
6. 硬地形阻挡水面光学视线，使岛后目标按现有侦查和残影规则处理。
7. 地形阻挡由 Domain 的地图几何决定，不由贴图透明度、Shader、`Area2D` 或表现节点决定。
8. 玩家、自动武器和 AI 使用同一组地形合法性查询，不存在只对某一方生效的碰撞或射界规则。
9. 没有配置战斗地形的关卡继续使用现有开阔海域规则，结果不应因本系统接入而改变。
10. 地形相关随机性必须使用战斗种子并可回放；硬地形碰撞本身不使用随机数。

这是一套服务玩法可读性的二维抽象，不追求现实中的完整弹道学或水动力学。

---

## 3. 分层边界

### 3.1 Domain

Domain 拥有会改变战斗结果的事实：

- 审核后的世界坐标地形多边形。
- 地形阻挡通道和水域语义。
- 舰船与地形的权威碰撞结果。
- 鱼雷和炮弹的地形阻挡结果。
- 水面视线遮挡结果。
- 动态环境区域的当前位置和生效状态。
- 设施所有权、运行状态、交互进度和支援合法性。
- 地形进入、离开、碰撞、投射物阻挡和设施变化事件。

Domain 不读取纹理像素，不依赖场景树、导航节点、Godot 物理回调或摄像机状态。

### 3.2 Application

Application 负责流程协调和低频规划：

- 从关卡 Definition 创建领域地形和设施状态。
- 把玩家目的地或 AI 移动意图转换为可执行短航路。
- 维护 AI 的环境任务、路线重算和战术记忆。
- 将领域命令按固定顺序送入 `BattleSession`。
- 生成阵营受限的快照和一次性事件。

路线规划可以使用导航图、可见图或网格，但规划结果必须交给 Domain 逐段验证。路线规划器不能绕过舰船吃水、碰撞半径或临时禁区。

### 3.3 Infrastructure

Infrastructure 负责：

- 加载和校验地图、地形、环境区和设施配置。
- 将已审核的关卡多边形转换到世界坐标。
- 构建只读空间索引和导航缓存。
- 保存战斗记录和固定种子回放所需数据。

`assets/environment/land/land_collision_manifest.json` 只提供候选边缘，不能直接成为运行时真源。正式地图必须保存人工审核后的语义多边形。

### 3.4 Presentation

Presentation 负责：

- 绘制陆地、岸线、浅水、天气和设施。
- 显示路径预览、不可通行区域、视线阻挡和武器拒绝原因。
- 消费地形碰撞、岸边命中和设施状态事件。
- 为调试模式显示领域几何和空间查询结果。

表现层可以镜像创建 `StaticBody2D`、`CollisionPolygon2D` 或导航可视化，但这些节点不能改变领域位置、投射物生命周期或伤害结果。

---

## 4. BattleState 扩展

场景战斗规则进入运行时后，`BattleState` 逻辑上增加：

```text
terrain_map
global_environment_state
environment_zones_by_id
facilities_by_id
support_missions_by_id
terrain_contact_cache
```

### 4.1 TerrainMapState

地形几何在单场战斗中默认不可变，可作为聚合根持有的只读值对象：

```text
map_id
world_bounds
obstacles_by_id
regions_by_id
facility_anchors_by_id
spatial_index
navigation_revision
```

- `obstacles_by_id` 保存硬地形和视线阻挡体。
- `regions_by_id` 保存深水、浅水、航道等水域区域。
- `facility_anchors_by_id` 保存设施与陆地/岸线的合法关系。
- `spatial_index` 是从审核后几何构建的 256 世界单位均匀网格；四类线段/扫掠查询只遍历命中单元的稳定候选集合，F9 绘制的也是这份 Domain 索引而非装饰网格。
- `navigation_revision` 在静态地图中固定；未来若允许地形破坏，改变后必须使路线缓存失效。

### 4.2 EnvironmentZoneState

动态软地形使用独立状态：

```text
zone_id
definition_id
shape
position
heading
drift_speed
drift_path
intensity
phase
remaining_time
active
```

软地形只保存战斗所需事实，不保存 Shader 参数、粒子密度或贴图引用。

### 4.3 FacilityState

设施是固定位置的领域实体：

```text
facility_id
definition_id
faction_id # 独立所有权维度
position
heading
life_state
operation_state
desired_operation_state
interaction_state
control_state
service_state
suppression_remaining
suppression_damage_accumulated
cooldown_remaining
charges_remaining
weapon_states
service_queue
```

设施是否拥有 HP、武器、服务队列或使用次数由 Definition 组合决定，不要求所有设施填写所有字段。

---

## 5. 地形 Definition 与语义

### 5.1 TerrainObstacleDefinition

硬地形定义建议包含：

```text
id
polygon
block_mask
height_class
source_asset_id
```

`block_mask` 是显式语义集合：

```text
ShipMovement
TorpedoTravel
ShellTravel
SurfaceOpticalLineOfSight
```

第一版岛屿和岸线统一启用以上四项。保留掩码的目的不是让第一版出现例外，而是为未来其他地形类型提供扩展位置。

### 5.2 TerrainRegionDefinition

水域和软通行区域建议包含：

```text
id
region_type
polygon
priority
access_tags
effect_profile_id
```

首轮语义至少区分：

- `DeepWater`：普通可通行水域。
- `CoastalWater`：近岸水域。
- `ShallowWater`：按单位通行标签判定。
- `ReefOrSandbar`：不可通行或特殊通行。
- `NavigationChannel`：关卡标记的主要航道。

区域重叠时按显式 `priority` 和固定 ID 处理，禁止依赖 JSON 或容器遍历顺序。

### 5.3 FacilityAnchorDefinition

设施挂点描述设施与陆地的战斗关系：

```text
id
position
heading
interaction_water_polygon
target_shape
shore_obstacle_id
```

- `interaction_water_polygon` 是舰船执行激活、补给或登陆交互的水域。
- `target_shape` 是设施可被攻击的领域形状。
- `shore_obstacle_id` 指向承载设施的岸线或岛屿。

设施可攻击形状必须经过人工审核，避免炮弹为了命中设施穿过同一岛屿的背面。

---

## 6. 几何约束与导入校验

### 6.1 多边形约束

运行时地形使用世界坐标简单多边形：

- 点数不少于 3。
- 不允许自相交。
- 不允许连续重复点或零长度边。
- 统一顶点绕序。
- 坐标必须位于允许的地图导入范围。
- 面积小于配置阈值的碎片不得进入硬碰撞。

一个视觉岛屿可以拆成多个简单多边形。带洞地形优先拆分为多个无洞组件，不在首轮几何服务中引入复杂布尔多边形。

### 6.2 世界变换

若关卡复用陆地资产，加载阶段统一应用：

```text
asset local polygon
  -> scale
  -> rotation
  -> translation
  -> reviewed world polygon
```

战斗开始后只读取转换完成的世界多边形。Domain 不在每次查询时重复处理资产坐标或场景节点变换。

### 6.3 边界规则

- 点恰好位于岸线上时视为进入硬地形。
- 线段擦过岸线时视为发生阻挡。
- 查询使用统一几何容差，不能由不同系统各自设置 epsilon。
- 同一距离出现多个命中时，按阻挡优先级和稳定 ID 决胜。

保守边界可以防止舰船、鱼雷或炮弹从多边形缝隙穿过。

---

## 7. TerrainQueryService

`TerrainQueryService` 是不依赖场景树的纯查询服务。建议提供：

```text
first_segment_hit(from, to, block_mask, sweep_radius = 0)
is_segment_clear(from, to, block_mask, sweep_radius = 0)
can_occupy_circle(center, radius, movement_tags)
resolve_circle_motion(from, displacement, radius, movement_tags)
regions_at(position)
movement_cost_at(position, movement_tags)
has_surface_line_of_sight(observer, target)
```

### 7.1 TerrainHit

所有线段和扫掠查询返回统一值对象：

```text
hit
obstacle_id
position
normal
fraction
distance
block_mask
```

- `fraction` 为从起点到终点的归一化首次命中位置。
- `normal` 用于舰船岸边滑动和表现反馈。
- 未命中返回明确 `hit = false`，不使用空字典表达多种含义。

### 7.2 空间索引

TerrainQueryService 可以使用均匀网格、BVH 或其他宽相加速，但必须满足：

- 索引只加速候选筛选，不改变精确几何结果。
- 候选按稳定 ID 排序后进行精确查询。
- 相同输入在不同帧率、机器和容器顺序下返回相同结果。
- 调试模式可以关闭索引并用全量查询校验结果一致性。

---

## 8. 舰船移动与岸边碰撞

### 8.1 移动命令

玩家和 AI 继续提交目标位置或移动意图，不直接提交未经验证的场景导航路径。

Application 流程：

```text
MoveCommand.target_position
  -> RoutePlanner 生成短航路
  -> Domain 校验每个航段
  -> 写入 MovementState.waypoints
```

若目的地位于陆地、不可进入浅水或完全不可达，命令被拒绝并返回稳定原因。不能把非法目标静默钳制到最近海面，否则玩家无法理解实际目的地。

### 8.2 权威移动碰撞

每个 Tick 更新舰船位置时：

1. 根据航向和速度计算期望位移。
2. 使用舰船碰撞半径对位移做圆形扫掠。
3. 没有命中则接受完整位移。
4. 命中硬地形则移动到首次接触前的安全位置。
5. 根据碰撞法线计算可选的沿岸切向剩余位移。
6. 再次校验切向位移，最多使用固定次数的碰撞迭代。
7. 仍无法前进则停止或进入卡住恢复状态。

硬地形扫掠与水深合法性必须同时检查整段位移。不能只检查航段终点，否则大吃水单位会在两个合法深水端点之间穿过中间浅水；路线直连、导航边、路径平滑、权威移动和沿岸滑动统一使用整段水深检查。

舰船中心不能仅做点与多边形判断。碰撞半径必须计入查询，避免大型舰体视觉上穿入岸线。

### 8.3 路线规划与最终合法性

路线规划器负责“如何绕行”，Domain 碰撞负责“绝不能穿过”。即使路线缓存错误或 AI 生成非法航点，Domain 仍必须阻止舰船进入陆地。

第一版推荐：

- 从已审核陆地多边形生成共享导航图或可见图。
- 按舰船半径和通行标签选择对应导航层。
- 玩家路径预览和 AI 路线使用同一规划结果。
- 目标、地形版本或单位偏离航路达到阈值时才重算。
- 局部避碰不能把舰船推入硬地形或非法浅水。

### 8.4 岸边碰撞结果

岸边碰撞默认只改变位置和移动状态，并提交 `UnitTerrainCollision`。是否造成搁浅、损伤或特殊状态属于后续战斗规则，不在本设计中自动引入。

---

## 9. 鱼雷与岛岸阻挡

鱼雷已经是具有位置、航向、速度和剩余航程的 Domain 实体。加入地形后，鱼雷更新必须从终点圆形检测改为连续扫掠检测。

### 9.1 每 Tick 更新

```text
start = projectile.position
end = start + heading_vector * movement

terrain_hit = first_segment_hit(
  start,
  end,
  TorpedoTravel,
  projectile.collision_radius
)

unit_hit = first_legal_unit_hit_on_sweep(start, end, projectile)
resolve earliest hit
```

### 9.2 命中优先级

- 比较地形和单位命中的 `fraction`，只处理最早命中。
- 地形更早：鱼雷移动到岸边接触点，提交 `ProjectileBlockedByTerrain`，立即移除。
- 单位更早：按现有鱼雷命中和伤害流程处理。
- 两者在统一容差内相同：硬地形优先，防止鱼雷隔着岸线命中贴岸舰船。
- 没有命中：移动到终点并扣除实际航程。

### 9.3 连续碰撞要求

- 不允许只检测鱼雷 Tick 结束位置，否则高速鱼雷可能穿过狭窄岛礁。
- 鱼雷圆形碰撞半径与舰船随航向旋转的 `collision_half_extents` 椭圆共同参与单位命中扫掠；岸线扫掠暂时继续使用兼容 `collision_radius`。
- 鱼雷与岸线接触后不反弹、不沿岸滑动、不穿透。
- 岸边失效不产生普通攻击伤害，也不继续搜索同 Tick 后方目标。
- 地形命中不消耗命中随机数。

---

## 10. 炮弹与岛岸阻挡

### 10.1 当前模型

当前火炮使用固定世界落点和延迟 `AttackRequest`，真实伤害在到达时间结算；炮弹飞行视图属于表现层。加入地形后不强制把全部炮弹改成逐 Tick Domain 实体。

### 10.2 开火合法性

所有火炮在创建攻击事实前执行：

```text
first_segment_hit(
  muzzle_or_unit_origin,
  intended_impact_position,
  ShellTravel
)
```

第一版规则：

- 线段没有命中硬地形：火炮可继续执行其他射程、射角、装填和目标校验。
- 线段命中岛屿或岸线：目标海域不可射击，拒绝原因为 `TERRAIN_BLOCKS_SHELL_PATH`。
- 手动主要武器因地形不合法时不消耗装填。
- 自动火炮将被地形阻挡的目标从合法候选中排除。
- AI 手动主炮命令经过同一校验。
- 炮弹不能从岛屿一侧攻击另一侧，即使目标由友军侦查发现。

### 10.3 齐射与散布

一轮炮击可能包含多个固定落点。规则建议分两级：

1. 玩家瞄准合法性使用齐射中心路径，保证操作反馈稳定。
2. 创建每发实际落点后，再分别查询发射点到该落点的地形阻挡。

若中心路径合法但某发散布落点被岸线截断：

- 该发在首次岸线接触点产生 `ShellBlockedByTerrain`。
- 该发不在原落点创建伤害请求。
- 同轮其他未被阻挡炮弹继续飞行和结算。

这样既不因为一发边缘散布取消整轮齐射，也不允许炮弹视觉穿岛后在另一侧造成伤害。

### 10.4 延迟攻击状态

每发延迟炮击至少保存：

```text
attack_id
source_unit_id
source_weapon_id
origin
intended_impact_position
resolved_impact_position
terrain_obstacle_id
resolve_at_time
blocked_by_terrain
```

由于首轮硬地形静态，阻挡在开火时确定，延迟到达时不重复改变结果。若未来允许地形破坏或移动障碍，必须引入 `navigation_revision` 和明确的飞行中重检规则，不能默认沿用静态假设。

### 10.5 岸基设施目标

设施 `target_shape` 可以位于或覆盖岸线。攻击设施时：

- 先求炮弹路径上的首个设施目标命中和首个硬地形命中。
- 只有设施命中早于地形命中，或在统一容差内被配置为岸线暴露目标时，炮弹才命中设施。
- 岛后、山后或岸线内侧且没有暴露目标形状的设施不能被水面火炮直接攻击。
- 炮弹不能为了命中设施忽略承载它的岛屿或岸线。

---

## 11. 水面视线与侦查

### 11.1 视线查询

现有侦查距离与隐蔽距离校验之前，增加水面视线条件：

```text
distance_and_concealment_valid
AND has_surface_line_of_sight(observer.position, target.position)
```

只要观察点到目标点之间首次命中启用了 `SurfaceOpticalLineOfSight` 的硬地形，当前观察者不能发现该目标。

### 11.2 阵营共享侦查

- 单个观察者被岛屿遮挡不影响其他具有清楚视线的友军观察者。
- 只要同阵营任一合法观察者发现目标，继续按现有规则阵营共享。
- 所有观察者失去视线后，目标进入现有残影流程。
- 残影只保存最后已知位置，不能沿岛后继续更新。
- 普通攻击不能锁定只存在于残影中的目标。

### 11.3 边缘与大体积单位

首轮使用单位中心点进行光学视线查询，以保持规则简单稳定。若后续需要表现大型舰体部分露出岬角，必须统一扩展为多个可见采样点，并同步玩家与 AI；不能只在表现层显示局部舰体却仍按中心点完全隐藏。

### 11.4 其他传感器

雷达、声呐、航空观察和岸基观察未来可以使用不同视线通道，但必须显式定义。未建立传感器分类前，不能通过角色例外绕过岛屿遮挡。

---

## 12. 浅水、航道与软地形

### 12.1 环境运行时结构

环境分为全图背景条件和局部区域两类：

```text
GlobalEnvironmentState
  ocean_palette
  weather
  time_of_day
  wind_vector
  base_sea_state
  optical_visibility_multiplier
  weapon_accuracy_modifier
  aviation_delay_multiplier
  aviation_condition
  sea_state_rules
  tide_phase
  forecast_revision

EnvironmentZoneState
  zone_id
  environment_type
  shape
  position
  heading
  drift_speed
  drift_path
  intensity
  phase
  active
```

- 全图状态表达整场共享的天气、昼夜、主风向、基础海况和潮汐阶段。
- `map.ocean_palette` 是关卡选择的共享条件 ID：Presentation 用它选择海面与天气层，Domain 用它解析 `WeatherBattleProfile` 和 `TimeBattleProfile`。双方读取同一 ID，但 Domain 不读取颜色、雨线密度或 Shader 参数。
- 5 种天气决定基础海况、天气能见度、武器操作和航空条件；4 个时段提供光照能见度以及克制的黄昏/夜间操作修正。首轮数值和 20 种组合定位见 `docs/18_facility_weather_effect_design.md`。
- 局部区域表达海雾、飑线、月光水域、强流区和背风水域等空间差异。
- `drift_path` 使用相对区域初始位置的折线点；运行时按 `drift_speed` 定速采样，走到终点后停留并等待阶段或持续时间规则处理。
- 同一局部区域可以引用全图状态，例如飑线按主风向漂移、背风水域削弱全图海况影响。
- 海面调色和天气 Shader 不是规则数值来源。`ocean_palette` 只负责关联两套经过校验的表现/规则配置，不能反向从画面亮度、雨线或闪电帧推断规则。

### 12.2 通行标签

Unit Definition 后续需要提供与舰种解耦的通行能力，例如：

```text
movement_tags
draft_class
can_submerge
```

`TerrainQueryService` 根据单位通行能力和区域 `access_tags` 判断合法性。舰种可以给出默认值，但 Domain 不应只用舰种枚举硬编码浅水规则。

### 12.3 近岸水域类型

近岸不是一种单独的减益，而是一组改变通行和任务关系的地形语义：

| 区域类型 | Domain 语义 |
| --- | --- |
| `DeepWater` | 默认水域；允许完整海上机动和需要深度的单位状态 |
| `CoastalWater` | 标记进入岸线、设施和受限航路影响的近岸范围，本身不自动施加固定减益 |
| `ShallowWater` | 按 `draft_class`、`movement_tags` 和潜航状态判断通行或状态限制 |
| `ReefOrSandbar` | 作为硬阻挡或特殊低速通行区，由关卡 Definition 明确选择，不随机触礁 |
| `NavigationChannel` | 可通行主航道，用于路线规划、AI 权重和关卡目标，不提供无条件速度加成 |
| `BayOrHarbor` | 允许设施交互、补给和维修挂点，并形成可封锁的有限出入口 |
| `LeeWater` | 岛岸背风区域，用于抵消部分全局风浪影响，不改变硬碰撞和视线 |

`CoastalWater`、`NavigationChannel` 和 `BayOrHarbor` 可以重叠。区域重叠只生成组合后的 `TerrainContext`，各系统不得重复应用同一语义。

### 12.4 TerrainContext

单位进入多个区域时，先由地形查询生成确定的 `TerrainContext`：

```text
region_ids
water_depth_class
movement_cost
current_vector
optical_environment_tags
sea_state_context
aviation_environment_tags
environment_effect_ids
facility_influence_ids
```

移动、侦查、航空和后续潜航系统只读取 `TerrainContext`，不各自重复进行点在多边形查询。

### 12.5 动态软地形通用规则

- 动态环境区在固定 Tick 中更新位置、强度和阶段。
- 区域漂移不读取 Shader 时间或渲染帧率。
- 单位进入、离开或区域强度跨过规则阈值时提交领域事件。
- 玩家和 AI 均可读取其阵营合法的当前环境状态与关卡允许公开的短期趋势。
- 软地形具体影响由独立效果配置和现有修正服务组合，不能写进表现脚本。
- 区域边界可以使用规则上的过渡带，避免单位跨过单条几何线时发生全部效果突变。
- 环境区域不直接修改 `base_stats`，只通过当前 `TerrainContext` 参与本 Tick 查询。
- 环境变化本身不消耗战斗随机数；只有其触发的既有命中、受击或其他随机规则按原流程取随机数。

### 12.6 海雾 `SeaFog`

海雾是局部光学环境区：

- DetectionService 在计算水面光学观察时读取观察者、目标和视线穿过的海雾上下文。
- 海雾影响观察条件，但不是硬地形；舰船、鱼雷和炮弹可以通过。
- 海雾不能绕过岛屿遮挡，也不能让近距离合法目标无条件永久消失。
- 目标离开有效观察后继续使用现有残影，不在雾中更新隐藏目标实时位置。
- 炮口暴露、后续雷达和其他传感器通过各自通道处理，不能把海雾写成对所有侦查方式的统一开关。
- AI 读取与玩家相同的阵营可见海雾和接触结果，不得利用雾中真实位置。

### 12.7 阵雨与飑线 `RainSquall`

飑线是可漂移的局部天气区：

- 按全图风向或关卡时间线推进，Domain 保存真实位置和阶段。
- 为光学观察和航空任务提供环境标签，不直接造成舰船伤害。
- 航空任务在创建、起飞和进入目标区域等合法节点读取天气条件，具体受影响环节由支援/航空规则定义。
- 飑线进入、离开地图以及强度阶段变化均使用固定事件，不依赖画面中的雨线位置。
- 关卡公开的短期趋势从同一状态推导，玩家与 AI 获得相同精度的预报信息。

### 12.8 强风与高海况 `HighSea`

高海况可以是全图基础状态，也可以由局部区域提高：

- MovementService、WeaponService 和航空/支援系统通过 `sea_state_context` 读取环境条件。
- 高海况只提供确定的规则上下文，不对舰船施加随机横移、随机转向或每 Tick 抖动。
- 不同单位如何响应海况由能力标签和效果配置决定，不能只按舰种名称散落硬编码。
- `LeeWater` 可以在岛屿背风侧降低局部海况上下文，为近岸路线提供稳定窗口。
- 风向同时作为天气漂移、后续烟幕和航空条件的共享事实，不在各系统复制一套风向。
- 当前档位由 `global_environment.sea_state_rules` 配置。区域 `intensity` 表示从全图基础海况向目标海况的插值，而不是直接乘以海况编号；这保证中等强度高海况不会因取整退回基础值。

### 12.9 月光水域与昼夜 `MoonlitLane`

昼夜属于 `GlobalEnvironmentState`，月光水域属于局部区域：

- DetectionService 使用昼夜和月光标签调整水面光学观察条件。
- 月光区不是硬视线来源，不穿透岛屿，也不替代合法观察者。
- 单位是否处于月光区由 Domain 位置查询决定，不能由屏幕亮度决定。
- 探照灯、照明弹和燃烧设施等主动照明未来可以生成限时环境区或观察效果，必须有稳定来源实体和持续时间。
- AI 只使用阵营已知的光照状态，不读取 Presentation 的曝光或色彩结果。
- 全局时段的光学倍率为白天 `1.00`、凌晨 `1.03`、黄昏 `0.90`、夜间 `0.72`；月光水域在全局结果上乘以 `1.18`，不会把夜间直接改写成白天。

### 12.10 强流与潮汐 `StrongCurrent`

海流是具有方向和强度的局部向量场：

- 舰船期望位移先由自身推进产生，再叠加 `TerrainContext.current_vector`，最终统一做岸线扫掠碰撞。
- 海流不能把舰船推入硬地形；碰撞后仍按岸边停止/滑动规则处理。
- 鱼雷若受海流影响，使用同一向量场推进，并以实际轨迹累计航程和执行扫掠碰撞。
- 路线规划器使用海流估算通行成本，但 Domain 以每 Tick 实际位移为最终真相。
- 潮汐阶段可以切换某些浅水区域的通行状态或海流 Definition；切换前由关卡公开趋势提供预告。
- 潮汐变化不能让已经位于区域内的舰船瞬间进入非法状态；需要定义撤离、限制或过渡规则，并由 Domain 状态机执行。
- 当前港湾潮汐每 45 秒推进一个阶段，顺序为 `Flood -> High -> Ebb -> Low`；前两阶段开放，后两阶段限制新进入。共享路线和权威移动都执行同一检查。

### 12.11 环境效果应用顺序

一次环境上下文计算建议按以下顺序：

```text
Ocean palette ID
  -> 天气基础条件
  -> 时段光照条件
  -> 全图风、潮汐和关卡参数
  -> 静态水域与近岸区域
  -> 动态局部环境区
  -> 岛岸遮挡和背风关系
  -> 设施影响区
  -> 生成 TerrainContext
```

各战斗服务只读取最终上下文和明确效果引用。相同 `effect_id` 在重叠区域中按配置的叠加规则处理，不能因为区域重叠次数被重复应用。

正式组合规则：

- 天气和时段的光学倍率先相乘，局部海雾、飑线或月光继续乘算，最终限制在 `0.45-1.25`。
- 武器命中修正相加；航空延迟相乘；航空条件按 `Normal < Restricted < Severe < Grounded` 取最严重等级。
- 天气提供基础海况，局部高海况/背风区改变最终海况，`sea_state_rules` 只按最终海况应用一次。
- 全局条件进入没有局部地形配置的开阔海域；局部环境不是全局天气生效的前置条件。
- 快照保存 `ocean_palette`、规范 palette、天气、时段和组合来源，供 HUD、调试和回放核对。
- `ocean_palette` 在战斗创建时锁定。仅用于美术 QA 的表现层 palette 热切换不改变 Domain；正式玩法若需要天气转场，必须新增带 Tick 和事件的全局环境状态变更，而不是直接调用 Shader 接口。

---

## 13. 岸基设施领域模型

### 13.1 通用能力组合

设施不建立观察站、岸炮、补给点、机场各一套完全独立生命周期。建议由通用能力组合：

```text
Detectable
Damageable
Suppressible
Interactable
Ownable
WeaponPlatform
ObservationSource
SensorSource
CommandRelay
ServiceProvider
SupportMissionProvider
HazardController
```

不同设施只选择所需能力与配置。

### 13.2 五类操作模式与状态

每个 `FacilityDefinition` 通过 `operation_modes` 组合以下职责，模式各自拥有数据、状态和命令，不共享一个近距离交互事务：

| 模式 | 领域职责 | 命令入口 |
| --- | --- | --- |
| `AreaControl` | 单执行舰控制、争夺与所有权变化 | `DeclareFacilityControlCommand` |
| `BerthingService` | 泊位、低速/位置/朝向、占用和服务 | `RequestFacilityServiceCommand` |
| `RemoteCommand` | 支援或布雷的状态、阵营、依赖、次数、冷却、航程和环境校验 | 对应远程任务命令 |
| `AutomaticOperation` | 观察、岸炮、雷达、通信和已部署实体自行运行 | 无重复使用命令 |
| `CombatDisposition` | 公共攻击、命中、伤害、压制和摧毁 | 普通攻击命令 |

区域控制使用 `control_state = {executor_unit_id, faction_id, progress, duration, entered_area}`；服务使用 `service_state = {unit_id, service_type, progress, duration}`；设施交互显示态使用 `Idle | Controlling | Contested | Moored | Docked | Servicing | Interrupted`。`Approaching` 属于单位任务，不写入设施占用状态。

区域控制先声明意图，执行舰进入交互水域后自动累计。MVP 每个设施同时只接受一艘控制执行舰，友舰不叠加速度；敌舰进入同一控制水域时进度暂停并显示 `Contested`。靠泊服务必须在申请时通过所有权、运行状态、依赖、泊位、位置、低速、占用和必要朝向检查。

设施四个状态维度彼此独立：`life_state = Alive | Destroyed`，`faction_id` 保存所有权，`operation_state` 保存运行状态，`interaction_state` 保存当前控制或服务占用。

设施通用运行状态：

```text
Dormant
Active
Suppressed
Silent
Disabled
```

状态不变量：

- `Destroyed` 只属于生命状态；对应运行态必须为 `Disabled`，不可恢复，除非未来战斗规则明确支持重建。
- `Suppressed` 设施不执行武器、观察、服务和支援任务。
- `Active` 必须同时满足生命、期望运行态、依赖状态和同阵营依赖；依赖失效时进入 `Silent` 或 `Disabled`，依赖恢复时重新计算。
- 压制不改变 `faction_id`；压制恢复、区域控制完成和依赖状态/阵营变化都重新计算合法运行态。
- `destroyable=false` 的设施使用 `damage_floor_ratio` 限制 HP 下限，超出伤害产生 `FacilityDamageLimited`；所有 `suppressible=true` 设施按累计伤害跨越阈值进入压制。
- 所有权变化、控制完成、服务、压制和摧毁必须提交领域事件。
- 设施不能由 Presentation 直接改旗或重置冷却。

### 13.3 交互命令

正式命令：

```text
DeclareFacilityControlCommand
RequestFacilityServiceCommand
CancelFacilityActionCommand
RequestSupportMissionCommand
```

控制声明只要求单位、阵营、设施与模式合法；舰船可以先声明再接近。进度阶段持续校验交互水域、争夺、设施和执行舰状态。服务申请必须当场满足：

- 操作者存活且属于命令阵营。
- 操作者位于合法交互水域且泊位未被占用。
- 航速不超过服务配置上限，朝向落在配置容差内。
- 舰船类型或能力允许该交互。
- 设施状态允许激活、夺取或服务。
- 周围威胁、移动状态和中断条件满足关卡规则。

交互进度属于 FacilityState 或独立 InteractionState，不依赖舰船持续停在 UI 圆圈的表现判断。

普通区域控制和未建立靠泊的设施交互不改变舰船运动规则：接受交互意图时不清空既有航路、不把航速归零，也不抵消推进、水流、海况、碰撞或外力。舰船被自身运动或水流带出交互水域时，控制进度或尚未建立靠泊的服务立即按 `UNIT_LEFT_INTERACTION_AREA` 中断。只有维修泊位等明确进入 `Docked` 的靠泊服务，才可以按其独立契约提供定点保持。

- 普通玩家与 AI 使用 `DeclareFacilityControlCommand` 表达“控制/占领”，完成后同时取得所有权并进入合法运行态。
- `Activate` 只用于关卡初始化、脚本事件或特殊待激活设施，不作为普通水面舰语义。
- 补给和维修只使用 `RequestFacilityServiceCommand`，不改变设施所有权。
- `Suppress` 由攻击、状态或专用任务触发，不伪装成占领交互。
- `Destroy` 由 Damageable 设施的正常伤害与生命周期处理。
- 加固岸炮、机场等设施可配置为不可夺取，只能压制或摧毁。

### 13.4 海岸观察站

观察站作为固定 `ObservationSource` 参与 DetectionService：

- 使用自身阵营、位置、侦查能力和视线查询。
- `contact_type = Optical`，固定距离先乘天气、时段和观察点/目标点局部光学倍率，再与目标隐蔽距离共同限制发现。
- 被硬地形遮挡时不能观察岛后目标。
- 被压制或摧毁后从合法观察者集合移除。
- 不把隐藏目标实时位置直接写给岸炮；只通过阵营接触状态共享。
- 观察站控制只改变自身所有权与期望运行态，不递归改变通信、岸炮或其他设施。

### 13.5 岸防炮

岸防炮作为固定 `WeaponPlatform` 复用 WeaponService 的装填、目标、射界和攻击事实：

- 关卡初态使用显式 Profile：`enemy_active` 为敌方激活且普通水面交互锁定，`player_dormant` 为己方休眠且只能由己方完成激活。
- 耐久、防护与炮术属性通过 `durability_reference_id = ship.warspite` 解析经典战列舰基线，不在设施数据复制一套漂移数值。
- 炮塔通过 `weapon_mount_reference` 引用厌战 381mm AP/HE 的伤害、散布、穿深、装填和弹药规则，但覆盖为一座联装炮塔，每轮两发；中/重甲选 AP，轻甲/无甲选 HE。
- 没有移动状态。
- 目标必须由己方合法发现。
- 炮弹同样受岛屿和岸线 `ShellTravel` 阻挡。
- 固定炮位不能穿过承载岛屿攻击背面目标。
- 被压制后暂停开火和装填行为由设施规则明确处理。
- 岸炮 `destroyable=false`，HP 受伤害下限保护，攻击只产生实际伤害、受限反馈和累计压制，不得进入 `Destroyed`。
- 同阵营任一已声明通信依赖可用时运行；通信暂时受压制时进入 `Disabled`，恢复后重算；全部依赖被摧毁或转为异阵营后进入 `Silent`。
- 岸炮不能读取隐藏敌舰位置或绕过命中与伤害服务。
- 岸炮控制与激活只改变自身，不转移或激活通信站及其他设施。

### 13.6 前沿补给点

补给点作为 `ServiceProvider`：

- 港湾默认中立、休眠，必须先通过区域控制取得所有权并激活；只接受同阵营舰船。
- 使用明确服务事务，申请时校验交互水域、最大入泊速度、朝向、运行态与单泊位占用。
- 服务开始时记录对象、类型和预计完成条件；第二艘舰在泊位释放前被拒绝。
- 舰船离开泊位、设施受击或设施被压制/摧毁时中断，当前 `progress_on_interrupt=Reset` 不保留部分进度。
- 服务完成后通过领域效果修改合法资源或状态。
- 不直接调用 UI、动画或角色配置文件。

港湾首轮基线由 Definition 的 `berthing_service` 配置：完成 7 秒补给后，当前武器装填进度恢复至就绪，并缩短 12 秒技能冷却；这些值是可调原型基线，不写死在设施服务中。

占领和服务只修改补给点自身与被服务舰船，不改变通信、岸炮、机场或其他设施的所有权和运行态。

### 13.7 近岸机场

机场作为 `SupportMissionProvider`：

- 玩家或 AI 提交同结构的支援请求。
- Domain 校验设施状态、使用次数、冷却、目标区域和环境条件。
- 成功后创建具有到达过程的支援任务或航空实体。
- 被压制、摧毁或条件失效时按支援任务规则取消、延迟或继续。

机场不能直接在目标区域瞬时修改 HP，也不能绕过现有侦查和攻击结算。

当前三种任务均有到达过程：侦察持续 18 秒、半径 620；战斗机巡逻持续 22 秒、半径 520，对敌方航空命中施加 `-0.28`；空袭使用 `weapon.enterprise_airstrike` 连续结算 3 次。正式数值保存在 `support_mission_definitions.json`。

### 13.8 雷达与通信站

雷达与通信站组合 `SensorSource` 和/或 `CommandRelay`：

- 雷达观察使用独立传感器通道，不复用光学观察的海雾标签冒充雷达规则。
- 地形是否阻挡雷达由传感器 Definition 显式声明；在该规则完成前，雷达站保持未启用状态。
- 通信站只扩展允许的命令、设施依赖或支援联络，不直接写入目标 HP、装填或命中结果。
- 主动工作、被压制和失去依赖时通过 FacilityState 改变能力集合。
- AI 与玩家从相同阵营快照读取雷达接触和通信可用性。

### 13.9 水雷控制站

水雷控制站组合 `HazardController`，控制关卡预先配置的 `MineFieldState`：

```text
minefield_id
polygon
owner_faction_id
operation_state
known_by_faction
controller_facility_id
```

- 控制站只能启用、停用或切换其明确引用的雷区，不能运行时任意生成全图水雷。
- 雷区位置、发现、扫除、触发和伤害由独立水雷规则负责，不由设施脚本直接扣血。
- 控制站被压制或夺取后的雷区状态必须由配置明确，不使用隐式猜测。
- 已知安全航道和雷区情报进入阵营快照，AI 不读取未发现雷区的真实边界。
- 港湾固定雷区单次触发伤害基线为 420，同一单位不会在同一雷区重复触发；控制站压制时雷区转为 `Dormant`，摧毁后转为 `Disabled`，夺取并激活后所有权随控制站转移。

### 13.10 港口维修泊位

维修泊位是独立 `ServiceProvider`，不与普通补给事务混为同一服务：

- 使用审核后的泊位水域和服务队列。
- 记录维修对象、服务类型、进度和中断原因。
- 只有设施、舰船和周边条件持续合法时推进。
- 修复内容、上限和是否能恢复结构 HP 由玩法与数值设计决定。
- 维修状态不能让舰船免疫攻击、碰撞或胜负判定。
- 港湾首轮基线为 9 秒服务、恢复最大 HP 的 28%，但单场岸基维修最高恢复到最大 HP 的 80%。

### 13.11 设施控制语义

设施结果统一区分：

```text
控制 Control：普通水面舰取得设施所有权并建立合法运行状态
特殊激活 Activate：仅供关卡初始化、脚本事件或特殊设施建立运行状态
压制 Suppress：暂时关闭设施能力
摧毁 Destroy：永久结束设施生命周期
```

程序上必须分别记录控制状态、所有权变化和运行状态，不能用单一“占领进度”同时表达全部结果。

### 13.12 设施依赖网络

设施可以通过显式依赖形成岸基支援网络：

```text
facility_dependencies
requires_all_active
requires_any_active
provided_capabilities
```

典型组合关系：

- 观察站或雷达站向岸防炮提供合法接触来源。
- 通信站向机场、岸炮或远程支援提供联络能力。
- 机场向舰队提供航空支援任务，但仍依赖自身状态与天气条件。
- 补给点和维修泊位各自服务舰船，不自动恢复其他设施。
- 水雷控制站只控制绑定雷区，不因其他设施存在获得额外伤害。

依赖图在加载时验证不存在非法循环。依赖失效只移除对应能力，不应默认把整条设施链全部摧毁或改旗。

---

## 14. AI 与路线规划

### 14.1 AI 可见视图

AI 可以读取：

- 地图公开的陆地、岸线、浅水和航道。
- 己方已知设施及其合法状态。
- 己方可见的动态环境区和关卡公开趋势。
- 己方单位完整状态与本阵营接触信息。

AI 不得读取：

- 隐藏敌舰的实时位置。
- 未发现敌方设施的完整状态。
- 玩家未来命令。
- 仅存在于 Presentation 的视觉遮罩或粒子位置。

玩家快照同样只公开本阵营已知设施。玩家从世界或小地图选择设施后提交的控制、服务、支援和布雷命令，与完整 AI 的对应命令进入同一 `FacilityService` 合法性、进度、中断、完成和效果结算。玩家受限辅助只可读取单位保存的 `player_facility_target_id` 并规划到该设施交互水域，不读取设施评分或替换目标。

完整 AI 的设施任务失败时清除执行任务并短期屏蔽同一设施，随后重新量化；同一单位对同一设施两次失败后本局放弃，任何单次设施任务连续占用最多 `12s`。机场支援与布雷是显式远程任务，仍校验设施状态、阵营、依赖、次数、冷却、航程、环境与目标区域。

### 14.2 共用合法性

- AI RoutePlanner 与玩家移动预览使用相同地图和通行层。
- AI 产生的路径仍由 Domain 每 Tick 碰撞验证。
- AI 火炮和鱼雷使用与玩家相同的地形阻挡查询。
- AI 不能因为拥有目标评分就隔岛锁定、开火或穿越岸线。
- AI 可按 `docs/16_enemy_ai_behavior_design.md` 选择环境任务，但任务只产生普通命令和移动意图。

### 14.3 路线代价

路线规划可以考虑：

- 路径长度和预计时间。
- 浅水或软地形的通行代价。
- 已知岸炮射界和持续危险区。
- 舰队编组、保护对象和目标方向。
- 航道拥堵与最小转弯空间。

这些属于 AI/Application 偏好，不能改变 Domain 的硬通行规则。

---

## 15. 命令、事件与拒绝原因

### 15.1 既有命令扩展

- `MoveUnitsCommand`：增加地形目标与航路合法性校验。
- `FirePrimaryWeaponCommand`：增加炮弹路径或鱼雷发射起点合法性校验。
- 自动攻击：增加水面视线和炮弹路径过滤。
- AI 主要武器命令：使用相同校验结果。

### 15.2 新事件

建议事件：

```text
UnitEnteredTerrainRegion
UnitExitedTerrainRegion
UnitTerrainCollision
ProjectileBlockedByTerrain
ShellBlockedByTerrain
SurfaceLineOfSightBlocked
SurfaceLineOfSightRestored
EnvironmentZoneChanged
EnvironmentForecastChanged
FacilityDiscovered
FacilityControlDeclared
FacilityControlCompleted
FacilityActionInterrupted
FacilityOwnershipChanged
FacilitySuppressed
FacilityRecovered
FacilityDestroyed
FacilityServiceStarted
FacilityServiceInterrupted
FacilityServiceCompleted
MineFieldStateChanged
SupportMissionRequested
SupportMissionStarted
SupportMissionCancelled
```

高频视线状态不要求每 Tick 发事件，只在状态发生变化时提交。

### 15.3 稳定拒绝原因

至少包含：

```text
TARGET_POSITION_ON_LAND
NO_NAVIGATION_PATH
TERRAIN_BLOCKS_MOVEMENT
TERRAIN_BLOCKS_SHELL_PATH
TERRAIN_BLOCKS_LINE_OF_SIGHT
WATER_DEPTH_NOT_ALLOWED
FACILITY_INTERACTION_NOT_ALLOWED
FACILITY_NOT_ACTIVE
FACILITY_SUPPRESSED
FACILITY_OUT_OF_RANGE
SUPPORT_MISSION_UNAVAILABLE
```

拒绝原因使用稳定英文枚举，中文显示由 UI 文本映射负责。

---

## 16. 固定 Tick 顺序

加入场景战斗规则后，一次 Tick 推荐顺序：

1. 收集并稳定排序玩家与 AI 命令。
2. 更新动态环境区的位置、阶段和公开状态。
3. 校验移动、主要武器、技能和设施交互命令。
4. 更新状态、装填、技能和设施冷却。
5. 根据航路更新舰船期望移动。
6. 处理舰船与硬地形、地图边界和其他单位的碰撞。
7. 使用扫掠查询更新鱼雷和其他领域投射物，处理最早地形/单位命中。
8. 更新阵营侦查，加入硬地形视线与观察站。
9. 按 AI 频率产生下一 Tick 战术命令。
10. 处理自动武器和已接受的手动武器请求，校验炮弹路径。
11. 处理延迟炮击到达、支援任务到达和攻击结算。
12. 推进设施交互、压制恢复和服务队列。
13. 应用伤害、沉没、设施摧毁和状态清理。
14. 检查胜负并提交事件和快照。

同一 Tick 中：

- 新发射鱼雷从下一 Tick 开始移动，延续现有确定性约束。
- 地形命中先于其后方同路径单位命中。
- 地形查询不消耗战斗随机数。
- 单位沉没或设施摧毁立即使其后续行为失效。

---

## 17. 快照与表现映射

### 17.1 静态地图数据

陆地、岸线、浅水和公开航道可由关卡 Definition 在进入战斗时一次性交给 Presentation，不必在每帧快照中重复复制全部多边形。

Presentation 读取的是只读地图数据；修改本地多边形不会改变 Domain 查询。

### 17.2 动态快照

战斗快照增加：

- 当前可见或公开的动态环境区状态。
- 设施阵营、运行状态、交互进度和可用性。
- 当前单位所在水域或环境标签。
- 可选的已计算路径预览和拒绝原因。
- 己方拥有或已经发现的固定雷区与安全航道；全知调试快照可以额外显示隐藏边界。

敌方隐藏设施和非公开环境信息按阵营过滤，调试全知快照与正式快照分离。

### 17.3 一次性表现

以下表现必须消费 Domain 事件：

- 舰船触岸或被路径阻挡。
- 鱼雷命中岛岸并消失。
- 炮弹在岛岸前终止并产生岸边命中。
- 设施激活、压制、恢复和摧毁。
- 支援任务开始、取消和到达。

炮弹飞行动画必须以 `resolved_impact_position` 为终点。若炮弹被岸线阻挡，表现层不能继续飞到原始目标点。

---

## 18. 目录与程序落点建议

```text
scripts/domain/
  terrain/
    terrain_map_state.gd
    terrain_obstacle.gd
    terrain_region.gd
    terrain_hit.gd
    terrain_context.gd
  facilities/
    facility_state.gd
    facility_interaction_state.gd
    support_mission_state.gd
  services/
    terrain_query_service.gd
    terrain_collision_service.gd
    facility_service.gd

scripts/application/
  navigation/
    route_planner.gd
    navigation_cache.gd
  battle_session.gd

scripts/infrastructure/
  data/
    terrain_definition_loader.gd
    terrain_definition_validator.gd
  spatial/
    terrain_spatial_index.gd

scripts/presentation/battle/
  terrain_view.gd
  facility_view.gd
  terrain_debug_overlay.gd
```

现有 `battle_session.gd` 可以先协调这些服务，但几何算法、设施状态机和路线规划不应继续全部堆入单一脚本。

---

## 19. 性能与确定性

### 19.1 性能目标

- 静态地形在创建战斗时预构建空间索引。
- 移动、鱼雷和视线查询只精确检测附近候选多边形。
- 侦查视线可以沿用低频更新，不必每渲染帧运行。
- 同一阵营相同观察对的短期视线结果可以按地形版本缓存。
- 路线规划低频执行，Domain 碰撞每 Tick 执行。
- 静态炮弹路径在开火时查询一次，不在飞行期间重复查询。

### 19.2 确定性规则

- 地形、设施、投射物和单位均使用稳定 ID。
- 查询候选和命中结果按距离、优先级、稳定 ID 排序。
- 使用统一几何容差。
- 不使用 Godot 物理引擎回调顺序决定领域结果。
- 动态环境使用固定 Tick 与战斗种子。
- 导航图和空间索引必须能从同一关卡 Definition 重建。

---

## 20. 配置校验

加载阶段至少拒绝：

- 自相交、退化、点数不足或越界的硬地形多边形。
- 同一地形重复 ID。
- 未知阻挡掩码、区域类型或通行标签。
- 浅水、航道或设施交互区完全落在硬陆地内。
- 舰队出生点或设施水上交互点位于不可通行区域。
- 设施引用不存在的岸线、效果、武器或支援定义。
- 岸炮炮口或设施暴露目标形状被自身承载地形完全封死。
- 路线图出口与视觉航道明显不一致。
- 动态环境区的移动时间线超出地图合法范围且没有消散规则。

美术候选边缘不能只因通过几何校验就自动升级为玩法真源，仍需要关卡设计人工确认通行、视线和射击结果。

---

## 21. 测试矩阵

### 21.1 几何与舰船

- 舰船正面驶向岛屿时停在碰撞半径外。
- 舰船斜向触岸时沿岸滑动且不会穿入多边形。
- 大小碰撞半径单位在同一岸线保持不同安全距离。
- 目标点位于陆地时移动命令被拒绝。
- 可达目的地能生成绕岛路径；完全封闭区域返回不可达。
- 局部避碰不能把舰船推入岸上。

### 21.2 鱼雷

- 鱼雷路径穿过岛屿时命中首个岸边并失效。
- 高速鱼雷单 Tick 跨过狭窄岛礁时仍被扫掠查询拦截。
- 舰船位于岛屿后方时不会被鱼雷隔岛命中。
- 舰船和岸线几乎同时命中时按统一规则由岸线优先。
- 地形命中不消耗命中随机数，不创建单位伤害。

### 21.3 炮弹

- 手动主炮瞄准岛后海域时返回地形阻挡且不消耗装填。
- 自动火炮不选择炮弹路径被岛屿阻挡的目标。
- AI 主炮不能越过岸线攻击目标。
- 齐射中心合法但单发散布撞岸时，只阻挡对应炮弹。
- 炮弹表现终点与 Domain 的岸边命中点一致。
- 岛后目标即使由友军发现也不能被水面炮弹穿岛命中。

### 21.4 侦查

- 距离和隐蔽均满足但中间有岛屿时，单个观察者不能发现目标。
- 另一友军拥有清楚视线时，阵营共享侦查仍能发现目标。
- 所有视线丢失后进入残影，残影不更新岛后真实位置。
- 目标重新离开遮挡后按正常规则重获。

### 21.5 区域与设施

- 单位进入和离开浅水/软地形只产生一次对应状态变化事件。
- 不具备通行能力的单位不能进入浅水。
- 海雾只影响配置的观察通道，不成为舰船或投射物硬障碍。
- 飑线按固定 Tick 和公开趋势移动，相同种子下轨迹一致。
- 高海况不产生随机横移，背风水域正确生成局部上下文。
- 月光水域只在合法视线存在时影响光学观察，不穿透岛屿。
- 海流影响舰船和配置为受流影响的鱼雷，但不能把它们推过岸线。
- 潮汐切换浅水状态时按过渡规则处理已在区域内的单位。
- 观察站被压制后不再提供发现来源。
- 岸炮被自身岛屿遮挡时不能攻击背面目标。
- 设施交互在条件失效时正确中断。
- 普通设施交互不清空航路、归零航速或抵消水流，驶出交互水域会中断；只有已建立 `Docked` 的靠泊服务可定点保持。
- `Control`、`Service`、`RemoteCommand`、`AutomaticOperation` 和 `CombatDisposition` 不混用状态、命令或进度。
- 雷达与通信站只提供已声明的传感器或联络能力。
- 水雷控制站只改变绑定雷区，且不泄露未发现雷区边界。
- 补给点与维修泊位使用独立服务事务和中断结果。
- 设施依赖失效时只关闭对应能力，不错误摧毁或改旗其他设施。
- 支援任务无法绕过设施状态、冷却和环境合法性。

### 21.6 回归与可重复性

- 未配置地形的现有 1v1、3v3、5v5、11v11 关卡模拟结果保持不变。
- 相同种子、关卡和命令序列产生相同地形碰撞、环境区和设施事件。
- 开启与关闭 Presentation、调试碰撞体或特效不会改变战斗结果。
- 关闭空间索引后的全量查询结果与开启索引一致。

---

## 22. 实施顺序

### 阶段 1：硬地形权威查询

- 定义审核后的世界多边形和阻挡掩码。
- 实现 TerrainQueryService 与统一几何容差。
- 实现舰船圆形扫掠和岸边停止/滑动。
- 实现鱼雷连续扫掠与岸边失效。
- 实现炮弹路径阻挡和手动瞄准拒绝。
- 实现水面光学视线阻挡。

该阶段完成后，岛屿和岸线必须已经真实阻挡舰船、鱼雷和炮弹，而不是只有视觉图层。

### 阶段 2：共享导航

- 从审核几何生成路线规划数据。
- 玩家移动预览和 AI 共用 RoutePlanner。
- 接入浅水通行标签、航道和不可达反馈。
- 增加卡住恢复与路线重算。

### 阶段 3：动态软地形

- 实现 EnvironmentZoneState 和固定 Tick 漂移。
- 接入 TerrainContext 与现有修正/侦查服务。
- 向玩家和 AI 提供一致的当前状态与公开趋势。
- 依次接入海雾、飑线、高海况/背风水域、月光水域和强流/潮汐。

当前状态：已完成。环境上下文已经实际进入侦查、机动、武器、航空、路线和潮汐通行，不再只是调试字段。

### 阶段 4：岸基设施

- 先实现观察站与岸炮，验证设施、侦查、武器和地形阻挡闭环。
- 再实现激活/压制状态机和通用交互。
- 再加入前沿补给点、维修泊位和近岸机场。
- 最后在传感器与水雷规则成熟后加入雷达通信站和水雷控制站。
- 验证设施依赖网络、夺取、压制、恢复和摧毁不会建立第二套战斗规则。

当前状态：港湾闭环已完成。雷达仍按 13.8 节明确禁用，等待独立雷达传感器设计；这不是用未实现规则伪装完成。

---

## 23. 完成标准

- 岛屿和岸线由 Domain 权威阻挡舰船、鱼雷、炮弹和水面光学视线。
- 玩家、自动武器和 AI 使用相同地形查询与拒绝原因。
- 舰船与鱼雷在低 Tick、高速度和多边形边缘情况下不会穿透地形。
- 炮弹真实结算和飞行表现都终止于同一岸边命中点。
- 玩家目标点、路径预览和 Domain 最终移动不产生规则矛盾。
- 未配置地形的开阔海域关卡保持现有行为。
- 地形几何、动态环境和设施状态可固定种子复现并脱离场景树测试。
- 海雾、飑线、高海况、月光水域、强流和潮汐均通过统一环境状态与 TerrainContext 进入规则。
- 20 套时间天气 palette 与 Domain 全局条件一一对应；开阔海域和近岸地图都使用同一组合入口，不允许只换画面不换规则。
- 深水、沿岸、浅水、礁滩、航道、海湾港池和背风水域具有明确且可组合的 Domain 语义。
- 观察站、岸炮、补给点、机场、雷达通信站、水雷控制站和维修泊位均由通用设施能力与状态组合表达。
- 设施系统通过普通领域命令、状态和事件协作，不建立绕过侦查、武器或伤害规则的第二套战斗系统。
- 港湾自动测试必须覆盖环境数值生效、潮汐进出、观察站压制、岸炮开火、补给维修、三类机场任务、水雷触发/控制、设施压制恢复摧毁和 AI 环境意图；批量模拟必须能记录设施来源伤害并正常结算。
