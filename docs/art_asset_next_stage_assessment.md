# 下一阶段美术资产评估

评估范围：动画状态机、VFX 绑定、炮弹/鱼雷/舰载机攻击表现。
评估前提：不考虑展示页；QA 资产不进入运行画面；当前战斗规则、操作闭环和 HUD 已具备继续接入表现层的条件。

## 总体结论

现有角色资产足够启动下一阶段，但不足以完整完成“炮弹、鱼雷、舰载机”全套攻击表现。

可以立即开始：

- 角色动画状态机。
- 角色基础战斗图层拆分。
- 角色绑定点读取与炮口/鱼雷口/航迹位置绑定。
- 基础开火、命中、水花、航迹、技能范围 VFX 播放。
- 现有火炮与鱼雷表现的第一版接入。

暂时不完整，需要新增或补充契约后再做：

- 通用炮弹/鱼雷实体贴图。
- 舰载机实体与编队表现。
- 弹体生命周期各阶段的统一表现规范。
- VFX 播放参数，例如持续时间、锚点、旋转规则、缩放规则、层级、是否跟随单位。
- 不同武器类型到 VFX role 的稳定映射。

## 当前资产已经具备的能力

### 角色动画

已配置角色均有以下动画状态：

- `idle`
- `move`
- `attack`
- `hit`
- `firepower`

每个状态已有帧列表、FPS 和是否循环信息。
结论：可以开始做轻量动画状态机，不需要等新美术。

建议第一版状态机：

- 默认 `idle`
- 有速度时 `move`
- 收到开火事件时短暂播放 `attack` 或 `firepower`
- 收到受击事件时短暂播放 `hit`
- 非循环动画结束后回到 `move` 或 `idle`

### 角色绑定点

已配置角色均有 `meta_bind_points`，覆盖了常见位置：

- `origin`
- `rig_mount`
- `muzzle_*`
- `turret_mount_*`
- `torpedo_port*`
- `wake_origin`
- `scan_origin`
- `sonar_origin`
- `aircraft_launch_*`

结论：可以开始把炮口、鱼雷口、航迹、扫描线、舰载机起飞点与角色资产绑定。

注意：不同角色命名不完全统一，例如 `torpedo_port`、`torpedo_port_01`、`torpedo_port_02` 并存。程序侧需要做 role 归一，或要求美术侧补统一命名规则。

### 角色 VFX

已配置角色均有 `vfx_config`，并提供语义 role，例如：

- 火炮：`muzzle_flash`、`heavy_muzzle`、`shell_trail`、`splash`、`water_impact`
- 鱼雷：`torpedo_trail`、`torpedo_warning`
- 航迹：`wake`、`wake_fast`、`wake_surge`
- 技能/范围：`reticle`、`range_arc`、`support_area`、`airstrike_area`
- 潜艇：`bubble_trail`、`sonar_pulse`、`underwater_shadow`
- 舰载机：`aircraft_path`、`deck_lane`

结论：可以开始接角色专属 VFX，但需要补充统一播放契约。

## 当前缺口

### 1. 缺少通用弹体资产

当前 `data/projectiles/projectiles.json` 只有逻辑定义：

- `projectile.shell`
- `projectile.surface_torpedo`
- `projectile.submarine_torpedo`

但没有稳定的弹体美术字段，也没有通用弹体贴图目录。

现状可临时用程序绘制线条/小图标，但若要完整表现，需要美术方提供：

- 炮弹飞行点/拖尾贴图，至少区分小口径、中口径、大口径。
- 鱼雷实体贴图，至少区分水面鱼雷、潜射鱼雷。
- 鱼雷尾迹贴图或可平铺拖尾。
- 命中水花、装甲命中、未命中落水等通用效果。

### 2. 舰载机表现还不能完整接入

`enterprise_cv6` 已有舰载机和航母 VFX，但它没有进入舰船数据和关卡，当前武器表也没有航空武器。

如要做舰载机攻击效果，需要新增：

- 航母舰船定义。
- 航空武器定义。
- 舰载机 projectile/actor 定义。
- 舰载机实体贴图与编队规则。
- 起飞、飞行、攻击、返航、被防空拦截的表现契约。

### 3. VFX 配置缺少播放参数

当前 `vfx_config` 能告诉程序“有什么资源”，但不足以稳定播放。建议补充：

- `duration`
- `fps` 或 `frame_count`
- `loop`
- `anchor`
- `z_layer`
- `blend_mode`
- `rotation_mode`
- `scale`
- `follow_owner`
- `screen_shake`
- `color_modulate`

