# 当前程序实现速查

本文档用于后续修改时快速定位代码位置。它不是设计文档，只记录“现在程序怎么分层、改什么先看哪里”。

项目阶段完成度、已知缺口和测试快照见 `docs/00_project_status.md`。

## 入口与场景

- Godot 项目入口：`project.godot`
  - 主场景：`scenes/menu/main_menu.tscn`
  - 自动加载：
    - `DataRegistry` -> `autoload/data_registry.gd`
    - `GameFlow` -> `scripts/application/game_flow.gd`
- 主界面：`scenes/menu/main_menu.tscn`
  - 脚本：`scripts/presentation/menu/main_menu.gd`
  - 负责模式选择、操作说明、游戏介绍、随机横向角色封面。
- 战斗场景：`scenes/battle/prototype_battle.tscn`
  - 主控制：`scripts/presentation/battle/prototype_battle.gd`
  - HUD：`scripts/presentation/battle/battle_hud.gd`
  - 海面：`scripts/presentation/battle/ocean_surface.gd`
- 独立天气层：`scripts/presentation/battle/weather_overlay.gd`
- 地形/浅水/设施表现：`scripts/presentation/battle/terrain_view.gd`
- 地形与 TerrainContext 调试：`scripts/presentation/battle/terrain_debug_overlay.gd`（运行时按 F9）

## 场景环境运行时契约

- `OceanSurface` 使用覆盖关卡地图范围的 `Node2D` 和 `canvas_item` Shader；海面纹理、噪声、波纹和天气采样以地图局部坐标为基础，镜头移动时不得变成屏幕贴片。
- `WeatherOverlay` 是独立 `Node2D`，位于海面之上、战斗单位与 HUD/战术叠层之下；天气环境光和遮罩不得改写单位、UI 或 Domain 状态。
- `OceanSurface` 与 `WeatherOverlay` 共用 `data/environments/ocean_palettes.json`。时间字段负责颜色、明度与反光，气候字段负责云影、风浪、白沫、雨雾、风暴、闪电和雪层强度；新增组合继续复用同一运行时结构。
- 同一个 `map.ocean_palette` 由 `TerrainContextService` 对照 `data/environments/ocean_battle_condition_definitions.json` 解析为全局天气和时段战斗条件。表现层与 Domain 共享 ID，不共享 Shader 参数。
- 两个环境节点的动画时间均由脚本累计并传入 Shader，不直接依赖 Shader `TIME`；战斗暂停时必须同时停止环境时间推进。
- 地图尺寸和默认海况来自关卡的 `map` 配置，禁止在表现层假定所有关卡尺寸相同；镜头边界按当前地图尺寸和逻辑视口动态计算。
- 项目继续使用 Compatibility 渲染器；修改海面或天气 Shader 后，至少运行场景展示测试，并用 `render_scene_qa.gd` 检查目标分辨率和代表性海况。

## 数据与配置

- 配置加载与校验：`scripts/infrastructure/data/config_registry.gd`
- 全局数据入口：`autoload/data_registry.gd`
  - `DataRegistry.registry`：读取战斗配置。
  - `DataRegistry.assets`：读取美术资产索引。
- 关卡配置：`data/levels/prototype_levels.json`
  - 新增 1v1、3v3、更多战斗模式时优先改这里。
  - `map.ocean_palette` 选择共享的海面/战斗环境条件，可引用 5 种气候 x 4 个时间段的组合海域。
- 舰船配置：`data/ships/prototype_ships.json`、`data/ships/expanded_roster_ships.json`、`data/ships/phase2_ships.json`
  - 角色基础属性、武器挂载、技能、主要武器组、弹种组、`asset_root`。
  - `base_speed/base_turn_speed/base_detection_range/base_concealment_distance` 保存设计基线；运行字段分别按 0.5 或 1.5 倍写入。
- 武器配置：`data/weapons/prototype_weapons.json`、`data/weapons/expanded_roster_weapons.json`、`data/weapons/phase2_weapons.json`
  - 自动武器与 `ManualPrimary` 主要武器。
  - HE/AP 共享冷却依赖相同 `weapon_group_id`。
  - `base_range` 保存设计基线，`range` 保存当前 1.5 倍有效射程；领域与 UI 均直接读取 `range`。
  - `base_projectile_speed` 保存炮弹、鱼雷、舰载机等攻击速度设计基线，`projectile_speed` 保存当前 0.5 倍运行速度。
  - 舰炮 `fire_arcs` 表示至少一座底座可射区，`full_salvo_fire_arcs` 表示全部底座齐射区。
