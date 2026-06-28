# 场景战斗地形美术资产与程序工具需求

日期：2026-06-27
主题：软地形、近岸水域、岛岸阻挡与岸基设施支持
状态：已实施（港湾入口为首张运行验证地图）

完成证据：正式数据与 manifest 已加载；`tools/terrain/validate_terrain_definition.py`、`validate_scene_combat_pipeline.py`、核心测试和场景测试通过；人工总览位于 `assets/environment/qa/scene_combat_contact_sheet.png`。

2026-06-28 最终审计：

- 十类岛屿均有按形状审核的浅水/礁滩/航道方案；每个硬岛体另有不参与规则的泥沙、碎浪、湿岩窄边缘。
- 三份 manifest 共登记 84 个正式资源，并校验尺寸、透明通道、`lowercase_snake_case`、语义唯一性和 2x UI 导出。
- 局部飑线的两张 512 x 512 正式透明纹理由风暴暗云、斜向雨线和雨点涟漪三张 1024 x 1024 AI 母版合成；manifest 保存母版来源和合成方式，可追溯且可确定性重建。
- Godot 制作插件通过 10 项加载检查和无损 JSON 往返；依赖循环或非法几何会在写正式数据前失败，事务式流水线不会发布非法出生点。
- 地形生产门禁与 9 个负例通过；核心规则 1327 项、场景表现 116 项、第二期配置 285 项通过。
- 五个关卡各批量模拟 6 局，港湾入口 6/6 正常结束；1920 x 1080、3840 x 2160、海雾、飑线和 F9 全知调试图已人工检查。

本工单承接 `docs/17_play_design.md` 与 `docs/35_scene_combat_domain_design.md`，只记录当前设计落地所需的美术资产和制作/调试工具。

状态标记：

- [x] 已有内容。
- [ ] 尚未完成。

---

## 要做

### 1. 复用现有资产与工具

- [x] 复用 `assets/environment/land/` 中十类岛屿与陆地母版。
- [x] 复用 `land_harbor_mouth.png` 作为首张近岸验证地图基础。
- [x] 复用 `assets/environment/weather/` 中现有云影、雨线、风暴、闪电和白沫母版。
- [x] 复用 `assets/vfx/combat/` 中现有炮弹、鱼雷、航空和普通命中资产。
- [x] 复用 `tools/art_pipeline/process_land_art.py` 生成陆地候选边缘。
- [x] 复用现有无画面测试、场景测试、批量模拟、小地图和调试绘制入口。

现有 `land_collision_manifest.json` 只是候选边缘。正式使用前必须人工区分硬陆地、浅水、视线阻挡、航道和纯视觉白沫。

### 2. 命名与目录

新增文件统一使用 `lowercase_snake_case`，并采用以下语义前缀：

```text
terrain_       水域、浅滩、航道和地形叠层
land_          岛屿、岸线和陆地母版
environment_   局部天气与软地形
facility_      岸基设施和状态覆盖
ui_marker_     战术标记和小地图图标
vfx_           一次性环境与命中表现
```

公共 VFX 延续现有 `_01` 变体编号；只有存在同语义多变体时才增加 `_02`。

推荐目录：

```text
assets/environment/terrain/
assets/environment/facilities/
assets/environment/weather/zones/
assets/ui/processed/battle/terrain/
assets/ui/export/2x/
assets/vfx/combat/environment/
assets/environment/qa/
tools/terrain/
addons/terrain_authoring/
```

### 3. 近岸与地形美术资产

- [x] 制作港湾入口的运行时清理版本：`assets/environment/land/land_harbor_mouth_runtime.png`。
- [x] 制作浅水填充：`terrain_shallow_water_fill_tile.png`。
- [x] 制作深浅水过渡遮罩：`terrain_shallow_water_edge_mask.png`。
- [x] 制作暗礁/沙洲叠层：`terrain_reef_sandbar_overlay.png`。
- [x] 制作航道叠层：`terrain_navigation_channel_overlay.png`。
- [x] 制作岛岸湿岩、泥沙和碎浪等通用命中底层元素。
- [x] 为浅水、航道、礁滩、触岸和无路径状态制作战术图标。

### 4. 软地形美术资产

