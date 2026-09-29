# 程序-美术资产接口设计

> **功能与边界**：本文是程序通过稳定语义查询角色、UI、公共战斗 VFX 和环境资产的接口真源，负责 `AssetCatalog` 入口、manifest、绑定点语义、回退与禁止硬编码规则。视觉目标见 `40-44`，表现字段见 `docs/25_presentation_data_schema.md`，生产与 QA 见 `docs/46_character_art_asset_pipeline.md`、`docs/47_scene_art_asset_pipeline.md`。本文不维护具体表现数值、战斗规则、当前资产完成度或表现节点算法。

## 目标

程序侧不直接拼接角色、UI、动画、VFX 和绑定点文件名，而是通过稳定语义查询资源。美术侧继续使用现有目录和后处理工具输出，不额外复制一套资产真源。

## 资产真源

- 角色运行时资产仍位于 `assets/characters/{character_id}/processed/`。
- 角色装配配置仍位于 `assets/characters/{character_id}/processed/config/`。
- UI 语义清单仍位于 `assets/ui/qa/ui_asset_manifest.json`。
- `data/visuals/` 保存投射物表现、武器表现映射和 VFX 播放参数；角色裁切、绑定点和资源派生信息仍只保存在 processed 配置与资产 manifest 中。

## 统一物理路径规范

本节是全项目美术路径的统一约束；`46/47` 维护生产细节，`34` 维护代码位置，`assets/README.md` 仅作入口。目录表中的 `{id}` 使用角色配置 ID 去掉 `ship.` 后的标识，不能使用显示名。

| 资产职责 | 正式位置与规则 |
|---|---|
| 角色源母版 | `assets/characters/{id}/{concept,ui,battle,vfx}/`；来源、裁切规格和生成记录位于 `meta/`，角色生产计划位于角色根目录 |
| 角色运行时 | `assets/characters/{id}/processed/{ui,battle,anim,vfx}/`；配置在 `processed/config/`；`processed/source_alpha/` 是可复现的处理源，不是战斗入口 |
| 角色 QA | `assets/characters/qa/`；保留交付报告、审查证据和总览；临时预览放系统临时目录或 `reports/` |
| UI | `assets/ui/raw/` 保存生产源母版，`processed/{common,battle,menu}/` 保存成品，`processed/source_alpha/` 保存处理源，`export/{1x,2x,4x}/` 保存倍率导出，`layout/` 保存布局契约 |
| 小地图 | `assets/ui/processed/battle/terrain/`；按该目录 `terrain_minimap_manifest.json` 中的地图 ID 查询，不从地图 ID 推测 PNG 文件名 |
| 海面 | `assets/environments/ocean/common/` 保存复用贴图，`concept/` 保存概念母版与说明 |
| 场景环境 | `assets/environment/{weather,land,terrain,facilities}/`；局部天气在 `weather/zones/`；陆地来源在 `land/source/` |
| 环境 QA | `assets/environment/qa/` 仅保留文档或 manifest 引用的最终证据；`land/generated/` 仅可作被 Git 忽略的临时工作区 |
| 公共 VFX | `assets/vfx/combat/{projectiles,trails,wakes,muzzle,impacts,aircraft,antiair,antisubmarine,skills,warnings,environment}/`；子目录按资源类型细分，角色共享模板位于 `character_templates/{ship_class}/` |
| VFX 来源与 QA | `assets/vfx/combat/source/` 保存可复现源，`qa/` 保存公共 manifest 与交付证据 |

命名和引用约束：