- 技能配置：`data/skills/prototype_skills.json`、`data/skills/expanded_roster_skills.json`、`data/skills/phase2_skills.json`
  - `base_cast_range` 保存设计基线，`cast_range` 保存当前 1.5 倍有效释放距离。
- 扩展角色武器/技能生成入口：`tools/data/build_expanded_roster_data.mjs`
- 第二期角色数据生成入口：`tools/data/build_phase2_roster_data.py`
- 投射物配置：`data/projectiles/projectiles.json`
  - `base_speed` 保存公共投射物 / 舰载机移动速度设计基线，`speed` 保存当前 0.5 倍运行速度。
  - 鱼雷 `minimum_detection_distance` 保存直接运行的最小发现距离；阵营共享观测由 `BattleSession._update_projectile_observation` 维护。
- 公式配置：`data/formulas/combat_formulas.json`
- 海面调色板：`data/environments/ocean_palettes.json`
  - 当前包含 20 套气候/时间组合，以及 `day_clear`、`cloudy`、`dusk` 三个兼容入口。
  - 同一配置同时驱动海面 Shader 与独立 WeatherOverlay；雪粒/雪雾资源已正式挂载，当前基础 20 组合默认强度为 0。
- 海面战斗条件：`data/environments/ocean_battle_condition_definitions.json`
  - 5 个天气 Profile、4 个时段 Profile、统一海况档位和 3 个兼容 palette 别名。
  - `scripts/domain/services/terrain_context_service.gd` 负责与局部环境区组合；`battle_session.gd` 只把关卡 palette ID 传入，不从画面反推规则。
- 表现设置：`data/settings/presentation_settings.json`
  - `window`：固定逻辑画布、主界面可选窗口尺寸与默认尺寸。
  - `camera`：默认缩放、滚轮步长、最近观察范围和最远地图占比。
- 战斗表现配置：`data/visuals/`
  - `projectile_visuals.json`：投射物贴图、尺寸、轨迹与颜色。
  - `weapon_visuals.json`、`phase2_weapon_visuals.json`：角色武器组到动画、绑定点、投射物和 VFX 的映射。
  - `vfx_playback_profiles.json`：公共 VFX 的时长、缩放、淡入淡出和混合参数。

## 战斗核心

- 战斗会话主逻辑：`scripts/application/battle_session.gd`
  - 创建战斗：`create_battle`
  - 固定步进：`advance_tick`
  - 玩家命令入口：`queue_command`
  - 给 UI 的只读状态：`snapshot`
  - 玩家槽位：`get_player_slots`
  - 操作状态：`get_operation_status`
  - 主要武器瞄准校验：`get_primary_aim_status`
  - 多扇区射角：`_weapon_fire_arcs`、`_angle_in_weapon_fire_arcs`
- 常改位置：
  - 移动：`_update_movement`
  - 索敌与接触残影：`_update_detection`
  - AI 行为：`_update_ai_intents`
  - 自动技能：`_update_auto_skills`
  - 自动武器：`_update_weapons`
  - 自动火炮预判与固定落点：`_automatic_aim_solution`、`_positive_intercept_time`、`_salvo_impact_position`
  - 手动主要武器与逐座鱼雷选择：`_fire_primary_weapon`、`_validate_primary_fire`、`_weapon_for_state`
  - 弹药切换：`_switch_ammo`
  - 技能释放：`_cast_skill`
  - 投射物、鱼雷角误差、管组间隔、阵营观测与延迟攻击：`_torpedo_error_profile`、`_start_mount_launch_interval`、`_spawn_projectile`、`_update_projectiles`、`_update_projectile_observation`、`_visible_projectiles`、`_resolve_delayed_attacks`
  - 命中与伤害：`_resolve_attack`、`_resolve_area_attack`
  - 胜负结算：`_check_victory`、`_check_timeout`、`_finish_battle`
  - 场景战术结果：`_update_facility_weapons`、`_handle_facility_event`、`_resolve_support_mission`、`_apply_mine_trigger`、`_environment_accuracy_modifier`
  - 敌方环境意图：`_ai_facility_plan`、`_update_ai_support_intents`；设施、潮汐和雷区意图仍转换为普通命令并经过共享合法性校验。
