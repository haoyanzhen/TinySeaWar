# 程序-美术资产接口设计

## 目标

程序侧不直接拼接角色、UI、动画、VFX 和绑定点文件名，而是通过稳定语义查询资源。美术侧继续使用现有目录和后处理工具输出，不额外复制一套资产真源。

## 资产真源

- 角色运行时资产仍位于 `assets/characters/{character_id}/processed/`。
- 角色装配配置仍位于 `assets/characters/{character_id}/processed/config/`。
- UI 语义清单仍位于 `assets/ui/qa/ui_asset_manifest.json`。
- `data/` 仍只保存战斗数值和关卡配置，不保存美术裁切、绑定点或资源派生信息。

## 运行时接口

统一入口为 `scripts/infrastructure/assets/asset_catalog.gd`，并通过 `DataRegistry.assets` 在运行时访问。

推荐调用方式：

```gdscript
var idle := DataRegistry.assets.animation_state("bismarck", "idle")
var wake := DataRegistry.assets.vfx_role("bismarck", "wake")
var rig_path := DataRegistry.assets.battle_asset_path("bismarck", "rig_base")
var torpedo_icon := DataRegistry.assets.ui_asset_path("ui.icon.torpedo", "2x")
var shell_visual := DataRegistry.assets.projectile_visual("shell.large")
var main_gun_visual := DataRegistry.assets.weapon_visual("bismarck", "main_gun")
var muzzle_profile := DataRegistry.assets.vfx_playback_profile("muzzle_flash.large")
```

角色接口：

- `animation_state(character_id, state_name)` 返回四帧动画、FPS 和循环标记。
- `vfx_role(character_id, role_name)` 返回角色 VFX 语义资源。
- `bind_points(character_id, asset_name)` 返回指定战斗部件的绑定点。
- `battle_asset_path(character_id, semantic_name)` 返回战斗部件路径，例如 `rig_base`。

通用战斗表现接口：

- `projectile_visual(projectile_key)` 返回公共弹体、拖尾和运动表现资源，例如 `shell.small`、`shell.medium`、`shell.large`、`torpedo.surface`、`torpedo.submerged`、`aircraft.bomb`。
- `weapon_visual(character_id, weapon_key)` 返回角色武器到公共表现的映射，例如主炮使用哪个炮弹档位、哪个炮口 profile、哪个命中 profile。
- `vfx_playback_profile(profile_key)` 返回 VFX 播放参数，例如 `duration`、`fps`、`loop`、`anchor`、`z_layer`、`rotation_mode`、`scale`、`follow_owner`、`blend_mode`。
- 角色目录中的专属 VFX role 可以覆盖公共 profile 的贴图或颜色，但仍需要声明其公共语义，例如 `bismarck.heavy_muzzle -> muzzle_flash.large`。

建议配置入口：

- `data/visuals/projectile_visuals.json`
- `data/visuals/weapon_visuals.json`
- `data/visuals/vfx_playback_profiles.json`

绑定点标准语义：

- 炮口使用 `muzzle_01`、`muzzle_02`、`muzzle_group`。
- 鱼雷口使用 `torpedo_port_01`、`torpedo_port_02`；旧配置中的单点 `torpedo_port` 读取时应能映射为 `torpedo_port_01`。
- 航迹使用 `wake_origin`。
- 航母使用 `aircraft_launch_01`、`aircraft_launch_02`、`aircraft_recovery`。
- 侦查、技能和扫描使用 `scan_origin`、`skill_origin`。
- 舰装挂点使用 `rig_mount`。

UI 接口：

- `ui_asset_path(asset_key, scale)` 返回 UI 资源路径。
- `asset_key` 支持原始名称，例如 `ui_icon_torpedo`。
- `asset_key` 也支持语义名称，例如 `ui.icon.torpedo`、`ui.marker.target`、`ui.panel.minimap_open_sea`。
- `scale` 可用 `processed`、`1x`、`2x`、`4x`。

## 约束

- 新程序代码应优先使用 `AssetCatalog`，不要直接写死角色或 UI 的完整 PNG 路径。
- 环境底图、Shader 引用等少量稳定资源可以继续固定路径，必要时再迁入接口层。
- 美术后处理工具继续负责产出 `anim_config`、`vfx_config`、`meta_bind_points` 和 UI manifest。
- 若资源缺失或 JSON 无法解析，`AssetCatalog.load_all()` 会记录错误，启动时通过 `DataRegistry` 报告。
