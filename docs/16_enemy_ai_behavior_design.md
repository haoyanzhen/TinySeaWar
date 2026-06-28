# 敌方 AI 行为、量化与实现设计

## 1. 文档目标

本文档作为 Tiny Sea War 敌方 AI 的统一设计入口。它同时回答三类问题：

- **AI 应该表现成什么样**：舰队战术、单舰模式、通用航行和攻击/技能策略。
- **哪些内容当前适合实现**：基于现有 Godot 原型评估工作量、前置依赖和裁剪顺序。
- **关键决策如何量化**：目标评分、模式切换、技能阈值和边界处理的首轮公式。

本文只设计 AI 决策，不修改舰船属性、命中公式、伤害公式和技能效果。核心战斗规则以 `docs/10_game_core_mechanics.md` 为准，角色能力与技能以 `docs/14_character_balance_design.md` 为准，关卡编成与 AI 递进以 `docs/15_battle_level_design.md` 为准，领域边界以 `docs/32_domain_design_phase1.md` 为准。

## 2. 设计原则

敌方 AI 的目标不是“最优解”，而是形成可读、可反制、能复用的海面战术行为。

1. **公平情报**：AI 只使用己方完整状态、己方当前可见敌人、合法残影和已公开事件；不得读取隐藏敌人的真实位置、玩家输入或未来随机结果。
2. **职责清晰**：同一舰船可以配置多种模式，例如岛风既可避战侦查，也可侧翼雷击旗舰/航母，或担任前锋对线。
3. **行为可读**：AI 应产生稳定航线、站位和攻击窗口，而不是每个 Tick 追逐最近目标。
4. **低频决策，高频合法性**：战术决策按 0.5 秒左右更新；武器、技能、移动、碰撞、边界仍由战斗系统逐 Tick 校验。
5. **可测试可调参**：目标、模式和技能使用都使用 `[0, 100]` 效用，关键分量进入调试事件，便于固定种子回放和批量模拟。

## 3. 当前程序基线与主要缺口

现有 `scripts/application/battle_session.gd` 已具备：

- 固定 Tick、固定随机种子和稳定单位 ID。
- 单位位置、航向、航速、转向速度和单一移动目标点。
- 矩形地图边界钳制、圆形碰撞半径和重叠后位置分离。
- 阵营共享侦查、当前可见敌人和最长 1 分钟的最后已知位置残影；目标重新被发现时残影立即失效。
- 自动武器、手动主要武器命令、技能命令与合法性校验。
- 实体鱼雷的位置、航向、速度、寿命和碰撞。
- 基础战斗事件、统计和批量模拟入口。

当前敌方 AI 实际接近以下流程：

```text
选择一个可见目标
  -> 远于期望距离：直接驶向目标
  -> 过近：直接反向退开
  -> 距离合适：停留
  -> 技能冷却完成：立即尝试释放
```

主要缺口：

- 没有 AI 运行时记忆、模式驻留、目标滞回和打断恢复。
- 没有专用 AI 可见视图，AI 逻辑仍容易直接读取战斗内部状态。
- 没有 AI Profile/Mode/Rule 配置类别、加载校验和关卡绑定。
- 敌方不会自动提交 `ManualPrimary` 主要武器命令，很多角色核心武器无法按设计使用。
- 没有阵位、编组、目标预留、技能用途标签和模式切换原因。
- 投射物尚无阵营可见性规则，AI 不能公平地规避所有鱼雷。
- 港湾入口已有岛屿、浅水、共享导航、视线遮挡、环境区、设施与已知雷区；AI 已使用同一航路和合法性，但尚未形成完整掩体槽位、编组地形任务和多模式效用决策。
- 潜航、氧气、反潜和航空拦截闭环尚未完整，相关 AI 模式暂缓。

### 3.1 当前场景战术基线

`level.prototype_harbor_3v3` 当前已有一层确定性兼容策略，用于验证场景系统而非替代本文后续完整 AI：

- 无合法接触时，敌方会为中立/敌对可夺取设施生成激活或夺取目标；低耐久时优先寻找己方活跃维修泊位。
- 活跃机场按冷却、次数、通信依赖、天气与合法接触自动申请空袭、巡逻或侦察任务。
- 已知活动雷区会把目标航线重定向到审核安全航道；未知雷区不会进入 AI 查询。
- 高海况且没有更高优先级设施/接触任务时，会寻找公开的背风水域。
- 潮汐关闭会由共享 `RoutePlanner` 和 Domain 移动拒绝，AI 不享受额外通行权。

这些意图全部转换为 `MoveUnits`、`StartFacilityInteraction` 或 `RequestSupportMission`，不会直接改位置、设施状态或目标 HP。完整模式驻留、目标滞回、编组和效用日志仍是本文件的未完成主体。

## 4. 总体 AI 结构

AI 分为四层：

