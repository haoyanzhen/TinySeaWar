# 设计文档整体结构再规划

> **功能与边界**：本文提出文档目录、职责、拆分、命名、导航和迁移顺序的整体方案。规划日期：2026-10-12；状态：已按用户指令实施搬迁、改名与拆分。当前有效路径以[README](README.md)与[AGENTS](../AGENTS.md)为准，功能完成度只见[00](00_project_status.md)。本文不定义玩法、数据字段或工程实现任务。

## 1. 结构决策

采用“按职责分目录、编号作为稳定标识、按任务提供阅读路线”的结构。保留已有编号，不进行全量重编号。根目录保留README、00状态、01本规划和34实现位置四个入口；专题进入对应目录。

本方案在上一轮[职责审计](history/95_design_document_boundary_audit_20261012.md)之上处理文件组织。上一轮已收敛正文边界，但目录仍有以下问题：

- 19是模拟平台技术契约，却排在玩法序列；36是实验方法，却混在技术设计中。
- 40–47同时承载视觉标准、资产接口和生产管线；50–52也混合声音标准与制作流程。
- 32/33文件名使用phase1/phase2，正文已经是长期核心Domain与表现架构，容易误导新任务。
- 15同时承载公共关卡规则、教学内容和三种规模挑战，局部调整容易牵动公共契约。
- 91/92是历史考据与纸面快照，放在根目录容易进入现行阅读路线。
- AGENTS、README和34都含导航，但未充分区分“任务约束”“设计检索”“代码定位”，阅读时需要重复搜索。

不以减少文件数为目标。规则、字段、状态所有权、表现标准、生产流程和验收方法具有不同修改原因，应保持独立。

## 2. 目标目录与所有权

以下目录结构已落地；本文件保留结构决策与旧名映射，执行证据见[重组记录](history/96_documentation_restructure_20261012.md)：

```text
docs/
  README.md                         设计检索、任务阅读路线和完整文件目录
  00_project_status.md              当前状态、证据与优先级
  01_documentation_structure_plan.md 本轮规划与迁移约束
  34_implementation_map.md           当前代码、数据、工具、测试位置
  gameplay/                         规则、操作、公式、平衡、角色、关卡、AI、体验、环境效果
  contracts/                        数据形状、加载约束及资产语义接口
  architecture/                     状态所有权、服务协作、表现架构和模拟平台架构
  presentation/                     角色、战斗、场景、UI、音乐和音效标准
  production/                       美术、音乐、音效的生成、后处理、交付与评审
  technical/                        跨系统工程方案；保留现有tNN路径
  validation/                       实验与验收方法、授权和结论生命周期
  history/                          旧状态、旧阶段、考据、审计与实施记录
```

目录按主要职责分类，不要求设计依赖只能从上到下单向阅读。例如架构需要引用规则，生产需要引用视觉标准，规则的验收又需要引用验证方法。引用不会转移所有权。

| 位置 | 回答的问题 | 禁止成为第二份真源的内容 |
|---|---|---|
| 00 | 现在完成了什么、有何证据、下一步是什么 | 完整规则、Schema、技术方案 |
| gameplay | 玩家和AI可以做什么、结果怎么算、内容如何设计 | 字段表、代码位置、实施日志 |
| contracts | 输入如何表达、类型与默认是什么、何时拒绝加载 | 玩法依据、推进流程、听感/画面标准 |
| architecture | 谁拥有状态、谁改变状态、怎样协作和终止 | 精确美术参数、逐关表、历史通过数 |
| presentation | 玩家应看见/听见什么、如何辨认 | 规则计算、命令推进、制作台账 |
| production | 如何可复现地制作、复核和交付资产 | 游戏结算、当前完成度、运行时隐藏事实 |
| technical | 一项跨系统问题如何工程化解决 | 替代上游规则/架构、堆叠长期测试历史 |
| validation | 如何提问、取样、比较、判定及限制结论 | 平台实现、角色目标值、具体当前验收状态 |
| history | 当时发生了什么、为什么这样决定 | 当前待办和最新规则 |

contracts中的20仍只索引数据契约20–26；45保持独立的资产语义接口，不强行转换为数据Schema。34保持代码位置唯一真源；production可保留操作所必需的命令和交付规范，工具参数细节仍由工具README负责。

## 3. 全量文件去向

本表覆盖原45份编号文档。左列保留迁移前文件名（原根目录文档的旧路径为docs/加该文件名，technical保持原目录），链接现行正文；右列是已落地路径。旧文件没有保留可编辑副本。

