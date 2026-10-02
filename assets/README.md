# 美术资产目录入口

统一目录、命名、路径格式和兼容例外以 [资产接口规范](../docs/45_art_asset_interface_design.md#统一物理路径规范) 为准；这里不维护第二份规则表。

- [角色生产与验收](../docs/46_character_art_asset_pipeline.md)：源母版、processed、配置及角色 QA。
- [场景生产与验收](../docs/47_scene_art_asset_pipeline.md)：海面、天气、陆地、设施与环境 QA。
- [UI 包说明](ui/README.md)：UI 目录和重建命令。
- [当前实现位置](../docs/34_implementation_map.md)与[项目状态](../docs/00_project_status.md)：工具入口和完成度。

运行时通过 `DataRegistry.assets` 查询资源。`environment/` 与 `environments/ocean/` 均是正式目录；UI 和公共 VFX 的 `qa/` 含运行时 manifest，不可整目录清理。

## 音效制作素材

[已采用音效源包](audio/sfx/source/selected_20261001_v1/README.md)与[52音效规范](../docs/52_sound_effect_design_and_production.md)：按分类/ID保留采用版及生成源，尚不是运行时播放资源。


音效运行时已接入 `audio/sfx/runtime/`，由 `data/audio/sfx_manifest.json` 查询；离线重建用 `python3 tools/sfx/build_runtime.py`。当前60项采用、9项循环派生，源包不变。技术/设备验证与人工剩余项见项目状态和音效工单。

## 音乐制作素材

[音乐源资产目录](audio/music/README.md)统一保存五首标题、四首战斗与胜负结算共十一首已采用源版、离线索引和制作证据。源包由 `.gdignore` 隔离；历史候选与试听页留在 `reports/audio/`，评审归档见 [音乐评审记录](../tools/music/reviews/README.md)。五首标题音乐运行时位于 `audio/music/runtime/`，由 `data/audio/music_manifest.json` 查询；另六首仅源版采用、未接入。重建与设备/人工验收限制见音乐目录及项目状态。