- 纯计算服务：
  - 伤害：`scripts/domain/services/damage_service.gd`
  - 修正值顺序：`scripts/domain/services/modifier_service.gd`
  - 舰装椭圆、圆-椭圆和连续扫掠：`scripts/domain/services/collision_geometry_service.gd`
  - 海况/风速鱼雷 sigma 倍率：`scripts/domain/services/terrain_context_service.gd`
  - 固定种子均匀与高斯抽样：`scripts/infrastructure/random/seeded_random_source.gd`
- 战斗统计：`scripts/infrastructure/analytics/battle_recorder.gd`
  - 分类与聚合工具：`scripts/infrastructure/analytics/damage_statistics.gd`
  - `BattleSession.get_unit_damage_statistics`：取得单舰完整统计。
  - `BattleSession.get_all_unit_damage_statistics`：取得本局全部舰船统计，包含零伤害舰船。
  - `BattleSession.get_unit_damage_for_category`：直接查询主炮、副炮、鱼雷、航空、技能、Buff 等分类值。
- 随机数：`scripts/infrastructure/random/seeded_random_source.gd`

## 玩家输入与战斗展示

- 中文显示文本：`scripts/presentation/ui_text.gd`
  - 统一转换模式、阶段、镜头、操作、海域、舰种、目标类型、阵营、结算原因、拒绝原因和角色 ID。
  - Domain 与配置引用仍使用稳定英文枚举，不直接显示给玩家。
- 战斗输入、镜头、单位绘制：`scripts/presentation/battle/prototype_battle.gd`
  - 数字键选槽位：`_slot_for_key`、`_select_slot`
  - 鼠标选择/集火/移动：`_unhandled_input`、`_select_at`
  - E 主要武器瞄准：`_begin_primary_aim`、`_confirm_primary_aim`
  - Q 弹药切换：`_switch_selected_ammo`
  - F 技能：`_begin_or_cast_skill`、`_confirm_skill_target`
  - V 跟随镜头：`_toggle_follow_selected`
  - WASD 镜头：`_update_camera`
  - 滚轮缩放与边界：`_adjust_camera_zoom`、`_configure_camera_zoom`、`_clamp_camera_to_map`
  - 战场角色图层：`_draw_unit`、`_draw_unit_art`
  - 瞄准叠层：`_draw_operation_overlay`
  - 红/绿/深绿/白主炮射界：`_draw_gun_aim_overlay`、`_draw_fire_arc_sectors`
  - 红/绿/白方向与战术范围叠层：`_draw_directional_aim_overlay`、`_draw_area_target_overlay`、`_draw_skill_target_overlay`、`_draw_annular_sector`
  - HUD 数据推送：`_update_hud`
- 战斗表现导演：`scripts/presentation/battle/battle_effect_director.gd`
  - 角色、投射物、VFX 同步：`sync_snapshot`、`consume_events`
  - 命中跳字：`_spawn_damage_number`、`_damage_number_entry`
  - 大口径未命中水柱：`_spawn_large_gun_water_column`；小/中口径未命中不生成水柱。
- 角色战场视图：`scripts/presentation/battle/ship_unit_view.gd`
  - 角色本体、舰装、状态图标、血条、动画和绑定点。
- 角色动画状态机：`scripts/presentation/battle/animation_state_machine.gd`
- 公共表现节点：
  - 投射物：`scripts/presentation/battle/projectile_view.gd`
  - 炮弹飞行与轨迹：`scripts/presentation/battle/shell_flight_view.gd`
  - VFX：`scripts/presentation/battle/battle_vfx.gd`
- 伤害跳字节点：`scripts/presentation/battle/damage_number_view.gd`
  - 运行时字体绘制、描边、动效、0.25 秒合并和每目标最多 3 组。
- HUD：`scripts/presentation/battle/battle_hud.gd`
  - 顶部状态：`_draw_top_status`
  - 敌我头像栏：`_draw_fleet_panel`、`_draw_roster_cell`
  - 操作槽：`_draw_operation_dock`
  - 小地图：`_draw_minimap`
  - 战斗日志：`_draw_log_panel`
  - 选中单位面板：`_draw_selected_panel`
  - 暂停面板：`_draw_pause_panel`
  - 结算画面：`_draw_result_panel`
  - 返回主界面/再玩一次按钮：`return_to_menu_requested`、`restart_requested`

## 主界面与流程

- 流程状态：`scripts/application/game_flow.gd`
  - `selected_level_id` 记录主界面选择的关卡。
  - `window_size_options`、`apply_window_size` 负责读取、应用并持久化窗口尺寸。
  - `_configure_content_scaling` 固定逻辑画布并启用等比界面缩放。