| [00_project_status.md](00_project_status.md) | `docs/00_project_status.md` | 保留根目录入口 |
| [10_game_core_mechanics.md](gameplay/10_game_core_mechanics.md) | `docs/gameplay/10_game_core_mechanics.md` | 移入职责目录，保留完整契约 |
| [11_game_operation_design.md](gameplay/11_game_operation_design.md) | `docs/gameplay/11_game_operation_design.md` | 移入职责目录，保留完整契约 |
| [12_combat_formula_design.md](gameplay/12_combat_formula_design.md) | `docs/gameplay/12_combat_formula_design.md` | 移入职责目录，保留完整契约 |
| [13_balance_baseline.md](gameplay/13_balance_baseline.md) | `docs/gameplay/13_balance_baseline.md` | 移入职责目录，保留完整契约 |
| [14_character_balance_design.md](gameplay/14_character_balance_design.md) | `docs/gameplay/14_character_balance_design.md` | 移入职责目录，保留完整契约 |
| [15-1_custom_battle_roster_design.md](gameplay/15-1_custom_battle_roster_design.md) | `docs/gameplay/15-1_custom_battle_roster_design.md` | 移入职责目录，保留完整契约 |
| [15-2_special_operations_design.md](gameplay/15-2_special_operations_design.md) | `docs/gameplay/15-2_special_operations_design.md` | 移入职责目录，保留完整契约 |
| [15_battle_level_design.md](gameplay/15_battle_level_design.md) | `docs/gameplay/15_battle_level_design.md` | 保留公共关卡规则，逐关内容分出15-3/15-4 |
| [16_enemy_ai_behavior_design.md](gameplay/16_enemy_ai_behavior_design.md) | `docs/gameplay/16_enemy_ai_behavior_design.md` | 移入职责目录，保留完整契约 |
| [17_play_design.md](gameplay/17_play_design.md) | `docs/gameplay/17_play_design.md` | 移入职责目录，保留完整契约 |
| [18_facility_weather_effect_design.md](gameplay/18_facility_weather_effect_design.md) | `docs/gameplay/18_facility_weather_effect_design.md` | 移入职责目录，保留完整契约 |
| [19_battle_simulator_design.md](architecture/19_battle_simulator_design.md) | `docs/architecture/19_battle_simulator_design.md` | 移入职责目录，保留完整契约 |
| [20_data_schema_design.md](contracts/20_data_schema_design.md) | `docs/contracts/20_data_schema_design.md` | 移入职责目录，保留完整契约 |
| [21_combat_data_schema.md](contracts/21_combat_data_schema.md) | `docs/contracts/21_combat_data_schema.md` | 移入职责目录，保留完整契约 |
| [22_scene_environment_data_schema.md](contracts/22_scene_environment_data_schema.md) | `docs/contracts/22_scene_environment_data_schema.md` | 移入职责目录，保留完整契约 |
| [23_level_progress_data_schema.md](contracts/23_level_progress_data_schema.md) | `docs/contracts/23_level_progress_data_schema.md` | 移入职责目录，保留完整契约 |
| [24_ai_data_schema.md](contracts/24_ai_data_schema.md) | `docs/contracts/24_ai_data_schema.md` | 移入职责目录，保留完整契约 |
| [25_presentation_data_schema.md](contracts/25_presentation_data_schema.md) | `docs/contracts/25_presentation_data_schema.md` | 移入职责目录，保留完整契约 |
| [26_simulation_data_schema.md](contracts/26_simulation_data_schema.md) | `docs/contracts/26_simulation_data_schema.md` | 移入职责目录，保留完整契约 |
| [30_technical_architecture.md](architecture/30_technical_architecture.md) | `docs/architecture/30_technical_architecture.md` | 移入职责目录，保留完整契约 |
| [32_domain_design_phase1.md](architecture/32_combat_domain_design.md) | `docs/architecture/32_combat_domain_design.md` | 移入架构，移除过时phase1命名 |
| [33_domain_design_phase2.md](architecture/33_battle_presentation_architecture.md) | `docs/architecture/33_battle_presentation_architecture.md` | 移入架构，移除过时phase2命名 |
| [34_implementation_map.md](34_implementation_map.md) | `docs/34_implementation_map.md` | 保留根目录入口 |
| [35_scene_combat_domain_design.md](architecture/35_scene_combat_domain_design.md) | `docs/architecture/35_scene_combat_domain_design.md` | 移入职责目录，保留完整契约 |
| [36_balance_testing_design.md](validation/36_balance_testing_design.md) | `docs/validation/36_balance_testing_design.md` | 实验方法独立归类，样本授权不变 |
| [37_environment_runtime_domain_design.md](architecture/37_environment_runtime_domain_design.md) | `docs/architecture/37_environment_runtime_domain_design.md` | 移入职责目录，保留完整契约 |
| [38_facility_combat_domain_design.md](architecture/38_facility_combat_domain_design.md) | `docs/architecture/38_facility_combat_domain_design.md` | 移入职责目录，保留完整契约 |
| [40_art_direction_design.md](presentation/40_art_direction_design.md) | `docs/presentation/40_art_direction_design.md` | 移入职责目录，保留完整契约 |
| [41_character_art_design.md](presentation/41_character_art_design.md) | `docs/presentation/41_character_art_design.md` | 移入职责目录，保留完整契约 |
| [42_combat_art_design.md](presentation/42_combat_art_design.md) | `docs/presentation/42_combat_art_design.md` | 移入职责目录，保留完整契约 |
| [43_scene_art_design.md](presentation/43_scene_art_design.md) | `docs/presentation/43_scene_art_design.md` | 移入职责目录，保留完整契约 |
| [44_ui_art_design.md](presentation/44_ui_art_design.md) | `docs/presentation/44_ui_art_design.md` | 移入职责目录，保留完整契约 |
| [45_art_asset_interface_design.md](contracts/45_art_asset_interface_design.md) | `docs/contracts/45_art_asset_interface_design.md` | 移入职责目录，保留完整契约 |
| [46_character_art_asset_pipeline.md](production/46_character_art_asset_pipeline.md) | `docs/production/46_character_art_asset_pipeline.md` | 移入职责目录，保留完整契约 |
| [47_scene_art_asset_pipeline.md](production/47_scene_art_asset_pipeline.md) | `docs/production/47_scene_art_asset_pipeline.md` | 移入职责目录，保留完整契约 |
| [50_music_playback_and_asset_design.md](presentation/50_music_playback_and_asset_design.md) | `docs/presentation/50_music_playback_and_asset_design.md` | 移入职责目录，保留完整契约 |
| [51_music_generation_and_review_pipeline.md](production/51_music_generation_and_review_pipeline.md) | `docs/production/51_music_generation_and_review_pipeline.md` | 移入职责目录，保留完整契约 |
| [52_sound_effect_design_and_production.md](presentation/52_sound_effect_design.md) | `docs/presentation/52_sound_effect_design.md` | 保留声音设计；制作交付迁新53 |
| [91_character_phase2_historical_validation.md](history/91_character_phase2_historical_validation.md) | `docs/history/91_character_phase2_historical_validation.md` | 移入历史路引，保留原日期与正文 |
| [92_character_phase2_static_balance_review.md](history/92_character_phase2_static_balance_review.md) | `docs/history/92_character_phase2_static_balance_review.md` | 移入历史路引，保留原日期与正文 |
| [t00_coastal_ai_performance_solution.md](technical/t00_coastal_ai_performance_solution.md) | `docs/technical/t00_coastal_ai_performance_solution.md` | 保留现有路径 |
| [t01_inertial_navigation_and_emergency_avoidance.md](technical/t01_inertial_navigation_and_emergency_avoidance.md) | `docs/technical/t01_inertial_navigation_and_emergency_avoidance.md` | 保留现有路径 |
| [t02_level_objective_reinforcement_progress_solution.md](technical/t02_level_objective_reinforcement_progress_solution.md) | `docs/technical/t02_level_objective_reinforcement_progress_solution.md` | 保留现有路径 |
| [t10_carrier_combat_presentation_solution.md](technical/t10_carrier_combat_presentation_solution.md) | `docs/technical/t10_carrier_combat_presentation_solution.md` | 保留现有路径 |

