# 当前美术资产使用审计

统计时间：2026-06-19。
口径说明：

- “运行画面使用”指当前主界面、战斗场景、HUD、结算画面会实际加载/绘制的贴图或 Shader。
- “资产索引使用”指 `AssetCatalog` 会扫描、记录路径或配置，但当前画面不一定渲染。
- `.import`、`.uid`、`.DS_Store`、`.gdignore` 不计入美术资产使用判断。

## 运行画面正在使用

### 角色

当前数据配置中的舰船为：

- `warspite`
- `bismarck`
- `aurora`
- `hindenburg`
- `shimakaze`
- `hai_shih`

这些角色在运行画面使用以下资源规则：

- 战场单位：
  - `assets/characters/{id}/processed/battle/{id}_battle_body_r.png`
  - `assets/characters/{id}/processed/battle/{id}_battle_rig_base.png`
- HUD 头像：
  - `assets/characters/{id}/processed/ui/{id}_ui_portrait_small.png`
  - 若小头像缺失，回退到 `{id}_ui_portrait.png`
- 主界面横向封面：
  - `assets/characters/{id}/processed/ui/{id}_illust_skill_cutin_alpha.png`
  - 主界面从当前舰船定义中随机选择。
- 结算纵向立绘：
  - `assets/characters/{id}/processed/ui/{id}_illust_full_alpha.png`
  - 当前关卡己方角色为 `warspite`、`aurora`、`shimakaze`，所以现有结算中只会随机出现这三名角色。

当前两个关卡实际会出场的角色：

- 己方：`warspite`、`aurora`、`shimakaze`
- 敌方：`bismarck`、`hindenburg`、`hai_shih`

### UI 图标与标记

当前运行代码使用 `assets/ui/export/2x/` 下列资源：

- 操作与状态：
  - `ui_icon_pause`
  - `ui_icon_continue`
  - `ui_icon_confirm`
  - `ui_icon_gunfire`
  - `ui_icon_skill_ready`
  - `ui_icon_camera_follow`
  - `ui_icon_flagship`
  - `ui_icon_unknown_contact`
- 舰种图标：
  - `ui_icon_class_battleship`
  - `ui_icon_class_heavy_cruiser`
  - `ui_icon_class_light_cruiser`
  - `ui_icon_class_destroyer`
  - `ui_icon_class_submarine`
  - `ui_icon_class_carrier`
- 战场标记：
  - `ui_marker_selected`
  - `ui_marker_target`
  - `ui_marker_flagship`
- 小地图：
  - `ui_minimap_camera_frame`
  - `ui_minimap_surface_player`
  - `ui_minimap_surface_enemy`
  - `ui_minimap_submarine_player`
  - `ui_minimap_submarine_enemy`
- 战斗日志：
  - `ui_log_contact_enemy`
  - `ui_log_last_contact`

合计：当前 `export/2x` 的 65 个 PNG 中，运行代码直接使用 24 个。

### 海面与环境

当前运行画面使用：

- `assets/environments/ocean/common/ocean_surface.gdshader`
- `assets/environments/ocean/common/ocean_base_day_clear_tile.png`
- `assets/environments/ocean/common/ocean_base_cloudy_tile.png`
- `assets/environments/ocean/common/ocean_base_dusk_tile.png`
- `assets/environments/ocean/common/ocean_cloud_shadow_tile.png`
- `assets/environments/ocean/common/ocean_wave_highlight_tile.png`

海面调色板由 `data/environments/ocean_palettes.json` 控制。

## 被资产索引扫描，但当前不直接渲染

`scripts/infrastructure/assets/asset_catalog.gd` 会扫描：

- `assets/characters/{id}/processed/battle/`
- `assets/characters/{id}/processed/ui/`
- `assets/characters/{id}/processed/anim/`
- `assets/characters/{id}/processed/vfx/`
- `assets/characters/{id}/processed/config/`
- `assets/ui/qa/ui_asset_manifest.json`

这意味着很多资源“可查询”，但当前画面还没有实际使用，例如：

- 角色动画帧：`processed/anim/*`
- 角色 VFX：`processed/vfx/*`
- 角色绑定点配置：`processed/config/*_meta_bind_points.json`
- UI 语义清单中的大量面板、按钮、状态条、结果装饰

