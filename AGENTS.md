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

### 当前状态

- `docs/00_project_status.md`：当前完成度、已知缺口、验证结果和下一阶段优先级的唯一状态真源。判断某项能力是否已完成时先读；不要仅凭存在代码、配置或资产就标记完成。

### 玩法与数值

- `docs/10_game_core_mechanics.md`：玩法骨架和已确定核心战斗机制。改胜负条件、舰种资源、侦查隐蔽、旗舰、潜航、技能等规则时先读。
- `docs/11_game_operation_design.md`：玩家输入、选中、主要武器、弹药切换、技能和镜头跟随规则。改交互、快捷键、瞄准或反馈时先读。
- `docs/12_combat_formula_design.md`：侦查、命中、伤害、护甲、状态、资源等计算顺序。改公式或战斗结算时必须对齐。
- `docs/13_balance_baseline.md`：MVP 首轮调参范围和节奏目标。改基础范围、战斗时长、资源消耗、舰种基线时参考。
- `docs/14_character_balance_design.md`：角色级初始数值、武器、技能和玩法变体。改角色配置、技能数值、角色定位时参考。
- `docs/15_battle_level_design.md`：自定义战斗、闯关章节、编成、地图预设、解锁和验收草案。改战斗模式、关卡结构或进度设计时先读。
- `docs/16_enemy_ai_behavior_design.md`：敌方 AI 的舰队战术、单舰模式、量化决策、技能使用、边界和岛屿处理方案。改 AI 行为或难度时先读。

### 数据契约

- `docs/20_data_schema_design.md`：运行时配置字段、枚举和数据引用关系。新增或改动 JSON、Resource、配置字段前先读。

### 技术与实现

- `docs/30_technical_architecture.md`：Godot 技术路线、目录结构、系统边界和长期技术原则。做架构性修改时先读。
- `docs/31_program_design_phase1.md`：第一阶段 3v3 战斗切片的程序实现范围。做原型功能取舍时以它为边界。
- `docs/32_domain_design_phase1.md`：Domain 层对象、状态所有权、命令、事件和系统协作。改战斗规则代码、模拟、测试时先读。
- `docs/33_domain_design_phase2.md`：第二阶段角色动画、战斗单位视图、投射物、VFX、绑定点和 HUD 接入边界。改战斗表现架构时先读。
- `docs/34_implementation_map.md`：当前代码位置速查。开始改代码时用它快速定位入口、数据、HUD、海面、测试和资产接口。

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
- `docs/93_character_phase2_art_asset_audit.md`：第二期角色美术资产验收、阻塞项和设计债记录。判断第二期 processed 资产是否合格时参考。
- `docs/94_art_asset_usage_audit.md`：运行画面、资产索引和未使用素材的历史盘点；阅读顶部状态更新，旧数量不一定代表当前状态。
- `docs/95_art_asset_next_stage_assessment.md`：角色动画、绑定点、VFX、弹体和航空表现的阶段缺口评估。规划下一轮美术接入时参考。

## 当前项目完成状态

详细状态以 `docs/00_project_status.md` 为准。当前摘要：

- **战斗设计已完成**：战斗方式、战场设置、数值设定、伤害计算等均已完成。
- **可运行战斗切片已完成**：主菜单、四个开阔海域模式、第一期 24 名角色关卡覆盖、核心战斗、玩家操作、HUD、结算、海面天气和自动测试均已有实现。
- **角色设计第二期部分完成**：24 名角色的数据、武器、技能和表现映射已加载，但未进入现有关卡；仅 4 名完成 processed 资产，其余 20 名仍待生产。
- **美术部分完成**：角色美术、战斗美术、UI美术、环境美术等资产接口已建立；航空、防空、反潜、正式岛屿地图和完整 UI 换肤仍需继续。
- **玩法策划未完成**：已有核心规则、关卡和 AI 设计基础，但自定义编成、闯关、AI 分层、奖励解锁、舰种生态与动态平衡尚未统一定稿和实机验收。
- **音效与音乐未完成**：当前没有正式音频设计、运行时音频资产、总线或播放代码，任何音频类别都不得标记为已完成。

## 代码、数据与资产路引

- `autoload/data_registry.gd`：运行时数据与资产总入口。
- `data/ships|weapons|skills/`：第一期与第二期角色规则配置；`data/levels/` 目前只有第一期角色关卡。
- `data/visuals/`：投射物表现、武器表现和 VFX 播放参数。
- `scripts/application/battle_session.gd`：战斗流程和当前大部分规则协调。
- `scripts/presentation/battle/ship_unit_view.gd`：角色战场视图；`animation_state_machine.gd` 管理角色动画状态。
- `scripts/presentation/battle/battle_effect_director.gd`：消费战斗事件并协调角色、投射物、炮弹轨迹、VFX 和伤害跳字。
- `scripts/presentation/battle/projectile_view.gd`、`shell_flight_view.gd`、`battle_vfx.gd`：公共战斗表现节点。
- `assets/characters/{character_id}/processed/`：已完成角色运行时资产；只有 `postprocess_plan.json` 不代表资产完成。
- `assets/vfx/`：公共战斗与角色模板特效；`assets/environment/`、`assets/environments/`：陆地、天气和海面资源。
- `tools/data/`：角色批次配置生成；`tools/art_pipeline/`：角色、UI、场景和陆地资产处理与验收。
- 当前不存在正式 `assets/audio/`；新增音频前必须先补音频设计、语义事件和总线约定。

## Codex 工作指引

### 开始任何任务

- 先检查 `git status --short`，保护用户已有改动，不回滚无关文件。
- 先读 `docs/00_project_status.md`，确认本次任务是在补缺口、扩展部分完成项，还是维护已完成基线。
- 根据任务类型阅读上面对应文档；如果涉及代码落点，再读 `docs/34_implementation_map.md`。
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
- 更新阶段完成度时，必须同时记录数据加载、运行时接入、关卡覆盖、资产覆盖和自动/人工验收，不以单一维度代替整体完成度。
