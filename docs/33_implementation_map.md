# 当前程序实现速查

本文档用于后续修改时快速定位代码位置。它不是设计文档，只记录“现在程序怎么分层、改什么先看哪里”。

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

## 数据与配置

- 配置加载与校验：`scripts/infrastructure/data/config_registry.gd`
- 全局数据入口：`autoload/data_registry.gd`
  - `DataRegistry.registry`：读取战斗配置。
  - `DataRegistry.assets`：读取美术资产索引。
- 关卡配置：`data/levels/prototype_levels.json`
  - 新增 1v1、3v3、更多战斗模式时优先改这里。
  - `map.ocean_palette` 控制海面调色板，可引用 5 种气候 x 4 个时间段的组合海域。
- 舰船配置：`data/ships/prototype_ships.json`、`data/ships/expanded_roster_ships.json`
  - 角色基础属性、武器挂载、技能、主要武器组、弹种组、`asset_root`。
  - `base_speed/base_turn_speed/base_detection_range/base_concealment_distance` 保存设计基线；运行字段分别按 0.5 或 1.5 倍写入。
- 武器配置：`data/weapons/prototype_weapons.json`、`data/weapons/expanded_roster_weapons.json`
  - 自动武器与 `ManualPrimary` 主要武器。
  - HE/AP 共享冷却依赖相同 `weapon_group_id`。
  - `base_range` 保存设计基线，`range` 保存当前 1.5 倍有效射程；领域与 UI 均直接读取 `range`。
  - `base_projectile_speed` 保存炮弹、鱼雷、舰载机等攻击速度设计基线，`projectile_speed` 保存当前 0.5 倍运行速度。
- 技能配置：`data/skills/prototype_skills.json`、`data/skills/expanded_roster_skills.json`
  - `base_cast_range` 保存设计基线，`cast_range` 保存当前 1.5 倍有效释放距离。
- 扩展角色武器/技能生成入口：`tools/data/build_expanded_roster_data.mjs`
- 投射物配置：`data/projectiles/projectiles.json`
  - `base_speed` 保存公共投射物 / 舰载机移动速度设计基线，`speed` 保存当前 0.5 倍运行速度。
- 公式配置：`data/formulas/combat_formulas.json`
- 海面调色板：`data/environments/ocean_palettes.json`
  - 当前包含 20 套气候/时间组合，以及 `day_clear`、`cloudy`、`dusk` 三个兼容入口。
- 表现设置：`data/settings/presentation_settings.json`
  - `window`：固定逻辑画布、主界面可选窗口尺寸与默认尺寸。
  - `camera`：默认缩放、滚轮步长、最近观察范围和最远地图占比。

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
  - 手动主要武器：`_fire_primary_weapon`
  - 弹药切换：`_switch_ammo`
  - 技能释放：`_cast_skill`
  - 投射物与延迟攻击：`_spawn_projectile`、`_update_projectiles`、`_resolve_delayed_attacks`
  - 命中与伤害：`_resolve_attack`、`_resolve_area_attack`
  - 胜负结算：`_check_victory`、`_check_timeout`、`_finish_battle`
- 纯计算服务：
  - 伤害：`scripts/domain/services/damage_service.gd`
  - 修正值顺序：`scripts/domain/services/modifier_service.gd`
- 战斗统计：`scripts/infrastructure/analytics/battle_recorder.gd`
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
  - 红/绿/白战术范围叠层：`_draw_directional_aim_overlay`、`_draw_area_target_overlay`、`_draw_skill_target_overlay`、`_draw_annular_sector`
  - HUD 数据推送：`_update_hud`
- 战斗表现导演：`scripts/presentation/battle/battle_effect_director.gd`
  - 角色、投射物、VFX 同步：`sync_snapshot`、`consume_events`
  - 命中跳字：`_spawn_damage_number`、`_damage_number_entry`
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
  - 战斗图层：`battle/*_battle_body_r.png`、`battle/*_battle_rig_base.png`
  - 头像：`ui/*_ui_portrait.png`、`ui/*_ui_portrait_small.png`
  - 横向封面：`ui/*_illust_skill_cutin_alpha.png`
  - 纵向结算立绘：`ui/*_illust_full_alpha.png`
- UI 图标：`assets/ui/export/2x/`
- UI 语义清单：`assets/ui/qa/ui_asset_manifest.json`
- 海面 Shader：`assets/environments/ocean/common/ocean_surface.gdshader`
- 海面贴图：`assets/environments/ocean/common/ocean_*_tile.png`

## 测试与调试

- 核心规则测试：`scripts/tests/test_runner.gd`
- 场景与展示测试：`scripts/tests/scene_presentation_test.gd`
- 批量模拟：`scripts/tests/batch_simulation.gd`
- 截图 QA：`scripts/tests/render_scene_qa.gd`
- 常用命令：
  - 启动检查：`godot --headless --path . --quit-after 2`
  - 核心测试：`godot --headless --path . --script res://scripts/tests/test_runner.gd`
  - 展示测试：`godot --headless --path . --script res://scripts/tests/scene_presentation_test.gd`
  - 格式检查：`git diff --check`

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
- 调整海面颜色、气候、时间、雨雾或闪电强度：改 `data/environments/ocean_palettes.json`。
- 调整海面算法和天气层合成：改 `assets/environments/ocean/common/ocean_surface.gdshader`。

## 分层约定

- `data/` 保存数值与关卡配置。
- `scripts/application/` 保存战斗会话、流程状态等应用层逻辑。
- `scripts/domain/` 保存不依赖场景的纯计算服务。
- `scripts/infrastructure/` 保存配置、资产、随机数、统计等基础设施。
- `scripts/presentation/` 保存场景、输入、绘制和 UI。
- UI 与场景不直接修改领域规则；玩家操作应转换为命令交给 `BattleSession`。
