# Tiny Sea War 文档入口

先读[00当前状态](00_project_status.md)，按任务选择设计真源；实现位置查[34](34_implementation_map.md)。[01结构与旧名映射](01_documentation_structure_plan.md)记录本次结构决策，实际迁移证据见[重组记录](history/96_documentation_restructure_20261012.md)。

## 开始工作

- 项目约束与工作规则见[AGENTS](../AGENTS.md)，本文维护完整设计目录。
- 目录表达职责，编号保留为稳定ID；19属于架构，36属于验证，45属于资产契约。
- 规则、字段、状态所有权、表现标准、生产流程、工程方案与验收方法分别维护。当前完成度只在00，精确运行值以data为准。
- 工单索引见[workorder状态清单](../workorder/00_workorder_status.md)；历史记录不作为当前待办。

## 按任务选读

| 任务 | 阅读路线（编号可在下方完整目录检索） |
|---|---|
| 理解项目 | 00 → 17 → 10 → 30；实现时读34 |
| 战斗规则/结算 | 00 → 10/12 → 21 → 32；环境与设施再读18/22/35/37/38 |
| 角色/武器/技能 | 00 → 13/14 → 21 → 12/32；AI影响读16/24 |
| 教学/挑战 | 00 → 15 → 15-3或15-4 → 23 → t02；正式实验再读19/26/36 |
| 自定义/特别行动 | 00 → 15 → 15-1或15-2 → 23/24；新增能力再读对应架构 |
| AI与导航 | 00 → 16/24 → 32/35 → t00/t01 |
| 角色美术 | 00 → 40/41 → 45 → 46；接入读25/33 |
| 场景美术 | 00 → 43 → 45/47；几何读22/35，玩法读18 |
| 操作与HUD | 00 → 11/44 → 25/33；武器表现读42 |
| 音乐/音效 | 00 → 50或52 → 51或53 → 45；接入读25/33 |
| 实验与平衡 | 00 → 受测专题 → 36 → 26/19；入口查34 |

## 按职责查文件

### 根目录入口

- [00 当前状态](00_project_status.md)
- [01 文档结构与迁移映射](01_documentation_structure_plan.md)
- [34 实现位置速查](34_implementation_map.md)

### 玩法与内容（gameplay）

- [10_game_core_mechanics：舰娘核心机制设定](gameplay/10_game_core_mechanics.md)
- [11_game_operation_design：战斗操作设计](gameplay/11_game_operation_design.md)
- [12_combat_formula_design：战斗公式设计](gameplay/12_combat_formula_design.md)
- [13_balance_baseline：初始平衡基线](gameplay/13_balance_baseline.md)
- [14_character_balance_design：角色数值设计](gameplay/14_character_balance_design.md)
- [15_battle_level_design：公共关卡规则与内容导航](gameplay/15_battle_level_design.md)
- [15-1_custom_battle_roster_design：自定义战斗：敌方阵容池与 Cost 区间抽取](gameplay/15-1_custom_battle_roster_design.md)
- [15-2_special_operations_design：特别行动：海军战术难题与关卡设计](gameplay/15-2_special_operations_design.md)
- [15-3_tutorial_level_design：教学关卡设计：T-01～T-08](gameplay/15-3_tutorial_level_design.md)
- [15-4_challenge_level_design：挑战关卡设计：S/M/L小型、中型与大型海战](gameplay/15-4_challenge_level_design.md)
- [16_enemy_ai_behavior_design：战斗 AI 行为、玩家辅助控制、量化与验证设计](gameplay/16_enemy_ai_behavior_design.md)
- [17_play_design：玩法趣味设计](gameplay/17_play_design.md)
- [18_facility_weather_effect_design：设施与天气效果策划](gameplay/18_facility_weather_effect_design.md)

### 数据与资产契约（contracts）

- [20_data_schema_design：数据契约索引与公共约定](contracts/20_data_schema_design.md)
- [21_combat_data_schema：战斗单位与结算数据契约](contracts/21_combat_data_schema.md)
- [22_scene_environment_data_schema：场景、环境与设施数据契约](contracts/22_scene_environment_data_schema.md)
- [23_level_progress_data_schema：关卡、目标与进度数据契约](contracts/23_level_progress_data_schema.md)
- [24_ai_data_schema：AI 配置数据契约](contracts/24_ai_data_schema.md)
- [25_presentation_data_schema：表现配置数据契约](contracts/25_presentation_data_schema.md)
- [26_simulation_data_schema：战斗模拟实验数据契约](contracts/26_simulation_data_schema.md)
- [45_art_asset_interface_design：程序-美术资产接口设计](contracts/45_art_asset_interface_design.md)

### 架构与Domain（architecture）