```text
舰队战术方案 Fleet Doctrine
  -> 战术编组 Tactical Group
    -> 单舰模式 Unit Mode
      -> 行动策略 + 攻击策略 + 技能策略
```

### 4.1 舰队战术方案

舰队战术方案决定全队的总体意图，例如标准推进、旗舰固守、双翼包围或航空消耗。它负责：

- 将舰船分配到主力线、护航层、左翼、右翼、侦查组或航空后排。
- 为编组设置集结点、推进轴、威胁方向和保护对象。
- 限制同时执行高风险突击的单位数量。
- 在旗舰受威胁、侧翼崩溃或敌方旗舰暴露时切换阶段。

首轮不建议让舰队方案直接控制单位移动；它只向单舰模式提供战术上下文。

### 4.2 战术编组

编组是 1 至 4 艘舰船组成的低频协同单元。推荐编组：

- 侦查舰 + 远程火力舰。
- 鱼雷突击舰 + 正面牵制舰。
- 航母 + 防空护航舰。
- 旗舰 + 近身护卫舰。
- 潜艇单舰伏击组。

编组只共享本阵营合法情报。组长沉没后，由剩余单位按稳定优先级接替；不得因为缺少组长停止行动。

### 4.3 单舰模式

单舰模式是可配置的行为包，包含：

- 期望距离带与相对站位。
- 可接受暴露程度和撤离阈值。
- 目标评分修正与禁火条件。
- 主要武器使用窗口。
- 主动技能触发、保留和取消条件。
- 主模式失效后的回退模式。

舰船配置声明其可选模式，关卡 AI 配置为具体敌舰选用其中一种。运行中只允许在该舰已声明的模式集合和回退模式之间切换。

### 4.4 决策频率

推荐频率：

| 决策 | 频率 | 说明 |
|---|---:|---|
| 舰队方案 | 2-4 秒 | 旗舰受击、关键单位沉没、敌方旗舰首次发现时立即评估 |
| 单舰完整决策 | 0.5 秒 | 目标评分、模式评分、技能效用和移动意图 |
| 边界风险与连招补发 | 每个固定 Tick | 当前原型约 0.1 秒 |
| 武器/技能合法性、移动、碰撞 | 每个固定 Tick | 继续由战斗系统处理 |

模式切换后设置最短驻留时间，普通切换建议 4 秒；紧急脱离、边界逃逸和保护旗舰可绕过驻留限制。

## 5. 通用行为规则

行动模式回答“这艘船当前想完成什么任务”，通用规则回答“它应当怎样航行、列阵、避险和利用环境”。所有模式共用通用规则，模式只能提供偏好参数，不能关闭领域合法性和强制安全规则。

### 5.1 规则优先级

| 优先级 | 规则层 | 示例 |
|---:|---|---|
| 1 | 领域硬约束 | 不越界、不穿越岛屿、不让沉没单位行动、满足武器/技能合法性 |
| 2 | 即时生存 | 避免碰撞、规避已发现鱼雷、处理氧气耗尽、脱离硬边界 |
| 3 | 关卡强制任务 | 保护指定单位、进入撤离区、阻止敌人突破 |
| 4 | 编组职责 | 保持护航层、占据侧翼、维持侦查链、回到阵位 |
| 5 | 单舰模式 | 斩首、炮线、侦查、前锋或航空后排偏好 |
| 6 | 局部优化 | 选择更佳射角、减少转向、缩短路径或提高技能覆盖数 |

高优先级规则临时打断低优先级规则时，应保存打断原因和恢复点。危险解除后重新评估原任务，而不是无条件回到已经失效的旧航点。

### 5.2 行进规则

- 移动目标先转换为 1 至 4 个战术航点，不直接每次朝目标实时位置转向。
- 开阔海域优先使用直线、侧切弧线和外扩弧线；有障碍物时才进入导航图或可通行区域查询。
- 航点必须考虑舰船转弯半径、当前航向和到达后的下一动作，不能生成需要原地瞬间掉头的路径。
- 追击移动使用目标的当前合法可见运动趋势估算短时拦截点；目标隐藏后立即停止使用其实时运动。
- 除紧急规避外，不因目标位置的小幅变化频繁重算航路。推荐每 0.8 至 1.5 秒，或目标偏离航路阈值后重算。
- 编队航行时以组内可持续最低航速为基准，快速舰允许在阵位附近前出—回收，不要求全程压低到最慢舰航速。
- 进入急转、友军密集区、边界软警戒区或未来岛岸安全区时提前减速。

首轮实现不需要连续数学优化。每次从“保持、左偏、右偏、接近、远离、外扩、脱离”等有限候选方向中评分，足以产生稳定航行。

### 5.3 航向与武器协同