- 主界面：`scripts/presentation/menu/main_menu.gd`
  - 按钮创建：`_create_buttons`
  - 开始战斗：`_start_level`
  - 模式说明：`_show_mode_select`
  - 操作说明：`_show_operation_guide`
  - 游戏介绍：`_show_game_intro`
  - 界面设置：`_create_settings_panel`、`_show_settings`、`_apply_selected_window_size`
  - 随机横向封面：`_random_character_id`、`_draw_cover_art`

## 美术资产

- 资产接口：`scripts/infrastructure/assets/asset_catalog.gd`
  - 设计说明：`docs/45_art_asset_interface_design.md`
  - 推荐新代码优先通过 `DataRegistry.assets` 查资源。
- 角色资源：`assets/characters/{character_id}/processed/`
  - 生产与验收流程：`docs/46_character_art_asset_pipeline.md`
  - 批量处理与契约检查：`tools/art_pipeline/`
  - 战斗图层：`battle/*_battle_body_r.png`、`battle/*_battle_rig_base.png`
  - 头像：`ui/*_ui_portrait.png`、`ui/*_ui_portrait_small.png`
  - 横向封面：`ui/*_illust_skill_cutin_alpha.png`
  - 纵向结算立绘：`ui/*_illust_full_alpha.png`
- UI 图标：`assets/ui/export/2x/`
- UI 语义清单：`assets/ui/qa/ui_asset_manifest.json`
- 海面 Shader：`assets/environments/ocean/common/ocean_surface.gdshader`
- 海面贴图：`assets/environments/ocean/common/ocean_*_tile.png`
- 天气层 Shader：`assets/environment/weather/weather_overlay.gdshader`
- 天气母版：`assets/environment/weather/ocean_weather_*_master.png`
- 陆地母版：`assets/environment/land/land_*.png`
- 陆地资产清单：`assets/environment/land/land_asset_manifest.json`
- 陆地碰撞候选边缘：`assets/environment/land/land_collision_manifest.json`
- 审核地形模板/世界几何：`data/terrain/terrain_templates.json`、`data/terrain/terrain_definitions.json`
- 共享导航：`data/terrain/navigation_definitions.json`、`scripts/application/navigation/route_planner.gd`
- 纯地形查询/环境上下文/设施/水雷状态：`scripts/domain/services/terrain_query_service.gd`、`terrain_context_service.gd`、`facility_service.gd`、`minefield_service.gd`
  - `TerrainContextService`：固定 Tick 天气与潮汐、最终海况规则档、机动/命中/航空上下文、潮滩进入与撤离校验。
  - `FacilityService`：观察源、岸炮状态、交互、服务事务、机场队列、依赖、HP、压制/恢复/摧毁。
  - `MinefieldService`：连续雷区进入、安全航道、单舰触发、阵营知识、控制站状态和 AI 已知雷区绕行点。
- 近岸/设施/局部环境资产清单：`assets/environment/terrain/terrain_asset_manifest.json`、`assets/environment/facilities/facility_asset_manifest.json`、`assets/environment/weather/zones/environment_zone_asset_manifest.json`
- 地形制作插件：`addons/terrain_authoring/`；可在 Template/Map 模式从正式 JSON 加载并回写硬地形、浅水、航道、纯视觉层、环境区、设施挂点/依赖、雷区与安全航道，并在警告未清除时阻止保存。
- 地形生产与 QA：`tools/terrain/`；`build_scene_combat_pipeline.py` 会在临时目录完成地形/导航烘焙与全量校验，通过后才事务式发布正式 JSON，再生成小地图和 QA；编辑往返入口为 `build_authoring_snapshot.py` / `apply_authoring_snapshot.py`。

## 测试与调试

- 核心规则测试：`scripts/tests/test_runner.gd`
- AI 量化模型：`scripts/application/ai/ai_quantitative_model.gd`
- AI 量化场景测试：`scripts/tests/ai_behavior_quantitative_test.gd`
- 场景与展示测试：`scripts/tests/scene_presentation_test.gd`
- 第二期配置与资产映射测试：`scripts/tests/phase2_config_test.gd`
- 地形制作插件测试：`scripts/tests/terrain_authoring_test.gd`
- 批量模拟：`scripts/tests/batch_simulation.gd`
- 战斗模拟器：
  - 实验运行：`scripts/application/simulation/simulation_runner.gd`
  - 清单加载：`scripts/infrastructure/simulation/experiment_loader.gd`
  - 聚合与报告：`scripts/infrastructure/simulation/simulation_aggregator.gd`、`simulation_report_writer.gd`
  - 逐舰分类伤害：`scripts/infrastructure/analytics/damage_statistics.gd`；模拟器通过 `BattleSession.get_all_unit_damage_statistics()` 读取，不另算伤害。
  - 命令入口：`tools/simulation/run_experiment.gd`
  - 示例实验：`data/simulations/experiments/smoke_single_battle.json`
  - 独立测试：`scripts/tests/battle_simulator_test.gd`
  - 伤害统计测试：`scripts/tests/damage_statistics_test.gd`