已新增的拆分文件：

| 目标路径 | 来源与职责 |
|---|---|
| `docs/gameplay/15-3_tutorial_level_design.md` | 15的教学关卡、教学步骤、逐关地图/出生/目标/奖励和教学专属内容验收 |
| `docs/gameplay/15-4_challenge_level_design.md` | 15的S/M/L逐关配方、任务、保护/取消、增援、奖励、目标胜率与挑战专属内容验收 |
| `docs/production/53_sound_effect_production_pipeline.md` | 52的候选生成、评审溯源、采用源包、后期和运行时派生交付 |

现有history文件与日期工单不重编号、不搬出各自历史位置；工单仍在workorder，报告仍在reports，模拟派生物仍在artifacts。文档重组不搬代码、数据、素材或实验产物。

## 4. 内容拆分与保留

### 4.1 关卡：15保留公共契约，逐关配方归分册

15保留模式定义、公共地图/部署约束、公共任务结算、通用进度/获取原则、共用验收边界，以及各分册入口。逐关内容只在分册维护。

| 当前15内容 | 唯一目标 | 拆分要求 |
|---|---|---|
| 第1–2节职责、模式与进度 | 15 | 公共规则保留，不写逐关步骤 |
| 第3.1–3.4公共地图结构/环境原则 | 15 | 地图通用约束保留 |
| 第3.5–3.8配方、出生、M/L约束与T/S地图 | 公共约束留15；教学行归15-3；S/M/L行归15-4 | 按表行/段落归属迁移，不能整节机械复制 |
| 第4节AI、时长与结算 | 公共语义留15；逐类目标随对应内容分册 | 样本/统计方法仍归36 |
| 第5节及教学专属动作 | 15-3 | 每关形成完整内容卡，保留教学正常操作与事实条件 |
| 第6–8节及挑战共用简报 | 15-4 | S/M/L保持同一文件，章内可比；不再拆成每关一个文件 |
| 第9节编成/获取 | 公共开放与获取原则留15；随机匹配只归15-1 | 奖励分配按关随分册；精确运行清单仍归data |
| 第10节内容验收 | 公共边界留15；教学/挑战特有要求归对应分册 | 工程实现顺序仍归t02 |
| 自定义环境变化与挑战时间线 | 自定义规则归15-1；挑战时间线归15-4 | 全局天气效果仍归18 |

