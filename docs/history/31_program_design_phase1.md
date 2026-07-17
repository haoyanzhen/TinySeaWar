# 第一阶段程序设计参考说明（历史存档）

> 存档说明：本文记录第一阶段 3v3 原型的早期实施范围，已不再作为当前架构、实现状态或代码位置的权威来源。当前技术边界见 `docs/30_technical_architecture.md`、`docs/32_domain_design_phase1.md` 与 `docs/33_domain_design_phase2.md`；当前代码位置见 `docs/34_implementation_map.md`；完成状态只见 `docs/00_project_status.md`。

## 1. 文档目的

本文档用于指导 Tinny Sea War 第一阶段战斗原型的程序实现。

第一阶段的首要目标不是完成全部设计内容，而是尽快获得一个可重复游玩的 3v3 战斗切片，用于验证：

- 舰娘在战场上的移动、距离感和交战节奏是否符合预期。
- 侦查、隐蔽、炮击、鱼雷和主动技能能否形成清晰的战术反馈。
- 自动战斗与玩家指令的比例是否合适。
- 角色美术、舰装、动画、投射物和 UI 在真实战斗中的可读性。
- 当前伤害公式、角色数值和资源消耗是否具备继续调参的基础。

程序结构需要支持后续加入六舰种、航空、防空、潜艇、阵型、更多技能、更多关卡和更大规模战斗，但第一阶段不得为了尚未验证的最终功能提前实现完整系统。

相关设计依据：

- `docs/32_domain_design_phase1.md`
- `docs/11_game_operation_design.md`
- `docs/30_technical_architecture.md`
- `docs/10_game_core_mechanics.md`
- `docs/20_data_schema_design.md`（数据契约索引）
- `docs/21_combat_data_schema.md`
- `docs/23_level_progress_data_schema.md`
- `docs/24_ai_data_schema.md`
- `docs/12_combat_formula_design.md`
- `docs/13_balance_baseline.md`
- `docs/history/90_design_audit_round4.md`

---

## 2. 第一阶段范围

### 2.1 必须实现

- Godot 4.x 项目可在 macOS 编辑器中运行。
- 一个固定边界的开阔海域战场。
- 1v1 调试关和 3v3 标准验证关。
- 5-6 名 Prototype 角色，覆盖至少驱逐、轻巡、战列三类舰种。
- 单位选择和移动目标指令。
- 对已发现目标下达集火指令。
- 自动移动、自动索敌和不可控武器自动攻击。
- 生命、装甲、航速、转向、侦查、隐蔽和闪避。
- 火炮与鱼雷两种攻击方式。
- 鱼雷使用可见实体投射物和碰撞判定。
- 每名 Prototype 角色一个主动技能。
- 技能的自身、目标或区域选择。
- `F` 技能、`Q` HE/AP、`E` 主要武器、`V` 视角跟踪的统一操作。
- `1` 到 `9`、`0`、`-` 快捷选择己方第 1 到第 11 位角色，预留 11v11 兼容。
- 旗舰胜负条件。
- 暂停、重开和基础结算界面。
- 基础战斗 HUD、血条、技能冷却和旗舰标记。
- 可输出关键战斗统计，支持数值复盘。

### 2.2 暂不实现

- 航空、防空和舰载机完整流程。
- 潜艇、氧气、上浮、下潜和反潜。
- 阵型集合与统一移动。
- 自由手绘路径和多节点路径编辑。
- 逐座控制炮塔、鱼雷管或防空武器；第一阶段只控制配置指定的一个主要武器组。
- 11v11 正式关卡。
- 岛屿、导航网格、视线遮挡和占点。
- 养成、抽卡、装备更换、基地、剧情和长期存档。
- 联机和回放。

这些功能应保留扩展位置，但不进入第一阶段完成标准。

---

## 3. 技术原则

### 3.1 数据驱动

角色、武器、投射物、技能和关卡的差异应来自配置，不为每名角色复制一套战斗逻辑。

第一阶段建议使用 JSON 作为人工维护和版本管理的配置真源。Godot 启动时加载并校验 JSON；后续如有性能或编辑器需求，可以增加导入工具生成 `.tres` 缓存，但不得同时维护两份可独立修改的真源数据。