没有这些字段时，程序只能硬编码播放行为，后续维护会变脆。

### 4. 绑定点语义需要统一

建议美术侧统一以下语义：

- 炮口：`muzzle_01`、`muzzle_02`、`muzzle_group`
- 鱼雷口：`torpedo_port_01`、`torpedo_port_02`
- 航迹：`wake_origin`
- 舰载机起飞：`aircraft_launch_01`、`aircraft_launch_02`
- 舰载机回收：`aircraft_recovery`
- 技能/扫描：`scan_origin`、`skill_origin`
- 舰装挂点：`rig_mount`

程序可以兼容旧命名，但新资产最好按统一语义输出。

### 5. 武器到表现资源缺少数据映射

当前武器只描述规则，不描述表现。建议在武器或 projectile 中增加表现字段，例如：

```json
{
  "projectile_visual_id": "visual.shell.large",
  "muzzle_vfx_role": "heavy_muzzle",
  "trail_vfx_role": "shell_trail",
  "impact_vfx_role": "splash",
  "fire_animation_state": "firepower"
}
```

这样程序不需要根据 `mount_type` 和角色名猜资源。

## 是否需要调整美术资产接口契约

需要，但不建议推翻现有接口。建议在现有 `AssetCatalog` 上增量扩展。

### 建议新增接口

- `animation_states(character_id)`：列出角色所有动画状态。
- `vfx_roles(character_id)`：列出角色所有 VFX role。
- `battle_asset_paths(character_id)`：列出角色战斗部件。
- `bind_point(character_id, asset_name, point_name)`：读取单个绑定点。
- `projectile_visual(projectile_visual_id)`：读取通用弹体表现。
- `weapon_visual(weapon_id, character_id)`：读取武器表现映射。

### 建议新增配置

新增通用表现配置目录：

- `data/visuals/projectile_visuals.json`
- `data/visuals/weapon_visuals.json`
- `data/visuals/vfx_playback_profiles.json`

或者在现有 `data/projectiles`、`data/weapons` 中直接增加表现字段。
如果希望规则与表现解耦，推荐单独建 `data/visuals/`。

## 是否需要美术方提供其他支持

需要，主要是规格支持，不只是继续出图。

### 美术方需要补充的资源

优先级高：

- 通用炮弹飞行贴图，小/中/大至少三档。
- 通用炮弹拖尾或 shell trail 规范。
- 通用鱼雷实体贴图。
- 通用鱼雷尾迹贴图。
- 通用命中水花、落水水花、装甲火花。
- 各角色缺失或命名不统一的炮口/鱼雷口绑定点。

优先级中：

- 通用防空弹幕、航空炸弹/鱼雷、舰载机受击/坠落效果。
- 舰载机单位贴图和编队标识。
- 技能释放短时 cut-in 或角色局部演出规则。

优先级低：

- 复杂多帧爆炸序列。
- 多天气专属 VFX。
- 高级沉没动画。

### 美术方需要补充的文档/数据

- 每个 VFX 的推荐播放时长。
- 每个 VFX 是否循环。
- 每个 VFX 的锚点和朝向规则。
- 每个 VFX 的推荐渲染层级。
- 每个战斗部件的语义说明。
- 弹体和 VFX 的推荐缩放基准。

## 建议实施顺序

1. 做动画状态机，只接 `idle/move/attack/hit/firepower`。
2. 扩展 `AssetCatalog`，暴露动画、VFX、绑定点列表和单点查询。
3. 接入战斗部件绑定点，让炮口/鱼雷口/航迹位置可视化。
4. 接入火炮表现：炮口火光、shell trail、落水/命中水花。
5. 接入鱼雷表现：鱼雷实体、尾迹、预警线、命中水花。
6. 补 `data/visuals/`，把武器到表现资源的映射数据化。
7. 再接舰载机表现和航母数据。

## 最终判断

- 角色动画：现有资产足够，可以开始。
- 角色 VFX：现有资产基本足够，可以开始第一版，但需要补播放参数契约。
- 火炮表现：角色 VFX 可支撑第一版，但缺通用弹体/命中表现契约。
- 鱼雷表现：已有角色鱼雷 VFX，但缺通用鱼雷实体与统一 projectile visual。
- 舰载机表现：当前不够，需要角色入表、航空武器、舰载机实体、编队和防空交互表现。
- 接口契约：需要增量扩展，不需要重做。
- 美术支持：需要提供通用弹体/VFX 规格、播放参数、绑定点命名规范和缺失资源清单。