- 新增目录、资产和配置使用小写 ASCII 字母、数字及下划线，扩展名小写；角色文件以 `{id}_` 开头，角色配置与源图后缀见 `46`。公共 VFX 使用 `vfx_`、`projectile_` 或 `aircraft_` 前缀并表达用途；UI 使用 `ui_`，小地图使用 `minimap_`。已登记的旧名称保持兼容，禁止只为改名复制资源。
- `README.md`、Godot `.gdignore`、自动生成的 `.import` 为明确例外；QA 日期前缀、批次标识中的连字符、已验收源母版原名允许保留。新增类别或例外必须先登记到本节和对应管线。
- 仓库内资产 manifest/生产配置允许仓库相对 `assets/...`；Godot 运行时统一使用 `res://assets/...`，由 `AssetCatalog` 归一化。`data/visuals` 的贴图字段继续遵循 `25` 的 `res://` 契约。不得把 `../`、机器绝对路径或 `user://` 用作正式美术资源入口。
- 来源追溯记录中的生成器原始绝对路径允许作为历史元数据保留，但不能作为运行依赖；可复现所需的接受源母版仍须入库。文档 Markdown 链接可以使用相对路径。
- 原始母版、透明处理源、运行时成品和 QA 各归其位。临时候选、缓存、单次截图及导出放系统临时目录或被忽略的 `reports/`，不可因文件名含 `raw` 就把合法源母版当临时文件删除。
- `environment/` 与 `environments/ocean/` 是保留的明确兼容边界；UI/VFX manifest 保留在各自 `qa/` 中，属于运行时依赖，不可按临时 QA 清理。未来迁移必须同步 manifest、工具、接口和全部引用。
- 表现层只提交语义名、角色 ID 或地图 ID，不手拼角色/UI/VFX PNG 路径。资产目录扫描、固定命名适配和路径归一化集中在 Infrastructure 或生产工具中。
- 固定路径例外限于现有 `ocean_surface.gd`、`weather_overlay.gd` 的共享海面/全局天气贴图，以及稳定 Shader/场景资源引用；局部环境、设施、小地图、角色和 UI 不借用此例外。

路径变更时必须检查：目录职责、manifest 唯一键、引用存在性、语义查询和资源缺失降级，并同步 `34` 与生产工具。路径检查通过不代表像素质量或实机演出验收通过。