15-1、15-2保持现有职责。15-2仅设计及人类反馈调平的边界原样保留。逐关卡片包含“意图→阵容/地图→目标与取消→增援/奖励→可执行选择→内容验收”，没有字段类型表、测试历史或当前完成标记。

### 4.2 音效：52保留设计，53负责生产

52保留声音语言、分类、复用、反馈语义、取消/静默范围，以及玩家感知层面的接受标准；53负责“怎样生产和交付”。

| 当前52内容 | 唯一目标 |
|---|---|
| 第1节声音语言，第2节分类和取消范围 | 52 |
| 第2节当前评审清单/素材包入口 | 53引用34；52不维护采用状态 |
| 第3节事实到声音的设计要求 | 52 |
| 第3节三候选、提示/种子、模型回执、评审绑定/返工流程 | 53 |
| 第4节采用源包与来源记录 | 53；公共资产路径规范仍由45拥有 |
| 第5节后期、哈希、格式与重建 | 53 |
| 第5–6节听感、循环、设备与重复疲劳标准 | 52；53引用标准并记录实际交付证据 |
| 第6节PCM16、声道、淡化、源/派生哈希 | 53；运行时字段与消费仍归25/33 |

源包格式与运行时manifest不能合并。53不得借搬迁恢复已取消声音、重新解释用户采用结果或重开W09。

### 4.3 其他文档保持完整

- 14保留角色设计总表，41保留角色视觉总表。48个角色共享同一设计比较口径，暂不建立48份角色Markdown；精确值仍由data维护。
- 16保留观察、单舰、编队、技能、难度和切换的完整决策链。潜艇段依赖公共决策与射击纪律，暂不拆独立文件；用目录与锚点改善检索。
- 19独立为模拟平台架构，26独立为实验数据契约，36独立为实验方法。三个文件相互引用，不合并成“模拟器大全”。
- 32、35、37、38保持聚合/子域边界；33保持表现生命周期，45保持资产语义接口。
- 46、47、51分别保留角色、场景和音乐生产流程，不能为了统一目录把不同输入、生成器和人工评审合并。
- t00/t01同属导航，但前者治理调度/预算，后者定义动力学航迹与恢复；保持独立。t02/t10继续负责跨系统工程适配。
- 不新增按“设计中/已完成/待验收”分类的目录；状态变化不会触发文件搬家。

## 5. 导航与阅读路线

AGENTS保留项目约束、工作规则和按任务选择权威源的短表；完整文档目录由README维护，代码路径由34维护。逐文件职责清单不在三处全量复制。各专题目录仅在需要解释边界时设短README，不再复制全仓库索引。

README的顺序改为“开始工作→按任务选读→按职责查文件→历史”，不要求每个任务从10一路读到52。

