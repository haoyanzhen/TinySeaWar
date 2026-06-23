# Tiny Sea War Agent Guide

本文件是 Codex 进入项目后的总路引。做任何设计、程序、美术资产或数据改动前，先用它判断应该阅读哪些设计文档，以及本次改动应该落在哪一层。

## 项目总纲

Tiny Sea War 是基于 Godot 4.x 的 2D 二次元舰娘海战原型。当前目标不是完整养成游戏，而是做出可重复游玩的战斗切片，用于验证移动、侦查、隐蔽、炮击、鱼雷、主动技能、UI 可读性、美术资产接入和初始数值节奏。

MVP 的核心约束：

- 以开阔海域半即时战斗为主，不做抽卡、养成、剧情、基地和长线经济系统。
- 舰娘是情感与识别核心，航向、武器方向、射程、命中和状态通过舰装、特效、海面叠层与 UI 表达。
- 自动战斗与玩家指令并存：高价值攻击由玩家决定时机，其余武器维持自动交战。
- 战斗规则、公式、数据结构和表现层分离，Domain 层规则应能脱离 Godot 场景树测试。
- 所有数值都是首轮原型基线，允许通过实机测试持续调整。

## 文档路引

设计文档位于 `docs/`，使用数字前缀保持阅读顺序。新增文档请遵守 `docs/README.md` 的命名规则。

### 玩法与数值

- `docs/10_game_core_mechanics.md`：玩法骨架和已确定核心战斗机制。改胜负条件、舰种资源、侦查隐蔽、旗舰、潜航、技能等规则时先读。
- `docs/11_game_operation_design.md`：玩家输入、选中、主要武器、弹药切换、技能和镜头跟随规则。改交互、快捷键、瞄准或反馈时先读。
- `docs/12_combat_formula_design.md`：侦查、命中、伤害、护甲、状态、资源等计算顺序。改公式或战斗结算时必须对齐。
- `docs/13_balance_baseline.md`：MVP 首轮调参范围和节奏目标。改基础范围、战斗时长、资源消耗、舰种基线时参考。
- `docs/14_character_balance_design.md`：角色级初始数值、武器、技能和玩法变体。改角色配置、技能数值、角色定位时参考。

### 数据契约

- `docs/20_data_schema_design.md`：运行时配置字段、枚举和数据引用关系。新增或改动 JSON、Resource、配置字段前先读。

### 技术与实现

- `docs/30_technical_architecture.md`：Godot 技术路线、目录结构、系统边界和长期技术原则。做架构性修改时先读。
- `docs/31_program_design_phase1.md`：第一阶段 3v3 战斗切片的程序实现范围。做原型功能取舍时以它为边界。
- `docs/32_domain_design_phase1.md`：Domain 层对象、状态所有权、命令、事件和系统协作。改战斗规则代码、模拟、测试时先读。
- `docs/33_implementation_map.md`：当前代码位置速查。开始改代码时用它快速定位入口、数据、HUD、海面、测试和资产接口。

### 美术与资产

- `docs/40_art_direction_design.md`：整体美术方向、角色资产契约、舰装节点、动画和交付要求。做角色资产或角色表现时先读。
- `docs/41_character_art_design.md`：角色原型、阵营、舰种、性格、战斗定位、核心美术方向和 MVP 资产重点。生成或调整角色美术时必须对齐。
- `docs/42_combat_art_design.md`：武器、投射物、发射过程、命中反馈和公共战斗特效。做炮弹、鱼雷、航空、防空、反潜和范围提示时参考。
- `docs/43_scene_art_design.md`：海面、镜头、环境、地图边界、场景承载和安全区。改海域环境、镜头或战场背景时先读。
- `docs/44_ui_art_design.md`：战斗 HUD、通用 UI 组件、叠层、弹窗、图标、适配和资产规格。改 UI 视觉或 HUD 资产时先读。
- `docs/45_art_asset_interface_design.md`：程序和美术资产之间的稳定语义接口。改运行时资产查找、资源目录、绑定点或 AssetCatalog 时必须对齐。
- `docs/46_art_pipeline_design.md`：角色美术后处理、透明拆件、配置生成和 QA 流程。改 `tools/art_pipeline/` 或角色 processed 资产时先读。
- `docs/47_scene_art_implementation_research.md`：场景美术实现方案调研。做海面 shader、程序纹理、AI 风格锚点或渲染兼容性判断时参考。
- `docs/48_scene_art_mvp_implementation.md`：当前场景美术 MVP 已实现内容。改现有海面、镜头、海况切换和场景范围时先确认这里。

