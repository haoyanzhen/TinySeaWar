# 导航碰撞场与惯性航迹连续验证工单

> 建立日期：2026-08-02
>
> 状态：自动实现与 Headless 正确性门禁完成；待带画面大编队交通、人工键鼠航行与剩余绝对性能关闭
>
> 优先级：P0 正确性 / P1 性能与航行质量
>
> **功能与边界**：本工单解决常规/紧急航迹规划器使用粗时间步、中心线与终点占位近似后，可能把高速转向擦岸航迹误判为安全，并在 Domain 权威移动中触岸停车的问题。正式方案建立由规则地形多边形离线派生的静态占用 BitMask 与保守距离场，使用与 Domain 相同固定 Tick 展开的参数化航迹做连续舰体净空查询，并只对近岸片段执行多边形精确窄相。碰撞场是共享空间查询的加速数据，不是第二套规则真源；美术贴图 Alpha、参考 Mask、小地图 Mask 和视觉区域均不得成为通行依据。

## 1. 关联真源与实现入口

### 1.1 必须保持一致的设计真源

- `docs/30_technical_architecture.md`：四层依赖、固定 Tick 与 Domain 权威边界。
- `docs/32_domain_design_phase1.md`：战斗状态所有权、命令与权威 Tick 顺序。
- `docs/35_scene_combat_domain_design.md`：硬地形、舰体几何、连续扫掠、确定性与规则几何真源。
- `docs/22_scene_environment_data_schema.md`：地形定义、区域、导航引用及新增碰撞场引用的字段契约。
- `docs/technical/t00_coastal_ai_performance_solution.md`：空间查询、路线预算、错峰调度与性能门禁。
- `docs/technical/t01_inertial_navigation_and_emergency_avoidance.md`：战略走廊、常规/紧急动力学航迹、SafetyHold 与移动恢复。
- `docs/47_scene_art_asset_pipeline.md`：视觉海岸与规则几何的同源变换边界；美术 Alpha 不得反向成为规则真相。

### 1.2 当前实现入口

- `scripts/application/navigation/trajectory_planner.gd`：候选控制、动力学预测、地形硬过滤与评分。
- `scripts/application/navigation/route_planner.gd`：直达段、导航图接入、A* 与稀疏走廊门。
- `scripts/application/battle_session.gd`：规划调度、当前控制执行、触岸处理与恢复状态。
- `scripts/domain/services/ship_motion_service.gd`：推进、制动、转向、水流和位置积分。
- `scripts/domain/services/terrain_query_service.gd`：权威地形多边形索引、带半径扫掠与移动解析。
- `tools/terrain/`：规则地形、导航图和派生产物的确定性烘焙与校验。
- `scripts/tests/trajectory_navigation_test.gd`、`ai_route_recovery_test.gd`、`coastal_runtime_test.gd`、`ai_navigation_performance_test.gd`：主要自动验收入口。

## 2. 问题陈述与现状证据

### 2.1 规划预测与权威移动口径不一致

当前正常候选预测时域为 `6.0s`，但采样步长为 `1.5s`。`ShipMotionService.step()` 先更新航向，再按更新后的航向推进完整步长；因此同一控制分别用 `1.5s` 和战斗固定 Tick 积分时，会得到不同的空间轨迹。规划器验证的是数段粗折线，Domain 执行的是大量短线段组成的转向弧线。

这违反以下正确性约束：

```text
相同初始状态 + 相同控制序列 + 相同环境上下文
必须让规划预测的承诺区间与 Domain 实际执行轨迹一致。
```

### 2.2 局部候选没有连续扫掠舰体半径

当前 `TrajectoryPlanner._segment_clear()` 对每个粗采样段执行：

```text
中心线不穿陆地
and 终点可以容纳 collision_radius 圆
```

中心线查询没有传入舰体半径，段中间也没有执行带半径连续扫掠。于是可能同时满足“起点合法、中心线不穿陆地、终点合法”，但舰体边缘在段中间擦到岸线。

Domain 实际移动调用 `resolve_circle_motion(..., collision_radius, ...)`，会在同一路段发现碰撞、截断位移并将航速归零。规划器的“安全”与 Domain 的“碰撞”因此可以同时成立。

### 2.3 直达走廊不代表当前姿态可安全驶入

战略层的直达检查只证明起点与目标之间存在一条带半径合法直线，不能证明舰船以当前航向、速度、转向能力和水流形成的弧线会留在该直线走廊内。直达结果不得成为局部动力学安全结论。

### 2.4 当前评分缺少净空与近岸速度代价

当前常规候选的主要差异来自“未来时域内向当前门取得的距离进展”，绝对舵量只带来极小连续性修正。代码尚未实现 `t01` 所描述的 `clearance_margin`、下一门进弯姿态、近岸高速风险和真实的控制切换成本。

结果是：只要近似硬过滤没有发现碰撞，全速贴岸候选很容易胜出；即使几何上只剩极小容错，它也不会输给净空更大的减速或外扩航迹。

### 2.5 触岸后的危险控制没有立即失效

