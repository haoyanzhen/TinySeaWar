# TinySeaWar Terrain Authoring

该目录是 TinySeaWar 的 Godot 编辑器插件边界，只承载地形作者工具的编辑器适配，不属于战斗运行时。

## 职责

- 在 Godot 编辑器中注册 `TerrainAuthoringRoot` 和“地形制作”Dock。
- 将正式作者数据加载为可编辑的 `Node2D`、多边形、设施挂点和岛屿实例。
- 把编辑结果写入作者快照，并调用 `tools/terrain/` 下的确定性回写、烘焙、校验、导航、小地图和 QA 流水线。

正式数据真源位于 `data/terrain/`、`data/environments/` 和 `data/facilities/`。插件场景与作者快照都不能替代正式 JSON 数据。

## 使用顺序

1. 在 Godot 中打开 `terrain_authoring_workspace.tscn`。
2. 在 `TerrainAuthoringRoot` Inspector 中选择 `Template` 或 `Map` 及稳定 ID。
3. 点击“从正式数据加载”，在 2D 视图中编辑顶点、实例和挂点。
4. 处理全部配置警告后点击“保存并回写正式数据”。
5. 运行完整流水线并检查校验输出和 QA 总览。

插件依赖项目根目录可用的 `python3` 与 `tools/terrain/` 脚本。当前开发平台为 macOS，命令通过 `/bin/zsh` 执行。

## 运行时与发布边界

- `scripts/`、场景和运行时数据不得依赖本目录中的脚本或工作场景。
- 运行时使用烘焙后的正式数据与资产，不加载 `EditorPlugin`。
- 建立正式 `export_presets.cfg` 时，应排除 `addons/terrain_authoring/**`、作者工作场景、`scripts/tests/**` 和 QA 中间产物，或使用仅导出运行时依赖资源的策略。
- 每次发布前应检查导出包，确认不存在本插件、作者快照和测试入口。

当前仓库尚未建立正式导出预设，因此发布排除规则仍需在创建目标平台预设时落地。