配置至少划分为：

```text
data/
  ships/
  weapons/
  projectiles/
  skills/
  levels/
  formulas/
```

所有配置使用稳定 `id` 相互引用。加载阶段应检查重复 ID、缺失引用、枚举错误和必要字段缺失。

### 3.2 组合优于角色继承

所有水面舰使用同一个基础 `ShipUnitView` 场景显示，并使用统一的 Domain `UnitState` 表达战斗能力。领域能力按职责组合：

- 移动状态与规则。
- 生命与受击规则。
- 侦查状态与规则。
- 武器状态与规则。
- 技能状态与规则。
- 状态效果与属性修正。
- AI 命令生产策略。

这些能力的真状态和规则位于 Domain，场景节点只提供对应表现。舰种和角色不建立深层继承树。只有行为生命周期确实不同的单位，例如后续舰载机和区域效果，才使用独立领域实体或基础场景。

### 3.3 计算与表现分离

伤害、命中、侦查和状态叠加由不依赖画面节点的计算模块完成。动画、音效、特效和伤害数字只消费结算结果，不参与决定结果。

这样可以：

- 对公式运行自动测试。
- 在无画面环境下批量模拟战斗。
- 调整表现而不改变数值。
- 将来实现回放或网络同步时复用战斗事件。

### 3.4 先支持验证，再支持规模

第一阶段只需稳定运行 3v3，但系统设计目标为至少支持 11v11 压力测试。不要为 11v11 编写特殊玩法逻辑；应通过对象池、集中式侦查查询、低频 AI 决策和可控的特效数量逐步验证性能。

---

## 4. 推荐目录结构

### 4.1 与当前仓库的兼容性

当前仓库已经存在以下顶层目录：

```text
assets/    角色源图、处理后资产和 QA 产物
data/      预留的运行时配置目录
design/    程序设计与实施参考
docs/      游戏、数值、美术和数据设计文档
scenes/    预留的 Godot 场景目录
scripts/   预留的 GDScript 目录
tools/     仓库外部运行的资产处理工具
```

本设计与该结构兼容。`scenes/`、`scripts/` 和 `data/` 直接在现有目录内扩展，不移动 `docs/`、`design/`、`tools/` 或现有角色资产。新增 `autoload/` 和 `project.godot` 即可把仓库根目录作为 Godot 项目根目录。

需要特别区分两类 JSON：

- `data/` 保存游戏运行时配置，是战斗数据真源。
- `assets/characters/{id}/processed/config/` 保存美术裁切、动画和绑定点配置，只负责资产装配，不保存角色战斗数值。

角色运行时场景应直接引用：

```text
assets/characters/{id}/processed/battle/
assets/characters/{id}/processed/anim/
assets/characters/{id}/processed/ui/
assets/characters/{id}/processed/vfx/
assets/characters/{id}/processed/config/
```

不要复制这些文件到另一个 `assets/art/` 目录，否则会形成两套资产真源，并破坏现有美术后处理工具的输出契约。

#### Godot 资源扫描约束

仓库中的角色目录同时保存母版 sheet、拆分结果和 QA 文件。若 `project.godot` 位于仓库根目录，Godot 会扫描 `res://` 下可识别的资源；只是不在场景中引用，并不能阻止源 PNG 被导入。

初始化 Godot 项目时，应使用 `.gdignore` 排除不参与运行时加载的目录：

```text
assets/characters/qa/
assets/characters/{id}/concept/
assets/characters/{id}/battle/
assets/characters/{id}/ui/
assets/characters/{id}/vfx/
assets/characters/{id}/meta/
assets/characters/{id}/processed/source_alpha/
tools/
```

其中 `processed/battle`、`processed/anim`、`processed/ui`、`processed/vfx` 和 `processed/config` 必须保持可见。`.gdignore` 的具体放置应由项目初始化步骤统一生成，避免误把整个角色目录排除。

`tools/` 中的 Python 程序继续从仓库根目录运行，不作为 Godot 运行时代码。`docs/` 和 `design/` 可以保留在项目根目录；它们不会影响运行时，但发布导出预设应只打包游戏所需资源。

