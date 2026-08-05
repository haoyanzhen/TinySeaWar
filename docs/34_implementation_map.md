# 当前实现位置速查

> **功能与边界**：本文只回答“当前代码、数据、场景、工具和测试在哪里”。规则归 `10–19`，字段契约归 `20–26`，架构与 Domain 边界归 `30/32/33/35/37/38`，完成状态只见 `00_project_status.md`。路径变化时更新本文，不在此复制公式、数值或验收结论。

## 1. 启动与主流程

| 入口 | 当前文件 |
|---|---|
| 数据与资产总入口 | `scripts/infrastructure/bootstrap/data_registry.gd`（Autoload：`DataRegistry`） |
| 游戏流、菜单到战斗 | `scripts/application/game_flow.gd` |
| 单局战斗协调 | `scripts/application/battle_session.gd` |
| 自定义关卡运行定义 | `scripts/application/game_flow.gd` 持有，调用 `BattleSession.create_battle_from_definition()` |
| 主菜单场景与脚本 | `scenes/menu/main_menu.tscn`、`scripts/presentation/menu/main_menu.gd` |
| 战斗场景与协调脚本 | `scenes/battle/prototype_battle.tscn`、`scripts/presentation/battle/prototype_battle.gd` |

## 2. 配置加载与公共设置

| 职责 | 当前文件/目录 |
|---|---|
| 配置加载、索引、校验 | `scripts/infrastructure/data/config_registry.gd` |
| 资产语义解析 | `scripts/infrastructure/assets/asset_catalog.gd` |
| 战斗公共设置 | `data/settings/combat_settings.json` |
| 表现公共设置 | `data/settings/presentation_settings.json` |
| 公式配置 | `data/formulas/combat_formulas.json` |
| 数据目录说明 | `data/README.md` |

新增或改字段前先查 `docs/20_data_schema_design.md`，再进入对应的 `21–26` 子契约和加载校验。

## 3. 核心战斗数据

| 数据类别 | 当前文件/目录 |
|---|---|
| 舰船定义 | `data/ships/prototype_ships.json`、`expanded_roster_ships.json`、`phase2_ships.json` |
| 武器定义 | `data/weapons/prototype_weapons.json`、`expanded_roster_weapons.json`、`phase2_weapons.json` |
| 技能定义 | `data/skills/prototype_skills.json`、`expanded_roster_skills.json`、`phase2_skills.json` |
| 投射物定义 | `data/projectiles/projectiles.json` |
| AI Profile | `data/ai/ai_profiles.json` |

## 4. 关卡、目标与进度

| 职责 | 当前文件/目录 |
|---|---|
| 原型与海岸验证关卡 | `data/levels/prototype_levels.json` |
| S-01 至 S-05 正式挑战关 | `data/levels/formal_level_01.json` |
| T-02 至 T-04 正式关卡 | `data/levels/formal_tutorial_levels_02_04.json` |
| T-05 至 T-08 正式关卡 | `data/levels/formal_tutorial_levels_05_08.json` |
| 声明式目标定义 | `data/objectives/level_objectives.json` |
| T-05 至 T-08 三轮设计路线实验 | `data/simulations/experiments/level_t05_win_rate_20.json` 至 `level_t08_route_round3_20.json` |
| 目标运行时服务 | `scripts/domain/services/level_objective_service.gd` |
| 进度存档 | `scripts/infrastructure/persistence/progress_save_store.gd` |
| 目标运行时测试 | `scripts/tests/level_objective_runtime_test.gd` |
| 进度存档测试 | `scripts/tests/progress_save_store_test.gd` |

关卡、目标、进度或接替增援是否已形成运行闭环，只以 `docs/00_project_status.md` 为准。

## 5. 核心战斗服务

| 职责 | 当前文件 |
|---|---|
| 伤害与结算 | `scripts/domain/services/damage_service.gd` |
| 修正聚合 | `scripts/domain/services/modifier_service.gd` |
| 舰船运动 | `scripts/domain/services/ship_motion_service.gd` |
| 火炮散布 | `scripts/domain/services/gun_dispersion_service.gd` |
| 几何碰撞 | `scripts/domain/services/collision_geometry_service.gd` |
| 确定性随机源 | `scripts/infrastructure/random/seeded_random_source.gd` |
| 核心规则回归 | `scripts/tests/test_runner.gd` |
| 技能运行时测试 | `scripts/tests/skill_runtime_test.gd` |

侦查、武器调度、技能编排和部分状态协调目前仍由 `scripts/application/battle_session.gd` 承载。是否进一步拆服务属于架构变更，不在本文判定。

## 6. AI 与导航