- 炮线舰优先维持能使用多数主炮底座的斜横向航向，但不能为了齐射长期暴露在明显鱼雷航线上。
- 鱼雷舰在攻击前调整到合法扇面，发射后优先沿预设脱离航向转出。
- 航母撤离时优先保持连续航速和远离威胁，不为次要自动武器射角改变航线。
- 潜艇的接近航线未来需要同时计算氧气余量、预计攻击时间和安全上浮点；当前暂缓。

### 5.4 列阵与编队规则

阵型属于战术编组，不建议让 11 艘舰船维持一个刚性大阵。3v3 可以使用单编组；5v5 和 11v11 应拆为主力、护航、侧翼和后排等多个弹性编组。

基础阵型：

| 阵型 | 结构 | 适用场景 | 主要风险 |
|---|---|---|---|
| `Column` | 沿推进轴前后排列 | 通过狭窄区域、降低正面宽度、跟随侦查舰 | 易受纵向鱼雷和头尾分割 |
| `LineAbreast` | 垂直推进轴展开 | 大范围侦查、正面接敌、建立炮线 | 转向慢，容易同时暴露 |
| `Wedge` | 前锋居前、主力分列两侧后方 | 标准推进、快速形成接触 | 前锋承压较高 |
| `EchelonLeft/Right` | 向指定侧翼斜向展开 | 单翼突击、保护另一翼 | 弱侧容易被穿透 |
| `Screen` | 保护对象前方或威胁侧形成弧形 | 旗舰/航母护航、反潜、防空 | 护卫舰可能被诱离 |
| `Dispersed` | 保持较大间隔，无严格轴线 | 对抗范围技能、航空和密集鱼雷 | 集火与互相支援减弱 |

阵型本身不提供命中、闪避或伤害加成；价值来自站位、视野、射界和防空覆盖。

阵位保持使用三层距离：

```text
舒适圈：不修正，继续当前任务
修正圈：逐步调整航速与航向回到阵位
脱队圈：完成紧急动作后优先归队，必要时由编组减速接应
```

首轮建议只做固定阵型和弹性阵位，不做战斗中自由切换六种阵型。阵型转换可以先由关卡阶段切换时重新生成槽位。

### 5.5 碰撞、边界与拥堵

- `_resolve_unit_overlap()` 保留为最后安全网，但 AI 不应依赖事后重叠分离完成避碰。
- 每艘舰预测短时间内与友军、敌舰、鱼雷和静态障碍的最近接近距离。
- 两艘友军冲突时，非旗舰、高机动、低任务优先级单位优先让路；双方均高优先级时按稳定实体 ID 决定。
- 让路优先小幅减速或向阵型外侧偏转，避免一艘舰的规避把整列舰船推向同一方向。
- 地图边缘设置软警戒区和硬限制区。普通模式不得把长期航点设在软警戒区内。
- 被逼入边界时优先沿边界切向脱离，而不是继续正对边界加速。
- 卡住检测保存数秒内位置进度和恢复次数；恢复可按“减速让路 -> 外扩航点 -> 强制脱离方向”逐级升级。

### 5.6 接触、搜索与巡逻

- 失去侦查时立即清除攻击锁定。
- 残影只能用于搜索、区域技能判断和航线风险估计，不能用于普通锁定攻击或持续追踪。
- 使用最后已知位置生成 2 至 3 个确定性搜索航点。
- 多舰搜索按稳定 ID 分配左/中/右扇区，避免全部冲向同一点。
- 残影置信度可由 `ghost_remaining` 线性推导，不需要首轮概率云。
- 无敌情巡逻可由关卡任务区与出生区生成固定巡逻弧线。

### 5.7 岛屿与掩体规则

当前地图只有宽、高和海况。岛屿 AI 不是增加一个“靠岛坐标”规则即可完成，它依赖：

1. 岛屿碰撞多边形和舰船安全膨胀区。
2. 玩家与 AI 共用的可通行查询或导航图。
3. 水面侦查视线遮挡查询。
4. 直射火炮、鱼雷和航空分别配置的遮挡规则。
5. 地图数据、编辑/验证工具和调试显示。
6. 玩家移动命令也能绕开障碍，不能只给 AI 寻路。

因此，岛屿寻路、岛后掩体、岛端鱼雷伏击和绕岛出击均应排在“玩家与 AI 共用地形、寻路和遮挡”之后，不计入首轮 AI 模式工期。

## 6. 单舰行动模式

### 6.1 模式总表