Domain 发现地形碰撞后会把 `current_speed` 归零并标记 `trajectory_dirty`，但当前正常规划主要仍按固定规划槽触发。若 `trajectory_dirty` 没有立即把下一规划 Tick 提前，舰船可能继续持有刚刚造成触岸的控制，表现为岸边重复碰撞、停车或长时间 SafetyHold。

## 3. 决策摘要

正式方案采用：

```text
TerrainDefinition 权威多边形
  -> 离线保守栅格化
    -> 静态占用 BitMask + 距离下界场 + 可选层级索引
      -> 与 Domain 同 Tick 的候选轨迹展开
        -> 栅格宽相 / 净空查询
          -> 近岸片段多边形精确窄相
            -> 硬拒绝碰撞候选并评分剩余候选
              -> Domain 每 Tick 使用同一几何语义权威执行
```

核心决策：

1. 不为每条候选路线创建地图尺寸的路径图片，也不执行整图 Mask 相乘。
2. 将“加粗路径”转换为“查询轨迹中心到陆地的距离”；静态地形只烘焙一次。
3. 不使用 GPU 回读参与权威判定；运行时查询使用 CPU 连续数组和确定性整数索引。
4. 碰撞场只由 `TerrainDefinition.obstacles` 中声明 `ShipMovement` 的规则多边形、地图边界及其作者变换派生。
5. 远岸片段由保守距离场直接证明安全；无法证明安全的近岸片段必须回到现有多边形连续扫掠，不能按“可能安全”放行。
6. 规划器和 Domain 共用固定 Tick 运动展开与地形查询语义；任何近似只能产生额外窄相或保守拒绝，不能产生漏撞。

## 4. 目标与非目标

### 4.1 目标

- 消除“规划器判安全、Domain 在承诺区间内触岸”的静态岸线假阴性。
- 让高速转向、制动、水流和倒车候选按照实际固定 Tick 航迹接受连续舰体检查。
- 让候选评分能够使用最小净空和近岸速度，而不是只追求当前门进展。
- 在十张 `6144 × 3456` 海岸地图与 11v11 场景中保持可接受的固定 Tick 性能。
- 保持 Headless、带画面运行、不同物理分辨率和固定种子结果一致。
- 保持规则多边形为唯一真源，碰撞场、导航图、小地图与表现派生物能够通过 revision 和 checksum 证明同源。
- 当碰撞场缺失、过期或校验失败时，可以确定性回退到多边形精确查询，而不是回退到中心线加终点占位的旧近似。

### 4.2 非目标

- 不把美术岛屿透明图、参考 Mask、视觉区域或浅水贴图升级为碰撞真源。
- 不在本工单实现真实舵机、六自由度水动力、侧滑、波浪姿态或高精度船舶操纵学。
- 不用碰撞场替代战略目标选择、A* 拓扑搜索、编队任务、威胁评估或武器决策。
- 不把动态舰船、鱼雷、雷区和敌方知识写入静态岛屿碰撞场。
- 不因性能优化降低 Domain 的权威连续扫掠、潮汐、水深或边界合法性。
- 不授权 `20` 局以上平衡实验、侧别交换或全量平衡矩阵；默认只执行 `1 -> 3` 个固定种子专项与既有自动测试。

## 5. 权威边界与正确性不变量

### 5.1 唯一规则真源

碰撞字段必须从以下输入确定性生成：

```text
terrain_definition_id
map_size
navigation_revision
obstacles[].polygon
obstacles[].block_mask
authoring_transform / baked world coordinates
```

只有包含 `ShipMovement` 的障碍进入舰船静态碰撞层。地图外区域按硬障碍处理。浅水、礁滩、航道、潮汐和局部环境继续遵守各自 Domain 语义；除非后续显式增加独立语义层，否则不得把它们粗暴并入“陆地”位。

### 5.2 必须成立的不变量

1. **无假安全**：碰撞场返回 `DefinitelyClear` 的片段，在相同半径与静态 revision 下，多边形连续扫掠必须同样无碰撞。
2. **不确定即窄相**：距离不足、边界量化误差、动态 revision 或字段缺失均返回 `NeedsExactCheck`，不得直接放行。
3. **同 Tick 轨迹**：规划器承诺的前部控制必须用与 Domain 相同的 Tick、积分顺序和环境上下文展开。
4. **最终候选复核**：评分最高候选在提交前必须完成所有不确定片段的精确连续验证。
5. **Domain 仍权威**：即使规划验证通过，Domain 每 Tick 仍执行最终移动合法性；碰撞场不直接写入位置。
6. **碰撞后立即失效**：若 Domain 仍发生静态地形碰撞，当前控制不得继续作为有效计划执行。
7. **确定性**：相同输入、revision、固定 Tick 和候选顺序必须得到相同的首个碰撞片段、最小净空和候选排序。

## 6. 静态碰撞场数据设计

### 6.1 基础栅格

当前实现使用：