- [19_battle_simulator_design：战斗模拟器设计](architecture/19_battle_simulator_design.md)
- [30_technical_architecture：Tiny Sea War 技术架构](architecture/30_technical_architecture.md)
- [32_combat_domain_design：战斗核心 Domain 设计](architecture/32_combat_domain_design.md)
- [33_battle_presentation_architecture：战斗表现架构设计](architecture/33_battle_presentation_architecture.md)
- [35_scene_combat_domain_design：硬地形与场景空间 Domain 设计](architecture/35_scene_combat_domain_design.md)
- [37_environment_runtime_domain_design：环境运行时 Domain 设计](architecture/37_environment_runtime_domain_design.md)
- [38_facility_combat_domain_design：设施战斗 Domain 设计](architecture/38_facility_combat_domain_design.md)

### 视觉与声音标准（presentation）

- [40_art_direction_design：角色美术方向与通用资产契约](presentation/40_art_direction_design.md)
- [41_character_art_design：角色美术设计](presentation/41_character_art_design.md)
- [42_combat_art_design：战斗美术设计文档](presentation/42_combat_art_design.md)
- [43_scene_art_design：场景美术设计文档](presentation/43_scene_art_design.md)
- [44_ui_art_design：UI 美术设计文档](presentation/44_ui_art_design.md)
- [50_music_playback_and_asset_design：音乐播放策略与资产标准](presentation/50_music_playback_and_asset_design.md)
- [52_sound_effect_design：音效声音设计与听感标准](presentation/52_sound_effect_design.md)

### 资产生产与评审（production）

- [46_character_art_asset_pipeline：角色美术资产生产与验收管线](production/46_character_art_asset_pipeline.md)
- [47_scene_art_asset_pipeline：场景美术资产生产与验收管线](production/47_scene_art_asset_pipeline.md)
- [51_music_generation_and_review_pipeline：音乐生成与人工评审流程](production/51_music_generation_and_review_pipeline.md)
- [53_sound_effect_production_pipeline：音效素材生产与交付管线](production/53_sound_effect_production_pipeline.md)

### 跨系统技术方案（technical）

方案命名与边界见[technical/README](technical/README.md)。

- [t00_coastal_ai_performance_solution：有岸地图 AI 决策性能解决方案](technical/t00_coastal_ai_performance_solution.md)
- [t01_inertial_navigation_and_emergency_avoidance：航行走廊、短时动力学轨迹与紧急规避解决方案](technical/t01_inertial_navigation_and_emergency_avoidance.md)
- [t02_level_objective_reinforcement_progress_solution：关卡目标、接替增援与进度存档技术契约](technical/t02_level_objective_reinforcement_progress_solution.md)
- [t10_carrier_combat_presentation_solution：航母作战战斗画面实施方案](technical/t10_carrier_combat_presentation_solution.md)

### 实验与验证方法（validation）

- [36_balance_testing_design：平衡性测试设计](validation/36_balance_testing_design.md)

## 历史与证据

历史保留原日期、原始失败和限制；现行结论以00及对应主设计为准。工单仍在workorder，报告和实验产物不因文档重组搬迁。

- [00_project_status_through_20261010：项目状态历史记录（截至2026-10-10）](history/00_project_status_through_20261010.md)
- [31_program_design_phase1：第一阶段程序设计参考说明（历史存档）](history/31_program_design_phase1.md)
- [52_sound_effect_production_iterations：音效生产与评审历史](history/52_sound_effect_production_iterations.md)
- [90_design_audit_round4：独立设计审计报告（第四轮复核）](history/90_design_audit_round4.md)
- [91_character_phase2_historical_validation：第二期角色历史考据验证](history/91_character_phase2_historical_validation.md)
- [92_character_phase2_static_balance_review：第二期角色静态纸面数值审查](history/92_character_phase2_static_balance_review.md)
- [95_design_document_boundary_audit_20261012：全设计文档职责与冗余审计（2026-10-12）](history/95_design_document_boundary_audit_20261012.md)
- [96_documentation_restructure_20261012：文档重组实施与内容保全记录](history/96_documentation_restructure_20261012.md)
- [t00_coastal_ai_performance_iterations：有岸 AI 性能实施与测量历史](history/t00_coastal_ai_performance_iterations.md)
- [t10_carrier_presentation_iterations：航空方案设计审计与实施历史](history/t10_carrier_presentation_iterations.md)

## 命名与维护

文件使用小写英文、下划线和稳定编号：`NN_topic_kind.md`；同主题分册使用`NN-N_topic_kind.md`，跨系统方案沿用`tNN_topic_solution.md`。编号不决定目录所有权，也不因阶段结束重新分配；新文件先确认职责及可用编号，再加入本索引。

每份主文档开头说明职责、不负责事项及权威依赖。引用优先使用当前相对链接和语义章节锚点。迁移、改名或拆分时同时更新AGENTS、本文、34相关入口、工单、工具与技能消费者；不要保留两份可编辑正文或长期旧路径占位副本。资产总入口见[assets/README](../assets/README.md)，路径规范由contracts/45维护。