| 模式 | 行动意图 | 攻击偏好 | 技能偏好 | 首轮可行性 |
|---|---|---|---|---|
| `ReconAvoid` | 前出维持视野，避免硬接战 | 仅打低风险目标，暴露风险高时禁火 | 侦查、机动、烟幕/撤离类 | `M` |
| `VanguardLine` | 占据前锋阵位，与敌前排对线 | 驱逐、潜艇、轻巡和突破目标 | 生存、干扰、短冷却火力 | `S-M` |
| `TorpedoFlank` | 从左/右翼制造雷击夹角 | 战列、航母、旗舰、慢速高价值目标 | 雷击强化、机动、隐蔽 | 简化版 `L` |
| `FlagshipRaid` | 发现机会后绕袭旗舰/航母 | 旗舰、航母、高 Cost 后排 | 爆发、突进、保命 | `M-L` |
| `EscortScreen` | 保护旗舰、航母或主力舰 | 威胁保护对象的近敌、潜艇、驱逐 | 防御、反潜、防空、嘲讽 | `M-L` |
| `AntiAirEscort` | 保持防空覆盖，拦截航空威胁 | 航空实体或来袭机群 | 防空强化、护盾 | 当前 `Blocked` |
| `GunlineSupport` | 保持中远距离炮线输出 | 重巡、战列、航母、旗舰 | 火控、增伤、装填 | `M` |
| `HoldDecisiveLine` | 守住任务线或关键区域 | 进入区域的高威胁目标 | 范围支援、防御 | `S-M` |
| `CarrierStandoff` | 保持远离水面威胁并持续输出 | 高价值可见目标，避免追轻舰 | 航空、侦查、撤离 | `S-M` |
| `SubmarineAmbush` | 潜航接近，伏击高价值目标 | 战列、航母、旗舰 | 潜航、雷击、脱离 | 当前 `Blocked` |
| `DisengageRegroup` | 脱离危险、恢复阵位或等待冷却 | 只保留自卫攻击 | 防御、机动、修复 | `S-M` |

首轮推荐真正实现 6 个模式：

```text
ReconAvoid
VanguardLine
TorpedoFlank（简化版）
GunlineSupport
CarrierStandoff
DisengageRegroup
```

`HoldDecisiveLine` 可先作为 `GunlineSupport` 的参数变体。`AntiAirEscort` 和 `SubmarineAmbush` 等航空、潜航闭环完善后再做。

### 6.2 舰种与模式搭配

舰种只限制合理模式集合，不锁定唯一行为。

| 舰种 | 推荐可选模式 |
|---|---|
| 驱逐舰 | `ReconAvoid`、`VanguardLine`、`TorpedoFlank`、`FlagshipRaid`、`EscortScreen`、`DisengageRegroup` |
| 轻巡洋舰 | `VanguardLine`、`EscortScreen`、`GunlineSupport`、`HoldDecisiveLine`、`DisengageRegroup` |
| 重巡洋舰 | `GunlineSupport`、`VanguardLine`、`EscortScreen`、`HoldDecisiveLine`、`DisengageRegroup` |
| 战列舰 | `GunlineSupport`、`HoldDecisiveLine`、`EscortScreen`、`DisengageRegroup` |
| 航母 | `CarrierStandoff`、`HoldDecisiveLine`、`DisengageRegroup` |
| 潜艇 | `SubmarineAmbush`、`ReconAvoid`、`DisengageRegroup` |

岛风这类高级驱逐舰示例：

- `ReconAvoid`：前出获取视野，保持侦查边缘，除非有低风险机会否则不主动暴露。
- `TorpedoFlank`：被分配左/右翼航点，等待鱼雷装填与扇面合法后攻击旗舰、航母或战列。
- `FlagshipRaid`：敌旗舰/航母暴露且护航薄弱时进入斩首；血量、边界或敌我压力恶化后切回 `DisengageRegroup`。
- `VanguardLine`：作为高机动前锋压制敌驱逐与潜艇威胁，为主力争取射界。

## 7. 统一量化原则

所有输入先转换到 `[0, 1]`，最终效用统一为 `[0, 100]`：

```text
clamp01(x) = clamp(x, 0, 1)
score100(x) = clamp(100 * x, 0, 100)
```

先做硬门槛，再评分。硬门槛失败的候选不得通过高权重补回来。

典型硬门槛：

- 目标存活、阵营合法、当前可见。
- 武器/技能目标类型合法。
- 模式在该舰允许集合中。
- 实际提交攻击或技能命令时满足射程、射角和冷却要求。
- 移动目标位于合法地图区域。

确定性规则：

- 同分使用稳定实体 ID 决胜。
- 首轮不在评分中加入随机扰动。
- 反应差异用决策间隔、确认次数和难度参数表达，不用随机犯错。
- 所有评分分量和最终选择可写入调试事件。

## 8. 目标评分

AI 必须区分两类目标：

- `task_target_id`：机动任务目标，可以是射程外的已发现敌舰、保护对象或残影搜索区。
- `attack_target_id`：当前武器攻击目标，必须满足可见性和武器合法性。

失去侦查时立即清除 `attack_target_id`；`task_target_id` 只能转为最后已知位置任务，不能继续读取目标实时位置。

### 8.1 目标分量