## 运行时查询接口

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
var water_column := DataRegistry.assets.combat_vfx_asset_path("impact.water.large")
```

角色接口：

- `animation_state(character_id, state_name)` 返回四帧动画、FPS 和循环标记。
- `vfx_role(character_id, role_name)` 返回角色 VFX 语义资源。
- 全部 VFX role 均引用存在的 `assets/vfx/combat/` 公共资源时允许省略角色本地 `processed/vfx/`；空 role 或缺失公共资源不满足该例外。
- `bind_points(character_id, asset_name)` 返回指定战斗部件的绑定点。
- `heading_offset_degrees(character_id, asset_name)` 返回该战斗部件相对“舰艏向右”零角度的纯表现校正；缺省为 `0`，只允许校正贴图母版方向，不得改变 Domain 航向或碰撞椭圆。
- `battle_asset_path(character_id, semantic_name)` 返回战斗部件路径，例如 `rig_base`。
- `character_ui_asset_path(character_id, semantic_name)` 返回角色 UI 路径；语义为文件名去掉角色前缀与扩展名，例如 `ui_portrait_small`、`ui_portrait`、`illust_full_alpha`。未知角色或语义返回空字符串；HUD 按小头像、普通头像顺序回退。
- `minimap_asset_path(terrain_definition_id)` 从小地图 manifest 返回遮罩路径；未知地图返回空字符串。加载器拒绝重复地图 ID、不存在资源及不在小地图目录中的路径。

通用战斗表现接口：

- `projectile_visual(projectile_key)` 返回公共弹体、拖尾和运动表现资源，例如 `shell.small`、`shell.medium`、`shell.large`、`torpedo.surface`、`torpedo.submerged`、`aircraft.bomb`。
- `weapon_visual(character_id, weapon_key)` 返回角色武器到公共表现的映射，例如主炮使用哪个炮弹档位、哪个炮口 profile、哪个命中 profile。
- `vfx_playback_profile(profile_key)` 返回 VFX 播放参数，例如 `duration`、`fps`、`loop`、`anchor`、`z_layer`、`rotation_mode`、`scale`、`follow_owner`、`blend_mode`。
- `combat_vfx_asset_path(semantic)` 从公共战斗 VFX manifest 返回语义资源路径，例如 `impact.water.large`；表现代码不得手拼公共水柱文件名。
- `environment_asset_path(semantic)` 从地形、岸基设施和局部环境三个 manifest 返回资源路径。浅水、航道、`visual_regions` 岸线叠层、设施状态和岛岸命中表现均通过该接口查询，不按文件名拼接；纯视觉多边形只能引用 manifest 语义，不能携带碰撞或通行规则。

环境 manifest：

```text
assets/environment/terrain/terrain_asset_manifest.json
assets/environment/facilities/facility_asset_manifest.json
assets/environment/weather/zones/environment_zone_asset_manifest.json
```
- 角色目录中的专属 VFX role 可以覆盖公共 profile 的贴图或颜色，但仍需要声明其公共语义，例如 `bismarck.heavy_muzzle -> muzzle_flash.large`。

炮弹曳尾接口：

- `projectile_visual` 返回口径档位、弹体、曳尾和颜色等表现参数；字段形状及校验只见 `docs/25_presentation_data_schema.md`。
- `weapon_visual` 将角色武器或武器组映射到公共投射物和 VFX Profile；缺少角色覆盖时必须使用明确公共回退。
- 口径档位、倍率、宽度、持续时间、颜色和残影的当前精确值只由 `data/visuals/` 拥有，接口文档不复制。
- 表现节点只消费已经成立的战斗事件和固定落点，不在资产查询层重新计算射击、命中或散布。

表现配置入口：

- `data/visuals/projectile_visuals.json`
- `data/visuals/weapon_visuals.json`
- `data/visuals/vfx_playback_profiles.json`

绑定点标准语义：

- 炮口使用 `muzzle_01`、`muzzle_02`、`muzzle_group`。
- 鱼雷口使用 `torpedo_port_01`、`torpedo_port_02`；旧配置中的单点 `torpedo_port` 读取时应能映射为 `torpedo_port_01`。
- 舰尾/侧投反潜投放点使用 `asw_launch_01`、`asw_launch_02`；不得复用主炮 `muzzle_*` 作为深水炸弹来源。
- 航迹使用 `wake_origin`。
- 航母旧 `aircraft_launch_01`、`aircraft_launch_02`、`aircraft_recovery` 保留兼容，新航空链从 Application 发布的角色位置生成，不依赖这些挂点或角色专属飞机。`unit_center` 表示无局部挂点的单位中心回退，不改变规则原点。
- 侦查、技能和扫描使用 `scan_origin`、`skill_origin`。
- 舰装挂点使用 `rig_mount`。
- processed 绑定点配置可在根级 `heading_offsets_degrees` 中按完整资产文件名记录角度；字段形状、范围与加载拒绝规则只见 `docs/25_presentation_data_schema.md`。`ShipUnitView` 对舰装绘制与该资产绑定点使用同一偏移，避免图像转正后炮口或特效挂点留在旧角度。

UI 接口：

- `ui_asset_path(asset_key, scale)` 返回 UI 资源路径。
- `asset_key` 支持原始名称，例如 `ui_icon_torpedo`。
- `asset_key` 也支持语义名称，例如 `ui.icon.torpedo`、`ui.marker.target`、`ui.panel.minimap_open_sea`。
- `scale` 可用 `processed`、`1x`、`2x`、`4x`。

## 约束

- 新程序代码应优先使用 `AssetCatalog`，不要直接写死角色或 UI 的完整 PNG 路径。
- 固定路径仅按本节上方登记的例外保留；新增资产消费者遵循语义查询。
- 美术后处理工具继续负责产出 `anim_config`、`vfx_config`、`meta_bind_points` 和 UI manifest。
- 若资源缺失或 JSON 无法解析，`AssetCatalog.load_all()` 会记录错误，启动时通过 `DataRegistry` 报告。

## 菜单封面接口（B 方案）

菜单通过 `DataRegistry.assets.menu_covers()` 和 `menu_cover(id)` 查询 `assets/ui/processed/menu/cover_manifest.json`。加载器检查唯一 ID、正式 menu 资源路径和文件存在性；表现层不拼接角色封面物理路径。七张场景插画位于 `assets/ui/processed/menu/covers/`，与角色战斗透明立绘分别管理。共享可缩放面板和按钮由 `scripts/presentation/ui_theme.gd` 绘制；头像、图标、血条继续通过现有语义接口查询。

航空持续消费者从可见投影携带的具体武器/机型解析公共 `visual.projectile.aircraft.*`，在视图绑定时缓存映射。投放实体 `projectile.air_torpedo` 交公共鱼雷查询，不从角色目录拼接。程序绘制的阴影、敌我形状标记、缺图箭头和符号LOD不新增角色包必需项。