| 参数 | 建议值 | 说明 |
|---|---:|---|
| 世界地图 | `6144 × 3456` | 当前大型海岸地图基线 |
| 基础单元 | `8 × 8` 世界单位 | 差分验证后的性能/保守性平衡值 |
| 栅格尺寸 | `768 × 432` | `6144 × 3456` 地图下的基础尺寸 |
| 静态占用 | `1 bit/cell` | 岛屿、硬岸或地图外 |
| 距离下界 | `uint16/cell` | 单位为世界单位或固定量化单位 |

估算内存：

- 单层 1-bit 占用约 `40.5 KiB`。
- 当前格式不保存可选 OR-Mipmap；若后续启用，完整层级约为基础位图的 `4/3`，合计约 `54 KiB`。
- 单层 `uint16` 距离场约 `648 KiB`。
- 只加载当前地图；不得一次常驻十图全部字段。

若 `8` 世界单位不足以满足尖角、凹岸和大型舰切线精度，应优先保持精确窄相并对近岸单元标记“不确定”，而不是直接把全图提升到美术像素分辨率。

### 6.2 占用 BitMask

占用层采用保守栅格化：只要规则障碍与单元存在交集，该单元即为占用。边界单元宁可产生假阻挡，也不能产生假安全。

用途：

- 快速空图/开阔水域判定。
- 路段包围盒或 DDA 访问的廉价障碍候选筛选。
- 可选 OR-Mipmap 的大范围无障碍跳过。
- 构建与运行时诊断显示；不得直接作为美术贴图显示真源。

### 6.3 保守距离下界场

每个单元保存：

```text
该单元内任意一点到最近 ShipMovement 障碍或地图外的距离下界
```

普通“单元中心到障碍的距离”可能高估单元边缘净空，不能直接作为安全证明。可选实现方式：

1. 对保守占用位图做确定性欧氏距离变换，并明确输出究竟是“到占用单元中心”还是“到占用单元面积”的距离。
2. 若输出中心到中心距离，必须同时扣除查询单元与占用单元的半对角线；若输出到占用单元面积的距离，则至少扣除查询单元半对角线。两种实现都必须再扣除量化误差。
3. 向下取整并截断到 `uint16`。
4. 对边界邻域执行多边形差分校验；任何高估都使构建失败。

概念公式：

```text
distance_lower_bound = max(
  0,
  floor(
    occupied_center_distance
    - query_cell_half_diagonal
    - occupied_cell_half_diagonal
    - quantization_guard
  )
)
```

若烘焙器直接计算查询单元到占用单元面积或权威多边形的距离，可使用对应的更紧下界，但必须在字段格式中记录算法版本，且仍需通过无高估差分门禁。

运行时只在 `distance_lower_bound > required_clearance` 时宣称确定安全；等于边界时进入精确窄相。

### 6.4 可选层级索引

占用位图可生成 2×2 OR-Mipmap。距离场可选生成 2×2 min-Mipmap。层级只用于跳过大片开水，不参与最终边界插值。

首轮不要求实现复杂四叉树。若基础 DDA 已满足预算，则保留连续数组比引入对象化树结构更简单、更可预测。

### 6.5 二进制格式与清单

建议新增：

```text
data/terrain/collision_fields/
  terrain_map_xxx.tscf
data/terrain/collision_field_manifest.json
```

`.tscf` 建议包含固定头和连续数据段：

```text
magic
schema_version
terrain_definition_id_hash
navigation_revision
map_width / map_height
cell_size
grid_width / grid_height
occupancy_offset / occupancy_length
distance_offset / distance_length
mip_offsets[]
source_checksum
payload_checksum
```

运行时加载前必须校验版本、地图尺寸、revision、源 checksum 和 payload checksum。失败时记录明确原因并走精确多边形回退。

## 7. 离线烘焙方案

### 7.1 工具入口

建议新增：

```text
tools/terrain/bake_collision_fields.py
tools/terrain/validate_collision_fields.py
```

并接入 `tools/terrain/build_scene_combat_pipeline.py` 与 `validate_scene_combat_pipeline.py`，保证地形、导航、碰撞场和小地图由同一次候选构建原子替换。

### 7.2 烘焙步骤

1. 读取已经应用作者变换的 `terrain_definitions.json`，不读取视觉 PNG。
2. 选取 `block_mask` 包含 `ShipMovement` 的障碍多边形。
3. 将地图外区域纳入边界距离。
4. 以保守覆盖规则生成基础占用位图。
5. 生成距离下界场与可选 Mipmap。
6. 写入稳定排序、固定端序和无时间戳的二进制文件。
7. 写入包含源 checksum、生成器版本和输出 checksum 的 manifest。
8. 重复烘焙两次并做字节一致性比较。
9. 用随机点、切线、凹角和长线段与多边形权威查询做差分验证。

### 7.3 禁止事项

- 禁止由 `assets/environment/land/source/reference_16x9/*_mask.png` 或运行时海岸透明图直接生成权威字段。
- 禁止使用小地图 Mask 作为碰撞输入。
- 禁止在烘焙结果中保存机器绝对路径、非稳定对象哈希或时间戳。
- 禁止仅靠图片目视对齐宣称规则字段有效。
- 禁止碰撞场过期时静默继续加载。

## 8. 统一动力学轨迹展开