| 任务 | 最小阅读路线（稳定编号） |
|---|---|
| 新成员理解项目 | 00 → 17 → 10 → 30；需要实现时再读34 |
| 修改战斗规则 | 00 → 10/12 → 21 → 32；环境/设施再读18/22/35/37/38 |
| 角色数值与技能 | 00 → 13/14 → 21 → 12/32；AI适用时读16/24 |
| 教学/挑战内容 | 00 → 15 → 15-3或15-4 → 23 → t02；正式实验再读19/26/36 |
| 自定义或特别行动 | 00 → 15 → 15-1或15-2 → 23/24；按是否新增能力补架构 |
| AI/导航 | 00 → 16/24 → 32/35 → t00/t01 |
| 角色美术 | 00 → 40/41 → 45 → 46；接入再读25/33 |
| 场景美术 | 00 → 43 → 45/47；涉及几何读22/35，涉及玩法读18 |
| UI和战斗反馈 | 00 → 11/44 → 25/33；武器表现读42 |
| 音乐/音效制作 | 00 → 50或52 → 51或53 → 45；接入读25/33 |
| 平衡实验 | 00 → 受测规则与内容 → 36 → 26/19；位置查34 |
| 定位历史决定 | 00的证据链接 → history或工单，不反向恢复旧待办 |

迁移完成后，每份主文档开头包含职责、不负责事项和上游/下游链接。长期章节使用语义标题，不以“phase1/phase2”表示现行责任；阶段信息只在历史记录中出现。跨文档引用优先文件＋章节锚点，少用易漂移的“第3.7节”。

## 6. 命名与维护规则

1. 保留现有数字作为稳定文档ID；目录表达职责，文件编号不再暗示它必须处在某种层。19移入architecture、36移入validation仍保留编号。
2. 新文件先分配职责，再选择未占用编号；同主题分册继续使用15-N。完成这次迁移时同步修改README命名说明与审计skill的分类规则，避免工具把所有10–19机械认作玩法。
3. 全局专题名保持小写英文和下划线。仅32/33及52因职责名称变化改basename；其余搬迁保留basename。
4. 不同时保留两份可编辑正文，不长期保留旧路径占位副本。仓库内引用在迁移批次内全部修复；外部绝对路径无法自动修复时，在本规划的映射表记录对应关系。
5. 主设计变更采用所属专题；技术方案负责工程决策，工单负责本次执行，报告负责事实，00负责当前结论。不把规划变成永久实施日志。
6. 迁移结束后，本文件只保留结构约束和映射，已执行步骤与检查结果进入历史/00；不再维护第二份进度表。

## 7. 迁移批次与退出条件

| 批次 | 动作 | 退出条件 |
|---|---|---|
| A 导航与目录 | 创建职责目录；移动不拆分文件；32/33改名；91/92移history；保留technical四份路径 | 旧活动路径引用已清除，全部本地链接存在；AGENTS/README/34及受影响skill路引一致 |
| B 内容拆分 | 按第4节拆15与52，创建15-3/15-4/53，更新交叉引用 | 每段独特规则、每个关卡、奖励、取消项、生产不变量有唯一归宿；无双份真源或丢失内容 |
| C 索引与工具 | README增加任务选读，AGENTS缩成任务路由；inventory递归覆盖现行目录并排除history | 工具不漏分册、technical或嵌套专题；历史单独检查，不与活动文件重复计数 |
| D 总体验收 | 逐项核对映射、章节锚点、字面路径与原文迁移；记录最终目录和实际检查 | 全部接受范围可用，无断链、无误改规则/数值/ID、无历史待办复活 |

每个批次都包含引用和工具修复，不能等最后一批才恢复可用导航。纯搬迁不改规则、公式、数据默认、角色数值、关卡ID、取消条件、实验授权及用户验收决定。

迁移搜索范围包含AGENTS、docs、workorder、assets/data/tools的README、代码/测试中的文档路径、仓库内.agents技能，以及用户级TinySeaWar美术/音乐技能中实际引用的旧路径。仓库外技能修正只限本次文档路径适配，不改其工作授权。

验证最低要求：迁移清单无遗漏/重号/目的地冲突；活动Markdown本地链接及章节锚点有效；旧路径只存在明确历史引用和迁移映射；归档/搬迁载荷对比保留独特内容；inventory与git diff --check通过。没有修改运行时或数据时不运行战斗矩阵；若发现代码读取某文档路径，则按实际消费者补最小验证。

## 8. 实施结果入口

本规划已实施：39份搬迁（含32/33/52改名和91/92归档），15拆出15-3/15-4，52拆出生产53；八类职责目录、任务导航及相关技能/工具引用已同步。原45份文档的去向见第3节，章节迁移与内容覆盖、链接/锚点及工具验证的实际结果见[重组记录](history/96_documentation_restructure_20261012.md)，项目当前结论仍只见[00](00_project_status.md)。

第4–7节保留拆分依据和长期维护约束，不作为第二份执行进度表。未改变角色/关卡ID、数值、规则、数据或用户验收决定；既有工作区改动保留。
