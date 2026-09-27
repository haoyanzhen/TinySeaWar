# 美术资产目录入口

统一目录、命名、路径格式和兼容例外以 [资产接口规范](../docs/45_art_asset_interface_design.md#统一物理路径规范) 为准；这里不维护第二份规则表。

- [角色生产与验收](../docs/46_character_art_asset_pipeline.md)：源母版、processed、配置及角色 QA。
- [场景生产与验收](../docs/47_scene_art_asset_pipeline.md)：海面、天气、陆地、设施与环境 QA。
- [UI 包说明](ui/README.md)：UI 目录和重建命令。
- [当前实现位置](../docs/34_implementation_map.md)与[项目状态](../docs/00_project_status.md)：工具入口和完成度。

运行时通过 `DataRegistry.assets` 查询资源。`environment/` 与 `environments/ocean/` 均是正式目录；UI 和公共 VFX 的 `qa/` 含运行时 manifest，不可整目录清理。