### 8.1 参数化表达

航迹不能表示为单值函数 `y = f(x)`，因为舰船可以垂直航行、回转、停车和倒车。运行时统一表达为：

```text
TrajectoryRequest = {
  initial_state,
  controls[{duration, thrust_ratio, turn_ratio}],
  fixed_tick_delta,
  horizon,
  environment_revision
}

TrajectorySample = {
  tick_offset,
  position,
  heading,
  speed,
  current_vector
}
```

### 8.2 同源展开服务

建议在 `ShipMotionService` 增加纯函数式入口：

```gdscript
simulate_control_sequence(
    initial_state,
    controls,
    fixed_tick_delta,
    context_sampler
) -> Array[TrajectorySample]
```

要求：

- 使用战斗实际固定 Tick，不允许正常候选另用 `1.5s` 粗步长。
- 每个 Tick 的环境上下文、水流和移动倍率读取顺序与 Domain 一致。
- 不访问场景树、HUD 或表现资源。
- 相同输入重复调用字节级事实结果一致，允许浮点比较使用统一容差。
- 规划器只承诺实际将执行的控制前部；下一规划槽从 Domain 真实状态重新展开。

### 8.3 计算规模

当前正常候选上限 `6`、预测时域 `6s`、固定 Tick 约 `0.1s`：

```text
6 candidates × 60 segments = 360 segment checks / ship / normal plan
```

11v11 全部单位每秒各规划一次时约 `7920` 个短段/秒；单位按稳定槽位错峰后，不会全部集中在同一 Tick。对于连续内存中的位图/距离场读取，该规模应远低于逐候选多边形全扫或整图 Mask 相乘。

若性能仍不足，允许按以下顺序优化：

1. 开阔地图或整段远岸时批量跳过。
2. 复用候选公共前缀状态，但不得合并具有不同控制的后续片段。
3. 使用 Mipmap 跳过长开水段。
4. 将纯查询内核迁移到 GDExtension；不得先降低采样正确性。

## 9. 舰体安全包络

### 9.1 首轮兼容口径

首轮必须先与当前 Domain 地形移动所使用的 `collision_radius` 完全一致，以消除规划/执行差异而不静默改变现有通行规则：

```text
required_clearance = collision_radius + navigation_margin
```

`navigation_margin` 是规划安全余量，不改变 Domain 物理碰撞半径；建议至少覆盖栅格量化误差，并通过近岸用例确定舒适余量。

当前余量为 `4` 世界单位。若舰体按 Domain 硬半径仍合法，只是位于这层额外软余量内，则原地保持按硬半径保留为安全回退；朝碰撞法线外侧离开的短段允许从软余量内连续扫掠脱离，进入余量或沿岸继续压缩净空仍按完整余量拒绝。软余量不得把合法单位永久锁成 `NO_SAFE_TRAJECTORY`。

### 9.2 最大半长度外接圆

若后续统一启用随航向旋转的椭圆舰体，用户提出的“最大半长度作为路径宽度”可作为最快的保守宽相：

```text
a = hull half length
b = hull half width
R_fast = max(a, b) + navigation_margin
```

严格说，路径总宽度为 `2 × R_fast`。若中心轨迹到岸距离始终大于 `R_fast`，任意朝向的舰体都必然安全。

该外接圆对大型舰和窄航道可能过度保守，所以外接圆与陆地重叠时只能返回 `NeedsExactCheck`，不得直接判定真实椭圆必然碰撞。

### 9.3 可选定向胶囊窄相

椭圆舰体的高性能保守近似可使用随航向旋转的胶囊：

```text
spine_half_length = max(0, a - b)
capsule_radius = b
```

胶囊包住椭圆但明显小于半径为 `a` 的外接圆。若实施该阶段，规划器与 Domain 必须同步切换到同一舰体语义，并更新 `32/35` 与相关测试；不得只在规划器单侧启用。

## 10. 运行时碰撞查询算法

### 10.1 查询返回值

共享接口建议返回：

```text
TrajectoryTerrainResult = {
  status: DefinitelyClear | ExactClear | Collides | FieldUnavailable,
  first_hit_tick,
  first_hit_fraction,
  obstacle_id,
  minimum_clearance,
  minimum_clearance_position,
  field_cells_visited,
  exact_segment_checks
}
```

Mask/SDF 无需保存障碍 ID；发生近岸不确定时，由多边形窄相返回稳定障碍 ID 和法线。

### 10.2 单个短段查询

对连续样本 `p0 -> p1`：

1. 将段端点转换到栅格坐标。
2. 用整数 DDA / supercover 遍历中心线经过的全部单元。
3. 读取每个单元的 `distance_lower_bound`。
4. 若所有单元均满足 `distance_lower_bound > required_clearance`，返回 `DefinitelyClear`。
5. 任一单元距离不足、超出字段、revision 不一致或数据无效时，对该短段调用 `is_movement_segment_clear()` / `first_segment_hit(..., sweep_radius)`。
6. 精确扫掠无碰撞则继续下一短段；有碰撞则立即返回首个碰撞 Tick 与分数。