| 分量 | 符号 | 范围 | 首轮计算 |
|---|---|---:|---|
| 模式任务价值 | `M` | 0-1 | 查模式—目标类型权重表；旗舰取模式的旗舰覆盖值 |
| 对当前任务的威胁 | `T` | 0-1 | 距保护对象/自身的接近程度、近期伤害和突破方向 |
| 武器适配 | `W` | 0-1 | 当前可用武器对目标类型/装甲厚度的适配 |
| 距离带适配 | `R` | 0-1 | 目标距离与模式期望射程比例的接近程度 |
| 击沉机会 | `K` | 0-1 | `1 - target_hp_ratio` |
| 编组集火 | `F` | 0-1 | 是当前合法编组目标则为 1，否则为 0 |
| 追击成本 | `P` | 0-1 | 距离、转向和脱队成本 |
| 过量伤害 | `O` | 0-1 | 已分配重武器预计伤害 / 目标剩余 HP |

### 8.2 模式任务价值 `M`

首轮类型权重：

| 模式 | 驱逐 | 轻巡 | 重巡 | 战列 | 航母 | 潜艇 | 旗舰覆盖值 |
|---|---:|---:|---:|---:|---:|---:|---:|
| `VanguardLine` | 0.95 | 0.75 | 0.45 | 0.35 | 0.55 | 1.00 | 0.65 |
| `TorpedoFlank` | 0.35 | 0.50 | 0.65 | 0.90 | 0.95 | 0.20 | 1.00 |
| `FlagshipRaid` | 0.20 | 0.30 | 0.45 | 0.75 | 0.95 | 0.10 | 1.00 |
| `EscortScreen` | 0.70 | 0.55 | 0.45 | 0.35 | 0.40 | 1.00 | 0.60 |
| `GunlineSupport` | 0.35 | 0.55 | 0.80 | 0.95 | 0.80 | 0.15 | 0.90 |
| `CarrierStandoff` | 0.45 | 0.65 | 0.75 | 0.85 | 0.90 | 0.25 | 1.00 |

```text
M = max(class_weight, flagship_override if target.is_flagship else 0)
```

### 8.3 威胁 `T`

```text
proximity = clamp01(1 - distance_to_protectee / threat_radius)
recent_damage = clamp01(damage_from_target_last_6s / (protectee_max_hp * 0.15))
route_threat = 1 if target is between protectee and main threat axis else 0

T = clamp01(
  0.55 * proximity
  + 0.30 * recent_damage
  + 0.15 * route_threat
)
```

没有保护对象时，`protectee` 使用自身。第一版若尚未保存按来源近期伤害，`recent_damage` 暂取 0，并把 `proximity` 权重临时提高到 0.75。

### 8.4 武器适配 `W`

首轮不重复伤害公式，只使用已经配置的目标类型和 `armor_damage_modifiers`：

```text
armor_fit = clamp01((armor_modifier - 0.20) / 1.05)
reload_ready = clamp01(1 - reload_remaining / base_reload_time)
weapon_fit = armor_fit * (0.60 + 0.40 * reload_ready)

W = max(所有能攻击该目标类型的武器 weapon_fit)
```

第二阶段可由 `DamageService` 提供只读预估接口，但不得在 AI 中复制伤害公式。

### 8.5 距离带适配 `R`

```text
distance_ratio = distance / primary_effective_range
R = clamp01(1 - abs(distance_ratio - preferred_range_ratio) / range_band_half_width)
```

| 模式 | `preferred_range_ratio` | `range_band_half_width` |
|---|---:|---:|
| `VanguardLine` | 0.60 | 0.45 |
| `TorpedoFlank` | 0.82 | 0.30 |
| `FlagshipRaid` | 0.72 | 0.35 |
| `EscortScreen` | 0.55 | 0.50 |
| `GunlineSupport` | 0.75 | 0.30 |
| `CarrierStandoff` | 0.85 | 0.45 |

### 8.6 追击成本 `P` 与过量伤害 `O`

```text
distance_cost = clamp01(distance / (primary_effective_range * 1.50))
turn_cost = abs(shortest_angle_to_target) / PI
leash_cost = clamp01(distance_from_group_slot / mode_leash_distance)

P = clamp01(0.45 * distance_cost + 0.30 * turn_cost + 0.25 * leash_cost)
O = clamp01(assigned_heavy_damage / max(target_current_hp, 1))
```

第一版不必精确预测所有在途伤害，只登记主炮轮次、鱼雷波和航空波等重武器的保守预计伤害；自动小口径武器不参与预留。

### 8.7 最终目标分

标准难度默认公式：

```text
target_score = clamp(
  100 * (
    0.30 * M
    + 0.22 * T
    + 0.18 * W
    + 0.12 * R
    + 0.10 * K
    + 0.08 * F
    - 0.12 * P
    - 0.12 * O
  ),
  0,
  100
)
```

