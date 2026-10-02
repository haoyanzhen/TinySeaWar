# Windows 10 x64 发布

使用当前工作区（包含未提交修改）构建。需要 Godot 4.6.3 stable、匹配的官方 Windows x64 Release 导出模板，以及仓库 uv 环境。模板放在 Godot 用户 export_templates/4.6.3.stable 下，不进入项目或交付包。

```sh
uv sync --locked
uv run --locked python tools/release/build_windows.py
mkdir -p build/windows-20261002/TinySeaWar-Windows10-x64
godot --headless --path . --export-release "Windows 10 x64"
uv run --locked python tools/release/inspect_windows_pack.py
```

生成器明确收集场景/运行脚本、动态数据、角色processed、UI/地图/公共VFX、音频runtime与正式manifest；保留两个qa目录中的运行清单。`.json`和`.tscf`以精确路径显式加入，资源交给Godot导入/重映射。生产源、source_alpha、提示词、测试、编辑器插件、模拟实验不在白名单内。构建目录由.gitignore和.gdignore隔离。

`runtime_asset_inventory.json`记录输入路径/大小/SHA256；`pck_inventory.json`记录实际交付文件、大小及验证后的MD5。检查器支持当前Godot PCK v3，验证包内全部文件摘要、原始数据存在、发布排除和Windows PE AMD64。

交付时将TinySeaWar.exe与TinySeaWar.pck放同一目录，附Godot LICENSE/COPYRIGHT、启动说明与校验值，再压缩整个目录。当前交付ZIP与证据见docs/00_project_status.md。此处检查不等于Windows实际运行通过；本次用户明确交人工测试。