### 4.2 目标目录结构

```text
project.godot

assets/
  characters/
    {id}/
      concept/              # 源资产，Godot 忽略
      battle/               # 源资产，Godot 忽略
      ui/                   # 源资产，Godot 忽略
      vfx/                  # 源资产，Godot 忽略
      meta/                 # 生产记录，Godot 忽略
      processed/
        battle/             # 运行时可用
        anim/               # 运行时可用
        ui/                 # 运行时可用
        vfx/                # 运行时可用
        config/             # 资产装配配置
        source_alpha/       # 中间产物，Godot 忽略

autoload/
  game_context.gd
  data_registry.gd
  battle_event_bus.gd

scenes/
  battle/
    battle.tscn
    battle_camera.tscn
  units/
    ship_unit.tscn
  projectiles/
    projectile.tscn
    torpedo_projectile.tscn
  skills/
    area_indicator.tscn
  ui/
    battle_hud.tscn
    unit_panel.tscn
    battle_result.tscn
  levels/
    prototype_1v1.tscn
    prototype_3v3.tscn

scripts/
  domain/                   # 战斗状态、规则、命令、事件和纯计算服务
    battle/
    units/
    weapons/
    projectiles/
    skills/
    detection/
    status/
    commands/
    events/
    services/
  application/              # BattleSession、固定步长、命令调度和快照
  infrastructure/           # JSON 加载、配置校验、统计和随机数源
    data/
    analytics/
    random/
  presentation/             # Godot 节点、战场输入和 HUD
    battle/
    units/
    projectiles/
    ui/
  tests/
    formula_tests.gd
    detection_tests.gd
    battle_smoke_tests.gd

data/
  ships/
  weapons/
  projectiles/
  skills/
  levels/
  formulas/

design/
docs/
tools/
```

这是一份目标视图，不要求一次创建所有空目录。目录名称可根据实际工程调整，但职责边界和现有美术管线输出路径应保持稳定。

---

## 5. 运行时结构

### 5.1 BattleController

`BattleController` 负责一场战斗的生命周期，不直接承担具体公式：

1. 加载关卡和双方舰队配置。
2. 生成单位并设置阵营、出生点和旗舰。
3. 启动战斗时钟和各战斗系统。
4. 接收暂停、重开和结束命令。
5. 监听旗舰沉没与超时事件。
6. 生成战斗结果和统计摘要。

不得把移动、目标选择、武器结算或 UI 更新集中写入该脚本。

### 5.2 ShipUnitView

`ShipUnitView` 是领域单位在 Godot 场景中的表现节点，不保存战斗真状态。建议节点结构：

```text
ShipUnitView (Node2D)
  VisualRoot
    RigBase
    CharacterAnimation
    WeaponMounts
    SelectionMarker
  CollisionBody
  SelectionInput
  AudioRoot
  VfxRoot
```

`ShipUnitView` 只维护 `entity_id`、资产装配和表现状态，通过 `BattleSnapshot` 同步位置、航向、生命和可见性。移动、生命、侦查、武器、技能、状态和 AI 的真状态属于 Domain，详细规则见 `docs/32_domain_design_phase1.md`。

UI 和场景节点不得直接修改领域字段。玩家输入转换为命令，经 Application 校验后修改 Domain；领域事件再驱动炮口火光、伤害数字、技能 cut-in 和沉没动画。

### 5.3 BattleEventBus

领域层在每个固定 Tick 内产生战斗事件，Application 提交状态后再通过 `BattleEventBus` 发布给表现和统计模块。全局事件总线不是领域规则执行器，也不能被用来回写战斗状态。第一阶段建议包含：

- `unit_spawned`
- `unit_selected`
- `unit_detected`
- `unit_lost_detection`
- `weapon_fired`
- `projectile_hit`
- `damage_resolved`
- `skill_cast`
- `unit_sunk`
- `flagship_sunk`
- `battle_finished`

事件用于表现、UI 和统计记录。高频位置、航向、生命和装填显示通过只读 `BattleSnapshot` 更新，不经过全局事件总线。事件的完整字段、顺序和状态所有权见 `docs/32_domain_design_phase1.md`。