- [x] 制作局部海雾主体、边缘和细节遮罩。
- [x] 制作局部飑线主体和边缘遮罩，并复用现有雨线与风暴母版。
- [x] 制作高海况白沫/强浪遮罩和背风水域遮罩。
- [x] 制作可定向拉伸的月光水域与主动照明遮罩。
- [x] 制作不会与鱼雷航迹混淆的强流纹理元素。
- [x] 制作海雾、飑线、高海况、背风水域、月光、海流和潮汐图标。
- [x] 制作软地形边界和移动趋势的通用图标；区域轮廓优先由程序绘制。

建议语义文件名：

```text
environment_sea_fog_mask.png
environment_sea_fog_edge_mask.png
environment_rain_squall_mask.png
environment_rain_squall_edge_mask.png
environment_high_sea_foam_mask.png
environment_lee_water_mask.png
environment_moonlit_lane_mask.png
environment_active_illumination_mask.png
environment_strong_current_streak_tile.png
```

### 5. 岸基设施美术资产

为以下设施制作正俯视基础图和确有结构差异的摧毁变体：

- [x] 海岸观察站：`facility_coastal_observation_post_*`。
- [x] 岸防炮：`facility_coastal_battery_*`。
- [x] 前沿补给点：`facility_forward_supply_point_*`。
- [x] 近岸机场：`facility_coastal_airfield_*`。
- [x] 雷达站：`facility_radar_station_*`。
- [x] 通信站：`facility_communication_station_*`。
- [x] 水雷控制站：`facility_mine_control_station_*`。
- [x] 港口维修泊位：`facility_repair_berth_*`。

同时需要：

- [x] 通用激活、压制、离线、通信中断、跑道压制和整备覆盖层。
- [x] 各设施的小地图与战术标记。
- [x] 激活、夺取、压制、恢复、摧毁、服务中断和服务完成图标。
- [x] 机场侦察、战斗机巡逻和空袭任务图标。
- [x] 已发现雷区、未知危险、停用雷区和安全航道图标。
- [x] 水雷触发与扫除表现。
- [x] 设施依赖链样式；连接线优先由程序绘制。

设施基础图不烘焙阵营颜色。阵营和运行状态由程序染色、公共覆盖层和 UI 标记表达。

### 6. 岛岸阻挡反馈资产

- [x] 炮弹撞击岛岸的小、中、大三档表现：`vfx_environment_shell_terrain_impact_*_01.png`。
- [x] 鱼雷撞岸失效表现：`vfx_environment_torpedo_terrain_impact_01.png`。
- [x] 舰船触岸提示：`ui_marker_terrain_collision.png`。
- [x] 炮弹路径被地形阻挡提示：`ui_marker_shell_path_blocked.png`。
- [x] 移动目标非法或无路径提示：`ui_marker_navigation_blocked.png`。

### 7. 地形制作工具

- [x] 建立 `addons/terrain_authoring/`，可编辑硬陆地、视线阻挡、浅水、航道、设施挂点和纯视觉区域。
- [x] 支持多边形顶点编辑、自相交检查、绕序检查和地图越界提示。
- [x] 实现 `tools/terrain/bake_terrain_definition.py`，把资产变换和语义多边形烘焙为运行时世界坐标。
- [x] 实现 `tools/terrain/validate_terrain_definition.py`，校验几何、引用、出生点、设施挂点和可达性。
- [x] 实现 `tools/terrain/render_terrain_qa.py`，输出语义总览、安全边界和查询命中点。
- [x] 实现 `terrain_debug_overlay.gd`，显示 Domain 实际硬边界、法线、空间索引和命中点。

### 8. 导航与阻挡测试工具

- [x] 实现 `tools/terrain/bake_navigation_graph.py`，生成玩家和 AI 共用导航数据。
- [x] 提供起点、终点、碰撞半径和通行标签的路线查询可视化。
- [x] 提供舰船、鱼雷、炮弹和光学视线四类线段/扫掠查询测试器。
- [x] 显示首次命中地形 ID、命中点、法线和路径比例。
- [x] 将地形纯规则、高速鱼雷防穿透、贴岸命中优先级和无地形回归接入现有测试框架。

### 9. 软地形制作工具

- [x] 在地形编辑器中支持海雾、飑线、高海况、背风水域、月光水域、强流和潮汐区域。
- [x] 支持区域形状、方向、漂移路径、阶段和公开趋势。
- [x] 实现固定 Tick 环境时间线预览与固定种子重放。
- [x] 实现 `TerrainContext` 检查器，显示水深、海流、海况、光学、航空和设施影响来源。
- [x] 支持检查重叠区域的效果顺序，避免重复应用。