| 职责 | 当前文件 |
|---|---|
| 阵营合法观察 | `scripts/application/ai/ai_observation.gd` |
| 量化决策模型 | `scripts/application/ai/ai_quantitative_model.gd` |
| 战略路线规划、不可接入目标的正向阶段投影与分类失败 | `scripts/application/navigation/route_planner.gd` |
| 路线请求预算 | `scripts/application/navigation/navigation_request_broker.gd` |
| 常规/紧急航迹候选 | `scripts/application/navigation/trajectory_planner.gd` |
| AI 观察测试 | `scripts/tests/ai_observation_test.gd` |
| AI 行为与难度测试 | `scripts/tests/ai_behavior_quantitative_test.gd`、`ai_difficulty_profile_test.gd` |
| 编组与协同测试 | `scripts/tests/ai_group_formation_test.gd`、`ai_coordination_test.gd` |
| 航迹、碰撞场与恢复测试 | `scripts/tests/trajectory_navigation_test.gd`、`navigation_collision_field_test.gd`、`ai_route_recovery_test.gd` |
| Tick 分阶段、导航/侦查性能、投影路线、失败/等待与大编队碰撞测试 | `scripts/tests/ai_navigation_performance_test.gd` |

## 7. 硬地形与场景空间

| 职责 | 当前文件/目录 |
|---|---|
| 地形运行定义 | `data/terrain/terrain_definitions.json` |
| 岸线距离/限制水域碰撞场 manifest 与二进制派生物 | `data/terrain/collision_field_manifest.json`、`data/terrain/collision_fields/` |
| 导航图定义 | `data/terrain/navigation_definitions.json` |
| 地形模板与作者输入 | `data/terrain/terrain_templates.json`、`data/terrain/authoring/terrain_maps.json` |
| 地形与射线查询 | `scripts/domain/services/terrain_query_service.gd` |
| 静态碰撞场查询与加载 | `scripts/domain/services/terrain_collision_field.gd`、`scripts/infrastructure/data/terrain_collision_field_loader.gd` |
| 地形上下文组合 | `scripts/domain/services/terrain_context_service.gd` |
| 地形场景视图 | `scripts/presentation/battle/terrain_view.gd` |
| 地形调试叠层 | `scripts/presentation/battle/terrain_debug_overlay.gd` |
| 构建与校验工具 | `tools/terrain/` |
| 碰撞场确定性烘焙与差分校验 | `tools/terrain/bake_collision_fields.py`、`tools/terrain/validate_collision_fields.py` |
| Godot 地形作者插件 | `addons/terrain_authoring/`（仅编辑器；使用与发布边界见目录内 `README.md`） |
| 16:9 海岸母版、透明化与接触表 | `tools/art_pipeline/process_coastal_map_art.py` |
| 16:9 海岸模板、地图与运行时绑定 | `tools/terrain/build_coastal_maps_16x9.py` |
| 16:9 海岸导航增量烘焙 | `tools/terrain/bake_coastal16_navigation.py` |
| 海岸运行时测试 | `scripts/tests/coastal_runtime_test.gd` |
| 碰撞场、同 Tick 展开与失效回退测试 | `scripts/tests/navigation_collision_field_test.gd` |
| 作者数据测试 | `scripts/tests/terrain_authoring_test.gd` |
| 海岸 5v5/11v11 映射负载 | `scripts/tests/ai_navigation_performance_test.gd --map-level=...` |

地形、环境、设施三类规则已分别由 `docs/35_scene_combat_domain_design.md`、`37_environment_runtime_domain_design.md`、`38_facility_combat_domain_design.md` 定义。

## 8. 环境运行时

| 职责 | 当前文件/目录 |
|---|---|
| 全局海战环境条件 | `data/environments/ocean_battle_condition_definitions.json` |
| 局部环境区 | `data/environments/environment_zone_definitions.json` |
| 海面调色板 | `data/environments/ocean_palettes.json` |
| 环境上下文服务 | `scripts/domain/services/terrain_context_service.gd` |
| 海面表现 | `scripts/presentation/battle/ocean_surface.gd` |
| 天气叠层 | `scripts/presentation/battle/weather_overlay.gd` |

## 9. 设施与水雷

| 职责 | 当前文件/目录 |
|---|---|
| 设施定义 | `data/facilities/facility_definitions.json` |
| 支援任务定义 | `data/facilities/support_mission_definitions.json` |
| 水雷定义 | `data/facilities/minefield_definitions.json` |
| 设施状态与任务 | `scripts/domain/services/facility_service.gd` |
| 水雷状态与触发 | `scripts/domain/services/minefield_service.gd` |
| 设施总契约测试 | `scripts/tests/facility_integration_contract_test.gd` |
| 生命周期测试 | `scripts/tests/facility_state_lifecycle_test.gd` |
| 岸炮 | `scripts/tests/coastal_battery_test.gd` |
| 观察站/雷达 | `scripts/tests/observation_post_test.gd`、`radar_station_test.gd` |
| 补给维修 | `scripts/tests/supply_point_test.gd`、`repair_berth_test.gd` |
| 通信/机场/水雷 | `scripts/tests/communication_station_test.gd`、`airfield_mission_test.gd`、`mine_control_station_test.gd` |
| AI 设施任务 | `scripts/tests/ai_facility_task_test.gd` |