---

## 6. 核心系统设计

### 6.1 移动与指令

第一阶段采用“点击目标点移动”，不实现手绘路径。

移动组件负责：

- 最大航速与加减速。
- 转向速度。
- 战场边界限制。
- 到达目标点后的减速和停止。
- 与其他单位重叠时的简单分离。

玩家指令和 AI 指令都转换为统一的 `MoveUnitsCommand`。后续加入阵型或多节点路径时，只需产生不同的移动命令，不应绕过 Domain 移动状态直接修改位置。

### 6.2 侦查

`DetectionSystem` 集中维护双方的可见关系，避免每个单位各自重复扫描全场。

第一阶段规则：

- 按固定频率更新，例如每秒 5-10 次，不要求每帧计算。
- 使用设计文档中的侦查范围与隐蔽距离双条件。
- 开火暴露持续时间按实时隐蔽距离除以实时航速计算。
- 侦查结果按阵营共享。
- 脱离侦查后生成最长 1 分钟残影。
- 残影停留在最后已知位置。
- 残影不能被普通攻击或目标技能锁定。
- 区域技能可以向残影位置释放。
- 目标重新被发现时立即移除残影并显示真实单位。

接口应允许后续加入侦查机、潜航修正、地形遮挡和特殊侦查来源。

### 6.3 目标选择与 AI

AI 决策建议以低频 Tick 执行，例如每秒 2-5 次。

第一阶段状态可以保持简单：

```text
AcquireTarget
ApproachPreferredRange
AttackTarget
FollowPlayerCommand
RecoverTarget
```

目标选择只考虑已发现目标，并根据配置组合舰种优先级、距离、旗舰和玩家集火指令。玩家命令应拥有高于自动行为的优先级，但可设置超时或完成条件，避免永久锁死 AI。

后续特殊行为通过策略或配置增加，不在 `UnitState` 或 `ShipUnitView` 内堆积舰种判断。

### 6.4 武器

每个单位的 Domain `UnitState` 持有多个 `WeaponState`，由统一武器领域服务处理。每个实例读取装备底座 Definition，维护：

- 装填状态。
- 当前目标。
- 射程与射角检查。
- 炮塔转向。
- 一轮发射数量。
- 共享冷却组。
- 自动目标优先级。
- 武器组、控制模式和当前 HE/AP 模式。

火炮和鱼雷共用发射流程，但命中方式不同：

- 火炮：可以使用飞行表现，抵达后执行概率命中和伤害结算。
- 鱼雷：使用实体碰撞，命中后执行伤害结算。

武器只提交攻击请求，不自行扣除目标生命。

每名角色最多一个 `ManualPrimary` 武器组。玩家按 `E` 进入鼠标准心瞄准，左键确认后提交主要武器命令；未被指定为主要武器的副炮、防空、反潜和其他武器维持自动开火。`Q` 只切换配置指定炮组的 HE/AP，不重置装填。完整规则见 `docs/11_game_operation_design.md`。

### 6.5 投射物

投射物由 `ProjectileFactory` 根据配置创建。基础配置应支持：

- 直线或落点移动。
- 速度、生命周期和碰撞半径。
- 可命中的目标类型。
- 命中销毁、穿透次数和范围爆炸。
- 表现资源引用。

第一阶段仅启用必要字段：火炮落点、直线鱼雷、命中销毁。追踪、穿透和复杂范围行为保留配置能力但可以不实现，未支持的枚举必须在加载时明确报错。

### 6.6 伤害结算

统一由 `DamageResolver` 按 `12_combat_formula_design.md` 执行：

1. 验证攻击和目标状态。
2. 执行命中或碰撞结果。
3. 读取武器、攻击方能力和目标装甲。
4. 计算装甲厚度补正与固定减伤。
5. 应用攻击方增益和目标减伤。
6. 生成不可变的 `DamageResult`。
7. 由生命组件应用最终伤害。
8. 发出表现和统计事件。

任何技能和武器都不应复制伤害公式。

### 6.7 技能与状态