### 10. 岸基设施制作工具

- [x] 支持设施位置、朝向、目标形状、交互水域和承载岸线编辑。
- [x] 校验岸炮不会被自身地形完全封死。
- [x] 校验补给点和维修泊位存在合法水上接近路线。
- [x] 提供设施依赖图编辑与循环依赖检查。
- [x] 提供设施状态调试面板，显示所有权、交互、压制、冷却、服务和依赖状态。
- [x] 支持固定雷区、安全航道、控制站引用和阵营可见信息编辑。

### 11. 生产与 QA 工具

- [x] 实现 `tools/terrain/build_minimap_masks.py`，从同一地图真源生成小地图语义遮罩。
- [x] 实现 `tools/terrain/build_scene_combat_contact_sheet.py`，生成地图、设施链、环境时间线和路径 QA 总览。
- [x] 批量检查不同碰撞半径和吃水单位到关键区域的可达性。
- [x] 批量检查岸炮视线和炮弹路径，禁止穿岛。
- [x] 批量验证固定种子下环境、设施和路线事件一致性。
- [x] 检查未引用资产，防止源图、候选边缘、QA 图和编辑器缓存进入导出包。

### 12. 配置与 manifest

- [x] `data/terrain/terrain_definitions.json`
- [x] `data/terrain/navigation_definitions.json`
- [x] `data/environments/environment_zone_definitions.json`
- [x] `data/facilities/facility_definitions.json`
- [x] `data/facilities/support_mission_definitions.json`
- [x] `data/facilities/minefield_definitions.json`
- [x] `assets/environment/terrain/terrain_asset_manifest.json`
- [x] `assets/environment/facilities/facility_asset_manifest.json`
- [x] `assets/environment/weather/zones/environment_zone_asset_manifest.json`

配置使用稳定英文 ID。资产 manifest 只保存资源语义、路径、尺寸和非运行时制作来源，不保存伤害、侦查、通行或设施战斗规则。

### 13. 验收

- [x] 地形、浅水、航道和设施在战场与小地图中语义一致。
- [x] 软地形边界可读，但不与武器范围、鱼雷航迹或危险预警混淆。
- [x] 岛岸命中与普通落水、舰体命中反馈清楚区分。
- [x] 新地图可完成“摆放母版 -> 标注语义 -> 烘焙 -> 校验 -> QA -> 运行”，无需手改运行时坐标。
- [x] Domain 地形、导航、小地图和 QA 使用同一份审核几何真源。
- [x] 玩家路线、AI 路线、炮弹路径、鱼雷扫掠和视线查询均可复现。
- [x] 工具能阻止非法多边形、出生点落陆、设施不可达、岸炮自遮挡和设施依赖循环进入运行时。
- [x] 所有工具具有确定性输出和非零失败码。

---

## 不要做

- 不重新制作角色立绘、头像、舰装或角色动画。
- 不重新制作已有公共炮弹、鱼雷、航空和普通命中资产。
- 不迁移现有 `assets/environment/land/` 和 `assets/environment/weather/` 资源。
- 不为每张地图制作一张不可复用的全尺寸背景图。
- 不从运行时 PNG alpha 自动推断碰撞、视线、浅水或通行规则。
- 不把浅水光晕、白沫、阴影和小装饰礁石全部当成硬碰撞。
- 不在设施基础图中烘焙阵营颜色。
- 不为每个设施重复制作能够由公共覆盖层表达的状态整图。
- 不用 `final`、`new`、`copy`、中文、空格或版本号命名正式资产。
- 不在工具脚本中重新实现伤害、命中、侦查或设施战斗规则。
- 不让编辑器碰撞体、导航节点或表现遮罩成为 Domain 真相。
- 不维护地形、导航、小地图和 QA 四套独立几何数据。
- 不让 AI 使用不同于玩家的地形、导航、视线或隐藏设施信息。
- 不把环境 Shader 参数当成软地形规则来源。
- 不让 QA 图、源图、候选边缘或编辑器缓存进入运行时引用。
- 不在设施、天气和水雷规则尚未完成时用临时特判绕过 `docs/35_scene_combat_domain_design.md`。