正向权重合计为 1，便于阅读；`P` 和 `O` 是额外惩罚，最多各扣 12 分。模式可以覆盖权重，但正向权重必须归一化为 1。

### 8.8 目标切换

推荐基线：

```text
target_minimum_hold = 2.0s
target_switch_margin = 12 points
target_switch_confirmations = 2
target_switch_cooldown = 1.5s
```

切换规则：

1. 当前目标非法、沉没或失去侦查：立即清除，不使用滞回。
2. 最短保持时间内不切换，紧急护航目标除外。
3. 新目标分必须至少高于当前目标 12 分。
4. 连续两次 0.5 秒决策都满足才切换。
5. 切换后 1.5 秒内不再次主动切换。

## 9. 模式切换量化

### 9.1 通用态势分量

| 分量 | 符号 | 计算 |
|---|---|---|
| HP 安全度 | `H` | `clamp01((hp_ratio - 0.20) / 0.60)` |
| 低 HP 压力 | `L` | `1 - H` |
| 局部敌我压力 | `Q` | 见下式 |
| 主要武器就绪 | `W_r` | 主要组内最高 `reload_ready` |
| 有效目标 | `V_t` | 有合法可见任务目标为 1，否则为 0 |
| 视野需求 | `V_n` | `1 - visible_enemy_count / known_alive_enemy_count` |
| 编组凝聚 | `C` | `1 - clamp01(distance_to_slot / leash_distance)` |
| 边界安全 | `B_s` | `1 - boundary_risk` |
| 侧翼路径质量 | `F_q` | 左/右翼候选路径的安全和横向展开评分 |
| 脱离出口质量 | `E_q` | 可用候选脱离方向比例与最佳安全分 |
| 高价值目标暴露 | `X` | 已发现旗舰/航母/高 Cost 主力时为 0.7-1，否则 0 |

局部战力使用 Cost 和剩余 HP，不读取隐藏敌人：

```text
unit_power = cost * hp_ratio
friendly_power = sum(局部友军 unit_power)
visible_enemy_power = sum(局部可见敌军 unit_power)
power_ratio = visible_enemy_power / max(friendly_power, 1)
Q = clamp01((power_ratio - 0.80) / 1.20)
```

局部半径建议为自身主要武器射程的 `1.2` 倍。

### 9.2 模式效用公式

首轮示例公式：

```text
U_DisengageRegroup = score100(
  0.35 * L
  + 0.25 * Q
  + 0.20 * (1 - B_s)
  + 0.20 * E_q
)

U_ReconAvoid = score100(
  0.35 * V_n
  + 0.25 * H
  + 0.20 * B_s
  + 0.20 * C
)

U_VanguardLine = score100(
  0.30 * V_t
  + 0.25 * H
  + 0.20 * C
  + 0.15 * (1 - Q)
  + 0.10 * W_r
)

U_TorpedoFlank = score100(
  0.30 * F_q
  + 0.25 * W_r
  + 0.20 * X
  + 0.15 * H
  + 0.10 * B_s
)

U_GunlineSupport = score100(
  0.30 * V_t
  + 0.25 * W_r
  + 0.20 * C
  + 0.15 * B_s
  + 0.10 * H
)

U_CarrierStandoff = score100(
  0.30 * (1 - Q)
  + 0.25 * B_s
  + 0.20 * H
  + 0.15 * V_t
  + 0.10 * E_q
)
```

`DisengageRegroup` 不需要成为最高分才可触发；当生命、边界或局部压力达到紧急条件时直接进入。

### 9.3 切换门槛

推荐基线：

```text
mode_decision_interval = 0.5s
mode_minimum_hold = 4.0s
mode_enter_threshold = 60
mode_exit_threshold = 40
mode_switch_margin = 15
mode_switch_confirmations = 2
mode_recovery_time = 1.5s
```

普通切换规则：

1. 当前模式仍合法且未达到最短驻留时间时，不切换。
2. 候选模式分数必须高于 `mode_enter_threshold`。
3. 候选模式必须高于当前模式至少 `mode_switch_margin`。
4. 连续两次决策同一候选胜出才切换。
5. 切换后清理目标候选确认次数，但保留合法任务目标。

紧急切换可绕过驻留时间：

- `hp_ratio <= 0.20`。
- `boundary_risk >= 0.80`。
- 已发现鱼雷预计短时间内碰撞。
- 潜艇氧气低于安全阈值。
- 保护对象承受高额近期伤害。

## 10. 技能使用量化

### 10.1 技能标签

技能配置可增加 AI 标签：