### 审计与历史

- `docs/90_design_audit_round4.md`：第四轮设计复核结论。处理历史争议、优先级或设计债务时参考，但不要把它当作最新运行时真源。
- `docs/91_character_phase2_historical_validation.md`：第二期角色的独立历史考据。核对实舰、方案状态、主要武装和舰种映射争议时参考。
- `docs/92_character_phase2_balance_validation.md`：第二期角色的独立纸面数值审查。评估 Cost、舰种生态、技能预算和动态验证计划时参考。

## Codex 工作指引

### 开始任何任务

- 先检查 `git status --short`，保护用户已有改动，不回滚无关文件。
- 根据任务类型阅读上面对应文档；如果涉及代码落点，再读 `docs/33_implementation_map.md`。
- 用 `rg` 或 `rg --files` 查找引用和调用点，避免只改一处留下旧路径、旧字段或旧规则。
- 只改和任务直接相关的文件。设计文档、数据、代码、美术资产不要顺手大范围重构。

### 设计改动

- 改核心规则时，同时检查玩法、公式、数据结构、Domain 和操作文档是否需要同步。
- 改数值时区分三层：`13_balance_baseline` 是范围，`14_character_balance_design` 是角色草案，`data/` 是当前可运行配置。
- 改美术职责时保持边界：角色表现归 `40/41`，公共战斗特效归 `42`，海面环境归 `43/47/48`，UI 归 `44`。
- 审计报告只记录历史判断；如它与编号较低的主设计文档冲突，优先更新主设计文档，并在审计相关处说明状态。

### 程序改动

- Godot 运行时代码按现有目录分层：`scripts/domain` 放规则，`scripts/application` 放流程协调，`scripts/presentation` 放场景和 UI，`scripts/infrastructure` 放数据、资产和外部支持。
- Domain 层不要依赖 Godot 场景树、HUD 节点或具体贴图路径。
- 表现层不要重新实现命中、伤害、装填、侦查等规则；这些规则应来自 Domain 或配置。
- 资产路径优先通过 `DataRegistry.assets` 或 `scripts/infrastructure/assets/asset_catalog.gd` 的语义查询，不在表现代码里手拼文件名。
- 新增配置字段时，同步更新 `docs/20_data_schema_design.md`、加载校验和相关测试。

### 美术资产与管线

- 角色运行时资产真源在 `assets/characters/{character_id}/processed/`，原始 sheet 和 QA 产物不要混作运行时入口。
- UI 运行时语义清单参考 `assets/ui/qa/ui_asset_manifest.json`，导出倍率目录位于 `assets/ui/export/`。
- 改角色后处理或资产验收时，优先复用 `tools/art_pipeline/` 中现有脚本。
- 不为每个角色重复制作公共炮弹、鱼雷、命中、水柱、范围圈等资产；优先使用公共类别资产加角色覆盖层。

### 验证

- 文档重命名或字段重命名后，用 `rg` 检查旧名称是否残留。
- 程序改动后，优先运行项目已有测试或最小可行的 Godot/脚本校验。
- 资产或 UI 改动后，检查对应 QA 报告、manifest 或运行时引用是否仍然能找到文件。
- 如果暂时无法运行测试，在最终回复中明确说明原因和剩余风险。