因为距离值是“单元内任一点”的下界，只要中心线穿过的每个单元均大于所需半径，就能证明整条中心线上的所有点都具有足够舰体净空。

### 10.3 候选级流程

```text
for candidate in stable_candidate_order:
  samples = simulate_control_sequence(..., fixed_tick_delta)
  result = collision_field.validate_trajectory(samples, hull, movement_tags)
  if result.Collides:
    hard reject
  else:
    retain result.minimum_clearance for scoring

sort retained candidates by utility and stable index

for candidate in sorted candidates:
  complete any deferred exact checks
  first fully validated candidate wins
```

不能先按进展选出一个候选，再因精确验证失败直接 SafetyHold；应尝试下一个已通过宽相的候选，直到候选耗尽。

### 10.4 静态与动态规则分离

- 静态岛岸与地图边界：碰撞字段宽相 + 多边形窄相。
- 固定浅水/礁滩/航道：现有 `movement_tags` 与区域规则；未来可增加独立语义栅格层，但不得混入陆地位。
- 潮汐：按 `tide_revision` 继续由 `TerrainContextService` 判定；字段只能保存不会随潮汐改变的静态部分。
- 动态舰船：继续使用独立空间索引和预测轨迹，不进入静态字段。
- 雷区与敌方知识：属于阵营风险成本，不进入公共物理碰撞字段。
- 设施：只有确实改变硬通道的静态/动态设施几何才通过明确 revision 接入；普通设施状态不重烘焙全图。

## 11. 与战略走廊和局部航迹的集成

### 11.1 战略层

- 导航图边仍在离线烘焙时按 Profile 半径验证。
- 直达段、起终接入段和最终采用的门间段可以用碰撞字段做快速确定安全筛选，不确定时仍执行现有多边形扫掠。
- 战略直达只输出宽走廊或单目标门，不宣称当前航向能够沿直线瞬时进入。
- 碰撞字段不得让 A* 开始逐 Tick 动力学搜索；战略层继续只解决长期拓扑可达与大范围进展。

### 11.2 局部层

局部层必须至少读取：

```text
current gate
next 1-2 corridor gates when available
current position / heading / speed
acceleration / braking / turn limit
current vector
hull envelope
```

下一门前视用于提前降速和选择转弯外扩，不要求精确跟随门中心线。

### 11.3 净空与速度评分

候选硬过滤后，建议评分增加：

```text
trajectory_utility =
    goal_progress
  + arrival_time_gain
  + clearance_score
  + next_gate_alignment
  + control_continuity
  - unnecessary_control_change
  - near_shore_speed_cost
```

建议语义：

```text
clearance_score = saturate(
  (minimum_clearance - required_clearance) / comfort_band
)

near_shore_speed_cost =
  speed_ratio^2
  * saturate(
      (comfort_clearance - minimum_clearance) / comfort_clearance
    )
```

具体权重必须通过固定场景行为测试确定，不能让软净空收益覆盖硬碰撞判定，也不能让舰船在大范围开水无故降速。

### 11.4 可接受的转向策略

当目标直线拓扑可达、但当前高速弧线会进入岸线安全包络时，候选集应允许：

- 保持短时直行后再转向。
- 降低推力后转向。
- 向远离岸线的一侧扩弧。
- 制动并等待下一规划槽。
- 已经贴岸时先按碰撞法线脱离，再恢复原语义目标。

不能因为“目标点与当前位置直线可达”而强制全速纯追踪。

## 12. 触岸恢复与失效处理

### 12.1 Domain 碰撞后的立即动作

若 `UnitTerrainCollision` 发生：

1. 当前 `trajectory_plan` 立即失效。
2. `current_control` 在本 Tick 结算后不得继续作为正常有效控制。
3. `next_normal_plan_tick` 提前到下一可执行 Tick，而不是只设置未消费的 dirty 标记。
4. 保存碰撞法线、障碍 ID、位置、进入速度和原语义目标。
5. 下一次常规恢复候选至少包含制动、沿远离法线转向和受限倒车转艏。
6. 达到安全净空后恢复原战略走廊；走廊本身失效时再提交高优先级路线请求。

### 12.2 诊断不变量

若一个已经以 `DefinitelyClear` 或 `ExactClear` 提交的控制，在同一静态 revision 和承诺区间内触发静态岸线碰撞，必须记录高优先级诊断：

```text
NavigationCollisionContractViolated = {
  unit_id,
  plan_tick,
  collision_tick,
  field_revision,
  terrain_revision,
  candidate_id,
  predicted_samples,
  executed_samples,
  first_divergence_tick,
  obstacle_id
}
```

自动测试中该事件必须直接失败；正式运行可确定性降级到精确查询并保留报告。

## 13. 组件与代码落点

建议新增或调整：