技能分为三个层次：

- `SkillConfig`：冷却、目标类型、范围和效果列表。
- `SkillExecutor`：验证释放条件并创建效果。
- `SkillEffect`：即时伤害、属性修正、额外发射或区域效果。

普通属性增益统一保存到 `UnitState.status_effects`，由 `ModifierService` 按 `FlatAdd`、`PercentAdd`、`StateMultiply` 和 `IndependentMultiply` 处理。第一阶段即使没有角色使用独立倍率，也应确保解析器能识别该枚举。

角色专属技能优先组合通用效果。只有无法由通用效果合理表达的机制，才新增专用效果脚本。

### 6.8 胜负与结算

第一阶段以旗舰沉没为主要结束条件。

`VictorySystem` 负责：

- 监听旗舰状态。
- 处理双方旗舰同一结算周期沉没。
- 处理时间限制。
- 记录结束原因。
- 将结果交给结算 UI。

手动结束对局可以暂缓；若实现，剩余生命百分比的分母使用开战时全部出击单位最大生命总和，沉没单位当前生命按 0 计算。

---

## 7. 玩家操作与 UI

第一阶段提供以下战术操作：

1. 选择我方单位并下达移动目标。
2. 选择已发现敌人并设置集火目标。
3. 使用 `F` 释放选中角色技能。
4. 使用 `Q` 切换选中角色可用炮组的 HE/AP。
5. 使用 `E` 进入主要武器瞄准，准心完全跟随鼠标，左键确认攻击。
6. 使用 `V` 切换选中角色视角跟踪。
7. 使用 `1` 到 `9`、`0`、`-` 选择己方第 1 到第 11 槽位角色。

建议基础流程：

- 左键选择单位。
- 右键或明确的移动模式下达移动目标。
- 点击敌方单位设置集火目标。
- 主要武器瞄准状态下右键取消攻击并拦截移动命令；普通状态下右键下达移动目标。
- `Esc` 取消当前技能目标模式或关闭当前界面。
- 主炮将准心解释为炮击海域，鱼雷将角色到准心的方向解释为鱼雷组中心方向，空袭将准心解释为范围中心。

暂停第一阶段只冻结战斗，不允许在暂停时批量规划指令。若后续允许暂停下令，需要作为独立 RTT 规则重新设计。

技能 cut-in 不暂停战斗，使用侧边短动画，持续约 0.6-1.0 秒，不遮挡主要交战区域。

摄像机至少支持：

- 鼠标拖拽平移。
- 滚轮缩放。
- 战场边界限制。
- `V` 跟踪当前选中单位；数字键切换角色时同步切换跟踪目标。
- 屏幕边缘的受击和旗舰威胁提示。

第一阶段不强制制作小地图。

---

## 8. 数据与扩展契约

### 8.1 舰娘配置

使用 `weapon_mounts` 作为唯一武器入口。不要在新代码中支持 `main_weapon`、`torpedo_weapon` 和 `anti_air_weapon` 兼容字段。

`variant_tags` 默认作为设计、筛选和测试元数据。只有系统明确查询某个标签时，标签才产生运行时效果。

### 8.2 武器与投射物

装备底座引用 `projectile_id`。两用武器使用 `shared_cooldown_group` 表达共享物理底座，不通过复制两套独立计时器模拟。

### 8.3 后续舰种扩展

- 航母：新增航空单位和部署技能，不修改基础伤害接口。
- 防空：作为目标类型为 `Air` 的周期武器接入武器控制器。
- 潜艇：通过单位状态、隐蔽修正和可攻击目标类型扩展，不另写一套战斗系统。
- 反潜：作为目标类型为 `Submerged` 的武器或区域效果。

### 8.4 后续战斗模式

关卡模式通过规则对象或配置切换胜负条件、出生逻辑和地图目标。不要在 `BattleController` 中不断增加 `if battle_mode == ...` 分支。

岛屿和地形加入后，可以替换或扩展移动与侦查查询，但单位命令、伤害和技能接口保持不变。

---

## 9. 战斗记录与验证指标

第一阶段必须记录足够的数据判断“战斗效果是否符合预期”，不能只依赖观看感受。

