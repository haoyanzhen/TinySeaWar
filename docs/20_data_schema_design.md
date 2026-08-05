# 数据契约索引与公共约定

## 1. 文档功能与边界

本文是 Tiny Sea War 数据契约体系的总索引，负责规定 Definition、State、Settings、Manifest 与 Experiment 的公共边界、命名、引用和变更流程。具体字段按领域拆分到 `docs/21_combat_data_schema.md` 至 `docs/26_simulation_data_schema.md`。

本文及 21–26 只定义数据形状、必填性、默认值、枚举、引用和加载校验，不重新定义玩法、公式、数值依据、Domain 状态机、实现完成度、代码位置或实验结论。对应真源分别见 `docs/10_game_core_mechanics.md` 至 `docs/19_battle_simulator_design.md`、`docs/32_domain_design_phase1.md`、`docs/35_scene_combat_domain_design.md`、`docs/37_environment_runtime_domain_design.md`、`docs/38_facility_combat_domain_design.md`、`docs/00_project_status.md`、`docs/34_implementation_map.md` 和 `docs/36_balance_testing_design.md`。

## 2. 专题契约路引

| 文档 | 唯一职责 | 主要数据 |
|---|---|---|
| `docs/21_combat_data_schema.md` | 战斗单位与结算输入 | 舰船、武器、公式、投射物、航空、技能、Buff、公共战斗设置 |
| `docs/22_scene_environment_data_schema.md` | 战场空间与场景战术内容 | 地图、地形、静态碰撞场、导航、天气、环境区、设施、支援任务、水雷 |
| `docs/23_level_progress_data_schema.md` | 可玩内容与长期进度 | 当前关卡、舰队成员、目标、进度存档；未实施的阶段与增援只见 t02 |
| `docs/24_ai_data_schema.md` | AI 配置输入 | 难度 Profile、技能 AI 标签、运行时记忆边界 |
| `docs/25_presentation_data_schema.md` | 纯表现配置 | 窗口、镜头、投射物表现、武器表现与 VFX 播放参数 |
| `docs/26_simulation_data_schema.md` | 无图形实验清单 | 实验、场景、策略、种子、侧别、胜率评估与输出 |

新增字段必须写入拥有该字段的专题契约，不再把所有字段追加回本文。

## 3. 数据对象类别

### 3.1 Definition

Definition 是战斗创建前加载并校验的共享配置，例如舰船、武器、技能、地形、设施和关卡。创建战斗后不得由单局状态反向修改或写回。

### 3.2 State

State 是由 Definition 派生的单场可变状态，例如 HP、装填、选择弹种、AI 记忆、设施服务进度和目标进度。State 不作为共享配置保存；只有 `docs/23_level_progress_data_schema.md` 明确允许的长期进度事实可以写入用户存档。

### 3.3 Settings

Settings 是全局共享常量或用户表现偏好。战斗规则设置必须经过数据校验；窗口与镜头等表现设置不得进入 Domain 结算或模拟随机源。

### 3.4 Manifest

Manifest 保存资产语义、发现信息和文件引用，不拥有战斗规则。资产接口只见 `docs/45_art_asset_interface_design.md`；数据契约只记录运行时实际消费的表现参数。

### 3.5 Experiment

Experiment 描述如何组合正式 Definition 运行无图形实验。参数覆盖必须创建隔离 Definition 集，实验不得修改正式配置或玩家进度。

## 4. 公共字段约定

- `id`：稳定、唯一、非空的语义 ID。跨文件引用使用 ID，不使用数组位置、显示名或资源路径。
- `display_name`：面向玩家或编辑器的名称，不参与引用。
- `*_id`：单一引用；`*_ids`：引用数组。加载时必须验证目标存在且类别正确。
- `schema_version`：需要独立迁移的文件必须声明正整数版本；不兼容版本应拒绝加载或经过显式迁移。
- 百分比倍率使用小数，例如 `0.20` 表示 `20%`；概率范围为 `[0, 1]`。
- 距离、位置、速度和时间使用游戏世界单位与秒；角度字段名称必须表明使用度或弧度。
- 二维向量在 JSON 中使用 `[x, y]`；颜色、资产语义和枚举按专题契约规定。
- 可选字段省略时使用专题契约声明的默认值；不得依靠未记录的隐式默认值表达规则差异。

## 5. 引用与校验

加载器至少验证：

- 同一注册类别内 ID 唯一。
- 必填字段存在、类型正确且数值范围合法。
- 枚举值属于白名单。
- 所有跨 Definition 引用存在且类型匹配。
- 舰队实体 ID、武器组 ID、设施放置 ID、目标条件 ID 等局部 ID 在所属对象内唯一。
- 配置不得嵌入脚本路径、回调名或任意可执行表达式；复杂行为只能引用程序支持的有限策略 ID。
- Definition 与 State 分离，单局可变字段不得写回共享配置。

具体负例和跨字段约束由 21–26 的对应章节定义。

## 6. 运行时真源与完成状态

当前运行配置以 `data/` 下被注册表实际加载的 JSON 为准；字段文档不以列出某个目录证明能力已实现。加载入口、校验器和测试位置只见 `docs/34_implementation_map.md`，能力是否完成只见 `docs/00_project_status.md`。

文档字段与运行数据不一致时：

1. 先确认对应玩法、公式或 Domain 真源。
2. 再确认当前数据与加载校验是否仍实际消费该字段。
3. 删除未消费的历史字段，或同步更新专题契约、数据、校验和测试。
4. 不用兼容字段继续承载新功能；兼容只用于显式迁移。

## 7. 变更检查表

新增、重命名或删除配置字段时，必须同步检查：

- 所属 21–26 专题契约。
- 数据文件与生成工具。
- 加载校验和非法配置负例。
- Domain/Application 的读取点与默认值。
- `docs/34_implementation_map.md` 中的入口是否变化。
- `docs/00_project_status.md` 中的完成度是否真的变化。
- 旧字段、旧枚举和旧路径是否仍有残留引用。