| 层级 | 文件/组件 | 职责 |
|---|---|---|
| Domain | `scripts/domain/services/terrain_collision_field.gd` | 只读碰撞字段查询、DDA、距离下界、宽相结果；不访问场景树 |
| Domain | `scripts/domain/services/terrain_query_service.gd` | 保留权威多边形窄相与移动解析；提供统一精确段接口 |
| Domain | `scripts/domain/services/ship_motion_service.gd` | 固定 Tick 控制序列展开，供规划与权威运动复用 |
| Application | `scripts/application/navigation/trajectory_planner.gd` | 生成候选、调用共享轨迹验证、净空评分与候选降级 |
| Application | `scripts/application/navigation/route_planner.gd` | 使用碰撞场快速筛选直达/接入/门间段，不拥有权威几何 |
| Application | `scripts/application/battle_session.gd` | 调度、碰撞后立即失效与恢复、诊断事件 |
| Infrastructure | `scripts/infrastructure/data/` | 二进制字段与 manifest 加载、checksum/revision 校验 |
| Tooling | `tools/terrain/bake_collision_fields.py` | 从规则多边形确定性生成字段 |
| Tooling | `tools/terrain/validate_collision_fields.py` | 差分、边界、过期与确定性校验 |
| Data | `data/terrain/collision_fields/` | 当前地图的只读派生字段 |
| Data | `data/terrain/collision_field_manifest.json` | 版本、地图、revision、尺寸、路径与 checksum |

若评测证明 GDScript 数组查询仍是瓶颈，可将 `terrain_collision_field` 的纯查询核心迁入 GDExtension；上层 API、确定性、字段格式和回退语义不得改变。

## 14. 调试与量测

新增可关闭指标：

```text
collision_field_usec
collision_field_queries
collision_field_cells_visited
collision_field_mip_skips
collision_field_definitely_clear
collision_field_exact_fallbacks
collision_field_unavailable_fallbacks
trajectory_segments_simulated
trajectory_candidates_rejected_by_terrain
trajectory_minimum_clearance
navigation_collision_contract_violations
terrain_collisions_after_clear_plan
```

性能数据只进入 profiler 和报告，不进入战斗状态、随机源或候选决胜。候选同分仍使用稳定模板序号。

建议首轮性能门禁：

- 11v11 有岸场景中，碰撞场查询不得使既有 `navigation_usec` P95/P99 恶化。
- `collision_field_usec` 的首轮建议为 P95 `<= 1ms`、P99 `<= 2ms`；2026-08-03 参考机器在三张 11v11 图实测最差 `1.558/1.646ms`，现阶段接受 P95 `<= 1.75ms`、P99 `<= 2ms`，不得通过放松保守下界换取达标。
- 远岸片段的多边形精确查询数量相对“每段全部精确扫掠”基线至少下降 `80%`。
- 不能以减少查询次数掩盖碰撞、停车、路线失败或任务进展退化。

## 15. 测试与验收矩阵

### 15.1 烘焙与字段测试

- [x] 相同输入连续烘焙两次，所有 `.tscf` 与 manifest 字节一致。
- [x] 修改任一障碍点、地图尺寸或 navigation revision 后，旧字段必定被拒绝。
- [x] 视觉 PNG、参考 Mask、`visual_regions` 或小地图变化不会单独改变规则碰撞字段。
- [x] 十张海岸地图的字段尺寸、cell size、世界变换和 checksum 与对应地形定义一致。
- [x] 损坏头、截断 payload、非法 offset、checksum 不符和未知版本均稳定报错并回退。

### 15.2 宽相/窄相差分测试

- [x] 对十图执行固定种子的随机点、随机带半径线段、规则岸线切线和地图边界查询，与多边形权威结果比较。
- [x] `DefinitelyClear` 对权威查询的假阴性必须为 `0`。
- [x] 记录保守命中与精确回退率；高保守性只能增加窄相，不得通过放松距离下界消除。
- [ ] 覆盖凸岸、凹角、尖角、薄障碍、岛间窄口、地图四边与多障碍相邻区域。
- [x] 覆盖当前三档导航半径 `20 / 32 / 46` 及 `±1` 边界浮动值。

### 15.3 动力学一致性测试

- [x] 同一初始状态和控制序列由规划展开与逐 Tick Domain 执行后，每 Tick 位置、航向和速度在统一容差内一致。
- [x] 覆盖静止起步、全速、制动、左右满舵、部分舵、先制动后倒车、水流和移动倍率变化。
- [x] 禁止重新引入 `1.5s` 粗步长作为安全结论；调试预览可以降采样显示，但不得降采样判定。

### 15.4 近岸航迹专项

- [ ] 平行岸线全速航行，净空不随重规划逐步收缩到碰撞边界。
- [x] 舰首背向/侧向目标时的全速转弯按完整舰体半径连续验证，危险轨迹不会被提交。
- [x] 目标直线可达但初始转弯弧线不安全时，能够选择直行后转、减速转或外扩转向。
- [ ] 进入窄口前能够提前减速；通过后恢复合理推进。
- [x] 三个近岸连续扫掠夹具不发生粗采样跨越或中心线安全、舰体擦岸。
- [x] 当前目标、玩家连续航点、AI 战术目标和接替增援舰进入同一安全验证入口。

### 15.5 碰撞恢复专项