| 标签 | 用途 |
|---|---|
| `Burst` | 斩杀、集火窗口、主要武器连招 |
| `Defense` | 低 HP、自身或保护对象受威胁 |
| `Recon` | 失去接触、需要扩大视野、准备远程火力 |
| `Mobility` | 侧翼切入、脱离、边界逃逸 |
| `Escort` | 护航、嘲讽、保护对象减伤 |
| `AreaSupport` | 多目标覆盖、区域控制、阵线推进 |
| `AntiAir` | 拦截航空威胁 |
| `Ambush` | 潜艇或伏击窗口 |

第一阶段建议只实现 `Burst`、`Defense`、`Recon`、`Mobility`、`AreaSupport`。

### 10.2 技能效用

基础门槛：

```text
skill_threshold = 60
easy_skill_threshold = 70
hard_skill_threshold = 52
```

各标签示例：

```text
U_Burst = score100(
  0.35 * kill_opportunity
  + 0.25 * target_value
  + 0.20 * primary_ready
  + 0.20 * focus_fire_window
)

U_Defense = score100(
  0.40 * low_hp_pressure
  + 0.25 * recent_damage_pressure
  + 0.20 * local_pressure
  + 0.15 * escape_quality
)

U_Recon = score100(
  0.40 * vision_need
  + 0.25 * lost_contact_value
  + 0.20 * safe_to_reveal
  + 0.15 * ally_long_range_ready
)

U_Mobility = score100(
  0.30 * flank_window
  + 0.25 * escape_need
  + 0.20 * boundary_pressure
  + 0.15 * weapon_window
  + 0.10 * regroup_need
)

U_AreaSupport = score100(
  0.35 * covered_enemy_value
  + 0.25 * ally_followup_ready
  + 0.20 * zone_importance
  + 0.20 * self_safety
)
```

技能释放仍必须通过技能本身的冷却、资源、目标类型、射程、状态和作用域校验。

### 10.3 连招与保留

部分技能需要与主要武器配合，例如“技能后立刻发射主武器”。不要依赖命令队列里的 `command_id` 排序制造连招。推荐在 AI 运行时状态中显式记录：

```text
pending_combo = {
  type = "FirePrimaryAfterSkill",
  skill_id = "...",
  target_id = "...",
  expires_at = battle_time + 0.8
}
```

连招补发应每个固定 Tick 检查，而不是等下一次 0.5 秒完整决策。

技能保留规则：

- `Burst` 技能在没有高价值目标、主要武器未就绪或目标即将丢失时可保留。
- `Defense` 技能通常不保留，达到危险阈值优先使用。
- `Recon` 技能在己方已经拥有稳定视野时保留。
- `Mobility` 技能可为侧翼窗口或紧急脱离保留，但边界/濒死优先级更高。

## 11. 边界处理量化

当前 `_clamp_to_map()` 只钳制单位中心点。实现 AI 边界前，应先引入半径感知的硬边界，确保单位圆不会视觉上越界。

### 11.1 动态边界距离

```text
turn_radius = reference_speed / max(turn_rate_rad, 0.01)
hard_margin = collision_radius + 12
soft_margin = clamp(
  1.5 * turn_radius + 2 * collision_radius,
  96,
  min(map_width, map_height) * 0.12
)
```

`reference_speed` 使用当前速度与最大速度的较大值，避免静止单位低估转出空间。

### 11.2 边界风险

```text
edge_now = 1 - clamp01(distance_to_edge / soft_margin)
future_position = position + velocity * lookahead_time
edge_future = 1 - clamp01(distance_from_future_position_to_edge / soft_margin)
outward = clamp01(dot(normal_to_nearest_edge, velocity_dir))

boundary_risk = clamp01(
  0.45 * edge_now
  + 0.35 * edge_future
  + 0.20 * edge_now * outward
)
```

`lookahead_time` 推荐 1.5 至 2.5 秒，高速驱逐取高值，低速战列取低值。

### 11.3 处理区间

| 风险 | 处理 |
|---:|---|
| `< 0.35` | 不干预，仅正常航行 |
| `0.35-0.65` | 航向评分加入边界惩罚 |
| `0.65-0.80` | 强制候选方向优先沿边界切向或向内 |
| `>= 0.80` | 进入 `BoundaryEscape` 打断，必要时切到 `DisengageRegroup` |

沿边界切向脱离时，先计算最近边界法线，再在两个切向方向中选择与任务目标、友军密度和敌方威胁综合评分更高的一侧。

## 12. 数据与程序结构

### 12.1 推荐数据字段

AI Profile 可声明：

```json
{
  "id": "ai_profile_shimakaze_elite",
  "allowed_modes": ["ReconAvoid", "TorpedoFlank", "VanguardLine", "DisengageRegroup"],
  "default_mode": "ReconAvoid",
  "fallback_mode": "DisengageRegroup",
  "common_rule_set_id": "ai_rules_default_surface",
  "formation_plan_id": "formation_wedge_fast_flank",
  "difficulty_modifiers": {
    "decision_interval": 0.5,
    "skill_threshold_offset": 0,
    "mode_switch_margin_offset": 0
  }
}
```