每场战斗建议输出：

- 战斗持续时间。
- 首次发现敌人的时间。
- 首次开火和首次命中的时间。
- 首次击沉时间。
- 各单位伤害、承伤和有效命中率。
- 各武器发射次数、命中次数和伤害占比。
- 技能释放次数和技能贡献。
- 各单位被发现的累计时间。
- 玩家移动、集火和技能指令次数。
- 旗舰死亡来源。

第一阶段重点观察：

- 3v3 是否能在合理时间内自然产生交战。
- 驱逐、轻巡和战列是否具有可感知的射程、机动和火力差异。
- 鱼雷是否可预警、可躲避，同时保持威胁。
- 未发现目标是否真的无法被普通攻击锁定。
- 玩家指令是否明显改变战局，而不是只做形式操作。
- 角色、舰装、弹道和 UI 在缩放后的战场中是否清楚。

暂不锁死最终目标值。首轮测试完成后，再根据实测分布修订 `13_balance_baseline.md`。

---

## 10. 测试要求

### 10.1 纯计算测试

- 侦查边界与开火破隐。
- 再隐蔽时间公式。
- 命中率上下限。
- 装甲厚度补正和固定减伤。
- 0 伤害结果。
- 状态叠加顺序和上限。
- 技能冷却。
- 旗舰同时沉没。

### 10.2 场景测试

- 单位能正确加载角色资产和绑定点。
- 炮口、鱼雷口和投射物出生位置正确。
- 角色左右翻转不会导致连续抖动。
- 舰装和炮塔朝向不会被角色镜像错误影响。
- 3v3 连续运行多局不出现目标引用失效或战斗无法结束。

### 10.3 无画面模拟

建议尽早提供简化的批量战斗模拟入口。它可以跳过动画和特效，以加速倍率运行相同的 AI、武器、伤害和胜负逻辑，用于发现明显数值失衡。

模拟结果不能代替真实战斗观感测试，但可以筛除大量无效参数组合。

---

## 11. 实施顺序

### 里程碑 1：最小交火

- 初始化 Godot 项目和数据加载。
- 创建基础战场、单个 Domain `UnitState` 与对应 `ShipUnitView`。
- 实现移动、生命、火炮和伤害数字。
- 完成 1v1 自动交火。

### 里程碑 2：核心战斗

- 加入侦查、目标选择和鱼雷投射物。
- 加入旗舰胜负和战斗结算。
- 接入正式角色战场资产。
- 完成稳定的 3v3 自动战斗。

### 里程碑 3：玩家战术操作

- 加入选择、移动、集火和技能目标模式。
- 完成 HUD、冷却和关键信息提示。
- 加入摄像机控制和技能 cut-in。

### 里程碑 4：验证与调整

- 输出战斗记录。
- 增加批量模拟和关键公式测试。
- 调整首次接敌、击沉时间、鱼雷威胁和玩家指令收益。
- 确定航空、潜艇或阵型中哪一项最适合进入下一阶段。

---

## 12. 第一阶段完成标准

满足以下条件后，第一阶段可以进入评审：

- 1v1 和 3v3 关卡可重复启动、结束和重开。
- 5-6 名 Prototype 角色通过配置加载，不依赖角色专属单位脚本。
- 火炮、鱼雷、侦查、移动、技能和旗舰胜负形成完整闭环。
- 玩家可以通过移动、集火和技能操作实际改变战斗结果。
- 战斗中的角色、目标、射程威胁和伤害反馈可辨认。
- 连续运行多场 3v3 不出现阻塞性错误。
- 核心公式有自动测试，战斗能输出可比较的统计记录。
- 新增一名同类角色主要通过配置和资产完成，不需要修改核心战斗系统。
- 后续航空、潜艇、阵型和新关卡模式可以沿现有接口扩展，不要求重写单位、伤害和命令体系。

第一阶段评审的最终问题不是“功能是否足够多”，而是：当前战斗是否已经表现出预期的海战距离感、舰种差异、玩家决策价值和角色可读性。如果答案尚不明确，应优先继续调整现有闭环，而不是立即扩大功能范围。