- [x] 人工构造不可避免触岸后，当前危险控制在下一 Tick 前失效。
- [x] 恢复能够利用碰撞法线选择制动/脱离/倒车，不永久原地重试同一控制。
- [x] 恢复后保留原语义目标；只有走廊失效时才重建战略路线。
- [x] 正常自动验收中 `NavigationCollisionContractViolated=0`；故意注入同 revision 不安全计划时能够命中诊断。

### 15.6 回归与性能

- [x] `trajectory_navigation_test.gd`、`ai_route_recovery_test.gd`、`coastal_runtime_test.gd` 全部通过。
- [x] 十张近岸地图各运行 `1` 个固定种子烟测；出现新异常时最多扩展到 `3` 个种子定位。
- [x] 港湾、长列岛、环形泻湖执行 11v11 `400 Tick` 定向复验，记录岸线碰撞、路线失败、等待、P95/P99 与碰撞场命中率。
- [ ] 带画面和 Headless 的固定输入轨迹事实一致。
- [x] 既有开阔海域不加载碰撞字段，11v11 定向样本未出现额外静态地形查询成本。

## 16. 实施阶段

### 阶段 A：建立失败夹具与量测

- [x] 固化三个近岸“中心线或端点不足以证明舰体安全”的连续扫掠夹具，保存姿态、速度、目标、控制与碰撞几何。
- [x] 增加规划样本/Domain 逐 Tick 一致性与静态碰撞契约统计。
- [x] 记录候选字段耗时、字段查询数和精确多边形调用数。

完成门禁：失败夹具在旧实现稳定失败，且能区分“路线拓扑不可达”“局部弧线不安全”和“预测/执行不一致”。

### 阶段 B：先修复正确性，不依赖碰撞场

- [x] 抽出同固定 Tick 的公共控制序列展开。
- [x] 局部候选每个不确定短段使用现有带半径精确连续扫掠。
- [x] 最终候选完整验证后才提交。
- [x] Domain 碰撞立即使当前计划和控制失效。

完成门禁：阶段 A 的擦岸夹具全部通过，`NavigationCollisionContractViolated=0`。即使此阶段性能暂未达标，也不得退回旧中心线/终点近似。

### 阶段 C：烘焙碰撞字段

- [x] 实现 BitMask、距离下界、manifest、checksum、加载与过期回退。
- [x] 接入十图生产流水线和重复构建确定性验证。
- [x] 完成固定种子带半径线段差分测试，证明 `DefinitelyClear` 假阴性为零；独立切线/半径浮动夹具仍见 15.2。

完成门禁：字段可安全代替远岸多边形查询，缺失或损坏字段会明确回退。

### 阶段 D：宽相/窄相集成与评分

- [x] 所有候选使用字段宽相，近岸片段使用多边形窄相。
- [x] 候选记录最小净空并接入净空/近岸速度评分。
- [x] 局部规划读取下一至两个走廊门，支持进弯减速和外扩。
- [x] 候选按稳定顺序逐一完成硬验证；失败时继续尝试下一候选，不直接进入 SafetyHold。

完成门禁：近岸行为专项通过，远岸精确多边形调用下降达到目标，且不增加静态岸线碰撞。

### 阶段 E：恢复、诊断与大编队复验

- [x] 完成碰撞法线驱动的局部脱离、受限倒车和原意图恢复。
- [x] 完成港湾、长列岛、环形泻湖 11v11 定向复验。
- [x] 核对 `t00` 绝对性能门禁；结果仍未通过，本工单自动正确性通过不代表港湾整体 P95/P99 已关闭。

### 阶段 F：文档与状态同步

- [x] 按实际实现更新 `docs/35_scene_combat_domain_design.md` 的共享碰撞场加速边界。
- [x] 更新 `docs/technical/t00_coastal_ai_performance_solution.md` 的查询预算与指标。
- [x] 更新 `docs/technical/t01_inertial_navigation_and_emergency_avoidance.md` 的同 Tick 轨迹、净空评分和恢复流程。
- [x] 更新 `docs/22_scene_environment_data_schema.md`、加载校验与负例。
- [x] 更新 `docs/34_implementation_map.md`、`docs/00_project_status.md` 和 `AGENTS.md`；只按已有自动/人工证据标记完成度。

## 17. 回滚与降级

- 碰撞字段加载失败、revision 不符或 checksum 异常：整场使用多边形精确宽度查询，记录一次明确错误，不重复刷日志。
- 单个字段查询返回不确定：只对相关短段进入精确窄相。
- 性能积压：减少软评分候选、复用仍合法的旧控制或延后收益型重算；不得跳过静态碰撞硬验证。
- GDExtension 不可用：继续使用 GDScript/PackedArray 查询或全精确回退，不改变判定语义。
- 新评分导致行为退化：可关闭净空软评分，但不能关闭同 Tick 轨迹和连续扫掠正确性。
- 不提供“恢复旧中心线加终点占位安全判断”的回滚开关。

## 18. 风险与处理原则