技能可增加：

```json
{
  "ai_tags": ["Burst", "Mobility"],
  "ai_policy_id": "burst_then_primary"
}
```

`ai_policy_id` 必须是程序内支持的有限策略 ID，不能在 JSON 中放可执行表达式。

### 12.2 推荐程序落点

首轮可在 Application 层新增纯逻辑对象：

```text
scripts/application/ai/ai_controller.gd
scripts/application/ai/ai_observation.gd
scripts/application/ai/ai_runtime_state.gd
scripts/application/ai/target_scorer.gd
scripts/application/ai/mode_evaluator.gd
scripts/application/ai/skill_evaluator.gd
scripts/application/ai/boundary_steering.gd
```

运行时状态建议包含：

```text
mode_id
mode_entered_at
mode_candidate_id
mode_candidate_confirmations
task_target_id
attack_target_id
target_acquired_at
target_candidate_id
target_candidate_confirmations
active_interrupt
skill_reserve_reason
pending_combo
recent_damage_by_source
decision_cooldown
```

这些状态属于 Application/策略层，不进入 Presentation，也不把关卡行为脚本堆入 `UnitState`。最终移动、碰撞、边界、地形通行、视线、攻击与技能合法性仍由 Domain/战斗系统决定。

## 13. 实现可行性与裁剪顺序

工作量等级：

| 等级 | 含义 | 粗略量级 |
|---|---|---|
| `S` | 可在现有函数附近扩展，风险低 | 0.5-2 人日 |
| `M` | 需要新增稳定状态或服务，并补自动测试 | 2-5 人日 |
| `L` | 跨移动、感知、数据或协同系统 | 1-2 周 |
| `XL` | 依赖尚不存在的地图/领域子系统 | 2-4 周以上 |
| `Blocked` | 前置玩法尚未实现，不应现在开发 | 前置完成后重估 |

### 13.1 第一阶段：AI MVP

建议先完成：

1. `AI Runtime State`、低频决策调度和调试事件。
2. `AIObservation`，保证敌方 AI 只读取合法可见信息。
3. 目标评分、目标滞回和当前目标解释日志。
4. 敌方主要武器命令，先对可见目标当前位置或简单提前点提交。
5. 简单技能阈值，支持 `Burst`、`Defense`、`Recon`、`Mobility`、`AreaSupport`。
6. 边界软警戒、切向脱离和半径感知硬钳制。
7. 四到六个模式：`VanguardLine`、`GunlineSupport`、`CarrierStandoff`、`DisengageRegroup`，再加入 `ReconAvoid` 和简化 `TorpedoFlank`。

这一阶段不做完整编队换阵、岛屿掩体、航空拦截和潜艇伏击。

### 13.2 第二阶段：协同与侧翼

在 MVP 稳定后加入：

- 固定阵型槽位、舒适/修正/脱队三层。
- 简化战术编组和保护对象。
- 侧翼航点、发射后脱离和目标预留。
- 残影搜索、多舰搜索分区和归队。
- 友军预测避碰和稳定让路权。

### 13.3 暂缓内容

以下内容仍暂不纳入首轮：

- 多出口掩体槽位、岛后伏击和编组级地形协同；基础岛屿寻路与视线遮挡已在港湾接入。
- 公平鱼雷规避的完整版本，需先实现投射物阵营可见性。
- `AntiAirEscort`，需完整航空实体与来袭机群规则。
- `SubmarineAmbush`，需潜航、氧气和反潜闭环。
- 战斗中复杂动态换阵和 11v11 多编组自由协同。

## 14. 调试与验证

AI 决策应记录以下调试事件：

- 模式切换：旧模式、新模式、分数、触发条件、是否紧急。
- 目标切换：旧目标、新目标、总分和各分量。
- 技能使用：技能 ID、标签、效用、阈值、保留或释放原因。
- 边界打断：风险值、最近边、选择的切向方向。
- 主要武器：目标、射程、射角、是否由连招触发。

建议测试：

1. 固定种子 3v3：AI 模式切换、目标选择和技能使用可重复。
2. 岛风场景：同一舰船分别配置 `ReconAvoid`、`TorpedoFlank`、`VanguardLine` 时行为明显不同。
3. 边界场景：高速舰贴近边缘时提前切向脱离，不再长期撞边。
4. 失去侦查：攻击目标立即清除，残影只驱动搜索航点。
5. 技能阈值：低难度更保守，高难度更积极，但不读取隐藏信息。
6. 批量模拟：记录平均战斗时长、旗舰击沉率、AI 越界/卡住次数、主要武器空转率和技能浪费率。

若测试发现 AI 显得“聪明但不可读”，优先增加驻留时间、切换门槛和航路稳定性，而不是降低命中或伤害数值。