## 10. 战斗表现与 HUD

| 职责 | 当前文件 |
|---|---|
| 单位视图 | `scripts/presentation/battle/ship_unit_view.gd` |
| 动画状态机 | `scripts/presentation/battle/animation_state_machine.gd` |
| 事件与效果编排 | `scripts/presentation/battle/battle_effect_director.gd` |
| 实体投射物视图 | `scripts/presentation/battle/projectile_view.gd` |
| 炮弹飞行表现 | `scripts/presentation/battle/shell_flight_view.gd` |
| 公共战斗 VFX | `scripts/presentation/battle/battle_vfx.gd` |
| 伤害数字 | `scripts/presentation/battle/damage_number_view.gd` |
| 战斗 HUD | `scripts/presentation/battle/battle_hud.gd` |
| UI 文本 | `scripts/presentation/ui_text.gd` |
| 场景表现测试 | `scripts/tests/scene_presentation_test.gd` |
| 场景 QA 渲染 | `scripts/tests/render_scene_qa.gd`；支持分辨率/镜头、F9、地图映射、多舰规模与固定 Tick |
| 运行时全地图比例视图 | `tools/scene_review/render_runtime_full_map_view.gd` |
| 16:9 海岸正式画面 QA | `assets/environment/qa/coastal_camera_resolution_matrix.png`、`coastal_f9_runtime_alignment.png`、`coastal_fleet_traffic_review.png`、`coastal_11v11_failure_review.png` |

表现配置位于 `data/visuals/`，包括武器、投射物、VFX 播放 Profile 和第二期映射。角色运行时资产位于 `assets/characters/{character_id}/processed/`；公共 VFX、环境和 UI 资产分别位于 `assets/vfx/`、`assets/environment|environments/` 与 `assets/ui/`。

## 11. 模拟、统计与报告

| 职责 | 当前文件/目录 |
|---|---|
| 实验清单 | `data/simulations/experiments/` |
| 实验加载 | `scripts/infrastructure/simulation/experiment_loader.gd` |
| 单次/批次运行协调 | `scripts/application/simulation/simulation_runner.gd` |
| 聚合统计 | `scripts/infrastructure/simulation/simulation_aggregator.gd` |
| 报告写出 | `scripts/infrastructure/simulation/simulation_report_writer.gd` |
| 战斗事实记录 | `scripts/infrastructure/analytics/battle_recorder.gd` |
| 伤害统计 | `scripts/infrastructure/analytics/damage_statistics.gd` |
| 命令行实验入口 | `tools/simulation/run_experiment.gd` |
| 平衡分析工具 | `tools/simulation/analyze_damage_ttk_balance.py`、`run_damage_ttk_balance.gd` |
| 模拟器测试 | `scripts/tests/battle_simulator_test.gd`、`batch_simulation.gd` |
| 单局冒烟 | `scripts/tests/battle_smoke_single_test.gd` |

实验产物写入 `artifacts/simulations/`，属于生成结果，不是配置真源。

## 12. 常见改动入口

| 要修改的内容 | 先读的设计真源 | 再定位的实现 |
|---|---|---|
| 核心规则/结算 | `10`、`12`、`32` | `battle_session.gd`、`scripts/domain/services/`、`test_runner.gd` |
| 操作与 HUD | `11`、`33`、`44` | `prototype_battle.gd`、`battle_hud.gd` |
| 角色/武器/技能 | `13`、`14`、`21` | `data/ships|weapons|skills/`、`config_registry.gd` |
| 关卡目标/进度 | `15`、`23`、`technical/t02` | `data/levels|objectives/`、`level_objective_service.gd`、`progress_save_store.gd` |
| AI 决策 | `16`、`24` | `scripts/application/ai/`、`data/ai/` |
| 导航与战斗 Tick 性能 | `technical/t00`、`technical/t01` | `battle_session.gd`、`scripts/application/navigation/`、`ship_motion_service.gd`、`ai_navigation_performance_test.gd` |
| 硬地形 | `35`、`22` | `data/terrain/`、`terrain_query_service.gd`、`tools/terrain/` |
| 天气/局部环境 | `18`、`37`、`22` | `data/environments/`、`terrain_context_service.gd` |
| 设施/水雷 | `18`、`38`、`22` | `data/facilities/`、`facility_service.gd`、`minefield_service.gd` |
| 表现资产 | `33`、`40–47`、`25` | `scripts/presentation/`、`data/visuals/`、`assets/` |
| 模拟实验 | `19`、`26`、`36` | `data/simulations/`、`scripts/*/simulation/`、`tools/simulation/` |

路径不存在或职责已移动时，应先修正本文，再更新引用；不要为了符合旧路引恢复过期目录。