| 风险 | 影响 | 处理原则 |
|---|---|---|
| 距离场高估净空 | 产生漏撞 | 保存距离下界、向下量化、随机差分；不确定即窄相 |
| 外接圆过度保守 | 大型舰拒绝合法窄口 | 只将重叠视为不确定，允许定向胶囊/多边形窄相恢复 |
| 全精确阶段过慢 | Tick 峰值上升 | 正确性阶段短期接受，随后以字段宽相消除远岸精确调用 |
| 字段与地形过期 | 规则/视觉/导航错位 | revision + source checksum + 构建原子替换 |
| 粗 Tick 重新出现 | 预测与执行再次分歧 | 安全验证强制使用战斗固定 Tick；只允许显示降采样 |
| 净空权重过大 | 舰船无故绕远或减速 | 净空收益饱和、开水归零、固定场景调权 |
| 碰撞后反复倒车 | 岸边振荡 | 法线迟滞、最小恢复时间、脱离净空门禁和确定性方向 |
| GPU 方案破坏确定性 | Headless/画面不一致 | 权威查询固定为 CPU；GPU 只可用于非权威调试显示 |

## 19. 状态汇总

| 项目 | 优先级 | 状态 |
|---|---|---|
| 失败夹具与预测/执行差异量测 | P0 | 自动夹具已实施并通过 |
| 同固定 Tick 轨迹展开 | P0 | 已实施并通过 |
| 带舰体半径连续候选验证 | P0 | 已实施并通过 |
| Domain 碰撞后立即计划失效 | P0 | 已实施并通过 |
| BitMask 与距离下界场烘焙 | P1 | 已实施并通过确定性门禁 |
| 宽相/窄相共享查询 | P1 | 已实施，精确回退最高 `3.56%` |
| 净空与近岸速度评分 | P1 | 已实施 |
| 定向胶囊/椭圆统一语义 | P2 | 外接圆兼容口径保留，定向窄相待决策 |
| 十图与 11v11 验收 | P1 | Headless 自动门禁通过；带画面/人工/绝对性能待关闭 |

### 19.1 2026-08-03 自动证据

- 字段确定性与差分：全部 `20` 个 TerrainMap 重复烘焙字节一致；三档半径及 `±1` 浮动值下，随机点/线段、岸线切线和地图边界共 `19737/19737` 个 `DefinitelyClear` 样本被权威连续查询确认，假阴性 `0`。
- 专项回归：`navigation_collision_field_test.gd 68/68`、`trajectory_navigation_test.gd 28/28`、`ai_route_recovery_test.gd 10/10`、`coastal_runtime_test.gd 12306/12306`。
- 候选裁剪：舒适净空带扫描 `96/80/64/48`；`64` 改善长列岛但恶化另两张高压图，软余量脱离修复后的 `80` 虽保持故障为 `0`，港湾/环形泻湖 Tick P99 与港湾字段 P99 仍恶化，`48` 长列岛 P99 反弹，最终保留总风险最低的 `96`。
- 十图 3v3：固定种子、每图 `400 Tick`，路线失败/岸线碰撞/航迹失败/结束等待均为 `0`；字段 P95/P99 范围为 `0.553-0.649/0.583-1.101ms`。
- 三图 11v11：港湾、长列岛、环形泻湖每图 `400 Tick` 均为上述四项 `0`；字段 P95/P99 分别为 `1.223/1.642ms`、`1.195/1.646ms`、`1.558/1.635ms`，精确窄相比例为 `2.12%/3.56%/2.49%`。
- Tick P95/P99：港湾 `41.620/47.897ms`、长列岛 `61.808/72.551ms`、环形泻湖 `32.125/43.766ms`。自动正确性通过，但 `t00` 绝对性能、长列岛/环形泻湖完整固定 Tick 成本、带画面交通和人工键鼠航行仍未通过关闭条件。

## 20. 关闭条件

只有同时满足以下条件，本工单才能标记为“已关闭”：

1. 规划器与 Domain 对承诺控制使用相同固定 Tick、运动积分顺序、环境上下文与舰体碰撞语义。
2. 当前已复现的高速转向擦岸场景全部形成自动夹具并通过。
3. 十图差分测试中，碰撞场 `DefinitelyClear` 相对权威多边形查询的假阴性为 `0`。
4. 所有胜出候选在提交前完成连续舰体验证；不再使用“中心线 + 终点占位”作为安全结论。
5. 同一静态 revision 的固定种子验收中，`NavigationCollisionContractViolated=0`，且不存在已验证计划在承诺区间触发静态岸线碰撞。
6. 触岸后危险控制立即失效，恢复流程不会长期重复撞岸或用 SafetyHold 掩盖无进展。
7. 十张近岸地图专项、港湾/长列岛/环形泻湖 11v11 定向复验和既有导航回归通过，并记录碰撞、路线失败、等待及性能数据。
8. 碰撞场加载失败、过期和损坏路径均能确定性回退到精确多边形查询。
9. 生产流水线能够确定性重建地形、导航、碰撞字段和相关 manifest，重复产物字节一致。
10. `35`、`t00`、`t01`、`22`（如适用）、`34`、`00` 与 `AGENTS.md` 已按实际实现和验收证据同步；不得因工单存在而提前标记功能完成。