- 截图 QA：`scripts/tests/render_scene_qa.gd`
- 常用命令：
  - 启动检查：`godot --headless --path . --quit-after 2`
  - 核心测试：`godot --headless --path . --script res://scripts/tests/test_runner.gd`
  - AI 量化测试：`godot --headless --path . --script res://scripts/tests/ai_behavior_quantitative_test.gd`
  - 展示测试：`godot --headless --path . --script res://scripts/tests/scene_presentation_test.gd`
  - 第二期配置测试：`godot --headless --path . --script res://scripts/tests/phase2_config_test.gd`
  - 战斗模拟器测试：`godot --headless --path . --script res://scripts/tests/battle_simulator_test.gd`
  - 运行示例模拟：`godot --headless --path . --script res://tools/simulation/run_experiment.gd -- res://data/simulations/experiments/smoke_single_battle.json`
  - 格式检查：`git diff --check`
  - 地形配置校验：`python3 tools/terrain/validate_terrain_definition.py`
  - 地形生产门禁：`python3 tools/terrain/validate_scene_combat_pipeline.py`
  - 地形制作插件：`godot --headless --path . --script res://scripts/tests/terrain_authoring_test.gd`

## 常见修改入口

- 新增角色：按所属批次修改 `data/ships/prototype_ships.json` 或 `data/ships/expanded_roster_ships.json`，再确认 `assets/characters/{id}/processed/` 资产完整。
- 新增武器或调整手动主武器：修改对应批次武器 JSON；扩展角色优先改生成入口并重新生成，必要时再改 `battle_session.gd` 的 `_fire_primary_weapon`、`_validate_primary_fire`。
- 调整伤害：优先改 `data/formulas/combat_formulas.json` 和 `damage_service.gd`。
- 调整 HE/AP：看舰船的 `ammo_selection_group_id`，武器的 `weapon_group_id`、`ammo_type`。
- 调整胜利条件：改 `battle_session.gd` 的 `_check_victory`、`_check_timeout`。
- 新增关卡/模式：改 `data/levels/prototype_levels.json`，主界面按钮改 `main_menu.gd`。
- 调整键鼠操作：改 `prototype_battle.gd` 的 `_unhandled_input` 和相关 `_begin/_confirm` 函数。
- 调整 HUD 布局：改 `battle_hud.gd`。
- 调整结算画面：改 `battle_hud.gd` 的 `_draw_result_panel` 和 `_draw_result_character`。
- 调整主界面文案/按钮：改 `main_menu.gd`。
- 调整海面颜色、气候、时间、雨雾、闪电或雪层强度：改 `data/environments/ocean_palettes.json`。
- 调整海面算法：改 `assets/environments/ocean/common/ocean_surface.gdshader`。
- 调整独立天气层合成：改 `assets/environment/weather/weather_overlay.gdshader`。
- 调整陆地/岛屿视觉资产：改 `assets/environment/land/` 下透明 PNG 和 `land_asset_manifest.json`。
- 调整陆地碰撞候选边缘：重新运行 `tools/art_pipeline/process_land_art.py`，并人工复核 `land_collision_manifest.json` 后再接入关卡。
- 调整投射物、武器动画/VFX 映射：改 `data/visuals/`，并同步 `asset_catalog.gd`、配置校验和第二期配置测试。
- 音效、音乐和语音当前没有运行时入口；建立音频方案前不要在表现脚本中零散硬编码音频路径。

## 分层约定

- `data/` 保存数值与关卡配置。
- `scripts/application/` 保存战斗会话、流程状态等应用层逻辑。
- `scripts/domain/` 保存不依赖场景的纯计算服务。
- `scripts/infrastructure/` 保存配置、资产、随机数、统计等基础设施。
- `scripts/presentation/` 保存场景、输入、绘制和 UI。
- UI 与场景不直接修改领域规则；玩家操作应转换为命令交给 `BattleSession`。