测试中会验证少量 AssetCatalog 能力，例如 `bismarck` 的动画、VFX、绑定点和 `ui.icon.torpedo` 查询，但这不代表这些资源已经在战斗画面渲染。

## 当前未使用或仅作为素材留存

### 未进入数据配置的角色

- `enterprise_cv6`

该角色有完整处理后资源，但没有出现在 `data/ships/prototype_ships.json`，因此当前主界面随机封面、战斗出场、HUD、结算都不会使用它。

### 角色包中未渲染的资源类型

对已配置的 6 名角色而言，当前画面未使用或暂未接入：

- `processed/anim/*`：待机、移动、攻击、受击等帧动画。
- `processed/vfx/*`：炮焰、航迹、技能、命中特效等。
- `processed/battle/*_turret_*`、节点部件、舰装细节点等。
- `processed/ui/*_expr_*`：表情差分。
- `processed/ui/*_ui_skill_*`：角色技能图标。
- `processed/ui/*_ui_chibi_head.png`：Q 版头像。
- `processed/ui/*_ui_class_*.png`：角色包内舰种图标；当前 HUD 使用的是通用 UI 舰种图标。
- `processed/ui/*_illust_half_alpha.png`：半身立绘。
- `processed/source_alpha/*`：源 alpha 资产。
- `concept/`、`battle/`、`ui/`、`vfx/` 下的原始 sheet 与概念图。

### 未直接使用的 UI export/2x 图标

当前 `assets/ui/export/2x/` 中未被运行代码直接引用的资源包括：

- `ui_badge_flagship_critical`
- `ui_badge_unknown_status`
- `ui_icon_airstrike`
- `ui_icon_antiair`
- `ui_icon_antisubmarine`
- `ui_icon_auto_move`
- `ui_icon_auto_skill`
- `ui_icon_auto_weapon`
- `ui_icon_cancel`
- `ui_icon_collapse`
- `ui_icon_cooldown`
- `ui_icon_detection`
- `ui_icon_exit`
- `ui_icon_expand`
- `ui_icon_health`
- `ui_icon_hit`
- `ui_icon_lost_vision`
- `ui_icon_oxygen`
- `ui_icon_restart`
- `ui_icon_selected`
- `ui_icon_submerged`
- `ui_icon_sunk`
- `ui_icon_surfaced`
- `ui_icon_target_lock`
- `ui_icon_torpedo`
- `ui_icon_warning`
- `ui_log_aircraft_wave`
- `ui_log_contact_friendly`
- `ui_marker_danger_area`
- `ui_marker_destination`
- `ui_marker_heading`
- `ui_marker_offscreen_danger`
- `ui_marker_offscreen_enemy`
- `ui_marker_offscreen_player`
- `ui_marker_path_endpoint`
- `ui_marker_skill_area`
- `ui_minimap_aircraft_enemy`
- `ui_minimap_aircraft_player`
- `ui_ring_cooldown_empty`
- `ui_ring_cooldown_half`
- `ui_ring_skill_ready`

### UI processed/raw/qa 大部分尚未渲染

当前 HUD 多数面板、按钮、血条仍是程序绘制矩形和文字，没有直接使用：

- `assets/ui/processed/battle/fleet/*`
- `assets/ui/processed/battle/hud/*`
- `assets/ui/processed/battle/results/*`
- `assets/ui/processed/common/buttons/*`
- `assets/ui/processed/common/bars/*`
- `assets/ui/raw/*`
- `assets/ui/qa/*` 中的 QA 接触图、提示文档等

## 结论

当前程序已经接入了：

- 6 名已配置舰船的基础战斗图层、头像、横向封面、纵向结算立绘。
- 24 个通用 UI export/2x 图标和标记。
- 海面 Shader 与 5 张海面贴图。

当前尚未接入的主要资产价值在：

- 角色动画与 VFX。
- 角色炮塔/节点细分图层。
- 技能图标、表情、Q 版头像、半身立绘。
- 大量 UI 面板、按钮状态、结果装饰、血条和冷却环。
- `enterprise_cv6` 整个角色包。
